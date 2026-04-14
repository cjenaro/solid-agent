# Plan 4: Tool System

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the unified tool system with Ruby tool definitions, MCP client integration, tool registry, and execution engine with concurrency control and approval gates.

**Architecture:** Tools share one universal interface (`name + JSON Schema + execute(args)`). Ruby tools run in-process. MCP tools are discovered from external servers via JSON-RPC. The registry stores tools in one MCP-compatible format; providers translate at request time. Execution engine handles concurrency limits, timeouts, and human-in-the-loop approval.

**Tech Stack:** Ruby 3.3+, Rails 8.0+, JSON-RPC, Minitest

---

## File Structure

```
lib/solid_agent/
├── tool/
│   ├── base.rb
│   ├── inline_tool.rb
│   ├── registry.rb
│   ├── schema.rb
│   ├── execution_engine.rb
│   └── mcp/
│       ├── client.rb
│       ├── transport/
│       │   ├── base.rb
│       │   ├── stdio.rb
│       │   └── sse.rb
│       └── mcp_tool.rb

test/
├── tool/
│   ├── base_test.rb
│   ├── inline_tool_test.rb
│   ├── registry_test.rb
│   ├── schema_test.rb
│   ├── execution_engine_test.rb
│   └── mcp/
│       ├── client_test.rb
│       ├── stdio_transport_test.rb
│       └── mcp_tool_test.rb
```

---

### Task 1: Tool Schema

**Files:**
- Create: `lib/solid_agent/tool/schema.rb`
- Test: `test/tool/schema_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/tool/schema_test.rb
require "test_helper"
require "solid_agent/tool/schema"

class ToolSchemaTest < ActiveSupport::TestCase
  test "creates schema from hash" do
    schema = SolidAgent::Tool::Schema.new(
      name: "web_search",
      description: "Search the web",
      input_schema: {
        type: "object",
        properties: { query: { type: "string" } },
        required: ["query"]
      }
    )
    assert_equal "web_search", schema.name
    assert_equal "Search the web", schema.description
    assert_equal "string", schema.input_schema[:properties][:query][:type]
  end

  test "to_hash returns MCP-compatible format" do
    schema = SolidAgent::Tool::Schema.new(
      name: "search",
      description: "Search",
      input_schema: { type: "object", properties: { q: { type: "string" } } }
    )
    h = schema.to_hash
    assert_equal "search", h[:name]
    assert_equal "Search", h[:description]
    assert h.key?(:inputSchema)
  end

  test "validates required fields" do
    assert_raises(ArgumentError) do
      SolidAgent::Tool::Schema.new(name: nil, description: "test", input_schema: {})
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/tool/schema_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement Schema**

```ruby
# lib/solid_agent/tool/schema.rb
module SolidAgent
  module Tool
    class Schema
      attr_reader :name, :description, :input_schema

      def initialize(name:, description:, input_schema:)
        raise ArgumentError, "name is required" if name.nil?
        @name = name.to_s
        @description = description.to_s
        @input_schema = input_schema
        freeze
      end

      def to_hash
        {
          name: name,
          description: description,
          inputSchema: input_schema
        }
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/tool/schema_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Tool::Schema with MCP-compatible format"
```

---

### Task 2: Tool::Base (Standalone Tool Class)

**Files:**
- Create: `lib/solid_agent/tool/base.rb`
- Test: `test/tool/base_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/tool/base_test.rb
require "test_helper"
require "solid_agent/tool/base"

class WebSearchTool < SolidAgent::Tool::Base
  name :web_search
  description "Search the web for information"

  parameter :query, type: :string, required: true, description: "Search query"
  parameter :max_results, type: :integer, default: 5, description: "Max results"

  def call(query:, max_results: 5)
    "Results for: #{query} (max #{max_results})"
  end
end

