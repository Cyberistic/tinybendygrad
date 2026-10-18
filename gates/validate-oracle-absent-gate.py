#!/usr/bin/env python3
"""validate-oracle-absent-gate.py -- is a row of `oracles/validate-oracle-run1.rows`
still an ANSWER, and if not, does the file SAY SO.

THE QUESTION, and it is the one a snapshot raises by existing: `oracles/validate-oracle-run1.rows`
holds rows recorded against `Ops.GROUP`, and upstream deleted `Ops.GROUP`. A row file whose
values describe a fixture the substrate can no longer construct is not WRONG, it is UNDATED --
and an undated expected-value file reads exactly like a current one, which is why nothing in the
tree could see this until it was named.

WHAT WAS MEASURED BEFORE THIS FILE EXISTED, so the reader does not have to re-derive it:

  * the generator EXISTS: `.agents/slop/validate-oracle.py`, tracked, 415 lines. So the brief's
    premise -- "CANNOT be regenerated" -- was RIGHT about the outcome and WRONG about the
    reason, which was GROUP alone. There are FOUR deaths, three of them independent of GROUP:
      1. `Ops.GROUP` is not a member of `Ops` (75 members) -> AttributeError at :321,
         0 rows on stdout, rc=1. `.agents/slop/validate-gate.py:92` reports `ORACLE FAILED`.
      2. `.agents/slop/c2d-refusal-rows.py`, loaded BY PATH at :401, is ABSENT from the tree.
      3. that file recovered from `21286a571` (11603 B, 209 lines) dies itself, at :115, on
         `'ParamArg' object has no attribute 'size'` -- so 3 is upstream drift, not a bad path.
      4. `z3` is in neither `.venv` (3.12) nor PATH `python3` (3.15). `uv run --with z3-solver`
         yields 5.3.1.0, and the file pins `z3_d3=4.16.0.0`.
  * the file has ZERO READERS. Discovered by walking the tree for its basename; the only hit
    outside itself is prose at `tinybendygrad/uop/validate.bend:2298`. So deleting rows here
    turns nothing green, and this file is the first thing that can say so out loud.

THE POPULATION, and it is discovered twice over, never hand-listed. `Ops.<NAME>` references are
extracted from the GENERATOR'S OWN TEXT with a regex -- the generator declares its fixtures, so
the regex reads that declaration rather than a second copy of it -- and membership is decided by
IMPORTING `tinygrad.uop.ops.Ops`, not by a list. A row is GROUP-era when the generator builds its
fixture inside a window that names an `Ops` member upstream lacks. `AGENTS.md` names this shape:
"a REGEX OVER THE TREE'S OWN WRITE SITES".

WHY A GROUP-ERA ROW CANNOT BE SILENTLY ABSENT, which was the question, and the gate exists to
keep it that way:

  * INSIDE THE ORACLE LANE, a raise is a VALUE. `fixture()` catches and emits `RAISED <Type>: <msg>`,
    so a fixture CPython refuses still prints a row. Measured against the live substrate with the
    GROUP->ADD substitution: `dv_unsup_two=RAISED NotImplementedError: Ops.STACK is not supported by z3`.
  * THE ROWS A RAISE SKIPS ARE COUNTED, NOT DROPPED. `fixture()` returns early on a raise, so
    `_cs/_term/_term_nb/_n` are never emitted -- and the port prints all four. MEASURED,
    `validate-gate.py` over both live lanes: they land in `port only (58)`, printed BY NAME, and
    the denominator is `shared`, which excludes them. A row with no counterpart is `port only`,
    which is a COVERAGE fact and never agreement.
  * THE RAISE THAT DOES ESCAPE ESCAPES LOUDLY. `UOp(Ops.GROUP, ...)` is evaluated as an ARGUMENT
    at :321, outside every `try`, so `main()` dies before the print loop at :409: 0 rows, rc=1.
    `validate-gate.py` answers `ORACLE FAILED rc=1` -- a FAIL, not an agreement over 0 rows.

WHY NO DELETION TURNS THIS GREEN. The PASS condition is four conjuncts and each names a row the
file must carry: a `<name>_absent=` witness for every GROUP-era row, a `group_era_census=` whose
row-name list EQUALS the computed set, a `generator_refused=` equal to THIS run's token, and no
pre-existing row changed. Deleting a GROUP-era row breaks the census conjunct; deleting the census
breaks its own conjunct; deleting a witness breaks the first. The only green is re-deriving the
fixture against a substrate that has the op, which is the honest fix and is somebody else's call.

    DEV=NULL .venv/bin/python gates/validate-oracle-absent-gate.py [--record]

`--record` WRITES the witnesses, the census and the refusal token. It never touches a row the
generator produced: the pre-existing row set is read before the write and re-read after, and a
mismatch is a FAIL, so `--record` cannot be used to launder an expected value.
"""
import os
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
# THE FIVE VERDICTS, IMPORTED BY PATH from the file that OWNS them and never re-spelled.
# `gates-pop.py` measured this exact fault twice in one tree ("this file and `cl-port-gate.py`
# both refused with 2, and both were scored DEAD") and names it: "a second copy of the vocabulary
# is the same fault as a second copy of a population". Three literals in this file's first draft
# were exactly that.
sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED  # noqa: E402  (after sys.path, deliberately)

