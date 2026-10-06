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

⚠ IT NEVER WRITES `tinybendygrad/uop/ops.bend`. The previous version did, at
`OPS.write_text(...)`, which is patching the live tree from a harness: `ops.bend` is
SHARED with another agent working on a different line range, so a read-then-write
whose window straddles their edit SILENTLY DESTROYS IT, and a kill inside the window
leaves the mutant on disk. Every run now stages `jj file show -r @` into the SAME
directory under a private filename, asserts the digest, edits only that, and deletes
it in a `finally`. The live file's digest is asserted unchanged at the end -- if
another agent wrote during the run, that is reported rather than hidden.

IT READS WITH `rebase-gate.py`'s `rows()`. The previous version had its own reader,
and agent-core.md's rule is that there is ONE row reader per repo: a name-comparing
harness reported 0 for all 30 mutations in one unit and 0 for all 68 in another.
"""
import importlib.util
import os
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
OPS = REPO / "tinybendygrad" / "uop" / "ops.bend"
ORACLE = REPO / ".agents/slop" / "ops-501-oracle.py"

_spec = importlib.util.spec_from_file_location("rebase_gate", pathlib.Path(__file__).with_name("rebase-gate.py"))
_rg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_rg)

# `UOp.getaddr.op`'s nine-op ladder, with its `def` header so the anchor is unique.
# The ladder's lines appear 2-62 times each elsewhere in ops.bend (`buf_uop.cont`,
# `hbi`'s set, `storage_base`), so an anchor without the header is ambiguous and
# `str.replace` would edit a DIFFERENT ladder.
_GA_LADDER = """def UOp.getaddr.op(op: Op) -> Bool:
  match op:
    case OpsBUFFER{}: True{}
    case OpsALLOC{}: True{}
    case OpsSHRINK{}: True{}
    case OpsBITCAST{}: True{}
    case OpsBINARY{}: True{}
    case OpsMSTACK{}: True{}
    case OpsMSELECT{}: True{}
    case OpsPARAM{}: True{}
    case OpsLINEAR{}: True{}
    case _: False{}
