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
