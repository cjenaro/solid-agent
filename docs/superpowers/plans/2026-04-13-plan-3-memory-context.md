# Plan 3: Memory & Context System

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement pluggable memory strategies (sliding window, full history, compaction, chained), a vector store interface with sqlite-vec adapter, and observational memory for cross-conversation knowledge retrieval.

**Architecture:** Memory strategies are Ruby classes under `SolidAgent::Memory::` inheriting from a common base. Each strategy implements `filter(messages)` and `compact!(messages)`. The base class composes these into `build_context(messages, system_prompt:)`. Strategies are resolved by symbol via a Registry. The vector store is a pluggable interface with a built-in sqlite-vec adapter. ObservationalMemory manages cross-conversation knowledge using embeddings stored in the existing `solid_agent_memory_entries` table and a vector store for similarity search.

**Tech Stack:** Ruby 3.3+, Rails 8.0+, SQLite, Minitest

---

## File Structure

```
lib/solid_agent/
├── memory/
│   ├── base.rb
│   ├── sliding_window.rb
│   ├── full_history.rb
│   ├── compaction.rb
│   ├── chain.rb
│   ├── registry.rb
│   └── chain_builder.rb
├── vector_store/
│   ├── base.rb
│   └── sqlite_vec_adapter.rb
├── embedder/
│   └── base.rb
└── observational_memory.rb

test/
├── memory/
│   ├── base_test.rb
│   ├── sliding_window_test.rb
│   ├── full_history_test.rb
│   ├── compaction_test.rb
│   ├── chain_test.rb
│   └── registry_test.rb
├── vector_store/
│   ├── base_test.rb
│   └── sqlite_vec_adapter_test.rb
├── embedder/
│   └── base_test.rb
└── observational_memory_test.rb
```

---

### Task 1: Test Helper Updates & Memory::Base

**Files:**
- Update: `test/test_helper.rb`
- Create: `lib/solid_agent/memory/base.rb`
- Test: `test/memory/base_test.rb`

- [ ] **Step 1: Update test_helper with memory requires and test doubles**

Add the following to the bottom of `test/test_helper.rb` (after the existing model requires):

```ruby
# test/test_helper.rb — append after existing requires

# Memory strategies
require_relative "../lib/solid_agent/memory/base"
require_relative "../lib/solid_agent/memory/sliding_window"
require_relative "../lib/solid_agent/memory/full_history"
require_relative "../lib/solid_agent/memory/compaction"
require_relative "../lib/solid_agent/memory/chain"
require_relative "../lib/solid_agent/memory/registry"
require_relative "../lib/solid_agent/memory/chain_builder"

# Vector store
require_relative "../lib/solid_agent/vector_store/base"
require_relative "../lib/solid_agent/vector_store/sqlite_vec_adapter"

# Embedder
require_relative "../lib/solid_agent/embedder/base"

# Observational memory
require_relative "../lib/solid_agent/observational_memory"

# Test doubles
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
  def build_messages(count, role: "user", token_count: 10)
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
```

- [ ] **Step 2: Write failing tests for Memory::Base**

```ruby
# test/memory/base_test.rb
require "test_helper"

class MemoryBaseTest < ActiveSupport::TestCase
  def setup
    @base = SolidAgent::Memory::Base.new
  end

  test "build_context raises NotImplementedError" do
    messages = build_messages(3)
    assert_raises(NotImplementedError) do
      @base.build_context(messages, system_prompt: "You are helpful")
    end
  end

  test "compact! raises NotImplementedError" do
    messages = build_messages(3)
    assert_raises(NotImplementedError) do
      @base.compact!(messages)
    end
  end

  test "filter returns messages unchanged by default" do
    messages = build_messages(3)
    result = @base.filter(messages)
    assert_equal messages, result
  end

  test "build_system_message creates system Message" do
    msg = @base.send(:build_system_message, "Be helpful")
    assert_instance_of SolidAgent::Message, msg
    assert_equal "system", msg.role
    assert_equal "Be helpful", msg.content
  end

  test "total_token_count sums message token counts" do
    messages = build_messages(3, token_count: 10)
    assert_equal 30, @base.send(:total_token_count, messages)
  end

  test "total_token_count handles nil token_count" do
    messages = [
      SolidAgent::Message.new(role: "user", content: "hi", token_count: 5),
      SolidAgent::Message.new(role: "user", content: "hello")
    ]
    assert_equal 5, @base.send(:total_token_count, messages)
  end

  test "build_context with system prompt prepends system message" do
    strategy = Class.new(SolidAgent::Memory::Base) do
      def filter(messages)
        messages
      end

      def compact!(messages)
        messages
      end
    end.new

    messages = build_messages(2)
    result = strategy.build_context(messages, system_prompt: "Be helpful")
    assert_equal 3, result.length
    assert_equal "system", result.first.role
    assert_equal "Be helpful", result.first.content
    assert_equal "Message 1", result[1].content
  end

  test "build_context without system prompt returns filtered only" do
    strategy = Class.new(SolidAgent::Memory::Base) do
      def filter(messages)
        messages
      end

      def compact!(messages)
        messages
      end
    end.new

    messages = build_messages(2)
    result = strategy.build_context(messages, system_prompt: nil)
    assert_equal 2, result.length
  end

  test "build_context ignores empty system prompt" do
    strategy = Class.new(SolidAgent::Memory::Base) do
      def filter(messages)
        messages
      end

      def compact!(messages)
        messages
      end
    end.new

    messages = build_messages(2)
    result = strategy.build_context(messages, system_prompt: "")
    assert_equal 2, result.length
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/memory/base_test.rb`
Expected: FAIL — `SolidAgent::Memory::Base` not defined

- [ ] **Step 4: Implement Memory::Base**

