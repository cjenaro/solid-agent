import Layout from "../../components/Layout"
import TraceStatusBadge from "../../components/TraceStatusBadge"
import { Link } from "@inertiajs/react"

interface ConversationShowProps {
  conversation: {
    id: number
    agent_class: string
    status: string
    metadata: object
    created_at: string
    updated_at: string
    traces: Array<{
      id: number
      agent_class: string
      status: string
      started_at: string | null
      completed_at: string | null
      usage: { input_tokens: number; output_tokens: number } | null
      duration: number | null
    }>
    messages: Array<{
      id: number
      role: string
      content: string
      tool_call_id: string | null
      token_count: number
      model: string | null
      created_at: string
    }>
  }
}

export default function ConversationShow({ conversation }: ConversationShowProps) {
  return (
    <Layout>
      <div className="mb-6">
        <div className="flex items-center gap-3 mb-2">
          <h1 className="text-2xl font-bold">Conversation #{conversation.id}</h1>
          <TraceStatusBadge status={conversation.status} />
        </div>
        <div className="flex gap-4 text-sm text-gray-600">
          <span className="font-mono">{conversation.agent_class}</span>
          <span>{conversation.traces.length} traces</span>
          <span>{conversation.messages.length} messages</span>
        </div>
      </div>

      {conversation.traces.length > 0 && (
        <div className="mb-6">
          <h2 className="text-lg font-semibold mb-3">Traces</h2>
          <div className="space-y-2">
            {conversation.traces.map((trace) => (
              <Link key={trace.id} href={`/solid_agent/traces/${trace.id}`}
                className="block rounded-lg border bg-white p-3 hover:bg-gray-50">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <span className="font-mono text-sm">#{trace.id}</span>
                    <span className="text-sm">{trace.agent_class}</span>
                    <TraceStatusBadge status={trace.status} />
                  </div>
                  <div className="flex items-center gap-4 text-sm text-gray-600">
                    {trace.duration && <span>{trace.duration.toFixed(1)}s</span>}
                    {trace.usage && (
                      <span>{(trace.usage.input_tokens + trace.usage.output_tokens).toLocaleString()} tokens</span>
                    )}
                  </div>
                </div>
              </Link>
            ))}
          </div>
        </div>
      )}

      <div>
        <h2 className="text-lg font-semibold mb-3">Messages</h2>
        <div className="space-y-3">
          {conversation.messages.map((msg) => (
            <div key={msg.id} className={`rounded-lg border p-4 ${
              msg.role === "user" ? "bg-blue-50 border-blue-200" :
              msg.role === "assistant" ? "bg-green-50 border-green-200" :
              msg.role === "system" ? "bg-gray-50 border-gray-200" :
              "bg-orange-50 border-orange-200"
            }`}>
              <div className="flex items-center justify-between mb-1">
                <span className="text-sm font-semibold uppercase">{msg.role}</span>
                <div className="flex gap-2 text-xs text-gray-500">
                  {msg.model && <span>{msg.model}</span>}
                  {msg.token_count > 0 && <span>{msg.token_count} tokens</span>}
                </div>
              </div>
              <p className="whitespace-pre-wrap text-sm">{msg.content}</p>
            </div>
          ))}
        </div>
      </div>
    </Layout>
  )
}
