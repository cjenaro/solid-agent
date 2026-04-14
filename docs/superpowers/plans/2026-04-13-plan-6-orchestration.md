# Plan 6: Multi-Agent Orchestration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the multi-agent orchestration layer with supervisor delegation (spawns child traces), agent-as-tool (inline spans), parallel execution via threads, error propagation strategies, and a DSL for declaring delegates and agent tools on `SolidAgent::Base`.

**Architecture:** Two orchestration patterns — `DelegateTool` wraps an agent as a tool that creates a child `Trace` with `parent_trace_id` linking and runs the agent's full ReAct loop; `AgentTool` wraps an agent as an inline tool that creates a `Span` on the parent trace. The `ParallelExecutor` runs up to `concurrency` tool calls concurrently using Ruby threads within each batch slice. Error propagation strategies (`:retry`, `:report_error`, `:fail_parent`) wrap execution blocks and determine how failures are surfaced to the parent agent. A `DSL` module mixed into `SolidAgent::Base` provides `delegate`, `agent_tool`, and `on_delegate_failure` class methods.

**Tech Stack:** Ruby 3.3+, Rails 8.0+, Solid Queue, Minitest

---

## Prerequisites

This plan depends on models from Plan 1 (`SolidAgent::Trace`, `SolidAgent::Span`, `SolidAgent::Conversation`) and expects the agent runtime (Plan 5) to provide `SolidAgent::Base` and `perform_now`. All tests use the in-memory SQLite setup from Plan 1's `test/test_helper.rb`. Agent classes are stubbed in tests — no real LLM calls.

---

## File Structure

```
lib/solid_agent/
├── orchestration.rb                    # Module definition, errors, PendingToolCall
├── orchestration/
│   ├── error_propagation.rb            # Strategy classes for retry/report_error/fail_parent
│   ├── delegate_tool.rb                # Wraps agent as delegate tool (creates child Trace)
│   ├── agent_tool.rb                   # Wraps agent as inline tool (creates Span)
│   ├── parallel_executor.rb            # Concurrent execution engine
│   └── dsl.rb                          # DSL module for SolidAgent::Base
test/
├── orchestration/
│   ├── error_propagation_test.rb
│   ├── delegate_tool_test.rb
│   ├── agent_tool_test.rb
│   ├── parallel_executor_test.rb
│   ├── dsl_test.rb
│   └── integration_test.rb
```

---

### Task 1: Module Skeleton & Error Propagation Strategies

**Files:**
- Create: `lib/solid_agent/orchestration.rb`
- Create: `lib/solid_agent/orchestration/error_propagation.rb`
- Create: `test/orchestration/error_propagation_test.rb`
- Update: `lib/solid_agent.rb` (add orchestration requires)
- Update: `test/test_helper.rb` (add orchestration requires)

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p lib/solid_agent/orchestration test/orchestration
```

- [ ] **Step 2: Create orchestration module file**

```ruby
# lib/solid_agent/orchestration.rb
module SolidAgent
  module Orchestration
    class Error < SolidAgent::Error; end
    class DelegateError < Error; end

    PendingToolCall = Struct.new(:name, :tool, :arguments, :tool_call_id, keyword_init: true)
  end
end
```

- [ ] **Step 3: Update lib/solid_agent.rb — append after existing requires**

```ruby
# lib/solid_agent.rb — add these lines after the existing require lines
require "solid_agent/orchestration"
require "solid_agent/orchestration/error_propagation"
require "solid_agent/orchestration/delegate_tool"
require "solid_agent/orchestration/agent_tool"
require "solid_agent/orchestration/parallel_executor"
require "solid_agent/orchestration/dsl"
```

The complete file should read:

```ruby
# lib/solid_agent.rb
require "solid_agent/engine"
require "solid_agent/configuration"
require "solid_agent/model"
require "solid_agent/models/open_ai"
require "solid_agent/models/anthropic"
require "solid_agent/models/google"

require "solid_agent/orchestration"
require "solid_agent/orchestration/error_propagation"
require "solid_agent/orchestration/delegate_tool"
require "solid_agent/orchestration/agent_tool"
require "solid_agent/orchestration/parallel_executor"
require "solid_agent/orchestration/dsl"

module SolidAgent
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
```

- [ ] **Step 4: Update test_helper.rb — append after existing model requires**

```ruby
# test/test_helper.rb — append after the existing require_relative lines
require_relative "../lib/solid_agent/orchestration"
require_relative "../lib/solid_agent/orchestration/error_propagation"
require_relative "../lib/solid_agent/orchestration/delegate_tool"
require_relative "../lib/solid_agent/orchestration/agent_tool"
require_relative "../lib/solid_agent/orchestration/parallel_executor"
require_relative "../lib/solid_agent/orchestration/dsl"
```

- [ ] **Step 5: Write failing tests for ErrorPropagation::Strategy**

```ruby
# test/orchestration/error_propagation_test.rb
require "test_helper"

class ErrorPropagationTest < ActiveSupport::TestCase
  test "orchestration module is defined" do
    assert defined?(SolidAgent::Orchestration)
  end

  test "DelegateError is defined" do
    assert defined?(SolidAgent::Orchestration::DelegateError)
    assert SolidAgent::Orchestration::DelegateError < SolidAgent::Error
  end

  test "PendingToolCall struct is defined" do
    call = SolidAgent::Orchestration::PendingToolCall.new(
      name: "research",
      tool: double("tool"),
      arguments: { "input" => "test" },
      tool_call_id: "call_1"
    )
    assert_equal "research", call.name
    assert_equal "call_1", call.tool_call_id
  end

  test "report_error strategy returns result on success" do
    strategy = SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:report_error)
    result = strategy.execute_with_handling { "success" }
    assert_equal "success", result
  end

  test "report_error strategy returns error string on failure" do
    strategy = SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:report_error)
    result = strategy.execute_with_handling { raise "boom" }
    assert_equal "Error: boom", result
  end

  test "retry strategy returns result on first success" do
    strategy = SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:retry, attempts: 3)
    result = strategy.execute_with_handling { "ok" }
    assert_equal "ok", result
  end

  test "retry strategy retries specified times and succeeds" do
    attempt_count = 0
    strategy = SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:retry, attempts: 3)
    result = strategy.execute_with_handling do
      attempt_count += 1
      raise "fail" if attempt_count < 3
      "success on attempt #{attempt_count}"
    end
    assert_equal "success on attempt 3", result
    assert_equal 3, attempt_count
  end

  test "retry strategy returns error string after all attempts fail" do
    strategy = SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:retry, attempts: 2)
    result = strategy.execute_with_handling { raise "persistent error" }
    assert_equal "Error after 2 attempts: persistent error", result
  end

  test "retry strategy default attempts is 1" do
    strategy = SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:retry)
    assert_equal 1, strategy.attempts
  end

  test "fail_parent strategy returns result on success" do
    strategy = SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:fail_parent)
    result = strategy.execute_with_handling { "ok" }
    assert_equal "ok", result
  end

  test "fail_parent strategy re-raises error on failure" do
    strategy = SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:fail_parent)
    assert_raises(RuntimeError, "fatal") do
      strategy.execute_with_handling { raise "fatal" }
    end
  end

  test "default strategy constant is report_error" do
    assert_equal :report_error, SolidAgent::Orchestration::ErrorPropagation::DEFAULT.type
  end

  test "strategy exposes type attribute" do
    strategy = SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:retry, attempts: 5)
    assert_equal :retry, strategy.type
    assert_equal 5, strategy.attempts
  end
