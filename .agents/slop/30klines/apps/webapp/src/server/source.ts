import { createServerFn } from "@tanstack/react-start"
import { Effect } from "effect"
import { FileSystem } from "effect/FileSystem"
import { Path } from "effect/Path"
import { NodeFs, repoRoot } from "../../plugins/repo-root"

/**
 * Read one source file for the compare view.
 *
 * The contents are not bundled: the two trees are ~280k lines, and a bundle
 * would pin the page to a revision the mapping was built from — which is the
 * drift this feature exists to make visible. The server reads the working tree
 * instead, so the line a link lands on is the line a human sees.
 *
 * The path is a parameter, so it is checked: two roots, no traversal, no
 * absolute paths. A page that can read /etc/passwd is a bug with a feature
 * request attached.
 */
// Three shapes: the two trees, and a root-level .py (sz.py lives beside them
// and sz.bend ports it).
const ALLOWED = [/^tinygrad\/[A-Za-z0-9_/]+\.py$/, /^tinybendygrad\/[A-Za-z0-9_/]+\.bend$/, /^[A-Za-z0-9_]+\.py$/]

export const readSource = createServerFn({ method: "GET" })
  .validator((input: { path: string }) => {
    const p = input?.path ?? ""
    if (!ALLOWED.some((re) => re.test(p))) throw new Error(`refused: ${p}`)
    if (p.includes("..") || p.startsWith("/")) throw new Error(`refused: ${p}`)
    return { path: p }
  })
  .handler(async ({ data }) => {
    const program = Effect.gen(function* () {
      const fs = yield* FileSystem
      const path = yield* Path
      const root = yield* repoRoot()
      return yield* fs.readFileString(path.join(root, data.path))
    }).pipe(Effect.provide(NodeFs))
    return { path: data.path, text: await Effect.runPromise(program) }
  })
