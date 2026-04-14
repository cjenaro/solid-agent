# Plan 5: Agent Runtime

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the agent definition DSL and ReAct loop runtime that executes agent runs as Solid Queue jobs with full traceability, resumability, and safety guards.

**Architecture:** Agents are defined as classes inheriting from `SolidAgent::Base` with an Active Job-inspired DSL. The ReAct loop (THINK → EVALUATE → ACT → OBSERVE) runs inside `SolidAgent::RunJob`, backed by Solid Queue. Each iteration writes spans and messages to the DB, making runs always resumable. The runtime integrates the provider, memory, and tool layers built in Plans 2-4.

**Tech Stack:** Ruby 3.3+, Rails 8.0+, Solid Queue, ActiveJob, Minitest

---

## File Structure

```
lib/solid_agent/
├── agent/
│   ├── base.rb
│   ├── dsl.rb
│   ├── result.rb
│   └── registry.rb
├── run_job.rb
├── react/
│   ├── loop.rb
│   └── observer.rb

test/
├── agent/
│   ├── base_test.rb
│   ├── dsl_test.rb
│   ├── result_test.rb
│   └── registry_test.rb
├── run_job_test.rb
├── react/
│   ├── loop_test.rb
│   └── observer_test.rb
```

---

### Task 1: Agent Result

**Files:**
- Create: `lib/solid_agent/agent/result.rb`
- Test: `test/agent/result_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/agent/result_test.rb
require "test_helper"
require "solid_agent/agent/result"

class AgentResultTest < ActiveSupport::TestCase
  test "creates result with output" do
    result = SolidAgent::Agent::Result.new(
      trace_id: 1,
      output: "The answer is 42",
      usage: SolidAgent::Usage.new(input_tokens: 100, output_tokens: 50),
      iterations: 3
    )
    assert_equal "The answer is 42", result.output
    assert_equal 150, result.usage.total_tokens
    assert_equal 3, result.iterations
  end

  test "result status predicates" do
    success = SolidAgent::Agent::Result.new(trace_id: 1, output: "done", status: :completed)
    assert success.completed?
    assert_not success.failed?

    failed = SolidAgent::Agent::Result.new(trace_id: 1, output: nil, status: :failed, error: "boom")
    assert failed.failed?
    assert_not failed.completed?
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/agent/result_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement Result**

```ruby
# lib/solid_agent/agent/result.rb
module SolidAgent
  module Agent
    class Result
      attr_reader :trace_id, :output, :usage, :iterations, :status, :error

      def initialize(trace_id:, output:, usage:, iterations:, status: :completed, error: nil)
        @trace_id = trace_id
        @output = output
        @usage = usage
        @iterations = iterations
        @status = status
        @error = error
      end

      def completed?
        @status == :completed
      end

      def failed?
        @status == :failed
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/agent/result_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Agent::Result value object"
```

---

### Task 2: Agent DSL

**Files:**
- Create: `lib/solid_agent/agent/dsl.rb`
- Test: `test/agent/dsl_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/agent/dsl_test.rb
require "test_helper"
require "solid_agent/agent/dsl"
require "solid_agent/agent/base"

class TestAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  max_tokens 4096
  temperature 0.7

  instructions "You are a test agent."

  memory :sliding_window, max_messages: 20

  tool :greet, description: "Say hello" do |name:|
    "Hello, #{name}!"
  end

  concurrency 2
  max_iterations 10
  max_tokens_per_run 50_000
  timeout 2.minutes
end

