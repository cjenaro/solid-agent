require 'test_helper'
require 'solid_agent'

class AnthropicProviderTest < ActiveSupport::TestCase
  def setup
    @provider = SolidAgent::Provider::Anthropic.new(api_key: 'test-key')
  end

  test 'build_request creates valid request with system prompt extraction' do
    messages = [
      SolidAgent::Types::Message.new(role: 'system', content: 'You are helpful'),
      SolidAgent::Types::Message.new(role: 'user', content: 'Hello')
    ]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::Anthropic::CLAUDE_SONNET_4
    )
    body = JSON.parse(request.body)
    assert_equal 'You are helpful', body['system']
    assert_equal 1, body['messages'].length
    assert_equal 'user', body['messages'][0]['role']
    assert_equal 'claude-sonnet-4-0', body['model']
    assert_includes request.headers['x-api-key'], 'test-key'
  end

  test 'build_request includes tools in Anthropic format' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Search')]
    tools = [{
      name: 'web_search',
      description: 'Search the web',
      inputSchema: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] }
    }]
    request = @provider.build_request(messages: messages, tools: tools, stream: false, model: SolidAgent::Models::Anthropic::CLAUDE_SONNET_4)
    body = JSON.parse(request.body)
    assert_equal 1, body['tools'].length
    assert_equal 'web_search', body['tools'][0]['name']
  end

  test 'build_request sets max_tokens' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(messages: messages, tools: [], stream: false,
                                      model: SolidAgent::Models::Anthropic::CLAUDE_SONNET_4, options: { max_tokens: 4096 })
    body = JSON.parse(request.body)
    assert_equal 4096, body['max_tokens']
  end

  test 'parse_response extracts content blocks' do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"Hello!"}],"model":"claude-sonnet-4-0","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":5}}'
    )
    response = @provider.parse_response(raw)
    assert_equal 'Hello!', response.messages.first.content
    assert_equal 'end_turn', response.finish_reason
    assert_equal 10, response.usage.input_tokens
  end

  test 'parse_response extracts tool_use content blocks' do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"id":"msg_2","type":"message","role":"assistant","content":[{"type":"text","text":"Let me search"},{"type":"tool_use","id":"toolu_1","name":"web_search","input":{"query":"test"}}],"model":"claude-sonnet-4-0","stop_reason":"tool_use","usage":{"input_tokens":20,"output_tokens":15}}'
    )
    response = @provider.parse_response(raw)
    assert response.has_tool_calls?
    tc = response.tool_calls.first
    assert_equal 'toolu_1', tc.id
    assert_equal 'web_search', tc.name
    assert_equal({ 'query' => 'test' }, tc.arguments)
  end

  test 'parse_stream_chunk parses content_block_delta' do
    chunk = @provider.parse_stream_chunk('event: content_block_delta' + "\n" + 'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}' + "\n\n")
    assert_equal 'Hi', chunk.delta_content
  end

  test 'parse_stream_chunk detects message_stop as done' do
    chunk = @provider.parse_stream_chunk('event: message_stop' + "\n" + 'data: {"type":"message_stop"}' + "\n\n")
    assert chunk.done?
  end

  test 'raises RateLimitError on 429' do
    raw = SolidAgent::HTTP::Response.new(
      status: 429, headers: {}, error: 'Rate limited',
      body: '{"error":{"type":"rate_limit_error","message":"Too many requests"}}'
    )
    assert_raises(SolidAgent::RateLimitError) { @provider.parse_response(raw) }
  end

  test 'raises error on overloaded' do
    raw = SolidAgent::HTTP::Response.new(
      status: 529, headers: {}, error: 'Overloaded',
      body: '{"error":{"type":"overloaded_error","message":"Overloaded"}}'
    )
    assert_raises(SolidAgent::ProviderError) { @provider.parse_response(raw) }
  end

  test 'tool_schema_format returns anthropic format' do
    assert_equal :anthropic, @provider.tool_schema_format
  end
end
