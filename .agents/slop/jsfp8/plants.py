#!/usr/bin/env python3
"""plants.py -- one mutation per fixed rule, plus the disarms, run on $TMPDIR.

    python3 .agents/slop/jsfp8/plants.py [--quick]

Every plant is a text edit applied to a COPY of the live `dtype.js`; the live
tree is never written. BASE is reconstructed by reverse-applying this unit's own
two fixes and is PROVEN by md5, so "before" is a checked claim and not a memory.

`OUT-OF-MECHANISM` is the assertion that can fail: each mutation carries the
mechanism(s) that name the rows that COULD move, and every row that moved but is
not in that set is reported. The C unit's version caught three of its own errors
(.agents/slop/FP8FIX.md:74-77), one of them naming the row the plant REPAIRS.

Subsets, not equalities, where the property is a fact about the PORT: the
mechanism determines which patterns are CANDIDATES, and whether the saturating
and the rounding answer differ at one is CPython's to say. Where the mechanism
does determine the answer exactly -- PLANT-fnuz-helper-inverted, whose guard is
one comparison -- equality is asserted and reported.
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import shutil
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gate import KINDS, NAME, centres, live_tree, run, worklist  # noqa: E402

# label, old, new, mechanisms. `none` = an expected zero (a disarm or a scope
# blind spot), and an empty mechanism list is never used: a zero with no reason
# is a request for a fixture.
EDITS: list[tuple[str, str, str, tuple[str, ...]]] = [
  # 1. The transcription: dtype.py's `-1` gone from ALL THREE formats that carry
  #    one. This is finding 1, and BASE is exactly this edit plus the comments.
  ("PLANT-ovf-transcription",
   "[15, 3, 0x3, 0x37000000, 0x476fffff, 0x7b, 0x38800000],\n"
   "  [8, 4, 0x7, 0x3a000000, 0x4377ffff, 0x7f, 0x3c000000],\n"
   "  [16, 3, 0x3, 0x36800000, 0x476fffff, 0x7f, 0x38000000],",
   "[15, 3, 0x3, 0x37000000, 0x47700000, 0x7b, 0x38800000],\n"
   "  [8, 4, 0x7, 0x3a000000, 0x43780000, 0x7f, 0x3c000000],\n"
   "  [16, 3, 0x3, 0x36800000, 0x47700000, 0x7f, 0x38000000],", ("ovf",)),
  # 1b. Granularity: ONE entry, so the plant says which format's row moved.
  ("PLANT-ovf-e5m2-only",
   "[15, 3, 0x3, 0x37000000, 0x476fffff, 0x7b, 0x38800000],",
   "[15, 3, 0x3, 0x37000000, 0x47700000, 0x7b, 0x38800000],", ("ovf",)),
  # 2. DISARM: the same three numbers, spelled as the value and an offset. A
  #    disarm is only a disarm after it has moved 0 IN FACT.
  ("DISARM-ovf-respell",
   "0x476fffff, 0x7b, 0x38800000],\n  [8, 4, 0x7, 0x3a000000, 0x4377ffff, 0x7f, 0x3c000000],\n"
   "  [16, 3, 0x3, 0x36800000, 0x476fffff, 0x7f, 0x38000000],",
   "0x47700000 - 1, 0x7b, 0x38800000],\n"
   "  [8, 4, 0x7, 0x3a000000, 0x43780000 - 1, 0x7f, 0x3c000000],\n"
   "  [16, 3, 0x3, 0x36800000, 0x47700000 - 1, 0x7f, 0x38000000],", ("none",)),
  # 3. The signed NaN. Finding 4, and the decode half of BASE.
  ("PLANT-nan-signed", "if (mant === mantMax) return 0x7fc00000;",
   "if (mant === mantMax) return sgn ? 0xffc00000 : 0x7fc00000;", ("nan",)),
  # 4. DISARM: the same value, spelled through the file's own bitcast helper.
  ("DISARM-nan-rewrap", "if (mant === mantMax) return 0x7fc00000;",
   "if (mant === mantMax) return bits32(NaN);", ("none",)),
  # 5. THE HELPER-INVERSION PLANT. `kind >= FP8_E4M3FNUZ` is the file's own fnuz
  #    test; `>` keeps e4m3fnuz out of it. A new gate is the weakest instrument in
  #    the tree, so this one inverts a helper to prove it is not blind.
  ("PLANT-fnuz-helper-inverted",
   "if (kind >= FP8_E4M3FNUZ && x === 0x80) return 0x7fc00000;",
   "if (kind > FP8_E4M3FNUZ && x === 0x80) return 0x7fc00000;", ("fnuz",)),
  # 6. A BLIND SPOT with its reason: this unit owns the fp8 half and no row in
  #    this set calls the bf16/fp16/i64 halves. It must move 0.
  ("BLIND-fp16-subnormal-zero", "if (e === 0) return m === 0 ? (s >>> 0) :",
   "if (e === 0) return m === 0 ? 0 :", ("none",)),
]

# The comments this unit added, reversed so BASE is BYTE-identical to the tree as
# it stood before, not merely code-identical. md5 below is the proof.
COMMENTS = [
  ("""// dtype.py's _fp8_cfg. denorm and min_norm are the f32 patterns of dtype.py's f64
