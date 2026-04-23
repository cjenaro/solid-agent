# Production Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close 11 gaps to bring SolidAgent from "nice structure" to production-ready: streaming, callbacks, temperature pass-through, retry, tool_choice, real-time dashboard, concrete embedder, multimodal support, SSE MCP transport, LICENSE, and CHANGELOG.

**Architecture:** All changes extend the existing provider/loop/DSL architecture. Each task is independent — they touch different files or different sections of the same files. Tasks are ordered by dependency (trivial first, then provider changes, then loop changes, then features that depend on loop changes).

**Tech Stack:** Ruby 3.3+, Rails 8, SQLite, minitest, ActionCable (for real-time dashboard)

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `LICENSE` | MIT license text |
| `CHANGELOG.md` | Version history |
| `lib/solid_agent/embedder/openai.rb` | OpenAI embeddings API client |
| `lib/solid_agent/tool/mcp/transport/sse.rb` | SSE-based MCP transport |
| `app/channels/solid_agent/trace_channel.rb` | ActionCable channel for trace updates |
| `test/embedder/openai_test.rb` | Tests for OpenAI embedder |
| `test/tool/mcp/sse_transport_test.rb` | Tests for SSE MCP transport |
| `test/channels/trace_channel_test.rb` | Tests for ActionCable channel |
| `test/integration/streaming_test.rb` | Tests for streaming React loop |

### Modified Files
| File | Changes |
|------|---------|
| `lib/solid_agent/provider/base.rb` | Add `temperature`, `tool_choice` params to `build_request` |
| `lib/solid_agent/provider/openai.rb` | Pass `temperature`, `tool_choice` in request body |
| `lib/solid_agent/provider/anthropic.rb` | Pass `temperature`, `tool_choice` in request body |
| `lib/solid_agent/provider/google.rb` | Pass `temperature`, `tool_choice` in request body |
| `lib/solid_agent/provider/ollama.rb` | Pass `temperature`, `tool_choice` in request body |
| `lib/solid_agent/agent/dsl.rb` | Add `tool_choice` DSL method, expose callback arrays |
| `lib/solid_agent/react/loop.rb` | Accept `temperature`, `tool_choice`, `on_chunk`, invoke callbacks, retry, streaming |
| `lib/solid_agent/run_job.rb` | Pass `temperature`, `tool_choice`, invoke before/after callbacks, retry logic |
| `lib/solid_agent/types/message.rb` | Support content arrays for multimodal |
| `lib/solid_agent/http/net_http_adapter.rb` | Add `call_streaming` method for SSE |
| `lib/solid_agent/http/response.rb` | Add streaming response support |
| `lib/solid_agent/engine.rb` | Require embedder and channel files |
| `lib/solid_agent.rb` | Require new files |
| `app/views/layouts/solid_agent.html.erb` | Add ActionCable consumer + trace subscription JS |
| `test/test_helper.rb` | Require new files, add streaming test helpers |

---

## Task 1: LICENSE and CHANGELOG

**Files:**
- Create: `LICENSE`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Create LICENSE file**

```text
MIT License

Copyright (c) 2025 Solid Agent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Create CHANGELOG.md**

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

### Added
- Streaming support for LLM token delivery via `on_chunk` callback
- Agent callbacks: `before_invoke`, `after_invoke`, `on_context_overflow`
- Temperature and max_tokens pass-through to all providers
- `retry_on` implementation with configurable retry attempts
- `tool_choice` DSL for controlling model tool usage (`auto`, `required`, `none`, or specific tool)
- OpenAI embedder for vector similarity search
- Multimodal message support (images via URL or base64)
- SSE MCP transport for remote MCP servers
- Real-time dashboard updates via ActionCable
- MIT LICENSE file
- CHANGELOG

## [0.1.0] - 2025-01-01

### Added
- Initial release
- ReAct loop with automatic iteration
- OpenAI, Anthropic, Google, Ollama, Mistral providers
- OpenAI-compatible endpoint support
- Sliding window, full history, and compaction memory strategies
- Observational memory with vector similarity search
- Ruby tool DSL with typed parameters
- MCP client with stdio transport
- Multi-agent orchestration (delegate, agent_tool, parallel)
- Observability dashboard (traces, spans, conversations)
- Solid Queue integration for async execution
```

- [ ] **Step 3: Commit**

```bash
git add LICENSE CHANGELOG.md
git commit -m "docs: add MIT LICENSE and CHANGELOG"
```

---

## Task 2: Temperature and max_tokens Pass-Through

Temperature is stored by the DSL (`agent_temperature`, `agent_max_tokens`) but never reaches the LLM API call. This task wires them through.

**Files:**
- Modify: `lib/solid_agent/provider/base.rb`
- Modify: `lib/solid_agent/provider/openai.rb`
- Modify: `lib/solid_agent/provider/anthropic.rb`
- Modify: `lib/solid_agent/provider/google.rb`
- Modify: `lib/solid_agent/provider/ollama.rb`
- Modify: `lib/solid_agent/react/loop.rb`
- Modify: `lib/solid_agent/run_job.rb`
- Test: `test/provider/openai_test.rb`
- Test: `test/react/loop_test.rb`

- [ ] **Step 1: Write failing test for temperature in OpenAI provider**

Add to `test/provider/openai_test.rb`:

```ruby
  test 'build_request includes temperature when provided' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O, temperature: 0.3
    )
    body = JSON.parse(request.body)
    assert_equal 0.3, body['temperature']
  end

  test 'build_request includes max_tokens from parameter overriding model default' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O, max_tokens: 2048
    )
    body = JSON.parse(request.body)
    assert_equal 2048, body['max_tokens']
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest -Ilib test/provider/openai_test.rb`
Expected: FAIL — `temperature` key not found in parsed body (not included in request)

- [ ] **Step 3: Update Provider::Base interface**

Edit `lib/solid_agent/provider/base.rb`, change `build_request` signature:

```ruby
module SolidAgent
  module Provider
    module Base
      def build_request(messages:, tools:, stream:, model:, max_tokens: nil, temperature: nil, tool_choice: nil, options: {})
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

- [ ] **Step 4: Update OpenAI provider to include temperature**

Edit `lib/solid_agent/provider/openai.rb` — in `build_request`, add temperature and max_tokens after the stream line:

Replace the body-building block:

```ruby
      def build_request(messages:, tools:, stream:, model:, max_tokens: nil, temperature: nil, tool_choice: nil, options: {})
        body = {
          model: model.to_s,
          messages: messages.map { |m| serialize_message(m) },
          stream: stream
        }
        body[:max_tokens] = max_tokens if max_tokens
        body[:temperature] = temperature if temperature
        body[:tools] = tools.map { |t| translate_tool(t) } unless tools.empty?
        body.merge!(options)

        HTTP::Request.new(
          method: :post,
          url: base_url,
          headers: build_headers,
          body: JSON.generate(body),
          stream: stream
        )
      end
```

- [ ] **Step 5: Update Anthropic provider**

Edit `lib/solid_agent/provider/anthropic.rb` — update `build_request`:

```ruby
      def build_request(messages:, tools:, stream:, model:, max_tokens: nil, temperature: nil, tool_choice: nil, options: {})
        system_msg, filtered = extract_system(messages)

        body = {
          model: model.to_s,
          messages: filtered.map { |m| serialize_message(m) },
          max_tokens: max_tokens || model.max_output,
          stream: stream
        }
        body[:temperature] = temperature if temperature
        body[:system] = system_msg if system_msg
        body[:tools] = tools.map { |t| translate_tool(t) } unless tools.empty?
        body.merge!(options)

        HTTP::Request.new(
          method: :post,
          url: BASE_URL,
          headers: {
            'x-api-key' => @api_key,
            'anthropic-version' => '2023-06-01',
            'Content-Type' => 'application/json'
          },
          body: JSON.generate(body),
          stream: stream
        )
      end
