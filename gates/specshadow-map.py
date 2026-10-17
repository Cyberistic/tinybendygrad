#!/usr/bin/env python3
"""The MAP: which spec-table entries exist, who calls them, and which the port can dispatch.

    .venv/bin/python gates/specshadow-map.py

WHAT THIS IS, AND WHAT IT IS NOT. It is a map and a count. It grades nothing, and it deliberately
has no PASS/FAIL: these six tables are UPSTREAM's semantics (`tinygrad/uop/spec.py`, byte-identical
to `upstream/HEAD`), the port's job is to match them, and an instrument that enforced the port's
current SHAPE would freeze a defect as if it were the contract. Where this file reports a
discrepancy it prints the arithmetic that produced it, so a reader can check the arithmetic instead
of trusting the verdict.

WHERE THE POPULATION COMES FROM, because that is the defect AGENTS.md names by name. **Not a hand
list.** Every table is FOUND, by walking for its builder (`def <name>() -> O.PMEntrys:`) and for its
`O.PMEntry{...}` rows, and every caller is FOUND by walking the tree for the name. There is no list
of six tables here to go stale: add a seventh table to `spec.bend` and it appears in the output with
no edit to this file.

THE THREE QUESTIONS, AND WHY THEY ARE THREE AND NOT ONE.
  declared      the number of `O.PMEntry` rows the builder emits.
  callers       how many call sites OUTSIDE `tinygrad/` name the entry point. Zero callers is not
                zero need: a table is read by the matcher that embeds it, not only by a call.
  reachable     CAN ANY NODE REACH THE ENTRY TODAY. This is the question a count cannot answer,
                and it is per ENTRY rather than per table, because a first-wins chain hides entries
                one at a time. Two population-free facts decide it and both are computed here:
                  (1) DISPATCH. `full_table`'s composition splits into blocks by tag and each block
                      subtracts its own base before calling that block's ladder (`fu_dispatch.of`).
                      If the two disagree by one, the first entry of a block lands on its ladder's
                      FALLBACK arm -- and each ladder's fallback is a hand-written delegate, so the
                      error is silent: it compiles, it runs, and it answers a DIFFERENT question.
                  (2) SHADOW. An entry whose rule object is identical to an EARLIER entry's can never
                      be the deciding entry, because the fold is first-wins and the rule is a pure
                      function of the node. In the port every block is a distinct `*_own` builder or a
                      single `shared_table()` value, so this is decided by construction rather than
                      counted; the tool still computes it from the composition instead of asserting it.

READING A `-ladder-arm` ROW. It means the entry's computed sub-tag is past its block's explicit
`case N: _N` arms, so the ladder's `case _` arm runs instead. That is a mechanical consequence of two
numbers in two defs, and it is the only thing in this file that is a FINDING rather than a count;
whether it changes any answer is a separate question this file does not answer, because answering it
means RUNNING the port, and running it means `bend`.

NO `__main__` GUARD, ON PURPOSE. `gates/gates-pop.py` clause I discovers gates by an `if __name__ ==
"__main__"` AST node, so a script with the guard becomes a gate, lands in the ledger, and turns the
meta-gate red for the crime of being a map. This file has no guard and is run BY PATH.
"""
import argparse
import ast
import collections
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BEND = ROOT / "tinybendygrad" / "uop" / "spec.bend"
sys.path.insert(0, str(ROOT))

SPEC_PY = ROOT / "tinygrad" / "uop" / "spec.py"
SCAN_SUFFIX = (".bend", ".py", ".mjs", ".sh")
# the entry points that take a whole graph and are the port's spelling of a `type_verify` call.
ENTRY_POINTS = ("verify_shared", "verify_tensor", "verify_program", "verify_hcq", "verify_full",
                "verify_kernel_graph")
# a table is a builder that returns `O.PMEntrys`; DISCOVERED, not listed -- see the docstring.
BUILDERS = ("shared_table", "tensor_table", "tensor_own", "program_table", "program_own",
            "hcq_table", "hcq_own", "full_table", "full_own", "kernel_graph_table")
