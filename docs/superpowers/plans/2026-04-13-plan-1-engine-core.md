# Plan 1: Engine Core

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the Rails engine gem skeleton with configuration system, all database migrations, and Active Record models.

**Architecture:** A standard Rails engine gem (`solid_agent`) that mounts into any Rails 8+ app. Configuration via a global `SolidAgent.configure` block. SQLite-first migrations for conversations, traces, spans, messages, and memory entries.

**Tech Stack:** Ruby 3.3+, Rails 8.0+, SQLite, Minitest

---

## File Structure

```
solid_agent/
├── solid_agent.gemspec
├── lib/
│   ├── solid_agent.rb
│   └── solid_agent/
│       ├── engine.rb
│       ├── configuration.rb
│       ├── model.rb
│       └── models/
│           ├── open_ai.rb
│           ├── anthropic.rb
│           └── google.rb
├── db/migrate/
│   ├── 001_create_solid_agent_conversations.rb
│   ├── 002_create_solid_agent_traces.rb
│   ├── 003_create_solid_agent_spans.rb
│   ├── 004_create_solid_agent_messages.rb
│   └── 005_create_solid_agent_memory_entries.rb
├── app/models/solid_agent/
│   ├── application_record.rb
│   ├── conversation.rb
│   ├── trace.rb
│   ├── span.rb
│   ├── message.rb
│   └── memory_entry.rb
├── test/
│   ├── test_helper.rb
│   ├── solid_agent_test.rb
│   ├── configuration_test.rb
│   └── models/
│       ├── conversation_test.rb
│       ├── trace_test.rb
│       ├── span_test.rb
│       ├── message_test.rb
│       └── memory_entry_test.rb
├── lib/generators/
│   └── solid_agent/
│       └── install/
│           ├── install_generator.rb
│           └── templates/
│               └── solid_agent.rb.tt
└── config/
    └── routes.rb
```

---

### Task 1: Gem Skeleton

**Files:**
- Create: `solid_agent.gemspec`
- Create: `lib/solid_agent.rb`
- Create: `lib/solid_agent/engine.rb`
- Create: `config/routes.rb`
- Create: `Gemfile`
- Create: `Rakefile`
- Test: `test/test_helper.rb`
- Test: `test/solid_agent_test.rb`

- [ ] **Step 1: Create gem directory structure**

```bash
mkdir -p lib/solid_agent lib/solid_agent/models db/migrate app/models/solid_agent test/models config lib/generators/solid_agent/install/templates
```

- [ ] **Step 2: Create Gemfile**

```ruby
# Gemfile
source "https://rubygems.org"

gemspec

gem "rails", "~> 8.0"
gem "sqlite3", "~> 2.0"
gem "solid_queue", "~> 1.0"

group :test do
  gem "minitest", "~> 5.0"
  gem "minitest-reporters"
end
```

- [ ] **Step 3: Create gemspec**

```ruby
# solid_agent.gemspec
Gem::Specification.new do |spec|
  spec.name = "solid_agent"
  spec.version = "0.1.0"
  spec.authors = ["Solid Agent"]
  spec.summary = "A plug-and-play Rails engine for agentic capabilities using the Solid stack"
  spec.description = "Zero-config agent framework backed by SQLite, Solid Queue, and Solid Cable"
  spec.license = "MIT"

  spec.files = Dir.glob("{app,config,db,lib}/**/*") + %w[README.md]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.3.0"

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "solid_queue", ">= 1.0"

  spec.add_development_dependency "sqlite3", "~> 2.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
```

- [ ] **Step 4: Create engine entry point**

```ruby
# lib/solid_agent.rb
require "solid_agent/engine"
require "solid_agent/configuration"
require "solid_agent/model"
require "solid_agent/models/open_ai"
require "solid_agent/models/anthropic"
require "solid_agent/models/google"

module SolidAgent
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
```

- [ ] **Step 5: Create engine class**

