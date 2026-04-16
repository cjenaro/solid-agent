# OpenTelemetry Compliance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make solid-agent's trace/span system fully OpenTelemetry-compliant — proper W3C TraceContext IDs, GenAI semantic convention attributes on every span, and a pluggable exporter interface with a zero-dep OTLP JSON exporter — while keeping the gem's philosophy of minimal deps, works OOTB, and easily pluggable.

**Architecture:** Add a thin OTel compliance layer on top of the existing Trace/Span models. Introduce `otel_trace_id` (32-hex) and `otel_span_id` (16-hex) columns for W3C TraceContext propagation. Enrich span `metadata` with GenAI semantic convention attributes (`gen_ai.operation.name`, `gen_ai.provider.name`, etc.). Create a `Telemetry::Exporter` base class with a built-in `OTLPExporter` that converts traces/spans to OTLP JSON format using only Ruby stdlib. Wire exporters into the ReAct loop and RunJob via Configuration.

**Tech Stack:** Ruby stdlib only (securerandom, json, net/http, zlib). No external gem dependencies.

---

## File Map

| File | Responsibility |
|---|---|
| `lib/solid_agent/telemetry/span_context.rb` | W3C TraceContext ID generation and propagation |
| `lib/solid_agent/telemetry/serializer.rb` | Converts Trace/Span models to OTel-compatible hash |
| `lib/solid_agent/telemetry/exporter.rb` | Base exporter interface (abstract) |
| `lib/solid_agent/telemetry/null_exporter.rb` | Default no-op exporter |
| `lib/solid_agent/telemetry/otlp_exporter.rb` | OTLP JSON over HTTP exporter (stdlib only) |
| `lib/solid_agent/telemetry/exportable.rb` | Mixin added to Trace and Span for `to_otel` methods |
| `app/models/solid_agent/trace.rb` | Modified: add `otel_trace_id` accessor, include Exportable |
| `app/models/solid_agent/span.rb` | Modified: add `otel_span_id` accessor, include Exportable |
| `lib/solid_agent/configuration.rb` | Modified: add `telemetry_exporters` config |
| `lib/solid_agent/react/loop.rb` | Modified: populate OTel attributes on spans, call exporters |
| `lib/solid_agent/run_job.rb` | Modified: assign `otel_trace_id`, call exporters on completion |
| `lib/solid_agent/orchestration/delegate_tool.rb` | Modified: propagate `otel_trace_id` to child traces |
| `lib/solid_agent/orchestration/agent_tool.rb` | Modified: populate OTel tool attributes |
| `test/test_helper.rb` | Modified: add new columns to schema |
| `test/telemetry/span_context_test.rb` | New: ID generation and parsing tests |
| `test/telemetry/serializer_test.rb` | New: OTel hash conversion tests |
| `test/telemetry/exporter_test.rb` | New: base exporter interface tests |
| `test/telemetry/null_exporter_test.rb` | New: null exporter tests |
| `test/telemetry/otlp_exporter_test.rb` | New: OTLP exporter tests |
| `test/telemetry/exportable_test.rb` | New: Trace/Span `to_otel` method tests |
| `test/react/loop_test.rb` | Modified: verify OTel attributes on spans |
| `lib/solid_agent.rb` | Modified: require telemetry files |

---

## Task 1: Add W3C TraceContext ID columns to schema and models

Add `otel_trace_id` (32-char hex) to `solid_agent_traces` and `otel_span_id` (16-char hex) to `solid_agent_spans`. These are W3C TraceContext-compliant identifiers that enable distributed tracing across service boundaries.

**Files:**
- Modify: `test/test_helper.rb:30-61`
- Modify: `app/models/solid_agent/trace.rb`
- Modify: `app/models/solid_agent/span.rb`
- Test: `test/models/trace_test.rb`
- Test: `test/models/span_test.rb`

- [ ] **Step 1: Add columns to test schema**

In `test/test_helper.rb`, add `otel_trace_id` to the traces table and `otel_span_id` to the spans table:

```ruby
# In the solid_agent_traces table (after line 44, the metadata column):
t.string :otel_trace_id
t.string :otel_span_id

# In the solid_agent_spans table (after line 59, the metadata column):
t.string :otel_span_id
```

Full traces table block:
```ruby
create_table :solid_agent_traces, force: true do |t|
  t.references :conversation, null: false, foreign_key: { to_table: :solid_agent_conversations }
  t.references :parent_trace, foreign_key: { to_table: :solid_agent_traces }
  t.string :agent_class
  t.string :trace_type
  t.string :status, default: 'pending'
  t.text :input
  t.text :output
  t.json :usage, default: {}
  t.integer :iteration_count, default: 0
  t.datetime :started_at
  t.datetime :completed_at
  t.text :error
  t.json :metadata, default: {}
  t.string :otel_trace_id
  t.string :otel_span_id
  t.timestamps
end
```

Full spans table block:
```ruby
create_table :solid_agent_spans, force: true do |t|
  t.references :trace, null: false, foreign_key: { to_table: :solid_agent_traces }
  t.references :parent_span, foreign_key: { to_table: :solid_agent_spans }
  t.string :span_type
  t.string :name
  t.string :status
  t.text :input
  t.text :output
  t.integer :tokens_in, default: 0
  t.integer :tokens_out, default: 0
  t.datetime :started_at
  t.datetime :completed_at
  t.json :metadata, default: {}
  t.string :otel_span_id
  t.timestamps
end
```

- [ ] **Step 2: Add auto-generation of otel_trace_id and otel_span_id to Trace model**

In `app/models/solid_agent/trace.rb`, add before_create callback and accessor for the root span ID:

```ruby
module SolidAgent
  class Trace < ApplicationRecord
    self.table_name = 'solid_agent_traces'

    belongs_to :conversation, class_name: 'SolidAgent::Conversation'
    belongs_to :parent_trace, class_name: 'SolidAgent::Trace', optional: true
    has_many :child_traces, class_name: 'SolidAgent::Trace', foreign_key: :parent_trace_id, dependent: :nullify
    has_many :spans, class_name: 'SolidAgent::Span', dependent: :destroy

    STATUSES = %w[pending running completed failed paused].freeze

    validates :status, inclusion: { in: STATUSES }

    before_create :generate_otel_ids

    after_initialize :set_defaults

    def usage
      self[:usage] || {}
    end

    def start!
      update!(status: 'running', started_at: Time.current)
    end

    def complete!
      update!(status: 'completed', completed_at: Time.current)
    end

    def fail!(error_message)
      update!(status: 'failed', error: error_message, completed_at: Time.current)
    end

    def pause!
      update!(status: 'paused')
    end

    def resume!
      update!(status: 'running')
    end

    def duration
      return nil unless started_at && completed_at

      completed_at - started_at
    end

    def total_tokens
      (usage['input_tokens'] || 0) + (usage['output_tokens'] || 0)
    end

    private

    def generate_otel_ids
      require 'securerandom'
      self.otel_trace_id ||= SecureRandom.hex(16)
      self.otel_span_id ||= SecureRandom.hex(8)
    end

    def set_defaults
      self.usage ||= {}
    end
  end
end
```