```ruby
# lib/solid_agent/memory/base.rb
module SolidAgent
  module Memory
    class Base
      def initialize(**options)
      end

      def filter(messages)
        messages
      end

      def build_context(messages, system_prompt:)
        result = filter(messages)
        if system_prompt && !system_prompt.empty?
          [build_system_message(system_prompt)] + result
        else
          result
        end
      end

      def compact!(messages)
        raise NotImplementedError, "#{self.class}#compact! must be implemented"
      end

      private

      def build_system_message(content)
        SolidAgent::Message.new(role: "system", content: content)
      end

      def total_token_count(messages)
        messages.sum { |m| m.token_count.to_i }
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/memory/base_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Memory::Base with interface, filter, and build_context"
```

---

### Task 2: Sliding Window Strategy

**Files:**
- Create: `lib/solid_agent/memory/sliding_window.rb`
- Test: `test/memory/sliding_window_test.rb`

- [ ] **Step 1: Write failing tests for SlidingWindow**

```ruby
# test/memory/sliding_window_test.rb
require "test_helper"

class SlidingWindowTest < ActiveSupport::TestCase
  def setup
    @strategy = SolidAgent::Memory::SlidingWindow.new(max_messages: 5)
  end

  test "default max_messages is 50" do
    strategy = SolidAgent::Memory::SlidingWindow.new
    assert_equal 50, strategy.max_messages
  end

  test "custom max_messages" do
    strategy = SolidAgent::Memory::SlidingWindow.new(max_messages: 10)
    assert_equal 10, strategy.max_messages
  end

  test "filter returns last N messages" do
    messages = build_messages(10)
    result = @strategy.filter(messages)
    assert_equal 5, result.length
    assert_equal "Message 6", result.first.content
    assert_equal "Message 10", result.last.content
  end

  test "filter returns all messages when under limit" do
    messages = build_messages(3)
    result = @strategy.filter(messages)
    assert_equal 3, result.length
  end

  test "filter returns all when count equals max" do
    messages = build_messages(5)
    result = @strategy.filter(messages)
    assert_equal 5, result.length
  end

  test "build_context adds system prompt and filters" do
    messages = build_messages(10)
    result = @strategy.build_context(messages, system_prompt: "You are helpful")
    assert_equal 6, result.length
    assert_equal "system", result.first.role
    assert_equal "Message 6", result[1].content
  end

  test "compact! returns last N messages" do
    messages = build_messages(10)
    result = @strategy.compact!(messages)
    assert_equal 5, result.length
    assert_equal "Message 6", result.first.content
  end

  test "compact! with under-limit messages returns all" do
    messages = build_messages(3)
    result = @strategy.compact!(messages)
    assert_equal 3, result.length
  end

  test "handles empty messages" do
    result = @strategy.filter([])
    assert_equal [], result
  end

  test "handles single message" do
    messages = build_messages(1)
    result = @strategy.filter(messages)
    assert_equal 1, result.length
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/memory/sliding_window_test.rb`
Expected: FAIL — `SolidAgent::Memory::SlidingWindow` not defined

- [ ] **Step 3: Implement SlidingWindow**

```ruby
# lib/solid_agent/memory/sliding_window.rb
module SolidAgent
  module Memory
    class SlidingWindow < Base
      attr_reader :max_messages

      def initialize(max_messages: 50, **options)
        @max_messages = max_messages
        super
      end

      def filter(messages)
        messages.last(@max_messages)
      end

      def compact!(messages)
        filter(messages)
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/memory/sliding_window_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Memory::SlidingWindow strategy"
```

---

### Task 3: Full History Strategy

**Files:**
- Create: `lib/solid_agent/memory/full_history.rb`
- Test: `test/memory/full_history_test.rb`

- [ ] **Step 1: Write failing tests for FullHistory**

```ruby
# test/memory/full_history_test.rb
require "test_helper"

class FullHistoryTest < ActiveSupport::TestCase
  def setup
    @strategy = SolidAgent::Memory::FullHistory.new
  end

  test "filter returns all messages unchanged" do
    messages = build_messages(100)
    result = @strategy.filter(messages)
    assert_equal 100, result.length
    assert_equal messages, result
  end

  test "filter returns empty array for no messages" do
    result = @strategy.filter([])
    assert_equal [], result
  end

  test "build_context adds system prompt before all messages" do
    messages = build_messages(3)
    result = @strategy.build_context(messages, system_prompt: "Be helpful")
    assert_equal 4, result.length
    assert_equal "system", result.first.role
    assert_equal "Be helpful", result.first.content
    assert_equal "Message 1", result[1].content
    assert_equal "Message 3", result.last.content
  end

  test "build_context without system prompt returns all messages" do
    messages = build_messages(3)
    result = @strategy.build_context(messages, system_prompt: nil)
    assert_equal 3, result.length
  end

  test "compact! returns all messages unchanged" do
    messages = build_messages(50)
    result = @strategy.compact!(messages)
    assert_equal 50, result.length
    assert_equal messages, result
  end

  test "compact! with empty messages returns empty" do
    result = @strategy.compact!([])
    assert_equal [], result
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/memory/full_history_test.rb`
Expected: FAIL — `SolidAgent::Memory::FullHistory` not defined

- [ ] **Step 3: Implement FullHistory**

```ruby
# lib/solid_agent/memory/full_history.rb
module SolidAgent
  module Memory
    class FullHistory < Base
      def filter(messages)
        messages
      end

      def compact!(messages)
        messages
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/memory/full_history_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Memory::FullHistory strategy"
```

---

### Task 4: Compaction Strategy

**Files:**
- Create: `lib/solid_agent/memory/compaction.rb`
- Test: `test/memory/compaction_test.rb`

- [ ] **Step 1: Write failing tests for Compaction**

