import Base
import ./../../tinybendygrad/helpers.bend as H
import ./../../tinybendygrad/LAWS/spec.bend as S
import ./../../tinybendygrad/uop/ops.bend as O

# key-pad-sweep.bend -- DOES THE `type(tag)` FIX SURVIVE AN ARENA THAT IS NOT EMPTY?
#
#   ./bin/bend .agents/slop/key-pad-sweep.bend
#
# WHY A PAD AT ALL. `ops.py:201`'s key is a dict lookup and the port's is a linear scan
# over `Arena.nodes`, so an answer that is right at pad 0 can be wrong at pad n if any
# index, bound or early exit in `intern.find` / `intern.put.shp` / `UOp.of` is off by a
# position. Every `ops.bend` row interns at pad 0, so pad 0 alone is ONE point.
#
# WHAT IT PADS WITH, and why the choice is load-bearing. The pad nodes are SINKs whose ARG
# is `ATuple{[k]}` for a U32 counter, so they are pairwise distinct for a reason that has
# nothing to do with tags. That matters because AFTER the fix `TInt{1}` and `TBool{True}`
# are the SAME key, so a pad that varied only the TAG would put its own first pad node on
# a candidate and the sweep would be measuring its own padding. The candidates carry
# `ANone{}`, so a pad can never collide with one on the arg either.
#
# THE PADS. 0, 1, 2, 5, 17, 64. Not arbitrary: 0 is "as every ops.bend row runs it", 1 is
# "one node already there", 2 and 5 straddle the single-vs-pair arms of `intern.find`'s
# `match ns ss`, and 17 and 64 are past every small constant in the file.
#
# WHAT IT DOES NOT CATCH, and the calibration is MEASURED by `key-pad-mutate.sh` rather
# than asserted here: the pad sweep varies ONE dimension, the number of nodes already
# interned. A defect that does not depend on that dimension is invisible at every pad in
# the list, so six pads are one axis sampled six times and not six axes.
#
# WHY SIX NEAR-IDENTICAL `pad*` DEFS INSTEAD OF ONE `go(n: Nat)`. A `List` is AFFINE in
# bend and a READ counts as a consumption -- MEASURED here: `len3(xs)` twice in one body is
# REFUSED with "expected : xs / observed : xs (consumed more than once)" -- so a pad count
# cannot be shared across the four cells and the two node counts. Each `pad*` therefore
# builds its own `List.range` per cell, and the six defs are the honest shape rather than
# a loop.

# `tag_same` at pad 0 is `ops.bend`'s own `tag_same`; this is the same two-call shape with
# the pad nodes in front. The self-call has to stay inside the def that owns the fuel match
# (renderer/__init__.bend note 9), so the recursion IS the walk -- and the fuel argument is
# FIRST, because bend reads a self-call's arguments left to right and refuses one that
# changes an argument before the shrinking one.
def pad.go(xs: List<&2, Nat>, +acc: O.Arena, +k: U32) -> O.Arena:
  match xs:
    case Nil{}: acc
    case _ <> t: pad.go(t, O.UOp.make(acc, O.OpsSINK{}, Nil{}, O.ATuple{[k]}, O.TNone{}), U32.add(k, 1))

def pad_same(xs: List<&2, Nat>, t1: O.Tag, t2: O.Tag) -> Bool:
  +e = pad.go(xs, O.Arena.empty(), 0)
  +u = O.UOp.new(e, O.OpsSINK{}, Nil{}, O.ANone{}, t1)
  +v = O.UOp.new(O.Found.ar(u), O.OpsSINK{}, Nil{}, O.ANone{}, t2)
  U32.is_eq(O.Found.i(u), O.Found.i(v))

# The four cells `ops.bend` gates, each padded. `const_split` is the CONTROL: at the top
# level `type(arg)` IS in the key, so that one must stay SPLIT at every pad, and a pad
# sweep that let it drift would be measuring the wrong thing.
def bool_int(xs: List<&2, Nat>) -> Bool: pad_same(xs, O.TBool{True{}}, O.TInt{1})
def true_false(xs: List<&2, Nat>) -> Bool: Bool.not(pad_same(xs, O.TBool{True{}}, O.TBool{False{}}))
def none_zero(xs: List<&2, Nat>) -> Bool: pad_same(xs, O.TNone{}, O.TInt{0})
def const_split(xs: List<&2, Nat>) -> Bool:
  +e = pad.go(xs, O.Arena.empty(), 0)
  +u = O.UOp.new(e, O.OpsCONST{}, Nil{}, O.APy{O.CBool{True{}}}, O.TNone{})
  +v = O.UOp.new(O.Found.ar(u), O.OpsCONST{}, Nil{}, O.APy{O.CInt{H.i64_of_i32(1)}}, O.TNone{})
  Bool.not(U32.is_eq(O.Found.i(u), O.Found.i(v)))

def pad_count(xs: List<&2, Nat>, t1: O.Tag, t2: O.Tag) -> O.Found:
  +e = pad.go(xs, O.Arena.empty(), 0)
  +u = O.UOp.new(e, O.OpsSINK{}, Nil{}, O.ANone{}, t1)
  O.UOp.new(O.Found.ar(u), O.OpsSINK{}, Nil{}, O.ANone{}, t2)