class AgentDSLTest < ActiveSupport::TestCase
  test "stores provider" do
    assert_equal :openai, TestAgent.agent_provider
  end

  test "stores model" do
    assert_equal SolidAgent::Models::OpenAi::GPT_4O, TestAgent.agent_model
  end

  test "stores max_tokens" do
    assert_equal 4096, TestAgent.agent_max_tokens
  end

  test "stores temperature" do
    assert_equal 0.7, TestAgent.agent_temperature
  end

  test "stores instructions" do
    assert_equal "You are a test agent.", TestAgent.agent_instructions
  end

  test "stores memory config" do
    config = TestAgent.agent_memory_config
    assert_equal :sliding_window, config[:strategy]
    assert_equal 20, config[:max_messages]
  end

  test "registers tools in registry" do
    assert TestAgent.agent_tool_registry.registered?("greet")
  end

  test "stores concurrency" do
    assert_equal 2, TestAgent.agent_concurrency
  end

  test "stores safety guards" do
    assert_equal 10, TestAgent.agent_max_iterations
    assert_equal 50_000, TestAgent.agent_max_tokens_per_run
    assert_equal 120, TestAgent.agent_timeout
  end

  test "default values" do
    bare = Class.new(SolidAgent::Base)
    assert_equal :openai, bare.agent_provider
    assert_equal 1, bare.agent_concurrency
    assert_equal 25, bare.agent_max_iterations
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/agent/dsl_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement DSL module**

```ruby
# lib/solid_agent/agent/dsl.rb
require "solid_agent/tool/inline_tool"
require "solid_agent/tool/registry"

module SolidAgent
  module Agent
    module DSL
      extend ActiveSupport::Concern

      class_methods do
        def provider(name)
          @agent_provider = name
        end

        def agent_provider
          @agent_provider || :openai
        end

        def model(model_const)
          @agent_model = model_const
        end

        def agent_model
          @agent_model || SolidAgent::Models::OpenAi::GPT_4O
        end

        def max_tokens(tokens)
          @agent_max_tokens = tokens
        end

        def agent_max_tokens
          @agent_max_tokens || 4096
        end

        def temperature(temp)
          @agent_temperature = temp
        end

        def agent_temperature
          @agent_temperature || 0.7
        end

        def instructions(text)
          @agent_instructions = text
        end

        def agent_instructions
          @agent_instructions || ""
        end

        def memory(strategy, **opts)
          @agent_memory_config = { strategy: strategy }.merge(opts)
        end

        def agent_memory_config
          @agent_memory_config || { strategy: :sliding_window, max_messages: 50 }
        end

        def tool(name_or_class, description: nil, &block)
          if block
            agent_tool_registry.register(
              SolidAgent::Tool::InlineTool.new(
                name: name_or_class,
                description: description || name_or_class.to_s,
                parameters: [],
                block: block
              )
            )
          else
            agent_tool_registry.register(name_or_class)
          end
        end

        def agent_tool_registry
          @agent_tool_registry ||= SolidAgent::Tool::Registry.new
        end

        def concurrency(max)
          @agent_concurrency = max
        end

        def agent_concurrency
          @agent_concurrency || 1
        end

        def max_iterations(count)
          @agent_max_iterations = count
        end

        def agent_max_iterations
          @agent_max_iterations || 25
        end

        def max_tokens_per_run(tokens)
          @agent_max_tokens_per_run = tokens
        end

        def agent_max_tokens_per_run
          @agent_max_tokens_per_run || 100_000
        end

        def timeout(duration)
          @agent_timeout = duration
        end

        def agent_timeout
          @agent_timeout || 300
        end

        def retry_on(error_class, attempts: 3)
          @agent_retry_config = { error: error_class, attempts: attempts }
        end

        def require_approval(*tool_names)
          @agent_approval_required = tool_names.map(&:to_s)
        end

        def agent_approval_required
          @agent_approval_required || []
        end

        def before_invoke(method_name)
          @before_invoke_callbacks ||= []
          @before_invoke_callbacks << method_name
        end

        def after_invoke(method_name)
          @after_invoke_callbacks ||= []
          @after_invoke_callbacks << method_name
        end

        def on_tool_error(method_name = nil, retry: nil, fallback: nil)
          @on_tool_error_config = { method: method_name, retry: binding.local_variable_get(:retry), fallback: fallback }
        end

        def on_context_overflow(method_name)
          @on_context_overflow = method_name
        end
      end
    end
  end
end
```

