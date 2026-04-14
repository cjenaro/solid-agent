require 'test_helper'
require 'solid_agent'

class OpenAiCompatibleProviderTest < ActiveSupport::TestCase
  def setup
    @provider = SolidAgent::Provider::OpenAiCompatible.new(
      base_url: 'http://localhost:8000/v1/chat/completions',
      api_key: 'test-key',
      default_model: 'my-custom-model'
    )
  end

  test 'build_request uses custom base_url' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(messages: messages, tools: [], stream: false, model: SolidAgent::Models::OpenAi::GPT_4O)
    assert_equal 'http://localhost:8000/v1/chat/completions', request.url
  end

  test 'inherits OpenAI parsing' do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"choices":[{"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}'
    )
    response = @provider.parse_response(raw)
    assert_equal 'Hello!', response.messages.first.content
  end

  test 'works without API key' do
    provider = SolidAgent::Provider::OpenAiCompatible.new(
      base_url: 'http://localhost:8000/v1/chat/completions'
    )
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hi')]
    request = provider.build_request(messages: messages, tools: [], stream: false, model: SolidAgent::Models::OpenAi::GPT_4O)
    assert_not request.headers.key?('Authorization')
  end
end
