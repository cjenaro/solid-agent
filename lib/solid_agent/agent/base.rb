require 'solid_agent/agent/dsl'
require 'solid_agent/agent/result'
require 'solid_agent/run_job'

module SolidAgent
  class Base
    include Agent::DSL

    def self.perform_later(input, conversation_id: nil)
      conversation = if conversation_id
                       SolidAgent::Conversation.find(conversation_id)
                     else
                       SolidAgent::Conversation.create!(agent_class: name)
                     end

      trace_input = input.is_a?(Hash) ? input[:text] || input['text'] || input.to_json : input

      trace = SolidAgent::Trace.create!(
        conversation: conversation,
        agent_class: name,
        trace_type: :agent_run,
        status: 'pending',
        input: trace_input
      )

      RunJob.perform_later(
        trace_id: trace.id,
        agent_class_name: name,
        input: input,
        conversation_id: conversation.id
      )

      trace
    end

    def self.perform_now(input, conversation_id: nil, trace: nil, conversation: nil)
      conversation ||= if conversation_id
                         SolidAgent::Conversation.find(conversation_id)
                       else
                         SolidAgent::Conversation.create!(agent_class: name)
                       end

      trace_input = input.is_a?(Hash) ? input[:text] || input['text'] || input.to_json : input

      trace ||= SolidAgent::Trace.create!(
        conversation: conversation,
        agent_class: name,
        trace_type: :agent_run,
        status: 'pending',
        input: trace_input
      )

      RunJob.perform_now(
        trace_id: trace.id,
        agent_class_name: name,
        input: input,
        conversation_id: conversation.id
      )
    rescue StandardError => e
      trace&.update!(status: 'failed', error: e.message, completed_at: Time.current) if trace&.status != 'failed'
      Agent::Result.new(
        trace_id: trace&.id,
        conversation_id: trace&.conversation_id,
        output: nil,
        usage: Types::Usage.new(input_tokens: 0, output_tokens: 0),
        iterations: trace&.iteration_count || 0,
        status: :failed,
        error: e.message
      )
    end
  end
end