```ruby
# lib/solid_agent/engine.rb
module SolidAgent
  class Engine < ::Rails::Engine
    isolate_namespace SolidAgent

    config.generators do |g|
      g.test_framework :minitest
      g.fixture_replacement :factory_bot, dir: "test/factories"
    end

    initializer "solid_agent.config" do
      config.to_prepare do
        SolidAgent.configuration.validate! if SolidAgent.configuration
      end
    end
  end
end
```

- [ ] **Step 6: Create config/routes.rb**

```ruby
# config/routes.rb
SolidAgent::Engine.routes.draw do
  # Dashboard routes will be added in Plan 7
end
```

- [ ] **Step 7: Create Rakefile**

```ruby
# Rakefile
require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test
```

- [ ] **Step 8: Create test helper**

```ruby
# test/test_helper.rb
require "bundler/setup"

ENV["RAILS_ENV"] = "test"

require "active_record"
require "active_support"
require "active_support/test_case"

require "rails"
require "solid_agent"

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

ActiveSupport::TestCase.test_order = :random

ActiveRecord::Schema.define do
  create_table :solid_agent_conversations, force: true do |t|
    t.string :agent_class
    t.string :status, default: "active"
    t.json :metadata, default: {}
    t.timestamps
  end

  create_table :solid_agent_traces, force: true do |t|
    t.integer :conversation_id, null: false
    t.integer :parent_trace_id
    t.string :agent_class
    t.string :trace_type
    t.string :status, default: "pending"
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
    t.integer :trace_id, null: false
    t.integer :parent_span_id
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
    t.integer :conversation_id, null: false
    t.integer :trace_id
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
    t.integer :conversation_id
    t.string :agent_class
    t.string :entry_type
    t.text :content
    t.binary :embedding
    t.float :relevance_score
    t.timestamps
  end

  add_foreign_key :solid_agent_traces, :solid_agent_conversations, column: :conversation_id
  add_foreign_key :solid_agent_traces, :solid_agent_traces, column: :parent_trace_id
  add_foreign_key :solid_agent_spans, :solid_agent_traces, column: :trace_id
  add_foreign_key :solid_agent_spans, :solid_agent_spans, column: :parent_span_id
  add_foreign_key :solid_agent_messages, :solid_agent_conversations, column: :conversation_id
  add_foreign_key :solid_agent_memory_entries, :solid_agent_conversations, column: :conversation_id
end

require_relative "../app/models/solid_agent/application_record"
require_relative "../app/models/solid_agent/conversation"
require_relative "../app/models/solid_agent/trace"
require_relative "../app/models/solid_agent/span"
require_relative "../app/models/solid_agent/message"
require_relative "../app/models/solid_agent/memory_entry"
```

- [ ] **Step 9: Write test for module loading**

```ruby
# test/solid_agent_test.rb
require "test_helper"

class SolidAgentTest < ActiveSupport::TestCase
  test "module is defined" do
    assert defined?(SolidAgent)
  end

  test "has configuration object" do
    assert_instance_of SolidAgent::Configuration, SolidAgent.configuration
  end

  test "configure yields configuration" do
    SolidAgent.configure do |config|
      config.default_provider = :openai
    end

    assert_equal :openai, SolidAgent.configuration.default_provider
  end

  test "reset configuration" do
    SolidAgent.configure { |c| c.default_provider = :anthropic }
    SolidAgent.reset_configuration!
    assert_equal :openai, SolidAgent.configuration.default_provider
  end
end
```

- [ ] **Step 10: Run tests to verify they fail**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/solid_agent_test.rb`
Expected: FAIL — `SolidAgent::Configuration` not defined yet

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: add gem skeleton with engine, test helper, and basic module"
```

---

### Task 2: Configuration System

**Files:**
- Create: `lib/solid_agent/configuration.rb`
- Test: `test/configuration_test.rb`

- [ ] **Step 1: Write failing tests for configuration**

