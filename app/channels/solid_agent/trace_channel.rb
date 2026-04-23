module SolidAgent
  class TraceChannel
    CHANNEL_NAME = 'solid_agent:trace'

    def self.broadcast_trace_update(trace)
      data = {
        type: 'trace_update',
        trace_id: trace.id,
        status: trace.status,
        iteration_count: trace.iteration_count,
        usage: trace.usage,
        started_at: trace.started_at,
        completed_at: trace.completed_at
      }
      broadcast(data)
    end

    def self.broadcast_span_update(span)
      data = {
        type: 'span_update',
        trace_id: span.trace_id,
        span_id: span.id,
        span_type: span.span_type,
        name: span.name,
        status: span.status,
        tokens_in: span.tokens_in,
        tokens_out: span.tokens_out,
        output: span.output&.truncate(500)
      }
      broadcast(data)
    end

    def self.subscribe(trace_id = nil)
      trace_id ? "#{CHANNEL_NAME}:#{trace_id}" : CHANNEL_NAME
    end

    private

    def self.broadcast(data)
      if defined?(ActionCable)
        ActionCable.server.broadcast(CHANNEL_NAME, data)
      end
    rescue StandardError => e
      Rails.logger.debug { "[SolidAgent] ActionCable broadcast skipped: #{e.message}" } if defined?(Rails)
    end
  end
end
