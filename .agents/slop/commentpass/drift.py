#!/usr/bin/env python3
"""Detect drift: has any in-scope file changed since the snapshot was taken?"""
import os, sys, glob
BEFORE = '.agents/slop/commentpass/before/'
SCOPE = sorted(glob.glob('tinybendygrad/nn/*.bend'))+sorted(glob.glob('tinybendygrad/mixin/*.bend'))+sorted(glob.glob('tinybendygrad/engine/*.bend'))+sorted(glob.glob('tinybendygrad/schedule/*.bend'))+['tinybendygrad/tensor.bend','tinybendygrad/device.bend']
drift = 0
for p in SCOPE:
    s = BEFORE + p
    if not os.path.exists(s):
        print(f'NEW    {p}'); drift += 1; continue
    a = open(s, 'rb').read(); b = open(p, 'rb').read()
    if a == b: continue
    # same non-comment lines => only comment drift, note it
    la = a.decode('utf-8', 'replace').split('\n'); lb = b.decode('utf-8', 'replace').split('\n')
    na = [x for x in la if not x.strip().startswith('#')]
    nb = [x for x in lb if not x.strip().startswith('#')]
    if na == nb:
        print(f'CMTDRIFT {p}  (non-comment lines identical)')
    else:
        print(f'DRIFT  {p}  ({len(na)} -> {len(nb)} non-comment lines)  *** STOP AND RESYNC ***')
        drift += 1
print('files needing resync:', drift)