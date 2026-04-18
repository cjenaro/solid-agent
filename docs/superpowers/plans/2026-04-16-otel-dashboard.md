# OTel-Aware Dashboards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface OpenTelemetry data (trace/span IDs, GenAI semantic convention attributes, OTel span names) in the solid-agent dashboard views.

**Architecture:** Pure ERB + inline CSS + inline JS changes. Helper methods added to `ApplicationHelper` for OTel-aware span labeling, ID truncation, and metadata formatting. Views updated to display OTel badges and metadata tables. No new dependencies, no controller changes.

**Tech Stack:** Ruby ERB, inline CSS, vanilla JS (`navigator.clipboard`).

---

## File Map

| File | Responsibility |
|---|---|
| `app/helpers/solid_agent/application_helper.rb` | OTel-aware `span_label`, `span_otel_meta`, `truncate_id`, `format_meta_value` |
| `app/views/solid_agent/traces/show.html.erb` | Display otel_trace_id + otel_span_id badges |
| `app/views/solid_agent/spans/show.html.erb` | Display otel_span_id badge + metadata table |
| `app/views/layouts/solid_agent.html.erb` | CSS for `.otel-id`, `.tree-otel-meta`, `.metadata-table`; JS for click-to-copy |
| `test/helpers/solid_agent/application_helper_test.rb` | New: tests for all helper methods |

---

## Task 1: Add helper methods to ApplicationHelper

**Files:**
- Modify: `app/helpers/solid_agent/application_helper.rb`
- Create: `test/helpers/solid_agent/application_helper_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/helpers/solid_agent/application_helper_test.rb`:

```ruby
require 'test_helper'

class SolidAgent::ApplicationHelperTest < ActionView::TestCase
  include SolidAgent::ApplicationHelper

  setup do
    ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = OFF')
    SolidAgent::Span.delete_all
    SolidAgent::Trace.delete_all
    SolidAgent::Conversation.delete_all
    ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = ON')

    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
    @trace = SolidAgent::Trace.create!(
      conversation: @conversation, agent_class: 'ResearchAgent', trace_type: :agent_run,
      otel_trace_id: 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6',
      otel_span_id: '1122334455667788'
    )
  end

  test 'span_label returns otel.span.name when present' do
    span = SolidAgent::Span.new(span_type: 'llm', name: 'step_0',
                                metadata: { 'otel.span.name' => 'chat gpt-4o' })
    assert_equal 'chat gpt-4o', span_label(span)
  end

  test 'span_label falls back to span.name when otel.span.name absent' do
    span = SolidAgent::Span.new(span_type: 'llm', name: 'step_0', metadata: {})
    assert_equal 'step_0', span_label(span)
  end

  test 'span_label falls back to span.name when metadata is nil' do
    span = SolidAgent::Span.new(span_type: 'llm', name: 'step_0', metadata: nil)
    assert_equal 'step_0', span_label(span)
  end

  test 'span_otel_meta returns provider for llm spans' do
    span = SolidAgent::Span.new(span_type: 'llm', name: 'step_0',
                                metadata: { 'gen_ai.provider.name' => 'openai' })
    assert_equal ['openai'], span_otel_meta(span)
  end

  test 'span_otel_meta returns empty for tool spans' do
    span = SolidAgent::Span.new(span_type: 'tool', name: 'web_search',
                                metadata: { 'gen_ai.tool.name' => 'web_search' })
    assert_equal [], span_otel_meta(span)
  end

  test 'span_otel_meta includes finish reasons' do
    span = SolidAgent::Span.new(span_type: 'llm', name: 'step_0',
                                metadata: {
                                  'gen_ai.provider.name' => 'anthropic',
                                  'gen_ai.response.finish_reasons' => ['stop']
                                })
    result = span_otel_meta(span)
    assert_includes result, 'anthropic'
    assert_includes result, 'stop'
  end

  test 'span_otel_meta returns empty for chunk spans' do
    span = SolidAgent::Span.new(span_type: 'chunk', name: 'compaction', metadata: {})
    assert_equal [], span_otel_meta(span)
  end

  test 'span_otel_meta handles nil metadata' do
    span = SolidAgent::Span.new(span_type: 'llm', name: 'step_0', metadata: nil)
    assert_equal [], span_otel_meta(span)
  end

  test 'truncate_id truncates long IDs' do
    result = truncate_id('a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6')
    assert_equal 'a1b2c3d4...c5d6', result
  end

  test 'truncate_id returns short IDs as-is' do
    assert_equal 'abc123', truncate_id('abc123')
  end

  test 'truncate_id returns nil for nil input' do
    assert_nil truncate_id(nil)
  end

  test 'format_meta_value renders strings' do
    assert_equal 'hello', format_meta_value('hello')
  end

  test 'format_meta_value renders integers' do
    assert_equal '500', format_meta_value(500)
  end

  test 'format_meta_value renders arrays' do
    assert_equal 'stop, tool_calls', format_meta_value(['stop', 'tool_calls'])
  end

  test 'format_meta_value renders hashes as JSON' do
    result = format_meta_value({ 'key' => 'value' })
    assert_match(/"key"/, result)
    assert_match(/"value"/, result)
  end

  test 'format_meta_value truncates long strings' do
    long_text = 'a' * 300
    result = format_meta_value(long_text)
    assert result.length < 300
    assert result.end_with?('...')
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/helpers/solid_agent/application_helper_test.rb`
Expected: FAIL — methods undefined

