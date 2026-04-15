# Solid Agent

Zero-config AI agent framework for Rails 8. Build, orchestrate, and observe LLM agents using the Solid stack -- no Redis, no vector database, no message broker.

---

## Features

**Agent Runtime**
- ReAct loop (THINK -> ACT -> OBSERVE) with automatic iteration
- Resumable traces with full span-level observability
- Solid Queue integration for async job execution
- Configurable iteration limits, token budgets, and timeouts

**LLM Providers**
- OpenAI, Anthropic, Google Gemini, Ollama, Mistral
- OpenAI-compatible endpoints (LiteLLM, vLLM, etc.)
- Pluggable HTTP adapters, streaming support, per-model cost tracking

**Memory**
- Sliding window, full history, and LLM-powered compaction
- Chain strategies for composing multiple memory approaches
- Observational memory with vector similarity search (sqlite-vec)
- Cross-conversation experience retention

**Tools**
- Ruby class DSL with typed parameters, required fields, and defaults
- Inline tool definitions with blocks
- MCP client (stdio and SSE transports)
- Concurrent execution, per-tool timeouts, and approval gates

**Orchestration**
- Supervisor pattern with `delegate` for hierarchical agent routing
- Agent-as-tool via `agent_tool` for composable workflows
- Parallel execution with configurable concurrency
- Error propagation strategies: retry, report, or fail

**Dashboard**
- Inertia + React + shadcn/ui observability dashboard
- Trace visualization with span-level detail
- Token usage tracking across conversations
- Agent, tool, and MCP server registries

**Zero Dependencies**
- No Redis, no Sidekiq, no Postgres
- SQLite-backed with Solid Queue and Solid Cable
- Single Docker container deployment via Kamal 2

---

## Installation

Add to your `Gemfile`:

```ruby
gem "solid_agent"
```

Then run:

```bash
bundle install
bin/rails solid_agent:install
bin/rails db:migrate
```

This creates `config/initializers/solid_agent.rb` and runs the necessary migrations.

**Requirements:** Ruby 3.3+, Rails 8.0+, SQLite

---

## Quick Start

### 1. Configure your provider

```ruby
# config/initializers/solid_agent.rb
SolidAgent.configure do |config|
  config.default_provider = :openai
  config.default_model = SolidAgent::Models::OpenAi::GPT_4O

  config.providers[:openai] = {
    api_key: ENV["OPENAI_API_KEY"]
  }
end
```

### 2. Define an agent

```ruby
# app/agents/research_agent.rb
class ResearchAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  temperature 0.3
  max_iterations 15
  timeout 120

  instructions <<~PROMPT
    You are a research assistant. Given a topic, search for relevant
    information using the available tools and provide a concise summary
    with key findings and sources.
  PROMPT

  tool :web_search, description: "Search the web for information about a topic" do |query:|
    "Search results for '#{query}': This is a placeholder. Replace with a real search implementation."
  end

  tool :summarize, description: "Summarize a block of text" do |text:|
    text.squeeze(" ").truncate(200)
  end
end
```

### 3. Run it

```ruby
# Synchronous execution
result = ResearchAgent.perform_now("What are the latest developments in Rails 8?")
result.output        # => "Rails 8 introduced..."
result.completed?    # => true
result.usage         # => #<SolidAgent::Types::Usage input_tokens=450, output_tokens=120>
result.iterations    # => 3
```

### 4. Run asynchronously

```ruby
# Async via Solid Queue -- returns a trace immediately
trace = ResearchAgent.perform_later("Explain Solid Queue internals")
trace.id      # => 1
trace.status  # => "pending"

# Later, check the result:
trace = SolidAgent::Trace.find(trace.id)
trace.status  # => "completed"
trace.output  # => "Solid Queue is..."
trace.total_tokens  # => 890
```

### 5. Continue a conversation

```ruby
# Pass a conversation_id to continue where you left off
trace = ResearchAgent.perform_now("What about Solid Cache?", conversation_id: 1)
```

