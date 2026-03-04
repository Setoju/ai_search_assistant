class MessagesController < ApplicationController
  RATE_LIMITER = RateLimiter.new

  def create
    @conversation = current_user.conversations.find(params[:conversation_id])

    begin
      RATE_LIMITER.check!(request.remote_ip)
    rescue RateLimiter::RateLimitExceeded => e
      @conversation.messages.create!(role: "user", content: message_params[:content])
      @conversation.messages.create!(role: "assistant", content: "Rate limit exceeded: #{e.message}")
      redirect_to conversation_path(@conversation)
      return
    end

    user_content = message_params[:content]
    return redirect_to conversation_path(@conversation), alert: "Message can't be blank." if user_content.blank?

    # Capture history BEFORE saving the new user message so it isn't
    # included in the context and duplicated in the AI prompt.
    history = @conversation.memory_messages(10)

    @conversation.messages.create!(role: "user", content: user_content)

    # Auto-generate title from first user message
    if @conversation.messages.where(role: "user").count == 1
      @conversation.update(title: user_content.truncate(60))
    end

    # Extract and store long-term memories in the background so the request
    # is not blocked by multiple LLM calls (extraction + conflict resolution).
    last_message = @conversation.messages.where(role: "user").order(created_at: :desc).first
    MemoryExtractionJob.perform_later(
      user_id: current_user.id,
      message_content: user_content,
      message_id: last_message&.id,
      message_at: last_message&.created_at || Time.current,
      recent_history_ids: history.map(&:id)
    )

    orchestrator = Orchestrator.new(user: current_user)
    result = orchestrator.process_with_memory(user_content, history)

    if result[:success]
      @conversation.messages.create!(role: "assistant", content: result[:response])
    else
      @conversation.messages.create!(role: "assistant", content: "Sorry, something went wrong: #{result[:error]}")
    end

    redirect_to conversation_path(@conversation)
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end
