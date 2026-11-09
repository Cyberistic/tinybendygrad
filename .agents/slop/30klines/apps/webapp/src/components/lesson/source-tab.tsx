import { useMemo } from "react"
import { motion } from "motion/react"
import { highlightLines } from "@viz/highlight"

type Ref = { file: string; start: number; end: number; lines: string[] }
type Claim = { id: string; lines: number[] }
type Beat = { cue?: { claims?: string[]; lines?: number[] } }

/**
 * The source pane: real lines, syntax highlighted at runtime, with the lines
 * the current beat talks about marked. The marker is a shared layout element so
 * it slides between lines instead of blinking — the same idea as the node tween
 * in the graph tab, and the same idea as effect.institute's moving highlight.
 */
export function SourceTab({ refs, claims, beat }: { refs: Ref[]; claims: Claim[]; beat: Beat }) {
  const highlighted = useMemo(
    () => refs.map((r) => highlightLines(r.lines.join("\n"))),
    [refs],
  )

  const active = useMemo(() => {
    const out = new Map<string, Set<number>>()
    const add = (i: number, line: number) => {
      const key = refs[i].file
      if (!out.has(key)) out.set(key, new Set())
      out.get(key)!.add(line)
    }
    if (beat.cue?.lines?.length) for (const n of beat.cue.lines) add(0, n)
    for (const cid of beat.cue?.claims ?? []) {
      const c = claims.find((x) => x.id === cid)
      if (c) for (const n of c.lines) add(0, n)
    }
    return out
  }, [beat, claims, refs])

  return (
    <div className="h-full overflow-auto">
      {refs.map((ref, ri) => (
        <section key={ref.file}>
          <header className="sticky top-0 z-10 flex justify-between border-b border-rule bg-paper px-4 py-2 text-[10px] text-muted">
            <span>{ref.file}</span>
            <span className="text-faint">{ref.start}–{ref.end}</span>
          </header>
          <div className="py-2 text-[11.5px] leading-[1.72]">
            {highlighted[ri].map((html, n) => {
              const line = ref.start + n
              const on = active.get(ref.file)?.has(line)
              return (
                <div key={line} className={"relative grid grid-cols-[52px_1fr] pr-6 " + (on ? "bg-wash" : "")}>
                  {on && (
                    <motion.span
                      layoutId="active-line"
                      className="absolute inset-y-0 left-0 w-[2px] bg-accent"
                      transition={{ type: "spring", stiffness: 380, damping: 34 }}
                    />
                  )}
                  <span className={"select-none pr-3 text-right text-[10px] " + (on ? "text-accent-ink" : "text-faint")}>
                    {line}
                  </span>
                  <span
                    className={"whitespace-pre-wrap break-words " + (on ? "text-ink" : "text-ink2")}
                    dangerouslySetInnerHTML={{ __html: html || " " }}
                  />
                </div>
              )
            })}
          </div>
        </section>
      ))}
    </div>
  )
}
