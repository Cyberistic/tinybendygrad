#!/usr/bin/env python3
"""The gate for the SPEC TABLES: the two lanes must AGREE, and the tag spaces must not drift.

    .venv/bin/python gates/specreach-gate.py            # the gate
    .venv/bin/python gates/specreach-gate.py --plant    # the plant and its control

WHY A GATE AND NOT A MAP. `gates/specreach-compare.py` is a MAP: it prints both lanes side by
side and counts the cells that differ, and it says so in its own header -- "Nothing here decides
whether a disagreement is acceptable". A MAP THAT CANNOT GO RED IS A LABEL, and `differ.py`'s
own plant 3 says it: "if it does not go red, the row is a label". So the map stays a map and
THIS file grades it. The subject is the same subject the map prints: the port's `fu_rewrite`
against CPython's `spec_full`, on the same three fixtures.

THE TWO THINGS THIS FILE CHECKS, and they are two because they failed two different ways.

  1. THE CELLS. `gates/specreach-map.rows` read `sf` as 9 against 0, 1 and 1 on all three
     fixtures, and the map could only REPORT that. The cells are graded here: any `NO` is a
     FAIL. The count is READ from the map's own `# DIFFER over N cells: M` line, so the
     denominator is derived and not written down here.

  2. THE TAG SPACES. `tinybendygrad/uop/spec.bend` spells every block base THREE times -- as the
     `bump(N, ...)` that builds `full_table`, as the `U32.sub(tag, N)` in `fu_dispatch.of`, and
     as a threshold in `fu_block.go` -- and NOTHING TIED THE THREE TOGETHER. On 2026-10-17 the
     twenty-third tensor rule was deleted and the first two moved to 26 / 59 / 68 while the
     third stayed at 27 / 60 / 69, so a block's FIRST rule was dispatched into the PREVIOUS
     block's ladder, where that ladder's `case _` arm handed it to a rule that does not apply
     to it: `spec_hcq`'s GETADDR rule (`spec.py:230`) went to `spec_shared`'s SINK rule
     (`spec.py:50`) and `spec_program`'s first rule (`spec.py:206`) went to no rule at all. It
     compiled, it ran, and it raised nothing. `gates/specshadow-map.py` is the MAP that
     computes the same arithmetic and prints `CANNOT-FIRE=3`; this file is its VERDICT.

THE PLANT, AND WHY IT IS A TEXT EDIT. `--plant` copies the WORKING COPY of `spec.bend` beside
itself, edits the COPY, and runs the probe against it. It never reads `git show HEAD:` -- a
plant that reads HEAD plants nothing the moment HEAD carries the defect's fix, and three units
scored green under `--falsify` for exactly that reason. The plant changes ONE RULE and the
`sf` rows MUST MOVE; the control adds a COMMENT and the `sf` rows MUST NOT. The control's
comment-only-ness is PROVED by `_code_only` -- the comment stripper from
`checks/port-compile-gate.py` plus a BLANK-LINE DROP, which is what makes a WHOLE-LINE comment
at column 0 count as comment-only -- and not asserted.

NO `if __name__ == "__main__"` GUARD, ON PURPOSE, and the reason is the OPPOSITE of the maps':
`gates/gates-pop.py` clause I DISCOVERS gates by that AST node, so a file WITH the guard is a
gate and lands in the ledger. This file IS a gate -- it grades and it can go red -- so it
carries the guard, and it is `gates/specreach-gate.py` rather than `gates/specreach-map.py` so
that the name says which of the two it is.

**DO NOT RUN THIS UNDER `checks/bendlock.sh`.** Every bend run here takes the lock ITSELF, one
per invocation, and an outer lock would wait on itself -- MEASURED, on 2026-10-22: the outer
`bendlock.sh` holds the lock for the whole command and the inner one waits for it, forever.
"""
import argparse
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HERE = ROOT / "gates"
PY = ROOT / ".venv" / "bin" / "python"
BOUNDED = ROOT / "checks" / "bounded.py"
BEND = ROOT / "bin" / "bend"
BENDLOCK = ROOT / "checks" / "bendlock.sh"
COMPARE = HERE / "specreach-compare.py"
SPEC = ROOT / "tinybendygrad" / "uop" / "spec.bend"
PROBE = HERE / "specreach.bend"
PLANT_SPEC = ROOT / "tinybendygrad" / "uop" / "spec-plant.bend"
PLANT_PROBE = HERE / "specreach-plant.bend"

sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED  # noqa: E402


