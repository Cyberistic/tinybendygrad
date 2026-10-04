#!/usr/bin/env python3
"""Mutation table for `UOp.variable` (tinygrad/uop/ops.py:1015).

    .venv/bin/python .agents/slop/ops-vrn-mutate.py

Five mutations, one per field the def sets, plus one CONTROL that must move nothing.

`variable` is five field WRITES and nothing else, which makes it the cleanest
conjunct-to-row mapping in the file: `slot`, `name`, `vmin_vmax`, `multiple_of`,
`addrspace`. There is no fold, no shape and no `Bnd` read, and that is the whole
reason it was portable the moment `ParamArg.no_slot` existed.

The check is EXACT -- the set of moved rows must EQUAL the predicted set. Every row
prints all five fields, so any mutation of any field moves ALL FOUR rows; a
subset check would call that a pass and throw away the only information the table
produces, which is WHICH conjunct each row is sensitive to. What differs between the
mutations is the VALUE, and the table prints the before/after so the difference is
visible rather than inferred.
"""
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
OPS = REPO / "tinybendygrad" / "uop" / "ops.bend"
BASELINE = REPO / ".agents/slop/ops-vrn-gate-py.txt"

ROWS = ["vrn_default", "vrn_int32", "vrn_multi", "vrn_neg"]

# (label, exact string, replacement, rows that MUST move)
MUTATIONS = [
  # 1. The SLOT, which is the field this def waited two commits for. `no_slot()` -> 0
  #    makes every row print `slot=0` and nothing else changes, because no other
  #    field reads it.
  ("slot_is_zero",
   "  UOp.variable.pa.of(ParamArg.of(ParamArg.no_slot(), dt), nm, PyRange{lo, hi}, mo)",
   "  UOp.variable.pa.of(ParamArg.of(0, dt), nm, PyRange{lo, hi}, mo)",
   ROWS),
  # 2. The ADDRSPACE. ALU is what `is_variable` tests, so `AGlobal` here makes every
  #    row print `addr=GLOBAL` -- and it is the mutation that would break the
  #    VARIABLE-ness of everything this def mints, which is why it is in the table
  #    even though the field is otherwise unobserved.
  ("addrspace_is_global",
   "      ParamArg{slot, dtype, size, Some{r}, Some{mo}, Some{nm}, S.Aalu{},",
   "      ParamArg{slot, dtype, size, Some{r}, Some{mo}, Some{nm}, S.AGlobal{},",
   ROWS),
  # 3. The NAME, dropped. Every row prints `name=-`, and the `None` arm of
  #    `vrn_opts` becomes reachable -- which is the row that says a Variable with no
  #    name is a shape this port can represent rather than one it invents.
  ("name_is_none",
   "      ParamArg{slot, dtype, size, Some{r}, Some{mo}, Some{nm}, S.Aalu{},",
   "      ParamArg{slot, dtype, size, Some{r}, Some{mo}, None{}, S.Aalu{},",
   ROWS),
  # 4. The RANGE, not the multiple_of. Swapping `lo` and `hi` is the mutation that
  #    a single "print the range" row could NOT see: `vrn_multi` answers
  #    `lo=...:4294967291 hi=0:5` and the swap answers `lo=0:5 hi=...:4294967291`,
  #    which is visible only because the two ends are SEPARATE fields of the row.
  ("range_ends_swapped",
   "  UOp.variable.pa.of(ParamArg.of(ParamArg.no_slot(), dt), nm, PyRange{lo, hi}, mo)",
   "  UOp.variable.pa.of(ParamArg.of(ParamArg.no_slot(), dt), nm, PyRange{hi, lo}, mo)",
   ROWS),
  # 5. The MULTIPLE_OF, hardcoded to 1. `vrn_multi` is the only row whose input is
  #    not 1, so it is the only row whose ANSWER changes -- and that is the point:
  #    it is the row that carries the parameter, and a table where every mutation
  #    moved every row could not tell that from the other four.
  ("multiple_of_hardcoded",
   "      ParamArg{slot, dtype, size, Some{r}, Some{mo}, Some{nm}, S.Aalu{},",
   "      ParamArg{slot, dtype, size, Some{r}, Some{1}, Some{nm}, S.Aalu{},",
   ["vrn_multi"]),
  # 6. CONTROL, and it is a DEAD-ARM control, which is the only kind this unit can
  #    have. Every row prints all five fields, so any WRITE to the record is visible
  #    in all four rows -- and a table where every mutation moved every row could not
  #    tell the conjuncts apart. `multiple_of_hardcoded` above is what restores the
  #    selectivity: it moves 1 of 4, because `vrn_multi` is the only fixture whose
  #    input is not 1.
  #
  #    This mutation is the `case _:` arm of `vrn_pa_of`, which NO `vrn_*` fixture
  #    reaches -- every one is a PARAM. It must move NOTHING, and if it moves
  #    something then a fixture is reaching a node the rows did not mean to build.
  #    That is the standing fixture discipline: a control that moves rows is a
  #    finding, and a control that is a broken build is not a control at all.
  #
  #    The first draft's control was `vrn_lo` calling `vrn_hi.of`, on the reasoning
  #    that it "cannot be a no-op by accident". It was not a control: `vrn_hi.of` is
  #    declared AFTER `vrn_lo`, so the edit is an R-3 violation and the run produced
  #    zero rows. The harness reported that as "NOT A ROW MOVE", which reads like a
  #    measurement and is actually a compile error -- the exact confusion this table
  #    exists to prevent, committed by the table itself.
  ("ctl_dead_fallback_arm",
   "    case _: ParamArg.of(ParamArg.no_slot(), S.weakint())",
   "    case _: ParamArg.of(0, S.int32())",
   []),
]


