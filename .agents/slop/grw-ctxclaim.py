#!/usr/bin/env python3
"""grw-ctxclaim.py -- is the deferral reason in `schedule/__init__.bend:7-13`
TRUE?

The header claims, in one sentence, a reason for all fifteen entry points of
`tinygrad/schedule/__init__.py:82-301`:

  "every rule in it is a `graph_rewrite` over the arena with a PYTHON `ctx`
   DICT, and these rules need the ctx to be a MUTABLE accumulator threaded
   through the pass"

Three claims, separable, and this script MEASURES each from the AST rather
than accepting it:

  C1  every one of the fifteen is a `graph_rewrite` caller
  C2  every one of them passes a `ctx` DICT
  C3  that DICT is a MUTABLE accumulator (some rule WRITES it)

A claim that fails is reported as failing.  Denominators everywhere.

Expectations come from the SOURCE, so this file contains no hand-typed
verdicts -- only the three questions.
"""
import ast
import pathlib
import re
import sys
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "tinygrad" / "schedule" / "__init__.py"
LO, HI = 82, 301  # the deferred region named by the header


def load():
    text = SRC.read_text()
    return text, ast.parse(text)


def top_level_defs(tree):
    """Every top-level def/class whose line falls in [LO, HI]."""
    out = []
    for n in tree.body:
        ln = getattr(n, "lineno", None)
        if ln is None or not (LO <= ln <= HI):
            continue
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            out.append((ln, "def", n.name, n))
        elif isinstance(n, ast.ClassDef):
            out.append((ln, "class", n.name, n))
    return out


def gr_calls(node):
    """graph_rewrite calls made DIRECTLY by this def's own body."""
    calls = [n for n in ast.walk(node)
             if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
             and n.func.id == "graph_rewrite"]
    return calls


def ctx_kind(call):
    """C2/C3, read off the `ctx=` keyword of one graph_rewrite call."""
    for kw in call.keywords:
        if kw.arg != "ctx":
            continue
        v = kw.value
        # `ctx=CallifyCtx()` -- a dataclass instance, whose fields are the
        # mutable accumulators.  MUTABLE.
        if isinstance(v, ast.Call):
            return "MUTABLE (fresh dataclass instance: %s)" % ast.unparse(v)
        # `ctx={}` / `ctx=({}, srcs)` -- a dict or a tuple of dicts.
        if isinstance(v, ast.Dict) and not v.keys:
            return "PRESENT but EMPTY dict literal -- no accumulator in it"
        if isinstance(v, (ast.Dict, ast.Tuple, ast.List)):
            return "PRESENT (container literal %s)" % type(v).__name__
        # `ctx=(ctx:=CallifyCtx())` -- a named expression.
        if isinstance(v, ast.NamedExpr):
            return "MUTABLE (named expression %s := %s)" % (
                ast.unparse(v.target), ast.unparse(v.value))
        return "PRESENT (%s)" % ast.unparse(v)[:60]
    # `ctx` is a keyword with default None upstream, so absent == None.
    return "ABSENT (defaults to None)"


def writes_ctx(node):
    """Does this def WRITE into a `ctx`?  C3 measured on the def itself."""
    hits = []
    for n in ast.walk(node):
        if isinstance(n, ast.Assign):
            for t in n.targets:
                s = ast.unparse(t)
                if s == "ctx" or s.startswith("ctx.") or s.startswith("ctx["):
                    hits.append(s)
        elif isinstance(n, ast.AugAssign):
            s = ast.unparse(n.target)
            if s == "ctx" or s.startswith("ctx.") or s.startswith("ctx["):
                hits.append(s + " (aug)")
        elif isinstance(n, ast.Call):
            f = ast.unparse(n.func)
            if f.endswith(".append") or f.endswith(".add") or f.endswith(".update"):
                base = ast.unparse(n.func.value) if isinstance(n.func, ast.Attribute) else ""
                if base == "ctx" or base.startswith("ctx.") or base.startswith("ctx["):
                    hits.append(f)
    return hits


# --------------------------------------------------------------------------
# C3 is TRANSITIVE.  `resolve_linear_call` passes `ctx=({}, srcs)` -- a tuple
# holding a dict -- and the dict is written by `create_new_buffer`, a rule
# reachable through `pm_post_sched_cache`.  A DIRECT-only classifier calls that
# "not mutable", which is wrong, so the matcher tables are read and the rule
# graph is closed.
# --------------------------------------------------------------------------

