r"""THE REACH HALF: at each site a bool CAN reach, WHAT ACTUALLY ARRIVES -- and is it LIVE?

A census that answers "can a bool reach this?" without answering "does one reach it TODAY, and
what does it DO when it does" is a presence count, and the brief asks for the CONSEQUENCE.

THE RULE, and it is a syntactic one so it is falsifiable:
  A site is REACHABLE-BY-A-BOOL when the index expression is
    (a) an `ast.Compare`                      -- `x == y` IS a bool
    (b) an `is`/`is not` compare against True/False/None
    (c) a call to `bool`/`isinstance`/`any`/`all`/`is True`
    (d) a Name whose EVERY assignment in the module is one of the above
    (e) a comparison folded through a walrus, an `if`, or a `bool(...)`

A site is LIVE when a REACHABLE-BY-A-BOOL expression is compared or indexed against an int-keyed
table with NO `isinstance(x, bool)` guard between them -- and LATENT when the guard exists, or
when the value at runtime is a constant int.

The grade is the useful one (`prune4`'s): **LATENT TODAY, A LIVE FALSE-VERDICT THE MOMENT ONE
CALLER PASSES A COMPARISON**. Latent is not safe. See REPORT.md §6.
"""
import ast
import sys

from census import ROOT, population, Binder

TRUEISH = (True, False)
NONEISH = (None,)


def _bool_expr(node, binder):
    """True when the EXPRESSION ITSELF evaluates to a bool. Syntactic, declared, falsifiable."""
    if isinstance(node, ast.Compare):
        return True                       # EVERY comparison is a bool. `is True` is fine here;
                                          # the hazard is what it is used AS, not that it is bool.
    if isinstance(node, ast.BoolOp):
        return True
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
        return True
    if isinstance(node, (ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)):
        return True
    if isinstance(node, ast.Await):
        return False
    if isinstance(node, ast.Call):
        f = node.func
        nm = f.id if isinstance(f, ast.Name) else (f.attr if isinstance(f, ast.Attribute) else None)
        if nm in ("bool", "any", "all", "isinstance", "issubclass", "callable"):
            return True
        if isinstance(f, ast.Attribute) and f.attr in ("startswith", "endswith", "match"):
            return True
    if isinstance(node, ast.Name):
        # a Name is a bool only if EVERY assignment to it in this module produced one.
        # A Name is a bool only if EVERY assignment to it produced one. `name_assigns` is the
        # count of assignments; `bool_names` is the count of bool-producing ones.
        total = binder.name_assigns.get(node.id, 0)
        bools = binder.bool_names.get(node.id, 0)
        return total > 0 and bools == total
    return False


def int_keyed(keys):
    """True when the container's keys include 0 or 1 or are int-valued: `int(True) == 1` means a
    bool DOES reach such a table. Returns (bool, keys)."""
    if keys is None:
        return False, None
    if any(k is None or k == "<**spread>" for k in keys):
        return False, keys
    if not keys:
        return False, keys
    numeric = [k for k in keys if isinstance(k, (int, float)) and not isinstance(k, bool)]
    if numeric and set(numeric) & {0, 1}:
        return True, keys
    if all(isinstance(k, (int, bool)) for k in keys):
        return True, keys
    return False, keys


def analyse(path, tree=None):
    """`tree` is PASSED IN, never re-parsed.

    MEASURED, and it is the `prune4` failure in a third costume: `_PARENTS` is keyed by
    `id(node)`, and this function used to `ast.parse` its own copy while `build_parents` walked
    another. Two trees, two sets of `id()`s, and every guard lookup silently returned
    "no-enclosing-function" -- so all 12 sites graded as UNGUARDED, including `gates/gatekit.py:97`
    which sits three lines below an `isinstance(code, bool)`. The census reported the opposite of
    the truth because two trees shared a key space."""
    try:
        src = path.read_text()
    except (OSError, UnicodeDecodeError):
        return []
    if tree is None:
        try:
            tree = ast.parse(src)
        except SyntaxError:
            return []
    b = Binder(tree, src)
    b.bool_names, b.name_assigns = {}, {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            vals = node.value.elts if isinstance(node.value, ast.Tuple) else [node.value]
            for t in node.targets:
                for nm in _names(t):
                    b.name_assigns[nm] = b.name_assigns.get(nm, 0) + 1
                    for v in vals:
                        if _bool_expr(v, b):
                            b.bool_names.setdefault(nm, 0)
                            b.bool_names[nm] += 1
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            nm = node.target.id
            b.name_assigns[nm] = b.name_assigns.get(nm, 0) + 1
            if node.value is not None and _bool_expr(node.value, b):
                b.bool_names[nm] = b.bool_names.get(nm, 0) + 1

    out = []
    lines = src.splitlines()
    for node in ast.walk(tree):
        # dict[T] and dict.get(T) -- the two ways an int-keyed table answers a question
        probes = []
        if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Name):
            probes.append((node.value.id, node.slice, "SUB"))
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
                and node.func.attr == "get" and isinstance(node.func.value, ast.Name) \
                and node.args:
            probes.append((node.func.value.id, node.args[0], "GET"))
        elif isinstance(node, ast.Compare):
            # `code in VERDICT` -- the shape `exitcode` caught with its own N4 plant. It is NOT
            # a subscript and NOT a `.get`, and a census that only handles those two would have
            # reported the class as missing the single most-named instance in the tree.
            for op, cmp in zip(node.ops, node.comparators):
                if isinstance(op, (ast.In, ast.NotIn)) and isinstance(cmp, ast.Name):
                    probes.append((cmp.id, node.left, "IN"))
        for cname, idx, how in probes:
            sh = b.shapes.get(cname, (None,))[0]
            if not sh or sh[0] != "dict":
                continue
            hit, keys = int_keyed(sh[1])
            if not hit:
                continue
            is_bool = _bool_expr(idx, b)
            guarded = _guarded(node, cname, src)
            out.append(dict(file=str(path.relative_to(ROOT)), ln=node.lineno, how=how,
                            table=cname, keys=keys, index=ast.unparse(idx),
                            bool_expr=is_bool, guarded=guarded,
                            src=lines[node.lineno - 1].strip()))
    return out


