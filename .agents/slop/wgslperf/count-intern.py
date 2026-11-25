#!/usr/bin/env python3
"""**THE **COUNTS **OF **THE **INTERNING **AND **THE **ARENA's **ACCESSORS**, **MEASURED **IN **THE
**COMPILED **JS.**

**WHY.** V8's PROFILE SAYS WHERE THE TIME IS (`Ops.value` 13.1%, `Arena.at.go` 21.5%,
`RTable.get.go` 9.4%) BUT NOT HOW MANY TIMES THE INNER WORK RUNS, AND THE COUNT IS THE
MULTIPLIER: A QUADRATIC SHOWS UP AS A COUNT, NOT AS A PERCENTAGE. THE TREE's OWN RULE: A COUNT
WITHOUT THE COMMAND THAT PRODUCED IT IS NOT A MEASUREMENT.

**THE **COMMANDS.**
  `.venv/bin/python .agents/slop/wgslperf/count-intern.py`

**THE **COUNTERS.**
  * `intern.find` CALLS == THE NODE COMPARISONS OF THE INTERNING (THE COMPILED FORM IS A REAL
    RECURSION, NOT A LOOP, SO ONE CALL IS ONE NODE).
  * `Ops.value` CALLS, AND A HISTOGRAM OF THE VALUE IT RETURNS -- THE VALUE IS THE ARM's
    POSITION, SO THE HISTOGRAM's WEIGHTED SUM IS THE NUMBER OF TAG COMPARISONS.
  * `Arena.at.go` ITERATIONS == THE CELLS WALKED (THE COMPILED FORM IS A `for(;;)` LOOP, SO THE
    ENTRY COUNTER FIRES ONCE PER CALL AND THE ITERATION COUNTER FIRES ONCE PER CELL).
  * `RTable.get.go` ITERATIONS == THE CELLS SCANNED.
"""

import json
import pathlib
import re
import subprocess
import sys

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents/slop/wgslperf"
BEND = R / "bin/bend"

ACC = """globalThis.__C = globalThis.__C || {};
globalThis.__CC = (k) => { globalThis.__C[k] = (globalThis.__C[k] || 0) + 1; };
globalThis.__CH = (k, v) => { globalThis.__C[k] = globalThis.__C[k] || {}; globalThis.__C[k][v] = (globalThis.__C[k][v] || 0) + 1; };"""


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
        rest = src[k + 1:k + 12].lstrip()
        if rest.startswith("else"):
          k += 1
          continue
        return i, k + 1
    k += 1
  return i, None


def build():
  out = HERE / "wgslprof.count.mjs"
  b = subprocess.run([str(BEND), str(HERE / "wgslprof.bend"), "-o", str(out)],
                     capture_output=True, text=True)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"WARN: the driver did not build:\n{b.stderr[:1500]}")
  return out


