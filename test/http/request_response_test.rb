require 'test_helper'
require 'solid_agent'

class HttpRequestResponseTest < ActiveSupport::TestCase
  test 'Request struct has all fields' do
    request = SolidAgent::HTTP::Request.new(
      method: :post,
      url: 'https://api.openai.com/v1/chat/completions',
      headers: { 'Authorization' => 'Bearer test' },
      body: '{"model":"gpt-4o"}',
      stream: false
    )
    assert_equal :post, request.method
    assert_equal 'https://api.openai.com/v1/chat/completions', request.url
    assert_equal({ 'Authorization' => 'Bearer test' }, request.headers)
    assert_equal '{"model":"gpt-4o"}', request.body
    assert_equal false, request.stream
  end

  test 'Response struct has all fields' do
    response = SolidAgent::HTTP::Response.new(
      status: 200,
      headers: { 'content-type' => 'application/json' },
      body: '{"id":"chatcmpl-123"}',
      error: nil
    )
    assert_equal 200, response.status
    assert_equal '{"id":"chatcmpl-123"}', response.body
    assert_nil response.error
  end

  test 'Response success predicate' do
    success = SolidAgent::HTTP::Response.new(status: 200, headers: {}, body: '', error: nil)
    assert success.success?

    client_error = SolidAgent::HTTP::Response.new(status: 400, headers: {}, body: '', error: 'bad request')
    assert_not client_error.success?

    server_error = SolidAgent::HTTP::Response.new(status: 500, headers: {}, body: '', error: 'internal')
    assert_not server_error.success?
  end

  test 'Response parses JSON body' do
    response = SolidAgent::HTTP::Response.new(
      status: 200,
      headers: {},
      body: '{"key": "value"}',
      error: nil
    )
    assert_equal({ 'key' => 'value' }, response.json)
  end
end