```ruby
# test/memory/compaction_test.rb
require "test_helper"

class CompactionTest < ActiveSupport::TestCase
  def setup
    @summarizer = ->(text) { "Summary of: #{text.truncate(50)}" }
    @strategy = SolidAgent::Memory::Compaction.new(
      max_tokens: 100,
      summarizer: @summarizer
    )
  end

  test "stores max_tokens" do
    assert_equal 100, @strategy.max_tokens
  end

  test "default max_tokens is 8000" do
    strategy = SolidAgent::Memory::Compaction.new
    assert_equal 8000, strategy.max_tokens
  end

  test "stores summarizer" do
    assert_equal @summarizer, @strategy.summarizer
  end

  test "filter returns all messages unchanged" do
    messages = build_messages(5, token_count: 10)
    result = @strategy.filter(messages)
    assert_equal messages, result
  end

  test "build_context adds system prompt" do
    messages = build_messages(3, token_count: 10)
    result = @strategy.build_context(messages, system_prompt: "Be helpful")
    assert_equal 4, result.length
    assert_equal "system", result.first.role
  end

  test "compact! returns messages when under token limit" do
    messages = build_messages(5, token_count: 10)
    result = @strategy.compact!(messages)
    assert_equal 5, result.length
    assert_equal messages, result
  end

  test "compact! summarizes older messages when over limit" do
    messages = build_messages(20, token_count: 10)
    result = @strategy.compact!(messages)
    assert result.length < 20, "Expected fewer messages after compaction"
    assert_equal "system", result.first.role
    assert result.first.content.start_with?("[Summary of earlier conversation]"), "Expected summary prefix, got: #{result.first.content}"
  end

  test "compact! preserves recent messages after summary" do
    messages = build_messages(20, token_count: 10)
    result = @strategy.compact!(messages)
    assert result.last.content.start_with?("Message"), "Expected recent message, got: #{result.last.content}"
    recent_original = messages.last.content
    assert_equal recent_original, result.last.content
  end

  test "compact! without summarizer returns messages unchanged" do
    strategy = SolidAgent::Memory::Compaction.new(max_tokens: 10)
    messages = build_messages(20, token_count: 10)
    result = strategy.compact!(messages)
    assert_equal 20, result.length
  end

  test "needs_compaction? returns true when over limit" do
    messages = build_messages(20, token_count: 10)
    assert @strategy.needs_compaction?(messages)
  end

  test "needs_compaction? returns false when under limit" do
    messages = build_messages(5, token_count: 10)
    refute @strategy.needs_compaction?(messages)
  end

  test "needs_compaction? returns false at exact limit" do
    messages = build_messages(10, token_count: 10)
    refute @strategy.needs_compaction?(messages)
  end

  test "compact! with mixed token counts" do
    messages = [
      SolidAgent::Message.new(role: "user", content: "Long question", token_count: 40),
      SolidAgent::Message.new(role: "assistant", content: "Long answer", token_count: 40),
      SolidAgent::Message.new(role: "user", content: "Short", token_count: 5),
      SolidAgent::Message.new(role: "assistant", content: "Short reply", token_count: 5)
    ]
    result = @strategy.compact!(messages)
    assert result.length < messages.length
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/memory/compaction_test.rb`
Expected: FAIL — `SolidAgent::Memory::Compaction` not defined

- [ ] **Step 3: Implement Compaction**

```ruby
# lib/solid_agent/memory/compaction.rb
module SolidAgent
  module Memory
    class Compaction < Base
      attr_reader :max_tokens, :summarizer

      def initialize(max_tokens: 8000, summarizer: nil, **options)
        @max_tokens = max_tokens
        @summarizer = summarizer
        super
      end

      def filter(messages)
        messages
      end

      def compact!(messages)
        return messages if total_token_count(messages) <= @max_tokens
        return messages unless @summarizer
        summarize_older(messages)
      end

      def needs_compaction?(messages)
        total_token_count(messages) > @max_tokens
      end

      private

      def summarize_older(messages)
        split_index = find_split_index(messages)
        return messages if split_index <= 0

        older = messages[0...split_index]
        recent = messages[split_index..]

        combined_text = older.map(&:content).compact.join("\n")
        summary_text = @summarizer.call(combined_text)
        summary_msg = build_system_message("[Summary of earlier conversation]: #{summary_text}")

        [summary_msg] + recent
      end

      def find_split_index(messages)
        total = 0
        half_budget = @max_tokens / 2
        messages.each_with_index do |msg, idx|
          total += msg.token_count.to_i
          return idx + 1 if total > half_budget
        end
        messages.length
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/memory/compaction_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Memory::Compaction strategy with summarizer injection"
```

---

### Task 5: Chain Strategy

**Files:**
- Create: `lib/solid_agent/memory/chain.rb`
- Test: `test/memory/chain_test.rb`

- [ ] **Step 1: Write failing tests for Chain**

