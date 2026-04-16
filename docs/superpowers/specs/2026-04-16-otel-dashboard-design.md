# OTel-Aware Dashboards

## Goal

Surface OpenTelemetry data (trace/span IDs, GenAI semantic convention attributes, OTel span names) in the solid-agent dashboard so operators can see distributed tracing identifiers and understand what operations each span represents.

## Context

The OTel compliance work (`2026-04-15-otel-compliance.md`) added:
- `otel_trace_id` (32-hex) and `otel_span_id` (16-hex) columns to traces and spans
- `gen_ai.*` metadata attributes on spans via `Telemetry::Serializer` (e.g. `gen_ai.operation.name`, `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.tool.name`)
- `otel.span.name` for human-readable OTel-convention span names (e.g. `chat gpt-4o`, `execute_tool web_search`)

None of this data appears in the dashboard UI today.

## Design Decisions

- **No new dependencies.** All changes are ERB template + inline CSS + inline JS. Copy-to-clipboard uses `navigator.clipboard.writeText` (zero-dep).
- **OTel IDs as small inline badges** next to existing IDs on trace and span detail pages. Truncated with `title` attribute for full value. Click-to-copy.
- **OTel span names replace raw span names** in the span tree. Fall back to `span.name` when `otel.span.name` is absent (backward compat for traces created before OTel work).
- **Key gen_ai attributes shown inline** in the span tree row (provider name for LLM spans). Full metadata on span detail page.
- **Trace list pages unchanged** — OTel details belong on detail pages.

## Changes

### 1. Span Tree Helper (`app/helpers/solid_agent/application_helper.rb`)

**`span_label`** — use `otel.span.name` from metadata when present:

```ruby
def span_label(span)
  metadata = span.metadata || {}
  metadata['otel.span.name'] || span.name
end
```

**Inline metadata badges** — add a helper method that returns key gen_ai attributes as small badge elements. Shown after the span label in the tree header:

- For LLM-type spans (`llm`, `llm_call`, `think`): show `gen_ai.provider.name`
- For tool-type spans (`tool`, `tool_execution`, `act`): no extra badge (tool name is already in the OTel span name)
- For all spans: show `gen_ai.response.finish_reasons` if present

```ruby
def span_otel_meta(span)
  metadata = span.metadata || {}
  parts = []
  if Telemetry::Serializer::OTLLM_SPAN_TYPES.include?(span.span_type)
    parts << metadata['gen_ai.provider.name'] if metadata['gen_ai.provider.name']
  end
  if metadata['gen_ai.response.finish_reasons'].present?
    parts << Array(metadata['gen_ai.response.finish_reasons']).join(', ')
  end
  parts
end
```

Wire `span_otel_meta` into `render_span_tree` after `tree-name`, rendering each part as `<span class="tree-otel-meta">value</span>`.

### 2. Trace Detail (`app/views/solid_agent/traces/show.html.erb`)

Add two fields to the `<dl>`:

```erb
<dt>Trace ID</dt>
<dd>
  #<%= @trace.id %>
  <span class="otel-id" title="<%= @trace.otel_trace_id %>" data-copy="<%= @trace.otel_trace_id %>">
    <%= truncate_id(@trace.otel_trace_id) %>
  </span>
</dt>
<dt>Root Span</dt>
<dd>
  <span class="otel-id" title="<%= @trace.otel_span_id %>" data-copy="<%= @trace.otel_span_id %>">
    <%= truncate_id(@trace.otel_span_id) %>
  </span>
</dt>
```

Add `truncate_id` helper:

```ruby
def truncate_id(id, prefix_len: 8, suffix_len: 4)
  return id unless id && id.length > prefix_len + suffix_len + 3
  "#{id[0, prefix_len]}...#{id[-suffix_len..]}"
end
```

### 3. Span Detail (`app/views/solid_agent/spans/show.html.erb`)

Add `otel_span_id` badge next to the span ID. Add a **Metadata** section that renders `span.metadata` as a key-value table, filtering out internal keys (starting with `_`) and the `otel.span.name` key (already shown as the span name):

