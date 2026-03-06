require "net/http"
require "json"

module Memory
  class Extractor
    MODEL = Memory::LlmClient::MODEL

    EXTRACTION_PROMPT = <<~PROMPT.freeze
      You are a fact extraction assistant. Your job is to extract personal facts,
      preferences, hobbies, and dislikes about the user by analyzing their CURRENT
      message together with the recent conversation history.

      Rules:
      - Extract facts that the user states or clearly reveals about themselves.
      - USE the conversation history to understand context. If the user says
        "I love doing it every weekend" and the conversation was about basketball,
        extract "Loves playing basketball every weekend".
      - When the conversation history shows the user repeatedly engaging with or
        expressing interest in a topic (e.g., asking many questions about cooking,
        discussing a sport), and the user's current message confirms personal
        involvement or enjoyment, extract that as a preference or hobby.
      - Resolve ALL pronouns and references ("it", "that", "this", "them") using
        the conversation history to produce clear, standalone facts.
      - Do NOT extract facts about other people, topics, or general knowledge.
      - Do NOT extract questions the user is asking unless they reveal a personal fact
        (e.g., "Where can I play tennis near me?" reveals the user plays tennis).
      - Each fact should be a concise, self-contained statement (no pronouns).
      - Categorize each fact as one of: preference, hobby, personal_fact, dislike.
      - Do NOT fabricate facts. Only extract what is supported by the messages.

      Respond ONLY with valid JSON. If there are no personal facts, respond with: {"facts": []}

      Response format:
      {
        "facts": [
          {"fact": "Likes basketball", "category": "preference"},
          {"fact": "Works as a software engineer", "category": "personal_fact"},
          {"fact": "Enjoys hiking on weekends", "category": "hobby"},
          {"fact": "Dislikes cold weather", "category": "dislike"}
        ]
      }
    PROMPT

    FACTS_SCHEMA = { facts: [{ fact: :string, category: :string }] }.freeze
    FACTS_VALIDATOR = AiGuardrails::SchemaValidator.new(FACTS_SCHEMA)

    def self.extract(user_message, recent_history: [])
      return [] if user_message.blank?

      context_block = build_context(recent_history)

      messages = [
        { role: "system", content: EXTRACTION_PROMPT },
        { role: "user", content: "#{context_block}Now, considering the conversation context above, extract personal facts, preferences or hobbies revealed by the user in this latest message:\n\n\"#{user_message}\"" }
      ]

      response = Memory::LlmClient.call(messages)
      parse_facts(response)
    rescue StandardError => e
      Rails.logger.error("[Memory::Extractor] #{e.class} - #{e.message}")
      []
    end

    private

    def self.parse_facts(response_text)
      return [] if response_text.blank?

      repaired = AiGuardrails::JsonRepair.repair(response_text)
      symbolized = repaired.is_a?(Hash) ? repaired.deep_symbolize_keys : {}

      success, result = FACTS_VALIDATOR.validate(symbolized)
      unless success
        Rails.logger.warn("[Memory::Extractor] Schema validation failed: #{result}")
        return []
      end

      valid_categories = UserMemory::CATEGORIES

      Array(result[:facts]).filter_map do |entry|
        fact = entry[:fact].to_s.strip
        category = entry[:category].to_s.strip.downcase

        next if fact.empty?
        next unless valid_categories.include?(category)

        { fact: fact, category: category }
      end
    rescue AiGuardrails::JsonRepair::RepairError => e
      Rails.logger.error("[Memory::Extractor] JSON repair failed: #{e.message}")
      []
    end

    def self.build_context(history)
      return "" if history.blank?

      lines = history.last(10).map do |msg|
        role_label = msg.role == "user" ? "User" : "Assistant"
        "#{role_label}: #{msg.content.to_s.truncate(300)}"
      end

      "Recent conversation history (use this to understand the discussion topic, " \
        "resolve pronouns/references, and identify user preferences or hobbies " \
        "that emerge from the conversation — but only extract facts about the USER, " \
        "not about assistant responses):\n#{lines.join("\n")}\n\n"
    end
  end
end
