module SolidAgent
  class ConversationsController < ApplicationController
    def index
      conversations = Conversation.order(updated_at: :desc).limit(50)

      render inertia: 'solid_agent/Conversations/Index', props: {
        conversations: conversations.as_json(
          only: %i[id agent_class status created_at updated_at],
          include: { traces: { only: %i[id status] } }
        )
      }
    end

    def show
      conversation = Conversation.includes(:traces, :messages).find(params[:id])

      render inertia: 'solid_agent/Conversations/Show', props: {
        conversation: conversation.as_json(
          only: %i[id agent_class status metadata created_at updated_at],
          include: {
            traces: { only: %i[id agent_class status started_at completed_at usage], methods: [:duration] },
            messages: { only: %i[id role content tool_call_id token_count model created_at] }
          }
        )
      }
    end
  end
end
