module SolidAgent
  module Agent
    class Registry
      Entry = Struct.new(:name, :klass)

      def initialize
        @agents = {}
      end

      def register(agent_class)
        name = agent_class.name
        raise Error, 'Agent class must have a name' unless name

        @agents[name] = Entry.new(name, agent_class)
      end

      def resolve(name)
        entry = @agents[name]
        raise Error, "Agent not found: #{name}" unless entry

        entry.klass
      end

      def registered?(name)
        @agents.key?(name)
      end

      def all
        @agents.values
      end
    end
  end
end