```ruby
# test/memory/chain_test.rb
require "test_helper"

class ChainTest < ActiveSupport::TestCase
  def setup
    @window = SolidAgent::Memory::SlidingWindow.new(max_messages: 5)
    @history = SolidAgent::Memory::FullHistory.new
    @chain = SolidAgent::Memory::Chain.new(strategies: [@window, @history])
  end

  test "stores strategies" do
    assert_equal 2, @chain.strategies.length
    assert_instance_of SolidAgent::Memory::SlidingWindow, @chain.strategies.first
    assert_instance_of SolidAgent::Memory::FullHistory, @chain.strategies.last
  end

  test "filter applies strategies in sequence" do
    messages = build_messages(10)
    result = @chain.filter(messages)
    # SlidingWindow filters to 5, FullHistory passes through
    assert_equal 5, result.length
    assert_equal "Message 6", result.first.content
  end

  test "build_context filters then adds system prompt" do
    messages = build_messages(10)
    result = @chain.build_context(messages, system_prompt: "Be helpful")
    assert_equal 6, result.length
    assert_equal "system", result.first.role
    assert_equal "Message 6", result[1].content
  end

  test "compact! chains through all strategies" do
    window = SolidAgent::Memory::SlidingWindow.new(max_messages: 3)
    chain = SolidAgent::Memory::Chain.new(strategies: [window])
    messages = build_messages(10)
    result = chain.compact!(messages)
    assert_equal 3, result.length
  end

  test "chain with compaction strategy" do
    summarizer = ->(text) { "Summary: #{text.truncate(20)}" }
    compaction = SolidAgent::Memory::Compaction.new(max_tokens: 50, summarizer: summarizer)
    window = SolidAgent::Memory::SlidingWindow.new(max_messages: 10)
    chain = SolidAgent::Memory::Chain.new(strategies: [window, compaction])

    messages = build_messages(20, token_count: 5)
    # Window filters to 10 (50 tokens), compaction triggers at 50
    result = chain.compact!(messages)
    assert result.length <= 10
  end

  test "chain with single strategy delegates" do
    window = SolidAgent::Memory::SlidingWindow.new(max_messages: 3)
    chain = SolidAgent::Memory::Chain.new(strategies: [window])
    messages = build_messages(10)

    filtered = chain.filter(messages)
    assert_equal 3, filtered.length
  end

  test "chain with empty strategies returns messages unchanged" do
    chain = SolidAgent::Memory::Chain.new(strategies: [])
    messages = build_messages(5)

    result = chain.filter(messages)
    assert_equal 5, result.length
  end

  test "compact! with empty strategies returns messages unchanged" do
    chain = SolidAgent::Memory::Chain.new(strategies: [])
    messages = build_messages(5)

    result = chain.compact!(messages)
    assert_equal 5, result.length
  end

  test "three-strategy chain" do
    window = SolidAgent::Memory::SlidingWindow.new(max_messages: 8)
    history = SolidAgent::Memory::FullHistory.new
    window2 = SolidAgent::Memory::SlidingWindow.new(max_messages: 3)

    chain = SolidAgent::Memory::Chain.new(strategies: [window, history, window2])
    messages = build_messages(20)

    result = chain.filter(messages)
    # Window to 8, FullHistory passes through, Window2 to 3
    assert_equal 3, result.length
    assert_equal "Message 18", result.first.content
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/memory/chain_test.rb`
Expected: FAIL — `SolidAgent::Memory::Chain` not defined

- [ ] **Step 3: Implement Chain**

```ruby
# lib/solid_agent/memory/chain.rb
module SolidAgent
  module Memory
    class Chain < Base
      attr_reader :strategies

      def initialize(strategies:, **options)
        @strategies = strategies
        super
      end

      def filter(messages)
        @strategies.reduce(messages) do |current, strategy|
          strategy.filter(current)
        end
      end

      def compact!(messages)
        @strategies.reduce(messages) do |current, strategy|
          strategy.compact!(current)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/memory/chain_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Memory::Chain for composing multiple strategies"
```

---

### Task 6: Registry & ChainBuilder

**Files:**
- Create: `lib/solid_agent/memory/registry.rb`
- Create: `lib/solid_agent/memory/chain_builder.rb`
- Test: `test/memory/registry_test.rb`

- [ ] **Step 1: Write failing tests for Registry**

```ruby
# test/memory/registry_test.rb
require "test_helper"

class MemoryRegistryTest < ActiveSupport::TestCase
  test "resolve returns class for known strategy" do
    klass = SolidAgent::Memory::Registry.resolve(:sliding_window)
    assert_equal SolidAgent::Memory::SlidingWindow, klass
  end

  test "resolve returns FullHistory for :full_history" do
    klass = SolidAgent::Memory::Registry.resolve(:full_history)
    assert_equal SolidAgent::Memory::FullHistory, klass
  end

  test "resolve returns Compaction for :compaction" do
    klass = SolidAgent::Memory::Registry.resolve(:compaction)
    assert_equal SolidAgent::Memory::Compaction, klass
  end

  test "resolve raises for unknown strategy" do
    assert_raises(ArgumentError) do
      SolidAgent::Memory::Registry.resolve(:nonexistent)
    end
  end

  test "build returns strategy instance without block" do
    strategy = SolidAgent::Memory::Registry.build(:sliding_window, max_messages: 20)
    assert_instance_of SolidAgent::Memory::SlidingWindow, strategy
    assert_equal 20, strategy.max_messages
  end

  test "build returns FullHistory instance" do
    strategy = SolidAgent::Memory::Registry.build(:full_history)
    assert_instance_of SolidAgent::Memory::FullHistory, strategy
  end

  test "build returns Compaction with options" do
    summarizer = ->(text) { "summary" }
    strategy = SolidAgent::Memory::Registry.build(:compaction, max_tokens: 4000, summarizer: summarizer)
    assert_instance_of SolidAgent::Memory::Compaction, strategy
    assert_equal 4000, strategy.max_tokens
  end

  test "build with block returns Chain" do
    strategy = SolidAgent::Memory::Registry.build(:sliding_window, max_messages: 30) do |m|
      m.then :compaction, max_tokens: 4000
    end

    assert_instance_of SolidAgent::Memory::Chain, strategy
    assert_equal 2, strategy.strategies.length
    assert_instance_of SolidAgent::Memory::SlidingWindow, strategy.strategies.first
    assert_instance_of SolidAgent::Memory::Compaction, strategy.strategies.last
  end

  test "build with block containing multiple thens" do
    strategy = SolidAgent::Memory::Registry.build(:full_history) do |m|
      m.then :sliding_window, max_messages: 10
      m.then :compaction, max_tokens: 2000
    end

    assert_instance_of SolidAgent::Memory::Chain, strategy
    assert_equal 3, strategy.strategies.length
  end

  test "ChainBuilder collects strategies" do
    builder = SolidAgent::Memory::ChainBuilder.new
    builder.then :sliding_window, max_messages: 10
    builder.then :compaction, max_tokens: 2000

    assert_equal 2, builder.strategies.length
    assert_instance_of SolidAgent::Memory::SlidingWindow, builder.strategies.first
    assert_instance_of SolidAgent::Memory::Compaction, builder.strategies.last
  end

  test "STRATEGIES constant has all known strategies" do
    assert SolidAgent::Memory::Registry::STRATEGIES.key?(:sliding_window)
    assert SolidAgent::Memory::Registry::STRATEGIES.key?(:full_history)
    assert SolidAgent::Memory::Registry::STRATEGIES.key?(:compaction)
  end

  test "built chain strategies are functional" do
    strategy = SolidAgent::Memory::Registry.build(:sliding_window, max_messages: 5) do |m|
      m.then :full_history
    end

    messages = build_messages(10)
    result = strategy.filter(messages)
    assert_equal 5, result.length
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/memory/registry_test.rb`
Expected: FAIL — `SolidAgent::Memory::Registry` not defined

