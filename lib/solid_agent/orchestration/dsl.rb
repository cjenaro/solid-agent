require "active_support/concern"

module SolidAgent
  module Orchestration
    module DSL
      extend ActiveSupport::Concern

      class_methods do
        def delegates
          @delegates ||= {}
        end

        def agent_tools
          @agent_tools ||= {}
        end

        def delegate_error_strategies
          @delegate_error_strategies ||= {}
        end

        def delegate(name, to:, description:)
          tool = DelegateTool.new(name, to, description: description)
          delegates[name.to_s] = tool
        end

        def agent_tool(name, agent:, description:)
          tool = AgentTool.new(name, agent, description: description)
          agent_tools[name.to_s] = tool
        end

        def on_delegate_failure(name, strategy:, attempts: 1)
          delegate_error_strategies[name.to_s] = ErrorPropagation::Strategy.new(strategy, attempts: attempts)
        end

        def orchestration_tools
          delegates.values + agent_tools.values
        end

        def orchestration_tool_schemas
          orchestration_tools.map(&:to_tool_schema)
        end

        def find_orchestration_tool(tool_name)
          delegates[tool_name] || agent_tools[tool_name]
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@delegates, @delegates.dup) if @delegates
          subclass.instance_variable_set(:@agent_tools, @agent_tools.dup) if @agent_tools
          subclass.instance_variable_set(:@delegate_error_strategies, @delegate_error_strategies.dup) if @delegate_error_strategies
        end
      end
    end
  end
end