class ToolBaseTest < ActiveSupport::TestCase
  test "tool has name" do
    assert_equal "web_search", WebSearchTool.tool_name
  end

  test "tool has description" do
    assert_equal "Search the web for information", WebSearchTool.tool_description
  end

  test "tool has parameters" do
    params = WebSearchTool.tool_parameters
    assert_equal 2, params.length
    query_param = params.find { |p| p[:name] == :query }
    assert_equal :string, query_param[:type]
    assert query_param[:required]
  end

  test "tool generates JSON Schema from parameters" do
    schema = WebSearchTool.to_schema
    assert_instance_of SolidAgent::Tool::Schema, schema
    assert_equal "web_search", schema.name
    assert_equal "string", schema.input_schema[:properties][:query][:type]
    assert_includes schema.input_schema[:required], "query"
  end

  test "tool execute calls the call method" do
    tool = WebSearchTool.new
    result = tool.execute({ "query" => "test search" })
    assert_equal "Results for: test search (max 5)", result
  end

  test "tool execute uses defaults for missing optional params" do
    tool = WebSearchTool.new
    result = tool.execute({ "query" => "test" })
    assert_includes result, "max 5"
  end

  test "tool execute raises on missing required params" do
    tool = WebSearchTool.new
    assert_raises(ArgumentError) { tool.execute({}) }
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/tool/base_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement Tool::Base**

```ruby
# lib/solid_agent/tool/base.rb
require "solid_agent/tool/schema"

module SolidAgent
  module Tool
    class Base
      class << self
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@tool_parameters, [])
        end

        def name(tool_name)
          @tool_name = tool_name.to_s
        end

        def description(desc)
          @tool_description = desc
        end

        def parameter(param_name, type:, required: false, default: nil, description: nil)
          @tool_parameters ||= []
          @tool_parameters << {
            name: param_name,
            type: type,
            required: required,
            default: default,
            description: description
          }
        end

        def tool_name
          @tool_name
        end

        def tool_description
          @tool_description
        end

        def tool_parameters
          @tool_parameters || []
        end

        def to_schema
          properties = {}
          required = []

          tool_parameters.each do |param|
            properties[param[:name]] = {
              type: param[:type].to_s,
              description: param[:description]
            }.compact
            required << param[:name].to_s if param[:required]
          end

          Schema.new(
            name: tool_name,
            description: tool_description,
            input_schema: {
              type: "object",
              properties: properties,
              required: required
            }
          )
        end
      end

      def execute(arguments)
        symbolized = arguments.transform_keys(&:to_sym)
        validate_required!(symbolized)
        apply_defaults!(symbolized)
        call(**symbolized)
      end
    end

    private

    def validate_required!(arguments)
      self.class.tool_parameters.select { |p| p[:required] }.each do |param|
        unless arguments.key?(param[:name])
          raise ArgumentError, "Missing required parameter: #{param[:name]}"
        end
      end
    end

    def apply_defaults!(arguments)
      self.class.tool_parameters.each do |param|
        if !arguments.key?(param[:name]) && !param[:default].nil?
          arguments[param[:name]] = param[:default]
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/tool/base_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Tool::Base with DSL for standalone tools"
```

---

### Task 3: Inline Tool

**Files:**
- Create: `lib/solid_agent/tool/inline_tool.rb`
- Test: `test/tool/inline_tool_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/tool/inline_tool_test.rb
require "test_helper"
require "solid_agent/tool/inline_tool"

class InlineToolTest < ActiveSupport::TestCase
  test "creates inline tool from block" do
    tool = SolidAgent::Tool::InlineTool.new(
      name: :greet,
      description: "Say hello",
      parameters: [{ name: :name, type: :string, required: true, description: "Person name" }],
      block: proc { |name:| "Hello, #{name}!" }
    )
    assert_equal "greet", tool.schema.name
    assert_equal "Hello, World!", tool.execute({ "name" => "World" })
  end

  test "generates schema from parameters" do
    tool = SolidAgent::Tool::InlineTool.new(
      name: :add,
      description: "Add numbers",
      parameters: [
        { name: :a, type: :integer, required: true },
        { name: :b, type: :integer, required: true }
      ],
      block: proc { |a:, b:| a + b }
    )
    schema = tool.schema
    assert_equal "add", schema.name
    assert_equal 2, schema.input_schema[:required].length
  end

  test "inline tool without parameters" do
    tool = SolidAgent::Tool::InlineTool.new(
      name: :ping,
      description: "Ping",
      parameters: [],
      block: proc { "pong" }
    )
    assert_equal "pong", tool.execute({})
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/tool/inline_tool_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement InlineTool**

```ruby
# lib/solid_agent/tool/inline_tool.rb
require "solid_agent/tool/schema"

