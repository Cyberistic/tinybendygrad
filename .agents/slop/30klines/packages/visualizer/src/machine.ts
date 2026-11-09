/**
 * The pass player, as an Effect-driven state machine.
 *
 * Shape follows kitlangton/visual-effect: a tiny external store with a set of
 * states, a table of transitions that REFUSES anything not in it, a sound cue on
 * every transition, and an Effect fiber doing the work. React subscribes with
 * useSyncExternalStore, so the machine is the single source of truth and the
 * component is a projection of it — the same reason `track.ts` owns the clock.
 *
 * Time is injected: the loop calls `Effect.sleep`, but `advance()` is public and
 * pure, so tests walk the states without waiting.
 */
import { Effect, Fiber } from "effect"

export type PlayerState =
  | { readonly type: "idle" }
  | { readonly type: "playing"; readonly index: number }
  | { readonly type: "paused"; readonly index: number }
  | { readonly type: "complete"; readonly index: number }

export type Cue = "start" | "step" | "pause" | "done"

/** A transition not in this table is refused, not thrown — a wrong state is a bug, a no-op is a symptom. */
export const VALID: Record<PlayerState["type"], ReadonlySet<PlayerState["type"]>> = {
  idle: new Set(["playing", "paused"]),  // seeking before playing positions you, it does not run
  playing: new Set(["playing", "paused", "complete", "idle"]),
  paused: new Set(["playing", "paused", "idle"]),
  complete: new Set(["playing", "complete", "idle"]),
}

export type PlayerOptions = {
  readonly count: number
  /** milliseconds between passes while playing */
  readonly delayMs?: number
  readonly cue?: (cue: Cue) => void
}

export class PassPlayer {
  private readonly listeners = new Set<() => void>()
  private fiber: Fiber.RuntimeFiber<void, never> | null = null
  private state: PlayerState = { type: "idle" }
  private readonly count: number
  private readonly delayMs: number
  private readonly cue: (cue: Cue) => void

  constructor(options: PlayerOptions) {
    this.count = Math.max(1, options.count)
    this.delayMs = options.delayMs ?? 1500
    this.cue = options.cue ?? (() => {})
  }

  readonly subscribe = (listener: () => void) => {
    this.listeners.add(listener)
    return () => {
      this.listeners.delete(listener)
    }
  }

  readonly snapshot = (): PlayerState => this.state

  get index(): number {
    return this.state.type === "idle" ? 0 : this.state.index
  }

  /** The only mutator. Refuses an illegal transition and says so in dev. */
  private set(next: PlayerState): boolean {
    if (!VALID[this.state.type].has(next.type)) {
      if (process.env.NODE_ENV !== "production") {
        console.warn(`refused transition ${this.state.type} → ${next.type}`)
      }
      return false
    }
    const before = this.state.type
    this.state = next
    if (before !== next.type) this.cue(cueFor(next))
    for (const l of this.listeners) l()
    return true
  }

  /**
   * One step. Public so a test can walk the whole sequence without timers.
   * Returns false when there is nowhere left to go.
   */
  advance(): boolean {
    const next = this.index + 1
    if (next >= this.count) {
      this.set({ type: "complete", index: this.count - 1 })
      return false
    }
    this.set({ type: "playing", index: next })
    this.cue("step")
    return true
  }

  play(): void {
    if (this.state.type === "playing") return
    const from = this.state.type === "complete" ? 0 : this.index
    if (!this.set({ type: "playing", index: from })) return
    let i = from
    this.fiber = Effect.runFork(
      Effect.gen(function* () {
        while (i < this.count - 1) {
          yield* Effect.sleep(`${this.delayMs} millis`)
          i += 1
          this.set({ type: "playing", index: i })
          this.cue("step")
        }
        this.set({ type: "complete", index: this.count - 1 })
      }.bind(this)) as Effect.Effect<void>,
    )
  }

  pause(): void {
    if (this.fiber) {
      Effect.runSync(Fiber.interrupt(this.fiber))
      this.fiber = null
    }
    if (this.state.type === "playing") this.set({ type: "paused", index: this.index })
  }

  seek(index: number): void {
    const i = Math.max(0, Math.min(index, this.count - 1))
    if (this.state.type === "playing") {
      this.pause()
      this.set({ type: "paused", index: i })
      return
    }
    this.set({ type: this.state.type === "complete" ? "complete" : "paused", index: i })
  }

  reset(): void {
    this.pause()
    this.set({ type: "idle" })
  }

  get running(): boolean {
    return this.state.type === "playing"
  }
}

function cueFor(state: PlayerState): Cue {
  switch (state.type) {
    case "playing":
      return "start"
    case "paused":
      return "pause"
    case "complete":
      return "done"
    default:
      return "start"
  }
}
