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

    private

    def span_label(span)
      case span.span_type
      when 'llm'
        span.name
      when 'chunk'
        span.name
      when 'tool'
        span.name
      else
        span.name
      end
    end

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
