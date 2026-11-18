import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/tensor.bend"

# **THE **SECOND **PASS**: **THE **BLOCKS **THAT **ARE **STILL **ESSAYS** AFTER **THE **FIRST
# **CUT**, **⇒⇒† AND **EVERY **ONE **OF **THEM **KEEPS **ITS **FACT **AND **ITS **CITATION**.
EDITS = [
  # THE TENSOR -- the third paragraph is a RESTATEMENT of the fold's rule, and the SECOND
  # paragraph's quote is a difference (Python's flag means something else).
  (50, 59, """# THE TENSOR -- tensor.py:44, `__slots__ = "uop", "is_param", "grad"` (:55). It carries the
# ARENA as well, which Python gets for free: an arena index is only meaningful in the arena that
# produced it and every op in this file grows it.
#
# tensor.py:65 -- "tensors can have gradients if you have called .backward". The flag is not
# "this tensor is differentiable" -- it is "a gradient has been computed for this tensor".
#
# THE READERS -- tensor.py:143-149. All three are fold properties, so all three are a DOUBLE
# `Maybe`: the OUTER `None` is "this fold cannot answer this node" and the INNER one is
# Python's own `None`."""),

  # SIBLING ARENAS -- the LAST paragraph is the second rule of the file, and the arena-growth
  # sentence repeats the `tn_alu.put` block above it. KEEP the measurement and the closure.
  (169, 191, """# SIBLING ARENAS: WAS A WALL, NOW CLOSED. The binops used to build with `tn_alu(lhs, OP,
# [Tensor.u(rhs)])`, which builds in `lhs.ar` and reads `rhs.u` THERE. MEASURED, `O.Rng.sig`
# (`ops.bend:802`) on `tn_add` with `lhs` a bare `CInt{3}` and `rhs` derived to depth N in its
# OWN arena:
#
#   rhs depth 0 (a bare const)   ok=True   sig `2 Ops.ADD/2 Ops.CONST Ops.CONST`
#   rhs depth 1 (one `tn_neg`)   ok=False  sig `1 Ops.ADD/2 Ops.CONST Ops.ADD`
#   rhs depth 2 (two `tn_neg`)   ok=False  sig `3 Ops.ADD/2 Ops.CONST Ops.NOOP`
#
# Depth 0 WAS RIGHT BY COINCIDENCE: `rhs.u` was a legal index in `lhs.ar` that happened to hold
# `lhs`'s own CONST. Depth 1 was SELF-REFERENTIAL and depth 2 read the `NOOP` bottom. No gate saw
# it: every `mk_tensor` in `gates/*.bend` makes each operand a bare const from `O.Arena.empty()`,
# so the depth was always 0. `gates/tn_binop_arena-gate.py` varies the depth and now answers 1
# at 0, 1 and 2 with ZERO divergences.
#
# THE CLOSURE IS `O.Arena.merge`: it re-interns the right operand's nodes into the left one's, so
# the sibling case gets a common descendant and the index is re-minted before it is read. There
# was no such primitive before -- VERIFIED at the time: `grep -nE "def [a-zA-Z_.]*\\(.*ar: Arena.*,
# .*ar2?: Arena"` over `ops.bend` and `tensor.bend` answered exactly one hit, `UOp.group.of`."""),

  # bitwise_not -- the LAST paragraph is about the OLD HEADER being wrong, and the fold read is
  # a `Maybe` shape every reader of this file already knows.
  (298, 312, """# `bitwise_not` -- elementwise.py:145, body at :156-157. three arms, and all three are
# PORTED. The BOOL arm is `tn_logical_not` ABOVE. The SIGNED arm is `self ^ -1` =
# `XOR(self, CONST(-1))`, and `-1` is `CInt{H.i64_of_i32(4294967295)}` -- two's complement,
# because `i64_of_i32` SIGN-EXTENDS a U32. The UNSIGNED arm is THE SAME GRAPH with `dtype.max`
# in place of `-1`: MEASURED in CPython the max stays a `CONST` of `weakint` and is NOT
# promoted, so the graph is `XOR(CAST u8, CONST weakint 255)` with no CAST of its own.
#
# `Maybe<&2, Tensor>` and not `Tensor`, and the `Maybe` is one dtype wide. CPython's `dtype.max`
# is a Python `int` with no width limit; `S.Dt.max` (LAWS/spec.bend:219) answers `None` past 32
# bits, so an unsigned dtype wider than `u32` is a REFUSAL here and not a wrong graph -- the
# graph it would have to build instead (`^ -1` on a `u64`) is WRONG."""),

  # promote -- the FOUR ARMS paragraph is a table of where each conjunct lives, and the file's
  # readers can see it. KEEP the MEASUREMENT and the `wk_remint` fact, which IS a difference.
  (840, 854, """# `promote` -- elementwise.py:29-33, `_broadcasted`'s inner closure, for `self` ALONE against
# the weakfloat `inf` const. `out_dtype` is therefore `least_upper_dtype(self.dtype, weakfloat)`
# and the arm that decides everything is `weak_dtype(out_dtype)`: weakfloat for a strong float,
# weakint for a concrete int, and for a WEAK self `weak_dtype(weakint) = weakint`, which is what
# makes a weakint `self` REMINT to `CONST weakfloat 4.0` while `self != self` -- whose
# `out_dtype` is `weakint` and whose weak arm is therefore the identity -- keeps
# `CONST weakint 4`. MEASURED in CPython, `.venv/bin/python` on
# `Tensor(UOp(Ops.CONST, arg=4)).isfinite()`: FIVE distinct CONST leaves,
# `weakint 4 | bool True | weakfloat 4.0 | inf | -inf`, 15 nodes.
#
# `W.wk_remint` is `remint` -- WHICH LIVES IN `uop/weak.bend` BECAUSE OF THIS CALL: it was
# `ew_remint` in `mixin/elementwise.bend`, and that file imports THIS one."""),

  # __repr__ -- the LAST paragraph explains why there are four defs, and the reader can count
  # them. KEEP the divergence.
  (952, 962, """# `__repr__` -- tinygrad/tensor.py:127-130. `f"<UOp {ld.device} {ld.shape}
# {str(ld.dtype)[7:]}>"`, and all three interpolations are a reader above. `str(dtypes.weakint)` is
# `"dtypes.weakint"`, so `[7:]` is the bare name, which is `S.Dt.nm`. THE DEVICE COLUMN is a
# divergence: a `Dev` is an interned tag, so it prints as its tag, and the gate therefore uses a
# device-LESS tensor where both sides print `None`. The grad column is `self.grad.uop if self.grad
# is not None else None` and 0 is the reserved `None`, so it prints `None` on every device-LESS
# fixture and `0` never."""),

  # __hash__ -- the LAST paragraph is a quote about the GC, and the ONE thing it says the reader
  # needs is that `id` is stable because CPython's GC does not move objects.
  (922, 931, """# `__hash__` -- tensor.py:134. `return id(self)`, and an arena index IS a graph node's
# identity in this port, so `__hash__` is the uop. THE DIFFERENCE, and it is why `_tensor_holds`
# reads the uop rather than a hash: Python's `id` separates two Tensor OBJECTS over one uop and
# this does not.
#
# tensor.py:131 -- "Python has a non moving GC, so this should be okay" -- is a claim about the
# RUNTIME, not about the algorithm, and it is why the port's `tn_hash` may key on a graph node:
# an arena index is not an address and is not reused."""),
]

apply(F, EDITS)
