#!/usr/bin/env python3
"""arenasrc_probe-check.py -- DOES EVERY SIZE-BEARING NODE POINT AT ITS OWN SIZE?

    .venv/bin/python gates/arenasrc_probe-check.py
    .venv/bin/python gates/arenasrc_probe-check.py --plant PATH:LINE

TWO LANES, FIVE VERDICTS, AND A PLANT THAT PROVES THE LANE CAN FAIL.

LANE 1 (`gates/arenasrc_rows.bend`, under `checks/bounded.py`) reads what four builders
actually intern: `UOp.new.param`, `mxw_buf` (`mixin/movement.bend`, the port's
BOTTOM-OF-EVERY-GRAPH builder), `fx_buf` (`function.bend`), and `idiom` -- the
throwaway-arena shape rebuilt ON PURPOSE, which is the CONTROL. If `idiom` ever stops
reading BAD this lane can no longer see the defect, so the control is asserted as BAD and
its being BAD is part of what makes the other rows mean anything.

LANE 2 (`gates/arenasrc_census.py`) walks `tinybendygrad/**/*.bend` and counts the
`param_src` call sites. `0` is the invariant: the helper interned a size node into a
throwaway arena and handed back only the index, so every site that called it built a node
that is its own parent.

**WHY A GREEN BUILD IS NOT THE ACCEPTANCE TEST.** `Arena.src(ar, i, 0)` answers
`Maybe.default(..., 0)`, so an index that names nothing reads the arena bottom with no
error at all. `bend --check-only` is green over this defect; these rows are not.

**THE PLANT, AND WHY IT BINDS NOTHING AT IMPORT.** `--plant PATH:LINE` is read inside
`main()` and resolved there, so the instrument's SOURCE and its SUBJECT come from two
places only when the plant asks for it. `gates/gapcensus-gate.py` first reported FAILED
because `UP`/`PORT` were bound at import while the plant moved them -- the same shape as
`AGENTS.md`'s `repro-paths.py`, an instrument's source and its subject from two places.
The plant rewrites the named line back to the throwaway-arena spelling, re-runs lane 1,
requires the row to go BAD, restores the byte-exact original, and requires it to go GOOD
again. It aborts if the restore does not reproduce the original bytes.
"""
from __future__ import annotations

import argparse
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import PASS, FAIL, REFUSED, SKIP, DEAD, VERDICT  # noqa: E402  -- one vocabulary

DRIVER = HERE / "arenasrc_rows.bend"
BOUNDED = ROOT / "checks" / "bounded.py"
PY = ROOT / ".venv" / "bin" / "python"
BEND = ROOT / "bin" / "bend"

#: the GOOD rows. A builder that reads `BUFFER` here is its own parent; a builder that
#: reads `N` for a size that was supplied has no size node at all.
WANT = {
    "threaded_src0_op": "CONST", "threaded_size": "12", "threaded_nsrc": "1", "threaded_next": "3",
    "mxw_buf_src0_op": "CONST", "mxw_buf_size": "12", "mxw_buf_nsrc": "1", "mxw_buf_next": "3",
    "mxw_buf0_src0_op": "CONST", "mxw_buf0_size": "0", "mxw_buf0_nsrc": "1", "mxw_buf0_next": "3",
    "fx_buf_src0_op": "CONST", "fx_buf_size": "12", "fx_buf_nsrc": "1", "fx_buf_next": "3",
    "reintern_4_4": "True", "distinct_4_6": "True",
    "distinct_0_1": "True", "distinct_0_none": "True",
}
#: the CONTROL. `idiom` rebuilds the defect on purpose, so it MUST read bad: a control that
#: reads good means the reader is broken and every row above it is worthless.
CONTROL_BAD = {"idiom_src0_op": "BUFFER", "idiom_size": "N", "idiom_nsrc": "1", "idiom_next": "2"}
WANT_CALL_SITES = 0


def run_lane1() -> tuple[dict[str, str], str]:
  """({row: value}, TOKEN). The TOKEN is the verdict and `$?` is not -- `bounded.py`
  records that in its own header."""
  env = dict(os.environ, SPEC="1", DEV="CPU")
  p = subprocess.run([str(PY), str(BOUNDED), "--seconds", "900", "--mb", "2048", "--",
                      str(BEND), str(DRIVER)], capture_output=True, text=True, env=env, cwd=ROOT)
  token = next((ln.split()[1] for ln in p.stderr.splitlines() if ln.startswith("[bounded] ")), "NONE")
  rows: dict[str, str] = {}
  for ln in p.stdout.splitlines():
    for part in ln.split():
      if "=" in part:
        k, v = part.split("=", 1)
        rows[k] = v
  return rows, token


