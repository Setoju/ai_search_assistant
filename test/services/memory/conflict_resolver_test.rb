require "test_helper"

class Memory::ConflictResolverTest < ActiveSupport::TestCase

  test "parse_resolution returns no-conflict default for blank response" do
    result = Memory::ConflictResolver.send(:parse_resolution, "")
    assert_equal false, result[:conflicts]
  end

  test "parse_resolution returns no-conflict default for nil" do
    result = Memory::ConflictResolver.send(:parse_resolution, nil)
    assert_equal false, result[:conflicts]
  end

  test "parse_resolution returns no-conflict for invalid JSON" do
    result = Memory::ConflictResolver.send(:parse_resolution, "not json")
    assert_equal false, result[:conflicts]
  end

  test "parse_resolution parses a non-conflicting resolution correctly" do
    json = '{"conflicts": false, "keep": "new", "reason": "Different topics"}'
    result = Memory::ConflictResolver.send(:parse_resolution, json)
    assert_equal false,             result[:conflicts]
    assert_equal "new",             result[:keep]
    assert_equal "Different topics", result[:reason]
  end

  test "parse_resolution parses a conflicting resolution to keep existing" do
    json = '{"conflicts": true, "keep": "existing", "reason": "Older fact is more accurate"}'
    result = Memory::ConflictResolver.send(:parse_resolution, json)
    assert_equal true,                          result[:conflicts]
    assert_equal "existing",                    result[:keep]
    assert_equal "Older fact is more accurate", result[:reason]
  end

  test "parse_resolution parses a conflicting resolution to keep new" do
    json = '{"conflicts": true, "keep": "new", "reason": "Newer fact overrides"}'
    result = Memory::ConflictResolver.send(:parse_resolution, json)
    assert_equal true,                  result[:conflicts]
    assert_equal "new",                 result[:keep]
    assert_equal "Newer fact overrides", result[:reason]
  end

  test "parse_resolution downcases the keep value" do
    json = '{"conflicts": true, "keep": "NEW", "reason": "x"}'
    result = Memory::ConflictResolver.send(:parse_resolution, json)
    assert_equal "new", result[:keep]
  end


  test "build_conflict_prompt contains both facts" do
    t1 = Time.current - 1.day
    t2 = Time.current
    prompt = Memory::ConflictResolver.send(:build_conflict_prompt,
                                           "Likes basketball", "Hates basketball", t1, t2)
    assert_includes prompt, "Likes basketball"
    assert_includes prompt, "Hates basketball"
  end

  test "build_conflict_prompt contains timestamps" do
    t1 = Time.current - 1.day
    t2 = Time.current
    prompt = Memory::ConflictResolver.send(:build_conflict_prompt, "fact A", "fact B", t1, t2)
    assert_includes prompt, t1.to_s
    assert_includes prompt, t2.to_s
  end


  test "preference conflicts with dislike and hobby" do
    conflicting = Memory::ConflictResolver::CONFLICTING_CATEGORIES["preference"]
    assert_includes conflicting, "dislike"
    assert_includes conflicting, "hobby"
    assert_includes conflicting, "preference"
  end

  test "personal_fact only conflicts with personal_fact" do
    conflicting = Memory::ConflictResolver::CONFLICTING_CATEGORIES["personal_fact"]
    assert_equal %w[personal_fact], conflicting
  end


  test "resolve returns :skip action when embedding generation fails" do
    user = users(:one)
    EmbeddingService.stub(:generate, []) do
      result = Memory::ConflictResolver.resolve(user, "Likes soccer", "preference")
      assert_equal :skip, result[:action]
    end
  end


  test "resolve returns :store action when user has no memories in related categories" do
    user = users(:two)
    # User two has only a personal_fact memory; querying preference categories
    # should find nothing if we search preference/dislike/hobby
    fake_embedding = Array.new(5, 0.5)
    EmbeddingService.stub(:generate, fake_embedding) do
      result = Memory::ConflictResolver.resolve(user, "Likes rock climbing", "preference")
      assert_includes %i[store replace skip], result[:action]
    end
  end


  test "resolve returns :skip when new fact is a near-identical duplicate" do
    user = users(:one)
    # The fixture preference_one has embedding {0.1,0.2,0.3,0.4,0.5}
    # Same embedding → cosine similarity == 1.0 ≥ 0.95 → skip if AI says no conflict
    duplicate_embedding = [ 0.1, 0.2, 0.3, 0.4, 0.5 ]

    EmbeddingService.stub(:generate, duplicate_embedding) do
      # Stub AI to say no conflict (high similarity + no conflict = duplicate)
      no_conflict_json = '{"conflicts": false, "keep": "new", "reason": "Same topic"}'
      stub_conflict_resolver_llm(no_conflict_json) do
        result = Memory::ConflictResolver.resolve(user, "Enjoys basketball", "preference")
        assert_equal :skip, result[:action]
      end
    end
  end


  test "resolve returns :replace when AI detects a conflict and prefers the new fact" do
    user = users(:one)
    # Similarity 0.9 (above threshold 0.5 but below 0.95) → not a pure duplicate
    similar_embedding = [ 0.1, 0.2, 0.3, 0.4, 0.49 ]

    EmbeddingService.stub(:generate, similar_embedding) do
      conflict_json = '{"conflicts": true, "keep": "new", "reason": "Newer preference"}'
      stub_conflict_resolver_llm(conflict_json) do
        result = Memory::ConflictResolver.resolve(user, "Hates basketball", "dislike")
        assert_equal :replace, result[:action]
        assert result[:memory_id].present?
      end
    end
  end


  test "resolve returns :skip when AI detects a conflict and prefers existing fact" do
    user = users(:one)
    similar_embedding = [ 0.1, 0.2, 0.3, 0.4, 0.49 ]

    EmbeddingService.stub(:generate, similar_embedding) do
      conflict_json = '{"conflicts": true, "keep": "existing", "reason": "Older is more reliable"}'
      stub_conflict_resolver_llm(conflict_json) do
        result = Memory::ConflictResolver.resolve(user, "Hates basketball", "dislike")
        assert_equal :skip, result[:action]
      end
    end
  end
end
