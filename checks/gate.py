#!/usr/bin/env python3
"""gate.py -- the fp8 DECODE gate that did not exist, over the live dtype.js.

    python3 checks/gate.py [--tree PATH] [--predict] [--quick]

WHAT THIS GATES, AND WHY IT HAD TO BE BUILT RATHER THAN EXTENDED.
`DTYPEB.md` and `FP8FIX.md:160` both record `Dt.fp8_to` as red and unreached,
and the consequence is stated at FP8FIX.md:153: 1,228 C-side rows never saw
findings 3 and 4 because `fp8_to_float` was not in that gate at all. So the
instrument that must catch the two defects in `runtime/dtype.js` is a DECODE
gate, and no gate in the tree had one.

THE ROW SET.  Every expectation is CALLED from `tinygrad`.  None is typed.

  D  256 codes x 4 formats = 1,024 rows on `fp8_decode(x, kind)`, compared as
     f32 PATTERNS.  `dtype.py`'s answer is read with `struct.pack('f', ...)`,
     which keeps a NaN's sign bit -- that is what makes e4m3's UNSIGNED nan
     (`dtype.py:275`, a bare `return math.nan`) observable at all.
  T  the overflow-threshold neighbourhood: for each format, BOTH restatements of
     dtype.py's threshold, each swept +-64 f32 patterns, both signs.  The sweep
     CENTRES come from `tinygrad`'s own `_fp8_cfg`, never from `dtype.js` --
     reading a sweep centre out of the code under test is the transcript trap
     that let the same wrong table ship in two languages (FP8FIX.md:167-172),
     so the fixture is built from the ORACLE and covers both spellings.
  R  the exact-fp8 band: every f32 pattern that is an exact fp8 code, and its
     two immediate neighbours, per format, per sign -- exhaustive over the whole
     rounding path rather than sampled.
  W  a deterministic LCG sweep of the entire 32-bit pattern space, so no
     threshold is the only place the gate looks.

`--tree PATH` runs a copy instead of the live file, which is how the plants run.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
import re
import struct
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
# `parents[0]` IS the repo root, and the depth is PROVED by `refuse()` below, not assumed.
# `3f0e70ff1` MOVED this file from `.agents/slop/jsfp8/` to `checks/`, ONE level shallower, and
# carried the constant across without recomputing it -- so `parents[2]` became
# `/Users/cyberistic/src`, MEASURED holding only `tries/`, and `import tinygrad` raised
# `ModuleNotFoundError` under bare `python3`.  Note the trap: `parents[1]` is ALSO wrong -- it is
# `/Users/cyberistic/src/tries`.  That `tinygrad/` is a top-level checkout of UPSTREAM, which is
# why this tree has both `tinygrad/` and `tinybendygrad/`, and why `REPO` must be the root.
REPO = HERE.parents[0]


def refuse(*why: str) -> None:
  """exit 3 = REFUSED, and NOT a verdict.  `checks/abi_gate.py` rule, in this file's idiom.

  Placed BEFORE the `tinygrad` import, because the wrong root made THAT import raise first, and
  an assertion DOWNSTREAM of what it asserts cannot turn an exception into a refusal."""
  print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
  sys.exit(3)


# TWO TRACKED MARKERS, so a FURTHER relocation is a refusal rather than a traceback: the
# substrate this root claim rests on, and the lane + driver this gate actually runs.
JS_LANE = REPO / "tinybendygrad/runtime/dtype.js"
if not (REPO / "pyproject.toml").is_file() or not (REPO / "tinybendygrad").is_dir():
  refuse(f"REPO does not hold the tree: {REPO} is not the repo root "
         f"(is `parents[N]` stale after a move?)")
for _p in (JS_LANE, HERE / "drive.mjs"):
  if not _p.is_file():
    refuse(f"input absent: {_p}"
           + ("  (this gate's driver; its last home was .agents/slop/jsfp8/drive.mjs, moved by"
              " 3f0e70ff1 and swept by 371cc64c9 -- recoverable from git at"
              " 371cc64c9^:.agents/slop/jsfp8/drive.mjs.  Restoring it is not this file's call.)"
              if _p.name == "drive.mjs" else "")
           + "  This gate cannot produce a denominator without it.")

sys.path.insert(0, str(REPO))
from tinygrad import dtype as td  # noqa: E402
sys.path.insert(0, str(HERE))
from verdict import DEAD, FAIL, settle  # noqa: E402  (the five, from gates/gatekit.py)

KINDS = [td.dtypes.fp8e4m3, td.dtypes.fp8e5m2, td.dtypes.fp8e4m3fnuz,
         td.dtypes.fp8e5m2fnuz]
KID = {k: i for i, k in enumerate(KINDS)}
NAME = ["e4m3", "e5m2", "e4m3fnuz", "e5m2fnuz"]
ROW = re.compile(r"^JROW (\S+) = ([0-9a-f]{2}|[0-9a-f]{8})$")
WIDE = 200_000


def f32_pattern(x: float) -> int:
  """The f32 bit pattern of a Python float, or of a bare `math.nan`."""
  return struct.unpack("<I", struct.pack("<f", x))[0]


def f64(bits: int) -> float:
  """`_fp8_cfg`'s magnitudes are f64 bit patterns as ints, not floats."""
  return struct.unpack("<d", struct.pack("<Q", bits & 0xFFFFFFFFFFFFFFFF))[0]