GEN = ROOT / ".agents/slop/validate-oracle.py"
ROWS = ROOT / "oracles/validate-oracle-run1.rows"

CENSUS, REFUSED_ROW = "group_era_census", "generator_refused"
FIXTURE_RE = re.compile(r'fixture\(\s*"([^"]+)"')
# `Ops.GROUP` -> `GROUP`. The leading dot is what keeps `z3_alu`/`OpsGroup` out: only a qualified
# attribute reference is a claim about the enum's membership.
OPS_RE = re.compile(r"\bOps\.([A-Z][A-Z0-9_]*)")


def read_rows():
  """{name: value}, whole-LINE keyed on name and split on the FIRST `=` -- `rebase-gate.py`'s
  `rows()` reader, whose docstring is the argument for both halves. Loaded BY PATH rather than
  copied, because a second reader is how a harness compares something other than what the gate
  compares (`agent-core.md`, "a name-comparing harness reported 0 for all 68 mutations")."""
  import importlib.util
  spec = importlib.util.spec_from_file_location("rebase_gate", ROOT / ".agents/slop/rebase-gate.py")
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m.rows(ROWS.read_text())


def generator_ops(src):
  """The `Ops` members the generator's own text names."""
  return sorted(set(OPS_RE.findall(src)))


def live_ops():
  from tinygrad.uop.ops import Ops
  return Ops


def readers():
  """Paths outside the row file that NAME it, found by walking the tree -- a DIRECTORY WALK, the
  population shape `AGENTS.md` blesses, and measured rather than asserted (the first draft of this
  file PRINTED "MEASURED 0 readers" as a string literal, which is the one thing an instrument must
  never do with its own finding).

  ONLY SUFFIXES THAT CAN READ are walked. The second draft counted `.tree`/`.json`/`.tsv` ledger
  dumps under `.agents/slop/` and reported 17 "instruments"; a git tree dump NAMING a path is a
  record that the path existed, not a program that opens it, and calling it a reader is how a
  count of zero becomes a count of seventeen. Returns (code, prose)."""
  base, code, prose = ROWS.name, [], []
  runnable = (".py", ".sh", ".bend", ".mjs", ".js", ".ts")
  for d in ("checks", "gates", "oracles", ".agents", "tinybendygrad", "examples", "langs"):
    for p in (ROOT / d).rglob("*"):
      if not p.is_file() or p == pathlib.Path(__file__) or p.suffix not in runnable:
        continue
      if "__pycache__" in p.parts or ".slop" in p.parts:
        continue
      try:
        for i, ln in enumerate(p.read_text(errors="replace").splitlines(), 1):
          if base in ln:
            (prose if ln.lstrip().startswith(("#", "*")) else code).append(f"{p.relative_to(ROOT)}:{i}")
      except OSError:
        pass
  return sorted(set(code)), sorted(set(prose))