- [ ] **Step 3: Implement helper methods**

Update `app/helpers/solid_agent/application_helper.rb`. Replace the existing `span_label` method and add new methods. The full file should be:

```ruby
module SolidAgent
  module ApplicationHelper
    def render_span_tree(span, depth)
      children = span.child_spans.sort_by(&:created_at)
      has_children = children.any? || span.output.present?
      duration = span.duration

      content_tag(:div, class: "tree-node tree-#{span.span_type}", style: "padding-left: #{depth * 1.5}rem") do
        header = content_tag(:div, class: 'tree-header') do
          parts = []
          parts << if has_children
                     content_tag(:span, "\u25BC", class: 'tree-toggle')
                   else
                     content_tag(:span, '', style: 'display:inline-block;width:1rem')
                   end
          parts << span_icon(span.span_type)
          parts << content_tag(:span, span_label(span), class: 'tree-name')
          span_otel_meta(span).each do |meta|
            parts << content_tag(:span, meta, class: 'tree-otel-meta')
          end
          if span.span_type != 'chunk'
            parts << content_tag(:span, span.span_type, class: "badge badge-type badge-#{span.span_type}")
          end
          parts << content_tag(:span, status_dot(span.status), class: 'tree-status')
          parts << content_tag(:span, "#{span.total_tokens} tokens", class: 'tree-meta') if span.total_tokens > 0
          parts << content_tag(:span, "#{duration.round(2)}s", class: 'tree-meta') if duration
          safe_join(parts)
        end

        children_html = ''.html_safe
        if has_children
          detail_html = if span.output.present? && %w[llm tool chunk].include?(span.span_type)
                          content_tag(:div, class: 'tree-detail') do
                            content_tag(:pre, format_output(span))
                          end
                        else
                          ''.html_safe
                        end
          child_spans = children.map { |c| render_span_tree(c, depth + 1) }.join.html_safe
          children_html = content_tag(:div, class: 'tree-children') do
            detail_html + child_spans
          end
        end

        header + children_html
      end
    end

    def render_trace_tree(trace, depth)
      trace_spans = trace.spans.select { |s| s.parent_span_id.nil? }.sort_by(&:created_at)

      content_tag(:div, class: 'tree-node', style: "padding-left: #{depth * 1.5}rem") do
        header = content_tag(:div, class: 'tree-header tree-header-trace') do
          parts = []
          parts << content_tag(:span, "\u25BC", class: 'tree-toggle')
          parts << content_tag(:span, 'agent-run', class: 'tree-icon-trace')
          parts << link_to(trace.agent_class, solid_agent.trace_path(trace), class: 'tree-name tree-name-link')
          parts << content_tag(:span, status_dot(trace.status), class: 'tree-status')
          parts << content_tag(:span, "#{trace.total_tokens} tokens", class: 'tree-meta') if trace.total_tokens > 0
          parts << content_tag(:span, "#{trace.duration.round(2)}s", class: 'tree-meta') if trace.duration
          safe_join(parts)
        end

        children_html = content_tag(:div, class: 'tree-children') do
          trace_spans.map { |s| render_span_tree(s, depth + 1) }.join.html_safe +
            trace.child_traces.map { |ct| render_trace_tree(ct, depth + 1) }.join.html_safe
        end

        header + children_html
      end
    end

    def span_label(span)
      metadata = span.metadata || {}
      metadata['otel.span.name'] || span.name
    end

    def span_otel_meta(span)
      metadata = span.metadata || {}
      parts = []
      if SolidAgent::Telemetry::Serializer::OTLLM_SPAN_TYPES.include?(span.span_type)
        parts << metadata['gen_ai.provider.name'] if metadata['gen_ai.provider.name']
      end
      if metadata['gen_ai.response.finish_reasons'].present?
        parts << Array(metadata['gen_ai.response.finish_reasons']).join(', ')
      end
      parts
    end

    def truncate_id(id, prefix_len: 8, suffix_len: 4)
      return id unless id && id.length > prefix_len + suffix_len + 3
      "#{id[0, prefix_len]}...#{id[-suffix_len..]}"
    end

    def format_meta_value(value)
      case value
      when Hash
        JSON.pretty_generate(value)
      when Array
        value.join(', ')
      when String
        value.length > 200 ? "#{value[0, 197]}..." : value
      else
        value.to_s
      end
    end

    private

    def format_output(span)
      return '' unless span.output

      text = span.output.to_s
      begin
        parsed = JSON.parse(text)
        JSON.pretty_generate(parsed)
      rescue JSON::ParserError
        text.truncate(500)
      end
    end

    def span_icon(span_type)
      icons = {
        'llm' => '&#x1F916;',
        'chunk' => '&#x1F4CB;',
        'tool' => '&#x1F527;',
        'think' => '&#x1F4AD;',
        'act' => '&#x2699;',
        'observe' => '&#x1F441;',
        'tool_execution' => '&#x1F527;',
        'llm_call' => '&#x1F916;'
      }
      content_tag(:span, (icons[span_type] || '&#x25CF;').html_safe, class: 'tree-icon')
    end

    def status_dot(status)
      colors = {
        'completed' => '#22c55e',
        'running' => '#3b82f6',
        'pending' => '#94a3b8',
        'failed' => '#ef4444',
        'error' => '#ef4444',
        'paused' => '#eab308'
      }
      color = colors[status] || '#94a3b8'
      "<span style=\"display:inline-block;width:8px;height:8px;border-radius:50%;background:#{color}\"></span>".html_safe
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/helpers/solid_agent/application_helper_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/helpers/solid_agent/application_helper.rb test/helpers/solid_agent/application_helper_test.rb
git commit -m "feat: add OTel-aware helper methods for span labels, IDs, and metadata"
```

