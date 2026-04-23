# frozen_string_literal: true

module SolidAgent
  module Tool
    # A tool result that includes an image alongside text.
    # When returned from a tool, the React loop will:
    #   1. Add a normal text tool result message
    #   2. Add a user message containing the image
    #
    # Usage in a tool:
    #   def call(timestamp:)
    #     image = VideoFrameService.new(url).frame_base64(timestamp)
    #     SolidAgent::Tool::ImageResult.new(
    #       text: "Frame at #{timestamp}s",
    #       image_data: image
    #     )
    #   end
    class ImageResult
      attr_reader :text, :image_data

      def initialize(text:, image_data:)
        @text = text
        @image_data = image_data
      end
    end
  end
end
