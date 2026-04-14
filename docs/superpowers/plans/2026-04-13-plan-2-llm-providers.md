# Plan 2: LLM Providers

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pluggable LLM provider layer with HTTP adapter abstraction, unified internal types, and provider implementations for OpenAI, Anthropic, Google, Ollama, and OpenAI-compatible endpoints.

**Architecture:** Providers never touch HTTP directly. They produce `Request` structs and consume `Response` structs via a pluggable adapter interface. Each provider translates between its API's format and our internal types (Message, Response, StreamChunk, ToolCall, Usage). One universal tool schema (MCP-compatible JSON Schema) is translated to each provider's tool format at request-build time.

**Tech Stack:** Ruby 3.3+, Rails 8.0+, net/http, json, Minitest

---

## File Structure

```
lib/solid_agent/
├── http/
│   ├── request.rb
│   ├── response.rb
│   ├── net_http_adapter.rb
│   └── adapters.rb
├── types/
│   ├── message.rb
│   ├── response.rb
│   ├── stream_chunk.rb
│   ├── tool_call.rb
│   └── usage.rb
├── provider/
│   ├── base.rb
│   ├── registry.rb
│   ├── errors.rb
│   ├── openai.rb
│   ├── anthropic.rb
│   ├── google.rb
│   ├── ollama.rb
│   └── openai_compatible.rb
├── model.rb          # already exists, needs pricing support
└── models/           # already exists, needs updating with latest models
    ├── open_ai.rb
    ├── anthropic.rb
    ├── google.rb
    ├── mistral.rb
    └── ollama.rb

test/
├── http/
│   ├── net_http_adapter_test.rb
│   └── request_response_test.rb
├── types/
│   ├── message_test.rb
│   ├── response_test.rb
│   ├── stream_chunk_test.rb
│   ├── tool_call_test.rb
│   └── usage_test.rb
├── provider/
│   ├── base_test.rb
│   ├── registry_test.rb
│   ├── openai_test.rb
│   ├── anthropic_test.rb
│   ├── google_test.rb
│   ├── ollama_test.rb
│   └── openai_compatible_test.rb
```

---

### Task 1: HTTP Request & Response Structs

**Files:**
- Create: `lib/solid_agent/http/request.rb`
- Create: `lib/solid_agent/http/response.rb`
- Test: `test/http/request_response_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/http/request_response_test.rb
require "test_helper"

class HttpRequestResponseTest < ActiveSupport::TestCase
  test "Request struct has all fields" do
    request = SolidAgent::HTTP::Request.new(
      method: :post,
      url: "https://api.openai.com/v1/chat/completions",
      headers: { "Authorization" => "Bearer test" },
      body: '{"model":"gpt-4o"}',
      stream: false
    )
    assert_equal :post, request.method
    assert_equal "https://api.openai.com/v1/chat/completions", request.url
    assert_equal({ "Authorization" => "Bearer test" }, request.headers)
    assert_equal '{"model":"gpt-4o"}', request.body
    assert_equal false, request.stream
  end

  test "Response struct has all fields" do
    response = SolidAgent::HTTP::Response.new(
      status: 200,
      headers: { "content-type" => "application/json" },
      body: '{"id":"chatcmpl-123"}',
      error: nil
    )
    assert_equal 200, response.status
    assert_equal '{"id":"chatcmpl-123"}', response.body
    assert_nil response.error
  end

  test "Response success predicate" do
    success = SolidAgent::HTTP::Response.new(status: 200, headers: {}, body: "", error: nil)
    assert success.success?

    client_error = SolidAgent::HTTP::Response.new(status: 400, headers: {}, body: "", error: "bad request")
    assert_not client_error.success?

    server_error = SolidAgent::HTTP::Response.new(status: 500, headers: {}, body: "", error: "internal")
    assert_not server_error.success?
  end

  test "Response parses JSON body" do
    response = SolidAgent::HTTP::Response.new(
      status: 200,
      headers: {},
      body: '{"key": "value"}',
      error: nil
    )
    assert_equal({ "key" => "value" }, response.json)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/http/request_response_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement Request**

```ruby
# lib/solid_agent/http/request.rb
module SolidAgent
  module HTTP
    Request = Struct.new(:method, :url, :headers, :body, :stream, keyword_init: true)
  end
end
```

- [ ] **Step 4: Implement Response**

```ruby
# lib/solid_agent/http/response.rb
require "json"

module SolidAgent
  module HTTP
    Response = Struct.new(:status, :headers, :body, :error, keyword_init: true) do
      def success?
        status.between?(200, 299) && error.nil?
      end

      def json
        JSON.parse(body)
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/http/request_response_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add HTTP Request and Response structs"
```

---

### Task 2: HTTP Adapter Interface & NetHttpAdapter

**Files:**
- Create: `lib/solid_agent/http/net_http_adapter.rb`
- Create: `lib/solid_agent/http/adapters.rb`
- Test: `test/http/net_http_adapter_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/http/net_http_adapter_test.rb
require "test_helper"
require "solid_agent/http/net_http_adapter"

class NetHttpAdapterTest < ActiveSupport::TestCase
  def setup
    @adapter = SolidAgent::HTTP::NetHttpAdapter.new
  end

  test "implements call method" do
    assert @adapter.respond_to?(:call)
  end

  test "makes successful HTTP request" do
    request = SolidAgent::HTTP::Request.new(
      method: :get,
      url: "https://httpbin.org/get",
      headers: {},
      body: nil,
      stream: false
    )
    response = @adapter.call(request)
    assert response.success?
    assert_equal 200, response.status
  end

  test "makes POST request with body" do
    request = SolidAgent::HTTP::Request.new(
      method: :post,
      url: "https://httpbin.org/post",
      headers: { "Content-Type" => "application/json" },
      body: '{"test": true}',
      stream: false
    )
    response = @adapter.call(request)
    assert response.success?
    parsed = response.json
    assert_equal '{"test": true}', parsed["data"]
  end

  test "handles connection errors" do
    request = SolidAgent::HTTP::Request.new(
      method: :get,
      url: "https://this-domain-does-not-exist-12345.com",
      headers: {},
      body: nil,
      stream: false
    )
    response = @adapter.call(request)
    assert_not response.success?
    assert response.error
  end

  test "sets streaming header when stream is true" do
    request = SolidAgent::HTTP::Request.new(
      method: :post,
      url: "https://httpbin.org/post",
      headers: { "Content-Type" => "application/json" },
      body: '{}',
      stream: true
    )
    response = @adapter.call(request)
    assert response.success?
    parsed = response.json
    assert parsed["headers"].key?("X-Stream")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/http/net_http_adapter_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement NetHttpAdapter**

```ruby
# lib/solid_agent/http/net_http_adapter.rb
require "net/http"
require "uri"
require "json"

module SolidAgent
  module HTTP
    class NetHttpAdapter
      def call(request)
        uri = URI.parse(request.url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 120
        http.open_timeout = 30

        net_request = build_request(uri, request)
        apply_headers(net_request, request)

        if request.stream
          net_request["X-Stream"] = "true"
        end

        response = http.request(net_request)

        if response.is_a?(Net::HTTPSuccess)
          Response.new(status: response.code.to_i, headers: response.each_header.to_h, body: response.body, error: nil)
        else
          Response.new(status: response.code.to_i, headers: {}, body: response.body, error: "HTTP #{response.code}: #{response.message}")
        end
      rescue => e
        Response.new(status: 0, headers: {}, body: nil, error: e.message)
      end

      private

      def build_request(uri, request)
        case request.method
        when :get
          Net::HTTP::Get.new(uri.request_uri)
        when :post
          Net::HTTP::Post.new(uri.request_uri).tap do |req|
            req.body = request.body
          end
        when :put
          Net::HTTP::Put.new(uri.request_uri).tap do |req|
            req.body = request.body
          end
        when :delete
          Net::HTTP::Delete.new(uri.request_uri)
        else
          raise ArgumentError, "Unsupported HTTP method: #{request.method}"
        end
      end

      def apply_headers(net_request, request)
        request.headers.each do |key, value|
          net_request[key] = value
        end
      end
    end
  end
end
```

- [ ] **Step 4: Implement adapter registry**

```ruby
# lib/solid_agent/http/adapters.rb
module SolidAgent
  module HTTP
    module Adapters
      BUILT_IN = {
        net_http: "SolidAgent::HTTP::NetHttpAdapter"
      }.freeze

      def self.resolve(adapter)
        case adapter
        when Symbol
          klass_name = BUILT_IN[adapter]
          raise Error, "Unknown HTTP adapter: #{adapter}" unless klass_name
          klass_name.constantize.new
        when Class
          adapter.new
        when nil
          NetHttpAdapter.new
        else
          adapter
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/http/net_http_adapter_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add NetHttpAdapter and adapter registry"
```

