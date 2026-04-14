require 'test_helper'
require 'solid_agent'

class ProviderErrorsTest < ActiveSupport::TestCase
  test 'ProviderError is base error' do
    assert SolidAgent::ProviderError < StandardError
  end

  test 'RateLimitError inherits ProviderError' do
    assert SolidAgent::RateLimitError < SolidAgent::ProviderError
    error = SolidAgent::RateLimitError.new('Rate limited', retry_after: 30)
    assert_equal 30, error.retry_after
  end

  test 'ContextLengthError inherits ProviderError' do
    assert SolidAgent::ContextLengthError < SolidAgent::ProviderError
    error = SolidAgent::ContextLengthError.new('Context too long', tokens_over: 5000)
    assert_equal 5000, error.tokens_over
  end

  test 'ProviderTimeoutError inherits ProviderError' do
    assert SolidAgent::ProviderTimeoutError < SolidAgent::ProviderError
  end
end
