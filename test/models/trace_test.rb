require 'test_helper'

class TraceTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
  end

  test 'creates a trace' do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'ResearchAgent', trace_type: :agent_run)
    assert_equal 'pending', trace.status
    assert_equal 'ResearchAgent', trace.agent_class
  end

  test 'has many spans' do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'TestAgent', trace_type: :agent_run)
    assert_equal 0, trace.spans.count
  end

  test 'parent trace relationship' do
    parent = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'Supervisor', trace_type: :agent_run)
    child = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'Worker', trace_type: :delegate,
                                      parent_trace: parent)
    assert_equal parent.id, child.parent_trace_id
    assert_includes parent.child_traces, child
  end

  test 'status transitions' do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'TestAgent', trace_type: :agent_run)
    trace.start!
    assert_equal 'running', trace.status
    trace.complete!
    assert_equal 'completed', trace.status
  end

  test 'can fail' do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'TestAgent', trace_type: :agent_run)
    trace.start!
    trace.fail!('Something went wrong')
    assert_equal 'failed', trace.status
    assert_equal 'Something went wrong', trace.error
  end

  test 'can pause and resume' do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'TestAgent', trace_type: :agent_run)
    trace.start!
    trace.pause!
    assert_equal 'paused', trace.status
    trace.resume!
    assert_equal 'running', trace.status
  end

  test 'tracks duration' do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'TestAgent', trace_type: :agent_run)
    trace.update!(started_at: 10.seconds.ago, completed_at: Time.current)
    assert trace.duration > 0
  end

  test 'token usage from usage JSON' do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'TestAgent', trace_type: :agent_run,
                                      usage: { 'input_tokens' => 500, 'output_tokens' => 250 })
    assert_equal 750, trace.total_tokens
  end
end