---

### Task 3: Internal Types

**Files:**
- Create: `lib/solid_agent/types/message.rb`
- Create: `lib/solid_agent/types/response.rb`
- Create: `lib/solid_agent/types/stream_chunk.rb`
- Create: `lib/solid_agent/types/tool_call.rb`
- Create: `lib/solid_agent/types/usage.rb`
- Test: `test/types/message_test.rb`
- Test: `test/types/response_test.rb`
- Test: `test/types/stream_chunk_test.rb`
- Test: `test/types/tool_call_test.rb`
- Test: `test/types/usage_test.rb`

- [ ] **Step 1: Write failing tests for all types**

```ruby
# test/types/message_test.rb
require "test_helper"

class TypesMessageTest < ActiveSupport::TestCase
  test "creates user message" do
    msg = SolidAgent::Message.new(role: "user", content: "Hello")
    assert_equal "user", msg.role
    assert_equal "Hello", msg.content
  end

  test "creates assistant message with tool calls" do
    tool_call = SolidAgent::ToolCall.new(id: "call_1", name: "search", arguments: { "query" => "test" })
    msg = SolidAgent::Message.new(role: "assistant", content: nil, tool_calls: [tool_call])
    assert_equal "assistant", msg.role
    assert_equal 1, msg.tool_calls.length
  end

  test "creates tool result message" do
    msg = SolidAgent::Message.new(role: "tool", content: "result text", tool_call_id: "call_1")
    assert_equal "tool", msg.role
    assert_equal "call_1", msg.tool_call_id
  end

  test "message is immutable" do
    msg = SolidAgent::Message.new(role: "user", content: "Hello")
    assert msg.frozen?
  end

  test "to_hash serializes for provider" do
    msg = SolidAgent::Message.new(role: "user", content: "Hello")
    hash = msg.to_hash
    assert_equal "user", hash[:role]
    assert_equal "Hello", hash[:content]
  end

  test "to_hash omits nil fields" do
    msg = SolidAgent::Message.new(role: "user", content: "Hello")
    hash = msg.to_hash
    assert_not hash.key?(:tool_calls)
    assert_not hash.key?(:tool_call_id)
  end
end
```

```ruby
# test/types/response_test.rb
require "test_helper"

class TypesResponseTest < ActiveSupport::TestCase
  test "creates response with message" do
    msg = SolidAgent::Message.new(role: "assistant", content: "Hi there")
    resp = SolidAgent::Response.new(
      messages: [msg],
      tool_calls: [],
      usage: SolidAgent::Usage.new(input_tokens: 10, output_tokens: 5),
      finish_reason: "stop"
    )
    assert_equal 1, resp.messages.length
    assert_equal "stop", resp.finish_reason
  end

  test "response with tool calls" do
    tool_call = SolidAgent::ToolCall.new(id: "call_1", name: "search", arguments: { "q" => "test" })
    msg = SolidAgent::Message.new(role: "assistant", content: nil, tool_calls: [tool_call])
    resp = SolidAgent::Response.new(
      messages: [msg],
      tool_calls: [tool_call],
      usage: SolidAgent::Usage.new(input_tokens: 50, output_tokens: 20),
      finish_reason: "tool_calls"
    )
    assert_equal 1, resp.tool_calls.length
    assert_equal "tool_calls", resp.finish_reason
  end

  test "has_tool_calls predicate" do
    tool_call = SolidAgent::ToolCall.new(id: "call_1", name: "search", arguments: {})
    resp_with = SolidAgent::Response.new(messages: [], tool_calls: [tool_call], usage: nil, finish_reason: "tool_calls")
    assert resp_with.has_tool_calls?

    resp_without = SolidAgent::Response.new(messages: [], tool_calls: [], usage: nil, finish_reason: "stop")
    assert_not resp_without.has_tool_calls?
  end
end
```

```ruby
# test/types/stream_chunk_test.rb
require "test_helper"

class TypesStreamChunkTest < ActiveSupport::TestCase
  test "creates text delta chunk" do
    chunk = SolidAgent::StreamChunk.new(delta_content: "Hello", delta_tool_calls: [], usage: nil, done: false)
    assert_equal "Hello", chunk.delta_content
    assert_not chunk.done?
  end

  test "creates tool call delta chunk" do
    chunk = SolidAgent::StreamChunk.new(
      delta_content: nil,
      delta_tool_calls: [{ "index" => 0, "id" => "call_1", "name" => "search" }],
      usage: nil,
      done: false
    )
    assert_equal 1, chunk.delta_tool_calls.length
  end

  test "creates done chunk" do
    chunk = SolidAgent::StreamChunk.new(
      delta_content: nil,
      delta_tool_calls: [],
      usage: SolidAgent::Usage.new(input_tokens: 100, output_tokens: 50),
      done: true
    )
    assert chunk.done?
    assert_equal 150, chunk.usage.total_tokens
  end
end
```

```ruby
# test/types/tool_call_test.rb
require "test_helper"

class TypesToolCallTest < ActiveSupport::TestCase
  test "creates tool call" do
    tc = SolidAgent::ToolCall.new(id: "call_1", name: "web_search", arguments: { "query" => "test" }, call_index: 0)
    assert_equal "call_1", tc.id
    assert_equal "web_search", tc.name
    assert_equal({ "query" => "test" }, tc.arguments)
    assert_equal 0, tc.call_index
  end

  test "tool call is immutable" do
    tc = SolidAgent::ToolCall.new(id: "call_1", name: "search", arguments: {})
    assert tc.frozen?
  end
end
```

```ruby
# test/types/usage_test.rb
require "test_helper"

class TypesUsageTest < ActiveSupport::TestCase
  test "creates usage" do
    usage = SolidAgent::Usage.new(input_tokens: 100, output_tokens: 50)
    assert_equal 100, usage.input_tokens
    assert_equal 50, usage.output_tokens
    assert_equal 150, usage.total_tokens
  end

  test "computes cost from pricing" do
    usage = SolidAgent::Usage.new(
      input_tokens: 1_000_000,
      output_tokens: 500_000,
      input_price_per_million: 2.50,
      output_price_per_million: 10.00
    )
    assert_in_delta 7.50, usage.cost, 0.01
  end

  test "cost is zero without pricing" do
    usage = SolidAgent::Usage.new(input_tokens: 1000, output_tokens: 500)
    assert_in_delta 0.0, usage.cost, 0.001
  end

  test "adds two usages together" do
    a = SolidAgent::Usage.new(input_tokens: 100, output_tokens: 50)
    b = SolidAgent::Usage.new(input_tokens: 200, output_tokens: 75)
    combined = a + b
    assert_equal 300, combined.input_tokens
    assert_equal 125, combined.output_tokens
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/types/ -v`
Expected: FAIL — types not defined

- [ ] **Step 3: Implement Message**

```ruby
# lib/solid_agent/types/message.rb
module SolidAgent
  class Message
    attr_reader :role, :content, :tool_calls, :tool_call_id, :metadata

    def initialize(role:, content:, tool_calls: nil, tool_call_id: nil, metadata: {})
      @role = role
      @content = content
      @tool_calls = tool_calls
      @tool_call_id = tool_call_id
      @metadata = metadata
      freeze
    end

    def to_hash
      h = { role: role }
      h[:content] = content if content
      h[:tool_calls] = tool_calls.map(&:to_hash) if tool_calls && !tool_calls.empty?
      h[:tool_call_id] = tool_call_id if tool_call_id
      h[:metadata] = metadata if metadata && !metadata.empty?
      h
    end
  end
end
```

- [ ] **Step 4: Implement ToolCall**

```ruby
# lib/solid_agent/types/tool_call.rb
module SolidAgent
  class ToolCall
    attr_reader :id, :name, :arguments, :call_index

    def initialize(id:, name:, arguments:, call_index: 0)
      @id = id
      @name = name
      @arguments = arguments
      @call_index = call_index
      freeze
    end

    def to_hash
      { id: id, name: name, arguments: arguments, call_index: call_index }
    end
  end
end
```

- [ ] **Step 5: Implement Usage**

