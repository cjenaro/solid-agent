module SolidAgent
  module Models
    module Anthropic
      CLAUDE_OPUS_4_6 = Model.new('claude-opus-4-6', context_window: 1_000_000, max_output: 128_000,
                                                     input_price_per_million: 5.0, output_price_per_million: 25.0).freeze
      CLAUDE_SONNET_4_6 = Model.new('claude-sonnet-4-6', context_window: 1_000_000, max_output: 64_000,
                                                         input_price_per_million: 3.0, output_price_per_million: 15.0).freeze
      CLAUDE_OPUS_4_5 = Model.new('claude-opus-4-5', context_window: 200_000, max_output: 64_000,
                                                     input_price_per_million: 5.0, output_price_per_million: 25.0).freeze
      CLAUDE_SONNET_4_5 = Model.new('claude-sonnet-4-5', context_window: 200_000, max_output: 64_000,
                                                         input_price_per_million: 3.0, output_price_per_million: 15.0).freeze
      CLAUDE_SONNET_4 = Model.new('claude-sonnet-4-0', context_window: 200_000, max_output: 64_000,
                                                       input_price_per_million: 3.0, output_price_per_million: 15.0).freeze
      CLAUDE_HAIKU_4_5 = Model.new('claude-haiku-4-5', context_window: 200_000, max_output: 64_000,
                                                       input_price_per_million: 1.0, output_price_per_million: 5.0).freeze
    end
  end
end
