#!/usr/bin/env python3
"""THE CPYTHON LANE for `tinybendygrad/viz/serve.bend`.

NOTHING HERE IS TYPED BY HAND. Every `name=value` line is produced by CALLING
`tinygrad/viz/serve.py`'s own functions on a fixture built below, and it prints
the SAME line shape the Bend lane prints -- `name=<port>|<cpython>` -- so a diff
is a real disagreement rather than a formatting difference.

    .venv/bin/python .agents/slop/vz/viz_oracle.py > .agents/slop/vz/py.txt
    ./bin/bend tinybendygrad/viz/serve.bend   > .agents/slop/vz/bd.txt
    ./bin/bend tinybendygrad/viz/serve.bend --check-only > .agents/slop/vz/bd2.txt
    diff .agents/slop/vz/py.txt .agents/slop/vz/bd.txt
    diff .agents/slop/vz/bd.txt  .agents/slop/vz/bd2.txt

THE FIXTURES ARE NON-UNIFORM ON PURPOSE. An all-equal fixture cannot detect
order, and viz is nothing but ordered lists. Proven elsewhere in this repo by
mutation: six rows all printing `1,1`, and reversing the list moved none of them.

THE ORACLE'S OWN EXIT PATH IS CHECKED FIRST. A lane that emits 0 rows and exits
non-zero has told you nothing, and one has already done that here: an oracle
printed 0 rows and exited 1 while the gate printed 432 rows. `main` asserts
`len(ROWS) >= 140` at the end and `sys.exit(1)` otherwise.
"""
import sys, os, json, struct
from decimal import Decimal

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)

ROWS = []
def row(name, got, both=False):
  # `both=True` for the op-colour ladder, whose Bend row embeds the expected
  # value so a transcription slip needs no second file. Every other row is plain
  # `name=value` on BOTH sides, so a diff is a disagreement and not a formatting
  # difference.
  ROWS.append("%s=%s|%s" % (name, got, got) if both else "%s=%s" % (name, got))

from tinygrad.viz import serve as viz
from tinygrad.uop.ops import Ops
from tinygrad.dtype import AddrSpace

# ===========================================================================
# 1. THE COLOUR TABLES. `uops_colors` is a dict LITERAL with three `**`
#    expansions and a Python dict literal is LAST-WINS -- so an op named
#    explicitly AND reached by an expansion takes the EXPANSION's colour. The
#    Bend ladder has to reproduce that order, not the visual order of the source.
#    Printing every op means the port cannot quietly disagree about which of the
#    two won for WMMA or UNSHARD, and the dict LENGTH catches a gained or lost
#    entry that no per-op row could see.
# ===========================================================================
def sec_colors():
  for op in Ops:
    row("op_color.%s" % op.name, viz.uops_colors.get(op, "#ffffff"), both=True)
  row("op_color_len", len(viz.uops_colors), both=True)
  for a in AddrSpace:
    row("addr_color.%s" % a.name, viz.addrspace_colors[a], both=True)
  for k, v in viz.wave_colors.items():
    row("wave_color.%s" % k, viz.wave_colors[k], both=True)
  row("wave_color_len", len(viz.wave_colors), both=True)

# ===========================================================================
# 2. THE PURE STRING FUNCTIONS. `row_tuple` is the sharpest: it answers a tuple
#    of (int,int) pairs whose LENGTH is the number of whitespace-separated
#    tokens, so a wrong split is a length diff, and `ord(ss[0][0])` is the
#    codepoint of the FIRST CHARACTER of the prefix, not the prefix.
# ===========================================================================
ROWS_TUP = [
  "ALUEXEC:0 WMMA", "VALUEXEC:1 SIMD:2", "WAVE:5", "VALU:0 SIMD:1",
  "Shader Clock", "LINE:Shader Clock", "GPC:0 TPC:1 SM:2 WAVE:3",
  "ALUEXEC:0 TFU", "SALU:3", "a:99", "plain", "x:0:1", "",
  "IMMEDIATE:0 VALU", "LDS:7 XCC:2", "MEM:100", "VALU:0",
]
def fmt_row_tuple(t):
  return "[" + ",".join("[%d, %d]" % p for p in t) + "]"
