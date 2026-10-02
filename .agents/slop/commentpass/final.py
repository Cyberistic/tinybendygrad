#!/usr/bin/env python3
"""FINAL VERIFICATION for the comment realignment pass.

For every in-scope file: zero non-comment lines changed, TODO(p*) count unchanged,
comment-line delta, and whether the file is in the changed set.
"""
import os, re, glob, sys
SNAP = '.agents/slop/commentpass/before/'
SCOPE = (sorted(glob.glob('tinybendygrad/nn/*.bend')) + sorted(glob.glob('tinybendygrad/mixin/*.bend')) +
         sorted(glob.glob('tinybendygrad/engine/*.bend')) + sorted(glob.glob('tinybendygrad/schedule/*.bend')) +
         ['tinybendygrad/tensor.bend', 'tinybendygrad/device.bend'])

def noncomment(lines):
    return [l for l in lines if not l.strip().startswith('#')]
def cmt(lines):
    return sum(1 for l in lines if l.strip().startswith('#'))

print(f"{'file':32s}{'lines':>16s}{'cmt':>14s}{'net':>8s}{'noncmt':>9s}{'TODO':>12s}")
tb = ta = cb = ca = nb = 0
touched = 0
for p in SCOPE:
    sb = SNAP + p
    if not os.path.exists(sb): continue
    B = open(sb, encoding='utf-8', errors='replace').read().split('\n')
    A = open(p, encoding='utf-8', errors='replace').read().split('\n')
    nb_, na_ = noncomment(B), noncomment(A)
    same = nb_ == na_
    todo_b = len(re.findall(r'TODO\(p\d+\)', '\n'.join(B)))
    todo_a = len(re.findall(r'TODO\(p\d+\)', '\n'.join(A)))
    net = len(A) - len(B)
    if net: touched += 1
    tb += len(B); ta += len(A); cb += cmt(B); ca += cmt(A)
    nb += sum(1 for x in nb_ if x.strip())
    flag = 'OK ' if same and todo_b == todo_a else '*** '
    print(f"{p.replace('tinybendygrad/',''):32s}{len(B):8d}->{len(A):<7d}{cmt(B):7d}->{cmt(A):<6d}"
          f"{net:8d}{'same' if same else 'DIFF':>9s}{todo_b:5d}->{todo_a:<5d}{flag}")
print()
print(f'TOTAL lines {tb} -> {ta} ({ta-tb})')
print(f'TOTAL comment lines {cb} -> {ca} ({ca-cb})')
print(f'files touched: {touched} of {len([p for p in SCOPE if os.path.exists(SNAP+p)])}')
allnc_ok = all(noncomment(open(SNAP+p,encoding='utf-8',errors='replace').read().split('\n')) ==
               noncomment(open(p,encoding='utf-8',errors='replace').read().split('\n'))
               for p in SCOPE if os.path.exists(SNAP+p))
print('ZERO non-comment lines changed in EVERY in-scope file:', allnc_ok)