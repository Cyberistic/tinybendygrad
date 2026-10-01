#!/usr/bin/env python3
"""Mutation harness for tinybendygrad/mixin/elementwise.bend.

Each entry is a (name, old, new) edit that must appear EXACTLY ONCE in the source.
The harness applies it to a scratch copy, runs the gate's interpreted lane, and diffs
against the unmutated lane. What moves is the measurement; what does NOT move is the
more useful half -- it names what this gate is blind to.

Usage:
    .venv/bin/python .agents/slop/ew-mutate.py            # run all
    .venv/bin/python .agents/slop/ew-mutate.py M7         # run one
"""

import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REL = "tinybendygrad/mixin/elementwise.bend"
BEND = os.path.join(ROOT, "bin", "bend")

# (id, the edit, what it is testing)
MUTATIONS = [
  ("M1",
   "  T.tn_alu(Tw.a(j), op, [T.Tensor.u(Tw.b(j))])",
   "  T.tn_alu(Tw.a(j), op, [T.Tensor.u(Tw.a(j))])",
   "`lhs.alu(op, rhs)`'s operand order: naming `lhs` twice instead of `rhs`."),

  ("M2",
   "  ew_promote.at(ew_is_invalid(fx, b), W.dt_weak(dt), O.eq_dt(dt, wd), ar, t, od, wd)",
   "  ew_promote.at(ew_is_invalid(fx, b), True{}, O.eq_dt(dt, wd), ar, t, od, wd)",
   "`promote`'s FIRST conjunct, `t.dtype in dtypes.weaks`."),

  ("M3",
   "  ew_promote.at(ew_is_invalid(fx, b), W.dt_weak(dt), O.eq_dt(dt, wd), ar, t, od, wd)",
   "  ew_promote.at(False{}, W.dt_weak(dt), O.eq_dt(dt, wd), ar, t, od, wd)",
   "`promote`'s `t._uop.base.is_invalid` arm -- the \"invalid bool is weak const\" one."),

  ("M4",
   "  ew_promote.at(ew_is_invalid(fx, b), W.dt_weak(dt), O.eq_dt(dt, wd), ar, t, od, wd)",
   "  ew_promote.at(ew_is_invalid(fx, b), W.dt_weak(dt), False{}, ar, t, od, wd)",
   "`t.dtype == weak_dtype(out_dtype)`, the \"keep the weak CONST weak\" test."),

  ("M5",
   "  W.replace_in(cr, u, List.append(&2, U32, [O.Found.i(child)], O.Arena.src_from(ar, u, 1)))",
   "  W.replace_in(cr, u, List.append(&2, U32, O.Arena.src_from(ar, u, 1), [O.Found.i(child)]))",
   "`u.replace(src=(...)+u.src[1:])` -- the head goes back IN FRONT."),

  ("M5b",
   "  W.replace_in(cr, u, List.append(&2, U32, [O.Found.i(child)], O.Arena.src_from(ar, u, 1)))",
   "  W.replace_in(cr, u, List.append(&2, U32, [O.Found.i(child)], O.Arena.src_to(ar, u, 1)))",
   "`u.src[1:]` is `src_from` (drop the first k) and NOT `src_to` (keep the first k): "
   "on a one-src node `src_to(_, 1)` is the whole list, and the replacement gains a src."),

  ("M6",
   "  ew_ccast.go(ew_const_bare(dt), dt, O.UOp.new(ar, O.OpsCONST{}, Nil{}, O.APy{v}, O.TNone{}))",
   "  ew_ccast.go(False{}, dt, O.UOp.new(ar, O.OpsCONST{}, Nil{}, O.APy{v}, O.TNone{}))",
   "ops.py:637's \".cast folds away at exactly bool/weakint/weakfloat\"."),

  ("M7",
   "  ew_neg.go(S.Dt.is_bool(W.wk_dt(fx, T.Tensor.u(t))), t)",
   "  ew_neg.go(False{}, t)",
   "`neg`'s bool arm versus its int arm. Two-sided: M7b swaps the other way."),

  ("M7b",
   "  ew_neg.go(S.Dt.is_bool(W.wk_dt(fx, T.Tensor.u(t))), t)",
   "  ew_neg.go(True{}, t)",
   "the other direction, so neither arm can be satisfied by the other's graph."),

  ("M8",
   "def ew_pair(rev: Bool, a: T.Tensor, b: T.Tensor) -> Br:\n"
   "  match rev:\n"
   "    case True{}: Br{b, a}\n"
   "    case False{}: Br{a, b}",
   "def ew_pair(rev: Bool, a: T.Tensor, b: T.Tensor) -> Br:\n"
   "  match rev:\n"
   "    case True{}: Br{a, b}\n"
   "    case False{}: Br{b, a}",
   "`x, y = (self, y) if not reverse else (y, self)`."),

  ("M9",
   "  +l = ew_promote(T.Tensor.ar(ew_br_l(p)), ew_br_l(p), od)\n"
   "  Br{l, ew_promote(T.Tensor.ar(l), ew_br_r(p), od)}",
   "  +l = ew_promote(T.Tensor.ar(ew_br_l(p)), ew_br_l(p), od)\n"
   "  Br{l, ew_promote(T.Tensor.ar(ew_br_l(p)), ew_br_r(p), od)}",
   "the re-fold BETWEEN the two promotions: the second must read the arena the first grew."),

  ("M10",
   "  ew_binop(O.OpsCMPNE{}, ew_cast(t, S.boolean()), ECon{O.CBool{True{}}}, False{})",
   "  ew_binop(O.OpsCMPNE{}, t, ECon{O.CBool{True{}}}, False{})",
   "`logical_not` is `self.cast(dtypes.bool).ne(True)` -- the CAST is not optional."),

  ("M11",
   "  ew_alu2(O.OpsADD{}, ew_br_l(p), b)",
   "  ew_alu2(O.OpsSUB{}, ew_br_l(p), b)",
   "`sub` is an ADD over a negated rhs and NOT an `Ops.SUB`."),

  ("M12",
   "def ew_rebase(ar: O.Arena, +t: T.Tensor) -> T.Tensor:\n"
   "  T.tn_new(ar, T.Tensor.u(t))",
   "def ew_rebase(ar: O.Arena, +t: T.Tensor) -> T.Tensor:\n"
   "  T.tn_new(ar, T.Tensor.u(t))  # no-op",
   "CONTROL: a whitespace-only edit, which must move NOTHING."),
]


