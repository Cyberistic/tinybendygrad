#!/usr/bin/env python3
"""prep-mutate.py -- the MUTATION TABLE for tinybendygrad/schedule/prepare.bend.

One edit per ported rule, re-run in the INTERPRETED lane (the native lane takes
minutes and adds nothing here -- the two lanes are byte-identical at baseline),
and the rows it moves are reported BY NAME.  A mutation that moves nothing is a
BLIND SPOT and is printed as one with its reason; it is never closed with a row.

Run:  python3 .agents/slop/prep-mutate.py
"""
import os, re, shutil, subprocess, sys, tempfile
import patch_not_apply as PNA
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, "tinybendygrad/schedule/prepare.bend")
ORACLE = os.path.join(ROOT, ".agents/slop/prepare-oracle.txt")

def rows(path):
  out = {}
  for l in open(path):
    l = l.rstrip("\n")
    if "=" in l and not l.startswith("=="):
      k, _, v = l.partition("=")
      out[k] = v
  return out

def run(src):
  """write `src` out, run it, return {row: value} or None if it does not compile"""
  d = tempfile.mkdtemp(dir=os.environ.get("TMPDIR", "/tmp"))
  shutil.copy(BEND, os.path.join(d, "prepare.bend"))
  # the file imports ./../uop/ops.bend etc., so it has to sit in place
  shutil.copy(os.path.join(d, "prepare.bend"), BEND)
  try:
    r = subprocess.run([os.path.join(ROOT, "bin/bend"), BEND],
                       capture_output=True, text=True, timeout=600)
    if r.returncode != 0 or "Error:" in r.stdout + r.stderr:
      return None
    return rows_txt(r.stdout)
  finally:
    shutil.copy(os.path.join(d, "prepare.bend"), BEND)
    shutil.rmtree(d, ignore_errors=True)

def rows_txt(out):
  d = {}
  for l in out.split("\n"):
    if "=" in l and not l.startswith("=="):
      k, _, v = l.rstrip("\n").partition("=")
      d[k] = v
  return d

BASE = open(BEND).read()
base = rows_txt(subprocess.run([os.path.join(ROOT, "bin/bend"), BEND],
                               capture_output=True, text=True, timeout=600).stdout)
oracle = rows(ORACLE)
print(f"baseline: {len(base)} rows, {sum(1 for k in base if base[k]!=oracle.get(k))} disagree with CPython")

