require 'test_helper'
require 'solid_agent/http/net_http_adapter'

class NetHttpAdapterTest < ActiveSupport::TestCase
  def setup
    @adapter = SolidAgent::HTTP::NetHttpAdapter.new
  end

  test 'implements call method' do
    assert @adapter.respond_to?(:call)
  end

  test 'makes successful HTTP request' do
    skip 'Network unavailable' unless network_available?

    request = SolidAgent::HTTP::Request.new(
      method: :get,
      url: 'https://httpbin.org/get',
      headers: {},
      body: nil,
      stream: false
    )
    response = @adapter.call(request)
    assert response.success?
    assert_equal 200, response.status
  end

  test 'makes POST request with body' do
    skip 'Network unavailable' unless network_available?

    request = SolidAgent::HTTP::Request.new(
      method: :post,
      url: 'https://httpbin.org/post',
      headers: { 'Content-Type' => 'application/json' },
      body: '{"test": true}',
      stream: false
    )
    response = @adapter.call(request)
    assert response.success?
    parsed = response.json
    assert_equal '{"test": true}', parsed['data']
  end

  test 'handles connection errors' do
    request = SolidAgent::HTTP::Request.new(
      method: :get,
      url: 'https://this-domain-does-not-exist-12345.com',
      headers: {},
      body: nil,
      stream: false
    )
    response = @adapter.call(request)
    assert_not response.success?
    assert response.error
  end

  test 'sets streaming header when stream is true' do
    skip 'Network unavailable' unless network_available?

    request = SolidAgent::HTTP::Request.new(
      method: :post,
      url: 'https://httpbin.org/post',
      headers: { 'Content-Type' => 'application/json' },
      body: '{}',
      stream: true
    )
    response = @adapter.call(request)
    assert response.success?
    parsed = response.json
    assert parsed['headers'].key?('X-Stream')
  end

  private

  def network_available?
    @network_available ||= begin
      uri = URI.parse('https://httpbin.org/get')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 5
      resp = http.get(uri.request_uri)
      resp.is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end
  end
end
