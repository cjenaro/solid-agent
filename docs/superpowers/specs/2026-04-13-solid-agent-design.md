# Solid Agent — Full Design Spec

A plug-and-play Rails engine that brings agentic capabilities to any Rails 8+ application using the Solid stack (Solid Queue, Solid Cache, Solid Cable) and SQLite for all persistence, memory, and orchestration. Zero external dependencies.

## Architecture: Layered Monolith

```
Dashboard (Inertia + React, mounted engine)
    ↓
Orchestration (supervisor delegation, agent-as-tool)
    ↓
Agent Runtime (ReAct loop via Solid Queue, resumable jobs)
    ↓
Memory (sliding window, compaction, observational — pluggable)
    ↓
LLM Providers (OpenAI, Anthropic, Google, Ollama — pluggable HTTP adapters)
    ↓
Engine Core (config, migrations, MCP client, tool registry)
```

Each layer depends only on layers below it. Namespaces: `SolidAgent::Provider`, `SolidAgent::Memory`, `SolidAgent::Agent`, `SolidAgent::Tool`, `SolidAgent::Orchestration`, `SolidAgent::Observability`.

---

## 1. Engine Core & Configuration

### Gem Structure

```
solid_agent/
├── app/
│   ├── models/solid_agent/
│   ├── controllers/solid_agent/
│   └── views/
├── app/frontend/
├── config/
│   ├── routes.rb
│   └── solid_agent.yml
├── db/migrate/
├── lib/
│   ├── solid_agent.rb
│   ├── solid_agent/
│   │   ├── engine.rb
│   │   ├── configuration.rb
│   │   ├── provider/
│   │   ├── memory/
│   │   ├── agent/
│   │   ├── tool/
│   │   ├── orchestration/
│   │   ├── vector_store/
│   │   └── observability/
│   └── generators/
├── test/
├── solid_agent.gemspec
└── README.md
```

### Requirements

- Rails 8+, Ruby 3.3+
- SQLite as default DB (users can use other DBs their app is configured with)
- Solid Queue for job execution
- Solid Cable for streaming
- Minitest for tests

### Configuration DSL

```ruby
# config/initializers/solid_agent.rb
SolidAgent.configure do |config|
  config.default_provider = :openai
  config.default_model = SolidAgent::Models::OpenAi::GPT_4O

  config.dashboard_enabled = true
  config.dashboard_route_prefix = "solid_agent"

  config.vector_store = :sqlite_vec  # or nil to disable, or custom class
  config.embedding_provider = :openai
  config.embedding_model = "text-embedding-3-small"

  config.http_adapter = :net_http  # :net_http (default), :faraday, :async_http, or custom class

  config.trace_retention = 30.days  # or :keep_all

  config.mcp_clients = {
    filesystem: {
      transport: :stdio,
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
    },
    github: {
      transport: :sse,
      url: "http://localhost:3001/mcp",
      headers: { "Authorization" => "Bearer #{ENV['GITHUB_TOKEN']}" }
    }
  }

  config.providers.openai = {
    api_key: ENV["OPENAI_API_KEY"],
    default_model: SolidAgent::Models::OpenAi::GPT_4O
  }
  config.providers.anthropic = {
    api_key: ENV["ANTHROPIC_API_KEY"],
    default_model: SolidAgent::Models::Anthropic::CLAUDE_SONNET_4
  }
end
```

### Installation

```bash
bin/rails solid_agent:install
# Copies migrations, mounts engine, creates config initializer
bin/rails db:migrate
```

---

## 2. HTTP Adapter Layer

Providers never touch HTTP directly. They produce `Request` structs and consume `Response` structs.

### Interface

```ruby
# Adapter-agnostic request/response
SolidAgent::HTTP::Request  = Struct.new(:method, :url, :headers, :body, :stream)
SolidAgent::HTTP::Response = Struct.new(:status, :headers, :body, :error)

# Any object responding to #call(request) -> Response
class SolidAgent::HTTP::NetHttpAdapter
  def call(request)
    # returns Response
  end
end
```

### Built-in Adapters

- `:net_http` — default, zero deps
- `:faraday` — for apps already using Faraday
- `:async_http` — for async execution

Users can provide any class responding to `call(Request) -> Response`.

---

## 3. LLM Provider Layer

### Provider Interface

Every provider implements:

