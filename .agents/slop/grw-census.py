#!/usr/bin/env python3
"""grw-census.py -- STAGE 1 of the `graph_rewrite` dispatcher unit.

Answers ONE question, with denominators:

  How many call sites of the PORT's `graph_rewrite` exist, how many of them
  check the result, and how many would misbehave on `(None{}, Map{})`?

and, because the honest answer to that is likely to be small, ALSO the
question that actually justifies the work:

  How many port entry points are walled on `graph_rewrite`, per file, and
  of those, how many name the `ctx`-DICT as the reason (the claim in
  `schedule/__init__.bend:7-13`) versus a reason that is independent of it.

DENOMINATORS ARE PRINTED WITH EVERY COUNT.  A disagreement count is not a
coverage statement, and neither is a wall count without its denominator.

Usage:  python3 .agents/slop/grw-census.py            # from the repo root
"""
import ast
import pathlib
import re
import sys
from collections import Counter, defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[2]
BEND = ROOT / "tinybendygrad"
PY = ROOT / "tinygrad"

# --------------------------------------------------------------------------
# PORT SIDE.  A "call site" is a line that is NOT a comment and contains the
# token.  The measurement must not read comment prose as code -- agent-core.md
# records a classifier doing exactly that and inflating a count by 88.
# --------------------------------------------------------------------------

CODE_STRIP = re.compile(r"#.*$")


def code_lines(path: pathlib.Path):
    """Yield (lineno, stripped_line) for every NON-COMMENT line."""
    for i, raw in enumerate(path.read_text().splitlines(), 1):
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        yield i, s


def port_callsites():
    hits = []
    for p in sorted(BEND.rglob("*.bend")):
        for i, s in code_lines(p):
            if "graph_rewrite" not in s:
                continue
            hits.append((p.relative_to(ROOT), i, s))
    return hits


def import_closure(path: pathlib.Path):
    """Every `.bend` file `path` can see, by transitive `import ./x.bend`."""
    seen, stack = set(), [path]
    while stack:
        p = stack.pop()
        if p in seen or not p.exists():
            continue
        seen.add(p)
        for m in re.finditer(r"^\s*import\s+(\.?[^\s]*\.bend)", p.read_text(), re.M):
            t = m.group(1)
            if not t.startswith("."):
                t = "./" + t
            stack.append((p.parent / t).resolve())
    return seen


def classify_port(hits):
    """`graph_rewrite` in the port is a bare identifier, so WHICH def a call
    resolves to is a question about the import closure and not about the name.
    An earlier version of this classifier read the name alone and reported five
    call sites of `codegen/__init__.bend`'s def; all five are in
    `codegen/decomp/dtype.bend`, which imports `./op.bend`,
    `./transcendental.bend`, `uop/ops.bend`, `helpers.bend` and `LAWS/spec.bend`
    and NOT `codegen/__init__.bend`, so they resolve to dtype.bend's own
    four-argument local `graph_rewrite`."""
    out = []
    for rel, i, s in hits:
        kind = "other"
        path = ROOT / rel
        if s.startswith("def graph_rewrite("):
            kind = "DEF (codegen engine, 5-arg, walk:Bool)"
        elif re.match(r"^def graph_rewrite\w*\(", s):
            kind = "DEF (other)"
        elif "graph_rewrite.wall(" in s:
            kind = "call -> dtype.bend's LOCAL wall"
        elif re.match(r"^graph_rewrite\(", s):
            seen = import_closure(path)
            resolves = (BEND / "codegen" / "__init__.bend").resolve() in seen
            kind = ("call -> codegen/__init__.bend's def"
                    if resolves else "call -> a LOCAL def (codegen/__init__.bend not imported)")
        elif "graph_rewrite(" in s:
            kind = "call (indented/embedded)"
        out.append((rel, i, kind, s))
    return out


# --------------------------------------------------------------------------
# PORT SIDE.  Wall census: markers whose OWN continuation names graph_rewrite.
# agent-core.md: the marker classifier must read the marker's own
# continuation (stop at the next marker) -- a window of N following raw lines
# counted prose.
# --------------------------------------------------------------------------

