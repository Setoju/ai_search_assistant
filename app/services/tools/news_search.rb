module Tools
  require "serpapi"

  class NewsSearch
    def self.schema
      {
        name: "news_search",
        description: "Search for recent news articles on a topic. Use this when the user asks about current events, breaking news, or recent developments.",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The news search query."
            },
            time_period: {
              type: "string",
              enum: %w[d w m],
              description: "Time period filter: 'd' for past day, 'w' for past week, 'm' for past month. Defaults to past week."
            }
          },
          required: [ "query" ]
        }
      }
    end

    def self.call(args)
      query = args[:query].to_s.strip
      time_period = args[:time_period] || "w"

      raise ArgumentError, "Query is required." if query.empty?
      raise ArgumentError, "Query must be between 3 and 200 characters." if query.length < 3 || query.length > 200
      raise ArgumentError, "Invalid time period." unless %w[d w m].include?(time_period)

      client = SerpApi::Client.new(
        engine: "google",
        safe: "active",
        api_key: ENV.fetch("SERPAPI_API_KEY")
      )

      response = client.search(q: query, tbm: "nws", tbs: "qdr:#{time_period}", num: 5)

      sanitize(response)
    end

    private

    def self.sanitize(data)
      results = (data[:news_results] || []).first(5).map do |result|
        {
          title: result[:title].to_s.slice(0, 200),
          url: result[:link],
          source: result[:source].to_s.slice(0, 100),
          published_date: result[:date].to_s.slice(0, 50),
          snippet: result[:snippet].to_s.slice(0, 500)
        }
      end

      { results: results, note: "For each article: write a 1-2 sentence summary of the snippet, then cite the source name, url, and published_date." }
    end
  end
end