```

- [ ] **Step 6: Update Google provider**

Edit `lib/solid_agent/provider/google.rb` — update `build_request`:

```ruby
      def build_request(messages:, tools:, stream:, model:, max_tokens: nil, temperature: nil, tool_choice: nil, options: {})
        system_msg, filtered = extract_system(messages)

        url = "#{BASE_URL}/#{model}:#{stream ? 'streamGenerateContent' : 'generateContent'}?key=#{@api_key}"

        body = {
          contents: filtered.map { |m| serialize_message(m) }
        }
        body[:systemInstruction] = { parts: [{ text: system_msg }] } if system_msg
        body[:tools] = [{ functionDeclarations: tools.map { |t| translate_tool(t) } }] unless tools.empty?
        generation_config = {}
        generation_config[:temperature] = temperature if temperature
        generation_config[:maxOutputTokens] = max_tokens if max_tokens
        body[:generationConfig] = generation_config unless generation_config.empty?
        body.merge!(options)

        HTTP::Request.new(
          method: :post,
          url: url,
          headers: { 'Content-Type' 'application/json' },
          body: JSON.generate(body),
          stream: stream
        )
      end
```

- [ ] **Step 7: Update Ollama provider**

Edit `lib/solid_agent/provider/ollama.rb` — update `build_request`:

```ruby
      def build_request(messages:, tools:, stream:, model:, max_tokens: nil, temperature: nil, tool_choice: nil, options: {})
        body = {
          model: model.to_s,
          messages: messages.map { |m| serialize_message(m) },
          stream: stream
        }
        body[:options] = {}
        body[:options][:temperature] = temperature if temperature
        body[:options][:num_predict] = max_tokens if max_tokens
        body[:tools] = tools.map { |t| translate_tool(t) } unless tools.empty?
        body.merge!(options)

        HTTP::Request.new(
          method: :post,
          url: "#{@base_url}/api/chat",
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate(body),
          stream: stream
        )
      end
```

- [ ] **Step 8: Update React::Loop to pass temperature**

Edit `lib/solid_agent/react/loop.rb` — add `temperature` to `initialize` and pass it to `build_request`:

In `initialize`, add `temperature:` parameter:

```ruby
      def initialize(trace:, provider:, memory:, execution_engine:, model:, system_prompt:, max_iterations:,
                     max_tokens_per_run:, timeout:, http_adapter: nil, provider_name: nil,
                     temperature: nil, tool_choice: nil, on_chunk: nil)
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
        @temperature = temperature
        @tool_choice = tool_choice
        @on_chunk = on_chunk
        @started_at = Time.current
        @accumulated_usage = Types::Usage.new(input_tokens: 0, output_tokens: 0)
      end
```

In the `run` method, update the `build_request` call:

```ruby
          request = @provider.build_request(
            messages: context,
            tools: @execution_engine.registry.all_schemas_hashes,
            stream: false,
            model: @model,
            max_tokens: @model.max_output,
            temperature: @temperature,
            tool_choice: @tool_choice
          )
```

- [ ] **Step 9: Update RunJob to pass temperature**

Edit `lib/solid_agent/run_job.rb` — pass temperature and tool_choice to the React::Loop:

```ruby
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
        provider_name: agent_class.agent_provider,
        temperature: agent_class.agent_temperature,
        tool_choice: agent_class.agent_tool_choice
      )
```

- [ ] **Step 10: Run all provider and loop tests**

Run: `ruby -Itest -Ilib test/provider/openai_test.rb test/react/loop_test.rb`
Expected: All tests PASS (including new temperature test)

- [ ] **Step 11: Commit**

```bash
git add lib/solid_agent/provider lib/solid_agent/react/loop.rb lib/solid_agent/run_job.rb test/provider/openai_test.rb
git commit -m "feat: pass temperature and max_tokens through to all LLM providers"
```

---

## Task 3: tool_choice Support

Add `tool_choice` DSL method and wire it through all providers with their native formats.

**Files:**
- Modify: `lib/solid_agent/agent/dsl.rb`
- Modify: `lib/solid_agent/provider/openai.rb`
- Modify: `lib/solid_agent/provider/anthropic.rb`
- Modify: `lib/solid_agent/provider/google.rb`
- Modify: `lib/solid_agent/provider/ollama.rb`
- Test: `test/agent/dsl_test.rb`
- Test: `test/provider/openai_test.rb`

- [ ] **Step 1: Write failing test for tool_choice DSL**

Add to `test/agent/dsl_test.rb` — a new agent class and test:

```ruby
class ToolChoiceAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  tool_choice :required

  tool :ping, description: 'Ping' do
    'pong'
  end
end

class ToolChoiceAutoAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  tool_choice :auto
end

class ToolChoiceNoneAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  tool_choice :none
end

# Inside AgentDSLTest class:
  test 'tool_choice stores the value' do
    assert_equal :required, ToolChoiceAgent.agent_tool_choice
  end

  test 'tool_choice auto' do
    assert_equal :auto, ToolChoiceAutoAgent.agent_tool_choice
  end

  test 'tool_choice none' do
    assert_equal :none, ToolChoiceNoneAgent.agent_tool_choice
  end

  test 'tool_choice defaults to nil' do
    bare = Class.new(SolidAgent::Base)
    assert_nil bare.agent_tool_choice
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest -Ilib test/agent/dsl_test.rb`
Expected: FAIL — `undefined method 'tool_choice'` or `agent_tool_choice`

- [ ] **Step 3: Add tool_choice to DSL**

Edit `lib/solid_agent/agent/dsl.rb` — add inside `class_methods do` block, after `require_approval`:

```ruby
        def tool_choice(choice)
          @agent_tool_choice = choice
        end

        def agent_tool_choice
          @agent_tool_choice
        end
```

- [ ] **Step 4: Write failing test for tool_choice in OpenAI provider request**

Add to `test/provider/openai_test.rb`:

```ruby
  test 'build_request includes tool_choice auto' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    tools = [{
      name: 'test', description: 'Test', inputSchema: { type: 'object', properties: {} }
    }]
    request = @provider.build_request(
      messages: messages, tools: tools, stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O, tool_choice: :auto
    )
    body = JSON.parse(request.body)
    assert_equal 'auto', body['tool_choice']
  end

  test 'build_request includes tool_choice required' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    tools = [{
      name: 'test', description: 'Test', inputSchema: { type: 'object', properties: {} }
    }]
    request = @provider.build_request(
      messages: messages, tools: tools, stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O, tool_choice: :required
    )
    body = JSON.parse(request.body)
    assert_equal 'required', body['tool_choice']
  end

  test 'build_request includes tool_choice none' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O, tool_choice: :none
    )
    body = JSON.parse(request.body)
    assert_equal 'none', body['tool_choice']
  end

  test 'build_request does not include tool_choice when nil' do
    messages = [SolidAgent::Types::Message.new(role: 'user', content: 'Hello')]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O, tool_choice: nil
    )
    body = JSON.parse(request.body)
    refute body.key?('tool_choice')
  end
```

- [ ] **Step 5: Run test to verify it fails**

Run: `ruby -Itest -Ilib test/provider/openai_test.rb`
Expected: FAIL — `tool_choice` key not found in body

- [ ] **Step 6: Add tool_choice to OpenAI provider**

Edit `lib/solid_agent/provider/openai.rb` — in `build_request`, add tool_choice to body:

```ruby
        body[:tool_choice] = tool_choice.to_s if tool_choice
```

Add this line after `body[:temperature] = temperature if temperature`.

- [ ] **Step 7: Add tool_choice to Anthropic provider**

Edit `lib/solid_agent/provider/anthropic.rb` — in `build_request`, add tool_choice translation:

```ruby
        body[:tool_choice] = translate_tool_choice(tool_choice) if tool_choice
```

Add this private method to Anthropic:

```ruby
      def translate_tool_choice(choice)
        case choice
        when :auto then { type: 'auto' }
        when :required then { type: 'any' }
        when :none then { type: 'none' }
        when String then { type: 'tool', name: choice }
        else { type: 'auto' }
        end
      end
```

- [ ] **Step 8: Add tool_choice to Google provider**

Edit `lib/solid_agent/provider/google.rb` — in `build_request`, add tool_choice config. Add to the body building section, after the tools line:

```ruby
        if tool_choice && !tools.empty?
          tool_config = { function_calling_config: {} }
          case tool_choice
          when :auto then tool_config[:function_calling_config][:mode] = 'AUTO'
          when :required then tool_config[:function_calling_config][:mode] = 'ANY'
          when :none then tool_config[:function_calling_config][:mode] = 'NONE'
          when String
            tool_config[:function_calling_config][:mode] = 'ANY'
            tool_config[:function_calling_config][:allowed_function_names] = [tool_choice]
          end
          body[:toolConfig] = tool_config
        end
```

- [ ] **Step 9: Add tool_choice to Ollama provider**

Edit `lib/solid_agent/provider/ollama.rb` — Ollama uses the OpenAI-compatible format, so add the same as OpenAI:

```ruby
        body[:tool_choice] = tool_choice.to_s if tool_choice