- [ ] **Step 4: Implement SolidAgent::Base**

```ruby
# lib/solid_agent/agent/base.rb
require "solid_agent/agent/dsl"

module SolidAgent
  class Base
    include Agent::DSL
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/agent/dsl_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Agent DSL with class-level configuration"
```

---

### Task 3: Agent Registry

**Files:**
- Create: `lib/solid_agent/agent/registry.rb`
- Test: `test/agent/registry_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/agent/registry_test.rb
require "test_helper"
require "solid_agent/agent/registry"
require "solid_agent/agent/base"

class RegisteredAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  instructions "Test"
end

class AgentRegistryTest < ActiveSupport::TestCase
  def setup
    @registry = SolidAgent::Agent::Registry.new
  end

  test "registers agent class" do
    @registry.register(RegisteredAgent)
    assert @registry.registered?("RegisteredAgent")
  end

  test "resolves agent by name" do
    @registry.register(RegisteredAgent)
    assert_equal RegisteredAgent, @registry.resolve("RegisteredAgent")
  end

  test "lists all registered agents" do
    @registry.register(RegisteredAgent)
    agents = @registry.all
    assert_equal 1, agents.length
    assert_equal "RegisteredAgent", agents.first.name
    assert_equal RegisteredAgent, agents.first.klass
  end

  test "raises for unknown agent" do
    assert_raises(SolidAgent::Error) { @registry.resolve("NonExistent") }
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/agent/registry_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement Agent Registry**

```ruby
# lib/solid_agent/agent/registry.rb
module SolidAgent
  module Agent
    class Registry
      Entry = Struct.new(:name, :klass)

      def initialize
        @agents = {}
      end

      def register(agent_class)
        name = agent_class.name
        raise Error, "Agent class must have a name" unless name
        @agents[name] = Entry.new(name, agent_class)
      end

      def resolve(name)
        entry = @agents[name]
        raise Error, "Agent not found: #{name}" unless entry
        entry.klass
      end

      def registered?(name)
        @agents.key?(name)
      end

      def all
        @agents.values
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/agent/registry_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Agent::Registry"
```

---

### Task 4: ReAct Observer

**Files:**
- Create: `lib/solid_agent/react/observer.rb`
- Test: `test/react/observer_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/react/observer_test.rb
require "test_helper"
require "solid_agent/react/observer"

class ReactObserverTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
    @trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: "TestAgent",
      trace_type: :agent_run,
      started_at: Time.current
    )
  end

  test "detects max iterations exceeded" do
    observer = SolidAgent::React::Observer.new(
      trace: @trace,
      max_iterations: 3,
      max_tokens_per_run: 100_000,
      started_at: Time.current,
      timeout: 5.minutes
    )
    @trace.update!(iteration_count: 3)
    assert observer.max_iterations_exceeded?
  end

  test "detects max iterations not exceeded" do
    observer = SolidAgent::React::Observer.new(
      trace: @trace,
      max_iterations: 3,
      max_tokens_per_run: 100_000,
      started_at: Time.current,
      timeout: 5.minutes
    )
    @trace.update!(iteration_count: 2)
    assert_not observer.max_iterations_exceeded?
  end

  test "detects token budget exceeded" do
    observer = SolidAgent::React::Observer.new(
      trace: @trace,
      max_iterations: 25,
      max_tokens_per_run: 100,
      started_at: Time.current,
      timeout: 5.minutes
    )
    @trace.update!(usage: { "input_tokens" => 60, "output_tokens" => 50 })
    assert observer.token_budget_exceeded?
  end

  test "detects timeout exceeded" do
    observer = SolidAgent::React::Observer.new(
      trace: @trace,
      max_iterations: 25,
      max_tokens_per_run: 100_000,
      started_at: 10.minutes.ago,
      timeout: 5.minutes
    )
    assert observer.timeout_exceeded?
  end

  test "detects context near limit" do
    observer = SolidAgent::React::Observer.new(
      trace: @trace,
      max_iterations: 25,
      max_tokens_per_run: 100_000,
      started_at: Time.current,
      timeout: 5.minutes
    )
    assert observer.context_near_limit?(current_tokens: 120_000, context_window: 128_000)
    assert_not observer.context_near_limit?(current_tokens: 50_000, context_window: 128_000)
  end

  test "should_stop combines all checks" do
    observer = SolidAgent::React::Observer.new(
      trace: @trace,
      max_iterations: 1,
      max_tokens_per_run: 100_000,
      started_at: Time.current,
      timeout: 5.minutes
    )
    @trace.update!(iteration_count: 1)
    stop, reason = observer.should_stop?(current_tokens: 50_000, context_window: 128_000)
    assert stop
    assert_equal :max_iterations, reason
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/react/observer_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement Observer**

