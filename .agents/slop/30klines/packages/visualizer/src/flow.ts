/**
 * Recorded UOp graph → React Flow nodes, with identities that survive a rewrite.
 *
 * The whole point of a rewrite view is continuity: a node that exists on both
 * sides must be the SAME element, so React Flow can move it instead of
 * replacing it. That means the id cannot be the toposort index (which changes
 * every pass) — it has to be the node's shape.
 *
 * Layout is layered: rank by depth from the sink, then order each rank by the
 * mean position of its sources so the edges stop crossing.
 */

export type UOp = { i: number; op: string; arg: string; dtype: string; src: number[] }

export type NodeState = "same" | "added" | "removed"

export type Placed = {
  id: string
  key: string
  position: { x: number; y: number }
  label: string
  op: string
  arg: string
  state: NodeState
}

export type Edge = { id: string; source: string; target: string }

const RANK_Y = 104
const COL_X = 178

/** tinygrad prints Ops.ADD; the graph reads better as ADD. */
const shortOp = (op: string) => op.replace(/^Ops\./, "")
const label = (n: UOp) => shortOp(n.op)

/** Structural identity. Ids are indices into one graph, so they cannot travel. */
export function keyOf(n: UOp, byIndex: Map<number, UOp>, seen = new Set<string>()): string {
  const memo = (byIndex as unknown as { _keys?: Map<number, string> })._keys ?? new Map<number, string>()
  ;(byIndex as unknown as { _keys?: Map<number, string> })._keys = memo
  const hit = memo.get(n.i)
  if (hit) return hit
  const src = n.src.map((s) => {
    const child = byIndex.get(s)
    return child ? keyOf(child, byIndex, seen) : `#${s}`
  })
  const k = `${n.op}|${n.arg}|${n.dtype}|${src.join(",")}`
  memo.set(n.i, k)
  return k
}

function ranks(nodes: UOp[]): Map<number, number> {
  // depth from the leaves, relaxed to a fixpoint so input order cannot change it
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

/** Positions keyed by structural key, so two passes can be compared by shape. */
export function layout(nodes: UOp[]): Map<string, { x: number; y: number }> {
  const byIndex = new Map(nodes.map((n) => [n.i, n]))
  const rank = ranks(nodes)
  const buckets = new Map<number, UOp[]>()
  for (const n of nodes) {
    const r = rank.get(n.i) ?? 0
    if (!buckets.has(r)) buckets.set(r, [])
    buckets.get(r)!.push(n)
  }

  // two sweeps of barycentre: order a rank by where its sources sit in the next
  const order = new Map<number, number>()
  for (const [, list] of buckets) list.forEach((n, i) => order.set(n.i, i))
  for (let sweep = 0; sweep < 2; sweep++) {
    const rankKeys = [...buckets.keys()].sort((a, b) => b - a) // deepest first
    for (const r of rankKeys) {
      const list = buckets.get(r)!
      list.sort((a, b) => {
        const bary = (n: UOp) =>
          n.src.length ? n.src.reduce((m, s) => m + (order.get(s) ?? 0), 0) / n.src.length : order.get(n.i) ?? 0
        return bary(a) - bary(b)
      })
      list.forEach((n, i) => order.set(n.i, i))
    }
  }

  const out = new Map<string, { x: number; y: number }>()
  for (const [r, list] of [...buckets].sort((a, b) => a[0] - b[0])) {
    const width = (list.length - 1) * COL_X
    list.forEach((n, i) => {
      out.set(keyOf(n, byIndex), { x: i * COL_X - width / 2, y: r * RANK_Y })
    })
  }
  return out
}

/**
 * One graph for one transition: the "after" state, plus any node that only
 * existed in "before" so it can fade out where it stood.
 */
export function compose(before: UOp[], after: UOp[]): { nodes: Placed[]; edges: Edge[] } {
  const afterPos = layout(after)
  const beforePos = layout(before)
  const afterByIndex = new Map(after.map((n) => [n.i, n]))
  const beforeByIndex = new Map(before.map((n) => [n.i, n]))

  const beforeKeys = new Set(before.map((n) => keyOf(n, beforeByIndex)))
  const nodes: Placed[] = []

  for (const n of after) {
    const key = keyOf(n, afterByIndex)
    nodes.push({
      id: key,
      key,
      position: afterPos.get(key) ?? { x: 0, y: 0 },
      label: label(n),
      op: shortOp(n.op),
      arg: n.arg,
      state: beforeKeys.has(key) ? "same" : "added",
    })
  }

  for (const n of before) {
    const key = keyOf(n, beforeByIndex)
    if (afterPos.has(key)) continue
    nodes.push({
      id: `gone-${key}`,
      key,
      position: beforePos.get(key) ?? { x: 0, y: 0 },
      label: label(n),
      op: shortOp(n.op),
      arg: n.arg,
      state: "removed",
    })
  }

  const edges: Edge[] = []
  for (const n of after) {
    const key = keyOf(n, afterByIndex)
    for (const s of n.src) {
      const child = afterByIndex.get(s)
      if (child) edges.push({ id: `${key}>${keyOf(child, afterByIndex)}`, source: key, target: keyOf(child, afterByIndex) })
    }
  }

  return { nodes, edges }
}

/** The caption: both axes, so a 21→21 pass cannot read as nothing. */
export function summarize(before: UOp[], after: UOp[]): string {
  const b = new Set(before.map((n) => keyOf(n, new Map(before.map((x) => [x.i, x])))))
  const a = new Set(after.map((n) => keyOf(n, new Map(after.map((x) => [x.i, x])))))
  const added = [...a].filter((k) => !b.has(k)).length
  const gone = [...b].filter((k) => !a.has(k)).length
  return `${before.length} → ${after.length} nodes · +${added} / −${gone}`
}