---

## Task 2: Add OTel ID badges to trace detail view

**Files:**
- Modify: `app/views/solid_agent/traces/show.html.erb`

- [ ] **Step 1: Update trace detail view**

Replace the full content of `app/views/solid_agent/traces/show.html.erb` with:

```erb
<h1>Trace #<%= @trace.id %></h1>

<div class="detail">
  <dl>
    <dt>Agent</dt>
    <dd><%= @trace.agent_class %></dd>
    <dt>Status</dt>
    <dd><span class="badge badge-<%= @trace.status %>"><%= @trace.status %></span></dd>
    <% if @trace.otel_trace_id.present? %>
      <dt>Trace ID</dt>
      <dd>
        <span class="otel-id" title="<%= @trace.otel_trace_id %>" data-copy="<%= @trace.otel_trace_id %>">
          <%= truncate_id(@trace.otel_trace_id) %>
        </span>
      </dd>
    <% end %>
    <% if @trace.otel_span_id.present? %>
      <dt>Root Span</dt>
      <dd>
        <span class="otel-id" title="<%= @trace.otel_span_id %>" data-copy="<%= @trace.otel_span_id %>">
          <%= truncate_id(@trace.otel_span_id) %>
        </span>
      </dd>
    <% end %>
    <dt>Input</dt>
    <dd><%= @trace.input %></dd>
    <% if @trace.output.present? %>
      <dt>Output</dt>
      <dd><%= @trace.output %></dd>
    <% end %>
    <% if @trace.error.present? %>
      <dt>Error</dt>
      <dd style="color: #991b1b"><%= @trace.error %></dd>
    <% end %>
    <dt>Tokens</dt>
    <dd><%= @trace.total_tokens %> (<%= @trace.usage['input_tokens'] || 0 %> in / <%= @trace.usage['output_tokens'] || 0 %> out)</dd>
    <dt>Iterations</dt>
    <dd><%= @trace.iteration_count %></dd>
    <% if @trace.started_at %>
      <dt>Started</dt>
      <dd><%= @trace.started_at.strftime("%Y-%m-%d %H:%M:%S") %></dd>
    <% end %>
    <% if @trace.completed_at %>
      <dt>Completed</dt>
      <dd><%= @trace.completed_at.strftime("%Y-%m-%d %H:%M:%S") %></dd>
    <% end %>
    <dt>Conversation</dt>
    <dd><%= link_to "##{@trace.conversation_id}", solid_agent.conversation_path(@trace.conversation) %></dd>
  </dl>
</div>

<h2>Spans</h2>
<% root_spans = @trace.spans.select { |s| s.parent_span_id.nil? }.sort_by(&:created_at) %>
<% if root_spans.any? %>
  <div class="tree">
    <% root_spans.each do |span| %>
      <%= render_span_tree(span, 0) %>
    <% end %>
    <% @trace.child_traces.each do |child| %>
      <%= render_trace_tree(child, 1) %>
    <% end %>
  </div>
<% else %>
  <div class="empty">No spans recorded.</div>
<% end %>
```

