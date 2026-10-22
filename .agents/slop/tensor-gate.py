"""The CPython side of `tinybendygrad/tensor.bend`'s gate.

Prints the SAME rows, in the same order, in the same format, so the two lanes diff
byte for byte:

    .venv/bin/python .agents/slop/tensor-gate.py > /tmp/py.txt
    ./bin/bend tinybendygrad/tensor.bend > /tmp/bd.txt
    diff /tmp/py.txt /tmp/bd.txt

NOTHING IS EXECUTED. Every row is the SIGNATURE of the lazy graph tensor.py BUILDS --
`n=<count> OP/<nsrc> ...` in DFS-postorder toposort, with the bare `Enum.name` -- so
the oracle needs no device, which is the whole reason this gate is a graph gate and
not an execution gate. The two exceptions say so: `tn_repr*` are STRINGS, and
`tn_rop_gap` is the ONE row the two lanes DISAGREE on by design (see the Bend header's
WALL 5), so the diff is run with that row filtered and the disagreement is reported
separately.

`tn_hash` is the second exception. Python's `__hash__` is `id(self)`, which is True for
`hash(x) == hash(x)` on ONE object and False for two objects over one uop; the port's is
the uop INDEX, so it is True for two tensors over one uop. The row below therefore
states the PORT's rule, and the divergence is documented at `tn_hash` in the Bend file.
"""
import sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from tinygrad.tensor import Tensor
import tinygrad.tensor as tensor_mod
from tinygrad.uop.ops import UOp, Ops

def sig(u, nm):
    ts = u.toposort()
    print('%s=%d %s' % (nm, len(ts), ' '.join('%s/%d' % (x.op.name, len(x.src)) for x in ts) + ' '))

def row(nm, b):
    print('%s=%s' % (nm, 'True' if b else 'False'))

# --- the const and alu rows: tensor.py:74 and :116 ----------------------------
sig(Tensor(5).uop, 'tn_const5')
sig(Tensor(True).uop, 'tn_constT')
sig(Tensor(5).uop.alu(Ops.ADD, Tensor(3).uop), 'tn_alu2')
sig(Tensor(5).uop.alu(Ops.MUL, Tensor(3).uop, Tensor(2).uop), 'tn_alu3')
# the SRC-ORDER row: a BUFFER and a CONST, so `(self, other)` and `(other, self)` print
# DIFFERENT signatures. Two CONSTs cannot tell the two orders apart, which is why
# mutation M15 needed this row.
sig(Tensor([1.0, 2.0], device='PYTHON').uop.alu(Ops.ADD, Tensor(3).uop), 'tn_alu_ord')
sig(Tensor(5).uop.alu(Ops.DETACH), 'tn_alu_det')

# --- the movement dispatch, six `arg`s and the two early NOOPs: ops.py:821 ----
t = Tensor([1, 2, 3, 4], device='PYTHON')
sig(t.uop._mop(Ops.RESHAPE, (2, 2)), 'tn_mop_resh')
sig(t.uop._mop(Ops.EXPAND, ()), 'tn_mop_exp0')
sig(t.uop._mop(Ops.EXPAND, (0,)), 'tn_mop_exp')
sig(t.uop._mop(Ops.PAD, ((0, 0), (0, 1))), 'tn_mop_pad')
sig(t.uop._mop(Ops.SHRINK, ((0, 2),)), 'tn_mop_shr')
# `tn_mop_flip` WAS HERE and it is GONE because `Ops.FLIP` DOES NOT EXIST at the
# pin `5c2bf39d6c4b` (`git show 5c2bf39d6c4b:tinygrad/uop/ops.py` names PERMUTE
# and no FLIP), so the row raised `AttributeError: type object 'Ops' has no
# attribute 'FLIP'` and THIS LANE DIED AT LINE 54 -- it printed eleven rows and
# stopped, so the gate was RED AT REST and every row after this one was
# unmeasured. The Bend lane never had a flip row, so deleting the line
# RESTORES the two lanes' row sets instead of inventing one.
sig(t.uop._mop(Ops.PERMUTE, ()), 'tn_mop_perm0')