```ruby
module SolidAgent::Provider::Base
  def build_request(messages:, tools:, stream:, model:, options:)
    # => SolidAgent::HTTP::Request
  end

  def parse_response(raw_response)
    # => SolidAgent::Response
  end

  def parse_stream_chunk(chunk)
    # => SolidAgent::StreamChunk
  end

  def parse_tool_call(raw_tool_call)
    # => SolidAgent::ToolCall
  end
end
```

### Internal Types

```ruby
SolidAgent::Message     # role, content, tool_calls, tool_call_id, metadata
SolidAgent::Response    # messages, tool_calls, usage, finish_reason
SolidAgent::StreamChunk # delta_content, delta_tool_calls, usage, done?
SolidAgent::ToolCall    # id, name, arguments (parsed JSON), call_index
SolidAgent::Usage       # input_tokens, output_tokens, total_cost
```

### Model Constants

No raw strings. Models are defined as constants with their metadata:

```ruby
class SolidAgent::Model
  attr_reader :id, :context_window, :max_output

  def initialize(id, context_window:, max_output:)
    @id = id
    @context_window = context_window
    @max_output = max_output
  end
end

module SolidAgent::Models
  module OpenAi
    GPT_4O = Model.new("gpt-4o", context_window: 128_000, max_output: 16_384)
    GPT_4O_MINI = Model.new("gpt-4o-mini", context_window: 128_000, max_output: 16_384)
    O3 = Model.new("o3", context_window: 200_000, max_output: 100_000)
    O3_MINI = Model.new("o3-mini", context_window: 200_000, max_output: 100_000)
  end

  module Anthropic
    CLAUDE_SONNET_4 = Model.new("claude-sonnet-4-20250514", context_window: 200_000, max_output: 16_384)
    CLAUDE_OPUS_4 = Model.new("claude-opus-4-20250514", context_window: 200_000, max_output: 32_000)
  end

  module Google
    GEMINI_2_5_PRO = Model.new("gemini-2.5-pro", context_window: 1_000_000, max_output: 8_192)
    GEMINI_2_5_FLASH = Model.new("gemini-2.5-flash", context_window: 1_000_000, max_output: 8_192)
  end
end
```

### Provider Implementations

```
lib/solid_agent/provider/
├── base.rb
├── openai.rb
├── anthropic.rb
├── google.rb
├── ollama.rb
└── openai_compatible.rb   # LiteLLM, vLLM, etc.
```

### Token Tracking

Token counts come from the LLM response `usage` object — no estimation. The framework accumulates totals per trace and per conversation. Model definitions include context windows so the memory strategy can decide when to compact.

### Model Pricing & Cost

Each provider registers model pricing:

```ruby
SolidAgent::Provider::OpenAi.register_pricing(SolidAgent::Models::OpenAi::GPT_4O,
  input_price_per_million: 2.50,
  output_price_per_million: 10.00
)
```

`Usage` objects compute cost automatically. Stored in DB for dashboard reporting.

### Streaming

Providers yield `StreamChunk` objects. Runtime accumulates and broadcasts via Solid Cable:

```ruby
provider.complete(messages:, stream: true) do |chunk|
  SolidAgent::Streaming.broadcast(conversation_id, chunk)
end
```

### Error Hierarchy

```ruby
SolidAgent::ProviderError < StandardError
SolidAgent::RateLimitError < ProviderError       # auto-retry
SolidAgent::ContextLengthError < ProviderError    # triggers compaction
SolidAgent::ProviderTimeoutError < ProviderError
```

---

## 4. Agent Definition DSL

Active Job-inspired class-based DSL:

```ruby
# app/agents/research_agent.rb
class ResearchAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  max_tokens 4096
  temperature 0.7

  instructions <<~PROMPT
    You are a research assistant. Analyze queries thoroughly
    and use available tools to gather information.
  PROMPT

  # Memory
  memory :sliding_window, max_messages: 50

  # Ruby tools
  tool :search, description: "Search the web for information" do |query:|
    SearchResult.where("content LIKE ?", "%#{query}%")
  end

  tool :read_document, description: "Read a document by ID" do |id:|
    Document.find(id).content
  end

  # MCP tools — allowlist from configured MCP clients
  mcp_tool :read_file, from: :filesystem
  mcp_tool :write_file, from: :filesystem

  # Concurrency
  concurrency 3

  # Safety
  max_iterations 25
  max_tokens_per_run 100_000
  timeout 5.minutes
  retry_on SolidAgent::RateLimitError, attempts: 3

  # Tool approval gate
  require_approval :write_file

  # Callbacks
  before_invoke :validate_input
  after_invoke :log_completion
  on_tool_error :handle_tool_failure
  on_context_overflow :compact_memory
end
```

