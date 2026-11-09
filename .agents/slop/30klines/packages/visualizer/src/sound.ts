/**
 * Cues, synthesised. No audio assets — the same rule as everything else here.
 *
 * One oscillator, one envelope, done. The reference project uses Tone.js for a
 * richer palette; this needs four blips and a browser, so it uses neither.
 */
export type Cue = "start" | "step" | "pause" | "done"

type Voice = { freq: number; ms: number; gain: number }

const VOICES: Record<Cue, Voice> = {
  start: { freq: 520, ms: 90, gain: 0.045 },
  step: { freq: 780, ms: 55, gain: 0.03 },
  pause: { freq: 300, ms: 70, gain: 0.035 },
  done: { freq: 640, ms: 220, gain: 0.05 },
}

let ctx: AudioContext | null = null
let unlocked = false

/** Chrome will not let an AudioContext start before a gesture. Call this from one. */
export function unlockAudio(): void {
  unlocked = true
  if (ctx?.state === "suspended") void ctx.resume()
}

export function cue(name: Cue, enabled = true): void {
  if (!enabled || !unlocked || typeof window === "undefined") return
  const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
  if (!Ctor) return
  ctx ??= new Ctor()
  const { freq, ms, gain } = VOICES[name]
  const t = ctx.currentTime
  const osc = ctx.createOscillator()
  const env = ctx.createGain()
  osc.type = "sine"
  osc.frequency.value = freq
  env.gain.setValueAtTime(0, t)
  env.gain.linearRampToValueAtTime(gain, t + 0.008)
  env.gain.exponentialRampToValueAtTime(0.0001, t + ms / 1000)
  osc.connect(env).connect(ctx.destination)
  osc.start(t)
  osc.stop(t + ms / 1000 + 0.02)
}
