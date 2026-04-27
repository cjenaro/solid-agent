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

    def update_status
      @trace = Trace.find(params[:id])
      new_status = params[:status]

      unless Trace::STATUSES.include?(new_status)
        redirect_to solid_agent.trace_path(@trace), alert: "Invalid status: #{new_status}" and return
      end

      @trace.update!(status: new_status, completed_at: %w[completed failed cancelled].include?(new_status) ? Time.current : nil)
      redirect_to solid_agent.trace_path(@trace), notice: "Trace ##{@trace.id} updated to #{new_status}"
    end

    def cancel_running
      count = Trace.where(status: %w[running pending]).update_all(status: 'cancelled', completed_at: Time.current)
      redirect_to solid_agent.traces_path, notice: "Cancelled #{count} trace(s)"
    end
  end
end
