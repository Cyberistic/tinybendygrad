#!/usr/bin/env python3
"""FX-1 -- build an executable that compiles the LIVE tinybendygrad/runtime/dtype.c.

The tree is NOT planted in the live repo; every build writes into <tree>/ and takes
its `--src` from a copy, so a plant is a copy with one line changed.

THE CONTEXT IS MINE (context.h) and the reason is MEASURED, not chosen: the route
substrate-check.sh:134 uses -- `bend -o .agents/slop/guardfix/probe-c.bend` -- emits
NOTHING today:

    ./bin/bend .agents/slop/guardfix/probe-c.bend -o gen.c   ->  rc 1, no gen.c
    expected : Nat / observed : U32 / Location: fp16_f32.norm / dtype.bend:687

`dtype.bend` is another unit's LIVE file. substrate-check.sh therefore prints
NO INSTRUMENT for every `.c` file in the tree right now. Reported; not worked around
by editing their file.

WHAT THE CONTEXT COSTS, MEASURED BY ITERATING UNTIL ZERO ERRORS (see deficit() and
the DEFICIT lines this script prints): bare `cc -fsyntax-only dtype.c` needs bend's
whole runtime (substrate-check.sh:97 counts 190 errors). This instrument calls the
two PURE halves and needs 7 declarations.

Usage: build.py <tree> [--src <dtype.c>] [--deficit]
Writes <tree>/bin/fp8gate, <tree>/bin/i64gate
"""
import os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
LIVE = os.path.join(REPO, 'tinybendygrad/runtime/dtype.c')


def cc():
    return shutil.which('cc') or shutil.which('clang')


def compile_(src, harness, exe, tree):
    """ONE translation unit: context.h, then dtype.c, then the driver. dtype.c's
    functions are `static`, so anything that is to CALL them has to be in the same
    unit -- which is also why a plant can be a copy of dtype.c with one line changed
    and nothing else."""
    c = cc()
    unit = os.path.join(tree, 'unit_%s.c' % os.path.basename(exe))
    open(unit, 'w').write('#include "context.h"\n#include "%s"\n#include "%s"\n'
                         % (os.path.abspath(src), os.path.join(HERE, harness)))
    p = subprocess.run([c, '-O1', '-w', '-I', HERE, '-o', exe, unit],
                       capture_output=True, text=True)
    errs = [l for l in p.stderr.split('\n') if ' error: ' in l]
    return p.returncode, errs[:3]


def deficit(src, tree):
    """How many declarations the bare file wants. Measured by removing context.h's
    contents one group at a time would be a project; instead: compile with an EMPTY
    context and count the distinct undeclared names, which is the same question."""
    empty = os.path.join(tree, 'empty.h')
    open(empty, 'w').write('')
    p = subprocess.run([cc(), '-fsyntax-only', '-I', tree, src], capture_output=True, text=True)
    names = sorted({m.group(1) for m in
                    (__import__('re').search(r"'(\w+)' (?:undeclared|has incomplete type|undeclared here)", l)
                     for l in p.stderr.split('\n') if ' error: ' in l) if m})
    return len(names), names


def main():
    tree = sys.argv[1]
    args = sys.argv[2:]
    src = args[args.index('--src') + 1] if '--src' in args else LIVE
    os.makedirs(os.path.join(tree, 'bin'), exist_ok=True)
    if '--deficit' in args:
        n, names = deficit(src, tree)
        print('DEFICIT bare cc on %s: %d distinct undeclared names: %s'
              % (os.path.relpath(src, REPO), n, ' '.join(names)))
        return 0
    outs = []
    for name, harness in (('fp8gate', 'harness.c'), ('i64gate', 'harness_i64.c')):
        exe = os.path.join(tree, 'bin', name)
        rc, errs = compile_(src, os.path.join(HERE, harness), exe, tree)
        if rc != 0:
            print('NO INSTRUMENT  %s: %s' % (name, errs[0][:180] if errs else 'link failed'))
            return 1
        outs.append(exe)
    print('LINKED %s  <- %s  [context: context.h, declared here, 7 names]'
          % (' '.join(os.path.relpath(o, tree) for o in outs), os.path.relpath(src, REPO)))
    return 0


if __name__ == '__main__':
    sys.exit(main())