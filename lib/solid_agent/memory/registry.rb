module SolidAgent
  module Memory
    class Registry
      STRATEGIES = {
        sliding_window: 'SolidAgent::Memory::SlidingWindow',
        full_history: 'SolidAgent::Memory::FullHistory',
        compaction: 'SolidAgent::Memory::Compaction'
      }.freeze

      def self.resolve(name)
        class_name = STRATEGIES[name]
        unless class_name
          raise ArgumentError,
                "Unknown memory strategy: #{name}. Available: #{STRATEGIES.keys.join(', ')}"
        end

        class_name.constantize
      end

      def self.build(name, **options, &block)
        strategy = resolve(name).new(**options)

        if block
          builder = ChainBuilder.new
          yield(builder)
          Chain.new(strategies: [strategy] + builder.strategies)
        else
          strategy
        end
      end
    end
  end
end
