#!/usr/bin/env python3
"""ARGOWNER census: the `Arg` EXHAUSTIVENESS SURFACE of tinybendygrad/uop/ops.bend.

POPULATION (all three, by the rules in AGENTS.md; none is a hand list):

  (a) the CONSTRUCTORS are PARSED out of the generator's own declaration:
      `type Arg is Data:` at tinybendygrad/uop/ops.bend, every indented `Ctor{...}`
      line under it.  Not typed here.  A typo in this file cannot inflate the
      denominator because the file is not read from this file.

  (b) the FILES are a DIRECTORY WALK: os.walk(tinybendygrad), *.bend.  A hand list
      of "the files that mention Arg" is exactly the failure class this census
      exists to kill.

  (c) the ALIAS is DERIVED, not assumed: the walk reads every
      `import ./../.../uop/ops.bend as X` line and takes X.  There are five OTHER
      `type Arg is Data:` declarations in the tree (renderer/amd/dsl.bend,
      engine/worker.bend, runtime/ops_python.bend, runtime/ops_cl.bend,
      runtime/support/hcq2.bend) -- `Arg` is a NAME in Bend, not a unique type.
      A census that greps `\bArg\b` and reports "one population" has conflated
      six.  The constructors that matter are `O.<Ctor>` and, inside ops.bend
      itself, the bare `<Ctor>`.

WHAT IS COUNTED AS A SITE: a `match` block (either shape -- multi-line arms, or
the one-line `match x: case P: e` form) with at least one arm naming a member of
the parsed population.  Sites are keyed (file, def, match_line).

CLASSIFICATION:
  exhaustive  -- names EVERY parsed ctor AND has no wildcard arm
  wildcarded  -- has a `case _` arm (so a new ctor cannot break it)
  incomplete  -- names some ctors, no wildcard: ALREADY RED, or partially total
  Note `ABad` is a REAL constructor, not a wildcard; `case O.ABad{}` is one named
  member like any other.

THE ZERO THAT IS NOT ZERO: if the parse of `type Arg is Data:` yields 0 ctors,
this file exits 3 with REFUSED rather than printing "0 sites".  AGENTS.md records
that failure twice.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
PORT = os.path.join(ROOT, "tinybendygrad")
OPS = os.path.join(PORT, "uop", "ops.bend")

TYPE_RE = re.compile(r"^type\s+(\w+)\s+is\s+Data:\s*(.*)$")
CTOR_RE = re.compile(r"^(\s+)([A-Z]\w*)\s*\{")
IMPORT_RE = re.compile(r"^import\s+(\S*ops\.bend)\s+as\s+(\w+)\s*$")
DEF_RE = re.compile(r"^(\s*)def\s+([\w.]+)")
MATCH_RE = re.compile(r"^(\s*)match\s+(.+?):\s*(.*)$")
CASE_RE = re.compile(r"^(\s*)case\s+(.+?):\s*(.*)$")
WILD_RE = re.compile(r"^_\w*$")


def ctors_of(path, want):
    """PARSED constructor list of `type <want> is Data:` in `path`."""
    lines = []
    with open(path) as fh:
        lines = fh.read().split("\n")
    for i, ln in enumerate(lines):
        m = TYPE_RE.match(ln)
        if not m or m.group(1) != want:
            continue
        name, inline = m.group(1), m.group(2)
        out = []
        rest = inline
        j = i + 1
        while True:
            if rest:
                c = CTOR_RE.match("  " + rest) or re.match(r"^\s*([A-Z]\w*)\s*\{", rest)
                if c:
                    out.append(c.group(1))
                    rest = ""
            if j >= len(lines):
                break
            nxt = lines[j]
            if nxt.strip() and not nxt.startswith((" ", "\t")):
                break  # dedented past the block
            if nxt.strip():
                c = CTOR_RE.match(nxt)
                if c:
                    out.append(c.group(2))
                elif not nxt.lstrip().startswith("#"):
                    break
            j += 1
        return name, out
    return None, []


def walk_bend():
    """(b) DIRECTORY WALK. Excludes nothing by hand: the nested duplicate that
    flipthird measured is gone (`ls` rc=2 today), and the count is printed."""
    files = []
    for dirpath, dirnames, filenames in os.walk(PORT):
        dirnames.sort()
        for fn in sorted(filenames):
            if fn.endswith(".bend"):
                files.append(os.path.join(dirpath, fn))
    return files


def aliases(files):
    """(c) DERIVED alias of ops.bend: every `import .../ops.bend as X`."""
    out = set()
    for f in files:
        with open(f) as fh:
            for ln in fh:
                m = IMPORT_RE.match(ln)
                if m:
                    out.add(m.group(2))
    return out


def blocks(lines):
    """Yield (match_line, indent, arms) for every match, both shapes."""
    i, n = 0, len(lines)
    while i < n:
        m = MATCH_RE.match(lines[i])
        if not m:
            i += 1
            continue
        indent, head, tail = len(m.group(1)), m.group(2), m.group(3)
        start, arms = i, []
        if tail.strip().startswith("case "):
            # one-line form: `match x: case P: e` -- arms run to end of line
            for seg in re.split(r"(?=\bcase\s)", tail.strip()):
                seg = seg.strip()
                if seg.startswith("case "):
                    c = re.match(r"case\s+(.+?):\s*(.*)$", seg, re.S)
                    if c:
                        arms.append(c.group(1))
            yield start, indent, arms, "oneline"
            i += 1
            continue
        j = i + 1
        while j < n:
            ln = lines[j]
            if ln.strip() and not ln.startswith(" " * (indent + 1)):
                break  # dedented out of the match
            c = CASE_RE.match(ln)
            if c and len(c.group(1)) == indent + 2:
                arms.append(c.group(2))
            j += 1
        yield start, indent, arms, "block"
        i = j


def main():
    files = walk_bend()
    alias = aliases(files)
    name, ctors = ctors_of(OPS, "Arg")
    if name != "Arg":
        print(f"REFUSED: parsed type name {name!r} from {OPS}, expected 'Arg'")
        return 3
    if not ctors:
        print("REFUSED: parsed ZERO constructors -- that is a None, not a zero")
        return 3
    # names a ctor under any alias, or bare inside ops.bend itself
    variants = set(alias) | {""}  # "" = ops.bend's own unqualified arms
    cset = set(ctors)

    def names_ctor(pat, variants):
        # a pattern can be a TUPLE of patterns (`match arg op:` -> `case _ _:`)
        parts = [p for p in re.split(r"[,|]", pat)]
        hit = None
        for part in parts:
            mm = re.match(r"(?:(\w+)\.)?([A-Z]\w*)\s*\{", part.strip())
            if mm and mm.group(2) in cset and (mm.group(1) or "") in variants:
                hit = mm.group(2)
        # WILDCARD: every conjunct is `_` or a bare binder, i.e. the arm cannot
        # be broken by a new ctor.  `case _` and `case _ _` are both total.
        toks = pat.split()
        wild = bool(toks) and all(re.fullmatch(r"_\w*", t) for t in toks)
        return hit, wild

    rows, tot, exh, wild, inc = [], 0, 0, 0, 0
    for f in files:
        rel = os.path.relpath(f, ROOT)
        with open(f) as fh:
            lines = fh.read().split("\n")
        # enclosing `def` for each line: a def starts at indent 0, so the LAST
        # def at or before the match line is the enclosing one.  Tracked by
        # scanning the file once, not by re-parsing per block.
        def_at = []
        cur = None
        for ln in lines:
            d = DEF_RE.match(ln)
            if d:
                cur = d.group(2)
            def_at.append(cur)

        for start, indent, arms, shape in blocks(lines):
            if not arms:
                continue
            cur_def = def_at[start]
            seen, has_wild, foreign = set(), False, 0
            # UNQUALIFIED ctor patterns are legal ONLY inside ops.bend itself.
            # Allowing them everywhere is a false-positive generator: engine/worker.bend
            # has its OWN `type Arg is Data:` (AU32, AStr) and its bare `case AStr{s}`
            # was scored as ops.bend's `AStr`.  MEASURED: that one bug put a phantom
            # site in the census (189/36 -> 188/35).
            local = variants if f == OPS else {a for a in variants if a}
            for pat in arms:
                pat = pat.strip()  # bend pads: `case _         : Nil{}`
                hit, w = names_ctor(pat, local)
                if w:
                    has_wild = True
                elif hit:
                    seen.add(hit)
                elif not re.match(r"^\(", pat):
                    foreign += 1
            if not seen:
                continue
            tot += 1
            missing = [c for c in ctors if c not in seen]
            if has_wild:
                kind = "wildcarded"
                wild += 1
            elif not missing:
                kind = "EXHAUSTIVE"
                exh += 1
            else:
                kind = "INCOMPLETE"
                inc += 1
            rows.append((rel, start + 1, cur_def or "?", kind, shape,
                         len(arms), ",".join(missing) if missing else "-"))

    rows.sort()
    print(f"# ARGOWNER census -- the Arg exhaustiveness surface")
    print(f"# population(a): PARSED from {os.path.relpath(OPS, ROOT)} `type {name} is Data:`"
          f" -- {len(ctors)} constructors")
    print(f"#   {' '.join(ctors)}")
    print(f"# population(b): os.walk(tinybendygrad) *.bend -- {len(files)} files")
    print(f"# population(c): DERIVED aliases of ops.bend -- {sorted(alias)}")
    print(f"# NEGATIVE CONTROL: 5 OTHER `type Arg is Data:` exist in the tree; "
          f"`\\bArg\\b` is a NAME in Bend, not a type. Constructors were qualified by "
          f"the derived alias so those five are NOT counted here.")
    print()
    print(f"{'file':52s} {'line':>5s}  {'kind':12s} {'shape':7s} arms missing")
    for r in rows:
        print(f"{r[0]:52s} {r[1]:5d}  {r[3]:12s} {r[4]:7s} {r[5]:5d} {r[6]}")
    print()
    print(f"# SITES (matches naming >=1 Arg ctor), scope = all {len(files)} .bend "
          f"files under tinybendygrad/: {tot}")
    print(f"#   EXHAUSTIVE (names all {len(ctors)}, no wildcard) -- a new ctor BREAKS these: {exh}")
    print(f"#   WILDCARDED (`case _`) -- a new ctor cannot break these: {wild}")
    print(f"#   INCOMPLETE (no wildcard, missing ctors) -- ALREADY RED: {inc}")
    print(f"# CLOSED SET (exhaustive + incomplete), i.e. the real owner surface: {exh + inc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())