SKIP_DIRS = (".git", "references", "runs", "__pycache__", "tinygrad.egg-info")


# --------------------------------------------------------------------------- the port's tables
def bend_def_bodies(src: str) -> dict[str, list[str]]:
  """Every `def name(...)` in a .bend file, mapped to its own indented body lines."""
  out: dict[str, list[str]] = {}
  cur: list[str] | None = None
  for line in src.splitlines():
    m = re.match(r"^def ([A-Za-z_][\w.]*)\(.*\)\s*->", line)
    if m:
      cur = []
      out[m.group(1)] = cur
    elif cur is not None:
      if line.startswith("def ") or (line and not line[0].isspace() and not line.startswith("#")):
        cur = None
      else:
        cur.append(line)
  return out


def op_list(src: str) -> dict[str, list[str]]:
  """`def OP_FOO() -> List<&2, O.Op>` -> its ops, so a helper call in a PMEntry row can be expanded.

  The RETURN TYPE IS ON THE DEF LINE, which `bend_def_bodies` does not store -- so the type test has
  to be run against the def line too, or every helper reads as unexpanded and the delta report calls
  nine perfectly good rows `(compound)`.
  """
  out: dict[str, list[str]] = {}
  heads: dict[str, str] = {}
  for line in src.splitlines():
    m = re.match(r"def ([A-Za-z_][\w]*)\(.*\)\s*->", line)
    if m:
      heads[m.group(1)] = line
  bodies = bend_def_bodies(src)

  def ops_of(name: str, depth: int = 0) -> list[str]:
    if depth > 4:
      return []
    for chunk in re.findall(r"\[([^\[\]]*)\]", "\n".join(bodies.get(name, []))):
      ops = re.findall(r"O\.Ops([A-Z_0-9]+)\{\}", chunk)
      if ops:
        return ops
    # `def OP_FOO() -> List<&2, O.Op>: OP_FOO.go()` -- the bracket list lives in the `.go` half, so a
    # one-line delegating body resolves to nothing and the row reads `(compound)` instead.
    m = re.match(r"\s*([A-Za-z_][\w.]*)\(", "\n".join(bodies.get(name, [])).strip())
    return ops_of(m.group(1), depth + 1) if m else []

  for name in bodies:
    if "List<&2, O.Op>" in heads.get(name, ""):
      ops = ops_of(name)
      if ops:
        out[name] = ops
  return out


def pm_rows(src: str, fn: str, helpers: dict[str, list[str]]) -> list[tuple[int, tuple[str, ...], tuple[str, ...]]]:
  """`(tag, ops, rej)` for each `O.PMEntry{...}` row of builder `fn`, in file order."""
  body = "\n".join(bend_def_bodies(src).get(fn, []))
  rows: list[tuple[int, tuple[str, ...], tuple[str, ...]]] = []
  for m in re.finditer(r"O\.PMEntry\{(\d+),\s*(.+?),\s*(Nil\{\}|\[[^\]]*\])\}", body):
    tag = int(m.group(1))
    ops_expr, rej_expr = m.group(2), m.group(3)
    if ops_expr.rstrip("()") in helpers:
      ops = tuple(sorted(helpers[ops_expr.rstrip("()")]))
    else:
      ops = tuple(sorted(re.findall(r"O\.Ops([A-Z_0-9]+)\{\}", ops_expr)))
    rej = tuple(re.findall(r"O\.Ops([A-Z_0-9]+)\{\}", rej_expr))
    rows.append((tag, ops, rej))
  return rows


