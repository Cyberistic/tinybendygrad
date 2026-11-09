import { Effect, Layer, ManagedRuntime } from "effect"
import { Course, CourseLive, type CourseShape } from "@/services/course"

/**
 * One runtime, built once.
 *
 * The app is a projection of Effect programs, not a place where logic lives.
 * Components call `runSync`, which is the boundary and the only place a fiber
 * is run; everything under it composes.
 */

export const AppLayer = Layer.mergeAll(CourseLive)

export const runtime = ManagedRuntime.make(AppLayer)

const withCourse = <A, E>(f: (course: CourseShape) => Effect.Effect<A, E>) =>
  Effect.gen(function* () {
    const course = yield* Course
    return yield* f(course)
  }).pipe(Effect.provide(AppLayer))

export const lessonOf = (id: string) => withCourse((c) => c.lesson(id))
export const lessonsOf = withCourse((c) => c.lessons)
export const stagesOf = withCourse((c) => c.stages)
export const traceOf = (name: string) => withCourse((c) => c.trace(name))
export const neighboursOf = (id: string) => withCourse((c) => c.neighbours(id))