def run_gate(src_path):
  """Run the interpreted lane. Returns (ok, stdout+stderr)."""
  r = subprocess.run([BEND, src_path], cwd=ROOT, capture_output=True, text=True)
  return (r.returncode == 0 and "PROOFS FAIL" not in r.stdout), r.stdout + r.stderr


def main():
  want = sys.argv[1:]
  with open(os.path.join(ROOT, REL)) as f:
    base = f.read()

  ok, baseline = run_gate(os.path.join(ROOT, REL))
  if not ok:
    print("BASELINE DOES NOT RUN:\n" + baseline[:2000])
    return 1
  base_lines = baseline.splitlines()

  results = []
  for mid, old, new, what in MUTATIONS:
    if mid and want and mid not in want:
      continue
    n = base.count(old)
    if n != 1:
      results.append((mid, None, "EDIT MATCHES %d TIMES -- fix the mutation" % n, what))
      continue
    scratch_dir = os.path.join(ROOT, os.path.dirname(REL))
    with tempfile.NamedTemporaryFile("w", suffix=".bend", dir=scratch_dir, delete=False) as tf:
      tf.write(base.replace(old, new))
      tmp = tf.name
    try:
      ok, out = run_gate(tmp)
    finally:
      os.unlink(tmp)
    if not ok:
      results.append((mid, None, "DID NOT COMPILE / RUN", what))
      continue
    mut = out.splitlines()
    moved = [i for i, (a, b) in enumerate(zip(base_lines, mut)) if a != b]
    nmoved = abs(len(base_lines) - len(mut))
    label = ", ".join(base_lines[i].split("=")[0] for i in moved) or "(none)"
    results.append((mid, moved, "%d row(s): %s%s" % (len(moved), label,
                     "  +%d lines" % nmoved if nmoved > 0 else ""), what))

  width = max(len(r[0]) for r in results) + 2
  for mid, moved, summary, what in results:
    print("%-*s %s" % (width, mid, summary))
    print("%-*s   %s" % (width, "", what))
  return 0


if __name__ == "__main__":
  sys.exit(main())