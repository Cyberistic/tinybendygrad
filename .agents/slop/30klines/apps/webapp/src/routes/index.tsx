import { createFileRoute, redirect } from "@tanstack/react-router"

export const Route = createFileRoute("/")({
  beforeLoad: () => {
    throw redirect({ to: "/lesson/$id", params: { id: "01.1" } })
  },
})
