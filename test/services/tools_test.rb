require "test_helper"

class ToolsTest < ActiveSupport::TestCase

  test "fetch returns the correct class for web_search" do
    assert_equal Tools::WebSearch, Tools.fetch("web_search")
  end

  test "fetch returns the correct class for news_search" do
    assert_equal Tools::NewsSearch, Tools.fetch("news_search")
  end

  test "fetch returns the correct class for weather_search" do
    assert_equal Tools::WeatherSearch, Tools.fetch("weather_search")
  end

  test "fetch returns the correct class for recall_memories" do
    assert_equal Tools::RecallMemories, Tools.fetch("recall_memories")
  end

  test "fetch accepts symbol keys" do
    assert_equal Tools::WebSearch, Tools.fetch(:web_search)
  end

  test "fetch raises ArgumentError for unknown tool" do
    err = assert_raises(ArgumentError) { Tools.fetch("nonexistent") }
    assert_match "nonexistent", err.message
  end


  test "schema returns an array" do
    assert_kind_of Array, Tools.schema
  end

  test "schema has one entry per registered tool" do
    assert_equal Tools.registry.size, Tools.schema.size
  end

  test "each schema entry has type 'function'" do
    Tools.schema.each do |entry|
      assert_equal "function", entry[:type]
    end
  end

  test "each schema entry has a function hash with name and parameters" do
    Tools.schema.each do |entry|
      fn = entry[:function]
      assert fn.key?(:name), "Missing :name in tool schema"
      assert fn.key?(:parameters), "Missing :parameters in tool schema"
    end
  end


  test "available_tool_names returns an array of strings" do
    names = Tools.available_tool_names
    assert_kind_of Array, names
    names.each { |n| assert_kind_of String, n }
  end

  test "available_tool_names includes all registered tool names" do
    names = Tools.available_tool_names
    assert_includes names, "web_search"
    assert_includes names, "news_search"
    assert_includes names, "weather_search"
    assert_includes names, "recall_memories"
  end
end
