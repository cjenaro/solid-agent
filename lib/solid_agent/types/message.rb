module SolidAgent
  module Types
    class Message
      attr_reader :role, :content, :tool_calls, :tool_call_id, :metadata

      def initialize(role:, content:, tool_calls: nil, tool_call_id: nil, metadata: {})
        @role = role
        @content = content
        @tool_calls = tool_calls
        @tool_call_id = tool_call_id
        @metadata = metadata
        freeze
      end

      def to_hash
        h = { role: role }
        h[:content] = content if content
        h[:tool_calls] = tool_calls.map(&:to_hash) if tool_calls && !tool_calls.empty?
        h[:tool_call_id] = tool_call_id if tool_call_id
        h[:metadata] = metadata if metadata && !metadata.empty?
        h
      end
    end
  end
end