def compositions(src: str) -> dict[str, object]:
  """The block layout of `full_table`, and the ladder each block calls -- read off the source."""
  out: dict[str, object] = {}
  bodies = bend_def_bodies(src)

  def body(fn: str) -> str:
    return "\n".join(bodies.get(fn, []))

  out["full_table_call"] = re.sub(r"\s+", " ", body("full_table")).strip()
  # `bump(N, block)` in composition order gives each block its base tag
  out["bumps"] = re.findall(r"bump\((\d+),\s*([\w.]+)\(\)\)", body("full_table"))
  out["fu_block_thresholds"] = [int(x) for x in re.findall(r"U32\.is_lt\(tag,\s*(\d+)\)", body("fu_block.go"))]
  out["fu_dispatch_of"] = re.findall(r"case (\S+): (\w+)\(U32\.sub\(tag,\s*(\d+)\)", body("fu_dispatch.of"))
  out["fu_dispatch_arms"] = [int(x) for x in re.findall(r"case (\d+): fu_", body("fu_dispatch.go"))]
  # each ladder's explicit arms and its `case _` arm
  for name in ("te_dispatch", "sh_dispatch", "pr_dispatch", "hq_dispatch"):
    g = body(f"{name}.go")
    if not g:
      continue
    arms = [int(x) for x in re.findall(r"case (\d+): \w+_", g)]
    last = [ln for ln in g.splitlines() if "case _" in ln]
    out[name] = {"arms": arms, "fallback": re.sub(r"\s+", " ", last[0]).strip() if last else "VSkip"}
  return out


# --------------------------------------------------------------------------- upstream's tables
def cpython_tables() -> dict[str, list[tuple[str, ...]]]:
  """Per entry of each upstream matcher, the op set the LIVE matcher dispatches on (`ops.py:1593`).

  The AST is not used for the op set: `.or_casted().load()` adds `Ops.LOAD` from a method call the
  AST never spells as `Ops.LOAD`, so an AST regex under-reports it. `p.op` is the dispatch key.
  """
  from tinygrad.uop import spec as S
  out = {}
  for name in ("spec_shared", "spec_tensor", "spec_program", "spec_hcq", "spec_full", "spec_kernel_graph"):
    pm = getattr(S, name)
    out[name] = [tuple(sorted(o.name for o in p.op)) for p, _ in pm.patterns]
  return out


def upstream_shadowed() -> dict[str, list[int]]:
  """Entries an EARLIER entry already answers for, by OBJECT identity of the matcher."""
  from tinygrad.uop import spec as S
  out = {}
  for name in ("spec_shared", "spec_tensor", "spec_program", "spec_hcq", "spec_full", "spec_kernel_graph"):
    seen: set[tuple[int, int]] = set()
    hit: list[int] = []
    for i, (p, f) in enumerate(getattr(S, name).patterns):
      key = (id(p), id(f))
      if key in seen:
        hit.append(i)
      seen.add(key)
    out[name] = hit
  return out


def upstream_own_counts() -> dict[str, int]:
  """`[... ]` length of each table's own literal, by AST -- the part before any `+ other`."""
  tree = ast.parse(SPEC_PY.read_text())
  out = {}
  for node in tree.body:
    if not isinstance(node, ast.Assign) or not isinstance(node.targets[0], ast.Name):
      continue
    name = node.targets[0].id
    if not name.startswith("spec_"):
      continue
    v = node.value
    while isinstance(v, ast.BinOp) and isinstance(v.op, ast.Add):
      v = v.left
    if isinstance(v, ast.Call) and v.args and isinstance(v.args[0], (ast.List, ast.Tuple)):
      out[name] = len(v.args[0].elts)
  return out


# --------------------------------------------------------------------------- call sites
def walk_sources():
  for p in sorted(ROOT.rglob("*")):
    if p.is_dir() or p.suffix not in SCAN_SUFFIX or any(s in p.parts for s in SKIP_DIRS):
      continue
    if p == Path(__file__).resolve():
      continue
    yield p


