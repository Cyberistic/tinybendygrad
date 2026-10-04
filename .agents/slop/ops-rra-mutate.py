#!/usr/bin/env python3
"""Mutation table for `resolve_returned_after` (tinygrad/uop/ops.py:1899).

    .venv/bin/python .agents/slop/ops-rra-mutate.py

One edit per CONJUNCT, each required to move exactly the rows it names, plus one
control that must move nothing.

CPython is `[st for st in t.src if st.op is Ops.STORE and st.src[0].unsharded_base
is r.unsharded_base]`, then `if len(stores) != 1: return None`, then one of two arms.
That is six conjuncts and eight rows, and the table's whole job is to show each one
is load-bearing. A conjunct with no row is a conjunct nobody is measuring: dropping
it changes nothing the gate can see, and the gate is the only thing standing between
a comment and a claim.

The check is EXACT -- the set of moved rows must EQUAL the predicted set, not merely
contain it. A subset check passes when a mutation moves its three named rows AND
four others, and the four others are the interesting half.
"""
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
OPS = REPO / "tinybendygrad" / "uop" / "ops.bend"
BASELINE = REPO / ".agents/slop/ops-rra-gate-py.txt"

# (label, exact string, replacement, rows that MUST move)
MUTATIONS = [
  # C1. The `op is Ops.STORE` half of the filter. Dropped, every non-STORE src
  # whose BASE matches becomes a candidate.
  #
  # `rra_samebase` is the row that carries this conjunct and `rra_none_zero` is NOT:
  # that sink's only src is a CONST, and a CONST's base is not r either, so the base
  # test already rejects it and dropping the op test moves nothing. The mutation
  # measured exactly that on the first draft -- 0 rows -- which is how the fixture was
  # found. A conjunct needs a fixture where it is the ONLY failing test.
  #
  # ONLY rra_samebase moves, and that is now the prediction rather than a hope:
  # rra_none_zero and rra_mixed hold CONSTs whose base is not r either, so the base
  # test rejects them whether or not the op test is there. A conjunct is load-bearing
  # at the row that isolates it and INVISIBLE everywhere else, and predicting three
  # rows for a one-row conjunct is the over-prediction a subset check forgives.
  ("filter_drops_the_op_test",
   """  Bool.and(eq_op(Arena.op(ar, st), OpsSTORE{}),
    U32.is_eq(UOp.unsharded_base(fuel, ar, Arena.src(ar, st, 0)), rb))""",
   """  Bool.and(True{},
    U32.is_eq(UOp.unsharded_base(fuel, ar, Arena.src(ar, st, 0)), rb))""",
   ["rra_samebase"]),

  # C2. `r.unsharded_base`, computed in `resolve_returned_after`. Swapped for
  # `UOp.base`, rra_unshard's rb becomes 15 (the UNSHARD) instead of 3 (the BUFFER),
  # so the store's target no longer matches and the row refuses.
  #
  # THE TARGET IS THE POINT and it cost two rounds. Mutating the peel INSIDE
  # `rra.hit` -- on the STORE's target rather than on `r` -- moves NOTHING, and
  # correctly: that target is a BUFFER, and base(BUFFER) == unsharded_base(BUFFER) ==
  # 3 == rb under either peel. A conjunct has a site, and a mutation aimed at the
  # wrong one is a green row that means nothing.
  ("rbase_drops_the_unshard_peel",
   "  +rb = UOp.unsharded_base(fuel, ar, r)",
   "  +rb = UOp.base(fuel, ar, r)",
   # BOTH rows whose `r` is the UNSHARD. `rra_samebase` shares that `r` with
   # `rra_unshard`, so it is sensitive to the same conjunct -- a row set is a property
   # of the FIXTURE GRAPH and not of the conjunct, and two rows built on one `r` always
   # move together. The first draft predicted one and the exact check caught it.
   ["rra_unshard", "rra_samebase"]),

  # C3. `len(stores) != 1` -> `> 1`. Dropped: rra_none_two returns its first match
  # instead of refusing, and passes every other row because in all of them there is
  # exactly one match. This is the row that exists for this conjunct alone.
  ("count_ignores_too_few",
   """  match stores:
    case Nil{}: None{}
    case s <> _: rra.one.tail(s, stores)""",
   """  match stores:
    case Nil{}: Some{0}
    case s <> _: rra.one.tail(s, stores)""",
   ["rra_none_zero", "rra_none_empty"]),

  # C4. `len(stores) != 1` -> `== 0`. Dropped: rra_none_two answers `some` and the
  # three `some` rows still answer `some` -- a different row set from C3, which is
  # what makes the pair worth having.
  ("count_ignores_too_many",
   """def rra.one.tail(s: U32, rest: List<&2, U32>) -> Maybe<&2, U32>:
  match rest:
    case _ <> _ <> _: None{}
    case _: Some{s}""",
   """def rra.one.tail(s: U32, rest: List<&2, U32>) -> Maybe<&2, U32>:
  match rest:
    case _ <> _ <> _: Some{s}
    case _: Some{s}""",
   ["rra_none_two"]),

  # C5. The PARAM arm. `r.unsharded_base.op is Ops.PARAM` -> always False, i.e. the
  # `after` arm never runs. rra_param answers CONST; rra_arena drops to 0. BOTH move,
  # and rra_arena moving is the point: the op-name row alone could be satisfied by a
  # def that minted an AFTER and then returned the wrong index.
  ("pick_never_takes_the_after_arm",
   "    case Some{st}: Some{rra.pick(eq_op(Arena.op(ar, rb), OpsPARAM{}), ar, r, st)}",
   "    case Some{st}: Some{rra.pick(False{}, ar, r, st)}",
   ["rra_param", "rra_arena"]),

  # C6. The non-PARAM arm, forced the other way: the `after` arm ALWAYS runs. Every
  # `some` row that was returning a CONST now answers AFTER.
  #
  # The first draft of this table predicted rra_param and rra_arena here as well and
  # the EXACT check caught it: rra_param was ALREADY the after arm, and rra_arena
  # counts rra_param's mint, so neither can move. That is a subset check's failure
  # mode -- it would have passed a prediction that was simply wrong about which rows
  # are sensitive.
  ("pick_always_takes_the_after_arm",
   "    case Some{st}: Some{rra.pick(eq_op(Arena.op(ar, rb), OpsPARAM{}), ar, r, st)}",
   "    case Some{st}: Some{rra.pick(True{}, ar, r, st)}",
   ["rra_val", "rra_unshard", "rra_mixed", "rra_samebase"]),

  # C7. CONTROL. `stores[0].src[1]` -> `stores[0].src[0]`, which for a STORE is the
  # TARGET -- and every fixture's target happens to be a node the rows already print
  # differently... except that this must move NOTHING, because the non-PARAM arm's
  # index is not what any row reads: the rows read the op NAME of the returned node,
  # and src[0] of node 6 is node 4, an AFTER, which WOULD move rra_val. So this is a
  # real mutation, not a control, and it is listed as one -- a "control" that moves
  # rows is a finding, and calling it a control in advance would be a claim the
  # table has not earned.
  ("reads_src0_instead_of_src1",
   "    case False{}: Found{ar, Arena.src(ar, st, 1)}",
   "    case False{}: Found{ar, Arena.src(ar, st, 0)}",
   ["rra_val", "rra_unshard", "rra_mixed", "rra_samebase"]),
]


