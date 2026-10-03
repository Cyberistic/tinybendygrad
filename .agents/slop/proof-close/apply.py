"""One-shot splice of the two closed laws into the live proof set.
Backs up nothing itself; the caller already copied the pre-edit files.
"""
from pathlib import Path

root = Path("tinybendygrad")

spec = (root / "LAWS/spec.bend").read_text()
old_max = """def Shape.max_dim(a: Sdim, b: Sdim) -> Sdim:
  match a:
    case SN{va}:
      match b:
        case SN{vb}: SN{Nat.max(va, vb)}
"""
new_max = r'''# tinygrad `_broadcast_shape`: a 1 broadcasts to the other size, including 0.
# `Nat.max(0n, 1n)` is 1, which is not that rule. Measured:
# Tensor.ones(2, 0) + Tensor.ones(1, 1) has shape (2, 0), not (2, 1).
def pick_dim(a: Nat, b: Nat) -> Nat:
  match a:
    case 1n: b
    case _:
      match b:
        case 1n: a
        case _: a

# A value of `AllSN` is the proof a dim list contains no symbolic axis.
# `SameLen` is the proof two lists have the same length, matchable, so the
# broadcast law can induct instead of rewriting a Nat equality.
def AllSN(ds: List<&2, Sdim>) -> Type:
  match ds:
    case Nil{}: Unit
    case SN{_} <> r: AllSN(r)
    case SS{_} <> _: Empty

def SameLen(a: List<&2, Sdim>, b: List<&2, Sdim>) -> Type:
  match a:
    case Nil{}:
      match b:
        case Nil{}: Unit
        case _ <> _: Empty
    case _ <> ra:
      match b:
        case Nil{}: Empty
        case _ <> rb: SameLen(ra, rb)

# Element-wise non-1-wins. Independent of `zip_max`, so a law that equates
# them pins the broadcast, not a name.
def elem_pick(a: List<&2, Sdim>, b: List<&2, Sdim>) -> List<&2, Sdim>:
  match a:
    case Nil{}: Nil{}
    case SN{va} <> ra:
      match b:
        case Nil{}: Nil{}
        case SN{vb} <> rb: SN{pick_dim(va, vb)} <> elem_pick(ra, rb)
        case SS{_} <> _: Nil{}
    case SS{_} <> _: Nil{}

def Shape.max_dim(a: Sdim, b: Sdim) -> Sdim:
  match a:
    case SN{va}:
      match b:
        case SN{vb}: SN{pick_dim(va, vb)}
'''
if old_max not in spec:
    raise SystemExit("spec max_dim anchor missing")
spec = spec.replace(old_max, new_max, 1)
old_main = '''    dn_gate("red1_456", dn_dims(dn_of(Sp.shape(dn_red(1n)))), "5,6")
'''
new_main = '''    dn_gate("red1_456", dn_dims(dn_of(Sp.shape(dn_red(1n)))), "5,6")
    # tinygrad: (2,0)+(1,1)=(2,0). Nat.max would print 2,1.
    dn_gate("bc_20_11", dn_dims(dn_of(Sp.shape(SpAdd{SpReshape{SpInvalid{}, SpInvalid{}, [SN{2n}, SN{0n}]}, SpReshape{SpInvalid{}, SpInvalid{}, [SN{1n}, SN{1n}]}}))), "2,0")
    dn_gate("bc_13_23", dn_dims(dn_of(Sp.shape(SpAdd{SpReshape{SpInvalid{}, SpInvalid{}, [SN{1n}, SN{3n}]}, SpReshape{SpInvalid{}, SpInvalid{}, [SN{2n}, SN{3n}]}}))), "2,3")
    dn_gate("bc_0_1", dn_dims(dn_of(Sp.shape(SpAdd{SpReshape{SpInvalid{}, SpInvalid{}, [SN{0n}]}, SpReshape{SpInvalid{}, SpInvalid{}, [SN{1n}]}}))), "0")
'''
if old_main not in spec:
    raise SystemExit("spec main anchor missing")
spec = spec.replace(old_main, new_main, 1)
(root / "LAWS/spec.bend").write_text(spec)

