import { describe, expect, test } from "bun:test"
import { readFileSync } from "node:fs"
import { beatAt, positionAt, startOf, validate, type Timeline } from "../src/track"

const t = (beats: [string, number, number][], duration: number, verified = true): Timeline => ({
  lesson: "test",
  mode: "clips",
  audio: null,
  duration,
  verified,
  beats: beats.map(([id, start, end]) => ({ id, start, end })),
})

const three = t([["a", 0, 1], ["b", 1, 2.5], ["c", 2.5, 4]], 4)

describe("beatAt", () => {
  test("returns the beat playing at a time", () => {
    expect(beatAt(three, 0)?.id).toBe("a")
    expect(beatAt(three, 1.2)?.id).toBe("b")
    expect(beatAt(three, 3.9)?.id).toBe("c")
  })

  test("a boundary belongs to the beat that starts there", () => {
    expect(beatAt(three, 1)?.id).toBe("b")
    expect(beatAt(three, 2.5)?.id).toBe("c")
  })

  test("past the end holds the last beat rather than returning nothing", () => {
    expect(beatAt(three, 99)?.id).toBe("c")
  })
})

describe("positionAt", () => {
  test("progress is linear inside a beat", () => {
    expect(positionAt(three, 1)?.progress).toBeCloseTo(0, 5)
    expect(positionAt(three, 1.75)?.progress).toBeCloseTo(0.5, 5)
    expect(positionAt(three, 4)?.progress).toBeCloseTo(1, 5)
  })

  test("reports the time left in the beat", () => {
    expect(positionAt(three, 1)?.remaining).toBeCloseTo(1.5, 5)
  })
})

describe("startOf", () => {
  test("seeks to a beat", () => {
    expect(startOf(three, "c")).toBe(2.5)
    expect(startOf(three, "nope")).toBeUndefined()
  })
})

describe("validate", () => {
  test("a contiguous timeline is clean", () => {
    expect(validate(three)).toEqual([])
  })

  test("a dropped beat shows up as a gap", () => {
    const holed = t([["a", 0, 1], ["c", 2.5, 4]], 4)
    expect(validate(holed).some((p) => p.includes("gap"))).toBe(true)
  })

  test("an unverified timeline never passes", () => {
    expect(validate(t([["a", 0, 4]], 4, false))).toEqual([
      "timeline was not verified against the audio",
    ])
  })

  test("a short tail is a failure, not a rounding difference", () => {
    expect(validate(t([["a", 0, 3.5]], 4)).some((p) => p.includes("end of the audio"))).toBe(true)
  })
})

describe("the draft 01.1 timeline on disk", () => {
  test("validates against the same rules the player applies", () => {
    const raw = readFileSync(`${import.meta.dir}/../../../content/voice/01.1/draft-timeline.json`, "utf8")
    const timeline = JSON.parse(raw) as Timeline
    expect(timeline.beats.length).toBe(5)
    expect(validate(timeline)).toEqual([])
    expect(beatAt(timeline, 0)?.id).toBe("b1")
  })
})