MUTS = [
  ("M01", "pr_fma_table", 'O.OpsMULACC{}], Nil{}},  # 2 ADD', 'O.OpsMULACC{}, O.OpsCONST{}], Nil{}},  # 2 ADD',
   "`pm_fold_moved_after` rule 2's ALU op set GAINS CONST (it loses CONST's own pdict entry)"),
  ("M02", "pr_mop_table", 'O.PMEntry{2, [O.OpsEND{}], Nil{}}', 'O.PMEntry{2, [O.OpsSTORE{}], Nil{}}',
   "`pm_mops` rule 2 claims END where Python claims INDEX-or-AFTER"),
  ("M03", "pr_ear_table", 'O.PMEntry{10, [O.OpsREDUCE{}], Nil{}}',
   'O.PMEntry{10, [O.OpsWHERE{}], Nil{}}',
   "`earliest_rewrites` rule 10 is `split_reduceop` and claims REDUCE, not WHERE"),
  ("M04", "pr_inl_table", 'O.PMEntry{0, [O.OpsCALL{}], Nil{}}', 'O.PMEntry{0, [O.OpsEND{}], Nil{}}',
   "`pm_inline_calls` rule 0 is `resolve_function` and claims CALL"),
  ("M05", "pr_dsk_table", 'O.PMEntry{0, [O.OpsCOPY{}], [O.OpsSTAGE{}]}',
   'O.PMEntry{0, [O.OpsCOPY{}], [O.OpsSTAGE{}, O.OpsCONST{}]}',
   "`pm_disk_copy` rule 0's early_reject gains CONST"),
  ("M06", "pr_mcl_table", 'O.PMEntry{5, [O.OpsSTACK{}], [O.OpsINDEX{}]}',
   'O.PMEntry{5, [O.OpsSTACK{}], [O.OpsINDEX{}, O.OpsCONST{}]}',
   "`mop_cleanup` rule 5's early_reject gains CONST"),
  ("M07", "pr_wm_hop", 'Bool.or(O.GroupOp.movement(op), pr_wm_extra(op))',
   'O.GroupOp.movement(op)', "drop the INDEX/UNSHARD/BITCAST half of `walk_mop`'s hop set"),
  ("M08", "pr_wm_extra", 'Bool.or(Bool.or(pr_wm_is(op, O.OpsINDEX{}), pr_wm_is(op, O.OpsUNSHARD{})),\n          pr_wm_is(op, O.OpsBITCAST{}))',
   'pr_wm_is(op, O.OpsINDEX{})', "keep only INDEX of the three extra hop ops"),
  ("M09", "pr_wm_step", 'Bool.or(pr_wm_hop(O.Arena.op(ar, me)), O.op_is(ar, me, O.OpsAFTER{}))',
   'pr_wm_hop(O.Arena.op(ar, me))', "the spine's loop condition loses the AFTER half"),
  ("M10", "pr_wm_keep", 'match hop:\n    case True{}: a\n    case False{}: WmA.of(WmA.ar(a), n)',
   'match hop:\n    case True{}: WmA.of(WmA.ar(a), n)\n    case False{}: WmA.of(WmA.ar(a), n)',
   "the movement arm of the fold stops KEEPING the answer and takes the node"),
  ("M11", "pr_wm_keep_a", 'U32.is_eq(b, s0)', 'Bool.not(U32.is_eq(b, s0))',
   "INVERT `walk_mop`'s `is not u.src[0]` -- rebuild when it did NOT change"),
  ("M12", "pr_wm_pre", 'List.append(&2, U32, [me], acc)', 'List.append(&2, U32, acc, [me])',
   "append the spine node instead of prepending it (the reverse of `xs ++ ys`)"),
  ("M13", "pr_wm_step.go.of", 'WmSp{ar, O.Arena.src0(ar, me), pr_wm_pre(me, acc), False{}}',
   'WmSp{ar, O.Arena.src0(ar, me), acc, False{}}', "the spine stops pushing on the descent"),
  ("M14", "pr_wm_step.end.of", 'WmSp{ar, me, pr_wm_pre(me, acc), True{}}', 'WmSp{ar, me, acc, True{}}',
   "the spine never pushes the TERMINAL node"),
  ("M15", "pr_wm_mk", 'O.Arena.src_from(ar, n, 1)', 'O.Arena.src_to(ar, n, 1)',
   "`b.after(*u.src[1:])` reads srcs BEFORE index 1 -- the slice is inverted"),
  ("M16", "pr_wm_turn.of", 'case True{}: st\n    case False{}: pr_wm_step(',
   'case True{}: pr_wm_step(', "the `done` flag is ignored and the walk never stops early"),
  ("M17", "pr_pd_go", 'pr_pd_str(O.op_in(O.PMEntry.ops(e), op), k)', 'pr_pd_str(False{}, k)',
   "the `pdict` scan claims no rule for any op"),
  ("M19", "rej_str", 'Bool.pick(String, U32.is_zero(len_ops(rej)), "{}", braced(rej))',
   'Bool.pick(String, U32.is_zero(len_ops(rej)), "{}", ops_str(rej))',
   "an EMPTY early_reject prints `-` where the oracle prints `{}`"),
  ("M20", "braced", 'String.concat(["{", ops_str(rej), "}"])', 'String.concat(["", ops_str(rej), ""])',
   "the reject set loses its braces"),
  ("M21", "shape_str.go", 'String.join(show_sints.go(xs, Nil{}), "x")', 'String.join(show_sints.go(xs, Nil{}), ",")',
   "a shape's dim separator is `,` where CPython uses `x`"),
  ("M22", "sint_str.go", 'case O.SU{u}: U32.show(u)', 'case O.SU{u}: H.i64_text(H.i64_of_i32(u))',
   "a symbolic shape dim prints `hi:lo` where CPython prints the number"),
  ("M23", "dt_name.of", 'case None{}: "ERR"', 'case None{}: "void"',
   "an unresolvable dtype prints `void` where the gate prints `ERR`"),
  ("M24", "sig4", 'U32.show(O.Arena.nsrc(ar, self))', 'U32.show(O.Arena.nsrc(ar, O.Arena.src0(ar, self)))',
   "the four facts' nsrc reads src[0]'s own nsrc"),
  ("M25", "pr_wm_more", 'Bool.or(pr_wm_hop(O.Arena.op(ar, me)), O.op_is(ar, me, O.OpsAFTER{}))',
   'O.op_is(ar, me, O.OpsAFTER{})', "the spine descends on AFTER only and never on a hop op"),
  ("M26", "pr_wm_fold", 'case n <> t: pr_wm_fold(t, pr_wm_arm(n, a))',
   'case n <> t: pr_wm_fold(t, a)', "the fold visits no node at all"),
  ("M27", "pr_ear_table", 'O.PMEntry{20, [O.OpsSTORE{}], Nil{}}', 'O.PMEntry{20, [O.OpsSTORE{}], [O.OpsAFTER{}]}',
   "`fix_store_hazard`'s early_reject gains AFTER"),
  ("M28", "pr_fma_table", 'O.PMEntry{0, [O.OpsAFTER{}], [O.OpsSTORE{}]}', 'O.PMEntry{0, [O.OpsAFTER{}], Nil{}}',
   "`found_after`'s early_reject loses STORE"),
]

print()
print("| mut | def | what it changes | rows moved |")
print("| --- | --- | --- | --- |")
summary = []
for mid, name, find, repl, what in MUTS:
  if find not in BASE:
    print(PNA.pipe([mid, "`%s`" % name, what,
                    PNA.not_applied("anchor not found")], 4))
    summary.append((mid, name, what, [PNA.not_applied()]))
    continue
  shutil.copy(BEND, BEND + ".bak")
  open(BEND, "w").write(BASE.replace(find, repl, 1))
  try:
    r = subprocess.run([os.path.join(ROOT, "bin/bend"), BEND], capture_output=True,
                       text=True, timeout=600)
    out = r.stdout + r.stderr
    if "Error:" in out or r.returncode != 0:
      moved = ["<does not compile>"]
    else:
      got = rows_txt(r.stdout)
      moved = sorted(k for k in base if got.get(k) != base[k])
  except subprocess.TimeoutExpired:
    moved = ["<timeout>"]
  finally:
    shutil.move(BEND + ".bak", BEND)
  if not moved:
    moved = ["NOTHING (0)"]
  print(f"| {mid} | `{name}` | {what} | {len(moved) if '<' not in moved[0] and 'NOT' not in moved[0] else 0}"
        + ("" if len(moved) <= 8 else f" ({', '.join(moved[:8])} ...)") + " |")
  summary.append((mid, name, what, moved))

print()
print("=== FULL ROW LISTS ===")
for mid, name, what, moved in summary:
  print(f"{mid} {name}: {moved if len(moved) <= 12 else str(len(moved)) + ' rows'}")
