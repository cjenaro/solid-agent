require 'solid_agent/provider/openai'

module SolidAgent
  module Provider
    class OpenAiCompatible < OpenAi
      def initialize(base_url:, api_key: nil, default_model: 'default')
        @api_key = api_key
        @default_model = default_model
        @base_url = base_url
      end
    end
  end
end