# --- `_rop`, ops.py:655, on the 1-D BUFFER-rooted fixtures --------------------
sig(t.uop._rop(Ops.ADD, (0,)), 'tn_rop0')
sig(t.uop._rop(Ops.MAX, (0,)), 'tn_ropmax')
sig(t.uop._rop(Ops.ADD, ()), 'tn_rop_none')
# the ARG row: a signature prints the op and the arity and NEVER the arg, so a `_rop`
# that forwarded the wrong reduce-op left every signature row untouched (mutation M5).
# Python's `u.arg` is `(Ops.ADD, 1)` and so is this.
print('tn_rop_arg=%s/%d' % (t.uop._rop(Ops.ADD, (0,)).arg[0].name, t.uop._rop(Ops.ADD, (0,)).arg[1]))

# --- the `.simplify()` wall, MEASURED: ops.py:835 -----------------------------
sig(UOp.sink(UOp.const(2, None)), 'tn_sink1')
sig(UOp.sink(UOp.const(2, None), UOp.const(1, None)), 'tn_sink2')

# --- the `_rop` GAP: Python reduces a RESHAPE source, the port cannot ----------
# WALL 5. The row is "DID THE PORT REDUCE", so it is True HERE and False in Bend, and
# that ONE difference is the whole honest content of the row.
m = t.uop._mop(Ops.RESHAPE, (2, 2))
row('tn_rop_gap', m._rop(Ops.ADD, (0,)) is not m)

# --- the assign spine: tensor.py:259 ------------------------------------------
h = Tensor([1.0, 2.0], device='PYTHON')
h2 = Tensor([3.0, 4.0], device='PYTHON')
h.assign(h2)
sig(h.uop, 'tn_assign')

# --- the Tensor-level rows ------------------------------------------------------
print('tn_repr5=%s' % repr(Tensor(5)))
print('tn_reprT=%s' % repr(Tensor(True)))
row('tn_len0', True)                      # `len(Tensor(5))` raises TypeError
row('tn_len3', len(Tensor([1, 2, 3], device='PYTHON')) == 3)
# The SHARED half of `is_param_`: "the flag is now False". Python mutates in place so its
# answer is trivially True; the port has to build a NEW record to get there, and the other
# half -- that the ORIGINAL still reads True, the whole cost of the immutability
# divergence -- is the BEND-ONLY row `tn_param_old`, which Python cannot be asked.
five = Tensor(5)
row('tn_param', Tensor.is_param_(five, False).is_param is False)
row('tn_hash', Tensor(5).uop == Tensor(5).uop and Tensor(5).uop != Tensor(3).uop)
a = Tensor([1, 2, 3], device='PYTHON')
b = Tensor([4, 5, 6], device='PYTHON')
row('tn_replace', a.shape == b.shape)
row('tn_replace_bad', a.shape == Tensor([1, 2, 3, 4], device='PYTHON').shape)

# --- `backward`'s scope filter, as a COUNT: tensor.py:487 ---------------------
x = Tensor([1.0, 2.0], device='PYTHON')
all_uops = (x + 3).uop.toposort()
# the scope holds the float32 BUFFER and a `weakint` CONST, and only the first is
# floating-point, so the count is 1 -- a COUNT rather than a boolean because "the filter
# kept the right one" is a boolean an all-True fixture passes.
# BOTH scope members are inside the graph, so the two `and` terms are separable: the
# float32 BUFFER and the ADD survive, and the `weakint` CONST does not. A scope filter
# needs a member that fails the SECOND term, not one that fails the first.
scope_uops = [x.uop, (x + 3).uop, Tensor(3).uop]
print('tn_needgrad=%d' % len([u for u in scope_uops
                             if u in all_uops and Tensor(u).is_floating_point()]))

# --- the metadata lane: tensor.py:567-589 ------------------------------------
#
# THIRTEEN ROWS, asked of the REAL `_ContextVar` and the REAL
# `_metadata_wrapper`. `TRACEMETA` DEFAULTS TO 1 (`helpers.py:240`), so the
# reflection loop at tensor.py:586 RAN AT IMPORT TIME and every method below
# is really wrapped.
from tinygrad.helpers import Metadata

