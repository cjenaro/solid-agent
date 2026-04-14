module SolidAgent
  class MemoryEntry < ApplicationRecord
    self.table_name = 'solid_agent_memory_entries'

    belongs_to :conversation, class_name: 'SolidAgent::Conversation', optional: true

    ENTRY_TYPES = %w[observation fact preference].freeze

    validates :entry_type, inclusion: { in: ENTRY_TYPES }
    validates :content, presence: true

    scope :for_agent, ->(agent_class) { where(agent_class: agent_class) }
    scope :observations, -> { where(entry_type: :observation) }
    scope :facts, -> { where(entry_type: :fact) }
    scope :preferences, -> { where(entry_type: :preference) }
  end
end
