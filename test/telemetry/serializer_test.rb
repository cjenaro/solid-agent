require 'test_helper'

class SerializerTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    @trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'ResearchAgent',
                                       trace_type: :agent_run)
  end

  test 'enriches llm span with gen_ai chat attributes' do
    span = @trace.spans.create!(span_type: 'llm', name: 'step_0', status: 'completed',
                                tokens_in: 100, tokens_out: 50)
    attrs = SolidAgent::Telemetry::Serializer.span_attributes(span, provider: :openai, model: 'gpt-4')

    assert_equal 'chat', attrs['gen_ai.operation.name']
    assert_equal 'openai', attrs['gen_ai.provider.name']
    assert_equal 'gpt-4', attrs['gen_ai.request.model']
    assert_equal 100, attrs['gen_ai.usage.input_tokens']
    assert_equal 50, attrs['gen_ai.usage.output_tokens']
  end

  test 'enriches tool span with execute_tool attributes' do
    span = @trace.spans.create!(span_type: 'tool', name: 'web_search', status: 'completed')
    attrs = SolidAgent::Telemetry::Serializer.span_attributes(span,
                                                              tool_name: 'web_search',
                                                              tool_call_id: 'call_abc123',
                                                              tool_type: 'function')

    assert_equal 'execute_tool', attrs['gen_ai.operation.name']
    assert_equal 'web_search', attrs['gen_ai.tool.name']
    assert_equal 'call_abc123', attrs['gen_ai.tool.call.id']
    assert_equal 'function', attrs['gen_ai.tool.type']
  end

  test 'enriches tool_execution span with execute_tool attributes' do
    span = @trace.spans.create!(span_type: 'tool_execution', name: 'agent_tool', status: 'completed')
    attrs = SolidAgent::Telemetry::Serializer.span_attributes(span,
                                                              tool_name: 'agent_tool',
                                                              tool_type: 'agent')

    assert_equal 'execute_tool', attrs['gen_ai.operation.name']
    assert_equal 'agent_tool', attrs['gen_ai.tool.name']
    assert_equal 'agent', attrs['gen_ai.tool.type']
  end

  test 'chunk spans get minimal attributes' do
    span = @trace.spans.create!(span_type: 'chunk', name: 'text', status: 'completed')
    attrs = SolidAgent::Telemetry::Serializer.span_attributes(span)

    assert_equal 'chunk', attrs['gen_ai.operation.name']
  end

  test 'merges with existing metadata' do
    span = @trace.spans.create!(span_type: 'llm', name: 'step_0', status: 'completed',
                                metadata: { 'custom.key' => 'value' })
    attrs = SolidAgent::Telemetry::Serializer.span_attributes(span, provider: :openai, model: 'gpt-4')

    assert_equal 'chat', attrs['gen_ai.operation.name']
    assert_equal 'value', attrs['custom.key']
  end

  test 'trace_resource_attributes returns service metadata' do
    attrs = SolidAgent::Telemetry::Serializer.trace_resource_attributes(@trace)

    assert_equal 'solid_agent', attrs['service.name']
    assert_equal 'ResearchAgent', attrs['solid_agent.agent_class']
  end

  test 'otel_span_name for llm span' do
    attrs = SolidAgent::Telemetry::Serializer.span_attributes(
      SolidAgent::Span.new(span_type: 'llm', name: 'step_0'),
      provider: :openai, model: 'gpt-4'
    )
    assert_equal 'chat gpt-4', attrs['otel.span.name']
  end

  test 'otel_span_name for tool span' do
    attrs = SolidAgent::Telemetry::Serializer.span_attributes(
      SolidAgent::Span.new(span_type: 'tool', name: 'web_search'),
      tool_name: 'web_search'
    )
    assert_equal 'execute_tool web_search', attrs['otel.span.name']
  end

  test 'otel_span_name for chunk span' do
    attrs = SolidAgent::Telemetry::Serializer.span_attributes(
      SolidAgent::Span.new(span_type: 'chunk', name: 'tool-call:web_search')
    )
    assert_equal 'tool-call:web_search', attrs['otel.span.name']
  end
end
