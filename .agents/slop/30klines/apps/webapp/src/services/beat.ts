import { Effect } from "effect"

/**
 * Beat navigation, as Effects.
 *
 * There is deliberately no error channel: the store clamps, and the buttons
 * that would go out of range are disabled. An unreachable failure modelled as
 * a typed error is noise; a reachable one belongs in the type. What matters is
 * that every transition is an Effect, so the caller composes rather than
 * mutating, and a test can run the sequence with no React and no clock.
 */

export type BeatState = { readonly index: number; readonly count: number }

export type BeatStore = {
  getSnapshot: () => BeatState
  subscribe: (listener: () => void) => () => void
  next: Effect.Effect<BeatState>
  previous: Effect.Effect<BeatState>
  seek: (index: number) => Effect.Effect<BeatState>
  reset: Effect.Effect<BeatState>
}

export function makeBeatStore(count: number, startIndex = 0): BeatStore {
  const clamp = (n: number) => Math.max(0, Math.min(n, count - 1))
  let state: BeatState = { index: clamp(startIndex), count }
  const listeners = new Set<() => void>()

  const move = (to: number) =>
    Effect.sync(() => {
      const index = clamp(to)
      if (index !== state.index) {
        state = { index, count }
        for (const l of listeners) l()
      }
      return state
    })

  return {
    getSnapshot: () => state,
    subscribe: (listener) => {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
    next: move(state.index + 1),
    previous: move(state.index - 1),
    seek: (index) => move(index),
    reset: move(0),
  }
}
