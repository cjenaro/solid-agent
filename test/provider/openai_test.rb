require 'test_helper'
require 'solid_agent'

class OpenAiProviderTest < ActiveSupport::TestCase
  def setup
    @provider = SolidAgent::Provider::OpenAi.new(api_key: 'test-key')
  end

  test 'build_request creates valid HTTP request' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(
      messages: messages,
      tools: [],
      stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O
    )
    assert_instance_of SolidAgent::HTTP::Request, request
    assert_equal :post, request.method
    assert_equal 'https://api.openai.com/v1/chat/completions', request.url
    assert_includes request.headers['Authorization'], 'test-key'
    body = JSON.parse(request.body)
    assert_equal 'gpt-4o', body['model']
    assert_equal 'user', body['messages'][0]['role']
  end

  test 'build_request includes tools in OpenAI format' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Search')]
    tools = [{
      name: 'web_search',
      description: 'Search the web',
      inputSchema: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] }
    }]
    request = @provider.build_request(messages: messages, tools: tools, stream: false, model: SolidAgent::Models::OpenAi::GPT_4O)
    body = JSON.parse(request.body)
    assert_equal 1, body['tools'].length
    assert_equal 'web_search', body['tools'][0]['function']['name']
  end

  test 'build_request sets stream option' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(messages: messages, tools: [], stream: true, model: SolidAgent::Models::OpenAi::GPT_4O)
    body = JSON.parse(request.body)
    assert_equal true, body['stream']
  end

  test 'parse_response extracts assistant message' do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"id":"chatcmpl-1","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}'
    )
    response = @provider.parse_response(raw)
    assert_equal 'Hello!', response.messages.first.content
    assert_equal 'stop', response.finish_reason
    assert_equal 10, response.usage.input_tokens
    assert_equal 5, response.usage.output_tokens
  end

  test 'parse_response extracts tool calls' do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"id":"chatcmpl-2","choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"web_search","arguments":"{\"query\":\"test\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":20,"completion_tokens":15}}'
    )
    response = @provider.parse_response(raw)
    assert response.has_tool_calls?
    assert_equal 1, response.tool_calls.length
    assert_equal 'call_1', response.tool_calls.first.id
    assert_equal 'web_search', response.tool_calls.first.name
    assert_equal({ 'query' => 'test' }, response.tool_calls.first.arguments)
  end

  test 'parse_stream_chunk parses SSE data' do
    chunk = @provider.parse_stream_chunk('data: {"id":"chatcmpl-3","choices":[{"delta":{"content":"Hi"}}]}' + "\n\n")
    assert_equal 'Hi', chunk.delta_content
    assert_not chunk.done?
  end

  test 'parse_stream_chunk detects done' do
    chunk = @provider.parse_stream_chunk("data: [DONE]\n\n")
    assert chunk.done?
  end

  test 'parse_stream_chunk with tool call delta' do
    chunk = @provider.parse_stream_chunk('data: {"id":"chatcmpl-4","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"search","arguments":""}}]}}]}' + "\n\n")
    assert_equal 1, chunk.delta_tool_calls.length
    assert_equal 'call_1', chunk.delta_tool_calls.first['id']
  end

  test 'raises RateLimitError on 429' do
    raw = SolidAgent::HTTP::Response.new(
      status: 429, headers: { 'retry-after' => '30' }, error: 'Rate limited',
      body: '{"error":{"message":"Rate limit exceeded"}}'
    )
    assert_raises(SolidAgent::RateLimitError) { @provider.parse_response(raw) }
  end

  test 'raises ContextLengthError on context length error' do
    raw = SolidAgent::HTTP::Response.new(
      status: 400, headers: {}, error: 'Bad request',
      body: '{"error":{"message":"maximum context length exceeded","code":"context_length_exceeded"}}'
    )
    assert_raises(SolidAgent::ContextLengthError) { @provider.parse_response(raw) }
  end

  test 'tool_schema_format returns openai format' do
    assert_equal :openai, @provider.tool_schema_format
  end

  test 'build_request includes temperature when provided' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O, temperature: 0.3
    )
    body = JSON.parse(request.body)
    assert_equal 0.3, body['temperature']
  end

  test 'build_request includes max_tokens from parameter overriding model default' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O, max_tokens: 2048
    )
    body = JSON.parse(request.body)
    assert_equal 2048, body['max_tokens']
  end

  test 'build_request includes tool_choice auto' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    tools = [{
      name: 'test', description: 'Test', inputSchema: { type: 'object', properties: {} }
    }]
    request = @provider.build_request(
      messages: messages, tools: tools, stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O, tool_choice: :auto
    )
    body = JSON.parse(request.body)
    assert_equal 'auto', body['tool_choice']
  end

  test 'build_request includes tool_choice required' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    tools = [{
      name: 'test', description: 'Test', inputSchema: { type: 'object', properties: {} }
    }]
    request = @provider.build_request(
      messages: messages, tools: tools, stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O, tool_choice: :required
    )
    body = JSON.parse(request.body)
    assert_equal 'required', body['tool_choice']
  end

  test 'build_request includes tool_choice none' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O, tool_choice: :none
    )
    body = JSON.parse(request.body)
    assert_equal 'none', body['tool_choice']
  end

  test 'build_request does not include tool_choice when nil' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O, tool_choice: nil
    )
    body = JSON.parse(request.body)
    refute body.key?('tool_choice')
  end
end
