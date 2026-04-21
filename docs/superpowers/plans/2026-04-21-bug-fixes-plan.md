# Bug Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 5 bugs (8-12) discovered during gem integration testing: dashboard mounting, dead config option, orphaned template, incorrect iteration count on failure, and stuck traces.

**Architecture:** Document updates, generator enhancement, configuration cleanup, dead code removal, error handling improvements, and new cleanup job with configurable timeout.

**Tech Stack:** Rails 8, SQLite, Solid Queue, Ruby 3.3+

---

## File Structure

**Files to modify:**
- `README.md` - Documentation updates for Bugs 8, 9, 12
- `lib/solid_agent/configuration.rb` - Remove dead config (Bug 9), add new config (Bug 12)
- `lib/generators/solid_agent/install/install_generator.rb` - Add mount injection (Bug 8)
- `lib/solid_agent/react/loop.rb` - Fix iteration count and error handling (Bugs 11, 12)

**Files to delete:**
- `lib/generators/solid_agent/install/templates/add_otel_ids.rb.tt` - Orphaned template (Bug 10)

**Files to create:**
- `app/jobs/solid_agent/trace_cleanup_job.rb` - New cleanup job (Bug 12)

---

## Task 1: Remove dead `dashboard_route_prefix` configuration (Bug 9)

**Files:**
- Modify: `lib/solid_agent/configuration.rb`

- [ ] **Step 1: Remove `dashboard_route_prefix` from attr_accessor**

In `lib/solid_agent/configuration.rb`, update the `attr_accessor` line to remove `:dashboard_route_prefix`:

```ruby
attr_accessor :default_provider, :default_model, :dashboard_enabled,
              :vector_store, :embedding_provider,
              :embedding_model, :http_adapter, :trace_retention,
              :providers, :mcp_clients, :telemetry_exporters,
              :max_trace_running_duration
```

- [ ] **Step 2: Remove `dashboard_route_prefix` from initialize method**

In `lib/solid_agent/configuration.rb`, remove this line from the `initialize` method:

```ruby
# DELETE THIS LINE:
@dashboard_route_prefix = 'solid_agent'
```

The `initialize` method should now have:

```ruby
def initialize
  @default_provider = :openai
  @default_model = Models::OpenAi::GPT_4O
  @dashboard_enabled = true
  @vector_store = :sqlite_vec
  @embedding_provider = :openai
  @embedding_model = 'text-embedding-3-small'
  @http_adapter = :net_http
  @trace_retention = 30.days
  @providers = {}
  @mcp_clients = {}
  @telemetry_exporters = [Telemetry::NullExporter.new]
  @max_trace_running_duration = nil
end
```

- [ ] **Step 3: Commit**

```bash
git add lib/solid_agent/configuration.rb
git commit -m "fix: remove unused dashboard_route_prefix configuration (Bug 9)"
```

---

## Task 2: Add `max_trace_running_duration` configuration (Bug 12)

**Files:**
- Modify: `lib/solid_agent/configuration.rb`

- [ ] **Step 1: Add `max_trace_running_duration` to attr_accessor**

In `lib/solid_agent/configuration.rb`, add `:max_trace_running_duration` to the attr_accessor line (already added in Task 1 Step 1):

```ruby
attr_accessor :default_provider, :default_model, :dashboard_enabled,
              :vector_store, :embedding_provider,
              :embedding_model, :http_adapter, :trace_retention,
              :providers, :mcp_clients, :telemetry_exporters,
              :max_trace_running_duration
```

- [ ] **Step 2: Add `max_trace_running_duration` default to initialize method**

In `lib/solid_agent/configuration.rb`, add the default value in the `initialize` method (already added in Task 1 Step 2):

```ruby
@max_trace_running_duration = nil
```

- [ ] **Step 3: Commit**

```bash
git add lib/solid_agent/configuration.rb
git commit -m "feat: add max_trace_running_duration configuration for stuck trace cleanup (Bug 12)"
```

---

## Task 3: Delete orphaned `add_otel_ids.rb.tt` template (Bug 10)

**Files:**
- Delete: `lib/generators/solid_agent/install/templates/add_otel_ids.rb.tt`

- [ ] **Step 1: Delete the template file**

```bash
rm lib/generators/solid_agent/install/templates/add_otel_ids.rb.tt
```

- [ ] **Step 2: Verify no code references the template**

```bash
grep -r "add_otel_ids" lib/generators/
```

Expected: No results (if any results found, those files need to be updated)

- [ ] **Step 3: Commit**

```bash
git add lib/generators/solid_agent/install/templates/add_otel_ids.rb.tt
git commit -m "fix: remove orphaned add_otel_ids.rb.tt template (Bug 10)"
```