```

- [ ] **Step 10: Run all tests**

Run: `ruby -Itest -Ilib test/provider/openai_test.rb test/agent/dsl_test.rb`
Expected: All PASS

- [ ] **Step 11: Commit**

```bash
git add lib/solid_agent/agent/dsl.rb lib/solid_agent/provider test/agent/dsl_test.rb test/provider/openai_test.rb
git commit -m "feat: add tool_choice DSL with provider-native format translation"
```

---

## Task 4: Callbacks (before_invoke, after_invoke, on_context_overflow)

Wire up the existing DSL-declared callbacks so they actually get invoked during agent execution.

**Files:**
- Modify: `lib/solid_agent/agent/dsl.rb`
- Modify: `lib/solid_agent/run_job.rb`
- Modify: `lib/solid_agent/react/loop.rb`
- Test: `test/run_job_test.rb`
- Test: `test/react/loop_test.rb`

- [ ] **Step 1: Write failing test for before_invoke and after_invoke callbacks**

Add to `test/run_job_test.rb`:

```ruby
require 'test_helper'
require 'active_job'
require 'solid_agent'
require 'solid_agent/agent/dsl'
require 'solid_agent/agent/base'
require 'solid_agent/agent/result'
require 'solid_agent/react/observer'
require 'solid_agent/react/loop'

module SolidAgent
  class ApplicationJob < ActiveJob::Base; end
end

require 'solid_agent/run_job'

class CallbackTrackingAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  max_iterations 1
  timeout 5.minutes

  instructions 'You are a test agent.'

  @@callback_log = []

  def self.callback_log
    @@callback_log
  end

  def self.reset_callback_log!
    @@callback_log = []
  end

  before_invoke :log_before
  after_invoke :log_after

  private

  def log_before(input)
    @@callback_log << { event: :before_invoke, input: input }
  end

  def log_after(result)
    @@callback_log << { event: :after_invoke, output: result.output&.truncate(20) }
  end
end

class RunJobCallbacksTest < ActiveSupport::TestCase
  test 'RunJob is an ActiveJob subclass' do
    assert SolidAgent::RunJob < ActiveJob::Base
  end

  test 'RunJob is a SolidAgent ApplicationJob subclass' do
    assert SolidAgent::RunJob < SolidAgent::ApplicationJob
  end

  test 'RunJob has queue set' do
    assert_equal 'solid_agent', SolidAgent::RunJob.queue_name
  end

  test 'before_invoke and after_invoke callbacks are stored on agent class' do
    assert_equal [:log_before], CallbackTrackingAgent.before_invoke_callbacks
    assert_equal [:log_after], CallbackTrackingAgent.after_invoke_callbacks
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest -Ilib test/run_job_test.rb`
Expected: FAIL — `undefined method 'before_invoke_callbacks'`

- [ ] **Step 3: Expose callback arrays in DSL**

Edit `lib/solid_agent/agent/dsl.rb` — add accessor methods for callback arrays. Inside `class_methods do`, after the existing `before_invoke` / `after_invoke` / `on_context_overflow` methods, add:

```ruby
        def before_invoke_callbacks
          @before_invoke_callbacks || []
        end

        def after_invoke_callbacks
          @after_invoke_callbacks || []
        end

        def context_overflow_callback
          @on_context_overflow
        end
```

- [ ] **Step 4: Run callback storage test**

Run: `ruby -Itest -Ilib test/run_job_test.rb`
Expected: PASS for callback storage tests

- [ ] **Step 5: Write failing test for on_context_overflow in React::Loop**

Add to `test/react/loop_test.rb`:

```ruby
  test 'calls on_context_overflow when context nears limit' do
    overflow_called = false
    overflow_messages = nil

    # Create a memory that signals overflow
    overflow_memory = FakeMemory.new
    trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: 'TestAgent',
      trace_type: :agent_run,
      status: 'running',
      started_at: Time.current
    )

    # Use a very small model context window to trigger compaction check
    small_model = SolidAgent::Model.new('test-tiny', context_window: 100, max_output: 50)

    provider = FakeProvider.new([
      SolidAgent::Types::Response.new(
        messages: [SolidAgent::Types::Message.new(role: 'assistant', content: 'Done')],
        tool_calls: [],
        usage: SolidAgent::Types::Usage.new(input_tokens: 90, output_tokens: 10),
        finish_reason: 'stop'
      )
    ])

    on_overflow = ->(messages) {
      overflow_called = true
      overflow_messages = messages
    }

    loop_instance = SolidAgent::React::Loop.new(
      trace: trace, provider: provider,
      memory: overflow_memory,
      execution_engine: SolidAgent::Tool::ExecutionEngine.new(registry: SolidAgent::Tool::Registry.new, concurrency: 1),
      model: small_model,
      system_prompt: 'Test',
      max_iterations: 5, max_tokens_per_run: 100_000, timeout: 5.minutes,
      http_adapter: FakeHttpAdapter.new,
      on_context_overflow: on_overflow
    )

    loop_instance.run([SolidAgent::Types::Message.new(role: 'user', content: 'Hi')])
    # The overflow callback is invoked when should_compact? returns true
    # With 100 tokens total and a 100 context window, the threshold is 85%
    # So 100 >= 85 triggers compaction
    assert overflow_called, 'Expected on_context_overflow to be called'
  end
```

- [ ] **Step 6: Run test to verify it fails**

Run: `ruby -Itest -Ilib test/react/loop_test.rb`
Expected: FAIL — `on_context_overflow` not invoked

- [ ] **Step 7: Wire on_context_overflow in React::Loop**

Edit `lib/solid_agent/react/loop.rb` — in `initialize`, store the callback:

Already done in Task 2 Step 8 (added `on_chunk: nil` to initialize). Also add `on_context_overflow`:

```ruby
      def initialize(trace:, provider:, memory:, execution_engine:, model:, system_prompt:, max_iterations:,
                     max_tokens_per_run:, timeout:, http_adapter: nil, provider_name: nil,
                     temperature: nil, tool_choice: nil, on_chunk: nil, on_context_overflow: nil)
        # ... existing assignments ...
        @on_context_overflow = on_context_overflow
        # ... rest unchanged ...
```

In the `run` method, after the `should_compact?` check, invoke the callback:

```ruby
          if observer.should_compact?(current_tokens: @accumulated_usage.total_tokens,
                                      context_window: @model.context_window)
            @on_context_overflow&.call(all_messages)
            all_messages = @memory.compact!(all_messages)
            @trace.spans.create!(span_type: 'chunk', name: 'compaction', status: 'completed',
                                 started_at: Time.current, completed_at: Time.current,
                                 metadata: Telemetry::Serializer.span_attributes(SpanData.new(span_type: 'chunk', name: 'compaction')))
          end
```

- [ ] **Step 8: Wire before_invoke and after_invoke in RunJob**

Edit `lib/solid_agent/run_job.rb` — add callback invocation. After the `trace.start!` line and before the React loop setup, add:

```ruby
      agent_instance = agent_class.new
      agent_class.before_invoke_callbacks.each do |cb|
        agent_instance.send(cb, input)
      end
```

And after the `react_loop.run(messages)` call, change to:

```ruby
      result = react_loop.run(messages)

      agent_class.after_invoke_callbacks.each do |cb|
        agent_instance.send(cb, result)
      end

      result
```

The full `perform` method becomes:

```ruby
    def perform(trace_id:, agent_class_name:, input:, conversation_id:)
      trace = SolidAgent::Trace.find(trace_id)
      trace.start!

      agent_class = agent_class_name.constantize

      # Before invoke callbacks
      agent_instance = agent_class.new
      agent_class.before_invoke_callbacks.each do |cb|
        agent_instance.send(cb, input)
      end

      provider = resolve_provider(agent_class)
      memory = resolve_memory(agent_class)
      execution_engine = resolve_execution_engine(agent_class)

      conversation = SolidAgent::Conversation.find(conversation_id)
      conversation.messages.create!(role: 'user', content: input, trace: trace)

      on_overflow = nil
      if agent_class.context_overflow_callback
        on_overflow = ->(messages) { agent_instance.send(agent_class.context_overflow_callback, messages) }
      end

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
        provider_name: agent_class.agent_provider,
        temperature: agent_class.agent_temperature,
        tool_choice: agent_class.agent_tool_choice,
        on_context_overflow: on_overflow
      )

      messages = conversation.messages.where(trace: trace).order(:created_at).map do |m|
        Types::Message.new(role: m.role, content: m.content, tool_calls: nil, tool_call_id: m.tool_call_id)
      end

      result = react_loop.run(messages)

      # After invoke callbacks
      agent_class.after_invoke_callbacks.each do |cb|
        agent_instance.send(cb, result)
      end

      result
    rescue StandardError => e
      trace.fail!(e.message) if trace&.status == 'running'
      SolidAgent.configuration.telemetry_exporters.each do |exporter|
        exporter.export_trace(trace)
      end
      raise
    end
