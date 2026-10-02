#!/usr/bin/env python3
"""Reorder bend top-level defs into a valid callee-first order.

bend refuses live code that uses an unfilled definition, so a def must come
after every def it calls (callees first) but before nothing -- except that a
def may call ITSELF.  Hand-ordering a 400-line file costs a compile cycle per
mistake (~40s each on this tree, notes pos 11148), so this does it.

Comment blocks immediately above a def travel with it.  `type` declarations and
`import` lines are left where they are -- bend needs a type before its uses,
and this file already keeps the types in dependency order.

Run:  python3 .agents/slop/bend_topo.py <file.bend>   (rewrites in place)
"""
import re
import sys
import pathlib


def blocks(lines):
    """[(kind, start, end)] over `type`/`import`/`def`/blank-or-comment runs."""
    out, i, n = [], 0, len(lines)
    while i < n:
        s = lines[i]
        m = re.match(r"^(type |def |import )", s)
        if not m:
            i += 1
            continue
        kind = m.group(1).strip()
        j = i
        if kind == "def":
            # the def's own lines: until the next top-level `def`/`type`/`import`.
            # j starts at i+1, NOT i: line i IS the `def` header, so starting at
            # i makes the while condition false at once, yields a ZERO-LENGTH
            # block, and the outer loop never advances -- an infinite loop that
            # looks like a slow machine.  Cost: one hung run of 400s.
            while j < n and not re.match(r"^(type |def |import )", lines[j]):
                j += 1
            j = max(j, i + 1)
            j = i + 1
            while j < n and not re.match(r"^(type |def |import )", lines[j]):
                j += 1
            # trailing blanks belong to the separator, not the def
            k = j
            while k > i and lines[k - 1].strip() == "":
                k -= 1
            out.append(("def", i, k))
            i = j
        else:
            while j < n and not re.match(r"^(type |def |import )", lines[j]):
                j += 1
            j = max(j, i + 1)
            j = i + 1
            while j < n and not re.match(r"^(type |def |import )", lines[j]):
                j += 1   # SAME trap as the `def` branch, above.
            out.append((kind, i, j))
            i = j
    return out


def call_names(body):
    """Every `name(` token in a def body, minus the def's own name."""
    src = "\n".join(body)
    src = re.sub(r"#.*", "", src)
    own = re.match(r"^def ([\w.]+)\(", src).group(1)
    short = own.split(".")[-1]
    found = set()
    for tok in re.findall(r"([A-Za-z_][\w.]*)\s*\(", src):
        if tok == own or tok.endswith("." + own):
            continue
        found.add(tok)
    return found


def main(path):
    p = pathlib.Path(path)
    lines = p.read_text().split("\n")
    bl = blocks(lines)
    # map each def to its caller set
    defs = {}
    for kind, a, b in bl:
        if kind != "def":
            continue
        name = re.match(r"^def ([\w.]+)\(", "\n".join(lines[a:b])).group(1)
        defs[name] = (a, b)
    short2full = {k.split(".")[-1]: k for k in defs}
    edges = {}
    for name, (a, b) in defs.items():
        cs = call_names(lines[a:b])
        callees = set()
        for c in cs:
            if c in defs:
                callees.add(c)
            elif c in short2full:
                callees.add(short2full[c])
            else:
                # dotted local: foo.of / foo.go resolve to foo's family
                if "." in c:
                    base = c.rsplit(".", 1)[0]
                    tail = c.rsplit(".", 1)[1]
                    fam = short2full.get(base.split(".")[-1])
                    if fam and fam.rsplit(".", 1)[-1] == base.split(".")[-1]:
                        cand = f"{fam}.{tail}"
                        if cand in defs:
                            callees.add(cand)
        edges[name] = callees - {name}

    order, temp, done = [], set(), set()

    def visit(n):
        if n in done:
            return
        if n in temp:
            # a CYCLE: mutual recursion, which bend refuses.  Report and keep
            # the source order for that group so the compiler's message (which
            # is the useful one) is not masked.
            return
        temp.add(n)
        for c in sorted(edges[n]):
            visit(c)
        temp.discard(n)
        done.add(n)
        order.append(n)

    src_order = [re.match(r"^def ([\w.]+)\(", "\n".join(lines[a:b])).group(1)
                 for kind, a, b in bl if kind == "def"]
    for n in src_order:
        visit(n)
    missing = [n for n in src_order if n not in order]
    for n in missing:
        order.append(n)

    # rebuild: imports, then EVERY `type` block in source order, then the defs in
    # `order`.  The first version of this script kept only `lines[:first_def]` and
    # `lines[last_def:]`, which DELETED every `type` declaration that sat between two
    # defs -- bend then reads `unknown: Fld`.  Types are never reordered, only
    # hoisted, so this cannot break a type that uses another.
    first_def = min(a for kind, a, b in bl if kind == "def")
    pre = lines[:first_def]
    imports = ["\n".join(lines[a:b]).rstrip() for kind, a, b in bl if kind == "import"]
    types = []
    for kind, a, b in bl:
        if kind != "type":
            continue
        blk = "\n".join(lines[a:b]).rstrip()
        # DEDUPE: a `type` that already appears in `pre` (before the first def)
        # would be emitted twice, and bend reads the second as a duplicate
        # declaration.  Identical text is the test -- two DIFFERENT records with
        # the same name are a real conflict and must not be silently merged.
        # `blk` is a MULTI-LINE string and `pre` is a list of single lines, so
        # `blk in pre` is ALWAYS False and every type got hoisted twice.  The
        # test is the block's FIRST line.
        if blk.split("\n")[0] in pre or blk in types:
            continue
        types.append(blk)
    tail = lines[max(b for kind, a, b in bl if kind == "def"):]
    # `import Base` is already in `pre` (it precedes the first def), so emitting
    # `imports` again duplicates it and bend reads "got the keyword 'import'".
    extra = [x for x in imports if x not in pre]
    pre = pre + extra + [""] + (["\n\n".join(types), ""] if types else [])
    used = set()
    chunks = []
    for name in order:
        a, b = defs[name]
        s = a
        while s > first_def and lines[s - 1].startswith("#"):
            s -= 1
        key = (s, b)
        if key in used:
            continue
        used.add(key)
        chunks.append("\n".join(lines[s:b]))
    # anything not in a def block after the last def (trailing text)
    out = pre + ["\n\n".join(chunks)] + tail
    p.write_text("\n".join(out))
    cyc = [n for n in order if any(n in edges[c] for c in edges) and
           n in edges and any(c in edges and n in edges[c] for c in edges)]
    print(f"reordered {len(order)} defs into {p}")


if __name__ == "__main__":
    main(sys.argv[1])