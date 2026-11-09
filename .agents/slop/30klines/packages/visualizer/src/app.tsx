/**
 * The pass scrubber, on one canvas.
 *
 * A rewrite is a morph, not a comparison: nodes that survive keep their
 * element and slide to their new rank, new ones arrive green, and the ones
 * that were replaced fade out where they stood. Two static canvases made the
 * viewer do the diffing; one animated canvas does it for them.
 *
 * The clock and the index belong to machine.ts. This file is a projection.
 */
import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react"
import { createRoot } from "react-dom/client"
import {
  Background,
  Controls,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
  type Edge,
  type Node,
} from "@xyflow/react"
import "@xyflow/react/dist/style.css"
import { compose, summarize, type Placed, type UOp } from "./flow"
import { PassPlayer } from "./machine"
import { cue, unlockAudio } from "./sound"
import data from "./data.json"

type Step = {
  i: number
  caller: string
  file: string
  line: number
  stage: string
  added: number
  removed: number
  before: UOp[]
  after: UOp[]
}

const steps = (data as unknown as { steps: Step[] }).steps
const start = (data as unknown as { start: number }).start

const player = new PassPlayer({ count: steps.length, delayMs: 1700, cue: (c) => cue(c, true) })

function usePlayer() {
  return useSyncExternalStore(player.subscribe, player.snapshot, player.snapshot)
}

const NODE_W = 132

const nodeStyle = (state: Placed["state"]): React.CSSProperties => ({
  width: NODE_W,
  padding: "6px 8px 5px",
  borderRadius: 0,
  border: state === "added" ? "1px solid #3DA639" : state === "removed" ? "1px dashed #C9C3B7" : "1px solid #C9C3B7",
  background: state === "added" ? "#E9F4DF" : state === "removed" ? "transparent" : "#FBFAF7",
  color: state === "added" ? "#1F6B22" : state === "removed" ? "#9A958C" : "#16161A",
  boxShadow: state === "removed" ? "none" : "0 1px 0 rgba(0,0,0,.03)",
  transition: "background .35s ease, border-color .35s ease, color .35s ease",
  animation: state === "added" ? "pop .42s cubic-bezier(.2,.9,.2,1)" : undefined,
  opacity: state === "removed" ? 0 : 1,
  // removed nodes fade where they stood, then the component drops them
  ...(state === "removed" ? { animation: "fade .55s ease forwards" } : {}),
})

const Graph = ({ nodes, edges }: { nodes: Placed[]; edges: Edge[] }) => {
  const rf = useReactFlow()
  const rfNodes: Node[] = nodes.map((n) => ({
    id: n.id,
    position: n.position,
    data: {
      label: (
        <div className="n">
          <span className="op">{n.label}</span>
          {n.arg && n.arg !== "None" ? <span className="arg">{n.arg}</span> : null}
        </div>
      ),
    },
    style: nodeStyle(n.state),
    draggable: false,
    selectable: false,
    sourcePosition: "bottom" as const,
    targetPosition: "top" as const,
  }))

  useEffect(() => {
    const t = setTimeout(() => rf.fitView({ padding: 0.22, duration: 420 }), 40)
    return () => clearTimeout(t)
  }, [nodes.length, rf])

  return (
    <ReactFlow
      nodes={rfNodes}
      edges={edges}
      proOptions={{ hideAttribution: true }}
      nodesDraggable={false}
      nodesConnectable={false}
      elementsSelectable={false}
      panOnScroll
      minZoom={0.25}
      maxZoom={1.6}
      defaultEdgeOptions={{ type: "smoothstep", style: { stroke: "#B7B1A4", strokeWidth: 1 } }}
    >
      <Background color="#DED9CE" gap={26} size={1} />
      <Controls showInteractive={false} />
    </ReactFlow>
  )
}

function App() {
  const state = usePlayer()
  const index = state.type === "idle" ? 0 : state.index
  const step = steps[index]
  const railRef = useRef<HTMLDivElement>(null)

  // ghosts stay one beat so they can fade rather than blink out
  const stable = useMemo(() => compose(step.before, step.after), [step])
  const [shown, setShown] = useState(stable)

  useEffect(() => {
    setShown(stable)
    const t = setTimeout(
      () => setShown((g) => ({ ...g, nodes: g.nodes.filter((n) => n.state !== "removed") })),
      550,
    )
    return () => clearTimeout(t)
  }, [stable])

  useEffect(() => {
    const unlock = () => unlockAudio()
    addEventListener("pointerdown", unlock, { once: true })
    addEventListener("keydown", unlock, { once: true })
    return () => {
      removeEventListener("pointerdown", unlock)
      removeEventListener("keydown", unlock)
    }
  }, [])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.code === "Space") {
        e.preventDefault()
        player.running ? player.pause() : player.play()
      }
      if (e.key === "ArrowRight") {
        player.pause()
        player.seek(Math.min(index + 1, steps.length - 1))
      }
      if (e.key === "ArrowLeft") {
        player.pause()
        player.seek(Math.max(index - 1, 0))
      }
    }
    addEventListener("keydown", onKey)
    return () => removeEventListener("keydown", onKey)
  }, [index])

  useEffect(() => {
    railRef.current?.querySelector(".tick.cur")?.scrollIntoView({ block: "nearest", inline: "center" })
  }, [index])

  const edges: Edge[] = shown.edges.map((e) => ({ id: e.id, source: e.source, target: e.target }))

  return (
    <>
      <div className="top">
        <div className="brand">30klinesofcode <span>· viz</span></div>
        <div className="meta">
          <b>{step.caller}</b>
          <span className="dim">{step.file}:{step.line}</span>
          <span className="dim">{step.stage}</span>
          <span className="sum">{summarize(step.before, step.after)}</span>
          <span className={"state " + state.type}>{state.type}</span>
        </div>
      </div>

      <main>
        <ReactFlowProvider>
          <Graph nodes={shown.nodes} edges={edges} />
        </ReactFlowProvider>
      </main>

      <div className="scrub">
        <button className="ctl" onClick={() => (player.running ? player.pause() : player.play())} title="space">
          {player.running ? "❚❚" : "▶"}
        </button>
        <div className="rail" ref={railRef}>
          {steps.map((s, i) => (
            <button
              key={s.i}
              className={"tick" + (i === index ? " cur" : "") + (i < index ? " past" : "") + (s.stage === "pattern" ? " pat" : "")}
              style={{ height: 5 + Math.min(19, (s.added + s.removed) * 0.6) }}
              title={`${s.caller} ${s.before.length}→${s.after.length}`}
              onClick={() => {
                player.pause()
                player.seek(i)
              }}
            />
          ))}
        </div>
        <span className="count">{index + 1} / {steps.length}</span>
      </div>
    </>
  )
}

const asked = Number(new URLSearchParams(location.search).get("i"))
player.seek(Number.isFinite(asked) && asked > 0 ? asked : start)

createRoot(document.getElementById("root")!).render(<App />)
