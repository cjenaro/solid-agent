module SolidAgent
  class ToolsController < ApplicationController
    def index
      tool_spans = Span.where(span_type: 'tool_execution')
      tool_names = tool_spans.distinct.pluck(:name)

      @tools = tool_names.map do |name|
        spans = tool_spans.where(name: name)
        durations = spans.filter_map(&:duration)
        OpenStruct.new(
          name: name,
          total_calls: spans.count,
          avg_duration: durations.empty? ? 0 : durations.sum / durations.size,
          error_count: spans.where(status: 'error').count,
          last_used: spans.maximum(:created_at)
        )
      end
    end
  end
end
