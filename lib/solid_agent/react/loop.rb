require 'solid_agent/react/observer'
require 'solid_agent/agent/result'

module SolidAgent
  SpanData = Struct.new(:span_type, :name, :metadata, :tokens_in, :tokens_out, keyword_init: true) do
    def initialize(*)
      super
      self.metadata ||= {}
      self.tokens_in ||= 0
      self.tokens_out ||= 0
    end
  end

  module React
    class Loop
      def initialize(trace:, provider:, memory:, execution_engine:, model:, system_prompt:, max_iterations:,
                     max_tokens_per_run:, timeout:, http_adapter: nil, provider_name: nil,
                     temperature: nil, tool_choice: nil, on_chunk: nil, on_context_overflow: nil)
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
        @provider_name = provider_name
        @temperature = temperature
        @tool_choice = tool_choice
        @on_chunk = on_chunk
        @on_context_overflow = on_context_overflow
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
            @on_context_overflow&.call(all_messages)
            all_messages = @memory.compact!(all_messages)
            @trace.spans.create!(span_type: 'chunk', name: 'compaction', status: 'completed',
                                 started_at: Time.current, completed_at: Time.current,
                                 metadata: Telemetry::Serializer.span_attributes(SpanData.new(span_type: 'chunk', name: 'compaction')))
          end

          context = @memory.build_context(all_messages, system_prompt: @system_prompt)

          llm_span = @trace.spans.create!(
            span_type: 'llm', name: "step_#{@trace.iteration_count - 1}",
            status: 'running', started_at: Time.current,
            metadata: Telemetry::Serializer.span_attributes(SpanData.new(span_type: 'llm', name: "step_#{@trace.iteration_count - 1}"),
                                                            provider: @provider_name, model: @model)
          )
          broadcast_span(llm_span)

          request = @provider.build_request(
            messages: context,
            tools: @execution_engine.registry.all_schemas_hashes,
            stream: false,
            model: @model,
            max_tokens: @model.max_output,
            temperature: @temperature,
            tool_choice: @tool_choice
          )

          http_response = @http_adapter.call(request)
          response = @provider.parse_response(http_response)

          llm_span.update!(
            status: 'completed',
            completed_at: Time.current,
            tokens_in: response.usage&.input_tokens || 0,
            tokens_out: response.usage&.output_tokens || 0
          )
          broadcast_span(llm_span)

          if response.usage
            @accumulated_usage += response.usage
            @trace.update!(usage: {
                             'input_tokens' => @accumulated_usage.input_tokens,
                             'output_tokens' => @accumulated_usage.output_tokens
                           })
          end

          assistant_msg = response.messages.first
          all_messages << assistant_msg if assistant_msg

          unless response.has_tool_calls?
            if assistant_msg&.content.present?
              @trace.spans.create!(
                span_type: 'chunk', name: 'text',
                status: 'completed', started_at: Time.current, completed_at: Time.current,
                parent_span: llm_span,
                output: assistant_msg.content,
                metadata: Telemetry::Serializer.span_attributes(SpanData.new(span_type: 'chunk', name: 'text'))
              )
              @on_chunk&.call(assistant_msg.content)
            end
            return build_result(status: :completed, output: assistant_msg&.content || '')
          end

          response.tool_calls.each do |tc|
            @trace.spans.create!(
              span_type: 'chunk', name: "tool-call:#{tc.name}",
              status: 'completed', started_at: Time.current, completed_at: Time.current,
              parent_span: llm_span,
              output: { id: tc.id, name: tc.name, arguments: tc.arguments }.to_json,
              metadata: Telemetry::Serializer.span_attributes(SpanData.new(span_type: 'chunk', name: "tool-call:#{tc.name}"),
                                                              tool_name: tc.name, tool_call_id: tc.id)
            )
          end

          tool_results = @execution_engine.execute_all(response.tool_calls)

          tool_results.each do |call_id, result|
            result_text = result.is_a?(Tool::ExecutionEngine::ToolExecutionError) ? "Error: #{result.message}" : result.to_s
            @on_chunk&.call(result_text)
            tool_call = response.tool_calls.find { |tc| tc.id == call_id }

            @trace.spans.create!(
              span_type: 'tool', name: tool_call&.name || 'tool',
              status: result.is_a?(Tool::ExecutionEngine::ToolExecutionError) ? 'error' : 'completed',
              started_at: Time.current, completed_at: Time.current,
              parent_span: llm_span,
              output: result_text,
              metadata: Telemetry::Serializer.span_attributes(SpanData.new(span_type: 'tool', name: tool_call&.name || 'tool'),
                                                              tool_name: tool_call&.name, tool_call_id: call_id,
                                                              tool_type: 'function')
            )

            @trace.spans.create!(
              span_type: 'chunk', name: "tool-result:#{call_id}",
              status: 'completed', started_at: Time.current, completed_at: Time.current,
              parent_span: llm_span,
              output: result_text,
              metadata: Telemetry::Serializer.span_attributes(SpanData.new(span_type: 'chunk', name: "tool-result:#{call_id}"),
                                                              tool_name: tool_call&.name, tool_call_id: call_id)
            )

            all_messages << Types::Message.new(role: 'tool', content: result_text, tool_call_id: call_id)
          end
        end
      rescue StandardError => e
        build_result(status: :failed, output: nil, error: e.message)
      end

      private

      def broadcast_span(span)
        SolidAgent::TraceChannel.broadcast_span_update(span) if defined?(SolidAgent::TraceChannel)
      rescue StandardError
        nil
      end

      def broadcast_trace_update(trace)
        SolidAgent::TraceChannel.broadcast_trace_update(trace) if defined?(SolidAgent::TraceChannel)
      rescue StandardError
        nil
      end

      def resolve_http_adapter
        SolidAgent::HTTP::Adapters.resolve(SolidAgent.configuration.http_adapter)
      end

      def build_result(status:, output:, error: nil, reason: nil)
        begin
          @trace.update!(
            status: status == :completed ? 'completed' : 'failed',
            completed_at: Time.current,
            output: output,
            error: error
          )
          broadcast_trace_update(@trace)
        rescue => e
          # Log the update failure but continue - this prevents trace status
          # updates from blocking the error handling flow (e.g., SQLite locking)
          Rails.logger.error("[SolidAgent] Failed to update trace status: #{e.message}")
        end

        SolidAgent.configuration.telemetry_exporters.each do |exporter|
          exporter.export_trace(@trace)
        end

        Agent::Result.new(
          trace_id: @trace.id,
          conversation_id: @trace.conversation_id,
          output: output,
          usage: @accumulated_usage,
          iterations: status == :failed ? 0 : @trace.iteration_count,
          status: status,
          error: error
        )
      end

      def extract_final_text(messages)
        messages.reverse_each do |msg|
          return msg.content if msg.role == 'assistant' && msg.content && !msg.content.empty?
        end
        tool_result = messages.reverse_each.find { |msg| msg.role == 'tool' && msg.content }
        tool_result&.content || ''
      end
    end
  end
end