def read_rows() -> dict:
  out = subprocess.run([str(REPO / "bin/bend"), str(OPS)],
                       capture_output=True, text=True, cwd=REPO)
  rows = {}
  for line in out.stdout.split("\n"):
    if line.startswith("vrn_") and "=" in line:
      k, v = line.split("=", 1)
      rows[k] = v
  return rows


def rows_moved(base: dict, got: dict) -> set:
  return {k for k in base if k in got and base[k] != got[k]}


def main() -> int:
  base = read_rows()
  if not BASELINE.exists():
    print(f"{BASELINE.relative_to(REPO)} does not exist -- run ops-vrn-gate.sh",
          file=sys.stderr)
    return 1
  want = [l.split("=", 1)[0] for l in BASELINE.read_text().split("\n") if l.startswith("vrn_")]
  if sorted(base) != sorted(want):
    print(f"ops-vrn-mutate: the port answers {sorted(base)}, the gate's baseline "
          f"{sorted(want)}. Run ops-vrn-gate.sh.", file=sys.stderr)
    return 1

  print(f"{'mutation':24} {'rows moved':6} {'one row, before -> after':52} verdict")
  bad = 0
  for label, old, new, must in MUTATIONS:
    text = OPS.read_text()
    if text.count(old) != 1:
      print(f"{label:24} {'-':6} {'PATTERN NOT UNIQUE (' + str(text.count(old)) + ')':52} NOT MEASURED")
      bad += 1
      continue
    OPS.write_text(text.replace(old, new, 1))
    try:
      got = read_rows()
      moved = rows_moved(base, got)
    finally:
      OPS.write_text(text)
    if len(got) != len(base):
      print(f"{label:24} {'-':6} {'RUN BROKE (' + str(len(got)) + ' rows)':52} NOT A ROW MOVE")
      bad += 1
      continue
    ok = moved == set(must)
    if not ok:
      bad += 1
    delta = "(no row should move)"
    if must:
        first = sorted(must)[0]
        delta = base[first][:30] + "  ->  " + got[first].split(" lo=")[0][:30] if first in got else "(row absent)"
    print(f"{label:24} {len(moved):6} {delta:52} {'ok' if ok else 'MOVED ' + str(sorted(set(must)))}")

  print(f"\n{len(MUTATIONS) - bad}/{len(MUTATIONS)} mutations moved EXACTLY the rows they name")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())
