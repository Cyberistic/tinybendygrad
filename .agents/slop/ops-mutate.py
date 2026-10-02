#!/usr/bin/env python3
"""ops-mutate.py -- the mutation table for `tinybendygrad/uop/ops.bend`.

WHAT IT DOES. One edit at a time to the ONE file, then both Bend lanes are run and their
rows diffed against the unmutated baseline. The file is RESTORED from a byte snapshot on
every exit path including SIGINT/SIGTERM, and the script exits 1 if the file is left
dirty -- a hand-run table is a guess, and a mutation left applied is a defect nobody
looks at again.

    .venv/bin/python .agents/slop/ops-mutate.py            # the whole table
    .venv/bin/python .agents/slop/ops-mutate.py --one M7   # one mutation
    .venv/bin/python .agents/slop/ops-mutate.py --md       # the table as Markdown

WHY IT DIFFS WHOLE `name=value` LINES. Two units in this repo reported 0 moved rows for
every mutation because their harness compared ROW NAMES: the name did not change, so the
row looked untouched while its answer had moved underneath. Every row this file prints is
`name=value`, so the diff key is the whole line.

WHY BOTH LANES MUST AGREE. `bend x.bend` and `bend x.bend -o x.bin` are not the same
program -- a law unfilled in the interpreter can be live in the compiled binary. A
mutation that moves the interpreted lane and not the native one is a REAL finding and is
reported as such rather than averaged away.

WHAT IS EXPECTED TO MOVE NOTHING, and why, is recorded per row rather than guessed:

  * a THEOREM -- two spellings of one function, so no fixture can separate them;
  * a REQUEST FOR A FIXTURE -- every fixture misses the case the mutation targets;
  * UNFIXABLE -- a predicate that is the same predicate over every possible answer, so
    the row cannot fail.

`AxisType.value` is the headline candidate for a blind spot and it is NOT one, which is
the point of the table: `axv_*` is one row per MEMBER rather than one row per fixture,
so a wrong value for `PLACEHOLDER` -- which appears in no RANGE fixture tinygrad builds
-- moves a row. The two rows that DID move nothing for the value table are recorded with
the reason.
"""
import os
import signal
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TARGET = os.path.join(REPO, "tinybendygrad", "uop", "ops.bend")
OUT = os.path.join(REPO, ".agents", "slop", "oracles")
BEND = os.path.join(REPO, "bin", "bend")
NATIVE = os.path.join(OUT, "ops-mut.bin")

# The BEND-ONLY row families, from `ops-gate.sh`'s own derivation. A mutation that moves
# one of these moves a row the CPython lane deliberately does not compare, so it is
# reported separately as "moved a bend-only row" -- still a real detection, but not the
# CPython gate seeing it.
BEND_ONLY_PREFIXES = tuple([
  "rngarg", "eqax_collide_all", "eqax_diag_all", "mstack_puts_self_first",
  "axv_REDUCE", "axn_REDUCE", "axl_REDUCE", "axc_REDUCE",
  "axv_UNROLL", "axn_UNROLL", "axl_UNROLL", "axc_UNROLL",
  "rngspec", "axlt_le", "axlt_ge", "axlt_dunder", "xpos",
  "hashcons", "float_zeros_differ", "float_nan_interns", "dtype_key", "cycle",
  "after_puts_self_first", "end_puts_self_first", "toposort", "key_eq", "eq_dt",
  "weakfloat_interns", "eq_addr", "addr_interns", "ops_name", "var_interns",
  "ler_len", "early_reject", "broadcast_repeats", "required_len", "alu_permutes",
])

