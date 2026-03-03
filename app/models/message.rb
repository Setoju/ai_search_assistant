class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :sender, class_name: 'User'

  validates :content, presence: true
  validates :role, presence: true, inclusion: { in: %w[user assistant system tool] }
end