- [ ] **Step 3: Implement Registry**

```ruby
# lib/solid_agent/memory/registry.rb
module SolidAgent
  module Memory
    class Registry
      STRATEGIES = {
        sliding_window: "SolidAgent::Memory::SlidingWindow",
        full_history: "SolidAgent::Memory::FullHistory",
        compaction: "SolidAgent::Memory::Compaction"
      }.freeze

      def self.resolve(name)
        class_name = STRATEGIES[name]
        raise ArgumentError, "Unknown memory strategy: #{name}. Available: #{STRATEGIES.keys.join(', ')}" unless class_name
        class_name.constantize
      end

      def self.build(name, **options, &block)
        strategy = resolve(name).new(**options)

        if block
          builder = ChainBuilder.new
          yield(builder)
          Chain.new(strategies: [strategy] + builder.strategies)
        else
          strategy
        end
      end
    end
  end
end
```

- [ ] **Step 4: Implement ChainBuilder**

```ruby
# lib/solid_agent/memory/chain_builder.rb
module SolidAgent
  module Memory
    class ChainBuilder
      attr_reader :strategies

      def initialize
        @strategies = []
      end

      def then(name, **options)
        strategy = Registry.resolve(name).new(**options)
        @strategies << strategy
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/memory/registry_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Memory::Registry and ChainBuilder for DSL resolution"
```

---

### Task 7: Vector Store Base & SQLite-vec Adapter

**Files:**
- Create: `lib/solid_agent/vector_store/base.rb`
- Create: `lib/solid_agent/vector_store/sqlite_vec_adapter.rb`
- Test: `test/vector_store/base_test.rb`
- Test: `test/vector_store/sqlite_vec_adapter_test.rb`

- [ ] **Step 1: Write failing tests for VectorStore::Base**

```ruby
# test/vector_store/base_test.rb
require "test_helper"

class VectorStoreBaseTest < ActiveSupport::TestCase
  def setup
    @store = SolidAgent::VectorStore::Base.new
  end

  test "upsert raises NotImplementedError" do
    assert_raises(NotImplementedError) do
      @store.upsert(id: 1, embedding: [0.1, 0.2], metadata: {})
    end
  end

  test "query raises NotImplementedError" do
    assert_raises(NotImplementedError) do
      @store.query(embedding: [0.1, 0.2], limit: 5, threshold: 0.7)
    end
  end

  test "delete raises NotImplementedError" do
    assert_raises(NotImplementedError) do
      @store.delete(id: 1)
    end
  end
end
```

- [ ] **Step 2: Implement VectorStore::Base**

```ruby
# lib/solid_agent/vector_store/base.rb
module SolidAgent
  module VectorStore
    class Base
      def upsert(id:, embedding:, metadata: {})
        raise NotImplementedError, "#{self.class}#upsert must be implemented"
      end

      def query(embedding:, limit: 10, threshold: 0.7)
        raise NotImplementedError, "#{self.class}#query must be implemented"
      end

      def delete(id:)
        raise NotImplementedError, "#{self.class}#delete must be implemented"
      end
    end
  end
end
```

- [ ] **Step 3: Write failing tests for SqliteVecAdapter**

These tests validate the adapter's behavior. The adapter gracefully degrades when sqlite-vec is not available.

```ruby
# test/vector_store/sqlite_vec_adapter_test.rb
require "test_helper"

class SqliteVecAdapterTest < ActiveSupport::TestCase
  def setup
    @adapter = SolidAgent::VectorStore::SqliteVecAdapter.new(dimensions: 8)
  end

  test "initializes with dimensions" do
    assert_equal 8, @adapter.dimensions
  end

  test "default dimensions is 1536" do
    adapter = SolidAgent::VectorStore::SqliteVecAdapter.new
    assert_equal 1536, adapter.dimensions
  end

  test "available? returns boolean" do
    assert [true, false].include?(@adapter.available?)
  end

  test "upsert returns nil when not available" do
    unless @adapter.available?
      result = @adapter.upsert(id: 1, embedding: [0.1] * 8, metadata: {})
      assert_nil result
    end
  end

  test "query returns empty array when not available" do
    unless @adapter.available?
      result = @adapter.query(embedding: [0.1] * 8, limit: 5, threshold: 0.5)
      assert_equal [], result
    end
  end

  test "delete returns nil when not available" do
    unless @adapter.available?
      result = @adapter.delete(id: 1)
      assert_nil result
    end
  end

  test "serialize_embedding produces binary string" do
    embedding = [0.1, 0.2, 0.3]
    blob = @adapter.send(:serialize_embedding, embedding)
    assert_instance_of String, blob
    assert blob.bytesize > 0
  end

  test "serialize_embedding round-trips correctly" do
    embedding = [0.1, 0.2, 0.3, 0.4]
    blob = @adapter.send(:serialize_embedding, embedding)
    restored = blob.unpack("f*")
    embedding.each_with_index do |val, i|
      assert_in_delta val, restored[i], 0.001
    end
  end

  # Tests that only run when sqlite-vec is available
  if defined?(SqliteVecHelper) && SqliteVecHelper.available?
    test "upsert and query cycle" do
      skip("sqlite-vec not available") unless @adapter.available?

      embedding1 = Array.new(8) { |i| (i + 1) / 10.0 }
      embedding2 = Array.new(8) { |i| (i + 5) / 10.0 }
      query_embedding = Array.new(8) { |i| (i + 1) / 10.0 }

      @adapter.upsert(id: 1, embedding: embedding1, metadata: { type: "test" })
      @adapter.upsert(id: 2, embedding: embedding2, metadata: { type: "test" })

      results = @adapter.query(embedding: query_embedding, limit: 5, threshold: 0.0)
      assert results.length >= 1
      assert_equal 1, results.first[:id]
    end

    test "delete removes entry" do
      skip("sqlite-vec not available") unless @adapter.available?

      @adapter.upsert(id: 99, embedding: Array.new(8, 0.5), metadata: {})
      @adapter.delete(id: 99)

      results = @adapter.query(embedding: Array.new(8, 0.5), limit: 5, threshold: 0.0)
      ids = results.map { |r| r[:id] }
      refute_includes ids, 99
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/vector_store/base_test.rb`
Expected: FAIL — `SolidAgent::VectorStore::Base` not defined

