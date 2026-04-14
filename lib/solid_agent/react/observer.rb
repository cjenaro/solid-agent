module SolidAgent
  module React
    class Observer
      CONTEXT_THRESHOLD = 0.85

      def initialize(trace:, max_iterations:, max_tokens_per_run:, started_at:, timeout:)
        @trace = trace
        @max_iterations = max_iterations
        @max_tokens_per_run = max_tokens_per_run
        @started_at = started_at
        @timeout = timeout
      end

      def max_iterations_exceeded?
        @trace.iteration_count >= @max_iterations
      end

      def token_budget_exceeded?
        total = (@trace.usage['input_tokens'] || 0) + (@trace.usage['output_tokens'] || 0)
        total >= @max_tokens_per_run
      end

      def timeout_exceeded?
        Time.current - @started_at > @timeout
      end

      def context_near_limit?(current_tokens:, context_window:)
        return false unless context_window && context_window > 0

        ratio = current_tokens.to_f / context_window
        ratio >= CONTEXT_THRESHOLD
      end

      def should_stop?(current_tokens:, context_window:)
        return [true, :max_iterations] if max_iterations_exceeded?

        return [true, :token_budget] if token_budget_exceeded?

        return [true, :timeout] if timeout_exceeded?

        [false, nil]
      end

      def should_compact?(current_tokens:, context_window:)
        context_near_limit?(current_tokens: current_tokens, context_window: context_window)
      end
    end
  end
end