```ruby
# lib/solid_agent/types/usage.rb
module SolidAgent
  class Usage
    attr_reader :input_tokens, :output_tokens, :input_price_per_million, :output_price_per_million

    def initialize(input_tokens:, output_tokens:, input_price_per_million: 0, output_price_per_million: 0)
      @input_tokens = input_tokens
      @output_tokens = output_tokens
      @input_price_per_million = input_price_per_million
      @output_price_per_million = output_price_per_million
    end

    def total_tokens
      input_tokens + output_tokens
    end

    def cost
      (input_tokens * input_price_per_million / 1_000_000.0) +
        (output_tokens * output_price_per_million / 1_000_000.0)
    end

    def +(other)
      Usage.new(
        input_tokens: input_tokens + other.input_tokens,
        output_tokens: output_tokens + other.output_tokens,
        input_price_per_million: input_price_per_million,
        output_price_per_million: output_price_per_million
      )
    end
  end
end
```

- [ ] **Step 6: Implement Response**

```ruby
# lib/solid_agent/types/response.rb
module SolidAgent
  class Response
    attr_reader :messages, :tool_calls, :usage, :finish_reason

    def initialize(messages:, tool_calls:, usage:, finish_reason:)
      @messages = messages
      @tool_calls = tool_calls
      @usage = usage
      @finish_reason = finish_reason
    end

    def has_tool_calls?
      !tool_calls.nil? && !tool_calls.empty?
    end
  end
end
```

- [ ] **Step 7: Implement StreamChunk**

```ruby
# lib/solid_agent/types/stream_chunk.rb
module SolidAgent
  class StreamChunk
    attr_reader :delta_content, :delta_tool_calls, :usage

    def initialize(delta_content:, delta_tool_calls:, usage:, done:)
      @delta_content = delta_content
      @delta_tool_calls = delta_tool_calls
      @usage = usage
      @done = done
    end

    def done?
      @done
    end
  end
end
```

- [ ] **Step 8: Add requires to solid_agent.rb**

Append to `lib/solid_agent.rb`:

```ruby
require "solid_agent/http/request"
require "solid_agent/http/response"
require "solid_agent/http/net_http_adapter"
require "solid_agent/http/adapters"
require "solid_agent/types/tool_call"
require "solid_agent/types/usage"
require "solid_agent/types/message"
require "solid_agent/types/response"
require "solid_agent/types/stream_chunk"
require "solid_agent/provider/errors"
require "solid_agent/provider/base"
require "solid_agent/provider/registry"
```

- [ ] **Step 9: Run all type tests**

Run: `bundle exec ruby -Itest test/types/ -v`
Expected: All tests PASS

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: add internal types (Message, Response, StreamChunk, ToolCall, Usage)"
```

---

### Task 4: Provider Errors

**Files:**
- Create: `lib/solid_agent/provider/errors.rb`
- Test: `test/provider/errors_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/provider/errors_test.rb
require "test_helper"

class ProviderErrorsTest < ActiveSupport::TestCase
  test "ProviderError is base error" do
    assert SolidAgent::ProviderError < StandardError
  end

  test "RateLimitError inherits ProviderError" do
    assert SolidAgent::RateLimitError < SolidAgent::ProviderError
    error = SolidAgent::RateLimitError.new("Rate limited", retry_after: 30)
    assert_equal 30, error.retry_after
  end

  test "ContextLengthError inherits ProviderError" do
    assert SolidAgent::ContextLengthError < SolidAgent::ProviderError
    error = SolidAgent::ContextLengthError.new("Context too long", tokens_over: 5000)
    assert_equal 5000, error.tokens_over
  end

  test "ProviderTimeoutError inherits ProviderError" do
    assert SolidAgent::ProviderTimeoutError < SolidAgent::ProviderError
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/provider/errors_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement errors**

```ruby
# lib/solid_agent/provider/errors.rb
module SolidAgent
  class ProviderError < Error
  end

  class RateLimitError < ProviderError
    attr_reader :retry_after

    def initialize(message = "Rate limited", retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end

  class ContextLengthError < ProviderError
    attr_reader :tokens_over

    def initialize(message = "Context length exceeded", tokens_over: 0)
      super(message)
      @tokens_over = tokens_over
    end
  end

  class ProviderTimeoutError < ProviderError
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/provider/errors_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add provider error hierarchy"
```

---

### Task 5: Provider Base Module

**Files:**
- Create: `lib/solid_agent/provider/base.rb`
- Create: `lib/solid_agent/provider/registry.rb`
- Test: `test/provider/base_test.rb`
- Test: `test/provider/registry_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/provider/base_test.rb
require "test_helper"

class ProviderBaseTest < ActiveSupport::TestCase
  class TestProvider
    include SolidAgent::Provider::Base

    def initialize(api_key:, default_model:)
      @api_key = api_key
      @default_model = default_model
    end

    def build_request(messages:, tools:, stream:, model:, options: {})
      SolidAgent::HTTP::Request.new(
        method: :post,
        url: "https://api.test.com/v1/chat",
        headers: { "Authorization" => "Bearer #{@api_key}" },
        body: JSON.generate({ messages: messages.map(&:to_hash), model: model.to_s }),
        stream: stream
      )
    end

    def parse_response(raw_response)
      data = raw_response.json
      SolidAgent::Response.new(
        messages: [SolidAgent::Message.new(role: "assistant", content: data.dig("choices", 0, "message", "content"))],
        tool_calls: [],
        usage: SolidAgent::Usage.new(input_tokens: data.dig("usage", "prompt_tokens") || 0, output_tokens: data.dig("usage", "completion_tokens") || 0),
        finish_reason: data.dig("choices", 0, "finish_reason")
      )
    end

    def parse_stream_chunk(chunk)
      SolidAgent::StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil, done: true)
    end

    def parse_tool_call(raw_tool_call)
      SolidAgent::ToolCall.new(id: raw_tool_call["id"], name: raw_tool_call["name"], arguments: raw_tool_call["arguments"])
    end
  end

  test "provider implements required interface" do
    provider = TestProvider.new(api_key: "test", default_model: "test-model")
    assert provider.respond_to?(:build_request)
    assert provider.respond_to?(:parse_response)
    assert provider.respond_to?(:parse_stream_chunk)
    assert provider.respond_to?(:parse_tool_call)
  end

  test "build_request returns HTTP Request" do
    provider = TestProvider.new(api_key: "test", default_model: "test-model")
    request = provider.build_request(
      messages: [SolidAgent::Message.new(role: "user", content: "hi")],
      tools: [],
      stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O
    )
    assert_instance_of SolidAgent::HTTP::Request, request
    assert_equal :post, request.method
  end

  test "parse_response returns Response" do
    provider = TestProvider.new(api_key: "test", default_model: "test-model")
    raw = SolidAgent::HTTP::Response.new(
      status: 200,
      headers: {},
      body: '{"choices":[{"message":{"content":"Hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}',
      error: nil
    )
    response = provider.parse_response(raw)
    assert_instance_of SolidAgent::Response, response
    assert_equal "Hello", response.messages.first.content
  end
end
```

```ruby
# test/provider/registry_test.rb
require "test_helper"

class ProviderRegistryTest < ActiveSupport::TestCase
  def setup
    @registry = SolidAgent::Provider::Registry.new
  end

  test "registers a provider" do
    @registry.register(:test) { { api_key: "key" } }
    assert @registry.registered?(:test)
  end

  test "resolves registered provider" do
    @registry.register(:test) { { api_key: "key" } }
    assert_instance_of Hash, @registry.resolve(:test)
  end

  test "raises for unknown provider" do
    assert_raises(SolidAgent::Error) { @registry.resolve(:nonexistent) }
  end

  test "lists registered providers" do
    @registry.register(:openai) { { api_key: "key1" } }
    @registry.register(:anthropic) { { api_key: "key2" } }
    assert_equal %i[openai anthropic], @registry.names
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/provider/ -v`
Expected: FAIL

- [ ] **Step 3: Implement Provider::Base**

```ruby
# lib/solid_agent/provider/base.rb
module SolidAgent
  module Provider
    module Base
      def build_request(messages:, tools:, stream:, model:, options: {})
        raise NotImplementedError, "#{self.class} must implement build_request"
      end

      def parse_response(raw_response)
        raise NotImplementedError, "#{self.class} must implement parse_response"
      end

      def parse_stream_chunk(chunk)
        raise NotImplementedError, "#{self.class} must implement parse_stream_chunk"
      end

      def parse_tool_call(raw_tool_call)
        raise NotImplementedError, "#{self.class} must implement parse_tool_call"
      end

      def tool_schema_format
        raise NotImplementedError, "#{self.class} must implement tool_schema_format"
      end
    end
  end
end
```

- [ ] **Step 4: Implement Provider::Registry**

