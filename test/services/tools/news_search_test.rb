require "test_helper"

class Tools::NewsSearchTest < ActiveSupport::TestCase
  VALID_RESPONSE = {
    news_results: [
      { title: "News One",  link: "https://news.com/1", source: "BBC",     date: "1 day ago",  snippet: "First article." },
      { title: "News Two",  link: "https://news.com/2", source: "Reuters", date: "2 days ago", snippet: "Second article." }
    ]
  }.freeze


  test "schema returns a hash with name 'news_search'" do
    assert_equal "news_search", Tools::NewsSearch.schema[:name]
  end

  test "schema lists query as a required parameter" do
    assert_includes Tools::NewsSearch.schema[:parameters][:required], "query"
  end

  test "schema defines valid time_period enum values" do
    enum_values = Tools::NewsSearch.schema[:parameters][:properties][:time_period][:enum]
    assert_equal %w[d w m], enum_values
  end


  test "raises ArgumentError when query is empty" do
    err = assert_raises(ArgumentError) { Tools::NewsSearch.call({ query: "" }) }
    assert_match "required", err.message
  end

  test "raises ArgumentError when query is shorter than 3 characters" do
    err = assert_raises(ArgumentError) { Tools::NewsSearch.call({ query: "ab" }) }
    assert_match "between 3 and 200", err.message
  end

  test "raises ArgumentError when query is longer than 200 characters" do
    err = assert_raises(ArgumentError) { Tools::NewsSearch.call({ query: "a" * 201 }) }
    assert_match "between 3 and 200", err.message
  end

  test "raises ArgumentError for invalid time_period value" do
    err = assert_raises(ArgumentError) { Tools::NewsSearch.call({ query: "AI news", time_period: "y" }) }
    assert_match "Invalid time period", err.message
  end


  test "call uses 'w' as default time_period" do
    captured_kwargs = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:search) do |**kwargs|
      captured_kwargs = kwargs
      VALID_RESPONSE
    end

    SerpApi::Client.stub(:new, fake_client) do
      Tools::NewsSearch.call({ query: "AI news" })
    end

    assert_equal "qdr:w", captured_kwargs[:tbs]
  end

  test "call accepts all valid time_period values" do
    %w[d w m].each do |period|
      stub_serpapi(VALID_RESPONSE) do
        result = Tools::NewsSearch.call({ query: "AI news", time_period: period })
        assert result.key?(:results)
      end
    end
  end

  test "call returns a results array" do
    stub_serpapi(VALID_RESPONSE) do
      result = Tools::NewsSearch.call({ query: "AI news" })
      assert_kind_of Array, result[:results]
    end
  end

  test "call maps title, url, source, published_date, snippet" do
    stub_serpapi(VALID_RESPONSE) do
      result = Tools::NewsSearch.call({ query: "AI news" })
      first = result[:results].first
      assert_equal "News One",             first[:title]
      assert_equal "https://news.com/1",   first[:url]
      assert_equal "BBC",                  first[:source]
      assert_equal "1 day ago",            first[:published_date]
      assert_equal "First article.",       first[:snippet]
    end
  end

  test "call returns a note key in the result" do
    stub_serpapi(VALID_RESPONSE) do
      result = Tools::NewsSearch.call({ query: "AI news" })
      assert result.key?(:note)
    end
  end

  test "call returns up to 5 results" do
    many_news = {
      news_results: (1..10).map { |i|
        { title: "N#{i}", link: "https://n.com/#{i}", source: "S#{i}", date: "#{i} days ago", snippet: "s#{i}" }
      }
    }
    stub_serpapi(many_news) do
      result = Tools::NewsSearch.call({ query: "tech news" })
      assert result[:results].length <= 5
    end
  end

  test "call returns empty results array when no news_results" do
    stub_serpapi({}) do
      result = Tools::NewsSearch.call({ query: "AI news" })
      assert_equal [], result[:results]
    end
  end
end