def matcher_tables(text, tree):
    """`NAME = PatternMatcher([(UPat(...), REPLACEMENT), ...])` -> the set of
    replacement SPELLINGS.

    The rule pair is read structurally -- `args[0]` of the `PatternMatcher`
    call is the list, each element is a 2-tuple, and `elts[1]` is the
    replacement.  Collecting `ast.Name` nodes instead is wrong twice over: an
    earlier version walked every `Call` in the value and so MISSED all six
    bare-name rules (`create_new_buffer`, `collect_stores`,
    `canonicalize_alloc`, `simplify_copy_kernel`, `copy_kernel_to_store`,
    `assert_all_same_devices`) -- a bare name in a tuple is a `Name`, not a
    `Call` -- while happily collecting every `UPat(...)` as if it were a rule.
    """
    tables = {}
    for n in ast.walk(tree):
        if not isinstance(n, ast.Assign) or not n.targets or not isinstance(n.targets[0], ast.Name):
            continue
        for val in (n.value, *[v for v in ast.walk(n.value) if isinstance(v, ast.BinOp)]):
            pass
        found = []
        for node in [n.value] + [v for v in ast.walk(n.value) if isinstance(v, ast.Call)
                                 and isinstance(v.func, ast.Name) and v.func.id == "PatternMatcher"]:
            if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                    and node.func.id == "PatternMatcher"):
                continue
            for arg in node.args:
                if not (isinstance(arg, (ast.List, ast.Tuple)) and arg.elts):
                    continue
                for elt in arg.elts:
                    if isinstance(elt, ast.Tuple) and len(elt.elts) == 2:
                        found.append(ast.unparse(elt.elts[1]))
        if found:
            tables[n.targets[0].id] = found
    return tables


def rule_calls(expr, tables, depth=0):
    """The rule SPELLINGS a matcher's expression reaches: the table name plus
    every entry of every table named in the expression's `+` chain."""
    out = set()
    for nm in re.findall(r"[A-Za-z_][A-Za-z_0-9]*", ast.unparse(expr)):
        out.add(nm)
        if nm in tables:
            out |= set(tables[nm])
    return out


def ctx_reaches_a_writer(call, tables, region_nodes):
    """Is the dict this call passes written by a rule that this call can run?

    The linkage is through the MATCHER, not through the ctx expression: the
    second positional argument names the table, the table names the rule, and
    the rule is the thing that writes.  `resolve_linear_call` hands
    `pm_post_sched_cache` a `({}, srcs)` tuple whose dict `create_new_buffer`
    writes -- the ctx expression names neither, so a classifier that reads the
    ctx expression alone calls this "not mutable", which is wrong."""
    names = set()
    if len(call.args) > 1:
        names |= rule_calls(call.args[1], tables)
    for kw in call.keywords:
        if kw.arg == "bpm":
            names |= rule_calls(kw.value, tables)
    if not names:
        return []
    writers = sorted({nm for nm in names
                      if any(getattr(x, "name", None) == nm and writes_ctx(x)
                             for x in region_nodes)})
    # NO further hop.  An earlier version walked every table and reported a
    # writer reachable from a DIFFERENT table (it named `replace_input_buffer`
    # for `pm_post_sched_cache`, whose writer is `create_new_buffer`).  The
    # one-hop answer is the one the source supports, and it is the one printed.
    return writers


def is_pm_rule(text, name):
    """Is `name` used as a rule body in a PatternMatcher literal in this file?"""
    return f"({name})" in text or f"= {name}" in text or f", {name}" in text


