require 'test_helper'
require 'solid_agent'

class SolidAgentTest < ActiveSupport::TestCase
  test 'module is defined' do
    assert defined?(SolidAgent)
  end

  test 'has Error class' do
    assert SolidAgent::Error < StandardError
  end
end
