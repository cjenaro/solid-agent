module SolidAgent
  module Models
    module OpenAi
      GPT_5_4_PRO = Model.new('gpt-5.4-pro', context_window: 1_050_000, max_output: 128_000,
                                             input_price_per_million: 30.0, output_price_per_million: 180.0).freeze
      GPT_5_4 = Model.new('gpt-5.4', context_window: 1_050_000, max_output: 128_000, input_price_per_million: 2.5,
                                     output_price_per_million: 15.0).freeze
      O3_PRO = Model.new('o3-pro', context_window: 200_000, max_output: 100_000, input_price_per_million: 20.0,
                                   output_price_per_million: 80.0).freeze
      O3 = Model.new('o3', context_window: 200_000, max_output: 100_000, input_price_per_million: 2.0,
                           output_price_per_million: 8.0).freeze
      GPT_4O = Model.new('gpt-4o', context_window: 128_000, max_output: 16_384, input_price_per_million: 2.5,
                                   output_price_per_million: 10.0).freeze
      GPT_4O_MINI = Model.new('gpt-4o-mini', context_window: 128_000, max_output: 16_384,
                                             input_price_per_million: 0.15, output_price_per_million: 0.6).freeze
    end
  end
end