```ruby
# test/configuration_test.rb
require "test_helper"

class ConfigurationTest < ActiveSupport::TestCase
  def setup
    @config = SolidAgent::Configuration.new
  end

  test "has default provider" do
    assert_equal :openai, @config.default_provider
  end

  test "has default model" do
    assert_equal SolidAgent::Models::OpenAi::GPT_4O, @config.default_model
  end

  test "dashboard is enabled by default" do
    assert_equal true, @config.dashboard_enabled
  end

  test "default dashboard route prefix" do
    assert_equal "solid_agent", @config.dashboard_route_prefix
  end

  test "default vector store is sqlite_vec" do
    assert_equal :sqlite_vec, @config.vector_store
  end

  test "default http adapter is net_http" do
    assert_equal :net_http, @config.http_adapter
  end

  test "default trace retention is 30 days" do
    assert_equal 30.days, @config.trace_retention
  end

  test "providers config is a hash" do
    assert_instance_of Hash, @config.providers
  end

  test "mcp_clients config is a hash" do
    assert_instance_of Hash, @config.mcp_clients
  end

  test "validates with valid config" do
    @config.default_provider = :openai
    assert_nil @config.validate!
  end

  test "accepts custom http adapter class" do
    custom_adapter = Class.new { def call(req); end }
    @config.http_adapter = custom_adapter
    assert_equal custom_adapter, @config.http_adapter
  end

  test "accepts custom vector store class" do
    custom_store = Class.new { def upsert(**); end }
    @config.vector_store = custom_store
    assert_equal custom_store, @config.vector_store
  end

  test "embedding configuration defaults" do
    assert_equal :openai, @config.embedding_provider
    assert_equal "text-embedding-3-small", @config.embedding_model
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/configuration_test.rb`
Expected: FAIL — `SolidAgent::Configuration` not defined

- [ ] **Step 3: Implement Configuration**

```ruby
# lib/solid_agent/configuration.rb
module SolidAgent
  class Configuration
    attr_accessor :default_provider, :default_model, :dashboard_enabled,
                  :dashboard_route_prefix, :vector_store, :embedding_provider,
                  :embedding_model, :http_adapter, :trace_retention,
                  :providers, :mcp_clients

    def initialize
      @default_provider = :openai
      @default_model = Models::OpenAi::GPT_4O
      @dashboard_enabled = true
      @dashboard_route_prefix = "solid_agent"
      @vector_store = :sqlite_vec
      @embedding_provider = :openai
      @embedding_model = "text-embedding-3-small"
      @http_adapter = :net_http
      @trace_retention = 30.days
      @providers = {}
      @mcp_clients = {}
    end

    def validate!
      unless @default_provider.is_a?(Symbol) || @default_provider.nil?
        raise Error, "default_provider must be a symbol"
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/configuration_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add configuration system with defaults"
```

---

### Task 3: Model Constants

**Files:**
- Create: `lib/solid_agent/model.rb`
- Create: `lib/solid_agent/models/open_ai.rb`
- Create: `lib/solid_agent/models/anthropic.rb`
- Create: `lib/solid_agent/models/google.rb`

- [ ] **Step 1: Write failing tests for Model**

```ruby
# test/models/model_test.rb
require "test_helper"

class ModelTest < ActiveSupport::TestCase
  test "Model stores id" do
    model = SolidAgent::Model.new("gpt-4o", context_window: 128_000, max_output: 16_384)
    assert_equal "gpt-4o", model.id
  end

  test "Model stores context_window" do
    model = SolidAgent::Model.new("gpt-4o", context_window: 128_000, max_output: 16_384)
    assert_equal 128_000, model.context_window
  end

  test "Model stores max_output" do
    model = SolidAgent::Model.new("gpt-4o", context_window: 128_000, max_output: 16_384)
    assert_equal 16_384, model.max_output
  end

  test "OpenAI GPT_4O constant" do
    assert_equal "gpt-4o", SolidAgent::Models::OpenAi::GPT_4O.id
    assert_equal 128_000, SolidAgent::Models::OpenAi::GPT_4O.context_window
  end

  test "Anthropic CLAUDE_SONNET_4 constant" do
    assert_equal "claude-sonnet-4-20250514", SolidAgent::Models::Anthropic::CLAUDE_SONNET_4.id
    assert_equal 200_000, SolidAgent::Models::Anthropic::CLAUDE_SONNET_4.context_window
  end

  test "Google GEMINI_2_5_PRO constant" do
    assert_equal "gemini-2.5-pro", SolidAgent::Models::Google::GEMINI_2_5_PRO.id
    assert_equal 1_000_000, SolidAgent::Models::Google::GEMINI_2_5_PRO.context_window
  end

  test "Model is frozen" do
    model = SolidAgent::Models::OpenAi::GPT_4O
    assert model.frozen?
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/models/model_test.rb`
Expected: FAIL — `SolidAgent::Model` not defined

