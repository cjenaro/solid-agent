module SolidAgent
  module Provider
    module Base
      def build_request(messages:, tools:, stream:, model:, max_tokens: nil, options: {})
        raise NotImplementedError, "#{self.class} must implement build_request"
      end

      def parse_response(raw_response)
        raise NotImplementedError, "#{self.class} must implement parse_response"
      end

      def parse_stream_chunk(chunk)
        raise NotImplementedError, "#{self.class} must implement parse_stream_chunk"
      end

      def parse_tool_call(raw_tool_call)
        raise NotImplementedError, "#{self.class} must implement parse_tool_call"
      end

      def tool_schema_format
        raise NotImplementedError, "#{self.class} must implement tool_schema_format"
      end
    end
  end
end
