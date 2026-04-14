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
end
