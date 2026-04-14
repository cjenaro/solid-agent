require 'test_helper'
require 'solid_agent'

class GoogleProviderTest < ActiveSupport::TestCase
  def setup
    @provider = SolidAgent::Provider::Google.new(api_key: 'test-key')
  end

  test 'build_request creates valid request' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::Google::GEMINI_2_5_PRO
    )
    assert_equal :post, request.method
    assert_includes request.url, 'generativelanguage.googleapis.com'
    assert_includes request.url, 'gemini-2.5-pro'
    body = JSON.parse(request.body)
    assert_equal 1, body['contents'].length
    assert_equal 'user', body['contents'][0]['role']
    assert_equal 'Hello', body['contents'][0]['parts'][0]['text']
  end

  test 'build_request extracts system instruction' do
    messages = [
      SolidAgent::Types::Message.new(role: 'system', content: 'Be helpful'),
      SolidAgent::Types::Message.new(role: 'user', content: 'Hi')
    ]
    request = @provider.build_request(messages: messages, tools: [], stream: false, model: SolidAgent::Models::Google::GEMINI_2_5_PRO)
    body = JSON.parse(request.body)
    assert_equal 'Be helpful', body['systemInstruction']['parts'][0]['text']
    assert_equal 1, body['contents'].length
  end

  test 'build_request includes tools in Google format' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Search')]
    tools = [{
      name: 'web_search',
      description: 'Search the web',
      inputSchema: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] }
    }]
    request = @provider.build_request(messages: messages, tools: tools, stream: false, model: SolidAgent::Models::Google::GEMINI_2_5_PRO)
    body = JSON.parse(request.body)
    assert_equal 1, body['tools'].length
    func_decls = body['tools'][0]['functionDeclarations']
    assert_equal 1, func_decls.length
    assert_equal 'web_search', func_decls[0]['name']
  end

  test 'parse_response extracts text' do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"candidates":[{"content":{"role":"model","parts":[{"text":"Hello!"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5}}'
    )
    response = @provider.parse_response(raw)
    assert_equal 'Hello!', response.messages.first.content
    assert_equal 'STOP', response.finish_reason
    assert_equal 10, response.usage.input_tokens
    assert_equal 5, response.usage.output_tokens
  end

  test 'parse_response extracts function calls' do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"web_search","args":{"query":"test"}}}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":20,"candidatesTokenCount":15}}'
    )
    response = @provider.parse_response(raw)
    assert response.has_tool_calls?
    tc = response.tool_calls.first
    assert_equal 'web_search', tc.name
    assert_equal({ 'query' => 'test' }, tc.arguments)
  end

  test 'parse_stream_chunk parses text chunk' do
    chunk = @provider.parse_stream_chunk('data: {"candidates":[{"content":{"parts":[{"text":"Hi"}]}}]}' + "\n\n")
    assert_equal 'Hi', chunk.delta_content
  end

  test 'raises error on non-success' do
    raw = SolidAgent::HTTP::Response.new(
      status: 400, headers: {}, error: 'Bad request',
      body: '{"error":{"message":"Invalid request"}}'
    )
    assert_raises(SolidAgent::ProviderError) { @provider.parse_response(raw) }
  end
end
