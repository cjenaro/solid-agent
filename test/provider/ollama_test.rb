require 'test_helper'
require 'solid_agent'

class OllamaProviderTest < ActiveSupport::TestCase
  def setup
    @provider = SolidAgent::Provider::Ollama.new(base_url: 'http://localhost:11434')
  end

  test 'build_request creates valid request' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::Ollama::LLAMA_3_3_70B
    )
    assert_equal :post, request.method
    assert_equal 'http://localhost:11434/api/chat', request.url
    body = JSON.parse(request.body)
    assert_equal 'llama3.3:70b', body['model']
    assert_equal false, body['stream']
  end

  test 'parse_response extracts message' do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"model":"llama3.3:70b","message":{"role":"assistant","content":"Hello!"},"done":true}'
    )
    response = @provider.parse_response(raw)
    assert_equal 'Hello!', response.messages.first.content
    assert_equal 'stop', response.finish_reason
  end

  test 'parse_stream_chunk parses message delta' do
    chunk = @provider.parse_stream_chunk('{"message":{"role":"assistant","content":"Hi"},"done":false}' + "\n")
    assert_equal 'Hi', chunk.delta_content
    assert_not chunk.done?
  end

  test 'parse_stream_chunk detects done' do
    chunk = @provider.parse_stream_chunk('{"done":true}' + "\n")
    assert chunk.done?
  end

  test 'supports custom base_url' do
    provider = SolidAgent::Provider::Ollama.new(base_url: 'http://my-server:8080')
    request = provider.build_request(
      messages: [SolidAgent::Types::Message.new(role: 'user', content: 'Hi')],
      tools: [], stream: false, model: SolidAgent::Models::Ollama::LLAMA_3_3_70B
    )
    assert_equal 'http://my-server:8080/api/chat', request.url
  end
end
