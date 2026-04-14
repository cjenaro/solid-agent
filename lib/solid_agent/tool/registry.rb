module SolidAgent
  module Tool
    class Registry
      def initialize
        @tools = {}
      end

      def register(tool_or_class)
        case tool_or_class
        when Class
          instance = tool_or_class.new
          schema = tool_or_class.to_schema
          @tools[schema.name] = { instance: instance, schema: schema }
        when InlineTool
          @tools[tool_or_class.schema.name] = { instance: tool_or_class, schema: tool_or_class.schema }
        else
          raise Error, "Cannot register tool of type: #{tool_or_class.class}"
        end
      end

      def lookup(name)
        entry = @tools[name.to_s]
        raise Error, "Tool not found: #{name}" unless entry

        entry[:instance]
      end

      def registered?(name)
        @tools.key?(name.to_s)
      end

      def all_schemas
        @tools.values.map { |e| e[:schema] }
      end

      def all_schemas_hashes
        all_schemas.map(&:to_hash)
      end

      def tool_count
        @tools.size
      end

      def tool_names
        @tools.keys
      end
    end
  end
end