module SolidAgent
  module Tool
    class InlineTool
      attr_reader :schema

      def initialize(name:, description:, parameters:, block:)
        @block = block
        @defaults = {}
        @required_keys = []

        properties = {}
        required = []
        parameters.each do |param|
          properties[param[:name]] = { type: param[:type].to_s, description: param[:description] }.compact
          required << param[:name].to_s if param[:required]
          @defaults[param[:name]] = param[:default] if param.key?(:default) && !param[:default].nil?
          @required_keys << param[:name] if param[:required]
        end

        @schema = Schema.new(
          name: name.to_s,
          description: description,
          input_schema: {
            type: "object",
            properties: properties,
            required: required
          }
        )
      end

      def execute(arguments)
        symbolized = arguments.transform_keys(&:to_sym)
        @required_keys.each do |key|
          raise ArgumentError, "Missing required parameter: #{key}" unless symbolized.key?(key)
        end
        @defaults.each { |k, v| symbolized[k] ||= v }
        @block.call(**symbolized)
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/tool/inline_tool_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add InlineTool for block-based tool definitions"
```

---

### Task 4: Tool Registry

**Files:**
- Create: `lib/solid_agent/tool/registry.rb`
- Test: `test/tool/registry_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/tool/registry_test.rb
require "test_helper"
require "solid_agent/tool/registry"
require "solid_agent/tool/base"
require "solid_agent/tool/inline_tool"

class RegistrySearchTool < SolidAgent::Tool::Base
  name :search
  description "Search"
  parameter :query, type: :string, required: true

  def call(query:)
    "found: #{query}"
  end
end

class ToolRegistryTest < ActiveSupport::TestCase
  def setup
    @registry = SolidAgent::Tool::Registry.new
  end

  test "register a standalone tool class" do
    @registry.register(RegistrySearchTool)
    assert @registry.registered?("search")
  end

  test "register an inline tool" do
    tool = SolidAgent::Tool::InlineTool.new(
      name: :calc, description: "Calculate", parameters: [],
      block: proc { 42 }
    )
    @registry.register(tool)
    assert @registry.registered?("calc")
  end

  test "lookup returns tool instance" do
    @registry.register(RegistrySearchTool)
    tool = @registry.lookup("search")
    assert_instance_of RegistrySearchTool, tool
  end

  test "lookup raises for unknown tool" do
    assert_raises(SolidAgent::Error) { @registry.lookup("nonexistent") }
  end

  test "all_schemas returns array of schemas" do
    @registry.register(RegistrySearchTool)
    inline = SolidAgent::Tool::InlineTool.new(
      name: :ping, description: "Ping", parameters: [], block: proc { "pong" }
    )
    @registry.register(inline)
    schemas = @registry.all_schemas
    assert_equal 2, schemas.length
    assert_instance_of SolidAgent::Tool::Schema, schemas.first
  end

  test "all_schemas_hashes returns MCP-compatible hashes" do
    @registry.register(RegistrySearchTool)
    hashes = @registry.all_schemas_hashes
    assert_equal 1, hashes.length
    assert hashes.first.key?(:inputSchema)
  end

  test "tool_count" do
    assert_equal 0, @registry.tool_count
    @registry.register(RegistrySearchTool)
    assert_equal 1, @registry.tool_count
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/tool/registry_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement Registry**

