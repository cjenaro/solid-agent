module SolidAgent
  class TraceRetentionJob < ApplicationJob
    queue_as :solid_agent

    def perform(retention: SolidAgent.configuration.trace_retention)
      return if retention == :keep_all

      cutoff = retention.ago
      old_traces = Trace.where('created_at < ?', cutoff)
      old_traces.find_each do |trace|
        trace.spans.destroy_all
        trace.destroy
      end
    end
  end
end
