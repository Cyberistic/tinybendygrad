#!/usr/bin/env python3
"""Mutation table for the ops.py:501-1928 unit of `tinybendygrad/uop/ops.bend`.

    .venv/bin/python .agents/slop/ops-501-mutate.py

Each mutation is a ONE-STRING edit to the port that should be a no-op if the gate
is measuring the def it claims to measure, and a ROW MOVER if the def is
load-bearing. A mutation that moves no row is a hole: either the def is not what
the row reads, or the row is not sensitive to the thing it names.

The claim being tested is the one the block's header makes -- that the six walks
differ ONLY in their op SETS, and that a walk REPEATS rather than testing once.
So the mutations are set edits, not arithmetic edits: each one swaps one op out of
a set and leaves every other arm alone.

Read fresh, write a single targeted `str.replace`, and never rewrite the file from
a stale read -- ops.bend is SHARED with another agent working on a different line
range, and a whole-file rewrite silently drops their concurrent edits.
"""
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
OPS = REPO / "tinybendygrad" / "uop" / "ops.bend"
GATE = REPO / ".agents/slop/ops-501-gate.sh"

# (label, the exact string to replace, its replacement, the rows that MUST move)
MUTATIONS = [
  # --- THE SETS. One op swapped out of one walk's peel set.
  ("base_drops_detach",
   "Bool.or(GroupOp.movement(Arena.op(ar, self)), eq_op(Arena.op(ar, self), OpsDETACH{}))",
   "GroupOp.movement(Arena.op(ar, self))", ["s5_base_detach"]),
  ("unsharded_drops_unshard",
   "Bool.or(UOp.base.peel(ar, self), eq_op(Arena.op(ar, self), OpsUNSHARD{}))",
   "UOp.base.peel(ar, self)", ["s5_unsharded_base_us"]),
  ("storage_drops_bitcast",
   """Bool.or(UOp.unsharded_base.peel(ar, self),
    Bool.or(eq_op(Arena.op(ar, self), OpsBITCAST{}), eq_op(Arena.op(ar, self), OpsAFTER{})))""",
   """Bool.or(UOp.unsharded_base.peel(ar, self),
    eq_op(Arena.op(ar, self), OpsAFTER{}))""", ["s5_storage_base_bc"]),
  ("without_after_drops_after",
   "case 1n+p: UOp.without_after(p, ar, Bool.pick(U32, eq_op(Arena.op(ar, self), OpsAFTER{}), Arena.src(ar, self, 0), self))",
   "case 1n+p: UOp.without_after(p, ar, self)", ["s5_wo_after_af"]),
  ("hbi_drops_after",
   "Bool.or(op_in3(Arena.op(ar, self)), Bool.and(after_ok, eq_op(Arena.op(ar, self), OpsAFTER{})))",
   "op_in3(Arena.op(ar, self))", ["s5_hbi_after_af"]),
  ("hbi_drops_unshard",
   """Bool.or(eq_op(op, OpsRESHAPE{}), Bool.or(eq_op(op, OpsUNSHARD{}), eq_op(op, OpsMSELECT{})))""",
   """Bool.or(eq_op(op, OpsRESHAPE{}), eq_op(op, OpsMSELECT{}))""", ["s5_hbi_us"]),
  # --- THE REPEAT. A walk that tests ONCE instead of peeling must answer RESHAPE on
  # --- the two-deep fixture and BUFFER on nothing else. `r2` is the row.
  ("base_tests_once",
   "case 1n+p: UOp.base(p, ar, Bool.pick(U32, UOp.base.peel(ar, self), Arena.src(ar, self, 0), self))",
   "case 1n+p: UOp.base(0n, ar, Bool.pick(U32, UOp.base.peel(ar, self), Arena.src(ar, self, 0), self))",
   ["s5_base_r2"]),
  # --- buf_uop's `len(s.src)` half. Dropping it walks off a leaf, and `c` is a leaf.
  ("buf_uop_drops_len",
   "Bool.and((Arena.nsrc(ar, self) > 0 : U32), UOp.buf_uop.cont(Arena.op(ar, self)))",
   "UOp.buf_uop.cont(Arena.op(ar, self))", ["s5_buf_uop_c"]),
  # --- buf_uop is a WALK PAST a non-buffer, not a peel. Making it a peel stops at
  # --- the RESHAPE, and `r1` is the row.
  ("buf_uop_becomes_peel",
   "Bool.and((Arena.nsrc(ar, self) > 0 : U32), UOp.buf_uop.cont(Arena.op(ar, self)))",
   "UOp.buf_uop.peel(ar, self)", ["s5_buf_uop_r1"]),
  # --- gate_kernel_sink's TWO NEGATIVE TESTS. Each is one row.
  ("gks_drops_linear",
   "case OpsLINEAR{}: False{}", "case OpsLINEAR{}: True{}", ["s5_gate_linear"]),
  ("gks_drops_kernelinfo",
   "case AKernel{ki}: False{}", "case AKernel{ki}: True{}", ["s5_gate_kernel"]),
  # --- split_uop's ORDER. Appending at the BACK answers the same length and the
  # --- reversed order, so only the SEQUENCE row sees it.
  ("split_pushes_to_back",
   "case True{}: Wk{List.append(&2, U32, srcs, work), out}",
   "case True{}: Wk{List.append(&2, U32, work, srcs), out}",
   ["s5_split_diamond"]),
  # --- split_uop's descent. Appending the srcs to the ANSWER instead of the
  # --- WORKLIST is the bug this file's `s5_split_nest` row was written to catch.
  ("split_appends_to_out",
   "case True{}: Wk{List.append(&2, U32, srcs, work), out}",
   "case True{}: Wk{work, List.append(&2, U32, out, srcs)}",
   ["s5_split_nest", "s5_split_left"]),
  # --- sharding's OP TEST. Without it a RESHAPE answers a pair.
  ("sharding_drops_op_test",
   """Bool.pick(List<&2, Shard>, eq_op(Arena.op(ar, self), OpsUNSHARD{}),
    sharding.pair(Arena.arg(ar, self), ar, self), Nil{})""",
   "sharding.pair(Arena.arg(ar, self), ar, self)", ["s5_sharding_none"]),
  # --- bufferize's extra src. Only the `+args` fixture sees it.
  ("bufferize_drops_args",
   "UOp.new(ar, OpsSTAGE{}, List.append(&2, U32, [self], args), ABad{}, TNone{})",
   "UOp.new(ar, OpsSTAGE{}, [self], ABad{}, TNone{})", ["s5_bufferize_arg"]),
]


