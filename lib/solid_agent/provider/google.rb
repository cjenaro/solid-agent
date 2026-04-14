require 'json'

module SolidAgent
  module Provider
    class Google
      include Base

      BASE_URL = 'https://generativelanguage.googleapis.com/v1beta/models'

      def initialize(api_key:, default_model: Models::Google::GEMINI_2_5_PRO)
        @api_key = api_key
        @default_model = default_model
      end

      def build_request(messages:, tools:, stream:, model:, options: {})
        system_msg, filtered = extract_system(messages)

        url = "#{BASE_URL}/#{model}:#{stream ? 'streamGenerateContent' : 'generateContent'}?key=#{@api_key}"

        body = {
          contents: filtered.map { |m| serialize_message(m) }
        }
        body[:systemInstruction] = { parts: [{ text: system_msg }] } if system_msg
        body[:tools] = [{ functionDeclarations: tools.map { |t| translate_tool(t) } }] unless tools.empty?
        body.merge!(options)

        HTTP::Request.new(
          method: :post,
          url: url,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate(body),
          stream: stream
        )
      end

      def parse_response(raw_response)
        raise_error(raw_response) unless raw_response.success?

        data = raw_response.json
        candidate = data.dig('candidates', 0)
        parts = candidate&.dig('content', 'parts') || []

        text_parts = parts.select { |p| p['text'] }.map { |p| p['text'] }
        function_calls = parts.select { |p| p['functionCall'] }

        tool_calls = function_calls.map.with_index do |fc, i|
          Types::ToolCall.new(
            id: "fc_#{i}",
            name: fc.dig('functionCall', 'name'),
            arguments: fc.dig('functionCall', 'args') || {},
            call_index: i
          )
        end

        message = Types::Message.new(
          role: 'assistant',
          content: text_parts.join,
          tool_calls: tool_calls.empty? ? nil : tool_calls
        )

        usage_data = data['usageMetadata']
        usage = Types::Usage.new(
          input_tokens: usage_data&.dig('promptTokenCount') || 0,
          output_tokens: usage_data&.dig('candidatesTokenCount') || 0
        )

        Types::Response.new(
          messages: [message],
          tool_calls: tool_calls,
          usage: usage,
          finish_reason: candidate&.dig('finishReason')
        )
      end

      def parse_stream_chunk(raw_chunk)
        line = raw_chunk.to_s.strip
        unless line.start_with?('data: ')
          return Types::StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil,
                                        done: false)
        end

        data = begin
          JSON.parse(line.sub('data: ', ''))
        rescue StandardError
          {}
        end
        parts = data.dig('candidates', 0, 'content', 'parts') || []
        text = parts.filter_map { |p| p['text'] }.join

        Types::StreamChunk.new(delta_content: text.empty? ? nil : text, delta_tool_calls: [], usage: nil, done: false)
      end

      def parse_tool_call(raw_tool_call)
        Types::ToolCall.new(
          id: raw_tool_call['id'] || 'fc_0',
          name: raw_tool_call['name'],
          arguments: raw_tool_call['args'] || {},
          call_index: 0
        )
      end

      def tool_schema_format
        :google
      end

      private

      def extract_system(messages)
        system_parts = messages.select { |m| m.role == 'system' }.map(&:content)
        others = messages.reject { |m| m.role == 'system' }
        [system_parts.empty? ? nil : system_parts.join("\n"), others]
      end

      def serialize_message(message)
        role = message.role == 'assistant' ? 'model' : 'user'

        if message.role == 'tool'
          return {
            role: 'function',
            parts: [{ functionResponse: { name: message.tool_call_id, response: { content: message.content } } }]
          }
        end

        h = { role: role, parts: [] }
        h[:parts] << { text: message.content } if message.content
        if message.tool_calls
          message.tool_calls.each do |tc|
            h[:parts] << { functionCall: { name: tc.name, args: tc.arguments } }
          end
        end
        h[:parts] = [{ text: '' }] if h[:parts].empty?
        h
      end

      def translate_tool(tool)
        {
          name: tool[:name],
          description: tool[:description],
          parameters: tool[:inputSchema]
        }
      end

      def raise_error(response)
        body = begin
          response.json
        rescue StandardError
          {}
        end
        message = body.dig('error', 'message') || response.error || 'Unknown error'

        case response.status
        when 429
          raise RateLimitError, message
        when 400
          if message.downcase.include?('token') || message.downcase.include?('context')
            raise ContextLengthError,
                  message
          end

          raise ProviderError, message
        else
          raise ProviderError, message
        end
      end
    end
  end
end