```ruby
# lib/solid_agent/react/observer.rb
module SolidAgent
  module React
    class Observer
      CONTEXT_THRESHOLD = 0.85

      def initialize(trace:, max_iterations:, max_tokens_per_run:, started_at:, timeout:)
        @trace = trace
        @max_iterations = max_iterations
        @max_tokens_per_run = max_tokens_per_run
        @started_at = started_at
        @timeout = timeout
      end

      def max_iterations_exceeded?
        @trace.iteration_count >= @max_iterations
      end

      def token_budget_exceeded?
        total = (@trace.usage["input_tokens"] || 0) + (@trace.usage["output_tokens"] || 0)
        total >= @max_tokens_per_run
      end

      def timeout_exceeded?
        Time.current - @started_at > @timeout
      end

      def context_near_limit?(current_tokens:, context_window:)
        return false unless context_window && context_window > 0
        ratio = current_tokens.to_f / context_window
        ratio >= CONTEXT_THRESHOLD
      end

      def should_stop?(current_tokens:, context_window:)
        if max_iterations_exceeded?
          return [true, :max_iterations]
        end

        if token_budget_exceeded?
          return [true, :token_budget]
        end

        if timeout_exceeded?
          return [true, :timeout]
        end

        [false, nil]
      end

      def should_compact?(current_tokens:, context_window:)
        context_near_limit?(current_tokens: current_tokens, context_window: context_window)
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/react/observer_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ReAct Observer for safety guard checks"
```

---

### Task 5: ReAct Loop

