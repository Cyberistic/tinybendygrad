import { describe, expect, test } from "bun:test"
import { readFileSync } from "node:fs"
import { removed, summarize, toFlow, type UOp } from "../src/flow"

const n = (i: number, op: string, src: number[] = [], arg = ""): UOp =>
  ({ i, op, arg, dtype: "void", src })

describe("layout", () => {
  test("the sink is at the top and every source sits below it", () => {
    // 0 = SINK, 1 = ADD, 2/3 = its operands
    const g = [n(0, "SINK", [1]), n(1, "ADD", [2, 3]), n(2, "CONST"), n(3, "CONST")]
    const y = new Map(toFlow(g).nodes.map((x) => [x.id, x.position.y]))
    expect(y.get("0")).toBe(0)
    expect(y.get("1")).toBe(86)
    expect(y.get("2")).toBe(172)
    expect(y.get("3")).toBe(172)
  })

  test("the same graph always lays out the same way", () => {
    const g = [n(0, "SINK", [1]), n(1, "ADD", [2]), n(2, "CONST")]
    expect(JSON.stringify(toFlow(g))).toBe(JSON.stringify(toFlow(g)))
  })

  test("one edge per src, and none pointing outside the graph", () => {
    const g = [n(0, "SINK", [1]), n(1, "ADD", [2, 99]), n(2, "CONST")]
    const f = toFlow(g)
    expect(f.edges.map((e) => e.id)).toEqual(["0->1", "1->2"])
  })
})

describe("diff", () => {
  test("a node with the same shape is the same node", () => {
    const before = [n(0, "ADD", [1, 2]), n(1, "CONST"), n(2, "CONST")]
    const after = [n(0, "ADD", [1, 2]), n(1, "CONST"), n(2, "CONST")]
    expect(toFlow(after, before).nodes.every((x) => x.data.state === "same")).toBe(true)
  })

  test("a renumbered but identical graph is not a change", () => {
    // ids are toposort positions, so they can move without the shape moving
    const before = [n(5, "ADD", [7]), n(7, "CONST")]
    const after = [n(0, "ADD", [1]), n(1, "CONST")]
    expect(toFlow(after, before).nodes.every((x) => x.data.state === "same")).toBe(true)
  })

  test("a replaced node is added, and its old self is removed", () => {
    const before = [n(0, "ADD", [1]), n(1, "CONST")]
    const after = [n(0, "MUL", [1]), n(1, "CONST")]
    expect(toFlow(after, before).nodes.find((x) => x.id === "0")?.data.state).toBe("added")
    expect(removed(before, after).map((x) => x.data.op)).toEqual(["ADD"])
  })

  test("the caption tells both axes, so a 21 to 21 pass cannot read as nothing", () => {
    const before = [n(0, "ADD", [1]), n(1, "CONST")]
    const after = [n(0, "MUL", [1]), n(1, "CONST")]
    expect(summarize(before, after)).toBe("2 → 2 nodes · +1 / −1")
  })
})

describe("a recorded pass on disk", () => {
  // Resolve by caller, not by index: a re-record renumbers passes, and a test
  // that pins an index is a change detector, not a check.
  const root = `${import.meta.dir}/../../../content/traces/add_relu_sum`
  const steps = JSON.parse(readFileSync(`${root}/steps.json`, "utf8")).steps as
    { i: number; caller: string; stage: string; kept: boolean }[]
  const pass = (caller: string) => {
    const s = steps.find((x) => x.caller === caller && x.kept)
    if (!s) throw new Error(`no kept pass for ${caller} — re-record with a bigger --keep-graphs`)
    const load = (side: string) =>
      JSON.parse(readFileSync(`${root}/graphs/${String(s.i).padStart(3, "0")}-${side}.json`, "utf8")) as UOp[]
    return { before: load("before"), after: load("after") }
  }

  test("transform_to_call keeps the count and changes every node", () => {
    const { before, after } = pass("transform_to_call")
    expect(before.length).toBe(after.length) // the number that would say "nothing happened"
    expect(summarize(before, after)).not.toContain("+0 / −0") // the structure that disagrees
  })

  test("get_kernel_graph removes more than half the graph", () => {
    const { before, after } = pass("get_kernel_graph")
    expect(removed(before, after).length).toBeGreaterThan(before.length / 2)
  })
})