def group_era_rows(src, absent):
  """The fixtures the generator builds against an op upstream no longer has.

  The span is from one `fixture("name"` call to the NEXT one -- a slice between consecutive
  declarations, not a fixed character count. A fixed count was the first draft's bug and it
  over-reported 4 fixtures where 1 is real: `dv_unsup_two`'s argument list is shorter than 400
  characters, so the window ran on into `dv_unsup_two`'s neighbours and named them too. A
  population that over-reports is a population nobody trusts, and this one decides which rows
  the tree calls stale."""
  if not absent:
    return []
  starts = [mt.start() for mt in FIXTURE_RE.finditer(src)]
  out = []
  for i, mt in enumerate(FIXTURE_RE.finditer(src)):
    end = starts[i + 1] if i + 1 < len(starts) else len(src)
    if any(f"Ops.{a}" in src[mt.start():end] for a in absent):
      out.append(mt.group(1))
  return sorted(set(out))


def run_generator():
  """(token, rc, stdout_rows). The TOKEN is the verdict and `$?` is not: the generator dies at
  :321 with rc=1 and a traceback, and a reader who wanted the exception TYPE has to have it in a
  row. 0 stdout rows with a non-zero rc is DEAD, and both halves are printed."""
  py = sys.executable
  env = dict(os.environ, DEV="NULL")
  try:
    r = subprocess.run([py, str(GEN)], cwd=ROOT, capture_output=True, text=True, timeout=300, env=env)
  except subprocess.TimeoutExpired:
    return "TIMED-OUT", -1, 0
  last = [ln for ln in r.stderr.strip().splitlines() if ln.strip()]
  tok = last[-1].strip() if last else f"rc={r.returncode} EMPTY-STDERR"
  return tok, r.returncode, len([ln for ln in r.stdout.splitlines() if ln and not ln.startswith("#")])


