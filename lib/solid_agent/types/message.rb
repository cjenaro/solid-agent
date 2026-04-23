module SolidAgent
  module Types
    class Message
      attr_reader :role, :content, :tool_calls, :tool_call_id, :metadata, :image_url, :image_data

      def initialize(role:, content:, tool_calls: nil, tool_call_id: nil, metadata: {},
                     image_url: nil, image_data: nil)
        @role = role
        @content = content
        @tool_calls = tool_calls
        @tool_call_id = tool_call_id
        @metadata = metadata
        @image_url = image_url
        @image_data = image_data
        freeze
      end

      def multimodal?
        @image_url || @image_data
      end

      def to_hash
        h = { role: role }
        h[:content] = build_content
        h[:tool_calls] = tool_calls.map(&:to_hash) if tool_calls && !tool_calls.empty?
        h[:tool_call_id] = tool_call_id if tool_call_id
        h[:metadata] = metadata if metadata && !metadata.empty?
        h
      end

      private

      def build_content
        return content unless multimodal?

        parts = [{ type: 'text', text: content }]
        if @image_url
          parts << { type: 'image_url', image_url: { url: @image_url } }
        end
        if @image_data
          parts << {
            type: 'image_url',
            image_url: {
              url: "data:#{@image_data[:media_type]};base64,#{@image_data[:data]}"
            }
          }
        end
        parts
      end
    end
  end
end
