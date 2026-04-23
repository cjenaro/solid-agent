# Agent DSL

Complete reference for defining agents with `SolidAgent::Base`.

## Class-Level Configuration

```ruby
class MyAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  max_tokens 4096
  temperature 0.7

  instructions <<~PROMPT
    You are a helpful assistant.
  PROMPT
end
```

### `provider(name)`

Sets the LLM provider. Accepts a symbol: `:openai`, `:anthropic`, `:google`, `:ollama`, `:openai_compatible`. Must match a key in `SolidAgent.configuration.providers`. Defaults to `:openai`.

### `model(model_const)`

Sets the model. Pass a `SolidAgent::Model` constant (e.g., `SolidAgent::Models::OpenAi::GPT_4O`). The model's `context_window` and `max_output` are used by the memory and runtime layers. Defaults to `SolidAgent::Models::OpenAi::GPT_4O`.

### `max_tokens(tokens)`

Maximum tokens the provider should generate per response. Defaults to `4096`.

### `temperature(temp)`

Sampling temperature. Defaults to `0.7`.

### `instructions(text)`

System prompt. Prepend to every message context sent to the LLM. Supports heredocs for multi-line prompts.

## Tool Definition

### Vision / Image Input

Agents accept image inputs alongside text. Use a vision-capable model and pass a hash to `perform_now` or `perform_later`:

```ruby
class ImageAnalyzer < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O

  instructions <<~PROMPT
    You analyze images. Describe what you see in detail.
  PROMPT
end

# By URL
result = ImageAnalyzer.perform_now({
  text: "What is in this image?",
  image_url: "https://example.com/photo.jpg"
})

# By base64
require "base64"
data = Base64.strict_encode64(File.read("screenshot.png"))

result = ImageAnalyzer.perform_now({
  text: "Describe this screenshot",
  image_data: { data: data, media_type: "image/png" }
})
```

