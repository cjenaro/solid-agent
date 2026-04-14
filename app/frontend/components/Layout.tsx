import { Link } from "@inertiajs/react"

interface LayoutProps {
  children: React.ReactNode
}

export default function Layout({ children }: LayoutProps) {
  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="border-b bg-white px-6 py-3">
        <div className="flex items-center gap-6">
          <Link href="/solid_agent" className="font-bold text-lg">
            SolidAgent
          </Link>
          <Link href="/solid_agent/traces" className="text-sm text-gray-600 hover:text-gray-900">
            Traces
          </Link>
          <Link href="/solid_agent/conversations" className="text-sm text-gray-600 hover:text-gray-900">
            Conversations
          </Link>
          <Link href="/solid_agent/agents" className="text-sm text-gray-600 hover:text-gray-900">
            Agents
          </Link>
          <Link href="/solid_agent/tools" className="text-sm text-gray-600 hover:text-gray-900">
            Tools
          </Link>
          <Link href="/solid_agent/mcp" className="text-sm text-gray-600 hover:text-gray-900">
            MCP
          </Link>
        </div>
      </nav>
      <main className="mx-auto max-w-7xl px-6 py-6">
        {children}
      </main>
    </div>
  )
}
