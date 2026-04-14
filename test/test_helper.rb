require 'bundler/setup'
require 'minitest/autorun'

ENV['RAILS_ENV'] = 'test'

require 'active_record'
require 'active_support'
require 'active_support/test_case'
require 'rails'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

ActiveSupport::TestCase.test_order = :random

ActiveRecord::Schema.define do
  create_table :solid_agent_conversations, force: true do |t|
    t.string :agent_class
    t.string :status, default: 'active'
    t.json :metadata, default: {}
    t.timestamps
  end

  create_table :solid_agent_traces, force: true do |t|
    t.references :conversation, null: false, foreign_key: { to_table: :solid_agent_conversations }
    t.references :parent_trace, foreign_key: { to_table: :solid_agent_traces }
    t.string :agent_class
    t.string :trace_type
    t.string :status, default: 'pending'
    t.text :input
    t.text :output
    t.json :usage, default: {}
    t.integer :iteration_count, default: 0
    t.datetime :started_at
    t.datetime :completed_at
    t.text :error
    t.json :metadata, default: {}
    t.timestamps
  end

  create_table :solid_agent_spans, force: true do |t|
    t.references :trace, null: false, foreign_key: { to_table: :solid_agent_traces }
    t.references :parent_span, foreign_key: { to_table: :solid_agent_spans }
    t.string :span_type
    t.string :name
    t.string :status
    t.text :input
    t.text :output
    t.integer :tokens_in, default: 0
    t.integer :tokens_out, default: 0
    t.datetime :started_at
    t.datetime :completed_at
    t.json :metadata, default: {}
    t.timestamps
  end

  create_table :solid_agent_messages, force: true do |t|
    t.references :conversation, null: false, foreign_key: { to_table: :solid_agent_conversations }
    t.references :trace, foreign_key: { to_table: :solid_agent_traces }
    t.string :role
    t.text :content
    t.json :tool_calls, default: []
    t.string :tool_call_id
    t.integer :token_count, default: 0
    t.string :model
    t.json :metadata, default: {}
    t.datetime :created_at
  end

  create_table :solid_agent_memory_entries, force: true do |t|
    t.references :conversation, foreign_key: { to_table: :solid_agent_conversations }
    t.string :agent_class
    t.string :entry_type
    t.text :content
    t.binary :embedding
    t.float :relevance_score
    t.timestamps
  end
end

require_relative '../app/models/solid_agent/application_record'
require_relative '../app/models/solid_agent/conversation'
require_relative '../app/models/solid_agent/trace'
require_relative '../app/models/solid_agent/span'
require_relative '../app/models/solid_agent/message'
require_relative '../app/models/solid_agent/memory_entry'

require_relative '../lib/solid_agent/memory/base'
require_relative '../lib/solid_agent/memory/sliding_window'
require_relative '../lib/solid_agent/memory/full_history'
require_relative '../lib/solid_agent/memory/compaction'
require_relative '../lib/solid_agent/memory/chain'
require_relative '../lib/solid_agent/memory/registry'
require_relative '../lib/solid_agent/memory/chain_builder'

require_relative '../lib/solid_agent/vector_store/base'
require_relative '../lib/solid_agent/vector_store/sqlite_vec_adapter'

require_relative '../lib/solid_agent/embedder/base'

require_relative '../lib/solid_agent/observational_memory'

class TestEmbedder < SolidAgent::Embedder::Base
  def embed(text)
    Array.new(8) { |i| (text.hash.abs % 1000 + i) / 1000.0 }
  end
end

class TestVectorStore < SolidAgent::VectorStore::Base
  attr_reader :store

  def initialize
    @store = {}
  end

  def upsert(id:, embedding:, metadata: {})
    @store[id] = { embedding: embedding, metadata: metadata }
  end

  def query(embedding:, limit: 10, threshold: 0.5)
    results = @store.map do |id, data|
      score = cosine_similarity(embedding, data[:embedding])
      { id: id, score: score }
    end
    results.select { |r| r[:score] >= threshold }
           .sort_by { |r| -r[:score] }
           .first(limit)
  end

  def delete(id:)
    @store.delete(id)
  end

  private

  def cosine_similarity(a, b)
    dot = a.zip(b).sum { |x, y| x * y }
    mag_a = Math.sqrt(a.sum { |x| x**2 })
    mag_b = Math.sqrt(b.sum { |x| x**2 })
    return 0.0 if mag_a.zero? || mag_b.zero?

    dot / (mag_a * mag_b)
  end
end

module MemoryTestHelper
  def build_messages(count, role: 'user', token_count: 10)
    count.times.map do |i|
      SolidAgent::Message.new(
        role: role,
        content: "Message #{i + 1}",
        token_count: token_count
      )
    end
  end
end

ActiveSupport::TestCase.include(MemoryTestHelper)