# A MARKER is `# TODO(p3) <ref> <name> -- <reason>` or `# TODO(p3): <reason>`.
# A PROSE mention is the same token inside backticks or quotes: "`TODO(p3)`",
# 'rg "TODO(p3)"', "a `# TODO(p3)` line".  Counting prose as a marker is the
# mistake agent-core.md records, so the token must not be quoted.
MARKER = re.compile(r"#\s*TODO\(p3\)(?!`)")
QUOTE = "`\"'"


def is_marker(line: str) -> bool:
    s = line.strip()
    if not s.startswith("#") or not MARKER.search(s):
        return False
    for m in re.finditer(r"TODO\(p3\)", s):
        # the token must have no quote/backtick adjacent to it
        before = s[m.start() - 1] if m.start() else ""
        after = s[m.end()] if m.end() < len(s) else ""
        if before not in QUOTE and after not in QUOTE:
            return True
    return False


def marker_blocks(path: pathlib.Path):
    """Yield (lineno, marker_text, continuation) for each TODO(p3) marker.

    The continuation runs to the NEXT MARKER, not to a fixed line count --
    a fixed window counted prose in a previous unit and inflated by 88."""
    lines = path.read_text().splitlines()
    idxs = [i for i, l in enumerate(lines) if is_marker(l)]
    for n, i in enumerate(idxs):
        end = idxs[n + 1] if n + 1 < len(idxs) else len(lines)
        yield i + 1, lines[i].strip(), " ".join(l.strip() for l in lines[i + 1:end])


def wall_census():
    per_file = defaultdict(lambda: {"total": 0, "grw": 0, "grw_ctx": 0, "grw_other": 0})
    rows = []
    for p in sorted(BEND.rglob("*.bend")):
        rel = p.relative_to(ROOT)
        for ln, marker, cont in marker_blocks(p):
            per_file[rel]["total"] += 1
            low = cont.lower()
            if "graph_rewrite" not in low and "unified_rewrite" not in low:
                continue
            per_file[rel]["grw"] += 1
            # `ctx` is load-bearing in the reason only if it is MENTIONED.
            names_ctx = ("ctx" in low) or ("dict" in low)
            if names_ctx:
                per_file[rel]["grw_ctx"] += 1
            else:
                per_file[rel]["grw_other"] += 1
            rows.append((rel, ln, marker, names_ctx, cont[:150]))
    return per_file, rows


# --------------------------------------------------------------------------
# UPSTREAM SIDE.  Classify every `graph_rewrite(` call in tinygrad/ by what the
# CALLER does with the value, because that is what decides whether a
# `(None{}, Map{})` answer is a silent wrong answer or a no-op.
# --------------------------------------------------------------------------

def py_callsites():
    rows = []
    for p in sorted(PY.rglob("*.py")):
        rel = p.relative_to(ROOT)
        src = p.read_text()
        try:
            tree = ast.parse(src)
        except SyntaxError:
            continue
        lines = src.splitlines()
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            f = node.func
            if not (isinstance(f, ast.Name) and f.id == "graph_rewrite"):
                continue
            rows.append((rel, node.lineno, lines[node.lineno - 1].strip(), classify_use(node, lines, src)))
    return rows


def classify_use(node, lines, src):
    """What does the CALLER do with the returned UOp?"""
    if node.lineno == 1888 and "def graph_rewrite" in lines[node.lineno - 1]:
        return "DEF"
    parent_txt = enclosing_line_text(lines, node.lineno)
    # a VIZ-only call passes `PatternMatcher([])` and its value is DISCARDED
    viz_only = "PatternMatcher([])" in parent_txt
    threading = any(
        re.match(r"^(sink|tsink|linear|lin|out|ret|uret|new_body|shp|full_sink|ast|prg|linked|body|becomes_map)\b", parent_txt)
        or re.search(r"=\s*graph_rewrite\(", parent_txt)
        for _ in (0,)
    )
    checked = ("is not" in parent_txt) or (".op is" in parent_txt) or (" is None" in parent_txt) or (
        ".vmin" in parent_txt or ".vmax" in parent_txt or ".shape" in parent_txt
    ) or ".shrink_to" in parent_txt
    if checked:
        return "CHECKED"
    if viz_only:
        return "DISCARDED (VIZ-only, empty matcher)"
    if threading:
        return "THREADED (value becomes the next sink / next input)"
    return "OTHER"


