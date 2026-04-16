require 'active_job'
require 'solid_agent/react/loop'
require 'solid_agent/agent/result'

module SolidAgent
  class ApplicationJob < ActiveJob::Base; end unless defined?(ApplicationJob)

  class RunJob < ApplicationJob
    queue_as :solid_agent

    def perform(trace_id:, agent_class_name:, input:, conversation_id:)
      trace = Trace.find(trace_id)
      trace.start!

      agent_class = agent_class_name.constantize

      provider = resolve_provider(agent_class)
      memory = resolve_memory(agent_class)
      execution_engine = resolve_execution_engine(agent_class)

      conversation = Conversation.find(conversation_id)
      conversation.messages.create!(role: 'user', content: input, trace: trace)

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
        provider_name: agent_class.agent_provider
      )

      messages = conversation.messages.where(trace: trace).order(:created_at).map do |m|
        Types::Message.new(role: m.role, content: m.content, tool_calls: nil, tool_call_id: m.tool_call_id)
      end

      react_loop.run(messages)
    rescue StandardError => e
      trace.fail!(e.message) if trace&.status == 'running'
      SolidAgent.configuration.telemetry_exporters.each do |exporter|
        exporter.export_trace(trace)
      end
      raise
    end

    private

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

    def resolve_execution_engine(agent_class)
      Tool::ExecutionEngine.new(
        registry: agent_class.agent_tool_registry,
        concurrency: agent_class.agent_concurrency,
        approval_required: agent_class.agent_approval_required
      )
    end
  end
end
