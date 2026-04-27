module SolidAgent
  module Orchestration
    class AgentTool
      attr_reader :name, :agent_class, :description

      def initialize(name, agent_class, description:)
        @name = name.to_s
        @agent_class = agent_class
        @description = description
      end

      def delegate?
        false
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
                description: 'The input for the agent'
              }
            },
            required: ['input']
          }
        }
      end

      def execute(arguments, context: {})
        trace = context[:trace]
        conversation = context[:conversation]
        input_text = arguments['input'] || arguments[:input]

        return run_without_span(input_text, conversation) unless trace

        span = nil

        begin
          tool_attrs = SolidAgent::Telemetry::Serializer.span_attributes(
            SolidAgent::Span.new(span_type: :tool_execution, name: @name),
            tool_name: @name,
            tool_type: 'agent'
          )

          span = SolidAgent::Span.create!(
            trace: trace,
            span_type: :tool_execution,
            name: @name,
            input: input_text,
            status: 'running',
            started_at: Time.current,
            metadata: {
              agent_class: @agent_class.name,
              tool_type: :agent_tool
            }.merge(tool_attrs)
          )

          result = @agent_class.perform_now(input_text, conversation: conversation)
          output_text = result.is_a?(SolidAgent::Agent::Result) ? result.output.to_s : result.to_s

          span.update!(
            output: output_text,
            status: 'completed',
            completed_at: Time.current
          )

          output_text
        rescue StandardError => e
          if span
            span.update!(
              output: e.message,
              status: 'error',
              completed_at: Time.current
            )
          end
          raise
        end
      end

      private

      def run_without_span(input_text, conversation)
        result = @agent_class.perform_now(input_text, conversation: conversation)
        result.is_a?(SolidAgent::Agent::Result) ? result.output.to_s : result.to_s
      end
    end
  end
end
