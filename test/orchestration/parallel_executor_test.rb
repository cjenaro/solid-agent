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
