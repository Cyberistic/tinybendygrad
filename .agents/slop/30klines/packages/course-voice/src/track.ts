/**
 * The seam between a recorded voice and the lesson it drives.
 *
 * The player never computes timing from the script text. It asks this module
 * where it is in the recording, and this module answers from a timeline that
 * was derived from the audio — by pause detection for a continuous take, or
 * by measurement for one clip per beat. Both produce the same shape, so the
 * player cannot tell which was used, and swapping a draft for a real take is
 * a file replacement rather than a code change.
 *
 * Deliberately dependency-free: it runs in a Worker, in Node for tests, and
 * in the browser unchanged.
 */

export type Beat = { readonly id: string; readonly start: number; readonly end: number }

export type Timeline = {
  readonly lesson: string
  readonly mode: "continuous" | "clips"
  readonly audio: string | null
  readonly duration: number
  /** Intentional pause between clips. Only meaningful when mode is "clips". */
  readonly gap?: number
  readonly verified: boolean
  readonly beats: readonly Beat[]
}

export type Position = {
  readonly beat: Beat
  readonly index: number
  /** 0 at the first sample of the beat, 1 at its last. */
  readonly progress: number
  /** Milliseconds remaining in this beat. */
  readonly remaining: number
}

const clamp01 = (n: number) => (n < 0 ? 0 : n > 1 ? 1 : n)

function indexAt(t: Timeline, ms: number): number {
  // beats are sorted and contiguous; a binary search keeps scrubbing cheap
  let lo = 0
  let hi = t.beats.length - 1
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1
    if (t.beats[mid].start <= ms) lo = mid
    else hi = mid - 1
  }
  return lo
}

/** The beat playing at `ms`, or undefined if the timeline is empty. */
export function beatAt(t: Timeline, ms: number): Beat | undefined {
  if (t.beats.length === 0) return undefined
  return t.beats[indexAt(t, ms)]
}

/** Beat plus how far through it we are — what a highlight and a progress bar need. */
export function positionAt(t: Timeline, ms: number): Position | undefined {
  if (t.beats.length === 0) return undefined
  const index = indexAt(t, ms)
  const beat = t.beats[index]
  const span = Math.max(beat.end - beat.start, 1e-6)
  return {
    beat,
    index,
    progress: clamp01((ms - beat.start) / span),
    remaining: Math.max(beat.end - ms, 0),
  }
}

/** Where to seek to hear `beat` from its start. */
export function startOf(t: Timeline, id: string): number | undefined {
  return t.beats.find((b) => b.id === id)?.start
}

/**
 * A timeline is usable only if it is contiguous and covers the audio. A gap
 * means a beat was dropped in the edit and the player would silently hold the
 * previous highlight for the length of the hole.
 */
export function validate(t: Timeline): readonly string[] {
  const problems: string[] = []
  // A continuous take is one stream: any hole is a dropped beat. Clips are
  // separate files played with a chosen pause, so that pause is not a hole —
  // but a longer one is, and it is still caught.
  const allowed = t.mode === "clips" ? (t.gap ?? 0) + 0.02 : 0.005
  if (!t.verified) problems.push("timeline was not verified against the audio")
  if (t.beats.length === 0) problems.push("no beats")
  t.beats.forEach((b, i) => {
    if (b.end <= b.start) problems.push(`${b.id}: end ${b.end} is not after start ${b.start}`)
    const hole = i > 0 ? b.start - t.beats[i - 1].end : 0
    if (hole > allowed) problems.push(`${b.id}: gap of ${hole.toFixed(3)}s`)
  })
  if (t.beats.length && Math.abs(t.beats[t.beats.length - 1].end - t.duration) > 0.05)
    problems.push("last beat does not reach the end of the audio")
  return problems
}
