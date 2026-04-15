module SolidAgent
  class DashboardController < ApplicationController
    def index
      @stats = dashboard_stats
      @recent_traces = Trace.order(created_at: :desc).limit(10)
    end

    private

    def dashboard_stats
      {
        total_traces: Trace.count,
        active_traces: Trace.where(status: 'running').count,
        total_conversations: Conversation.count,
        total_tokens: total_tokens,
        agents: Trace.distinct.pluck(:agent_class)
      }
    end

    def recent_traces
      Trace.order(created_at: :desc).limit(10).as_json(
        only: %i[id agent_class status started_at completed_at usage]
      )
    end

    def total_tokens
      Trace.all.sum { |t| (t.usage['input_tokens'] || 0) + (t.usage['output_tokens'] || 0) }
    end
  end
end