- [ ] **Step 3: Implement Model**

```ruby
# lib/solid_agent/model.rb
module SolidAgent
  class Model
    attr_reader :id, :context_window, :max_output

    def initialize(id, context_window:, max_output:)
      @id = id.freeze
      @context_window = context_window
      @max_output = max_output
      freeze
    end

    def to_s
      id
    end
  end
end
```

- [ ] **Step 4: Implement OpenAI models**

```ruby
# lib/solid_agent/models/open_ai.rb
module SolidAgent
  module Models
    module OpenAi
      GPT_4O = Model.new("gpt-4o", context_window: 128_000, max_output: 16_384).freeze
      GPT_4O_MINI = Model.new("gpt-4o-mini", context_window: 128_000, max_output: 16_384).freeze
      O3 = Model.new("o3", context_window: 200_000, max_output: 100_000).freeze
      O3_MINI = Model.new("o3-mini", context_window: 200_000, max_output: 100_000).freeze
    end
  end
end
```

- [ ] **Step 5: Implement Anthropic models**

```ruby
# lib/solid_agent/models/anthropic.rb
module SolidAgent
  module Models
    module Anthropic
      CLAUDE_SONNET_4 = Model.new("claude-sonnet-4-20250514", context_window: 200_000, max_output: 16_384).freeze
      CLAUDE_OPUS_4 = Model.new("claude-opus-4-20250514", context_window: 200_000, max_output: 32_000).freeze
    end
  end
end
```

- [ ] **Step 6: Implement Google models**

```ruby
# lib/solid_agent/models/google.rb
module SolidAgent
  module Models
    module Google
      GEMINI_2_5_PRO = Model.new("gemini-2.5-pro", context_window: 1_000_000, max_output: 8_192).freeze
      GEMINI_2_5_FLASH = Model.new("gemini-2.5-flash", context_window: 1_000_000, max_output: 8_192).freeze
    end
  end
end
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/models/model_test.rb`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add Model class and provider model constants"
```

---

### Task 4: Active Record Models — Conversation

**Files:**
- Create: `app/models/solid_agent/application_record.rb`
- Create: `app/models/solid_agent/conversation.rb`
- Create: `db/migrate/001_create_solid_agent_conversations.rb`
- Test: `test/models/conversation_test.rb`

- [ ] **Step 1: Write failing tests for Conversation**

```ruby
# test/models/conversation_test.rb
require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "creates a conversation" do
    conversation = SolidAgent::Conversation.create!(agent_class: "ResearchAgent")
    assert_equal "ResearchAgent", conversation.agent_class
    assert_equal "active", conversation.status
  end

  test "has many traces" do
    conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
    SolidAgent::Trace.create!(conversation: conversation, agent_class: "TestAgent", trace_type: :agent_run)
    assert_equal 1, conversation.traces.count
  end

  test "has many messages" do
    conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
    SolidAgent::Message.create!(conversation: conversation, role: "user", content: "Hello")
    assert_equal 1, conversation.messages.count
  end

  test "has many memory entries" do
    conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
    SolidAgent::MemoryEntry.create!(conversation: conversation, agent_class: "TestAgent", entry_type: :observation, content: "User prefers concise answers")
    assert_equal 1, conversation.memory_entries.count
  end

  test "can be archived" do
    conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
    conversation.archive!
    assert_equal "archived", conversation.status
  end

  test "total token usage across traces" do
    conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
    SolidAgent::Trace.create!(conversation: conversation, agent_class: "TestAgent", trace_type: :agent_run, usage: { "input_tokens" => 100, "output_tokens" => 50 })
    SolidAgent::Trace.create!(conversation: conversation, agent_class: "TestAgent", trace_type: :agent_run, usage: { "input_tokens" => 200, "output_tokens" => 80 })
    assert_equal 430, conversation.total_tokens
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/models/conversation_test.rb`
Expected: FAIL — `SolidAgent::ApplicationRecord` not defined

- [ ] **Step 3: Implement ApplicationRecord**

```ruby
# app/models/solid_agent/application_record.rb
module SolidAgent
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
```

- [ ] **Step 4: Implement Conversation**

```ruby
# app/models/solid_agent/conversation.rb
module SolidAgent
  class Conversation < ApplicationRecord
    has_many :traces, class_name: "SolidAgent::Trace", dependent: :destroy
    has_many :messages, class_name: "SolidAgent::Message", dependent: :destroy
    has_many :memory_entries, class_name: "SolidAgent::MemoryEntry", dependent: :destroy

    def archive!
      update!(status: "archived")
    end

    def total_tokens
      traces.sum { |t| (t.usage["input_tokens"] || 0) + (t.usage["output_tokens"] || 0) }
    end
  end