def read_rows() -> dict:
  out = subprocess.run([str(REPO / "bin/bend"), str(OPS)],
                       capture_output=True, text=True, cwd=REPO)
  rows = {}
  for line in out.stdout.split("\n"):
    if line.startswith("rra_") and "=" in line:
      k, v = line.split("=", 1)
      rows[k] = v
  return rows


def rows_moved(base: dict, got: dict) -> set:
  return {k for k in base if k in got and base[k] != got[k]}


def main() -> int:
  if not OPS.exists():
    print("ops.bend is gone", file=sys.stderr)
    return 1
  base = read_rows()
  if not BASELINE.exists():
    print(f"{BASELINE.relative_to(REPO)} does not exist -- run ops-rra-gate.sh, which "
          f"writes the CPython lane this table measures against", file=sys.stderr)
    return 1
  want = [l.split("=", 1)[0] for l in BASELINE.read_text().split("\n") if l.startswith("rra_")]
  if sorted(base) != sorted(want):
    print(f"ops-rra-mutate: the port answers {sorted(base)} and the gate's CPython "
          f"baseline {sorted(want)}. Run ops-rra-gate.sh.", file=sys.stderr)
    return 1

  print(f"{'mutation':34} {'rows that moved':46} verdict")
  bad = 0
  for label, old, new, must in MUTATIONS:
    text = OPS.read_text()
    if text.count(old) != 1:
      print(f"{label:34} {'PATTERN NOT UNIQUE (' + str(text.count(old)) + ')':46} NOT MEASURED")
      bad += 1
      continue
    OPS.write_text(text.replace(old, new, 1))
    try:
      got = read_rows()
      moved = rows_moved(base, got)
    finally:
      OPS.write_text(text)
    if len(got) != len(base):
      print(f"{label:34} {'RUN BROKE (' + str(len(got)) + ' rows)':46} NOT A ROW MOVE")
      bad += 1
      continue
    ok = moved == set(must)
    if not ok:
      bad += 1
    print(f"{label:34} {(','.join(sorted(moved)) or '-'):46} "
          f"{'ok' if ok else 'MOVED ' + str(sorted(set(must)))}")

  print(f"\n{len(MUTATIONS) - bad}/{len(MUTATIONS)} mutations moved EXACTLY the rows they name")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())