Run: `bundle exec ruby -Itest test/vector_store/sqlite_vec_adapter_test.rb`
Expected: FAIL — `SolidAgent::VectorStore::SqliteVecAdapter` not defined

- [ ] **Step 5: Implement SqliteVecAdapter**

```ruby
# lib/solid_agent/vector_store/sqlite_vec_adapter.rb
module SolidAgent
  module VectorStore
    class SqliteVecAdapter < Base
      DEFAULT_DIMENSIONS = 1536
      TABLE_NAME = "solid_agent_vec_entries"

      attr_reader :dimensions

      def initialize(dimensions: DEFAULT_DIMENSIONS)
        @dimensions = dimensions
        @available = false
        @connection = nil
        setup_extension
      end

      def available?
        @available
      end

      def upsert(id:, embedding:, metadata: {})
        return nil unless @available
        blob = serialize_embedding(embedding)
        execute("DELETE FROM #{TABLE_NAME} WHERE rowid = ?", [id])
        execute("INSERT INTO #{TABLE_NAME}(rowid, embedding) VALUES (?, ?)", [id, blob])
        true
      end

      def query(embedding:, limit: 10, threshold: 0.7)
        return [] unless @available
        blob = serialize_embedding(embedding)
        max_distance = 1.0 - threshold
        rows = execute(
          "SELECT rowid, distance FROM #{TABLE_NAME} WHERE embedding MATCH ? AND distance <= ? ORDER BY distance LIMIT ?",
          [blob, max_distance, limit]
        )
        rows.map { |row| { id: row[0], score: 1.0 - row[1] } }
      rescue StandardError
        []
      end

      def delete(id:)
        return nil unless @available
        execute("DELETE FROM #{TABLE_NAME} WHERE rowid = ?", [id])
        true
      end

      private

      def setup_extension
        raw_conn = ActiveRecord::Base.connection.raw_connection
        return unless raw_conn.respond_to?(:enable_load_extension)

        raw_conn.enable_load_extension(true)
        raw_conn.load_extension("vec0")
        raw_conn.enable_load_extension(false)

        raw_conn.execute(<<~SQL)
          CREATE VIRTUAL TABLE IF NOT EXISTS #{TABLE_NAME}
          USING vec0(embedding float[#{@dimensions}])
        SQL

        @connection = raw_conn
        @available = true
      rescue StandardError
        @available = false
      end

      def execute(sql, params = [])
        @connection.execute(sql, params)
      end

      def serialize_embedding(embedding)
        embedding.pack("f*")
      end
    end
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/vector_store/base_test.rb`
Expected: All tests PASS

Run: `bundle exec ruby -Itest test/vector_store/sqlite_vec_adapter_test.rb`
Expected: All tests PASS (graceful degradation tests pass; sqlite-vec tests skip if unavailable)

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add VectorStore::Base interface and SqliteVecAdapter with graceful degradation"
```

---

### Task 8: Embedder Base & Observational Memory

**Files:**
- Create: `lib/solid_agent/embedder/base.rb`
- Create: `lib/solid_agent/observational_memory.rb`
- Test: `test/embedder/base_test.rb`
- Test: `test/observational_memory_test.rb`

- [ ] **Step 1: Write failing tests for Embedder::Base**

```ruby
# test/embedder/base_test.rb
require "test_helper"

class EmbedderBaseTest < ActiveSupport::TestCase
  def setup
    @embedder = SolidAgent::Embedder::Base.new
  end

  test "embed raises NotImplementedError" do
    assert_raises(NotImplementedError) do
      @embedder.embed("test text")
    end
  end
end
```

- [ ] **Step 2: Implement Embedder::Base**

```ruby
# lib/solid_agent/embedder/base.rb
module SolidAgent
  module Embedder
    class Base
      def embed(text)
        raise NotImplementedError, "#{self.class}#embed must be implemented"
      end
    end
  end
