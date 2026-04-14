require 'test_helper'

class MemoryEntryTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
  end

  test 'creates an observation entry' do
    entry = SolidAgent::MemoryEntry.create!(conversation: @conversation, agent_class: 'ResearchAgent',
                                            entry_type: :observation, content: 'User prefers bullet points')
    assert_equal 'observation', entry.entry_type
  end

  test 'entry types are validated' do
    entry = SolidAgent::MemoryEntry.new(conversation: @conversation, agent_class: 'TestAgent', entry_type: 'invalid',
                                        content: 'test')
    assert_not entry.valid?
  end

  test 'scope by agent class' do
    SolidAgent::MemoryEntry.create!(conversation: @conversation, agent_class: 'AgentA', entry_type: :observation,
                                    content: 'a')
    SolidAgent::MemoryEntry.create!(conversation: @conversation, agent_class: 'AgentB', entry_type: :observation,
                                    content: 'b')
    assert_equal 1, SolidAgent::MemoryEntry.for_agent('AgentA').count
  end

  test 'scope by entry type' do
    SolidAgent::MemoryEntry.create!(conversation: @conversation, agent_class: 'TestAgent', entry_type: :observation,
                                    content: 'a')
    SolidAgent::MemoryEntry.create!(conversation: @conversation, agent_class: 'TestAgent', entry_type: :fact,
                                    content: 'b')
    assert_equal 1, SolidAgent::MemoryEntry.observations.where(conversation: @conversation).count
  end
end
