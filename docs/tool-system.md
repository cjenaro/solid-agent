# Tool System

Tools give agents the ability to take action. Solid Agent supports Ruby tools (defined inline or as standalone classes) and MCP tools (external processes). Both share the same uniform interface.

## Ruby Tools

### Inline Definition

Define tools directly in the agent class:

```ruby
class MyAgent < SolidAgent::Base
  tool :get_weather, description: "Get the current weather for a city" do |city:|
    WeatherService.current(city).to_json
  end

  tool :create_record, description: "Create a database record" do |table:, attributes:|
    klass = table.classify.constantize
    klass.create!(JSON.parse(attributes)).as_json
  end
end
```

The block receives keyword arguments. Return values are serialized to strings and sent back to the LLM as tool result messages.

**Limitation:** Inline tools do not support declared parameters with types or defaults. The block signature is the only interface. If you need parameter validation, use a standalone class.

### Standalone Tool Classes

For reusable, validated tools:

```ruby
class DatabaseQueryTool < SolidAgent::Tool::Base
  name :db_query
  description "Execute a read-only SQL query against the application database"

  parameter :sql, type: :string, required: true, description: "SQL query to execute (SELECT only)"

  def call(sql:)
    raise ArgumentError, "Only SELECT queries are allowed" unless sql.strip.match?(/^SELECT/i)

    result = ActiveRecord::Base.connection.exec_query(sql)
    result.to_a.first(50).to_json
  end
end
```

Register in the agent:

```ruby
class MyAgent < SolidAgent::Base
  tool DatabaseQueryTool
end
```

### Parameter DSL

The `parameter` class method defines the tool's input schema:

```ruby
class SearchTool < SolidAgent::Tool::Base
  name :search
  description "Search records"

  parameter :query,      type: :string,  required: true,  description: "Search query"
  parameter :scope,      type: :string,  required: false, description: "Scope to search within"
  parameter :limit,      type: :integer, default: 10,     description: "Max results"
  parameter :order,      type: :string,  default: "desc", description: "Sort order"
  parameter :exact_match, type: :boolean, default: false,  description: "Use exact matching"

  def call(query:, scope: nil, limit: 10, order: "desc", exact_match: false)
    # ...
  end
end
```

| Option | Description |
|---|---|
| `type:` | JSON Schema type: `:string`, `:integer`, `:boolean`, `:number`, `:array`, `:object` |
| `required:` | If `true`, `execute` raises `ArgumentError` when missing |
| `default:` | Applied when the argument is not provided |
| `description:` | Included in the schema sent to the LLM |

`execute` handles validation automatically: it checks required parameters, applies defaults, and symbolizes keys before calling `call`.

## Tool Schema Format

Tools are stored as `SolidAgent::Tool::Schema` objects with a single, MCP-compatible JSON Schema format:

```ruby
{
  name: "search",
  description: "Search records",
  inputSchema: {
    type: "object",
    properties: {
      query: { type: "string", description: "Search query" },
      limit: { type: "integer", description: "Max results" }
    },
    required: ["query"]
  }
}
```

Each provider translates this to its own format at request-build time:

- **OpenAI**: wraps in `{ type: "function", function: { name:, description:, parameters: } }`
- **Anthropic**: uses `{ name:, description:, input_schema: }` directly
- **Google**: wraps in `{ functionDeclarations: [{ name:, description:, parameters: }] }`

You write one schema. The provider layer handles translation.

## Tool Registry

Each agent has its own `Tool::Registry` instance:

```ruby
class MyAgent < SolidAgent::Base
  tool :inline_tool, description: "An inline tool" do |x:|
    x * 2
  end

  tool StandaloneTool
end
```

The registry stores tools keyed by name:

```ruby
registry = MyAgent.agent_tool_registry
registry.registered?(:inline_tool)   # => true
registry.registered?(:standalone_tool) # => true
registry.lookup(:inline_tool)        # => #<InlineTool>
registry.all_schemas                 # => [#<Schema>, #<Schema>]
registry.all_schemas_hashes          # => [{ name:, description:, inputSchema: }, ...]
registry.tool_names                  # => ["inline_tool", "standalone_tool"]
```

## Execution Engine

The `Tool::ExecutionEngine` receives tool calls from the LLM response and executes them:

```ruby
engine = SolidAgent::Tool::ExecutionEngine.new(
  registry: agent.agent_tool_registry,
  concurrency: agent.agent_concurrency,
  approval_required: agent.agent_approval_required
)
results = engine.execute_all(tool_calls)
# => { "call_abc123" => "result string", "call_def456" => "result string" }
```

### Concurrency

