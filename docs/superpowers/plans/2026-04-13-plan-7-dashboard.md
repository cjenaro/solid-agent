# Plan 7: Observability Dashboard

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Inertia.js + React + shadcn/ui dashboard mounted as an engine route to visualize agent traces, spans, conversations, tool execution, token usage, and MCP client status.

**Architecture:** The dashboard is a set of Rails controllers within the engine that render Inertia pages. React components (shadcn/ui) display trace trees, timing waterfalls, token usage charts, and agent/tool registries. A scheduled Solid Queue job handles trace retention cleanup.

**Tech Stack:** Ruby 3.3+, Rails 8.0+, Inertia.js, React, shadcn/ui, Minitest

---

## File Structure

```
app/
├── controllers/solid_agent/
│   ├── application_controller.rb
│   ├── dashboard_controller.rb
│   ├── traces_controller.rb
│   ├── conversations_controller.rb
│   ├── agents_controller.rb
│   ├── tools_controller.rb
│   └── mcp_controller.rb
├── views/
│   └── layouts/
│       └── solid_agent.html.erb
├── frontend/
│   ├── pages/
│   │   ├── Dashboard.tsx
│   │   ├── Traces/
│   │   │   ├── Index.tsx
│   │   │   └── Show.tsx
│   │   ├── Conversations/
│   │   │   ├── Index.tsx
│   │   │   └── Show.tsx
│   │   ├── Agents/
│   │   │   └── Index.tsx
│   │   ├── Tools/
│   │   │   └── Index.tsx
│   │   └── Mcp/
│   │       └── Index.tsx
│   ├── components/
│   │   ├── Layout.tsx
│   │   ├── SpanTree.tsx
│   │   ├── TimingWaterfall.tsx
│   │   ├── TokenUsageChart.tsx
│   │   └── TraceStatusBadge.tsx
│   └── entrypoint.tsx
├── jobs/solid_agent/
│   └── trace_retention_job.rb

config/
└── routes.rb (update)

test/
├── controllers/
│   ├── dashboard_controller_test.rb
│   ├── traces_controller_test.rb
│   └── conversations_controller_test.rb
└── jobs/
    └── trace_retention_job_test.rb
```

---

### Task 1: Engine Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Define all dashboard routes**

```ruby
# config/routes.rb
SolidAgent::Engine.routes.draw do
  root "dashboard#index"

  resources :traces, only: %i[index show] do
    resources :spans, only: %i[show], controller: "spans"
  end

  resources :conversations, only: %i[index show]

  resources :agents, only: %i[index]
  resources :tools, only: %i[index]

  get "mcp", to: "mcp#index", as: :mcp_status
end
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: add dashboard routes"
```

---

### Task 2: Application Controller

**Files:**
- Create: `app/controllers/solid_agent/application_controller.rb`
- Create: `app/views/layouts/solid_agent.html.erb`

- [ ] **Step 1: Implement base controller**

```ruby
# app/controllers/solid_agent/application_controller.rb
module SolidAgent
  class ApplicationController < ActionController::Base
    layout "solid_agent"

    before_action :check_dashboard_enabled

    private

    def check_dashboard_enabled
      unless SolidAgent.configuration.dashboard_enabled
        render plain: "SolidAgent dashboard is disabled.", status: :not_found
      end
    end
  end
end
```

- [ ] **Step 2: Create layout**

```erb
<!-- app/views/layouts/solid_agent.html.erb -->
<!DOCTYPE html>
<html>
<head>
  <title>SolidAgent</title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <% if defined?(ViteRuby) %>
    <%= vite_client_tag %>
    <%= vite_javascript_tag "solid_agent" %>
  <% else %>
    <script defer src="https://unpkg.com/@inertiajs/inertia@latest"></script>
  <% end %>
</head>
<body>
  <%= yield %>
  <%= inertia_shared_data %>
</body>
</html>
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add dashboard application controller and layout"
```

---

### Task 3: Dashboard Controller (Overview)

