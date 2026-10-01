# MUT -- the mutation driver for tinybendygrad/codegen/{kernel,rewriter}.bend.
#
# Applies ONE textual edit to a COPY of a file, re-checks it, and diffs the gate
# against the clean one. `rows moved` is the set difference of the two gates, so it
# names rows by the property they test and not by the def that computes them.
#
#   python3 .agents/slop/mut/../codegen-mut.py          # both files
#   python3 .agents/slop/notes/codegen-mut.py rewriter  # one file
#
# A mutation that does not compile is reported as COMPILE FAIL and is NOT a silent
# pass: the point of the table is that each entry either moves rows or is the reason
# a row exists.
import os, re, subprocess, sys, tempfile, shutil

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
BEND = os.path.join(ROOT, "bin", "bend")

MUTATIONS = {
  "rewriter.bend": [
    # M1 the reported inversion: ru_ret's two arms swapped. `reduce_parented` empty
    # must answer src[0], NOT a REDUCE with the parented tail.
    ("ru_ret arm order", "    case True{} : Rew{ar, rw_src0(ar, self)}\n    case False{}: rew_hit(O.UOp.new(ar, rw_op(ar, self), List.append(&2, U32, [rw_src0(ar, self)], ps),\n                                         rw_arg(ar, self), rw_tag(ar, self)))",
                        "    case True{} : rew_hit(O.UOp.new(ar, rw_op(ar, self), List.append(&2, U32, [rw_src0(ar, self)], ps),\n                                         rw_arg(ar, self), rw_tag(ar, self)))\n    case False{}: Rew{ar, rw_src0(ar, self)}"),
    # M2 `r.src[0]` read as `r.src[1:]` -- the RANGE BOUND becomes the RANGE's tail.
    ("ret * r.src[0] -> ret * r.src[1:]", "ru_scale.of(ru_add(rop), ru_mul(rop), r, rw_src0(ar, s), ar)",
                                              "ru_scale.of(ru_add(rop), ru_mul(rop), r, rw_src(ar, s, 1), ar)"),
    # M3 `range_start` for LINEAR: 0 -> 1.
    ("LINEAR offset 0 -> 1", "            rw_is(ar, i, O.OpsREDUCE{}), rw_is(ar, i, O.OpsCALL{}))",
                             "            rw_is(ar, i, O.OpsREDUCE{}), Bool.or(rw_is(ar, i, O.OpsCALL{}), rw_is(ar, i, O.OpsLINEAR{})))"),
    # M4 dedup drops the HEAD instead of the later duplicate.
    ("dd_put keeps the later", "def dd_put.of(dup: Bool, x: U32, ys: List<&2, U32>) -> List<&2, U32>:\n  match dup:\n    case True{} : ys\n    case False{}: List.append(&2, U32, ys, [x])",
                               "def dd_put.of(dup: Bool, x: U32, ys: List<&2, U32>) -> List<&2, U32>:\n  match dup:\n    case True{} : List.append(&2, U32, ys, [x])\n    case False{}: ys"),
    # M5 the src[:off] head dropped -- the bug `fr_grow_same`/`fr_en2_shape` caught.
    ("fr_head drops src0", "def fr_head.of(zero: Bool, ar: O.Arena, self: U32) -> List<&2, U32>:\n  match zero:\n    case True{} : Nil{}\n    case False{}: [rw_src0(ar, self)]",
                          "def fr_head.of(zero: Bool, ar: O.Arena, self: U32) -> List<&2, U32>:\n  match zero:\n    case True{} : Nil{}\n    case False{}: Nil{}"),
    # M6 the wall arm answers Some: `rw_ranges` on a non-RANGE pretends to be empty.
    ("rw_ranges non-RANGE -> Some", "def rw_ranges.go(is_range: Bool, +ar: O.Arena, i: U32) -> Maybe<&2, List<&2, U32>>:\n  match is_range:\n    case True{} : Some{[i]}\n    case False{}: None{}",
                                      "def rw_ranges.go(is_range: Bool, +ar: O.Arena, i: U32) -> Maybe<&2, List<&2, U32>>:\n  match is_range:\n    case True{} : Some{[i]}\n    case False{}: Some{Nil{}}"),
    # M7 `symbolic`'s 123 rules folded into the table length.
    ("rc_composite loses symbolic", "  U32.add(t_rc_len(), symbolic_len())", "  t_rc_len()"),
    # M8 the rop guard widened: POW is NOT in {ADD, MAX, MUL} (simplify.py:88).
    ("ru_rop_ok adds POW", "def ru_rop_ok(+rop: O.Op) -> Bool:\n  Bool.or(Bool.or(ru_add(rop), ru_max(rop)), ru_mul(rop))",
                            "def ru_rop_ok(+rop: O.Op) -> Bool:\n  Bool.or(Bool.or(ru_add(rop), ru_max(rop)), Bool.or(ru_mul(rop), O.eq_op(rop, O.OpsPOW{})))"),
  ],
  "kernel.bend": [
    # M1 `ctx[0] += 1` then `slot=ctx[0]-1` written as `slot = n - 1`.
    ("kn_np slot n -> n-1", "NP{kn_np.go(fresh, ar, i, n), kn_np.next(fresh, n)}", "NP{kn_np.go(fresh, ar, i, U32.sub(n, 1)), kn_np.next(fresh, n)}"),
    # M2 the increment dropped: every PARAM gets the same slot.
    ("kn_np.next no increment", "def kn_np.next(fresh: Bool, n: U32) -> U32:\n  match fresh:\n    case True{} : U32.add(n, 1)\n    case False{}: n",
                                 "def kn_np.next(fresh: Bool, n: U32) -> U32:\n  match fresh:\n    case True{} : n\n    case False{}: n"),
    # M4 `pm_cast_float_alu`'s op set loses RECIPROCAL -- one of the five arms.
    ("kn_alu_is loses RECIPROCAL", "    case O.OpsRECIPROCAL{}: True{}\n    case _: False{}", "    case _: False{}"),
    # M5 `pm_alloc_to_buf` does not change the op.
    ("ab_new keeps ALLOC", "def ab_new(+ar: O.Arena, +self: U32) -> Ker:\n  ker_hit(O.UOp.new(ar, O.OpsBUFFER{}, O.Arena.srcs(ar, self), kn_arg(ar, self), kn_tag(ar, self)))",
                           "def ab_new(+ar: O.Arena, +self: U32) -> Ker:\n  Ker{ar, self}"),
    # M6 rule 3's INS arm read as reachable: stage_pr3 goes back to 3.
    ("tp_stage reads the INS", "  tp_stage.w1(Nat.is_eq(U32.to_nat(kn_nsrc(ar, self)), 1n),\n              Nat.is_eq(U32.to_nat(kn_nsrc(ar, self)), 2n),\n              Nat.is_eq(U32.to_nat(kn_nsrc(ar, self)), 3n))",
                               "  tp_stage.w1(Nat.is_eq(U32.to_nat(kn_nsrc(ar, self)), 1n),\n              Bool.and(Nat.is_eq(U32.to_nat(kn_nsrc(ar, self)), 2n), k_is_ins(ar, self)),\n              Nat.is_eq(U32.to_nat(kn_nsrc(ar, self)), 3n))"),
    # M7 the arity test dropped: every PROGRAM is stage 1.
    ("tp_stage arity always one", "  tp_stage.w1(Nat.is_eq(U32.to_nat(kn_nsrc(ar, self)), 1n),", "  tp_stage.w1(Bool.and(True{}, Nat.is_eq(U32.to_nat(kn_nsrc(ar, self)), 3n)),"),
    # M8 the 12th config flag: cfg and cfg_ctx collapse onto each other.
    ("cfg_ctx_len 14 -> 12", "def cfg_ctx_len() -> U32:\n  14", "def cfg_ctx_len() -> U32:\n  12"),
    # M9 the acc threaded backwards: lw_miss_nsrc sees a one-src node.
    ("lw_map drops the head", "def lw_map.go(ss: List<&2, U32>, +subs: List<&2, Sub>) -> List<&2, U32>:\n  match ss:\n    case Nil{}   : Nil{}\n    case s <> t  : List.append(&2, U32, lw_map.go(t, subs), [lw_find(subs, s)])",
                          "def lw_map.go(ss: List<&2, U32>, +subs: List<&2, Sub>) -> List<&2, U32>:\n  match ss:\n    case Nil{}   : Nil{}\n    case s <> t  : lw_map.go(t, subs)"),
    # M10 `lw_find`'s arms swapped: the hit returns the KEY not the VALUE.
    ("lw_find.hit arms swapped", "def lw_find.hit(same: Bool, s: Sub, hold: U32) -> U32:\n  match same:\n    case True{} : Sub.now(s)\n    case False{}: hold",
                                "def lw_find.hit(same: Bool, s: Sub, hold: U32) -> U32:\n  match same:\n    case True{} : hold\n    case False{}: Sub.now(s)"),
    # M11 `build_range_map`'s axis_type conjunct dropped -- counts EVERY RANGE.
    ("kn_is_expand0 drops axis_type", "  Bool.and(kn_is(ar, i, O.OpsRANGE{}), kn_unroll.at(F.UOp.axis_type(ar, i)))",
                                      "  Bool.and(kn_is(ar, i, O.OpsRANGE{}), True{})"),
    # M12 `ret is not uop` inverted: every rewrite is kept.
    ("ker_self inverted", "def ker_self.of(drop: Bool, +r: Ker) -> Ker:\n  match drop:\n    case True{} : Ker{Ker.ar(r), 0}\n    case False{}: r",
                          "def ker_self.of(drop: Bool, +r: Ker) -> Ker:\n  match drop:\n    case True{} : r\n    case False{}: Ker{Ker.ar(r), 0}"),
  ],
}