end
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/orchestration/error_propagation_test.rb`
Expected: FAIL — `SolidAgent::Orchestration::ErrorPropagation` not defined

- [ ] **Step 7: Implement ErrorPropagation**

```ruby
# lib/solid_agent/orchestration/error_propagation.rb
module SolidAgent
  module Orchestration
    module ErrorPropagation
      class Strategy
        attr_reader :type, :attempts

        def initialize(type, attempts: 1)
          @type = type
          @attempts = type == :retry ? attempts : 1
        end

        def execute_with_handling
          case @type
          when :retry
            execute_with_retry { yield }
          when :report_error
            execute_with_report { yield }
          when :fail_parent
            execute_with_fail_parent { yield }
          else
            yield
          end
        end

        private

        def execute_with_retry
          last_error = nil
          @attempts.times do
            begin
              return yield
            rescue => e
              last_error = e
            end
          end
          "Error after #{@attempts} attempts: #{last_error.message}"
        end

        def execute_with_report
          yield
        rescue => e
          "Error: #{e.message}"
        end

        def execute_with_fail_parent
          yield
        end
      end

      DEFAULT = Strategy.new(:report_error)
    end
  end
end
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/orchestration/error_propagation_test.rb`
Expected: All tests PASS

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add orchestration module, errors, PendingToolCall, and ErrorPropagation strategies"
```

---

### Task 2: Delegate Tool Class

**Files:**
- Create: `lib/solid_agent/orchestration/delegate_tool.rb`
- Test: `test/orchestration/delegate_tool_test.rb`

The `DelegateTool` wraps an agent class as a callable tool. When executed, it creates a child `Trace` linked via `parent_trace_id`, runs the agent's `perform_now`, and returns the result. Children are full Trace records — observable, resumable, dashboard-visible.

- [ ] **Step 1: Write failing tests for DelegateTool**

```ruby
# test/orchestration/delegate_tool_test.rb
require "test_helper"

class DelegateToolTest < ActiveSupport::TestCase
  class StubAgent
    def self.name
      "DelegateToolTest::StubAgent"
    end

    def self.perform_now(input, trace:, conversation:)
      trace.update!(output: "Researched: #{input}")
      "Researched: #{input}"
    end
  end

  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: "SupervisorAgent")
    @parent_trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: "SupervisorAgent",
      trace_type: :agent_run
    )
    @parent_trace.start!
    @tool = SolidAgent::Orchestration::DelegateTool.new(
      :research, StubAgent, description: "Research a topic"
    )
  end

  test "has a name" do
    assert_equal "research", @tool.name
  end

  test "has a description" do
    assert_equal "Research a topic", @tool.description
  end

  test "exposes agent_class" do
    assert_equal StubAgent, @tool.agent_class
  end

  test "identifies as delegate" do
    assert @tool.delegate?
  end

  test "generates tool schema" do
    schema = @tool.to_tool_schema
    assert_equal "research", schema[:name]
    assert_equal "Research a topic", schema[:description]
    assert_equal "object", schema[:inputSchema][:type]
    assert_includes schema[:inputSchema][:required], "input"
    assert_equal "string", schema[:inputSchema][:properties][:input][:type]
  end

  test "creates child trace linked to parent" do
    @tool.execute(
      { "input" => "Q4 trends" },
      context: { trace: @parent_trace, conversation: @conversation }
    )

    child = @parent_trace.child_traces.last
    assert_not_nil child
    assert_equal "DelegateToolTest::StubAgent", child.agent_class
    assert_equal "delegate", child.trace_type
    assert_equal "Q4 trends", child.input
    assert_equal @parent_trace.id, child.parent_trace_id
  end

  test "starts and completes child trace" do
    @tool.execute(
      { "input" => "Q4 trends" },
      context: { trace: @parent_trace, conversation: @conversation }
    )

    child = @parent_trace.child_traces.last
    assert_equal "completed", child.status
    assert_not_nil child.started_at
    assert_not_nil child.completed_at
  end

  test "returns agent result as string" do
    result = @tool.execute(
      { "input" => "Q4 trends" },
      context: { trace: @parent_trace, conversation: @conversation }
    )
    assert_equal "Researched: Q4 trends", result
  end

  test "stores result in child trace output" do
    @tool.execute(
      { "input" => "Q4 trends" },
      context: { trace: @parent_trace, conversation: @conversation }
    )

    child = @parent_trace.child_traces.last
    assert_equal "Researched: Q4 trends", child.output
  end

  test "fails child trace on agent error and re-raises" do
    failing_agent = Class.new do
      def self.name
        "DelegateToolTest::FailingAgent"
      end

      def self.perform_now(input, trace:, conversation:)
        raise "Agent crashed"
      end
    end

    tool = SolidAgent::Orchestration::DelegateTool.new(
      :fail_test, failing_agent, description: "Always fails"
    )

    error = assert_raises(RuntimeError) do
      tool.execute(
        { "input" => "test" },
        context: { trace: @parent_trace, conversation: @conversation }
      )
    end
    assert_equal "Agent crashed", error.message

    child = @parent_trace.child_traces.last
    assert_equal "failed", child.status
    assert_equal "Agent crashed", child.error
  end

  test "accepts symbol argument keys" do
    result = @tool.execute(
      { input: "symbol key" },
      context: { trace: @parent_trace, conversation: @conversation }
    )
    assert_equal "Researched: symbol key", result
  end

  test "creates child trace without parent when parent trace is nil" do
    result = @tool.execute(
      { "input" => "orphan" },
      context: { conversation: @conversation }
    )
    assert_equal "Researched: orphan", result

    child = SolidAgent::Trace.where(
      conversation: @conversation,
      trace_type: "delegate"
    ).last
    assert_not_nil child
    assert_nil child.parent_trace_id
    assert_equal "completed", child.status
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/orchestration/delegate_tool_test.rb`
Expected: FAIL — `SolidAgent::Orchestration::DelegateTool` not defined