### Standalone Ruby Tools

Reusable across agents:

```ruby
# app/tools/web_search_tool.rb
class WebSearchTool < SolidAgent::Tool::Base
  name :web_search
  description "Search the web for information"

  parameter :query, type: :string, required: true, description: "The search query"
  parameter :max_results, type: :integer, default: 5

  def call(query:, max_results: 5)
    # return value is serialized and sent back to the LLM
  end
end

class ResearchAgent < SolidAgent::Base
  tool WebSearchTool
end
```

### Invoking Agents

```ruby
# Async (Solid Queue job)
run = ResearchAgent.perform_later("Analyze Q4 market trends")
# => SolidAgent::Trace (queryable, resumable)

# Sync (blocks)
result = ResearchAgent.perform_now("Analyze Q4 market trends")
# => SolidAgent::Result

# Streaming
ResearchAgent.perform_later("Analyze Q4 market trends", stream: true)

# Continue a conversation
trace = SolidAgent::Trace.find(id)
trace.conversation.continue("Now focus on the European market")

# Resume a paused trace
trace.resume
trace.resume(additional_input: "Focus on X")
```

---

## 5. Tool System

### Three-Layer Model

```
Agent's Tool Allowlist
├── Ruby Tools (in-process)
│   #call runs Ruby code directly
│   Defined inline or as standalone classes
│
└── MCP Client Tools (external)
    #call sends JSON-RPC to external MCP server
    Discovered at boot from configured MCP clients
```

Both share the same interface: `name + schema + execute(args)`. The runtime doesn't distinguish between them.

### Tool Schema Format

One universal format (MCP-compatible JSON Schema). The provider layer translates to provider-specific formats at request-build time:

```ruby
# Registry stores ONE format
{
  name: "web_search",
  description: "Search the web",
  inputSchema: {
    type: "object",
    properties: { query: { type: "string" } },
    required: ["query"]
  }
}

# Provider::OpenAi#build_request translates inputSchema → OpenAI tools format
# Provider::Anthropic#build_request translates inputSchema → Anthropic tool format
```

### MCP Client

The framework is an MCP client only. Users run MCP servers externally (Docker, npx, etc.). We connect and discover tools:

```ruby
SolidAgent.configure do |config|
  config.mcp_clients = {
    filesystem: { transport: :stdio, command: "npx", args: [...] },
    github: { transport: :sse, url: "http://localhost:3001/mcp" }
  }
end
```

Client architecture:

```
SolidAgent::MCP::Client
├── manages transport (stdio subprocess or SSE connection)
├── handles JSON-RPC protocol (initialize, tools/list, tools/call)
├── caches tool schemas after discovery
└── wraps MCP tools in SolidAgent::Tool instances (uniform interface)
```

### Tool Execution

```ruby
module SolidAgent::Tool::Base
  def execute(arguments)
    # Ruby tools: call .call(**arguments)
    # MCP tools: send JSON-RPC to server, await response
  end
end
```

### Concurrency

```ruby
class ResearchAgent < SolidAgent::Base
  concurrency 3  # max parallel tool executions per ReAct step
end
```

Runtime takes the tool_calls array from the LLM response and executes up to `concurrency` at a time. `concurrency 1` = sequential (default). Specific tool sequencing constraints are handled via prompting in `instructions`.

### Tool Approval

```ruby
require_approval :write_file, :delete_file
```

When triggered, the run pauses with status `awaiting_approval`. Dashboard surfaces the pending call. Run resumes on approval (or rejects with reason sent back to the LLM).

---

## 6. Agent Runtime — ReAct Loop

Runs inside `SolidAgent::RunJob < ActiveJob::Base` (Solid Queue). Each iteration is a DB transaction — always resumable.

```
START → Run created, input message appended
  │
  ▼
THINK → Build messages + context → call LLM provider
  │
  ▼
EVALUATE → Tool calls or text-only?
  │           │
  │           └── Text only → DONE
  │
  ▼ (has tool_calls)
ACT → Execute tool calls (Ruby or MCP, up to concurrency limit)
    → Append tool results to messages
  │
  ▼
OBSERVE → Check limits:
  ├── Max iterations?     → STOP
  ├── Hard timeout?       → STOP
  ├── Error?              → FAIL (or retry)
  ├── Context near limit? → COMPACT → back to THINK
  └── All clear?          → back to THINK
```

### Trace States

```
pending → running → completed
                 → failed
                 → paused (iteration limit / awaiting human input / awaiting approval)
```

