module SolidAgent
  class TracesController < ApplicationController
    def index
      traces = Trace.includes(:conversation)
      traces = traces.where(agent_class: params[:agent_class]) if params[:agent_class].present?
      traces = traces.where(status: params[:status]) if params[:status].present?
      traces = traces.order(created_at: :desc).limit(50)

      render inertia: 'solid_agent/Traces/Index', props: {
        traces: traces.as_json(
          only: %i[id agent_class status started_at completed_at usage iteration_count created_at],
          include: { conversation: { only: %i[id agent_class] } }
        ),
        agent_classes: Trace.distinct.pluck(:agent_class),
        statuses: Trace::STATUSES
      }
    end

    def show
      trace = Trace.includes(spans: :child_spans, child_traces: :spans).find(params[:id])

      render inertia: 'solid_agent/Traces/Show', props: {
        trace: trace.as_json(
          only: %i[id agent_class status started_at completed_at usage iteration_count input output error created_at],
          include: {
            spans: { only: %i[id span_type name status tokens_in tokens_out started_at completed_at input output
                              parent_span_id] },
            child_traces: { only: %i[id agent_class status started_at completed_at] },
            conversation: { only: %i[id] }
          }
        ),
        parent_trace: trace.parent_trace&.as_json(only: %i[id agent_class])
      }
    end
  end
end