end
```

- [ ] **Step 5: Create migration**

```ruby
# db/migrate/001_create_solid_agent_conversations.rb
class CreateSolidAgentConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_agent_conversations do |t|
      t.string :agent_class
      t.string :status, default: "active"
      t.json :metadata, default: {}
      t.timestamps
    end
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/models/conversation_test.rb`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add Conversation model with traces, messages, and memory entries"
```

---

### Task 5: Active Record Models — Trace

**Files:**
- Create: `app/models/solid_agent/trace.rb`
- Create: `db/migrate/002_create_solid_agent_traces.rb`
- Test: `test/models/trace_test.rb`

- [ ] **Step 1: Write failing tests for Trace**

```ruby
# test/models/trace_test.rb
require "test_helper"

class TraceTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
  end

  test "creates a trace" do
    trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: "ResearchAgent",
      trace_type: :agent_run
    )
    assert_equal "pending", trace.status
    assert_equal "ResearchAgent", trace.agent_class
  end

  test "has many spans" do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: "TestAgent", trace_type: :agent_run)
    SolidAgent::Span.create!(trace: trace, span_type: :think, name: "think_1")
    assert_equal 1, trace.spans.count
  end

  test "parent trace relationship" do
    parent = SolidAgent::Trace.create!(conversation: @conversation, agent_class: "Supervisor", trace_type: :agent_run)
    child = SolidAgent::Trace.create!(conversation: @conversation, agent_class: "Worker", trace_type: :delegate, parent_trace: parent)
    assert_equal parent.id, child.parent_trace_id
    assert_includes parent.child_traces, child
  end

  test "status transitions" do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: "TestAgent", trace_type: :agent_run)
    assert trace.may_start?
    trace.start!
    assert_equal "running", trace.status
    assert trace.may_complete?
    trace.complete!
    assert_equal "completed", trace.status
  end

  test "can fail" do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: "TestAgent", trace_type: :agent_run)
    trace.start!
    trace.fail!("Something went wrong")
    assert_equal "failed", trace.status
    assert_equal "Something went wrong", trace.error
  end

  test "can pause and resume" do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: "TestAgent", trace_type: :agent_run)
    trace.start!
    trace.pause!
    assert_equal "paused", trace.status
    trace.resume!
    assert_equal "running", trace.status
  end

  test "tracks duration" do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: "TestAgent", trace_type: :agent_run)
    trace.update!(started_at: 10.seconds.ago, completed_at: Time.current)
    assert trace.duration > 0
  end

  test "token usage from usage JSON" do
    trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: "TestAgent",
      trace_type: :agent_run,
      usage: { "input_tokens" => 500, "output_tokens" => 250 }
    )
    assert_equal 750, trace.total_tokens
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/models/trace_test.rb`
Expected: FAIL — `SolidAgent::Trace` not defined

