# Getting Started

Add agentic AI capabilities to any Rails 8+ application with Solid Agent.

## Requirements

- Rails 8.0+
- Ruby 3.3+
- Solid Queue
- An LLM provider API key (OpenAI, Anthropic, Google, or Ollama)

## 1. Add the Gem

In your `Gemfile`:

```ruby
gem "solid_agent"
```

Then bundle:

```bash
bundle install
```

## 2. Run the Installer

```bash
bin/rails solid_agent:install
bin/rails db:migrate
```

The installer copies migrations and creates `config/initializers/solid_agent.rb`. Six tables are created: `solid_agent_conversations`, `solid_agent_traces`, `solid_agent_spans`, `solid_agent_messages`, `solid_agent_memory_entries`, and the engine routes are mounted at `/solid_agent`.

## 3. Configure Your Provider

Edit `config/initializers/solid_agent.rb`:

```ruby
SolidAgent.configure do |config|
  config.providers.openai = {
    api_key: ENV["OPENAI_API_KEY"]
  }

  config.trace_retention = 30.days
end
```

For other providers, see the [Providers guide](providers.md).

## 4. Define Your First Agent

Create `app/agents/greeting_agent.rb`:

```ruby
class GreetingAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O_MINI

  instructions <<~PROMPT
    You are a friendly assistant. Answer concisely.
  PROMPT

  tool :current_time, description: "Get the current time" do
    Time.current.strftime("%Y-%m-%d %H:%M:%S %Z")
  end
end
```

The agent class inherits from `SolidAgent::Base`. The DSL methods (`provider`, `model`, `instructions`, `tool`) configure the agent at class load time. See the [Agent DSL reference](agent-dsl.md) for the full API.

## 5. Run It

### Synchronous

Blocks until the ReAct loop finishes. Good for controllers, background jobs, and Rake tasks.

```ruby
result = GreetingAgent.perform_now("What time is it?")

result.completed?  # => true
result.output      # => "The current time is 2026-04-14 10:30:00 UTC"
result.usage.total_tokens  # => 342
result.iterations  # => 2 (one think, one act, one final think)
result.trace_id    # => 42
```

### Asynchronous

Enqueues a Solid Queue job. Returns a `Trace` record immediately.

```ruby
trace = GreetingAgent.perform_later("What time is it?")
# => SolidAgent::Trace (status: pending)

trace.reload.status   # => "running", "completed", etc.
trace.reload.output   # => "The current time is..."
trace.total_tokens    # => 342
trace.spans.count     # => 3
```

### Continuing a Conversation

Pass a `conversation_id` to continue an existing conversation:

```ruby
trace = GreetingAgent.perform_now("What time is it?")
conversation_id = trace.conversation_id

GreetingAgent.perform_now("And what day of the week is that?", conversation_id: conversation_id)
```

## 6. Check the Dashboard

Start your server:

```bash
bin/rails server
```

Navigate to `http://localhost:3000/solid_agent`. The dashboard shows:

- Active and recent traces
- Token usage totals
- Registered agents

From there, drill into individual traces to see the span tree (think/act/observe steps), token breakdown per step, and tool execution results. See the [Observability guide](observability.md) for details.

## 7. Next Steps

- **Add tools.** Define inline tools with the `tool` DSL, or create standalone tool classes. See [Tool System](tool-system.md).
- **Use MCP servers.** Connect to external MCP servers for filesystem access, GitHub, databases, and more. See [Tool System -- MCP Client](tool-system.md#mcp-client).
- **Configure memory.** Choose a memory strategy for long conversations. See [Memory Strategies](memory-strategies.md).
- **Build multi-agent systems.** Use supervisor delegation or agent-as-tool patterns. See [Multi-Agent Orchestration](multi-agent-orchestration.md).
- **Set up approval gates.** Require human approval before certain tools execute. See [Agent DSL -- require_approval](agent-dsl.md#require_approval).