- [ ] **Step 3: Implement DelegateTool**

```ruby
# lib/solid_agent/orchestration/delegate_tool.rb
module SolidAgent
  module Orchestration
    class DelegateTool
      attr_reader :name, :agent_class, :description

      def initialize(name, agent_class, description:)
        @name = name.to_s
        @agent_class = agent_class
        @description = description
      end

      def delegate?
        true
      end

      def to_tool_schema
        {
          name: @name,
          description: @description,
          inputSchema: {
            type: "object",
            properties: {
              input: {
                type: "string",
                description: "The task to delegate to the agent"
              }
            },
            required: ["input"]
          }
        }
      end

      def execute(arguments, context: {})
        parent_trace = context[:trace]
        conversation = context[:conversation]
        input_text = arguments["input"] || arguments[:input]

        child_trace = nil

        begin
          child_trace = SolidAgent::Trace.create!(
            conversation: conversation,
            parent_trace: parent_trace,
            agent_class: @agent_class.name,
            trace_type: :delegate,
            input: input_text
          )

          child_trace.start!
          result = @agent_class.perform_now(input_text, trace: child_trace, conversation: conversation)
          child_trace.update!(output: result.to_s)
          child_trace.complete!

          result.to_s
        rescue => e
          child_trace&.fail!(e.message) if child_trace&.status == "running"
          raise
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/orchestration/delegate_tool_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add DelegateTool — spawns child traces for supervisor delegation"
```

---

### Task 3: Agent-as-Tool Class

**Files:**
- Create: `lib/solid_agent/orchestration/agent_tool.rb`
- Test: `test/orchestration/agent_tool_test.rb`

The `AgentTool` wraps an agent as a lightweight inline tool. When executed, it creates a `Span` (not a separate Trace) on the parent trace, runs the agent inline within the parent's ReAct loop, and returns the result. The agent's `perform_now` receives the input and conversation but no dedicated trace.

- [ ] **Step 1: Write failing tests for AgentTool**

```ruby
# test/orchestration/agent_tool_test.rb
require "test_helper"

class AgentToolTest < ActiveSupport::TestCase
  class StubSummaryAgent
    def self.name
      "AgentToolTest::StubSummaryAgent"
    end

    def self.perform_now(input, conversation:)
      "Summary of: #{input}"
    end
  end

  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: "SupervisorAgent")
    @trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: "SupervisorAgent",
      trace_type: :agent_run
    )
    @trace.start!
    @tool = SolidAgent::Orchestration::AgentTool.new(
      :quick_summary, StubSummaryAgent, description: "Quick summaries"
    )
  end

  test "has a name" do
    assert_equal "quick_summary", @tool.name
  end

  test "has a description" do
    assert_equal "Quick summaries", @tool.description
  end

  test "exposes agent_class" do
    assert_equal StubSummaryAgent, @tool.agent_class
  end

  test "does not identify as delegate" do
    refute @tool.delegate?
  end

  test "generates tool schema" do
    schema = @tool.to_tool_schema
    assert_equal "quick_summary", schema[:name]
    assert_equal "Quick summaries", schema[:description]
    assert_equal "object", schema[:inputSchema][:type]
    assert_includes schema[:inputSchema][:required], "input"
    assert_equal "string", schema[:inputSchema][:properties][:input][:type]
  end

  test "creates span on parent trace" do
    @tool.execute(
      { "input" => "Long text here" },
      context: { trace: @trace, conversation: @conversation }
    )

    span = @trace.spans.where(span_type: "tool_execution", name: "quick_summary").last
    assert_not_nil span
    assert_equal "Long text here", span.input
    assert_equal "completed", span.status
  end

  test "does not create child traces" do
    @tool.execute(
      { "input" => "Long text" },
      context: { trace: @trace, conversation: @conversation }
    )

    assert_equal 0, @trace.child_traces.count
  end

  test "returns agent result as string" do
    result = @tool.execute(
      { "input" => "Long text" },
      context: { trace: @trace, conversation: @conversation }
    )
    assert_equal "Summary of: Long text", result
  end

  test "stores result in span output" do
    @tool.execute(
      { "input" => "Long text" },
      context: { trace: @trace, conversation: @conversation }
    )

    span = @trace.spans.last
    assert_equal "Summary of: Long text", span.output
  end

  test "records timing in span" do
    @tool.execute(
      { "input" => "Long text" },
      context: { trace: @trace, conversation: @conversation }
    )

    span = @trace.spans.last
    assert_not_nil span.started_at
    assert_not_nil span.completed_at
    assert span.completed_at >= span.started_at
  end

  test "stores agent class in span metadata" do
    @tool.execute(
      { "input" => "text" },
      context: { trace: @trace, conversation: @conversation }
    )

    span = @trace.spans.last
    assert_equal "AgentToolTest::StubSummaryAgent", span.metadata["agent_class"]
    assert_equal "agent_tool", span.metadata["tool_type"]
  end

  test "marks span as error on failure and re-raises" do
    failing_agent = Class.new do
      def self.name
        "AgentToolTest::FailingAgent"
      end

      def self.perform_now(input, conversation:)
        raise "Summary engine exploded"
      end
    end

    tool = SolidAgent::Orchestration::AgentTool.new(
      :bad_summary, failing_agent, description: "Always fails"
    )

    error = assert_raises(RuntimeError) do
      tool.execute(
        { "input" => "test" },
        context: { trace: @trace, conversation: @conversation }
      )
    end
    assert_equal "Summary engine exploded", error.message

    span = @trace.spans.last
    assert_equal "error", span.status
    assert_equal "Summary engine exploded", span.output
  end

  test "creates span even without parent trace" do
    result = @tool.execute(
      { "input" => "no trace" },
      context: { conversation: @conversation }
    )
    assert_equal "Summary of: no trace", result
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/orchestration/agent_tool_test.rb`
Expected: FAIL — `SolidAgent::Orchestration::AgentTool` not defined

