module Tools
  require "serpapi"

  class WeatherSearch
    def self.schema
      {
        name: "weather_search",
        description: "Get current weather information for a specific location. Use this when the user asks about weather conditions, temperature, or forecasts.",
        parameters: {
          type: "object",
          properties: {
            location: {
              type: "string",
              description: "The city or location to get weather for (e.g. 'New York', 'London, UK', 'Tokyo')."
            }
          },
          required: [ "location" ]
        }
      }
    end

    def self.call(args)
      location = args[:location].to_s.strip

      raise ArgumentError, "Location is required." if location.empty?
      raise ArgumentError, "Location must be between 2 and 100 characters." if location.length < 2 || location.length > 100

      client = SerpApi::Client.new(
        engine: "google",
        safe: "active",
        api_key: ENV.fetch("SERPAPI_API_KEY")
      )

      response = client.search(q: "weather in #{location}")

      sanitize(response, location)
    end

    private

    def self.sanitize(data, location)
      answer_box = data[:answer_box] || {}

      # SerpAPI returns type "weather_result" when Google shows a weather card
      is_weather = answer_box[:type] == "weather_result" || answer_box[:temperature]

      if is_weather
        {
          location: location,
          temperature: answer_box[:temperature],
          unit: answer_box[:unit],
          description: answer_box[:weather],
          humidity: answer_box[:humidity],
          wind: answer_box[:wind],
          precipitation: answer_box[:precipitation],
          forecast: extract_forecast(answer_box)
        }.compact
      else
        # No weather card found — tell the model clearly so it doesn't hallucinate
        { location: location, error: "No structured weather data found for '#{location}'. Do not guess or fabricate weather conditions." }
      end
    end

    def self.extract_forecast(answer_box)
      forecast = answer_box[:forecast] || []
      return nil if forecast.empty?

      forecast.first(4).map do |day|
        {
          day: day[:day],
          high: day[:temperature]&.dig(:high),
          low: day[:temperature]&.dig(:low),
          description: day[:weather]
        }.compact
      end
    end
  end
end