def _load_port_compile():
  """`checks/port-compile-gate.py` BY PATH, for its `strip_comments()`.

  The comment stripper is that file's, and it knows that a `#` inside a string is not a
  comment. Re-typing a second stripper here would be a second copy of the question, and the
  two would drift.
  """
  spec = importlib.util.spec_from_file_location("port_compile", ROOT / "checks" / "port-compile-gate.py")
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def _code_only(text: str) -> str:
  """The file with every comment REMOVED and every blank line DROPPED.

  The comment removal is `checks/port-compile-gate.py`'s own `strip_comments()`. The
  BLANK-LINE DROP is `gates/ptx_render_census-gate.py`'s addition, and it is what makes the
  proof cover a WHOLE-LINE comment: a comment on its own line contributes a line that is empty
  once the comment is stripped, and comparing LINE LISTS would call that "not comment-only" --
  which is the most comment-only edit there is.
  """
  pc = _load_port_compile()
  return "\n".join(l for l in pc.strip_comments(text).split("\n") if l.strip())


# --------------------------------------------------------------------------- the tag spaces
def _bodies(src: str) -> dict[str, str]:
  """Every `def name(...)` in a `.bend` file, mapped to its own body."""
  out: dict[str, str] = {}
  cur: str | None = None
  for line in src.splitlines():
    m = re.match(r"^def ([A-Za-z_][\w.]*)\(", line)
    if m:
      cur = m.group(1)
      out[cur] = ""
    elif cur is not None:
      if line.startswith("def ") or (line and not line[0].isspace() and not line.startswith("#")):
        cur = None
      else:
        out[cur] += line + "\n"
  return out


def _rows(body: str) -> int:
  """How many `O.PMEntry{...}` rows a builder emits."""
  return len(re.findall(r"O\.PMEntry\{", body))


def _arms(body: str) -> dict[int, str]:
  """`case N: rule` of a ladder, as `{N: rule}`."""
  return {int(n): r for n, r in re.findall(r"case (\d+): (\w+)\(", body)}


def tag_spaces() -> list[str]:
  """Every disagreement between the THREE spellings of a block base and the block SIZES.

  The population is DISCOVERED -- the blocks are the ones `full_table` composes -- and the
  sizes are COUNTED from the builders, so a rule that is added or removed moves the numbers
  this reads.
  """
  src = SPEC.read_text()
  b = _bodies(src)
  bad: list[str] = []
  comp = re.findall(r"bump\((\d+),\s*([\w.]+)\(\)\)", b.get("full_table", ""))
  if len(comp) != 4:
    return [f"full_table composes {len(comp)} blocks, not 4 -- the composition moved and this "
            f"file's shape has to move with it"]
  # (builder, ladder, rule-family) for the four blocks, in composition order.
  kinds = (("tensor_own", "te_dispatch", "te"), ("shared_table", "sh_dispatch", "sh"),
           ("program_own", "pr_dispatch", "pr"), ("hcq_own", "hq_dispatch", "hq"))
  sizes = {k: _rows(b.get(k, "")) for k, _, _ in kinds}
  n_full = _rows(b.get("full_own", ""))
  # the bases the composition ACTUALLY uses
  bases = {k: int(n) for (n, k) in comp}
  # the bases the sizes SAY the blocks must have
  want: dict[str, int] = {}
  acc = n_full
  for k, _, _ in kinds:
    want[k] = acc
    acc += sizes[k]
  for k, _, _ in kinds:
    if bases.get(k) != want[k]:
      bad.append(f"full_table bumps {k} to {bases.get(k)} but the sizes make it {want[k]} "
                 f"(full_own={n_full} + the blocks before it) -- a hole in the tag space")
  # `fu_dispatch.of` subtracts a base per block, and `fu_block.go` THRESHOLDS on one.
  subs = {lad: int(n) for _, lad, n in
          re.findall(r"case (\S+): (\w+)\(U32\.sub\(tag,\s*(\d+)\)", b.get("fu_dispatch.of", ""))}
  for k, lad, _ in kinds:
    if subs.get(lad) != want[k]:
      bad.append(f"fu_dispatch.of subtracts {subs.get(lad)} for {lad} but {k}'s base is {want[k]}")
  thr = [int(x) for x in re.findall(r"U32\.is_lt\(tag,\s*(\d+)\)", b.get("fu_block.go", ""))]
  for (k, _, _), t in zip(kinds[1:], thr):
    if t != want[k]:
      bad.append(f"fu_block.go's threshold for {k} is {t} but {k}'s base is {want[k]} -- a block's "
                 f"FIRST rule lands in the PREVIOUS block's ladder")
  if len(thr) != 3:
    bad.append(f"fu_block.go has {len(thr)} thresholds, not 3")
  # every ladder's arms are its block's own rules, `case N: _N`, and no more.
  for k, lad, fam in kinds:
    arms = _arms(b.get(lad + ".go", ""))
    if len(arms) != sizes[k]:
      bad.append(f"{lad}.go has {len(arms)} arms and {k} has {sizes[k]} rules")
    for i in range(sizes[k]):
      if arms.get(i) != f"{fam}_{i}":
        bad.append(f"{lad}.go's arm {i} names {arms.get(i)!r}, not {fam}_{i}")
  # EVERY entry of the composed table lands on its OWN rule.
  for k, lad, fam in kinds:
    base, n = want[k], sizes[k]
    for i in range(n):
      tag = base + i
      blk = next((j for j, t in enumerate(thr) if tag < t), len(thr))
      if kinds[blk][0] != k:
        bad.append(f"tag {tag} ({k}'s rule {fam}_{i}) is dispatched into {kinds[blk][0]}'s ladder")
        continue
      sub = tag - want[k]
      if sub not in _arms(b.get(lad + ".go", "")):
        bad.append(f"tag {tag} ({k}'s rule {fam}_{i}) falls through {lad}'s `case _` arm")
  # the probe's seam tags are the bases, so it probes the seams.
  probe = PROBE.read_text()
  for t in re.findall(r"fu_dispatch\((\d+),", probe):
    if int(t) not in set(want.values()) | {want["hcq_own"] + sizes["hcq_own"] - 1}:
      bad.append(f"gates/specreach.bend probes fu_dispatch({t}) and {t} is not a block base")
  return bad


