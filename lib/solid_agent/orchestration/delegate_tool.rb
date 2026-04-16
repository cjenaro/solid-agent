module SolidAgent
  module Orchestration
    class DelegateTool
      attr_reader :name, :agent_class, :description

      def initialize(name, agent_class, description:)
        @name = name.to_s
        @agent_class = agent_class
        @description = description
      end

      def delegate?
        true
      end

      def to_tool_schema
        {
          name: @name,
          description: @description,
          inputSchema: {
            type: 'object',
            properties: {
              input: {
                type: 'string',
                description: 'The task to delegate to the agent'
              }
            },
            required: ['input']
          }
        }
      end

      def execute(arguments, context: {})
        parent_trace = context[:trace]
        conversation = context[:conversation]
        input_text = arguments['input'] || arguments[:input]

        child_trace = nil

        begin
          child_trace = SolidAgent::Trace.create!(
            conversation: conversation,
            parent_trace: parent_trace,
            agent_class: @agent_class.name,
            trace_type: :delegate,
            input: input_text,
            otel_trace_id: parent_trace&.otel_trace_id
          )

          child_trace.start!
          result = @agent_class.perform_now(input_text, trace: child_trace, conversation: conversation)
          child_trace.update!(output: result.to_s)
          child_trace.complete!

          result.to_s
        rescue StandardError => e
          child_trace&.fail!(e.message) if child_trace&.status == 'running'
          raise
        end
      end
    end
  end
end