Paused traces can be resumed: `trace.resume` or `trace.resume(additional_input: "...")`.

### Safety Guards

```ruby
max_iterations 25
max_tokens_per_run 100_000
timeout 5.minutes
retry_on SolidAgent::RateLimitError, attempts: 3
```

---

## 7. Memory & Context System

### Memory Strategies (pluggable, per-agent)

```ruby
class ResearchAgent < SolidAgent::Base
  memory :sliding_window, max_messages: 50
  # or
  memory :compaction, max_tokens: 8000
  # or
  memory :full_history
  # or chain them
  memory :sliding_window, max_messages: 30 do |m|
    m.then :compaction, max_tokens: 4000
  end
end
```

### Strategy Interface

```ruby
class SolidAgent::Memory::SlidingWindow < SolidAgent::Memory::Base
  def initialize(max_messages: 50)
  end

  def build_context(messages, system_prompt:)
    # => Array<SolidAgent::Message> ready for the provider
  end

  def compact!(messages)
    # => Array<SolidAgent::Message> reduced context
  end
end
```

Token counts are tracked from LLM response `usage` objects — no estimation. The memory strategy reads the running total and the model's `context_window` to decide when to compact.

### Observational Memory

Agents accumulate knowledge across conversations:

```ruby
class ResearchAgent < SolidAgent::Base
  observational_memory enabled: true, max_entries: 500, retrieval_count: 10
end
```

- After each completed run, agent extracts observations worth remembering
- Stored as `solid_agent_memory_entries` with embeddings
- On next conversation start, relevant entries retrieved via similarity search
- Injected into system prompt as background context

### Vector Store (pluggable)

```ruby
module SolidAgent::VectorStore::Base
  def upsert(id:, embedding:, metadata:)
  def query(embedding:, limit:, threshold:)
  def delete(id:)
end

# Built-in: sqlite-vec (zero config)
# Users can swap in: Pgvector, Qdrant, custom class
# If no vector store configured, observational memory is disabled gracefully
```

---

## 8. Multi-Agent Orchestration

### Two Patterns

```ruby
class ProjectManagerAgent < SolidAgent::Base
  # Pattern 1: Supervisor delegation — spawns separate trace
  delegate :research, to: ResearchAgent, description: "Research a topic"
  delegate :writing, to: WriterAgent, description: "Write content"

  # Pattern 2: Agent-as-tool — runs inline as a tool call
  agent_tool :quick_summary, agent: SummaryAgent, description: "Quick summaries"
end
```

### Supervisor Delegation

The LLM sees delegate tools. When called, the runtime spawns a child trace:

```
Trace #1 (Supervisor)
├── THINK → "Delegate research and competitive analysis"
├── ACT → delegate(:research, query: "Q4 trends")
│   └── Trace #2 (child, parent_trace_id: 1)
│       └── Full independent ReAct loop
├── ACT → delegate(:competitive, query: "competitors")
│   └── Trace #3 (child, parent_trace_id: 1)
├── OBSERVE → both results returned
└── THINK → synthesize final answer
```

Children are full `Trace` records — observable, resumable, dashboard-visible. Parent trace links to children via `parent_trace_id`.

### Agent-as-Tool

Lighter weight. Agent runs within the parent's ReAct loop as a tool call. Logged as a span, not a separate trace.

### Parallel vs Sequential

Controlled by the agent's `concurrency` setting and LLM prompting. When the LLM returns multiple delegate/tool calls in one response, the runtime executes up to `concurrency` in parallel.

```ruby
class ProjectManagerAgent < SolidAgent::Base
  concurrency 3

  instructions <<~PROMPT
    When tasks are independent, invoke multiple tools in the same
    response to run them in parallel. When tasks depend on each
    other, invoke them sequentially.
  PROMPT
end
```

### Error Propagation

```ruby
class ProjectManagerAgent < SolidAgent::Base
  on_delegate_failure :research, strategy: :retry, attempts: 2
  on_delegate_failure :writing, strategy: :report_error
  on_delegate_failure :review, strategy: :fail_parent
end
```

---

## 9. Observability Dashboard

### Mounting

Installed via `bin/rails solid_agent:install`. Mounts at `/solid_agent` by default.

### Pages (Inertia + React, shadcn/ui)

