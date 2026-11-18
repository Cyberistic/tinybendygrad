<!-- FROM: tinybendygrad/uop/render.bend:2105 -->
# BLOCK:
# the arena fixtures that drive `pyrender`. render.py:143 is the whole repr
# port's reason to exist and until these rows landed NOTHING called it, so the
# three `pa` fixtures above -- which pin `arg_repr` -- were pinning a formatter
# whose caller was untested.
#
# every fixture is a CPython `UOp` tree rebuilt node for node, and the `py=` text
# is what `pyrender` prints for THAT tree on this `tinygrad/`. Nothing here is a
# transcription: each row's oracle was measured, and the numbering matters -- a
# `cN` label is the toposort INDEX, so the Bend arena has to reach the same
# toposort ORDER CPython does, not merely hold the same nodes.
#
# THE `cN` NUMBERS ALSO PIN THE `to_render` PASS, which is where a lot of
# render.py's behaviour lives: `shared` forces one node onto its own line
# because it has two consumers, `sink`/`store`/`reduce2` force one because the
# SINK/STORE/REDUCE arms add srcs unconditionally, and `buffer`/`copy`/`index`
# show the inverse (BUFFER/RANGE/SPECIAL are `always_rendered`, so they get a
# line even with exactly one consumer).
# `UOp.const(n)` -- CONST(3) is a weakint CONST here and in CPython, so `dt_of`
# agrees and no CAST is involved.
# END BLOCK

# the arena fixtures that drive `pyrender`. render.py:143 is the whole repr
# port's reason to exist and until these rows landed NOTHING called it, so the
# three `pa` fixtures above -- which pin `arg_repr` -- were pinning a formatter
# whose caller was untested.
#
# every fixture is a CPython `UOp` tree rebuilt node for node, and the `py=` text
# is what `pyrender` prints for THAT tree on this `tinygrad/`. Nothing here is a
# transcription: each row's oracle was measured, and the numbering matters -- a
# `cN` label is the toposort INDEX, so the Bend arena has to reach the same
# toposort ORDER CPython does, not merely hold the same nodes.
#
# THE `cN` NUMBERS ALSO PIN THE `to_render` PASS, which is where a lot of
# render.py's behaviour lives: `shared` forces one node onto its own line
# because it has two consumers, `sink`/`store`/`reduce2` force one because the
# SINK/STORE/REDUCE arms add srcs unconditionally, and `buffer`/`copy`/`index`
# show the inverse (BUFFER/RANGE/SPECIAL are `always_rendered`, so they get a
# line even with exactly one consumer).
# `UOp.const(n)` -- CONST(3) is a weakint CONST here and in CPython, so `dt_of`
# agrees and no CAST is involved.
