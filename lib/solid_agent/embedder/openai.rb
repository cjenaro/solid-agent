require 'json'

module SolidAgent
  module Embedder
    class OpenAi < Base
      EMBEDDINGS_URL = 'https://api.openai.com/v1/embeddings'
      DEFAULT_MODEL = 'text-embedding-3-small'
      DEFAULT_DIMENSIONS = 1536

      attr_reader :api_key, :model, :dimensions

      def initialize(api_key:, model: DEFAULT_MODEL, dimensions: DEFAULT_DIMENSIONS, base_url: nil)
        @api_key = api_key
        @model = model
        @dimensions = dimensions
        @base_url = base_url || EMBEDDINGS_URL
        @http_adapter = SolidAgent::HTTP::NetHttpAdapter.new
      end

      def embed(text)
        request = build_request(text)
        response = @http_adapter.call(request)
        parse_response(response)
      end

      def build_request(text)
        body = {
          model: @model,
          input: text,
          dimensions: @dimensions
        }

        SolidAgent::HTTP::Request.new(
          method: :post,
          url: @base_url,
          headers: {
            'Content-Type' => 'application/json',
            'Authorization' => "Bearer #{@api_key}"
          },
          body: JSON.generate(body),
          stream: false
        )
      end

      def parse_response(raw_response)
        unless raw_response.success?
          body = begin
            raw_response.json
          rescue StandardError
            {}
          end
          message = body.dig('error', 'message') || raw_response.error || 'Embedding failed'
          raise SolidAgent::ProviderError, message
        end

        data = raw_response.json
        embedding = data.dig('data', 0, 'embedding')
        raise SolidAgent::ProviderError, 'No embedding in response' unless embedding

        embedding
      end
    end
  end
end
