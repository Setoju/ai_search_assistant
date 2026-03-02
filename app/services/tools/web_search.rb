module Tools
  require "serpapi"

  class WebSearch
    def self.schema
      {
        name: "web_search",
        description: "General web search for any topic. Use this when the user asks a question that can be answered by searching the web.",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The search query."
            }
          },
          required: ["query"]
        }
      }
    end

    def self.call(args)
      query = args[:query]

      raise ArgumentError, "Query is required." unless query
      raise ArgumentError, "Query must be between 3 and 200 characters." if query.length < 3 || query.length > 200

      client = SerpApi::Client.new(
        engine: "google",
        location: args[:location] || "",
        safe: "active",
        api_key: ENV.fetch("SERPAPI_API_KEY")
      )

      response = client.search(q: query, num: 5)

      sanitize(response)
    end

    private

    def self.sanitize(data)
      results = (data[:organic_results] || []).first(5).map do |result|
        {
          title: result[:title].to_s.slice(0, 200),
          url: result[:link],
          content: result[:snippet].to_s.slice(0, 1000)
        }
      end

      { results: results }
    end
  end
end