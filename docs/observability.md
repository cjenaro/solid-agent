# Observability

The Solid Agent dashboard provides visibility into every agent run. Built with Inertia + React and mounted as a Rails engine.

## Accessing the Dashboard

The dashboard is mounted at `/solid_agent` by default:

```ruby
# config/initializers/solid_agent.rb
SolidAgent.configure do |config|
  config.dashboard_enabled = true
  config.dashboard_route_prefix = "solid_agent"
end
```

Mount in your routes (done automatically by the installer):

```ruby
# config/routes.rb
mount SolidAgent::Engine, at: "solid_agent"
```

Navigate to `http://localhost:3000/solid_agent`.

## Routes

| Route | Description |
|---|---|
| `/solid_agent` | Dashboard overview |
| `/solid_agent/traces` | Trace list with filters |
| `/solid_agent/traces/:id` | Trace detail with span tree |
| `/solid_agent/traces/:id/spans/:span_id` | Individual span detail |
| `/solid_agent/conversations` | Conversation list |
| `/solid_agent/conversations/:id` | Conversation with messages and traces |
| `/solid_agent/agents` | Registered agents with stats |
| `/solid_agent/tools` | Tool registry with execution stats |
| `/solid_agent/mcp` | MCP client status |

## Understanding Traces, Spans, and the Execution Tree

### Traces

A trace represents a single agent run. Each call to `perform_now` or `perform_later` creates one trace.

```
Trace #42 -- ResearchAgent -- completed -- 12.3s
  agent_class: "ResearchAgent"
  status: "completed"
  usage: { input_tokens: 4500, output_tokens: 1200 }
  iteration_count: 4
  parent_trace_id: nil  (child traces reference a parent)
```

Trace statuses: `pending`, `running`, `completed`, `failed`, `paused`.

### Spans

Each trace contains multiple spans representing steps in the ReAct loop:

| Span Type | Description |
|---|---|
| `think` | LLM call -- includes token counts and output |
| `act` | Tool execution batch |
| `observe` | Safety check or compaction |
| `tool_execution` | Individual tool call (used for agent-as-tool) |
| `llm_call` | Low-level LLM API call |

### The Execution Tree

The trace detail view shows a hierarchical span tree:

```
Trace #42 -- ResearchAgent -- completed -- 12.3s -- 5,700 tokens
|
+-- think_1 -------- 0.8s -- 842 in / 210 out
|   Output: tool_calls: [:web_search]
|
+-- act_1 ---------- 1.2s
|   +-- web_search(query: "Q4 market trends")
|       Result: "US GDP grew 3.1%..."
|
+-- think_2 -------- 0.6s -- 1,203 in / 180 out
|   Output: tool_calls: [:analyze_data]
|
+-- act_2 ---------- 2.1s
|   +-- analyze_data(data: [...])
|       Result: "Key findings: ..."
|
+-- think_3 -------- 0.4s -- 956 in / 530 out
    Final answer: "Based on the analysis..."
```

Spans are expandable. Click a span to see full input/output. For child traces (multi-agent orchestration), parent traces show inline child trace links.

### Parent-Child Relationships

In multi-agent systems, the dashboard shows parent-child trace relationships:

```
Trace #1 -- ProjectManagerAgent -- completed
  |
  +-- Trace #2 (child) -- ResearchAgent -- completed
  +-- Trace #3 (child) -- WriterAgent -- completed
```

## Token Usage Tracking and Cost Estimation

### Per-Trace Usage

Each trace stores accumulated token usage in a JSON column:

```ruby
trace = SolidAgent::Trace.find(42)
trace.usage
# => { "input_tokens" => 4500, "output_tokens" => 1200 }
trace.total_tokens  # => 5700
```

### Cost Estimation

Model constants include pricing. Use `SolidAgent::Types::Usage` to compute cost:

```ruby
model = SolidAgent::Models::OpenAi::GPT_4O
usage = SolidAgent::Types::Usage.new(
  input_tokens: 4500,
  output_tokens: 1200,
  input_price_per_million: model.input_price_per_million,
  output_price_per_million: model.output_price_per_million
)
usage.cost  # => 0.02325 ($0.02)
```

