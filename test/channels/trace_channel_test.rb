require 'test_helper'
require_relative '../../app/channels/solid_agent/trace_channel'

module SolidAgent
  class TraceChannelTest < ActiveSupport::TestCase
    test 'broadcasts trace update without error' do
      conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
      trace = SolidAgent::Trace.create!(
        conversation: conversation,
        agent_class: 'TestAgent',
        trace_type: :agent_run,
        status: 'running',
        started_at: Time.current
      )

      # Should not raise even without ActionCable
      SolidAgent::TraceChannel.broadcast_trace_update(trace)
      assert true
    end

    test 'broadcasts span update without error' do
      conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
      trace = SolidAgent::Trace.create!(
        conversation: conversation,
        agent_class: 'TestAgent',
        trace_type: :agent_run,
        status: 'running',
        started_at: Time.current
      )
      span = SolidAgent::Span.create!(
        trace: trace,
        span_type: 'llm',
        name: 'step_0',
        status: 'completed',
        started_at: Time.current,
        completed_at: Time.current
      )

      SolidAgent::TraceChannel.broadcast_span_update(span)
      assert true
    end

    test 'subscribe returns channel name' do
      assert_equal 'solid_agent:trace', SolidAgent::TraceChannel.subscribe
    end

    test 'subscribe with trace_id returns scoped channel' do
      assert_equal 'solid_agent:trace:42', SolidAgent::TraceChannel.subscribe(42)
    end
  end
end