def census_call_sites() -> int:
  sys.path.insert(0, str(HERE))
  import arenasrc_census as C
  _rows, totals = C.census()
  return sum(v for k, v in totals["classes"].items() if k.startswith("param_src/"))


def check(rows: dict[str, str], sites: int) -> list[str]:
  bad = [f"{k}={rows.get(k, '<ABSENT>')} want {v}" for k, v in WANT.items() if rows.get(k) != v]
  bad += [f"CONTROL {k}={rows.get(k, '<ABSENT>')} want {v} (BAD)"
          for k, v in CONTROL_BAD.items() if rows.get(k) != v]
  if sites != WANT_CALL_SITES:
    bad.append(f"param_src call sites = {sites}, want {WANT_CALL_SITES}")
  return bad


def plant(path: pathlib.Path, lineno: int) -> str | None:
  """rewrite ONE migrated line back to the throwaway-arena spelling and restore it.
  Returns None on success or a refusal string."""
  lines = path.read_text().split("\n")
  i = lineno - 1
  if not 0 <= i < len(lines):
    return f"{path}:{lineno} is not a line of the file"
  before = lines[i]
  if ".param(" not in before:
    return f"{path}:{lineno} does not hold a migrated `*.param(` call: {before.strip()[:70]!r}"
  sys.path.insert(0, str(HERE))
  import arenasrc_census as C
  code, why = C.lex(before)
  if why:
    return f"{path}:{lineno} will not lex: {why}"
  m = C.SITE.search(code)
  lines[i] = before
  if m:
    return f"{path}:{lineno} already holds a `param_src` site -- nothing to plant"
  call = C.CONSTRUCTOR.search(code)
  if not call:
    return f"{path}:{lineno} holds no `UOp.new` call to plant into"
  try:
    end, args = C.span_of(code, call.end() - 1)
  except ValueError:
    return f"{path}:{lineno} has an unbalanced `UOp.new` call"
  if len(args) != 5 or "AParam" not in args[3]:
    return f"{path}:{lineno} builds no AParam node, so a planted size would be invisible"
  # `CONSTRUCTOR` matches through the trailing `(`. The callee is therefore the match MINUS
  # that bracket, and it is used THREE ways, each of which the first version got wrong:
  #   full  `O.UOp.new.param` -- keep the module prefix, `mixin/movement.bend` has no bare
  #         `UOp` in scope and dropping `O.` makes bend say "expected : a defined name".
  #   base  `O.UOp.new`       -- strip ONLY a trailing `.param`, so the planted call keeps
  #         the plain constructor the site used.
  #   help  `O.param_src` -- the sibling of `O.UOp`, see the rule below; `base +
  #         ".param_src"` names a function that does not exist.
  full = call.group(0)[:-1]
  base = full[:-len(".param")] if full.endswith(".param") else full
  # The helper is `param_src`, a TOP-LEVEL def SIBLING of the `UOp` namespace in the same
  # ops module -- not a member of it, so both `O.UOp.new.param_src` ("expected : a defined
  # name") and a bare `param_src` (the alias is not in scope) are wrong. Its name is
  # therefore the callee with the `UOp.new.param` path replaced by `param_src`, which is
  # the sibling relation stated structurally rather than guessed from a name: this tree's
  # aliases are ALL capitals (`O`, `H`, `S`, `MX`), so a case rule cannot find them.
  TAIL = ".UOp.new.param"
  if not full.endswith(TAIL):
    return (f"{path}:{lineno} calls {full!r}, whose module alias this plant cannot derive "
            f"(`param_src` is a sibling of `UOp`, not a member), so planting here would "
            f"produce a name that does not exist rather than a defect")
  helper = full[:-len(TAIL)] + ".param_src"
  size = C.norm(args[2])
  if not size.startswith(("Some{", "None{}")):
    return (f"{path}:{lineno} has no size Maybe to plant -- its third argument is "
            f"{size[:40]!r}, so the planted node would not be a size-bearing one")
  # The splice ends at `end` -- the offset just past the ORIGINAL call's closer, from the
  # same `span_of` that read its arguments. Splicing to `call.end() - 1` instead kept the
  # original argument list and produced `... O.TNone{}(ar, O.OpsBUFFER{}, Some{size}, ...)`:
  # the lane emitted nothing, and a plant that only asks "did the row change?" reads an
  # absent row as success.
  planted = (before[:call.start()] + f"{base}({C.norm(args[0])}, "
             f"{C.norm(args[1])}, {helper}({C.norm(args[0])}, {size}), "
             f"{C.norm(args[3])}, {C.norm(args[4])})" + before[end:])
  path.write_text("\n".join(lines[:i] + [planted] + lines[i + 1:]))
  return None if _plant_state(path) else "the planted line does not hold a `param_src` call"


