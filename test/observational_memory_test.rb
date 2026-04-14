require 'test_helper'

class ObservationalMemoryTest < ActiveSupport::TestCase
  def setup
    @vector_store = TestVectorStore.new
    @embedder = TestEmbedder.new
    @memory = SolidAgent::ObservationalMemory.new(
      vector_store: @vector_store,
      embedder: @embedder,
      max_entries: 5,
      retrieval_count: 3
    )
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
  end

  test 'enabled when vector_store and embedder provided' do
    assert @memory.enabled
  end

  test 'disabled when vector_store is nil' do
    memory = SolidAgent::ObservationalMemory.new(vector_store: nil, embedder: @embedder)
    refute memory.enabled
  end

  test 'disabled when embedder is nil' do
    memory = SolidAgent::ObservationalMemory.new(vector_store: @vector_store, embedder: nil)
    refute memory.enabled
  end

  test 'disabled when enabled: false' do
    memory = SolidAgent::ObservationalMemory.new(
      vector_store: @vector_store,
      embedder: @embedder,
      enabled: false
    )
    refute memory.enabled
  end

  test 'store_observation creates MemoryEntry' do
    entry = @memory.store_observation(
      agent_class: 'CreateTestAgent',
      content: 'User prefers concise answers',
      conversation: @conversation
    )

    assert_instance_of SolidAgent::MemoryEntry, entry
    assert_equal 'CreateTestAgent', entry.agent_class
    assert_equal 'observation', entry.entry_type
    assert_equal 'User prefers concise answers', entry.content
    assert_equal @conversation.id, entry.conversation_id
  end

  test 'store_observation persists to database' do
    agent = "PersistAgent_#{object_id}"
    before_count = SolidAgent::MemoryEntry.for_agent(agent).count
    @memory.store_observation(
      agent_class: agent,
      content: 'User likes examples',
      conversation: @conversation
    )

    assert_equal before_count + 1, SolidAgent::MemoryEntry.for_agent(agent).count
    assert_equal 'User likes examples', SolidAgent::MemoryEntry.last.content
  end

  test 'store_observation upserts to vector store' do
    entry = @memory.store_observation(
      agent_class: 'UpsertAgent',
      content: 'User prefers bullet points',
      conversation: @conversation
    )

    assert @vector_store.store.key?(entry.id)
  end

  test 'store_observation returns nil when disabled' do
    memory = SolidAgent::ObservationalMemory.new(vector_store: nil, embedder: @embedder)
    result = memory.store_observation(agent_class: 'TestAgent', content: 'test')
    assert_nil result
  end

  test 'store_observation without conversation is valid' do
    entry = @memory.store_observation(
      agent_class: 'NoConvAgent',
      content: 'General knowledge'
    )

    assert_instance_of SolidAgent::MemoryEntry, entry
    assert_nil entry.conversation_id
  end

  test 'retrieve_relevant returns matching entries' do
    agent = "RetrieveAgent_#{object_id}"
    @memory.store_observation(agent_class: agent, content: 'Ruby is great')
    @memory.store_observation(agent_class: agent, content: 'Python is okay')

    results = @memory.retrieve_relevant(
      agent_class: agent,
      query_text: 'Ruby is great'
    )

    assert results.length >= 1
    assert(results.any? { |e| e.content == 'Ruby is great' })
  end

  test 'retrieve_relevant filters by agent_class' do
    agent_a = "FilterA_#{object_id}"
    agent_b = "FilterB_#{object_id}"
    @memory.store_observation(agent_class: agent_a, content: 'Alpha data')
    @memory.store_observation(agent_class: agent_b, content: 'Beta data')

    results = @memory.retrieve_relevant(agent_class: agent_a, query_text: 'Alpha data')
    results.each do |entry|
      assert_equal agent_a, entry.agent_class
    end
  end

  test 'retrieve_relevant returns empty when disabled' do
    memory = SolidAgent::ObservationalMemory.new(vector_store: nil, embedder: @embedder)
    results = memory.retrieve_relevant(agent_class: 'TestAgent', query_text: 'test')
    assert_equal [], results
  end

  test 'retrieve_relevant respects limit' do
    agent = "LimitAgent_#{object_id}"
    5.times do |i|
      @memory.store_observation(agent_class: agent, content: "Observation #{i}")
    end

    results = @memory.retrieve_relevant(
      agent_class: agent,
      query_text: 'Observation',
      limit: 2
    )
    assert results.length <= 2
  end

  test 'build_system_context returns formatted string' do
    agent = "ContextAgent_#{object_id}"
    @memory.store_observation(agent_class: agent, content: 'User prefers brevity')

    context = @memory.build_system_context(
      agent_class: agent,
      query_text: 'User prefers brevity'
    )

    assert context.start_with?("## Relevant Memories\n")
    assert context.include?('User prefers brevity')
  end

  test 'build_system_context returns empty string when no matches' do
    context = @memory.build_system_context(
      agent_class: 'NonExistentAgent',
      query_text: 'nothing relevant'
    )

    assert_equal '', context
  end

  test 'build_system_context returns empty when disabled' do
    memory = SolidAgent::ObservationalMemory.new(vector_store: nil, embedder: @embedder)
    context = memory.build_system_context(agent_class: 'TestAgent', query_text: 'test')
    assert_equal '', context
  end

  test 'trims entries beyond max_entries' do
    agent = "TrimAgent_#{object_id}"
    7.times do |i|
      @memory.store_observation(agent_class: agent, content: "Entry #{i}")
    end

    count = SolidAgent::MemoryEntry.for_agent(agent).count
    assert count <= @memory.max_entries,
           "Expected at most #{@memory.max_entries} entries, got #{count}"
  end

  test 'trims oldest entries first' do
    agent = "TrimOldAgent_#{object_id}"
    first = @memory.store_observation(agent_class: agent, content: 'Oldest entry')

    5.times do |i|
      @memory.store_observation(agent_class: agent, content: "Entry #{i}")
    end

    refute SolidAgent::MemoryEntry.exists?(first.id),
           'Expected oldest entry to be trimmed'
  end

  test 'does not trim entries from other agents' do
    agent_a = "TrimA_#{object_id}"
    agent_b = "TrimB_#{object_id}"
    7.times do |i|
      @memory.store_observation(agent_class: agent_a, content: "A entry #{i}")
    end

    3.times do |i|
      @memory.store_observation(agent_class: agent_b, content: "B entry #{i}")
    end

    agent_b_count = SolidAgent::MemoryEntry.for_agent(agent_b).count
    assert_equal 3, agent_b_count,
                 'AgentB entries should not be affected by AgentA trimming'
  end

  test 'default max_entries is 500' do
    memory = SolidAgent::ObservationalMemory.new(
      vector_store: @vector_store,
      embedder: @embedder
    )
    assert_equal 500, memory.max_entries
  end

  test 'default retrieval_count is 10' do
    memory = SolidAgent::ObservationalMemory.new(
      vector_store: @vector_store,
      embedder: @embedder
    )
    assert_equal 10, memory.retrieval_count
  end
end
