require 'test_helper'
require 'solid_agent/tool/mcp/mcp_tool'

class FakeClient
  def call_tool(name, arguments)
    "result from #{name}: #{arguments}"
  end
end

class MCPToolTest < ActiveSupport::TestCase
  test 'delegates execute to MCP client' do
    schema = SolidAgent::Tool::Schema.new(
      name: 'read_file',
      description: 'Read a file',
      input_schema: { type: 'object', properties: { path: { type: 'string' } } }
    )
    tool = SolidAgent::Tool::MCP::McpTool.new(schema: schema, client: FakeClient.new)
    result = tool.execute({ 'path' => '/tmp/test.txt' })
    assert_equal 'result from read_file: {"path"=>"/tmp/test.txt"}', result
  end

  test 'exposes schema' do
    schema = SolidAgent::Tool::Schema.new(
      name: 'write_file',
      description: 'Write a file',
      input_schema: { type: 'object', properties: { path: { type: 'string' }, content: { type: 'string' } } }
    )
    tool = SolidAgent::Tool::MCP::McpTool.new(schema: schema, client: FakeClient.new)
    assert_equal 'write_file', tool.schema.name
  end
end
