module SolidAgent
  class ConversationsController < ApplicationController
    def index
      @conversations = Conversation.order(updated_at: :desc).limit(50)
    end

    def show
      @conversation = Conversation.includes(:traces, :messages).find(params[:id])
    end
  end
end
