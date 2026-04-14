module SolidAgent
  module Provider
    class Registry
      def initialize
        @providers = {}
      end

      def register(name, &config_block)
        @providers[name.to_sym] = config_block
      end

      def resolve(name)
        block = @providers[name.to_sym]
        raise Error, "Provider not registered: #{name}" unless block

        block.call
      end

      def registered?(name)
        @providers.key?(name.to_sym)
      end

      def names
        @providers.keys
      end
    end
  end
end
