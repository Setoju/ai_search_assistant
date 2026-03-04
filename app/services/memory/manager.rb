module Memory
  class Manager
    # Process a user message: extract facts, resolve conflicts, and store memories.
    # Accepts optional recent_history for pronoun/context resolution.
    def self.process_message(user:, message_content:, message_id: nil, message_at: nil, recent_history: [])
      message_at ||= Time.current

      facts = Memory::Extractor.extract(message_content, recent_history: recent_history)
      Rails.logger.info("[Memory::Manager] Extracted #{facts.length} facts from message: #{facts.map { |f| f[:fact] }.inspect}")
      return [] if facts.empty?

      stored_memories = []

      facts.each do |fact_data|
        resolution = Memory::ConflictResolver.resolve(user, fact_data[:fact], fact_data[:category])

        case resolution[:action]
        when :store
          if resolution[:embedding].blank?
            Rails.logger.warn("[Memory::Manager] Cannot store '#{fact_data[:fact]}' — no embedding")
            next
          end
          memory = user.user_memories.create!(
            fact: fact_data[:fact],
            category: fact_data[:category],
            embedding: resolution[:embedding],
            source_message_id: message_id,
            source_message_at: message_at
          )
          stored_memories << memory
          Rails.logger.info("[Memory::Manager] Stored new memory: #{fact_data[:fact]} (#{fact_data[:category]})")

        when :replace
          old_memory = user.user_memories.find_by(id: resolution[:memory_id])
          if old_memory
            Rails.logger.info("[Memory::Manager] Replacing memory: '#{old_memory.fact}' -> '#{fact_data[:fact]}'")
            old_memory.update!(
              fact: fact_data[:fact],
              category: fact_data[:category],
              embedding: resolution[:embedding],
              source_message_id: message_id,
              source_message_at: message_at
            )
            stored_memories << old_memory
          end

        when :skip
          Rails.logger.info("[Memory::Manager] Skipped memory: #{fact_data[:fact]} (#{resolution[:reason]})")
        end
      end

      stored_memories
    rescue StandardError => e
      Rails.logger.error("[Memory::Manager] #{e.class} - #{e.message}")
      []
    end

    # Retrieve relevant memories for a query.
    def self.recall(user:, query:, limit: 5)
      query_embedding = EmbeddingService.generate(query)
      return [] if query_embedding.blank?

      UserMemory.relevant_for(user.id, query_embedding, limit: limit)
    end

    # Get all memories for a user, formatted as context.
    def self.context_for(user:, query:, limit: 5)
      memories = recall(user: user, query: query, limit: limit)
      return nil if memories.empty?

      memory_lines = memories.map do |m|
        "- [#{m.category}] #{m.fact}"
      end

      "Known facts about the user:\n#{memory_lines.join("\n")}"
    end
  end
end