# THE ABSOLUTE ROW, and it exists because a MEASURED blind spot put it here.
# `key-pad-mutate.sh` injected four defect classes and the pad sweep was BLIND to two of
# them -- a wrong CONSTANT (`intern.find` seeded at 1) and a wrong OFFSET
# (`UOp.of.intern.put` reading `Arena.next - 2`) -- moving 0 lines at every pad, while it
# caught a stale arena and a dropped field at every pad. The reason is structural and not
# fixable by adding pads: EVERY cell above compares `Found.i(u)` against `Found.i(v)`, and
# a uniform shift in how an index is READ cancels in a comparison of two of them. So this
# row asks for the index of the FIRST candidate in ABSOLUTE terms, which is `n` at pad n,
# and a shift cannot cancel against a constant.
#
# `Arena.next` is absolute too but it measures the ARENA, not the index the constructor
# hands back, which is exactly the pair C2 desynchronises.
def abs_first(xs: List<&2, Nat>) -> U32:
  +e = pad.go(xs, O.Arena.empty(), 0)
  O.Found.i(O.UOp.new(e, O.OpsSINK{}, Nil{}, O.ANone{}, O.TBool{True{}}))

# AND THE MISS PATH, added for the same reason and MEASURED: with `abs_first` alone, the
# wrong-OFFSET class STILL moved 0 lines. `UOp.new.of` is `Found{made, UOp.of(made, ...)}`
# -- make first, then read the index back out of the ALREADY-GROWN arena -- so `UOp.of`
# always takes the `Some{i}` HIT branch and the `case None{}` arm of `UOp.of.intern.put`,
# which is the arm that computes `Arena.next - 1`, is NEVER REACHED from `UOp.new` at all.
# It is reached only by a caller that calls `UOp.of` on an arena that does not yet contain
# the node, which is what the `sg_*`/`s5_*` sugar rows do. So this row calls `UOp.of`
# directly on a freshly-made arena, and the index it must return is `n + 1` at pad n.
def of_first(xs: List<&2, Nat>) -> U32:
  +e = pad.go(xs, O.Arena.empty(), 0)
  O.UOp.of(O.UOp.make(e, O.OpsSINK{}, Nil{}, O.ANone{}, O.TBool{True{}}),
           O.OpsSINK{}, Nil{}, O.ANone{}, O.TBool{True{}})

# The NODE-COUNT half. At pad n a merged pair leaves `n + 1` nodes and a split pair `n + 2`,
# so these two columns are what catch a comparator that returns the right Bool while still
# appending a duplicate.
def merged_next(xs: List<&2, Nat>) -> U32:
  O.Arena.next(O.Found.ar(pad_count(xs, O.TBool{True{}}, O.TInt{1})))

def split_next(xs: List<&2, Nat>) -> U32:
  O.Arena.next(O.Found.ar(pad_count(xs, O.TBool{True{}}, O.TBool{False{}})))

def emit(nm: String, b1: Bool, b2: Bool, b3: Bool, b4: Bool, c1: U32, c2: U32, a1: U32, a2: U32) -> IO(Unit):
  IO.print(String.concat([nm,
                           " bool_int=", Bool.show(b1),
                           " true_false=", Bool.show(b2),
                           " none_zero=", Bool.show(b3),
                           " const_split=", Bool.show(b4),
                           " count_merged=", U32.show(c1),
                           " count_split=", U32.show(c2),
                           " abs_first=", U32.show(a1),
                           " of_first=", U32.show(a2), "\n"]))

def pad0() -> IO(Unit):
  emit("pad0", bool_int(List.range(0n)), true_false(List.range(0n)), none_zero(List.range(0n)),
       const_split(List.range(0n)), merged_next(List.range(0n)), split_next(List.range(0n)),
       abs_first(List.range(0n)),
       of_first(List.range(0n)))

def pad1() -> IO(Unit):
  emit("pad1", bool_int(List.range(1n)), true_false(List.range(1n)), none_zero(List.range(1n)),
       const_split(List.range(1n)), merged_next(List.range(1n)), split_next(List.range(1n)),
       abs_first(List.range(1n)),
       of_first(List.range(1n)))

def pad2() -> IO(Unit):
  emit("pad2", bool_int(List.range(2n)), true_false(List.range(2n)), none_zero(List.range(2n)),
       const_split(List.range(2n)), merged_next(List.range(2n)), split_next(List.range(2n)),
       abs_first(List.range(2n)),
       of_first(List.range(2n)))

def pad5() -> IO(Unit):
  emit("pad5", bool_int(List.range(5n)), true_false(List.range(5n)), none_zero(List.range(5n)),
       const_split(List.range(5n)), merged_next(List.range(5n)), split_next(List.range(5n)),
       abs_first(List.range(5n)),
       of_first(List.range(5n)))

def pad17() -> IO(Unit):
  emit("pad17", bool_int(List.range(17n)), true_false(List.range(17n)), none_zero(List.range(17n)),
       const_split(List.range(17n)), merged_next(List.range(17n)), split_next(List.range(17n)),
       abs_first(List.range(17n)),
       of_first(List.range(17n)))

def pad64() -> IO(Unit):
  emit("pad64", bool_int(List.range(64n)), true_false(List.range(64n)), none_zero(List.range(64n)),
       const_split(List.range(64n)), merged_next(List.range(64n)), split_next(List.range(64n)),
       abs_first(List.range(64n)),
       of_first(List.range(64n)))

# renderer/__init__.bend note 7: a def whose body is a `do` block must be the LAST def in
# the file, so `main` is last, and its body ends with a BARE TERM rather than a
# `_ : Unit <- ...` binding.
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- pad0()
    b : Unit <- pad1()
    c : Unit <- pad2()
    d : Unit <- pad5()
    e : Unit <- pad17()
    f : Unit <- pad64()
    IO.print("end\n")