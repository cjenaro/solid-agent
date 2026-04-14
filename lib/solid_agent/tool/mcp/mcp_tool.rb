module SolidAgent
  module Tool
    module MCP
      class McpTool
        attr_reader :schema

        def initialize(schema:, client:)
          @schema = schema
          @client = client
        end

        def execute(arguments)
          @client.call_tool(schema.name, arguments)
        end
      end
    end
  end
end