def main():
  base = build()
  src = base.read_text()
  out = src

  def patch_fn(tail: str, entry: str, iter_marker=None):
    """**THE **COUNTER **AT **THE **ENTRY**, **AND **THE **ITERATION **COUNTER **INSIDE **THE
    **LOOP **BODY **IF **THE **FUNCTION **IS **A **LOOP**."""
    nonlocal out
    pat = re.compile(r"function (\$[A-Za-z0-9_]*" + re.escape(tail) + r")\(")
    ms = pat.findall(out)
    if len(ms) != 1:
      print(f"  (the {tail} name matched {len(ms)} functions -- SKIPPED, an ambiguous name is not a count)")
      return
    fname = ms[0]
    i, end = find_fn(out, fname)
    body = out[i:end]
    body = body.replace("{", "{\n  globalThis.__CC(\"" + entry + "\");", 1)
    if iter_marker:
      body = body.replace(iter_marker, iter_marker + "\n  globalThis.__CC(\"" + entry + ".iter\");", 1)
    out = out[:i] + body + out[end:]

  # THE ENTRY COUNTERS.
  patch_fn("intern_find", "intern.find")
  patch_fn("UOp_make_intern", "UOp.make.intern")
  patch_fn("UOp_of_intern", "UOp.of.intern")
  patch_fn("intern_put_shp", "intern.put.shp")
  patch_fn("eq_node_ov_go", "eq_node.ov.go")
  patch_fn("eq_u32", "eq_u32")
  patch_fn("eq_arg", "eq_arg")
  patch_fn("eq_tag", "eq_tag")
  patch_fn("Arena_next", "Arena.next")

  # THE ITERATION COUNTERS: THE LOOP BODY'S FIRST STATEMENT.
  patch_fn("Arena_at_go", "Arena.at.go", "    const _ns_0 = $0;")
  patch_fn("RTable_get_go", "RTable.get.go", "    const _rs_0 = $0;")
  patch_fn("Kahn_get_chunk_go", "Kahn.get.chunk.go", "    const _es_0 = $0;")

  # THE OPS.value HISTOGRAM: EVERY `return N;` IN THE FUNCTION BECOMES A COUNT.
  pat = re.compile(r"function (\$[A-Za-z0-9_]*Ops_value)\(")
  ms = pat.findall(out)
  if len(ms) != 1:
    raise SystemExit(f"WARN: Ops.value matched {len(ms)} functions")
  fname = ms[0]
  i, end = find_fn(out, fname)
  body = out[i:end]
  body = body.replace("{", "{\n  globalThis.__CC(\"Ops.value\");", 1)
  body = re.sub(r"return (\d+);", r'return globalThis.__CH("Ops.value.by", \1), \1;', body)
  out = out[:i] + body + out[end:]

  # THE MATCH POSITION: `intern.find.pick` IS THE HEAD'S VERDICT, AND IT IS TRUE FOR THE NODE
  # THAT MATCHED, SO THE HISTOGRAM OF ITS `k` IS THE HISTOGRAM OF WHERE THE MATCH WAS.
  pat = re.compile(r"function (\$[A-Za-z0-9_]*intern_find_pick)\(")
  ms = pat.findall(out)
  if len(ms) == 1:
    fname = ms[0]
    i, end = find_fn(out, fname)
    body = out[i:end]
    body = body.replace("if (_hit_0) {",
                        "if (_hit_0) {\n    globalThis.__CH(\"intern.hit\", _k_0);", 1)
    out = out[:i] + body + out[end:]

  # THE DEPTH THE ARENA STORES: `intern.put.shp` IS THE ONLY WRITER, AND THE DEPTH IS PART OF
  # THE INTERNING's KEY (`sh == depth`), SO THE HISTOGRAM SAYS WHETHER THE KEY IS TRIVIAL.
  pat = re.compile(r"function (\$[A-Za-z0-9_]*intern_put_shp)\(")
  ms = pat.findall(out)
  if len(ms) == 1:
    fname = ms[0]
    i, end = find_fn(out, fname)
    body = out[i:end]
    body = body.replace("{", "{\n  globalThis.__CH(\"arena.depth\", _depth_0);", 1)
    out = out[:i] + body + out[end:]

  m = re.search(r"function (\$chain_wgsl)\(([^)]*)\)\s*\{", out)
  if not m:
    raise SystemExit("WARN: no chain_wgsl")
  i = out.find(m.group(0))
  out = out[:i] + ACC + out[i:]

  outp = HERE / "wgslprof.count.mjs"
  outp.write_text(out)
  chk = subprocess.run(["node", "--check", str(outp)], capture_output=True, text=True)
  if chk.returncode != 0:
    raise SystemExit(f"WARN: the counting build does not parse:\n{chk.stderr[:1500]}")

  call = HERE / "call-count.mjs"
  call.write_text('import M from "./wgslprof.count.mjs";\n'
                  'import fs from "fs";\n'
                  'M["chain_wgsl"]();\n'
                  'fs.writeFileSync(process.env.__WGSL_OUT || "/tmp/wgslcount.json",\n'
                  '  JSON.stringify(globalThis.__C || {}));\n')
  env = dict(subprocess.os.environ)
  env["__WGSL_OUT"] = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/wgslcount.json"
  b = subprocess.run(["node", str(call)], capture_output=True, text=True, env=env, cwd=str(HERE))
  if b.returncode != 0:
    print(b.stderr[:1500])
    raise SystemExit("WARN: the counting driver did not run")
  C = json.loads(pathlib.Path(env["__WGSL_OUT"]).read_text())
  print("THE COUNTS:")
  for k in sorted(C):
    if k.endswith(".by") or k in ("intern.hit", "arena.depth"):
      continue
    print(f"  {k:28s} {C[k]:14,}")
  by = C.get("Ops.value.by", {})
  if by:
    tot = sum(by.values())
    weighted = sum(int(k) * v for k, v in by.items())
    print()
    print(f"  Ops.value: {tot:,} calls, THE WEIGHTED SUM OF THE ARM POSITIONS: {weighted:,}")
    print(f"  (THE MEAN ARM POSITION: {weighted/max(tot,1):.1f} OF ~60, SO A CALL IS ~{weighted/max(tot,1):.0f} TAG COMPARISONS)")
    print("  THE TOP ARMS:")
    for k, v in sorted(by.items(), key=lambda kv: -kv[1])[:12]:
      print(f"    value {k:>3s}  {v:12,}  ({100.0*v/tot:5.1f}%)")
  dep = C.get("arena.depth", {})
  if dep:
    tot = sum(dep.values())
    print()
    print(f"THE DEPTH THE ARENA STORES: {tot:,} NODES, AND THE HISTOGRAM IS "
          + ", ".join(f"{k}:{v}" for k, v in sorted(dep.items(), key=lambda kv: -kv[1])[:6]))
  hit = C.get("intern.hit", {})
  if hit:
    tot = sum(hit.values())
    mean = sum(int(k) * v for k, v in hit.items()) / max(tot, 1)
    print()
    print(f"THE MATCH POSITION: {tot:,} HITS, THE MEAN INDEX {mean:.1f}")
    print("  THE DISTRIBUTION (THE BUCKETS ARE THE MATCH'S INDEX):")
    for lo in range(0, 512, 32):
      n = sum(v for k, v in hit.items() if lo <= int(k) < lo + 32)
      if n:
        print(f"    {lo:4d}-{lo + 31:4d}  {n:12,}  ({100.0*n/tot:5.1f}%)")


if __name__ == "__main__":
  main()
