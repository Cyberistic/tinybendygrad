"""bnxtdev.bend -- PAREN BALANCE PER top-LEVEL DEF.

An unclosed paren in a `def` body does not report at that def. It swallows
everything up to the next paren-free top-level construct and the parse error
appears at the NEXT `def`, which reads like that def is malformed and is not.
Three of them on this file: `wqe.words` (four nested `List.append` calls),
`bs.extra_at` (eight nested `Bool.pick`), and `t_hdr0`'s `hdr0_SEND_FLAGS_AT8`
row (one short). Each cost a compile cycle plus a bisect to locate.

    python3 .agents/slop/paren.py tinybendygrad/runtime/support/rdma/bnxtdev.bend

Reports every top-level def whose body does not balance, and names the line the
balance returns to zero on, which is where the reader should look first.
"""
import re
import sys

P = sys.argv[1] if len(sys.argv) > 1 else 'tinybendygrad/runtime/support/rdma/bnxtdev.bend'
lines = open(P).read().split('\n')

# strings are the only place parens do not count
STR = re.compile(r'"(?:[^"\\]|\\.)*"')


def depth_delta(code):
    code = STR.sub('""', code)
    return code.count('(') - code.count(')')


starts = [i for i, l in enumerate(lines) if re.match(r'^(def|type) ', l)]
bad = 0
for k, a in enumerate(starts):
    b = starts[k + 1] if k + 1 < len(starts) else len(lines)
    d = 0
    worst = None
    for i in range(a, b):
        dl = depth_delta(lines[i])
        if worst is None or abs(d + dl) < abs(worst[1]):
            worst = (i, d + dl)
        d += dl
        # NOTE: do NOT stop when the depth returns to zero. A def whose body is
        # one expression per line returns to 0 on the FIRST body line, so the
        # early exit checked one line and missed both of this file's faults.
        # The signature line's own parens balance, so depth 0 is also where the
        # body starts -- the scan must cover every line of the block.
    if d != 0:
        bad += 1
        # the line where the imbalance starts is the best single suspect: the
        # first line whose cumulative depth differs from its paren delta
        print(f"line {a + 1}: {lines[a][:70]}")
        print(f"    body ends at depth {d:+d} (should be 0); "
              f"closest to balanced at line {worst[0] + 1}")
print(f"{P}: {len(starts)} top-level defs, {bad} UNBALANCED -> "
      f"{'clean after' if bad == 0 else 'FIX THESE'}")
sys.exit(1 if bad else 0)