def rows_moved(before: dict, after: dict) -> list:
  return sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k))


def read_rows() -> dict:
  out = subprocess.run([str(REPO / "bin/bend"), str(OPS)], capture_output=True, text=True, cwd=REPO)
  rows = {}
  for line in out.stdout.split("\n"):
    if line.startswith("s5_") and "=" in line:
      k, v = line.split("=", 1)
      rows[k] = v
  return rows


def main() -> int:
  if not OPS.exists():
    print("ops.bend is gone", file=sys.stderr)
    return 1
  base = read_rows()
  if len(base) != 82:
    print(f"ops-501-mutate: the unmutated file answers {len(base)} rows, not 82 -- "
          f"run ops-501-gate.sh first and fix that before measuring anything", file=sys.stderr)
    return 1
  print(f"{'mutation':28} {'rows that moved':44} verdict")
  bad = 0
  for label, old, new, must in MUTATIONS:
    text = OPS.read_text()
    if text.count(old) != 1:
      print(f"{label:28} {'PATTERN NOT UNIQUE (' + str(text.count(old)) + ')':44} NOT MEASURED")
      bad += 1
      continue
    OPS.write_text(text.replace(old, new, 1))
    try:
      got = read_rows()
      moved = rows_moved(base, got)
    finally:
      OPS.write_text(text)
    if len(got) != len(base):
      print(f"{label:28} {'RUN BROKE (' + str(len(got)) + ' of ' + str(len(base)) + ' rows)':44} NOT A ROW MOVE")
      bad += 1
      continue
    ok = all(m in moved for m in must)
    if not ok:
      bad += 1
    print(f"{label:28} {','.join(moved) or '-':44} {'ok' if ok else 'MISSING ' + ','.join(must)}")
  print(f"\n{len(MUTATIONS) - bad}/{len(MUTATIONS)} mutations moved the rows they name")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())
