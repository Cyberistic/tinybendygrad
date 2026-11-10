import { createFileRoute } from "@tanstack/react-router"
import { Effect } from "effect"
import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { highlightLines } from "@viz/highlight"
import compareData from "virtual:compare-data"
import { readSource } from "@/server/source"
import { FileTree, type FileNode } from "@/components/ai-elements/file-tree"

export const Route = createFileRoute("/compare")({
  validateSearch: (s: Record<string, unknown>) => ({ file: typeof s.file === "string" ? s.file : undefined }),
  component: ComparePage,
})

type Side = "py" | "bend"

const short = (p: string) => p.replace(/^tinygrad\//, "").replace(/^tinybendygrad\//, "")

function ComparePage() {
  const { file } = Route.useSearch()
  const navigate = Route.useNavigate()
  const files = compareData.files
  const entries = useMemo(() => {
    // A pair is one entry on the Python side; the badge says what the other
    // side has. B = bend only, P = python only, so a missing counterpart is a
    // letter, not an absence the eye has to notice.
    const paired = files.map((f) => ({ path: (f.py ?? f.bend) as string, badge: f.py ? "↔" : "B" }))
    const only = compareData.pythonOnlyFiles.map((p) => ({ path: p, badge: "P" }))
    return [...paired, ...only].sort((a, b) => a.path.localeCompare(b.path))
  }, [files])

  const tree = useMemo(() => buildTree(entries), [entries])

  const pick = file ?? entries[0]?.path
  const entry: (typeof files)[number] =
    files.find((f) => f.py === pick || f.bend === pick) ??
    ({ py: compareData.pythonOnlyFiles.includes(pick ?? "") ? pick : null, bend: pick ?? "" } as never)

  const [sources, setSources] = useState<{ py?: string; bend?: string }>({})
  const [leftPct, setLeftPct] = useState(50)
  const [focus, setFocus] = useState<{ side: Side; line: number } | null>(null)
  const pyRef = useRef<HTMLDivElement>(null)
  const bendRef = useRef<HTMLDivElement>(null)

  // contents are read on the server; the mapping came from the build
  useEffect(() => {
    let stale = false
    const load = async () => {
      const next: { py?: string; bend?: string } = {}
      if (entry.py) next.py = (await readSource({ data: { path: entry.py } })).text
      if (entry.bend) next.bend = (await readSource({ data: { path: entry.bend } })).text
      if (!stale) setSources(next)
    }
    Effect.runPromise(Effect.tryPromise({ try: load, catch: (e) => e as Error })).catch(() => setSources({}))
    return () => {
      stale = true
    }
  }, [entry.py, entry.bend])

  const pyLines = useMemo(() => (sources.py ? highlightLines(sources.py, "py") : []), [sources.py])
  const bendLines = useMemo(() => (sources.bend ? highlightLines(sources.bend, "bend") : []), [sources.bend])

  const linkOf = useMemo(() => {
    const pyToBend = new Map<number, number>()
    const bendToPy = new Map<number, number>()
    for (const [p, b] of entry.links ?? []) {
      pyToBend.set(p, b)
      bendToPy.set(b, p)
    }
    return { pyToBend, bendToPy }
  }, [entry])

  const jump = useCallback(
    (from: Side, line: number) => {
      const target = from === "py" ? linkOf.pyToBend.get(line) : linkOf.bendToPy.get(line)
      if (target === undefined) return
      const pane = from === "py" ? bendRef.current : pyRef.current
      const row = pane?.querySelector<HTMLElement>(`[data-line="${target}"]`)
      if (!row || !pane) return
      pane.scrollTo({ top: row.offsetTop - pane.clientHeight / 3, behavior: "smooth" })
      row.classList.remove("flash")
      void row.offsetWidth
      row.classList.add("flash")
      setFocus({ side: from === "py" ? "bend" : "py", line: target })
    },
    [linkOf],
  )

  const drag = (e: React.PointerEvent) => {
    const startX = e.clientX
    const start = leftPct
    const box = (e.currentTarget.parentElement as HTMLElement).getBoundingClientRect()
    const move = (ev: PointerEvent) => {
      const pct = ((ev.clientX - box.left) / box.width) * 100
      setLeftPct(Math.max(0, Math.min(100, pct + (start - ((startX - box.left) / box.width) * 100))))
    }
    const up = () => {
      removeEventListener("pointermove", move)
      removeEventListener("pointerup", up)
    }
    addEventListener("pointermove", move)
    addEventListener("pointerup", up)
  }

  const stats = [
    ["lines", `${entry.pyLines ?? "—"} → ${entry.bendLines ?? "—"}`],
    ["defs", `${entry.pyDefs ?? "—"} → ${entry.bendDefs ?? "—"}`],
    ["linked", `${entry.links?.length ?? 0}`],
    ["unmatched", `${entry.pyOnly?.length ?? 0} py · ${entry.bendOnly?.length ?? 0} bend`],
  ]

  return (
    <div className="flex h-[calc(100vh-44px)] flex-col">
      <div className="flex items-center justify-between border-b border-rule px-4 py-2 text-[10.5px] text-muted">
        <div className="flex items-center gap-4">
          {stats.map(([k, v]) => (
            <span key={k}>
              <span className="text-faint">{k} </span>
              <span className="tabular-nums text-ink">{v}</span>
            </span>
          ))}
        </div>
        <span className="text-faint">
          {compareData.totals.pairs} pairs · {compareData.totals.bendOnly} bend-only · {compareData.totals.links} links
        </span>
      </div>

      <div className="flex min-h-0 flex-1">
        <div className="w-[270px] shrink-0 overflow-auto border-r border-rule py-2">
          <FileTree
            nodes={tree}
            selected={pick}
            onSelect={(path) => navigate({ search: { file: path } })}
          />
        </div>

        <div className="relative flex min-w-0 flex-1">
          <Pane
            side="py"
            path={entry.py}
            lines={pyLines}
            width={leftPct}
            paneRef={pyRef}
            linked={linkOf.pyToBend}
            onJump={jump}
            focus={focus?.side === "py" ? focus.line : null}
            lang="py"
          />
          <div
            onPointerDown={drag}
            className="w-[5px] shrink-0 cursor-col-resize border-x border-rule bg-paper2 hover:bg-accent/30"
          />
          <Pane
            side="bend"
            path={entry.bend}
            lines={bendLines}
            width={100 - leftPct}
            paneRef={bendRef}
            linked={linkOf.bendToPy}
            onJump={jump}
            focus={focus?.side === "bend" ? focus.line : null}
            lang="bend"
          />
        </div>
      </div>
    </div>
  )
}

function Pane(props: {
  side: Side
  path: string | null
  lines: string[]
  width: number
  paneRef: React.RefObject<HTMLDivElement | null>
  linked: Map<number, number>
  onJump: (side: Side, line: number) => void
  focus: number | null
  lang: "py" | "bend"
}) {
  const { side, path, lines, width, paneRef, linked, onJump, focus } = props
  if (!path) {
    return (
      <div className="flex items-center justify-center border-rule p-6 text-[11px] text-faint" style={{ width: `${width}%` }}>
        no counterpart on this side
      </div>
    )
  }
  return (
    <div className="min-w-0 overflow-hidden" style={{ width: `${width}%` }}>
      <header className="sticky top-0 z-10 flex justify-between border-b border-rule bg-paper px-3 py-1.5 text-[10px] text-muted">
        <span className="truncate">{path}</span>
        <span className="text-faint">{lines.length}</span>
      </header>
      <div ref={paneRef} className="h-[calc(100%-28px)] overflow-auto py-1 text-[11px] leading-[1.7]">
        {lines.map((html, i) => {
          const line = i + 1
          const target = linked.get(line)
          return (
            <div
              key={line}
              data-line={line}
              onClick={() => target !== undefined && onJump(side, line)}
              className={
                "grid grid-cols-[46px_1fr] pr-3 " +
                (target !== undefined ? "cursor-pointer hover:bg-wash/60 " : "") +
                (focus === line ? "bg-wash " : "")
              }
              title={target !== undefined ? `→ line ${target}` : undefined}
            >
              <span className="select-none pr-3 text-right text-[10px] text-faint">{line}</span>
              <span
                className="whitespace-pre-wrap break-words text-ink2"
                dangerouslySetInnerHTML={{ __html: html || " " }}
              />
            </div>
          )
        })}
      </div>
    </div>
  )
}

/** Group paths into folders; a pair is one entry on the Python side. */
function buildTree(entries: { path: string; badge: string }[]): FileNode[] {
  const root: FileNode = { name: "", path: "", type: "folder", children: [] }
  for (const { path, badge } of entries) {
    const parts = path.split("/")
    let node = root
    parts.forEach((part, i) => {
      const full = parts.slice(0, i + 1).join("/")
      const isFile = i === parts.length - 1
      let child = node.children?.find((c) => c.path === full)
      if (!child) {
        child = isFile
          ? // the extension is the same on every row, so it is noise in a tree
            { name: part.replace(/\.(py|bend)$/, ""), path: full, type: "file", badge }
          : { name: part, path: full, type: "folder", children: [] }
        node.children?.push(child)
      }
      node = child
    })
  }
  const sort = (n: FileNode) => {
    n.children?.sort((a, b) => (a.type === b.type ? a.name.localeCompare(b.name) : a.type === "folder" ? -1 : 1))
    n.children?.forEach(sort)
  }
  sort(root)
  return root.children ?? []
}