def run_gate(path):
  """The gate's rows, or None if it does not compile."""
  chk = subprocess.run([BEND, path, "--check-only"], capture_output=True, text=True)
  if "ALL PROOFS CHECK" not in chk.stdout:
    return None
  got = subprocess.run([BEND, path], capture_output=True, text=True)
  if got.returncode != 0:
    return None
  d = {}
  for line in got.stdout.strip().split("\n"):
    if "=" in line:
      k, v = line.split("=", 1)
      d[k] = v
  return d

def apply_to(path, name, old, new):
  src = open(path).read()
  if old not in src:
    return None
  return src.replace(old, new, 1)

def main():
  which = sys.argv[1] if len(sys.argv) > 1 else None
  files = ["rewriter.bend", "kernel.bend"] if which is None else [f"{which}.bend"]
  for fname in files:
    path = os.path.join(ROOT, "tinybendygrad", "codegen", fname)
    clean = run_gate(path)
    if clean is None:
      print(f"{fname}: CLEAN GATE DOES NOT COMPILE")
      continue
    print(f"\n=== {fname}: clean gate, {len(clean)} rows\n")
    print(f"{'mutation':<40} rows moved")
    print("-" * 78)
    for (name, old, new) in MUTATIONS[fname]:
      mutated = apply_to(path, name, old, new)
      if mutated is None:
        print(f"{name:<40} PATTERN NOT FOUND")
        continue
      # The mutant lives BESIDE the original, not in a subdirectory: a file's
      # `import ./../helpers.bend` is resolved against its OWN directory, so a
      # mutant one level down would fail to find the substrate and every entry
      # would read COMPILE FAIL.
      tmp = os.path.join(ROOT, "tinybendygrad", "codegen", "_mut_" + fname)
      open(tmp, "w").write(mutated)
      got = run_gate(tmp)
      os.remove(tmp)
      if got is None:
        print(f"{name:<40} COMPILE FAIL")
        continue
      moved = sorted(k for k in set(clean) | set(got) if clean.get(k) != got.get(k))
      print(f"{name:<40} {', '.join(moved) if moved else '(none)'}")

if __name__ == "__main__":
  main()