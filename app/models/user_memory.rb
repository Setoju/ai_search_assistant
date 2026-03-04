class UserMemory < ApplicationRecord
  belongs_to :user

  CATEGORIES = %w[preference hobby personal_fact dislike].freeze

  validates :fact, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :embedding, presence: true

  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :by_category, ->(category) { where(category: category) }
  scope :recent_first, -> { order(source_message_at: :desc) }

  # Compute cosine similarity between this memory's embedding and a query embedding.
  def cosine_similarity(query_embedding)
    return 0.0 if embedding.blank? || query_embedding.blank?
    return 0.0 if embedding.length != query_embedding.length

    dot = embedding.zip(query_embedding).sum { |a, b| a * b }
    mag_a = Math.sqrt(embedding.sum { |v| v**2 })
    mag_b = Math.sqrt(query_embedding.sum { |v| v**2 })

    return 0.0 if mag_a.zero? || mag_b.zero?

    dot / (mag_a * mag_b)
  end

  # Find the most relevant memories for a given query embedding.
  def self.relevant_for(user_id, query_embedding, limit: 5, threshold: 0.3)
    memories = for_user(user_id).to_a
    return [] if memories.empty? || query_embedding.blank?

    scored = memories.map do |memory|
      { memory: memory, score: memory.cosine_similarity(query_embedding) }
    end

    scored
      .select { |entry| entry[:score] >= threshold }
      .sort_by { |entry| -entry[:score] }
      .first(limit)
      .map { |entry| entry[:memory] }
  end
end
