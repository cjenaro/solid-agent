module SolidAgent
  module Orchestration
    class ParallelExecutor
      def self.execute(tool_calls, context:, concurrency:, error_strategies: {})
        return [] if tool_calls.empty?

        tool_calls.each_slice(concurrency).flat_map do |batch|
          execute_batch(batch, context, error_strategies)
        end
      end

      def self.execute_batch(batch, context, error_strategies)
        threads = batch.map do |tool_call|
          Thread.new(tool_call) do |tc|
            execute_tool_call(tc, error_strategies, context)
          end
        end

        results = []
        threads.each do |thread|
          results << thread.value
        rescue StandardError
          threads.each { |t| t.kill if t.alive? && t != thread }
          raise
        end
        results
      end

      def self.execute_tool_call(tc, error_strategies, context)
        if defined?(ActiveRecord::Base)
          ActiveRecord::Base.connection_pool.with_connection do
            run_tool(tc, error_strategies, context)
          end
        else
          run_tool(tc, error_strategies, context)
        end
      end

      def self.run_tool(tc, error_strategies, context)
        strategy = error_strategies[tc.name]
        if strategy
          strategy.execute_with_handling do
            tc.tool.execute(tc.arguments, context: context)
          end
        else
          tc.tool.execute(tc.arguments, context: context)
        end
      end

      private_class_method :execute_batch, :execute_tool_call, :run_tool
    end
  end
end
