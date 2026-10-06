#!/usr/bin/env python
"""Does each referenced dependency / subject still exist on disk? (read-only)"""
import os, subprocess

ROOT = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                      capture_output=True, text=True).stdout.strip()
os.chdir(ROOT)

DEPS = [
    # non-bend instrument dependencies (loaded by path)
    '.agents/slop/rebase-gate.py',
    '.agents/slop/cstyle-gate.py',
    '.agents/slop/revision-ledger.py',
    '.agents/slop/wire_parse.py',
    '.agents/slop/rebase-scan-oracles.py',
    '.agents/slop/rebase-gate-selftest.py',
    '.agents/slop/patch_not_apply.py',
    '.agents/slop/xd2/cdp.mjs',
    '.agents/slop/xd2/serve.mjs',
    '.agents/slop/blobrows/CURRENT/tinybendygrad__renderer__cstyle.bend.txt',
    '.agents/slop/cstyle-parity/oracle.txt',
    # subjects
    'tinybendygrad/uop/fold.bend',
    'tinybendygrad/renderer/amd/generate.bend',
    'tinybendygrad/mixin/op.bend',
    'tinybendygrad/nn/__init__.bend',
    'tinybendygrad/schedule/rangeify.bend',
    '.agents/slop/rf2root/schedule/rf2_work.bend',
    'tinybendygrad/nn/state.bend',
    'tinybendygrad/renderer/tc_ptx.bend',
    'tinybendygrad/uop/divandmod.bend',
    'tinybendygrad/sz.bend',
    'bin/bend',
    'tinybendygrad/uop/ops.bend',
    'tinybendygrad/helpers.bend',
]
for d in DEPS:
    print(f'{"OK " if os.path.exists(d) else "MISS"}  {d}')
