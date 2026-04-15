module SolidAgent
  class TracesController < ApplicationController
    def index
      @traces = Trace.includes(:conversation)
      @traces = @traces.where(agent_class: params[:agent_class]) if params[:agent_class].present?
      @traces = @traces.where(status: params[:status]) if params[:status].present?
      @traces = @traces.order(created_at: :desc).limit(50)
      @agent_classes = Trace.distinct.pluck(:agent_class)
      @statuses = Trace::STATUSES
    end

    def show
      @trace = Trace.includes(spans: :child_spans, child_traces: :spans).find(params[:id])
      @parent_trace = @trace.parent_trace
    end
  end
end
