module SolidAgent
  class AgentsController < ApplicationController
    def index
      @agents = Trace.distinct.pluck(:agent_class).map do |name|
        traces = Trace.where(agent_class: name)
        OpenStruct.new(
          name: name,
          total_traces: traces.count,
          total_tokens: traces.sum { |t| (t.usage['input_tokens'] || 0) + (t.usage['output_tokens'] || 0) },
          last_run: traces.maximum(:created_at)
        )
      end
    end
  end
end
