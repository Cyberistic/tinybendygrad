# Diff the BEND gate against the CPython ORACLE.
#
# TWO RULES, both from agent-core and both learned the hard way in this repo:
#   * diff whole `name=value` lines, NEVER row NAMES -- a name-comparing
#     harness reported 0 for all 68 mutations in another unit;
#   * CHECK THE ORACLE'S EXIT PATH -- an oracle that emitted 0 rows and exited 1
#     while the gate printed 432 rows. So this file re-runs the oracle, refuses a
#     non-zero exit, and refuses a row count it did not expect.
#
# The oracle's section 8 emits rows named EXACTLY as the gate's rows, so the
# comparison is a plain name lookup on both sides. That replaced a 23-entry alias
# table that left 87 rows uncompared, which is not a gate.
#
# The rows the oracle cannot answer are PORT TAGS and are listed, with a reason,
# in PORT_TAGS below. A row in PORT_TAGS is checked by the mutation table and by
# nothing else, and saying so is the point.
#
#   .venv/bin/python .agents/slop/objc/objc_diff.py
import re, subprocess, sys

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
PY = ROOT + "/.venv/bin/python"
ORACLE = ROOT + "/.agents/slop/objc/objc_oracle.py"
BEND = ROOT + "/tinybendygrad/runtime/support/objc.bend"
MIN_ORACLE_ROWS = 200

# a bend CT_* tag is the same SLOT as a ctypes class name, so a list row compares
# after this map. Anything not in the map must match literally, which is what
# makes a NEW list row fail loudly instead of passing by luck.
# CPYTHON TYPE NAME -> BEND CT_* TAG. ONE DIRECTION, names to tags: the numeric
# keys an earlier version had (`"5": "c_bool"`) turned every ordinary count in the
# gate into a type name and made 22 rows disagree for no reason at all. A scalar
# is mapped ONLY when it is literally a type name, so a count stays a count.
KIND = {"id_": "1", "c_ulong": "4", "c_int": "2", "c_bool": "5", "c_char_p": "6",
        "ChildFake": "7", "TwoArgFake": "7", "NSCoder": "3"}

# PORT TAGS: rows the ORACLE CANNOT ANSWER, each with its reason. A row here is
# checked by the mutation table and by nothing else, and that is the claim.
#
#   sel_ix_commit_is_1, sel_ix_absent_is_0, shape_send_sel_ix,
#   shape_send_sel_ix_third -- a selector's REGISTRY INDEX.  In cpython it is an
#       ADDRESS, which is ASLR-dependent and not comparable.  What IS comparable
#       -- that a name is PRESENT -- is `sel_hit_commit_true`, which is compared.
#   shape_send_recv_cls, shape_send_recv_cls_in_three -- the clsmeth receiver is a
#       live CLASS OBJECT's `_objc_class_` in cpython and a U32 tag here.
#   shape_send_recv_inst -- compared (0xAAAA == 43690), so NOT here.
#   meth_args_inst_is_not_8 -- the substituted slot against the ctypes `str`
#       `'instancetype'`; `meth_args_inst_third` already compares the slot itself.
#   shape_at_0_present / shape_at_2_absent / shape_at_2_is_MISSING -- `List.get`
#       has no cpython counterpart; the BOUNDS are compared by `inh_none`,
#       `msg_argc_none` and `sel_names_len_5`.
PORT_TAGS = {
  "sel_ix_commit_is_1", "sel_ix_absent_is_0", "shape_send_sel_ix", "shape_send_sel_ix_third",
  "shape_send_recv_cls", "shape_send_recv_cls_in_three",
  "meth_args_inst_is_not_8", "meth_ret_inst_becomes_class",
  "shape_at_0_present", "shape_at_2_absent", "shape_at_2_is_MISSING",
}

def run_oracle():
  r = subprocess.run([PY, ORACLE], capture_output=True, text=True, cwd=ROOT)
  if r.returncode != 0:
    print(f"ORACLE EXITED {r.returncode} -- the gate is BLIND, not passing"); print(r.stderr[-2000:]); sys.exit(1)
  out = {}
  for line in r.stdout.splitlines():
    if "=" not in line or line.startswith("#"): continue
    k, _, v = line.partition("=")
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k): out[k] = v
  if len(out) < MIN_ORACLE_ROWS:
    print(f"ORACLE EMITTED {len(out)} ROWS, expected >= {MIN_ORACLE_ROWS} -- the recorder stub is broken")
    sys.exit(1)
  return out

def main():
  o = run_oracle()
  r = subprocess.run([ROOT + "/bin/bend", BEND], capture_output=True, text=True, cwd=ROOT)
  if r.returncode != 0:
    print(f"BEND LANE EXITED {r.returncode}"); print(r.stderr[-3000:]); sys.exit(1)
  if not r.stdout.rstrip().endswith("objc-done=1"):
    print("NO DONE MARKER -- the lane did not start, or it broke"); sys.exit(1)
  got, want = {}, {}
  for line in r.stdout.splitlines():
    if "py=[" not in line: continue
    nm = line.split(" = [", 1)[0].strip()
    g, w = line.split(" = [", 1)[1].rsplit("]   py=[", 1)
    got[nm], want[nm] = g, w.rstrip("]")
  print(f"oracle rows={len(o)}   gate rows with py={len(got)}")

  # (1) SELF: the bend side must equal its own py= half. This caught THREE real
  # port bugs today -- getsel_ix answering 1 for an absent name, msg_argc using
  # the tail of a `d <> r` pattern, and Idr.own emitting only the msgSend -- and
  # TWO hand-typed expectations that were wrong about the fixture.
  self_bad = [k for k in got if got[k] != want[k]]
  for k in self_bad: print(f"  SELF-MISMATCH {k}: bend=[{got[k]}] py=[{want[k]}]")

  # (2) ORACLE: the py= half must be a real oracle row of the SAME name, after
  # the kind map. An unmatched row is an error, not a pass.
  checked, bad, unmatched = 0, [], []
  for k, py in want.items():
    ov = o.get(k)
    if ov is None:
      if k not in PORT_TAGS: unmatched.append(k)
      continue
    if ov.startswith("[") and ov.endswith("]"): ov = ov[1:-1]
    if ov == "[]": ov = ""
    if k in PORT_TAGS:
      # the tag is the port's own, so only the SHAPE is comparable.
      if ov.count(",") != py.count(","):
        bad.append((k, py, ov)); print(f"  SHAPE DISAGREES {k}: py=[{py}] cpython=[{ov}]")
      checked += 1; continue
    ov = ",".join(KIND.get(x, x) for x in ov.split(",")) if "," in ov else KIND.get(ov, ov)
    py2 = ",".join(KIND.get(x, x) for x in py.split(",")) if "," in py else py
    checked += 1
    if py2 != ov: bad.append((k, py, ov)); print(f"  ORACLE DISAGREES {k}: py=[{py2}] cpython=[{ov}]")
  print(f"self-mismatches: {len(self_bad)}   oracle disagreements: {len(bad)}   "
        f"compared by name: {checked}   PORT TAGS: {len(PORT_TAGS & set(want))}   "
        f"NO ORACLE ROW: {len(unmatched)}")
  if unmatched: print(f"  NOT AN ORACLE ROW AND NOT A DECLARED PORT TAG: {', '.join(unmatched)}")
  ok = not self_bad and not bad and not unmatched
  print("ALL PROOFS CHECK" if ok else "GATE FAILS")
  sys.exit(0 if ok else 1)

main()