**Files:**
- Create: `app/controllers/solid_agent/dashboard_controller.rb`
- Test: `test/controllers/dashboard_controller_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/controllers/dashboard_controller_test.rb
require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include Engine.routes.url_helpers

  test "GET index returns ok" do
    get root_path
    assert_response :success
  end

  test "shows stats in props" do
    conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
    SolidAgent::Trace.create!(
      conversation: conversation, agent_class: "TestAgent",
      trace_type: :agent_run, status: "completed",
      usage: { "input_tokens" => 100, "output_tokens" => 50 }
    )

    get root_path
    assert_response :success
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/controllers/dashboard_controller_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement DashboardController**

```ruby
# app/controllers/solid_agent/dashboard_controller.rb
module SolidAgent
  class DashboardController < ApplicationController
    def index
      render inertia: "solid_agent/Dashboard", props: {
        stats: dashboard_stats,
        recent_traces: recent_traces
      }
    end

    private

    def dashboard_stats
      {
        total_traces: Trace.count,
        active_traces: Trace.where(status: "running").count,
        total_conversations: Conversation.count,
        total_tokens: total_tokens,
        agents: Trace.distinct.pluck(:agent_class)
      }
    end

    def recent_traces
      Trace.order(created_at: :desc).limit(10).as_json(
        only: %i[id agent_class status started_at completed_at usage]
      )
    end

    def total_tokens
      Trace.all.sum { |t| (t.usage["input_tokens"] || 0) + (t.usage["output_tokens"] || 0) }
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/controllers/dashboard_controller_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Dashboard controller with stats"
```

---

### Task 4: Traces Controller

**Files:**
- Create: `app/controllers/solid_agent/traces_controller.rb`
- Create: `app/controllers/solid_agent/spans_controller.rb`
- Test: `test/controllers/traces_controller_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/controllers/traces_controller_test.rb
require "test_helper"

class TracesControllerTest < ActionDispatch::IntegrationTest
  include Engine.routes.url_helpers

  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
  end

  test "GET index returns traces list" do
    SolidAgent::Trace.create!(
      conversation: @conversation, agent_class: "ResearchAgent",
      trace_type: :agent_run, status: "completed"
    )

    get traces_path
    assert_response :success
  end

  test "GET show returns trace with spans" do
    trace = SolidAgent::Trace.create!(
      conversation: @conversation, agent_class: "ResearchAgent",
      trace_type: :agent_run, status: "completed",
      usage: { "input_tokens" => 100, "output_tokens" => 50 }
    )
    SolidAgent::Span.create!(
      trace: trace, span_type: "think", name: "think_1",
      status: "completed", tokens_in: 100, tokens_out: 50,
      started_at: 1.minute.ago, completed_at: Time.current
    )

    get trace_path(trace)
    assert_response :success
  end

  test "GET index filters by agent" do
    SolidAgent::Trace.create!(conversation: @conversation, agent_class: "AgentA", trace_type: :agent_run)
    SolidAgent::Trace.create!(conversation: @conversation, agent_class: "AgentB", trace_type: :agent_run)

    get traces_path, params: { agent_class: "AgentA" }
    assert_response :success
  end

  test "GET index filters by status" do
    SolidAgent::Trace.create!(conversation: @conversation, agent_class: "Test", trace_type: :agent_run, status: "completed")
    SolidAgent::Trace.create!(conversation: @conversation, agent_class: "Test", trace_type: :agent_run, status: "failed")

    get traces_path, params: { status: "completed" }
    assert_response :success
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/controllers/traces_controller_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement TracesController**

```ruby
# app/controllers/solid_agent/traces_controller.rb
module SolidAgent
  class TracesController < ApplicationController
    def index
      traces = Trace.includes(:conversation)
      traces = traces.where(agent_class: params[:agent_class]) if params[:agent_class].present?
      traces = traces.where(status: params[:status]) if params[:status].present?
      traces = traces.order(created_at: :desc).limit(50)

      render inertia: "solid_agent/Traces/Index", props: {
        traces: traces.as_json(
          only: %i[id agent_class status started_at completed_at usage iteration_count created_at],
          include: { conversation: { only: %i[id agent_class] } }
        ),
        agent_classes: Trace.distinct.pluck(:agent_class),
        statuses: Trace::STATUSES
      }
    end

    def show
      trace = Trace.includes(spans: :child_spans, child_traces: :spans).find(params[:id])

      render inertia: "solid_agent/Traces/Show", props: {
        trace: trace.as_json(
          only: %i[id agent_class status started_at completed_at usage iteration_count input output error created_at],
          include: {
            spans: { only: %i[id span_type name status tokens_in tokens_out started_at completed_at input output parent_span_id] },
            child_traces: { only: %i[id agent_class status started_at completed_at] },
            conversation: { only: %i[id] }
          }
        ),
        parent_trace: trace.parent_trace&.as_json(only: %i[id agent_class])
      }
    end
  end
end
```

