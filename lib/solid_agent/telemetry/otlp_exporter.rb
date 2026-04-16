require 'json'
require 'net/http'
require 'uri'
require 'stringio'
require 'zlib'

module SolidAgent
  module Telemetry
    class OTLPExporter < Exporter
      DEFAULT_ENDPOINT = 'http://localhost:4318/v1/traces'

      attr_reader :endpoint, :headers

      def initialize(endpoint: DEFAULT_ENDPOINT, headers: {})
        @endpoint = endpoint
        @headers = headers
      end

      def export_trace(trace)
        body = build_otlp_body(trace)
        return if body.nil?

        uri = URI.parse(@endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Post.new(uri.path, {
          'Content-Type' => 'application/json'
        }.merge(@headers))
        request.body = body

        http.request(request)
      rescue StandardError
      end

      def build_otlp_body(trace)
        resource_spans = build_resource_spans(trace)
        return nil unless resource_spans

        { resourceSpans: [resource_spans] }.to_json
      end

      def build_resource_spans(trace)
        spans = trace.spans.where.not(otel_span_id: nil).order(:started_at)
        return nil if spans.empty? && !trace.otel_trace_id

        {
          resource: {
            attributes: [
              { key: 'solid_agent', value: true },
              { key: 'service.name', value: { stringValue: 'solid_agent' } },
              { key: 'service.version', value: { stringValue: '0.1.0' } }
            ]
          },
          scope_spans: [
            {
              scope: { name: 'solid_agent', version: '0.1.0' },
              spans: spans.map { |span| build_otel_span(span, trace) }
            }
          ]
        }
      end

      private

      def build_otel_span(span, trace)
        otel_name = otel_span_name(span)
        parent_id = span.parent_span&.otel_span_id || trace.otel_span_id

        otel_span = {
          trace_id: trace.otel_trace_id,
          span_id: span.otel_span_id,
          parent_span_id: parent_id,
          name: otel_name,
          kind: span_kind(span),
          start_time_unix_nano: time_to_nanos(span.started_at || span.created_at),
          end_time_unix_nano: time_to_nanos(span.completed_at || Time.current),
          status: otel_status(span),
          attributes: build_otel_attributes(span, trace)
        }

        otel_span[:parent_span_id] = nil if otel_span[:parent_span_id] == "\0" * 8
        otel_span
      end

      def otel_span_name(span)
        metadata = span.metadata || {}
        operation = metadata['gen_ai.operation.name']

        if operation == 'chat'
          model = metadata['gen_ai.request.model'] || 'unknown'
          "chat #{model}"
        elsif operation == 'execute_tool'
          tool_name = metadata['gen_ai.tool.name'] || span.name
          "execute_tool #{tool_name}"
        else
          span.name || 'unknown'
        end
      end

      def span_kind(span)
        metadata = span.metadata || {}
        operation = metadata['gen_ai.operation.name']
        operation == 'chat' ? :SPAN_KIND_CLIENT : :SPAN_KIND_INTERNAL
      end

      def otel_status(span)
        if span.status == 'error'
          { code: :STATUS_CODE_ERROR }
        else
          { code: :STATUS_CODE_OK }
        end
      end

      def build_otel_attributes(span, trace)
        metadata = span.metadata || {}
        attrs = []

        metadata.each do |key, value|
          next if key.start_with?('_')

          attrs << if value.is_a?(Integer)
                     { key: key, value: { intValue: value } }
                   elsif value.is_a?(Float)
                     { key: key, value: { doubleValue: value } }
                   elsif value.is_a?(TrueClass) || value.is_a?(FalseClass)
                     { key: key, value: { boolValue: value } }
                   elsif value.is_a?(Array)
                     { key: key, value: { arrayValue: { values: value.map { |v| { stringValue: v.to_s } } } } }
                   else
                     { key: key, value: value.to_s }
                   end
        end

        attrs << { key: 'solid_agent.span_type', value: span.span_type.to_s }
        attrs << { key: 'solid_agent.agent_class', value: trace.agent_class.to_s }

        attrs << { key: 'gen_ai.conversation.id', value: trace.conversation_id.to_s } if trace.conversation_id

        attrs
      end

      def hex_to_binary(hex_string)
        return nil unless hex_string

        [hex_string].pack('H*')
      end

      def time_to_nanos(time)
        return 0 unless time

        (time.to_f * 1_000_000_000).to_i
      end

      def gzip(data)
        io = StringIO.new
        gz = Zlib::GzipWriter.new(io)
        gz.write(data)
        gz.close
        io.string
      end
    end
  end
end