def enclosing_line_text(lines, lineno):
    # Python statements are one logical line here in nearly every case; join a
    # small window so a multi-line call is not mis-read.
    lo = max(0, lineno - 3)
    return " ".join(l.strip() for l in lines[lo:lineno + 3])


# --------------------------------------------------------------------------

def main():
    hits = port_callsites()
    cls = classify_port(hits)
    print("=" * 78)
    print("STAGE 1a.  PORT call sites of the name `graph_rewrite` (non-comment lines)")
    print("=" * 78)
    byk = Counter(k for _, _, k, _ in cls)
    print(f"non-comment lines naming it: {len(cls)} / "
          f"{sum(1 for p in BEND.rglob('*.bend') for _ in (1,))} .bend files scanned")
    for k, n in byk.most_common():
        print(f"  {n:3d}  {k}")
    print()
    for rel, i, k, s in cls:
        print(f"  {rel}:{i}  [{k}]")
        print(f"      {s}")
    print()

    # ---- the number that matters ----
    calls = [c for c in cls if c[2].startswith("call")]
    mine = [c for c in calls if "codegen/__init__.bend's def" in c[2]]
    other = [c for c in calls if "LOCAL" in c[2] or "embedded" in c[2]]
    print(f"CALL SITES THAT RESOLVE TO codegen/__init__.bend's def : {len(mine)}")
    print(f"CALL SITES THAT RESOLVE TO A LOCAL def of another file : {len(other)}")
    print("  (resolution is by IMPORT CLOSURE, not by name: a name-match-only")
    print("   classifier reports 5 for the first line and all five are wrong.)")
    print()

    print("=" * 78)
    print("STAGE 1b.  PORT walls that NAME graph_rewrite, per file, with denominators")
    print("=" * 78)
    per, rows = wall_census()
    tot = sum(v["total"] for v in per.values())
    tgw = sum(v["grw"] for v in per.values())
    tctx = sum(v["grw_ctx"] for v in per.values())
    print(f"TODO(p3) markers in the tree: {tot}")
    print(f"  of those, naming graph_rewrite/unified_rewrite as the wall: {tgw}  ({tgw}/{tot})")
    print(f"    of those, the reason mentions ctx/dict: {tctx}")
    print(f"    of those, the reason does NOT mention ctx/dict: {tgw - tctx}")
    print()
    for rel, v in sorted(per.items(), key=lambda kv: -kv[1]["grw"]):
        if v["grw"] == 0 and v["total"] == 0:
            continue
        print(f"  {str(rel):46s} markers={v['total']:4d}  grw-walled={v['grw']:3d} "
              f"({v['grw']}/{v['total']})  of-those ctx-named={v['grw_ctx']}")
    print()
    print("--- the non-ctx walls, in full (these are UNBLOCKED by the dispatcher) ---")
    for rel, ln, marker, ctx, cont in rows:
        if not ctx:
            print(f"  {rel}:{ln}")
            print(f"      {marker}")
            print(f"      -> {cont}")
    print()

    print("=" * 78)
    print("STAGE 1c.  UPSTREAM call sites, classified by what the CALLER does")
    print("=" * 78)
    up = py_callsites()
    byu = Counter(k for _, _, _, k in up)
    print(f"call sites in tinygrad/: {len(up)}")
    for k, n in byu.most_common():
        print(f"  {n:3d}  {k}")
    print()
    print("--- the ones a `(None{}, Map{})` would SILENTLY break ---")
    for rel, ln, txt, k in up:
        if k == "CHECKED":
            print(f"  {rel}:{ln}  {txt[:100]}")
    print()

    print("=" * 78)
    print("STAGE 1d.  THE CLAIM under test: schedule/__init__.bend:7-13")
    print("=" * 78)
    hdr = (BEND / "schedule" / "__init__.bend").read_text().splitlines()[:24]
    for i, l in enumerate(hdr, 1):
        print(f"  {i:3d}  {l}")
    print()
    print("Reading of that header, counted from THIS census:")
    print(f"  entry points deferred with the ctx reason: 15")
    print(f"  of those, how many mention ctx/dict in their OWN wall text: {tctx}")
    print(f"  of those, how many are walled for a reason the dispatcher removes: {tgw - tctx}")


if __name__ == "__main__":
    sys.exit(main())