String input remains fully backward compatible. See [Providers -- Vision](providers.md#vision--multimodal-support) for provider-specific details.

### Inline Tools

Define tools directly in the agent class with a block:

```ruby
class MyAgent < SolidAgent::Base
  tool :search, description: "Search the database for records" do |query:, limit: 10|
    Record.where("name ILIKE ?", "%#{query}%").limit(limit).map(&:to_h)
  end

  tool :calculate, description: "Run a calculation" do |expression:|
    eval(expression)
  end
end
```

The block receives keyword arguments matching the tool's parameters. The return value is serialized to a string and sent back to the LLM as a tool result message.

### Standalone Tool Classes

For reusable tools shared across agents:

```ruby
class WebSearchTool < SolidAgent::Tool::Base
  name :web_search
  description "Search the web for information"

  parameter :query, type: :string, required: true, description: "The search query"
  parameter :max_results, type: :integer, default: 5, description: "Max results to return"

  def call(query:, max_results: 5)
    # ... perform search ...
    results.map(&:to_h).to_json
  end
end
```

Register in the agent:

```ruby
class MyAgent < SolidAgent::Base
  tool WebSearchTool
end
```

Standalone tools validate required parameters and apply defaults automatically. See [Tool System](tool-system.md) for the full tool class API.

### MCP Tool Allowlisting

Use `mcp_tool` to expose specific tools from a configured MCP client:

```ruby
class MyAgent < SolidAgent::Base
  mcp_tool :read_file, from: :filesystem
  mcp_tool :list_directory, from: :filesystem
end
```

This makes the MCP server's `read_file` and `list_directory` tools available to this agent. The MCP client named `:filesystem` must be configured in `SolidAgent.configure`. See [Tool System -- MCP Client](tool-system.md#mcp-client).

## Memory Strategy Configuration

```ruby
class MyAgent < SolidAgent::Base
  memory :sliding_window, max_messages: 50
end
```

Available strategies: `:sliding_window`, `:compaction`, `:full_history`. See [Memory Strategies](memory-strategies.md) for details and chaining.

### Observational Memory

Agents can accumulate knowledge across conversations:

```ruby
class MyAgent < SolidAgent::Base
  observational_memory enabled: true, max_entries: 500, retrieval_count: 10
end
```

See [Memory Strategies -- Observational Memory](memory-strategies.md#observational-memory) for full details.

## Concurrency

```ruby
class MyAgent < SolidAgent::Base
  concurrency 3
end
```

Controls how many tool calls the runtime executes in parallel within a single ReAct step. Defaults to `1` (sequential). When the LLM returns multiple tool calls in one response, the runtime batches them into groups of `concurrency` and runs each group via threads.

## Safety Guards

```ruby
class MyAgent < SolidAgent::Base
  max_iterations 25
  max_tokens_per_run 100_000
  timeout 5.minutes
  retry_on SolidAgent::RateLimitError, attempts: 3
end
```

| Method | Default | Description |
|---|---|---|
| `max_iterations(n)` | 25 | Maximum ReAct loop iterations before stopping |
| `max_tokens_per_run(n)` | 100,000 | Accumulated token budget across the entire run |
| `timeout(duration)` | 300 seconds | Wall-clock time limit for the entire run |
| `retry_on(error, attempts:)` | nil | Auto-retry on specific error classes |

The runtime checks these limits at the top of every iteration via `React::Observer`. When a limit is hit, the trace completes with the current output.

`max_tokens_per_run` is tracked from actual LLM response `usage` objects -- not estimated. The observer also triggers compaction when token usage reaches 85% of the model's context window.

## Callbacks

```ruby
class MyAgent < SolidAgent::Base
  before_invoke :validate_input
  after_invoke :log_completion
  on_context_overflow :compact_memory
end
```

| Callback | When |
|---|---|
| `before_invoke(method)` | Before the agent run starts |
| `after_invoke(method)` | After the agent run completes |
| `on_context_overflow(method)` | When context tokens approach the window limit |

Callback methods should be instance methods on the agent class. The `on_context_overflow` callback is invoked before the memory strategy's `compact!` method, giving you a chance to take custom action.

## require_approval

```ruby
class MyAgent < SolidAgent::Base
  tool :delete_record, description: "Delete a database record" do |id:|
    Record.find(id).destroy
  end

  require_approval :delete_record
end
```

When the LLM invokes a tool on the approval list, the runtime returns an `ApprovalRequired` sentinel instead of executing the tool. The trace pauses and the dashboard surfaces the pending approval. Call `execution_engine.approve(tool_call_id)` or `execution_engine.reject(tool_call_id, reason)` to resume.

Multiple tools can be listed:

```ruby
require_approval :delete_record, :send_email, :write_file
```

## Real-World Patterns

### Multi-Tool Agent

```ruby
class CustomerSupportAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O

  instructions <<~PROMPT
    You are a customer support agent. Use the available tools to look up
    customer information, check order status, and create support tickets.
    Always verify the customer's identity before sharing order details.
  PROMPT

  tool :lookup_customer, description: "Find a customer by email" do |email:|
    Customer.find_by(email: email)&.as_json(only: %i[id name email plan])
  end

  tool :get_order, description: "Get order details by ID" do |order_id:|
    order = Order.find(order_id)
    { id: order.id, status: order.status, total: order.total_cents / 100.0,
      created_at: order.created_at }.to_json
  end

  tool :create_ticket, description: "Create a support ticket" do |subject:, description:, customer_id:|
    ticket = Ticket.create!(customer_id: customer_id, subject: subject, description: description)
    { ticket_id: ticket.id, status: ticket.status }.to_json
  end

  tool WebSearchTool

  concurrency 2
  max_iterations 15
  timeout 3.minutes
end
```

### Agent with Chained Memory and Approval

```ruby
class CodeReviewAgent < SolidAgent::Base
  provider :anthropic
  model SolidAgent::Models::Anthropic::CLAUDE_SONNET_4

  instructions <<~PROMPT
    You are a senior code reviewer. Analyze code for bugs, performance
    issues, and style problems. Be specific about line numbers and
    suggest fixes.
  PROMPT

  memory :sliding_window, max_messages: 30 do |m|
    m.then :compaction, max_tokens: 4000
  end

  tool :read_file, description: "Read file contents" do |path:|
    File.read(path) if File.exist?(path)
  end

  tool :write_file, description: "Write changes to a file" do |path:, content:|
    File.write(path, content)
    "Wrote #{content.lines.count} lines to #{path}"
  end

  require_approval :write_file

  max_iterations 20
  timeout 10.minutes
end
```
