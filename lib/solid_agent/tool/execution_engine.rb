require 'timeout'

module SolidAgent
  module Tool
    class ExecutionEngine
      class ToolExecutionError
        attr_reader :message

        def initialize(message)
          @message = message
        end

        def to_s
          @message
        end
      end

      class ApprovalRequired
        attr_reader :tool_name, :tool_call_id, :arguments

        def initialize(tool_name:, tool_call_id:, arguments:)
          @tool_name = tool_name
          @tool_call_id = tool_call_id
          @arguments = arguments
        end

        def to_s
          "Approval required for tool: #{@tool_name}"
        end
      end

      def initialize(registry:, concurrency: 1, timeout: 30, approval_required: [])
        @registry = registry
        @concurrency = concurrency
        @timeout = timeout
        @approval_required = approval_required.map(&:to_s)
        @approved = Set.new
      end

      def approve(tool_call_id)
        @approved.add(tool_call_id)
      end

      def reject(tool_call_id, reason = 'Rejected')
        @rejected ||= {}
        @rejected[tool_call_id] = reason
      end

      def execute_all(tool_calls)
        results = {}

        tool_calls.each_slice(@concurrency) do |batch|
          threads = batch.map do |tc|
            Thread.new(tc) do |tool_call|
              results[tool_call.id] = execute_one(tool_call)
            end
          end
          threads.each(&:join)
        end

        results
      end

      private

      def execute_one(tool_call)
        return ToolExecutionError.new(@rejected[tool_call.id]) if @rejected&.key?(tool_call.id)

        if @approval_required.include?(tool_call.name) && !@approved.include?(tool_call.id)
          return ApprovalRequired.new(
            tool_name: tool_call.name,
            tool_call_id: tool_call.id,
            arguments: tool_call.arguments
          )
        end

        tool = @registry.lookup(tool_call.name)
        Timeout.timeout(@timeout) do
          tool.execute(tool_call.arguments)
        end
      rescue Timeout::Error
        ToolExecutionError.new("Tool '#{tool_call.name}' timed out after #{@timeout}s")
      rescue StandardError => e
        ToolExecutionError.new("Tool '#{tool_call.name}' error: #{e.message}")
      end
    end
  end
end
