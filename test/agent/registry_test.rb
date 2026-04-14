require 'test_helper'
require 'solid_agent'
require 'solid_agent/agent/registry'
require 'solid_agent/agent/base'

class RegisteredAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  instructions 'Test'
end

class AgentRegistryTest < ActiveSupport::TestCase
  def setup
    @registry = SolidAgent::Agent::Registry.new
  end

  test 'registers agent class' do
    @registry.register(RegisteredAgent)
    assert @registry.registered?('RegisteredAgent')
  end

  test 'resolves agent by name' do
    @registry.register(RegisteredAgent)
    assert_equal RegisteredAgent, @registry.resolve('RegisteredAgent')
  end

  test 'lists all registered agents' do
    @registry.register(RegisteredAgent)
    agents = @registry.all
    assert_equal 1, agents.length
    assert_equal 'RegisteredAgent', agents.first.name
    assert_equal RegisteredAgent, agents.first.klass
  end

  test 'raises for unknown agent' do
    assert_raises(SolidAgent::Error) { @registry.resolve('NonExistent') }
  end
end
