/**
 * The pass scrubber.
 *
 * One recorded run, 33 passes, walked with the Effect state machine in
 * machine.ts. React is a projection: the machine owns the index and whether it
 * is running, the component subscribes with useSyncExternalStore and redraws.
 * Nothing here decides which pass is current — that is the same rule as
 * track.ts for the voice, and the same rule as the reference repo.
 */
import { useEffect, useRef, useState, useSyncExternalStore } from "react"
import { createRoot } from "react-dom/client"
import { Background, Controls, ReactFlow, type Edge, type Node } from "@xyflow/react"
import "@xyflow/react/dist/style.css"
import { removed, summarize, toFlow, type UOp } from "./flow"
import { PassPlayer } from "./machine"
import { cue } from "./sound"
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

const player = new PassPlayer({
  count: steps.length,
  delayMs: 1600,
  cue: (c) => cue(c, true),
})

function usePlayer() {
  return useSyncExternalStore(player.subscribe, player.snapshot, player.snapshot)
}

const box = (state: string) => ({
  border: state === "added" ? "1.5px solid #3DA639" : state === "removed" ? "1px dashed #BDB7A9" : "1px solid #BDB7A9",
  background: state === "added" ? "#E4EFD9" : state === "removed" ? "transparent" : "#F4F2ED",
  color: state === "added" ? "#1F6B22" : state === "removed" ? "#9A958C" : "#16161A",
  font: "11px ui-monospace, Menlo, monospace",
  padding: "5px 8px",
  borderRadius: 0,
  minWidth: 64,
  textAlign: "center" as const,
})

function canvas(nodes: UOp[], previous: UOp[], ghosts: boolean) {
  const flow = toFlow(nodes, previous)
  const gone = ghosts ? removed(previous, nodes) : []
  const rightmost = flow.nodes.reduce((m, n) => Math.max(m, n.position.x), 0)

  const rfNodes: Node[] = [
    ...flow.nodes.map((n) => ({
      id: n.id,
      position: n.position,
      data: { label: n.data.label },
      style: box(n.data.state),
      draggable: false,
    })),
    ...gone.map((g, i) => ({
      id: g.id,
      position: { x: rightmost + 300, y: i * 42 - (gone.length * 42) / 2 },
      data: { label: g.data.label },
      style: box("removed"),
      draggable: false,
    })),
  ]
  const rfEdges: Edge[] = flow.edges.map((e) => ({
    id: e.id,
    source: e.source,
    target: e.target,
    type: "smoothstep",
    style: { stroke: "#A8A296", strokeWidth: 1 },
    markerEnd: { type: "arrowclosed" as const, color: "#A8A296", width: 12, height: 12 },
  }))
  return { rfNodes, rfEdges }
}

function Panel({ title, nodes, previous, ghosts }: { title: string; nodes: UOp[]; previous: UOp[]; ghosts: boolean }) {
  const { rfNodes, rfEdges } = canvas(nodes, previous, ghosts)
  return (
    <section className="panel">
      <header>
        <span>{title}</span>
        <span className="n">{nodes.length} nodes</span>
      </header>
      <div className="canvas">
        <ReactFlow
          key={`${title}-${nodes.length}-${rfNodes[0]?.data.label ?? ""}`}
          nodes={rfNodes}
          edges={rfEdges}
          fitView
          fitViewOptions={{ padding: 0.18 }}
          proOptions={{ hideAttribution: true }}
          nodesDraggable={false}
          nodesConnectable={false}
          elementsSelectable={false}
          panOnScroll={false}
        >
          <Background color="#D6D1C7" gap={24} size={1} />
          <Controls showInteractive={false} />
        </ReactFlow>
      </div>
    </section>
  )
}

function App() {
  const state = usePlayer()
  const index = state.type === "idle" ? 0 : state.index
  const step = steps[index]
  const railRef = useRef<HTMLDivElement>(null)

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

  return (
    <>
      <div className="top">
        <div className="brand">30klinesofcode <span>· viz</span></div>
        <div className="meta">
          <b>{step.caller}</b> · {step.file}:{step.line} · {step.stage}
          <span className="sum">{summarize(step.before, step.after)}</span>
          <span className={"state " + state.type}>{state.type}</span>
        </div>
      </div>

      <main>
        <Panel title="before" nodes={step.before} previous={[]} ghosts={false} />
        <Panel title="after" nodes={step.after} previous={step.before} ghosts />
      </main>

      <div className="scrub">
        <button className="ctl" onClick={() => (player.running ? player.pause() : player.play())}
                title="space">
          {player.running ? "❚❚" : "▶"}
        </button>
        <div className="rail" ref={railRef}>
          {steps.map((s, i) => (
            <button
              key={s.i}
              className={
                "tick" + (i === index ? " cur" : "") + (i < index ? " past" : "") +
                (s.stage === "pattern" ? " pat" : "")
              }
              style={{ height: 6 + Math.min(20, (s.added + s.removed) * 0.7) }}
              title={`${s.caller} ${s.before.length}→${s.after.length}`}
              onClick={() => { player.pause(); player.seek(i) }}
            />
          ))}
        </div>
        <span className="count">{index + 1} / {steps.length}</span>
      </div>
    </>
  )
}

// ?i=12 opens at a pass, so a figure can be cited by position
const asked = Number(new URLSearchParams(location.search).get("i"))
player.seek(Number.isFinite(asked) && asked > 0 ? asked : start)

createRoot(document.getElementById("root")!).render(<App />)
