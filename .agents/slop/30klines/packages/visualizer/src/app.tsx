/**
 * The VIZ view, in React Flow.
 *
 * Two canvases: the graph before the pass and after it, laid out by the same
 * deterministic adapter both times. A node that survived keeps its label; one
 * that appeared is green; one that vanished is drawn as a ghost so the eye can
 * count what the caption says.
 *
 * Data comes from tools/recorder/record.py — these are recorded passes, not
 * drawings. That is the whole difference between this and a diagram.
 */
import { createRoot } from "react-dom/client"
import { Background, Controls, ReactFlow, type Edge, type Node } from "@xyflow/react"
import "@xyflow/react/dist/style.css"
import { removed, summarize, toFlow, type UOp } from "./flow"
import data from "./data.json"

type Step = { before: UOp[]; after: UOp[]; caller: string; file: string; line: number; stage: string }

const step = data.step as Step

const style: Record<string, { border: string; background: string; color: string; borderStyle?: string }> = {
  same: { border: "1px solid #BDB7A9", background: "#F4F2ED", color: "#16161A" },
  added: { border: "1.5px solid #3DA639", background: "#E4EFD9", color: "#1F6B22" },
  removed: { border: "1px dashed #BDB7A9", background: "transparent", color: "#9A958C", borderStyle: "dashed" },
}

function canvas(nodes: UOp[], previous: UOp[], withGhosts: boolean) {
  const flow = toFlow(nodes, previous)
  const ghosts = withGhosts ? removed(previous, nodes) : []

  const rightmost = flow.nodes.reduce((m, n) => Math.max(m, n.position.x), 0)
  const rfNodes: Node[] = [
    ...flow.nodes.map((n) => ({
      id: n.id,
      position: n.position,
      data: { label: n.data.label },
      style: {
        ...style[n.data.state],
        font: "11px ui-monospace, Menlo, monospace",
        padding: "5px 8px",
        borderRadius: 0,
        width: "auto",
        minWidth: 64,
        textAlign: "center" as const,
      },
      // React Flow draws edges behind nodes by default; a plain box is enough
      draggable: false,
    })),
    ...ghosts.map((g, i) => ({
      id: g.id,
      position: { x: rightmost + 300, y: i * 42 - (ghosts.length * 42) / 2 },
      data: { label: g.data.label },
      style: {
        ...style.removed,
        font: "11px ui-monospace, Menlo, monospace",
        padding: "5px 8px",
        borderRadius: 0,
        minWidth: 64,
        textAlign: "center" as const,
      },
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
  return (
    <>
      <div className="top">
        <div className="brand">30klinesofcode <span>· viz</span></div>
        <div className="meta">
          <b>graph_rewrite</b> · {step.caller} · {step.file}:{step.line} · {step.stage}
          <span className="sum">{summarize(step.before, step.after)}</span>
        </div>
      </div>
      <main>
        <Panel title="before" nodes={step.before} previous={[]} ghosts={false} />
        <Panel title="after" nodes={step.after} previous={step.before} ghosts />
      </main>
    </>
  )
}

createRoot(document.getElementById("root")!).render(<App />)
