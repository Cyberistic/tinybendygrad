# tinybendygrad/renderer/isa/__init__.bend -- port of tinygrad/renderer/isa/__init__.py
#
# **NOT AN EMPTY MARKER. UPSTREAM IS 50 LINES AND THEY ARE NOT PORTED HERE.**
#
# `tinygrad/renderer/isa/__init__.py` declares the ISA renderers' shared furniture:
#
#   * `Register` -- a frozen dataclass `(name, index, _cons)` with `__mul__`, `__add__`
#     and `enum`, i.e. the register algebra the x86/PTX/NIR renderers compose with;
#   * the helpers built on it (`Reg`, register-set constructors) and `Renderer`
#     subclasses' entry points that take one.
#
# WHY THIS IS A MARKER AND NOT A PORT: MEASURED, the port's own ISA renderer does not
# use it. `tinybendygrad/renderer/isa/x86.bend` carries the register table as DATA with
# `TODO(p3)` markers naming `x86.py`'s `Register`/`alloc_vregs` (see its lines 19, 157,
# 255-257), so the algebra in this file has no consumer until that work lands. Porting a
# dataclass and its operators ahead of its only user would be a transcription nothing
# can check -- the class of marker `.agents/slop/PARITY.md` records as "a row that
# cannot go red".
#
# ⇒ SO THE HONEST STATE IS: ONE GAP, NAMED TWICE, IN TWO PLACES. `x86.bend` records
# `TODO(p3)` for the same defs from the consumer's side; this file records it from the
# provider's side. When p3 lands, the two collapse into one real port and this marker
# becomes the `engine/__init__.py` shape (empty upstream, nothing to re-export).
