import Layout from "../components/Layout"

interface Stats {
  total_traces: number
  active_traces: number
  total_conversations: number
  total_tokens: number
  agents: string[]
}

interface DashboardProps {
  stats: Stats
  recent_traces: Array<{
    id: number
    agent_class: string
    status: string
    started_at: string | null
    created_at: string
    usage: { input_tokens: number; output_tokens: number } | null
  }>
}

export default function Dashboard({ stats, recent_traces }: DashboardProps) {
  return (
    <Layout>
      <h1 className="text-2xl font-bold mb-6">SolidAgent Dashboard</h1>

      <div className="grid grid-cols-4 gap-4 mb-8">
        <div className="rounded-lg border bg-white p-4">
          <p className="text-sm text-gray-500">Total Traces</p>
          <p className="text-2xl font-bold">{stats.total_traces}</p>
        </div>
        <div className="rounded-lg border bg-white p-4">
          <p className="text-sm text-gray-500">Active Traces</p>
          <p className="text-2xl font-bold">{stats.active_traces}</p>
        </div>
        <div className="rounded-lg border bg-white p-4">
          <p className="text-sm text-gray-500">Total Tokens</p>
          <p className="text-2xl font-bold">{stats.total_tokens.toLocaleString()}</p>
        </div>
        <div className="rounded-lg border bg-white p-4">
          <p className="text-sm text-gray-500">Conversations</p>
          <p className="text-2xl font-bold">{stats.total_conversations}</p>
        </div>
      </div>

      <div className="rounded-lg border bg-white">
        <div className="border-b px-4 py-3">
          <h2 className="font-semibold">Recent Traces</h2>
        </div>
        <table className="w-full">
          <thead>
            <tr className="border-b text-left text-sm text-gray-500">
              <th className="px-4 py-2">ID</th>
              <th className="px-4 py-2">Agent</th>
              <th className="px-4 py-2">Status</th>
              <th className="px-4 py-2">Tokens</th>
              <th className="px-4 py-2">Created</th>
            </tr>
          </thead>
          <tbody>
            {recent_traces.map((trace) => (
              <tr key={trace.id} className="border-b hover:bg-gray-50">
                <td className="px-4 py-2">
                  <a href={`/solid_agent/traces/${trace.id}`} className="text-blue-600 hover:underline">
                    #{trace.id}
                  </a>
                </td>
                <td className="px-4 py-2 font-mono text-sm">{trace.agent_class}</td>
                <td className="px-4 py-2">
                  <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium
                    ${trace.status === "completed" ? "bg-green-100 text-green-800" : ""}
                    ${trace.status === "running" ? "bg-blue-100 text-blue-800" : ""}
                    ${trace.status === "failed" ? "bg-red-100 text-red-800" : ""}
                    ${trace.status === "paused" ? "bg-yellow-100 text-yellow-800" : ""}
                  `}>
                    {trace.status}
                  </span>
                </td>
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
