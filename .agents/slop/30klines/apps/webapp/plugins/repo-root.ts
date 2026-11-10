import { Effect, Layer } from "effect"
import { FileSystem } from "effect/FileSystem"
import { Path } from "effect/Path"
import { layer as nodeFileSystem } from "@effect/platform-node/NodeFileSystem"
import { layer as nodePath } from "@effect/platform-node/NodePath"

/**
 * The repo root, found by walking up until the directory that holds both trees.
 *
 * This is Effect, not `node:fs`, because it is I/O in application code: the
 * failure is typed, the two `exists` calls compose, and the adapter that
 * actually touches the disk is a Layer — the only place a platform import is
 * allowed to appear.
 *
 * Shared by the build-time data plugin and the runtime source reader so the two
 * cannot disagree about where the code lives; a disagreement would show up as a
 * compare page where every file 404s.
 */
export const NodeFs = Layer.mergeAll(nodeFileSystem, nodePath)

export class RepoRootNotFound extends Error {
  readonly _tag = "RepoRootNotFound"
  constructor(readonly from: string) {
    super(`no tinygrad/ + tinybendygrad/ above ${from}`)
  }
}

export const repoRoot = (from: string = process.cwd()) =>
  Effect.gen(function* () {
    const fs = yield* FileSystem
    const path = yield* Path
    let dir = from
    for (let i = 0; i < 8; i++) {
      const [py, bend] = yield* Effect.all([fs.exists(path.join(dir, "tinygrad")), fs.exists(path.join(dir, "tinybendygrad"))])
      if (py && bend) return dir
      dir = path.dirname(dir)
    }
    return yield* Effect.fail(new RepoRootNotFound(from))
  }).pipe(Effect.provide(NodeFs))

export const repoRootPromise = (from?: string) => Effect.runPromise(repoRoot(from))
