import { AnimatePresence, motion } from "motion/react"
import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"

type Claim = { id: string; kind: string; text: string; lines: number[] }
type Beat = { id: string; text: string; cue?: { claims?: string[]; lines?: number[] }; direction?: string }

const KIND: Record<string, string> = {
  effect: "what it does",
  reason: "why",
  cost: "what it costs",
  trap: "the trap",
}

/**
 * The explanation, paced.
 *
 * effect.institute's move is that a sentence and a line arrive together. So the
 * unit here is the beat, not the paragraph: each beat brings its claims in with
 * a short stagger, and the previous ones leave rather than accumulate, which is
 * what keeps a 6-beat lesson readable instead of a wall.
 */
export function ExplainTab({ claims, beats }: { claims: Claim[]; beats: Beat[] }) {
  const [i, setI] = useState(0)
  const beat = beats[Math.min(i, beats.length - 1)]

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "ArrowRight" || e.code === "Space") {
        e.preventDefault()
        setI((n) => Math.min(n + 1, beats.length - 1))
      }
      if (e.key === "ArrowLeft") setI((n) => Math.max(n - 1, 0))
    }
    addEventListener("keydown", onKey)
    return () => removeEventListener("keydown", onKey)
  }, [beats.length])

  const shown = (beat.cue?.claims ?? [])
    .map((id) => claims.find((c) => c.id === id))
    .filter(Boolean) as Claim[]

  return (
    <div className="mx-auto flex h-full max-w-[62ch] flex-col px-8 py-10">
      <div className="mb-8 flex items-center gap-2">
        {beats.map((b, n) => (
          <button
            key={b.id}
            onClick={() => setI(n)}
            aria-label={`beat ${n + 1}`}
            className={
              "h-[3px] flex-1 transition-colors " +
              (n < i ? "bg-ink" : n === i ? "bg-accent" : "bg-rule")
            }
          />
        ))}
        <span className="ml-3 text-[10px] tabular-nums text-faint">
          {i + 1} / {beats.length}
        </span>
      </div>

      <div className="min-h-[240px]">
        <AnimatePresence mode="wait">
          <motion.div key={beat.id} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }} transition={{ duration: 0.22, ease: [0.2, 0.9, 0.2, 1] }}>
            {shown.map((c, n) => (
              <motion.div
                key={c.id}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.05 + n * 0.07, duration: 0.26, ease: "easeOut" }}
                className="mb-6 border-l-2 border-accent pl-4"
              >
                <div className="mb-1 text-[9px] uppercase tracking-[.14em] text-accent-ink">
                  {KIND[c.kind] ?? c.kind}
                </div>
                <p className="font-sans text-[15px] leading-[1.65] text-ink">{c.text}</p>
              </motion.div>
            ))}
          </motion.div>
        </AnimatePresence>
      </div>

      <div className="mt-auto border-t border-rule pt-4">
        <div className="mb-1 text-[9px] uppercase tracking-[.14em] text-faint">narration</div>
        <p className="font-sans text-[13px] leading-[1.7] text-muted italic">{beat.text}</p>
        <div className="mt-5 flex items-center gap-2">
          <Button variant="outline" size="sm" className="h-7 rounded-none text-[11px]"
            onClick={() => setI((n) => Math.max(n - 1, 0))} disabled={i === 0}>
            ←
          </Button>
          <Button size="sm" className="h-7 rounded-none bg-ink text-[11px] text-paper hover:bg-ink2"
            onClick={() => setI((n) => Math.min(n + 1, beats.length - 1))} disabled={i === beats.length - 1}>
            next beat →
          </Button>
          <span className="ml-2 text-[10px] text-faint">space / arrows</span>
        </div>
      </div>
    </div>
  )
}
