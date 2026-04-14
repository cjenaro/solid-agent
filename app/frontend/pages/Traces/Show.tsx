import Layout from "../../components/Layout"
import SpanTree from "../../components/SpanTree"
import TraceStatusBadge from "../../components/TraceStatusBadge"

interface TraceShowProps {
  trace: {
    id: number
    agent_class: string
    status: string
    started_at: string | null
    completed_at: string | null
    usage: { input_tokens: number; output_tokens: number } | null
    iteration_count: number
    input: string | null
    output: string | null
    error: string | null
    created_at: string
    spans: Array<{
      id: number
      span_type: string
      name: string
      status: string
      tokens_in: number
      tokens_out: number
      started_at: string | null
      completed_at: string | null
      input: string | null
      output: string | null
      parent_span_id: number | null
    }>
    child_traces: Array<{
      id: number
      agent_class: string
      status: string
      started_at: string | null
      completed_at: string | null
    }>
    conversation: { id: number }
  }
  parent_trace: { id: number; agent_class: string } | null
}

export default function TraceShow({ trace, parent_trace }: TraceShowProps) {
  const totalTokens = trace.usage ? trace.usage.input_tokens + trace.usage.output_tokens : 0

  return (
    <Layout>
      <div className="mb-6">
        <div className="flex items-center gap-3 mb-2">
          <h1 className="text-2xl font-bold">Trace #{trace.id}</h1>
          <TraceStatusBadge status={trace.status} />
        </div>
        <div className="flex gap-4 text-sm text-gray-600">
          <span className="font-mono">{trace.agent_class}</span>
          {trace.started_at && trace.completed_at && (
            <span>{((new Date(trace.completed_at).getTime() - new Date(trace.started_at).getTime()) / 1000).toFixed(1)}s</span>
          )}
          <span>{totalTokens.toLocaleString()} tokens</span>
          <span>{trace.iteration_count} iterations</span>
        </div>
        {parent_trace && (
          <a href={`/solid_agent/traces/${parent_trace.id}`} className="text-sm text-blue-600 hover:underline">
            Parent: #{parent_trace.id} ({parent_trace.agent_class})
          </a>
        )}
      </div>

      {trace.input && (
        <div className="mb-4 rounded-lg border bg-white p-4">
          <h3 className="text-sm font-semibold text-gray-500 mb-1">Input</h3>
          <p className="whitespace-pre-wrap">{trace.input}</p>
        </div>
      )}

      <div className="mb-4">
        <h2 className="text-lg font-semibold mb-3">Execution Spans</h2>
        <SpanTree spans={trace.spans} />
      </div>

      {trace.child_traces.length > 0 && (
        <div className="mb-4">
          <h2 className="text-lg font-semibold mb-3">Child Traces</h2>
          <div className="space-y-2">
            {trace.child_traces.map((child) => (
              <a key={child.id} href={`/solid_agent/traces/${child.id}`}
                className="block rounded-lg border bg-white p-3 hover:bg-gray-50">
                <div className="flex items-center gap-3">
                  <span className="font-mono text-sm">#{child.id}</span>
                  <span className="text-sm">{child.agent_class}</span>
                  <TraceStatusBadge status={child.status} />
                </div>
              </a>
            ))}
          </div>
        </div>
      )}

      {trace.output && (
        <div className="mb-4 rounded-lg border bg-white p-4">
          <h3 className="text-sm font-semibold text-gray-500 mb-1">Output</h3>
          <p className="whitespace-pre-wrap">{trace.output}</p>
        </div>
      )}

      {trace.error && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4">
          <h3 className="text-sm font-semibold text-red-800 mb-1">Error</h3>
          <p className="text-red-700 whitespace-pre-wrap">{trace.error}</p>
        </div>
      )}
    </Layout>
  )
}
