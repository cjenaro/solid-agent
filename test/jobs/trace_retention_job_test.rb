require 'test_helper'

class TraceRetentionJobTest < ActiveSupport::TestCase
  setup do
    ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = OFF')
    SolidAgent::MemoryEntry.delete_all
    SolidAgent::Message.delete_all
    SolidAgent::Span.delete_all
    SolidAgent::Trace.delete_all
    SolidAgent::Conversation.delete_all
    ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = ON')
  end

  test 'deletes old traces' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')

    old_trace = SolidAgent::Trace.create!(
      conversation: conversation, agent_class: 'Test',
      trace_type: :agent_run, status: 'completed',
      created_at: 31.days.ago
    )
    SolidAgent::Span.create!(trace: old_trace, span_type: 'think', name: 'old', created_at: 31.days.ago)

    new_trace = SolidAgent::Trace.create!(
      conversation: conversation, agent_class: 'Test',
      trace_type: :agent_run, status: 'completed'
    )

    SolidAgent::TraceRetentionJob.perform_now(retention: 30.days)

    assert_not SolidAgent::Trace.exists?(old_trace.id)
    assert SolidAgent::Trace.exists?(new_trace.id)
  end

  test 'keeps all traces when retention is :keep_all' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    trace = SolidAgent::Trace.create!(
      conversation: conversation, agent_class: 'Test',
      trace_type: :agent_run, status: 'completed',
      created_at: 100.days.ago
    )

    SolidAgent::TraceRetentionJob.perform_now(retention: :keep_all)

    assert SolidAgent::Trace.exists?(trace.id)
  end
end
