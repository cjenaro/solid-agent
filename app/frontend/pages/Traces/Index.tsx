import Layout from "../../components/Layout"
import TraceStatusBadge from "../../components/TraceStatusBadge"
import { Link } from "@inertiajs/react"

interface Trace {
  id: number
  agent_class: string
  status: string
  started_at: string | null
  completed_at: string | null
  usage: { input_tokens: number; output_tokens: number } | null
  iteration_count: number
  created_at: string
  conversation: { id: number; agent_class: string } | null
}

interface TracesIndexProps {
  traces: Trace[]
  agent_classes: string[]
  statuses: string[]
}

export default function TracesIndex({ traces, agent_classes, statuses }: TracesIndexProps) {
  return (
    <Layout>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Traces</h1>
        <div className="flex gap-3">
          <select className="rounded border px-3 py-1.5 text-sm">
            <option value="">All Agents</option>
            {agent_classes.map((a) => <option key={a} value={a}>{a}</option>)}
          </select>
          <select className="rounded border px-3 py-1.5 text-sm">
            <option value="">All Statuses</option>
            {statuses.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </div>
      </div>

      <div className="rounded-lg border bg-white">
        <table className="w-full">
          <thead>
            <tr className="border-b text-left text-sm text-gray-500">
              <th className="px-4 py-2">ID</th>
              <th className="px-4 py-2">Agent</th>
              <th className="px-4 py-2">Status</th>
              <th className="px-4 py-2">Iterations</th>
              <th className="px-4 py-2">Tokens</th>
              <th className="px-4 py-2">Created</th>
            </tr>
          </thead>
          <tbody>
            {traces.map((trace) => (
              <tr key={trace.id} className="border-b hover:bg-gray-50">
                <td className="px-4 py-2">
                  <Link href={`/solid_agent/traces/${trace.id}`} className="text-blue-600 hover:underline">
                    #{trace.id}
                  </Link>
                </td>
                <td className="px-4 py-2 font-mono text-sm">{trace.agent_class}</td>
                <td className="px-4 py-2"><TraceStatusBadge status={trace.status} /></td>
                <td className="px-4 py-2 text-sm">{trace.iteration_count}</td>
                <td className="px-4 py-2 text-sm">
                  {trace.usage ? (trace.usage.input_tokens + trace.usage.output_tokens).toLocaleString() : "—"}
                </td>
                <td className="px-4 py-2 text-sm text-gray-500">{trace.created_at}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Layout>
  )
}