end
```

- [ ] **Step 3: Run embedder base tests to verify they pass**

Run: `bundle exec ruby -Itest test/embedder/base_test.rb`
Expected: All tests PASS

- [ ] **Step 4: Write failing tests for ObservationalMemory**

```ruby
# test/observational_memory_test.rb
require "test_helper"

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
    @conversation = SolidAgent::Conversation.create!(agent_class: "TestAgent")
  end

  test "enabled when vector_store and embedder provided" do
    assert @memory.enabled
  end

  test "disabled when vector_store is nil" do
    memory = SolidAgent::ObservationalMemory.new(vector_store: nil, embedder: @embedder)
    refute memory.enabled
  end

  test "disabled when embedder is nil" do
    memory = SolidAgent::ObservationalMemory.new(vector_store: @vector_store, embedder: nil)
    refute memory.enabled
  end

  test "disabled when enabled: false" do
    memory = SolidAgent::ObservationalMemory.new(
      vector_store: @vector_store,
      embedder: @embedder,
      enabled: false
    )
    refute memory.enabled
  end

  test "store_observation creates MemoryEntry" do
    entry = @memory.store_observation(
      agent_class: "TestAgent",
      content: "User prefers concise answers",
      conversation: @conversation
    )

    assert_instance_of SolidAgent::MemoryEntry, entry
    assert_equal "TestAgent", entry.agent_class
    assert_equal "observation", entry.entry_type
    assert_equal "User prefers concise answers", entry.content
    assert_equal @conversation.id, entry.conversation_id
  end

  test "store_observation persists to database" do
    @memory.store_observation(
      agent_class: "TestAgent",
      content: "User likes examples",
      conversation: @conversation
    )

    assert_equal 1, SolidAgent::MemoryEntry.for_agent("TestAgent").count
    assert_equal "User likes examples", SolidAgent::MemoryEntry.last.content
  end

  test "store_observation upserts to vector store" do
    entry = @memory.store_observation(
      agent_class: "TestAgent",
      content: "User prefers bullet points",
      conversation: @conversation
    )

    assert @vector_store.store.key?(entry.id)
  end

  test "store_observation returns nil when disabled" do
    memory = SolidAgent::ObservationalMemory.new(vector_store: nil, embedder: @embedder)
    result = memory.store_observation(agent_class: "TestAgent", content: "test")
    assert_nil result
  end

  test "store_observation without conversation is valid" do
    entry = @memory.store_observation(
      agent_class: "TestAgent",
      content: "General knowledge"
    )

    assert_instance_of SolidAgent::MemoryEntry, entry
    assert_nil entry.conversation_id
  end

  test "retrieve_relevant returns matching entries" do
    @memory.store_observation(agent_class: "TestAgent", content: "Ruby is great")
    @memory.store_observation(agent_class: "TestAgent", content: "Python is okay")

    results = @memory.retrieve_relevant(
      agent_class: "TestAgent",
      query_text: "Ruby is great"
    )

    assert results.length >= 1
    assert results.any? { |e| e.content == "Ruby is great" }
  end

  test "retrieve_relevant filters by agent_class" do
    @memory.store_observation(agent_class: "AgentA", content: "Alpha data")
    @memory.store_observation(agent_class: "AgentB", content: "Beta data")

    results = @memory.retrieve_relevant(agent_class: "AgentA", query_text: "Alpha data")
    results.each do |entry|
      assert_equal "AgentA", entry.agent_class
    end
  end

  test "retrieve_relevant returns empty when disabled" do
    memory = SolidAgent::ObservationalMemory.new(vector_store: nil, embedder: @embedder)
    results = memory.retrieve_relevant(agent_class: "TestAgent", query_text: "test")
    assert_equal [], results
  end

  test "retrieve_relevant respects limit" do
    5.times do |i|
      @memory.store_observation(agent_class: "TestAgent", content: "Observation #{i}")
    end

    results = @memory.retrieve_relevant(
      agent_class: "TestAgent",
      query_text: "Observation",
      limit: 2
    )
    assert results.length <= 2
  end

  test "build_system_context returns formatted string" do
    @memory.store_observation(agent_class: "TestAgent", content: "User prefers brevity")

    context = @memory.build_system_context(
      agent_class: "TestAgent",
      query_text: "User prefers brevity"
    )

    assert context.start_with?("## Relevant Memories\n")
    assert context.include?("User prefers brevity")
  end

  test "build_system_context returns empty string when no matches" do
    context = @memory.build_system_context(
      agent_class: "NonExistentAgent",
      query_text: "nothing relevant"
    )

    assert_equal "", context
  end

  test "build_system_context returns empty when disabled" do
    memory = SolidAgent::ObservationalMemory.new(vector_store: nil, embedder: @embedder)
    context = memory.build_system_context(agent_class: "TestAgent", query_text: "test")
    assert_equal "", context
  end

  test "trims entries beyond max_entries" do
    7.times do |i|
      @memory.store_observation(agent_class: "TestAgent", content: "Entry #{i}")
    end

    count = SolidAgent::MemoryEntry.for_agent("TestAgent").count
    assert count <= @memory.max_entries,
      "Expected at most #{@memory.max_entries} entries, got #{count}"
  end

  test "trims oldest entries first" do
    first = @memory.store_observation(agent_class: "TestAgent", content: "Oldest entry")

    5.times do |i|
      @memory.store_observation(agent_class: "TestAgent", content: "Entry #{i}")
    end

    refute SolidAgent::MemoryEntry.exists?(first.id),
      "Expected oldest entry to be trimmed"
  end

  test "does not trim entries from other agents" do
    7.times do |i|
      @memory.store_observation(agent_class: "AgentA", content: "A entry #{i}")
    end

    3.times do |i|
      @memory.store_observation(agent_class: "AgentB", content: "B entry #{i}")
    end

    agent_b_count = SolidAgent::MemoryEntry.for_agent("AgentB").count
    assert_equal 3, agent_b_count,
      "AgentB entries should not be affected by AgentA trimming"
  end

  test "default max_entries is 500" do
    memory = SolidAgent::ObservationalMemory.new(
      vector_store: @vector_store,
      embedder: @embedder
    )
    assert_equal 500, memory.max_entries
  end

  test "default retrieval_count is 10" do
    memory = SolidAgent::ObservationalMemory.new(
      vector_store: @vector_store,
      embedder: @embedder
    )
    assert_equal 10, memory.retrieval_count
  end
