#!/usr/bin/env python3
"""
nv_ip_assemble.py -- splice the GENERATED block of ip.bend from nv_ip_tables.bend.

    python3 .agents/slop/nv_ip_gen.py          # regenerate tables + rows
    python3 .agents/slop/nv_ip_assemble.py     # splice them in

The markers in ip.bend are `# --- GENERATED BEGIN nv_ip_tables.bend ---` and
`# --- GENERATED END nv_ip_tables.bend ---`; everything between them is replaced.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
IP = os.path.abspath(os.path.join(HERE, '..', '..', 'tinybendygrad/runtime/support/nv/ip.bend'))
TAB = os.path.join(HERE, 'nv_ip_tables.bend')
B, E = '# --- GENERATED BEGIN nv_ip_tables.bend ---', '# --- GENERATED END nv_ip_tables.bend ---'
s = open(IP).read()
i, j = s.index(B) + len(B), s.index(E)
body = open(TAB).read().rstrip('\n')
open(IP, 'w').write(s[:i] + '\n' + body + '\n\n' + s[j:])
print('spliced %d B of tables; ip.bend is now %d B' % (len(body), os.path.getsize(IP)))