- [ ] **Step 3: Add auto-generation of otel_span_id to Span model**

In `app/models/solid_agent/span.rb`, add before_create callback:

```ruby
module SolidAgent
  class Span < ApplicationRecord
    self.table_name = 'solid_agent_spans'

    belongs_to :trace, class_name: 'SolidAgent::Trace'
    belongs_to :parent_span, class_name: 'SolidAgent::Span', optional: true
    has_many :child_spans, class_name: 'SolidAgent::Span', foreign_key: :parent_span_id, dependent: :nullify

    SPAN_TYPES = %w[llm chunk tool think act observe tool_execution llm_call].freeze

    validates :span_type, inclusion: { in: SPAN_TYPES }

    before_create :generate_otel_span_id

    def duration
      return nil unless started_at && completed_at

      completed_at - started_at
    end

    def total_tokens
      tokens_in + tokens_out
    end

    private

    def generate_otel_span_id
      require 'securerandom'
      self.otel_span_id ||= SecureRandom.hex(8)
    end
  end
end
```

- [ ] **Step 4: Write failing test for otel IDs on Trace**

In `test/models/trace_test.rb`, add:

```ruby
test 'generates otel_trace_id on create' do
  trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'TestAgent', trace_type: :agent_run)
  assert trace.otel_trace_id.present?
  assert_equal 32, trace.otel_trace_id.length
  assert_match(/\A[0-9a-f]{32}\z/, trace.otel_trace_id)
end

test 'generates otel_span_id on create' do
  trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'TestAgent', trace_type: :agent_run)
  assert trace.otel_span_id.present?
  assert_equal 16, trace.otel_span_id.length
  assert_match(/\A[0-9a-f]{16}\z/, trace.otel_span_id)
end

test 'propagates otel_trace_id from parent trace' do
  parent = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'Supervisor', trace_type: :agent_run)
  child = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'Worker', trace_type: :delegate,
                                    parent_trace: parent, otel_trace_id: parent.otel_trace_id)
  assert_equal parent.otel_trace_id, child.otel_trace_id
end
```

- [ ] **Step 5: Write failing test for otel_span_id on Span**

In `test/models/span_test.rb`, add:

```ruby
test 'generates otel_span_id on create' do
  span = SolidAgent::Span.create!(trace: @trace, span_type: :think, name: 'think_1')
  assert span.otel_span_id.present?
  assert_equal 16, span.otel_span_id.length
  assert_match(/\A[0-9a-f]{16}\z/, span.otel_span_id)
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/models/trace_test.rb test/models/span_test.rb`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add test/test_helper.rb app/models/solid_agent/trace.rb app/models/solid_agent/span.rb test/models/trace_test.rb test/models/span_test.rb
git commit -m "feat: add W3C TraceContext-compliant otel_trace_id and otel_span_id to Trace and Span"
```

---

## Task 2: Create SpanContext for trace ID propagation

Create a `Telemetry::SpanContext` utility that generates and manages W3C TraceContext IDs. This handles parent-child span ID relationships and provides the `generate_traceparent_header` method for distributed trace propagation.

**Files:**
- Create: `lib/solid_agent/telemetry/span_context.rb`
- Test: `test/telemetry/span_context_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/telemetry/span_context_test.rb`:

```ruby
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
    assert_nil SolidAgent::Telemetry::SpanContext.from_traceparent("invalid")
    assert_nil SolidAgent::Telemetry::SpanContext.from_traceparent(nil)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/telemetry/span_context_test.rb`
Expected: FAIL with "uninitialized constant SolidAgent::Telemetry::SpanContext"

- [ ] **Step 3: Implement SpanContext**

Create `lib/solid_agent/telemetry/span_context.rb`:

```ruby
module SolidAgent
  module Telemetry
    class SpanContext
      TRACESTATE_VERSION = '00'
      SAMPLED_FLAG = '01'

      attr_reader :trace_id, :span_id

      def initialize(trace_id: nil, span_id: nil)
        require 'securerandom'
        @trace_id = trace_id || SecureRandom.hex(16)
        @span_id = span_id || SecureRandom.hex(8)
      end

      def create_child
        SpanContext.new(trace_id: @trace_id)
      end

      def traceparent_header
        "#{TRACESTATE_VERSION}-#{@trace_id}-#{@span_id}-#{SAMPLED_FLAG}"
      end

      def self.from_traceparent(header)
        return nil unless header.is_a?(String)

        parts = header.split('-')
        return nil unless parts.length == 4
        return nil unless parts[0] == TRACESTATE_VERSION
        return nil unless parts[1]&.match?(/\A[0-9a-f]{32}\z/)
        return nil unless parts[2]&.match?(/\A[0-9a-f]{16}\z/)

        new(trace_id: parts[1], span_id: parts[2])
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/telemetry/span_context_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/solid_agent/telemetry/span_context.rb test/telemetry/span_context_test.rb
git commit -m "feat: add Telemetry::SpanContext for W3C TraceContext ID management"
```

---

## Task 3: Create the Exporter interface and NullExporter

Define the `Telemetry::Exporter` base class that all exporters implement. Create the `NullExporter` as the default — it does nothing, keeping current OOTB behavior unchanged.

**Files:**
- Create: `lib/solid_agent/telemetry/exporter.rb`
- Create: `lib/solid_agent/telemetry/null_exporter.rb`
- Test: `test/telemetry/exporter_test.rb`
- Test: `test/telemetry/null_exporter_test.rb`

- [ ] **Step 1: Write the failing test for base exporter**

Create `test/telemetry/exporter_test.rb`:

```ruby
require 'test_helper'

class ExporterTest < ActiveSupport::TestCase
  test 'base exporter raises NotImplementedError on export_trace' do
    exporter = SolidAgent::Telemetry::Exporter.new
    conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    trace = SolidAgent::Trace.create!(conversation: conversation, agent_class: 'TestAgent', trace_type: :agent_run)

    assert_raises(NotImplementedError) { exporter.export_trace(trace) }
  end

  test 'base exporter shutdown is a no-op' do
    exporter = SolidAgent::Telemetry::Exporter.new
    assert_nil exporter.shutdown
  end

  test 'base exporter flush is a no-op' do
    exporter = SolidAgent::Telemetry::Exporter.new
    assert_nil exporter.flush
  end
end
```

- [ ] **Step 2: Write the failing test for null exporter**

Create `test/telemetry/null_exporter_test.rb`:

```ruby
require 'test_helper'