```ruby
# lib/solid_agent/provider/registry.rb
module SolidAgent
  module Provider
    class Registry
      def initialize
        @providers = {}
      end

      def register(name, &config_block)
        @providers[name.to_sym] = config_block
      end

      def resolve(name)
        block = @providers[name.to_sym]
        raise Error, "Provider not registered: #{name}" unless block
        block.call
      end

      def registered?(name)
        @providers.key?(name.to_sym)
      end

      def names
        @providers.keys
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/provider/ -v`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Provider::Base module and Provider::Registry"
```

---

### Task 6: Update Model Constants with Pricing

**Files:**
- Modify: `lib/solid_agent/model.rb`
- Modify: `lib/solid_agent/models/open_ai.rb`
- Modify: `lib/solid_agent/models/anthropic.rb`
- Modify: `lib/solid_agent/models/google.rb`
- Create: `lib/solid_agent/models/mistral.rb`
- Test: `test/models/model_test.rb` (update)

- [ ] **Step 1: Update Model class to support pricing**

```ruby
# lib/solid_agent/model.rb
module SolidAgent
  class Model
    attr_reader :id, :context_window, :max_output, :input_price_per_million, :output_price_per_million

    def initialize(id, context_window:, max_output:, input_price_per_million: 0, output_price_per_million: 0)
      @id = id.freeze
      @context_window = context_window
      @max_output = max_output
      @input_price_per_million = input_price_per_million
      @output_price_per_million = output_price_per_million
      freeze
    end

    def to_s
      id
    end
  end
end
```

- [ ] **Step 2: Update OpenAI models**

```ruby
# lib/solid_agent/models/open_ai.rb
module SolidAgent
  module Models
    module OpenAi
      GPT_5_4_PRO = Model.new("gpt-5.4-pro", context_window: 1_050_000, max_output: 128_000, input_price_per_million: 30.0, output_price_per_million: 180.0).freeze
      GPT_5_4 = Model.new("gpt-5.4", context_window: 1_050_000, max_output: 128_000, input_price_per_million: 2.5, output_price_per_million: 15.0).freeze
      O3_PRO = Model.new("o3-pro", context_window: 200_000, max_output: 100_000, input_price_per_million: 20.0, output_price_per_million: 80.0).freeze
      O3 = Model.new("o3", context_window: 200_000, max_output: 100_000, input_price_per_million: 2.0, output_price_per_million: 8.0).freeze
      GPT_4O = Model.new("gpt-4o", context_window: 128_000, max_output: 16_384, input_price_per_million: 2.5, output_price_per_million: 10.0).freeze
      GPT_4O_MINI = Model.new("gpt-4o-mini", context_window: 128_000, max_output: 16_384, input_price_per_million: 0.15, output_price_per_million: 0.6).freeze
    end
  end
end
```

- [ ] **Step 3: Update Anthropic models**

```ruby
# lib/solid_agent/models/anthropic.rb
module SolidAgent
  module Models
    module Anthropic
      CLAUDE_OPUS_4_6 = Model.new("claude-opus-4-6", context_window: 1_000_000, max_output: 128_000, input_price_per_million: 5.0, output_price_per_million: 25.0).freeze
      CLAUDE_SONNET_4_6 = Model.new("claude-sonnet-4-6", context_window: 1_000_000, max_output: 64_000, input_price_per_million: 3.0, output_price_per_million: 15.0).freeze
      CLAUDE_OPUS_4_5 = Model.new("claude-opus-4-5", context_window: 200_000, max_output: 64_000, input_price_per_million: 5.0, output_price_per_million: 25.0).freeze
      CLAUDE_SONNET_4_5 = Model.new("claude-sonnet-4-5", context_window: 200_000, max_output: 64_000, input_price_per_million: 3.0, output_price_per_million: 15.0).freeze
      CLAUDE_SONNET_4 = Model.new("claude-sonnet-4-0", context_window: 200_000, max_output: 64_000, input_price_per_million: 3.0, output_price_per_million: 15.0).freeze
      CLAUDE_HAIKU_4_5 = Model.new("claude-haiku-4-5", context_window: 200_000, max_output: 64_000, input_price_per_million: 1.0, output_price_per_million: 5.0).freeze
    end
  end
end
```

- [ ] **Step 4: Update Google models**

```ruby
# lib/solid_agent/models/google.rb
module SolidAgent
  module Models
    module Google
      GEMINI_2_5_PRO = Model.new("gemini-2.5-pro", context_window: 1_048_576, max_output: 65_536, input_price_per_million: 1.25, output_price_per_million: 10.0).freeze
      GEMINI_2_5_FLASH = Model.new("gemini-2.5-flash", context_window: 1_048_576, max_output: 65_536, input_price_per_million: 0.3, output_price_per_million: 2.5).freeze
      GEMINI_2_5_FLASH_LITE = Model.new("gemini-2.5-flash-lite", context_window: 1_048_576, max_output: 65_536, input_price_per_million: 0.1, output_price_per_million: 0.4).freeze
      GEMINI_2_0_FLASH = Model.new("gemini-2.0-flash", context_window: 1_048_576, max_output: 8_192, input_price_per_million: 0.1, output_price_per_million: 0.4).freeze
    end
  end
end
```

- [ ] **Step 5: Add Mistral models**

```ruby
# lib/solid_agent/models/mistral.rb
module SolidAgent
  module Models
    module Mistral
      MISTRAL_LARGE = Model.new("mistral-large-2512", context_window: 262_144, max_output: 262_144, input_price_per_million: 0.5, output_price_per_million: 1.5).freeze
      MISTRAL_MEDIUM = Model.new("mistral-medium-latest", context_window: 128_000, max_output: 16_384, input_price_per_million: 0.4, output_price_per_million: 2.0).freeze
      MISTRAL_SMALL = Model.new("mistral-small-latest", context_window: 256_000, max_output: 256_000, input_price_per_million: 0.15, output_price_per_million: 0.6).freeze
      CODESTRAL = Model.new("codestral-latest", context_window: 256_000, max_output: 4_096, input_price_per_million: 0.3, output_price_per_million: 0.9).freeze
    end
  end
end
```

- [ ] **Step 6: Add Ollama placeholder models**

```ruby
# lib/solid_agent/models/ollama.rb
module SolidAgent
  module Models
    module Ollama
      LLAMA_3_3_70B = Model.new("llama3.3:70b", context_window: 128_000, max_output: 4_096).freeze
      QWEN_2_5_72B = Model.new("qwen2.5:72b", context_window: 128_000, max_output: 8_192).freeze
      DEEPSEEK_V3 = Model.new("deepseek-v3:671b", context_window: 128_000, max_output: 8_192).freeze
    end
  end
end
```

- [ ] **Step 7: Update requires and model test**

Add to `lib/solid_agent.rb`:
```ruby
require "solid_agent/models/mistral"
require "solid_agent/models/ollama"
```

Update `test/models/model_test.rb` to verify pricing:

```ruby
# test/models/model_test.rb
require "test_helper"

class ModelTest < ActiveSupport::TestCase
  test "Model stores id" do
    model = SolidAgent::Model.new("gpt-4o", context_window: 128_000, max_output: 16_384)
    assert_equal "gpt-4o", model.id
  end

  test "Model stores context_window" do
    model = SolidAgent::Model.new("gpt-4o", context_window: 128_000, max_output: 16_384)
    assert_equal 128_000, model.context_window
  end

  test "Model stores max_output" do
    model = SolidAgent::Model.new("gpt-4o", context_window: 128_000, max_output: 16_384)
    assert_equal 16_384, model.max_output
  end

  test "Model stores pricing" do
    model = SolidAgent::Model.new("gpt-4o", context_window: 128_000, max_output: 16_384, input_price_per_million: 2.5, output_price_per_million: 10.0)
    assert_equal 2.5, model.input_price_per_million
    assert_equal 10.0, model.output_price_per_million
  end

  test "Model is frozen" do
    model = SolidAgent::Models::OpenAi::GPT_4O
    assert model.frozen?
  end

  test "OpenAI model constants" do
    assert_equal "gpt-4o", SolidAgent::Models::OpenAi::GPT_4O.id
    assert_equal 128_000, SolidAgent::Models::OpenAi::GPT_4O.context_window
    assert_equal 2.5, SolidAgent::Models::OpenAi::GPT_4O.input_price_per_million
  end

  test "Anthropic model constants" do
    assert_equal "claude-sonnet-4-0", SolidAgent::Models::Anthropic::CLAUDE_SONNET_4.id
    assert_equal 200_000, SolidAgent::Models::Anthropic::CLAUDE_SONNET_4.context_window
  end

  test "Google model constants" do
    assert_equal "gemini-2.5-pro", SolidAgent::Models::Google::GEMINI_2_5_PRO.id
    assert_equal 1_048_576, SolidAgent::Models::Google::GEMINI_2_5_PRO.context_window
  end

  test "Mistral model constants" do
    assert_equal "mistral-large-2512", SolidAgent::Models::Mistral::MISTRAL_LARGE.id
  end

  test "Ollama model constants have no pricing" do
    assert_equal 0, SolidAgent::Models::Ollama::LLAMA_3_3_70B.input_price_per_million
  end
