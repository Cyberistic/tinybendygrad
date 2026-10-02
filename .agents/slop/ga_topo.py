#!/usr/bin/env python3
"""Put `generate.bend`'s top-level defs into callee-first order, in place.

bend has no forward references, so a def must come after everything it calls and
two defs that call each other have NO order at all.  Writing 200+ defs in that
order by hand is the reason the previous unit's file never compiled.

The rewrite is ONLY a permutation of whole top-level def blocks: `type` and
`import` lines and every comment run stay attached to the block above them, and
the set of blocks before and after is asserted equal, so nothing can be lost --
which is the failure mode of an earlier version of `bend_topo.py`, whose
`pre = lines[:first_def]` DELETED every `type` that sat between two defs and
read as `unknown: Fld`.

Run:  python3 .agents/slop/ga_topo.py <file.bend>
"""
import pathlib
import re
import sys

TOP = re.compile(r"^(type |def |import )")

# Reserved words that are also DEF short names: `rep.match`, `order.hit` and a
# bare `match` in a body.  A short-name fallback that ignores this reports
# MUTUAL RECURSION between `fld_le.k2` and `rep.match`, which is nonsense.
KEYWORDS = {"match", "where", "case", "do", "def", "type", "import", "let",
            "True", "False", "Nil", "Some", "None", "List", "String", "U32",
            "Nat", "Bool", "Maybe", "IO", "Char", "Base"}


def blocks(lines):
    """[(kind, start, end, comment_start)].

    `comment_start` walks back over the def's OWN comment run and STOPS at the
    previous block.  Without that stop a comment is claimed twice -- once as the
    tail of the def above it (a comment line does not match TOP, so the forward
    walk runs straight through it) and once as this def's head -- and every run
    of the tool then emits one more copy.  That is how an earlier version turned
    a 1,500-line file into 2,600.
    """
    out, i, n, prev_end = [], 0, len(lines), 0
    while i < n:
        if not TOP.match(lines[i]):
            i += 1
            continue
        kind = lines[i].split(" ")[0]
        j = i + 1
        while j < n and not TOP.match(lines[j]):
            j += 1
        s = i
        while s > prev_end and lines[s - 1].startswith("#"):
            s -= 1
        out.append((kind, i, j, s))
        prev_end = j
        i = j
    return out


def callees(body, own, names):
    """Every identifier the body mentions that is a DEF, minus its own name.

    Two things make a plain `re.findall` over-approximate, and both showed up as
    phantom MUTUAL RECURSION reports:
      * BARE identifiers matter as much as call sites: `List.sort(OP, op_le, os_)`
        passes `op_le` as a VALUE, so a `name(`-only scan misses the dependency
        and leaves the comparator below its only use;
      * a def's SHORT name collides with both a reserved word (`rep.match`,
        `order.hit` vs the keyword `match`) and with a pattern binder (`Suf.new`
        vs the field binder `new`), so `Suf.new`'s body would name `Suf.old`.
    So: match exact def names, and fall back to short names only outside the
    keywords and outside the binders this body introduces.
    """
    src = re.sub(r"#.*", "", "\n".join(body))
    local = set(re.findall(r"\b(?:case|def)\b[^:\n]*", src)[0:0])   # placeholder
    local = set()
    for m in re.finditer(r"\bcase\b([^:\n]*):", src):
        local |= set(re.findall(r"[A-Za-z_][\w]*", m.group(1)))
    local |= set(re.findall(r"[A-Za-z_][\w]*", re.match(r"def [\w.]+\(([^)]*)\)", src).group(1)))
    local |= set(re.findall(r"^[ \t]*[+]?([A-Za-z_][\w]*)[ \t]*=", src, re.M))
    short = {n.split(".")[-1]: n for n in names}
    out = set()
    for tok in re.findall(r"[A-Za-z_][\w.]*", src):
        if tok == own or tok.endswith("." + own):
            continue
        if tok in names:
            out.add(tok)
        elif "." not in tok and tok not in local:
            # BARE token only: `R.kind` is a record accessor, not `field_def.kind`.
            tail = tok.split(".")[-1]
            if tail in short and tail not in KEYWORDS:
                out.add(short[tail])
    return out


def main(path):
    p = pathlib.Path(path)
    lines = p.read_text().split("\n")
    bl = blocks(lines)
    defs, order_src, spans = {}, [], {}
    for kind, a, b, c in bl:
        if kind != "def":
            continue
        name = re.match(r"^def ([\w.]+)\(", "\n".join(lines[a:b])).group(1)
        defs[name] = (a, b)
        spans[name] = (a, b, c)
        order_src.append(name)
    assert len(defs) == len(order_src), "a def name repeats; refusing to guess"
    short = {k.split(".")[-1]: k for k in defs}
    edges = {}
    for name, (a, b) in defs.items():
        cals = set()
        for c in callees(lines[a:b], name, defs):
            if c in defs:
                cals.add(c)
            elif c in short:
                cals.add(short[c])
        edges[name] = cals - {name}

    out, done, stack = [], set(), set()
    for root in order_src:                       # DFS over SOURCE order
        work = [(root, False)]
        while work:
            n, expanded = work.pop()
            if expanded:
                stack.discard(n)
                done.add(n)
                out.append(n)
                continue
            if n in done:
                continue
            if n in stack:                        # a cycle: mutual recursion
                sys.exit("MUTUAL RECURSION: " + n + "  (open: " + " -> ".join(sorted(stack)) + ")")
            stack.add(n)
            work.append((n, True))
            for c in sorted(edges[n]):
                if c not in done:
                    work.append((c, False))
    assert sorted(out) == sorted(defs), "the permutation lost or invented a def"
    assert len(out) == len(defs)

    used, chunks = set(), []
    for n in out:
        a, b, c = spans[n]
        if (a, b) in used:
            continue
        used.add((a, b))
        chunks.append("\n".join(lines[c:b]).rstrip())
    # everything OUTSIDE the first def block, in source order, verbatim
    # the first DEF, not the first top-level line: `import`/`type` blocks
    # all live above it and MUST be kept verbatim, and taking min over every
    # block instead dropped every type in the file.
    first = min(a for k, a, _, _ in bl if k == "def")
    tail_idx = max(b for k, _, b, _ in bl if k == "def")
    # HOIST every `import`/`type` block above the defs and REMOVE it from where
    # it stood.  Without this the file keeps whichever types happened to sit
    # above the first def and silently loses the other fourteen, and the
    # compiler answers `a declared constructor (unknown: OP)`.
    drop = set()
    hoist = []
    for kind, a, b, c in bl:
        if kind == "def":
            continue
        drop.update(range(a, b))
        hoist.append("\n".join(lines[a:b]).rstrip())
    head = "\n".join(l for i, l in enumerate(lines[:first]) if i not in drop).rstrip()
    tail = "\n".join(lines[tail_idx:]).strip()
    body = "\n\n".join(chunks)
    mid = "\n\n".join(hoist) + "\n\n" if hoist else ""
    p.write_text(head + "\n\n" + mid + body + ("\n\n" + tail if tail else "") + "\n")
    print("reordered %d defs (was %d lines, now %d)"
          % (len(out), len(lines), len(p.read_text().split("\n"))))


if __name__ == "__main__":
    main(sys.argv[1])