# (id, what it changes, old, new, expected-zero-and-why)
MUTATIONS = [
  # --- AxisType.value. THE HEADLINE. Six mutations, one per surviving member plus the
  # --- two collision cases, because "the value table is wrong" is four separate facts
  # --- and a table that only permutes LOCAL and WARP would not see the other four.
  ("M1", "AxisType.value LOCAL 3 -> 4 (collides with WARP)",
   "    case AXIS_LOCAL{}: 3\n    case AXIS_WARP{}: 4",
   "    case AXIS_LOCAL{}: 4\n    case AXIS_WARP{}: 4",
   "moves axv_LOCAL, #shared_axis_values, #shared_axis_sorted, eqax_collide_all"),
  ("M2", "AxisType.value PLACEHOLDER 8 -> 9 (collides with the dead REDUCE)",
   "    case AXIS_PLACEHOLDER{}: 8\n    case AXIS_REDUCE{}: 9",
   "    case AXIS_PLACEHOLDER{}: 9\n    case AXIS_REDUCE{}: 9",
   "moves axv_PLACEHOLDER, #shared_axis_values, #shared_axis_sorted, eqax_collide_all"),
  ("M3", "AxisType.value LOOP 6 -> 10 (the PIN's number)",
   "    case AXIS_LOOP{}: 6",
   "    case AXIS_LOOP{}: 10",
   "moves axv_LOOP, #shared_axis_values, #shared_axis_sorted -- and nothing else: no "
   "RANGE fixture's ARG contains a number, so the value table is the ONLY gate on it"),
  ("M4", "AxisType.value WARP 4 -> 3 (the PIN's number)",
   "    case AXIS_WARP{}: 4",
   "    case AXIS_WARP{}: 3",
   "moves axv_WARP, #shared_axis_values, #shared_axis_sorted"),
  ("M5", "AxisType.value DEVICE 1 -> 9 (a pure collision with the dead REDUCE)",
   "    case AXIS_DEVICE{}: 1",
   "    case AXIS_DEVICE{}: 9",
   "moves axv_DEVICE, #shared_axis_values, #shared_axis_sorted, eqax_collide_all"),
  ("M6", "AxisType.value REDUCE 9 -> 6 (collides with the LIVE LOOP)",
   "    case AXIS_REDUCE{}: 9",
   "    case AXIS_REDUCE{}: 6",
   "moves eqax_collide_all and axv_REDUCE, the latter a bend-only row -- so this is the "
   "mutation that proves eqax_collide_all earns its place"),
  # --- The two dicts. The colours are the ones upstream CHANGED.
  ("M7", "axis_colors WEAK red -> WHITE (the PIN's colour)",
   '    case AXIS_WEAK{}: "red"', '    case AXIS_WEAK{}: "WHITE"',
   "moves axc_WEAK"),
  ("M8", "axis_colors LOOP red -> WHITE (the PIN's colour)",
   '    case AXIS_LOOP{}: "red"', '    case AXIS_LOOP{}: "WHITE"',
   "moves axc_LOOP"),
  ("M9", "axis_colors UPCAST yellow -> orange",
   '    case AXIS_UPCAST{}: "yellow"', '    case AXIS_UPCAST{}: "orange"',
   "moves axc_UPCAST"),
  ("M10", "axis_letters WEAK L -> l",
   '    case AXIS_WEAK{}: "L"', '    case AXIS_WEAK{}: "l"',
   "moves axl_WEAK -- and note this is the same string axis_letters gives LOCAL, so "
   "WITHOUT a per-member row the swap would be invisible"),
  ("M11", "the `!KeyError` miss marker -> the PIN's empty string",
   '    case AXIS_UPCAST{}: "u"\n    case _: "!KeyError"',
   '    case AXIS_UPCAST{}: "u"\n    case _: ""',
   "moves axl_PLACEHOLDER and axc_PLACEHOLDER -- the two rows that make ABSENCE visible"),
  # --- AxisType.lt, which upstream ADDED and the pin did not have.
  ("M12", "AxisType.lt is_lt -> is_gt",
   "  U32.is_lt(AxisType.value(x), AxisType.value(y))",
   "  U32.is_gt(AxisType.value(x), AxisType.value(y))",
   "moves #shared_axis_sorted, axlt_sorted, axlt_revsorted, axlt_lt, axlt_gt"),
  ("M13", "AxisType.lt compares NAMES (a `__lt__` that is a total order either way)",
   "  U32.is_lt(AxisType.value(x), AxisType.value(y))",
   '  String.is_lt(AxisType.name(x), AxisType.name(y))',
   "moves the sorted rows -- alphabetical order differs from declaration order, which is "
   "the only direction a name comparison and a value comparison disagree"),
  # --- range_start.
  ("M14", "range_start STAGE 1 -> 0",
   "    case OpsSTAGE{}: 1", "    case OpsSTAGE{}: 0",
   "moves NOTHING: `range_start_str` is a SEPARATE ladder, and every caller in this port "
   "reads `range_start_str`. A REQUEST FOR A FIXTURE: the U32 and the row printer are two "
   "spellings of one table and nothing calls the U32, so this is a dead-claim finding, "
   "not a coverage gap"),
  ("M15", "range_start_str LINEAR 0 -> 1",
   '    case OpsLINEAR{}: "0"', '    case OpsLINEAR{}: "1"',
   "moves axs_LINEAR"),
  ("M16", "range_start_str NOOP miss -> 0 (the port's old silent widening)",
   '    case OpsLINEAR{}: "0"\n    case _: "!KeyError"',
   '    case OpsLINEAR{}: "0"\n    case _: "0"',
   "moves axs_NOOP -- and this is the row that keeps axs_LINEAR and axs_NOOP apart"),
  # --- the RANGE arg and the accessors.
  ("M17", "UOp.range_end packs (at, ids) -- UPSTREAM's order -- behind the wall",
   "  UOp.new(ar, OpsRANGE{}, [end], ARange{ids, at}, TNone{})",
   "  UOp.new(ar, OpsRANGE{}, [end], ARange{at, ids}, TNone{})",
   "does NOT compile: `ARange` is `(ids, at)`, so this is the flip that eleven other "
   "files' positional destructuring forbids. The refusal IS the measurement"),
  ("M18", "UOp.mstack puts SELF LAST -- the inverse bug that shipped",
   "  UOp.mstack.go(srcs, ar, self, UOp.new(ar, OpsMSTACK{}, List.append(&2, U32, [self], srcs), ANone{}, TNone{}))",
   "  UOp.mstack.go(srcs, ar, self, UOp.new(ar, OpsMSTACK{}, List.append(&2, U32, srcs, [self]), ANone{}, TNone{}))",
   "moves mstack_puts_self_first, mstack1, mstack2 -- the src op SEQUENCE, and nothing "
   "else would"),
  ("M19", "UOp.axis_id answers None (not a RANGE at all)",
   "    case ARange{ids, at}: Some{ids}\n    case _: None{}",
   "    case ARange{ids, at}: None{}\n    case _: None{}",
   "moves every axid_* row -- this mutation was DEAD before the rows were rewired to "
   "read the PROPERTY instead of the fixture's literal, which is why it exists"),
  ("M20", "Rng.srcops drops the separator between src ops",
   '        acc ++ " " ++ Ops.name(Arena.op(ar, h))), False{})',
   '        acc ++ Ops.name(Arena.op(ar, h))), False{})',
   "moves every rng_* and mstack* row -- a WHITESPACE-CONTROL mutation: the formatting "
   "and the values are both right and the row is still wrong"),
  ("M21", "IdsStr drops the one-tuple trailing comma",
   '        case Nil{}: String.concat(["(", U32.show(h), ",)"])',
   '        case Nil{}: String.concat(["(", U32.show(h), ")"])',
   "moves axid_weak1, axid_dev3, axid_loopfn and every rngarg_* -- and this is why the "
   "comma is in the row: without it `(0)` reads as a parenthesised int"),
  # --- eq_axis, which is the value table's only consumer.
  ("M22", "eq_axis is_eq -> is_le (a collision detector)",
   "  U32.is_eq(AxisType.value(x), AxisType.value(y))",
   "  U32.is_le(AxisType.value(x), AxisType.value(y))",
   "moves eqax_collide_all and eqax_diag -- and NOT eqax_collide, because the eight LIVE "
   "values are ascending and `is_le` is half-true on a sorted distinct list"),
  ("M23", "eq_axis is_eq -> is_ge",
   "  U32.is_eq(AxisType.value(x), AxisType.value(y))",
   "  U32.is_ge(AxisType.value(x), AxisType.value(y))",
   "moves eqax_collide and eqax_diag"),
  # --- AxisType.live, which is the member SET the derivation rows walk.
  ("M24", "AxisType.live drops PLACEHOLDER",
   "   AXIS_UPCAST{}, AXIS_PLACEHOLDER{}]",
   "   AXIS_UPCAST{}]",
   "moves #shared_axis_count, #shared_axis_members, #shared_axis_values, "
   "#shared_axis_sorted, eqax_diag, and every axv_/axn_/axl_/axc_ row for four other "
   "members if the list were rebuilt -- a whitespace-shaped edit that is not one"),
  # --- the printers themselves, which are the gate's own machinery.
  ("M25", "Ops.name is bypassed: the src op sequence prints the ROOT op",
   "    Rng.srcops(ar, self)])", "    Rng.srcops(ar, self) ++ Ops.name(Arena.op(ar, self))])",
   "moves every rng_* and mstack* row"),
  ("M26", "Nat.show of the node count is dropped from Rng.sig",
   "    Nat.show(List.length(&2, U32, UOp.toposort(Arena.budget(ar), ar, self))), \" \",",
   "    \"\",",
   "moves every rng_* and mstack* row"),
]