end
```

- [ ] **Step 8: Run tests**

Run: `bundle exec ruby -Itest test/models/model_test.rb`
Expected: All tests PASS

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: update model constants with pricing, add Mistral and Ollama"
```

---

### Task 7: OpenAI Provider

**Files:**
- Create: `lib/solid_agent/provider/openai.rb`
- Test: `test/provider/openai_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/provider/openai_test.rb
require "test_helper"
require "solid_agent/provider/openai"

class OpenAiProviderTest < ActiveSupport::TestCase
  def setup
    @provider = SolidAgent::Provider::OpenAi.new(api_key: "test-key")
  end

  test "build_request creates valid HTTP request" do
    messages = [SolidAgent::Message.new(role: "user", content: "Hello")]
    request = @provider.build_request(
      messages: messages,
      tools: [],
      stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O
    )
    assert_instance_of SolidAgent::HTTP::Request, request
    assert_equal :post, request.method
    assert_equal "https://api.openai.com/v1/chat/completions", request.url
    assert_includes request.headers["Authorization"], "test-key"
    body = JSON.parse(request.body)
    assert_equal "gpt-4o", body["model"]
    assert_equal "user", body["messages"][0]["role"]
  end

  test "build_request includes tools in OpenAI format" do
    messages = [SolidAgent::Message.new(role: "user", content: "Search")]
    tools = [{
      name: "web_search",
      description: "Search the web",
      inputSchema: { type: "object", properties: { query: { type: "string" } }, required: ["query"] }
    }]
    request = @provider.build_request(messages: messages, tools: tools, stream: false, model: SolidAgent::Models::OpenAi::GPT_4O)
    body = JSON.parse(request.body)
    assert_equal 1, body["tools"].length
    assert_equal "web_search", body["tools"][0]["function"]["name"]
  end

  test "build_request sets stream option" do
    messages = [SolidAgent::Message.new(role: "user", content: "Hello")]
    request = @provider.build_request(messages: messages, tools: [], stream: true, model: SolidAgent::Models::OpenAi::GPT_4O)
    body = JSON.parse(request.body)
    assert_equal true, body["stream"]
  end

  test "parse_response extracts assistant message" do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"id":"chatcmpl-1","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}'
    )
    response = @provider.parse_response(raw)
    assert_equal "Hello!", response.messages.first.content
    assert_equal "stop", response.finish_reason
    assert_equal 10, response.usage.input_tokens
    assert_equal 5, response.usage.output_tokens
  end

  test "parse_response extracts tool calls" do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"id":"chatcmpl-2","choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"web_search","arguments":"{\"query\":\"test\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":20,"completion_tokens":15}}'
    )
    response = @provider.parse_response(raw)
    assert response.has_tool_calls?
    assert_equal 1, response.tool_calls.length
    assert_equal "call_1", response.tool_calls.first.id
    assert_equal "web_search", response.tool_calls.first.name
    assert_equal({ "query" => "test" }, response.tool_calls.first.arguments)
  end

  test "parse_stream_chunk parses SSE data" do
    chunk = @provider.parse_stream_chunk('data: {"id":"chatcmpl-3","choices":[{"delta":{"content":"Hi"}}]}' + "\n\n")
    assert_equal "Hi", chunk.delta_content
    assert_not chunk.done?
  end

  test "parse_stream_chunk detects done" do
    chunk = @provider.parse_stream_chunk("data: [DONE]\n\n")
    assert chunk.done?
  end

  test "parse_stream_chunk with tool call delta" do
    chunk = @provider.parse_stream_chunk('data: {"id":"chatcmpl-4","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"search","arguments":""}}]}}]}' + "\n\n")
    assert_equal 1, chunk.delta_tool_calls.length
    assert_equal "call_1", chunk.delta_tool_calls.first["id"]
  end

  test "raises RateLimitError on 429" do
    raw = SolidAgent::HTTP::Response.new(
      status: 429, headers: { "retry-after" => "30" }, error: "Rate limited",
      body: '{"error":{"message":"Rate limit exceeded"}}'
    )
    assert_raises(SolidAgent::RateLimitError) { @provider.parse_response(raw) }
  end

  test "raises ContextLengthError on context length error" do
    raw = SolidAgent::HTTP::Response.new(
      status: 400, headers: {}, error: "Bad request",
      body: '{"error":{"message":"maximum context length exceeded","code":"context_length_exceeded"}}'
    )
    assert_raises(SolidAgent::ContextLengthError) { @provider.parse_response(raw) }
  end

  test "tool_schema_format returns openai format" do
    assert_equal :openai, @provider.tool_schema_format
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/provider/openai_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement OpenAI provider**

```ruby
# lib/solid_agent/provider/openai.rb
require "json"

module SolidAgent
  module Provider
    class OpenAi
      include Base

      BASE_URL = "https://api.openai.com/v1/chat/completions"

      def initialize(api_key:, default_model: Models::OpenAi::GPT_4O, base_url: nil)
        @api_key = api_key
        @default_model = default_model
        @base_url = base_url || BASE_URL
      end

      def build_request(messages:, tools:, stream:, model:, options: {})
        body = {
          model: model.to_s,
          messages: messages.map { |m| serialize_message(m) },
          stream: stream
        }
        body[:tools] = tools.map { |t| translate_tool(t) } unless tools.empty?
        body.merge!(options)

        HTTP::Request.new(
          method: :post,
          url: @base_url,
          headers: {
            "Authorization" => "Bearer #{@api_key}",
            "Content-Type" => "application/json"
          },
          body: JSON.generate(body),
          stream: stream
        )
      end

      def parse_response(raw_response)
        raise_error(raw_response) unless raw_response.success?

        data = raw_response.json
        choice = data.dig("choices", 0)
        msg = choice&.dig("message")

        tool_calls = parse_tool_calls_from_message(msg)
        message = Message.new(
          role: msg&.dig("role") || "assistant",
          content: msg&.dig("content"),
          tool_calls: tool_calls.empty? ? nil : tool_calls
        )

        usage = parse_usage(data["usage"])
        Response.new(
          messages: [message],
          tool_calls: tool_calls,
          usage: usage,
          finish_reason: choice&.dig("finish_reason")
        )
      end

      def parse_stream_chunk(raw_chunk)
        line = raw_chunk.to_s.strip
        if line.start_with?("data: [DONE]")
          return StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil, done: true)
        end

        return StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil, done: false) unless line.start_with?("data: ")

        json_str = line.sub("data: ", "")
        data = JSON.parse(json_str) rescue {}
        choice = data.dig("choices", 0) || {}

        delta = choice["delta"] || {}
        delta_content = delta["content"]
        delta_tool_calls = delta["tool_calls"] || []

        StreamChunk.new(
          delta_content: delta_content,
          delta_tool_calls: delta_tool_calls,
          usage: nil,
          done: false
        )
      end

      def parse_tool_call(raw_tool_call)
        args = raw_tool_call["arguments"]
        arguments = args.is_a?(String) ? JSON.parse(args) : args
        ToolCall.new(
          id: raw_tool_call["id"],
          name: raw_tool_call["name"] || raw_tool_call.dig("function", "name"),
          arguments: arguments,
          call_index: raw_tool_call["index"] || 0
        )
      end

      def tool_schema_format
        :openai
      end

      private

      def serialize_message(message)
        h = { role: message.role }
        h[:content] = message.content if message.content
        if message.tool_calls && !message.tool_calls.empty?
          h[:tool_calls] = message.tool_calls.map do |tc|
            {
              id: tc.id,
              type: "function",
              function: { name: tc.name, arguments: JSON.generate(tc.arguments) }
            }
          end
        end
        h[:tool_call_id] = message.tool_call_id if message.tool_call_id
        h
      end

      def translate_tool(tool)
        {
          type: "function",
          function: {
            name: tool[:name],
            description: tool[:description],
            parameters: tool[:inputSchema]
          }
        }
      end

      def parse_tool_calls_from_message(msg)
        return [] unless msg&.dig("tool_calls")
        msg["tool_calls"].map do |tc|
          func = tc["function"]
          args = func["arguments"]
          arguments = args.is_a?(String) ? JSON.parse(args) : args
          ToolCall.new(
            id: tc["id"],
            name: func["name"],
            arguments: arguments,
            call_index: tc["index"] || 0
          )
        end
      end

      def parse_usage(usage_data)
        return Usage.new(input_tokens: 0, output_tokens: 0) unless usage_data
        Usage.new(
          input_tokens: usage_data["prompt_tokens"] || 0,
          output_tokens: usage_data["completion_tokens"] || 0
        )
      end

      def raise_error(response)
        body = begin
          response.json
        rescue
          {}
        end
        message = body.dig("error", "message") || response.error || "Unknown error"

        case response.status
        when 429
          retry_after = response.headers["retry-after"]&.to_i
          raise RateLimitError.new(message, retry_after: retry_after)
        when 400
          code = body.dig("error", "code")
          if code == "context_length_exceeded" || message.downcase.include?("context length")
            raise ContextLengthError.new(message)
          end
          raise ProviderError, message
        when 408, 504
          raise ProviderTimeoutError, message
        else
          raise ProviderError, message
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/provider/openai_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add OpenAI provider with tool calls, streaming, and error handling"
```

---

### Task 8: Anthropic Provider

**Files:**
- Create: `lib/solid_agent/provider/anthropic.rb`
- Test: `test/provider/anthropic_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/provider/anthropic_test.rb
require "test_helper"
require "solid_agent/provider/anthropic"