def sec_rows():
  for r in ROWS_TUP:
    nm = "row_tuple.%s" % (r if r else "empty")
    row(nm, fmt_row_tuple(viz.row_tuple(r)))
  for k in ["GPU:0", "GPU Memory", "CPU:1", "GC", "USER", "TINY", "ALLDEVS", "DISK",
            "CPU:0 Memory", "AMD:0", "AMD:3", "AMD:x", "GPU:12", "GPU Memory ",
            "GPU:007", "X", "X:y Memory", "0:0", "GPU:9:9"]:
    mem, spec, base, full = viz.device_sort_fn(k)
    row("dev_sort.%s" % k, "%s/%d/%s/%s" % ("true" if mem else "false", spec, base, full))
  for t in ["gfx11", "gfx1100", "gfx12", "gfx1201", "gfx10", "gfx9", "rdna3", "gfx110", ""]:
    row("get_arch.%s" % (t if t else "empty"), viz.get_arch(t))
  for op_name, simm16 in [("S_BRANCH", 0x0010), ("S_BRANCH", 0xFFF0), ("S_BRANCH", 0x8000),
                          ("branch", 0x0004), ("S_CBRANCH_VCCZ", 0xFFFE), ("V_ADD_F32", 0x0001),
                          ("branch_x", 0x0002), ("s_branch", 0x0010)]:
    r = viz.parse_branch(type("I", (), {"op_name": op_name, "simm16": simm16})())
    # `H.I64` PRINTS AS `hi:lo` in this tree (helpers.bend:1303 says so and gives
    # the reason: 2^63 has no U32 image), so the oracle projects the same two
    # words rather than a decimal. -64 is `4294967295:4294967232` and BOTH halves
    # are checked -- a port that sign-extended only the low word gets the low half
    # right, which is the shape of bug this row exists to catch.
    if r is None:
      row("parse_branch.%s.%04x" % (op_name, simm16), "null")
    else:
      u = r & 0xFFFFFFFFFFFFFFFF
      row("parse_branch.%s.%04x" % (op_name, simm16), "%d:%d" % (u >> 32, u & 0xFFFFFFFF))

# ===========================================================================
# 3. THE ENCODER HELPERS, THE STRING TABLE AND THE SHAPE FORMATTERS.
#    `enum_str` is a STATEFUL string table whose answer is an INDEX INTO
#    FIRST-SEEN ORDER, so the row is the whole table after the call, comma
#    joined -- an index is only meaningful against the table it indexes. The
#    fixture is `alpha beta alpha gamma beta delta ""`, which has a REPEAT, an
#    EMPTY STRING LAST, and two names that recur in different positions: an
#    all-distinct fixture cannot see a cache that never hits.
# ===========================================================================
def sec_encoder():
  cache = {}
  seq = []
  for s in ["alpha", "beta", "alpha", "gamma", "beta", "delta", ""]:
    seq.append(str(viz.enum_str(s, cache)))
  row("enum_str.seq", ",".join(seq))
  row("enum_str.table", ",".join(cache.keys()))
  row("option", ",".join([str(viz.option(v)) for v in [None, 0, 5, 123]]))
  for ts, st in [(100, 0), (0, 0), (0xFFFFFFFF, 0), (0x100000000, 0), (5, 10)]:
    try:
      r = str(viz.rel_ts(ts, st, "ctx"))
    except ValueError:
      r = "REFUSED"
    row("rel_ts.%s.%s" % (ts, st), r)

# ===========================================================================
# 4. STEPS, SHAPES AND THE NO_COLOR ARM.
#    `create_step`'s argument is a `(path, ctx, step)` TUPLE and the answer
#    embeds all three, so a swapped index is a diff. `filter_keys` drops the
#    `_`-prefixed keys and keeps insertion order, so the row is the ORDERED
#    JSON of what survives.
# ===========================================================================
def sec_step():
  s1 = viz.create_step("Name", ("/graph-rewrites", 3, 7))
  s2 = viz.create_step("N", ("/code", 0, 12), data="D", depth=2, match_count=5, code_line="f.py:9")
  row("step.query1", s1["query"])
  row("step.query2", s2["query"])
  row("step.filter1", json.dumps(viz.filter_keys(s1)))
  row("step.filter2", json.dumps(viz.filter_keys(s2)))

def sec_shape():
  for s in [(4,), (4, 8), (), (1, 2, 3, 4), (0,), (7,)]:
    row("shape_str.%s" % (s,), viz.shape_to_str(s))
  for m in [((4,),), ((4, 8),), ((),), ((4,), (1, 2)), ((0, 0), (9, 9, 9))]:
    row("mask_str.%s" % (m,), viz.mask_to_str(m))
  row("fmt_colored.off", viz.fmt_colored("\x1b[31mred\x1b[0m"))
  from tinygrad.helpers import Context
  with Context(NO_COLOR=1):
    row("fmt_colored.on", viz.fmt_colored("\x1b[31mred\x1b[0m"))
    row("fmt_colored.on2", viz.fmt_colored("plain"))

def main():
  sec_colors()
  sec_rows()
  sec_encoder()
  sec_step()
  sec_shape()
  for r in ROWS:
    print(r)
  if len(ROWS) < 170:
    sys.stderr.write("ORACLE PRODUCED %d ROWS -- this is not a gate\n" % len(ROWS))
    sys.exit(1)
  sys.exit(0)

if __name__ == "__main__":
  main()