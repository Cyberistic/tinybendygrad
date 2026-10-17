#!/usr/bin/env python3
"""opsref-census.py -- CLASSIFY every `Ops.GROUP` / `Ops.FLIP` SITE, and MEASURE every renumbering.

    .venv/bin/python gates/opsref-census.py              # the census
    .venv/bin/python gates/opsref-census.py --rows F     # TSV: class, op, file:line, def

WHAT IT IS FOR. Upstream deleted `Ops.GROUP` and `Ops.FLIP` (77 -> 75) and REIMPLEMENTED both
behaviours without the ops (`Tensor.flip` is now transpose/PAD/SHRINK, `UOp.group` is now
`UOp(Ops.STACK).after(...)`), so the port's references are not all the same kind of thing and a
count is not a work estimate. This classifies every occurrence and prints the renumberings.

A REFERENCE IS NOT NECESSARILY A USE. The classes are separated by one discriminator -- **would
deleting the op change behaviour, and what kind?** -- because the prior 70 was an import-closure
number that mixes all four kinds.

  EMIT    the op is the OPERAND of a node constructor. Deleting it changes a GRAPH.
  CONSUME the op is a KEY of a `match` / `op_in` / `is_*` / `sp_op` / `lt_op_is` / name-string test.
          Deleting it changes a DECISION.
  SHAPE   the op is an ITEM of an ENUMERATION: the `type Op is Data:` block, an `Ops.value` arm,
          an `Ops.name.of` arm, an `all_ops` entry, or a literal op-list a file returns as data
          (`dd_ops.all`, `GS_ALL`, `OP_ALL`, `op_list`, `pr_ear_keys`, a written-out
          `GroupOp.Movement`, `PSEUDO_OPS`, a `PMEntry{tag,[ops]}` row, a ladder rung).
          Deleting it RENUMBERS, and the renumbering is measured below, not asserted.
  PROSE   inside a comment, or inside a string that is not a match key. Deleting it changes NOTHING,
          and costs a `file:line` citation that `gates/citations-census-gate.py` grades -- so the
          honest plan for PROSE is "leave it and say why", not "delete it".

POPULATION, AND WHY IT IS NOT A LIST. `os.walk` over `tinybendygrad/**/*.bend` INTERSECTED with
`git ls-tree -r HEAD -- tinybendygrad` -- the COMMIT, never `git ls-files`, because `jj` colocation
arms git's index and an armed index makes `git ls-files` report the working copy as staged. The
four enumeration tables are named by `gates/opseven-gate.py`'s OWN parsers (`_declared_ops`,
`_value_arms`, `_name_arms`, `_all_ops`), imported BY PATH, so the SHAPE set is that instrument's
declaration and not a transcription here (AGENTS.md doctrine 1).

TWO ORDERING HAZARDS, BOTH MEASURED ON THIS FILE BEFORE IT GOT THE ORDER RIGHT:
  * `case O.OpsFLIP{}: mm.lift.mv(srcs)` matches a constructor-ish regex on `mm.lift` and reads as
    EMIT. It is CONSUME: `mm.lift.mv` is the READER THE ARM SELECTS. So `CASE_ARM` is tested
    BEFORE `CTOR`.
  * the enclosing-`def` locator must skip the site's own line and must require the def's indent to
    be STRICTLY LESS than the site's. A sibling line at equal indent is not a scope, and returning
    it reported `<module>` for every site in the tree.
"""

import importlib.util
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
REMOVED = ("GROUP", "FLIP")

# the generator's own parsers, LOADED BY PATH
_spec = importlib.util.spec_from_file_location("opseven_gate", HERE / "opseven-gate.py")
OG = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(OG)

SITE = re.compile(r"\bOps(GROUP|FLIP)\b")
CASE_ARM = re.compile(r"^\s*case\s+(O\.)?Ops(GROUP|FLIP)\{\}")
CTOR = re.compile(
    r"\b(UOp\.new|UOp\.make|f_new|ix_g3|mm\.lift|tn_mop|g_ds_row|lf_row|Wk\{|O\.Node\{|O\.WK)")
TEST = re.compile(
    r"\b(op_in|is_any\d|is_op|lt_op_is|sy_op_in|sy_is_op|sp_op|sp_op_in|op_color|op_of|opname"
    r"|fz_op|dispatch|match op|case \")")
NAME_ARM = re.compile(r'^\s*case Ops(GROUP|FLIP)\{\}: "')
VALUE_ARM = re.compile(r"^\s*case Ops(GROUP|FLIP)\{\}: \d+\s*$")
DECL_ARM = re.compile(r"^\s*Ops(GROUP|FLIP)\{\}\s*$")


