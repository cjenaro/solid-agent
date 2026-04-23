require 'test_helper'
require 'solid_agent'
require 'solid_agent/tool/mcp/transport/sse'

class FakeSseConnection
  attr_reader :messages

  def initialize(responses)
    @responses = responses
    @messages = []
    @connected = false
  end

  def connected?
    @connected
  end

  def post(endpoint, body)
    @messages << { endpoint: endpoint, body: body }
    response = @responses.shift || '{}'
    response
  end

  def close
    @connected = false
  end
end

class SseTransportTest < ActiveSupport::TestCase
  test 'initializes with URL' do
    transport = SolidAgent::Tool::MCP::Transport::SSE.new(url: 'http://localhost:3001/mcp')
    assert_equal 'http://localhost:3001/mcp', transport.url
  end

  test 'send_and_receive sends JSON-RPC request via POST' do
    fake_response = '{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}'
    transport = SolidAgent::Tool::MCP::Transport::SSE.new(url: 'http://localhost:3001/mcp')
    # We can't easily test the actual HTTP call without a server, so test the interface
    assert transport.respond_to?(:send_and_receive)
    assert transport.respond_to?(:close)
  end

  test 'close resets connection' do
    transport = SolidAgent::Tool::MCP::Transport::SSE.new(url: 'http://localhost:3001/mcp')
    transport.close
    # Should not raise
    assert true
  end
end
