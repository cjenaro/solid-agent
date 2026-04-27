require 'active_job'
require 'solid_agent/react/loop'
require 'solid_agent/agent/result'

module SolidAgent
  class ApplicationJob < ActiveJob::Base; end unless defined?(ApplicationJob)

  class RunJob < ApplicationJob
    queue_as :solid_agent

    def perform(trace_id:, agent_class_name:, input:, conversation_id:)
      trace = SolidAgent::Trace.find(trace_id)
      trace.start!

      agent_class = agent_class_name.constantize

      # Before invoke callbacks
      agent_instance = agent_class.new
      agent_class.before_invoke_callbacks.each do |cb|
        agent_instance.send(cb, input)
      end

      retry_config = agent_class.agent_retry_config
      attempts = retry_config ? retry_config[:attempts] : 1
      retry_error_class = retry_config&.dig(:error)

      result = nil
      last_error = nil

      attempts.times do |attempt|
        begin
          result = execute_run(trace: trace, agent_class: agent_class, agent_instance: agent_instance,
                               input: input, conversation_id: conversation_id)
          last_error = nil
          break
        rescue => e
          last_error = e
          if retry_error_class && e.is_a?(retry_error_class) && attempt < attempts - 1
            Rails.logger.warn("[SolidAgent] Retry #{attempt + 1}/#{attempts} for #{agent_class_name}: #{e.message}")
            trace.update!(status: 'running') if trace.status == 'failed'
          else
            raise
          end
        end
      end

      # After invoke callbacks
      agent_class.after_invoke_callbacks.each do |cb|
        agent_instance.send(cb, result)
      end

      result
    rescue StandardError => e
      trace.fail!(e.message) if trace&.status == 'running'
      SolidAgent.configuration.telemetry_exporters.each do |exporter|
        exporter.export_trace(trace)
      end
      raise
    end

    private

    def execute_run(trace:, agent_class:, agent_instance:, input:, conversation_id:)
      provider = resolve_provider(agent_class)
      memory = resolve_memory(agent_class)
      execution_engine = resolve_execution_engine(agent_class, trace: trace, conversation_id: conversation_id)

      conversation = SolidAgent::Conversation.find(conversation_id)

      on_overflow = nil
      if agent_class.context_overflow_callback
        on_overflow = ->(messages) { agent_instance.send(agent_class.context_overflow_callback, messages) }
      end

      react_loop = React::Loop.new(
        trace: trace,
        provider: provider,
        memory: memory,
        execution_engine: execution_engine,
        model: agent_class.agent_model,
        system_prompt: agent_class.agent_instructions,
        max_iterations: agent_class.agent_max_iterations,
        max_tokens_per_run: agent_class.agent_max_tokens_per_run,
        timeout: agent_class.agent_timeout,
        provider_name: agent_class.agent_provider,
        temperature: agent_class.agent_temperature,
        tool_choice: agent_class.agent_tool_choice,
        on_context_overflow: on_overflow
      )

      conversation.messages.where(trace: trace).destroy_all if trace.messages.any?

      # Support string input or multimodal hash: { text:, image_url:, image_data: }
      msg_attrs = if input.is_a?(Hash)
                    { role: 'user', content: input[:text] || input['text'], trace: trace,
                      image_url: input[:image_url] || input['image_url'],
                      image_data: input[:image_data] || input['image_data'] }.compact
                  else
                    { role: 'user', content: input, trace: trace }
                  end
      conversation.messages.create!(msg_attrs)

      messages = conversation.messages.where(trace: trace).order(:created_at).map do |m|
        img_data = m.image_data
        img_data = img_data.transform_keys(&:to_sym) if img_data.is_a?(Hash)
        Types::Message.new(
          role: m.role,
          content: m.content,
          tool_calls: nil,
          tool_call_id: m.tool_call_id,
          image_url: m.image_url,
          image_data: img_data
        )
      end

      react_loop.run(messages)
    end

    def resolve_provider(agent_class)
      provider_name = agent_class.agent_provider
      config = SolidAgent.configuration.providers[provider_name] || {}
      provider_map = { openai: 'OpenAi', anthropic: 'Anthropic', google: 'Google', ollama: 'Ollama',
                       openai_compatible: 'OpenAiCompatible' }
      provider_class_name = provider_map[provider_name] || provider_name.to_s.camelize
      provider_class = "SolidAgent::Provider::#{provider_class_name}".constantize
      provider_class.new(**config.transform_keys(&:to_sym))
    end

    def resolve_memory(agent_class)
      config = agent_class.agent_memory_config
      memory_map = { sliding_window: 'SlidingWindow', full_history: 'FullHistory', compaction: 'Compaction' }
      memory_class_name = memory_map[config[:strategy]] || config[:strategy].to_s.camelize
      "SolidAgent::Memory::#{memory_class_name}".constantize.new(**config.except(:strategy).transform_keys(&:to_sym))
    end

    def resolve_execution_engine(agent_class, trace:, conversation_id:)
      registry = agent_class.agent_tool_registry

      # Register orchestration tools (delegates/agent_tools) in the same registry
      if agent_class.respond_to?(:orchestration_tools)
        agent_class.orchestration_tools.each do |_name, tool|
          registry.register(tool) unless registry.registered?(tool.name)
        end
      end

      context = {
        trace: trace,
        conversation: SolidAgent::Conversation.find(conversation_id)
      }

      Tool::ExecutionEngine.new(
        registry: registry,
        concurrency: agent_class.agent_concurrency,
        approval_required: agent_class.agent_approval_required,
        context: context
      )
    end
  end
end