- [ ] **Step 4: Implement SpansController**

```ruby
# app/controllers/solid_agent/spans_controller.rb
module SolidAgent
  class SpansController < ApplicationController
    def show
      span = Span.find(params[:id])
      render inertia: "solid_agent/Spans/Show", props: {
        span: span.as_json(only: %i[id span_type name status tokens_in tokens_out started_at completed_at input output metadata])
      }
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/controllers/traces_controller_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Traces and Spans controllers"
```

---

### Task 5: Conversations Controller

**Files:**
- Create: `app/controllers/solid_agent/conversations_controller.rb`
- Test: `test/controllers/conversations_controller_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/controllers/conversations_controller_test.rb
require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  include Engine.routes.url_helpers

  test "GET index returns conversations" do
    SolidAgent::Conversation.create!(agent_class: "ResearchAgent")
    get conversations_path
    assert_response :success
  end

  test "GET show returns conversation with traces and messages" do
    conversation = SolidAgent::Conversation.create!(agent_class: "ResearchAgent")
    trace = SolidAgent::Trace.create!(conversation: conversation, agent_class: "ResearchAgent", trace_type: :agent_run)
    SolidAgent::Message.create!(conversation: conversation, trace: trace, role: "user", content: "Hello")
    SolidAgent::Message.create!(conversation: conversation, trace: trace, role: "assistant", content: "Hi!")

    get conversation_path(conversation)
    assert_response :success
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/controllers/conversations_controller_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement ConversationsController**

```ruby
# app/controllers/solid_agent/conversations_controller.rb
module SolidAgent
  class ConversationsController < ApplicationController
    def index
      conversations = Conversation.order(updated_at: :desc).limit(50)

      render inertia: "solid_agent/Conversations/Index", props: {
        conversations: conversations.as_json(
          only: %i[id agent_class status created_at updated_at],
          include: { traces: { only: %i[id status] } }
        )
      }
    end

    def show
      conversation = Conversation.includes(:traces, :messages).find(params[:id])

      render inertia: "solid_agent/Conversations/Show", props: {
        conversation: conversation.as_json(
          only: %i[id agent_class status metadata created_at updated_at],
          include: {
            traces: { only: %i[id agent_class status started_at completed_at usage], methods: [:duration] },
            messages: { only: %i[id role content tool_call_id token_count model created_at] }
          }
        )
      }
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/controllers/conversations_controller_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Conversations controller"
```

---

### Task 6: Agents, Tools, and MCP Controllers

**Files:**
- Create: `app/controllers/solid_agent/agents_controller.rb`
- Create: `app/controllers/solid_agent/tools_controller.rb`
- Create: `app/controllers/solid_agent/mcp_controller.rb`

- [ ] **Step 1: Implement AgentsController**

```ruby
# app/controllers/solid_agent/agents_controller.rb
module SolidAgent
  class AgentsController < ApplicationController
    def index
      agent_names = Trace.distinct.pluck(:agent_class)
      agents = agent_names.map do |name|
        traces = Trace.where(agent_class: name)
        {
          name: name,
          total_traces: traces.count,
          total_tokens: traces.sum { |t| (t.usage["input_tokens"] || 0) + (t.usage["output_tokens"] || 0) },
          last_run: traces.maximum(:created_at)
        }
      end

      render inertia: "solid_agent/Agents/Index", props: { agents: agents }
    end
  end
end
```

- [ ] **Step 2: Implement ToolsController**

```ruby
# app/controllers/solid_agent/tools_controller.rb
module SolidAgent
  class ToolsController < ApplicationController
    def index
      tool_spans = Span.where(span_type: "tool_execution")
      tool_names = tool_spans.distinct.pluck(:name)

      tools = tool_names.map do |name|
        spans = tool_spans.where(name: name)
        {
          name: name,
          total_calls: spans.count,
          avg_duration: spans.filter_map(&:duration).then { |d| d.empty? ? 0 : d.sum / d.size },
          error_count: spans.where(status: "error").count,
          last_used: spans.maximum(:created_at)
        }
      end

      render inertia: "solid_agent/Tools/Index", props: { tools: tools }
    end
  end
