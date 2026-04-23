require 'test_helper'
require 'solid_agent'
require 'solid_agent/agent/dsl'
require 'solid_agent/agent/base'

class TestAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  max_tokens 4096
  temperature 0.7

  instructions 'You are a test agent.'

  memory :sliding_window, max_messages: 20

  tool :greet, description: 'Say hello' do |name:|
    "Hello, #{name}!"
  end

  concurrency 2
  max_iterations 10
  max_tokens_per_run 50_000
  timeout 2.minutes
end

class AgentDSLTest < ActiveSupport::TestCase
  test 'stores provider' do
    assert_equal :openai, TestAgent.agent_provider
  end

  test 'stores model' do
    assert_equal SolidAgent::Models::OpenAi::GPT_4O, TestAgent.agent_model
  end

  test 'stores max_tokens' do
    assert_equal 4096, TestAgent.agent_max_tokens
  end

  test 'stores temperature' do
    assert_equal 0.7, TestAgent.agent_temperature
  end

  test 'stores instructions' do
    assert_equal 'You are a test agent.', TestAgent.agent_instructions
  end

  test 'stores memory config' do
    config = TestAgent.agent_memory_config
    assert_equal :sliding_window, config[:strategy]
    assert_equal 20, config[:max_messages]
  end

  test 'registers tools in registry' do
    assert TestAgent.agent_tool_registry.registered?('greet')
  end

  test 'stores concurrency' do
    assert_equal 2, TestAgent.agent_concurrency
  end

  test 'stores safety guards' do
    assert_equal 10, TestAgent.agent_max_iterations
    assert_equal 50_000, TestAgent.agent_max_tokens_per_run
    assert_equal 120, TestAgent.agent_timeout
  end

  test 'default values' do
    bare = Class.new(SolidAgent::Base)
    assert_equal :openai, bare.agent_provider
    assert_equal 1, bare.agent_concurrency
    assert_equal 25, bare.agent_max_iterations
  end
end

class ToolChoiceAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  tool_choice :required

  tool :ping, description: 'Ping' do
    'pong'
  end
end

class ToolChoiceAutoAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  tool_choice :auto
end

class ToolChoiceNoneAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  tool_choice :none
end

class AgentToolChoiceTest < ActiveSupport::TestCase
  test 'tool_choice stores the value' do
    assert_equal :required, ToolChoiceAgent.agent_tool_choice
  end

  test 'tool_choice auto' do
    assert_equal :auto, ToolChoiceAutoAgent.agent_tool_choice
  end

  test 'tool_choice none' do
    assert_equal :none, ToolChoiceNoneAgent.agent_tool_choice
  end

  test 'tool_choice defaults to nil' do
    bare = Class.new(SolidAgent::Base)
    assert_nil bare.agent_tool_choice
  end
end
