require "net/http"
require "json"

module Memory
  # Required env vars:
  #   GEMINI_API_KEY=your_api_key
  #   GEMINI_MEMORY_MODEL=gemini-2.5-flash-lite  (optional, defaults to gemini-2.5-flash-lite)
  module LlmClient
    MODEL           = ENV.fetch("GEMINI_MEMORY_MODEL", "gemini-2.5-flash-lite").freeze
    GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models".freeze

    def self.call(messages)
      api_key = ENV.fetch("GEMINI_API_KEY") do
        raise "GEMINI_API_KEY is not set — required for memory extraction."
      end

      # Convert to Gemini format.
      # Gemini uses role "user" / "model" with no dedicated "system" role —
      # system prompts are merged into the first user turn.
      contents = []
      pending_system = []

      messages.each do |msg|
        case msg[:role].to_s
        when "system"
          pending_system << msg[:content].to_s
        when "user"
          text = pending_system.any? ? "#{pending_system.join("\n\n")}\n\n#{msg[:content]}" : msg[:content].to_s
          pending_system = []
          contents << { role: "user", parts: [ { text: text } ] }
        when "assistant", "model"
          contents << { role: "model", parts: [ { text: msg[:content].to_s } ] }
        end
      end

      body = {
        contents: contents,
        generationConfig: {
          temperature: 0.1,
          responseMimeType: "application/json"
        }
      }

      uri = URI("#{GEMINI_API_BASE}/#{MODEL}:generateContent?key=#{api_key}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = true
      http.open_timeout = 10
      http.read_timeout = 60

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = body.to_json

      response = http.request(request)
      raise "Gemini error: #{response.code} #{response.body.to_s.truncate(200)}" unless response.code.to_i == 200

      parsed = JSON.parse(response.body)
      parsed.dig("candidates", 0, "content", "parts", 0, "text") || ""
    end
  end
end
