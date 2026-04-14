require 'solid_agent/react/observer'
require 'solid_agent/agent/result'

module SolidAgent
  module React
    class Loop
      def initialize(trace:, provider:, memory:, execution_engine:, model:, system_prompt:, max_iterations:,
                     max_tokens_per_run:, timeout:, http_adapter: nil)
        @trace = trace
        @provider = provider
        @memory = memory
        @execution_engine = execution_engine
        @model = model
        @system_prompt = system_prompt
        @max_iterations = max_iterations
        @max_tokens_per_run = max_tokens_per_run
        @timeout = timeout
        @http_adapter = http_adapter || resolve_http_adapter
        @started_at = Time.current
        @accumulated_usage = Types::Usage.new(input_tokens: 0, output_tokens: 0)
      end

      def run(messages)
        all_messages = messages.dup

        loop do
          @trace.increment!(:iteration_count)

          observer = Observer.new(
            trace: @trace,
            max_iterations: @max_iterations,
            max_tokens_per_run: @max_tokens_per_run,
            started_at: @started_at,
            timeout: @timeout
          )

          stop, reason = observer.should_stop?(
            current_tokens: @accumulated_usage.total_tokens,
            context_window: @model.context_window
          )

          return build_result(status: :completed, output: extract_final_text(all_messages), reason: reason) if stop

          if observer.should_compact?(current_tokens: @accumulated_usage.total_tokens,
                                      context_window: @model.context_window)
            all_messages = @memory.compact!(all_messages)
            @trace.spans.create!(span_type: 'observe', name: 'compact', status: 'completed', started_at: Time.current,
                                 completed_at: Time.current)
          end

          context = @memory.build_context(all_messages, system_prompt: @system_prompt)

          think_span = @trace.spans.create!(
            span_type: 'think', name: "think_#{@trace.iteration_count}",
            status: 'running', started_at: Time.current
          )

          request = @provider.build_request(
            messages: context,
            tools: @execution_engine.registry.all_schemas_hashes,
            stream: false,
            model: @model,
            max_tokens: @model.max_output
          )

          http_response = @http_adapter.call(request)
          response = @provider.parse_response(http_response)

          think_span.update!(
            status: 'completed',
            completed_at: Time.current,
            tokens_in: response.usage&.input_tokens || 0,
            tokens_out: response.usage&.output_tokens || 0,
            output: response.has_tool_calls? ? "tool_calls: #{response.tool_calls.map(&:name)}" : response.messages.first&.content&.truncate(200)
          )

          if response.usage
            @accumulated_usage += response.usage
            @trace.update!(usage: {
                             'input_tokens' => @accumulated_usage.input_tokens,
                             'output_tokens' => @accumulated_usage.output_tokens
                           })
          end

          assistant_msg = response.messages.first
          all_messages << assistant_msg if assistant_msg

          return build_result(status: :completed, output: assistant_msg&.content || '') unless response.has_tool_calls?

          act_span = @trace.spans.create!(
            span_type: 'act', name: "act_#{@trace.iteration_count}",
            status: 'running', started_at: Time.current
          )

          tool_results = @execution_engine.execute_all(response.tool_calls)
          tool_results.each do |call_id, result|
            result_text = result.is_a?(Tool::ExecutionEngine::ToolExecutionError) ? "Error: #{result.message}" : result.to_s
            all_messages << Types::Message.new(role: 'tool', content: result_text, tool_call_id: call_id)
          end

          act_span.update!(status: 'completed', completed_at: Time.current)
        end
      rescue StandardError => e
        build_result(status: :failed, output: nil, error: e.message)
      end

      private

      def resolve_http_adapter
        SolidAgent::HTTP::Adapters.resolve(SolidAgent.configuration.http_adapter)
      end

      def build_result(status:, output:, error: nil, reason: nil)
        @trace.update!(
          status: status == :completed ? 'completed' : 'failed',
          completed_at: Time.current,
          output: output,
          error: error
        )

        Agent::Result.new(
          trace_id: @trace.id,
          output: output,
          usage: @accumulated_usage,
          iterations: @trace.iteration_count,
          status: status,
          error: error
        )
      end

      def extract_final_text(messages)
        messages.reverse_each do |msg|
          return msg.content if msg.role == 'assistant' && msg.content && !msg.content.empty?
        end
        ''
      end
    end
  end
end
