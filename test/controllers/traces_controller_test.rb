require 'test_helper'

class TracesControllerTest < ActiveSupport::TestCase
  setup do
    ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = OFF')
    SolidAgent::MemoryEntry.delete_all
    SolidAgent::Message.delete_all
    SolidAgent::Span.delete_all
    SolidAgent::Trace.delete_all
    SolidAgent::Conversation.delete_all
    ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = ON')
  end

  test 'trace filtering by agent_class' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    SolidAgent::Trace.create!(conversation: conversation, agent_class: 'AgentA', trace_type: :agent_run)
    SolidAgent::Trace.create!(conversation: conversation, agent_class: 'AgentB', trace_type: :agent_run)

    traces = SolidAgent::Trace.includes(:conversation).where(agent_class: 'AgentA')
    assert_equal 1, traces.count
    assert_equal 'AgentA', traces.first.agent_class
  end

  test 'trace filtering by status' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    SolidAgent::Trace.create!(conversation: conversation, agent_class: 'Test', trace_type: :agent_run,
                              status: 'completed')
    SolidAgent::Trace.create!(conversation: conversation, agent_class: 'Test', trace_type: :agent_run, status: 'failed')

    traces = SolidAgent::Trace.includes(:conversation).where(status: 'completed')
    assert_equal 1, traces.count
  end

  test 'trace show includes spans and child traces' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    trace = SolidAgent::Trace.create!(
      conversation: conversation, agent_class: 'ResearchAgent',
      trace_type: :agent_run, status: 'completed',
      usage: { 'input_tokens' => 100, 'output_tokens' => 50 }
    )
    SolidAgent::Span.create!(
      trace: trace, span_type: 'think', name: 'think_1',
      status: 'completed', tokens_in: 100, tokens_out: 50,
      started_at: 1.minute.ago, completed_at: Time.current
    )

    loaded_trace = SolidAgent::Trace.includes(:spans).find(trace.id)
    assert_equal 1, loaded_trace.spans.size
    assert_equal 'think_1', loaded_trace.spans.first.name
  end

  test 'distinct agent_classes returns unique names' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    SolidAgent::Trace.create!(conversation: conversation, agent_class: 'AgentA', trace_type: :agent_run)
    SolidAgent::Trace.create!(conversation: conversation, agent_class: 'AgentA', trace_type: :agent_run)
    SolidAgent::Trace.create!(conversation: conversation, agent_class: 'AgentB', trace_type: :agent_run)

    agent_classes = SolidAgent::Trace.distinct.pluck(:agent_class)
    assert_equal 2, agent_classes.size
    assert_includes agent_classes, 'AgentA'
    assert_includes agent_classes, 'AgentB'
  end
end
