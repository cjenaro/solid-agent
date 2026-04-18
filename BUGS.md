# SolidAgent Bugs

Bugs and issues found during integration testing of the `solid_agent` gem (v0.1.0) into the pbanalyzer Rails app.

> **Status:** Bugs 1–5 were fixed by the gem author. Bug 6 and Bug 7 have been fixed. All bugs resolved.

---

## ~~Bug 1: Missing namespace for `Trace` and `Conversation` in `agent/base.rb`~~ ✅ Fixed

**Severity:** Critical — app crashes at runtime

**Files:**
- `lib/solid_agent/agent/base.rb` (lines 11, 13, 16, 36, 38, 41)

**Description:**
`Agent::Base.perform_now` and `perform_later` referenced `Trace` and `Conversation` as bare constants, but these models are namespaced under `SolidAgent::`.

---

## ~~Bug 2: Missing namespace for `Trace` and `Conversation` in `run_job.rb`~~ ✅ Fixed

**Severity:** Critical — app crashes at runtime

**Files:**
- `lib/solid_agent/run_job.rb` (lines 12, 21)

Same root cause as Bug 1.

---

## ~~Bug 3: Install template uses dot notation on Hash~~ ✅ Fixed

**Severity:** Moderate — `rails solid_agent:install` crashes during migration step

**File:** `lib/generators/solid_agent/install/templates/solid_agent.rb.tt`

**Description:**
Template used `config.providers.openai = { ... }` (dot notation on a plain Hash). Ruby's `Hash` does not support dot notation for setting keys.

---

## ~~Bug 4: No migrations provided by the engine~~ ✅ Fixed

**Severity:** Critical — `db:migrate` does not create required tables

Migrations were added to `db/migrate/`. However, see **Bug 6** for a new issue with those migrations.

---

## ~~Bug 5: `Agent::Result` missing `conversation_id`~~ ✅ Fixed

**Severity:** Low — inconvenient API

**File:** `lib/solid_agent/agent/result.rb`

**Description:**
`Agent::Result` exposes `trace_id` but not `conversation_id`. Consumers who want to continue a conversation must look up the trace first:

```ruby
result = MyAgent.perform_now("hello")
# To get conversation_id, you need:
trace = SolidAgent::Trace.find(result.trace_id)
conversation_id = trace.conversation_id
```

**Fix:** Add `conversation_id` to `Result` or expose it directly.

---

## ~~Bug 6: Duplicate index on `references` columns in all migrations~~ ✅ Fixed

**Severity:** Critical — `db:migrate` crashes on SQLite (and likely other DBs)

**Files:**
- `db/migrate/20250101000003_create_solid_agent_spans.rb`
- `db/migrate/20250101000004_create_solid_agent_messages.rb`
- `db/migrate/20250101000005_create_solid_agent_memory_entries.rb`

**Description:**
Each migration uses `t.references :trace, ...` which automatically creates an index, then explicitly calls `add_index` on the same column. This produces a duplicate index error:

```ruby
# In create_solid_agent_spans:
t.references :trace, null: false, foreign_key: { to_table: :solid_agent_traces }
# ↑ This already creates index_solid_agent_spans_on_trace_id

add_index :solid_agent_spans, :trace_id  # ← DUPLICATE! Crashes on SQLite
```

Same pattern in `create_solid_agent_messages` (duplicate on `conversation_id`) and `create_solid_agent_memory_entries` (duplicate on `conversation_id`).

**Impact:** `SQLite3::SQLException: index ... already exists` — the entire migration chain aborts. Spans, messages, and memory_entries tables are never created.

**Fix:** Remove the explicit `add_index` calls for columns already covered by `t.references`:

```ruby
# Remove these duplicate lines:
# add_index :solid_agent_spans, :trace_id         # already indexed by t.references
# add_index :solid_agent_messages, :conversation_id # already indexed by t.references
# add_index :solid_agent_memory_entries, :conversation_id # already indexed by t.references
```

---

## ~~Bug 7: README says `bin/rails solid_agent:install` but command is `bin/rails generate solid_agent:install`~~ ✅ Fixed

**Severity:** Low — confusing documentation

**Files:**
- `README.md` (Installation section)

**Description:**
The README instructs users to run:
```bash
bin/rails solid_agent:install
```

But that produces:
```
Unrecognized command "solid_agent:install"
Did you mean?  solid_cache:install
```

The correct command is:
```bash
bin/rails generate solid_agent:install
```

**Fix:** Update the README to use `bin/rails generate solid_agent:install`, or add a Rails command that delegates to the generator.

---

## ~~Design Smell: Wasteful ActiveRecord instantiation for metadata serialization~~ ✅ Fixed

**Severity:** Low (performance)

**File:** `lib/solid_agent/react/loop.rb` (lines 50, 58, 98, 110, 127, 137)

**Description:**
The React loop creates `SolidAgent::Span` ActiveRecord instances (e.g., `Span.new(span_type: 'chunk', name: 'compaction')`) solely to pass to `Telemetry::Serializer.span_attributes()`. These objects are never persisted — they're used as lightweight structs. Creating AR objects has overhead (allocation, callbacks setup, attribute tracking).

**Fix:** Use a plain Ruby struct or data class for telemetry serialization:

```ruby
SpanData = Struct.new(:span_type, :name, :metadata, :tokens_in, :tokens_out, keyword_init: true)
SpanData.new(span_type: 'chunk', name: 'compaction')
```