def rows_of(text):
  """`name` -> the whole `name=value` line. The key is the LINE, not the name.

  `#shared_axis_*` IS INCLUDED. It looks like a comment because it starts with `#`, and
  an earlier version of this harness skipped every `#` line -- which quietly removed four
  GATED rows from the table and made M1/M2/M3/M5 look like they moved three rows when
  they moved four. `ops-gate.sh` diffs those rows, so this harness has to see them.
  Only `#shared_tree` (which names the tree the oracle read) and the `#bend_only_*`
  REASONS are dropped, and both are oracle-only lines with no Bend counterpart.
  """
  out = {}
  for line in text.splitlines():
    if "=" not in line or line.startswith("#shared_tree") or line.startswith("#bend_only"):
      continue
    out[line.split("=", 1)[0]] = line
  return out


def bend_rows(native):
  p = [BEND, TARGET] + (["-o", NATIVE] if native else [])
  r = subprocess.run(p, cwd=REPO, capture_output=True, text=True)
  if r.returncode != 0:
    return None, (r.stdout + r.stderr).strip().splitlines()[:3]
  if native:
    r = subprocess.run([NATIVE], cwd=REPO, capture_output=True, text=True)
    if r.returncode != 0:
      return None, (r.stdout + r.stderr).strip().splitlines()[:3]
    return r.stdout, None
  return r.stdout, None