laws = (root / "LAWS.bend").read_text()
old_law = '''# The previous law here claimed the result took the LEFT operand's shape. That
# is refuted by the rule itself: broadcasting (1,3) with (2,3) gives (2,3), which
# is neither operand. The result is the element-wise max, so its count is the
# larger of the two counts.
# ===========================================================================

law broadcast_is_elementwise_max:
  for +a: S.Sp
  for +b: S.Sp
  {Nat.max(numel_of(S.SpAdd{a, b}), numel_of(b)) == numel_of(S.SpAdd{a, b}) : Nat}
'''
new_law = '''# The previous law here claimed the result took the LEFT operand's shape. That
# is refuted by the rule itself: broadcasting (1,3) with (2,3) gives (2,3), which
# is neither operand.
#
# The count form `max(numel(add), numel(b)) == numel(add)` is false as
# quantified, measured on the live spec and on tinygrad:
#   spec (SS,5)+(3,7) is 21==0; (5,0)+(3,) is 3==0; shapeless+(3,3) is 9==0
#   tinygrad (2,0)+(1,1) is a valid broadcast of shape (2,0), numel 0 < 1
#   tinygrad (2,3)+(3,3) is not a broadcast at all (neither axis is 1)
# What tinyspec and tinygrad agree on, once a 1 is allowed to broadcast to 0,
# is the axis rule: equal-length concrete shapes, each axis is the non-1 size.
# Equal length is the alignment boundary (the spec zips from the head; tinygrad
# right-aligns; they coincide exactly when the ranks match). Symbolic axes are
# excluded because `dim_of(SS)` is 0, which is not tinygrad's symbolic shape.
# ===========================================================================

law broadcast_is_elementwise_max:
  for +a: S.Sp
  for +b: S.Sp
  for +sa: S.Shape
  for +sb: S.Shape
  for +pa: {shape_of(a) == Some{sa} : Maybe<&2, S.Shape>}
  for +pb: {shape_of(b) == Some{sb} : Maybe<&2, S.Shape>}
  for same: S.SameLen(S.Shape.to_dims(sa), S.Shape.to_dims(sb))
  for ca: S.AllSN(S.Shape.to_dims(sa))
  for cb: S.AllSN(S.Shape.to_dims(sb))
  {shape_of(S.SpAdd{a, b}) == Some{S.Shape.of(S.elem_pick(S.Shape.to_dims(sa), S.Shape.to_dims(sb)))} : Maybe<&2, S.Shape>}
'''
if old_law not in laws:
    raise SystemExit("law anchor missing")
(root / "LAWS.bend").write_text(laws.replace(old_law, new_law, 1))

proof = (root / "PROOF.bend").read_text()
proof = proof.replace(
'''# TWO laws remain open. `broadcast_is_elementwise_max` is FALSE as written
# (a symbolic axis counts as 0). `reduce_numel_divides_by_the_reduced_axes`
# was false for two independent reasons, both measured and both fixed in the
# contract: `drop_n` dropped `n+1`, and the multiplier was the kept product
# rather than `List.take(dims, n)`. The corrected statement is true on the
# measured cases and unproven here. Both are marked where they would go.
''',
'''# Every law this file owns is filled. Reduce is `reduced * prod(take(dims, n))
# == numel`, proved by `reduce_numel_go`. Broadcast is restated: equal-length
# concrete shapes, each axis the non-1 size (`pick_dim`). The induction is
# `bcast_axes`.
''',
1)

proof = proof.replace(
'''def L.max_dim_idempotent(x):
  match x:
    case S.SN{v}:
      %nat_max_idem(v) : {S.SN{Nat.max(v, v)} == S.SN{_} : S.Sdim}
      {==}
    case S.SS{p}:
      {==}
''',
'''def pick_idem(v: Nat) -> {S.pick_dim(v, v) == v : Nat}:
  match v:
    case 0n:
      {==}
    case 1n:
      {==}
    case 1n+1n+p:
      {==}

def L.max_dim_idempotent(x):
  match x:
    case S.SN{v}:
      %pick_idem(v) : {S.SN{S.pick_dim(v, v)} == S.SN{_} : S.Sdim}
      {==}
    case S.SS{p}:
      {==}
''',
1)

p10 = Path(".agents/slop/proof-close/p10-lemmas.bend").read_text()
chunks = []
cur = []
for line in p10.splitlines(True):
    if line.startswith("def ") and cur:
        chunks.append("".join(cur))
        cur = [line]
    else:
        cur.append(line)
if cur:
    chunks.append("".join(cur))
lemmas = "".join(ch for ch in chunks if ch.startswith("def ") and not ch.startswith("def main") and not ch.startswith("def nat_mul_zero_r"))
split = Path(".agents/slop/proof-close/p11-split.bend").read_text()
split = split[split.index("def split("):split.index("def main(")].replace("N.", "")
extra = lemmas + "\n" + split + '''
def reduce_numel_go(m: Maybe<&2, S.Shape>, n: Nat) -> {Nat.mul(S.dims_prod(S.Sp.shape.reduce(m, n)), S.prod(List.take(&2, S.Sdim, L.dims_of.go(m), n))) == S.dims_prod(m) : Nat}:
  match m:
    case None{}:
      {==}
    case Some{sh}:
      match sh:
        case S.Sh{ds}:
          split(ds, n)

'''
anchor = """def nat_mul_zero_r(k: Nat) -> {Nat.mul(k, 0n) == 0n : Nat}:
  match k:
    case 0n:
      {==}
    case 1n+p:
      nat_mul_zero_r(p)
"""
if anchor not in proof:
    raise SystemExit("mul_zero anchor missing")
proof = proof.replace(anchor, anchor + "\n" + extra, 1)