"""


def ga_drops(op: str) -> str:
  return _GA_LADDER.replace(f"    case {op}{{}}: True{{}}\n", "")


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
  # "A walk that peels ONCE" is not expressible as a legal mutation -- passing
  # `0n` to the self-call is not decreasing, so the file does not CHECK and the
  # run prints nothing. The same claim IS expressible through the FUEL, which is
  # better anyway: an under-fueled caller is the realistic way to get one step.
  # With NO fuel every walk answers its own node, so `r1` and `r2` both stop at the
  # RESHAPE and the rows say the walk REPEATS rather than testing once. One unit
  # was tried first and moved only `r2`: `case 1n+p` recurses with `p = 0n`, and
  # `case 0n:` then answers the node ONE level down, so a one-deep chain still
  # resolves. The fuel is a CALL argument here, not a self-call, so `0n` is legal.
  ("base_no_fuel",
   "    b : Unit <- s5.base(Arena.budget(ar), ar, f)",
   "    b : Unit <- s5.base(0n, ar, f)", ["s5_base_r1", "s5_base_r2"]),
  # --- buf_uop's `len(s.src)` half. Dropping it walks off a leaf, and `c` is a leaf.
  ("buf_uop_drops_len",
   "Bool.and((Arena.nsrc(ar, self) > 0 : U32), UOp.buf_uop.cont(Arena.op(ar, self)))",
   "UOp.buf_uop.cont(Arena.op(ar, self))", ["s5_buf_uop_c"]),
  # --- buf_uop is a WALK PAST a non-buffer, not a peel. Making it a peel stops at
  # --- the RESHAPE, and `r1` is the row.
  # `buf_uop` is a WALK PAST a non-buffer, not a peel over the buffer-ish set.
  # Treating RESHAPE as a stop makes it that peel, and `r1` and `r2` are the rows:
  # both then answer RESHAPE instead of reaching the BUFFER underneath.
  ("buf_uop_stops_at_reshape",
   """    case OpsBUFFER{}: False{}
    case OpsALLOC{}: False{}
    case OpsPARAM{}: False{}
    case OpsSTAGE{}: False{}
    case OpsMSTACK{}: False{}
    case _: True{}""",
   """    case OpsBUFFER{}: False{}
    case OpsALLOC{}: False{}
    case OpsPARAM{}: False{}
    case OpsSTAGE{}: False{}
    case OpsMSTACK{}: False{}
    case OpsRESHAPE{}: False{}
    case _: True{}""", ["s5_buf_uop_r1", "s5_buf_uop_r2"]),
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
   ["s5_split_nest"]),
  # --- split_uop's descent. Appending the srcs to the ANSWER instead of the
  # --- WORKLIST is the bug this file's `s5_split_nest` row was written to catch.
  ("split_appends_to_out",
   "case True{}: Wk{List.append(&2, U32, srcs, work), out}",
   "case True{}: Wk{work, List.append(&2, U32, out, srcs)}",
   ["s5_split_nest"]),
  # --- sharding's OP TEST. Without it a RESHAPE answers a pair.
  ("sharding_drops_op_test",
   """Bool.pick(List<&2, Shard>, eq_op(Arena.op(ar, self), OpsUNSHARD{}),
    sharding.pair(Arena.arg(ar, self), ar, self), Nil{})""",
   "sharding.pair(Arena.arg(ar, self), ar, self)", ["s5_sharding_none"]),
  # --- bufferize's extra src. Only the `+args` fixture sees it.
  ("bufferize_drops_args",
   "UOp.new(ar, OpsSTAGE{}, List.append(&2, U32, [self], args), ABad{}, TNone{})",
   "UOp.new(ar, OpsSTAGE{}, [self], ABad{}, TNone{})", ["s5_bufferize_arg"]),

  # --- THE MOVERS ROUND TWO, ops.py:758 `copy_to_device`, :846 `device_range_src`,
  # --- :841 `getaddr`. These 19 rows were ORACLE-ONLY for the whole life of the
  # --- gate, so until these seven mutations existed nothing said a single one of
  # --- them read the port.
  # `device_range_src` counts the tags. Hard-coding 1 makes a two-device RANGE
  # answer a one-device one, and `s5_devrange_single` is `-` so it cannot see it.
  ("devrange_hardcodes_one",
   "U32.from_nat(List.length(&2, U32, tags))", "U32.from_nat(1n)", ["s5_devrange_two"]),
  # `getaddr`'s nine-op ladder, one op dropped per mutation, `def` header as the
  # anchor so the replace cannot land on `buf_uop.cont` or `hbi`'s set instead.
  ("ga_drops_param", _GA_LADDER, ga_drops("OpsPARAM"), ["s5_ga_param"]),
  ("ga_drops_mstack", _GA_LADDER, ga_drops("OpsMSTACK"), ["s5_ga_mstack"]),
  ("ga_drops_linear", _GA_LADDER, ga_drops("OpsLINEAR"), ["s5_ga_linear"]),
  ("ga_drops_bitcast", _GA_LADDER, ga_drops("OpsBITCAST"), ["s5_ga_bitcast"]),
  # `self.without_after.op`, not `self.op`: a peel reading the node directly
  # typechecks and answers AFTER where CPython answers GETADDR.
  ("ga_peel_reads_self",
   "UOp.getaddr.op(Arena.op(ar, UOp.without_after(fuel, ar, self)))",
   "UOp.getaddr.op(Arena.op(ar, self))", ["s5_ga_after"]),
  # `inp = self if arg is None else MSELECT(self, arg)`: dropping the MSELECT
  # makes `s5_copy_sel` print `s5_copy_multi`'s value.
  ("copy_sel_drops_mselect",
   "    case Some{j}: UOp.mselect(ar, self, j)", "    case Some{j}: Found{ar, self}",
   ["s5_copy_sel"]),
  # `src=(inp, *device_range_src(device))`: dropping the RANGE costs the COPY its
  # second src on BOTH fixtures that have one.
  ("copy_drops_device_range",
   "List.append(&2, U32, [Found.i(f)], DRng.ys(d))", "[Found.i(f)]",
   ["s5_copy_multi", "s5_copy_sel"]),
]


def stage() -> pathlib.Path:
  """`jj file show -r @` into ops.bend's OWN DIRECTORY, under a private name.

  In place because ops.bend:166-168 imports ./../helpers.bend and ./../LAWS/spec.bend:
  a copy in $TMPDIR cannot resolve them and prints a phantom 0 rows, which is
  indistinguishable from "not started". Private name so it cannot be confused with the
  live file. The caller deletes it in a finally.
  """
  raw = subprocess.run(["jj", "file", "show", "-r", "@", str(OPS.relative_to(REPO))],
                       cwd=REPO, capture_output=True, text=True, timeout=300)
  if raw.returncode:
    raise SystemExit(f"jj file show failed: {raw.stderr[:200]}")
  path = OPS.parent / f"ops-501-MUT-{os.getpid()}.bend"
  if path.exists():
    raise SystemExit(f"{path.name} already exists -- a previous run was killed; remove it")
  path.write_text(raw.stdout)
  if path.read_text() != raw.stdout:
    path.unlink()
    raise SystemExit("staged copy does not match the revision -- refusing to measure")
  return path


def read_rows(path: pathlib.Path) -> dict:
  """The port's `s5_` rows, read with rebase-gate.py's `rows()`.

  The PREFIX filter is the gate's own (`ops-501-gate.sh:41` `grep '^s5_'`) and it is
  applied to the KEYS, not re-implemented as a line parser: ops.bend emits 284 rows in
  total and 101 of them are this unit's.
  """
  out = subprocess.run([str(REPO / "bin/bend"), str(path)], capture_output=True, text=True, cwd=REPO)
  return {k: v for k, v in _rg.rows(out.stdout).items() if k.startswith("s5_")}


def moved(base: dict, after: dict) -> list:
  return sorted(k for k in set(base) | set(after) if base.get(k) != after.get(k))


def main() -> int:
  if not OPS.exists():
    print("ops.bend is gone", file=sys.stderr)
    return 1
  live_before = OPS.read_bytes()
  oracle = subprocess.run([sys.executable, str(ORACLE)], capture_output=True, text=True, cwd=REPO)
  want = {k: v for k, v in _rg.rows(oracle.stdout).items() if k.startswith("s5_")}
  if not want:
    print(f"ops-501-mutate: the oracle printed no rows (rc={oracle.returncode}); "
          f"stderr={oracle.stderr.splitlines()[-1] if oracle.stderr else ''}", file=sys.stderr)
    return 1

  try:
    staged = stage()
  except SystemExit as e:
    print(f"ops-501-mutate: {e}", file=sys.stderr)
    return 1
  try:
    base = read_rows(staged)
    if len(base) != len(want):
      print(f"ops-501-mutate: the port answers {len(base)} rows and the oracle has "
            f"{len(want)} ({len(set(want) - set(base))} oracle-only, "
            f"{len(set(base) - set(want))} port-only), and "
            f"{len([k for k in set(base) & set(want) if base[k] != want[k]])} disagree. "
            f"Run ops-501-gate.sh and fix THAT before measuring anything: a mutation "
            f"table pointed at a disagreeing baseline measures the disagreement.", file=sys.stderr)
      return 1
    print(f"baseline: {len(base)} rows, the port and the oracle agree on every one")
    print(f"{'mutation':28} {'rows that moved':44} verdict")
    bad = 0
    for label, old, new, must in MUTATIONS:
      text = staged.read_text()
      if text.count(old) != 1:
        print(f"{label:28} {'PATTERN NOT UNIQUE (' + str(text.count(old)) + ')':44} NOT MEASURED")
        bad += 1
        continue
      staged.write_text(text.replace(old, new, 1))
      try:
        got = read_rows(staged)
        row_move = moved(base, got)
      finally:
        staged.write_text(text)
      if len(got) != len(base):
        print(f"{label:28} {'RUN BROKE (' + str(len(got)) + ' of ' + str(len(base)) + ' rows)':44} NOT A ROW MOVE")
        bad += 1
        continue
      ok = all(m in row_move for m in must)
      bad += 0 if ok else 1
      print(f"{label:28} {','.join(row_move) or '-':44} {'ok' if ok else 'MISSING ' + ','.join(must)}")
    print(f"\n{len(MUTATIONS) - bad}/{len(MUTATIONS)} mutations moved the rows they name")
    return 1 if bad else 0
  finally:
    staged.unlink(missing_ok=True)
    if OPS.read_bytes() == live_before:
      print("live ops.bend: byte-identical (nothing was patched)")
    else:
      print("live ops.bend: CHANGED -- another agent wrote during this run, and this "
            "harness did not write it", file=sys.stderr)


if __name__ == "__main__":
  sys.exit(main())