**Files:**
- Create: `lib/solid_agent/react/loop.rb`
- Test: `test/react/loop_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/react/loop_test.rb
require "test_helper"
require "solid_agent/react/loop"

class FakeProvider
  attr_reader :call_count

  def initialize(responses)
    @responses = responses
    @call_count = 0
  end

  def build_request(messages:, tools:, stream:, model:, options: {})
    SolidAgent::HTTP::Request.new(
      method: :post, url: "https://fake.test/v1/chat",
      headers: {}, body: "{}", stream: false
    )
  end

  def parse_response(raw_response)
    @call_count += 1
    resp = @responses[@call_count - 1] || @responses.last
    resp
  end
end

class FakeMemory
  def build_context(messages, system_prompt:)
    messages
  end

  def compact!(messages)
    messages.last(5)
  end
end

class ReactLoopTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
    @trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: "TestAgent",
      trace_type: :agent_run,
      status: "running",
      started_at: Time.current
    )
  end

  test "simple loop: think once, no tools, done" do
    provider = FakeProvider.new([
      SolidAgent::Response.new(
        messages: [SolidAgent::Message.new(role: "assistant", content: "The answer is 42")],
        tool_calls: [],
        usage: SolidAgent::Usage.new(input_tokens: 100, output_tokens: 50),
        finish_reason: "stop"
      )
    ])
    memory = FakeMemory.new
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: SolidAgent::Tool::Registry.new, concurrency: 1)

    loop = SolidAgent::React::Loop.new(
      trace: @trace,
      provider: provider,
      memory: memory,
      execution_engine: engine,
      model: SolidAgent::Models::OpenAi::GPT_4O,
      system_prompt: "You are a test agent.",
      max_iterations: 5,
      max_tokens_per_run: 100_000,
      timeout: 5.minutes
    )

    result = loop.run([SolidAgent::Message.new(role: "user", content: "What is 6*7?")])
    assert result.completed?
    assert_equal "The answer is 42", result.output
    assert_equal 1, provider.call_count
  end

  test "loop with tool call then final answer" do
    registry = SolidAgent::Tool::Registry.new
    registry.register(SolidAgent::Tool::InlineTool.new(
      name: :add, description: "Add", parameters: [
        { name: :a, type: :integer, required: true },
        { name: :b, type: :integer, required: true }
      ],
      block: proc { |a:, b:| a + b }
    ))
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: registry, concurrency: 1)

    provider = FakeProvider.new([
      SolidAgent::Response.new(
        messages: [SolidAgent::Message.new(role: "assistant", content: nil, tool_calls: [
          SolidAgent::ToolCall.new(id: "c1", name: "add", arguments: { "a" => 3, "b" => 4 })
        ])],
        tool_calls: [SolidAgent::ToolCall.new(id: "c1", name: "add", arguments: { "a" => 3, "b" => 4 })],
        usage: SolidAgent::Usage.new(input_tokens: 50, output_tokens: 20),
        finish_reason: "tool_calls"
      ),
      SolidAgent::Response.new(
        messages: [SolidAgent::Message.new(role: "assistant", content: "3 + 4 = 7")],
        tool_calls: [],
        usage: SolidAgent::Usage.new(input_tokens: 80, output_tokens: 30),
        finish_reason: "stop"
      )
    ])

    loop = SolidAgent::React::Loop.new(
      trace: @trace,
      provider: provider,
      memory: FakeMemory.new,
      execution_engine: engine,
      model: SolidAgent::Models::OpenAi::GPT_4O,
      system_prompt: "You are helpful.",
      max_iterations: 5,
      max_tokens_per_run: 100_000,
      timeout: 5.minutes
    )

    result = loop.run([SolidAgent::Message.new(role: "user", content: "What is 3+4?")])
    assert result.completed?
    assert_equal "3 + 4 = 7", result.output
    assert_equal 2, provider.call_count
  end

  test "loop stops at max iterations" do
    always_tool = SolidAgent::Response.new(
      messages: [SolidAgent::Message.new(role: "assistant", content: nil, tool_calls: [
        SolidAgent::ToolCall.new(id: "c1", name: :ping, arguments: {})
      ])],
      tool_calls: [SolidAgent::ToolCall.new(id: "c1", name: :ping, arguments: {})],
      usage: SolidAgent::Usage.new(input_tokens: 10, output_tokens: 5),
      finish_reason: "tool_calls"
    )
    provider = FakeProvider.new([always_tool])

    registry = SolidAgent::Tool::Registry.new
    registry.register(SolidAgent::Tool::InlineTool.new(
      name: :ping, description: "Ping", parameters: [], block: proc { "pong" }
    ))
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: registry, concurrency: 1)

    loop = SolidAgent::React::Loop.new(
      trace: @trace,
      provider: provider,
      memory: FakeMemory.new,
      execution_engine: engine,
      model: SolidAgent::Models::OpenAi::GPT_4O,
      system_prompt: "Keep going",
      max_iterations: 2,
      max_tokens_per_run: 100_000,
      timeout: 5.minutes
    )

    result = loop.run([SolidAgent::Message.new(role: "user", content: "Go")])
    assert result.completed? || result.failed?
  end

  test "creates spans for each iteration" do
    provider = FakeProvider.new([
      SolidAgent::Response.new(
        messages: [SolidAgent::Message.new(role: "assistant", content: "Done")],
        tool_calls: [],
        usage: SolidAgent::Usage.new(input_tokens: 10, output_tokens: 5),
        finish_reason: "stop"
      )
    ])

    loop = SolidAgent::React::Loop.new(
      trace: @trace,
      provider: provider,
      memory: FakeMemory.new,
      execution_engine: SolidAgent::Tool::ExecutionEngine.new(registry: SolidAgent::Tool::Registry.new, concurrency: 1),
      model: SolidAgent::Models::OpenAi::GPT_4O,
      system_prompt: "Test",
      max_iterations: 5,
      max_tokens_per_run: 100_000,
      timeout: 5.minutes
    )

    loop.run([SolidAgent::Message.new(role: "user", content: "Hi")])
    @trace.reload
    assert @trace.spans.length >= 1
    think_span = @trace.spans.find { |s| s.span_type == "think" }
    assert think_span
    assert_equal 10, think_span.tokens_in
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/react/loop_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement ReAct Loop**

```ruby
# lib/solid_agent/react/loop.rb
require "solid_agent/react/observer"
require "solid_agent/agent/result"