class AnthropicProviderTest < ActiveSupport::TestCase
  def setup
    @provider = SolidAgent::Provider::Anthropic.new(api_key: "test-key")
  end

  test "build_request creates valid request with system prompt extraction" do
    messages = [
      SolidAgent::Message.new(role: "system", content: "You are helpful"),
      SolidAgent::Message.new(role: "user", content: "Hello")
    ]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::Anthropic::CLAUDE_SONNET_4
    )
    body = JSON.parse(request.body)
    assert_equal "You are helpful", body["system"]
    assert_equal 1, body["messages"].length
    assert_equal "user", body["messages"][0]["role"]
    assert_equal "claude-sonnet-4-0", body["model"]
    assert_includes request.headers["x-api-key"], "test-key"
  end

  test "build_request includes tools in Anthropic format" do
    messages = [SolidAgent::Message.new(role: "user", content: "Search")]
    tools = [{
      name: "web_search",
      description: "Search the web",
      inputSchema: { type: "object", properties: { query: { type: "string" } }, required: ["query"] }
    }]
    request = @provider.build_request(messages: messages, tools: tools, stream: false, model: SolidAgent::Models::Anthropic::CLAUDE_SONNET_4)
    body = JSON.parse(request.body)
    assert_equal 1, body["tools"].length
    assert_equal "web_search", body["tools"][0]["name"]
    assert_equal "web_search", body["tools"][0]["description"]
  end

  test "build_request sets max_tokens" do
    messages = [SolidAgent::Message.new(role: "user", content: "Hello")]
    request = @provider.build_request(messages: messages, tools: [], stream: false, model: SolidAgent::Models::Anthropic::CLAUDE_SONNET_4, max_tokens: 4096)
    body = JSON.parse(request.body)
    assert_equal 4096, body["max_tokens"]
  end

  test "parse_response extracts content blocks" do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"Hello!"}],"model":"claude-sonnet-4-0","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":5}}'
    )
    response = @provider.parse_response(raw)
    assert_equal "Hello!", response.messages.first.content
    assert_equal "end_turn", response.finish_reason
    assert_equal 10, response.usage.input_tokens
  end

  test "parse_response extracts tool_use content blocks" do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"id":"msg_2","type":"message","role":"assistant","content":[{"type":"text","text":"Let me search"},{"type":"tool_use","id":"toolu_1","name":"web_search","input":{"query":"test"}}],"model":"claude-sonnet-4-0","stop_reason":"tool_use","usage":{"input_tokens":20,"output_tokens":15}}'
    )
    response = @provider.parse_response(raw)
    assert response.has_tool_calls?
    tc = response.tool_calls.first
    assert_equal "toolu_1", tc.id
    assert_equal "web_search", tc.name
    assert_equal({ "query" => "test" }, tc.arguments)
  end

  test "parse_stream_chunk parses content_block_delta" do
    chunk = @provider.parse_stream_chunk('event: content_block_delta' + "\n" + 'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}' + "\n\n")
    assert_equal "Hi", chunk.delta_content
  end

  test "parse_stream_chunk detects message_stop as done" do
    chunk = @provider.parse_stream_chunk('event: message_stop' + "\n" + 'data: {"type":"message_stop"}' + "\n\n")
    assert chunk.done?
  end

  test "raises RateLimitError on 429" do
    raw = SolidAgent::HTTP::Response.new(
      status: 429, headers: {}, error: "Rate limited",
      body: '{"error":{"type":"rate_limit_error","message":"Too many requests"}}'
    )
    assert_raises(SolidAgent::RateLimitError) { @provider.parse_response(raw) }
  end

  test "raises error on overloaded" do
    raw = SolidAgent::HTTP::Response.new(
      status: 529, headers: {}, error: "Overloaded",
      body: '{"error":{"type":"overloaded_error","message":"Overloaded"}}'
    )
    assert_raises(SolidAgent::ProviderError) { @provider.parse_response(raw) }
  end

  test "tool_schema_format returns anthropic format" do
    assert_equal :anthropic, @provider.tool_schema_format
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/provider/anthropic_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement Anthropic provider**

```ruby
# lib/solid_agent/provider/anthropic.rb
require "json"

module SolidAgent
  module Provider
    class Anthropic
      include Base

      BASE_URL = "https://api.anthropic.com/v1/messages"

      def initialize(api_key:, default_model: Models::Anthropic::CLAUDE_SONNET_4)
        @api_key = api_key
        @default_model = default_model
      end

      def build_request(messages:, tools:, stream:, model:, options: {})
        system_msg, filtered = extract_system(messages)

        body = {
          model: model.to_s,
          messages: filtered.map { |m| serialize_message(m) },
          max_tokens: options.delete(:max_tokens) || model.max_output,
          stream: stream
        }
        body[:system] = system_msg if system_msg
        body[:tools] = tools.map { |t| translate_tool(t) } unless tools.empty?
        body.merge!(options)

        HTTP::Request.new(
          method: :post,
          url: BASE_URL,
          headers: {
            "x-api-key" => @api_key,
            "anthropic-version" => "2023-06-01",
            "Content-Type" => "application/json"
          },
          body: JSON.generate(body),
          stream: stream
        )
      end

      def parse_response(raw_response)
        raise_error(raw_response) unless raw_response.success?

        data = raw_response.json
        content_blocks = data["content"] || []
        text_parts = content_blocks.select { |b| b["type"] == "text" }.map { |b| b["text"] }
        tool_use_parts = content_blocks.select { |b| b["type"] == "tool_use" }

        tool_calls = tool_use_parts.map do |tu|
          ToolCall.new(id: tu["id"], name: tu["name"], arguments: tu["input"], call_index: 0)
        end

        message = Message.new(
          role: "assistant",
          content: text_parts.join,
          tool_calls: tool_calls.empty? ? nil : tool_calls
        )

        usage = Usage.new(
          input_tokens: data.dig("usage", "input_tokens") || 0,
          output_tokens: data.dig("usage", "output_tokens") || 0
        )

        Response.new(
          messages: [message],
          tool_calls: tool_calls,
          usage: usage,
          finish_reason: data["stop_reason"]
        )
      end

      def parse_stream_chunk(raw_chunk)
        lines = raw_chunk.to_s.strip.split("\n")
        event_line = lines.find { |l| l.start_with?("event:") }
        data_line = lines.find { |l| l.start_with?("data:") }

        event_type = event_line&.sub("event: ", "")&.strip

        return StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil, done: true) if event_type == "message_stop"

        return StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil, done: false) unless data_line

        data = JSON.parse(data_line.sub("data: ", "")) rescue {}

        case event_type
        when "content_block_delta"
          delta = data["delta"] || {}
          StreamChunk.new(
            delta_content: delta["text"],
            delta_tool_calls: [],
            usage: nil,
            done: false
          )
        when "message_delta"
          usage_data = data.dig("usage")
          StreamChunk.new(
            delta_content: nil,
            delta_tool_calls: [],
            usage: usage_data ? Usage.new(input_tokens: 0, output_tokens: usage_data["output_tokens"] || 0) : nil,
            done: false
          )
        else
          StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil, done: false)
        end
      end

      def parse_tool_call(raw_tool_call)
        ToolCall.new(
          id: raw_tool_call["id"],
          name: raw_tool_call["name"],
          arguments: raw_tool_call["input"] || {},
          call_index: 0
        )
      end

      def tool_schema_format
        :anthropic
      end

      private

      def extract_system(messages)
        system_parts = messages.select { |m| m.role == "system" }.map(&:content)
        others = messages.reject { |m| m.role == "system" }
        [system_parts.empty? ? nil : system_parts.join("\n"), others]
      end

      def serialize_message(message)
        h = { role: message.role }
        h[:content] = message.content || ""
        if message.tool_calls && !message.tool_calls.empty?
          h[:content] = message.content || ""
          h[:content] = [message.content || ""] if message.content && !message.content.empty?
          tool_blocks = message.tool_calls.map do |tc|
            { type: "tool_use", id: tc.id, name: tc.name, input: tc.arguments }
          end
          text_block = message.content ? [{ type: "text", text: message.content }] : []
          h[:content] = text_block + tool_blocks
        end
        if message.role == "tool"
          h[:role] = "user"
          h[:content] = [{ type: "tool_result", tool_use_id: message.tool_call_id, content: message.content }]
        end
        h
      end

      def translate_tool(tool)
        {
          name: tool[:name],
          description: tool[:description],
          input_schema: tool[:inputSchema]
        }
      end

      def raise_error(response)
        body = begin
          response.json
        rescue
          {}
        end
        message = body.dig("error", "message") || response.error || "Unknown error"
        error_type = body.dig("error", "type")

        case response.status
        when 429
          raise RateLimitError, message
        when 400
          if message.downcase.include?("context") || message.downcase.include?("token")
            raise ContextLengthError, message
          end
          raise ProviderError, message
        when 529
          raise ProviderError, message
        when 408, 504
          raise ProviderTimeoutError, message
        else
          raise ProviderError, message
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/provider/anthropic_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Anthropic provider with content blocks and tool use"
```

