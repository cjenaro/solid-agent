require 'test_helper'
require 'solid_agent'

class TypesResponseTest < ActiveSupport::TestCase
  test 'creates response with message' do
    msg = SolidAgent::Types::Message.new(role: 'assistant', content: 'Hi there')
    resp = SolidAgent::Types::Response.new(
      messages: [msg],
      tool_calls: [],
      usage: SolidAgent::Types::Usage.new(input_tokens: 10, output_tokens: 5),
      finish_reason: 'stop'
    )
    assert_equal 1, resp.messages.length
    assert_equal 'stop', resp.finish_reason
  end

  test 'response with tool calls' do
    tool_call = SolidAgent::Types::ToolCall.new(id: 'call_1', name: 'search', arguments: { 'q' => 'test' })
    msg = SolidAgent::Types::Message.new(role: 'assistant', content: nil, tool_calls: [tool_call])
    resp = SolidAgent::Types::Response.new(
      messages: [msg],
      tool_calls: [tool_call],
      usage: SolidAgent::Types::Usage.new(input_tokens: 50, output_tokens: 20),
      finish_reason: 'tool_calls'
    )
    assert_equal 1, resp.tool_calls.length
    assert_equal 'tool_calls', resp.finish_reason
  end

  test 'has_tool_calls predicate' do
    tool_call = SolidAgent::Types::ToolCall.new(id: 'call_1', name: 'search', arguments: {})
    resp_with = SolidAgent::Types::Response.new(messages: [], tool_calls: [tool_call], usage: nil, finish_reason: 'tool_calls')
    assert resp_with.has_tool_calls?

    resp_without = SolidAgent::Types::Response.new(messages: [], tool_calls: [], usage: nil, finish_reason: 'stop')
    assert_not resp_without.has_tool_calls?
  end
end