module SolidAgent
  module React
    class Loop
      def initialize(trace:, provider:, memory:, execution_engine:, model:, system_prompt:, max_iterations:, max_tokens_per_run:, timeout:)
        @trace = trace
        @provider = provider
        @memory = memory
        @execution_engine = execution_engine
        @model = model
        @system_prompt = system_prompt
        @max_iterations = max_iterations
        @max_tokens_per_run = max_tokens_per_run
        @timeout = timeout
        @started_at = Time.current
        @accumulated_usage = Usage.new(input_tokens: 0, output_tokens: 0)
      end

      def run(messages)
        all_messages = messages.dup

        loop do
          @trace.increment!(:iteration_count)

          observer = Observer.new(
            trace: @trace,
            max_iterations: @max_iterations,
            max_tokens_per_run: @max_tokens_per_run,
            started_at: @started_at,
            timeout: @timeout
          )

          stop, reason = observer.should_stop?(
            current_tokens: @accumulated_usage.total_tokens,
            context_window: @model.context_window
          )

          if stop
            return build_result(status: :completed, output: extract_final_text(all_messages), reason: reason)
          end

          if observer.should_compact?(current_tokens: @accumulated_usage.total_tokens, context_window: @model.context_window)
            all_messages = @memory.compact!(all_messages)
            @trace.spans.create!(span_type: "observe", name: "compact", status: "completed", started_at: Time.current, completed_at: Time.current)
          end

          context = @memory.build_context(all_messages, system_prompt: @system_prompt)

          think_span = @trace.spans.create!(
            span_type: "think", name: "think_#{@trace.iteration_count}",
            status: "running", started_at: Time.current
          )

          request = @provider.build_request(
            messages: context,
            tools: @execution_engine.registry.all_schemas_hashes,
            stream: false,
            model: @model,
            max_tokens: @model.max_output
          )

          http_response = SolidAgent.configuration.http_adapter_instance.call(request)
          response = @provider.parse_response(http_response)

          think_span.update!(
            status: "completed",
            completed_at: Time.current,
            tokens_in: response.usage&.input_tokens || 0,
            tokens_out: response.usage&.output_tokens || 0,
            output: response.has_tool_calls? ? "tool_calls: #{response.tool_calls.map(&:name)}" : response.messages.first&.content&.truncate(200)
          )

          if response.usage
            @accumulated_usage = @accumulated_usage + response.usage
            @trace.update!(usage: {
              "input_tokens" => @accumulated_usage.input_tokens,
              "output_tokens" => @accumulated_usage.output_tokens
            })
          end

          assistant_msg = response.messages.first
          all_messages << assistant_msg if assistant_msg

          unless response.has_tool_calls?
            return build_result(status: :completed, output: assistant_msg&.content || "")
          end

          act_span = @trace.spans.create!(
            span_type: "act", name: "act_#{@trace.iteration_count}",
            status: "running", started_at: Time.current
          )

          tool_results = @execution_engine.execute_all(response.tool_calls)
          tool_results.each do |call_id, result|
            result_text = result.is_a?(Tool::ExecutionEngine::ToolExecutionError) ? "Error: #{result.message}" : result.to_s
            all_messages << Message.new(role: "tool", content: result_text, tool_call_id: call_id)
          end

          act_span.update!(status: "completed", completed_at: Time.current)
        end
      rescue => e
        build_result(status: :failed, output: nil, error: e.message)
      end

      private

      def build_result(status:, output:, error: nil, reason: nil)
        @trace.update!(
          status: status == :completed ? "completed" : "failed",
          completed_at: Time.current,
          output: output,
          error: error
        )

        Agent::Result.new(
          trace_id: @trace.id,
          output: output,
          usage: @accumulated_usage,
          iterations: @trace.iteration_count,
          status: status,
          error: error
        )
      end

      def extract_final_text(messages)
        messages.reverse_each do |msg|
          return msg.content if msg.role == "assistant" && msg.content && !msg.content.empty?
        end
        ""
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/react/loop_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ReAct loop with THINK-EVALUATE-ACT-OBSERVE cycle"
```

---

### Task 6: RunJob (Solid Queue Integration)

**Files:**
- Create: `lib/solid_agent/run_job.rb`
- Create: `app/jobs/solid_agent/application_job.rb`
- Test: `test/run_job_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/run_job_test.rb
require "test_helper"
require "solid_agent/run_job"

