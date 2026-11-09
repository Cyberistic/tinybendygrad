import { describe, expect, test } from "bun:test"
import { PassPlayer, VALID } from "../src/machine"

const player = (count = 4) => new PassPlayer({ count, delayMs: 0 })

describe("transitions", () => {
  test("starts idle at zero", () => {
    const p = player()
    expect(p.snapshot().type).toBe("idle")
    expect(p.index).toBe(0)
  })

  test("idle cannot claim to be finished", () => {
    expect(VALID.idle.has("complete")).toBe(false)
    // but it can be positioned: seek before play parks you at a pass without running
    expect(VALID.idle.has("paused")).toBe(true)
  })

  test("every state can always return to idle", () => {
    for (const from of ["playing", "paused", "complete"] as const) {
      expect(VALID[from].has("idle")).toBe(true)
    }
  })
})

describe("walking the passes without a clock", () => {
  test("advance moves one pass and stops at the end", () => {
    const p = player(4)
    p.seek(0)
    expect(p.snapshot()).toEqual({ type: "paused", index: 0 })
    expect(p.advance()).toBe(true)
    expect(p.snapshot()).toEqual({ type: "playing", index: 1 })
    expect(p.advance()).toBe(true) // 2
    expect(p.advance()).toBe(true) // 3 — the last pass
    expect(p.advance()).toBe(false) // nowhere left
    expect(p.snapshot()).toEqual({ type: "complete", index: 3 })
  })

  test("advancing past the end does not run off the array", () => {
    const p = player(2)
    p.seek(0)
    p.advance()
    p.advance()
    p.advance()
    expect(p.index).toBe(1)
  })

  test("seek clamps to the range", () => {
    const p = player(3)
    p.seek(99)
    expect(p.index).toBe(2)
    p.seek(-5)
    expect(p.index).toBe(0)
  })
})

describe("the fiber", () => {
  test("play starts a fiber and pause interrupts it", async () => {
    const p = new PassPlayer({ count: 20, delayMs: 5 })
    p.play()
    expect(p.snapshot().type).toBe("playing")
    await new Promise((r) => setTimeout(r, 30))
    expect(p.index).toBeGreaterThan(0)
    p.pause()
    expect(p.snapshot().type).toBe("paused")
    const stopped = p.index
    await new Promise((r) => setTimeout(r, 30))
    expect(p.index).toBe(stopped) // an interrupted fiber does not keep ticking
  })

  test("reaching the end settles on complete, once", async () => {
    const p = new PassPlayer({ count: 3, delayMs: 2 })
    const seen: string[] = []
    p.subscribe(() => seen.push(p.snapshot().type))
    p.play()
    await new Promise((r) => setTimeout(r, 60))
    expect(p.snapshot()).toEqual({ type: "complete", index: 2 })
    expect(seen.at(-1)).toBe("complete")
  })
})

describe("subscribers", () => {
  test("one notification per state change, none for a refused move", () => {
    const p = player(3)
    let n = 0
    p.subscribe(() => n++)
    p.seek(1)
    expect(n).toBe(1)
    p.reset()
    expect(n).toBe(2)
  })
})