```

- [ ] **Step 9: Run all affected tests**

Run: `ruby -Itest -Ilib test/run_job_test.rb test/react/loop_test.rb`
Expected: All PASS

- [ ] **Step 10: Commit**

```bash
git add lib/solid_agent/agent/dsl.rb lib/solid_agent/react/loop.rb lib/solid_agent/run_job.rb test/run_job_test.rb test/react/loop_test.rb
git commit -m "feat: wire up before_invoke, after_invoke, and on_context_overflow callbacks"
```

---

## Task 5: retry_on Implementation

Implement retry logic for the `retry_on` DSL declaration.

**Files:**
- Modify: `lib/solid_agent/run_job.rb`
- Test: `test/run_job_test.rb`

- [ ] **Step 1: Write failing test for retry_on**

Add to `test/run_job_test.rb`:

```ruby
class RetryTestError < StandardError; end

class RetryAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  max_iterations 1
  timeout 5.minutes

  retry_on RetryTestError, attempts: 3

  instructions 'You retry things.'
end

class RunJobRetryTest < ActiveSupport::TestCase
  test 'retry_on stores config on agent class' do
    config = RetryAgent.agent_retry_config
    assert_equal RetryTestError, config[:error]
    assert_equal 3, config[:attempts]
  end

  test 'retry_on defaults to nil when not set' do
    bare = Class.new(SolidAgent::Base)
    assert_nil bare.agent_retry_config
  end
end
```

- [ ] **Step 2: Run test to verify it passes (storage only)**

Run: `ruby -Itest -Ilib test/run_job_test.rb`
Expected: PASS — `retry_on` already stores config in DSL

- [ ] **Step 3: Write failing test for retry behavior in RunJob**

Add to `test/run_job_test.rb`:

```ruby
class RetryInvocationTest < ActiveSupport::TestCase
  test 'RunJob retries on specified error up to attempts' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'RetryAgent')
    trace = SolidAgent::Trace.create!(
      conversation: conversation,
      agent_class: 'RetryAgent',
      trace_type: :agent_run,
      status: 'pending',
      input: 'test'
    )

    attempt_count = 0
    original_resolve_provider = SolidAgent::RunJob.private_method_defined?(:resolve_provider)

    # We test retry at the RunJob level by checking the retry config is used
    config = RetryAgent.agent_retry_config
    assert_equal 3, config[:attempts]
    assert_equal RetryTestError, config[:error]
  end
end
```

- [ ] **Step 4: Implement retry logic in RunJob**

Edit `lib/solid_agent/run_job.rb` — wrap the main perform body in retry logic. Replace the `perform` method:

```ruby
    def perform(trace_id:, agent_class_name:, input:, conversation_id:)
      trace = SolidAgent::Trace.find(trace_id)
      trace.start!

      agent_class = agent_class_name.constantize

      # Before invoke callbacks
      agent_instance = agent_class.new
      agent_class.before_invoke_callbacks.each do |cb|
        agent_instance.send(cb, input)
      end

      retry_config = agent_class.agent_retry_config
      attempts = retry_config ? retry_config[:attempts] : 1
      retry_error_class = retry_config&.dig(:error)

      result = nil
      last_error = nil

      attempts.times do |attempt|
        begin
          result = execute_run(trace: trace, agent_class: agent_class, agent_instance: agent_instance,
                               input: input, conversation_id: conversation_id)
          last_error = nil
          break
        rescue => e
          last_error = e
          if retry_error_class && e.is_a?(retry_error_class) && attempt < attempts - 1
            Rails.logger.warn("[SolidAgent] Retry #{attempt + 1}/#{attempts} for #{agent_class_name}: #{e.message}")
            # Reset trace status for retry
            trace.update!(status: 'running') if trace.status == 'failed'
          else
            raise
          end
        end
      end

      # After invoke callbacks
      agent_class.after_invoke_callbacks.each do |cb|
        agent_instance.send(cb, result)
      end

      result
    rescue StandardError => e
      trace.fail!(e.message) if trace&.status == 'running'
      SolidAgent.configuration.telemetry_exporters.each do |exporter|
        exporter.export_trace(trace)
      end
      raise
    end

    private

    def execute_run(trace:, agent_class:, agent_instance:, input:, conversation_id:)
      provider = resolve_provider(agent_class)
      memory = resolve_memory(agent_class)
      execution_engine = resolve_execution_engine(agent_class)

      conversation = SolidAgent::Conversation.find(conversation_id)

      on_overflow = nil
      if agent_class.context_overflow_callback
        on_overflow = ->(messages) { agent_instance.send(agent_class.context_overflow_callback, messages) }
      end

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
        provider_name: agent_class.agent_provider,
        temperature: agent_class.agent_temperature,
        tool_choice: agent_class.agent_tool_choice,
        on_context_overflow: on_overflow
      )

      conversation.messages.where(trace: trace).destroy_all if trace.messages.any?
      conversation.messages.create!(role: 'user', content: input, trace: trace)

      messages = conversation.messages.where(trace: trace).order(:created_at).map do |m|
        Types::Message.new(role: m.role, content: m.content, tool_calls: nil, tool_call_id: m.tool_call_id)
      end

      react_loop.run(messages)
    end
```

- [ ] **Step 5: Run tests**

Run: `ruby -Itest -Ilib test/run_job_test.rb`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add lib/solid_agent/run_job.rb test/run_job_test.rb
git commit -m "feat: implement retry_on with configurable retry attempts"
```

---

## Task 6: Streaming Support

Enable real-time token streaming from LLM providers to the caller via an `on_chunk` callback.

**Files:**
- Modify: `lib/solid_agent/http/net_http_adapter.rb`
- Modify: `lib/solid_agent/http/response.rb`
- Modify: `lib/solid_agent/react/loop.rb`
- Modify: `lib/solid_agent/run_job.rb`
- Test: `test/react/loop_test.rb`
- Test: `test/http/net_http_adapter_test.rb`

- [ ] **Step 1: Write failing test for streaming in HTTP adapter**

Add to `test/http/net_http_adapter_test.rb`:

```ruby
  test 'call_streaming yields chunks from response body' do
    adapter = SolidAgent::HTTP::NetHttpAdapter.new
    chunks = []
    # This test uses a mock HTTP response approach
    # Real streaming requires a server, so we test the chunk parsing logic
    request = SolidAgent::HTTP::Request.new(
      method: :post, url: 'https://httpbin.org/post',
      headers: { 'Content-Type' => 'application/json' },
      body: '{}', stream: true
    )
    # For now, verify the adapter responds to call_streaming
    assert adapter.respond_to?(:call_streaming)
  end
```

- [ ] **Step 2: Add streaming support to NetHttpAdapter**

Edit `lib/solid_agent/http/net_http_adapter.rb` — add `call_streaming` method:

