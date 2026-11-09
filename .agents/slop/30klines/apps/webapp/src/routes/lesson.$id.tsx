import { createFileRoute, Link } from "@tanstack/react-router"
import { Effect, Result } from "effect"
import { useMemo, useSyncExternalStore } from "react"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { ExplainTab } from "@/components/lesson/explain-tab"
import { SourceTab } from "@/components/lesson/source-tab"
import { GraphTab } from "@/components/lesson/graph-tab"
import { lessonOf, neighboursOf, traceOf } from "@/lib/course"
import { makeBeatStore } from "@/services/beat"

export const Route = createFileRoute("/lesson/$id")({ component: LessonPage })

function LessonPage() {
  const { id } = Route.useParams()

  const lesson = useMemo(() => {
    const result = Effect.runSync(Effect.result(lessonOf(id)))
    return Result.isSuccess(result) ? result.success : null
  }, [id])

  const neighbours = useMemo(() => {
    const result = Effect.runSync(Effect.result(neighboursOf(id)))
    return Result.isSuccess(result) ? result.success : { previous: undefined, next: undefined }
  }, [id])

  const store = useMemo(() => makeBeatStore(lesson?.beats.length ?? 1), [lesson])
  const beat = useSyncExternalStore(store.subscribe, store.getSnapshot, store.getSnapshot)

  if (!lesson) {
    return (
      <div className="p-10 text-[12px] text-muted">
        No lesson <b className="text-ink">{id}</b>.{" "}
        <Link to="/lesson/$id" params={{ id: "01.1" }} className="border-b border-accent text-accent-ink">
          start at 01.1
        </Link>
      </div>
    )
  }

  const figure = lesson.figure
  const steps = useMemo(() => {
    if (!figure) return []
    const result = Effect.runSync(Effect.result(traceOf(figure.trace)))
    return Result.isSuccess(result) ? [...result.success] : []
  }, [figure])

  const current = lesson.beats[Math.min(beat.index, lesson.beats.length - 1)]

  return (
    <div className="flex h-[calc(100vh-44px)] flex-col">
      <div className="border-b border-rule px-6 py-4">
        <div className="flex items-baseline gap-3">
          <span className="text-[10px] tabular-nums text-faint">{lesson.id}</span>
          <h1 className="text-[15px] font-semibold tracking-tight">{lesson.title}</h1>
          <span className="text-[10px] text-faint">{lesson.minutes} min</span>
        </div>
        <p className="mt-1 max-w-[80ch] font-sans text-[12.5px] text-muted">{lesson.summary}</p>
      </div>

      <Tabs defaultValue="explain" className="flex min-h-0 flex-1 flex-col gap-0">
        <div className="flex items-center justify-between border-b border-rule bg-paper2/40 pr-4">
          <TabsList className="h-9 gap-0 rounded-none bg-transparent p-0">
            {[
              ["explain", "explanation"],
              ["source", lesson.refs[0]?.file.split("/").pop() ?? "source"],
              ["graph", "graph"],
            ].map(([value, label]) => (
              <TabsTrigger
                key={value}
                value={value}
                className="h-9 rounded-none border-r border-rule px-4 text-[11px] text-muted data-[state=active]:bg-paper data-[state=active]:text-ink data-[state=active]:shadow-[inset_0_2px_0_0_#3DA639]"
              >
                {label}
              </TabsTrigger>
            ))}
          </TabsList>
          <div className="flex items-center gap-3 text-[10px] text-faint">
            {neighbours.previous && (
              <Link to="/lesson/$id" params={{ id: neighbours.previous.id }}>← {neighbours.previous.id}</Link>
            )}
            {neighbours.next && (
              <Link to="/lesson/$id" params={{ id: neighbours.next.id }}>{neighbours.next.id} →</Link>
            )}
          </div>
        </div>

        <TabsContent value="explain" className="min-h-0 flex-1 overflow-auto">
          <ExplainTab claims={lesson.claims} beats={lesson.beats} />
        </TabsContent>

        <TabsContent value="source" className="min-h-0 flex-1 overflow-hidden">
          <SourceTab refs={lesson.refs} claims={lesson.claims} beat={current} />
        </TabsContent>

        <TabsContent value="graph" className="min-h-0 flex-1 overflow-hidden">
          {steps.length > 0 ? (
            <GraphTab steps={steps} startAt={figure?.step} />
          ) : (
            <div className="p-10 text-[11px] text-faint">
              This lesson has no recorded pass yet — the figure is declared but never recorded.
            </div>
          )}
        </TabsContent>
      </Tabs>
    </div>
  )
}