// values, bit for bit. ovf is NOT: dtype.py writes it an f64 ULP LOW on three of the
// four formats (dtype.py:239-241), which is how `absx > ovf_threshold` includes the
// value it names -- and the f32 pattern of `61439.99999999999` is 61440's own, so
// restating the value drops the -1 and loses one boundary row per affected format.
// ovf therefore holds the LAST f32 magnitude dtype.py still rounds normally, and the
// `>` in fp8_encode is dtype.py's own `>`. e4m3 is the fourth threshold dtype.py
// writes without the -1, and its entry is the value itself. Same table as
// dtype.c:43; .agents/slop/JSFP8.md records how the wrong one shipped in two
// languages at once.
""",
   "// dtype.py's _fp8_cfg with the f64 magnitude patterns as f32 patterns.\n"),
  ("""    // dtype.py:275 signs NEITHER of e4m3's answers -- a bare `return math.nan`, so
    // it is unsigned whatever the code's top bit was. e5m2's above are the signed
    // ones (dtype.py:273 `copysign`).
""", ""),
]

BASE_EDITS = ["PLANT-ovf-transcription", "PLANT-nan-signed"]
BASE_CODE_MD5 = "fa61344f1dbecd9afa7563364583ae47"   # the pre-fix file, measured


def derived(kind: str, rows: list[list]) -> set[str]:
  """The rows the MECHANISM says could move: candidates, never predictions."""
  out = set()
  for fam, x, kid, name in rows:
    if kind == "ovf" and fam == "E" and any(x & 0x7FFFFFFF == t for t in centres(KINDS[kid])):
      out.add(name)
    elif kind == "nan" and fam == "D" and kid == 0 and x & 0x7F == 0x7F:
      out.add(name)
    elif kind == "fnuz" and fam == "D" and kid == 2 and x == 0x80:
      # EXACT, not a candidate set. `>= ` -> `>` changes the file's fnuz test for
      # kind 2 ONLY -- kinds 0, 1 stay false and kind 3 stays true -- and this arm
      # is guarded by `x === 0x80`, so the mechanism determines the answer.
      out.add(name)
  return out


def edit(text: str, label: str) -> str:
  for lab, old, new, _ in EDITS:
    if lab == label:
      if text.count(old) != 1:
        sys.exit(f"{label}: anchor is not unique ({text.count(old)} matches)")
      return text.replace(old, new)
  sys.exit(f"{label}: no such edit")


def main() -> None:
  ap = argparse.ArgumentParser()
  ap.add_argument("--quick", action="store_true")
  a = ap.parse_args()
  rows = worklist(0 if a.quick else 200_000)
  fixed_text = live_tree().read_text()
  base_text = fixed_text
  for lab in reversed(BASE_EDITS):
    base_text = edit(base_text, lab)
  for new, old in COMMENTS:
    if base_text.count(new) != 1:
      sys.exit(f"BASE comment anchor not unique ({base_text.count(new)}): {new[:40]!r}")
    base_text = base_text.replace(new, old)

  with tempfile.TemporaryDirectory() as tmp:
    w = pathlib.Path(tmp)
    print(f"live dtype.js  md5 {hashlib.md5(fixed_text.encode()).hexdigest()}")
    got_md5 = hashlib.md5(base_text.encode()).hexdigest()
    print(f"BASE           md5 {got_md5}\n{'':19}expected {BASE_CODE_MD5}"
          f"   {'PROVEN byte-identical' if got_md5 == BASE_CODE_MD5 else '*** MISMATCH ***'}")
    (w / "fixed.js").write_text(fixed_text)
    ref, _ = run(w / "fixed.js", w / "wf", rows)
    print(f"rows {len(rows)}   present {len(ref)}   (the differ is whole"
          " `name=value` lines, never row names)\n")

    print(f"{'mutation':<28}{'moved':>7}{'mech':>7}{'out-of':>8}  verdict")
    trees = [(f"BASE ({len(BASE_EDITS)} fixes reversed)", base_text, ("ovf", "nan"))]
    trees += [(lab, edit(fixed_text, lab), mech) for lab, _, _, mech in EDITS]
    for label, text, mech in trees:
      (w / "t.js").write_text(text)
      got, _ = run(w / "t.js", w / "wt", rows)
      moved = {n for n in ref if got.get(n) != ref[n]}
      der = set().union(*(derived(m, rows) for m in mech)) if "none" not in mech else set()
      out = moved - der
      exact = mech == ("fnuz",)   # one comparison: the mechanism IS the answer
      verdict = ("hold, 0 moved" if not moved else
                 "EXACT" if exact and moved == der else
                 "BOUND" if not out else "*** OUT OF MECHANISM ***")
      print(f"{label:<28}{len(moved):>7}{len(der):>11}{len(out):>8}  {verdict}")
      if label.startswith("BLIND"):
        print(f"{'':<28}stated blind spot: no row here calls the bf16/fp16/i64 halves")
      for n in sorted(moved - der):
        print(f"{'':<28}   NOT DERIVED {n}")
      if moved and len(moved) <= 14:
        for n in sorted(moved):
          print(f"{'':<28}   {n:<26} {ref[n]} -> {got[n]}")
      if der - moved and label.startswith(("PLANT-nan", "PLANT-ovf")):
        why = ("dtype.py:275's nan is a BARE `return math.nan`, so it is unsigned on"
               " BOTH e4m3 codes and the plant can only move the negative one"
               if "nan" in mech else
               "dtype.py:238-241 writes the `-1` on three of four formats; e4m3 is"
               " the one without it, and for the other formats the plant changes"
               " only the pattern AT the threshold, not its predecessor")
        print(f"{'':<28}   {len(der - moved)} candidates did not move:"
              f" {sorted(der - moved)[:3]}\n{'':<28}   {why}")
      shutil.rmtree(w / "wt", ignore_errors=True)


if __name__ == "__main__":
  main()