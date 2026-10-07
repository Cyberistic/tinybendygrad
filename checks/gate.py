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
    sys.exit(f"gate fixture: {len(dup)} duplicate row names, first {dup[:4]}")
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
    sys.exit(f"node failed rc={p.returncode}\n{p.stdout[-3000:]}\n{p.stderr[-3000:]}")
  # The driver appends one line to the live bytes to reach a module-local fn.
  # Assert that here, so "we drove the tree" is a checked claim.
  append = re.search(r'^APPEND (".*")$', p.stdout, re.M).group(1)
  probe = (work / "dtype.probe.mjs").read_text()
  live = tree.read_text()
  if probe != live + json.loads(append):
    sys.exit("drive.mjs altered dtype.js by more than its declared APPEND")
  got, src_md5 = {}, re.search(r"^SRC_MD5 (\w+)$", p.stdout, re.M).group(1)
  # A census with a zero denominator has found nothing to look at. All TEN of
  # dtype.js's `io_eff` registrations must have run, or the file was never
  # evaluated and every row below would be an absent row.
  reg = re.search(r"^REGISTERED (.*)$", p.stdout, re.M).group(1).split()
  if len(reg) != 10:
    sys.exit(f"drive.mjs registered {len(reg)} of dtype.js's 10 seams: {reg}")
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


def main() -> None:
  ap = argparse.ArgumentParser()
  ap.add_argument("--tree", type=pathlib.Path, default=JS_LANE)
  ap.add_argument("--quick", action="store_true", help="drop the wide sweep")
  a = ap.parse_args()

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
  sys.exit(1 if bad or missing else 0)


if __name__ == "__main__":
  main()