def _names(t):
    if isinstance(t, ast.Name):
        return [t.id]
    if isinstance(t, (ast.Tuple, ast.List)):
        return [n for e in t.elts for n in _names(e)]
    return []


def _guarded(node, cname, src):
    """Is there an `isinstance(<something>, bool)` between here and the FUNCTION it is in?

    A guard is only a guard if it is on the SAME NAME. `gatekit.verdict_of` tests
    `isinstance(code, bool)` and `charge` tests the same `code`; a guard on a different name, or
    one in a different function, does not protect this site and is reported as NO GUARD."""
    fn = _enclosing_function(node)
    if fn is None:
        return "no-enclosing-function"
    args = [a.arg for a in fn.args.args]
    body = ast.unparse(fn)
    # the guarded names: `isinstance(NAME, bool)` anywhere in the function, BEFORE this line
    guarded = set()
    for sub in ast.walk(fn):
        if isinstance(sub, ast.Call) and isinstance(sub.func, ast.Name) \
                and sub.func.id == "isinstance" and len(sub.args) == 2 \
                and isinstance(sub.args[1], ast.Name) and sub.args[1].id == "bool":
            for nm in _names(sub.args[0]):
                guarded.add(nm)
    earlier = any(
        isinstance(sub, ast.Call) and isinstance(sub.func, ast.Name)
        and sub.func.id == "isinstance" and len(sub.args) == 2
        and isinstance(sub.args[1], ast.Name) and sub.args[1].id == "bool"
        and getattr(sub, "lineno", 0) < node.lineno
        for sub in ast.walk(fn))
    if earlier:
        return "EARLIER-isinstance-bool-on:" + ",".join(sorted(guarded))
    # SAME-LINE GUARD BY SHORT-CIRCUIT. `code in VERDICT and not isinstance(code, bool)` --
    # MEASURED at `gates/gatekit.py:110` -- is protected even though the `isinstance` is not on
    # an EARLIER line: `and` evaluates left to right, so a `False` from the first operand means
    # the table was never probed for a bool in the first place. A line-order test alone graded
    # the tree's own fix UNGUARDED, which is how a guard gets "fixed" twice.
    if _sibling_guard(node, fn):
        return "SAME-EXPR-and-isinstance-bool (short-circuit)"
    return "isinstance-bool-after-only" if guarded else "NONE"


def _sibling_guard(node, fn):
    """An `isinstance(_, bool)` joined to this node by `and` inside ONE BoolOp."""
    for anc in _walk_up(node):
        if not isinstance(anc, ast.BoolOp):
            continue
        # `BoolOp.op` is a SINGLE operator node on 3.12+, not a list of them. Written as
        # `any(... for o in anc.ops)` this raised `AttributeError: 'BoolOp' object has no
        # attribute 'ops'` and -- because the exception propagated out of the whole census --
        # took the run down with it. MEASURED, and the lesson is the one this file keeps
        # relearning: a grader that cannot ask the question must SAY it cannot.
        if not isinstance(anc.op, ast.And):
            continue
        for v in anc.values:
            for sub in ast.walk(v):
                if isinstance(sub, ast.Call) and isinstance(sub.func, ast.Name) \
                        and sub.func.id == "isinstance" and len(sub.args) == 2 \
                        and isinstance(sub.args[1], ast.Name) and sub.args[1].id == "bool":
                    return True
    return False