---

## Task 4: Fix `perform_now` returning incorrect iterations on failure (Bug 11)

**Files:**
- Modify: `lib/solid_agent/react/loop.rb`

- [ ] **Step 1: Locate the `build_result` method**

In `lib/solid_agent/react/loop.rb`, find the `build_result` private method around line 160-180.

- [ ] **Step 2: Update `build_result` to set iterations to 0 on failure**

Modify the `build_result` method to set `iterations: 0` when `status: :failed`:

```ruby
def build_result(status:, output:, error: nil, reason: nil)
  @trace.update!(
    status: status == :completed ? 'completed' : 'failed',
    completed_at: Time.current,
    output: output,
    error: error
  )

  SolidAgent.configuration.telemetry_exporters.each do |exporter|
    exporter.export_trace(@trace)
  end

  Agent::Result.new(
    trace_id: @trace.id,
    conversation_id: @trace.conversation_id,
    output: output,
    usage: @accumulated_usage,
    iterations: status == :failed ? 0 : @trace.iteration_count,
    status: status,
    error: error
  )
end
```

The key change is the `iterations` line: `iterations: status == :failed ? 0 : @trace.iteration_count`

- [ ] **Step 3: Commit**

```bash
git add lib/solid_agent/react/loop.rb
git commit -m "fix: return iterations: 0 when perform_now fails (Bug 11)"
```

---

## Task 5: Wrap trace update in error handling for stuck traces (Bug 12 - Part 1)

**Files:**
- Modify: `lib/solid_agent/react/loop.rb`

- [ ] **Step 1: Update `build_result` to handle update failures**

Modify the `build_result` method to wrap `@trace.update!` in begin/rescue:

```ruby
def build_result(status:, output:, error: nil, reason: nil)
  begin
    @trace.update!(
      status: status == :completed ? 'completed' : 'failed',
      completed_at: Time.current,
      output: output,
      error: error
    )
  rescue => e
    # Log the update failure but continue - this prevents trace status
    # updates from blocking the error handling flow (e.g., SQLite locking)
    Rails.logger.error("[SolidAgent] Failed to update trace status: #{e.message}")
  end

  SolidAgent.configuration.telemetry_exporters.each do |exporter|
    exporter.export_trace(@trace)
  end

  Agent::Result.new(
    trace_id: @trace.id,
    conversation_id: @trace.conversation_id,
    output: output,
    usage: @accumulated_usage,
    iterations: status == :failed ? 0 : @trace.iteration_count,
    status: status,
    error: error
  )
end
```

- [ ] **Step 2: Commit**

```bash
git add lib/solid_agent/react/loop.rb
git commit -m "fix: handle trace update failures in error path to prevent stuck traces (Bug 12)"
```

---

## Task 6: Create trace cleanup job (Bug 12 - Part 2)

**Files:**
- Create: `app/jobs/solid_agent/trace_cleanup_job.rb`

- [ ] **Step 1: Create the trace cleanup job file**

Create `app/jobs/solid_agent/trace_cleanup_job.rb`:

```ruby
module SolidAgent
  class ApplicationJob < ActiveJob::Base; end unless defined?(ApplicationJob)

  class TraceCleanupJob < ApplicationJob
    queue_as :solid_agent

    def perform
      max_duration = SolidAgent.configuration.max_trace_running_duration
      return if max_duration.nil?

      # Find traces that have been running longer than max_duration
      cutoff_time = max_duration.ago

      SolidAgent::Trace.where(status: 'running')
                       .where('started_at < ?', cutoff_time)
                       .find_each do |trace|
        # Mark the trace as failed
        trace.update!(
          status: 'failed',
          error: 'Timed out - exceeded max_trace_running_duration',
          completed_at: Time.current
        )

        # Also mark any running spans on this trace as failed
        trace.spans.where(status: 'running').update_all(
          status: 'failed',
          completed_at: Time.current
        )
      end
    end
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add app/jobs/solid_agent/trace_cleanup_job.rb
git commit -m "feat: add TraceCleanupJob for automatic cleanup of stuck traces (Bug 12)"
```

---

## Task 7: Update install generator to inject mount statement (Bug 8)

**Files:**
- Modify: `lib/generators/solid_agent/install/install_generator.rb`

- [ ] **Step 1: Read the current install generator**

```bash
cat lib/generators/solid_agent/install/install_generator.rb
```

- [ ] **Step 2: Add mount injection method**

Add a new method to inject the mount statement into routes.rb:

