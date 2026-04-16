module SolidAgent
  module Telemetry
    class Serializer
      OTLLM_SPAN_TYPES = %w[llm llm_call think].freeze
      OTTOOL_SPAN_TYPES = %w[tool tool_execution act].freeze

      def self.span_attributes(span, provider: nil, model: nil, tool_name: nil,
                               tool_call_id: nil, tool_type: nil, finish_reasons: nil)
        attrs = (span.metadata || {}).dup

        if OTLLM_SPAN_TYPES.include?(span.span_type)
          attrs['gen_ai.operation.name'] = 'chat'
          attrs['gen_ai.provider.name'] = provider.to_s if provider
          attrs['gen_ai.request.model'] = model.to_s if model
          attrs['gen_ai.usage.input_tokens'] = span.tokens_in if span.tokens_in > 0
          attrs['gen_ai.usage.output_tokens'] = span.tokens_out if span.tokens_out > 0
          attrs['gen_ai.response.finish_reasons'] = Array(finish_reasons) if finish_reasons
          attrs['otel.span.name'] = "chat #{model || 'unknown'}"
        elsif OTTOOL_SPAN_TYPES.include?(span.span_type)
          attrs['gen_ai.operation.name'] = 'execute_tool'
          attrs['gen_ai.tool.name'] = (tool_name || span.name).to_s
          attrs['gen_ai.tool.call.id'] = tool_call_id.to_s if tool_call_id
          attrs['gen_ai.tool.type'] = tool_type.to_s if tool_type
          attrs['otel.span.name'] = "execute_tool #{tool_name || span.name}"
        else
          attrs['gen_ai.operation.name'] = span.span_type
          attrs['otel.span.name'] = span.name.to_s
        end

        attrs
      end

      def self.trace_resource_attributes(trace)
        {
          'service.name' => 'solid_agent',
          'service.version' => '0.1.0',
          'solid_agent.agent_class' => trace.agent_class.to_s,
          'solid_agent.trace_type' => trace.trace_type.to_s
        }
      end
    end
  end
end
