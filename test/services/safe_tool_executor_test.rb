require "test_helper"

class SafeToolExecutorTest < ActiveSupport::TestCase
  setup do
    @executor = SafeToolExecutor.new
  end


  test "execute calls the correct tool and returns a result" do
    fake_tool = Class.new do
      def self.call(args)
        { answer: "42", query: args[:query] }
      end
    end

    Tools.stub(:fetch, ->(_) { fake_tool }) do
      result = @executor.execute("web_search", { query: "meaning of life" })
      assert_equal "42", result[:answer]
    end
  end

  test "execute increments call_count" do
    fake_tool = Class.new { def self.call(_); {}; end }

    Tools.stub(:fetch, ->(_) { fake_tool }) do
      assert_equal 0, @executor.call_count
      @executor.execute("web_search", {})
      assert_equal 1, @executor.call_count
      @executor.execute("web_search", {})
      assert_equal 2, @executor.call_count
    end
  end


  test "returns error hash for unknown tool name" do
    result = @executor.execute("nonexistent_tool", {})
    assert result.key?(:error)
    assert_match "nonexistent_tool", result[:error]
  end

  test "returns error hash when tool raises ArgumentError" do
    bad_tool = Class.new { def self.call(_); raise ArgumentError, "Query is required."; end }

    Tools.stub(:fetch, ->(_) { bad_tool }) do
      result = @executor.execute("web_search", {})
      assert result.key?(:error)
      assert_match "Invalid input", result[:error]
    end
  end

  test "returns timeout error when tool exceeds TOOL_TIMEOUT" do
    slow_tool = Class.new do
      def self.call(_)
        sleep 0.01  # minimal; Timeout stubbed below
      end
    end

    Tools.stub(:fetch, ->(_) { slow_tool }) do
      Timeout.stub(:timeout, ->(_) { raise Timeout::Error }) do
        result = @executor.execute("web_search", {})
        assert result.key?(:error)
        assert_match "timed out", result[:error]
      end
    end
  end

  test "returns too-many-calls error after MAX_TOOL_CALLS_PER_REQUEST calls" do
    fake_tool = Class.new { def self.call(_); {}; end }

    # exhaust the limit
    (SafeToolExecutor::MAX_TOOL_CALLS_PER_REQUEST).times do
      Tools.stub(:fetch, ->(_) { fake_tool }) { @executor.execute("web_search", {}) }
    end

    # The very next call should return the error
    result = Tools.stub(:fetch, ->(_) { fake_tool }) { @executor.execute("web_search", {}) }
    assert result.key?(:error)
    assert_match "Maximum tool calls", result[:error]
  end

  test "returns generic error hash for unexpected exceptions" do
    broken_tool = Class.new { def self.call(_); raise RuntimeError, "boom"; end }

    Tools.stub(:fetch, ->(_) { broken_tool }) do
      result = @executor.execute("web_search", {})
      assert result.key?(:error)
      assert_match "encountered an error", result[:error]
    end
  end


  test "sanitize_arguments symbolizes hash keys" do
    result = @executor.send(:sanitize_arguments, { "query" => "hello", "num" => 5 })
    assert result.key?(:query)
    assert result.key?(:num)
  end

  test "sanitize_arguments parses a JSON string" do
    result = @executor.send(:sanitize_arguments, '{"query":"hello"}')
    assert_equal "hello", result[:query]
  end

  test "sanitize_arguments returns empty hash for invalid JSON string" do
    result = @executor.send(:sanitize_arguments, "not json at all")
    assert_equal({}, result)
  end

  test "sanitize_arguments returns empty hash for nil" do
    result = @executor.send(:sanitize_arguments, nil)
    assert_equal({}, result)
  end

  test "sanitize_arguments strips non-alphanumeric characters from keys" do
    result = @executor.send(:sanitize_arguments, { "key!@#" => "val" })
    assert result.key?(:key)
    refute result.key?(:"key!@#")
  end


  test "truncate_output returns short hash unchanged" do
    input = { results: [ { title: "short" } ] }
    result = @executor.send(:truncate_output, input)
    assert_equal "short", result[:results].first[:title]
  end

  test "truncate_output truncates long string values in hash" do
    long_string = "x" * 10_001
    input = { summary: long_string }
    result = @executor.send(:truncate_output, input)
    assert_includes result[:summary], "[truncated]"
  end

  test "truncate_output trims arrays in hash when output is too large" do
    input = { results: (1..20).map { |i| { title: "item #{i}", content: "c" * 600 } } }
    result = @executor.send(:truncate_output, input)
    assert result[:results].length <= 3
  end
end