```ruby
# lib/solid_agent/tool/registry.rb
module SolidAgent
  module Tool
    class Registry
      def initialize
        @tools = {}
      end

      def register(tool_or_class)
        case tool_or_class
        when Class
          instance = tool_or_class.new
          schema = tool_or_class.to_schema
          @tools[schema.name] = { instance: instance, schema: schema }
        when InlineTool
          @tools[tool_or_class.schema.name] = { instance: tool_or_class, schema: tool_or_class.schema }
        else
          raise Error, "Cannot register tool of type: #{tool_or_class.class}"
        end
      end

      def lookup(name)
        entry = @tools[name.to_s]
        raise Error, "Tool not found: #{name}" unless entry
        entry[:instance]
      end

      def registered?(name)
        @tools.key?(name.to_s)
      end

      def all_schemas
        @tools.values.map { |e| e[:schema] }
      end

      def all_schemas_hashes
        all_schemas.map(&:to_hash)
      end

      def tool_count
        @tools.size
      end

      def tool_names
        @tools.keys
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/tool/registry_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Tool::Registry with schema resolution"
```

---

### Task 5: MCP Client — Transport Layer

**Files:**
- Create: `lib/solid_agent/tool/mcp/transport/base.rb`
- Create: `lib/solid_agent/tool/mcp/transport/stdio.rb`
- Test: `test/tool/mcp/stdio_transport_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/tool/mcp/stdio_transport_test.rb
require "test_helper"
require "solid_agent/tool/mcp/transport/stdio"

class StdioTransportTest < ActiveSupport::TestCase
  test "initializes with command and args" do
    transport = SolidAgent::Tool::MCP::Transport::Stdio.new(
      command: "echo",
      args: ["hello"]
    )
    assert_equal "echo", transport.command
    assert_equal ["hello"], transport.args
  end

  test "sends JSON-RPC request and reads response via echo" do
    transport = SolidAgent::Tool::MCP::Transport::Stdio.new(
      command: "cat"
    )
    request = { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }
    response = transport.send_and_receive(request)
    parsed = JSON.parse(response)
    assert_equal "2.0", parsed["jsonrpc"]
    assert_equal 1, parsed["id"]
  end

  test "handles missing command" do
    transport = SolidAgent::Tool::MCP::Transport::Stdio.new(
      command: "nonexistent_command_12345"
    )
    assert_raises(SolidAgent::Error) { transport.send_and_receive({}) }
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/tool/mcp/stdio_transport_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement transport base**

```ruby
# lib/solid_agent/tool/mcp/transport/base.rb
module SolidAgent
  module Tool
    module MCP
      module Transport
        class Base
          def send_and_receive(request)
            raise NotImplementedError
          end

          def close
            raise NotImplementedError
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Implement stdio transport**

```ruby
# lib/solid_agent/tool/mcp/transport/stdio.rb
require "json"
require "open3"
require "solid_agent/tool/mcp/transport/base"

module SolidAgent
  module Tool
    module MCP
      module Transport
        class Stdio < Base
          attr_reader :command, :args, :env

          def initialize(command:, args: [], env: {})
            @command = command
            @args = args
            @env = env
            @stdin = nil
            @stdout = nil
            @stderr = nil
            @wait_thr = nil
          end

          def connect
            return if @stdin
            @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(@env, @command, *@args)
          end

          def send_and_receive(request)
            connect
            json_str = JSON.generate(request)
            @stdin.puts(json_str)
            @stdin.flush

            response_line = @stdout.gets
            raise Error, "MCP server closed connection" unless response_line

            response_line.strip
          end

          def close
            @stdin&.close
            @stdout&.close
            @stderr&.close
            @wait_thr&.kill
            @stdin = @stdout = @stderr = @wait_thr = nil
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/tool/mcp/stdio_transport_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add MCP stdio transport"
```

---

### Task 6: MCP Client

