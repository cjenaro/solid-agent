require 'test_helper'
require 'solid_agent/tool/mcp/transport/stdio'

class StdioTransportTest < ActiveSupport::TestCase
  test 'initializes with command and args' do
    transport = SolidAgent::Tool::MCP::Transport::Stdio.new(
      command: 'echo',
      args: ['hello']
    )
    assert_equal 'echo', transport.command
    assert_equal ['hello'], transport.args
  end

  test 'sends JSON-RPC request and reads response via echo' do
    transport = SolidAgent::Tool::MCP::Transport::Stdio.new(
      command: 'cat'
    )
    request = { jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }
    response = transport.send_and_receive(request)
    parsed = JSON.parse(response)
    assert_equal '2.0', parsed['jsonrpc']
    assert_equal 1, parsed['id']
  ensure
    transport.close
  end

  test 'handles missing command' do
    transport = SolidAgent::Tool::MCP::Transport::Stdio.new(
      command: 'nonexistent_command_12345'
    )
    assert_raises(SolidAgent::Error) { transport.send_and_receive({}) }
  end
end
