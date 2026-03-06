require "test_helper"

class Tools::WeatherSearchTest < ActiveSupport::TestCase
  WEATHER_RESPONSE = {
    answer_box: {
      type: "weather_result",
      temperature: "72",
      unit: "Fahrenheit",
      weather: "Partly cloudy",
      humidity: "60%",
      wind: "10 mph",
      precipitation: "0%",
      forecast: [
        { day: "Mon", temperature: { high: "75", low: "60" }, weather: "Sunny" },
        { day: "Tue", temperature: { high: "70", low: "58" }, weather: "Cloudy" },
        { day: "Wed", temperature: { high: "68", low: "55" }, weather: "Rainy" },
        { day: "Thu", temperature: { high: "73", low: "59" }, weather: "Partly cloudy" },
        { day: "Fri", temperature: { high: "77", low: "62" }, weather: "Sunny" }
      ]
    }
  }.freeze

  NO_WEATHER_RESPONSE = { answer_box: { type: "calculator" } }.freeze


  test "schema returns a hash with name 'weather_search'" do
    assert_equal "weather_search", Tools::WeatherSearch.schema[:name]
  end

  test "schema declares location as a required parameter" do
    assert_includes Tools::WeatherSearch.schema[:parameters][:required], "location"
  end


  test "raises ArgumentError when location is empty" do
    err = assert_raises(ArgumentError) { Tools::WeatherSearch.call({ location: "" }) }
    assert_match "required", err.message
  end

  test "raises ArgumentError when location is only whitespace" do
    err = assert_raises(ArgumentError) { Tools::WeatherSearch.call({ location: "   " }) }
    assert_match "required", err.message
  end

  test "raises ArgumentError when location is 1 character" do
    err = assert_raises(ArgumentError) { Tools::WeatherSearch.call({ location: "A" }) }
    assert_match "between 2 and 100", err.message
  end

  test "raises ArgumentError when location is longer than 100 characters" do
    err = assert_raises(ArgumentError) { Tools::WeatherSearch.call({ location: "A" * 101 }) }
    assert_match "between 2 and 100", err.message
  end


  test "call returns structured weather data when answer_box has weather_result type" do
    stub_serpapi(WEATHER_RESPONSE) do
      result = Tools::WeatherSearch.call({ location: "San Francisco" })
      assert_equal "San Francisco", result[:location]
      assert_equal "72",            result[:temperature]
      assert_equal "Partly cloudy", result[:description]
    end
  end

  test "call returns forecast with at most 4 days" do
    stub_serpapi(WEATHER_RESPONSE) do
      result = Tools::WeatherSearch.call({ location: "San Francisco" })
      assert result[:forecast].length <= 4
    end
  end

  test "call returns forecast with day, high, low, description keys" do
    stub_serpapi(WEATHER_RESPONSE) do
      result = Tools::WeatherSearch.call({ location: "San Francisco" })
      day = result[:forecast].first
      assert day.key?(:day)
      assert day.key?(:high)
      assert day.key?(:low)
      assert day.key?(:description)
    end
  end


  test "call returns error message when answer_box has no weather data" do
    stub_serpapi(NO_WEATHER_RESPONSE) do
      result = Tools::WeatherSearch.call({ location: "Mars" })
      assert result.key?(:error)
      assert_match "No structured weather data", result[:error]
    end
  end

  test "call returns error message when response is empty" do
    stub_serpapi({}) do
      result = Tools::WeatherSearch.call({ location: "Atlantis" })
      assert result.key?(:error)
    end
  end


  test "extract_forecast returns nil for empty forecast array" do
    result = Tools::WeatherSearch.send(:extract_forecast, { forecast: [] })
    assert_nil result
  end

  test "extract_forecast returns nil when forecast key is absent" do
    result = Tools::WeatherSearch.send(:extract_forecast, {})
    assert_nil result
  end

  test "extract_forecast maps each day correctly" do
    answer_box = {
      forecast: [
        { day: "Monday", temperature: { high: "80", low: "65" }, weather: "Sunny" }
      ]
    }
    result = Tools::WeatherSearch.send(:extract_forecast, answer_box)
    assert_equal 1, result.length
    assert_equal "Monday", result.first[:day]
    assert_equal "80",     result.first[:high]
    assert_equal "65",     result.first[:low]
    assert_equal "Sunny",  result.first[:description]
  end

  test "extract_forecast limits to 4 days" do
    answer_box = {
      forecast: (1..7).map { |i| { day: "Day#{i}", temperature: { high: "70", low: "50" }, weather: "Clear" } }
    }
    result = Tools::WeatherSearch.send(:extract_forecast, answer_box)
    assert_equal 4, result.length
  end

  test "extract_forecast compacts nil values" do
    answer_box = {
      forecast: [ { day: "Mon", temperature: nil, weather: "Sunny" } ]
    }
    result = Tools::WeatherSearch.send(:extract_forecast, answer_box)
    # high/low will be nil (from nil&.dig), compact removes them
    refute result.first.key?(:high)
    refute result.first.key?(:low)
  end
end
