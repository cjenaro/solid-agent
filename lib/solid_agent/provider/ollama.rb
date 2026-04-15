require 'json'

module SolidAgent
  module Provider
    class Ollama
      include Base

      DEFAULT_BASE_URL = 'http://localhost:11434'

      def initialize(base_url: DEFAULT_BASE_URL)
        @base_url = base_url.chomp('/')
      end

      def build_request(messages:, tools:, stream:, model:, max_tokens: nil, options: {})
        body = {
          model: model.to_s,
          messages: messages.map { |m| serialize_message(m) },
          stream: stream
        }
        body[:tools] = tools.map { |t| translate_tool(t) } unless tools.empty?
        body.merge!(options)

        HTTP::Request.new(
          method: :post,
          url: "#{@base_url}/api/chat",
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate(body),
          stream: stream
        )
      end

      def parse_response(raw_response)
        raise_error(raw_response) unless raw_response.success?

        data = raw_response.json
        msg = data['message'] || {}

        message = Types::Message.new(
          role: msg['role'] || 'assistant',
          content: msg['content']
        )

        Types::Response.new(
          messages: [message],
          tool_calls: [],
          usage: Types::Usage.new(input_tokens: 0, output_tokens: 0),
          finish_reason: data['done'] ? 'stop' : nil
        )
      end

      def parse_stream_chunk(raw_chunk)
        line = raw_chunk.to_s.strip
        return Types::StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil, done: false) if line.empty?

        data = begin
          JSON.parse(line)
        rescue StandardError
          {}
        end
        done = data['done'] == true

        Types::StreamChunk.new(
          delta_content: data.dig('message', 'content'),
          delta_tool_calls: [],
          usage: nil,
          done: done
        )
      end

      def parse_tool_call(raw_tool_call)
        Types::ToolCall.new(
          id: raw_tool_call['id'] || 'tc_0',
          name: raw_tool_call['name'],
          arguments: raw_tool_call['arguments'] || raw_tool_call['input'] || {},
          call_index: 0
        )
      end

      def tool_schema_format
        :openai
      end

      private

      def serialize_message(message)
        { role: message.role, content: message.content || '' }
      end

      def translate_tool(tool)
        {
          type: 'function',
          function: {
            name: tool[:name],
            description: tool[:description],
            parameters: tool[:inputSchema]
          }
        }
      end

      def raise_error(response)
        raise ProviderError, response.error || "Ollama error: HTTP #{response.status}"
      end
    end
  end
end