- [ ] **Step 3: Implement AgentTool**

```ruby
# lib/solid_agent/orchestration/agent_tool.rb
module SolidAgent
  module Orchestration
    class AgentTool
      attr_reader :name, :agent_class, :description

      def initialize(name, agent_class, description:)
        @name = name.to_s
        @agent_class = agent_class
        @description = description
      end

      def delegate?
        false
      end

      def to_tool_schema
        {
          name: @name,
          description: @description,
          inputSchema: {
            type: "object",
            properties: {
              input: {
                type: "string",
                description: "The input for the agent"
              }
            },
            required: ["input"]
          }
        }
      end

      def execute(arguments, context: {})
        trace = context[:trace]
        conversation = context[:conversation]
        input_text = arguments["input"] || arguments[:input]

        span = nil

        begin
          span = SolidAgent::Span.create!(
            trace: trace,
            span_type: :tool_execution,
            name: @name,
            input: input_text,
            status: "running",
            started_at: Time.current,
            metadata: {
              agent_class: @agent_class.name,
              tool_type: :agent_tool
            }
          )

          result = @agent_class.perform_now(input_text, conversation: conversation)

          span.update!(
            output: result.to_s,
            status: "completed",
            completed_at: Time.current
          )

          result.to_s
        rescue => e
          if span
            span.update!(
              output: e.message,
              status: "error",
              completed_at: Time.current
            )
          end
          raise
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/orchestration/agent_tool_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add AgentTool — inline agent execution logged as span"
```

---

### Task 4: DSL Methods on SolidAgent::Base

**Files:**
- Create: `lib/solid_agent/orchestration/dsl.rb`
- Test: `test/orchestration/dsl_test.rb`

The DSL module provides `delegate`, `agent_tool`, and `on_delegate_failure` class methods. It uses `ActiveSupport::Concern` so it can be mixed into `SolidAgent::Base` (Plan 5). Delegates and agent tools are stored in class-level hashes that are duped on inheritance, giving each subclass its own copy while sharing the parent's definitions.

- [ ] **Step 1: Write failing tests for DSL**

```ruby
# test/orchestration/dsl_test.rb
require "test_helper"

class DSLTest < ActiveSupport::TestCase
  class StubAgent
    def self.name
      "DSLTest::StubAgent"
    end
  end

  def setup
    @agent_class = Class.new do
      include SolidAgent::Orchestration::DSL
    end
  end

  test "delegate registers a DelegateTool" do
    @agent_class.delegate :research, to: StubAgent, description: "Research a topic"

    assert_instance_of SolidAgent::Orchestration::DelegateTool, @agent_class.delegates["research"]
    assert_equal "research", @agent_class.delegates["research"].name
    assert_equal StubAgent, @agent_class.delegates["research"].agent_class
    assert_equal "Research a topic", @agent_class.delegates["research"].description
  end

  test "agent_tool registers an AgentTool" do
    @agent_class.agent_tool :quick_summary, agent: StubAgent, description: "Quick summaries"

    assert_instance_of SolidAgent::Orchestration::AgentTool, @agent_class.agent_tools["quick_summary"]
    assert_equal "quick_summary", @agent_class.agent_tools["quick_summary"].name
    assert_equal StubAgent, @agent_class.agent_tools["quick_summary"].agent_class
    assert_equal "Quick summaries", @agent_class.agent_tools["quick_summary"].description
  end

  test "on_delegate_failure registers an error strategy" do
    @agent_class.delegate :research, to: StubAgent, description: "Research"
    @agent_class.on_delegate_failure :research, strategy: :retry, attempts: 3

    strategy = @agent_class.delegate_error_strategies["research"]
    assert_instance_of SolidAgent::Orchestration::ErrorPropagation::Strategy, strategy
    assert_equal :retry, strategy.type
    assert_equal 3, strategy.attempts
  end

  test "on_delegate_failure with report_error strategy" do
    @agent_class.delegate :research, to: StubAgent, description: "Research"
    @agent_class.on_delegate_failure :research, strategy: :report_error

    strategy = @agent_class.delegate_error_strategies["research"]
    assert_equal :report_error, strategy.type
  end

  test "on_delegate_failure with fail_parent strategy" do
    @agent_class.delegate :research, to: StubAgent, description: "Research"
    @agent_class.on_delegate_failure :research, strategy: :fail_parent

    strategy = @agent_class.delegate_error_strategies["research"]
    assert_equal :fail_parent, strategy.type
  end

  test "multiple delegates can be registered" do
    @agent_class.delegate :research, to: StubAgent, description: "Research"
    @agent_class.delegate :writing, to: StubAgent, description: "Write content"

    assert_equal 2, @agent_class.delegates.size
    assert @agent_class.delegates.key?("research")
    assert @agent_class.delegates.key?("writing")
  end

  test "multiple agent tools can be registered" do
    @agent_class.agent_tool :summarize, agent: StubAgent, description: "Summarize"
    @agent_class.agent_tool :translate, agent: StubAgent, description: "Translate"

    assert_equal 2, @agent_class.agent_tools.size
    assert @agent_class.agent_tools.key?("summarize")
    assert @agent_class.agent_tools.key?("translate")
  end

  test "delegates start empty" do
    assert_equal({}, @agent_class.delegates)
    assert_equal({}, @agent_class.agent_tools)
    assert_equal({}, @agent_class.delegate_error_strategies)
  end

  test "delegates are inherited by subclasses" do
    @agent_class.delegate :research, to: StubAgent, description: "Research"
    @agent_class.agent_tool :summarize, agent: StubAgent, description: "Summarize"
    @agent_class.on_delegate_failure :research, strategy: :retry, attempts: 2

    child_class = Class.new(@agent_class)

    assert child_class.delegates.key?("research")
    assert child_class.agent_tools.key?("summarize")
    assert child_class.delegate_error_strategies.key?("research")
    assert_equal :retry, child_class.delegate_error_strategies["research"].type
  end

  test "subclass delegates are independent from parent" do
    @agent_class.delegate :research, to: StubAgent, description: "Research"

    child_class = Class.new(@agent_class)
    child_class.delegate :writing, to: StubAgent, description: "Write"

    assert_equal 1, @agent_class.delegates.size
    assert_equal 2, child_class.delegates.size
    assert child_class.delegates.key?("writing")
    refute @agent_class.delegates.key?("writing")
  end

  test "orchestration_tools combines delegates and agent_tools" do
    @agent_class.delegate :research, to: StubAgent, description: "Research"
    @agent_class.agent_tool :summarize, agent: StubAgent, description: "Summary"

    tools = @agent_class.orchestration_tools
    assert_equal 2, tools.size
    assert tools.any? { |t| t.name == "research" && t.delegate? }
    assert tools.any? { |t| t.name == "summarize" && !t.delegate? }
  end

  test "orchestration_tool_schemas returns tool schemas" do
    @agent_class.delegate :research, to: StubAgent, description: "Research"
    @agent_class.agent_tool :summarize, agent: StubAgent, description: "Summary"

    schemas = @agent_class.orchestration_tool_schemas
    assert_equal 2, schemas.size
    names = schemas.map { |s| s[:name] }
    assert_includes names, "research"
    assert_includes names, "summarize"

    schemas.each do |schema|
      assert schema[:name]
      assert schema[:description]
      assert schema[:inputSchema]
      assert_equal "object", schema[:inputSchema][:type]
    end
  end

  test "find_orchestration_tool by name" do
    @agent_class.delegate :research, to: StubAgent, description: "Research"
    @agent_class.agent_tool :summarize, agent: StubAgent, description: "Summary"

    assert_equal "research", @agent_class.find_orchestration_tool("research").name
    assert_equal "summarize", @agent_class.find_orchestration_tool("summarize").name
    assert_nil @agent_class.find_orchestration_tool("nonexistent")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/orchestration/dsl_test.rb`
