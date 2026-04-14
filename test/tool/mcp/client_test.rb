require 'test_helper'
require 'solid_agent/tool/mcp/client'

class EchoMCPTransport < SolidAgent::Tool::MCP::Transport::Base
  def initialize(responses = {})
    @responses = responses
  end

  def send_and_receive(request)
    method = request[:method]
    response = @responses[method]
    JSON.generate({
                    jsonrpc: '2.0',
                    id: request[:id],
                    result: response
                  })
  end

  def close; end
end

class MCPClientTest < ActiveSupport::TestCase
  test 'initializes and discovers tools' do
    transport = EchoMCPTransport.new({
                                       'initialize' => { capabilities: { tools: {} } },
                                       'tools/list' => {
                                         tools: [
                                           { name: 'read_file', description: 'Read a file',
                                             inputSchema: { type: 'object', properties: { path: { type: 'string' } } } }
                                         ]
                                       }
                                     })
    client = SolidAgent::Tool::MCP::Client.new(name: :filesystem, transport: transport)
    client.initialize!
    tools = client.discover_tools
    assert_equal 1, tools.length
    assert_equal 'read_file', tools.first.schema.name
  end

  test 'calls a tool via JSON-RPC' do
    transport = EchoMCPTransport.new({
                                       'initialize' => { capabilities: {} },
                                       'tools/list' => { tools: [] },
                                       'tools/call' => { content: [{ type: 'text', text: 'file contents' }] }
                                     })
    client = SolidAgent::Tool::MCP::Client.new(name: :test, transport: transport)
    client.initialize!
    result = client.call_tool('read_file', { 'path' => '/tmp/test.txt' })
    assert_equal({ content: [{ 'type' => 'text', 'text' => 'file contents' }] }, result)
  end
end