**Files:**
- Create: `lib/solid_agent/tool/mcp/client.rb`
- Create: `lib/solid_agent/tool/mcp/mcp_tool.rb`
- Test: `test/tool/mcp/client_test.rb`
- Test: `test/tool/mcp/mcp_tool_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/tool/mcp/client_test.rb
require "test_helper"
require "solid_agent/tool/mcp/client"

class EchoMCPTransport < SolidAgent::Tool::MCP::Transport::Base
  def initialize(responses = {})
    @responses = responses
  end

  def send_and_receive(request)
    method = request[:method]
    response = @responses[method]
    JSON.generate({
      jsonrpc: "2.0",
      id: request[:id],
      result: response
    })
  end

  def close; end
end

class MCPClientTest < ActiveSupport::TestCase
  test "initializes and discovers tools" do
    transport = EchoMCPTransport.new({
      "initialize" => { capabilities: { tools: {} } },
      "tools/list" => {
        tools: [
          { name: "read_file", description: "Read a file", inputSchema: { type: "object", properties: { path: { type: "string" } } } }
        ]
      }
    })
    client = SolidAgent::Tool::MCP::Client.new(name: :filesystem, transport: transport)
    client.initialize!
    tools = client.discover_tools
    assert_equal 1, tools.length
    assert_equal "read_file", tools.first.schema.name
  end

  test "calls a tool via JSON-RPC" do
    transport = EchoMCPTransport.new({
      "initialize" => { capabilities: {} },
      "tools/list" => { tools: [] },
      "tools/call" => { content: [{ type: "text", text: "file contents" }] }
    })
    client = SolidAgent::Tool::MCP::Client.new(name: :test, transport: transport)
    client.initialize!
    result = client.call_tool("read_file", { "path" => "/tmp/test.txt" })
    assert_equal({ "content" => [{ "type" => "text", "text" => "file contents" }] }, result)
  end
end
```

```ruby
# test/tool/mcp/mcp_tool_test.rb
require "test_helper"
require "solid_agent/tool/mcp/mcp_tool"

class FakeClient
  def call_tool(name, arguments)
    "result from #{name}: #{arguments}"
  end
end

class MCPToolTest < ActiveSupport::TestCase
  test "delegates execute to MCP client" do
    schema = SolidAgent::Tool::Schema.new(
      name: "read_file",
      description: "Read a file",
      input_schema: { type: "object", properties: { path: { type: "string" } } }
    )
    tool = SolidAgent::Tool::MCP::McpTool.new(schema: schema, client: FakeClient.new)
    result = tool.execute({ "path" => "/tmp/test.txt" })
    assert_equal "result from read_file: {\"path\"=>\"/tmp/test.txt\"}", result
  end

  test "exposes schema" do
    schema = SolidAgent::Tool::Schema.new(
      name: "write_file",
      description: "Write a file",
      input_schema: { type: "object", properties: { path: { type: "string" }, content: { type: "string" } } }
    )
    tool = SolidAgent::Tool::MCP::McpTool.new(schema: schema, client: FakeClient.new)
    assert_equal "write_file", tool.schema.name
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/tool/mcp/ -v`
Expected: FAIL

- [ ] **Step 3: Implement MCP Client**

```ruby
# lib/solid_agent/tool/mcp/client.rb
require "json"

module SolidAgent
  module Tool
    module MCP
      class Client
        attr_reader :name, :tools

        def initialize(name:, transport:)
          @name = name
          @transport = transport
          @tools = []
          @id_counter = 0
          @initialized = false
        end

        def initialize!
          return if @initialized
          send_request("initialize", {
            protocolVersion: "2024-11-05",
            capabilities: {},
            clientInfo: { name: "solid_agent", version: "0.1.0" }
          })
          @initialized = true
        end

        def discover_tools
          response = send_request("tools/list", {})
          @tools = (response[:tools] || []).map do |tool_def|
            schema = Schema.new(
              name: tool_def["name"],
              description: tool_def["description"] || "",
              input_schema: tool_def["inputSchema"] || { type: "object", properties: {} }
            )
            McpTool.new(schema: schema, client: self)
          end
          @tools
        end

        def call_tool(name, arguments)
          send_request("tools/call", { name: name, arguments: arguments })
        end

        def close
          @transport.close
        end

        private

        def send_request(method, params)
          request = {
            jsonrpc: "2.0",
            id: next_id,
            method: method,
            params: params
          }
          raw = @transport.send_and_receive(request)
          data = JSON.parse(raw, symbolize_names: false)
          if data["error"]
            raise Error, "MCP error: #{data["error"]["message"]}"
          end
          data["result"].is_a?(Hash) ? data["result"].transform_keys(&:to_sym) : data["result"]
        end

        def next_id
          @id_counter += 1
        end
      end
    end
  end
end
```

