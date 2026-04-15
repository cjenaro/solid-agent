require 'json'

module SolidAgent
  module Provider
    class OpenAi
      include Base

      BASE_URL = 'https://api.openai.com/v1/chat/completions'

      def initialize(api_key:, default_model: Models::OpenAi::GPT_4O, base_url: nil)
        @api_key = api_key
        @default_model = default_model
        @base_url = base_url || BASE_URL
      end

      def build_request(messages:, tools:, stream:, model:, max_tokens: nil, options: {})
        body = {
          model: model.to_s,
          messages: messages.map { |m| serialize_message(m) },
          stream: stream
        }
        body[:max_tokens] = max_tokens if max_tokens
        body[:tools] = tools.map { |t| translate_tool(t) } unless tools.empty?
        body.merge!(options)

        HTTP::Request.new(
          method: :post,
          url: base_url,
          headers: build_headers,
          body: JSON.generate(body),
          stream: stream
        )
      end

      def parse_response(raw_response)
        raise_error(raw_response) unless raw_response.success?

        data = raw_response.json
        choice = data.dig('choices', 0)
        msg = choice&.dig('message')

        tool_calls = parse_tool_calls_from_message(msg)
        message = Types::Message.new(
          role: msg&.dig('role') || 'assistant',
          content: msg&.dig('content'),
          tool_calls: tool_calls.empty? ? nil : tool_calls
        )

        usage = parse_usage(data['usage'])
        Types::Response.new(
          messages: [message],
          tool_calls: tool_calls,
          usage: usage,
          finish_reason: choice&.dig('finish_reason')
        )
      end

      def parse_stream_chunk(raw_chunk)
        line = raw_chunk.to_s.strip
        if line.start_with?('data: [DONE]')
          return Types::StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil, done: true)
        end

        unless line.start_with?('data: ')
          return Types::StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil,
                                        done: false)
        end

        json_str = line.sub('data: ', '')
        data = begin
          JSON.parse(json_str)
        rescue StandardError
          {}
        end
        choice = data.dig('choices', 0) || {}

        delta = choice['delta'] || {}
        delta_content = delta['content']
        delta_tool_calls = delta['tool_calls'] || []

        Types::StreamChunk.new(
          delta_content: delta_content,
          delta_tool_calls: delta_tool_calls,
          usage: nil,
          done: false
        )
      end

      def parse_tool_call(raw_tool_call)
        args = raw_tool_call['arguments']
        arguments = args.is_a?(String) ? JSON.parse(args) : args
        Types::ToolCall.new(
          id: raw_tool_call['id'],
          name: raw_tool_call['name'] || raw_tool_call.dig('function', 'name'),
          arguments: arguments,
          call_index: raw_tool_call['index'] || 0
        )
      end

      def tool_schema_format
        :openai
      end

      private

      attr_reader :base_url

      def build_headers
        headers = { 'Content-Type' => 'application/json' }
        headers['Authorization'] = "Bearer #{@api_key}" if @api_key
        headers
      end

      def serialize_message(message)
        h = { role: message.role }
        h[:content] = message.content if message.content
        if message.tool_calls && !message.tool_calls.empty?
          h[:tool_calls] = message.tool_calls.map do |tc|
            {
              id: tc.id,
              type: 'function',
              function: { name: tc.name, arguments: JSON.generate(tc.arguments) }
            }
          end
        end
        h[:tool_call_id] = message.tool_call_id if message.tool_call_id
        h
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

      def parse_tool_calls_from_message(msg)
        return [] unless msg&.dig('tool_calls')

        msg['tool_calls'].map do |tc|
          func = tc['function']
          args = func['arguments']
          arguments = args.is_a?(String) ? JSON.parse(args) : args
          Types::ToolCall.new(
            id: tc['id'],
            name: func['name'],
            arguments: arguments,
            call_index: tc['index'] || 0
          )
        end
      end

      def parse_usage(usage_data)
        return Types::Usage.new(input_tokens: 0, output_tokens: 0) unless usage_data

        Types::Usage.new(
          input_tokens: usage_data['prompt_tokens'] || 0,
          output_tokens: usage_data['completion_tokens'] || 0
        )
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
          retry_after = response.headers['retry-after']&.to_i
          raise RateLimitError.new(message, retry_after: retry_after)
        when 400
          code = body.dig('error', 'code')
          if code == 'context_length_exceeded' || message.downcase.include?('context length')
            raise ContextLengthError.new(message)
          end

          raise ProviderError, message
        when 408, 504
          raise ProviderTimeoutError, message
        else
          raise ProviderError, message
        end
      end
    end
  end
end
