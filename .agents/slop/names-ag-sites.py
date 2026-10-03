#!/usr/bin/env python3
"""For a list of (bend file, def name): where is it defined, how many call sites,
how many importers, and is the same identifier already defined in the same file."""
import re, sys, os, subprocess

def defs_of(path):
    out = []
    if not os.path.exists(path): return out
    for i, l in enumerate(open(path), 1):
        m = re.match(r'(?:def|struct|type)\s+([A-Za-z_][\w.]*)', l)
        if m: out.append((m.group(1), i))
    return out

def count_sites(root, name):
    """call sites: the identifier used as a callee `name(` or a dotted ref ending `.name(`"""
    pat = re.compile(r'(?<![\w.])' + re.escape(name) + r'\s*\(')
    patd = re.compile(r'\.' + re.escape(name) + r'\s*\(')
    hits = []
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d not in ('__pycache__', 'reference', '.git')]
        for f in fn:
            if not f.endswith('.bend'): continue
            p = os.path.join(dp, f)
            for i, l in enumerate(open(p, errors='replace'), 1):
                a, b = len(pat.findall(l)), len(patd.findall(l))
                if a or b: hits.append((p, i, a, b, l.rstrip()[:110]))
    return hits

for spec in sys.argv[1:]:
    f, name = spec.split('::')
    p = os.path.join('tinybendygrad', f)
    d = [(n, i) for n, i in defs_of(p) if n == name or n.endswith('.' + name)]
    sites = count_sites('tinybendygrad', name)
    bare = [s for s in sites if not s[3]]
    dot = [s for s in sites if s[3]]
    print('%-44s %-22s def@%s  bare-sites=%d  dotted-sites=%d'
          % (f, name, d[0][1] if d else 'NONE', len(bare), len(dot)))
    for h in bare[:8]: print('      %s:%d  %s' % (h[0], h[1], h[4]))
    for h in dot[:8]:  print('   .  %s:%d  %s' % (h[0], h[1], h[4]))
    if len(bare) > 8 or len(dot) > 8: print('      ... %d more' % (len(bare) - 8 + max(0, len(dot) - 8)))