```ruby
# lib/generators/solid_agent/install/install_generator.rb
require 'rails/generators'
require 'rails/generators/migration'

module SolidAgent
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc 'Installs SolidAgent into your Rails application'

      def copy_initializer
        template 'solid_agent.rb.tt', 'config/initializers/solid_agent.rb'
      end

      def copy_migrations
        rake 'solid_agent:install:migrations'
      end

      def mount_engine
        mount_statement = "  mount SolidAgent::Engine, at: '/solid_agent'"
        routes_file = 'config/routes.rb'

        if File.exist?(routes_file)
          routes_content = File.read(routes_file)

          # Check if mount already exists (case-insensitive, allows whitespace variations)
          unless routes_content.match?(/mount\s+SolidAgent::Engine/i)
            # Insert at the end, before the final 'end' if present
            if routes_content.strip.end_with?('end')
              # Insert before the last 'end'
              last_end_index = routes_content.rindex(/\n\s*end\s*\z/)
              if last_end_index
                routes_content.insert(last_end_index, "#{mount_statement}\n")
              else
                routes_content << "\n#{mount_statement}\n"
              end
            else
              routes_content << "\n#{mount_statement}\n"
            end

            File.write(routes_file, routes_content)
            say "Added mount statement to #{routes_file}"
          else
            say "Mount statement already exists in #{routes_file}", :green
          end
        else
          say "Warning: #{routes_file} not found - please manually add: #{mount_statement}", :yellow
        end
      end

      def show_readme
        say "\nSolidAgent installed! Run `bin/rails db:migrate` to create the tables."
      end
    end
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add lib/generators/solid_agent/install/install_generator.rb
git commit -m "feat: add mount statement injection to install generator (Bug 8)"
```

---

## Task 8: Update README - remove auto-mount claim and dead config (Bugs 8, 9)

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update "Observability Dashboard > Mounting" section**

Find the "Observability Dashboard" section in README.md and update the "Mounting" subsection to remove auto-mount claim and add manual mount instruction:

```markdown
### Mounting

Add the dashboard to your routes:

```ruby
# config/routes.rb
mount SolidAgent::Engine, at: "/solid_agent"
```

This will mount the dashboard at `/solid_agent`.
```

Remove any mention of auto-mounting or `dashboard_route_prefix`.

- [ ] **Step 2: Update Configuration Reference table**

Find the "Configuration Reference" table in README.md and remove the `dashboard_route_prefix` row.

The table should now look like this (verify it matches):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `default_provider` | Symbol | `:openai` | Default LLM provider for agents |
| `default_model` | `SolidAgent::Model` | `Models::OpenAi::GPT_4O` | Default model |
| `dashboard_enabled` | Boolean | `true` | Enable the observability dashboard |
| `vector_store` | Symbol | `:sqlite_vec` | Vector store backend |
| `embedding_provider` | Symbol | `:openai` | Provider for embeddings |
| `embedding_model` | String | `"text-embedding-3-small"` | Embedding model name |
| `http_adapter` | Symbol | `:net_http` | HTTP adapter for LLM requests |
| `trace_retention` | ActiveSupport::Duration | `30.days` | How long to keep trace data |
| `providers` | Hash | `{}` | Provider-specific configuration (API keys, base URLs, etc.) |
| `mcp_clients` | Hash | `{}` | MCP server configurations |

- [ ] **Step 3: Add new `max_trace_running_duration` to Configuration Reference table**

Add this row to the Configuration Reference table:

| `max_trace_running_duration` | ActiveSupport::Duration | `nil` | Maximum time a trace can remain running before being marked as failed. `nil` disables automatic cleanup. |

- [ ] **Step 4: Add documentation for scheduling the cleanup job**

Add a new subsection after "Trace Retention" in the Observability Dashboard section:

```markdown
### Trace Cleanup

To automatically clean up traces that get stuck in the `running` state (e.g., due to crashes or database locking), configure `max_trace_running_duration` and schedule the cleanup job:

```ruby
# config/initializers/solid_agent.rb
SolidAgent.configure do |config|
  config.max_trace_running_duration = 1.hour  # Mark traces as failed after 1 hour
end
```

Then schedule the cleanup job via Solid Queue:

```ruby
# config/initializers/solid_queue.rb or in a cron job
SolidAgent::TraceCleanupJob.set(wait_until: 1.day.from_now, queue: :solid_agent).perform_later
```

You can also schedule it to run periodically using Solid Queue's recurring jobs feature.
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: update README for manual mounting and new max_trace_running_duration config (Bugs 8, 9, 12)"
```

---

## Task 9: Verify all changes and update BUGS.md

**Files:**
- Modify: `BUGS.md`

