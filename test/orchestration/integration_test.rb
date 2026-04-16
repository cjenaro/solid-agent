require 'test_helper'

class OrchestrationIntegrationTest < ActiveSupport::TestCase
  class ResearchAgent
    def self.name
      'OrchestrationIntegrationTest::ResearchAgent'
    end

    def self.perform_now(input, trace:, conversation:)
      trace.update!(output: "Researched: #{input}")
      "Researched: #{input}"
    end
  end

  class WriterAgent
    def self.name
      'OrchestrationIntegrationTest::WriterAgent'
    end

    def self.perform_now(input, trace:, conversation:)
      trace.update!(output: "Written: #{input}")
      "Written: #{input}"
    end
  end

  class SummaryAgent
    def self.name
      'OrchestrationIntegrationTest::SummaryAgent'
    end

    def self.perform_now(input, conversation:)
      "Summary: #{input}"
    end
  end

  class FailingAgent
    def self.name
      'OrchestrationIntegrationTest::FailingAgent'
    end

    def self.perform_now(_input, trace:, conversation:)
      raise 'Agent crashed'
    end
  end

  class FlakeyAgent
    attr_reader :call_count

    def initialize
      @call_count = 0
    end

    def name
      'OrchestrationIntegrationTest::FlakeyAgent'
    end

    def perform_now(input, trace:, conversation:)
      @call_count += 1
      raise 'Transient failure' if @call_count < 3

      trace.update!(output: "Eventually worked: #{input}")
      "Eventually worked: #{input}"
    end
  end

  def build_supervisor
    Class.new do
      include SolidAgent::Orchestration::DSL

      delegate :research, to: ResearchAgent, description: 'Research a topic'
      delegate :writing, to: WriterAgent, description: 'Write content'
      delegate :failing, to: FailingAgent, description: 'Always fails'
      agent_tool :summarize, agent: SummaryAgent, description: 'Quick summary'

      on_delegate_failure :research, strategy: :report_error
      on_delegate_failure :writing, strategy: :retry, attempts: 3
      on_delegate_failure :failing, strategy: :report_error
    end
  end

  def build_context
    conversation = SolidAgent::Conversation.create!(agent_class: 'SupervisorAgent')
    trace = SolidAgent::Trace.create!(
      conversation: conversation,
      agent_class: 'SupervisorAgent',
      trace_type: :agent_run
    )
    trace.start!
    { trace: trace, conversation: conversation }
  end

  test 'full delegation creates complete trace tree' do
    supervisor = build_supervisor
    context = build_context

    tool = supervisor.delegates['research']
    result = tool.execute(
      { 'input' => 'Q4 trends' },
      context: context
    )

    assert_equal 'Researched: Q4 trends', result

    parent = context[:trace]
    assert_equal 1, parent.child_traces.count

    child = parent.child_traces.last
    assert_equal 'delegate', child.trace_type
    assert_equal 'OrchestrationIntegrationTest::ResearchAgent', child.agent_class
    assert_equal 'completed', child.status
    assert_equal parent.id, child.parent_trace_id
    assert_equal context[:conversation].id, child.conversation_id
    assert_equal 'Q4 trends', child.input
    assert_equal 'Researched: Q4 trends', child.output
    assert_not_nil child.started_at
    assert_not_nil child.completed_at
  end

  test 'agent-as-tool creates span not child trace' do
    supervisor = build_supervisor
    context = build_context

    tool = supervisor.agent_tools['summarize']
    result = tool.execute(
      { 'input' => 'Long document text' },
      context: context
    )

    assert_equal 'Summary: Long document text', result

    parent = context[:trace]
    assert_equal 0, parent.child_traces.count, 'Agent tool should not create child traces'

    span = parent.spans.where(name: 'summarize').last
    assert_not_nil span
    assert_equal 'tool_execution', span.span_type
    assert_equal 'completed', span.status
    assert_equal 'Summary: Long document text', span.output
    assert_equal 'Long document text', span.input
    assert_equal 'agent_tool', span.metadata['tool_type']
    assert_equal 'OrchestrationIntegrationTest::SummaryAgent', span.metadata['agent_class']
  end

  test 'parallel delegation creates multiple child traces' do
    supervisor = build_supervisor
    context = build_context

    calls = [
      build_call('research', supervisor.delegates['research'], { 'input' => 'topic A' }),
      build_call('writing', supervisor.delegates['writing'], { 'input' => 'topic B' })
    ]

    results = SolidAgent::Orchestration::ParallelExecutor.execute(
      calls, context: context, concurrency: 2,
             error_strategies: supervisor.delegate_error_strategies
    )

    assert_equal 2, results.size
    assert_includes results, 'Researched: topic A'
    assert_includes results, 'Written: topic B'

    parent = context[:trace]
    assert_equal 2, parent.child_traces.count

    children = parent.child_traces.order(:id).to_a
    assert_equal 'delegate', children[0].trace_type
    assert_equal 'delegate', children[1].trace_type
    assert_equal 'completed', children[0].status
    assert_equal 'completed', children[1].status
    assert_equal parent.id, children[0].parent_trace_id
    assert_equal parent.id, children[1].parent_trace_id
  end

  test 'mixed delegates and agent tools in parallel' do
    supervisor = build_supervisor
    context = build_context

    calls = [
      build_call('research', supervisor.delegates['research'], { 'input' => 'research topic' }),
      build_call('summarize', supervisor.agent_tools['summarize'], { 'input' => 'text to summarize' })
    ]

    results = SolidAgent::Orchestration::ParallelExecutor.execute(
      calls, context: context, concurrency: 2,
             error_strategies: supervisor.delegate_error_strategies
    )

    assert_equal 2, results.size
    assert_includes results, 'Researched: research topic'
    assert_includes results, 'Summary: text to summarize'

    parent = context[:trace]
    assert_equal 1, parent.child_traces.count, 'Only delegate creates child trace'
    assert_equal 1, parent.spans.where(name: 'summarize').count, 'Agent tool creates span'
  end

  test 'report_error strategy returns error to parent without failing parent trace' do
    supervisor = build_supervisor
    context = build_context

    tool = supervisor.delegates['failing']
    strategy = supervisor.delegate_error_strategies['failing']

    result = strategy.execute_with_handling do
      tool.execute({ 'input' => 'test' }, context: context)
    end

    assert_includes result, 'Agent crashed'

    parent = context[:trace]
    assert_equal 'running', parent.status, 'Parent trace should still be running'

    child = parent.child_traces.last
    assert_equal 'failed', child.status
    assert_equal 'Agent crashed', child.error
  end

  test 'fail_parent strategy propagates error to parent trace' do
    supervisor = Class.new do
      include SolidAgent::Orchestration::DSL
      delegate :critical, to: FailingAgent, description: 'Critical task'
      on_delegate_failure :critical, strategy: :fail_parent
    end

    context = build_context

    tool = supervisor.delegates['critical']
    strategy = supervisor.delegate_error_strategies['critical']

    assert_raises(RuntimeError) do
      strategy.execute_with_handling do
        tool.execute({ 'input' => 'critical task' }, context: context)
      end
    end

    child = context[:trace].child_traces.last
    assert_equal 'failed', child.status
  end

  test 'retry strategy retries and creates multiple child traces' do
    flakey = FlakeyAgent.new

    agent_class = Class.new do
      define_method(:name) { 'FlakeyAgent' }
      define_method(:perform_now) do |input, trace:, conversation:|
        flakey.perform_now(input, trace: trace, conversation: conversation)
      end
    end

    supervisor = Class.new do
      include SolidAgent::Orchestration::DSL
    end
    supervisor.delegate :research, to: agent_class.new, description: 'Research'
    supervisor.on_delegate_failure :research, strategy: :retry, attempts: 3

    context = build_context

    tool = supervisor.delegates['research']
    strategy = supervisor.delegate_error_strategies['research']

    result = strategy.execute_with_handling do
      tool.execute({ 'input' => 'flakey task' }, context: context)
    end

    assert_equal 'Eventually worked: flakey task', result

    parent = context[:trace]
    assert parent.child_traces.count >= 1
  end

  test 'orchestration_tool_schemas ready for LLM' do
    supervisor = build_supervisor

    schemas = supervisor.orchestration_tool_schemas
    assert_equal 4, schemas.size

    names = schemas.map { |s| s[:name] }
    assert_includes names, 'research'
    assert_includes names, 'writing'
    assert_includes names, 'failing'
    assert_includes names, 'summarize'

    schemas.each do |schema|
      assert schema[:name].is_a?(String)
      assert schema[:description].is_a?(String)
      assert_equal 'object', schema[:inputSchema][:type]
      assert_includes schema[:inputSchema][:required], 'input'
    end
  end

  test 'find_orchestration_tool locates delegates and agent tools' do
    supervisor = build_supervisor

    research = supervisor.find_orchestration_tool('research')
    assert research.delegate?
    assert_equal 'Research a topic', research.description

    summarize = supervisor.find_orchestration_tool('summarize')
    refute summarize.delegate?
    assert_equal 'Quick summary', summarize.description

    assert_nil supervisor.find_orchestration_tool('nonexistent')
  end

  test 'complete trace tree with delegates, agent tools, and nested spans' do
    supervisor = build_supervisor
    context = build_context
    parent = context[:trace]

    research_tool = supervisor.delegates['research']
    research_tool.execute({ 'input' => 'topic A' }, context: context)

    summarize_tool = supervisor.agent_tools['summarize']
    summarize_tool.execute({ 'input' => 'notes' }, context: context)

    writing_tool = supervisor.delegates['writing']
    writing_tool.execute({ 'input' => 'topic B' }, context: context)

    summarize_tool.execute({ 'input' => 'final notes' }, context: context)

    assert_equal 2, parent.child_traces.count
    assert_equal 2, parent.spans.where(name: 'summarize').count

    child_traces = parent.child_traces.order(:id).to_a
    assert_equal 'OrchestrationIntegrationTest::ResearchAgent', child_traces[0].agent_class
    assert_equal 'OrchestrationIntegrationTest::WriterAgent', child_traces[1].agent_class
    assert_equal 'completed', child_traces[0].status
    assert_equal 'completed', child_traces[1].status

    spans = parent.spans.where(name: 'summarize').order(:id).to_a
    assert_equal 'completed', spans[0].status
    assert_equal 'completed', spans[1].status
    assert_equal 'Summary: notes', spans[0].output
    assert_equal 'Summary: final notes', spans[1].output
  end

  test 'child traces are independently queryable' do
    supervisor = build_supervisor
    context = build_context

    tool = supervisor.delegates['research']
    tool.execute({ 'input' => 'Q4 trends' }, context: context)

    child = context[:trace].child_traces.last

    found = SolidAgent::Trace.find(child.id)
    assert_equal 'delegate', found.trace_type
    assert_equal 'completed', found.status
    assert_equal 'Q4 trends', found.input
    assert_equal 'Researched: Q4 trends', found.output
    assert_not_nil found.parent_trace_id
  end

  test 'delegates across conversations are isolated' do
    supervisor = build_supervisor

    context_a = build_context
    context_b = build_context

    tool = supervisor.delegates['research']
    tool.execute({ 'input' => 'topic A' }, context: context_a)
    tool.execute({ 'input' => 'topic B' }, context: context_b)

    trace_a = context_a[:trace]
    trace_b = context_b[:trace]

    assert_equal 1, trace_a.child_traces.count
    assert_equal 1, trace_b.child_traces.count

    child_a = trace_a.child_traces.last
    child_b = trace_b.child_traces.last

    assert_equal 'topic A', child_a.input
    assert_equal 'topic B', child_b.input
    assert_equal trace_a.id, child_a.parent_trace_id
    assert_equal trace_b.id, child_b.parent_trace_id
    assert_not_equal child_a.conversation_id, child_b.conversation_id
  end

  test 'delegate tool propagates otel_trace_id to child trace' do
    supervisor = build_supervisor
    context = build_context

    tool = supervisor.delegates['research']
    tool.execute({ 'input' => 'Q4 trends' }, context: context)

    parent = context[:trace]
    child = parent.child_traces.last

    assert_not_nil parent.otel_trace_id, 'Parent trace should have an otel_trace_id'
    assert_equal parent.otel_trace_id, child.otel_trace_id, 'Child trace should inherit parent otel_trace_id'
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