Tool calls are batched by the concurrency limit and executed in parallel via threads:

```ruby
# concurrency 3, 5 tool calls returned by LLM
# Batch 1: calls 1, 2, 3 (parallel threads)
# Batch 2: calls 4, 5 (parallel threads)
```

Each thread checks out its own ActiveRecord connection via `ActiveRecord::Base.connection_pool.with_connection`.

### Timeout

Each tool call has a 30-second timeout by default. Exceeding it returns a `ToolExecutionError`:

```
"Tool 'db_query' timed out after 30s"
```

The timeout is configurable:

```ruby
SolidAgent::Tool::ExecutionEngine.new(
  registry: registry,
  timeout: 60  # seconds
)
```

### Approval Gates

Tools on the `require_approval` list are intercepted:

```ruby
engine = SolidAgent::Tool::ExecutionEngine.new(
  registry: registry,
  approval_required: ["delete_record", "send_email"]
)

results = engine.execute_all(tool_calls)
# For an approval-required tool:
# results["call_abc"] => #<ApprovalRequired tool_name: "delete_record", ...>
```

The trace pauses. Use `approve` and `reject` to resume:

```ruby
engine.approve("call_abc")
engine.reject("call_def", "Deletion not authorized for this record")
```

### Error Handling

All exceptions from tool execution are caught and returned as `ToolExecutionError` objects. The error message is sent back to the LLM as the tool result, allowing the LLM to decide how to proceed:

```
"Tool 'db_query' error: Table 'missing_table' does not exist"
```

## MCP Client

MCP (Model Context Protocol) servers provide external tools. Solid Agent connects as a client.

### Configuration

```ruby
SolidAgent.configure do |config|
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
end
```

### Transport Types

**Stdio** -- launches a subprocess and communicates over stdin/stdout. The process is started lazily on the first request.

```ruby
{
  transport: :stdio,
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/path"],
  env: { "DEBUG" => "1" }  # optional environment variables
}
```

**SSE** -- connects to an HTTP server endpoint.

```ruby
{
  transport: :sse,
  url: "http://localhost:3001/mcp",
  headers: { "Authorization" => "Bearer token" }
}
```

### Discovering Tools

At boot time (or on first use), the MCP client sends `tools/list` to discover available tools:

```ruby
client = SolidAgent::Tool::MCP::Client.new(
  name: :filesystem,
  transport: SolidAgent::Tool::MCP::Transport::Stdio.new(
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
  )
)

client.initialize!
tools = client.discover_tools
# => [#<McpTool name="read_file", ...>, #<McpTool name="list_directory", ...>]
```

Discovered tools are wrapped in `McpTool` instances, which implement the same `execute(arguments)` interface as Ruby tools. The MCP client caches the tool list after discovery.

### MCP Tools in Agents

Allowlist specific MCP tools per agent using `mcp_tool`:

```ruby
class MyAgent < SolidAgent::Base
  mcp_tool :read_file, from: :filesystem
  mcp_tool :list_directory, from: :filesystem
  mcp_tool :search_repositories, from: :github
end
```

## Writing a Custom Tool: Complete Example

A tool with input validation, error handling, and structured output:

```ruby
class EmailSenderTool < SolidAgent::Tool::Base
  name :send_email
  description "Send an email to a recipient"

  parameter :to,           type: :string, required: true,  description: "Recipient email address"
  parameter :subject,      type: :string, required: true,  description: "Email subject line"
  parameter :body,         type: :string, required: true,  description: "Email body (plain text)"
  parameter :cc,           type: :string, required: false, description: "CC recipients (comma-separated)"
  parameter :high_priority, type: :boolean, default: false, description: "Mark as high priority"

  def call(to:, subject:, body:, cc: nil, high_priority: false)
    validate_email!(to)
    validate_email!(cc) if cc

    mailer = ApplicationMailer.custom_email(
      to: to,
      subject: subject,
      body: body,
      cc: cc,
      high_priority: high_priority
    )

    mailer.deliver_now

    {
      status: "sent",
      to: to,
      message_id: mailer.message_id
    }.to_json
  rescue ActiveRecord::RecordNotFound => e
    { status: "error", message: e.message }.to_json
  end

  private

  def validate_email!(address)
    return unless address

    address.split(",").each do |addr|
      unless addr.strip.match?(/\A[^@\s]+@[^@\s]+\z/)
        raise ArgumentError, "Invalid email address: #{addr}"
      end
    end
  end
end
```

Register in the agent with approval:

```ruby
class SupportAgent < SolidAgent::Base
  tool EmailSenderTool
  require_approval :send_email
end
```