- [ ] **Step 3: Implement Trace**

```ruby
# app/models/solid_agent/trace.rb
module SolidAgent
  class Trace < ApplicationRecord
    belongs_to :conversation, class_name: "SolidAgent::Conversation"
    belongs_to :parent_trace, class_name: "SolidAgent::Trace", optional: true
    has_many :child_traces, class_name: "SolidAgent::Trace", foreign_key: :parent_trace_id, dependent: :nullify
    has_many :spans, class_name: "SolidAgent::Span", dependent: :destroy

    STATUSES = %w[pending running completed failed paused].freeze

    validates :status, inclusion: { in: STATUSES }

    def start!
      update!(status: "running", started_at: Time.current)
    end

    def complete!
      update!(status: "completed", completed_at: Time.current)
    end

    def fail!(error_message)
      update!(status: "failed", error: error_message, completed_at: Time.current)
    end

    def pause!
      update!(status: "paused")
    end

    def resume!
      update!(status: "running")
    end

    def may_start?
      status == "pending"
    end

    def may_complete?
      status == "running"
    end

    def duration
      return nil unless started_at && completed_at
      completed_at - started_at
    end

    def total_tokens
      (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
    end
  end
end
```

- [ ] **Step 4: Create migration**

```ruby
# db/migrate/002_create_solid_agent_traces.rb
class CreateSolidAgentTraces < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_agent_traces do |t|
      t.references :conversation, null: false, foreign_key: { to_table: :solid_agent_conversations }
      t.references :parent_trace, foreign_key: { to_table: :solid_agent_traces }
      t.string :agent_class
      t.string :trace_type
      t.string :status, default: "pending"
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
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/models/trace_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Trace model with status machine and parent/child relationships"
```

---

### Task 6: Active Record Models — Span

**Files:**
- Create: `app/models/solid_agent/span.rb`
- Create: `db/migrate/003_create_solid_agent_spans.rb`
- Test: `test/models/span_test.rb`

- [ ] **Step 1: Write failing tests for Span**

```ruby
# test/models/span_test.rb
require "test_helper"

class SpanTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
    @trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: "TestAgent", trace_type: :agent_run)
  end

  test "creates a span" do
    span = SolidAgent::Span.create!(trace: @trace, span_type: :think, name: "think_1")
    assert_equal "think", span.span_type
    assert_equal "think_1", span.name
  end

  test "parent span relationship" do
    parent = SolidAgent::Span.create!(trace: @trace, span_type: :act, name: "act_1")
    child = SolidAgent::Span.create!(trace: @trace, span_type: :tool_execution, name: "web_search", parent_span: parent)
    assert_equal parent.id, child.parent_span_id
    assert_includes parent.child_spans, child
  end

  test "tracks duration" do
    span = SolidAgent::Span.create!(
      trace: @trace, span_type: :think, name: "think_1",
      started_at: 2.seconds.ago, completed_at: Time.current
    )
    assert span.duration > 0
  end

  test "tracks tokens" do
    span = SolidAgent::Span.create!(
      trace: @trace, span_type: :think, name: "think_1",
      tokens_in: 500, tokens_out: 200
    )
    assert_equal 700, span.total_tokens
  end

  test "span types are valid" do
    %i[think act observe tool_execution llm_call].each do |span_type|
      span = SolidAgent::Span.create!(trace: @trace, span_type: span_type, name: "test")
      assert_equal span_type.to_s, span.span_type
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/models/span_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement Span**

```ruby
# app/models/solid_agent/span.rb
module SolidAgent
  class Span < ApplicationRecord
    belongs_to :trace, class_name: "SolidAgent::Trace"
    belongs_to :parent_span, class_name: "SolidAgent::Span", optional: true
    has_many :child_spans, class_name: "SolidAgent::Span", foreign_key: :parent_span_id, dependent: :nullify

    SPAN_TYPES = %w[think act observe tool_execution llm_call].freeze

    validates :span_type, inclusion: { in: SPAN_TYPES }

    def duration
      return nil unless started_at && completed_at
      completed_at - started_at
    end

    def total_tokens
      tokens_in + tokens_out
    end
  end
