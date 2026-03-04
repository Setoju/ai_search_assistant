module Tools
  class RecallMemories
    def self.schema
      {
        name: "recall_memories",
        description: "Search the user's stored personal memories, preferences, hobbies, and facts. " \
                     "Use this tool when you need to recall something the user has previously told you about themselves, " \
                     "their preferences, hobbies, or personal details.",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "A search query describing what you want to recall about the user. " \
                           "For example: 'favorite sport', 'job', 'food preferences', 'hobbies'."
            }
          },
          required: ["query"]
        }
      }
    end

    def self.call(args)
      query = args[:query].to_s.strip
      raise ArgumentError, "Query is required." if query.empty?

      user_id = args[:user_id]
      raise ArgumentError, "User context is required." unless user_id

      user = User.find_by(id: user_id)
      return { results: [], message: "No user found." } unless user

      memories = MemoryManager.recall(user: user, query: query, limit: 5)

      if memories.empty?
        { results: [], message: "No memories found matching '#{query}'." }
      else
        {
          results: memories.map { |m|
            {
              fact: m.fact,
              category: m.category,
              recorded_at: m.source_message_at&.iso8601
            }
          },
          message: "Found #{memories.length} relevant memories."
        }
      end
    rescue StandardError => e
      Rails.logger.error("[RecallMemories] #{e.class} - #{e.message}")
      { results: [], message: "Error recalling memories." }
    end
  end
end
