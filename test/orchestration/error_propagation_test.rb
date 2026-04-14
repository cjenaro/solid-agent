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
      tool: nil,
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
