#!/usr/bin/env python3
"""amdfix.py -- drive `./bin/bend --check-only` and apply the mechanical fixes
this file needs: `+` on a parameter the checker reports as consumed twice, and
`U32.shln`'s Nat shift. Stops on anything else and prints it.

Usage: python3 .agents/slop/tools/amdfix.py <file> [max_iters]
"""
import re, subprocess, sys, os

BEND = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__))))), 'bin', 'bend')

def check(f):
    r = subprocess.run([BEND, f, '--check-only'], capture_output=True, text=True)
    return r.stdout + r.stderr

def add_plus(lines, defline, pname):
    # the parameter list may span lines: find `def NAME(` then the matching
    # `) ->` across lines and rewrite the joined text.
    txt = '\n'.join(lines)
    i = defline - 1
    m = re.compile(r'def ' + re.escape(lines[i].split('(')[0][4:]) + r'\(').search(txt, 0)
    if not m: return False
    start = m.end()
    depth = 1; j = start
    while j < len(txt) and depth:
        if txt[j] == '(': depth += 1
        elif txt[j] == ')': depth -= 1
        j += 1
    params = txt[start:j-1]
    parts = []
    depth = 0; cur = ''
    for ch in params:
        if ch in '([<{': depth += 1
        elif ch in ')]>}': depth -= 1
        if ch == ',' and depth == 0: parts.append(cur); cur = ''
        else: cur += ch
    parts.append(cur)
    for i2, p in enumerate(parts):
        toks = p.strip().split()
        name = toks[0].rstrip(':') if toks else ''
        if name == pname and not toks[0].startswith('+'):
            parts[i2] = p.replace(name, '+' + name, 1)
            new = txt[:start] + ','.join(parts) + txt[j-1:]
            open(F[0], 'w').write(new)
            return new != txt
    return False

F = [None]

def main():
    f = sys.argv[1]
    F[0] = f
    mx = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    for it in range(mx):
        out = check(f)
        if 'ALL PROOFS CHECK' in out:
            print("GREEN after", it, "fixes"); return 0
        m2 = re.search(r'Location:?\s*\n?\s*([A-Za-z0-9_.]+)\n', out)
        if 'consumed more than once' in out and m2:
            dname = m2.group(1)
            pm = re.search(r'- expected : (\S+)\n- observed : \S+ \(consumed', out)
            pname = pm.group(1) if pm else None
            src = open(f).read()
            lines = src.split('\n')
            defline = None
            for i, l in enumerate(lines):
                if re.match(r'def ' + re.escape(dname) + r'\(', l): defline = i + 1; break
            if defline is None: print("no def", dname); print(out[:1500]); return 1
            if pname and add_plus(lines, defline, pname):
                print("iter", it, "+", pname, "on", dname)
                continue
        print(out[:2000]); return 1
    print("gave up"); return 1

sys.exit(main())