end
```

- [ ] **Step 4: Create migration**

```ruby
# db/migrate/003_create_solid_agent_spans.rb
class CreateSolidAgentSpans < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_agent_spans do |t|
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
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/models/span_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Span model with parent/child and token tracking"
```

---

### Task 7: Active Record Models — Message

**Files:**
- Create: `app/models/solid_agent/message.rb`
- Create: `db/migrate/004_create_solid_agent_messages.rb`
- Test: `test/models/message_test.rb`

- [ ] **Step 1: Write failing tests for Message**

```ruby
# test/models/message_test.rb
require "test_helper"

class MessageTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
  end

  test "creates a user message" do
    message = SolidAgent::Message.create!(
      conversation: @conversation,
      role: "user",
      content: "Hello agent"
    )
    assert_equal "user", message.role
    assert_equal "Hello agent", message.content
  end

  test "creates an assistant message with tool calls" do
    message = SolidAgent::Message.create!(
      conversation: @conversation,
      role: "assistant",
      content: nil,
      tool_calls: [
        { "id" => "call_1", "name" => "web_search", "arguments" => { "query" => "test" } }
      ]
    )
    assert_equal 1, message.tool_calls.length
    assert_equal "web_search", message.tool_calls.first["name"]
  end

  test "creates a tool response message" do
    message = SolidAgent::Message.create!(
      conversation: @conversation,
      role: "tool",
      content: "Search results here",
      tool_call_id: "call_1"
    )
    assert_equal "tool", message.role
    assert_equal "call_1", message.tool_call_id
  end

  test "roles are validated" do
    message = SolidAgent::Message.new(
      conversation: @conversation,
      role: "invalid",
      content: "test"
    )
    assert_not message.valid?
  end

  test "optional trace association" do
    trace = SolidAgent::Trace.create!(conversation: @conversation, agent_class: "TestAgent", trace_type: :agent_run)
    message = SolidAgent::Message.create!(
      conversation: @conversation,
      trace: trace,
      role: "assistant",
      content: "response"
    )
    assert_equal trace, message.trace
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/models/message_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement Message**

```ruby
# app/models/solid_agent/message.rb
module SolidAgent
  class Message < ApplicationRecord
    belongs_to :conversation, class_name: "SolidAgent::Conversation"
    belongs_to :trace, class_name: "SolidAgent::Trace", optional: true

    ROLES = %w[system user assistant tool].freeze

    validates :role, inclusion: { in: ROLES }
    validates :content, presence: true, if: -> { role.in?(%w[system user tool]) }
  end
end
```

- [ ] **Step 4: Create migration**

```ruby
# db/migrate/004_create_solid_agent_messages.rb
class CreateSolidAgentMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_agent_messages do |t|
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
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/models/message_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Message model with role validation and tool call support"
```

---

### Task 8: Active Record Models — MemoryEntry

**Files:**
- Create: `app/models/solid_agent/memory_entry.rb`
- Create: `db/migrate/005_create_solid_agent_memory_entries.rb`
- Test: `test/models/memory_entry_test.rb`

- [ ] **Step 1: Write failing tests for MemoryEntry**

