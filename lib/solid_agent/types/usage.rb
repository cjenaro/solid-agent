module SolidAgent
  module Types
    class Usage
      attr_reader :input_tokens, :output_tokens, :input_price_per_million, :output_price_per_million

      def initialize(input_tokens:, output_tokens:, input_price_per_million: 0, output_price_per_million: 0)
        @input_tokens = input_tokens
        @output_tokens = output_tokens
        @input_price_per_million = input_price_per_million
        @output_price_per_million = output_price_per_million
      end

      def total_tokens
        input_tokens + output_tokens
      end

      def cost
        (input_tokens * input_price_per_million / 1_000_000.0) +
          (output_tokens * output_price_per_million / 1_000_000.0)
      end

      def +(other)
        Usage.new(
          input_tokens: input_tokens + other.input_tokens,
          output_tokens: output_tokens + other.output_tokens,
          input_price_per_million: input_price_per_million,
          output_price_per_million: output_price_per_million
        )
      end
    end
  end
end
