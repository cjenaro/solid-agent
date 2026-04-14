module SolidAgent
  module Types
    class Response
      attr_reader :messages, :tool_calls, :usage, :finish_reason

      def initialize(messages:, tool_calls:, usage:, finish_reason:)
        @messages = messages
        @tool_calls = tool_calls
        @usage = usage
        @finish_reason = finish_reason
      end

      def has_tool_calls?
        !tool_calls.nil? && !tool_calls.empty?
      end
    end
  end
end
