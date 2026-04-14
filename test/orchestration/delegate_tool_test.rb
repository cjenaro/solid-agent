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
