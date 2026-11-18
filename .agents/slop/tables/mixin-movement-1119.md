<!-- FROM: tinybendygrad/mixin/movement.bend:1119 -->
# BLOCK:
# the pad fixture, and it is fully straight-line on purpose. Eight CONSTs and two STACKs are
# interned one after another with `+f = ...` bindings and no fold at all. THE FOLDED VERSION
# WAS WRITTEN AND REFUSED: building four CONSTs from a `List<&2, U32>` of values wants a
# `Nat` countdown that doubles as the value index, which wants a `1n+p` / `2n+p` / catch-all
# ladder; that ladder is a CALL, and the call has to be an argument of the self-call that
# consumes the element, which makes the arm read `p` twice; and splitting the step out to
# avoid that makes `.go` and `.at` MUTUAL RECURSION, which Bend refuses in either declaration
# order. Twelve lines of fixture beat forty of fold for a graph with eight nodes, and a
# fixture is exactly where the transliteration argument does not apply: the reader under test
# is `mxm_marg`, not this.
#
# every CONST is built in the arena the previous one left -- the whole of the aliasing rule
# the notes record ("an index is only meaningful in the arena that produced it"), because a
# literal list of CONST indices would be interned in whatever arena happened to be current and
# read back as a different node. the two shape args of a pad: the offsets `((0,1),(0,0),(1,1))`
# and the SIZES `((1,4),(8,8),(10,10))` -- which is CPython's `marg=((0,1),(0,4),(1,10),
# (1,10))` zipped apart, and the row `pad_n` is what says the zip happened rather than the
# two lists having been concatenated.
# END BLOCK

# the pad fixture, and it is fully straight-line on purpose. Eight CONSTs and two STACKs are
# interned one after another with `+f = ...` bindings and no fold at all. THE FOLDED VERSION
# WAS WRITTEN AND REFUSED: building four CONSTs from a `List<&2, U32>` of values wants a
# `Nat` countdown that doubles as the value index, which wants a `1n+p` / `2n+p` / catch-all
# ladder; that ladder is a CALL, and the call has to be an argument of the self-call that
# consumes the element, which makes the arm read `p` twice; and splitting the step out to
# avoid that makes `.go` and `.at` MUTUAL RECURSION, which Bend refuses in either declaration
# order. Twelve lines of fixture beat forty of fold for a graph with eight nodes, and a
# fixture is exactly where the transliteration argument does not apply: the reader under test
# is `mxm_marg`, not this.
#
# every CONST is built in the arena the previous one left -- the whole of the aliasing rule
# the notes record ("an index is only meaningful in the arena that produced it"), because a
# literal list of CONST indices would be interned in whatever arena happened to be current and
# read back as a different node. the two shape args of a pad: the offsets `((0,1),(0,0),(1,1))`
# and the SIZES `((1,4),(8,8),(10,10))` -- which is CPython's `marg=((0,1),(0,4),(1,10),
# (1,10))` zipped apart, and the row `pad_n` is what says the zip happened rather than the
# two lists having been concatenated.
