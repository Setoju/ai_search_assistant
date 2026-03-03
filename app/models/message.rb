class Message < ApplicationRecord
  belongs_to :conversation, touch: true

  validates :content, presence: true
  validates :role, presence: true, inclusion: { in: %w[user assistant] }

  scope :recent, ->(n = 10) { order(created_at: :desc).limit(n) }
  scope :chronological, -> { order(created_at: :asc) }
end
