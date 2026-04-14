module SolidAgent
  module Types
    class StreamChunk
      attr_reader :delta_content, :delta_tool_calls, :usage

      def initialize(delta_content:, delta_tool_calls:, usage:, done:)
        @delta_content = delta_content
        @delta_tool_calls = delta_tool_calls
        @usage = usage
        @done = done
      end

      def done?
        @done
      end
    end
  end
end