| Route | Purpose |
|-------|---------|
| `/solid_agent` | Overview — active runs, recent traces, token usage summary |
| `/solid_agent/traces` | Trace list — filterable by agent, status, date |
| `/solid_agent/traces/:id` | Trace detail — span tree, timing waterfall, token usage |
| `/solid_agent/traces/:id/spans/:span_id` | Span detail — input/output, tool results |
| `/solid_agent/conversations` | Conversation list |
| `/solid_agent/conversations/:id` | Conversation with all its traces |
| `/solid_agent/agents` | Agent registry — configured agents, tools, models |
| `/solid_agent/tools` | Tool registry — all tools, execution stats |
| `/solid_agent/mcp` | MCP client status — connected servers, discovered tools |

### Trace Detail View

```
Trace #42 — ResearchAgent — completed — 12.3s — 4,521 tokens
│
├── THINK ──── 0.8s ── 842 in / 210 out
│   └── Output: tool_calls: [:web_search]
├── ACT ────── 1.2s
│   └── web_search(query: "Q4 market trends")
│       └── Result: "US GDP grew 3.1%..."
├── THINK ──── 0.6s ── 1,203 in / 180 out
│   └── Output: tool_calls: [:analyze_data]
├── ACT ────── 2.1s
│   └── analyze_data(...)
└── THINK ──── 0.4s ── 956 in / 530 out
    └── Final answer: "Based on the analysis..."
```

Spans are expandable. Parent traces show inline child traces with drill-down links.

### Data Retention

```ruby
config.trace_retention = 30.days  # auto-cleanup via scheduled Solid Queue job
config.trace_retention = :keep_all
```

---

## 10. Data Model

### Conversations

```
solid_agent_conversations
  id                  INTEGER PRIMARY KEY
  agent_class         TEXT
  status              TEXT (active/archived)
  metadata            JSON
  created_at          DATETIME
  updated_at          DATETIME
```

### Traces

```
solid_agent_traces
  id                  INTEGER PRIMARY KEY
  conversation_id     INTEGER (FK)
  parent_trace_id     INTEGER (FK, nullable — for child traces)
  agent_class         TEXT
  trace_type          TEXT (:agent_run/:tool_call/:delegate)
  status              TEXT (pending/running/completed/failed/paused)
  input               TEXT
  output              TEXT
  usage               JSON ({input_tokens, output_tokens, estimated_cost})
  iteration_count     INTEGER
  started_at          DATETIME
  completed_at        DATETIME
  error               TEXT
  metadata            JSON
```

### Spans

```
solid_agent_spans
  id                  INTEGER PRIMARY KEY
  trace_id            INTEGER (FK)
  parent_span_id      INTEGER (FK, nullable)
  span_type           TEXT (:think/:act/:observe/:tool_execution/:llm_call)
  name                TEXT
  status              TEXT
  input               TEXT
  output              TEXT
  tokens_in           INTEGER
  tokens_out          INTEGER
  started_at          DATETIME
  completed_at        DATETIME
  metadata            JSON
```

### Messages

```
solid_agent_messages
  id                  INTEGER PRIMARY KEY
  conversation_id     INTEGER (FK)
  trace_id            INTEGER (FK, nullable)
  role                TEXT (system/user/assistant/tool)
  content             TEXT
  tool_calls          JSON
  tool_call_id        TEXT
  token_count         INTEGER
  model               TEXT
  metadata            JSON
  created_at          DATETIME
```

### Memory Entries

```
solid_agent_memory_entries
  id                  INTEGER PRIMARY KEY
  conversation_id     INTEGER (FK)
  agent_class         TEXT
  entry_type          TEXT (:observation/:fact/:preference)
  content             TEXT
  embedding           BLOB (via sqlite-vec)
  relevance_score     FLOAT
  created_at          DATETIME
```

### Relationships

```
Conversation → has many Traces → each Trace has many Spans
                                    Traces nest via parent_trace_id
                                    Spans nest via parent_span_id
Conversation → has many Messages
Conversation → has many MemoryEntries
```

---

## 11. Key Dependencies

| Dependency | Purpose | Required |
|---|---|---|
| `rails` >= 8.0 | Framework | Yes |
| `solid_queue` | Agent job execution | Yes |
| `solid_cable` | Streaming broadcasts | Yes |
| `sqlite_vec` | Vector similarity (default store) | Optional |
| `inertia_rails` | Dashboard frontend | Yes |
| `react`, `shadcn/ui` | Dashboard UI | Yes (engine bundles) |
| `faraday` | Alternative HTTP adapter | Optional |
| `async` | Alternative HTTP adapter | Optional |

No Redis. No external vector database. No external message broker. SQLite + Solid Queue + Solid Cable handles everything.
