require 'test_helper'
require_relative '../../../app/helpers/solid_agent/application_helper'

class SolidAgent::ApplicationHelperTest < ActionView::TestCase
  include SolidAgent::ApplicationHelper

  setup do
    ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = OFF')
    SolidAgent::Span.delete_all
    SolidAgent::Trace.delete_all
    SolidAgent::Conversation.delete_all
    ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = ON')

    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    @trace = SolidAgent::Trace.create!(
      conversation: @conversation, agent_class: 'ResearchAgent', trace_type: :agent_run,
      otel_trace_id: 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6',
      otel_span_id: '1122334455667788'
    )
  end

  test 'span_label returns otel.span.name when present' do
    span = SolidAgent::Span.new(span_type: 'llm', name: 'step_0',
                                metadata: { 'otel.span.name' => 'chat gpt-4o' })
    assert_equal 'chat gpt-4o', span_label(span)
  end

  test 'span_label falls back to span.name when otel.span.name absent' do
    span = SolidAgent::Span.new(span_type: 'llm', name: 'step_0', metadata: {})
    assert_equal 'step_0', span_label(span)
  end

  test 'span_label falls back to span.name when metadata is nil' do
    span = SolidAgent::Span.new(span_type: 'llm', name: 'step_0', metadata: nil)
    assert_equal 'step_0', span_label(span)
  end

  test 'span_otel_meta returns provider for llm spans' do
    span = SolidAgent::Span.new(span_type: 'llm', name: 'step_0',
                                metadata: { 'gen_ai.provider.name' => 'openai' })
    assert_equal ['openai'], span_otel_meta(span)
  end

  test 'span_otel_meta returns provider for think spans' do
    span = SolidAgent::Span.new(span_type: 'think', name: 'think_1',
                                metadata: { 'gen_ai.provider.name' => 'openai' })
    assert_equal ['openai'], span_otel_meta(span)
  end

  test 'span_otel_meta returns empty for tool spans' do
    span = SolidAgent::Span.new(span_type: 'tool', name: 'web_search',
                                metadata: { 'gen_ai.tool.name' => 'web_search' })
    assert_equal [], span_otel_meta(span)
  end

  test 'span_otel_meta includes finish reasons' do
    span = SolidAgent::Span.new(span_type: 'llm', name: 'step_0',
                                metadata: {
                                  'gen_ai.provider.name' => 'anthropic',
                                  'gen_ai.response.finish_reasons' => ['stop']
                                })
    result = span_otel_meta(span)
    assert_includes result, 'anthropic'
    assert_includes result, 'stop'
  end

  test 'span_otel_meta returns empty for chunk spans' do
    span = SolidAgent::Span.new(span_type: 'chunk', name: 'compaction', metadata: {})
    assert_equal [], span_otel_meta(span)
  end

  test 'span_otel_meta handles nil metadata' do
    span = SolidAgent::Span.new(span_type: 'llm', name: 'step_0', metadata: nil)
    assert_equal [], span_otel_meta(span)
  end

  test 'truncate_id truncates long IDs' do
    result = truncate_id('a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6')
    assert_equal 'a1b2c3d4...c5d6', result
  end

  test 'truncate_id returns short IDs as-is' do
    assert_equal 'abc123', truncate_id('abc123')
  end

  test 'truncate_id returns nil for nil input' do
    assert_nil truncate_id(nil)
  end

  test 'format_meta_value renders strings' do
    assert_equal 'hello', format_meta_value('hello')
  end

  test 'format_meta_value renders integers' do
    assert_equal '500', format_meta_value(500)
  end

  test 'format_meta_value renders arrays' do
    assert_equal 'stop, tool_calls', format_meta_value(%w[stop tool_calls])
  end

  test 'format_meta_value renders hashes as JSON' do
    result = format_meta_value({ 'key' => 'value' })
    assert_match(/"key"/, result)
    assert_match(/"value"/, result)
  end

  test 'format_meta_value truncates long strings' do
    long_text = 'a' * 300
    result = format_meta_value(long_text)
    assert result.length < 300
    assert result.end_with?('...')
  end
end