class RunJobTest < ActiveSupport::TestCase
  test "RunJob is an ActiveJob subclass" do
    assert SolidAgent::RunJob < ActiveJob::Base
  end

  test "perform creates trace and runs loop" do
    conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
    trace = SolidAgent::Trace.create!(
      conversation: conversation,
      agent_class: "TestAgent",
      trace_type: :agent_run,
      status: "pending",
      input: "Hello"
    )

    job = SolidAgent::RunJob.new
    job.trace_id = trace.id
    job.agent_class_name = "TestAgent"
    job.input = "Hello"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/run_job_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement ApplicationJob**

```ruby
# app/jobs/solid_agent/application_job.rb
module SolidAgent
  class ApplicationJob < ActiveJob::Base
  end
end
```

- [ ] **Step 4: Implement RunJob**

```ruby
# lib/solid_agent/run_job.rb
module SolidAgent
  class RunJob < ApplicationJob
    queue_as :solid_agent

    attr_accessor :trace_id, :agent_class_name, :input, :conversation_id

    def perform(trace_id:, agent_class_name:, input:, conversation_id:)
      trace = Trace.find(trace_id)
      trace.start!

      agent_class = agent_class_name.constantize

      provider = resolve_provider(agent_class)
      memory = resolve_memory(agent_class)
      execution_engine = resolve_execution_engine(agent_class)

      conversation = Conversation.find(conversation_id)
      conversation.messages.create!(role: "user", content: input, trace: trace)

      react_loop = React::Loop.new(
        trace: trace,
        provider: provider,
        memory: memory,
        execution_engine: execution_engine,
        model: agent_class.agent_model,
        system_prompt: agent_class.agent_instructions,
        max_iterations: agent_class.agent_max_iterations,
        max_tokens_per_run: agent_class.agent_max_tokens_per_run,
        timeout: agent_class.agent_timeout
      )

      messages = conversation.messages.where(trace: trace).to_a.map do |m|
        Message.new(role: m.role, content: m.content, tool_calls: nil, tool_call_id: m.tool_call_id)
      end

      result = react_loop.run(messages)
      result
    rescue => e
      trace.fail!(e.message) if trace&.status == "running"
      raise
    end

    private

    def resolve_provider(agent_class)
      provider_name = agent_class.agent_provider
      config = SolidAgent.configuration.providers[provider_name] || {}
      provider_class = "SolidAgent::Provider::#{provider_name.to_s.camelize}".constantize
      provider_class.new(**config.transform_keys(&:to_sym))
    end

    def resolve_memory(agent_class)
      config = agent_class.agent_memory_config
      "SolidAgent::Memory::#{config[:strategy].to_s.camelize}".constantize.new(**config.except(:strategy).transform_keys(&:to_sym))
    end

    def resolve_execution_engine(agent_class)
      Tool::ExecutionEngine.new(
        registry: agent_class.agent_tool_registry,
        concurrency: agent_class.agent_concurrency,
        approval_required: agent_class.agent_approval_required
      )
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/run_job_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add RunJob for Solid Queue integration"
```

