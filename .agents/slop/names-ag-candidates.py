#!/usr/bin/env python3
"""THE HONEST CANDIDATE LIST. Every filter stated, every count measured.

Filter 1  drop a 1-5 char prefix and require the tail to be a top-level upstream name
          IN THE SAME FILE. (Splitting at any underscore alone yields 352 and is wrong:
          `DFLT_OFF -> OFF` and `bf_bits -> bits` are SUFFIX coincidences.)
Filter 2  require the prefix to be STRUCTURAL in that file: >=2 DISTINCT tails yield
          upstream, so the prefix is systematic and not chance.
Filter 3  require the bare tail name to be FREE in the file. `renderer/tc.py`'s
          `r_tbl_amd_cdna3 -> amd_cdna3` fails here: `amd_cdna3` is already a def, so
          "renaming" is a duplicate-declaration compile error, not a fix.
Filter 4  require the def NOT to be a test gate (`-> IO(Unit)` printing rows) and NOT to
          be one of several accessors of the same upstream name (a flat table's
          columns; Bend has no metaclass and forbids duplicate declarations).
"""
import os, re, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slop_1to1 import core_py, top_level_defs, bend_defs, bend_for

def run():
    rows = []
    for rel in core_py():
        up = top_level_defs('tinygrad/' + rel)
        p = bend_for(rel)
        if not os.path.exists(p): continue
        bd = bend_defs(p)
        decl = {}
        for l in open(p):
            m = re.match(r'(?:def|struct|type)\s+([A-Za-z_][\w.]*)', l)
            if m: decl.setdefault(m.group(1), l.rstrip())
        rest = bd - up
        t = collections.defaultdict(lambda: [0, 0, set()])
        for n in rest:
            for i, ch in enumerate(n):
                if ch != '_' or i == 0 or i + 1 >= len(n) or i > 5: continue
                e = t[n[:i]]; e[0] += 1
                if n[i+1:] in up: e[1] += 1; e[2].add(n[i+1:])
        sys_prefix = {pre for pre, (h, y, d) in t.items() if y >= 2 and len(d) >= 2}
        raw = []
        for n in sorted(rest):
            for pre in sorted(sys_prefix, key=len, reverse=True):
                if n.startswith(pre + '_') and n[len(pre)+1:] in up:
                    raw.append((n, pre, n[len(pre)+1:]))
                    break
        # keyed on the TAIL alone, not (prefix, tail): in renderer/amd/sqtt.py six
        # DIFFERENT prefixes (cls_ dflt_ mask_ dlo_ himax dmask) all expand to the same
        # 48 upstream PacketType names. Those 263 defs are the columns of one flat table,
        # so >1 def per upstream name is the test, and it must not be per-prefix.
        per_up = collections.Counter(tail for _, _, tail in raw)
        for n, pre, tail in raw:
            d = decl.get(n, '')
            dup = per_up[tail] > 1
            gate = d.endswith('-> IO(Unit):')
            rows.append((rel, n, pre, tail, tail in bd, dup, gate, d))
    return rows

if __name__ == '__main__':
    rows = run()
    print('after filters 1+2 (structural prefix):        %d' % len(rows))
    print('after filter 3 (bare name free):              %d'
          % sum(1 for r in rows if not r[4]))
    keep = [r for r in rows if not r[4] and not r[5] and not r[6]]
    print('after filter 4 (not a dup accessor, not a test gate): %d   <- THE LIST' % len(keep))
    for rel, n, pre, tail, taken, dup, gate, d in keep:
        print('  %-34s %-24s drop %-7s -> %-22s %s' % (rel, n, pre + '_', tail, d[:56]))
    print('\nrejected at filter 3 (bare already taken):')
    for rel, n, pre, tail, taken, dup, gate, d in rows:
        if taken: print('  %-34s %-24s -> %-22s' % (rel, n, tail))
    print('\nrejected at filter 4 (dup accessor of the same upstream name):')
    for rel, n, pre, tail, taken, dup, gate, d in rows:
        if dup and not taken: print('  %-34s %-24s -> %-22s' % (rel, n, tail))