# --------------------------------------------------------------------------- the lanes
def run_probe(probe: Path) -> tuple[str, str]:
  """Run a probe under the lock and under `checks/bounded.py`, and return (stdout, verdict).

  THE VERDICT IS THE TOKEN AND NOT THE EXIT STATUS: `checks/bounded.py`'s own header records a
  unit that lost 425 rows by believing the status. The lock is `checks/bendlock.sh`, one bend
  at a time, and the lock is TAKEN PER INVOCATION -- a command that runs many bends and holds
  it for the whole command makes every other unit wait.
  """
  p = subprocess.run([str(BENDLOCK), "--", str(PY), str(BOUNDED), "--mb", "2048", "--",
                      str(BEND), str(probe)], capture_output=True, text=True, cwd=ROOT)
  token = next((l for l in p.stderr.splitlines() if l.startswith("[bounded]")), "[bounded] NOT RUN")
  return p.stdout, token


def cells() -> tuple[int, int, str]:
  """(differing, total, map text) from `gates/specreach-compare.py`'s OWN count line."""
  p = subprocess.run([str(PY), str(COMPARE)], capture_output=True, text=True, cwd=ROOT)
  m = re.search(r"# DIFFER over (\d+) cells: (\d+)", p.stdout)
  if not m:
    return (-1, -1, p.stdout + p.stderr[-800:])
  return int(m.group(2)), int(m.group(1)), p.stdout


# --------------------------------------------------------------------------- the plant
PLANT_ANCHOR = "sp_op(fx, self, O.OpsGETADDR{})"
PLANT_EDIT = "sp_op(fx, self, O.OpsPROGRAM{})"


def sf_rows(text: str) -> dict[str, str]:
  """The `sf` row of every fixture in a probe's output."""
  out = {}
  for line in text.splitlines():
    m = re.match(r"^(\w+)_sf=(\d)$", line.strip())
    if m:
      out[m.group(1)] = m.group(2)
  return out


