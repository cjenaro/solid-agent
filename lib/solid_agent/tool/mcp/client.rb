require 'json'
require 'solid_agent/tool/schema'
require 'solid_agent/tool/mcp/mcp_tool'

module SolidAgent
  module Tool
    module MCP
      class Client
        attr_reader :name, :tools

        def initialize(name:, transport:)
          @name = name
          @transport = transport
          @tools = []
          @id_counter = 0
          @initialized = false
        end

        def initialize!
          return if @initialized

          send_request('initialize', {
                         protocolVersion: '2024-11-05',
                         capabilities: {},
                         clientInfo: { name: 'solid_agent', version: '0.1.0' }
                       })
          @initialized = true
        end

        def discover_tools
          response = send_request('tools/list', {})
          @tools = (response[:tools] || []).map do |tool_def|
            schema = Schema.new(
              name: tool_def['name'],
              description: tool_def['description'] || '',
              input_schema: tool_def['inputSchema'] || { type: 'object', properties: {} }
            )
            McpTool.new(schema: schema, client: self)
          end
          @tools
        end

        def call_tool(name, arguments)
          send_request('tools/call', { name: name, arguments: arguments })
        end

        def close
          @transport.close
        end

        private

        def send_request(method, params)
          request = {
            jsonrpc: '2.0',
            id: next_id,
            method: method,
            params: params
          }
          raw = @transport.send_and_receive(request)
          data = JSON.parse(raw, symbolize_names: false)
          raise Error, "MCP error: #{data['error']['message']}" if data['error']

          data['result'].is_a?(Hash) ? data['result'].transform_keys(&:to_sym) : data['result']
        end

        def next_id
          @id_counter += 1
        end
      end
    end
  end
end
