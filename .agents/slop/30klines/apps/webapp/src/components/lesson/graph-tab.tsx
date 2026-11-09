import { useEffect, useMemo, useRef, useState } from "react"
import { animate } from "motion/react"
import { Background, Controls, ReactFlow, ReactFlowProvider, useReactFlow, type Edge, type Node } from "@xyflow/react"
import "@xyflow/react/dist/style.css"
import { compose, summarize, type Placed, type UOp } from "@viz/flow"

type Step = { i: number; caller: string; file: string; line: number; before: UOp[]; after: UOp[] }

const NODE_W = 128
const DURATION = 0.45

const style = (state: Placed["state"]): React.CSSProperties => ({
  width: NODE_W,
  padding: "5px 7px 4px",
  borderRadius: 0,
  border: state === "added" ? "1px solid #3DA639" : state === "removed" ? "1px dashed #C9C3B7" : "1px solid #C9C3B7",
  background: state === "added" ? "#E9F4DF" : state === "removed" ? "transparent" : "#FBFAF7",
  color: state === "added" ? "#1F6B22" : state === "removed" ? "#9A958C" : "#16161A",
  transition: "background .3s ease, border-color .3s ease, color .3s ease",
  opacity: state === "removed" ? 0.5 : 1,
})

/** Interpolate every node from where it was to where it now belongs. */
function useTweened(placed: Placed[], key: number) {
  const [pos, setPos] = useState<Record<string, { x: number; y: number }>>({})
  const from = useRef<Record<string, { x: number; y: number }>>({})

  const target = useMemo(() => {
    const m: Record<string, { x: number; y: number }> = {}
    for (const n of placed) m[n.id] = n.position
    return m
  }, [placed])

  useEffect(() => {
    const start = { ...target }
    const controls = animate(0, 1, {
      duration: DURATION,
      ease: [0.2, 0.9, 0.2, 1],
      onUpdate: (t) => {
        const next: Record<string, { x: number; y: number }> = {}
        for (const id of Object.keys(target)) {
          const a = from.current[id] ?? target[id] // a new node starts where it lands
          const b = target[id]
          next[id] = { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t }
        }
        setPos(next)
      },
      onComplete: () => {
        from.current = start
      },
    })
    return () => controls.stop()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, target])

  return pos
}

function Canvas({ placed, edges, tick }: { placed: Placed[]; edges: Edge[]; tick: number }) {
  const positions = useTweened(placed, tick)
  const rf = useReactFlow()

  useEffect(() => {
    const t = setTimeout(() => rf.fitView({ padding: 0.24, duration: 0.4 }), 60)
    return () => clearTimeout(t)
  }, [tick, rf])

  const nodes: Node[] = placed.map((n) => ({
    id: n.id,
    position: positions[n.id] ?? n.position,
    data: {
      label: (
        <div className="text-left">
          <div className="text-[10.5px] leading-tight">{n.op}</div>
          {n.arg && n.arg !== "None" ? (
            <div className="truncate text-[9px] leading-tight text-faint">{n.arg}</div>
          ) : null}
        </div>
      ),
    },
    style: style(n.state),
    draggable: false,
    selectable: false,
    sourcePosition: "bottom" as const,
    targetPosition: "top" as const,
  }))

  return (
    <ReactFlow
      nodes={nodes}
      edges={edges}
      proOptions={{ hideAttribution: true }}
      nodesDraggable={false}
      nodesConnectable={false}
      elementsSelectable={false}
      minZoom={0.2}
      maxZoom={1.5}
      defaultEdgeOptions={{ type: "smoothstep", style: { stroke: "#B7B1A4", strokeWidth: 1 } }}
    >
      <Background color="#DED9CE" gap={26} size={1} />
      <Controls showInteractive={false} />
    </ReactFlow>
  )
}

export function GraphTab({ steps, startAt }: { steps: Step[]; startAt?: number }) {
  const initial = Math.max(0, steps.findIndex((s) => s.i === startAt))
  const [i, setI] = useState(initial === -1 ? 0 : initial)
  const step = steps[i]

  const composed = useMemo(() => compose(step.before, step.after), [step])
  const edges: Edge[] = composed.edges.map((e) => ({ id: e.id, source: e.source, target: e.target }))

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "ArrowRight") setI((n) => Math.min(n + 1, steps.length - 1))
      if (e.key === "ArrowLeft") setI((n) => Math.max(n - 1, 0))
    }
    addEventListener("keydown", onKey)
    return () => removeEventListener("keydown", onKey)
  }, [steps.length])

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center justify-between border-b border-rule px-4 py-2 text-[10.5px] text-muted">
        <span>
          <b className="font-medium text-ink">{step.caller}</b>{" "}
          <span className="text-faint">{step.file}:{step.line}</span>
        </span>
        <span className="text-accent">{summarize(step.before, step.after)}</span>
      </div>
      <div className="relative flex-1">
        <ReactFlowProvider>
          <Canvas placed={composed.nodes} edges={edges} tick={i} />
        </ReactFlowProvider>
      </div>
      <div className="flex items-center gap-2 border-t border-rule px-4 py-2">
        <button onClick={() => setI(Math.max(0, i - 1))} className="border border-rule2 px-2 py-1 text-[11px]">←</button>
        <button onClick={() => setI(Math.min(steps.length - 1, i + 1))} className="border border-rule2 px-2 py-1 text-[11px]">→</button>
        <input
          type="range" min={0} max={steps.length - 1} value={i}
          onChange={(e) => setI(Number(e.target.value))}
          className="mx-2 flex-1 accent-[#3DA639]"
        />
        <span className="text-[10px] tabular-nums text-faint">{i + 1} / {steps.length}</span>
      </div>
    </div>
  )
}