def plant() -> int:
  """THE PLANT AND ITS CONTROL. The plant is a TEXT EDIT of a COPY, never of the tree."""
  original = SPEC.read_text()
  if PLANT_ANCHOR not in original:
    print(f"REFUSED: the plant's anchor {PLANT_ANCHOR!r} is not in {SPEC.relative_to(ROOT)} as it "
          f"stands. THE PLANT IS A TEXT EDIT ON THE WORKING COPY, so an anchor that moved means "
          f"the plant must be re-anchored -- NOT that it should fall back to reading git.")
    return REFUSED
  probe_src = PROBE.read_text()
  imp = "./../tinybendygrad/uop/spec.bend"
  if imp not in probe_src:
    print(f"REFUSED: the plant's probe import {imp!r} is not in {PROBE.relative_to(ROOT)} as it "
          f"stands. Re-anchor the plant; do not fall back to reading git.")
    return REFUSED
  base_sf = sf_rows(run_probe(PROBE)[0])
  if not base_sf:
    print("REFUSED: the unplanted probe printed no `sf` row, so the plant has nothing to move.")
    return REFUSED
  bad = 0
  try:
    # 1. THE PLANT: one rule's op, changed. The `sf` rows MUST MOVE.
    PLANT_SPEC.write_text(original.replace(PLANT_ANCHOR, PLANT_EDIT))
    PLANT_PROBE.write_text(probe_src.replace(imp, "./../tinybendygrad/uop/spec-plant.bend"))
    planted_sf = sf_rows(run_probe(PLANT_PROBE)[0])
    moved = {k: (base_sf.get(k), planted_sf.get(k)) for k in base_sf if base_sf.get(k) != planted_sf.get(k)}
    print(f"PLANT    one rule edited ({PLANT_ANCHOR} -> {PLANT_EDIT})")
    print(f"         sf before={base_sf} after={planted_sf} moved={moved}")
    if not moved:
      print("  THE PLANT DID NOT FIRE: the `sf` rows did not move, so the map cannot go red.")
      bad += 1
    # 2. THE CONTROL: a comment, and NOTHING else. The `sf` rows MUST NOT MOVE.
    comment_src = original.replace("# spec.py:228 (UPat(Ops.GETADDR", "# THE CONTROL: a comment.\n"
                                                   "# spec.py:228 (UPat(Ops.GETADDR")
    PLANT_SPEC.write_text(comment_src)
    comment_sf = sf_rows(run_probe(PLANT_PROBE)[0])
    same_code = _code_only(comment_src) == _code_only(original)
    print(f"CONTROL  a whole-line comment added, comment-only={same_code}")
    print(f"         sf before={base_sf} after={comment_sf}")
    if comment_sf != base_sf:
      print("  THE CONTROL IS NOT A CONTROL: the `sf` rows moved on a comment-only edit.")
      bad += 1
    if not same_code:
      print("  THE CONTROL IS NOT A CONTROL: the edit changed the CODE, so it was not "
            "comment-only -- and a control that edits more than it meant to is not a control.")
      bad += 1
  finally:
    for p in (PLANT_SPEC, PLANT_PROBE):
      if p.exists():
        p.unlink()
  print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
  return FAIL if bad else PASS


def corpus_carriers() -> list[str]:
  """WHICH GRAPHS OF THE CORPUS CARRY THE SHAPES THE MISROUTED RULES DECIDE.

  The population is `graphcmp.GRAPHS` -- the generator's OWN declaration, loaded BY PATH,
  never a hand list, and `checks/differ.py` reads it the same way -- and the graphs are built
  with upstream's own constructors, so the ops are upstream's.

  THIS IS A REPORT AND NOT A CHECK, and the reason is worth stating: the corpus's two lanes
  never run the port's spec tables. Its bend lane imports `LAWS/spec.bend`, which is a
  DIFFERENT file, and `specshadow-map.py` measures the port's `verify_*` entry points at
  CALL=0. So the corpus CANNOT see a spec defect, and adding a graph to it would not change
  that -- the corpus's own `getaddr` graph already carries a GETADDR. What is missing is a
  VERDICT LANE over the corpus's population, and this file prints which graphs would feed
  one.
  """
  spec = importlib.util.spec_from_file_location("graphcmp_corpus",
                                                ROOT / ".agents" / "slop" / "graphcmp.py")
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  mod.load_tinygrad()          # the builders use upstream's `Tensor` and `dtypes`
  out = []
  for name, build in sorted(mod.GRAPHS.items()):
    g = build()
    ops = {u.op.name for u in g.toposort(enter_calls=True)}
    why = []
    if "GETADDR" in ops:
      why.append("GETADDR (upstream's spec.py:230)")
    if "BINARY" in ops:
      why.append("BINARY (upstream's spec.py:95/206)")
    if why:
      out.append(f"{name}: {', '.join(why)}")
  return out


# --------------------------------------------------------------------------- the gate
def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--plant", action="store_true", help="run the plant and its control")
  args = ap.parse_args()
  if args.plant:
    return plant()
  bad: list[str] = []
  differing, total, text = cells()
  if total < 0:
    print("REFUSED: `gates/specreach-compare.py` printed no cell count, so there is no verdict to "
          "grade. That is a FAILURE of the instrument, not an agreement.")
    print(text[-800:])
    return REFUSED
  print(f"THE CELLS: {differing} of {total} differ")
  for line in text.splitlines():
    if line.endswith("\tNO"):
      print(f"  {line}")
  if differing:
    bad.append(f"{differing} of {total} cells differ between the port's `fu_rewrite` and CPython's "
               f"`spec_full`")
  spaces = tag_spaces()
  print(f"THE TAG SPACES: {len(spaces)} problem(s)")
  for line in spaces:
    print(f"  {line}")
  bad.extend(spaces)
  print("THE CORPUS'S OWN GRAPHS THAT CARRY THE SHAPES (a report: the corpus never runs the "
        "spec tables)")
  for line in corpus_carriers():
    print(f"  {line}")
  if bad:
    print(f"\n=== specreach-gate: FAIL: {len(bad)} problem(s) ===")
    return FAIL
  print("\n=== specreach-gate: PASS ===")
  return PASS


if __name__ == "__main__":
  raise SystemExit(main())
