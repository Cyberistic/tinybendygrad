/**
 * The VIZ adapter: a recorded UOp graph → React Flow nodes and edges.
 *
 * tinygrad's own VIZ lays this out with dagre in a worker (viz/js/worker.js).
 * We do the same job with a deterministic layered pass so the same graph
 * always produces the same picture — a figure that moves between builds is a
 * figure you cannot cite.
 *
 * The diff is by structure, not by recorded id: ids are positions in one
 * graph's toposort, so they only mean something within that graph.
 */

export type UOp = { i: number; op: string; arg: string; dtype: string; src: number[] }

export type NodeState = "same" | "added" | "removed"

export type FlowNode = {
  id: string
  position: { x: number; y: number }
  data: { label: string; op: string; arg: string; dtype: string; state: NodeState }
}

export type FlowEdge = {
  id: string
  source: string
  target: string
  state: NodeState
}

export type Flow = { nodes: FlowNode[]; edges: FlowEdge[] }

const RANK_Y = 86
const COL_X = 208
/** A node's number is its label in tinygrad; keep it short and stable. */
const label = (n: UOp) => (n.arg ? `${n.op}:${n.arg}` : n.op)

/** Structural identity: two nodes are the same if they are the same shape. */
function key(n: UOp, byIndex: Map<number, UOp>): string {
  return `${n.op}|${n.arg}|${n.dtype}|${n.src.map((s) => (byIndex.get(s) ? key(byIndex.get(s)!, byIndex) : s)).join(",")}`
}

/**
 * Longest path from the sink. The sink is rank 0 and sinks-to.
 * Iterative on purpose: graphs are deep and recursion here would be a footgun
 * for the same reason toposort is iterative in tinygrad.
 */
function ranks(nodes: UOp[]): Map<number, number> {
  // Depth from the leaves, then inverted so the sink is rank 0 and the picture
  // reads top-down. Relaxed to a fixpoint rather than trusting the input order:
  // the recorder emits toposort order, but a caller that hands us something
  // else should get the same picture, not a flat line.
  const rank = new Map<number, number>(nodes.map((n) => [n.i, 0]))
  for (let pass = 0; pass <= nodes.length; pass++) {
    let changed = false
    for (const n of nodes) {
      const r = n.src.length ? Math.max(...n.src.map((s) => rank.get(s) ?? 0)) + 1 : 0
      if (r > (rank.get(n.i) ?? 0)) {
        rank.set(n.i, r)
        changed = true
      }
    }
    if (!changed) break
  }
  const deepest = Math.max(0, ...rank.values())
  for (const [i, r] of rank) rank.set(i, deepest - r)
  return rank
}

export function toFlow(nodes: UOp[], previous: UOp[] = []): Flow {
  const rank = ranks(nodes)
  const before = new Map<number, UOp>(previous.map((n) => [n.i, n]))
  const prevKeys = new Set(previous.map((n) => key(n, before)))
  const nowByIndex = new Map<number, UOp>(nodes.map((n) => [n.i, n]))

  const buckets = new Map<number, UOp[]>()
  for (const n of nodes) {
    const r = rank.get(n.i) ?? 0
    if (!buckets.has(r)) buckets.set(r, [])
    buckets.get(r)!.push(n)
  }

  const flow: FlowNode[] = []
  for (const [r, list] of [...buckets].sort((a, b) => a[0] - b[0])) {
    list.sort((a, b) => a.op.localeCompare(b.op) || a.i - b.i)
    const width = (list.length - 1) * COL_X
    list.forEach((n, row) => {
      const k = key(n, nowByIndex)
      flow.push({
        id: String(n.i),
        position: { x: row * COL_X - width / 2, y: r * RANK_Y },
        data: {
          label: label(n),
          op: n.op,
          arg: n.arg,
          dtype: n.dtype,
          state: previous.length === 0 ? "same" : prevKeys.has(k) ? "same" : "added",
        },
      })
    })
  }

  const edges: FlowEdge[] = []
  for (const n of nodes) {
    for (const s of n.src) {
      if (!nowByIndex.has(s)) continue
      edges.push({ id: `${n.i}->${s}`, source: String(n.i), target: String(s), state: "same" })
    }
  }

  return { nodes: flow, edges }
}

/** The nodes that vanished: present before, absent now, matched structurally. */
export function removed(previous: UOp[], nodes: UOp[]): FlowNode[] {
  const nowByIndex = new Map(nodes.map((n) => [n.i, n]))
  const nowKeys = new Set(nodes.map((n) => key(n, nowByIndex)))
  const beforeByIndex = new Map(previous.map((n) => [n.i, n]))
  return previous
    .filter((n) => !nowKeys.has(key(n, beforeByIndex)))
    .map((n) => ({
      id: `gone-${n.i}`,
      position: { x: 0, y: 0 },
      data: { label: label(n), op: n.op, arg: n.arg, dtype: n.dtype, state: "removed" as const },
    }))
}

/** One line for the figure caption: what changed, in counts that cannot lie about both axes. */
export function summarize(before: UOp[], after: UOp[]): string {
  const b = new Set(before.map((n) => key(n, new Map(before.map((x) => [x.i, x])))))
  const a = new Set(after.map((n) => key(n, new Map(after.map((x) => [x.i, x])))))
  const added = [...a].filter((k) => !b.has(k)).length
  const gone = [...b].filter((k) => !a.has(k)).length
  return `${before.length} → ${after.length} nodes · +${added} / −${gone}`
}
