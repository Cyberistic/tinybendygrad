"""Stable topological sort of a Bend file's top-level declarations.

Bend's R-3 rule is that a declaration must precede every use of it, so a merged
file whose blocks were concatenated by provenance can reference a def that is
declared later.  A STABLE sort fixes exactly that and nothing else: a file that
is already ordered comes back byte-identical.
"""

import re
import sys

DEF = re.compile(r'^def ([\w.]+)\s*\(')
DEF_BARE = re.compile(r'^def ([\w.]+)\s*:')
TYPE = re.compile(r'^type ([\w.]+) is')
DECL = re.compile(r'^(?:def|type|law)\b')


def blocks(lines):
    """Partition the file so each DECL owns the comment/blank run above it.

    A run of `#`/blank lines belongs to the next decl when the next real line is
    a decl, and to the previous body otherwise.  That makes the spans a true
    partition, so re-emitting them in any order cannot duplicate a line.
    """
    decls = [i for i, l in enumerate(lines) if DECL.match(l)]
    owner = []
    for d in decls:
        a = d
        while a > 0 and (lines[a - 1].startswith('#') or not lines[a - 1].strip()):
            a -= 1
        owner.append(a)
    spans, prev = [], 0
    for n, d in enumerate(decls):
        a = min(owner[n], prev)          # never reach behind the previous span
        # the span runs to the line before the next block's own start, so each
        # block carries its TRAILING blank lines and a reorder cannot reflow
        # the file's vertical rhythm.
        b = (owner[n + 1] - 1) if n + 1 < len(decls) else len(lines) - 1
        spans.append((a, b))
        prev = b + 1
    return spans


def uses(text, names):
    """Names referenced by `text`, longest match wins, comments stripped."""
    text = re.sub(r'#.*', '', text)
    found, i, L = set(), 0, len(text)
    while i < L:
        best = None
        for nm in names:
            if not text.startswith(nm, i):
                continue
            j = i + len(nm)
            nxt = text[j:j + 1]
            if nxt and (nxt.isalnum() or nxt == '_'):
                continue
            if i and (text[i - 1].isalnum() or text[i - 1] in '._'):
                continue
            if best is None or len(nm) > len(best):
                best = nm
        if best:
            found.add(best)
            i += len(best)
        else:
            i += 1
    return found




def sort_file(path, write=True):
    text = open(path).read()
    lines = text.split('\n')
    spans = blocks(lines)

    # Every top-level name, and the block that declares it.
    owner = {}
    for idx, (a, b) in enumerate(spans):
        body = [l for l in lines[a:b + 1] if not l.startswith('#')]
        for l in body:
            m = DEF.match(l) or DEF_BARE.match(l) or TYPE.match(l)
            if m:
                owner.setdefault(m.group(1), idx)
                break
    names = sorted(owner, key=len, reverse=True)
    used = [uses('\n'.join(l for l in lines[a:b + 1] if not l.startswith('#')), names)
            for a, b in spans]

    # FIXPOINT SWAPS, not a topological sort. A block that uses a name declared
    # LATER is moved down to just after the block that declares it; repeat until no
    # block moves.
    #
    # This is less code than Tarjan, and it needs no cycle handling for the case
    # that matters: a block whose only late dependency is ITSELF is already fine, so
    # self-recursion needs no special case at all.
    #
    # What it cannot do is a MUTUAL cycle -- `A` uses `B` and `B` uses `A` -- because
    # the two constraints contradict and the pass oscillates. That is detected rather
    # than looped on: `budget` bounds the passes, and a file that has not converged is
    # reported and NOT WRITTEN. A fuel-bounded fold is mutual by nature and its
    # members' order is the author's, so silently rewriting it would be the one thing
    # this tool must never do.
    order = list(range(len(spans)))
    pos = {b: i for i, b in enumerate(order)}
    budget = 4 * len(spans) + 16
    while budget:
        budget -= 1
        moved = 0
        for b in list(order):          # a snapshot: the loop body reorders `order`
            for nm in used[b]:
                d = owner[nm]
                if d == b or pos[d] < pos[b]:
                    continue        # self-recursion, or already declared above
                order.remove(d)
                order.insert(order.index(b), d)
                pos = {x: i for i, x in enumerate(order)}
                moved += 1
                break
        if not moved:
            break
    else:
        late = sorted({nm for b in order for nm in used[b] if pos[owner[nm]] > pos[b]})
        sys.exit(f"{path}: did not converge in {4 * len(spans) + 16} passes, so there is "
                 f"a MUTUAL cycle. NOT WRITTEN. Still out of order: {late[:8]}")

    if order == list(range(len(spans))):
        print(f"{path}: already ordered ({len(spans)} blocks), byte-identical")
        return False

    out, prev_end = [], -1
    for i in order:
        a, b = spans[i]
        out.extend(lines[a:b + 1])
        prev_end = b
    out.extend(lines[prev_end + 1:])
    moved = sum(1 for i in range(len(spans)) if order[i] != i)
    print(f"{path}: reordered {moved} of {len(spans)} blocks")
    if write:
        open(path, 'w').write('\n'.join(out))
    return True


if __name__ == '__main__':
    sort_file(sys.argv[1])
