import { Context, Effect, Layer, Schema } from "effect"
import raw from "@/data/course.json"
import { CourseData, decodeCourse, Lesson, Stage, TraceStep } from "@/domain/course"

/**
 * The course, as a service.
 *
 * Nothing in the UI imports `course.json`. Every read is an Effect with a typed
 * failure, so a missing lesson is a value the route can handle rather than a
 * `undefined` that crashes three components later.
 */

export class LessonNotFound extends Schema.TaggedError<LessonNotFound>()(
  "LessonNotFound",
  { id: Schema.String },
  { description: "The course has no lesson with this id." },
) {}

export class TraceNotFound extends Schema.TaggedError<TraceNotFound>()(
  "TraceNotFound",
  { name: Schema.String },
  { description: "No recorded trace with this name." },
) {}

export type CourseShape = {
  readonly data: Effect.Effect<CourseData>
  readonly stages: Effect.Effect<ReadonlyArray<Stage>>
  readonly lessons: Effect.Effect<ReadonlyArray<Lesson>>
  readonly lesson: (id: string) => Effect.Effect<Lesson, LessonNotFound>
  readonly neighbours: (id: string) => Effect.Effect<{ previous?: Lesson; next?: Lesson }, LessonNotFound>
  readonly trace: (name: string) => Effect.Effect<ReadonlyArray<TraceStep>, TraceNotFound>
}

export class Course extends Context.Service<Course, CourseShape>()(
  "@30k/Course",
) {}

// Decoded once, at module load: a generator that emits a bad shape fails the
// build instead of shipping a page that renders nothing.
const data = decodeCourse(raw)
const byId = new Map(data.lessons.map((l) => [l.id, l]))
const ordered = [...data.lessons].sort((a, b) => a.id.localeCompare(b.id))

export const CourseLive = Layer.succeed(Course, {
  data: Effect.succeed(data),
  stages: Effect.succeed(data.stages),
  lessons: Effect.succeed(ordered),
  lesson: (id) => {
    const hit = byId.get(id)
    return hit ? Effect.succeed(hit) : Effect.fail(new LessonNotFound({ id }))
  },
  neighbours: (id) => {
    const i = ordered.findIndex((l) => l.id === id)
    if (i < 0) return Effect.fail(new LessonNotFound({ id }))
    return Effect.succeed({
      previous: i > 0 ? ordered[i - 1] : undefined,
      next: i < ordered.length - 1 ? ordered[i + 1] : undefined,
    })
  },
  trace: (name) => {
    const hit = data.traces[name]
    return hit ? Effect.succeed(hit) : Effect.fail(new TraceNotFound({ name }))
  },
})
