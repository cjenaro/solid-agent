module SolidAgent
  class Conversation < ApplicationRecord
    self.table_name = 'solid_agent_conversations'

    has_many :traces, class_name: 'SolidAgent::Trace', dependent: :destroy
    has_many :messages, class_name: 'SolidAgent::Message', dependent: :destroy
    has_many :memory_entries, class_name: 'SolidAgent::MemoryEntry', dependent: :destroy

    def archive!
      update!(status: 'archived')
    end

    def total_tokens
      traces.sum { |t| (t.usage['input_tokens'] || 0) + (t.usage['output_tokens'] || 0) }
    end
  end
end
