require 'test_helper'
require 'solid_agent'

class TypesToolCallTest < ActiveSupport::TestCase
  test 'creates tool call' do
    tc = SolidAgent::Types::ToolCall.new(id: 'call_1', name: 'web_search', arguments: { 'query' => 'test' }, call_index: 0)
    assert_equal 'call_1', tc.id
    assert_equal 'web_search', tc.name
    assert_equal({ 'query' => 'test' }, tc.arguments)
    assert_equal 0, tc.call_index
  end

  test 'tool call is immutable' do
    tc = SolidAgent::Types::ToolCall.new(id: 'call_1', name: 'search', arguments: {})
    assert tc.frozen?
  end

  test 'tool call defaults call_index to 0' do
    tc = SolidAgent::Types::ToolCall.new(id: 'call_2', name: 'test', arguments: {})
    assert_equal 0, tc.call_index
  end
end
