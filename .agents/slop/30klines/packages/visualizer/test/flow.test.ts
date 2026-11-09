import { describe, expect, test } from "bun:test"
import { readFileSync } from "node:fs"
import { compose, layout, summarize, type UOp } from "../src/flow"

const n = (i: number, op: string, src: number[] = [], arg = ""): UOp =>
  ({ i, op, arg, dtype: "void", src })

const find = (nodes: ReturnType<typeof compose>["nodes"], op: string) =>
  nodes.filter((x) => x.op === op)

describe("layout", () => {
  test("the sink sits at the top and its sources below", () => {
    const g = [n(0, "SINK", [1]), n(1, "ADD", [2, 3]), n(2, "CONST"), n(3, "CONST")]
    const composed = compose([], g).nodes
    const y = (op: string) => find(composed, op)[0].position.y
    expect(y("SINK")).toBe(0)
    expect(y("ADD")).toBe(104)
    expect(find(composed, "CONST").every((c) => c.position.y === 208)).toBe(true)
  })

  test("siblings do not sit on top of each other", () => {
    const g = [n(0, "SINK", [1, 2]), n(1, "A"), n(2, "B")]
    const xs = compose([], g).nodes.map((x) => x.position.x)
    expect(new Set(xs).size).toBe(xs.length)
  })

  test("the same graph always lays out the same way", () => {
    const g = [n(0, "SINK", [1]), n(1, "ADD", [2]), n(2, "CONST")]
    expect(JSON.stringify(compose([], g))).toBe(JSON.stringify(compose([], g)))
  })

  test("input order cannot change the ranks", () => {
    const forward = [n(0, "SINK", [1]), n(1, "ADD", [2]), n(2, "CONST")]
    const shuffled = [n(2, "CONST"), n(0, "SINK", [1]), n(1, "ADD", [2])]
    expect(layout(forward).get("SINK|")).toEqual(layout(shuffled).get("SINK|"))
  })
})

describe("identity survives a rewrite", () => {
  test("a node with the same shape keeps its id, so React moves it", () => {
    const before = [n(0, "ADD", [1]), n(1, "CONST")]
    const after = [n(9, "ADD", [8]), n(8, "CONST")] // renumbered, same shape
    const composed = compose(before, after)
    expect(composed.nodes.every((x) => x.state === "same")).toBe(true)
    expect(new Set(composed.nodes.map((x) => x.id)).size).toBe(2)
  })

  test("a replaced node is added, and its old self is removed", () => {
    const before = [n(0, "ADD", [1]), n(1, "CONST")]
    const after = [n(0, "MUL", [1]), n(1, "CONST")]
    const composed = compose(before, after)
    expect(find(composed.nodes, "MUL")[0].state).toBe("added")
    expect(find(composed.nodes, "ADD")[0].state).toBe("removed")
  })

  test("removed nodes keep the position they held, so they fade in place", () => {
    const before = [n(0, "SINK", [1]), n(1, "ADD")]
    const after = [n(0, "SINK", [1]), n(1, "MUL")]
    const gone = find(compose(before, after).nodes, "ADD")[0]
    expect(gone.position.y).toBe(104)
  })

  test("edges only point at nodes that exist", () => {
    const g = [n(0, "SINK", [1]), n(1, "ADD", [2, 99]), n(2, "CONST")]
    const ids = new Set(compose([], g).nodes.map((x) => x.id))
    for (const e of compose([], g).edges) {
      expect(ids.has(e.source)).toBe(true)
      expect(ids.has(e.target)).toBe(true)
    }
  })
})

describe("the caption", () => {
  test("tells both axes, so a 21 to 21 pass cannot read as nothing", () => {
    expect(summarize([n(0, "ADD", [1]), n(1, "CONST")], [n(0, "MUL", [1]), n(1, "CONST")]))
      .toBe("2 → 2 nodes · +1 / −1")
  })
})

describe("a recorded pass on disk", () => {
  // Resolve by caller and by the recorder's kept flag: a re-record renumbers
  // passes, and a test pinned to an index is a change detector.
  const root = `${import.meta.dir}/../../../content/traces/add_relu_sum`
  const steps = JSON.parse(readFileSync(`${root}/steps.json`, "utf8")).steps as
    { i: number; caller: string; kept: boolean }[]
  const pass = (caller: string) => {
    const s = steps.find((x) => x.caller === caller && x.kept)
    if (!s) throw new Error(`no kept pass for ${caller}`)
    const load = (side: string) =>
      JSON.parse(readFileSync(`${root}/graphs/${String(s.i).padStart(3, "0")}-${side}.json`, "utf8")) as UOp[]
    return { before: load("before"), after: load("after") }
  }

  test("transform_to_call keeps the count and changes every node", () => {
    const { before, after } = pass("transform_to_call")
    expect(before.length).toBe(after.length)
    expect(summarize(before, after)).not.toContain("+0 / −0")
  })

  test("at least one get_kernel_graph pass halves the graph", () => {
    const cuts = steps
      .filter((s) => s.caller === "get_kernel_graph" && s.kept)
      .map((s) => {
        const load = (side: string) =>
          JSON.parse(readFileSync(`${root}/graphs/${String(s.i).padStart(3, "0")}-${side}.json`, "utf8")) as UOp[]
        const b = load("before"), a = load("after")
        const gone = compose(b, a).nodes.filter((x) => x.state === "removed").length
        return gone / b.length
      })
    expect(Math.max(...cuts)).toBeGreaterThan(0.5)
  })
})
