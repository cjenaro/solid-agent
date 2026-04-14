require 'test_helper'
require 'solid_agent'
require 'solid_agent/react/observer'

class ReactObserverTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    @trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: 'TestAgent',
      trace_type: :agent_run,
      started_at: Time.current
    )
  end

  test 'detects max iterations exceeded' do
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

  test 'detects max iterations not exceeded' do
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

  test 'detects token budget exceeded' do
    observer = SolidAgent::React::Observer.new(
      trace: @trace,
      max_iterations: 25,
      max_tokens_per_run: 100,
      started_at: Time.current,
      timeout: 5.minutes
    )
    @trace.update!(usage: { 'input_tokens' => 60, 'output_tokens' => 50 })
    assert observer.token_budget_exceeded?
  end

  test 'detects timeout exceeded' do
    observer = SolidAgent::React::Observer.new(
      trace: @trace,
      max_iterations: 25,
      max_tokens_per_run: 100_000,
      started_at: 10.minutes.ago,
      timeout: 5.minutes
    )
    assert observer.timeout_exceeded?
  end

  test 'detects context near limit' do
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

  test 'should_stop combines all checks' do
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
