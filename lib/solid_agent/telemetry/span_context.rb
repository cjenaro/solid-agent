module SolidAgent
  module Telemetry
    class SpanContext
      TRACESTATE_VERSION = '00'
      SAMPLED_FLAG = '01'

      attr_reader :trace_id, :span_id

      def initialize(trace_id: nil, span_id: nil)
        require 'securerandom'
        @trace_id = trace_id || SecureRandom.hex(16)
        @span_id = span_id || SecureRandom.hex(8)
      end

      def create_child
        SpanContext.new(trace_id: @trace_id)
      end

      def traceparent_header
        "#{TRACESTATE_VERSION}-#{@trace_id}-#{@span_id}-#{SAMPLED_FLAG}"
      end

      def self.from_traceparent(header)
        return nil unless header.is_a?(String)

        parts = header.split('-')
        return nil unless parts.length == 4
        return nil unless parts[0] == TRACESTATE_VERSION
        return nil unless parts[1]&.match?(/\A[0-9a-f]{32}\z/)
        return nil unless parts[2]&.match?(/\A[0-9a-f]{16}\z/)

        new(trace_id: parts[1], span_id: parts[2])
      end
    end
  end
end
