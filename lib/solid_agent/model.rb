module SolidAgent
  class Model
    attr_reader :id, :context_window, :max_output, :input_price_per_million, :output_price_per_million

    def initialize(id, context_window:, max_output:, input_price_per_million: 0, output_price_per_million: 0)
      @id = id.freeze
      @context_window = context_window
      @max_output = max_output
      @input_price_per_million = input_price_per_million
      @output_price_per_million = output_price_per_million
      freeze
    end

    def to_s
      id
    end
  end
end
