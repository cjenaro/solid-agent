import Layout from "../../components/Layout"
import TraceStatusBadge from "../../components/TraceStatusBadge"
import { Link } from "@inertiajs/react"

interface Conversation {
  id: number
  agent_class: string
  status: string
  created_at: string
  updated_at: string
  traces: Array<{ id: number; status: string }>
}

interface ConversationsIndexProps {
  conversations: Conversation[]
}

export default function ConversationsIndex({ conversations }: ConversationsIndexProps) {
  return (
    <Layout>
      <h1 className="text-2xl font-bold mb-6">Conversations</h1>

      <div className="rounded-lg border bg-white">
        <table className="w-full">
          <thead>
            <tr className="border-b text-left text-sm text-gray-500">
              <th className="px-4 py-2">ID</th>
              <th className="px-4 py-2">Agent</th>
              <th className="px-4 py-2">Status</th>
              <th className="px-4 py-2">Traces</th>
              <th className="px-4 py-2">Updated</th>
            </tr>
          </thead>
          <tbody>
            {conversations.map((conv) => (
              <tr key={conv.id} className="border-b hover:bg-gray-50">
                <td className="px-4 py-2">
                  <Link href={`/solid_agent/conversations/${conv.id}`} className="text-blue-600 hover:underline">
                    #{conv.id}
                  </Link>
                </td>
                <td className="px-4 py-2 font-mono text-sm">{conv.agent_class}</td>
                <td className="px-4 py-2"><TraceStatusBadge status={conv.status} /></td>
                <td className="px-4 py-2 text-sm">{conv.traces.length}</td>
                <td className="px-4 py-2 text-sm text-gray-500">{conv.updated_at}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Layout>
  )
}
