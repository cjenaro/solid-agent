require 'test_helper'

class MessageTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
  end

  test 'creates a user message' do
    message = SolidAgent::Message.create!(conversation: @conversation, role: 'user', content: 'Hello agent')
    assert_equal 'user', message.role
    assert_equal 'Hello agent', message.content
  end

  test 'creates an assistant message with tool calls' do
    message = SolidAgent::Message.create!(conversation: @conversation, role: 'assistant', content: nil,
                                          tool_calls: [{ 'id' => 'call_1', 'name' => 'web_search', 'arguments' => { 'query' => 'test' } }])
    assert_equal 1, message.tool_calls.length
    assert_equal 'web_search', message.tool_calls.first['name']
  end

  test 'creates a tool response message' do
    message = SolidAgent::Message.create!(conversation: @conversation, role: 'tool', content: 'Search results here',
                                          tool_call_id: 'call_1')
    assert_equal 'tool', message.role
    assert_equal 'call_1', message.tool_call_id
  end

  test 'roles are validated' do
    message = SolidAgent::Message.new(conversation: @conversation, role: 'invalid', content: 'test')
    assert_not message.valid?
  end

  test 'optional trace association' do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'TestAgent', trace_type: :agent_run)
    message = SolidAgent::Message.create!(conversation: @conversation, trace: trace, role: 'assistant',
                                          content: 'response')
    assert_equal trace, message.trace
  end
end
