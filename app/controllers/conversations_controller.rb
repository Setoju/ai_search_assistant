class ConversationsController < ApplicationController
  before_action :set_conversation, only: [ :show, :destroy ]

  def index
    @conversations = current_user.conversations.recent
    @conversation = nil
  end

  def show
    @conversations = current_user.conversations.recent
    @messages = @conversation.messages.chronological
  end

  def create
    @conversation = current_user.conversations.build

    if @conversation.save
      redirect_to conversation_path(@conversation)
    else
      redirect_to conversations_path, alert: "Failed to create conversation."
    end
  end

  def destroy
    @conversation.destroy
    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def set_conversation
    @conversation = current_user.conversations.find(params[:id])
  end
end