def tracked_bend() -> list[str]:
    """`.bend` paths under `tinybendygrad` that exist NOW and are in the COMMIT tree.

    The intersection matters: a mutation harness leaves untracked `*-mut.bend` copies beside the
    substrate (MEASURED 10 of 141 at the time of writing, two of which carry a duplicate of these
    refs), and an import-closure count that includes them is counting a scratch file.
    """
    out = subprocess.run(
        ["git", "ls-tree", "-r", "HEAD", "--name-only", "--", "tinybendygrad"],
        cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
    return sorted({p for p in out if p.endswith(".bend") and os.path.isfile(ROOT / p)})


def walk_bend() -> list[str]:
    """The same walk with no git filter, so the two numbers can be compared rather than assumed.

    RELATIVE to `ROOT`, like `tracked_bend()`: the two are differenced below, and a set difference
    between an absolute and a relative path is the whole population. The first version of this
    printed `UNTRACKED = 141` and listed every file in the tree, which is what a difference of
    disjoint representations looks like and is indistinguishable from a real finding."""
    return sorted(str((Path(d) / n).relative_to(ROOT)) for d, _, ns in os.walk(ROOT / "tinybendygrad")
                  for n in ns if n.endswith(".bend"))


def enclosing(lines: list[str], i: int) -> str:
    """The nearest ENCLOSING `def`, by indentation. The durable locator: `opseven-gate._body()`
    insists that "a locator that a rename invalidates is not a locator", so every row carries a
    def NAME beside the line number."""
    own = re.match(r"def ([A-Za-z0-9_.$]+)", lines[i].strip())
    if own:
        return own.group(1)
    indent = len(lines[i]) - len(lines[i].lstrip())
    for j in range(i - 1, -1, -1):
        s = lines[j]
        if not s.strip() or s.lstrip().startswith("#"):
            continue
        if len(s) - len(s.lstrip()) >= indent:
            continue
        m = re.match(r"def ([A-Za-z0-9_.$]+)", s.strip())
        if m:
            return m.group(1)
        if re.match(r"(type|law)\s", s.strip()):
            return "<DATA BLOCK>"
    return "<module>"


def code_part(line: str) -> str:
    """The line with its trailing COMMENT removed, respecting string literals -- `#` inside a
    string is not a comment. This is the only difference between a site and a PROSE citation."""
    q = False
    for k, ch in enumerate(line):
        if ch == '"':
            q = not q
        elif ch == "#" and not q:
            return line[:k]
    return line


def classify(line: str, in_ops_bend_tables: bool) -> str:
    cut = code_part(line)
    if not SITE.search(cut):
        return "PROSE"
    if in_ops_bend_tables and (DECL_ARM.match(cut) or NAME_ARM.match(cut) or VALUE_ARM.match(cut)):
        return "SHAPE"
    # ORDER IS LOAD-BEARING: a `case` arm is a KEY before it is anything else.
    if CASE_ARM.match(cut):
        return "CONSUME"
    if CTOR.search(cut):
        return "EMIT"
    if TEST.search(cut):
        return "CONSUME"
    return "SHAPE"


def census() -> list[dict]:
    rows = []
    for rel in tracked_bend():
        lines = (ROOT / rel).read_text().splitlines()
        tables = rel.endswith("uop/ops.bend")
        for i, ln in enumerate(lines):
            klass = classify(ln, tables)
            if klass is None:
                continue
            for m in SITE.finditer(code_part(ln)) or []:
                pass
            if klass == "PROSE" and not SITE.search(ln):
                continue
            for m in SITE.finditer(code_part(ln)):
                rows.append(dict(klass=klass, op=m.group(1), file=rel, line=i + 1,
                                 defname=enclosing(lines, i)))
    return rows


def renumbering() -> None:
    """MEASURE every renumbering. `Ops.value` is an INDEX, so removing a variant moves every arm
    below it; `PMEntry{tag,[ops]}` carries the tag as an explicit FIELD, so removing a tag moves
    every tag above it. Neither number is asserted anywhere in the tree today."""
    decl = OG._declared_ops()
    value = OG._value_arms()
    pos = {n: i for i, n in enumerate(decl, 1)}
    rm = sorted(pos[n] for n in REMOVED if n in pos)
    print(f"\n== (a) `Ops.value`: declared={len(decl)}, removed at 1-based positions {rm}")
    buckets: dict[str, list] = {"unchanged": [], "shift -1": [], "shift -2": [], "deleted": []}
    for i, (name, v) in enumerate(value, 1):
        if i in rm:
            buckets["deleted"].append((i, name, int(v)))
            continue
        d = (i - sum(1 for r in rm if r < i)) - i
        buckets["unchanged" if d == 0 else (f"shift {d:+d}")].append((i, name, int(v)))
    for k, b in buckets.items():
        span = f" positions {b[0][0]}..{b[-1][0]}" if b else ""
        eg = f"  {b[0][1]}: {b[0][2]}->{b[0][0] - sum(1 for r in rm if r < b[0][0])}" if b else ""
        print(f"     {k:10s} n={len(b):3d}{span}{eg}")
    ren = len(buckets["shift -1"]) + len(buckets["shift -2"])
    print(f"     => {ren} of {len(value)} arms RENUMBER. The `58` is the shift-by-one band alone; "
          f"a second band of {len(buckets['shift -2'])} moves by two, so quoting 58 alone "
          f"undercounts.")
    for label, keys in (("Ops.name.of", [n for n, _ in OG._name_arms()]), ("all_ops", OG._all_ops())):
        hits = [(i, n) for i, n in enumerate(keys, 1) if n in REMOVED]
        print(f"     {label:12s} n={len(keys)} -> {len(keys) - len(hits)}; entries at {hits}. "
              f"KEYED, not positional: no other entry moves.")

    print("\n== (b) `O.PMEntrys{[ ... ]}` tables carrying the tag as a FIELD")
    for rel in sorted((ROOT / "tinybendygrad").rglob("*.bend")):
        src = rel.read_text()
        for m0 in re.finditer(r"O\.PMEntrys\{\[", src):
            depth, j = 0, m0.end() - 1
            while j < len(src):
                if src[j] == "[":
                    depth += 1
                elif src[j] == "]":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            body = src[m0.end():j]
            pairs = re.findall(r"O\.PMEntry\{(\d+),\s*(\[[^\]]*\]|\w+\(\))", body, re.S)
            hits = [(int(t), b) for t, b in pairs if SITE.search(b)]
            if not hits:
                continue
            lineno = src[:m0.start()].count("\n") + 1
            top = max(t for t, _ in hits)
            above = sum(1 for t, _ in pairs if int(t) > top)
            # the OPS each hit row carries, read out of its own body -- a row may carry both, and
            # `"GROUP" in b` on a body that also has SINK labels the row 'GROUP' twice over.
            labels = [(t, sorted({m.group(1) for m in SITE.finditer(b)})) for t, b in hits]
            print(f"     {rel.relative_to(ROOT)}:{lineno}  tags={len(pairs)} "
                  f"(0..{max(int(t) for t, _ in pairs)})  hits={labels}"
                  f"  => {above} tags above shift by -{len(hits)}")


def main() -> int:
    walk, tracked = walk_bend(), tracked_bend()
    untracked = sorted(set(walk) - set(tracked))
    rows = census()
    c = Counter(r["klass"] for r in rows)
    print(f"walk(tinybendygrad/**/*.bend) = {len(walk)}; tracked in HEAD = {len(tracked)}; "
          f"UNTRACKED (mutation-harness copies, NOT substrate) = {len(untracked)}")
    for u in untracked:
        print(f"    {u}")
    print(f"\nSITES = {sum(c.values())} occurrences on {len({(r['file'], r['line']) for r in rows})} "
          f"lines in {len({r['file'] for r in rows})} files")
    for k in ("EMIT", "CONSUME", "SHAPE", "PROSE"):
        g = sum(1 for r in rows if r["klass"] == k and r["op"] == "GROUP")
        f = sum(1 for r in rows if r["klass"] == k and r["op"] == "FLIP")
        print(f"    {k:8s} {g + f:3d}   GROUP={g:3d}  FLIP={f:3d}")
    for k in ("EMIT", "CONSUME", "SHAPE", "PROSE"):
        sel = [r for r in rows if r["klass"] == k]
        if not sel:
            print(f"\n-- {k}: NONE")
            continue
        print(f"\n-- {k} ({len(sel)}) --")
        seen: set[tuple[str, int]] = set()
        for r in sel:
            key = (r["file"], r["line"])
            mult = ""
            if key not in seen:
                seen.add(key)
                n = sum(1 for q in sel if (q["file"], q["line"]) == key)
                if n > 1:
                    mult = f" x{n}"
            else:
                continue
            print(f"   {r['op']:5s} {r['file'].replace('tinybendygrad/', '')}:{r['line']:<5d} "
                  f"{r['defname']}{mult}")
    renumbering()
    if "--rows" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--rows") + 1])
        out.write_text("".join(f"{r['klass']}\t{r['op']}\t{r['file']}:{r['line']}\t{r['defname']}\n"
                               for r in rows))
        print(f"\nwrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())