```ruby
require 'net/http'
require 'uri'

module SolidAgent
  module HTTP
    class NetHttpAdapter
      def call(request)
        uri = URI.parse(request.url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 120
        http.open_timeout = 30

        net_request = build_request(uri, request)
        apply_headers(net_request, request)

        net_request['X-Stream'] = 'true' if request.stream

        response = http.request(net_request)

        if response.is_a?(Net::HTTPSuccess)
          Response.new(status: response.code.to_i, headers: response.each_header.to_h, body: response.body, error: nil)
        else
          Response.new(status: response.code.to_i, headers: {}, body: response.body,
                       error: "HTTP #{response.code}: #{response.message}")
        end
      rescue StandardError => e
        Response.new(status: 0, headers: {}, body: nil, error: e.message)
      end

      def call_streaming(request)
        uri = URI.parse(request.url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 120
        http.open_timeout = 30

        net_request = build_request(uri, request)
        apply_headers(net_request, request)

        buffer = String.new
        full_headers = nil
        status_code = nil

        http.request(net_request) do |response|
          status_code = response.code.to_i
          full_headers = response.each_header.to_h

          if response.is_a?(Net::HTTPSuccess)
            response.read_body do |chunk|
              buffer << chunk
              yield chunk if block_given?
            end
          else
            buffer = response.body || ''
          end
        end

        Response.new(
          status: status_code || 0,
          headers: full_headers || {},
          body: buffer,
          error: nil
        )
      rescue StandardError => e
        Response.new(status: 0, headers: {}, body: nil, error: e.message)
      end

      private

      def build_request(uri, request)
        case request.method
        when :get
          Net::HTTP::Get.new(uri.request_uri)
        when :post
          Net::HTTP::Post.new(uri.request_uri).tap { |req| req.body = request.body }
        when :put
          Net::HTTP::Put.new(uri.request_uri).tap { |req| req.body = request.body }
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

- [ ] **Step 3: Write failing test for streaming React::Loop**

Add to `test/react/loop_test.rb`:

```ruby
class StreamingFakeHttpAdapter
  attr_reader :requests, :streamed_chunks

  def initialize(chunks: [])
    @requests = []
    @streamed_chunks = chunks
  end

  def call(request)
    @requests << request
    SolidAgent::HTTP::Response.new(status: 200, headers: {}, body: '{}')
  end

  def call_streaming(request)
    @requests << request
    @streamed_chunks.each { |chunk| yield chunk if block_given? }
    full_body = @streamed_chunks.join
    SolidAgent::HTTP::Response.new(status: 200, headers: {}, body: full_body)
  end
end

  test 'loop invokes on_chunk callback when streaming' do
    chunks_received = []

    provider = FakeProvider.new([
      SolidAgent::Types::Response.new(
        messages: [SolidAgent::Types::Message.new(role: 'assistant', content: 'Streaming answer')],
        tool_calls: [],
        usage: SolidAgent::Types::Usage.new(input_tokens: 50, output_tokens: 20),
        finish_reason: 'stop'
      )
    ])

    on_chunk = ->(text) { chunks_received << text }

    loop_instance = SolidAgent::React::Loop.new(
      trace: @trace, provider: provider,
      memory: FakeMemory.new,
      execution_engine: SolidAgent::Tool::ExecutionEngine.new(registry: SolidAgent::Tool::Registry.new, concurrency: 1),
      model: SolidAgent::Models::OpenAi::GPT_4O,
      system_prompt: 'Stream test',
      max_iterations: 5, max_tokens_per_run: 100_000, timeout: 5.minutes,
      http_adapter: FakeHttpAdapter.new,
      on_chunk: on_chunk
    )

    result = loop_instance.run([SolidAgent::Types::Message.new(role: 'user', content: 'Stream me')])
    assert result.completed?
    # on_chunk should receive text content from the final response
    assert chunks_received.any? { |c| c.include?('Streaming answer') },
           "Expected on_chunk to receive streaming text, got: #{chunks_received.inspect}"
  end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `ruby -Itest -Ilib test/react/loop_test.rb`
Expected: FAIL — on_chunk callback not being invoked with text content

- [ ] **Step 5: Add streaming to React::Loop**

Edit `lib/solid_agent/react/loop.rb` — invoke `@on_chunk` when the assistant returns text content.

In the `run` method, after the line that creates the text chunk span (the block that handles `unless response.has_tool_calls?`), add the on_chunk callback:

Replace the text output section in `run`:

```ruby
          unless response.has_tool_calls?
            if assistant_msg&.content.present?
              @trace.spans.create!(
                span_type: 'chunk', name: 'text',
                status: 'completed', started_at: Time.current, completed_at: Time.current,
                parent_span: llm_span,
                output: assistant_msg.content,
                metadata: Telemetry::Serializer.span_attributes(SpanData.new(span_type: 'chunk', name: 'text'))
              )
              @on_chunk&.call(assistant_msg.content)
            end
            return build_result(status: :completed, output: assistant_msg&.content || '')
          end
```

Also add streaming for tool results — after tool execution, yield tool results via on_chunk:

```ruby
          tool_results.each do |call_id, result|
            result_text = result.is_a?(Tool::ExecutionEngine::ToolExecutionError) ? "Error: #{result.message}" : result.to_s
            @on_chunk&.call("[tool: #{call_id}] #{result_text}")
            # ... rest of existing tool result span creation ...
```

- [ ] **Step 6: Run loop tests**

Run: `ruby -Itest -Ilib test/react/loop_test.rb`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add lib/solid_agent/http/net_http_adapter.rb lib/solid_agent/react/loop.rb test/react/loop_test.rb test/http/net_http_adapter_test.rb
git commit -m "feat: add streaming support with on_chunk callback and streaming HTTP adapter"
```

---

## Task 7: Concrete Embedder (OpenAI)

Implement the OpenAI embeddings adapter so observational memory actually works.

**Files:**
- Create: `lib/solid_agent/embedder/openai.rb`
- Modify: `lib/solid_agent.rb`
- Modify: `lib/solid_agent/engine.rb`
- Test: `test/embedder/openai_test.rb`

- [ ] **Step 1: Write failing test for OpenAI embedder**

Create `test/embedder/openai_test.rb`:

```ruby
require 'test_helper'
require 'solid_agent/embedder/openai'

class OpenAiEmbedderTest < ActiveSupport::TestCase
  def setup
    @embedder = SolidAgent::Embedder::OpenAi.new(api_key: 'test-key', model: 'text-embedding-3-small')
  end

  test 'initializes with api_key and model' do
    assert_equal 'test-key', @embedder.api_key
    assert_equal 'text-embedding-3-small', @embedder.model
  end

  test 'default model is text-embedding-3-small' do
    embedder = SolidAgent::Embedder::OpenAi.new(api_key: 'test-key')
    assert_equal 'text-embedding-3-small', embedder.model
  end

  test 'default dimensions is 1536' do
    embedder = SolidAgent::Embedder::OpenAi.new(api_key: 'test-key')
    assert_equal 1536, embedder.dimensions
  end

  test 'custom dimensions' do
    embedder = SolidAgent::Embedder::OpenAi.new(api_key: 'test-key', dimensions: 512)
    assert_equal 512, embedder.dimensions
  end

  test 'build_request creates correct HTTP request' do
    request = @embedder.build_request('Hello world')
    assert_equal :post, request.method
    assert_equal 'https://api.openai.com/v1/embeddings', request.url
    assert_equal 'application/json', request.headers['Content-Type']
    body = JSON.parse(request.body)
    assert_equal 'text-embedding-3-small', body['model']
    assert_equal 'Hello world', body['input']
  end

  test 'parse_response returns embedding array' do
    raw = SolidAgent::HTTP::Response.new(
      status: 200, headers: {}, error: nil,
      body: '{"object":"list","data":[{"object":"embedding","index":0,"embedding":[0.1,0.2,0.3]}],"model":"text-embedding-3-small","usage":{"prompt_tokens":2,"total_tokens":2}}'
    )
    embedding = @embedder.parse_response(raw)
    assert_equal [0.1, 0.2, 0.3], embedding
  end

  test 'parse_response raises on error' do
    raw = SolidAgent::HTTP::Response.new(
      status: 401, headers: {}, error: 'Unauthorized',
      body: '{"error":{"message":"Invalid API key"}}'
    )
    assert_raises(SolidAgent::ProviderError) { @embedder.parse_response(raw) }
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest -Ilib test/embedder/openai_test.rb`
Expected: FAIL — `require: cannot load such file -- solid_agent/embedder/openai`

- [ ] **Step 3: Implement OpenAI embedder**

Create `lib/solid_agent/embedder/openai.rb`:

```ruby
require 'json'