```erb
<% if @span.otel_span_id.present? %>
  <dt>Span ID</dt>
  <dd>
    <span class="otel-id" title="<%= @span.otel_span_id %>" data-copy="<%= @span.otel_span_id %>">
      <%= truncate_id(@span.otel_span_id) %>
    </span>
  </dd>
<% end %>

<% otel_metadata = (@span.metadata || {}).except('otel.span.name').reject { |k, _| k.start_with?('_') } %>
<% if otel_metadata.any? %>
  <dt>Metadata</dt>
  <dd>
    <table class="metadata-table">
      <% otel_metadata.each do |key, value| %>
        <tr>
          <td class="meta-key"><%= key %></td>
          <td class="meta-value"><%= format_meta_value(value) %></td>
        </tr>
      <% end %>
    </table>
  </dd>
<% end %>
```

Add `format_meta_value` helper — handles arrays, hashes, and long strings gracefully (truncate long strings, JSON-encode complex values).

### 4. Layout CSS (`app/views/layouts/solid_agent.html.erb`)

Add styles for new elements:

```css
.otel-id {
  font-family: 'SF Mono', 'Fira Code', monospace;
  font-size: 0.7rem;
  background: #f1f5f9;
  color: #475569;
  padding: 0.125rem 0.375rem;
  border-radius: 0.25rem;
  cursor: pointer;
  border: 1px solid #e2e8f0;
}
.otel-id:hover { background: #e2e8f0; }
.otel-id.copied { background: #dcfce7; color: #166534; border-color: #86efac; }
.tree-otel-meta {
  font-size: 0.6875rem;
  color: #94a3b8;
  background: #f8fafc;
  padding: 0.0625rem 0.375rem;
  border-radius: 0.25rem;
}
.metadata-table { width: 100%; box-shadow: none; }
.metadata-table td { padding: 0.25rem 0.5rem; font-size: 0.8125rem; }
.metadata-table .meta-key { color: #64748b; font-family: monospace; width: 12rem; }
.metadata-table .meta-value { word-break: break-all; }
```

### 5. Click-to-Copy JS (`app/views/layouts/solid_agent.html.erb`)

Add to existing `<script>` block — no external dependency:

```js
document.addEventListener('click', function(e) {
  var otelId = e.target.closest('.otel-id');
  if (otelId && otelId.dataset.copy) {
    navigator.clipboard.writeText(otelId.dataset.copy).then(function() {
      otelId.classList.add('copied');
      otelId.textContent = 'Copied!';
      setTimeout(function() {
        otelId.classList.remove('copied');
        otelId.textContent = otelId.dataset.copy.length > 12
          ? otelId.dataset.copy.substring(0, 8) + '...' + otelId.dataset.copy.slice(-4)
          : otelId.dataset.copy;
      }, 1500);
    });
  }
});
```

### 6. Trace Detail — Show trace OTel context for child traces

In `render_trace_tree`, show the `otel_trace_id` is the same as the parent (propagated). No UI change needed — just the span tree changes above cover this.

## Files Modified

| File | Change |
|---|---|
| `app/helpers/solid_agent/application_helper.rb` | `span_label` uses `otel.span.name`; add `span_otel_meta`, `truncate_id`, `format_meta_value` |
| `app/views/solid_agent/traces/show.html.erb` | Add otel_trace_id and otel_span_id badges |
| `app/views/solid_agent/spans/show.html.erb` | Add otel_span_id badge + metadata key-value table |
| `app/views/layouts/solid_agent.html.erb` | CSS for `.otel-id`, `.tree-otel-meta`, `.metadata-table`; JS for click-to-copy |
| `test/helpers/application_helper_test.rb` | Tests for `span_label` with OTel names, `truncate_id`, `format_meta_value`, `span_otel_meta` |

## What's NOT Changing

- Trace index and dashboard recent traces table — overview pages don't need OTel detail
- Conversations, agents, tools pages — no OTel data relevant there
- Controller logic — no query changes needed, all data already loaded via existing eager-loading
- Database schema — all columns already exist from the OTel compliance work
