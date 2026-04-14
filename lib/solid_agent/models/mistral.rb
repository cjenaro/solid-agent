module SolidAgent
  module Models
    module Mistral
      MISTRAL_LARGE = Model.new('mistral-large-2512', context_window: 262_144, max_output: 262_144,
                                                      input_price_per_million: 0.5, output_price_per_million: 1.5).freeze
      MISTRAL_MEDIUM = Model.new('mistral-medium-latest', context_window: 128_000, max_output: 16_384,
                                                          input_price_per_million: 0.4, output_price_per_million: 2.0).freeze
      MISTRAL_SMALL = Model.new('mistral-small-latest', context_window: 256_000, max_output: 256_000,
                                                        input_price_per_million: 0.15, output_price_per_million: 0.6).freeze
      CODESTRAL = Model.new('codestral-latest', context_window: 256_000, max_output: 4_096,
                                                input_price_per_million: 0.3, output_price_per_million: 0.9).freeze
    end
  end
end