```ruby
# test/models/memory_entry_test.rb
require "test_helper"

class MemoryEntryTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
  end

  test "creates an observation entry" do
    entry = SolidAgent::MemoryEntry.create!(
      conversation: @conversation,
      agent_class: "ResearchAgent",
      entry_type: :observation,
      content: "User prefers bullet points"
    )
    assert_equal "observation", entry.entry_type
  end

  test "entry types are validated" do
    entry = SolidAgent::MemoryEntry.new(
      conversation: @conversation,
      agent_class: "TestAgent",
      entry_type: "invalid",
      content: "test"
    )
    assert_not entry.valid?
  end

  test "scope by agent class" do
    SolidAgent::MemoryEntry.create!(conversation: @conversation, agent_class: "AgentA", entry_type: :observation, content: "a")
    SolidAgent::MemoryEntry.create!(conversation: @conversation, agent_class: "AgentB", entry_type: :observation, content: "b")
    assert_equal 1, SolidAgent::MemoryEntry.for_agent("AgentA").count
  end

  test "scope by entry type" do
    SolidAgent::MemoryEntry.create!(conversation: @conversation, agent_class: "TestAgent", entry_type: :observation, content: "a")
    SolidAgent::MemoryEntry.create!(conversation: @conversation, agent_class: "TestAgent", entry_type: :fact, content: "b")
    assert_equal 1, SolidAgent::MemoryEntry.observations.count
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/models/memory_entry_test.rb`
Expected: FAIL

- [ ] **Step 3: Implement MemoryEntry**

```ruby
# app/models/solid_agent/memory_entry.rb
module SolidAgent
  class MemoryEntry < ApplicationRecord
    belongs_to :conversation, class_name: "SolidAgent::Conversation", optional: true

    ENTRY_TYPES = %w[observation fact preference].freeze

    validates :entry_type, inclusion: { in: ENTRY_TYPES }
    validates :content, presence: true

    scope :for_agent, ->(agent_class) { where(agent_class: agent_class) }
    scope :observations, -> { where(entry_type: :observation) }
    scope :facts, -> { where(entry_type: :fact) }
    scope :preferences, -> { where(entry_type: :preference) }
  end
end
```

- [ ] **Step 4: Create migration**

```ruby
# db/migrate/005_create_solid_agent_memory_entries.rb
class CreateSolidAgentMemoryEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_agent_memory_entries do |t|
      t.references :conversation, foreign_key: { to_table: :solid_agent_conversations }
      t.string :agent_class
      t.string :entry_type
      t.text :content
      t.binary :embedding
      t.float :relevance_score
      t.timestamps
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/models/memory_entry_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Run full test suite**

Run: `bundle exec rake test`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add MemoryEntry model with scopes and entry type validation"
```

---

### Task 9: Install Generator

**Files:**
- Create: `lib/generators/solid_agent/install/install_generator.rb`
- Create: `lib/generators/solid_agent/install/templates/solid_agent.rb.tt`

- [ ] **Step 1: Implement install generator**

```ruby
# lib/generators/solid_agent/install/install_generator.rb
module SolidAgent
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs SolidAgent into your Rails application"

      def copy_initializer
        template "solid_agent.rb.tt", "config/initializers/solid_agent.rb"
      end

      def copy_migrations
        rake "solid_agent:install:migrations"
      end

      def show_readme
        say "\nSolidAgent installed! Run `bin/rails db:migrate` to create the tables."
      end
    end
  end
end
```

- [ ] **Step 2: Create initializer template**

```ruby
# lib/generators/solid_agent/install/templates/solid_agent.rb.tt
SolidAgent.configure do |config|
  config.default_provider = :openai
  config.default_model = SolidAgent::Models::OpenAi::GPT_4O

  config.providers.openai = {
    api_key: ENV["OPENAI_API_KEY"]
  }
end
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add install generator with initializer template"
```

---

### Task 10: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rake test`
Expected: All tests PASS, 0 failures

- [ ] **Step 2: Verify gem can be built**

Run: `gem build solid_agent.gemspec`
Expected: Successfully built gem

- [ ] **Step 3: Commit any final cleanup**

```bash
git add -A
git commit -m "chore: engine core plan complete — all models, config, migrations"
```
