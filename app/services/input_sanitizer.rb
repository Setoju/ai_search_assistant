class InputSanitizer
  MAX_QUERY_LENGTH = 500
  MIN_QUERY_LENGTH = 2

  # Patterns that indicate prompt injection attempts
  INJECTION_PATTERNS = [
    /ignore\s+(all\s+)?previous\s+instructions/i,
    /disregard\s+(all\s+)?previous/i,
    /forget\s+(all\s+)?previous/i,
    /you\s+are\s+now\s+(a|an)\s+/i,
    /new\s+instructions?\s*:/i,
    /system\s*:\s*/i,
    /\[SYSTEM\]/i,
    /\[INST\]/i,
    /<<SYS>>/i,
    /<\|im_start\|>/i,
    /\bdo\s+not\s+follow\s+(any\s+)?rules\b/i,
    /\bact\s+as\s+if\s+you\s+(have\s+)?no\s+restrictions\b/i,
    /\bjailbreak\b/i,
    /\bDAN\s+mode\b/i,
    /\bdev(eloper)?\s+mode\b/i,
    /\boverride\s+(all\s+)?safety\b/i,
    /\bbypass\s+(all\s+)?filters?\b/i,
    /pretend\s+you\s+(are|can|have)/i,
    /reveal\s+(your\s+)?system\s+prompt/i,
    /show\s+(me\s+)?(your\s+)?instructions/i,
    /what\s+(are|is)\s+(your\s+)?system\s+(prompt|message|instructions)/i,
    /repeat\s+(your\s+)?(system\s+)?instructions/i,
    /output\s+(your\s+)?(initial|system)\s+(prompt|instructions)/i
  ].freeze

  SAFETY_FILTER = AiGuardrails::SafetyFilter.new(blocklist: INJECTION_PATTERNS).freeze

  # Characters that could be used for encoding attacks
  SUSPICIOUS_CHARS = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/ # Control characters except \t, \n, \r

  class InvalidInputError < StandardError
    attr_reader :code

    def initialize(message, code = :invalid_input)
      @code = code
      super(message)
    end
  end

  def self.sanitize(query)
    raise InvalidInputError.new("Query cannot be empty.", :empty_query) if query.nil? || query.to_s.strip.empty?

    cleaned = query.to_s
      .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      .gsub(SUSPICIOUS_CHARS, "")
      .gsub(/\s+/, " ")
      .strip

    if cleaned.length < MIN_QUERY_LENGTH
      raise InvalidInputError.new("Query is too short (minimum #{MIN_QUERY_LENGTH} characters).", :too_short)
    end

    if cleaned.length > MAX_QUERY_LENGTH
      raise InvalidInputError.new("Query is too long (maximum #{MAX_QUERY_LENGTH} characters).", :too_long)
    end

    unless SAFETY_FILTER.safe?(cleaned)
      Rails.logger.warn("[InputSanitizer] Prompt injection attempt detected: #{cleaned.slice(0, 100)}")
      raise InvalidInputError.new(
        "Your query contains patterns that look like an attempt to manipulate the assistant. Please rephrase your question.",
        :injection_detected
      )
    end

    # Check for excessive special character density (possible encoding attack)
    special_char_ratio = cleaned.count('{}[]<>|\\').to_f / cleaned.length
    if special_char_ratio > 0.3
      raise InvalidInputError.new(
        "Query contains too many special characters. Please use natural language.",
        :suspicious_characters
      )
    end

    # Check for excessive repetition (token waste attack)
    words = cleaned.downcase.split
    if words.length > 5
      unique_ratio = words.uniq.length.to_f / words.length
      if unique_ratio < 0.2
        raise InvalidInputError.new(
          "Query contains excessive repetition. Please provide a clear, concise question.",
          :excessive_repetition
        )
      end
    end

    cleaned
  end

  # Extract location hints from a query for location-aware search
  def self.extract_location(query)
    location_patterns = [
      /\bin\s+([A-Z][a-zA-Z\s,]+?)(?:\s*\?|\s*$|\s+for\b|\s+that\b|\s+with\b)/,
      /\bnear\s+([A-Z][a-zA-Z\s,]+?)(?:\s*\?|\s*$|\s+for\b)/,
      /\baround\s+([A-Z][a-zA-Z\s,]+?)(?:\s*\?|\s*$)/,
      /\bat\s+([A-Z][a-zA-Z\s,]+?)(?:\s*\?|\s*$)/
    ]

    location_patterns.each do |pattern|
      match = query.match(pattern)
      if match
        location = match[1].strip.gsub(/\s*,\s*$/, "")
        return location if location.length >= 2 && location.length <= 100
      end
    end

    nil
  end
end
