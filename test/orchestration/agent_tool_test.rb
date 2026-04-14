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
