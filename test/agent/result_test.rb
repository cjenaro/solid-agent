require 'test_helper'
require 'solid_agent'
require 'solid_agent/agent/result'

class AgentResultTest < ActiveSupport::TestCase
  test 'creates result with output' do
    result = SolidAgent::Agent::Result.new(
      trace_id: 1,
      output: 'The answer is 42',
      usage: SolidAgent::Types::Usage.new(input_tokens: 100, output_tokens: 50),
      iterations: 3
    )
    assert_equal 'The answer is 42', result.output
    assert_equal 150, result.usage.total_tokens
    assert_equal 3, result.iterations
  end

  test 'result status predicates' do
    success = SolidAgent::Agent::Result.new(
      trace_id: 1, output: 'done', status: :completed,
      usage: SolidAgent::Types::Usage.new(input_tokens: 0, output_tokens: 0), iterations: 1
    )
    assert success.completed?
    assert_not success.failed?

    failed = SolidAgent::Agent::Result.new(
      trace_id: 1, output: nil, status: :failed, error: 'boom',
      usage: SolidAgent::Types::Usage.new(input_tokens: 0, output_tokens: 0), iterations: 1
    )
    assert failed.failed?
    assert_not failed.completed?
  end
end
