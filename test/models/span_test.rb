require 'test_helper'

class SpanTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    @trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'TestAgent', trace_type: :agent_run)
  end

  test 'creates a span' do
    span = SolidAgent::Span.create!(trace: @trace, span_type: :think, name: 'think_1')
    assert_equal 'think', span.span_type
    assert_equal 'think_1', span.name
  end

  test 'parent span relationship' do
    parent = SolidAgent::Span.create!(trace: @trace, span_type: :act, name: 'act_1')
    child = SolidAgent::Span.create!(trace: @trace, span_type: :tool_execution, name: 'web_search', parent_span: parent)
    assert_equal parent.id, child.parent_span_id
    assert_includes parent.child_spans, child
  end

  test 'tracks duration' do
    span = SolidAgent::Span.create!(trace: @trace, span_type: :think, name: 'think_1', started_at: 2.seconds.ago,
                                    completed_at: Time.current)
    assert span.duration > 0
  end

  test 'tracks tokens' do
    span = SolidAgent::Span.create!(trace: @trace, span_type: :think, name: 'think_1', tokens_in: 500, tokens_out: 200)
    assert_equal 700, span.total_tokens
  end

  test 'valid span types' do
    %i[think act observe tool_execution llm_call].each do |span_type|
      span = SolidAgent::Span.create!(trace: @trace, span_type: span_type, name: 'test')
      assert_equal span_type.to_s, span.span_type
    end
  end

  test 'generates otel_span_id on create' do
    span = SolidAgent::Span.create!(trace: @trace, span_type: :think, name: 'think_1')
    assert span.otel_span_id.present?
    assert_equal 16, span.otel_span_id.length
    assert_match(/\A[0-9a-f]{16}\z/, span.otel_span_id)
  end
end