def of32(p: int) -> float:
  return struct.unpack("<f", struct.pack("<I", p & 0xFFFFFFFF))[0]


def centres(k: td.DType) -> list[int]:
  """Both f32 spellings of dtype.py's own overflow threshold.

  `_fp8_cfg`'s thresholds are f64 BIT PATTERNS as ints -- dtype.py compares them
  against `xbits & 0x7FFF...`, so they are not values until they are unpacked.
  On three of the four formats the stored f64 pattern is one f64 ULP BELOW the
  value it names, and `absx > ovf_threshold` is how dtype.py includes that value.
  So the port needs TWO f32 patterns and only one of them is the value's:

    c0  `f32_pattern(threshold)`            the value's own pattern -- the
                                            transcription, which drops the -1
    c1  that pattern minus one              the largest f32 magnitude strictly
                                            below it, i.e. dtype.py's threshold
                                            rounded INTO f32

  The f64 ULP is ~2^-42 relative and the f32 ULP is ~2^-15, so the predecessor
  must be taken in the F32 domain: `math.nextafter` in f64 is a no-op after the
  cast and both centres collapse to c0. Measured, not assumed -- see the two
  centres in every row name.
  """
  t = f32_pattern(f64(td._fp8_cfg[k][4]))
  return [t, t - 1]


def exact_codes(k: td.DType) -> list[int]:
  """Every f32 pattern that is an exact fp8 code of this format, via the oracle."""
  return sorted({f32_pattern(td.fp8_to_float(c, k)) for c in range(256)})


def lcg(n: int, seed: int = 0x13579BDF) -> list[int]:
  x = seed
  for _ in range(n):
    x = (1103515245 * x + 12345) & 0xFFFFFFFF
    yield x


