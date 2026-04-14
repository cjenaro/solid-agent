interface TraceStatusBadgeProps {
  status: string
}

export default function TraceStatusBadge({ status }: TraceStatusBadgeProps) {
  const colors: Record<string, string> = {
    completed: "bg-green-100 text-green-800",
    running: "bg-blue-100 text-blue-800",
    failed: "bg-red-100 text-red-800",
    paused: "bg-yellow-100 text-yellow-800",
    pending: "bg-gray-100 text-gray-800",
  }

  return (
    <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${colors[status] || "bg-gray-100 text-gray-800"}`}>
      {status}
    </span>
  )
}
