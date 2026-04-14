module SolidAgent
  class ToolsController < ApplicationController
    def index
      tool_spans = Span.where(span_type: 'tool_execution')
      tool_names = tool_spans.distinct.pluck(:name)

      tools = tool_names.map do |name|
        spans = tool_spans.where(name: name)
        {
          name: name,
          total_calls: spans.count,
          avg_duration: spans.filter_map(&:duration).then { |d| d.empty? ? 0 : d.sum / d.size },
          error_count: spans.where(status: 'error').count,
          last_used: spans.maximum(:created_at)
        }
      end

      render inertia: 'solid_agent/Tools/Index', props: { tools: tools }
    end
  end
end
