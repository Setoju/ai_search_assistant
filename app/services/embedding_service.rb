require "net/http"
require "json"

class EmbeddingService
  OLLAMA_BASE_URL = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  EMBEDDING_MODEL = ENV.fetch("OLLAMA_EMBEDDING_MODEL", "nomic-embed-text")

  # Generate an embedding vector for the given text using Ollama's nomic-embed-text.
  # Returns an Array of floats, or an empty array on failure.
  def self.generate(text)
    return [] if text.blank?

    Rails.logger.info("[EmbeddingService] Generating embedding for: #{text.truncate(80)}")

    result = embed(text)

    if result.empty?
      Rails.logger.error("[EmbeddingService] Failed to generate embedding")
    else
      Rails.logger.info("[EmbeddingService] Generated embedding with #{result.length} dimensions")
    end

    result
  rescue StandardError => e
    Rails.logger.error("[EmbeddingService] #{e.class} - #{e.message}")
    []
  end

  private

  def self.embed(text)
    uri = URI("#{OLLAMA_BASE_URL}/api/embeddings")
    body = { model: EMBEDDING_MODEL, prompt: text }

    response = make_request(uri, body)
    return [] unless response

    parsed = JSON.parse(response.body)
    embedding = parsed["embedding"]

    if embedding.is_a?(Array) && !embedding.empty?
      embedding.map(&:to_f)
    else
      Rails.logger.warn("[EmbeddingService] /api/embeddings unexpected format: #{parsed.keys}")
      []
    end
  rescue StandardError => e
    Rails.logger.warn("[EmbeddingService] /api/embeddings failed: #{e.message}")
    []
  end

  def self.make_request(uri, body)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 10
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = body.to_json

    response = http.request(request)

    unless response.code.to_i == 200
      Rails.logger.warn("[EmbeddingService] #{uri.path} returned #{response.code}: #{response.body.to_s.truncate(200)}")
      return nil
    end

    response
  end
end
