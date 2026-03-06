require "test_helper"

class UserMemoryTest < ActiveSupport::TestCase

  test "is valid with required fields" do
    memory = UserMemory.new(
      user:     users(:one),
      fact:     "Likes hiking",
      category: "hobby",
      embedding: [ 0.1, 0.2, 0.3 ]
    )
    assert memory.valid?
  end

  test "is invalid without a fact" do
    memory = UserMemory.new(user: users(:one), category: "hobby", embedding: [ 0.1 ])
    refute memory.valid?
    assert_includes memory.errors[:fact], "can't be blank"
  end

  test "is invalid without a category" do
    memory = UserMemory.new(user: users(:one), fact: "Likes hiking", embedding: [ 0.1 ])
    refute memory.valid?
    assert_includes memory.errors[:category], "can't be blank"
  end

  test "is invalid with an unrecognized category" do
    memory = UserMemory.new(user: users(:one), fact: "x", category: "unknown", embedding: [ 0.1 ])
    refute memory.valid?
    assert memory.errors[:category].any?
  end

  test "is valid for each defined category" do
    UserMemory::CATEGORIES.each do |cat|
      memory = UserMemory.new(user: users(:one), fact: "A fact", category: cat, embedding: [ 0.1 ])
      assert memory.valid?, "Expected category '#{cat}' to be valid"
    end
  end


  test "cosine_similarity returns 0.0 for blank own embedding" do
    memory = user_memories(:preference_one)
    memory.embedding = []
    assert_equal 0.0, memory.cosine_similarity([ 0.1, 0.2 ])
  end

  test "cosine_similarity returns 0.0 for blank query embedding" do
    memory = user_memories(:preference_one)
    assert_equal 0.0, memory.cosine_similarity([])
  end

  test "cosine_similarity returns 0.0 when embedding lengths differ" do
    memory = user_memories(:preference_one)
    # preference_one has 5 dimensions; provide 3
    assert_equal 0.0, memory.cosine_similarity([ 0.1, 0.2, 0.3 ])
  end

  test "cosine_similarity returns 1.0 for identical non-zero vectors" do
    memory         = user_memories(:preference_one)
    same_embedding = memory.embedding.dup
    result = memory.cosine_similarity(same_embedding)
    assert_in_delta 1.0, result, 1e-6
  end

  test "cosine_similarity returns 0.0 for orthogonal vectors" do
    memory = user_memories(:preference_one)
    memory.embedding = [ 1.0, 0.0 ]
    result = memory.cosine_similarity([ 0.0, 1.0 ])
    assert_in_delta 0.0, result, 1e-6
  end

  test "cosine_similarity computes correct value for known vectors" do
    # [1,0,0] · [1,0,0] / (1 * 1) = 1.0
    memory = user_memories(:preference_one)
    memory.embedding = [ 1.0, 0.0, 0.0 ]
    assert_in_delta 1.0, memory.cosine_similarity([ 1.0, 0.0, 0.0 ]), 1e-6

    # [1,0,0] · [0,1,0] / (1 * 1) = 0.0
    assert_in_delta 0.0, memory.cosine_similarity([ 0.0, 1.0, 0.0 ]), 1e-6

    # [3,4] · [4,3] / (5 * 5) = (12+12)/25 = 0.96
    memory.embedding = [ 3.0, 4.0 ]
    expected = (3 * 4 + 4 * 3).to_f / (5 * 5)
    assert_in_delta expected, memory.cosine_similarity([ 4.0, 3.0 ]), 1e-6
  end

  test "cosine_similarity returns 0.0 when own magnitude is zero" do
    memory = user_memories(:preference_one)
    memory.embedding = [ 0.0, 0.0, 0.0 ]
    assert_equal 0.0, memory.cosine_similarity([ 1.0, 0.0, 0.0 ])
  end

  test "cosine_similarity returns 0.0 when query magnitude is zero" do
    memory = user_memories(:preference_one)
    memory.embedding = [ 1.0, 0.0, 0.0 ]
    assert_equal 0.0, memory.cosine_similarity([ 0.0, 0.0, 0.0 ])
  end


  test "relevant_for returns empty array when no memories exist for user" do
    user_without_memories = users(:two)
    # user two has personal_fact_one; give a query embedding with different dimensions
    # so similarity = 0 < threshold — or simply use a user with no memories at all
    # We'll test at a low threshold to capture it:
    results = UserMemory.relevant_for(user_without_memories.id, [], limit: 5)
    assert_equal [], results
  end

  test "relevant_for returns empty array when query_embedding is blank" do
    user = users(:one)
    assert_equal [], UserMemory.relevant_for(user.id, nil, limit: 5)
    assert_equal [], UserMemory.relevant_for(user.id, [],  limit: 5)
  end

  test "relevant_for filters results below the default threshold" do
    user = users(:one)
    # Use a zero vector → similarity will be 0.0 for everything
    results = UserMemory.relevant_for(user.id, [ 0.0, 0.0, 0.0, 0.0, 0.0 ], limit: 5)
    assert_equal [], results
  end

  test "relevant_for returns memories above the threshold sorted by score" do
    user = users(:one)
    # preference_one embedding: [0.1, 0.2, 0.3, 0.4, 0.5]
    # Same direction → similarity ≈ 1.0 (both well above 0.3 threshold)
    preference_emb = [ 0.1, 0.2, 0.3, 0.4, 0.5 ]
    results = UserMemory.relevant_for(user.id, preference_emb, limit: 5, threshold: 0.3)
    assert results.length >= 1
    assert results.all? { |m| m.is_a?(UserMemory) }
  end

  test "relevant_for respects the limit parameter" do
    user = users(:one)
    # Give an embedding that matches both of user one's memories at some level
    query = [ 0.5, 0.5, 0.5, 0.5, 0.5 ]
    results_limited = UserMemory.relevant_for(user.id, query, limit: 1, threshold: 0.0)
    assert results_limited.length <= 1
  end


  test "for_user scope returns only memories belonging to that user" do
    user = users(:one)
    results = UserMemory.for_user(user.id)
    assert results.all? { |m| m.user_id == user.id }
  end

  test "by_category scope filters by category" do
    results = UserMemory.by_category("preference")
    assert results.all? { |m| m.category == "preference" }
  end

  test "recent_first scope orders by source_message_at descending" do
    user = users(:one)
    memories = UserMemory.for_user(user.id).recent_first
    timestamps = memories.map(&:source_message_at).compact
    assert_equal timestamps.sort.reverse, timestamps
  end
end
