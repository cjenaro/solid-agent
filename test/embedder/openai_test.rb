require 'test_helper'
require 'solid_agent'
require 'solid_agent/embedder/openai'

class OpenAiEmbedderTest < ActiveSupport::TestCase
  def setup
    @embedder = SolidAgent::Embedder::OpenAi.new(api_key: 'test-key', model: 'text-embedding-3-small')
  end

  test 'initializes with api_key and model' do
    assert_equal 'test-key', @embedder.api_key
    assert_equal 'text-embedding-3-small', @embedder.model
  end

  test 'default model is text-embedding-3-small' do
    embedder = SolidAgent::Embedder::OpenAi.new(api_key: 'test-key')
    assert_equal 'text-embedding-3-small', embedder.model
  end

  test 'default dimensions is 1536' do
    embedder = SolidAgent::Embedder::OpenAi.new(api_key: 'test-key')
    assert_equal 1536, embedder.dimensions
  end

  test 'custom dimensions' do
    embedder = SolidAgent::Embedder::OpenAi.new(api_key: 'test-key', dimensions: 512)
    assert_equal 512, embedder.dimensions
  end

  test 'build_request creates correct HTTP request' do
    request = @embedder.build_request('Hello world')
    assert_equal :post, request.method
    assert_equal 'https://api.openai.com/v1/embeddings', request.url
    assert_equal 'application/json', request.headers['Content-Type']
    body = JSON.parse(request.body)
    assert_equal 'text-embedding-3-small', body['model']
    assert_equal 'Hello world', body['input']
  end

  test 'parse_response returns embedding array' do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"object":"list","data":[{"object":"embedding","index":0,"embedding":[0.1,0.2,0.3]}],"model":"text-embedding-3-small","usage":{"prompt_tokens":2,"total_tokens":2}}'
    )
    embedding = @embedder.parse_response(raw)
    assert_equal [0.1, 0.2, 0.3], embedding
  end

  test 'parse_response raises on error' do
    raw = SolidAgent::HTTP::Response.new(
      status: 401, headers: {}, error: 'Unauthorized',
      body: '{"error":{"message":"Invalid API key"}}'
    )
    assert_raises(SolidAgent::ProviderError) { @embedder.parse_response(raw) }
  end
end