Expected: FAIL — `SolidAgent::Orchestration::DSL` not defined

- [ ] **Step 3: Implement DSL module**

```ruby
# lib/solid_agent/orchestration/dsl.rb
require "active_support/concern"

module SolidAgent
  module Orchestration
    module DSL
      extend ActiveSupport::Concern

      class_methods do
        def delegates
          @delegates ||= {}
        end

        def agent_tools
          @agent_tools ||= {}
        end

        def delegate_error_strategies
          @delegate_error_strategies ||= {}
        end

        def delegate(name, to:, description:)
          tool = DelegateTool.new(name, to, description: description)
          delegates[name.to_s] = tool
        end

        def agent_tool(name, agent:, description:)
          tool = AgentTool.new(name, agent, description: description)
          agent_tools[name.to_s] = tool
        end

        def on_delegate_failure(name, strategy:, attempts: 1)
          delegate_error_strategies[name.to_s] = ErrorPropagation::Strategy.new(strategy, attempts: attempts)
        end

        def orchestration_tools
          delegates.values + agent_tools.values
        end

        def orchestration_tool_schemas
          orchestration_tools.map(&:to_tool_schema)
        end

        def find_orchestration_tool(tool_name)
          delegates[tool_name] || agent_tools[tool_name]
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@delegates, @delegates.dup) if @delegates
          subclass.instance_variable_set(:@agent_tools, @agent_tools.dup) if @agent_tools
          subclass.instance_variable_set(:@delegate_error_strategies, @delegate_error_strategies.dup) if @delegate_error_strategies
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/orchestration/dsl_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Run all orchestration tests together**

Run: `bundle exec ruby -Itest test/orchestration/**/*_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add orchestration DSL — delegate, agent_tool, on_delegate_failure"
```

---

### Task 5: Parallel Execution Engine

**Files:**
- Create: `lib/solid_agent/orchestration/parallel_executor.rb`
- Test: `test/orchestration/parallel_executor_test.rb`

The `ParallelExecutor` takes an array of `PendingToolCall` structs, slices them into batches of `concurrency` size, and executes each batch concurrently using Ruby threads. It applies error strategies per tool and handles `:fail_parent` by killing remaining threads and re-raising.

- [ ] **Step 1: Write failing tests for ParallelExecutor**

```ruby
# test/orchestration/parallel_executor_test.rb
require "test_helper"

