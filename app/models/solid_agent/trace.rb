module SolidAgent
  class Trace < ApplicationRecord
    self.table_name = 'solid_agent_traces'

    belongs_to :conversation, class_name: 'SolidAgent::Conversation'
    belongs_to :parent_trace, class_name: 'SolidAgent::Trace', optional: true
    has_many :child_traces, class_name: 'SolidAgent::Trace', foreign_key: :parent_trace_id, dependent: :nullify
    has_many :spans, class_name: 'SolidAgent::Span', dependent: :destroy

    STATUSES = %w[pending running completed failed paused].freeze

    validates :status, inclusion: { in: STATUSES }

    after_initialize :set_defaults

    def usage
      self[:usage] || {}
    end

    def start!
      update!(status: 'running', started_at: Time.current)
    end

    def complete!
      update!(status: 'completed', completed_at: Time.current)
    end

    def fail!(error_message)
      update!(status: 'failed', error: error_message, completed_at: Time.current)
    end

    def pause!
      update!(status: 'paused')
    end

    def resume!
      update!(status: 'running')
    end

    def duration
      return nil unless started_at && completed_at

      completed_at - started_at
    end

    def total_tokens
      (usage['input_tokens'] || 0) + (usage['output_tokens'] || 0)
    end

    private

    def set_defaults
      self.usage ||= {}
    end
  end
end
