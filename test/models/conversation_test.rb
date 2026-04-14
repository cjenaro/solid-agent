require 'test_helper'

class ConversationTest < ActiveSupport::TestCase
  test 'creates a conversation' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'ResearchAgent')
    assert_equal 'ResearchAgent', conversation.agent_class
    assert_equal 'active', conversation.status
  end

  test 'has many traces' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    SolidAgent::Trace.create!(conversation: conversation, agent_class: 'TestAgent', trace_type: :agent_run)
    assert_equal 1, conversation.traces.count
  end

  test 'can be archived' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    conversation.archive!
    assert_equal 'archived', conversation.status
  end

  test 'total token usage across traces' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    SolidAgent::Trace.create!(conversation: conversation, agent_class: 'TestAgent', trace_type: :agent_run,
                              usage: { 'input_tokens' => 100, 'output_tokens' => 50 })
    SolidAgent::Trace.create!(conversation: conversation, agent_class: 'TestAgent', trace_type: :agent_run,
                              usage: { 'input_tokens' => 200, 'output_tokens' => 80 })
    assert_equal 430, conversation.total_tokens
  end
end