end
```

- [ ] **Step 3: Implement McpController**

```ruby
# app/controllers/solid_agent/mcp_controller.rb
module SolidAgent
  class McpController < ApplicationController
    def index
      mcp_clients = SolidAgent.configuration.mcp_clients.map do |name, config|
        {
          name: name,
          transport: config[:transport],
          command: config[:command],
          url: config[:url]
        }
      end

      render inertia: "solid_agent/Mcp/Index", props: { mcp_clients: mcp_clients }
    end
  end
end
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add Agents, Tools, and MCP controllers"
```

---

### Task 7: Trace Retention Job

**Files:**
- Create: `app/jobs/solid_agent/trace_retention_job.rb`
- Test: `test/jobs/trace_retention_job_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/jobs/trace_retention_job_test.rb
require "test_helper"

class TraceRetentionJobTest < ActiveSupport::TestCase
  test "deletes old traces" do
    conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")

    old_trace = SolidAgent::Trace.create!(
      conversation: conversation, agent_class: "Test",
      trace_type: :agent_run, status: "completed",
      created_at: 31.days.ago
    )
    SolidAgent::Span.create!(trace: old_trace, span_type: "think", name: "old", created_at: 31.days.ago)

    new_trace = SolidAgent::Trace.create!(
      conversation: conversation, agent_class: "Test",
      trace_type: :agent_run, status: "completed"
    )

    SolidAgent::TraceRetentionJob.perform_now(retention: 30.days)

    assert_not SolidAgent::Trace.exists?(old_trace.id)
    assert SolidAgent::Trace.exists?(new_trace.id)
  end

  test "keeps all traces when retention is :keep_all" do
    conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
    trace = SolidAgent::Trace.create!(
      conversation: conversation, agent_class: "Test",
      trace_type: :agent_run, status: "completed",
      created_at: 100.days.ago
    )

    SolidAgent::TraceRetentionJob.perform_now(retention: :keep_all)

    assert SolidAgent::Trace.exists?(trace.id)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/jobs/trace_retention_job_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement TraceRetentionJob**

```ruby
# app/jobs/solid_agent/trace_retention_job.rb
module SolidAgent
  class TraceRetentionJob < ApplicationJob
    queue_as :solid_agent

    def perform(retention: SolidAgent.configuration.trace_retention)
      return if retention == :keep_all

      cutoff = retention.ago
      old_traces = Trace.where("created_at < ?", cutoff)
      old_traces.find_each do |trace|
        trace.spans.destroy_all
        trace.destroy
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/jobs/trace_retention_job_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add TraceRetentionJob for data cleanup"
```

---

### Task 8: React Page Components

These components will live in the engine's frontend bundle. They use Inertia.js for data loading and shadcn/ui for styling.

**Files:**
- Create: `app/frontend/pages/Dashboard.tsx`
- Create: `app/frontend/pages/Traces/Index.tsx`
- Create: `app/frontend/pages/Traces/Show.tsx`
- Create: `app/frontend/components/Layout.tsx`
- Create: `app/frontend/components/SpanTree.tsx`
- Create: `app/frontend/components/TraceStatusBadge.tsx`

- [ ] **Step 1: Create Layout component**

```tsx
// app/frontend/components/Layout.tsx
import { Link } from "@inertiajs/react"

interface LayoutProps {
  children: React.ReactNode
}

export default function Layout({ children }: LayoutProps) {
  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="border-b bg-white px-6 py-3">
        <div className="flex items-center gap-6">
          <Link href="/solid_agent" className="font-bold text-lg">
            SolidAgent
          </Link>
          <Link href="/solid_agent/traces" className="text-sm text-gray-600 hover:text-gray-900">
            Traces
          </Link>
          <Link href="/solid_agent/conversations" className="text-sm text-gray-600 hover:text-gray-900">
            Conversations
          </Link>
          <Link href="/solid_agent/agents" className="text-sm text-gray-600 hover:text-gray-900">
            Agents
          </Link>
          <Link href="/solid_agent/tools" className="text-sm text-gray-600 hover:text-gray-900">
            Tools
          </Link>
          <Link href="/solid_agent/mcp" className="text-sm text-gray-600 hover:text-gray-900">
            MCP
          </Link>
        </div>
      </nav>
      <main className="mx-auto max-w-7xl px-6 py-6">
        {children}
      </main>
    </div>
  )
}
```

