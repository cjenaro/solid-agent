require 'solid_agent/tool/inline_tool'
require 'solid_agent/tool/registry'

module SolidAgent
  module Agent
    module DSL
      extend ActiveSupport::Concern

      class_methods do
        def provider(name)
          @agent_provider = name
        end

        def agent_provider
          @agent_provider || :openai
        end

        def model(model_const)
          @agent_model = model_const
        end

        def agent_model
          @agent_model || SolidAgent::Models::OpenAi::GPT_4O
        end

        def max_tokens(tokens)
          @agent_max_tokens = tokens
        end

        def agent_max_tokens
          @agent_max_tokens || 4096
        end

        def temperature(temp)
          @agent_temperature = temp
        end

        def agent_temperature
          @agent_temperature || 0.7
        end

        def instructions(text)
          @agent_instructions = text
        end

        def agent_instructions
          @agent_instructions || ''
        end

        def memory(strategy, **opts)
          @agent_memory_config = { strategy: strategy }.merge(opts)
        end

        def agent_memory_config
          @agent_memory_config || { strategy: :sliding_window, max_messages: 50 }
        end

        def tool(name_or_class, description: nil, parameters: nil, &block)
          if block
            agent_tool_registry.register(
              SolidAgent::Tool::InlineTool.new(
                name: name_or_class,
                description: description || name_or_class.to_s,
                parameters: parameters || extract_block_parameters(block),
                block: block
              )
            )
          else
            agent_tool_registry.register(name_or_class)
          end
        end

        def agent_tool_registry
          @agent_tool_registry ||= SolidAgent::Tool::Registry.new
        end

        def concurrency(max)
          @agent_concurrency = max
        end

        def agent_concurrency
          @agent_concurrency || 1
        end

        def max_iterations(count)
          @agent_max_iterations = count
        end

        def agent_max_iterations
          @agent_max_iterations || 25
        end

        def max_tokens_per_run(tokens)
          @agent_max_tokens_per_run = tokens
        end

        def agent_max_tokens_per_run
          @agent_max_tokens_per_run || 100_000
        end

        def timeout(duration)
          @agent_timeout = duration
        end

        def agent_timeout
          @agent_timeout || 300
        end

        def retry_on(error_class, attempts: 3)
          @agent_retry_config = { error: error_class, attempts: attempts }
        end

        def agent_retry_config
          @agent_retry_config
        end

        def require_approval(*tool_names)
          @agent_approval_required = tool_names.map(&:to_s)
        end

        def agent_approval_required
          @agent_approval_required || []
        end

        def before_invoke(method_name)
          @before_invoke_callbacks ||= []
          @before_invoke_callbacks << method_name
        end

        def after_invoke(method_name)
          @after_invoke_callbacks ||= []
          @after_invoke_callbacks << method_name
        end

        def on_context_overflow(method_name)
          @on_context_overflow = method_name
        end

        private

        def extract_block_parameters(block)
          return [] unless block.parameters.any?

          block.parameters.map do |kind, name|
            {
              name: name.to_s,
              type: :string,
              description: name.to_s.tr('_', ' ').capitalize,
              required: kind == :keyreq
            }
          end
        end
      end
    end
  end
end
