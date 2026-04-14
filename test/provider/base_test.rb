require 'test_helper'
require 'solid_agent'

class ProviderBaseTest < ActiveSupport::TestCase
  class TestProvider
    include SolidAgent::Provider::Base

    def initialize(api_key:, default_model:)
      @api_key = api_key
      @default_model = default_model
    end

    def build_request(messages:, tools:, stream:, model:, options: {})
      SolidAgent::HTTP::Request.new(
        method: :post,
        url: 'https://api.test.com/v1/chat',
        headers: { 'Authorization' => "Bearer #{@api_key}" },
        body: JSON.generate({ messages: messages.map(&:to_hash), model: model.to_s }),
        stream: stream
      )
    end

    def parse_response(raw_response)
      data = raw_response.json
      SolidAgent::Types::Response.new(
        messages: [SolidAgent::Types::Message.new(role: 'assistant', content: data.dig('choices', 0, 'message', 'content'))],
        tool_calls: [],
        usage: SolidAgent::Types::Usage.new(input_tokens: data.dig('usage', 'prompt_tokens') || 0,
                                     output_tokens: data.dig('usage',
                                                             'completion_tokens') || 0),
        finish_reason: data.dig('choices', 0, 'finish_reason')
      )
    end

    def parse_stream_chunk(_chunk)
      SolidAgent::Types::StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil, done: true)
    end

    def parse_tool_call(raw_tool_call)
      SolidAgent::Types::ToolCall.new(id: raw_tool_call['id'], name: raw_tool_call['name'],
                               arguments: raw_tool_call['arguments'])
    end
  end

  test 'provider implements required interface' do
    provider = TestProvider.new(api_key: 'test', default_model: 'test-model')
    assert provider.respond_to?(:build_request)
    assert provider.respond_to?(:parse_response)
    assert provider.respond_to?(:parse_stream_chunk)
    assert provider.respond_to?(:parse_tool_call)
  end

  test 'build_request returns HTTP Request' do
    provider = TestProvider.new(api_key: 'test', default_model: 'test-model')
    request = provider.build_request(
      messages: [SolidAgent::Types::Message.new(role: 'user', content: 'hi')],
      tools: [],
      stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O
    )
    assert_instance_of SolidAgent::HTTP::Request, request
    assert_equal :post, request.method
  end

  test 'parse_response returns Response' do
    provider = TestProvider.new(api_key: 'test', default_model: 'test-model')
    raw = SolidAgent::HTTP::Response.new(
      status: 200,
      headers: {},
      body: '{"choices":[{"message":{"content":"Hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}',
      error: nil
    )
    response = provider.parse_response(raw)
    assert_instance_of SolidAgent::Types::Response, response
    assert_equal 'Hello', response.messages.first.content
  end
end
