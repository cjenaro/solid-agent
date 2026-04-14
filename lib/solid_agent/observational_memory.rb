module SolidAgent
  class ObservationalMemory
    attr_reader :enabled, :max_entries, :retrieval_count

    def initialize(vector_store: nil, embedder: nil, enabled: true, max_entries: 500, retrieval_count: 10)
      @vector_store = vector_store
      @embedder = embedder
      @enabled = enabled && vector_store.present? && embedder.present?
      @max_entries = max_entries
      @retrieval_count = retrieval_count
    end

    def store_observation(agent_class:, content:, conversation: nil)
      return nil unless @enabled

      embedding = @embedder.embed(content)
      entry = SolidAgent::MemoryEntry.create!(
        agent_class: agent_class,
        content: content,
        entry_type: :observation,
        conversation: conversation
      )

      @vector_store.upsert(
        id: entry.id,
        embedding: embedding,
        metadata: { agent_class: agent_class, entry_type: 'observation' }
      )

      trim_entries!(agent_class)
      entry
    end

    def retrieve_relevant(agent_class:, query_text:, limit: nil)
      return [] unless @enabled

      limit ||= @retrieval_count
      query_embedding = @embedder.embed(query_text)
      results = @vector_store.query(embedding: query_embedding, limit: limit, threshold: 0.0)

      entry_ids = results.map { |r| r[:id] }
      entries = SolidAgent::MemoryEntry.where(id: entry_ids, agent_class: agent_class).to_a
      entries.sort_by { |e| entry_ids.index(e.id) }
    end

    def build_system_context(agent_class:, query_text:)
      return '' unless @enabled

      entries = retrieve_relevant(agent_class: agent_class, query_text: query_text)
      return '' if entries.empty?

      header = "## Relevant Memories\n"
      items = entries.map { |e| "- #{e.content}" }.join("\n")
      header + items
    end

    private

    def trim_entries!(agent_class)
      count = SolidAgent::MemoryEntry.for_agent(agent_class).count
      return unless count > @max_entries

      excess = count - @max_entries
      SolidAgent::MemoryEntry.for_agent(agent_class)
                             .order(:created_at)
                             .limit(excess)
                             .destroy_all
    end
  end
end