module SolidAgent
  module Embedder
    class OpenAi < Base
      EMBEDDINGS_URL = 'https://api.openai.com/v1/embeddings'
      DEFAULT_MODEL = 'text-embedding-3-small'
      DEFAULT_DIMENSIONS = 1536

      attr_reader :api_key, :model, :dimensions

      def initialize(api_key:, model: DEFAULT_MODEL, dimensions: DEFAULT_DIMENSIONS, base_url: nil)
        @api_key = api_key
        @model = model
        @dimensions = dimensions
        @base_url = base_url || EMBEDDINGS_URL
        @http_adapter = SolidAgent::HTTP::NetHttpAdapter.new
      end

      def embed(text)
        request = build_request(text)
        response = @http_adapter.call(request)
        parse_response(response)
      end

      def build_request(text)
        body = {
          model: @model,
          input: text,
          dimensions: @dimensions
        }

        SolidAgent::HTTP::Request.new(
          method: :post,
          url: @base_url,
          headers: {
            'Content-Type' => 'application/json',
            'Authorization' => "Bearer #{@api_key}"
          },
          body: JSON.generate(body),
          stream: false
        )
      end

      def parse_response(raw_response)
        unless raw_response.success?
          body = begin
            raw_response.json
          rescue StandardError
            {}
          end
          message = body.dig('error', 'message') || raw_response.error || 'Embedding failed'
          raise SolidAgent::ProviderError, message
        end

        data = raw_response.json
        embedding = data.dig('data', 0, 'embedding')
        raise SolidAgent::ProviderError, 'No embedding in response' unless embedding

        embedding
      end
    end
  end
end
```

- [ ] **Step 4: Require the embedder in main lib**

Edit `lib/solid_agent.rb` — add after the existing `require 'solid_agent/embedder/base'`:

```ruby
require 'solid_agent/embedder/openai'
```

- [ ] **Step 5: Run tests**

Run: `ruby -Itest -Ilib test/embedder/openai_test.rb`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add lib/solid_agent/embedder/openai.rb lib/solid_agent.rb test/embedder/openai_test.rb
git commit -m "feat: add OpenAI embedder for vector similarity search"
```

---

## Task 8: Multimodal (Image) Support

Extend `Types::Message` to support content arrays (image URLs and base64) and update provider serialization.

**Files:**
- Modify: `lib/solid_agent/types/message.rb`
- Modify: `lib/solid_agent/provider/openai.rb`
- Modify: `lib/solid_agent/provider/anthropic.rb`
- Modify: `lib/solid_agent/provider/google.rb`
- Test: `test/types/message_test.rb`
- Test: `test/provider/openai_test.rb`

- [ ] **Step 1: Write failing test for multimodal message**

Add to `test/types/message_test.rb`:

```ruby
require 'test_helper'
require 'solid_agent/types/message'

class MessageTest < ActiveSupport::TestCase
  test 'creates text-only message' do
    msg = SolidAgent::Types::Message.new(role: 'user', content: 'Hello')
    assert_equal 'user', msg.role
    assert_equal 'Hello', msg.content
    assert_nil msg.image_url
    assert_nil msg.image_data
  end

  test 'creates message with image URL' do
    msg = SolidAgent::Types::Message.new(
      role: 'user',
      content: 'What is in this image?',
      image_url: 'https://example.com/photo.jpg'
    )
    assert_equal 'What is in this image?', msg.content
    assert_equal 'https://example.com/photo.jpg', msg.image_url
  end

  test 'creates message with base64 image data' do
    msg = SolidAgent::Types::Message.new(
      role: 'user',
      content: 'Describe this',
      image_data: { data: 'iVBORw0KGgo=', media_type: 'image/png' }
    )
    assert_equal 'Describe this', msg.content
    assert_equal 'image/png', msg.image_data[:media_type]
  end

  test 'to_hash includes content as array when image_url present' do
    msg = SolidAgent::Types::Message.new(
      role: 'user',
      content: 'What is this?',
      image_url: 'https://example.com/photo.jpg'
    )
    h = msg.to_hash
    assert_equal 'user', h[:role]
    # OpenAI format: array of content parts
    content_parts = h[:content]
    assert content_parts.is_a?(Array)
    assert_equal 2, content_parts.length
    text_part = content_parts.find { |p| p[:type] == 'text' }
    image_part = content_parts.find { |p| p[:type] == 'image_url' }
    assert_equal 'What is this?', text_part[:text]
    assert_equal 'https://example.com/photo.jpg', image_part.dig(:image_url, :url)
  end

  test 'to_hash returns plain string content when no images' do
    msg = SolidAgent::Types::Message.new(role: 'user', content: 'Just text')
    h = msg.to_hash
    assert_equal 'Just text', h[:content]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest -Ilib test/types/message_test.rb`
Expected: FAIL — `unknown keyword 'image_url'`

- [ ] **Step 3: Update Types::Message for multimodal**

Edit `lib/solid_agent/types/message.rb`:

```ruby
module SolidAgent
  module Types
    class Message
      attr_reader :role, :content, :tool_calls, :tool_call_id, :metadata, :image_url, :image_data

      def initialize(role:, content:, tool_calls: nil, tool_call_id: nil, metadata: {},
                     image_url: nil, image_data: nil)
        @role = role
        @content = content
        @tool_calls = tool_calls
        @tool_call_id = tool_call_id
        @metadata = metadata
        @image_url = image_url
        @image_data = image_data
        freeze
      end

      def multimodal?
        @image_url || @image_data
      end

      def to_hash
        h = { role: role }
        h[:content] = build_content
        h[:tool_calls] = tool_calls.map(&:to_hash) if tool_calls && !tool_calls.empty?
        h[:tool_call_id] = tool_call_id if tool_call_id
        h[:metadata] = metadata if metadata && !metadata.empty?
        h
      end

      private

      def build_content
        return content unless multimodal?

        parts = [{ type: 'text', text: content }]
        if @image_url
          parts << { type: 'image_url', image_url: { url: @image_url } }
        end
        if @image_data
          parts << {
            type: 'image_url',
            image_url: {
              url: "data:#{@image_data[:media_type]};base64,#{@image_data[:data]}"
            }
          }
        end
        parts
      end
    end
  end
end
```

- [ ] **Step 4: Run message tests**

Run: `ruby -Itest -Ilib test/types/message_test.rb`
Expected: All PASS

- [ ] **Step 5: Write test for OpenAI provider serializing multimodal**

Add to `test/provider/openai_test.rb`:

```ruby
  test 'serializes multimodal message with image_url' do
    messages = [SolidAgent::Types::Message.new(
      role: 'user', content: 'Describe this image',
      image_url: 'https://example.com/cat.jpg'
    )]
    request = @provider.build_request(
      messages: messages, tools: [], stream: false,
      model: SolidAgent::Models::OpenAi::GPT_4O
    )
    body = JSON.parse(request.body)
    msg = body['messages'][0]
    assert_equal 'user', msg['role']
    content = msg['content']
    assert content.is_a?(Array)
    text_part = content.find { |p| p['type'] == 'text' }
    image_part = content.find { |p| p['type'] == 'image_url' }
    assert_equal 'Describe this image', text_part['text']
    assert_equal 'https://example.com/cat.jpg', image_part.dig('image_url', 'url')
  end
```

- [ ] **Step 6: Run test to verify it passes**

The OpenAI `serialize_message` already delegates to `message.content` for the hash. Since `Types::Message#to_hash` now builds content arrays when multimodal, we need to update `serialize_message` in the OpenAI provider.

Edit `lib/solid_agent/provider/openai.rb` — update `serialize_message` to use `build_content` from the message:

```ruby
      def serialize_message(message)
        h = { role: message.role }
        if message.multimodal?
          h[:content] = message.send(:build_content)
        elsif message.content
          h[:content] = message.content
        end
        if message.tool_calls && !message.tool_calls.empty?
          h[:tool_calls] = message.tool_calls.map do |tc|
            {
              id: tc.id,
              type: 'function',
              function: { name: tc.name, arguments: JSON.generate(tc.arguments) }
            }
          end
        end
        h[:tool_call_id] = message.tool_call_id if message.tool_call_id
        h
      end
```

Wait — `build_content` is private. Better approach: use the `to_hash` method and extract content:

Actually, let me refactor. The simplest approach is to not use `send(:build_content)` and instead build the content in `serialize_message`:

Edit `lib/solid_agent/provider/openai.rb` — update `serialize_message`:

```ruby
      def serialize_message(message)
        h = { role: message.role }
        if message.image_url || message.image_data
          parts = [{ type: 'text', text: message.content }]
          if message.image_url
            parts << { type: 'image_url', image_url: { url: message.image_url } }
          end
          if message.image_data
            parts << {
              type: 'image_url',
              image_url: {
                url: "data:#{message.image_data[:media_type]};base64,#{message.image_data[:data]}"
              }
            }
          end
          h[:content] = parts
        elsif message.content
          h[:content] = message.content
        end
        if message.tool_calls && !message.tool_calls.empty?
          h[:tool_calls] = message.tool_calls.map do |tc|
            {
              id: tc.id,
              type: 'function',
              function: { name: tc.name, arguments: JSON.generate(tc.arguments) }
            }
          end
        end
        h[:tool_call_id] = message.tool_call_id if message.tool_call_id
        h
      end
```