proof = proof.replace(
'''# OPEN. The statement is the measured one: `reduced_numel * prod(take(dims, n))
# == numel`. It is not `{==}` from here. `reduced_numel` sits behind
# `Sp.shape.reduce`, and `n` is a symbolic binder, so `List.drop`/`List.take`
# do not reduce. Not closed. Not false: see the foot of this file.
# law reduce_numel_divides_by_the_reduced_axes(t, n)
''',
'''# tinyspec Reduce: "remove the first n axes". The count of what remains times
# the product of the axes that were removed is the original count. The match
# lives in `reduce_numel_go` because a law binder is symbolic.
def L.reduce_numel_divides_by_the_reduced_axes(t, n):
  reduce_numel_go(S.Sp.shape(t), n)
''',
1)

proof = proof.replace(
'''# OPEN -- AND THE LAW IS FALSE as written, not merely stuck. `dim_of(SS{x})` is
# `0n` in spec.bend, so the count of a shape carrying a symbolic axis is `0n`,
# and the law is universally quantified over `Sp`, which admits one. The
# counterexamples are at the foot of this file, printed by
# `.agents/slop/ind/p3.bend`.
#
# It does hold for the literal shapes the name describes -- (2,3) with (3,3) is 9
# against 9 -- and fails as soon as either operand carries a symbolic axis or a
# zero. Restricting the quantifier, or restating it over `Shape` rather than over
# a count, is a `LAWS.bend` change: owner ruling. Not closed.
# law broadcast_is_elementwise_max(a, b)
''',
'''def bcast_axes(a: List<&2, S.Sdim>, b: List<&2, S.Sdim>, ca: S.AllSN(a), cb: S.AllSN(b), same: S.SameLen(a, b)) -> {S.zip_max(a, b) == S.elem_pick(a, b) : List<&2, S.Sdim>}:
  match a:
    case Nil{}:
      match b:
        case Nil{}:
          {==}
        case _ <> _:
          match same:
    case S.SN{va} <> ra:
      match b:
        case Nil{}:
          match same:
        case S.SN{vb} <> rb:
          ih = bcast_axes(ra, rb, ca, cb, same)
          f = cons_head(S.SN{S.pick_dim(va, vb)})
          Equal.cong(List<&2, S.Sdim>, List<&2, S.Sdim>, f, S.zip_max(ra, rb), S.elem_pick(ra, rb), ih)
        case S.SS{_} <> _:
          match cb:
    case S.SS{_} <> _:
      match ca:

def L.broadcast_is_elementwise_max(a, b, sa, sb, pa, pb, same, ca, cb):
  spa = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(a), Some{sa}, pa)
  %spa : {S.dims_zip_max(_, S.Sp.shape(b)) == Some{S.Sh{S.elem_pick(S.Shape.to_dims(sa), S.Shape.to_dims(sb))}} : Maybe<&2, S.Shape>}
  spb = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(b), Some{sb}, pb)
  %spb : {S.dims_zip_max(Some{sa}, _) == Some{S.Sh{S.elem_pick(S.Shape.to_dims(sa), S.Shape.to_dims(sb))}} : Maybe<&2, S.Shape>}
  ih = bcast_axes(S.Shape.to_dims(sa), S.Shape.to_dims(sb), ca, cb, same)
  c1 = Equal.cong(List<&2, S.Sdim>, S.Shape, of_shape, S.zip_max(S.Shape.to_dims(sa), S.Shape.to_dims(sb)), S.elem_pick(S.Shape.to_dims(sa), S.Shape.to_dims(sb)), ih)
  Equal.cong(S.Shape, Maybe<&2, S.Shape>, some_shape, S.Shape.of(S.zip_max(S.Shape.to_dims(sa), S.Shape.to_dims(sb))), S.Shape.of(S.elem_pick(S.Shape.to_dims(sa), S.Shape.to_dims(sb))), c1)
''',
1)

foot_old = proof[proof.index("# ===========================================================================\n# THE TWO LAWS LEFT OPEN."):]
foot_new = '''# ===========================================================================
# Both laws are closed. The measurements that justified the rulings:
#
# reduce, after `drop_n` became `List.drop` and the multiplier became
# `prod(List.take(dims, n))`: (4,) n=0 is 4==4; (4,5,6) n=1 is 120==120;
# n past the rank is 120==120; a symbolic axis is 0==0. `take(n+1)` is
# 16==4 and 600==120, false once drop is exact. `prod(drop)` is the kept
# product, 16==4 and 900==120, also false.
#
# broadcast count form, false as quantified: spec (SS,5)+(3,7) is 21==0;
# (5,0)+(3,) is 3==0; shapeless+(3,3) is 9==0. tinygrad (2,0)+(1,1) is a
# valid broadcast of shape (2, 0), so the count inequality is false there
# too. The axis rule on equal-length concrete shapes is what both do.
# ===========================================================================
'''
proof = proof.replace(foot_old, foot_new, 1)
(root / "PROOF.bend").write_text(proof)
Path(".agents/slop/proof-close/PROOF.bend").write_text(proof)
Path(".agents/slop/proof-close/spec.bend").write_text(spec)
Path(".agents/slop/proof-close/LAWS.bend").write_text((root / "LAWS.bend").read_text())
print("spliced", len(proof))
