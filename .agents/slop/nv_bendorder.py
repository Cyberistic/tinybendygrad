#!/usr/bin/env python3
# .agents/slop/nv_bendorder.py -- reorder top-level `def` blocks so that a def
# is declared before every def that calls it, using the COMPILER's own error as
# the oracle. Bend has no forward references, and the message for a mis-ordered
# def is the same one it gives for a law left unfilled, so the compiler is the
# only authority worth asking.
#
# It moves ONE block per compiler round and STOPS when the compiler stops
# complaining, and it collapses blank-line runs afterwards because the move loop
# compounds them.
import re, subprocess, sys

P = sys.argv[1] if len(sys.argv) > 1 else "tinybendygrad/runtime/support/nv/nvdev.bend"

def compile():
    r = subprocess.run(["./bin/bend", P], capture_output=True, text=True)
    return r.stdout + r.stderr

def blocks(src):
    lines = src.split("\n")
    out, cur = [], []
    for ln in lines:
        if ln.startswith("def ") and cur and any(x.startswith("def ") for x in cur):
            out.append("\n".join(cur)); cur = [ln]
        else:
            cur.append(ln)
    out.append("\n".join(cur))
    return out

def name_of(b):
    for l in b.split("\n"):
        m = re.match(r'def ([A-Za-z_][A-Za-z_0-9.]*)\s*\(', l)
        if m: return m.group(1)

def uses(b, t):
    return re.search(r'(?<![A-Za-z_0-9.])' + re.escape(t) + r'(?![A-Za-z_0-9])', b) is not None

def save(src):
    # collapse the blank-line runs the move loop compounds
    open(P, "w").write(re.sub(r'\n{3,}', '\n\n', src))

def main():
    src = open(P).read()
    moved, seen = [], set()
    for it in range(200):
        out = compile()
        m = re.search(r'- observed : (\S+)', out)
        if not m:
            print(f"STOP after {len(moved)} moves (round {it})")
            save(src); return 0
        t = m.group(1)
        if (t, len(moved)) in seen:          # two-cycle guard
            print(f"TWO-CYCLE on {t}; stopping"); save(src); return 1
        seen.add((t, len(moved)))
        bs = blocks(src)
        names = [name_of(b) for b in bs]
        if t not in names:
            print(f"no def named {t}\n{out[:800]}"); save(src); return 1
        ti = names.index(t)
        # the caller the compiler named is the one the error's Location line sits
        # in; find the EARLIEST block that uses t and is not t.
        caller = next((j for j, b in enumerate(bs) if j != ti and uses(b, t)), None)
        if caller is None:
            print(f"no caller for {t}\n{out[:600]}"); save(src); return 1
        if caller > ti:
            print(f"{t} at {ti} already precedes its caller at {caller}; the real"
                  f" dependency is elsewhere\n{out[:900]}")
            save(src); return 1
        blk = bs.pop(ti)
        bs.insert(caller, blk)
        src = "\n\n".join(b for b in bs if b.strip())
        save(src)                      # the next round's compile() reads the FILE
        moved.append(t)
        print(f"  {t} -> {caller}")
    print("GAVE UP after 200 moves"); save(src); return 1

sys.exit(main())