"""bnxtdev.bend -- THE CONSTANT SWEEP.

    python3 .agents/slop/bnxt_sweep.py            # all constant defs
    python3 .agents/slop/bnxt_sweep.py --list

`+1` on EVERY `def NAME() -> U32: V` that is a constant, ONE AT A TIME, the
interpreted lane run, and the whole `name=value` lines diffed. This is the
`ops_metal` sweep, which found 30 blind out of 111 -- all `CALL_*` tags with no
Python counterpart -- and correctly refused to close them with rows that encode
the bug.

A `+1` on a constant nothing reads is a BLIND SPOT and is reported with a
reason. It is never closed by a row that asserts the wrong value.

The sweep is SLOW (one Bend process per constant), so `--only` restricts it.
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(REPO, 'tinybendygrad/runtime/support/rdma/bnxtdev.bend')
BEND = os.path.join(REPO, 'bin/bend')
CONST = re.compile(r'^def ([A-Z][A-Za-z_0-9]*)\(\) -> U32: (\d+)$')


def rows_of(out):
    d = {}
    for line in out.split('\n'):
        if '=' in line:
            k, v = line.split('=', 1)
            d.setdefault(k, set()).add(v)
    return d


def run(src):
    p = SRC + '.sweep'
    with open(p, 'w') as f:
        f.write(src)
    try:
        r = subprocess.run([BEND, p], capture_output=True, text=True, cwd=REPO)
        return r.stdout + r.stderr
    finally:
        os.unlink(p)


def main():
    src = open(SRC).read()
    consts = [(m.group(1), int(m.group(2)), src[:m.start()].count('\n') + 1)
              for m in map(CONST.match, src.split('\n')) if m]
    if '--list' in sys.argv:
        for n, v, ln in consts:
            print(f"  line {ln:5d}  {n} = {v}")
        print(f"{len(consts)} constant defs")
        return
    base_out = run(src)
    if 'done=1' not in base_out:
        print("BASELINE DID NOT RUN:\n" + base_out[:800])
        return
    base = rows_of(base_out)
    only = [a for a in sys.argv[1:] if not a.isdigit()]
    want = [n for n, _v, _l in consts if not only or any(o in n for o in only)]
    blind, moved = [], 0
    for n, v, ln in consts:
        if n not in want:
            continue
        out = run(src.replace(f'def {n}() -> U32: {v}', f'def {n}() -> U32: {v + 1}', 1))
        if 'done=1' not in out:
            blind.append((n, v, 'DID NOT COMPILE'))
            continue
        m = sorted(k for k in set(base) | set(rows_of(out))
                   if base.get(k, set()) != rows_of(out).get(k, set()))
        if m:
            moved += 1
            print(f"{n:46s} {v:12d} +1 -> {len(m):3d} rows  ({', '.join(m[:5])})")
        else:
            blind.append((n, v, 'no row reads it'))
    print(f"\n{len(want)} constants swept: {moved} moved a row, {len(blind)} BLIND")
    for n, v, why in blind:
        print(f"  BLIND  {n} = {v}  -- {why}")


if __name__ == '__main__':
    main()