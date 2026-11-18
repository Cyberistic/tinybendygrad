<!-- FROM: tinybendygrad/renderer/nir.bend:1199 -->

# the gate, and what every group is for.
#
#   .venv/bin/python .agents/slop/nir/nir-oracle.py rows > .agents/slop/nir/py1.txt
#   ./bin/bend tinybendygrad/renderer/nir.bend            > /tmp/nir_i.txt
#   ./bin/bend tinybendygrad/renderer/nir.bend -o /tmp/nir && /tmp/nir > /tmp/nir_n.txt
#   diff /tmp/nir_i.txt .agents/slop/nir/py1.txt && diff /tmp/nir_n.txt .agents/slop/nir/py1.txt
#
# The whole gate is ONE `IO.print`, so its own newline is the only frame and the
# oracle's single trailing "\n" is its match. BOTH lanes are compared -- the
# interpreted and the native.
#
# `aop.*` AND `aop rev.*` ARE THE TWO DIRECTIONS, and they are separate rows on
# purpose: `u_aop` reads nir.py:19-20 forwards and `u_aop.rev` reads it
# backwards, so an arm moved in one leaves the other green. `aop rev` prints
# `name -> rev(name) -> forward(rev(name))`, so a REVERSE table that disagrees
# with the FORWARD one is caught rather than assumed consistent.
#
# `mesa.nir_op_*` IS THE CONSTANT SWEEP: every enum this file names is gated by
# `getattr` on the live module, and `aop.*` carries the SAME value inline as
# `OP=nir_name/value`, so a table entry and the constant behind it move together.
