module SolidAgent
  module Memory
    class ChainBuilder
      attr_reader :strategies

      def initialize
        @strategies = []
      end

      def then(name, **options)
        strategy = Registry.resolve(name).new(**options)
        @strategies << strategy
      end
    end
  end
end
