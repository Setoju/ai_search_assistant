class MemoryExtractionJob < ApplicationJob
  queue_as :default

  # Runs memory extraction + conflict resolution in the background so the
  # HTTP request is not blocked by multiple LLM calls.
  def perform(user_id:, message_content:, message_id: nil, message_at: nil, recent_history_ids: [])
    user = User.find_by(id: user_id)
    return unless user

    # Reconstruct recent history from message IDs
    recent_history = if recent_history_ids.present?
      Message.where(id: recent_history_ids).order(:created_at)
    else
      []
    end

    Memory::Manager.process_message(
      user: user,
      message_content: message_content,
      message_id: message_id,
      message_at: message_at || Time.current,
      recent_history: recent_history
    )
  rescue StandardError => e
    Rails.logger.error("[MemoryExtractionJob] #{e.class} - #{e.message}")
  end
end
