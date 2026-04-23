require 'json'

module SolidAgent
  module Provider
    class Anthropic
      include Base

      BASE_URL = 'https://api.anthropic.com/v1/messages'

      def initialize(api_key:, default_model: Models::Anthropic::CLAUDE_SONNET_4)
        @api_key = api_key
        @default_model = default_model
      end

      def build_request(messages:, tools:, stream:, model:, max_tokens: nil, temperature: nil, tool_choice: nil, options: {})
        system_msg, filtered = extract_system(messages)

        body = {
          model: model.to_s,
          messages: filtered.map { |m| serialize_message(m) },
          max_tokens: max_tokens || model.max_output,
          stream: stream
        }
        body[:temperature] = temperature if temperature
        body[:system] = system_msg if system_msg
        body[:tools] = tools.map { |t| translate_tool(t) } unless tools.empty?
        body.merge!(options)

        HTTP::Request.new(
          method: :post,
          url: BASE_URL,
          headers: {
            'x-api-key' => @api_key,
            'anthropic-version' => '2023-06-01',
            'Content-Type' => 'application/json'
          },
          body: JSON.generate(body),
          stream: stream
        )
      end

      def parse_response(raw_response)
        raise_error(raw_response) unless raw_response.success?

        data = raw_response.json
        content_blocks = data['content'] || []
        text_parts = content_blocks.select { |b| b['type'] == 'text' }.map { |b| b['text'] }
        tool_use_parts = content_blocks.select { |b| b['type'] == 'tool_use' }

        tool_calls = tool_use_parts.map do |tu|
          Types::ToolCall.new(id: tu['id'], name: tu['name'], arguments: tu['input'], call_index: 0)
        end

        message = Types::Message.new(
          role: 'assistant',
          content: text_parts.join,
          tool_calls: tool_calls.empty? ? nil : tool_calls
        )

        usage = Types::Usage.new(
          input_tokens: data.dig('usage', 'input_tokens') || 0,
          output_tokens: data.dig('usage', 'output_tokens') || 0
        )

        Types::Response.new(
          messages: [message],
          tool_calls: tool_calls,
          usage: usage,
          finish_reason: data['stop_reason']
        )
      end

      def parse_stream_chunk(raw_chunk)
        lines = raw_chunk.to_s.strip.split("\n")
        event_line = lines.find { |l| l.start_with?('event:') }
        data_line = lines.find { |l| l.start_with?('data:') }

        event_type = event_line&.sub('event: ', '')&.strip

        if event_type == 'message_stop'
          return Types::StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil,
                                        done: true)
        end

        unless data_line
          return Types::StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil,
                                        done: false)
        end

        data = begin
          JSON.parse(data_line.sub('data: ', ''))
        rescue StandardError
          {}
        end

        case event_type
        when 'content_block_delta'
          delta = data['delta'] || {}
          Types::StreamChunk.new(
            delta_content: delta['text'],
            delta_tool_calls: [],
            usage: nil,
            done: false
          )
        when 'message_delta'
          usage_data = data.dig('usage')
          Types::StreamChunk.new(
            delta_content: nil,
            delta_tool_calls: [],
            usage: if usage_data
                     Types::Usage.new(input_tokens: 0,
                                      output_tokens: usage_data['output_tokens'] || 0)
                   end,
            done: false
          )
        else
          Types::StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil, done: false)
        end
      end

      def parse_tool_call(raw_tool_call)
        Types::ToolCall.new(
          id: raw_tool_call['id'],
          name: raw_tool_call['name'],
          arguments: raw_tool_call['input'] || {},
          call_index: 0
        )
      end

      def tool_schema_format
        :anthropic
      end

      private

      def extract_system(messages)
        system_parts = messages.select { |m| m.role == 'system' }.map(&:content)
        others = messages.reject { |m| m.role == 'system' }
        [system_parts.empty? ? nil : system_parts.join("\n"), others]
      end

      def serialize_message(message)
        h = { role: message.role }

        if message.role == 'tool'
          h[:role] = 'user'
          h[:content] = [{ type: 'tool_result', tool_use_id: message.tool_call_id, content: message.content }]
          return h
        end

        if message.tool_calls && !message.tool_calls.empty?
          text_block = message.content ? [{ type: 'text', text: message.content }] : []
          tool_blocks = message.tool_calls.map do |tc|
            { type: 'tool_use', id: tc.id, name: tc.name, input: tc.arguments }
          end
          h[:content] = text_block + tool_blocks
        else
          h[:content] = message.content || ''
        end

        h
      end

      def translate_tool(tool)
        {
          name: tool[:name],
          description: tool[:description],
          input_schema: tool[:inputSchema]
        }
      end

      def raise_error(response)
        body = begin
          response.json
        rescue StandardError
          {}
        end
        message = body.dig('error', 'message') || response.error || 'Unknown error'
        body.dig('error', 'type')

        case response.status
        when 429
          raise RateLimitError, message
        when 400
          if message.downcase.include?('context') || message.downcase.include?('token')
            raise ContextLengthError, message
          end

          raise ProviderError, message
        when 529
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
