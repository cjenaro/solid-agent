require 'test_helper'

class ConversationsControllerTest < ActiveSupport::TestCase
  setup do
    ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = OFF')
    SolidAgent::MemoryEntry.delete_all
    SolidAgent::Message.delete_all
    SolidAgent::Span.delete_all
    SolidAgent::Trace.delete_all
    SolidAgent::Conversation.delete_all
    ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = ON')
  end

  test 'conversation index returns conversations' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'ResearchAgent')
    SolidAgent::Trace.create!(conversation: conversation, agent_class: 'ResearchAgent', trace_type: :agent_run)

    conversations = SolidAgent::Conversation.order(updated_at: :desc).limit(50)
    assert_equal 1, conversations.size
  end

  test 'conversation show includes traces and messages' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'ResearchAgent')
    trace = SolidAgent::Trace.create!(conversation: conversation, agent_class: 'ResearchAgent', trace_type: :agent_run)
    SolidAgent::Message.create!(conversation: conversation, trace: trace, role: 'user', content: 'Hello')
    SolidAgent::Message.create!(conversation: conversation, trace: trace, role: 'assistant', content: 'Hi!')

    loaded = SolidAgent::Conversation.includes(:traces, :messages).find(conversation.id)
    assert_equal 1, loaded.traces.size
    assert_equal 2, loaded.messages.size
    assert_equal 'user', loaded.messages.first.role
    assert_equal 'assistant', loaded.messages.last.role
  end
end
