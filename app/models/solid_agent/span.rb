module SolidAgent
  class Span < ApplicationRecord
    self.table_name = 'solid_agent_spans'

    belongs_to :trace, class_name: 'SolidAgent::Trace'
    belongs_to :parent_span, class_name: 'SolidAgent::Span', optional: true
    has_many :child_spans, class_name: 'SolidAgent::Span', foreign_key: :parent_span_id, dependent: :nullify

    SPAN_TYPES = %w[llm chunk tool think act observe tool_execution llm_call].freeze

    validates :span_type, inclusion: { in: SPAN_TYPES }

    def duration
      return nil unless started_at && completed_at

      completed_at - started_at
    end

    def total_tokens
      tokens_in + tokens_out
    end
  end
end
