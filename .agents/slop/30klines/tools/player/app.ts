/**
 * The lesson player, as a real page rather than a mock.
 *
 * It is built by tools/player/build.py, which writes data.json beside this file
 * and bundles it with bun. Every timing question goes through track.ts: the
 * player never decides which beat is playing, it asks. That is the whole point
 * of the seam — swapping a draft take for a recorded one changes a file, not
 * this code.
 */
import { beatAt, positionAt, type Timeline } from "../../../packages/course-voice/src/track"
import data from "./data.json"

type Ref = { file: string; start: number; end: number; lines: string[] }
type Claim = { id: string; ref: number; kind: string; lines: number[]; text: string }
type Beat = { id: string; text: string; cue?: { claims?: string[]; lines?: number[] }; direction?: string }
type Lesson = { id: string; title: string; summary: string; refs: Ref[]; claims: Claim[]; beats: Beat[] }
type Clip = { id: string; src: string }

const lesson = (data as any).lesson as Lesson
const timeline = (data as any).timeline as Timeline
const clips = (data as any).clips as Clip[]
const clipOf = new Map(clips.map((c) => [c.id, c.src]))

const $ = <T extends HTMLElement>(sel: string) => document.querySelector(sel) as T
const el = (tag: string, cls?: string, text?: string) => {
  const n = document.createElement(tag)
  if (cls) n.className = cls
  if (text !== undefined) n.textContent = text
  return n
}

/** The lines a beat talks about: its own cue, or every line its claims name. */
function linesFor(beat: Beat): Map<string, Set<number>> {
  const out = new Map<string, Set<number>>()
  const add = (refIdx: number, line: number) => {
    const key = lesson.refs[refIdx].file
    if (!out.has(key)) out.set(key, new Set())
    out.get(key)!.add(line)
  }
  if (beat.cue?.lines?.length) {
    // bare line numbers belong to the first ref; multi-ref cues name claims instead
    for (const n of beat.cue.lines) add(0, n)
  }
  for (const cid of beat.cue?.claims ?? []) {
    const claim = lesson.claims.find((c) => c.id === cid)
    if (!claim) continue
    for (const n of claim.lines) add(claim.ref, n)
  }
  return out
}

let index = 0
let playing = false
const audio = new Audio()

function renderSources() {
  const host = $("#sources")
  host.innerHTML = ""
  lesson.refs.forEach((ref, i) => {
    const block = el("section", "ref")
    const head = el("header", "refhead")
    head.append(el("span", "path", ref.file), el("span", "range", `${ref.start}–${ref.end}`))
    const code = el("div", "code")
    ref.lines.forEach((text, n) => {
      const row = el("div", "row")
      row.dataset.file = ref.file
      row.dataset.line = String(ref.start + n)
      row.dataset.ref = String(i)
      row.append(el("span", "ln", String(ref.start + n)), el("span", "ct", text || " "))
      code.append(row)
    })
    block.append(head, code)
    host.append(block)
  })
}

function paint(i: number) {
  index = Math.max(0, Math.min(i, lesson.beats.length - 1))
  const beat = lesson.beats[index]
  const want = linesFor(beat)

  for (const row of document.querySelectorAll<HTMLElement>(".row")) {
    const on = want.get(row.dataset.file!)?.has(Number(row.dataset.line))
    row.classList.toggle("on", !!on)
  }
  for (const [n, item] of beatItems.entries()) item.classList.toggle("cur", n === index)

  const claims = (beat.cue?.claims ?? [])
    .map((id) => lesson.claims.find((c) => c.id === id))
    .filter(Boolean) as Claim[]
  $("#claim").innerHTML = claims.map((c) => `<p><b>${c.kind}</b> ${c.text}</p>`).join("")
  $("#said").textContent = beat.text
  $("#beatno").textContent = `${index + 1} / ${lesson.beats.length}`

  const pos = positionAt(timeline, timeline.beats[index]?.start ?? 0)
  if (pos) ($("#progress") as HTMLInputElement).value = String(pos.progress)
  $("#tracklabel").textContent = beat.id

  const src = clipOf.get(beat.id)
  if (src && audio.src !== new URL(src, location.href).href) audio.src = src
}

function play() {
  playing = true
  document.body.classList.add("playing")
  audio.play().catch(() => { playing = false })
}

function pause() {
  playing = false
  document.body.classList.remove("playing")
  audio.pause()
}

audio.onended = () => (index + 1 < lesson.beats.length ? (paint(index + 1), playing && play()) : pause())

$("#play").onclick = () => (playing ? pause() : play())
$("#next").onclick = () => { paint(index + 1); if (playing) play() }
$("#prev").onclick = () => { paint(index - 1); if (playing) play() }

addEventListener("keydown", (e) => {
  if (e.code === "Space") { e.preventDefault(); playing ? pause() : play() }
  if (e.key === "ArrowRight") { paint(index + 1); if (playing) play() }
  if (e.key === "ArrowLeft") { paint(index - 1); if (playing) play() }
})

const beatItems = new Map<number, HTMLElement>()
function renderBeats() {
  const host = $("#beats")
  lesson.beats.forEach((b, i) => {
    const item = el("button", "beat")
    item.append(el("span", "bi", b.id), el("span", "bt", b.text.slice(0, 64) + "…"))
    item.onclick = () => { paint(i); if (playing) play() }
    beatItems.set(i, item)
    host.append(item)
  })
}

renderSources()
renderBeats()
$("#title").textContent = lesson.title
$("#id").textContent = lesson.id
$("#summary").textContent = lesson.summary

// ?beat=b3 lets a link point at a frame, which is also how the screenshots are taken
const deep = new URLSearchParams(location.search).get("beat")
paint(deep ? Math.max(0, lesson.beats.findIndex((b) => b.id === deep)) : 0)