class ParallelExecutorTest < ActiveSupport::TestCase
  class CountingTool
    attr_reader :name, :call_count

    def initialize(name, result_value)
      @name = name
      @result_value = result_value
      @call_count = 0
    end

    def execute(arguments, context: {})
      @call_count += 1
      @result_value
    end

    def delegate?
      true
    end
  end

  class SlowTool
    attr_reader :name

    def initialize(name, delay, result_value)
      @name = name
      @delay = delay
      @result_value = result_value
    end

    def execute(arguments, context: {})
      sleep(@delay)
      @result_value
    end

    def delegate?
      true
    end
  end

  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
    @trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: "TestAgent",
      trace_type: :agent_run
    )
    @trace.start!
    @context = { trace: @trace, conversation: @conversation }
  end

  test "executes multiple tool calls and returns results" do
    calls = [
      build_call("tool_a", CountingTool.new("tool_a", "result_a"), { "input" => "a" }),
      build_call("tool_b", CountingTool.new("tool_b", "result_b"), { "input" => "b" })
    ]

    results = SolidAgent::Orchestration::ParallelExecutor.execute(
      calls, context: @context, concurrency: 2
    )

    assert_equal 2, results.size
    assert_includes results, "result_a"
    assert_includes results, "result_b"
  end

  test "respects concurrency limit by slicing into batches" do
    tools = (1..4).map { |i| CountingTool.new("tool_#{i}", "result_#{i}") }
    calls = tools.map { |t| build_call(t.name, t, { "input" => t.name }) }

    results = SolidAgent::Orchestration::ParallelExecutor.execute(
      calls, context: @context, concurrency: 2
    )

    assert_equal 4, results.size
    %w[result_1 result_2 result_3 result_4].each do |r|
      assert_includes results, r
    end
  end

  test "runs tools concurrently within batch" do
    calls = [
      build_call("slow_a", SlowTool.new("slow_a", 0.15, "result_a"), { "input" => "a" }),
      build_call("slow_b", SlowTool.new("slow_b", 0.15, "result_b"), { "input" => "b" })
    ]

    start_time = Time.current
    results = SolidAgent::Orchestration::ParallelExecutor.execute(
      calls, context: @context, concurrency: 2
    )
    elapsed = Time.current - start_time

    assert_equal 2, results.size
    assert elapsed < 0.4, "Parallel execution should be faster than sequential (took #{elapsed}s)"
  end

  test "applies report_error strategy" do
    failing_tool = Class.new do
      attr_reader :name
      define_method(:initialize) { @name = "fail_tool" }
      define_method(:execute) { |*a, **k| raise "Tool error" }
      define_method(:delegate?) { true }
    end

    calls = [
      build_call("fail_tool", failing_tool.new, { "input" => "test" })
    ]

    strategies = {
      "fail_tool" => SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:report_error)
    }

    results = SolidAgent::Orchestration::ParallelExecutor.execute(
      calls, context: @context, concurrency: 2, error_strategies: strategies
    )

    assert_equal 1, results.size
    assert_includes results.first, "Tool error"
  end

  test "applies retry strategy" do
    attempt_count = 0
    retry_tool = Class.new do
      attr_reader :name
      define_method(:initialize) { |counter_ref| @name = "retry_tool"; @counter = counter_ref }
      define_method(:execute) do |*a, **k|
        @counter[0] += 1
        raise "fail" if @counter[0] < 3
        "recovered"
      end
      define_method(:delegate?) { true }
    end

    counter_ref = [0]
    calls = [
      build_call("retry_tool", retry_tool.new(counter_ref), { "input" => "test" })
    ]

    strategies = {
      "retry_tool" => SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:retry, attempts: 3)
    }

    results = SolidAgent::Orchestration::ParallelExecutor.execute(
      calls, context: @context, concurrency: 2, error_strategies: strategies
    )

    assert_equal 1, results.size
    assert_equal "recovered", results.first
    assert_equal 3, counter_ref[0]
  end

  test "fail_parent strategy raises and stops other threads" do
    failing_tool = Class.new do
      attr_reader :name
      define_method(:initialize) { @name = "fatal_tool" }
      define_method(:execute) { |*a, **k| raise "Fatal error" }
      define_method(:delegate?) { true }
    end

    calls = [
      build_call("fatal_tool", failing_tool.new, { "input" => "test" })
    ]

    strategies = {
      "fatal_tool" => SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:fail_parent)
    }

    error = assert_raises(RuntimeError) do
      SolidAgent::Orchestration::ParallelExecutor.execute(
        calls, context: @context, concurrency: 2, error_strategies: strategies
      )
    end
    assert_equal "Fatal error", error.message
  end

  test "executes with no error strategies" do
    calls = [
      build_call("tool_a", CountingTool.new("tool_a", "ok"), { "input" => "a" })
    ]

    results = SolidAgent::Orchestration::ParallelExecutor.execute(
      calls, context: @context, concurrency: 2
    )

    assert_equal ["ok"], results
  end

  test "handles empty tool calls" do
    results = SolidAgent::Orchestration::ParallelExecutor.execute(
      [], context: @context, concurrency: 2
    )

    assert_equal [], results
  end

  test "mixed success and report_error in same batch" do
    failing_tool = Class.new do
      attr_reader :name
      define_method(:initialize) { @name = "fail_tool" }
      define_method(:execute) { |*a, **k| raise "partial failure" }
      define_method(:delegate?) { true }
    end

    calls = [
      build_call("good", CountingTool.new("good", "good_result"), { "input" => "a" }),
      build_call("fail", failing_tool.new, { "input" => "b" })
    ]

    strategies = {
      "fail" => SolidAgent::Orchestration::ErrorPropagation::Strategy.new(:report_error)
    }

    results = SolidAgent::Orchestration::ParallelExecutor.execute(
      calls, context: @context, concurrency: 2, error_strategies: strategies
    )

    assert_equal 2, results.size
    assert_includes results, "good_result"
    error_result = results.find { |r| r != "good_result" }
    assert_includes error_result, "partial failure"
  end

  private

  def build_call(name, tool, arguments)
    SolidAgent::Orchestration::PendingToolCall.new(
      name: name,
      tool: tool,
      arguments: arguments,
      tool_call_id: "call_#{name}"
    )
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/orchestration/parallel_executor_test.rb`
Expected: FAIL — `SolidAgent::Orchestration::ParallelExecutor` not defined

- [ ] **Step 3: Implement ParallelExecutor**

```ruby
# lib/solid_agent/orchestration/parallel_executor.rb
module SolidAgent
  module Orchestration
    class ParallelExecutor
      def self.execute(tool_calls, context:, concurrency:, error_strategies: {})
        return [] if tool_calls.empty?

        tool_calls.each_slice(concurrency).flat_map do |batch|
          execute_batch(batch, context, error_strategies)
        end
      end

      def self.execute_batch(batch, context, error_strategies)
        threads = batch.map do |tool_call|
          Thread.new(tool_call) do |tc|
            strategy = error_strategies[tc.name]
            if strategy
              strategy.execute_with_handling do
                tc.tool.execute(tc.arguments, context: context)
              end
            else
              tc.tool.execute(tc.arguments, context: context)
            end
          end
        end

        results = []
        threads.each do |thread|
          results << thread.value
        rescue => e
          threads.each { |t| t.kill if t.alive? && t != thread }
          raise
        end
        results
      end

      private_class_method :execute_batch
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/orchestration/parallel_executor_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ParallelExecutor — concurrent tool execution with error strategies"
```

---

### Task 6: Trace Tree Integration

**Files:**
- Test: `test/orchestration/integration_test.rb`

End-to-end integration tests exercising the full orchestration layer: supervisor delegation creating child traces, agent-as-tool creating spans, parallel delegation with multiple children, error propagation across the trace tree, and verifying the trace tree structure is correct for dashboard rendering.

- [ ] **Step 1: Write integration tests**

```ruby
# test/orchestration/integration_test.rb
require "test_helper"