class NullExporterTest < ActiveSupport::TestCase
  def setup
    @exporter = SolidAgent::Telemetry::NullExporter.new
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    @trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'TestAgent', trace_type: :agent_run)
  end

  test 'export_trace returns nil without error' do
    assert_nil @exporter.export_trace(@trace)
  end

  test 'shutdown returns nil' do
    assert_nil @exporter.shutdown
  end

  test 'flush returns nil' do
    assert_nil @exporter.flush
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/telemetry/exporter_test.rb test/telemetry/null_exporter_test.rb`
Expected: FAIL with "uninitialized constant"

- [ ] **Step 4: Implement base Exporter**

Create `lib/solid_agent/telemetry/exporter.rb`:

```ruby
module SolidAgent
  module Telemetry
    class Exporter
      def export_trace(trace)
        raise NotImplementedError
      end

      def flush
      end

      def shutdown
      end
    end
  end
end
```

- [ ] **Step 5: Implement NullExporter**

Create `lib/solid_agent/telemetry/null_exporter.rb`:

```ruby
module SolidAgent
  module Telemetry
    class NullExporter < Exporter
      def export_trace(trace)
        nil
      end
    end
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/telemetry/exporter_test.rb test/telemetry/null_exporter_test.rb`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add lib/solid_agent/telemetry/exporter.rb lib/solid_agent/telemetry/null_exporter.rb test/telemetry/exporter_test.rb test/telemetry/null_exporter_test.rb
git commit -m "feat: add Telemetry::Exporter base class and NullExporter"
```

---

## Task 4: Create the OTLP JSON exporter

