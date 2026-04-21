# SolidAgent Integration Test — Bugs & Issues

Tested `solid_agent` gem (v0.1.0, path: `../solid-agent`) integrated into a Rails 8.1 + Inertia + Vite app.
Date: 2026-04-18

> All items below are **new findings** not covered by the previously-fixed Bugs 1–7 in the gem's own `BUGS.md`.

---

## Bug 8: README claims dashboard auto-mounts — it does not

**Severity:** Moderate (confusing onboarding)

**Files:**
- `README.md` (Dashboard section)
- `lib/solid_agent/engine.rb`

**Description:**
The README states:

> The dashboard mounts automatically at `/solid_agent` when `config.dashboard_enabled` is `true` (the default).

However, `SolidAgent::Engine` is a bare `Rails::Engine` with `isolate_namespace` — it has no auto-mounting logic (no `ActiveSupport.on_load`, no engine initializer, no route injection). Users **must** manually add to `config/routes.rb`:

```ruby
mount SolidAgent::Engine, at: "/solid_agent"
```

Without this, `bin/rails routes` shows zero SolidAgent routes and `/solid_agent` returns 404.

**Fix options:**
1. Add auto-mounting via an engine initializer (e.g., `initializer "solid_agent.mount", before: :set_routes_reloader_hook`)
2. Update README to instruct users to add the `mount` line manually (the install generator could also inject it)

---

## Bug 9: `dashboard_route_prefix` config is dead — defined but never used

**Severity:** Low

**Files:**
- `lib/solid_agent/configuration.rb` (attr_accessor defined)
- No references anywhere else in the codebase

**Description:**
The `Configuration` class exposes `dashboard_route_prefix` (default: `'solid_agent'`) and the README documents it as a way to customize the route prefix. However:
- The Engine routes are hardcoded in `config/routes.rb`
- No code reads `dashboard_route_prefix` to adjust mount path or route generation
- Setting it has no effect

**Fix:** Either wire it into the engine (e.g., as a configurable mount path) or remove it from the Configuration and README.

---

## Bug 10: Install generator has an orphaned `add_otel_ids.rb.tt` template

**Severity:** Low (unused dead code)

**Files:**
- `lib/generators/solid_agent/install/templates/add_otel_ids.rb.tt` — exists but never used
- `lib/generators/solid_agent/install/install_generator.rb` — only copies `solid_agent.rb.tt` and runs migrations

**Description:**
The template `add_otel_ids.rb.tt` adds `otel_trace_id`, `otel_span_id`, and `otel_span_id` columns to traces/spans. However:
1. The install generator never copies this template
2. The main migrations (`create_solid_agent_traces`, `create_solid_agent_spans`) **already include** the `otel_*` columns

This means the template is dead code that would also cause a migration failure if someone tried to use it (adding columns that already exist).

**Fix:** Delete `add_otel_ids.rb.tt` since the columns are already in the main migrations.

---

## Bug 11: `perform_now` returns `iterations: 1` on failure — should be `0`

**Severity:** Low (misleading API)

**Files:**
- `lib/solid_agent/agent/base.rb` (rescue block)

**Description:**
When `perform_now` fails (e.g., no API key), the result returns `iterations: 1` even though no actual ReAct loop iteration completed. The trace in the DB has `iteration_count` defaulting to its schema value.

Observed:
```ruby
result = TestAgent.perform_now("Hello")
result.iterations  # => 1   (expected: 0)
result.status      # => :failed
```

The `rescue` block in `Base.perform_now` uses `trace&.iteration_count || 0`, but the trace was created with a default `iteration_count` (likely 1 or set during the partial run).

**Fix:** In the rescue block, explicitly set `iterations: 0` when the error occurs before any iteration completes, or check `trace.status` to determine actual iteration count.

---

## Design Note: `delegate` and `agent_tool` are separate from `agent_tool_registry`

**Severity:** Not a bug — but may confuse users

**Description:**
The Orchestration DSL's `delegate` and `agent_tool` methods store tools in separate hashes (`delegates`, `agent_tools`) rather than in the shared `agent_tool_registry`. This means:
- `MyAgent.agent_tool_registry.tool_count` returns `0` even when delegates are defined
- Tools are accessed via `MyAgent.delegates` / `MyAgent.agent_tools` / `MyAgent.orchestration_tools`
- The ReAct loop must know to check both registries

This is likely intentional for separation of concerns, but worth documenting since users may expect `agent_tool_registry` to contain all tools.

---

## Bug 12: `perform_later` via async adapter leaves trace stuck as `running` when LLM call fails

**Severity:** Moderate

**Files:**
- `lib/solid_agent/react/loop.rb` (rescue block)
- `lib/solid_agent/run_job.rb` (rescue block)

**Description:**
When `perform_later` is used with the default Rails async queue adapter (development), and the LLM call fails (e.g., no API key), the trace is left stuck with `status: "running"` and the LLM span is also stuck as `status: "running"` with `tokens_in: 0, tokens_out: 0`.

The sequence:
1. `RunJob#perform` calls `trace.start!` → `status: "running"`
2. `React::Loop#run` increments iteration_count, creates LLM span as `status: "running"`
3. `@http_adapter.call(request)` fails (401 Unauthorized)
4. `@provider.parse_response` raises `ProviderError`
5. `React::Loop#run` rescue catches it and calls `build_result(status: :failed)`
6. `build_result` calls `@trace.update!(status: 'failed')` — **but this appears to silently fail**, likely due to SQLite locking contention between the async job thread and the main thread (which was simultaneously running `perform_now`)
7. The trace and LLM span are left permanently as `"running"`

**Impact:** Stale `"running"` traces clutter the dashboard and make it hard to distinguish real in-progress work from failed runs.

**Fix options:**
1. Wrap `build_result`'s `@trace.update!` in its own begin/rescue to ensure the status is always updated
2. Add a `SolidAgent::Trace.where(status: 'running').where('started_at < ?', 1.hour.ago).update_all(status: 'failed', error: 'Timed out')` cleanup job
3. Use `update` instead of `update!` in the rescue path to avoid raising on validation errors

---

## Summary

| # | Bug | Severity | Status |
|---|-----|----------|--------|
| 8 | Dashboard doesn't auto-mount despite README claim | Moderate | Fixed |
| 9 | `dashboard_route_prefix` config is dead/unused | Low | Fixed |
| 10 | Orphaned `add_otel_ids.rb.tt` template | Low | Fixed |
| 11 | `perform_now` returns `iterations: 1` on failure | Low | Fixed |
| 12 | `perform_later` leaves trace stuck as `running` on LLM failure | Moderate | Fixed |
