require 'test_helper'
require 'active_job'
require 'solid_agent'
require 'solid_agent/agent/dsl'
require 'solid_agent/agent/base'
require 'solid_agent/agent/result'
require 'solid_agent/react/observer'
require 'solid_agent/react/loop'
require 'solid_agent/run_job'

class SimpleAgent < SolidAgent::Base
  provider :openai
  model SolidAgent::Models::OpenAi::GPT_4O
  instructions 'You are simple.'
end

class AgentBaseTest < ActiveSupport::TestCase
  test 'perform_later creates trace and enqueues job' do
    conversation = SolidAgent::Conversation.create!(agent_class: 'SimpleAgent')
    trace = SimpleAgent.perform_later('Hello', conversation_id: conversation.id)

    assert_instance_of SolidAgent::Trace, trace
    assert_equal 'pending', trace.status
    assert_equal 'Hello', trace.input
  end

  test 'creates conversation if not provided' do
    trace = SimpleAgent.perform_later('Hello')
    assert trace.conversation
    assert_equal 'SimpleAgent', trace.conversation.agent_class
  end
end