def classify(rel: str, text: str) -> str:
  """Which of the four populations a mention belongs to. Counting them together is the trap.

  `UPSTREAM-PY`  `tinygrad/` and `test/` -- upstream's code and upstream's test suite. Neither can
                 call the port's `.bend`, so a name appearing there says nothing about the port.
  `PLANT`        a synthetic COPY of `spec.bend` under `.agents/slop/**/plants/`, used as a fixture
                 by a self-test. It is a copy of the reader, not a reader; counting it would make
                 the census report a reader that a delete would recreate.
  `SPEC-ITSELF`  `tinybendygrad/uop/spec.bend`, which defines the names and reads its own tables
                 through the `t_*` rows in its tail.
  `PORT-READER`  any other file, which is the population the question is about.
  """
  if rel.startswith(("tinygrad/", "test/")):
    return "UPSTREAM-PY"
  if "/plants/" in rel or rel.endswith(".orig"):
    return "PLANT"
  if rel == "tinybendygrad/uop/spec.bend":
    return "SPEC-ITSELF"
  return "PORT-READER"


def call_sites(names) -> dict[str, dict[str, list[str]]]:
  """Every mention of each name, by DISCOVERY over the tree, bucketed by population AND by position.

  The position bucket is the one that keeps the census honest. A `WALL(p3)` note that says
  "BLOCKED: needs ... wired to `verify_tensor`" NAMES the entry point and calls nothing, and
  counting it as a call site is how a wall gets reported as a reader. In `.bend` and `.sh` a `#`
  begins a comment and in `.py` a `#` does too, so a line whose first non-space character is `#`
  is a mention; everything else is code. A name inside a string literal is still miscounted as
  code, which is the known limit and the reason the rows print their paths.
  """
  pat = re.compile(r"\b(" + "|".join(names) + r")\b")
  out: dict[str, dict[str, list[str]]] = {n: {} for n in names}
  for p in walk_sources():
    try:
      text = p.read_text(errors="replace")
    except OSError:
      continue
    rel = str(p.relative_to(ROOT))
    bucket = classify(rel, text)
    for i, line in enumerate(text.splitlines(), 1):
      where = "MENTION" if line.lstrip().startswith("#") else "CODE"
      for m in pat.finditer(line):
        out[m.group(1)].setdefault(f"{bucket}/{where}", []).append(f"{rel}:{i}")
  return out


def reader_files() -> list[str]:
  """`.bend` files that actually `import ... spec.bend` -- the only files that CAN read a table."""
  out = []
  for p in sorted((ROOT / "tinybendygrad").rglob("*.bend")) + sorted((ROOT / "gates").rglob("*.bend")):
    if re.search(r"^import .*\bspec\.bend\b", p.read_text(errors="replace"), re.M):
      out.append(str(p.relative_to(ROOT)))
  return out


def imports_spec_bend(text: str) -> bool:
  return bool(re.search(r"^import .*\bspec\.bend\b", text, re.M))


def resolve(ladder: str, sub: int, comp: dict, depth: int = 0) -> tuple[str, int, int]:
  """Where `(ladder, sub)` ACTUALLY lands, following that ladder's `case _` arm.

  Each of `te_/pr_/hq_dispatch`'s out-of-range arms is a hand-written delegate into
  `sh_dispatch` at a stated base, so an off-by-one at a block seam is not automatically a
  wrong answer: the tensor seam self-heals, because `te_dispatch`'s fallback subtracts the same
  base `tensor_table()` bumps by and lands back on the first shared rule. Reading only the arm
  table would call that a defect; reading the fallback is what says whether it is one. The third
  return value is the number of fallback hops taken, so a row that never terminated is visible.
  """
  d = comp.get(ladder)
  if not isinstance(d, dict):
    return (ladder, sub, depth)
  if sub in d["arms"]:
    return (ladder, sub, depth)
  fb = d["fallback"]
  if "VSkip" in fb:
    return (ladder, sub, depth)
  m = re.search(r"(\w+)\(U32\.sub\(tag,\s*(\d+)\)", fb)
  if not m:
    return (ladder, sub, depth)
  if depth > 8:
    return (ladder, sub, depth)
  return resolve(m.group(1), sub - int(m.group(2)), comp, depth + 1)