end
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/observational_memory_test.rb`
Expected: FAIL — `SolidAgent::ObservationalMemory` not defined

- [ ] **Step 6: Implement ObservationalMemory**

```ruby
# lib/solid_agent/observational_memory.rb
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
        metadata: { agent_class: agent_class, entry_type: "observation" }
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
      return "" unless @enabled

      entries = retrieve_relevant(agent_class: agent_class, query_text: query_text)
      return "" if entries.empty?

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
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bundle exec ruby -Itest test/embedder/base_test.rb`
Expected: All tests PASS

Run: `bundle exec ruby -Itest test/observational_memory_test.rb`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add Embedder::Base, ObservationalMemory with vector store integration"
```

---

### Task 9: Wire Into Engine Entry Point

**Files:**
- Update: `lib/solid_agent.rb`

- [ ] **Step 1: Add requires to engine entry point**

Add the following requires to `lib/solid_agent.rb` after the existing requires:

```ruby
# lib/solid_agent.rb — add after existing requires

require "solid_agent/memory/base"
require "solid_agent/memory/sliding_window"
require "solid_agent/memory/full_history"
require "solid_agent/memory/compaction"
require "solid_agent/memory/chain"
require "solid_agent/memory/registry"
require "solid_agent/memory/chain_builder"
require "solid_agent/vector_store/base"
require "solid_agent/vector_store/sqlite_vec_adapter"
require "solid_agent/embedder/base"
require "solid_agent/observational_memory"
```

The full file should now read:

```ruby
# lib/solid_agent.rb
require "solid_agent/engine"
require "solid_agent/configuration"
require "solid_agent/model"
require "solid_agent/models/open_ai"
require "solid_agent/models/anthropic"
require "solid_agent/models/google"

require "solid_agent/memory/base"
require "solid_agent/memory/sliding_window"
require "solid_agent/memory/full_history"
require "solid_agent/memory/compaction"
require "solid_agent/memory/chain"
require "solid_agent/memory/registry"
require "solid_agent/memory/chain_builder"
require "solid_agent/vector_store/base"
require "solid_agent/vector_store/sqlite_vec_adapter"
require "solid_agent/embedder/base"
require "solid_agent/observational_memory"

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

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: wire Memory, VectorStore, Embedder, and ObservationalMemory into engine"
```

---

### Task 10: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rake test`
Expected: All tests PASS, 0 failures

- [ ] **Step 2: Run individual test files to confirm coverage**

Run each test file individually:

```bash
bundle exec ruby -Itest test/memory/base_test.rb
bundle exec ruby -Itest test/memory/sliding_window_test.rb
bundle exec ruby -Itest test/memory/full_history_test.rb
bundle exec ruby -Itest test/memory/compaction_test.rb
bundle exec ruby -Itest test/memory/chain_test.rb
bundle exec ruby -Itest test/memory/registry_test.rb
bundle exec ruby -Itest test/vector_store/base_test.rb
bundle exec ruby -Itest test/vector_store/sqlite_vec_adapter_test.rb
bundle exec ruby -Itest test/embedder/base_test.rb
bundle exec ruby -Itest test/observational_memory_test.rb
```

Expected: All PASS

- [ ] **Step 3: Verify gem can be built**

Run: `gem build solid_agent.gemspec`
Expected: Successfully built gem

- [ ] **Step 4: Commit any final cleanup**

```bash
git add -A
git commit -m "chore: memory & context system plan complete — strategies, vector store, observational memory"
```

---

## Summary of Deliverables

| Component | File | Purpose |
|---|---|---|
| `Memory::Base` | `lib/solid_agent/memory/base.rb` | Abstract base with `filter`, `build_context`, `compact!` interface |
| `Memory::SlidingWindow` | `lib/solid_agent/memory/sliding_window.rb` | Keeps last N messages |
| `Memory::FullHistory` | `lib/solid_agent/memory/full_history.rb` | Passes all messages through |
| `Memory::Compaction` | `lib/solid_agent/memory/compaction.rb` | Summarizes older messages via injected summarizer |
| `Memory::Chain` | `lib/solid_agent/memory/chain.rb` | Composes multiple strategies in sequence |
| `Memory::Registry` | `lib/solid_agent/memory/registry.rb` | Resolves symbols to strategy classes; builds chains from DSL blocks |
| `Memory::ChainBuilder` | `lib/solid_agent/memory/chain_builder.rb` | Collects chained strategies via `.then` |
| `VectorStore::Base` | `lib/solid_agent/vector_store/base.rb` | Interface: `upsert`, `query`, `delete` |
| `VectorStore::SqliteVecAdapter` | `lib/solid_agent/vector_store/sqlite_vec_adapter.rb` | sqlite-vec implementation with graceful degradation |
| `Embedder::Base` | `lib/solid_agent/embedder/base.rb` | Interface: `embed(text)` |
| `ObservationalMemory` | `lib/solid_agent/observational_memory.rb` | Cross-conversation memory with similarity retrieval |

### Design Decisions

1. **`filter` + `build_context` split**: Each strategy overrides `filter(messages)` for pure message selection. `build_context` (inherited from Base) calls `filter` then prepends the system prompt. Chain composes strategies by chaining `filter` calls, adding the system prompt once at the end.

2. **Summarizer injection**: Compaction takes an optional `summarizer` callable (`->(text) { ... }`). The agent runtime provides one that calls the LLM. Tests use simple lambdas. When no summarizer is provided, `compact!` is a no-op.

3. **Token tracking from usage**: Token counts come from the `token_count` field on `SolidAgent::Message` (populated from LLM usage objects). No estimation is used for existing messages. The `total_token_count` helper in Base sums these values.

4. **Graceful vector store degradation**: `SqliteVecAdapter` catches all errors during extension loading and sets `available?` to `false`. All operations become no-ops. `ObservationalMemory` disables itself when no vector store is configured.

5. **Test doubles**: `TestEmbedder` and `TestVectorStore` are defined in `test_helper.rb` for use across all memory tests. `TestVectorStore` implements cosine similarity in pure Ruby for deterministic testing without sqlite-vec.
