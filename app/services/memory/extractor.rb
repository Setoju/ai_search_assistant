require "net/http"
require "json"

module Memory
  class Extractor
    OLLAMA_BASE_URL = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
    MODEL = ENV.fetch("OLLAMA_MODEL", "llama3.2")

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

    # Extract user facts from a message. Returns an array of hashes with :fact and :category.
    # Accepts optional recent_history (array of Message-like objects) so pronouns
    # and references ("it", "that", etc.) can be resolved against conversation context.
    def self.extract(user_message, recent_history: [])
      return [] if user_message.blank?

      context_block = build_context(recent_history)

      messages = [
        { role: "system", content: EXTRACTION_PROMPT },
        { role: "user", content: "#{context_block}Now, considering the conversation context above, extract personal facts, preferences or hobbies revealed by the user in this latest message:\n\n\"#{user_message}\"" }
      ]

      response = call_llm(messages)
      parse_facts(response)
    rescue StandardError => e
      Rails.logger.error("[Memory::Extractor] #{e.class} - #{e.message}")
      []
    end

    private

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

    def self.parse_facts(response_text)
      return [] if response_text.blank?

      parsed = JSON.parse(response_text)
      facts = parsed["facts"]

      return [] unless facts.is_a?(Array)

      valid_categories = UserMemory::CATEGORIES

      facts.filter_map do |entry|
        fact = entry["fact"].to_s.strip
        category = entry["category"].to_s.strip.downcase

        next if fact.empty?
        next unless valid_categories.include?(category)

        { fact: fact, category: category }
      end
    rescue JSON::ParserError => e
      Rails.logger.error("[Memory::Extractor] JSON parse error: #{e.message}")
      []
    end

    # Build a context summary from recent conversation history so the extractor
    # can understand topics being discussed, resolve pronouns, and identify
    # preferences/hobbies that emerge across multiple messages.
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
