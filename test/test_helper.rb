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
    t.string :name
    t.string :span_type
    t.timestamps
  end
end

require_relative '../app/models/solid_agent/application_record'
require_relative '../app/models/solid_agent/conversation'
require_relative '../app/models/solid_agent/trace'
require_relative '../app/models/solid_agent/span'