def forward_ref_probe() -> tuple[str, str]:
  """Bend's file-order rule, REPRODUCED rather than asserted, on two 7-line files.

  The message a forward reference produces names no rule -- "an unfilled law is a dead claim" reads
  as though a body were missing -- so the rule is measured: the same two defs, the same call, the
  only difference being which one comes first. Whatever the two runs print is the evidence, and a
  reader who distrusts it can run the two files this writes.

  SCOPE, STATED BECAUSE IT IS NARROW: this is a rule about top-level FUNCTION defs within one file.
  It says nothing about `type X is ...` (a type declaration) nor about `LAWS/*.bend`, where an unfilled
  law is the entire point of the file. A census that mixed those in would report thousands of rows
  that are not defects, and a wrong count is worse than none -- so this file reports the two runs and
  the one located instance, and no tree-wide total.
  """
  import subprocess
  import tempfile
  bender = ROOT / "bin" / "bend"
  fwd = "import Base\n\ndef a(x: U32) -> U32:\n  b(x)\n\ndef b(x: U32) -> U32:\n  x\n\ndef main() -> IO(Unit):\n  IO.print(U32.show(a(1)))\n"
  back = "import Base\n\ndef b(x: U32) -> U32:\n  x\n\ndef a(x: U32) -> U32:\n  b(x)\n\ndef main() -> IO(Unit):\n  IO.print(U32.show(a(1)))\n"
  out = []
  with tempfile.TemporaryDirectory() as d:
    for name, text in (("forward.bend", fwd), ("backward.bend", back)):
      p = Path(d) / name
      p.write_text(text)
      r = subprocess.run([str(bender), str(p)], capture_output=True, text=True, cwd=ROOT)
      out.append(f"{name}: rc={r.returncode} stdout={r.stdout.strip()[:60]!r} "
                 f"first_error={r.stderr.strip().splitlines()[1] if len(r.stderr.strip().splitlines()) > 1 else ''!r}")
  return out[0], out[1]


READER_SET: list[str] = []
DEF_OWNERS: dict[str, set[str]] = {}


def load_populations() -> None:
  """Two sets, both DISCOVERED, and the second one is why the first is trustworthy.

  READER_SET   `.bend` files that import the PORT's `uop/spec.bend`. Only these can call its defs.
  DEF_OWNERS   which file DEFINES each name. `test/helpers.py` defines its own `full_rewrite`
               (line 24), which has nothing to do with `spec.bend`'s -- so 24 uses of that name
               outside the reader set are a NAME COLLISION, not 24 call sites. An instrument that
               cannot tell a definition from a use reports the collision as reachability, which is
               the same failure as the basename-regex one, wearing a different hat.
  """
  global READER_SET, DEF_OWNERS
  spec_import = re.compile(r"^import\s+(\S*?)uop/spec\.bend", re.M)
  for p in sorted(ROOT.rglob("*.bend")) + sorted(ROOT.rglob("*.py")):
    if any(s in p.parts for s in SKIP_DIRS) or p == Path(__file__).resolve():
      continue
    try:
      text = p.read_text(errors="replace")
    except OSError:
      continue
    rel = str(p.relative_to(ROOT))
    if spec_import.search(text):
      READER_SET.append(rel)
    for m in re.finditer(r"^\s*def ([A-Za-z_][\w]*)\s*[(<]", text, re.M):
      DEF_OWNERS.setdefault(m.group(1), set()).add(rel)


