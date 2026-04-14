# Memory Strategies

How Solid Agent manages conversation context and the trade-offs of each strategy.

## How It Works

Every agent run loads messages from the database, passes them through the memory strategy's `build_context` method, and sends the result to the LLM. The memory strategy decides which messages to include, when to compact, and how to format the system prompt.

```
DB Messages
  |
  v
Memory Strategy #build_context(messages, system_prompt:)
  |   - Filters messages (sliding window, full history, etc.)
  |   - Prepends system prompt as a system message
  v
Array<SolidAgent::Message> -> sent to LLM provider
```

Token counts come from the LLM response `usage` object -- never estimated. The runtime accumulates totals per trace and per conversation. The memory strategy reads the running total and the model's `context_window` to decide when to compact.

## Strategy Interface

All strategies inherit from `SolidAgent::Memory::Base`:

```ruby
class SolidAgent::Memory::Base
  def build_context(messages, system_prompt:)
    result = filter(messages)
    if system_prompt && !system_prompt.empty?
      [build_system_message(system_prompt)] + result
    else
      result
    end
  end

  def filter(messages)
    messages
  end

  def compact!(messages)
    raise NotImplementedError
  end
end
```

To implement a custom strategy, subclass `Base` and override `filter` and `compact!`.

## Sliding Window

Keeps the most recent N messages and discards older ones. This is the default strategy.

```ruby
class MyAgent < SolidAgent::Base
  memory :sliding_window, max_messages: 50
end
```

### When to Use

- Short-to-medium conversations
- When you do not need the full conversation history
- When token cost matters more than perfect recall

### Behavior

- `filter` returns `messages.last(max_messages)`, keeping the most recent messages.
- `compact!` does the same thing.
- The system prompt is always prepended regardless of the window size.

### Gotchas

- A large `max_messages` value can still blow past the context window if individual messages are long (tool results, large documents).
- The sliding window drops messages silently. If the LLM needs earlier context, it is gone. Combine with observational memory or compaction to preserve important information.

## Compaction

Summarizes older messages when the conversation exceeds a token threshold, keeping recent messages intact.

```ruby
class MyAgent < SolidAgent::Base
  memory :compaction, max_tokens: 8000
end
```

### How Summarization Works

Compaction requires a `summarizer` -- a callable that receives the combined text of older messages and returns a summary string. Without a summarizer, compaction is a no-op.

```ruby
summarizer = ->(text) {
  provider = SolidAgent::Provider::OpenAi.new(api_key: ENV["OPENAI_API_KEY"])
  response = provider.build_request(
    messages: [
      SolidAgent::Types::Message.new(role: "user", content: "Summarize this conversation concisely:\n\n#{text}")
    ],
    tools: [],
    stream: false,
    model: SolidAgent::Models::OpenAi::GPT_4O_MINI,
    max_tokens: 500
  )
  http_response = SolidAgent::HTTP::NetHttpAdapter.new.call(response)
  parsed = provider.parse_response(http_response)
  parsed.messages.first.content
}

memory :compaction, max_tokens: 8000, summarizer: summarizer
```

### Behavior

1. When `total_token_count(messages) > max_tokens`, compaction triggers.
2. Messages are split at the midpoint of the token budget. Older messages go to the summarizer; recent messages stay intact.
3. The summary is injected as a system message: `"[Summary of earlier conversation]: ..."`.
4. The result is `[summary_message] + recent_messages`.

### Gotchas

- The summarizer call costs additional tokens and adds latency. Use a cheap model for summarization.
- The split point is based on accumulated token counts per message, not per-word estimates. Messages without a `token_count` are counted as zero, which can throw off the split.
- Compaction is one-way. You cannot recover the original messages after summarization.

## Full History

Passes all messages through without any filtering or compaction.

```ruby
class MyAgent < SolidAgent::Base
  memory :full_history
end
```

### Trade-offs

- Simplest option. No data loss.
- Will eventually exceed the model's context window for long conversations.
- The runtime triggers compaction via `React::Observer` at 85% of the context window, but `full_history`'s `compact!` is a no-op. You must handle this yourself via `on_context_overflow`.

### When to Use

