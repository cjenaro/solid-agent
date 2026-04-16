module SolidAgent
  module Agent
    class Result
      attr_reader :trace_id, :conversation_id, :output, :usage, :iterations, :status, :error

      def initialize(trace_id:, output:, usage:, iterations:, conversation_id: nil, status: :completed, error: nil)
        @trace_id = trace_id
        @conversation_id = conversation_id
        @output = output
        @usage = usage
        @iterations = iterations
        @status = status
        @error = error
      end

      def completed?
        @status == :completed
      end

      def failed?
        @status == :failed
      end
    end
  end
end
