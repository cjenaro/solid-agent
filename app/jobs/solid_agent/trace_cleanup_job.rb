module SolidAgent
  class ApplicationJob < ActiveJob::Base; end unless defined?(ApplicationJob)

  class TraceCleanupJob < ApplicationJob
    queue_as :solid_agent

    def perform
      max_duration = SolidAgent.configuration.max_trace_running_duration
      return if max_duration.nil?

      # Find traces that have been running longer than max_duration
      cutoff_time = max_duration.ago

      SolidAgent::Trace.where(status: 'running')
                       .where('started_at < ?', cutoff_time)
                       .find_each do |trace|
        # Mark the trace as failed
        trace.update!(
          status: 'failed',
          error: 'Timed out - exceeded max_trace_running_duration',
          completed_at: Time.current
        )

        # Also mark any running spans on this trace as failed
        trace.spans.where(status: 'running').update_all(
          status: 'failed',
          completed_at: Time.current
        )
      end
    end
  end
end