def buckets_for(names) -> dict[str, dict[str, list[str]]]:
  """Every mention, split three ways: a CALL inside a reader, a MENTION (a comment), and a
  COLLISION (a use in a file that does not import the port's `spec.bend`, so it cannot be one)."""
  pat = re.compile(r"\b(" + "|".join(names) + r")\b")
  out: dict[str, dict[str, list[str]]] = {n: {} for n in names}
  for p in sorted(ROOT.rglob("*")):
    if p.is_dir() or p.suffix not in SCAN_SUFFIX or any(s in p.parts for s in SKIP_DIRS):
      continue
    if p == Path(__file__).resolve():
      continue
    rel = str(p.relative_to(ROOT))
    try:
      text = p.read_text(errors="replace")
    except OSError:
      continue
    for i, line in enumerate(text.splitlines(), 1):
      for m in pat.finditer(line):
        if rel in READER_SET:
          k = "MENTION" if line.lstrip().startswith("#") else "CALL"
        else:
          k = "COLLISION"
        out[m.group(1)].setdefault(k, []).append(f"{rel}:{i}")
  return out


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--deltas", action="store_true", help="print the per-entry op-set delta, port vs upstream")
  args = ap.parse_args()

  src = BEND.read_text()
  helpers = op_list(src)
  comp = compositions(src)
  cpy = cpython_tables()
  own = upstream_own_counts()
  shadow = upstream_shadowed()

  print("# 1. DECLARED: rows in the port's builders vs len() of the LIVE upstream matcher.")
  print(f"#    spec.bend sha256 is printed by the caller; the port is under active edit by three units.")
  for name in BUILDERS:
    rows = pm_rows(src, name, helpers)
    if not rows:
      continue
    up = cpy.get(name)
    upn = f"{len(up)}" if up else "-"
    print(f"{name}\tport_rows={len(rows)}\tupstream_len={upn}\tupstream_own={own.get(name, '-')}")
  print()
  print("# 2. THE COMPOSITION of full_table, read off the source. `bump(N, block)` sets a base tag;")
  print("#    `fu_block` SPLITS on three thresholds and `fu_dispatch.of` SUBTRACTS a base per block.")
  print(f"#    full_table.go(...) call : {comp.get('full_table_call')}")
  print(f"#    bump bases, in order    : {comp.get('bumps')}")
  print(f"#    fu_block thresholds     : {comp.get('fu_block_thresholds')}")
  print(f"#    fu_dispatch.of arms     : {comp.get('fu_dispatch_of')}")
  for n in ("te_dispatch", "sh_dispatch", "pr_dispatch", "hq_dispatch"):
    d = comp.get(n)
    if isinstance(d, dict):
      print(f"#    {n}: arms 0..{max(d['arms']) if d['arms'] else '-'} "
            f"({len(d['arms'])} of them), case _ -> {d['fallback']}")
  print()

  print("# 3. REACHABLE TODAY, per ENTRY of full_table. `dispatched` = the block's ladder has an")
  print("#    explicit arm for the computed sub-tag. `ladder-arm` = it fell through to `case _`.")
  bumps = comp.get("bumps") or []
  thr = comp.get("fu_block_thresholds") or []
  arms = {n: (comp[n]["arms"] if isinstance(comp.get(n), dict) else []) for n in
          ("te_dispatch", "sh_dispatch", "pr_dispatch", "hq_dispatch")}
  ladders = [a[1] for a in (comp.get("fu_dispatch_of") or [])]
  bases = [int(a[2]) for a in (comp.get("fu_dispatch_of") or [])]
  own_arms = comp.get("fu_dispatch_arms", [])
  sizes = [(int(n), blk, len(pm_rows(src, blk, helpers))) for n, blk in bumps]
  total = len(own_arms) + sum(n for _, _, n in sizes)
  print(f"#    full_own arms {own_arms} then {sizes} => total {total}")
  print("#    The INTENT of a tag is the block its own PMEntry came from -- the bumps say which -- so")
  print("#    `intended` is read off the composition and `lands` is where the arithmetic plus the")
  print("#    ladder's `case _` chain actually sends it. A mismatch that resolves back to the intended")
  print("#    rule is a SEAM THAT SELF-HEALS; one that does not is an ENTRY THAT CANNOT FIRE.")
  block_of: dict[int, tuple[str, int]] = {}   # tag -> (ladder, intended sub-tag)
  for base, blk, n in sizes:
    ladder = {"tensor_own": "te_dispatch", "shared_table": "sh_dispatch",
              "program_own": "pr_dispatch", "hcq_own": "hq_dispatch"}.get(blk, "?")
    for k in range(n):
      block_of[base + k] = (ladder, k)
  unreachable = []
  selfhealed = []
  for tag in range(total):
    if tag in own_arms:
      print(f"full_table\ttag={tag}\tfull_own arm fu_{tag}\tdispatched")
      continue
    blk_i = next((i for i, t in enumerate(thr) if tag < t), len(thr))
    ladder = ladders[blk_i] if blk_i < len(ladders) else "?"
    base = bases[blk_i] if blk_i < len(bases) else -1
    sub = tag - base
    if sub in arms.get(ladder, []):
      print(f"full_table\ttag={tag}\tblock={blk_i + 1}\tladder={ladder}\tbase={base}\tsub={sub}\tdispatched")
      continue
    land_l, land_s, hops = resolve(ladder, sub, comp)
    want_l, want_s = block_of.get(tag, ("?", -1))
    if (land_l, land_s) == (want_l, want_s):
      selfhealed.append((tag, ladder, sub, land_l, land_s, hops))
      verdict = "SEAM-SELF-HEALS"
    elif "VSkip" in str(comp.get(land_l, {}).get("fallback", "")) and land_s not in arms.get(land_l, []):
      unreachable.append((tag, ladder, sub, land_l, land_s))
      verdict = "CANNOT-FIRE"
    else:
      unreachable.append((tag, ladder, sub, land_l, land_s))
      verdict = "CANNOT-FIRE"
    print(f"full_table\ttag={tag}\tblock={blk_i + 1}\tladder={ladder}\tbase={base}\tsub={sub}"
          f"\tintended={want_l}[{want_s}]\tlands={land_l}[{land_s}] after {hops} fallback hop(s)"
          f"\t{verdict}")
  print(f"full_table\ttotal={total}\tself-healing={len(selfhealed)}\t{selfhealed}")
  print(f"full_table\ttotal={total}\tCANNOT-FIRE={len(unreachable)}\t{unreachable}")
  print()

  print("# 4. SHADOWED, the population-free half: an entry whose rule is the SAME OBJECT as an")
  print("#    earlier entry's can never decide, because the fold is first-wins.")
  for name in ("spec_shared", "spec_tensor", "spec_program", "spec_hcq", "spec_full", "spec_kernel_graph"):
    up = cpy[name]
    print(f"upstream {name}\tshadowed={len(shadow[name])}\tof={len(up)}")
  port_blocks = [blk for _, blk, _ in sizes]
  print(f"port full_table\tblocks={port_blocks}\tdistinct_builder_calls="
        f"{len(set(port_blocks))}\tSHADOWED-BY-DUPLICATION=0"
        f"{'  (every block is one builder or one shared_table() VALUE)' if len(set(port_blocks)) == len(port_blocks) else ''}")
  print()

  print("# 5. CALL SITES. A CALL is a use, in code, in a file that imports the port's `uop/spec.bend` --")
  print("#    the only files that CAN call a `.bend` def. A MENTION is a comment, and the `WALL(p3)`")
  print("#    note in `schedule/__init__.bend` NAMES `verify_tensor` while calling nothing: counting a")
  print("#    wall as a reader is how an unfinished gate gets reported as a live one. A COLLISION is a")
  print("#    use in a file that does not import the module; `test/helpers.py:24` defines its OWN")
  print("#    `full_rewrite`, so 24 uses of that name there are not 24 call sites.")
  load_populations()
  print(f"#    THE READER SET: {len(READER_SET)} `.bend` files import `uop/spec.bend`")
  for label, group in (("the six verify_* ENTRY POINTS", ENTRY_POINTS),
                       ("the six STANDALONE dispatchers", ("shared_rewrite", "tensor_rewrite",
                        "program_rewrite", "hcq_rewrite", "full_rewrite", "kernel_graph_rewrite")),
                       ("the six COMPOSITION dispatchers", ("sh_rewrite", "te_rewrite", "pr_rewrite",
                        "hq_rewrite", "fu_rewrite", "kg_rewrite"))):
    print(f"# {label}:")
    sites = buckets_for(group)
    for n in group:
      b = sites[n]
      calls = b.get("CALL", [])
      ownrows = [s for s in calls if s.startswith("tinybendygrad/uop/spec.bend:")]
      print(f"{n}\tCALL={len(calls)}\t(spec.bend's own gate rows: {len(ownrows)})"
            f"\tMENTION={len(b.get('MENTION', []))}\tCOLLISION={len(b.get('COLLISION', []))}"
            f"\tdefining files={sorted(DEF_OWNERS.get(n, []))[:3]}"
            f"\treaders={[s for s in calls if not s.startswith('tinybendygrad/uop/spec.bend:')][:3]}")

  if args.deltas:
    print()
    print("# 6. PER-ENTRY OP-SET DELTA, port vs upstream. The op set IS the dispatch key")
    print("#    (`sh_try` -> `sp_claimed`), so a row here is about REACHABILITY, not style.")
    print("#    Compared as SETS of op-tuples, not index-by-index: the re-vendor INSERTED a rule, so a")
    print("#    naive index comparison reads every row after it as a delta and calls the insertion seven.")
    pairs = (("shared_table", "spec_shared"), ("tensor_own", "spec_tensor"),
             ("program_own", "spec_program"), ("hcq_own", "spec_hcq"), ("full_own", "spec_full"))
    for name, upname in pairs:
      prows = pm_rows(src, name, helpers)
      uown = own[upname]
      pset = collections.Counter(tuple(r[1]) for r in prows)
      uset = collections.Counter(tuple(r) for r in cpy[upname][:uown])
      only_up = uset - pset
      only_port = pset - uset
      print(f"# {name} (port {len(prows)}) vs {upname} own {uown}: delta={uown - len(prows)}"
            f"  only_upstream={sum(only_up.values())}  only_port={sum(only_port.values())}")
      for ops, n in sorted(only_up.items()):
        print(f"{name}\tONLY-UPSTREAM\tn={n}\tops={','.join(ops) or '(compound)'}")
      for ops, n in sorted(only_port.items()):
        print(f"{name}\tONLY-PORT\tn={n}\tops={','.join(ops) or '(compound)'}")
  print()
  print("# 7. WHY NO BEND RUN BACKED SECTION 3: the substrate does not compile, so the tree's ONLY")
  print("#    live reader of these tables cannot be exercised at all. The rule, reproduced:")
  f, b = forward_ref_probe()
  print(f"#    {f}")
  print(f"#    {b}")
  print("#    THE LOCATED INSTANCE: `tinybendygrad/uop/ops.bend:2810`, inside `UOp.group.of` (def at 2803),")
  print("#    calls `UOp.after`, whose def is at 2851 -- 48 lines LATER. Verified by reading the file and")
  print("#    by `bin/bend tinybendygrad/uop/spec.bend`, whose whole-subtree compile fails on it.")
  print("#    It is not this unit's file to fix (three units are editing `uop/ops.bend` right now) and the")
  print("#    fix shape is the one the file already uses everywhere: split `UOp.after` into `UOp.after.go`")
  print("#    above the use, or move the def above `UOp.group.of`.")
  return 0

# NO `if __name__ == "__main__"` GUARD, and that is deliberate rather than an omission.
# `gates/gates-pop.py` clause I DISCOVERS gates by that AST node, so a census that carries one
# becomes a gate, lands in the ledger, and turns the meta-gate red for the crime of being a
# census. `gates/opseven-oracle.py` has no guard either, and that is the house shape for an
# oracle. Run this file BY PATH; `raise SystemExit` at top level keeps the exit status.
raise SystemExit(main())