---

### Task 9: Google Provider

**Files:**
- Create: `lib/solid_agent/provider/google.rb`
- Test: `test/provider/google_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/provider/google_test.rb
require "test_helper"
require "solid_agent/provider/google"

class GoogleProviderTest < ActiveSupport::TestCase
  def setup
    @provider = SolidAgent::Provider::Google.new(api_key: "test-key")
  end

  test "build_request creates valid request" do
    messages = [SolidAgent::Message.new(role: "user", content: "Hello")]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::Google::GEMINI_2_5_PRO
    )
    assert_equal :post, request.method
    assert_includes request.url, "generativelanguage.googleapis.com"
    assert_includes request.url, "gemini-2.5-pro"
    body = JSON.parse(request.body)
    assert_equal 1, body["contents"].length
    assert_equal "user", body["contents"][0]["role"]
    assert_equal "Hello", body["contents"][0]["parts"][0]["text"]
  end

  test "build_request extracts system instruction" do
    messages = [
      SolidAgent::Message.new(role: "system", content: "Be helpful"),
      SolidAgent::Message.new(role: "user", content: "Hi")
    ]
    request = @provider.build_request(messages: messages, tools: [], stream: false, model: SolidAgent::Models::Google::GEMINI_2_5_PRO)
    body = JSON.parse(request.body)
    assert_equal "Be helpful", body["systemInstruction"]["parts"][0]["text"]
    assert_equal 1, body["contents"].length
  end

  test "build_request includes tools in Google format" do
    messages = [SolidAgent::Message.new(role: "user", content: "Search")]
    tools = [{
      name: "web_search",
      description: "Search the web",
      inputSchema: { type: "object", properties: { query: { type: "string" } }, required: ["query"] }
    }]
    request = @provider.build_request(messages: messages, tools: tools, stream: false, model: SolidAgent::Models::Google::GEMINI_2_5_PRO)
    body = JSON.parse(request.body)
    assert_equal 1, body["tools"].length
    func_decls = body["tools"][0]["functionDeclarations"]
    assert_equal 1, func_decls.length
    assert_equal "web_search", func_decls[0]["name"]
  end

  test "parse_response extracts text" do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"candidates":[{"content":{"role":"model","parts":[{"text":"Hello!"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5}}'
    )
    response = @provider.parse_response(raw)
    assert_equal "Hello!", response.messages.first.content
    assert_equal "STOP", response.finish_reason
    assert_equal 10, response.usage.input_tokens
    assert_equal 5, response.usage.output_tokens
  end

  test "parse_response extracts function calls" do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"web_search","args":{"query":"test"}}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":20,"candidatesTokenCount":15}}'
    )
    response = @provider.parse_response(raw)
    assert response.has_tool_calls?
    tc = response.tool_calls.first
    assert_equal "web_search", tc.name
    assert_equal({ "query" => "test" }, tc.arguments)
  end

  test "parse_stream_chunk parses text chunk" do
    chunk = @provider.parse_stream_chunk('data: {"candidates":[{"content":{"parts":[{"text":"Hi"}]}}]}' + "\n\n")
    assert_equal "Hi", chunk.delta_content
  end

  test "raises error on non-success" do
    raw = SolidAgent::HTTP::Response.new(
      status: 400, headers: {}, error: "Bad request",
      body: '{"error":{"message":"Invalid request"}}'
    )
    assert_raises(SolidAgent::ProviderError) { @provider.parse_response(raw) }
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/provider/google_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement Google provider**

```ruby
# lib/solid_agent/provider/google.rb
require "json"

module SolidAgent
  module Provider
    class Google
      include Base

      BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"

      def initialize(api_key:, default_model: Models::Google::GEMINI_2_5_PRO)
        @api_key = api_key
        @default_model = default_model
      end

      def build_request(messages:, tools:, stream:, model:, options: {})
        system_msg, filtered = extract_system(messages)

        url = "#{BASE_URL}/#{model.to_s}:#{stream ? 'streamGenerateContent' : 'generateContent'}?key=#{@api_key}"

        body = {
          contents: filtered.map { |m| serialize_message(m) }
        }
        body[:systemInstruction] = { parts: [{ text: system_msg }] } if system_msg
        body[:tools] = [{ functionDeclarations: tools.map { |t| translate_tool(t) } }] unless tools.empty?
        body.merge!(options)

        HTTP::Request.new(
          method: :post,
          url: url,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate(body),
          stream: stream
        )
      end

      def parse_response(raw_response)
        raise_error(raw_response) unless raw_response.success?

        data = raw_response.json
        candidate = data.dig("candidates", 0)
        parts = candidate&.dig("content", "parts") || []

        text_parts = parts.select { |p| p["text"] }.map { |p| p["text"] }
        function_calls = parts.select { |p| p["functionCall"] }

        tool_calls = function_calls.map.with_index do |fc, i|
          ToolCall.new(
            id: "fc_#{i}",
            name: fc.dig("functionCall", "name"),
            arguments: fc.dig("functionCall", "args") || {},
            call_index: i
          )
        end

        message = Message.new(
          role: "assistant",
          content: text_parts.join,
          tool_calls: tool_calls.empty? ? nil : tool_calls
        )

        usage_data = data["usageMetadata"]
        usage = Usage.new(
          input_tokens: usage_data&.dig("promptTokenCount") || 0,
          output_tokens: usage_data&.dig("candidatesTokenCount") || 0
        )

        Response.new(
          messages: [message],
          tool_calls: tool_calls,
          usage: usage,
          finish_reason: candidate&.dig("finishReason")
        )
      end

      def parse_stream_chunk(raw_chunk)
        line = raw_chunk.to_s.strip
        return StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil, done: false) unless line.start_with?("data: ")

        data = JSON.parse(line.sub("data: ", "")) rescue {}
        parts = data.dig("candidates", 0, "content", "parts") || []
        text = parts.filter_map { |p| p["text"] }.join

        StreamChunk.new(delta_content: text.empty? ? nil : text, delta_tool_calls: [], usage: nil, done: false)
      end

      def parse_tool_call(raw_tool_call)
        ToolCall.new(
          id: raw_tool_call["id"] || "fc_0",
          name: raw_tool_call["name"],
          arguments: raw_tool_call["args"] || {},
          call_index: 0
        )
      end

      def tool_schema_format
        :google
      end

      private

      def extract_system(messages)
        system_parts = messages.select { |m| m.role == "system" }.map(&:content)
        others = messages.reject { |m| m.role == "system" }
        [system_parts.empty? ? nil : system_parts.join("\n"), others]
      end

      def serialize_message(message)
        role = message.role == "assistant" ? "model" : "user"

        if message.role == "tool"
          return {
            role: "function",
            parts: [{ functionResponse: { name: message.tool_call_id, response: { content: message.content } } }]
          }
        end

        h = { role: role, parts: [] }
        h[:parts] << { text: message.content } if message.content
        if message.tool_calls
          message.tool_calls.each do |tc|
            h[:parts] << { functionCall: { name: tc.name, args: tc.arguments } }
          end
        end
        h[:parts] = [{ text: "" }] if h[:parts].empty?
        h
      end

      def translate_tool(tool)
        {
          name: tool[:name],
          description: tool[:description],
          parameters: tool[:inputSchema]
        }
      end

      def raise_error(response)
        body = begin
          response.json
        rescue
          {}
        end
        message = body.dig("error", "message") || response.error || "Unknown error"

        case response.status
        when 429
          raise RateLimitError, message
        when 400
          raise ContextLengthError, message if message.downcase.include?("token") || message.downcase.include?("context")
          raise ProviderError, message
        else
          raise ProviderError, message
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/provider/google_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Google Gemini provider"
```

---

### Task 10: Ollama Provider

**Files:**
- Create: `lib/solid_agent/provider/ollama.rb`
- Test: `test/provider/ollama_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/provider/ollama_test.rb
require "test_helper"
require "solid_agent/provider/ollama"

