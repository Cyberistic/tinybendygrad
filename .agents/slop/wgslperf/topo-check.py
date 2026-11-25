#!/usr/bin/env python3
"""**IS **THE **ARENA's **INDEX **ORDER **A **TOPOLOGICAL **ORDER?**

**WHY.** THE FOLD IS A KAHN TOPOLOGICAL SORT, AND IT PAYS FOR IT TWICE: EVERY POP WALKS THE
WHOLE ARENA TO FIND THE POPPED NODE's CONSUMERS (`Kahn.consumers`, 495,015,580 VISITS), AND
EVERY RESOLUTION WALKS THE ARENA TO FIND THE NODE ITSELF (`O.Arena.node(ar, i)`, A LINEAR
`Arena_at`). BOTH GO AWAY IF THE ARENA's INDEX ORDER IS ALREADY TOPOLOGICAL -- I.E. IF EVERY
NODE's SRCS HAVE SMALLER INDICES THAN THE NODE -- BECAUSE THEN THE FOLD IS A SINGLE FORWARD
PASS OVER THE ARENA IN INDEX ORDER.

**THE MEASUREMENT.** THE COMPILED JS's OWN ARENA: `ar["nodes"]` IS A LINKED LIST OF NODES AND
EACH NODE's `src` FIELD IS A LINKED LIST OF INDICES. THE INSTRUMENT WALKS BOTH AND COUNTS THE
SRCS THAT ARE **NOT** BELOW THEIR NODE's INDEX.

**THE VERDICT.** A VIOLATION MEANS THE FORWARD PASS CANNOT REPLACE KAHN. A CLEAN COUNT MEANS
IT CAN.
"""

import json
import pathlib
import subprocess
import sys
import time

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents/slop/wgslperf"
BEND = R / "bin/bend"

CHECK = """
function __topo(ar) {
  let nd = ar["nodes"], i = 0, bad = 0, edges = 0, selfref = 0, maxsrc = 0;
  while (nd.$ !== "Nil") {
    const node = nd["head"];
    let s = node["src"];
    while (s.$ !== "Nil") {
      const v = s["head"];
      edges++;
      if (v > maxsrc) maxsrc = v;
      if (v === i) selfref++;
      if (v >= i) bad++;
      s = s["tail"];
    }
    i++;
    nd = nd["tail"];
  }
  const g = globalThis.__T = globalThis.__T || {bad: 0, edges: 0, folds: 0, nodes: 0, maxsrc: 0, selfref: 0};
  g.bad += bad; g.edges += edges; g.folds++; g.nodes += i;
  if (maxsrc > g.maxsrc) g.maxsrc = maxsrc;
  g.selfref += selfref;
  return ar;
}
"""


def find_fn(src: str, name: str):
  i = src.find(f"function {name}(")
  if i < 0:
    return None, None
  j = src.index("{", i)
  depth = 0
  k = j
  while k < len(src):
    ch = src[k]
    if ch == '"':
      k += 1
      while k < len(src):
        if src[k] == "\\":
          k += 2
          continue
        if src[k] == '"':
          break
        k += 1
    elif ch == "{":
      depth += 1
    elif ch == "}":
      depth -= 1
      if depth == 0:
        return i, k + 1
    k += 1
  return i, None


def main():
  base = HERE / "wgslprof.mjs"
  b = subprocess.run([str(BEND), str(HERE / "wgslprof.bend"), "-o", str(base)],
                     capture_output=True, text=True)
  if b.returncode != 0:
    raise SystemExit(f"WARN: the driver did not build:\n{b.stderr[:1200]}")
  src = base.read_text()

  import re
  m = re.search(r"function (\$[A-Za-z0-9_]*uop_fold_Kahn_seed)\(", src)
  if not m:
    raise SystemExit("WARN: no Kahn_seed")
  fname = m.group(1)
  i, end = find_fn(src, fname)
  body = src[i:end]
  # **⇒⇒† AND **THE **CHECK **IS **THE **FIRST **STATEMENT** (⇒⇒† AND **AND **THE **ARENA **IS **THE
  # **ARGUMENT**)
  body = body.replace("{", "{\n  __topo(_ar_0);", 1)
  src = src[:i] + body + src[end:]
  src = CHECK + src

  outp = HERE / "wgslprof.topo.mjs"
  outp.write_text(src)
  run = HERE / "topo.run.mjs"
  run.write_text('import M from "./wgslprof.topo.mjs";\n'
                 'import fs from "fs";\n'
                 'M["chain_wgsl"]();\n'
                 'fs.writeFileSync("/tmp/topo.json", JSON.stringify(globalThis.__T || {}));\n')
  t0 = time.perf_counter()
  b = subprocess.run(["node", str(run)], capture_output=True, text=True)
  wall = (time.perf_counter() - t0) * 1000
  if b.returncode != 0:
    print(b.stderr[:2000])
    raise SystemExit("WARN: the driver did not run")
  print(f"THE WHOLE: {wall:.1f} ms")
  T = json.loads(pathlib.Path("/tmp/topo.json").read_text())
  print("THE TOPOLOGY CENSUS:")
  print(f"  THE FOLDS CHECKED:   {T['folds']:,}")
  print(f"  THE NODES VISITED:   {T['nodes']:,}")
  print(f"  THE EDGES VISITED:   {T['edges']:,}")
  print(f"  THE SRCS NOT BELOW:  {T['bad']:,}   <- A NON-ZERO HERE KILLS THE FORWARD PASS")
  print(f"  THE SELF SRCS:       {T['selfref']:,}")
  print(f"  THE LARGEST SRC INDEX SEEN: {T['maxsrc']:,}")


if __name__ == "__main__":
  main()
