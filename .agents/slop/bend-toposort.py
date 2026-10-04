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
    owner, decl_re = {}, []
    for idx, (a, b) in enumerate(spans):
        head = lines[a:b + 1]
        body = '\n'.join(l for l in head if not l.startswith('#'))
        m = DEF.match(body.lstrip('\n')) or DEF_BARE.match(body.lstrip('\n')) or TYPE.match(body.lstrip('\n'))
        if m:
            owner.setdefault(m.group(1), idx)
            decl_re.append(m.group(1))
    names = sorted(owner, key=len, reverse=True)

    # edge: user -> used, so used sorts first
    adj = {i: set() for i in range(len(spans))}
    indeg = {i: 0 for i in range(len(spans))}
    for idx, (a, b) in enumerate(spans):
        body = '\n'.join(l for l in lines[a:b + 1] if not l.startswith('#'))
        for nm in uses(body, names):
            j = owner[nm]
            if j != idx and idx not in adj[j]:
                adj[j].add(idx)
                indeg[idx] += 1

    # Kahn, smallest original index first: that is what makes it stable.
    import heapq
    ready = [i for i in range(len(spans)) if indeg[i] == 0]
    heapq.heapify(ready)
    order = []
    while ready:
        i = heapq.heappop(ready)
        order.append(i)
        for k in sorted(adj[i]):
            indeg[k] -= 1
            if indeg[k] == 0:
                heapq.heappush(ready, k)
    if len(order) != len(spans):
        stuck = [names_of(i) for i in range(len(spans)) if i not in order]
        sys.exit(f"CYCLE among {len(stuck)} blocks: {stuck[:8]}")

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
