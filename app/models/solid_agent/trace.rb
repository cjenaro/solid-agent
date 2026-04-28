module SolidAgent
  class Trace < ApplicationRecord
    self.table_name = 'solid_agent_traces'

    belongs_to :conversation, class_name: 'SolidAgent::Conversation'
    belongs_to :parent_trace, class_name: 'SolidAgent::Trace', optional: true
    has_many :child_traces, class_name: 'SolidAgent::Trace', foreign_key: :parent_trace_id, dependent: :nullify
    has_many :spans, class_name: 'SolidAgent::Span', dependent: :destroy
    has_many :messages, class_name: 'SolidAgent::Message', dependent: :destroy

    STATUSES = %w[pending running completed failed paused cancelled].freeze

    validates :status, inclusion: { in: STATUSES }

    before_create :generate_otel_ids

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

    def cost
      model = resolve_model
      return 0.0 unless model

      in_tok = usage['input_tokens'] || 0
      out_tok = usage['output_tokens'] || 0
      (in_tok * model.input_price_per_million / 1_000_000.0) +
        (out_tok * model.output_price_per_million / 1_000_000.0)
    end

    # Recursively aggregates cost from child traces (delegate/agent_tool runs)
    def total_cost
      own = cost
      children_cost = child_traces.sum(&:total_cost)
      own + children_cost
    end

    def total_iterations
      iteration_count + child_traces.sum(&:total_iterations)
    end

    def tool_summary
      all_spans = self_and_descendant_spans
      tool_spans = all_spans.select { |s| s.span_type == 'tool' }
      tool_spans.group_by(&:name).transform_values(&:count)
    end

    def model_name
      resolve_model&.id || extract_model_from_spans
    end

    def self_and_descendant_spans
      all_spans = spans.to_a
      child_traces.each do |ct|
        all_spans.concat(ct.self_and_descendant_spans)
      end
      all_spans
    end

    private

    def resolve_model
      model_id = extract_model_from_spans
      SolidAgent::Models::OpenAi.find(model_id) if model_id
    end

    def extract_model_from_spans
      llm_span = spans.where(span_type: 'llm').where.not(metadata: nil)
                        .where("metadata LIKE '%gen_ai.request.model%'")
                        .order(:created_at).first
      llm_span&.metadata&.dig('gen_ai.request.model')
    end

    def generate_otel_ids
      require 'securerandom'
      self.otel_trace_id ||= SecureRandom.hex(16)
      self.otel_span_id ||= SecureRandom.hex(8)
    end

    def set_defaults
      self.usage ||= {}
    end
  end
end
