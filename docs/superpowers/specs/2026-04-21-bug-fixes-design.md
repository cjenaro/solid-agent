# Bug Fixes Design

**Date:** 2026-04-21
**Status:** Approved

## Overview

This document describes fixes for 5 bugs discovered during gem integration testing (bugs 8-12 from BUGS.md).

## Bug 8: Dashboard doesn't auto-mount despite README claim

**Severity:** Moderate

**Problem:** README states dashboard auto-mounts at `/solid_agent` when `config.dashboard_enabled` is `true`, but `SolidAgent::Engine` is a bare `Rails::Engine` with no auto-mounting logic.

**Fix:** Update documentation and inject mount statement via install generator.

### Implementation

1. Update README "Observability Dashboard > Mounting" section:
   - Remove auto-mount claim
   - Add clear instruction: "Add to `config/routes.rb`: `mount SolidAgent::Engine, at: '/solid_agent'`"
   - Remove outdated `dashboard_route_prefix` example

2. Update install generator (`lib/generators/solid_agent/install/install_generator.rb`):
   - Add method to inject mount line into `config/routes.rb`
   - Check if mount already exists to avoid duplicates
   - Use regex pattern to match existing mount statements

### Files Changed
- `README.md`
- `lib/generators/solid_agent/install/install_generator.rb`

---

## Bug 9: `dashboard_route_prefix` config is dead/unused

**Severity:** Low

**Problem:** `Configuration` class exposes `dashboard_route_prefix` but it's never used - setting it has no effect.

**Fix:** Remove the unused configuration option entirely.

### Implementation

1. Remove from `lib/solid_agent/configuration.rb`:
   - Remove `:dashboard_route_prefix` from `attr_accessor` list
   - Remove from `initialize` method (`@dashboard_route_prefix = 'solid_agent'`)

2. Remove from `README.md`:
   - Remove from "Configuration Reference" table
   - Remove from "Observability Dashboard > Mounting" section

### Files Changed
- `lib/solid_agent/configuration.rb`
- `README.md`

---

## Bug 10: Orphaned `add_otel_ids.rb.tt` template

**Severity:** Low

**Problem:** Template exists but is never used by install generator, and main migrations already include the otel columns. If used, it would cause migration conflicts.

**Fix:** Delete the dead template file.

### Implementation

1. Delete `lib/generators/solid_agent/install/templates/add_otel_ids.rb.tt`

### Files Changed
- Delete: `lib/generators/solid_agent/install/templates/add_otel_ids.rb.tt`

---

## Bug 11: `perform_now` returns `iterations: 1` on failure

**Severity:** Low

**Problem:** When `perform_now` fails (e.g., no API key), result returns `iterations: 1` even though no actual ReAct loop iteration completed. The trace has `iteration_count` incremented by the loop before the LLM call fails.

**Fix:** Explicitly set `iterations: 0` in the result when status is `:failed`.

### Implementation

1. In `lib/solid_agent/react/loop.rb`, modify `build_result` method:
   - When `status: :failed`, set `iterations: 0` in `Agent::Result` instead of using `@trace.iteration_count`
   - This correctly reflects that no iteration was completed before failure

### Files Changed
- `lib/solid_agent/react/loop.rb`

---

## Bug 12: `perform_later` leaves trace stuck as `running` on LLM failure

**Severity:** Moderate

**Problem:** When `perform_later` is used with Rails async adapter and LLM call fails, trace is left stuck with `status: 'running'`. The `@trace.update!` in `build_result` appears to silently fail due to SQLite locking contention between async job thread and main thread.

**Fix:** Two-part solution - ensure status updates in error path and add configurable cleanup.

### Implementation

1. In `lib/solid_agent/react/loop.rb`, modify `build_result` method:
   - Wrap `@trace.update!` in begin/rescue block
   - Log any update failures but continue to return result
   - Prevents the update failure from blocking the error handling flow

2. Add new configuration option in `lib/solid_agent/configuration.rb`:
   - `max_trace_running_duration` (default: `nil`)
   - When set, defines maximum time a trace can remain `running` before being marked as `failed`
   - `nil` means no automatic cleanup (backward compatible)

3. Create new job `app/jobs/solid_agent/trace_cleanup_job.rb`:
   - Scheduled job that runs periodically (e.g., daily via Solid Queue)
   - Finds traces with `status: 'running'` where `started_at < max_trace_running_duration.ago`
   - Updates those traces to `status: 'failed', error: 'Timed out'`
   - Also updates any `running` spans on those traces to `status: 'failed'`

4. Update `README.md`:
   - Add `max_trace_running_duration` to configuration table
   - Document how to schedule the cleanup job if using the feature

### Files Changed
- `lib/solid_agent/configuration.rb`
- `lib/solid_agent/react/loop.rb`
- `app/jobs/solid_agent/trace_cleanup_job.rb` (new)
- `README.md`

---

## Testing Strategy

1. **Bug 8:** Test install generator on fresh Rails app, verify mount line is injected correctly
2. **Bug 9:** Verify `SolidAgent.configuration.dashboard_route_prefix` raises `NoMethodError`
3. **Bug 10:** Verify template file is deleted and no references remain
4. **Bug 11:** Test `perform_now` with invalid API key, verify `result.iterations == 0`
5. **Bug 12:**
   - Test that failed traces still get status updated in error path
   - Test cleanup job with various `max_trace_running_duration` settings
   - Verify it only affects `running` traces, not `completed` or `failed`

## Backward Compatibility

- Bug 8: Existing users who already added mount line manually are unaffected
- Bug 9: `dashboard_route_prefix` was never functional, removal is non-breaking
- Bug 10: Template was never used, deletion is non-breaking
- Bug 11: Fix changes behavior for failed traces (iterations now 0 instead of 1), which is more correct
- Bug 12: Configurable cleanup is opt-in (default `nil`), no change for existing users

## Dependencies

None - all changes use existing Rails and Solid Queue functionality.
