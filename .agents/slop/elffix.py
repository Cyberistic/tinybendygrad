#!/usr/bin/env python3
# elffix.py -- hoist a def above its caller, one call site at a time.
# bend 2.0.34 has no forward references, so a mutual or out-of-order pair has to
# be resolved by hand. This does the move and asserts the move happened, which
# is the "a scripted block move must assert end > start" trap from
# .agents/slop/agent-core.md.
#
#     python3 elffix.py <file> MOVE <name>

import sys, re

def defs(lines):
    """(start, end) line spans of every top-level `def `/`type `, 0-based."""
    out, i = [], 0
    while i < len(lines):
        if re.match(r'^(def|type) ', lines[i]):
            j = i
            while j < len(lines) and (j == i or lines[j].startswith((' ', '  ', '\t'))):
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out

def span_of(lines, name):
    for a, b in defs(lines):
        if re.match(r'^(def|type) ' + re.escape(name) + r'(\.|\b)', lines[a]):
            return a, b
    return None

def main():
    path, cmd, name = sys.argv[1], sys.argv[2], sys.argv[3]
    lines = open(path).read().split('\n')
    sp = span_of(lines, name)
    if sp is None:
        print(f"no such def: {name}"); sys.exit(1)
    a, b = sp
    block = lines[a:b]
    # find the first CALLER that is not inside the block
    pat = re.compile(r'\b' + re.escape(name) + r'\(')
    for c, d in defs(lines):
        if a <= c < b:
            continue
        for k in range(c, d):
            if pat.search(lines[k]):
                # back up over the comment block immediately above the caller,
                # but only the comments that belong to THIS def (a blank line
                # ends the run), so the caller's own docs travel with it.
                j = c
                while j > 0 and lines[j-1].startswith('#'):
                    j -= 1
                if j >= b:
                    print(f"would overlap: caller at {c+1}, block at {a+1}..{b}")
                    sys.exit(2)
                new = lines[:j] + block + lines[j:a] + lines[b:]
                # drop the original span, shift by len(block)
                lines2 = new
                open(path, 'w').write('\n'.join(lines2))
                print(f"moved {name} from line {a+1} to {j+1} (caller was {c+1})")
                sys.exit(0)
    print(f"{name} has no caller"); sys.exit(3)

main()