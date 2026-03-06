require "test_helper"
require "ostruct"

class Memory::ExtractorTest < ActiveSupport::TestCase

  test "parse_facts returns empty array for blank response" do
    assert_equal [], Memory::Extractor.send(:parse_facts, "")
    assert_equal [], Memory::Extractor.send(:parse_facts, nil)
  end

  test "parse_facts returns empty array for invalid JSON" do
    assert_equal [], Memory::Extractor.send(:parse_facts, "not json at all")
  end

  test "parse_facts returns empty array when JSON has no facts key" do
    assert_equal [], Memory::Extractor.send(:parse_facts, '{"other": []}')
  end

  test "parse_facts returns empty array when facts is not an array" do
    assert_equal [], Memory::Extractor.send(:parse_facts, '{"facts": "string"}')
  end

  test "parse_facts returns parsed facts for valid JSON" do
    json = '{"facts": [{"fact": "Likes basketball", "category": "preference"}]}'
    result = Memory::Extractor.send(:parse_facts, json)
    assert_equal 1, result.length
    assert_equal "Likes basketball", result.first[:fact]
    assert_equal "preference",       result.first[:category]
  end

  test "parse_facts downcases category" do
    json = '{"facts": [{"fact": "Plays tennis", "category": "HOBBY"}]}'
    result = Memory::Extractor.send(:parse_facts, json)
    assert_equal "hobby", result.first[:category]
  end

  test "parse_facts filters out entries with invalid category" do
    json = '{"facts": [
      {"fact": "Likes pizza",        "category": "preference"},
      {"fact": "Unknown category",   "category": "invalid_cat"}
    ]}'
    result = Memory::Extractor.send(:parse_facts, json)
    assert_equal 1, result.length
    assert_equal "preference", result.first[:category]
  end

  test "parse_facts filters out entries with blank fact" do
    json = '{"facts": [{"fact": "", "category": "preference"}]}'
    assert_equal [], Memory::Extractor.send(:parse_facts, json)
  end

  test "parse_facts handles all valid categories" do
    UserMemory::CATEGORIES.each do |cat|
      json = %Q({"facts": [{"fact": "Some fact", "category": "#{cat}"}]})
      result = Memory::Extractor.send(:parse_facts, json)
      assert_equal 1, result.length, "Expected category '#{cat}' to be valid"
    end
  end


  test "build_context returns empty string for blank history" do
    assert_equal "", Memory::Extractor.send(:build_context, [])
    assert_equal "", Memory::Extractor.send(:build_context, nil)
  end

  test "build_context includes User/Assistant prefixes" do
    messages = [
      OpenStruct.new(role: "user",      content: "I love hiking"),
      OpenStruct.new(role: "assistant", content: "That is great!")
    ]
    result = Memory::Extractor.send(:build_context, messages)
    assert_includes result, "User: I love hiking"
    assert_includes result, "Assistant: That is great!"
  end

  test "build_context uses only the last 10 messages" do
    messages = (1..15).map { |i| OpenStruct.new(role: "user", content: "msg #{i}") }
    result = Memory::Extractor.send(:build_context, messages)
    refute_includes result, "msg 5"   # msgs 1-5 are dropped; "msg 5" can't be a substring of any kept message
    assert_includes result, "msg 6"   # 15 - 10 + 1 = 6th is the earliest kept
    assert_includes result, "msg 15"
  end

  test "build_context truncates long message content" do
    long_msg = "x" * 400
    messages = [ OpenStruct.new(role: "user", content: long_msg) ]
    result = Memory::Extractor.send(:build_context, messages)
    # Truncated to 300 chars, so the full 400-char string should not appear
    refute_includes result, long_msg
  end


  test "extract returns empty array for blank message" do
    assert_equal [], Memory::Extractor.extract("")
    assert_equal [], Memory::Extractor.extract(nil)
  end

  test "extract returns parsed facts when LLM responds with valid JSON" do
    json_response = '{"facts": [{"fact": "Enjoys hiking", "category": "hobby"}]}'
    stub_extractor_llm(json_response) do
      result = Memory::Extractor.extract("I love hiking every weekend")
      assert_equal 1, result.length
      assert_equal "Enjoys hiking", result.first[:fact]
    end
  end

  test "extract returns empty array when LLM returns no facts" do
    stub_extractor_llm('{"facts": []}') do
      result = Memory::Extractor.extract("What is the weather in London?")
      assert_equal [], result
    end
  end

  test "extract returns empty array when LLM returns invalid JSON" do
    stub_extractor_llm("oops not json") do
      result = Memory::Extractor.extract("I like cats")
      assert_equal [], result
    end
  end

  test "extract passes recent_history to build_context" do
    history = [ OpenStruct.new(role: "user", content: "I play chess") ]
    built_context = nil

    Memory::Extractor.stub(:build_context, ->(h) { built_context = h; "" }) do
      stub_extractor_llm('{"facts": []}') do
        Memory::Extractor.extract("I love it", recent_history: history)
      end
    end

    assert_equal history, built_context
  end
end