---

## Agent DSL Reference

### Configuration

```ruby
class MyAgent < SolidAgent::Base
  provider :anthropic
  model SolidAgent::Models::Anthropic::CLAUDE_SONNET_4_5
  temperature 0.7
  max_tokens 8192
  max_iterations 25
  max_tokens_per_run 100_000
  timeout 300
end
```

### Instructions

```ruby
class MyAgent < SolidAgent::Base
  instructions "You are a helpful assistant that speaks concisely."

  # Or a heredoc for longer prompts:
  instructions <<~PROMPT
    You are a code reviewer. Analyze the provided code for:
    - Bugs and security issues
    - Performance problems
    - Style and readability improvements
    Always provide specific line references.
  PROMPT
end
```

### Ruby Tools

**Inline tools** with blocks:

```ruby
class MyAgent < SolidAgent::Base
  tool :calculate, description: "Evaluate a math expression" do |expression:|
    eval(expression)
  end
end
```

**Standalone tool classes:**

```ruby
class WeatherTool < SolidAgent::Tool::Base
  name "get_weather"
  description "Get the current weather for a city"

  parameter :city, type: :string, required: true, description: "City name"
  parameter :units, type: :string, required: false, default: "celsius",
            description: "Temperature units"

  def call(city:, units: "celsius")
    # Fetch weather data...
    "Weather in #{city}: 22#{units == 'celsius' ? 'C' : 'F'}, sunny"
  end
end

class WeatherAgent < SolidAgent::Base
  tool WeatherTool
end
```

### MCP Tools

```ruby
class MyAgent < SolidAgent::Base
  tool :filesystem, description: "File system operations via MCP",
       transport: :stdio, command: "npx", args: ["@anthropic/mcp-filesystem", "/tmp"]
end
```

