module SolidAgent
  module Memory
    class Chain < Base
      attr_reader :strategies

      def initialize(strategies:, **options)
        @strategies = strategies
        super
      end

      def filter(messages)
        @strategies.reduce(messages) do |current, strategy|
          strategy.filter(current)
        end
      end

      def compact!(messages)
        @strategies.reduce(messages) do |current, strategy|
          strategy.compact!(current)
        end
      end
    end
  end
end