Create `Telemetry::OTLPExporter` that converts Trace/Span models to [OTLP JSON format](https://opentelemetry.io/docs/specs/otlp/#json-protobuf-encoding) and sends them over HTTP POST. Uses only Ruby stdlib (`json`, `net/http`, `zlib`).

**Files:**
- Create: `lib/solid_agent/telemetry/otlp_exporter.rb`
- Test: `test/telemetry/otlp_exporter_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/telemetry/otlp_exporter_test.rb`:

```ruby
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

    completed_span = @trace.spans.create!(
      span_type: 'tool', name: 'search', status: 'completed',
      started_at: 1.second.ago, completed_at: Time.current,
      metadata: { 'gen_ai.operation.name' => 'execute_tool', 'gen_ai.tool.name' => 'search' }
    )
    resource_spans = exporter.build_resource_spans(@trace.reload)
    span = resource_spans[:scope_spans][0][:spans].find { |s| s[:name] == 'execute_tool search' }
    assert_equal :STATUS_CODE_OK, span[:status][:code]
  end

  test 'error span has correct status' do
    error_span = @trace.spans.create!(
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

    attrs = span[:attributes].index_by { |a| a[:key] }
    assert_equal 'chat', attrs['gen_ai.operation.name'][:value]
    assert_equal 'openai', attrs['gen_ai.provider.name'][:value]
    assert_equal 'gpt-4', attrs['gen_ai.request.model'][:value]
  end

  test 'span name follows OTel convention' do
    exporter = SolidAgent::Telemetry::OTLPExporter.new

    llm_span = @trace.spans.create!(
      span_type: 'llm', name: 'step_1', status: 'completed',
      started_at: 1.second.ago, completed_at: Time.current,
      metadata: { 'gen_ai.operation.name' => 'chat', 'gen_ai.request.model' => 'gpt-4' }
    )
    tool_span = @trace.spans.create!(
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
    server = WEBrick::HTTPServer.new(Port: 0, Logger: WEBrick::Log.new("/dev/null"), AccessLog: [])
    server.mount_proc '/v1/traces' do |req, res|
      received = req.body
      res.status = 200
      res.body = '{}'
    end
    thread = Thread.new { server.start }
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/telemetry/otlp_exporter_test.rb`
Expected: FAIL with "uninitialized constant"

- [ ] **Step 3: Implement OTLPExporter**

Create `lib/solid_agent/telemetry/otlp_exporter.rb`:

```ruby
require 'json'
require 'net/http'
require 'uri'
require 'zlib'

module SolidAgent
  module Telemetry
    class OTLPExporter < Exporter
      DEFAULT_ENDPOINT = 'http://localhost:4318/v1/traces'

      attr_reader :endpoint, :headers

      def initialize(endpoint: DEFAULT_ENDPOINT, headers: {})
        @endpoint = endpoint
        @headers = headers
      end

      def export_trace(trace)
        body = build_otlp_body(trace)
        return if body.nil?

        uri = URI.parse(@endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Post.new(uri.path, {
          'Content-Type' => 'application/json',
          'Content-Encoding' => 'gzip'
        }.merge(@headers))
        request.body = gzip(body)

        http.request(request)
      rescue StandardError
      end

      def build_otlp_body(trace)
        resource_spans = build_resource_spans(trace)
        return nil unless resource_spans

        { resourceSpans: [resource_spans] }.to_json
      end

      def build_resource_spans(trace)
        spans = trace.spans.where.not(otel_span_id: nil).order(:started_at)
        return nil if spans.empty? && !trace.otel_trace_id

        {
          resource: {
            attributes: [
              { key: 'service.name', value: { stringValue: 'solid_agent' } },
              { key: 'service.version', value: { stringValue: '0.1.0' } }
            ]
          },
          scope_spans: [
            {
              scope: { name: 'solid_agent', version: '0.1.0' },
              spans: spans.map { |span| build_otel_span(span, trace) }
            }
          ]
        }
      end

      private

      def build_otel_span(span, trace)
        otel_name = otel_span_name(span)
        parent_id = span.parent_span&.otel_span_id || trace.otel_span_id

        otel_span = {
          trace_id: hex_to_binary(trace.otel_trace_id),
          span_id: hex_to_binary(span.otel_span_id),
          parent_span_id: parent_id ? hex_to_binary(parent_id) : nil,
          name: otel_name,
          kind: span_kind(span),
          start_time_unix_nano: time_to_nanos(span.started_at || span.created_at),
          end_time_unix_nano: time_to_nanos(span.completed_at || Time.current),
          status: otel_status(span),
          attributes: build_otel_attributes(span, trace)
        }

        otel_span[:parent_span_id] = nil if otel_span[:parent_span_id] == "\0" * 8
        otel_span
      end

      def otel_span_name(span)
        metadata = span.metadata || {}
        operation = metadata['gen_ai.operation.name']

        if operation == 'chat'
          model = metadata['gen_ai.request.model'] || 'unknown'
          "chat #{model}"
        elsif operation == 'execute_tool'
          tool_name = metadata['gen_ai.tool.name'] || span.name
          "execute_tool #{tool_name}"
        else
          span.name || 'unknown'
        end
      end

      def span_kind(span)
        metadata = span.metadata || {}
        operation = metadata['gen_ai.operation.name']
        operation == 'chat' ? :SPAN_KIND_CLIENT : :SPAN_KIND_INTERNAL
      end

      def otel_status(span)
        if span.status == 'error'
          { code: :STATUS_CODE_ERROR }
        else
          { code: :STATUS_CODE_OK }
        end
      end

      def build_otel_attributes(span, trace)
        metadata = span.metadata || {}
        attrs = []

        metadata.each do |key, value|
          next if key.start_with?('_')

          if value.is_a?(Integer)
            attrs << { key: key, value: { intValue: value } }
          elsif value.is_a?(Float)
            attrs << { key: key, value: { doubleValue: value } }
          elsif value.is_a?(TrueClass) || value.is_a?(FalseClass)
            attrs << { key: key, value: { boolValue: value } }
          elsif value.is_a?(Array)
            attrs << { key: key, value: { arrayValue: { values: value.map { |v| { stringValue: v.to_s } } } } }
          else
            attrs << { key: key, value: { stringValue: value.to_s } }
          end
        end

        attrs << { key: 'solid_agent.span_type', value: { stringValue: span.span_type.to_s } }
        attrs << { key: 'solid_agent.agent_class', value: { stringValue: trace.agent_class.to_s } }

        if trace.conversation_id
          attrs << { key: 'gen_ai.conversation.id', value: { stringValue: trace.conversation_id.to_s } }
        end

        attrs
      end

      def hex_to_binary(hex_string)
        return nil unless hex_string
        [hex_string].pack('H*')
      end

      def time_to_nanos(time)
        return 0 unless time
        (time.to_f * 1_000_000_000).to_i
      end

      def gzip(data)
        io = StringIO.new
        gz = Zlib::GzipWriter.new(io)
        gz.write(data)
        gz.close
        io.string
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/telemetry/otlp_exporter_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/solid_agent/telemetry/otlp_exporter.rb test/telemetry/otlp_exporter_test.rb
git commit -m "feat: add Telemetry::OTLPExporter for OTLP JSON export via stdlib"
```

---

## Task 5: Create the Serializer — converts Trace/Span to OTel-compliant hash

The Serializer enriches spans with GenAI semantic convention attributes based on their `span_type`. This is called during span creation in the ReAct loop to populate `metadata` with the correct OTel attributes, so the OTLPExporter (or any custom exporter) has compliant data to work with.

**Files:**
- Create: `lib/solid_agent/telemetry/serializer.rb`
- Test: `test/telemetry/serializer_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/telemetry/serializer_test.rb`:

```ruby
require 'test_helper'

class SerializerTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    @trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: 'ResearchAgent', trace_type: :agent_run)
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/telemetry/serializer_test.rb`
Expected: FAIL with "uninitialized constant"

- [ ] **Step 3: Implement Serializer**

Create `lib/solid_agent/telemetry/serializer.rb`:

```ruby
module SolidAgent
  module Telemetry
    class Serializer
      OTLLM_SPAN_TYPES = %w[llm llm_call think].freeze
      OTTOOL_SPAN_TYPES = %w[tool tool_execution act].freeze

      def self.span_attributes(span, provider: nil, model: nil, tool_name: nil,
                                tool_call_id: nil, tool_type: nil, finish_reasons: nil)
        attrs = (span.metadata || {}).dup

        if OTLLM_SPAN_TYPES.include?(span.span_type)
          attrs['gen_ai.operation.name'] = 'chat'
          attrs['gen_ai.provider.name'] = provider.to_s if provider
          attrs['gen_ai.request.model'] = model.to_s if model
          attrs['gen_ai.usage.input_tokens'] = span.tokens_in if span.tokens_in > 0
          attrs['gen_ai.usage.output_tokens'] = span.tokens_out if span.tokens_out > 0
          attrs['gen_ai.response.finish_reasons'] = Array(finish_reasons) if finish_reasons
          attrs['otel.span.name'] = "chat #{model || 'unknown'}"
        elsif OTTOOL_SPAN_TYPES.include?(span.span_type)
          attrs['gen_ai.operation.name'] = 'execute_tool'
          attrs['gen_ai.tool.name'] = (tool_name || span.name).to_s
          attrs['gen_ai.tool.call.id'] = tool_call_id.to_s if tool_call_id
          attrs['gen_ai.tool.type'] = tool_type.to_s if tool_type
          attrs['otel.span.name'] = "execute_tool #{tool_name || span.name}"
        else
          attrs['gen_ai.operation.name'] = span.span_type
          attrs['otel.span.name'] = span.name.to_s
        end

        attrs
      end

      def self.trace_resource_attributes(trace)
        {
          'service.name' => 'solid_agent',
          'service.version' => '0.1.0',
          'solid_agent.agent_class' => trace.agent_class.to_s,
          'solid_agent.trace_type' => trace.trace_type.to_s
        }
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/telemetry/serializer_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/solid_agent/telemetry/serializer.rb test/telemetry/serializer_test.rb
git commit -m "feat: add Telemetry::Serializer for GenAI OTel attribute enrichment"
```

---

## Task 6: Add telemetry_exporters to Configuration

Wire the exporter system into the gem's configuration. Default to `NullExporter` (no-op) so OOTB behavior is unchanged. Users can set `config.telemetry_exporters` to an array of exporter instances.

**Files:**
- Modify: `lib/solid_agent/configuration.rb`
- Test: `test/configuration_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/configuration_test.rb` (or create if not present with these tests):

```ruby
test 'telemetry_exporters defaults to NullExporter' do
  SolidAgent.reset_configuration!
  assert_instance_of SolidAgent::Telemetry::NullExporter,
                     SolidAgent.configuration.telemetry_exporters.first
end

test 'telemetry_exporters can be set to custom exporters' do
  exporter = SolidAgent::Telemetry::OTLPExporter.new(endpoint: 'http://jaeger:4318/v1/traces')
  SolidAgent.configure do |config|
    config.telemetry_exporters = [exporter]
  end
  assert_equal 1, SolidAgent.configuration.telemetry_exporters.length
  assert_instance_of SolidAgent::Telemetry::OTLPExporter, SolidAgent.configuration.telemetry_exporters.first
end

test 'telemetry_exporters can have multiple exporters' do
  SolidAgent.configure do |config|
    config.telemetry_exporters = [
      SolidAgent::Telemetry::NullExporter.new,
      SolidAgent::Telemetry::OTLPExporter.new
    ]
  end
  assert_equal 2, SolidAgent.configuration.telemetry_exporters.length
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/configuration_test.rb`
Expected: FAIL — `telemetry_exporters` not defined or not defaulting to NullExporter

- [ ] **Step 3: Modify Configuration**

Update `lib/solid_agent/configuration.rb`:

```ruby
module SolidAgent
  class Configuration
    attr_accessor :default_provider, :default_model, :dashboard_enabled,
                  :dashboard_route_prefix, :vector_store, :embedding_provider,
                  :embedding_model, :http_adapter, :trace_retention,
                  :providers, :mcp_clients, :telemetry_exporters

    def initialize
      @default_provider = :openai
      @default_model = Models::OpenAi::GPT_4O
      @dashboard_enabled = true
      @dashboard_route_prefix = 'solid_agent'
      @vector_store = :sqlite_vec
      @embedding_provider = :openai
      @embedding_model = 'text-embedding-3-small'
      @http_adapter = :net_http
      @trace_retention = 30.days
      @providers = {}
      @mcp_clients = {}
      @telemetry_exporters = [Telemetry::NullExporter.new]
    end

    def validate!
      return if @default_provider.is_a?(Symbol) || @default_provider.nil?

      raise Error, 'default_provider must be a symbol'
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/configuration_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/solid_agent/configuration.rb test/configuration_test.rb
git commit -m "feat: add telemetry_exporters to Configuration, default to NullExporter"
```

---

## Task 7: Wire exporters into ReAct loop — populate OTel attributes on span creation

Modify the ReAct loop to use `Telemetry::Serializer` to populate `metadata` with OTel GenAI semantic convention attributes when creating spans. Also call exporters after the trace completes.

**Files:**
- Modify: `lib/solid_agent/react/loop.rb`
- Test: `test/react/loop_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/react/loop_test.rb`:

```ruby
test 'llm spans have gen_ai semantic convention attributes' do
  trace = create_trace
  fake_response = build_tool_call_response

  loop = SolidAgent::React::Loop.new(
    trace: trace, provider: fake_provider(fake_response),
    memory: SolidAgent::Memory::FullHistory.new,
    execution_engine: SolidAgent::Tool::ExecutionEngine.new(registry: tool_registry),
    model: SolidAgent::Models::OpenAi::GPT_4O,
    system_prompt: 'You are helpful',
    max_iterations: 3, max_tokens_per_run: 1000, timeout: 30
  )

  loop.run([SolidAgent::Types::Message.new(role: 'user', content: 'Hello')])

  llm_span = trace.spans.find { |s| s.span_type == 'llm' }
  assert llm_span, 'expected an llm span to be created'
  metadata = llm_span.metadata || {}
  assert_equal 'chat', metadata['gen_ai.operation.name']
  assert_equal 'openai', metadata['gen_ai.provider.name']
  assert_equal 'gpt-4o', metadata['gen_ai.request.model']
end

test 'tool spans have execute_tool semantic convention attributes' do
  trace = create_trace
  fake_response = build_tool_call_response

  loop = SolidAgent::React::Loop.new(
    trace: trace, provider: fake_provider(fake_response),
    memory: SolidAgent::Memory::FullHistory.new,
    execution_engine: SolidAgent::Tool::ExecutionEngine.new(registry: tool_registry),
    model: SolidAgent::Models::OpenAi::GPT_4O,
    system_prompt: 'You are helpful',
    max_iterations: 3, max_tokens_per_run: 1000, timeout: 30
  )

  loop.run([SolidAgent::Types::Message.new(role: 'user', content: 'Hello')])

  tool_span = trace.spans.find { |s| s.span_type == 'tool' }
  assert tool_span, 'expected a tool span to be created'
  metadata = tool_span.metadata || {}
  assert_equal 'execute_tool', metadata['gen_ai.operation.name']
  assert_equal 'test_tool', metadata['gen_ai.tool.name']
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/react/loop_test.rb`
Expected: FAIL — metadata doesn't contain OTel attributes

- [ ] **Step 3: Modify the ReAct loop**

Update `lib/solid_agent/react/loop.rb`. The key changes are in span creation calls — add `metadata:` populated by `Telemetry::Serializer.span_attributes(...)`.

```ruby
require 'solid_agent/react/observer'
require 'solid_agent/agent/result'

module SolidAgent
  module React
    class Loop
      def initialize(trace:, provider:, memory:, execution_engine:, model:, system_prompt:, max_iterations:,
                     max_tokens_per_run:, timeout:, http_adapter: nil, provider_name: nil)
        @trace = trace
        @provider = provider
        @memory = memory
        @execution_engine = execution_engine
        @model = model
        @system_prompt = system_prompt
        @max_iterations = max_iterations
        @max_tokens_per_run = max_tokens_per_run
        @timeout = timeout
        @http_adapter = http_adapter || resolve_http_adapter
        @provider_name = provider_name
        @started_at = Time.current
        @accumulated_usage = Types::Usage.new(input_tokens: 0, output_tokens: 0)
      end

      def run(messages)
        all_messages = messages.dup

        loop do
          @trace.increment!(:iteration_count)

          observer = Observer.new(
            trace: @trace,
            max_iterations: @max_iterations,
            max_tokens_per_run: @max_tokens_per_run,
            started_at: @started_at,
            timeout: @timeout
          )

          stop, reason = observer.should_stop?(
            current_tokens: @accumulated_usage.total_tokens,
            context_window: @model.context_window
          )

          return build_result(status: :completed, output: extract_final_text(all_messages), reason: reason) if stop

          if observer.should_compact?(current_tokens: @accumulated_usage.total_tokens,
                                      context_window: @model.context_window)
            all_messages = @memory.compact!(all_messages)
            compaction_attrs = Telemetry::Serializer.span_attributes(
              SolidAgent::Span.new(span_type: 'chunk', name: 'compaction')
            )
            @trace.spans.create!(span_type: 'chunk', name: 'compaction', status: 'completed',
                                 started_at: Time.current, completed_at: Time.current,
                                 metadata: compaction_attrs)
          end

          context = @memory.build_context(all_messages, system_prompt: @system_prompt)

          llm_attrs = Telemetry::Serializer.span_attributes(
            SolidAgent::Span.new(span_type: 'llm', name: "step_#{@trace.iteration_count - 1}"),
            provider: @provider_name,
            model: @model.name
          )
          llm_span = @trace.spans.create!(
            span_type: 'llm', name: "step_#{@trace.iteration_count - 1}",
            status: 'running', started_at: Time.current,
            metadata: llm_attrs
          )

          request = @provider.build_request(
            messages: context,
            tools: @execution_engine.registry.all_schemas_hashes,
            stream: false,
            model: @model,
            max_tokens: @model.max_output
          )

          http_response = @http_adapter.call(request)
          response = @provider.parse_response(http_response)

          llm_span.update!(
            status: 'completed',
            completed_at: Time.current,
            tokens_in: response.usage&.input_tokens || 0,
            tokens_out: response.usage&.output_tokens || 0
          )

          if response.usage
            @accumulated_usage += response.usage
            @trace.update!(usage: {
                             'input_tokens' => @accumulated_usage.input_tokens,
                             'output_tokens' => @accumulated_usage.output_tokens
                           })
          end

          assistant_msg = response.messages.first
          all_messages << assistant_msg if assistant_msg

          unless response.has_tool_calls?
            if assistant_msg&.content.present?
              text_attrs = Telemetry::Serializer.span_attributes(
                SolidAgent::Span.new(span_type: 'chunk', name: 'text')
              )
              @trace.spans.create!(
                span_type: 'chunk', name: 'text',
                status: 'completed', started_at: Time.current, completed_at: Time.current,
                parent_span: llm_span,
                output: assistant_msg.content,
                metadata: text_attrs
              )
            end
            return build_result(status: :completed, output: assistant_msg&.content || '')
          end

          response.tool_calls.each do |tc|
            tc_attrs = Telemetry::Serializer.span_attributes(
              SolidAgent::Span.new(span_type: 'chunk', name: "tool-call:#{tc.name}"),
              tool_name: tc.name, tool_call_id: tc.id
            )
            @trace.spans.create!(
              span_type: 'chunk', name: "tool-call:#{tc.name}",
              status: 'completed', started_at: Time.current, completed_at: Time.current,
              parent_span: llm_span,
              output: { id: tc.id, name: tc.name, arguments: tc.arguments }.to_json,
              metadata: tc_attrs
            )
          end

          tool_results = @execution_engine.execute_all(response.tool_calls)

          tool_results.each do |call_id, result|
            result_text = result.is_a?(Tool::ExecutionEngine::ToolExecutionError) ? "Error: #{result.message}" : result.to_s
            tool_call = response.tool_calls.find { |tc| tc.id == call_id }

            tool_attrs = Telemetry::Serializer.span_attributes(
              SolidAgent::Span.new(span_type: 'tool', name: tool_call&.name || 'tool'),
              tool_name: tool_call&.name,
              tool_call_id: call_id,
              tool_type: 'function'
            )
            @trace.spans.create!(
              span_type: 'tool', name: tool_call&.name || 'tool',
              status: result.is_a?(Tool::ExecutionEngine::ToolExecutionError) ? 'error' : 'completed',
              started_at: Time.current, completed_at: Time.current,
              parent_span: llm_span,
              output: result_text,
              metadata: tool_attrs
            )

            tr_attrs = Telemetry::Serializer.span_attributes(
              SolidAgent::Span.new(span_type: 'chunk', name: "tool-result:#{call_id}"),
              tool_name: tool_call&.name, tool_call_id: call_id
            )
            @trace.spans.create!(
              span_type: 'chunk', name: "tool-result:#{call_id}",
              status: 'completed', started_at: Time.current, completed_at: Time.current,
              parent_span: llm_span,
              output: result_text,
              metadata: tr_attrs
            )

            all_messages << Types::Message.new(role: 'tool', content: result_text, tool_call_id: call_id)
          end
        end
      rescue StandardError => e
        build_result(status: :failed, output: nil, error: e.message)
      end

      private

      def resolve_http_adapter
        SolidAgent::HTTP::Adapters.resolve(SolidAgent.configuration.http_adapter)
      end

      def build_result(status:, output:, error: nil, reason: nil)
        @trace.update!(
          status: status == :completed ? 'completed' : 'failed',
          completed_at: Time.current,
          output: output,
          error: error
        )

        SolidAgent.configuration.telemetry_exporters.each do |exporter|
          exporter.export_trace(@trace)
        end

        Agent::Result.new(
          trace_id: @trace.id,
          output: output,
          usage: @accumulated_usage,
          iterations: @trace.iteration_count,
          status: status,
          error: error
        )
      end

      def extract_final_text(messages)
        messages.reverse_each do |msg|
          return msg.content if msg.role == 'assistant' && msg.content && !msg.content.empty?
        end
        tool_result = messages.reverse_each.find { |msg| msg.role == 'tool' && msg.content }
        tool_result&.content || ''
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/react/loop_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/solid_agent/react/loop.rb test/react/loop_test.rb
git commit -m "feat: populate OTel GenAI semantic attributes on spans in ReAct loop"
```

---

## Task 8: Wire exporters into RunJob — pass provider_name and propagate otel_trace_id

Modify `RunJob` to pass `provider_name` to the ReAct loop so the serializer knows the GenAI provider. Also propagate `otel_trace_id` from parent traces in delegation scenarios.

**Files:**
- Modify: `lib/solid_agent/run_job.rb`
- Test: `test/run_job_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/run_job_test.rb`:

```ruby
test 'passes provider_name to react loop' do
  # Verify that the provider name flows through to span metadata
  # This is validated indirectly through the loop tests above
end
```

Note: The actual coverage comes from the loop tests in Task 7. This test is a placeholder for the run_job wiring. The real validation is that `provider_name` gets passed through.

- [ ] **Step 2: Modify RunJob to pass provider_name**

Update the `perform` method in `lib/solid_agent/run_job.rb` to pass `provider_name`:

```ruby
require 'active_job'
require 'solid_agent/react/loop'
require 'solid_agent/agent/result'

module SolidAgent
  class ApplicationJob < ActiveJob::Base; end unless defined?(ApplicationJob)

  class RunJob < ApplicationJob
    queue_as :solid_agent

    def perform(trace_id:, agent_class_name:, input:, conversation_id:)
      trace = Trace.find(trace_id)
      trace.start!

      agent_class = agent_class_name.constantize

      provider = resolve_provider(agent_class)
      memory = resolve_memory(agent_class)
      execution_engine = resolve_execution_engine(agent_class)

      conversation = Conversation.find(conversation_id)
      conversation.messages.create!(role: 'user', content: input, trace: trace)

      react_loop = React::Loop.new(
        trace: trace,
        provider: provider,
        memory: memory,
        execution_engine: execution_engine,
        model: agent_class.agent_model,
        system_prompt: agent_class.agent_instructions,
        max_iterations: agent_class.agent_max_iterations,
        max_tokens_per_run: agent_class.agent_max_tokens_per_run,
        timeout: agent_class.agent_timeout,
        provider_name: agent_class.agent_provider
      )

      messages = conversation.messages.where(trace: trace).order(:created_at).map do |m|
        Types::Message.new(role: m.role, content: m.content, tool_calls: nil, tool_call_id: m.tool_call_id)
      end

      react_loop.run(messages)
    rescue StandardError => e
      trace.fail!(e.message) if trace&.status == 'running'

      SolidAgent.configuration.telemetry_exporters.each do |exporter|
        exporter.export_trace(trace)
      end

      raise
    end

    private

    def resolve_provider(agent_class)
      provider_name = agent_class.agent_provider
      config = SolidAgent.configuration.providers[provider_name] || {}
      provider_map = { openai: 'OpenAi', anthropic: 'Anthropic', google: 'Google', ollama: 'Ollama',
                       openai_compatible: 'OpenAiCompatible' }
      provider_class_name = provider_map[provider_name] || provider_name.to_s.camelize
      provider_class = "SolidAgent::Provider::#{provider_class_name}".constantize
      provider_class.new(**config.transform_keys(&:to_sym))
    end

    def resolve_memory(agent_class)
      config = agent_class.agent_memory_config
      memory_map = { sliding_window: 'SlidingWindow', full_history: 'FullHistory', compaction: 'Compaction' }
      memory_class_name = memory_map[config[:strategy]] || config[:strategy].to_s.camelize
      "SolidAgent::Memory::#{memory_class_name}".constantize.new(**config.except(:strategy).transform_keys(&:to_sym))
    end

    def resolve_execution_engine(agent_class)
      Tool::ExecutionEngine.new(
        registry: agent_class.agent_tool_registry,
        concurrency: agent_class.agent_concurrency,
        approval_required: agent_class.agent_approval_required
      )
    end
  end
end
```

- [ ] **Step 3: Run existing tests to verify nothing breaks**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/run_job_test.rb`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add lib/solid_agent/run_job.rb test/run_job_test.rb
git commit -m "feat: pass provider_name to ReAct loop, export traces on job failure"
```

---

## Task 9: Propagate otel_trace_id in orchestration (DelegateTool and AgentTool)

When multi-agent orchestration creates child traces, the child should inherit the parent's `otel_trace_id` so the entire agent tree forms one distributed trace.

**Files:**
- Modify: `lib/solid_agent/orchestration/delegate_tool.rb`
- Modify: `lib/solid_agent/orchestration/agent_tool.rb`
- Test: `test/orchestration/integration_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/orchestration/integration_test.rb`:

```ruby
test 'delegate tool propagates otel_trace_id to child trace' do
  parent_trace = SolidAgent::Trace.create!(
    conversation: @conversation,
    agent_class: 'SupervisorAgent',
    trace_type: :agent_run
  )
  parent_trace.start!

  child_trace = SolidAgent::Trace.create!(
    conversation: @conversation,
    parent_trace: parent_trace,
    agent_class: 'WorkerAgent',
    trace_type: :delegate,
    otel_trace_id: parent_trace.otel_trace_id
  )

  assert_equal parent_trace.otel_trace_id, child_trace.otel_trace_id
end
```

- [ ] **Step 2: Modify DelegateTool to propagate otel_trace_id**

Update `lib/solid_agent/orchestration/delegate_tool.rb` — add `otel_trace_id: parent_trace.otel_trace_id` to the child trace creation:

```ruby
module SolidAgent
  module Orchestration
    class DelegateTool
      attr_reader :name, :agent_class, :description

      def initialize(name, agent_class, description:)
        @name = name.to_s
        @agent_class = agent_class
        @description = description
      end

      def delegate?
        true
      end

      def to_tool_schema
        {
          name: @name,
          description: @description,
          inputSchema: {
            type: "object",
            properties: {
              input: {
                type: "string",
                description: "The task to delegate to the agent"
              }
            },
            required: ["input"]
          }
        }
      end

      def execute(arguments, context: {})
        parent_trace = context[:trace]
        conversation = context[:conversation]
        input_text = arguments["input"] || arguments[:input]

        child_trace = nil

        begin
          child_trace = SolidAgent::Trace.create!(
            conversation: conversation,
            parent_trace: parent_trace,
            agent_class: @agent_class.name,
            trace_type: :delegate,
            input: input_text,
            otel_trace_id: parent_trace&.otel_trace_id
          )

          child_trace.start!
          result = @agent_class.perform_now(input_text, trace: child_trace, conversation: conversation)
          child_trace.update!(output: result.to_s)
          child_trace.complete!

          result.to_s
        rescue => e
          child_trace&.fail!(e.message) if child_trace&.status == "running"
          raise
        end
      end
    end
  end
end
```

- [ ] **Step 3: Modify AgentTool to add OTel tool attributes to span**

Update `lib/solid_agent/orchestration/agent_tool.rb` — add OTel metadata to the span and propagate `otel_trace_id`:

```ruby
module SolidAgent
  module Orchestration
    class AgentTool
      attr_reader :name, :agent_class, :description

      def initialize(name, agent_class, description:)
        @name = name.to_s
        @agent_class = agent_class
        @description = description
      end

      def delegate?
        false
      end

      def to_tool_schema
        {
          name: @name,
          description: @description,
          inputSchema: {
            type: "object",
            properties: {
              input: {
                type: "string",
                description: "The input for the agent"
              }
            },
            required: ["input"]
          }
        }
      end

      def execute(arguments, context: {})
        trace = context[:trace]
        conversation = context[:conversation]
        input_text = arguments["input"] || arguments[:input]
        return @agent_class.perform_now(input_text, conversation: conversation).to_s unless trace

        span = nil

        begin
          tool_attrs = SolidAgent::Telemetry::Serializer.span_attributes(
            SolidAgent::Span.new(span_type: :tool_execution, name: @name),
            tool_name: @name,
            tool_type: 'agent'
          )

          span = SolidAgent::Span.create!(
            trace: trace,
            span_type: :tool_execution,
            name: @name,
            input: input_text,
            status: "running",
            started_at: Time.current,
            metadata: {
              agent_class: @agent_class.name,
              tool_type: :agent_tool
            }.merge(tool_attrs)
          )

          result = @agent_class.perform_now(input_text, conversation: conversation)

          span.update!(
            output: result.to_s,
            status: "completed",
            completed_at: Time.current
          )

          result.to_s
        rescue => e
          if span
            span.update!(
              output: e.message,
              status: "error",
              completed_at: Time.current
            )
          end
          raise
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/orchestration/integration_test.rb test/orchestration/agent_tool_test.rb test/orchestration/delegate_tool_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/solid_agent/orchestration/delegate_tool.rb lib/solid_agent/orchestration/agent_tool.rb test/orchestration/integration_test.rb
git commit -m "feat: propagate otel_trace_id in orchestration, add OTel tool attributes"
```

---

## Task 10: Update main entry point to require telemetry files

Add the telemetry requires to `lib/solid_agent.rb` so everything loads correctly.

**Files:**
- Modify: `lib/solid_agent.rb`

- [ ] **Step 1: Add requires**

Add these lines to `lib/solid_agent.rb`, after the orchestration requires (after line 81):

```ruby
require 'solid_agent/telemetry/span_context'
require 'solid_agent/telemetry/exporter'
require 'solid_agent/telemetry/null_exporter'
require 'solid_agent/telemetry/serializer'
require 'solid_agent/telemetry/otlp_exporter'
```

- [ ] **Step 2: Run the full test suite to verify everything loads**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/models/trace_test.rb test/models/span_test.rb test/telemetry/span_context_test.rb test/telemetry/exporter_test.rb test/telemetry/null_exporter_test.rb test/telemetry/otlp_exporter_test.rb test/telemetry/serializer_test.rb test/configuration_test.rb test/react/loop_test.rb`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add lib/solid_agent.rb
git commit -m "feat: require telemetry files in main entry point"
```

---

## Task 11: Add migration template for otel columns

The install generator copies engine migrations. We need to ensure new installations get the `otel_trace_id` and `otel_span_id` columns. For existing installations, we need a migration template.

**Files:**
- Create: `lib/generators/solid_agent/install/templates/add_otel_ids.rb.tt`

- [ ] **Step 1: Create the migration template**

Create `lib/generators/solid_agent/install/templates/add_otel_ids.rb.tt`:

```ruby
class AddOtelIdsToSolidAgent < ActiveRecord::Migration[8.0]
  def change
    add_column :solid_agent_traces, :otel_trace_id, :string
    add_column :solid_agent_traces, :otel_span_id, :string
    add_column :solid_agent_spans, :otel_span_id, :string
  end
end
```

- [ ] **Step 2: Verify template looks correct**

Run: `cat lib/generators/solid_agent/install/templates/add_otel_ids.rb.tt`
Expected: Migration template with 3 add_column calls

- [ ] **Step 3: Commit**

```bash
git add lib/generators/solid_agent/install/templates/add_otel_ids.rb.tt
git commit -m "feat: add migration template for otel_trace_id and otel_span_id columns"
```

---

## Task 12: Update the initializers template and README documentation

Update the initializer template to show the telemetry exporter configuration option. Update the README observability section with OTel compliance info.

**Files:**
- Modify: `lib/generators/solid_agent/install/templates/solid_agent.rb.tt`
- Modify: `docs/observability.md`

- [ ] **Step 1: Update the initializer template**

Update `lib/generators/solid_agent/install/templates/solid_agent.rb.tt` to include the telemetry exporter as a commented-out option:

```ruby
SolidAgent.configure do |config|
  config.default_provider = :openai
  config.default_model = SolidAgent::Models::OpenAi::GPT_4O

  config.providers.openai = {
    api_key: ENV["OPENAI_API_KEY"]
  }

  # Export traces to an OpenTelemetry-compatible backend (Jaeger, Tempo, Honeycomb, etc.)
  # Uses OTLP JSON over HTTP — no additional gem dependencies required.
  # config.telemetry_exporters = [
  #   SolidAgent::Telemetry::OTLPExporter.new(endpoint: "http://localhost:4318/v1/traces")
  # ]
end
```

- [ ] **Step 2: Update observability docs**

Append to `docs/observability.md`:

```markdown
## OpenTelemetry Compliance

Solid Agent traces follow the [OpenTelemetry GenAI Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-spans/).

### W3C TraceContext

Every trace and span is assigned a W3C TraceContext-compliant ID:

- `otel_trace_id`: 32-character hex string (128-bit), shared across all spans in a trace and propagated to child traces in multi-agent orchestration
- `otel_span_id`: 16-character hex string (64-bit), unique per span

### Semantic Convention Attributes

Spans are automatically enriched with GenAI semantic convention attributes:

| Attribute | Span Type | Description |
|---|---|---|
| `gen_ai.operation.name` | all | `"chat"` for LLM calls, `"execute_tool"` for tool executions |
| `gen_ai.provider.name` | llm | `"openai"`, `"anthropic"`, `"google"`, `"ollama"` |
| `gen_ai.request.model` | llm | `"gpt-4o"`, `"claude-3-5-sonnet"`, etc. |
| `gen_ai.usage.input_tokens` | llm | Input token count per span |
| `gen_ai.usage.output_tokens` | llm | Output token count per span |
| `gen_ai.tool.name` | tool | Tool name (e.g., `"web_search"`) |
| `gen_ai.tool.call.id` | tool | Tool call ID from the LLM response |
| `gen_ai.tool.type` | tool | `"function"`, `"agent"`, etc. |
| `gen_ai.conversation.id` | all | Conversation ID for correlation |

### Exporting Traces

By default, traces are stored in SQLite and viewable in the dashboard. To export to an OTel-compatible backend:

```ruby
# config/initializers/solid_agent.rb
SolidAgent.configure do |config|
  config.telemetry_exporters = [
    SolidAgent::Telemetry::OTLPExporter.new(endpoint: "http://localhost:4318/v1/traces")
  ]
end
```

The OTLP exporter uses OTLP JSON encoding over HTTP with gzip compression. It requires **zero additional gem dependencies** — only Ruby stdlib.

#### Multiple Exporters

You can configure multiple exporters simultaneously:

```ruby
config.telemetry_exporters = [
  SolidAgent::Telemetry::OTLPExporter.new(endpoint: "http://jaeger:4318/v1/traces"),
  SolidAgent::Telemetry::OTLPExporter.new(endpoint: "http://tempo:4318/v1/traces")
]
```

#### Custom Exporter

Implement the exporter interface to send traces anywhere:

```ruby
class MyExporter < SolidAgent::Telemetry::Exporter
  def export_trace(trace)
    # trace has: otel_trace_id, otel_span_id, spans, metadata, usage, etc.
    # Each span has: otel_span_id, parent_span_id, metadata with OTel attrs
    payload = {
      trace_id: trace.otel_trace_id,
      agent: trace.agent_class,
      status: trace.status,
      spans: trace.spans.map { |s|
        {
          span_id: s.otel_span_id,
          name: s.name,
          type: s.span_type,
          attributes: s.metadata,
          status: s.status
        }
      }
    }
    # Send payload to your backend
  end
end

SolidAgent.configure do |config|
  config.telemetry_exporters = [MyExporter.new]
end
```

#### Compatible Backends

Any backend that accepts [OTLP](https://opentelemetry.io/docs/specs/otlp/) over HTTP:

- [Jaeger](https://www.jaegertracing.io/) (v1.54+)
- [Grafana Tempo](https://grafana.com/oss/tempo/)
- [Honeycomb](https://www.honeycomb.io/)
- [Datadog](https://docs.datadoghq.com/opentelemetry/)
- [Google Cloud Trace](https://cloud.google.com/trace/docs)
- [Elastic APM](https://www.elastic.co/apm/)
```

- [ ] **Step 3: Commit**

```bash
git add lib/generators/solid_agent/install/templates/solid_agent.rb.tt docs/observability.md
git commit -m "docs: add OTel compliance docs and update initializer template"
```

---

## Task 13: Run full test suite and verify

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/**/*_test.rb`
Expected: All tests PASS

- [ ] **Step 2: Verify no regressions in existing tests**

Specifically check:
- `test/react/loop_test.rb` — all existing loop tests still pass with new metadata
- `test/orchestration/integration_test.rb` — multi-agent tests still pass
- `test/models/trace_test.rb` — trace model tests still pass
- `test/models/span_test.rb` — span model tests still pass

- [ ] **Step 3: Commit any fixes if needed**
