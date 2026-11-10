import { readFileSync, readdirSync } from "node:fs"
import path from "node:path"
import type { Plugin } from "vite"

/**
 * The Python ↔ Bend map, derived at build time from the sources themselves.
 *
 * It has to be generated, not committed: every link is a line number, and a
 * line number in a file someone edited yesterday is a lie that looks like a
 * feature. So this runs on `buildStart`, serves the result as a virtual module,
 * and invalidates when a `.py` or `.bend` file changes in dev.
 *
 * File pairing comes from the port's own header (`# ops.bend -- tinygrad/uop/ops.py.`)
 * because that is the only statement of intent in the repo; the path convention
 * is the fallback, not the rule. Symbols match on qualified name first
 * (`Tensor.__init__`), then on the final segment, one-to-one in order.
 */

export type CompareFile = {
  py: string | null
  bend: string
  pyLines?: number
  bendLines?: number
  pyDefs?: number
  bendDefs?: number
  links?: [number, number, string][]
  pyOnly?: string[]
  bendOnly?: string[]
}

export type CompareData = {
  files: CompareFile[]
  pythonOnlyFiles: string[]
  totals: { pairs: number; bendOnly: number; pythonOnly: number; links: number }
}

const PY_HEADER = /tinygrad\/[A-Za-z0-9_/]+\.py/
const BARE_PY = /\b([A-Za-z0-9_/]+)\.py\b/
const BEND_DEF = /^def\s+([A-Za-z_][\w.]*)\s*\(/gm
const SKIP = ["runtime/autogen", "viz/assets"]

import { repoRootPromise } from "./repo-root"

function walk(dir: string, ext: string): string[] {
  const out: string[] = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) out.push(...walk(full, ext))
    else if (entry.name.endsWith(ext)) out.push(full)
  }
  return out
}

/**
 * Python symbols by indentation. Not a parser: tinygrad's defs are unindented
 * or one level inside a class, so tracking the indent stack is faithful for
 * this tree and would not be for a file using lambdas assigned to names.
 */
function pySymbols(src: string): { qual: string; line: number }[] {
  const out: { qual: string; line: number }[] = []
  const stack: { indent: number; name: string }[] = []
  src.split("\n").forEach((text, i) => {
    const m = /^(\s*)(?:(?:async\s+)?def|class)\s+([A-Za-z_]\w*)/.exec(text)
    if (!m) return
    const indent = m[1].length
    while (stack.length && stack[stack.length - 1].indent >= indent) stack.pop()
    const qual = [...stack.map((s) => s.name), m[2]].join(".")
    out.push({ qual, line: i + 1 })
    stack.push({ indent, name: m[2] })
  })
  return out
}

function bendSymbols(src: string): { qual: string; line: number }[] {
  const out: { qual: string; line: number }[] = []
  for (const m of src.matchAll(BEND_DEF)) {
    out.push({ qual: m[1], line: src.slice(0, m.index).split("\n").length })
  }
  return out
}

export async function buildCompareData(): Promise<CompareData> {
  const root = await repoRootPromise()
  const pyFiles = new Map<string, string>()
  // root-level .py too: sz.py lives beside tinygrad/, and sz.bend ports it
  for (const name of readdirSync(root).filter((f) => f.endsWith(".py"))) {
    pyFiles.set(name, path.join(root, name))
  }
  for (const p of walk(path.join(root, "tinygrad"), ".py")) {
    const rel = path.relative(root, p).split(path.sep).join("/")
    if (SKIP.some((s) => rel.includes(s))) continue
    pyFiles.set(rel, p)
  }

  const bendPaths = walk(path.join(root, "tinybendygrad"), ".bend").sort()
  const pairs: CompareFile[] = []
  const claimed = new Set<string>()

  for (const bp of bendPaths) {
    const relBend = path.relative(root, bp).split(path.sep).join("/")
    const src = readFileSync(bp, "utf8")
    const head = src.split("\n").slice(0, 80).join("\n")
    const header = PY_HEADER.exec(head)?.[0]
    let target = header && pyFiles.has(header) ? header : null
    if (!target) {
      // the port does not always write `tinygrad/` — sz.bend says "# sz.py in Bend:"
      const bare = BARE_PY.exec(head)?.[1]
      if (bare) {
        for (const candidate of [`${bare}.py`, `tinygrad/${bare}.py`]) {
          if (pyFiles.has(candidate)) {
            target = candidate
            break
          }
        }
      }
    }

    if (!target) {
      const guess = `tinygrad/${relBend.replace(/^tinybendygrad\//, "").replace(/\.bend$/, ".py")}`
      if (pyFiles.has(guess)) target = guess
    }
    if (!target) {
      pairs.push({ py: null, bend: relBend, bendLines: src.split("\n").length, bendDefs: bendSymbols(src).length })
      continue
    }

    claimed.add(target)
    const pyPath = path.join(root, target)
    const py = readFileSync(pyPath, "utf8")
    const psy = pySymbols(py)
    const bsy = bendSymbols(src)

    const used = new Set<number>()
    const links: [number, number, string][] = []
    for (const s of psy) {
      const i = bsy.findIndex((b, n) => !used.has(n) && b.qual === s.qual)
      if (i >= 0) {
        used.add(i)
        links.push([s.line, bsy[i].line, s.qual])
      }
    }
    const byTail = new Map<string, { qual: string; line: number }>()
    for (const s of psy) byTail.set(s.qual.split(".").pop()!, s)
    bsy.forEach((b, i) => {
      if (used.has(i)) return
      const tail = b.qual.split(".").pop()!
      const hit = byTail.get(tail)
      if (hit) {
        byTail.delete(tail)
        used.add(i)
        links.push([hit.line, b.line, hit.qual])
      }
    })

    const matchedTails = new Set(links.map(([,, q]) => q.split(".").pop()!))
    pairs.push({
      py: target,
      bend: relBend,
      pyLines: py.split("\n").length,
      bendLines: src.split("\n").length,
      pyDefs: psy.length,
      bendDefs: bsy.length,
      links: links.sort((a, b) => a[0] - b[0]),
      pyOnly: [...new Set(psy.map((s) => s.qual.split(".").pop()!))].filter((n) => !matchedTails.has(n)).sort(),
      bendOnly: bsy.filter((_, i) => !used.has(i)).map((b) => b.qual.split(".").pop()!).sort(),
    })
  }

  const pythonOnlyFiles = [...pyFiles.keys()].filter((f) => !claimed.has(f)).sort()
  return {
    files: pairs.sort((a, b) => (a.py ?? a.bend).localeCompare(b.py ?? b.bend)),
    pythonOnlyFiles,
    totals: {
      pairs: pairs.filter((p) => p.py).length,
      bendOnly: pairs.filter((p) => !p.py).length,
      pythonOnly: pythonOnlyFiles.length,
      links: pairs.reduce((n, p) => n + (p.links?.length ?? 0), 0),
    },
  }
}

const ID = "virtual:compare-data"
const RESOLVED = "\0" + ID

export function compareData(): Plugin {
  let cached: string | null = null
  return {
    name: "30k:compare-data",
    resolveId: (id) => (id === ID ? RESOLVED : null),
    async load(id) {
      if (id !== RESOLVED) return null
      cached ??= JSON.stringify(await buildCompareData())
      return `export default ${cached}`
    },
    buildStart() {
      cached = null
    },
    handleHotUpdate({ file, server }) {
      if (!/\.(py|bend)$/.test(file)) return
      cached = null
      const mod = server.moduleGraph.getModuleById(RESOLVED)
      if (mod) server.moduleGraph.invalidateModule(mod)
    },
  }
}
