#!/usr/bin/env python3
# dd-sort.py -- TOPOLOGICALLY SORT THE TOP-LEVEL DEFS of one .bend file.
#
# WHY IT EXISTS: bend 2.0.34 refuses a forward reference ("expected : a filled
# definition"), so a def may call only defs declared ABOVE it. Writing a 1400
# line file in dependency order by hand is a loop of one-error-at-a-time
# compiles; this does it once. The call graph is READ OFF THE FILE, so it cannot
# be wrong about which def calls which.
#
# TWO THINGS THE REGEX MUST NOT COUNT, both measured:
#   * a COMMENT mentioning `name(`. Prose in this repo names the callee in
#     every block header, and a comment-only edge is a cycle the compiler does
#     not have.
#   * the def's own HEAD. `def l2i_cdiv.neg(` would be an edge from
#     `l2i_cdiv.neg` to itself, and every `Cd.bn(x: Cd)` reader to every def
#     whose name happens to be a prefix.
# So comment lines are dropped and the head line is dropped, then a whole-word
# match over the rest.
#
# IT IS ORDER-STABLE: among defs whose dependencies are satisfied, the original
# file order is kept, so a re-sorted diff is small and reviewable.
#
#   dd-sort.py <file.bend>          rewrite in place
#   dd-sort.py <file.bend> --check  print the order, write nothing
import re
import sys

DEF = re.compile(r'^(def|type) ([A-Za-z_][A-Za-z0-9_.]*)', re.M)
CALL = re.compile(r'\b([A-Za-z_][A-Za-z0-9_.]*)\s*\(')


def main():
    path = sys.argv[1]
    check = '--check' in sys.argv
    text = open(path).read()
    marks = [(m.start(), m.group(1), m.group(2)) for m in DEF.finditer(text)]
    if not marks:
        print("dd-sort: no top-level defs", file=sys.stderr)
        return 1
    names = {n for _, _, n in marks}
    spans = {}
    deps = {}
    for i, (a, _, name) in enumerate(marks):
        b = marks[i + 1][0] if i + 1 < len(marks) else len(text)
        spans[name] = (a, b)
        code = '\n'.join(l for l in text[a:b].split('\n') if not l.lstrip().startswith('#'))
        nl = code.find('\n')
        code = code[nl + 1:] if nl >= 0 else ''
        deps[name] = {m.group(1) for m in CALL.finditer(code)} & names - {name}
    order, done = [], set()
    pend = [n for _, _, n in marks]
    while pend:
        ready = [n for n in pend if deps[n] <= done]
        if not ready:
            print("dd-sort: CYCLE among", sorted(pend), file=sys.stderr)
            return 1
        pick = ready[0]
        order.append(pick)
        done.add(pick)
        pend.remove(pick)
    if check:
        print('\n'.join(order))
        return 0
    chunks = []
    for i, n in enumerate(order):
        a, b = spans[n]
        if not i:
            a = 0
        else:
            k = a
            while k > 0 and (text[k - 1] == '\n' or
                             (k >= 2 and text[k - 2] == '#')):
                k -= 1
            a = k
        chunks.append(text[a:b].strip('\n'))
    out = '\n\n'.join(chunks) + '\n'
    if out != text:
        open(path, 'w').write(out)
        print(f"dd-sort: reordered {len(order)} defs in {path}")
    else:
        print(f"dd-sort: {path} already ordered")
    return 0


if __name__ == '__main__':
    sys.exit(main())