def _plant_state(path: pathlib.Path) -> bool:
  sys.path.insert(0, str(HERE))
  import arenasrc_census as C
  return any(C.SITE.search(C.lex(l)[0]) for l in path.read_text().split("\n"))


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--plant", metavar="PATH:LINE", default=None)
  a = ap.parse_args()

  rows, token = run_lane1()
  if token != "WITHIN-LIMITS":
    print(f"== {VERDICT[DEAD] if not rows else VERDICT[FAIL]}: the lane token is {token}",
          file=sys.stderr)
    return DEAD if not rows else FAIL
  sites = census_call_sites()
  bad = check(rows, sites)
  for b in bad:
    print(f"  {b}", file=sys.stderr)
  if bad and not a.plant:
    print(f"== {VERDICT[FAIL]}: arenasrc_probe-check", file=sys.stderr)
    return FAIL

  if a.plant:
    rel, _, ln = a.plant.rpartition(":")
    target = (ROOT / rel).resolve()
    if not target.is_relative_to(ROOT) or not target.exists():
      print(f"== {VERDICT[REFUSED]}: --plant target {a.plant!r} is not a file in this repo",
            file=sys.stderr)
      return REFUSED
    original = target.read_bytes()
    why = plant(target, int(ln))
    if why:
      target.write_bytes(original)
      print(f"== {VERDICT[REFUSED]}: {why}", file=sys.stderr)
      return REFUSED
    prows, ptoken = run_lane1()
    target.write_bytes(original)
    if not target.exists() or target.read_bytes() != original:
      print(f"== {VERDICT[FAIL]}: the restore did not reproduce {target} byte for byte",
            file=sys.stderr)
      return FAIL
    rrows, rtoken = run_lane1()
    # "MOVED" MEANS: a row this gate cares about CHANGED, and NO row went ABSENT. Tying the
    # criterion to `mxw_buf_*` was too narrow and it FAILED a real defect -- planting
    # `uop/fold.bend:4308` moves that node's `src[0]` without touching `mxw_buf`, and the
    # check called the unchanged row a non-movement. Tying it to "the row differs" was too
    # weak: a malformed plant makes the lane emit NOTHING, every row goes absent, and that
    # reads as maximal change. Both halves are required.
    lost = sorted(k for k in WANT if k not in prows)
    moved = sorted(k for k in WANT if k in prows and prows[k] != WANT[k])
    back = all(rrows.get(k) == v for k, v in WANT.items())
    print(f"PLANT   {rel}:{ln} -> " + " ".join(f"{k}={prows.get(k, '<ABSENT>')}" for k in moved)
          + f" (token {ptoken})")
    print(f"RESTORE {rel}:{ln} -> {sum(1 for k in WANT if rrows.get(k) == WANT[k])}/{len(WANT)} "
          f"rows back (token {rtoken})")
    if lost:
      print(f"== {VERDICT[FAIL]}: the planted lane emitted no value for {len(lost)} row(s) "
            f"({', '.join(lost[:4])}) -- a lane that stopped running is not a detected defect",
            file=sys.stderr)
      return FAIL
    if not moved:
      print(f"== {VERDICT[FAIL]}: the plant changed no row this gate measures, so it is "
            "planted somewhere this lane cannot see", file=sys.stderr)
      return FAIL
    if not back:
      print(f"== {VERDICT[FAIL]}: the rows did not all return after the restore", file=sys.stderr)
      return FAIL
    print(f"== {VERDICT[PASS]}: the plant moved the row and the restore put it back")
    return PASS

  print(f"== {VERDICT[PASS]}: arenasrc_probe-check -- {len(WANT)} rows + "
        f"{len(CONTROL_BAD)} control rows + {WANT_CALL_SITES} `param_src` call sites")
  return PASS


if __name__ == "__main__":
  sys.exit(main())