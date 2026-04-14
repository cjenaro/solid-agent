require 'test_helper'
require 'solid_agent/tool/execution_engine'
require 'solid_agent/tool/inline_tool'

class ExecutionEngineTest < ActiveSupport::TestCase
  def setup
    @registry = SolidAgent::Tool::Registry.new
    @registry.register(SolidAgent::Tool::InlineTool.new(
                         name: :fast_tool, description: 'Fast', parameters: [],
                         block: proc { 'fast_result' }
                       ))
    @registry.register(SolidAgent::Tool::InlineTool.new(
                         name: :slow_tool, description: 'Slow', parameters: [],
                         block: proc {
                           sleep 0.1
                           'slow_result'
                         }
                       ))
    @registry.register(SolidAgent::Tool::InlineTool.new(
                         name: :error_tool, description: 'Errors', parameters: [],
                         block: proc { raise 'tool error' }
                       ))
    @registry.register(SolidAgent::Tool::InlineTool.new(
                         name: :add, description: 'Add', parameters: [
                                                           { name: :a, type: :integer, required: true },
                                                           { name: :b, type: :integer, required: true }
                                                         ],
                         block: proc { |a:, b:| a + b }
                       ))
  end

  test 'executes single tool call' do
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: @registry, concurrency: 1)
    results = engine.execute_all([
                                   SolidAgent::Types::ToolCall.new(id: 'c1', name: 'fast_tool', arguments: {})
                                 ])
    assert_equal 1, results.length
    assert_equal 'fast_result', results['c1']
  end

  test 'executes multiple tool calls sequentially with concurrency 1' do
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: @registry, concurrency: 1)
    results = engine.execute_all([
                                   SolidAgent::Types::ToolCall.new(id: 'c1', name: 'fast_tool', arguments: {}),
                                   SolidAgent::Types::ToolCall.new(id: 'c2', name: 'fast_tool', arguments: {})
                                 ])
    assert_equal 2, results.length
    assert_equal 'fast_result', results['c1']
    assert_equal 'fast_result', results['c2']
  end

  test 'executes tool calls in parallel with concurrency > 1' do
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: @registry, concurrency: 3)
    start = Time.now
    results = engine.execute_all([
                                   SolidAgent::Types::ToolCall.new(id: 'c1', name: 'slow_tool', arguments: {}),
                                   SolidAgent::Types::ToolCall.new(id: 'c2', name: 'slow_tool', arguments: {}),
                                   SolidAgent::Types::ToolCall.new(id: 'c3', name: 'slow_tool', arguments: {})
                                 ])
    elapsed = Time.now - start
    assert_equal 3, results.length
    assert elapsed < 0.35, "Parallel execution should be faster than sequential (was #{elapsed}s)"
  end

  test 'captures tool errors' do
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: @registry, concurrency: 1)
    results = engine.execute_all([
                                   SolidAgent::Types::ToolCall.new(id: 'c1', name: 'error_tool', arguments: {})
                                 ])
    assert_instance_of SolidAgent::Tool::ExecutionEngine::ToolExecutionError, results['c1']
  end

  test 'executes tool with arguments' do
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: @registry, concurrency: 1)
    results = engine.execute_all([
                                   SolidAgent::Types::ToolCall.new(id: 'c1', name: 'add',
                                                                   arguments: { 'a' => 3, 'b' => 4 })
                                 ])
    assert_equal 7, results['c1']
  end

  test 'respects timeout' do
    @registry.register(SolidAgent::Tool::InlineTool.new(
                         name: :timeout_tool, description: 'Timeout', parameters: [],
                         block: proc {
                           sleep 10
                           'done'
                         }
                       ))
    engine = SolidAgent::Tool::ExecutionEngine.new(registry: @registry, concurrency: 1, timeout: 0.1)
    results = engine.execute_all([
                                   SolidAgent::Types::ToolCall.new(id: 'c1', name: 'timeout_tool', arguments: {})
                                 ])
    assert_instance_of SolidAgent::Tool::ExecutionEngine::ToolExecutionError, results['c1']
  end

  test 'requires approval for flagged tools' do
    engine = SolidAgent::Tool::ExecutionEngine.new(
      registry: @registry, concurrency: 1,
      approval_required: ['fast_tool']
    )
    results = engine.execute_all([
                                   SolidAgent::Types::ToolCall.new(id: 'c1', name: 'fast_tool', arguments: {})
                                 ])
    assert_instance_of SolidAgent::Tool::ExecutionEngine::ApprovalRequired, results['c1']
  end

  test 'approved tool executes normally' do
    engine = SolidAgent::Tool::ExecutionEngine.new(
      registry: @registry, concurrency: 1,
      approval_required: ['fast_tool']
    )
    engine.approve('c1')
    results = engine.execute_all([
                                   SolidAgent::Types::ToolCall.new(id: 'c1', name: 'fast_tool', arguments: {})
                                 ])
    assert_equal 'fast_result', results['c1']
  end
end