def _walk_up(node):
    seen, cur = set(), node
    while cur is not None and id(cur) not in seen:
        seen.add(id(cur))
        ps = _parents(cur)
        if not ps:
            return
        cur = ps[0]
        yield cur


def _enclosing_function(node):
    """The nearest enclosing function, found by WALKING UP -- one level is not enough.

    MEASURED: the first version looked only at `_parents(node)`, which holds the DIRECT parent,
    so a `Subscript` inside `return X[k]` saw only the `Return` and reported
    `no-enclosing-function` for every site in the tree. Same confident wrong answer as the two
    bugs above, from a third cause: an instrument that cannot answer is not an instrument."""
    seen, cur = set(), node
    while cur is not None and id(cur) not in seen:
        seen.add(id(cur))
        ps = _parents(cur)
        if not ps:
            return None
        cur = ps[0]
        if isinstance(cur, (ast.FunctionDef, ast.AsyncFunctionDef)):
            return cur
    return None


_PARENTS = {}


def _parents(node):
    return _PARENTS.get(id(node), [])


def build_parents(tree):
    """RESET FIRST, then walk.

    `_PARENTS` is keyed by `id(node)`, and CPython RECYCLES `id()` of a freed object. Holding the
    map across files means file 2's nodes can alias file 1's dead nodes' entries -- MEASURED, and
    it is why every site graded `no-enclosing-function` even for `gates/gatekit.py:97`, three
    lines below a real `isinstance(code, bool)`. The map is per-TREE and dies with it; nothing
    here reaches outside one `analyse` call."""
    _PARENTS.clear()
    for parent in ast.walk(tree):
        for child in ast.iter_child_nodes(parent):
            _PARENTS.setdefault(id(child), []).insert(0, parent)


def main():
    rows = []
    for rel, p in population():
        try:
            tree = ast.parse(p.read_text())
        except (SyntaxError, OSError, UnicodeDecodeError):
            continue
        build_parents(tree)
        rows.extend(analyse(p, tree))   # the SAME tree -- see `analyse`'s docstring
    print(f"# THE REACH HALF -- {len(rows)} sites where an INT-KEYED table is probed, over "
          f"{len(population())} files discovered by os.walk under checks/ + gates/")
    def _is_guarded(g):
        """ANY protecting guard -- earlier-line OR same-expression short-circuit.

        MEASURED: this summary used to test for the literal substring `"EARLIER"`, so the
        SAME-EXPR guard at `gates/gatekit.py:110` was correctly DETECTED by `_guarded` and then
        DROPPED by the tally, printing "GUARDED: 2" under a table that lists three. The census
        found it and the summary hid it -- the same failure as the rest of this unit's, in the
        last line of code that should have checked."""
        return g.startswith("EARLIER") or g.startswith("SAME-EXPR")

    live = [r for r in rows if r["bool_expr"] and not _is_guarded(r["guarded"])]
    latent = [r for r in rows if not r["bool_expr"] and not _is_guarded(r["guarded"])]
    guarded = [r for r in rows if _is_guarded(r["guarded"])]
    print(f"## LIVE    : a bool EXPRESSION indexes the table, no guard at all            : {len(live)}")
    print(f"## LATENT  : a non-bool expression indexes it, no guard -- LIVE the moment a "
          f"caller passes a comparison : {len(latent)}")
    print(f"## GUARDED : an isinstance(x, bool) protecting the site, earlier-line OR "
          f"same-expression : {len(guarded)}")
    # THE THREE TALLIES MUST SUM TO THE SITE COUNT. MEASURED: the summary printed "GUARDED: 2"
    # under a table listing THREE, because the classifier found the same-expression guard and the
    # tally then dropped it on a substring test. A partition that does not sum is a partition with
    # a hole in it, and `rebase-gate-selftest`'s "0 disagreements over 0 comparisons" is the
    # same shape -- so it is ASSERTED, not trusted.
    total = len(live) + len(latent) + len(guarded)
    if total != len(rows):
        print(f"## PARTITION ERROR: {len(live)}+{len(latent)}+{len(guarded)} = {total}, "
              f"but {len(rows)} sites were found. The grades DO NOT COVER the population.")
        return 1
    print()
    for title, group in (("LIVE", live), ("GUARDED", guarded), ("LATENT", latent)):
        print(f"## --- {title} ({len(group)}) ---")
        for r in group:
            print(f"{r['file']:<32}:{r['ln']:<5} {r['how']:<4} {r['table']:<10} "
                  f"keys={str(r['keys']):<18} index={r['index'][:28]:<28} "
                  f"bool={str(r['bool_expr']):<5} guard={r['guarded'][:34]}")
            print(f"{'':>52}  | {r['src'][:100]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())