class OllamaProviderTest < ActiveSupport::TestCase
  def setup
    @provider = SolidAgent::Provider::Ollama.new(base_url: "http://localhost:11434")
  end

  test "build_request creates valid request" do
    messages = [SolidAgent::Message.new(role: "user", content: "Hello")]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::Ollama::LLAMA_3_3_70B
    )
    assert_equal :post, request.method
    assert_equal "http://localhost:11434/api/chat", request.url
    body = JSON.parse(request.body)
    assert_equal "llama3.3:70b", body["model"]
    assert_equal false, body["stream"]
  end

  test "parse_response extracts message" do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"model":"llama3.3:70b","message":{"role":"assistant","content":"Hello!"},"done":true}'
    )
    response = @provider.parse_response(raw)
    assert_equal "Hello!", response.messages.first.content
    assert_equal "stop", response.finish_reason
  end

  test "parse_stream_chunk parses message delta" do
    chunk = @provider.parse_stream_chunk('{"message":{"role":"assistant","content":"Hi"},"done":false}' + "\n")
    assert_equal "Hi", chunk.delta_content
    assert_not chunk.done?
  end

  test "parse_stream_chunk detects done" do
    chunk = @provider.parse_stream_chunk('{"done":true}' + "\n")
    assert chunk.done?
  end

  test "supports custom base_url" do
    provider = SolidAgent::Provider::Ollama.new(base_url: "http://my-server:8080")
    request = provider.build_request(
      messages: [SolidAgent::Message.new(role: "user", content: "Hi")],
      tools: [], stream: false, model: SolidAgent::Models::Ollama::LLAMA_3_3_70B
    )
    assert_equal "http://my-server:8080/api/chat", request.url
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/provider/ollama_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement Ollama provider**

```ruby
# lib/solid_agent/provider/ollama.rb
require "json"

module SolidAgent
  module Provider
    class Ollama
      include Base

      DEFAULT_BASE_URL = "http://localhost:11434"

      def initialize(base_url: DEFAULT_BASE_URL)
        @base_url = base_url.chomp("/")
      end

      def build_request(messages:, tools:, stream:, model:, options: {})
        body = {
          model: model.to_s,
          messages: messages.map { |m| serialize_message(m) },
          stream: stream
        }
        body[:tools] = tools.map { |t| translate_tool(t) } unless tools.empty?
        body.merge!(options)

        HTTP::Request.new(
          method: :post,
          url: "#{@base_url}/api/chat",
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate(body),
          stream: stream
        )
      end

      def parse_response(raw_response)
        raise_error(raw_response) unless raw_response.success?

        data = raw_response.json
        msg = data["message"] || {}

        message = Message.new(
          role: msg["role"] || "assistant",
          content: msg["content"]
        )

        Response.new(
          messages: [message],
          tool_calls: [],
          usage: Usage.new(input_tokens: 0, output_tokens: 0),
          finish_reason: data["done"] ? "stop" : nil
        )
      end

      def parse_stream_chunk(raw_chunk)
        line = raw_chunk.to_s.strip
        return StreamChunk.new(delta_content: nil, delta_tool_calls: [], usage: nil, done: false) if line.empty?

        data = JSON.parse(line) rescue {}
        done = data["done"] == true

        StreamChunk.new(
          delta_content: data.dig("message", "content"),
          delta_tool_calls: [],
          usage: nil,
          done: done
        )
      end

      def parse_tool_call(raw_tool_call)
        ToolCall.new(
          id: raw_tool_call["id"] || "tc_0",
          name: raw_tool_call["name"],
          arguments: raw_tool_call["arguments"] || raw_tool_call["input"] || {},
          call_index: 0
        )
      end

      def tool_schema_format
        :openai
      end

      private

      def serialize_message(message)
        h = { role: message.role, content: message.content || "" }
        h
      end

      def translate_tool(tool)
        {
          type: "function",
          function: {
            name: tool[:name],
            description: tool[:description],
            parameters: tool[:inputSchema]
          }
        }
      end

      def raise_error(response)
        raise ProviderError, response.error || "Ollama error: HTTP #{response.status}"
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/provider/ollama_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Ollama provider for local models"
```

---

### Task 11: OpenAI-Compatible Provider

**Files:**
- Create: `lib/solid_agent/provider/openai_compatible.rb`
- Test: `test/provider/openai_compatible_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/provider/openai_compatible_test.rb
require "test_helper"
require "solid_agent/provider/openai_compatible"

class OpenAiCompatibleProviderTest < ActiveSupport::TestCase
  def setup
    @provider = SolidAgent::Provider::OpenAiCompatible.new(
      base_url: "http://localhost:8000/v1/chat/completions",
      api_key: "test-key",
      default_model: "my-custom-model"
    )
  end

  test "build_request uses custom base_url" do
    messages = [SolidAgent::Message.new(role: "user", content: "Hello")]
    request = @provider.build_request(messages: messages, tools: [], stream: false, model: SolidAgent::Models::OpenAi::GPT_4O)
    assert_equal "http://localhost:8000/v1/chat/completions", request.url
  end

  test "inherits OpenAI parsing" do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"choices":[{"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}'
    )
    response = @provider.parse_response(raw)
    assert_equal "Hello!", response.messages.first.content
  end

  test "works without API key" do
    provider = SolidAgent::Provider::OpenAiCompatible.new(
      base_url: "http://localhost:8000/v1/chat/completions"
    )
    messages = [SolidAgent::Message.new(role: "user", content: "Hi")]
    request = provider.build_request(messages: messages, tools: [], stream: false, model: SolidAgent::Models::OpenAi::GPT_4O)
    assert_not request.headers.key?("Authorization")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/provider/openai_compatible_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement OpenAI-compatible provider**

```ruby
# lib/solid_agent/provider/openai_compatible.rb
module SolidAgent
  module Provider
    class OpenAiCompatible < OpenAi
      def initialize(base_url:, api_key: nil, default_model: "default")
        @base_url_override = base_url
        @api_key = api_key
        @default_model = default_model
      end

      private

      def base_url
        @base_url_override
      end
    end
  end
end
```

Wait — the parent `OpenAi` hardcodes `BASE_URL` and uses it in `build_request`. We need to make `base_url` an instance method that can be overridden. Update `OpenAi` first.

- [ ] **Step 3a: Update OpenAi to use instance method for base_url**

In `lib/solid_agent/provider/openai.rb`, change the `build_request` method to use `base_url` instance method instead of the constant, and add:

```ruby
def base_url
  @base_url || BASE_URL
end
```

Then implement:

```ruby
# lib/solid_agent/provider/openai_compatible.rb
module SolidAgent
  module Provider
    class OpenAiCompatible < OpenAi
      def initialize(base_url:, api_key: nil, default_model: "default")
        @api_key = api_key
        @default_model = default_model
        @base_url = base_url
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/provider/openai_compatible_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add OpenAI-compatible provider for LiteLLM, vLLM, etc."
```

---

### Task 12: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rake test`
Expected: All tests PASS, 0 failures

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "chore: LLM provider layer plan complete"
```
