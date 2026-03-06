require "test_helper"

class Tools::WebSearchTest < ActiveSupport::TestCase
  VALID_RESPONSE = {
    organic_results: [
      { title: "Result One",  link: "https://example.com/1", snippet: "First snippet." },
      { title: "Result Two",  link: "https://example.com/2", snippet: "Second snippet." }
    ]
  }.freeze


  test "schema returns a hash with name 'web_search'" do
    assert_equal "web_search", Tools::WebSearch.schema[:name]
  end

  test "schema declares query as a required parameter" do
    schema = Tools::WebSearch.schema
    assert_includes schema[:parameters][:required], "query"
  end


  test "raises ArgumentError when query key is absent" do
    assert_raises(ArgumentError) { Tools::WebSearch.call({}) }
  end

  test "raises ArgumentError when query is nil" do
    assert_raises(ArgumentError) { Tools::WebSearch.call({ query: nil }) }
  end

  test "raises ArgumentError when query is shorter than 3 characters" do
    err = assert_raises(ArgumentError) { Tools::WebSearch.call({ query: "ab" }) }
    assert_match "between 3 and 200", err.message
  end

  test "raises ArgumentError when query is longer than 200 characters" do
    long = "a" * 201
    err = assert_raises(ArgumentError) { Tools::WebSearch.call({ query: long }) }
    assert_match "between 3 and 200", err.message
  end


  test "call returns a results array" do
    stub_serpapi(VALID_RESPONSE) do
      result = Tools::WebSearch.call({ query: "ruby on rails" })
      assert result.key?(:results)
      assert_kind_of Array, result[:results]
    end
  end

  test "call returns up to 5 results" do
    many_results = {
      organic_results: (1..10).map { |i|
        { title: "R#{i}", link: "https://example.com/#{i}", snippet: "s#{i}" }
      }
    }
    stub_serpapi(many_results) do
      result = Tools::WebSearch.call({ query: "ruby on rails" })
      assert result[:results].length <= 5
    end
  end

  test "call maps title, url, and content from organic_results" do
    stub_serpapi(VALID_RESPONSE) do
      result = Tools::WebSearch.call({ query: "ruby on rails" })
      first = result[:results].first
      assert_equal "Result One",             first[:title]
      assert_equal "https://example.com/1",  first[:url]
      assert_equal "First snippet.",          first[:content]
    end
  end

  test "call truncates titles to 200 characters" do
    long_title = "T" * 300
    response = { organic_results: [ { title: long_title, link: "https://x.com", snippet: "s" } ] }
    stub_serpapi(response) do
      result = Tools::WebSearch.call({ query: "ruby on rails" })
      assert result[:results].first[:title].length <= 200
    end
  end

  test "call truncates snippets to 1000 characters" do
    long_snippet = "s" * 1500
    response = { organic_results: [ { title: "T", link: "https://x.com", snippet: long_snippet } ] }
    stub_serpapi(response) do
      result = Tools::WebSearch.call({ query: "ruby on rails" })
      assert result[:results].first[:content].length <= 1000
    end
  end

  test "call returns empty results array when no organic_results" do
    stub_serpapi({}) do
      result = Tools::WebSearch.call({ query: "ruby on rails" })
      assert_equal [], result[:results]
    end
  end
end