class OrchestrationIntegrationTest < ActiveSupport::TestCase
  class ResearchAgent
    def self.name
      "OrchestrationIntegrationTest::ResearchAgent"
    end

    def self.perform_now(input, trace:, conversation:)
      trace.update!(output: "Researched: #{input}")
      "Researched: #{input}"
    end
  end

  class WriterAgent
    def self.name
      "OrchestrationIntegrationTest::WriterAgent"
    end

    def self.perform_now(input, trace:, conversation:)
      trace.update!(output: "Written: #{input}")
      "Written: #{input}"
    end
  end

  class SummaryAgent
    def self.name
      "OrchestrationIntegrationTest::SummaryAgent"
    end

    def self.perform_now(input, conversation:)
      "Summary: #{input}"
    end
  end

  class FailingAgent
    def self.name
      "OrchestrationIntegrationTest::FailingAgent"
    end

    def self.perform_now(input, trace:, conversation:)
      raise "Agent crashed"
    end
  end

  class FlakeyAgent
    attr_reader :call_count

    def initialize
      @call_count = 0
    end

    def name
      "OrchestrationIntegrationTest::FlakeyAgent"
    end

    def perform_now(input, trace:, conversation:)
      @call_count += 1
      raise "Transient failure" if @call_count < 3
      trace.update!(output: "Eventually worked: #{input}")
      "Eventually worked: #{input}"
    end
  end

  def build_supervisor
    Class.new do
      include SolidAgent::Orchestration::DSL

      delegate :research, to: ResearchAgent, description: "Research a topic"
      delegate :writing, to: WriterAgent, description: "Write content"
      delegate :failing, to: FailingAgent, description: "Always fails"
      agent_tool :summarize, agent: SummaryAgent, description: "Quick summary"

      on_delegate_failure :research, strategy: :report_error
      on_delegate_failure :writing, strategy: :retry, attempts: 3
      on_delegate_failure :failing, strategy: :report_error
    end
  end

  def build_context
    conversation = SolidAgent::Conversation.create!(agent_class: "SupervisorAgent")
    trace = SolidAgent::Trace.create!(
      conversation: conversation,
      agent_class: "SupervisorAgent",
      trace_type: :agent_run
    )
    trace.start!
    { trace: trace, conversation: conversation }
  end

  test "full delegation creates complete trace tree" do
    supervisor = build_supervisor
    context = build_context

    tool = supervisor.delegates["research"]
    result = tool.execute(
      { "input" => "Q4 trends" },
      context: context
    )

    assert_equal "Researched: Q4 trends", result

    parent = context[:trace]
    assert_equal 1, parent.child_traces.count

    child = parent.child_traces.last
    assert_equal "delegate", child.trace_type
    assert_equal "OrchestrationIntegrationTest::ResearchAgent", child.agent_class
    assert_equal "completed", child.status
    assert_equal parent.id, child.parent_trace_id
    assert_equal context[:conversation].id, child.conversation_id
    assert_equal "Q4 trends", child.input
    assert_equal "Researched: Q4 trends", child.output
    assert_not_nil child.started_at
    assert_not_nil child.completed_at
  end

  test "agent-as-tool creates span not child trace" do
    supervisor = build_supervisor
    context = build_context

    tool = supervisor.agent_tools["summarize"]
    result = tool.execute(
      { "input" => "Long document text" },
      context: context
    )

    assert_equal "Summary: Long document text", result

    parent = context[:trace]
    assert_equal 0, parent.child_traces.count, "Agent tool should not create child traces"

    span = parent.spans.where(name: "quick_summary").last
    assert_not_nil span
    assert_equal "tool_execution", span.span_type
    assert_equal "completed", span.status
    assert_equal "Summary: Long document text", span.output
    assert_equal "Long document text", span.input
    assert_equal "agent_tool", span.metadata["tool_type"]
    assert_equal "OrchestrationIntegrationTest::SummaryAgent", span.metadata["agent_class"]
  end

  test "parallel delegation creates multiple child traces" do
    supervisor = build_supervisor
    context = build_context

    calls = [
      build_call("research", supervisor.delegates["research"], { "input" => "topic A" }),
      build_call("writing", supervisor.delegates["writing"], { "input" => "topic B" })
    ]

    results = SolidAgent::Orchestration::ParallelExecutor.execute(
      calls, context: context, concurrency: 2,
      error_strategies: supervisor.delegate_error_strategies
    )

    assert_equal 2, results.size
    assert_includes results, "Researched: topic A"
    assert_includes results, "Written: topic B"

    parent = context[:trace]
    assert_equal 2, parent.child_traces.count

    children = parent.child_traces.order(:id).to_a
    assert_equal "delegate", children[0].trace_type
    assert_equal "delegate", children[1].trace_type
    assert_equal "completed", children[0].status
    assert_equal "completed", children[1].status
    assert_equal parent.id, children[0].parent_trace_id
    assert_equal parent.id, children[1].parent_trace_id
  end

  test "mixed delegates and agent tools in parallel" do
    supervisor = build_supervisor
    context = build_context

    calls = [
      build_call("research", supervisor.delegates["research"], { "input" => "research topic" }),
      build_call("summarize", supervisor.agent_tools["summarize"], { "input" => "text to summarize" })
    ]

    results = SolidAgent::Orchestration::ParallelExecutor.execute(
      calls, context: context, concurrency: 2,
      error_strategies: supervisor.delegate_error_strategies
    )

    assert_equal 2, results.size
    assert_includes results, "Researched: research topic"
    assert_includes results, "Summary: text to summarize"

    parent = context[:trace]
    assert_equal 1, parent.child_traces.count, "Only delegate creates child trace"
    assert_equal 1, parent.spans.where(name: "quick_summary").count, "Agent tool creates span"
  end

  test "report_error strategy returns error to parent without failing parent trace" do
    supervisor = build_supervisor
    context = build_context

    tool = supervisor.delegates["failing"]
    strategy = supervisor.delegate_error_strategies["failing"]

    result = strategy.execute_with_handling do
      tool.execute({ "input" => "test" }, context: context)
    end

    assert_includes result, "Agent crashed"

    parent = context[:trace]
    assert_equal "running", parent.status, "Parent trace should still be running"

    child = parent.child_traces.last
    assert_equal "failed", child.status
    assert_equal "Agent crashed", child.error
  end

  test "fail_parent strategy propagates error to parent trace" do
    supervisor = Class.new do
      include SolidAgent::Orchestration::DSL
      delegate :critical, to: FailingAgent, description: "Critical task"
      on_delegate_failure :critical, strategy: :fail_parent
    end

    context = build_context

    tool = supervisor.delegates["critical"]
    strategy = supervisor.delegate_error_strategies["critical"]

    assert_raises(RuntimeError) do
      strategy.execute_with_handling do
        tool.execute({ "input" => "critical task" }, context: context)
      end
    end

    child = context[:trace].child_traces.last
    assert_equal "failed", child.status
  end

  test "retry strategy retries and creates multiple child traces" do
    flakey = FlakeyAgent.new

    agent_class = Class.new do
      define_method(:name) { "FlakeyAgent" }
      define_method(:perform_now) { |input, trace:, conversation:|
        flakey.perform_now(input, trace: trace, conversation: conversation)
      }
    end

    supervisor = Class.new do
      include SolidAgent::Orchestration::DSL
    end
    supervisor.delegate :research, to: agent_class.new, description: "Research"
    supervisor.on_delegate_failure :research, strategy: :retry, attempts: 3

    context = build_context

    tool = supervisor.delegates["research"]
    strategy = supervisor.delegate_error_strategies["research"]

    result = strategy.execute_with_handling do
      tool.execute({ "input" => "flakey task" }, context: context)
    end

    assert_equal "Eventually worked: flakey task", result

    parent = context[:trace]
    assert parent.child_traces.count >= 1
  end

  test "orchestration_tool_schemas ready for LLM" do
    supervisor = build_supervisor

    schemas = supervisor.orchestration_tool_schemas
    assert_equal 4, schemas.size

    names = schemas.map { |s| s[:name] }
    assert_includes names, "research"
    assert_includes names, "writing"
    assert_includes names, "failing"
    assert_includes names, "summarize"

    schemas.each do |schema|
      assert schema[:name].is_a?(String)
      assert schema[:description].is_a?(String)
      assert_equal "object", schema[:inputSchema][:type]
      assert_includes schema[:inputSchema][:required], "input"
    end
  end

  test "find_orchestration_tool locates delegates and agent tools" do
    supervisor = build_supervisor

    research = supervisor.find_orchestration_tool("research")
    assert research.delegate?
    assert_equal "Research a topic", research.description

    summarize = supervisor.find_orchestration_tool("summarize")
    refute summarize.delegate?
    assert_equal "Quick summary", summarize.description

    assert_nil supervisor.find_orchestration_tool("nonexistent")
  end

  test "complete trace tree with delegates, agent tools, and nested spans" do
    supervisor = build_supervisor
    context = build_context
    parent = context[:trace]

    research_tool = supervisor.delegates["research"]
    research_tool.execute({ "input" => "topic A" }, context: context)

    summarize_tool = supervisor.agent_tools["summarize"]
    summarize_tool.execute({ "input" => "notes" }, context: context)

    writing_tool = supervisor.delegates["writing"]
    writing_tool.execute({ "input" => "topic B" }, context: context)

    summarize_tool.execute({ "input" => "final notes" }, context: context)

    assert_equal 2, parent.child_traces.count
    assert_equal 2, parent.spans.where(name: "quick_summary").count

    child_traces = parent.child_traces.order(:id).to_a
    assert_equal "OrchestrationIntegrationTest::ResearchAgent", child_traces[0].agent_class
    assert_equal "OrchestrationIntegrationTest::WriterAgent", child_traces[1].agent_class
    assert_equal "completed", child_traces[0].status
    assert_equal "completed", child_traces[1].status

    spans = parent.spans.where(name: "quick_summary").order(:id).to_a
    assert_equal "completed", spans[0].status
    assert_equal "completed", spans[1].status
    assert_equal "Summary: notes", spans[0].output
    assert_equal "Summary: final notes", spans[1].output
  end

  test "child traces are independently queryable" do
    supervisor = build_supervisor
    context = build_context

    tool = supervisor.delegates["research"]
    tool.execute({ "input" => "Q4 trends" }, context: context)

    child = context[:trace].child_traces.last

    found = SolidAgent::Trace.find(child.id)
    assert_equal "delegate", found.trace_type
    assert_equal "completed", found.status
    assert_equal "Q4 trends", found.input
    assert_equal "Researched: Q4 trends", found.output
    assert_not_nil found.parent_trace_id
  end

  test "delegates across conversations are isolated" do
    supervisor = build_supervisor

    context_a = build_context
    context_b = build_context

    tool = supervisor.delegates["research"]
    tool.execute({ "input" => "topic A" }, context: context_a)
    tool.execute({ "input" => "topic B" }, context: context_b)

    trace_a = context_a[:trace]
    trace_b = context_b[:trace]

    assert_equal 1, trace_a.child_traces.count
    assert_equal 1, trace_b.child_traces.count

    child_a = trace_a.child_traces.last
    child_b = trace_b.child_traces.last

    assert_equal "topic A", child_a.input
    assert_equal "topic B", child_b.input
    assert_equal trace_a.id, child_a.parent_trace_id
    assert_equal trace_b.id, child_b.parent_trace_id
    assert_not_equal child_a.conversation_id, child_b.conversation_id
  end

  private

  def build_call(name, tool, arguments)
    SolidAgent::Orchestration::PendingToolCall.new(
      name: name,
      tool: tool,
      arguments: arguments,
      tool_call_id: "call_#{name}_#{rand(1000)}"
    )
  end
end
```

- [ ] **Step 2: Run integration tests to verify they pass**

Run: `bundle exec ruby -Itest test/orchestration/integration_test.rb`
Expected: All tests PASS

- [ ] **Step 3: Run full orchestration test suite**

Run: `bundle exec rake test`
Expected: All orchestration tests PASS, all existing tests PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add orchestration integration tests — trace tree, parallel, error propagation"
```

---

### Task 7: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rake test`
Expected: All tests PASS, 0 failures

- [ ] **Step 2: Verify require chain loads cleanly**

Run: `bundle exec ruby -e "require 'solid_agent'; puts SolidAgent::Orchestration::DSL"`
Expected: prints module reference, no errors

- [ ] **Step 3: Commit any final cleanup**

```bash
git add -A
git commit -m "chore: orchestration plan complete — delegate, agent_tool, parallel, error propagation, trace tree"
```
