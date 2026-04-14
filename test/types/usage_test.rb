require 'test_helper'
require 'solid_agent'

class TypesUsageTest < ActiveSupport::TestCase
  test 'creates usage' do
    usage = SolidAgent::Types::Usage.new(input_tokens: 100, output_tokens: 50)
    assert_equal 100, usage.input_tokens
    assert_equal 50, usage.output_tokens
    assert_equal 150, usage.total_tokens
  end

  test 'computes cost from pricing' do
    usage = SolidAgent::Types::Usage.new(
      input_tokens: 1_000_000,
      output_tokens: 500_000,
      input_price_per_million: 2.50,
      output_price_per_million: 10.00
    )
    assert_in_delta 7.50, usage.cost, 0.01
  end

  test 'cost is zero without pricing' do
    usage = SolidAgent::Types::Usage.new(input_tokens: 1000, output_tokens: 500)
    assert_in_delta 0.0, usage.cost, 0.001
  end

  test 'adds two usages together' do
    a = SolidAgent::Types::Usage.new(input_tokens: 100, output_tokens: 50)
    b = SolidAgent::Types::Usage.new(input_tokens: 200, output_tokens: 75)
    combined = a + b
    assert_equal 300, combined.input_tokens
    assert_equal 125, combined.output_tokens
  end
end