- [ ] **Step 1: Test the install generator with mount injection**

```bash
# Create a temporary test Rails app
cd /tmp
rails new test_app --no-git
cd test_app

# Add the solid_agent gem to Gemfile (using local path)
echo "gem 'solid_agent', path: '/home/jenaro/solid-agent'" >> Gemfile
bundle install

# Run the install generator
bin/rails generate solid_agent:install

# Verify routes.rb has the mount statement
grep "mount SolidAgent::Engine" config/routes.rb
```

Expected: Mount statement is present in config/routes.rb

- [ ] **Step 2: Verify configuration changes**

```bash
cd /home/jenaro/solid-agent
bundle exec rails console << 'EOF'
# Verify dashboard_route_prefix is removed
begin
  SolidAgent.configuration.dashboard_route_prefix
rescue NoMethodError => e
  puts "✓ dashboard_route_prefix removed: #{e.message}"
end

# Verify max_trace_running_duration is available
if SolidAgent.configuration.max_trace_running_duration.nil?
  puts "✓ max_trace_running_duration defaults to nil"
end
EOF
```

- [ ] **Step 3: Update BUGS.md to mark bugs as fixed**

At the end of BUGS.md, update the status table:

```markdown
| # | Bug | Severity | Status |
|---|-----|----------|--------|
| 8 | Dashboard doesn't auto-mount despite README claim | Moderate | Fixed |
| 9 | `dashboard_route_prefix` config is dead/unused | Low | Fixed |
| 10 | Orphaned `add_otel_ids.rb.tt` template | Low | Fixed |
| 11 | `perform_now` returns `iterations: 1` on failure | Low | Fixed |
| 12 | `perform_later` leaves trace stuck as `running` on LLM failure | Moderate | Fixed |
```

- [ ] **Step 4: Run existing tests**

```bash
cd /home/jenaro/solid-agent
bundle exec rails test
```

Expected: All tests pass (or note any failures to investigate)

- [ ] **Step 5: Commit**

```bash
git add BUGS.md
git commit -m "docs: mark bugs 8-12 as fixed in BUGS.md"
```

---

## Task 10: Final verification and summary

- [ ] **Step 1: Review all commits**

```bash
git log --oneline -10
```

Verify you have commits for:
1. Remove unused dashboard_route_prefix configuration
2. Add max_trace_running_duration configuration
3. Remove orphaned add_otel_ids.rb.tt template
4. Fix perform_now iterations on failure
5. Handle trace update failures
6. Add TraceCleanupJob
7. Add mount injection to install generator
8. Update README documentation
9. Mark bugs as fixed in BUGS.md

- [ ] **Step 2: Verify all files changed**

```bash
git diff --name-only HEAD~9
```

Expected files:
- lib/solid_agent/configuration.rb
- lib/generators/solid_agent/install/install_generator.rb
- lib/generators/solid_agent/install/templates/add_otel_ids.rb.tt (deleted)
- lib/solid_agent/react/loop.rb
- app/jobs/solid_agent/trace_cleanup_job.rb (new)
- README.md
- BUGS.md

- [ ] **Step 3: Create a summary commit**

```bash
git commit --allow-empty -m "fix: complete fixes for bugs 8-12

- Bug 8: Updated README and install generator for manual dashboard mounting
- Bug 9: Removed unused dashboard_route_prefix configuration
- Bug 10: Deleted orphaned add_otel_ids.rb.tt template
- Bug 11: Fixed perform_now to return iterations: 0 on failure
- Bug 12: Added max_trace_running_duration config and TraceCleanupJob for stuck traces"
```

---

## Self-Review

**Spec coverage:**
- ✓ Bug 8: README updated (Task 8), install generator enhanced (Task 7)
- ✓ Bug 9: Config removed from Configuration class (Task 1) and README (Task 8)
- ✓ Bug 10: Template deleted (Task 3)
- ✓ Bug 11: Iterations set to 0 on failure (Task 4)
- ✓ Bug 12: Error handling in build_result (Task 5), new config (Task 2), cleanup job (Task 6), README docs (Task 8)

**Placeholder scan:**
- ✓ No TBD, TODO, or "implement later" found
- ✓ All code steps include actual code
- ✓ All commands include exact syntax

**Type consistency:**
- ✓ `max_trace_running_duration` used consistently across configuration, job, and documentation
- ✓ Method names match throughout (e.g., `TraceCleanupJob`)
- ✓ Configuration option names match README table

**Execution ready:**
- ✓ Each task is 2-5 minutes
- ✓ Each step is one action
- ✓ Exact file paths provided
- ✓ Complete code in every code step
- ✓ Test commands with expected output included