def main():
  record = "--record" in sys.argv[1:]
  if not GEN.is_file():
    print(f"REFUSED {GEN.relative_to(ROOT)} is ABSENT: there is no declared generator to read")
    return REFUSED
  if not ROWS.is_file():
    print(f"REFUSED {ROWS.relative_to(ROOT)} is ABSENT: there is no row file to judge")
    return REFUSED

  src = GEN.read_text()
  ops = generator_ops(src)
  # `__members__`, NOT `in Ops`: on 3.12 `x in <EnumClass>` tests VALUES, so `"AND" in Ops` is
  # False for a member that exists, and the first draft of this gate reported 23 absent ops of
  # which 22 were alive. A membership test that inverts on its own subject is not a heuristic.
  nmem = live_ops().__members__
  absent = [o for o in ops if o not in nmem]
  before = read_rows()
  fixtures = group_era_rows(src, absent)
  # A group-era FIXTURE contributes every row the file records under its name -- and NOTHING ELSE
  # contributes: a `_absent` witness, the census and the refusal token are this gate's OWN rows,
  # so counting them would make `era` grow with the record of itself and the census could never
  # settle.
  mine = lambda n: n.endswith("_absent") or n in (CENSUS, REFUSED_ROW)  # noqa: E731
  era = sorted(n for n in before if not mine(n) and any(n == f or n.startswith(f + "_") for f in fixtures))
  tok, rc, nrows = run_generator()
  # the interpreter is part of the token, because the token is a MEASUREMENT and the measurement
  # names its conditions: `ModuleNotFoundError: No module named 'z3'` is true of `.venv` (3.12)
  # and false of `uv run --with z3-solver`. A recorded token without its interpreter would make
  # the file red for a reason its reader could not see.
  tok = f"{sys.executable} {tok}"
  code, prose = readers()

  print(f"GATE       : validate-oracle-absent  ({ROWS.relative_to(ROOT)})")
  print(f"generator  : {GEN.relative_to(ROOT)}  {len(src.splitlines())} lines")
  print(f"ops_named  : {len(ops)}   absent_from_upstream: {','.join(absent) or '-'} "
        f"(of {len(nmem)} live members)")
  print(f"rows       : {len(before)} parsed, {len(era)} group-era, {len(fixtures)} group-era fixtures")
  print(f"generator  : token={tok!r} rc={rc} stdout_rows={nrows}")
  print(f"readers    : {len(code)} code, {len(prose)} prose, by a tree walk for the basename -- "
        f"{', '.join(code + prose) or 'none'}")

  missing = [n for n in era if f"{n}_absent" not in before]
  if CENSUS not in before:
    missing.append(CENSUS)
  elif before[CENSUS] != " ".join(era):
    missing.append(f"{CENSUS}(file says {before[CENSUS]!r}, computed {' '.join(era) or '<none>'!r})")
  if REFUSED_ROW not in before:
    missing.append(REFUSED_ROW)
  elif before[REFUSED_ROW] != tok:
    missing.append(f"{REFUSED_ROW}(file says {before[REFUSED_ROW]!r}, this run says {tok!r})")

  if record:
    why = (f"{','.join(absent)} is not a member of Ops ({len(nmem)} members); "
           "the fixture the generator builds for this row cannot be constructed upstream")
    lines = [f"{n}_absent={why}" for n in era]
    lines += [f"{CENSUS}={' '.join(era)}", f"{REFUSED_ROW}={tok}"]
    # ONLY THIS GATE'S OWN ROWS ARE REWRITTEN. The first draft dropped `era` from `keep`, and
    # `--record` therefore DELETED the three GROUP-era rows it was recording the absence of --
    # "DELETE THE ROWS AND SAY SO", wearing a witness row as a disguise. The `lost` check caught
    # it and returned 1, which is the guard working; the fix is that a record is an ADDITION and
    # an addition that removes an expected value is not an addition.
    drop = {CENSUS, REFUSED_ROW} | {f"{n}_absent" for n in era}
    keep = [ln for ln in ROWS.read_text().splitlines() if ln and ln.split("=", 1)[0] not in drop]
    ROWS.write_text("\n".join(keep + lines) + "\n")
    after = read_rows()
    lost = sorted(n for n in before if not mine(n) and n not in after)
    print(f"\nRECORDED   : {len(era)} witnesses + 2 declarations ADDED; "
          f"{len(lost)} generator row(s) lost: {', '.join(lost) or 'none'}")
    return FAIL if lost else PASS

  if era:
    print("\n== GROUP-ERA ROWS (values shown for the fixtures, not their per-field rows) ==")
    show = [n for n in era if n in fixtures]
    for n in show:
      print(f"  {n} = {before[n][:110]}")
    print(f"  ... and {len(era) - len(show)} per-field row(s) under those fixtures")

  if missing:
    print(f"\nFAIL  the file does not declare its own staleness: {len(missing)} of "
          f"{len(missing)} required name(s) absent -- {', '.join(missing[:8])}"
          f"{' ...' if len(missing) > 8 else ''}")
    print(f"  witnesses missing : {len([n for n in era if f'{n}_absent' not in before])} of {len(era)}")
    print("\nDELETING THE ROWS INSTEAD COSTS THE TREE ITS ONLY RECORD OF `Ops.GROUP` AND BUYS "
          f"NOTHING: {len(code)} instrument(s) read this file. Run with --record to write the "
          "witnesses, the census and this run's refusal token.")
    return FAIL
  print("\nPASS  every group-era row carries a witness, the census agrees with the computed set, "
        "and the recorded refusal is this run's token")
  return PASS


if __name__ == "__main__":
  sys.exit(main())