- [ ] **Step 2: Run existing tests to verify no regressions**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/controllers/traces_controller_test.rb`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add app/views/solid_agent/traces/show.html.erb
git commit -m "feat: display otel_trace_id and otel_span_id badges on trace detail"
```

---

## Task 3: Add OTel span ID and metadata to span detail view

**Files:**
- Modify: `app/views/solid_agent/spans/show.html.erb`

- [ ] **Step 1: Update span detail view**

Replace the full content of `app/views/solid_agent/spans/show.html.erb` with:

```erb
<h1>Span #<%= @span.id %></h1>

<div class="detail">
  <dl>
    <dt>Type</dt>
    <dd><%= @span.span_type %></dd>
    <dt>Name</dt>
    <dd><%= span_label(@span) %></dd>
    <dt>Status</dt>
    <dd><span class="badge badge-<%= @span.status %>"><%= @span.status %></span></dd>
    <% if @span.otel_span_id.present? %>
      <dt>Span ID</dt>
      <dd>
        <span class="otel-id" title="<%= @span.otel_span_id %>" data-copy="<%= @span.otel_span_id %>">
          <%= truncate_id(@span.otel_span_id) %>
        </span>
      </dd>
    <% end %>
    <dt>Tokens</dt>
    <dd><%= @span.tokens_in %> in / <%= @span.tokens_out %> out</dd>
    <% if @span.started_at %>
      <dt>Started</dt>
      <dd><%= @span.started_at.strftime("%Y-%m-%d %H:%M:%S") %></dd>
    <% end %>
    <% if @span.completed_at %>
      <dt>Completed</dt>
      <dd><%= @span.completed_at.strftime("%Y-%m-%d %H:%M:%S") %></dd>
    <% end %>
    <% if @span.input.present? %>
      <dt>Input</dt>
      <dd><pre><%= @span.input %></pre></dd>
    <% end %>
    <% if @span.output.present? %>
      <dt>Output</dt>
      <dd><pre><%= @span.output %></pre></dd>
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
  </dl>
</div>
```

- [ ] **Step 2: Run existing tests to verify no regressions**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/controllers/traces_controller_test.rb`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add app/views/solid_agent/spans/show.html.erb
git commit -m "feat: display otel_span_id and metadata table on span detail"
```

---

## Task 4: Add CSS and click-to-copy JS to layout

**Files:**
- Modify: `app/views/layouts/solid_agent.html.erb`

- [ ] **Step 1: Add CSS rules**

In `app/views/layouts/solid_agent.html.erb`, add these CSS rules inside the existing `<style>` block, after the `.tree-children.collapsed` rule (before the closing `</style>` tag):

```css
.otel-id {
  font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
  font-size: 0.7rem;
  background: #f1f5f9;
  color: #475569;
  padding: 0.125rem 0.375rem;
  border-radius: 0.25rem;
  cursor: pointer;
  border: 1px solid #e2e8f0;
  transition: background 0.15s, color 0.15s, border-color 0.15s;
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
.metadata-table { width: 100%; box-shadow: none; border: 1px solid #e2e8f0; border-radius: 0.375rem; overflow: hidden; }
.metadata-table td { padding: 0.25rem 0.5rem; font-size: 0.8125rem; border-top: 1px solid #f1f5f9; }
.metadata-table tr:first-child td { border-top: none; }
.metadata-table .meta-key { color: #64748b; font-family: 'SF Mono', 'Fira Code', monospace; font-size: 0.75rem; width: 14rem; white-space: nowrap; }
.metadata-table .meta-value { word-break: break-all; }
```

- [ ] **Step 2: Add click-to-copy JS**

In `app/views/layouts/solid_agent.html.erb`, add this handler inside the existing `<script>` block, after the tree-toggle click handler:

```js
document.addEventListener('click', function(e) {
  var otelId = e.target.closest('.otel-id');
  if (otelId && otelId.dataset.copy) {
    navigator.clipboard.writeText(otelId.dataset.copy).then(function() {
      var fullId = otelId.dataset.copy;
      var displayId = fullId.length > 12
        ? fullId.substring(0, 8) + '...' + fullId.slice(-4)
        : fullId;
      otelId.classList.add('copied');
      otelId.textContent = 'Copied!';
      setTimeout(function() {
        otelId.classList.remove('copied');
        otelId.textContent = displayId;
      }, 1500);
    });
  }
});
```

- [ ] **Step 3: Run the full test suite to verify no regressions**

Run: `cd /home/jenaro/solid-agent && bundle exec ruby -Itest test/`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add app/views/layouts/solid_agent.html.erb
git commit -m "feat: add CSS and click-to-copy JS for OTel badges and metadata table"
```
