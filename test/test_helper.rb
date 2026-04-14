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
