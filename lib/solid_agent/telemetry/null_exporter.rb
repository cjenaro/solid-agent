module SolidAgent
  module Telemetry
    class NullExporter < Exporter
      def export_trace(_trace)
        nil
      end
    end
  end
end