def main():
    text, tree = load()
    defs = top_level_defs(tree)
    tables = matcher_tables(text, tree)
    region_nodes = [n for _, _, _, n in defs]
    print("=" * 78)
    print("THE CLAIM: schedule/__init__.bend:7-13, deferring __init__.py:82-301")
    print("=" * 78)
    print(f"top-level defs/classes in __init__.py:[{LO},{HI}]: {len(defs)}")
    print(f"PatternMatcher tables read: {len(tables)}")
    print()
    rows = []
    for ln, kind, name, node in defs:
        calls = gr_calls(node)
        wr = writes_ctx(node)
        ctxs = []
        for c in calls:
            k = ctx_kind(c)
            ctxexpr = next((kw.value for kw in c.keywords if kw.arg == "ctx"), None)
            ws = ctx_reaches_a_writer(c, tables, region_nodes) if ctxexpr is not None else []
            if ws and "EMPTY" not in k:
                k += f"  + dict WRITTEN by reachable rule {','.join(ws)} -> MUTABLE"
            ctxs.append(k)
        rows.append((ln, kind, name, len(calls), ctxs, wr, calls))
        print(f"{ln:4d} {kind:5s} {name}")
        if not calls:
            print("       graph_rewrite calls made here: 0")
        else:
            for c, k in zip(calls, ctxs):
                print(f"       :{c.lineno}  ctx -> {k}")
        if wr:
            print(f"       WRITES ctx: {', '.join(sorted(set(wr)))}")
    print()

    # ---- C1 / C2 / C3, each with its denominator ----
    n = len(rows)
    c1 = sum(1 for r in rows if r[3] > 0)
    c2 = sum(1 for r in rows if any("ABSENT" not in x for x in r[4]))
    c3 = sum(1 for r in rows if any("MUTABLE" in x for x in r[4]))
    c3b = sum(1 for r in rows if r[5])
    neither = sum(1 for r in rows if r[3] == 0 and not r[5])
    print("=" * 78)
    print("THE THREE CLAIMS, MEASURED")
    print("=" * 78)
    print(f"C1  'every rule in it is a graph_rewrite over the arena'")
    print(f"      entry points that CALL graph_rewrite themselves : {c1}/{n}")
    print(f"      entry points that call NOTHING and write no ctx  : {neither}/{n}")
    print(f"      -> C1 {'HOLDS' if c1 == n else 'FAILS'}: {n - c1} of {n} do not.")
    print()
    print(f"C2  'every one of them ... WITH a PYTHON ctx DICT'")
    absent = [r for r in rows if r[3] > 0 and all("ABSENT" in x for x in r[4])]
    print(f"      callers that pass ctx                             : {c2}/{n}")
    print(f"      callers that pass NO ctx at all                    : {len(absent)}/{n}")
    for r in absent:
        print(f"        {r[0]:4d} {r[2]}  ({r[3]} call(s), none with ctx=)")
    print(f"      -> C2 {'HOLDS' if not absent else 'FAILS'}: {len(absent)} of {n} pass no ctx.")
    print()
    print(f"C3  'these rules need the ctx to be a MUTABLE accumulator'")
    mutable = [r for r in rows if any("MUTABLE" in x for x in r[4])]
    empty = [r for r in rows if any("EMPTY" in x for x in r[4])]
    print(f"      callers passing a MUTABLE ctx                     : {c3}/{n}")
    print(f"      callers passing a ctx that is EMPTY (no acc.)    : {len(empty)}/{n}")
    print(f"      entry points that WRITE ctx as a rule body       : {c3b}/{n}")
    direct_covered = {r[0] for r in mutable} | {r[0] for r in rows if r[5]}
    print(f"      union (DIRECT): ctx IS the question               : {len(direct_covered)}/{n}")

    # ---- TRANSITIVE.  An entry point that calls graph_rewrite with no ctx is
    # still ctx-blocked if a matcher rule it can reach is a ctx writer.  This
    # is the honest form of C3 and it is reported separately, never merged.
    transitive = set(direct_covered)
    trans_why = {}
    for ln, kind, name, node, calls in ((r[0], r[1], r[2], d[3], r[6]) for r, d in zip(rows, defs)):
        if not calls:
            continue
        reached = set()
        for c in calls:
            m = c.args[1] if len(c.args) > 1 else None
            if m is None:
                continue
            for nm in re.findall(r"[A-Za-z_][A-Za-z_0-9]*", ast.unparse(m)):
                reached |= {nm} | set(tables.get(nm, ()))
        writers = sorted(nm for nm in reached
                          if any(getattr(x, "name", None) == nm and writes_ctx(x)
                                 for x in region_nodes))
        if writers and ln not in direct_covered:
            transitive.add(ln)
            trans_why[ln] = writers
    print(f"      union (TRANSITIVE): a reachable rule writes ctx  : {len(transitive)}/{n}")
    for ln, ws in sorted(trans_why.items()):
        nm = next(r[2] for r in rows if r[0] == ln)
        print(f"        {ln:4d} {nm:26s} reachable ctx-writers: {', '.join(ws)}")
    print(f"      -> C3 DIRECT   {'HOLDS for all' if len(direct_covered) == n else f'FAILS'}: "
          f"{n - len(direct_covered)} of {n} are not ctx-blocked at all.")
    print(f"      -> C3 TRANSIT  {'HOLDS for all' if len(transitive) == n else f'FAILS'}: "
          f"{n - len(transitive)} of {n} are not ctx-blocked even transitively.")
    print()
    print("=" * 78)
    print("THE MUTABLE-ACCUMULATOR SET, BY NAME (these are the header's cases)")
    print("=" * 78)
    for r in sorted(mutable, key=lambda r: r[0]):
        print(f"  {r[0]:4d} {r[2]}")
    for r in sorted((r for r in rows if r[5]), key=lambda r: r[0]):
        if r[0] not in {x[0] for x in mutable}:
            print(f"  {r[0]:4d} {r[2]}   (writes ctx, never calls graph_rewrite itself)")
    for ln in sorted(trans_why):
        print(f"  {ln:4d} {next(r[2] for r in rows if r[0] == ln)}   (TRANSITIVE only)")
    print()
    print("=" * 78)
    print("THE SET THE HEADER'S REASON DOES NOT COVER  (direct reading)")
    print("=" * 78)
    for r in sorted((r for r in rows if r[0] not in direct_covered), key=lambda r: r[0]):
        why = []
        if r[3] == 0:
            why.append("calls no graph_rewrite")
        if r[4] and all("ABSENT" in x for x in r[4]):
            why.append("passes no ctx")
        if any("EMPTY" in x for x in r[4]):
            why.append("ctx is an empty dict literal, not an accumulator")
        tag = "  [TRANSITIVE ctx: " + ", ".join(trans_why[r[0]]) + "]" if r[0] in trans_why else ""
        print(f"  {r[0]:4d} {r[2]:26s} {'; '.join(why)}{tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())