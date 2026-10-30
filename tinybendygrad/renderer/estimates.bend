# renderer/estimates.bend -- tinygrad/renderer/__init__.py:15-24, the `Estimates` RECORD.
#
# WHY A FILE OF ITS OWN. `Estimates` is `tinygrad.renderer`'s cost model and
# `KernelInfo` -- `tinygrad.uop.ops` -- carries it as a field. UPSTREAM BREAKS
# THAT CYCLE BY IMPORTING UNDER `TYPE_CHECKING`:
#
#   tinygrad/uop/ops.py:26   if TYPE_CHECKING:
#                              from tinygrad.renderer import Estimates
#
# BEND HAS NO `TYPE_CHECKING`, AND AN IMPORT CYCLE IS REFUSED OUTRIGHT --
# MEASURED, `a.bend` importing `b.bend` while `b.bend` imports `a.bend` answers
# "an import cycle through .../a.bend". SO THE CYCLE IS BROKEN BY A THIRD
# FILE: this one, which imports `Base` and NOTHING ELSE, and which BOTH
# `uop/ops.bend` and `renderer/__init__.bend` import. It is upstream's own
# split -- the record lives with the renderer, and `ops.py` names it -- with
# the deferred import made a module instead of a flag.
#
# THE METHODS THAT NEED `ops.bend` STAY IN `renderer/__init__.bend`:
# `Estimates.from_uops` reads `Ops`, so it lives beside its subject's
# consumers. WHAT IS HERE IS THE RECORD AND ITS ACCESSORS, which need `U32`.

import Base

# ===========================================================================
# `Estimates` -- __init__.py:15-61.
#
#     ops:sint = 0   # number of FLOPS used in the Kernel
#     lds:sint = 0   # bytes accessed in loads and stores
#     mem:dict[tuple[UOp, Ops], sint] = {}   # total bytes, counted ONCE
#
# `sint` is `UOp|int` and has NO Bend spelling, so the port carries the COUNT as
# a `U32`. That is not a shortcut: the ONLY caller is `do_estimates`
# (codegen/__init__.py:437) and it passes `lin.src` -- the LINEARIZED list -- on
# which there is no RANGE, no END, no BACKEDGE and no SPECIAL, so `mults` is 1
# at every step and the `mult_stack` never pushes. The symbolic branch of
# `mults` (`UOp.simplify` is `# TODO(p3) ops.py:495 symbol=UOp.simplify`; the `vmax` under
# `to_max_shape` is `# TODO(p3) ops.py:1092 symbol=UOp.vmax`) is unreachable from that call site,
# so counting the linear list needs none of it.
#
# THE `mem` DICT IS THE ONE PLACE THE PORT'S SHAPE DEPARTS FROM 1:1, and the
# departure is load-bearing rather than cosmetic. Python keys it by
# `(buffer, op)`, so a buffer that is both READ and WRITTEN carries TWO counts
# that `sum(mem.values())` adds. A `Data` record cannot key a `Map` by a pair --
# there is no hasher for a pair and no tuple key -- so the key is the buffer
# index alone, which is the SAME `U32.show` identity `Ctx` uses, and the op is
# DROPPED. `from_uops` below therefore returns the sum over buffers, and a
# buffer read-then-written contributes ONE count where CPython contributes two.
# That is a real disagreement on a real kernel and it is stated rather than
# hidden. Splitting it needs a two-word key, which is a P3 change to the
# substrate's `Map`, not to this file.
# ===========================================================================

type Estimates is Data:
  Estimates{ops: U32, lds: U32, mem: U32}

def Estimates.of(o: U32, l: U32, m: U32) -> Estimates: Estimates{o, l, m}

def Estimates.ops(a: Estimates) -> U32:
  match a:
    case Estimates{ops, lds, mem}: ops

def Estimates.lds(a: Estimates) -> U32:
  match a:
    case Estimates{ops, lds, mem}: lds

def Estimates.mem(a: Estimates) -> U32:
  match a:
    case Estimates{ops, lds, mem}: mem

# `def __add__(self, o)` -- __init__.py:23. Three `U32.add`s; the method is
# exactly them.
def Estimates.add(+a: Estimates, +b: Estimates) -> Estimates:
  Estimates{U32.add(Estimates.ops(a), Estimates.ops(b)), U32.add(Estimates.lds(a), Estimates.lds(b)),
    U32.add(Estimates.mem(a), Estimates.mem(b))}

# `def simplify(self)` -- __init__.py:24: `Estimates(ssimplify(ops),
# ssimplify(lds), ssimplify(mem))`. `ssimplify` on a plain int is the IDENTITY,
# and the port's counter IS a plain int, so this returns its argument and says
# so. Reproducing a `simplify` that cannot simplify anything would be a lie about
# the substrate; returning the record is the honest answer and the gate pins it.
def Estimates.simplify(a: Estimates) -> Estimates: a

# `Estimates.__repr__` is a dataclass repr, so the oracle is CPython's own
# `Estimates(1,2,3)+Estimates(4,5,6)` printed -- the SAME three-field spelling
# the port emits, and a dropped field shows as a shorter string.
#
# IT IS HERE AND NOT IN `renderer/__init__.bend` because `uop/render.bend`
# PRINTS IT: `KernelInfo`'s repr renders the `estimates` field, and upstream's
# `KernelInfo.__repr__` prints `Estimates(ops=1, lds=2, mem=3)` when the field
# holds a value. ONE SPELLING, TWO CALLERS.
def Estimates.str(+a: Estimates) -> String:
  String.concat(["Estimates(ops=", U32.show(Estimates.ops(a)), ", lds=", U32.show(Estimates.lds(a)),
    ", mem=", U32.show(Estimates.mem(a)), ")"])