See the [MCP Client](#mcp-client) section for full configuration details.

### Memory Strategies

```ruby
class MyAgent < SolidAgent::Base
  # Sliding window (default) -- keeps the last N messages
  memory :sliding_window, max_messages: 50

  # Full history -- passes everything to the LLM
  memory :full_history

  # Compaction -- summarizes older messages when context fills up
  memory :compaction, max_tokens: 8000

  # Chain multiple strategies together
  memory SolidAgent::Memory::Chain.new(
    strategies: [
      SolidAgent::Memory::Compaction.new(max_tokens: 6000),
      SolidAgent::Memory::SlidingWindow.new(max_messages: 30)
    ]
  )
end
```

### Safety Guards

```ruby
class MyAgent < SolidAgent::Base
  max_iterations 10
  timeout 60
  max_tokens_per_run 50_000
  retry_on SolidAgent::Error, attempts: 3
end
```

### Callbacks

```ruby
class MyAgent < SolidAgent::Base
  before_invoke :log_start
  after_invoke :log_completion
  on_context_overflow :handle_overflow

  private

  def log_start(input)
    Rails.logger.info("[Agent] Starting with input: #{input}")
  end

  def log_completion(result)
    Rails.logger.info("[Agent] Completed in #{result.iterations} iterations")
  end

  def handle_overflow(messages)
    Rails.logger.warn("[Agent] Context overflow detected")
  end
end
```

### Tool Approval

```ruby
class MyAgent < SolidAgent::Base
  tool :delete_record, description: "Delete a database record" do |table:, id:|
    # Dangerous operation
  end

  tool :read_record, description: "Read a database record" do |table:, id:|
    # Safe operation
  end

  # Require human approval before executing these tools
  require_approval :delete_record
end
```

---

## Running Agents

### Synchronous

```ruby
result = MyAgent.perform_now("Hello")
result.output       # => "Hi! How can I help?"
result.status       # => :completed
result.usage        # => #<SolidAgent::Types::Usage>
result.iterations   # => 1
result.trace_id     # => 42
```

### Asynchronous

```ruby
trace = MyAgent.perform_later("Hello")
# Trace is processed by Solid Queue
trace = SolidAgent::Trace.find(trace.id)
trace.status   # => "completed" | "running" | "failed" | "paused"
trace.output   # => "Hi! How can I help?"
```

### Continuing Conversations

```ruby
# First message
trace1 = MyAgent.perform_now("My name is Alice")

# Continue on the same conversation
trace2 = MyAgent.perform_now("What's my name?", conversation_id: trace1.conversation_id)
# The agent remembers the previous messages
```

### Resuming Paused Traces

```ruby
trace = SolidAgent::Trace.find(42)
trace.pause!

# Later, resume from where it left off
trace.resume!
RunJob.perform_now(
  trace_id: trace.id,
  agent_class_name: trace.agent_class,
  input: trace.input,
  conversation_id: trace.conversation_id
)
```

---

## Multi-Agent Orchestration

### Supervisor with Delegation

```ruby
class SupervisorAgent < SolidAgent::Base
  include SolidAgent::Orchestration::DSL

  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O

  instructions "You are a supervisor. Delegate tasks to the appropriate specialist."

  delegate :research, to: ResearchAgent,
           description: "Search for information and summarize findings"

  delegate :write_code, to: CoderAgent,
           description: "Write or modify code based on specifications"

  delegate :review, to: ReviewerAgent,
           description: "Review code for bugs and improvements"

  on_delegate_failure :research, strategy: :retry, attempts: 3
  on_delegate_failure :review, strategy: :report_error
end
```

### Agent-as-Tool

```ruby
class OrchestratorAgent < SolidAgent::Base
  include SolidAgent::Orchestration::DSL

  instructions "You coordinate multiple agents to solve complex tasks."

  agent_tool :analyzer, agent: AnalysisAgent,
             description: "Analyze data and provide insights"

  agent_tool :writer, agent: WriterAgent,
             description: "Generate reports and documentation"

  tool :save_to_file, description: "Save content to a file" do |path:, content:|
    File.write(path, content)
    "Saved to #{path}"
  end
end
```

### Parallel Execution

```ruby
class ParallelAgent < SolidAgent::Base
  include SolidAgent::Orchestration::DSL

  concurrency 4

  delegate :search_1, to: SearchAgent, description: "Search source A"
  delegate :search_2, to: SearchAgent, description: "Search source B"
  delegate :search_3, to: SearchAgent, description: "Search source C"
  delegate :summarize, to: SummaryAgent, description: "Combine results"
end
```

### Error Propagation Strategies

```ruby
class ResilientSupervisor < SolidAgent::Base
  include SolidAgent::Orchestration::DSL

  # Retry up to 3 times on failure
  on_delegate_failure :flaky_tool, strategy: :retry, attempts: 3

  # Return error message to the LLM instead of crashing
  on_delegate_failure :optional_tool, strategy: :report_error

  # Let the exception propagate (default)
  on_delegate_failure :critical_tool, strategy: :fail_parent
end
```

---

## Memory Strategies

### Sliding Window

Keeps only the most recent messages. Default strategy for all agents.

```ruby
memory :sliding_window, max_messages: 50
```

### Full History

Passes the entire conversation history to the LLM. Works well with large-context models.

```ruby
memory :full_history
```

### Compaction

When context approaches the token limit, older messages are summarized into a single system message.

```ruby
memory :compaction, max_tokens: 8000
```

### Chaining Strategies

Combine multiple strategies in sequence. Each strategy processes the output of the previous one.

```ruby
memory SolidAgent::Memory::Chain.new(
  strategies: [
    SolidAgent::Memory::Compaction.new(max_tokens: 6000),
    SolidAgent::Memory::SlidingWindow.new(max_messages: 30)
  ]
)
```

### Observational Memory

Stores and retrieves cross-conversation knowledge using vector similarity search. Requires `sqlite-vec`.

```ruby
SolidAgent.configure do |config|
  config.vector_store = :sqlite_vec
  config.embedding_provider = :openai
  config.embedding_model = "text-embedding-3-small"
end

# Observations are stored automatically during agent runs and retrieved
# as system context for relevant future queries within the same agent class.
```

---

## MCP Client

### Configuration

MCP servers are configured in the initializer:

```ruby
SolidAgent.configure do |config|
  config.mcp_clients[:filesystem] = {
    transport: :stdio,
    command: "npx",
    args: ["@anthropic/mcp-filesystem", "/tmp"]
  }

  config.mcp_clients[:remote_tools] = {
    transport: :sse,
    url: "http://localhost:3001/mcp"
  }
end
```

### Connecting to MCP Tools in Agents

```ruby
class MyAgent < SolidAgent::Base
  # All tools from the :filesystem MCP server
  tool SolidAgent::Tool::MCP::Client.new(
    name: :filesystem,
    transport: SolidAgent::Tool::MCP::Transport::Stdio.new(
      command: "npx",
      args: ["@anthropic/mcp-filesystem", "/tmp"]
    )
  )

  # After declaration, call discover_tools to load available tools
  # Tools are automatically registered in the agent's tool registry
end
```

### Supported Transports

**stdio** -- Launches an MCP server as a subprocess:

```ruby
SolidAgent::Tool::MCP::Transport::Stdio.new(
  command: "npx",
  args: ["@anthropic/mcp-filesystem", "/tmp"],
  env: { "DEBUG" => "1" }
)
```

**SSE** -- Connects to a remote MCP server over HTTP:

```ruby
SolidAgent::Tool::MCP::Transport::SSE.new(
  url: "http://localhost:3001/mcp"
)
```

---

## Observability Dashboard

### Mounting

The dashboard mounts automatically at `/solid_agent` when `config.dashboard_enabled` is `true` (the default).

To customize the route prefix:

```ruby
SolidAgent.configure do |config|
  config.dashboard_route_prefix = "ai"
end
```

Then mount in your routes:

```ruby
# config/routes.rb
mount SolidAgent::Engine, at: "/ai"
```

### What You'll See

- **Dashboard** -- Overview of recent traces, token usage, and active conversations
- **Traces** -- Full trace history with status, duration, token counts, and iteration counts
- **Trace Detail** -- Span-by-span visualization of each agent run (think, act, observe cycles)
- **Conversations** -- Message history across all conversations
- **Agents** -- Registry of all defined agent classes
- **Tools** -- Registry of all available tools (Ruby + MCP)
- **MCP Status** -- Connected MCP servers and their tool counts

### Trace Retention

```ruby
SolidAgent.configure do |config|
  config.trace_retention = 30.days  # Default
end
```

Traces older than the retention period can be cleaned up via a scheduled Solid Queue job.

---

## Configuration Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `default_provider` | Symbol | `:openai` | Default LLM provider for agents |
| `default_model` | `SolidAgent::Model` | `Models::OpenAi::GPT_4O` | Default model |
| `dashboard_enabled` | Boolean | `true` | Enable the observability dashboard |
| `dashboard_route_prefix` | String | `"solid_agent"` | Route prefix for dashboard |
| `vector_store` | Symbol | `:sqlite_vec` | Vector store backend |
| `embedding_provider` | Symbol | `:openai` | Provider for embeddings |
| `embedding_model` | String | `"text-embedding-3-small"` | Embedding model name |
| `http_adapter` | Symbol | `:net_http` | HTTP adapter for LLM requests |
| `trace_retention` | ActiveSupport::Duration | `30.days` | How long to keep trace data |
| `providers` | Hash | `{}` | Provider-specific configuration (API keys, base URLs, etc.) |
| `mcp_clients` | Hash | `{}` | MCP server configurations |

### Provider Configuration

```ruby
SolidAgent.configure do |config|
  # OpenAI
  config.providers[:openai] = {
    api_key: ENV["OPENAI_API_KEY"]
  }

  # Anthropic
  config.providers[:anthropic] = {
    api_key: ENV["ANTHROPIC_API_KEY"]
  }

  # Google Gemini
  config.providers[:google] = {
    api_key: ENV["GOOGLE_API_KEY"]
  }

  # Ollama (local)
  config.providers[:ollama] = {
    base_url: "http://localhost:11434"
  }

  # OpenAI-compatible (LiteLLM, vLLM, etc.)
  config.providers[:openai_compatible] = {
    api_key: ENV["LLM_API_KEY"],
    base_url: "http://localhost:8000/v1"
  }
end
```

### Available Models

**OpenAI**
- `SolidAgent::Models::OpenAi::GPT_5_4_PRO`
- `SolidAgent::Models::OpenAi::GPT_5_4`
- `SolidAgent::Models::OpenAi::O3_PRO`
- `SolidAgent::Models::OpenAi::O3`
- `SolidAgent::Models::OpenAi::GPT_4O` (default)
- `SolidAgent::Models::OpenAi::GPT_4O_MINI`

**Anthropic**
- `SolidAgent::Models::Anthropic::CLAUDE_OPUS_4_6`
- `SolidAgent::Models::Anthropic::CLAUDE_SONNET_4_6`
- `SolidAgent::Models::Anthropic::CLAUDE_OPUS_4_5`
- `SolidAgent::Models::Anthropic::CLAUDE_SONNET_4_5`
- `SolidAgent::Models::Anthropic::CLAUDE_SONNET_4`
- `SolidAgent::Models::Anthropic::CLAUDE_HAIKU_4_5`

**Google**
- `SolidAgent::Models::Google::GEMINI_2_5_PRO`
- `SolidAgent::Models::Google::GEMINI_2_5_FLASH`
- `SolidAgent::Models::Google::GEMINI_2_5_FLASH_LITE`
- `SolidAgent::Models::Google::GEMINI_2_0_FLASH`

**Ollama**
- `SolidAgent::Models::Ollama::LLAMA_3_3_70B`
- `SolidAgent::Models::Ollama::QWEN_2_5_72B`
- `SolidAgent::Models::Ollama::DEEPSEEK_V3`

**Mistral**
- `SolidAgent::Models::Mistral` (see `lib/solid_agent/models/mistral.rb` for available models)

---

## Deployment

### Kamal 2 (Single Container)

Solid Agent runs entirely on SQLite with Solid Queue. No Redis, no external database, no message broker.

```yaml
# config/deploy.yml
service: my-app
image: my-app

servers:
  web:
    hosts:
      - 192.168.1.1

env:
  clear:
    RAILS_ENV: production
    OPENAI_API_KEY: "${OPENAI_API_KEY}"
  secret:
    - RAILS_MASTER_KEY

traefik:
  options:
    docker:
      composeFile: "config/docker-compose.yml"

hooks:
  post deploy:
    - bundle exec rails solid_agent:install:migrations
    - bundle exec rails db:migrate
    - bundle exec rails solid_queue:start
```

### Data Sovereignty

All data stays in SQLite on your infrastructure. No telemetry, no external data stores. LLM API calls go directly to your configured provider.

### SQLite in Production

Solid Agent is designed for SQLite from the ground up:

- Solid Queue handles background job processing
- `sqlite-vec` provides vector similarity search for memory
- WAL mode enables concurrent reads during writes
- Single-file database simplifies backups and migration

**Important:** When using SQLite, Solid Queue must run in async mode to avoid database locking. Add to `config/puma.rb`:

```ruby
plugin :solid_queue
solid_queue_mode :async
```

And set a generous busy timeout in `config/database.yml`:

```yaml
default: &default
  adapter: sqlite3
  database: db/development.sqlite3
  busy_timeout: 30000
```

For PostgreSQL or MySQL, use the default fork mode with `bin/rails solid_queue:start` as a separate process.

---

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b my-feature`)
3. Run tests (`bin/rails test`)
4. Commit your changes (`git commit -am 'Add feature'`)
5. Push to the branch (`git push origin my-feature`)
6. Open a Pull Request

## License

Released under the [MIT License](https://opensource.org/licenses/MIT).
