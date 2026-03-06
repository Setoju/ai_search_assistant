require "net/http"
require "json"

module Memory
  class ConflictResolver
    OLLAMA_BASE_URL = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
    MODEL = ENV.fetch("OLLAMA_MODEL", "llama3.2")
    SIMILARITY_THRESHOLD = 0.5

    # Categories that can conflict with each other (opposite sentiments about same topic)
    CONFLICTING_CATEGORIES = {
      "preference" => %w[preference dislike hobby],
      "dislike" => %w[preference dislike hobby],
      "hobby" => %w[preference dislike hobby],
      "personal_fact" => %w[personal_fact]
    }.freeze

    RESOLUTION_PROMPT = <<~PROMPT.freeze
      You are a fact conflict resolver. Given an existing fact and a new fact about a user,
      determine if they conflict and which one should be kept.

      Rules:
      - Facts conflict if they are about the SAME topic but express DIFFERENT or OPPOSITE sentiments.
      - Example conflict: "Likes basketball" vs "Hates basketball" — same topic, opposite sentiment
      - Example conflict: "Enjoys playing football on weekends" vs "Hates playing football" — same topic, opposite sentiment
      - Example conflict: "Works as a teacher" vs "Works as an engineer" — same topic, different value
      - Example NOT conflict: "Likes basketball" vs "Likes soccer" — different topics, both can be true
      - Example NOT conflict: "Has a dog" vs "Has a cat" — both can be true
      - Facts in DIFFERENT categories CAN still conflict (e.g. preference "likes X" vs dislike "hates X")
      - When facts DO conflict, the NEWER fact (later timestamp) should be kept, as it reflects the user's current state.

      Respond ONLY with valid JSON in this format:
      {"conflicts": true/false, "keep": "new" or "existing", "reason": "brief explanation"}
    PROMPT

    RESOLUTION_SCHEMA = { conflicts: :boolean, keep: :string, reason: :string }.freeze
    RESOLUTION_VALIDATOR = AiGuardrails::SchemaValidator.new(RESOLUTION_SCHEMA)

    # Check a new fact against existing memories and resolve conflicts.
    # Returns :store if the new fact should be stored,
    #         :skip if it's a duplicate,
    #         or the ID of the memory to replace if there's a conflict.
    def self.resolve(user, new_fact_text, new_fact_category)
      # Generate embedding for the new fact
      new_embedding = EmbeddingService.generate(new_fact_text)
      if new_embedding.blank?
        Rails.logger.warn("[Memory::ConflictResolver] Skipping fact (embedding generation failed): #{new_fact_text}")
        return { action: :skip, reason: "Embedding generation failed" }
      end

      # Find similar existing memories across ALL potentially conflicting categories
      related_categories = CONFLICTING_CATEGORIES.fetch(new_fact_category, [new_fact_category])
      existing_memories = user.user_memories.where(category: related_categories).to_a
      return { action: :store, embedding: new_embedding } if existing_memories.empty?

      similar_memories = existing_memories.filter_map do |memory|
        similarity = memory.cosine_similarity(new_embedding)
        { memory: memory, similarity: similarity } if similarity >= SIMILARITY_THRESHOLD
      end

      return { action: :store, embedding: new_embedding } if similar_memories.empty?

      # Check each similar memory for conflicts
      similar_memories.sort_by { |m| -m[:similarity] }.each do |entry|
        existing_memory = entry[:memory]

        # Use AI to determine if they conflict (even for very high similarity,
        # because opposite sentiments about the same topic — e.g. "likes drawing"
        # vs "hates drawing" — produce near-identical embeddings).
        resolution = check_conflict(existing_memory.fact, new_fact_text,
                                    existing_memory.source_message_at, Time.current)

        if resolution[:conflicts]
          if resolution[:keep] == "new"
            return { action: :replace, memory_id: existing_memory.id, embedding: new_embedding }
          else
            return { action: :skip, reason: resolution[:reason] }
          end
        end

        # If AI says no conflict and similarity is near-identical, skip as duplicate
        if entry[:similarity] >= 0.95
          return { action: :skip, reason: "Duplicate of existing memory" }
        end
      end

      { action: :store, embedding: new_embedding }
    rescue StandardError => e
      Rails.logger.error("[Memory::ConflictResolver] #{e.class} - #{e.message}")
      # On error, default to storing the new fact
      { action: :store, embedding: new_embedding.presence || [] }
    end

    private

    def self.check_conflict(existing_fact, new_fact, existing_timestamp, new_timestamp)
      messages = [
        { role: "system", content: RESOLUTION_PROMPT },
        { role: "user", content: build_conflict_prompt(existing_fact, new_fact,
                                                         existing_timestamp, new_timestamp) }
      ]

      response = call_llm(messages)
      parse_resolution(response)
    rescue StandardError => e
      Rails.logger.error("[Memory::ConflictResolver] Conflict check failed: #{e.message}")
      { conflicts: false }
    end

    def self.build_conflict_prompt(existing_fact, new_fact, existing_timestamp, new_timestamp)
      <<~MSG
        Existing fact (recorded at #{existing_timestamp}): "#{existing_fact}"
        New fact (recorded at #{new_timestamp}): "#{new_fact}"

        Do these facts conflict? If so, which should be kept?
      MSG
    end

    def self.call_llm(messages)
      uri = URI("#{OLLAMA_BASE_URL}/api/chat")

      body = {
        model: MODEL,
        messages: messages,
        stream: false,
        format: "json",
        options: { temperature: 0.1 }
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10
      http.read_timeout = 60

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = body.to_json

      response = http.request(request)
      raise "Ollama error: #{response.code}" unless response.code.to_i == 200

      parsed = JSON.parse(response.body)
      parsed.dig("message", "content") || ""
    end

    def self.parse_resolution(response_text)
      return { conflicts: false } if response_text.blank?

      repaired = AiGuardrails::JsonRepair.repair(response_text)
      symbolized = repaired.is_a?(Hash) ? repaired.symbolize_keys : {}

      success, result = RESOLUTION_VALIDATOR.validate(symbolized)
      unless success
        Rails.logger.warn("[Memory::ConflictResolver] Schema validation failed: #{result}")
        return { conflicts: false }
      end

      {
        conflicts: result[:conflicts] == true,
        keep: result[:keep].to_s.downcase,
        reason: result[:reason].to_s
      }
    rescue AiGuardrails::JsonRepair::RepairError
      { conflicts: false }
    end
  end
end