### Per-Span Usage

Each `think` span records its own token counts:

```ruby
span = trace.spans.find_by(span_type: "think")
span.tokens_in   # => 842
span.tokens_out  # => 210
span.total_tokens # => 1052
```

### Dashboard Aggregation

The dashboard overview page shows:

- Total traces and active traces
- Total conversations
- Aggregate token count across all traces
- List of registered agent classes

## Tool Execution Monitoring

The tools page (`/solid_agent/tools`) shows per-tool statistics aggregated from span data:

| Metric | Source |
|---|---|
| `total_calls` | Count of `tool_execution` spans |
| `avg_duration` | Average of span durations |
| `error_count` | Spans with `status: "error"` |
| `last_used` | Most recent span timestamp |

The agents page (`/solid_agent/agents`) shows per-agent statistics:

| Metric | Source |
|---|---|
| `total_traces` | Count of traces for the agent class |
| `total_tokens` | Sum of token usage across traces |
| `last_run` | Most recent trace timestamp |

## MCP Client Status

The MCP page (`/solid_agent/mcp`) displays configured MCP clients:

```
Client Name    Transport    Command/URL
filesystem     stdio        npx -y @modelcontextprotocol/server-filesystem /tmp
github         sse          http://localhost:3001/mcp
```

This page reads from `SolidAgent.configuration.mcp_clients`. It shows the configured transport type, command (for stdio) or URL (for SSE), and the client name.

## Trace Retention and Cleanup

### Configuration

```ruby
SolidAgent.configure do |config|
  config.trace_retention = 30.days  # auto-cleanup
  # or
  config.trace_retention = :keep_all
end
```

### Cleanup Job

`SolidAgent::TraceRetentionJob` runs as a scheduled Solid Queue job. It deletes traces older than the retention period, along with their associated spans:

```ruby
SolidAgent::TraceRetentionJob.perform_now
# Deletes traces older than 30.days.ago and their spans
```

To schedule it, add to your Solid Queue configuration:

```ruby
# config/solid_queue.yml
recurring:
  solid_agent_trace_cleanup:
    class: SolidAgent::TraceRetentionJob
    schedule: every day at midnight
```

## Adding Custom Dashboard Pages

The dashboard is an Inertia + React application bundled within the engine. To add custom pages:

1. Create a controller action:

```ruby
# app/controllers/solid_agent/custom_controller.rb
module SolidAgent
  class CustomController < ApplicationController
    def index
      render inertia: "solid_agent/Custom/Index", props: {
        custom_data: SolidAgent::Trace.group(:agent_class).count
      }
    end
  end
end
```

2. Add a route in your application (the engine routes are frozen):

```ruby
# config/routes.rb
mount SolidAgent::Engine, at: "solid_agent" do
  # Additional engine routes go here
end
```

Or create a separate controller outside the engine namespace and render engine data.

### Querying Trace Data

All models are standard ActiveRecord:

```ruby
# Recent failures
SolidAgent::Trace.where(status: "failed").order(created_at: :desc).limit(20)

# Token usage by agent
SolidAgent::Trace.group(:agent_class)
  .select("agent_class, SUM(CAST(usage->>'input_tokens' AS INTEGER) + CAST(usage->>'output_tokens' AS INTEGER)) as total_tokens")
  .order("total_tokens DESC")

# Slowest traces
SolidAgent::Trace.where.not(started_at: nil).where.not(completed_at: nil)
  .order(Arel.sql("julianday(completed_at) - julianday(started_at) DESC"))
  .limit(10)

# Tools with highest error rate
SolidAgent::Span.where(span_type: "tool_execution")
  .group(:name)
  .select("name, COUNT(*) as total, SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END) as errors")
  .having("errors > 0")
  .order("errors DESC")
```

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

The OTLP exporter uses OTLP JSON encoding over HTTP. It requires **zero additional gem dependencies** — only Ruby stdlib.

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