- [ ] **Step 4: Implement MCP Tool adapter**

```ruby
# lib/solid_agent/tool/mcp/mcp_tool.rb
module SolidAgent
  module Tool
    module MCP
      class McpTool
        attr_reader :schema

        def initialize(schema:, client:)
          @schema = schema
          @client = client
        end

        def execute(arguments)
          @client.call_tool(schema.name, arguments)
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/tool/mcp/ -v`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add MCP client and MCP tool adapter"
```

---

### Task 7: Execution Engine

**Files:**
- Create: `lib/solid_agent/tool/execution_engine.rb`
- Test: `test/tool/execution_engine_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/tool/execution_engine_test.rb
require "test_helper"
require "solid_agent/tool/execution_engine"
require "solid_agent/tool/inline_tool"

class ExecutionEngineTest < ActiveSupport::TestCase
  def setup
    @registry = SolidAgent::Tool::Registry.new
    @registry.register(SolidAgent::Tool::InlineTool.new(
      name: :fast_tool, description: "Fast", parameters: [],
      block: proc { "fast_result" }
    ))
    @registry.register(SolidAgent::Tool::InlineTool.new(
      name: :slow_tool, description: "Slow", parameters: [],
      block: proc { sleep 0.1; "slow_result" }
    ))
    @registry.register(SolidAgent::Tool::InlineTool.new(
      name: :error_tool, description: "Errors", parameters: [],
      block: proc { raise "tool error" }
    ))
    @registry.register(SolidAgent::Tool::InlineTool.new(
      name: :add, description: "Add", parameters: [
        { name: :a, type: :integer, required: true },
        { name: :b, type: :integer, required: true }
      ],
      block: proc { |a:, b:| a + b }
    ))
  end

  test "executes single tool call" do
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: @registry, concurrency: 1)
    results = engine.execute_all([
      SolidAgent::ToolCall.new(id: "c1", name: "fast_tool", arguments: {})
    ])
    assert_equal 1, results.length
    assert_equal "fast_result", results["c1"]
  end

  test "executes multiple tool calls sequentially with concurrency 1" do
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: @registry, concurrency: 1)
    results = engine.execute_all([
      SolidAgent::ToolCall.new(id: "c1", name: "fast_tool", arguments: {}),
      SolidAgent::ToolCall.new(id: "c2", name: "fast_tool", arguments: {})
    ])
    assert_equal 2, results.length
    assert_equal "fast_result", results["c1"]
    assert_equal "fast_result", results["c2"]
  end

  test "executes tool calls in parallel with concurrency > 1" do
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: @registry, concurrency: 3)
    start = Time.now
    results = engine.execute_all([
      SolidAgent::ToolCall.new(id: "c1", name: "slow_tool", arguments: {}),
      SolidAgent::ToolCall.new(id: "c2", name: "slow_tool", arguments: {}),
      SolidAgent::ToolCall.new(id: "c3", name: "slow_tool", arguments: {})
    ])
    elapsed = Time.now - start
    assert_equal 3, results.length
    assert elapsed < 0.35, "Parallel execution should be faster than sequential (was #{elapsed}s)"
  end

  test "captures tool errors" do
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: @registry, concurrency: 1)
    results = engine.execute_all([
      SolidAgent::ToolCall.new(id: "c1", name: "error_tool", arguments: {})
    ])
    assert_instance_of SolidAgent::Tool::ExecutionEngine::ToolExecutionError, results["c1"]
  end

  test "executes tool with arguments" do
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: @registry, concurrency: 1)
    results = engine.execute_all([
      SolidAgent::ToolCall.new(id: "c1", name: "add", arguments: { "a" => 3, "b" => 4 })
    ])
    assert_equal 7, results["c1"]
  end

  test "respects timeout" do
    @registry.register(SolidAgent::Tool::InlineTool.new(
      name: :timeout_tool, description: "Timeout", parameters: [],
      block: proc { sleep 10; "done" }
    ))
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: @registry, concurrency: 1, timeout: 0.1)
    results = engine.execute_all([
      SolidAgent::ToolCall.new(id: "c1", name: "timeout_tool", arguments: {})
    ])
    assert_instance_of SolidAgent::Tool::ExecutionEngine::ToolExecutionError, results["c1"]
  end

  test "requires approval for flagged tools" do
    engine = SolidAgent::Tool::ExecutionEngine.new(
      registry: @registry, concurrency: 1,
      approval_required: ["fast_tool"]
    )
    results = engine.execute_all([
      SolidAgent::ToolCall.new(id: "c1", name: "fast_tool", arguments: {})
    ])
    assert_instance_of SolidAgent::Tool::ExecutionEngine::ApprovalRequired, results["c1"]
  end

  test "approved tool executes normally" do
    engine = SolidAgent::Tool::ExecutionEngine.new(
      registry: @registry, concurrency: 1,
      approval_required: ["fast_tool"]
    )
    engine.approve("c1")
    results = engine.execute_all([
      SolidAgent::ToolCall.new(id: "c1", name: "fast_tool", arguments: {})
    ])
    assert_equal "fast_result", results["c1"]
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/tool/execution_engine_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement ExecutionEngine**

