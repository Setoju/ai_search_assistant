class Conversation < ApplicationRecord
  belongs_to :user
  has_many :messages, dependent: :destroy

  validates :title, length: { maximum: 255 }

  before_validation :set_default_title, on: :create

  scope :recent, -> { order(updated_at: :desc) }

  def short_title
    title.present? ? title.truncate(40) : "New Conversation"
  end

  def memory_messages(limit = 10)
    messages.order(created_at: :desc).limit(limit).reverse
  end

  private

  def set_default_title
    self.title = "New Conversation" if title.blank?
  end
end
