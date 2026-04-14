module SolidAgent
  module Models
    module Google
      GEMINI_2_5_PRO = Model.new('gemini-2.5-pro', context_window: 1_048_576, max_output: 65_536,
                                                   input_price_per_million: 1.25, output_price_per_million: 10.0).freeze
      GEMINI_2_5_FLASH = Model.new('gemini-2.5-flash', context_window: 1_048_576, max_output: 65_536,
                                                       input_price_per_million: 0.3, output_price_per_million: 2.5).freeze
      GEMINI_2_5_FLASH_LITE = Model.new('gemini-2.5-flash-lite', context_window: 1_048_576, max_output: 65_536,
                                                                 input_price_per_million: 0.1, output_price_per_million: 0.4).freeze
      GEMINI_2_0_FLASH = Model.new('gemini-2.0-flash', context_window: 1_048_576, max_output: 8_192,
                                                       input_price_per_million: 0.1, output_price_per_million: 0.4).freeze
    end
  end
end
