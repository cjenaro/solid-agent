require 'test_helper'

class SpanContextTest < ActiveSupport::TestCase
  test 'generates 32-char hex trace_id' do
    context = SolidAgent::Telemetry::SpanContext.new
    assert_equal 32, context.trace_id.length
    assert_match(/\A[0-9a-f]{32}\z/, context.trace_id)
  end

  test 'generates 16-char hex span_id' do
    context = SolidAgent::Telemetry::SpanContext.new
    assert_equal 16, context.span_id.length
    assert_match(/\A[0-9a-f]{16}\z/, context.span_id)
  end

  test 'creates child context with same trace_id' do
    parent = SolidAgent::Telemetry::SpanContext.new
    child = parent.create_child
    assert_equal parent.trace_id, child.trace_id
    refute_equal parent.span_id, child.span_id
  end

  test 'generates valid W3C traceparent header' do
    context = SolidAgent::Telemetry::SpanContext.new
    header = context.traceparent_header
    assert_match(/\A00-[0-9a-f]{32}-[0-9a-f]{16}-01\z/, header)
  end

  test 'parses traceparent header' do
    context = SolidAgent::Telemetry::SpanContext.new
    header = context.traceparent_header
    parsed = SolidAgent::Telemetry::SpanContext.from_traceparent(header)
    assert_equal context.trace_id, parsed.trace_id
    assert_equal context.span_id, parsed.span_id
  end

  test 'from_traceparent handles malformed input' do
    assert_nil SolidAgent::Telemetry::SpanContext.from_traceparent('invalid')
    assert_nil SolidAgent::Telemetry::SpanContext.from_traceparent(nil)
  end
end
