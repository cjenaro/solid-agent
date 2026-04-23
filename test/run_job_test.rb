require 'test_helper'
require 'active_job'
require 'solid_agent'
require 'solid_agent/agent/dsl'
require 'solid_agent/agent/base'
require 'solid_agent/agent/result'
require 'solid_agent/react/observer'
require 'solid_agent/react/loop'

module SolidAgent
  class ApplicationJob < ActiveJob::Base; end
end

require 'solid_agent/run_job'

class CallbackTrackingAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  max_iterations 1
  timeout 5.minutes

  instructions 'You are a test agent.'

  @@callback_log = []

  def self.callback_log
    @@callback_log
  end

  def self.reset_callback_log!
    @@callback_log = []
  end

  before_invoke :log_before
  after_invoke :log_after

  private

  def log_before(input)
    @@callback_log << { event: :before_invoke, input: input }
  end

  def log_after(result)
    @@callback_log << { event: :after_invoke, output: result.output&.truncate(20) }
  end
end

class RunJobTest < ActiveSupport::TestCase
  test 'RunJob is an ActiveJob subclass' do
    assert SolidAgent::RunJob < ActiveJob::Base
  end

  test 'RunJob is a SolidAgent ApplicationJob subclass' do
    assert SolidAgent::RunJob < SolidAgent::ApplicationJob
  end

  test 'RunJob has queue set' do
    assert_equal 'solid_agent', SolidAgent::RunJob.queue_name
  end

  test 'before_invoke and after_invoke callbacks are stored on agent class' do
    assert_equal [:log_before], CallbackTrackingAgent.before_invoke_callbacks
    assert_equal [:log_after], CallbackTrackingAgent.after_invoke_callbacks
  end
end