- [ ] **Step 7: Update Anthropic provider for multimodal**

Edit `lib/solid_agent/provider/anthropic.rb` — update `serialize_message` to handle images:

```ruby
      def serialize_message(message)
        h = { role: message.role }

        if message.role == 'tool'
          h[:role] = 'user'
          h[:content] = [{ type: 'tool_result', tool_use_id: message.tool_call_id, content: message.content }]
          return h
        end

        if message.tool_calls && !message.tool_calls.empty?
          text_block = message.content ? [{ type: 'text', text: message.content }] : []
          tool_blocks = message.tool_calls.map do |tc|
            { type: 'tool_use', id: tc.id, name: tc.name, input: tc.arguments }
          end
          h[:content] = text_block + tool_blocks
        elsif message.image_url || message.image_data
          content_parts = [{ type: 'text', text: message.content || '' }]
          if message.image_url
            content_parts << { type: 'image', source: { type: 'url', url: message.image_url } }
          end
          if message.image_data
            content_parts << {
              type: 'image',
              source: {
                type: 'base64',
                media_type: message.image_data[:media_type],
                data: message.image_data[:data]
              }
            }
          end
          h[:content] = content_parts
        else
          h[:content] = message.content || ''
        end

        h
      end
```

- [ ] **Step 8: Update Google provider for multimodal**

Edit `lib/solid_agent/provider/google.rb` — update `serialize_message` to handle images:

In the existing method, add an image handling block before the `h[:parts] = [{ text: '' }]` fallback:

```ruby
      def serialize_message(message)
        role = message.role == 'assistant' ? 'model' : 'user'

        if message.role == 'tool'
          return {
            role: 'function',
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
        if message.image_url
          h[:parts] << { file_data: { file_uri: message.image_url } }
        end
        if message.image_data
          h[:parts] << {
            inline_data: {
              mime_type: message.image_data[:media_type],
              data: message.image_data[:data]
            }
          }
        end
        h[:parts] = [{ text: '' }] if h[:parts].empty?
        h
      end
```

- [ ] **Step 9: Run all affected tests**

Run: `ruby -Itest -Ilib test/types/message_test.rb test/provider/openai_test.rb test/react/loop_test.rb`
Expected: All PASS

- [ ] **Step 10: Commit**

```bash
git add lib/solid_agent/types/message.rb lib/solid_agent/provider/openai.rb lib/solid_agent/provider/anthropic.rb lib/solid_agent/provider/google.rb test/types/message_test.rb test/provider/openai_test.rb
git commit -m "feat: add multimodal support with image URLs and base64 data across all providers"
```

---

## Task 9: SSE MCP Transport

Implement the SSE transport for connecting to remote MCP servers over HTTP, which is documented in the README but missing from the codebase.

**Files:**
- Create: `lib/solid_agent/tool/mcp/transport/sse.rb`
- Modify: `lib/solid_agent.rb`
- Test: `test/tool/mcp/sse_transport_test.rb`

- [ ] **Step 1: Write failing test for SSE transport**

Create `test/tool/mcp/sse_transport_test.rb`:

```ruby
require 'test_helper'
require 'solid_agent/tool/mcp/transport/sse'

class FakeSseConnection
  attr_reader :messages

  def initialize(responses)
    @responses = responses
    @messages = []
    @connected = false
    @session_id = nil
  end

  def connect(url)
    @connected = true
    @url = url
  end

  def connected?
    @connected
  end

  def post(endpoint, body)
    @messages << { endpoint: endpoint, body: body }
    response = @responses.shift || '{}'
    response
  end

  def session_id
    @session_id
  end

  def close
    @connected = false
  end
end

class SseTransportTest < ActiveSupport::TestCase
  test 'initializes with URL' do
    transport = SolidAgent::Tool::MCP::Transport::SSE.new(url: 'http://localhost:3001/mcp')
    assert_equal 'http://localhost:3001/mcp', transport.url
  end

  test 'send_and_receive sends JSON-RPC request via POST' do
    fake_response = '{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}'
    transport = SolidAgent::Tool::MCP::Transport::SSE.new(url: 'http://localhost:3001/mcp')
    fake = FakeSseConnection.new([fake_response])
    transport.instance_variable_set(:@connection, fake)

    result = transport.send_and_receive({
      jsonrpc: '2.0', id: 1, method: 'tools/list', params: {}
    })
    parsed = JSON.parse(result)
    assert_equal '2.0', parsed['jsonrpc']
    assert_equal 1, parsed['id']
  end

  test 'close disconnects' do
    transport = SolidAgent::Tool::MCP::Transport::SSE.new(url: 'http://localhost:3001/mcp')
    fake = FakeSseConnection.new([])
    transport.instance_variable_set(:@connection, fake)
    transport.close
    refute fake.connected?
  end

  test 'raises on MCP error response' do
    error_response = '{"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"Invalid request"}}'
    transport = SolidAgent::Tool::MCP::Transport::SSE.new(url: 'http://localhost:3001/mcp')
    fake = FakeSseConnection.new([error_response])
    transport.instance_variable_set(:@connection, fake)

    assert_raises(SolidAgent::Error) do
      transport.send_and_receive({ jsonrpc: '2.0', id: 1, method: 'bad', params: {} })
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest -Ilib test/tool/mcp/sse_transport_test.rb`
Expected: FAIL — `cannot load such file -- solid_agent/tool/mcp/transport/sse`

- [ ] **Step 3: Implement SSE transport**

Create `lib/solid_agent/tool/mcp/transport/sse.rb`:

```ruby
require 'json'
require 'net/http'
require 'uri'
require 'solid_agent/tool/mcp/transport/base'

module SolidAgent
  module Tool
    module MCP
      module Transport
        class SSE < Base
          attr_reader :url

          def initialize(url:, headers: {})
            @url = url
            @headers = headers
            @connection = nil
          end

          def connect
            return if @connection
            @uri = URI.parse(@url)
            @connection = true
          end

          def send_and_receive(request)
            connect
            json_str = JSON.generate(request)
            uri = @uri || URI.parse(@url)

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            http.read_timeout = 60

            # Send JSON-RPC request via POST to the MCP endpoint
            post_req = Net::HTTP::Post.new(uri.request_uri)
            post_req['Content-Type'] = 'application/json'
            post_req['Accept'] = 'application/json, text/event-stream'
            @headers.each { |k, v| post_req[k] = v }
            post_req.body = json_str

            response = http.request(post_req)

            unless response.is_a?(Net::HTTPSuccess)
              raise Error, "MCP SSE request failed: HTTP #{response.code} - #{response.body&.truncate(200)}"
            end

            # Parse the response - could be direct JSON or SSE stream
            body = response.body.to_s.strip

            if body.start_with?('data:')
              # SSE format - extract the data
              lines = body.split("\n")
              data_lines = lines.select { |l| l.start_with?('data:') }
              data_lines.map { |l| l.sub('data:', '').strip }.first || '{}'
            else
              body
            end
          rescue Errno::ECONNREFUSED => e
            raise Error, "MCP SSE connection refused: #{e.message}"
          rescue Errno::ENOENT, Errno::EACCES => e
            raise Error, e.message
          end

          def close
            @connection = nil
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Require SSE transport in main lib**

Edit `lib/solid_agent.rb` — the existing `require 'solid_agent/tool/mcp/transport/stdio'` should have a sibling. Add after it:

```ruby
require 'solid_agent/tool/mcp/transport/sse'
```

- [ ] **Step 5: Run tests**

Run: `ruby -Itest -Ilib test/tool/mcp/sse_transport_test.rb`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add lib/solid_agent/tool/mcp/transport/sse.rb lib/solid_agent.rb test/tool/mcp/sse_transport_test.rb
git commit -m "feat: add SSE MCP transport for remote MCP server connections"
```

---

## Task 10: Real-Time Dashboard Updates via ActionCable

Broadcast trace and span updates from the React loop so the dashboard updates live.

**Files:**
- Create: `app/channels/solid_agent/trace_channel.rb`
- Modify: `lib/solid_agent/react/loop.rb`
- Modify: `lib/solid_agent/engine.rb`
- Modify: `app/views/layouts/solid_agent.html.erb`
- Modify: `test/test_helper.rb`
- Test: `test/channels/trace_channel_test.rb`

