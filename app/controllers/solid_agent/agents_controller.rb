module SolidAgent
  class AgentsController < ApplicationController
    def index
      agent_names = Trace.distinct.pluck(:agent_class)
      agents = agent_names.map do |name|
        traces = Trace.where(agent_class: name)
        {
          name: name,
          total_traces: traces.count,
          total_tokens: traces.sum { |t| (t.usage['input_tokens'] || 0) + (t.usage['output_tokens'] || 0) },
          last_run: traces.maximum(:created_at)
        }
      end

      render inertia: 'solid_agent/Agents/Index', props: { agents: agents }
    end
  end
end
