interface Span {
  id: number
  span_type: string
  name: string
  status: string
  tokens_in: number
  tokens_out: number
  started_at: string | null
  completed_at: string | null
  parent_span_id: number | null
}

interface SpanTreeProps {
  spans: Span[]
}

export default function SpanTree({ spans }: SpanTreeProps) {
  const getDuration = (span: Span) => {
    if (!span.started_at || !span.completed_at) return null
    return ((new Date(span.completed_at).getTime() - new Date(span.started_at).getTime()) / 1000).toFixed(2)
  }

  const typeColors: Record<string, string> = {
    think: "bg-purple-50 border-purple-200",
    act: "bg-orange-50 border-orange-200",
    observe: "bg-blue-50 border-blue-200",
    tool_execution: "bg-green-50 border-green-200",
    llm_call: "bg-gray-50 border-gray-200",
  }

  return (
    <div className="space-y-1">
      {spans.filter(s => !s.parent_span_id).map((span) => (
        <div key={span.id} className={`rounded border p-3 ${typeColors[span.span_type] || ""}`}>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="font-mono text-xs text-gray-500 uppercase">{span.span_type}</span>
              <span className="font-medium">{span.name}</span>
            </div>
            <div className="flex items-center gap-4 text-sm text-gray-600">
              {getDuration(span) && <span>{getDuration(span)}s</span>}
              {span.tokens_in > 0 && (
                <span>{span.tokens_in} in / {span.tokens_out} out</span>
              )}
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}
