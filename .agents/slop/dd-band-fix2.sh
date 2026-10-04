#!/bin/sh
# dd-band-fix2.sh -- STAGE 2, in a throwaway tree: the two remaining `f2f.em1` uses.
#
# `f2f.em1` has THREE shapes and is wrong in all three; dd-band-fix.sh fixed the first.
#
#   (1) MASK VALUE  -- `f2f.down.uf` L1697, `f2f.down.isnan` L1735: `dd_band`'s third
#       parameter is a CONSTANT (`dc_band` interns `dc_cint(ar, k)`), and `shl(1, k) - 1`
#       IS a Python int. FIXED by `f2f.mask1`.
#
#   (2) `tx_shl` SRC0 -- `f2f.qnan` L1605, `f2f.fnuz` L1615: dtype.py writes
#       `shl((shl(1, te) - 1), tm)`, and `shl(1, te) - 1` is a PYTHON INT, so CPython's
#       node is `CONST` and its partner is `MUL(CONST, 2**tm)`. `em1` hands back an
#       `ADD(C(2**te), MUL(C(1), C(-1)))` node instead, so the port builds four nodes
#       where CPython builds none.
#
#   (3) THE COLLAPSE. `+b = T.tx_shl(O.Found.ar(a), f2f.em1(O.Found.ar(a), te), tm)` hands
#       THE SAME ARENA to two node builders. `f2f.em1` builds its five nodes into its own
#       copy and returns an INDEX; `tx_shl` then starts writing at that same `next` in the
#       arena it was given, so the first builder's nodes are OVERWRITTEN. `O.Arena` is an
#       immutable record, so this is silent: the graph reads back as a node with a FORWARD
#       or SELF src, which is impossible in an append-only arena and is exactly the
#       "count barely moves, cone collapses" signature agent-core.md records four times.
#       Measured on the UNFIXED tree, `.agents/slop/dd-bandarena.bend`: `w1` slot 22 is
#       `MUL <- OR(23), C(8388608)` -- src0 is a LATER slot -- and `w1` answers
#       `BITCAST(C(-1))` with a 2-node cone against CPython's 29.
#
# THE FIX for (2) and (3) is the same line: intern the CONST in its own arena STEP and pass
# its INDEX, so the only builder in `tx_shl`'s argument list is `tx_shl` itself.
set -eu
S=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode
F=$S/dd-band-fix2src/tinybendygrad/codegen/decomp/dtype.bend
[ -f "$F" ] || { echo "no source tree at $F" >&2; exit 2; }
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
FIX = [
 ("f2f.qnan: CONST src0, in its own arena step",
  "  +a = T.tx_shl(ar, O.Found.i(ns), U32.sub(tm, fm))\n  +b = T.tx_shl(O.Found.ar(a), f2f.em1(O.Found.ar(a), te), tm)",
  "  +a = T.tx_shl(ar, O.Found.i(ns), U32.sub(tm, fm))\n  +mc = dd_wk(O.Found.ar(a), f2f.em1.i64(te))\n  +b = T.tx_shl(O.Found.ar(mc), O.Found.i(mc), tm)"),
 ("f2f.fnuz: CONST src0, in its own arena step",
  "  +q1 = T.tx_shl(O.Found.ar(fn), f2f.em1(O.Found.ar(fn), te), tm)",
  "  +mc = dd_wk(O.Found.ar(fn), f2f.em1.i64(te))\n  +q1 = T.tx_shl(O.Found.ar(mc), O.Found.i(mc), tm)"),
 ("f2f.down.npat: CONST src0, in its own arena step",
  "  +b = T.tx_shl(O.Found.ar(a), f2f.em1(O.Found.ar(a), te), tm)\n  +c = dd_or(O.Found.ar(b), O.Found.i(a), O.Found.i(b))",
  "  +mc = dd_wk(O.Found.ar(a), f2f.em1.i64(te))\n  +b = T.tx_shl(O.Found.ar(mc), O.Found.i(mc), tm)\n  +c = dd_or(O.Found.ar(b), O.Found.i(a), O.Found.i(b))"),
]
for name, old, new in FIX:
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"ANCHOR {n}-BAD for {name}: {old[:70]!r}")
    s = s.replace(old, new, 1)
    print(f"applied {name}")
open(p, "w").write(s)
PY
md5 -q "$F"