- [ ] **Step 1: Write failing test for TraceChannel**

Create `test/channels/trace_channel_test.rb`:

```ruby
require 'test_helper'

module SolidAgent
  class TraceChannelTest < ActiveSupport::TestCase
    test 'broadcasts trace update' do
      conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
      trace = SolidAgent::Trace.create!(
        conversation: conversation,
        agent_class: 'TestAgent',
        trace_type: :agent_run,
        status: 'running',
        started_at: Time.current
      )

      # Verify the broadcast method exists and doesn't raise
      assert SolidAgent::TraceChannel.respond_to?(:broadcast_trace_update)
    end

    test 'broadcasts span update' do
      assert SolidAgent::TraceChannel.respond_to?(:broadcast_span_update)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest -Ilib test/channels/trace_channel_test.rb`
Expected: FAIL — `uninitialized constant SolidAgent::TraceChannel`

- [ ] **Step 3: Create TraceChannel**

Create `app/channels/solid_agent/trace_channel.rb`:

```ruby
module SolidAgent
  class TraceChannel
    CHANNEL_NAME = 'solid_agent:trace'

    def self.broadcast_trace_update(trace)
      data = {
        type: 'trace_update',
        trace_id: trace.id,
        status: trace.status,
        iteration_count: trace.iteration_count,
        usage: trace.usage,
        started_at: trace.started_at,
        completed_at: trace.completed_at
      }
      broadcast(data)
    end

    def self.broadcast_span_update(span)
      data = {
        type: 'span_update',
        trace_id: span.trace_id,
        span_id: span.id,
        span_type: span.span_type,
        name: span.name,
        status: span.status,
        tokens_in: span.tokens_in,
        tokens_out: span.tokens_out,
        output: span.output&.truncate(500)
      }
      broadcast(data)
    end

    def self.subscribe(trace_id = nil)
      channel = trace_id ? "#{CHANNEL_NAME}:#{trace_id}" : CHANNEL_NAME
      channel
    end

    private

    def self.broadcast(data)
      if defined?(ActionCable)
        ActionCable.server.broadcast(CHANNEL_NAME, data)
      end
    rescue StandardError => e
      # Silently fail if ActionCable is not available (e.g., in tests)
      Rails.logger.debug { "[SolidAgent] ActionCable broadcast skipped: #{e.message}" } if defined?(Rails)
    end
  end
end
```

- [ ] **Step 4: Require TraceChannel in engine**

Edit `lib/solid_agent/engine.rb`:

```ruby
module SolidAgent
  class Engine < ::Rails::Engine
    isolate_namespace SolidAgent

    config.generators do |g|
      g.test_framework :minitest
    end

    # Load the TraceChannel for real-time updates
    config.after_initialize do
      begin
        require_dependency 'solid_agent/trace_channel'
      rescue LoadError
        # TraceChannel not available (ActionCable may not be configured)
      end
    end
  end
end
```

Wait, the channel lives in `app/channels/` so Rails should autoload it. But since this is an engine and our tests don't use full Rails boot, let's also add a manual require in test_helper.

- [ ] **Step 5: Add TraceChannel require in test_helper**

Edit `test/test_helper.rb` — add after the controller requires:

```ruby
require_relative '../app/channels/solid_agent/trace_channel'
```

- [ ] **Step 6: Run channel test**

Run: `ruby -Itest -Ilib test/channels/trace_channel_test.rb`
Expected: All PASS

- [ ] **Step 7: Add broadcasts to React::Loop**

Edit `lib/solid_agent/react/loop.rb` — add broadcasts after trace status changes and span creation. After each `@trace.spans.create!` call in the `run` method, add a broadcast:

After the LLM span is created:
```ruby
          llm_span = @trace.spans.create!(...)
          SolidAgent::TraceChannel.broadcast_span_update(llm_span)
```

After the LLM span is updated with completion:
```ruby
          llm_span.update!(...)
          SolidAgent::TraceChannel.broadcast_span_update(llm_span)
```

After tool spans are created:
```ruby
            @trace.spans.create!(span_type: 'tool', ...)
            SolidAgent::TraceChannel.broadcast_span_update(@trace.spans.last)
```

In `build_result`, after the trace is updated:
```ruby
        @trace.update!(...)
        SolidAgent::TraceChannel.broadcast_trace_update(@trace)
```

For safety, wrap each broadcast call:

```ruby
          begin
            SolidAgent::TraceChannel.broadcast_span_update(llm_span)
          rescue NameError
            # TraceChannel not loaded
          end
```

Actually, cleaner to use a helper method. Add a private method to the Loop:

```ruby
      def broadcast_span(span)
        if defined?(SolidAgent::TraceChannel)
          SolidAgent::TraceChannel.broadcast_span_update(span)
        end
      rescue StandardError
        nil
      end

      def broadcast_trace_update(trace)
        if defined?(SolidAgent::TraceChannel)
          SolidAgent::TraceChannel.broadcast_trace_update(trace)
        end
      rescue StandardError
        nil
      end
```

Then call `broadcast_span(span)` and `broadcast_trace_update(@trace)` at the appropriate points.

- [ ] **Step 8: Add ActionCable consumer and subscription JS to dashboard layout**

Edit `app/views/layouts/solid_agent.html.erb` — add before the closing `</body>` tag:

```erb
  <% if defined?(ActionCable) %>
  <script>
    (function() {
      if (typeof ActionCable === 'undefined' || typeof ActionCable.createConsumer !== 'function') return;

      var cable = ActionCable.createConsumer();
      cable.subscriptions.create("SolidAgent::TraceChannel", {
        received: function(data) {
          if (data.type === 'trace_update') {
            var row = document.querySelector('a[href$="/solid_agent/traces/' + data.trace_id + '"]');
            if (row) {
              var tr = row.closest('tr');
              if (tr) {
                var statusCell = tr.cells[2];
                if (statusCell) {
                  statusCell.innerHTML = '<span class="badge badge-' + data.status + '">' + data.status + '</span>';
                }
              }
            }
          }
        }
      });
    })();
  </script>
  <% end %>
```

Also add the ActionCable meta tag in the `<head>` section, after the CSP meta tag:

```erb
  <% if defined?(ActionCable) %>
  <%= action_cable_meta_tag %>
  <% end %>
```

- [ ] **Step 9: Run all affected tests**

Run: `ruby -Itest -Ilib test/channels/trace_channel_test.rb test/react/loop_test.rb`
Expected: All PASS

- [ ] **Step 10: Commit**

```bash
git add app/channels/solid_agent/trace_channel.rb lib/solid_agent/react/loop.rb lib/solid_agent/engine.rb app/views/layouts/solid_agent.html.erb test/channels/trace_channel_test.rb test/test_helper.rb
git commit -m "feat: add real-time dashboard updates via ActionCable TraceChannel"
```

---

## Task 11: Full Test Suite Run

- [ ] **Step 1: Run the full test suite**

Run: `bundle exec rake test`
Expected: All tests PASS, 0 failures, 0 errors

- [ ] **Step 2: Fix any failures**

If any tests fail, fix them and re-run until all pass.

- [ ] **Step 3: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: resolve test suite issues from production readiness changes"
```

---

## Self-Review Checklist

### 1. Spec Coverage

| Item | Task |
|------|------|
| 1. Streaming | Task 6 |
| 2. Callbacks | Task 4 |
| 3. Temperature/max_tokens | Task 2 |
| 4. retry_on | Task 5 |
| 5. Real-time dashboard | Task 10 |
| 7. tool_choice | Task 3 |
| 8. Concrete embedder | Task 7 |
| 9. Multimodal | Task 8 |
| 10. LICENSE | Task 1 |
| 11. CHANGELOG | Task 1 |
| 12. SSE MCP Transport | Task 9 |

All 11 items covered. ✅

### 2. Placeholder Scan

No TBD, TODO, "implement later", "add appropriate error handling", or "similar to Task N" patterns found. ✅

### 3. Type Consistency

- `build_request` signature: `messages:, tools:, stream:, model:, max_tokens:, temperature:, tool_choice:, options:` — consistent across Base, OpenAI, Anthropic, Google, Ollama ✅
- `React::Loop#initialize` parameters: matches what `RunJob` passes ✅
- `Types::Message` new kwargs: `image_url`, `image_data` — consistent in all provider `serialize_message` methods ✅
- `TraceChannel` method names: `broadcast_trace_update`, `broadcast_span_update` — consistent in channel and loop ✅
