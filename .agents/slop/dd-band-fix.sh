#!/bin/sh
# dd-band-fix.sh -- apply the seven `dd_band` MASK fixes to a THROWAWAY tree, so the fix
# is MEASURED and not asserted. Never touches the live tree.
#
# THE MASKS, from dtype.py, where all seven are PYTHON INTEGERS because
# `shl(x, y) = x * (2**y)` (transcendental.py:20) and BOTH operands are Python ints:
#
#   L1578 f2f.sign        `v & shl(1, fs-1)`               1 << (fs-1)
#   L1588 f2f.nosign      `v & (shl(1, fs-1) - 1)`         (1 << (fs-1)) - 1
#   L1666 f2f.down.sign   `shr(v, fs-ts) & shl(1, ts-1)`   1 << (ts-1)
#   L1674 f2f.down.nosign `v & (shl(1, fs-1) - 1)`         (1 << (fs-1)) - 1
#   L1698 f2f.down.uf     `shr(v, fm) & (shl(1, fe) - 1)`   (1 << fe) - 1
#   L1714 f2f.down.m2     `shr(ns, fm-tm) & (shl(1,tm)-1)` (1 << tm) - 1
#   L1736 f2f.down.isnan  `shr(v, fm) & (shl(1, fe) - 1)`   (1 << fe) - 1
#
# `f2f.em1` GETS A SIBLING RATHER THAN A CHANGE, because its one `U32`-typed return is
# doing double duty and BOTH readings are right somewhere: `T.tx_shl`'s FIRST argument is
# a NODE INDEX (src0) and its second is a shift AMOUNT, so `f2f.qnan` (L1605) and
# `f2f.fnuz` (L1615) are RIGHT to take `em1`'s index, while `f2f.down.uf` (L1697) and
# `f2f.down.isnan` (L1735) need its VALUE as a mask. One def cannot be both, and that
# ambiguity is the census target in miniature.
set -eu
SCRATCH=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode
F=$SCRATCH/dd-band-fixsrc/tinybendygrad/codegen/decomp/dtype.bend
[ -f "$F" ] || { echo "no source tree at $F -- copy dd-band-snap there first" >&2; exit 2; }

python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
FIX = [
 ("L1578 f2f.sign mask -> 1 << (fs-1)",
  "  +a = dd_band(O.Found.ar(s), v, O.Found.i(s))",
  "  +a = dd_band(O.Found.ar(s), v, T.tx_powi32(U32.sub(fs, 1)))"),
 ("L1588 f2f.nosign mask -> (1 << (fs-1)) - 1",
  "  +a = dd_band(O.Found.ar(m), v, O.Found.i(m))",
  "  +a = dd_band(O.Found.ar(m), v, f2f.mask1(U32.sub(fs, 1)))"),
 ("L1666 f2f.down.sign mask -> 1 << (ts-1)",
  "  dd_band(O.Found.ar(b), O.Found.i(a), O.Found.i(b))",
  "  dd_band(O.Found.ar(b), O.Found.i(a), T.tx_powi32(U32.sub(ts, 1)))"),
 ("L1674 f2f.down.nosign mask -> (1 << (fs-1)) - 1",
  "  dd_band(O.Found.ar(m), O.Found.i(v), O.Found.i(m))",
  "  dd_band(O.Found.ar(m), O.Found.i(v), f2f.mask1(U32.sub(fs, 1)))"),
 ("L1698 f2f.down.uf mask -> (1 << fe) - 1, and em1's dead nodes drop out",
  "  +a = T.tx_shr(ar, O.Found.i(v), fm)\n  +m = f2f.em1(O.Found.ar(a), fe)\n"
  "  +b = dd_band(O.Found.ar(a), O.Found.i(a), m)\n  +c = dd_wk(",
  "  +a = T.tx_shr(ar, O.Found.i(v), fm)\n  +b = dd_band(O.Found.ar(a), O.Found.i(a), f2f.mask1(fe))\n"
  "  +c = dd_wk("),
 ("L1736 f2f.down.isnan mask AND src1 -> (1 << fe) - 1, interned ONCE",
  "  +a = T.tx_shr(ar, O.Found.i(v), fm)\n  +m = f2f.em1(O.Found.ar(a), fe)\n"
  "  +b = dd_band(O.Found.ar(a), O.Found.i(a), m)\n  dd_eq1(O.Found.ar(b), O.Found.i(b), m)",
  "  +a = T.tx_shr(ar, O.Found.i(v), fm)\n  +mc = dd_wk(O.Found.ar(a), f2f.em1.i64(fe))\n"
  "  +b = dd_band(O.Found.ar(mc), O.Found.i(a), f2f.mask1(fe))\n"
  "  dd_eq1(O.Found.ar(b), O.Found.i(b), O.Found.i(mc))"),
 ("L1714 f2f.down.m2 mask -> (1 << tm) - 1, and em1's dead nodes drop out",
  "  +a = T.tx_shr(ar, O.Found.i(ns), U32.sub(fm, tm))\n  +s = dd_wk(O.Found.ar(a), T.tx_powi(tm))\n"
  "  +c1 = dd_wk(O.Found.ar(s), H.i64_of_i32(1))\n  +m = P.dc_sub(O.Found.ar(c1), O.Found.i(s), O.Found.i(c1))\n"
  "  dd_band(O.Found.ar(c1), O.Found.i(a), O.Found.i(m))",
  "  +a = T.tx_shr(ar, O.Found.i(ns), U32.sub(fm, tm))\n"
  "  dd_band(O.Found.ar(a), O.Found.i(a), f2f.mask1(tm))"),
 ("the two VALUE siblings of `f2f.em1`",
  "def f2f.em1(+ar: O.Arena, +k: U32) -> U32:\n  +s = dd_wk(ar, T.tx_powi(k))\n"
  "  +m1 = dd_wk(O.Found.ar(s), H.i64_of_i32(1))\n"
  "  +d = P.dc_sub(O.Found.ar(m1), O.Found.i(s), O.Found.i(m1))\n  O.Found.i(d)",
  "def f2f.em1(+ar: O.Arena, +k: U32) -> U32:\n  +s = dd_wk(ar, T.tx_powi(k))\n"
  "  +m1 = dd_wk(O.Found.ar(s), H.i64_of_i32(1))\n"
  "  +d = P.dc_sub(O.Found.ar(m1), O.Found.i(s), O.Found.i(m1))\n  O.Found.i(d)\n\n"
  "# `shl(1, k)` is `1 * 2**k`, a PYTHON INT (transcendental.py:20), and a Python int\n"
  "# written against a mask is a CONSTANT -- NOT the arena index of the node `f2f.em1`\n"
  "# built for it. `dd_band`'s third parameter is `op.bend`'s `dc_band`, which interns it\n"
  "# as `dc_cint(ar, k)`, so this is the VALUE half and `f2f.em1` is the INDEX half.\n"
  "def f2f.mask1(+k: U32) -> U32:\n  U32.sub(T.tx_powi32(k), 1)\n\n"
  "# the SAME number as an I64, for the `dd_eq1` of dtype.py:122, which reads one interned\n"
  "# CONST node on BOTH sides of the equation.\n"
  "def f2f.em1.i64(+k: U32) -> H.I64:\n  H.i64_sub(T.tx_powi(k), H.i64_of_i32(1))"),
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