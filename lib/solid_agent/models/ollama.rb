module SolidAgent
  module Models
    module Ollama
      LLAMA_3_3_70B = Model.new('llama3.3:70b', context_window: 128_000, max_output: 4_096).freeze
      QWEN_2_5_72B = Model.new('qwen2.5:72b', context_window: 128_000, max_output: 8_192).freeze
      DEEPSEEK_V3 = Model.new('deepseek-v3:671b', context_window: 128_000, max_output: 8_192).freeze
    end
  end
end
