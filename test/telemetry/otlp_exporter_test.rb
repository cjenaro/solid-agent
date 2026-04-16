require 'test_helper'
require 'webrick'

class OTLPExporterTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    @trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: 'ResearchAgent',
      trace_type: :agent_run,
      status: 'completed',
      input: 'Find Q4 trends',
      output: 'US GDP grew 3.1%',
      usage: { 'input_tokens' => 500, 'output_tokens' => 200 },
      metadata: { 'gen_ai.provider.name' => 'openai', 'gen_ai.request.model' => 'gpt-4' }
    )
    @trace.update!(started_at: 5.seconds.ago, completed_at: 1.second.ago)

    @span = @trace.spans.create!(
      span_type: 'llm',
      name: 'step_0',
      status: 'completed',
      started_at: 4.seconds.ago,
      completed_at: 3.seconds.ago,
      tokens_in: 500,
      tokens_out: 200,
      metadata: {
        'gen_ai.operation.name' => 'chat',
        'gen_ai.provider.name' => 'openai',
        'gen_ai.request.model' => 'gpt-4',
        'gen_ai.usage.input_tokens' => 500,
        'gen_ai.usage.output_tokens' => 200
      }
    )
  end

  test 'initializes with endpoint' do
    exporter = SolidAgent::Telemetry::OTLPExporter.new(endpoint: 'http://localhost:4318/v1/traces')
    assert_equal 'http://localhost:4318/v1/traces', exporter.endpoint
  end

  test 'initializes with default endpoint' do
    exporter = SolidAgent::Telemetry::OTLPExporter.new
    assert_equal 'http://localhost:4318/v1/traces', exporter.endpoint
  end

  test 'converts trace to OTLP resource spans' do
    exporter = SolidAgent::Telemetry::OTLPExporter.new
    resource_spans = exporter.build_resource_spans(@trace)

    assert_kind_of Hash, resource_spans
    assert_equal 'solid_agent', resource_spans[:resource][:attributes][0][:key]
    assert_equal 1, resource_spans[:scope_spans].length
    assert_equal 1, resource_spans[:scope_spans][0][:spans].length
  end

  test 'span has correct OTel fields' do
    exporter = SolidAgent::Telemetry::OTLPExporter.new
    resource_spans = exporter.build_resource_spans(@trace)
    span = resource_spans[:scope_spans][0][:spans][0]

    assert_equal @trace.otel_trace_id, span[:trace_id]
    assert_equal @span.otel_span_id, span[:span_id]
    assert_equal @trace.otel_span_id, span[:parent_span_id]
    assert_equal 'chat gpt-4', span[:name]
    assert span[:start_time_unix_nano] > 0
    assert span[:end_time_unix_nano] > 0
  end

  test 'span status maps correctly' do
    exporter = SolidAgent::Telemetry::OTLPExporter.new

    @trace.spans.create!(
      span_type: 'tool', name: 'search', status: 'completed',
      started_at: 1.second.ago, completed_at: Time.current,
      metadata: { 'gen_ai.operation.name' => 'execute_tool', 'gen_ai.tool.name' => 'search' }
    )
    resource_spans = exporter.build_resource_spans(@trace.reload)
    span = resource_spans[:scope_spans][0][:spans].find { |s| s[:name] == 'execute_tool search' }
    assert_equal :STATUS_CODE_OK, span[:status][:code]
  end

  test 'error span has correct status' do
    @trace.spans.create!(
      span_type: 'tool', name: 'failing_tool', status: 'error',
      started_at: 1.second.ago, completed_at: Time.current,
      metadata: { 'gen_ai.operation.name' => 'execute_tool', 'gen_ai.tool.name' => 'failing_tool' }
    )
    exporter = SolidAgent::Telemetry::OTLPExporter.new
    resource_spans = exporter.build_resource_spans(@trace.reload)
    span = resource_spans[:scope_spans][0][:spans].find { |s| s[:name] == 'execute_tool failing_tool' }
    assert_equal :STATUS_CODE_ERROR, span[:status][:code]
  end

  test 'span attributes include gen_ai semantic conventions' do
    exporter = SolidAgent::Telemetry::OTLPExporter.new
    resource_spans = exporter.build_resource_spans(@trace)
    span = resource_spans[:scope_spans][0][:spans][0]

    attrs = span[:attributes].each_with_object({}) { |a, h| h[a[:key]] = a }
    assert_equal 'chat', attrs['gen_ai.operation.name'][:value]
    assert_equal 'openai', attrs['gen_ai.provider.name'][:value]
    assert_equal 'gpt-4', attrs['gen_ai.request.model'][:value]
  end

  test 'span name follows OTel convention' do
    exporter = SolidAgent::Telemetry::OTLPExporter.new

    @trace.spans.create!(
      span_type: 'llm', name: 'step_1', status: 'completed',
      started_at: 1.second.ago, completed_at: Time.current,
      metadata: { 'gen_ai.operation.name' => 'chat', 'gen_ai.request.model' => 'gpt-4' }
    )
    @trace.spans.create!(
      span_type: 'tool', name: 'web_search', status: 'completed',
      started_at: 1.second.ago, completed_at: Time.current,
      metadata: { 'gen_ai.operation.name' => 'execute_tool', 'gen_ai.tool.name' => 'web_search' }
    )

    resource_spans = exporter.build_resource_spans(@trace.reload)
    names = resource_spans[:scope_spans][0][:spans].map { |s| s[:name] }

    assert_includes names, 'chat gpt-4'
    assert_includes names, 'execute_tool web_search'
  end

  test 'builds valid OTLP JSON body' do
    exporter = SolidAgent::Telemetry::OTLPExporter.new
    body = exporter.build_otlp_body(@trace)
    parsed = JSON.parse(body)

    assert parsed.key?('resourceSpans')
    assert_equal 1, parsed['resourceSpans'].length
  end

  test 'sends trace to endpoint' do
    received = nil
    server = WEBrick::HTTPServer.new(Port: 0, Logger: WEBrick::Log.new('/dev/null'), AccessLog: [])
    server.mount_proc '/v1/traces' do |req, res|
      received = req.body
      res.status = 200
      res.body = '{}'
    end
    thread = Thread.new { server.start }
    sleep 0.1
    port = server.config[:Port]

    exporter = SolidAgent::Telemetry::OTLPExporter.new(endpoint: "http://localhost:#{port}/v1/traces")
    exporter.export_trace(@trace)

    server.shutdown
    thread.join

    assert received.present?
    parsed = JSON.parse(received)
    assert parsed.key?('resourceSpans')
  end
end