- [ ] **Step 2: Create Dashboard page**

```tsx
// app/frontend/pages/Dashboard.tsx
import Layout from "../components/Layout"

interface Stats {
  total_traces: number
  active_traces: number
  total_conversations: number
  total_tokens: number
  agents: string[]
}

interface DashboardProps {
  stats: Stats
  recent_traces: Array<{
    id: number
    agent_class: string
    status: string
    started_at: string | null
    created_at: string
    usage: { input_tokens: number; output_tokens: number } | null
  }>
}

export default function Dashboard({ stats, recent_traces }: DashboardProps) {
  return (
    <Layout>
      <h1 className="text-2xl font-bold mb-6">SolidAgent Dashboard</h1>

      <div className="grid grid-cols-4 gap-4 mb-8">
        <div className="rounded-lg border bg-white p-4">
          <p className="text-sm text-gray-500">Total Traces</p>
          <p className="text-2xl font-bold">{stats.total_traces}</p>
        </div>
        <div className="rounded-lg border bg-white p-4">
          <p className="text-sm text-gray-500">Active Traces</p>
          <p className="text-2xl font-bold">{stats.active_traces}</p>
        </div>
        <div className="rounded-lg border bg-white p-4">
          <p className="text-sm text-gray-500">Total Tokens</p>
          <p className="text-2xl font-bold">{stats.total_tokens.toLocaleString()}</p>
        </div>
        <div className="rounded-lg border bg-white p-4">
          <p className="text-sm text-gray-500">Conversations</p>
          <p className="text-2xl font-bold">{stats.total_conversations}</p>
        </div>
      </div>

      <div className="rounded-lg border bg-white">
        <div className="border-b px-4 py-3">
          <h2 className="font-semibold">Recent Traces</h2>
        </div>
        <table className="w-full">
          <thead>
            <tr className="border-b text-left text-sm text-gray-500">
              <th className="px-4 py-2">ID</th>
              <th className="px-4 py-2">Agent</th>
              <th className="px-4 py-2">Status</th>
              <th className="px-4 py-2">Tokens</th>
              <th className="px-4 py-2">Created</th>
            </tr>
          </thead>
          <tbody>
            {recent_traces.map((trace) => (
              <tr key={trace.id} className="border-b hover:bg-gray-50">
                <td className="px-4 py-2">
                  <a href={`/solid_agent/traces/${trace.id}`} className="text-blue-600 hover:underline">
                    #{trace.id}
                  </a>
                </td>
                <td className="px-4 py-2 font-mono text-sm">{trace.agent_class}</td>
                <td className="px-4 py-2">
                  <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium
                    ${trace.status === "completed" ? "bg-green-100 text-green-800" : ""}
                    ${trace.status === "running" ? "bg-blue-100 text-blue-800" : ""}
                    ${trace.status === "failed" ? "bg-red-100 text-red-800" : ""}
                    ${trace.status === "paused" ? "bg-yellow-100 text-yellow-800" : ""}
                  `}>
                    {trace.status}
                  </span>
                </td>
                <td className="px-4 py-2 text-sm">
                  {trace.usage ? (trace.usage.input_tokens + trace.usage.output_tokens).toLocaleString() : "—"}
                </td>
                <td className="px-4 py-2 text-sm text-gray-500">{trace.created_at}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Layout>
  )
}
```

- [ ] **Step 3: Create TraceStatusBadge component**

```tsx
// app/frontend/components/TraceStatusBadge.tsx
interface TraceStatusBadgeProps {
  status: string
}