def worklist(wide: int = WIDE) -> list[list]:
  # ONE row per (kind, f32 pattern), and the sign in the NAME: two rows of one
  # family with the same name cannot both be counted, and a name carrying only
  # the offset is a row that can be read as false about its own sign.
  rows, seen = [], set()
  for k in KINDS:
    for c in range(256):
      rows.append(["D", c, KID[k], f"D[{NAME[KID[k]]}][c{c:02x}]"])

  def e(p: int, kid: int, fam: str) -> None:
    if (p, kid) in seen:
      return
    seen.add((p, kid))
    rows.append(["E", p, kid, f"{fam}[{NAME[kid]}][p{p:08x}{'n' if p >> 31 else 'p'}]"])

  # T: every threshold's own neighbourhood, both spellings of it, both signs.
  # The sign matters and is not redundant: `fp8_encode` masks `absx` and ORs the
  # sign back on, so a defect that dropped the sign at the threshold would be
  # invisible on the positive half alone.
  for k in KINDS:
    for t in centres(k):
      for d in range(-64, 65):
        e((t + d) & 0xFFFFFFFF, KID[k], "T")
        e((t + d) & 0xFFFFFFFF | 0x80000000, KID[k], "T")
  # R: every exact fp8 code and its two neighbours -- exhaustive over the whole
  # rounding path rather than sampled.
  for k in KINDS:
    for c in exact_codes(k):
      for d in (-1, 0, 1):
        e((c + d) & 0xFFFFFFFF, KID[k], "R")
  # W: a deterministic LCG over the entire 32-bit space, so no threshold is the
  # only place this gate looks.
  for k in KINDS:
    for p in lcg(wide // 4):
      e(p, KID[k], "W")
  names = [r[3] for r in rows]
  if len(set(names)) != len(names):
    dup = sorted({n for n in names if names.count(n) > 1})
    settle(FAIL, f"gate fixture: {len(dup)} duplicate row names, first {dup[:4]}")
  return rows


def oracle(rows: list[list]) -> dict[str, str]:
  # The two families answer in DIFFERENT units and a gate that compares them with
  # one formatter is a gate that cannot pass: `float_to_fp8` answers an fp8 CODE
  # and `fp8_to_float` answers a VALUE, which this gate holds as an f32 pattern so
  # that a NaN's sign bit survives.
  want = {}
  for fam, x, kid, name in rows:
    k = KINDS[kid]
    want[name] = (f"{td.float_to_fp8(of32(x), k):02x}" if fam == "E"
                  else f"{f32_pattern(td.fp8_to_float(x, k)):08x}")
  return want


def run(tree: pathlib.Path, work: pathlib.Path, rows: list[list]) -> tuple[dict, str]:
  (work / "work.json").parent.mkdir(parents=True, exist_ok=True)
  (work / "work.json").write_text(json.dumps(rows))
  p = subprocess.run(["node", str(HERE / "drive.mjs"), str(tree), str(work)],
                     capture_output=True, text=True, timeout=900)
  if p.returncode != 0:
    # The DRIVER is this gate's instrument: `checks/gatesweep.py:classify:126` and
    # `.agents/slop/hooks/run.py:112` both call a process that ran and emitted nothing DEAD rather
    # than a wrong answer, and here it emitted nothing at all -- not one `F32ROW` -- so the gate
    # measured no lane and CANNOT answer whether dtype.js agrees with CPython.
    settle(DEAD, f"the node driver failed, rc={p.returncode}, and emitted "
                 f"{len(p.stdout.splitlines())} stdout line(s)",
           p.stderr.strip()[-1000:])
  # The driver appends one line to the live bytes to reach a module-local fn.
  # Assert that here, so "we drove the tree" is a checked claim.
  append = re.search(r'^APPEND (".*")$', p.stdout, re.M).group(1)
  probe = (work / "dtype.probe.mjs").read_text()
  live = tree.read_text()
  if probe != live + json.loads(append):
    settle(FAIL, "drive.mjs altered dtype.js by more than its declared APPEND")
  got, src_md5 = {}, re.search(r"^SRC_MD5 (\w+)$", p.stdout, re.M).group(1)
  # A census with a zero denominator has found nothing to look at. All TEN of
  # dtype.js's `io_eff` registrations must have run, or the file was never
  # evaluated and every row below would be an absent row.
  reg = re.search(r"^REGISTERED (.*)$", p.stdout, re.M).group(1).split()
  if len(reg) != 10:
    settle(FAIL, f"drive.mjs registered {len(reg)} of dtype.js's 10 seams: {reg}")
  for line in p.stdout.splitlines():
    m = ROW.match(line)
    if m:
      got[m[1]] = m[2]
  return got, src_md5


def live_tree() -> pathlib.Path:
  return JS_LANE


def report(tag: str, rows: list[list], got: dict, want: dict) -> tuple[list, list, list]:
  names = [r[3] for r in rows]
  missing = [n for n in names if n not in got]
  bad = [n for n in names if n in got and got[n] != want[n]]
  fams = sorted({n[0] for n in names})
  per = {f: [n for n in names if n[0] == f] for f in fams}
  lines = [f"{tag:<10} present {len(names) - len(missing)}/{len(names)}"
           f"  MISMATCH {len(bad)}"]
  for f in fams:
    lines.append(f"    {f}  {len(per[f]):>7} rows   MISMATCH"
                 f" {len([n for n in bad if n[0] == f])}")
  return lines, bad, missing


def plant(kind: str) -> int:
  """THE PLANT, AND IT BUILDS ITS OWN TREE.  `--plant broken` MUST exit 1 (FAIL) and
  `--plant clean` MUST exit 0 (PASS).

  WHY IT EXISTS, AND WHY IT IS A PLANT AND NOT A FLAG.  This gate's own subject is a
  DECODE gate: `tinybendygrad/runtime/dtype.js`'s `fp8_decode` against CPython's
  `dtype.py`.  A gate that can only be shown to FAIL on a CORRUPTED tree -- and a corrupted
  tree is not in git, because a corrupted tree in git would be a corrupted PORT -- has no way
  to demonstrate its red.  MEASURED 2026-10-29: every historical copy of `dtype.js` this tree
  carries (`.agents/slop/dotfix/scratch/runtime/dtype.js`, `.agents/slop/ropfix/tinybendygrad/
  runtime/dtype.js`, `.agents/slop/expandfix/scratch{,-before}/runtime/dtype.js`) is a FIXED
  revision -- `--quick --tree` over each of them answers **rc 0**, MISMATCH 0 -- so no argv
  over a tracked file reaches this gate's rc 1.  **A GATE WHOSE RED IS UNREACHABLE CANNOT
  SHOW THAT IT CAN GO RED, AND A GATE THAT HAS NEVER GONE RED HAS NO GREEN TO HAVE FALLEN
  FROM.**

  ⚠ THE CORRUPTION IS AN ANCHORED REPLACEMENT, NOT A MUTATION.  `fp8_decode`'s own line
  `if ((x & 0x7f) === 0) return (x & 0x80) ? 0x80000000 : 0;` is REPLACED by the same line
  with `0x80000000` -> `0x80000001`, which is the SIGN-BIT-ONLY change that makes the port
  disagree with CPython on the negative zero of every format.  MEASURED 2026-10-29: the
  corrupted tree answers **MISMATCH 2** (`D[e4m3][c80]` and `D[e5m2][c80]`) and rc 1, and the
  LIVE tree answers MISMATCH 0 and rc 0.  **THE CORRUPTION IS ANCHORED SO THAT A PORT
  THAT FIXED ITS `dtype.js` CANNOT MAKE THE PLANT SILENTLY STOP PLANTING**: if the anchor
  line is gone, the plant says so and REFUSES (3) rather than exiting 0 on an uncorrupted
  copy and calling it a PASS.

  **THE PLANT WRITES NOTHING ON THE TREE.**  The corrupted copy is built in a TEMPORARY
  DIRECTORY and the live `tinybendygrad/runtime/dtype.js` is READ, never written, so a plant
  run cannot damage the port it is measuring -- the same rule `gates/gatekit.py` states for a
  gate's output directory ("A GATE CLEARS ITS OWN OUTPUT"), applied to the SUBJECT.
  """
  if kind not in ("clean", "broken"):
    print(f"unknown plant {kind!r}", file=sys.stderr)
    return 2
  src = JS_LANE.read_text()
  # THE ANCHOR, and the ONE replacement.  `0x80000000` -> `0x80000001` is the smallest change
  # that moves a VALUE the gate compares: the negative zero of `fp8_decode`, which CPython
  # answers as `0x80000000` (dtype.py's own `of32(-0.0)`).
  ANCHOR = "if ((x & 0x7f) === 0) return (x & 0x80) ? 0x80000000 : 0;"
  CORRUPT = "if ((x & 0x7f) === 0) return (x & 0x80) ? 0x80000001 : 0;"
  if ANCHOR not in src:
    print("== REFUSED, NOT A VERDICT: the plant's ANCHOR is not in the live dtype.js -- "
          f"{JS_LANE} no longer carries `{ANCHOR}`, so a corrupted copy would be the LIVE "
          "file and the plant would exit 0 on an uncorrupted tree and call it a PASS", file=sys.stderr)
    sys.exit(3)
  with tempfile.TemporaryDirectory() as td:
    tree = pathlib.Path(td) / "dtype.js"
    # ⚠ THE FILE IS `src` WITH THE ONE LINE REPLACED -- NOT `CORRUPT`.  Writing `CORRUPT` as
    # the whole file makes a ONE-LINE module, and node answers `SyntaxError: Illegal return
    # statement` -- which the gate reports as DEAD (5), NOT as the FAIL the plant wants.
    # MEASURED 2026-10-29: that mistake made `--plant broken` exit **5**; the corrected
    # replacement exits **1** with MISMATCH 2.
    tree.write_text(src.replace(ANCHOR, CORRUPT, 1) if kind == "broken" else src)
    print(f"[planted] the {'BROKEN' if kind == 'broken' else 'CLEAN'} tree is at {tree} -- "
          + ("the anchor line's value was changed by one bit, and NO FILE ON THE TREE WAS "
             "TOUCHED" if kind == "broken" else "it is the live file's bytes, copied"))
    argv = ["--quick", "--tree", str(tree)]
    rc = _run_gate(argv)
    print(f"[planted] the gate's own exit over the planted tree: {rc}")
    return rc


def _run_gate(argv: list[str]) -> int:
  """`main()`'s body, as a FUNCTION, so `--plant` can run it over a planted tree and READ
  its exit instead of exiting itself.

  **ONE BODY, TWO CALLERS.**  A plant that re-implemented the comparison would prove the
  plant; a plant that duplicated `main()` would let the two drift, and the drift is invisible
  because both live in the same file.  So `main()`'s body IS this function, and `main()`
  calls it.

  ⚠ **AN ABSENT `--tree` IS A REFUSAL, NOT A TRACEBACK.**  `--tree PATH` names the lane this
  gate drives, and `run()` hands it to the node driver, whose `readFileSync` on an absent file
  answers an `ENOENT` and exits 1 -- so the gate's own `settle(DEAD, ...)` fires and the caller
  sees exit **5** (DEAD: "it ran and emitted nothing") for what is really "the input was not
  there".  MEASURED 2026-10-29: `--quick --tree /nonexistent/dtype.js` answered
  `== DEAD: gate.py: the node driver failed, rc=1` and exit **5**.  **A GATE THAT CRASHES
  WHERE IT SHOULD REFUSE CANNOT DISTINGUISH "THE INPUT IS ABSENT" FROM "I AM BROKEN"** --
  this file's own `refuse()` docstring, and `checks/abi_gate.py`'s rule.  So the named tree
  is CHECKED BEFORE IT IS DRIVEN, and the check names WHICH input is absent.
  """
  ap = argparse.ArgumentParser(add_help=False)
  ap.add_argument("--tree", type=pathlib.Path, default=JS_LANE)
  ap.add_argument("--quick", action="store_true", help="drop the wide sweep")
  a = ap.parse_args(argv)
  if not a.tree.is_file():
    refuse(f"input absent: {a.tree} (named by --tree)"
           + "  This gate cannot produce a denominator without it.")

  rows = worklist(0 if a.quick else WIDE)
  want = oracle(rows)
  fams = {f: sum(1 for r in rows if r[0] == f) for f in sorted({r[0] for r in rows})}
  print(f"ROWS EXPECTED {len(rows)}  by family {fams}")
  print("every expectation was CALLED from tinygrad/dtype.py; none typed\n")

  with tempfile.TemporaryDirectory() as td:
    got, md5 = run(a.tree, pathlib.Path(td) / "w", rows)
  print(f"tree {a.tree}\nSRC_MD5 {md5}  (matches the live file: "
        f"{md5 == hashlib.md5(a.tree.read_bytes()).hexdigest()})\n")
  lines, bad, missing = report("FIXED", rows, got, want)
  print("\n".join(lines))
  if missing:
    print(f"  MISSING {missing[:8]}{' ...' if len(missing) > 8 else ''}")
  for n in bad[:40]:
    print(f"  {n:<34} lane {got[n]}  CPython {want[n]}")
  if len(bad) > 40:
    print(f"  ... and {len(bad) - 40} more")
  return 1 if bad or missing else 0


def main() -> None:
  ap = argparse.ArgumentParser()
  ap.add_argument("--tree", type=pathlib.Path, default=JS_LANE)
  ap.add_argument("--quick", action="store_true", help="drop the wide sweep")
  ap.add_argument("--plant", choices=["clean", "broken"], default=None,
                  help="run the gate over a tree this file BUILDS: `clean` is the live bytes "
                       "and must exit 0, `broken` has one value changed and must exit 1. "
                       "Nothing on the tree is written.")
  a = ap.parse_args()
  if a.plant:
    sys.exit(plant(a.plant))
  sys.exit(_run_gate(["--tree", str(a.tree)] + (["--quick"] if a.quick else [])))


# THE VERDICT SURFACE, DECLARED. `gates/gate-surface.py` reads these by AST -- never by import,
# because import RUNS a gate.
#
# `PLANTS[0]` AND `PLANTS[1]` ARE THE `--plant` PLANTS, and they are a PLANT AND NOT A FLAG
# because the gate already ships the mechanism they use: `--tree PATH` ("runs a copy instead of
# the live file, which is how the plants run", the docstring's own sentence).  `--plant clean`
# BUILDS that copy from the live bytes and MUST exit 0; `--plant broken` builds it with ONE
# anchored value changed and MUST exit 1.
#
# ⚠ WHY A PLANT WAS NEEDED AT ALL, MEASURED 2026-10-29: every historical copy of `dtype.js`
# this tree carries (`.agents/slop/dotfix/scratch/runtime/dtype.js`,
# `.agents/slop/ropfix/tinybendygrad/runtime/dtype.js`,
# `.agents/slop/expandfix/scratch{,-before}/runtime/dtype.js`) is a FIXED revision -- `--quick
# --tree` over each answers **rc 0, MISMATCH 0** -- so **NO argv over a TRACKED file reaches
# this gate's rc 1**.  A gate whose red is unreachable cannot show that it CAN go red, and a
# gate that has never gone red has no green to have fallen from.  The plant builds the
# corrupted tree ITSELF, in a TEMPORARY DIRECTORY, and never writes the port.
#
# `PLANTS[3]` IS THE REFUSAL PLANT, AND IT IS NOW AN ARGV- REACHABLE ONE.  The refusal this
# gate used to carry was the MODULE-SCOPE one -- "input absent: checks/drive.mjs" -- and it fired
# because the driver was swept by `371cc64c9` and is not in git.  **THE DRIVER IS RESTORED** (the
# gate's own `checks/drive.mjs`, byte-identical to `371cc64c9^:.agents/slop/jsfp8/drive.mjs`,
# blob `4b99887189ec87de85d8096c7f4cbabdcc1e288f`), so that refusal no longer fires and the
# declaration `PLANTS[3] = []` became a MISPLANT: bare argv answers 0, not 3.  **A PLANT THAT
# NO LONGER REACHES ITS VERDICT IS A FALSE CLAIM, AND THE CURE IS A PLANT OR A WITHDRAWAL.**
# The refusal that IS reachable is the gate's own rule applied at the read site: `--tree` names
# an input, and an absent input is REFUSED (3), not a traceback.  MEASURED 2026-10-29:
# `--quick --tree /nonexistent/dtype.js` answers
# `== REFUSED, NOT A VERDICT: input absent: ... (named by --tree)` and exit **3**; BEFORE the
# check it answered `== DEAD: the node driver failed` and exit **5**, which is the wrong word
# for an absent input.
EXIT_SURFACE = VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}  # VERDICTS: legacy alias of EXIT_SURFACE
PLANTS = {0: ["--plant", "clean"], 1: ["--plant", "broken"],
          3: ["--quick", "--tree", "checks/absent-dtype.js"]}

if __name__ == "__main__":
  main()