#!/usr/bin/env python3
"""afloat-probe.py -- what CPython's ucache does with a BARE float `arg`.

`UOpMetaClass.__call__` keys on `(op, src, arg, tag, type(arg))` (ops.py:201) and the
key HOLDS the float, so the answer is Python's own `dict` semantics for a `float`
ELEMENT, not a bit comparison. Two facts decide it and both are asked here:

  * `hash(0.0) == hash(-0.0)` and `0.0 == -0.0`, so the two land in one bucket and the
    tuple comparison says equal -> ONE node.
  * `x == x` is False for NaN, so two DISTINCT NaN objects with the same bits do not
    join, while the SAME NaN object does (dict lookup short-circuits on identity).

Read `TG_TREE` so the pin can be compared. Run it twice: the answers depend on
`ucache` lifetime, and a discarded node deletes its own key.
"""
import os
import sys

TG_TREE = os.environ.get('TG_TREE', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'opstree'))
sys.path.insert(0, TG_TREE)

import tinygrad.uop.ops as O  # noqa: E402
from tinygrad.uop import Ops  # noqa: E402
from tinygrad.uop.ops import UOp  # noqa: E402

print(f"#tree={TG_TREE}")
print(f"#ops_py_key_line={__import__('inspect').getsourcelines(O.UOpMetaClass.__call__)[1]}")


def bits(x) -> int:
  import struct
  return struct.unpack('<I', struct.pack('<f', x))[0]


def cell(*args):
  """`len(ucache)` FRESH, then the pair, then the count -- the count has to be read
  INSIDE the cell because the cache accumulates."""
  O.UOpMetaClass.ucache.clear()
  keep = [UOp(Ops.CONST, src=(), arg=a) for a in args]
  return keep, len(O.UOpMetaClass.ucache)


# --- 1. the two signed zeros. Same magnitude, opposite sign. -------------------
z, n = cell(0.0, -0.0)
print(f"zeros_same_node={z[0] is z[1]}")
print(f"zeros_count={n}")
print(f"zeros_bits={bits(0.0)},{bits(-0.0)}")
print(f"zeros_hash_eq={hash(0.0) == hash(-0.0)}")
print(f"zeros_eq={0.0 == -0.0}")
print(f"zeros_keyeq={(Ops.CONST, (), 0.0, None, float) == (Ops.CONST, (), -0.0, None, float)}")

# --- 2. two DISTINCT NaN objects with identical bits. --------------------------
nan_a, nan_b = float('nan'), float('nan')
nan, n2 = cell(nan_a, nan_b)
print(f"nan_distinct_same_node={nan[0] is nan[1]}")
print(f"nan_distinct_count={n2}")
print(f"nan_bits={bits(nan_a)},{bits(nan_b)}")
print(f"nan_eq={nan_a == nan_b}")
print(f"nan_keyeq={(Ops.CONST, (), nan_a, None, float) == (Ops.CONST, (), nan_b, None, float)}")

# --- 3. the SAME NaN object twice, which is what `is` in one expression gives. ---
nan_c = float('nan')
nan3, n3 = cell(nan_c, nan_c)
print(f"nan_same_obj_same_node={nan3[0] is nan3[1]}")
print(f"nan_same_obj_count={n3}")
print(f"nan_same_obj_is={nan_c is nan_c}")

# --- 4. 0.0 against itself, the DIAGONAL, so the fixture has a True in it. ------
d, n4 = cell(0.0, 0.0)
print(f"zero_diag_same_node={d[0] is d[1]}")
print(f"zero_diag_count={n4}")

# --- 5. the ordered pair: does the key HOLD the float at all? ------------------
e, n5 = cell(1.5, 1.5)
print(f"onefive_same_node={e[0] is e[1]}")
print(f"onefive_count={n5}")
f, n6 = cell(1.5, 2.5)
print(f"onefive_vs_twofive_same_node={f[0] is f[1]}")
print(f"onefive_vs_twofive_count={n6}")

# --- 6. what `type(arg)` contributes: an int 0 and a float 0.0. ---------------
g, n7 = cell(0, 0.0)
print(f"int0_vs_float0_same_node={g[0] is g[1]}")
print(f"int0_vs_float0_count={n7}")
print(f"int0_vs_float0_keyeq={(Ops.CONST, (), 0, None, int) == (Ops.CONST, (), 0.0, None, float)}")

# --- 7. the CONSTRUCTOR'S own dtype, so the row can be about a real node. ------
print(f"zeros_dtypes={[u.dtype for u in z]}")
print(f"zeros_arg_types={[type(u.arg).__name__ for u in z]}")