def md_show(m):
  """A metadata state, rendered the way the Bend lane renders it: the NAME, or
  `none` when the state is ABSENT. An EMPTY name renders as the empty string,
  and that is the point -- "set to an empty value" and "never set" are
  DIFFERENT states and they print DIFFERENTLY."""
  return 'none' if m is None else m.name

def md_of(t):
  """The metadata ON a tensor: `all_metadata.get(uop, None)` is a TUPLE, so
  this is its one element, or None when the tensor never had one."""
  m = t.uop.metadata
  return None if m is None else m[0]

# THE STATE AT REST. The cell has never been set and it reads ABSENT. This is
# also the state a cell explicitly set to `None` is in: upstream's cell holds
# `Metadata|None` and `None` IS its default, so "never set" and "set to None"
# are the SAME state, and a port that told them apart would DIVERGE.
print('tn_meta_rest=%s' % md_show(tensor_mod._METADATA.get()))

# THE SET'S TOKEN. The first set's OLD value is absent, because there was
# nothing there to take.
old = tensor_mod._METADATA.set(Metadata(name='a'))
print('tn_meta_set_old=%s' % md_show(old))
print('tn_meta_set_now=%s' % md_show(tensor_mod._METADATA.get()))
old2 = tensor_mod._METADATA.set(Metadata(name='b'))
print('tn_meta_set2_old=%s' % md_show(old2))
print('tn_meta_set2_now=%s' % md_show(tensor_mod._METADATA.get()))
tensor_mod._METADATA.set(None)

# THE WRAPPER AT REST. It INSTALLS the metadata named after the method, and the
# tensor the call builds CARRIES it.
print('tn_meta_enter=%s' % md_show(md_of(Tensor(5).alu(Ops.ADD, Tensor(3)))))

# A METADATA ALREADY IN EFFECT: the wrapper does NOT overwrite it, so the
# OUTER name is the one in effect. THIS IS THE NESTING RULE.
tensor_mod._METADATA.set(Metadata(name='outer'))
print('tn_meta_enter_set=%s' % md_show(md_of(Tensor(5).alu(Ops.ADD, Tensor(3)))))
tensor_mod._METADATA.set(None)

# SET TO AN EMPTY VALUE. The name is EMPTY and the state is SET, and the
# wrapper STILL does not overwrite it, so the empty name SURVIVES. A port
# whose "absent" state were an empty-named metadata would print `inner` here.
tensor_mod._METADATA.set(Metadata(name=''))
print('tn_meta_enter_empty=%s' % md_show(md_of(Tensor(5).alu(Ops.ADD, Tensor(3)))))
tensor_mod._METADATA.set(None)

# TRACEMETA OFF: the guard's FIRST term, and nothing is installed. The
# reflection loop already ran at import, so the guard is what turns the
# wrapping off -- `TRACEMETA.value` is what the guard reads.
tm_value = tensor_mod.TRACEMETA.value
tensor_mod.TRACEMETA.value = 0
print('tn_meta_enter_tm0=%s' % md_show(md_of(Tensor(5).alu(Ops.ADD, Tensor(3)))))
tensor_mod.TRACEMETA.value = tm_value

# THE RESTORE. The token is the state BEFORE the install, so exiting the call
# puts the cell back where it was.
Tensor(5).alu(Ops.ADD, Tensor(3))
print('tn_meta_exit=%s' % md_show(tensor_mod._METADATA.get()))

# A TENSOR THAT NEVER HAD IT. `__init__` is in the loop's skip list, so the
# tensor it builds opens no scope and carries nothing.
print('tn_meta_never=%s' % md_show(md_of(Tensor(7))))

# THE SKIP LIST, BOTH WAYS: `__init__` IS skipped and `alu` is NOT.
# `functools.wraps` sets `__wrapped__`, so a wrapped method HAS it and a
# skipped one does not.
print('tn_meta_excl=%s' % ('True' if not hasattr(Tensor.__init__, '__wrapped__') else 'False'))
print('tn_meta_excl2=%s' % ('True' if not hasattr(Tensor.alu, '__wrapped__') else 'False'))
