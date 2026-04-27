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

      attr_reader :registry, :concurrency

      def initialize(registry:, concurrency: 1, timeout: 30, approval_required: [], context: {})
        @registry = registry
        @concurrency = concurrency
        @timeout = timeout
        @approval_required = approval_required.map(&:to_s)
        @approved = Set.new
        @context = context
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
              if defined?(ActiveRecord::Base)
                ActiveRecord::Base.connection_pool.with_connection do
                  results[tool_call.id] = execute_one(tool_call)
                end
              else
                results[tool_call.id] = execute_one(tool_call)
              end
            end
          end
          threads.each do |thread|
            thread.value
          rescue StandardError
            # Thread errors are captured in results; raise only if thread itself fails outside
            raise
          end
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

        # Determine effective timeout:
        # 1. Subagent tools (DelegateTool/AgentTool) manage their own timeout
        #    via the child agent's React loop — don't cut them short.
        # 2. Per-tool timeout declared via `timeout N` on Tool::Base subclasses.
        # 3. Default engine timeout (30s).
        effective_timeout = if tool.respond_to?(:agent_class)
                              0 # disable Timeout.timeout for subagent tools
                            elsif (per_tool = @registry.lookup_timeout(tool_call.name))
                              per_tool
                            else
                              @timeout
                            end

        Timeout.timeout(effective_timeout) do
          # DelegateTool/AgentTool accept context:, regular tools just take arguments
          if tool.respond_to?(:delegate?) || tool.method(:execute).arity.abs == 2
            tool.execute(tool_call.arguments, context: @context)
          else
            tool.execute(tool_call.arguments)
          end
        end
      rescue Timeout::Error
        ToolExecutionError.new("Tool '#{tool_call.name}' timed out after #{@timeout}s")
      rescue StandardError => e
        ToolExecutionError.new("Tool '#{tool_call.name}' error: #{e.message}")
      end
    end
  end
end
