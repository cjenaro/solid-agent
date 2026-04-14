module SolidAgent
  class Message < ApplicationRecord
    self.table_name = 'solid_agent_messages'

    belongs_to :conversation, class_name: 'SolidAgent::Conversation'
    belongs_to :trace, class_name: 'SolidAgent::Trace', optional: true

    ROLES = %w[system user assistant tool].freeze

    validates :role, inclusion: { in: ROLES }
    validates :content, presence: true, if: -> { role.in?(%w[system user tool]) }
  end
end