```ruby
# lib/solid_agent/tool/execution_engine.rb
require "timeout"

module SolidAgent
  module Tool
    class ExecutionEngine
      class ToolExecutionError
        attr_reader :message

        def initialize(message)
          @message = message
        end

        def to_s
          @message
        end
      end

      class ApprovalRequired
        attr_reader :tool_name, :tool_call_id, :arguments

        def initialize(tool_name:, tool_call_id:, arguments:)
          @tool_name = tool_name
          @tool_call_id = tool_call_id
          @arguments = arguments
        end

        def to_s
          "Approval required for tool: #{@tool_name}"
        end
      end

      def initialize(registry:, concurrency: 1, timeout: 30, approval_required: [])
        @registry = registry
        @concurrency = concurrency
        @timeout = timeout
        @approval_required = approval_required.map(&:to_s)
        @approved = Set.new
      end

      def approve(tool_call_id)
        @approved.add(tool_call_id)
      end

      def reject(tool_call_id, reason = "Rejected")
        @rejected ||= {}
        @rejected[tool_call_id] = reason
      end

      def execute_all(tool_calls)
        results = {}

        tool_calls.each_slice(@concurrency) do |batch|
          threads = batch.map do |tc|
            Thread.new(tc) do |tool_call|
              results[tool_call.id] = execute_one(tool_call)
            end
          end
          threads.each(&:join)
        end

        results
      end

      private

      def execute_one(tool_call)
        if @rejected&.key?(tool_call.id)
          return ToolExecutionError.new(@rejected[tool_call.id])
        end

        if @approval_required.include?(tool_call.name) && !@approved.include?(tool_call.id)
          return ApprovalRequired.new(
            tool_name: tool_call.name,
            tool_call_id: tool_call.id,
            arguments: tool_call.arguments
          )
        end

        tool = @registry.lookup(tool_call.name)
        Timeout.timeout(@timeout) do
          tool.execute(tool_call.arguments)
        end
      rescue Timeout::Error
        ToolExecutionError.new("Tool '#{tool_call.name}' timed out after #{@timeout}s")
      rescue => e
        ToolExecutionError.new("Tool '#{tool_call.name}' error: #{e.message}")
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/tool/execution_engine_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Tool::ExecutionEngine with concurrency, timeout, and approval"
```

---

### Task 8: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rake test`
Expected: All tests PASS, 0 failures

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "chore: tool system plan complete"
```