- Short conversations (few turns)
- When the LLM has a very large context window (Gemini's 1M tokens)
- When you are certain the conversation will not exceed the window

## Chaining Strategies

Chain multiple strategies together. Messages flow through each strategy in order:

```ruby
class MyAgent < SolidAgent::Base
  memory :sliding_window, max_messages: 30 do |m|
    m.then :compaction, max_tokens: 4000
  end
end
```

### How It Works

`Memory::Chain` stores an array of strategies. `filter` and `compact!` each reduce messages through the chain sequentially:

```ruby
# filter
messages = sliding_window.filter(messages)   # keep last 30
messages = compaction.filter(messages)        # pass through (no-op for compaction)

# compact!
messages = sliding_window.compact!(messages)  # keep last 30
messages = compaction.compact!(messages)      # summarize if over 4000 tokens
```

### Common Patterns

**Sliding window then compaction:**

```ruby
memory :sliding_window, max_messages: 50 do |m|
  m.then :compaction, max_tokens: 8000
end
```

Best for long-running agents. The sliding window prevents unbounded growth, and compaction summarizes what remains if it is still too large.

## Observational Memory

Accumulates knowledge across conversations. Unlike in-conversation memory (sliding window, compaction), observational memory persists between separate conversations with the same agent.

```ruby
class MyAgent < SolidAgent::Base
  observational_memory enabled: true, max_entries: 500, retrieval_count: 10
end
```

### How It Extracts, Stores, and Retrieves Facts

**Extraction:** After a completed run, the agent can call `observational_memory.store_observation` to save a fact. This is typically done in an `after_invoke` callback or by a post-processing step.

**Storage:** Facts are stored as `SolidAgent::MemoryEntry` records with an embedding vector. The embedding is generated via the configured embedder.

**Retrieval:** At the start of a new conversation, relevant entries are retrieved via similarity search against the user's query text. They are injected into the system prompt under a `## Relevant Memories` header.

```ruby
# Behind the scenes:
memories = observational_memory.retrieve_relevant(
  agent_class: "MyAgent",
  query_text: user_input
)
# Returns: [#<MemoryEntry content: "User prefers concise answers">, ...]

# Injected into system prompt:
# ## Relevant Memories
# - User prefers concise answers
# - User works in the healthcare industry
```

### Configuration Options

| Option | Default | Description |
|---|---|---|
| `enabled` | `true` | Enable/disable (auto-disables if no vector store or embedder) |
| `max_entries` | 500 | Maximum entries per agent class. Oldest are trimmed. |
| `retrieval_count` | 10 | Number of relevant entries to retrieve per query |

### Prerequisites

Observational memory requires a vector store and an embedder, both configured at the engine level:

```ruby
SolidAgent.configure do |config|
  config.vector_store = :sqlite_vec
  config.embedding_provider = :openai
  config.embedding_model = "text-embedding-3-small"
end
```

If no vector store or embedder is available, `enabled` is silently set to `false`.

### Manual Usage

```ruby
# Store a fact
memory = SolidAgent::ObservationalMemory.new(
  vector_store: store,
  embedder: embedder
)
memory.store_observation(
  agent_class: "MyAgent",
  content: "User prefers detailed code examples",
  conversation: conversation
)

# Retrieve relevant facts
entries = memory.retrieve_relevant(
  agent_class: "MyAgent",
  query_text: "Write a sorting function"
)

# Build system context string
context = memory.build_system_context(
  agent_class: "MyAgent",
  query_text: "Write a sorting function"
)
```

## Custom Strategies

Implement `SolidAgent::Memory::Base`:

```ruby
class PriorityMemory < SolidAgent::Memory::Base
  def initialize(max_tokens: 16_000, **options)
    @max_tokens = max_tokens
    super
  end

  def filter(messages)
    return messages if total_token_count(messages) <= @max_tokens

    # Always keep system messages and the last 10 messages
    system_msgs = messages.select { |m| m.role == "system" }
    tail = messages.last(10)
    remaining_budget = @max_tokens - total_token_count(system_msgs + tail)

    # Fill remaining budget with middle messages, newest first
    middle = messages[system_msgs.size...-10].reverse
    selected = []
    middle.each do |msg|
      break if total_token_count(selected) + msg.token_count.to_i > remaining_budget
      selected.unshift(msg)
    end

    system_msgs + selected + tail
  end

  def compact!(messages)
    filter(messages)
  end
end
```

Register it with the memory registry before use:

```ruby
SolidAgent::Memory::Registry::STRATEGIES[:priority] = "PriorityMemory"
```

Then use it:

```ruby
class MyAgent < SolidAgent::Base
  memory :priority, max_tokens: 16_000
end
```

## Token Tracking and Context Window Management

Token tracking uses actual counts from LLM response `usage` objects. No estimation is performed.

The `React::Observer` monitors three conditions at the start of each iteration:

1. **Stop conditions** (hard limits):
   - `max_iterations` exceeded
   - `max_tokens_per_run` exceeded
   - `timeout` exceeded

2. **Compaction condition** (soft limit):
   - Current tokens >= 85% of model's `context_window`

When compaction triggers, the observer calls `memory.compact!(messages)` before building the context for the next LLM call. The compaction strategy replaces older messages with a summary (or drops them, in the case of sliding window).

If `compact!` cannot reduce the context enough and the next iteration would still exceed the token budget, the observer stops the loop with the current output.