export default function TraceStatusBadge({ status }: TraceStatusBadgeProps) {
  const colors: Record<string, string> = {
    completed: "bg-green-100 text-green-800",
    running: "bg-blue-100 text-blue-800",
    failed: "bg-red-100 text-red-800",
    paused: "bg-yellow-100 text-yellow-800",
    pending: "bg-gray-100 text-gray-800",
  }

  return (
    <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${colors[status] || "bg-gray-100 text-gray-800"}`}>
      {status}
    </span>
  )
}
```

- [ ] **Step 4: Create SpanTree component**

```tsx
// app/frontend/components/SpanTree.tsx
interface Span {
  id: number
  span_type: string
  name: string
  status: string
  tokens_in: number
  tokens_out: number
  started_at: string | null
  completed_at: string | null
  parent_span_id: number | null
}

interface SpanTreeProps {
  spans: Span[]
}

export default function SpanTree({ spans }: SpanTreeProps) {
  const getDuration = (span: Span) => {
    if (!span.started_at || !span.completed_at) return null
    return ((new Date(span.completed_at).getTime() - new Date(span.started_at).getTime()) / 1000).toFixed(2)
  }

  const typeColors: Record<string, string> = {
    think: "bg-purple-50 border-purple-200",
    act: "bg-orange-50 border-orange-200",
    observe: "bg-blue-50 border-blue-200",
    tool_execution: "bg-green-50 border-green-200",
    llm_call: "bg-gray-50 border-gray-200",
  }

  return (
    <div className="space-y-1">
      {spans.filter(s => !s.parent_span_id).map((span) => (
        <div key={span.id} className={`rounded border p-3 ${typeColors[span.span_type] || ""}`}>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="font-mono text-xs text-gray-500 uppercase">{span.span_type}</span>
              <span className="font-medium">{span.name}</span>
            </div>
            <div className="flex items-center gap-4 text-sm text-gray-600">
              {getDuration(span) && <span>{getDuration(span)}s</span>}
              {span.tokens_in > 0 && (
                <span>{span.tokens_in} in / {span.tokens_out} out</span>
              )}
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}
```

- [ ] **Step 5: Create Traces Index page**

```tsx
// app/frontend/pages/Traces/Index.tsx
import Layout from "../../components/Layout"
import TraceStatusBadge from "../../components/TraceStatusBadge"
import { Link } from "@inertiajs/react"

interface Trace {
  id: number
  agent_class: string
  status: string
  started_at: string | null
  completed_at: string | null
  usage: { input_tokens: number; output_tokens: number } | null
  iteration_count: number
  created_at: string
  conversation: { id: number; agent_class: string } | null
}

interface TracesIndexProps {
  traces: Trace[]
  agent_classes: string[]
  statuses: string[]
}

export default function TracesIndex({ traces, agent_classes, statuses }: TracesIndexProps) {
  return (
    <Layout>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Traces</h1>
        <div className="flex gap-3">
          <select className="rounded border px-3 py-1.5 text-sm">
            <option value="">All Agents</option>
            {agent_classes.map((a) => <option key={a} value={a}>{a}</option>)}
          </select>
          <select className="rounded border px-3 py-1.5 text-sm">
            <option value="">All Statuses</option>
            {statuses.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </div>
      </div>

      <div className="rounded-lg border bg-white">
        <table className="w-full">
          <thead>
            <tr className="border-b text-left text-sm text-gray-500">
              <th className="px-4 py-2">ID</th>
              <th className="px-4 py-2">Agent</th>
              <th className="px-4 py-2">Status</th>
              <th className="px-4 py-2">Iterations</th>
              <th className="px-4 py-2">Tokens</th>
              <th className="px-4 py-2">Created</th>
            </tr>
          </thead>
          <tbody>
            {traces.map((trace) => (
              <tr key={trace.id} className="border-b hover:bg-gray-50">
                <td className="px-4 py-2">
                  <Link href={`/solid_agent/traces/${trace.id}`} className="text-blue-600 hover:underline">
                    #{trace.id}
                  </Link>
                </td>
                <td className="px-4 py-2 font-mono text-sm">{trace.agent_class}</td>
                <td className="px-4 py-2"><TraceStatusBadge status={trace.status} /></td>
                <td className="px-4 py-2 text-sm">{trace.iteration_count}</td>
                <td className="px-4 py-2 text-sm">
                  {trace.usage ? (trace.usage.input_tokens + trace.usage.output_tokens).toLocaleString() : "—"}
                </td>
                <td className="px-4 py-2 text-sm text-gray-500">{trace.created_at}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Layout>
  )
}
```

- [ ] **Step 6: Create Traces Show page**

```tsx
// app/frontend/pages/Traces/Show.tsx
import Layout from "../../components/Layout"
import SpanTree from "../../components/SpanTree"
import TraceStatusBadge from "../../components/TraceStatusBadge"

interface TraceShowProps {
  trace: {
    id: number
    agent_class: string
    status: string
    started_at: string | null
    completed_at: string | null
    usage: { input_tokens: number; output_tokens: number } | null
    iteration_count: number
    input: string | null
    output: string | null
    error: string | null
    created_at: string
    spans: Array<{
      id: number
      span_type: string
      name: string
      status: string
      tokens_in: number
      tokens_out: number
      started_at: string | null
      completed_at: string | null
      input: string | null
      output: string | null
      parent_span_id: number | null
    }>
    child_traces: Array<{
      id: number
      agent_class: string
      status: string
      started_at: string | null
      completed_at: string | null
    }>
    conversation: { id: number }
  }
  parent_trace: { id: number; agent_class: string } | null
}

export default function TraceShow({ trace, parent_trace }: TraceShowProps) {
  const totalTokens = trace.usage ? trace.usage.input_tokens + trace.usage.output_tokens : 0

  return (
    <Layout>
      <div className="mb-6">
        <div className="flex items-center gap-3 mb-2">
          <h1 className="text-2xl font-bold">Trace #{trace.id}</h1>
          <TraceStatusBadge status={trace.status} />
        </div>
        <div className="flex gap-4 text-sm text-gray-600">
          <span className="font-mono">{trace.agent_class}</span>
          {trace.started_at && trace.completed_at && (
            <span>{((new Date(trace.completed_at).getTime() - new Date(trace.started_at).getTime()) / 1000).toFixed(1)}s</span>
          )}
          <span>{totalTokens.toLocaleString()} tokens</span>
          <span>{trace.iteration_count} iterations</span>
        </div>
        {parent_trace && (
          <a href={`/solid_agent/traces/${parent_trace.id}`} className="text-sm text-blue-600 hover:underline">
            Parent: #{parent_trace.id} ({parent_trace.agent_class})
          </a>
        )}
      </div>

      {trace.input && (
        <div className="mb-4 rounded-lg border bg-white p-4">
          <h3 className="text-sm font-semibold text-gray-500 mb-1">Input</h3>
          <p className="whitespace-pre-wrap">{trace.input}</p>
        </div>
      )}

      <div className="mb-4">
        <h2 className="text-lg font-semibold mb-3">Execution Spans</h2>
        <SpanTree spans={trace.spans} />
      </div>

      {trace.child_traces.length > 0 && (
        <div className="mb-4">
          <h2 className="text-lg font-semibold mb-3">Child Traces</h2>
          <div className="space-y-2">
            {trace.child_traces.map((child) => (
              <a key={child.id} href={`/solid_agent/traces/${child.id}`}
                className="block rounded-lg border bg-white p-3 hover:bg-gray-50">
                <div className="flex items-center gap-3">
                  <span className="font-mono text-sm">#{child.id}</span>
                  <span className="text-sm">{child.agent_class}</span>
                  <TraceStatusBadge status={child.status} />
                </div>
              </a>
            ))}
          </div>
        </div>
      )}

      {trace.output && (
        <div className="mb-4 rounded-lg border bg-white p-4">
          <h3 className="text-sm font-semibold text-gray-500 mb-1">Output</h3>
          <p className="whitespace-pre-wrap">{trace.output}</p>
        </div>
      )}

      {trace.error && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4">
          <h3 className="text-sm font-semibold text-red-800 mb-1">Error</h3>
          <p className="text-red-700 whitespace-pre-wrap">{trace.error}</p>
        </div>
      )}
    </Layout>
  )
}
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add React dashboard components with trace visualization"
```

---

### Task 9: Final Verification

- [ ] **Step 1: Run all controller and job tests**

Run: `bundle exec ruby -Itest test/controllers/ test/jobs/ -v`
Expected: All tests PASS

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "chore: dashboard plan complete"
```