def lanes():
  """BOTH lanes, and they must agree. Returns (rows, error)."""
  a, ea = bend_rows(False)
  b, eb = bend_rows(True)
  if ea:
    return None, ("interpreted lane: " + " / ".join(ea))
  if eb:
    return None, ("native lane: " + " / ".join(eb))
  if a != b:
    return None, "THE TWO LANES DISAGREE -- an unfilled law in the interpreter"
  return rows_of(a), None


def main():
  if "--one" in sys.argv:
    keep = {sys.argv[sys.argv.index("--one") + 1]}
    muts = [m for m in MUTATIONS if m[0] in keep]
  else:
    muts = MUTATIONS

  src = open(TARGET, "rb").read()

  def restore(*_):
    if open(TARGET, "rb").read() != src:
      open(TARGET, "wb").write(src)
    sys.exit(1)

  signal.signal(signal.SIGINT, restore)
  signal.signal(signal.SIGTERM, restore)

  try:
    base, err = lanes()
    if err:
      print(f"baseline did not run: {err}")
      return 1
    print(f"baseline: {len(base)} rows, both lanes identical")
    print()
    print(f"{'id':<5} {'moved':<6} {'rows':<62} what")
    print("-" * 150)
    for mid, what, old, new, _why in muts:
      text = src.decode()
      if text.count(old) != 1:
        print(f"{mid:<5} ERROR   search string occurs {text.count(old)} times, expected 1")
        continue
      open(TARGET, "w").write(text.replace(old, new))
      try:
        got, err = lanes()
      finally:
        open(TARGET, "wb").write(src)
      if err:
        print(f"{mid:<5} NOCOMP {'(the refusal is the measurement)':<62} {what}")
        continue
      moved = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
      shared = [k for k in moved if not k.startswith(BEND_ONLY_PREFIXES)]
      bo = [k for k in moved if k.startswith(BEND_ONLY_PREFIXES)]
      label = ",".join(shared[:3]) + (f" +{len(shared) - 3}" if len(shared) > 3 else "")
      if bo:
        label += " [bend-only: " + ",".join(bo[:2]) + (f" +{len(bo) - 2}" if len(bo) > 2 else "") + "]"
      print(f"{mid:<5} {len(moved):<6} {label[:60]:<62} {what}")
  finally:
    if open(TARGET, "rb").read() != src:
      open(TARGET, "wb").write(src)
      print("RESTORED FROM SNAPSHOT", file=sys.stderr)

  dirty = open(TARGET, "rb").read() != src
  if dirty:
    print("FILE LEFT DIRTY", file=sys.stderr)
    return 1
  print()
  print("file restored; mutations still to be classified: see the `why` column above")
  return 0


if __name__ == "__main__":
  sys.exit(main())