---

### Task 7: SolidAgent::Base — perform_later and perform_now

**Files:**
- Modify: `lib/solid_agent/agent/base.rb`
- Test: `test/agent/base_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/agent/base_test.rb
require "test_helper"
require "solid_agent/agent/base"

class SimpleAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  instructions "You are simple."
end

class AgentBaseTest < ActiveSupport::TestCase
  test "perform_later creates trace and enqueues job" do
    conversation = SolidAgent::Conversation.create!(agent_class: "SimpleAgent")
    trace = SimpleAgent.perform_later("Hello", conversation_id: conversation.id)

    assert_instance_of SolidAgent::Trace, trace
    assert_equal "pending", trace.status
    assert_equal "Hello", trace.input
  end

  test "perform_now creates trace synchronously" do
    conversation = SolidAgent::Conversation.create!(agent_class: "SimpleAgent")
    trace = SolidAgent::Trace.create!(
      conversation: conversation,
      agent_class: "SimpleAgent",
      trace_type: :agent_run,
      status: "pending",
      input: "Test"
    )

    assert_instance_of SolidAgent::Trace, trace
    assert_equal "SimpleAgent", trace.agent_class
  end

  test "creates conversation if not provided" do
    trace = SimpleAgent.perform_later("Hello")
    assert trace.conversation
    assert_equal "SimpleAgent", trace.conversation.agent_class
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/agent/base_test.rb`
Expected: FAIL

- [ ] **Step 3: Update SolidAgent::Base with perform methods**

```ruby
# lib/solid_agent/agent/base.rb
require "solid_agent/agent/dsl"
require "solid_agent/agent/result"

module SolidAgent
  class Base
    include Agent::DSL

    def self.perform_later(input, conversation_id: nil)
      conversation = if conversation_id
        Conversation.find(conversation_id)
      else
        Conversation.create!(agent_class: name)
      end

      trace = Trace.create!(
        conversation: conversation,
        agent_class: name,
        trace_type: :agent_run,
        status: "pending",
        input: input
      )

      RunJob.perform_later(
        trace_id: trace.id,
        agent_class_name: name,
        input: input,
        conversation_id: conversation.id
      )

      trace
    end

    def self.perform_now(input, conversation_id: nil)
      conversation = if conversation_id
        Conversation.find(conversation_id)
      else
        Conversation.create!(agent_class: name)
      end

      trace = Trace.create!(
        conversation: conversation,
        agent_class: name,
        trace_type: :agent_run,
        status: "pending",
        input: input
      )

      job = RunJob.new
      job.perform(
        trace_id: trace.id,
        agent_class_name: name,
        input: input,
        conversation_id: conversation.id
      )
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/agent/base_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add perform_later and perform_now to SolidAgent::Base"
```

---

### Task 8: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rake test`
Expected: All tests PASS, 0 failures

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "chore: agent runtime plan complete"
```
