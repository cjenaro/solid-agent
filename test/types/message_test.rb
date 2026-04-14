require 'test_helper'
require 'solid_agent'

class TypesMessageTest < ActiveSupport::TestCase
  test 'creates user message' do
    msg = SolidAgent::Types::Message.new(role: 'user', content: 'Hello')
    assert_equal 'user', msg.role
    assert_equal 'Hello', msg.content
  end

  test 'creates assistant message with tool calls' do
    tool_call = SolidAgent::Types::ToolCall.new(id: 'call_1', name: 'search', arguments: { 'query' => 'test' })
    msg = SolidAgent::Types::Message.new(role: 'assistant', content: nil, tool_calls: [tool_call])
    assert_equal 'assistant', msg.role
    assert_equal 1, msg.tool_calls.length
  end

  test 'creates tool result message' do
    msg = SolidAgent::Types::Message.new(role: 'tool', content: 'result text', tool_call_id: 'call_1')
    assert_equal 'tool', msg.role
    assert_equal 'call_1', msg.tool_call_id
  end

  test 'message is immutable' do
    msg = SolidAgent::Types::Message.new(role: 'user', content: 'Hello')
    assert msg.frozen?
  end

  test 'to_hash serializes for provider' do
    msg = SolidAgent::Types::Message.new(role: 'user', content: 'Hello')
    hash = msg.to_hash
    assert_equal 'user', hash[:role]
    assert_equal 'Hello', hash[:content]
  end

  test 'to_hash omits nil fields' do
    msg = SolidAgent::Types::Message.new(role: 'user', content: 'Hello')
    hash = msg.to_hash
    assert_not hash.key?(:tool_calls)
    assert_not hash.key?(:tool_call_id)
  end
end
