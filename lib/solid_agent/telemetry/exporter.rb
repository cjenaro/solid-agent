module SolidAgent
  module Telemetry
    class Exporter
      def export_trace(trace)
        raise NotImplementedError
      end

      def flush; end

      def shutdown; end
    end
  end
end
