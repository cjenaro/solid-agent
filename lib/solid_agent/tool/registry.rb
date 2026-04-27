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
          @tools[schema.name] = { instance: instance, schema: schema, timeout: tool_or_class.tool_timeout }
        when InlineTool
          @tools[tool_or_class.schema.name] = { instance: tool_or_class, schema: tool_or_class.schema, timeout: tool_or_class.tool_timeout }
        else
          # Duck-typed tools: must respond to to_tool_schema (e.g., DelegateTool, AgentTool)
          if tool_or_class.respond_to?(:to_tool_schema)
            schema_hash = tool_or_class.to_tool_schema
            name = schema_hash[:name]
            @tools[name] = { instance: tool_or_class, schema_hash: schema_hash, timeout: nil }
          else
            raise Error, "Cannot register tool of type: #{tool_or_class.class}"
          end
        end
      end

      def lookup(name)
        entry = @tools[name.to_s]
        raise Error, "Tool not found: #{name}" unless entry

        entry[:instance]
      end

      def lookup_timeout(name)
        entry = @tools[name.to_s]
        entry&.dig(:timeout)
      end

      def registered?(name)
        @tools.key?(name.to_s)
      end

      def all_schemas
        @tools.values.map { |e| e[:schema] }.compact
      end

      def all_schemas_hashes
        @tools.values.map do |e|
          if e[:schema]
            e[:schema].to_hash
          elsif e[:schema_hash]
            e[:schema_hash]
          end
        end.compact
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
