#!/usr/bin/env python3
"""mutanchor.py -- READ a mutation harness without running it.

Importing a harness runs its mutation loop, and three of them rewrite the LIVE
tree while they do it, so the only honest way to ask a harness a question about
its own anchors is `ast`.  Both consumers need the same four answers -- what
file does it patch, what literal does each mutation look for, where does it
write, and can that be read without executing it -- so they live here once.

WHAT THIS IS NOT.  Nothing here executes anything or measures anything.  A
harness that says its own substrate is fine is not evidence; `dd-mutate.py`
proves the point the hard way, by asserting a digest.
"""
import ast
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
# Scratch is the pre-approved external directory, not `$TMPDIR`: a `$TMPDIR`
# mirror cannot resolve a relative import, and that produced 22 phantom blind
# spots in one unit.
SCRATCH_ROOT = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"
TARGET_NAMES = ("SRC", "TARGET", "BEND", "F", "PORT", "FILE", "SOURCE")
WRITE_RECV = ("write_text", "write_bytes")     # X.write_text(...) writes to X
WRITE_LAST = ("copy", "copyfile", "copy2", "copymode", "replace", "rename")


def parse(path):
    """The harness's AST, or None.  A harness that will not parse is UNREADABLE."""
    try:
        return ast.parse(open(path, errors="replace").read())
    except (OSError, SyntaxError):
        return None


def _path(node, env, self_name=None):
    """The filesystem path a path-EXPRESSION denotes, or None.

    Handles the four idioms these harnesses actually use -- a literal, `a / b`,
    `Path(...)` and `os.path.join(...)` -- plus the `os.path.dirname` chain that
    every one of them uses to find the repo root.  The chain is RESOLVED rather
    than approximated: `dirname(dirname(dirname(__file__)))` from
    `.agents/slop/x.py` is the repo root, so counting the `dirname`s names it
    exactly.  Anything else is None and callers report UNDECIDED rather than
    guessing -- a wrong path turns an ANCHOR-GONE verdict into a fiction.
    """
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        # `__file__` is this harness's own path, which is what makes the
        # `dirname(dirname(__file__))` climb resolvable rather than a guess.
        return os.path.join(HERE, self_name) \
            if node.id == "__file__" and self_name else env.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        return _join(_path(node.left, env, self_name), _path(node.right, env, self_name))
    if isinstance(node, ast.Call):
        return _call(node, env, self_name)
    return None


def _join(*parts):
    if not all(parts) or any(p.startswith("/") for p in parts[1:]):
        return None
    return os.path.join(*parts)


def _call(node, env, self_name):
    f = node.func
    if not isinstance(f, ast.Attribute):
        return _path(node.args[0], env, self_name) \
            if isinstance(f, ast.Name) and f.id == "Path" and node.args else None
    args = [_path(a, env, self_name) for a in node.args]
    if f.attr in ("dirname", "abspath", "realpath"):
        return _dirname(node, env, self_name) if f.attr == "dirname" \
            else _abspath(node, env, self_name)
    if f.attr == "Path" and args:
        return args[0]
    if f.attr != "join" or not args:
        return None
    # `os.path.join` has no receiver path, so only the ARGUMENTS matter.  The
    # receiver is checked too for `Path(...).join(...)`, which no harness here
    # uses but which costs three lines to not get wrong.
    recv = _path(f.value, env, self_name) if not (isinstance(f.value, ast.Attribute)
                                                  and f.value.attr == "path") else None
    return _join(recv, *args) if recv else _join(*args)


def _dirname(node, env, self_name):
    """`os.path.dirname(x)`, resolving `__file__` chains to real directories.

    `__file__` is this harness's own path, so a chain of `dirname`s is a climb
    to a directory that already exists and can simply be asked.  A chain that
    does not land on an existing directory returns None rather than a guess.
    """
    if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and node.func.attr == "dirname" and node.args):
        return None
    base = _path(node.args[0], env, self_name)
    d = os.path.dirname(base) if base else None
    return d if d and os.path.isdir(d) else None


def _abspath(node, env, self_name):
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
       and node.func.attr in ("abspath", "realpath") and node.args:
        p = _path(node.args[0], env, self_name)
        return os.path.abspath(p) if p and os.path.exists(p) else None
    return None


def _bounds(tree, self_name=None):
    """`{name: path}` for every path-ish module constant, to a fixpoint.

    The fixpoint is load-bearing and short: `ROOT = dirname(dirname(__file__))`
    must resolve before `WORK = os.path.join(ROOT, "...")` can, and `WORK` must
    resolve before a mutation's destination can.  One pass finds none of those
    three, and a reader that stops at the first pass declares
    `ops-python-mutate.py`'s target UNDECLARED -- which is what the earlier
    sweep did, silently disabling its own ANCHOR-GONE check for that harness.
    """
    env = {}
    for _ in range(8):
        grown = dict(env)
        for n in ast.walk(tree):
            if isinstance(n, ast.Assign) and len(n.targets) == 1 \
               and isinstance(n.targets[0], ast.Name):
                p = _path(n.value, env, self_name)
                if p:
                    grown.setdefault(n.targets[0].id, p)
        if grown == env:
            return env
        env = grown
    return env


def absolve(p):
    """`p` made absolute against the repo root."""
    return os.path.join(ROOT, p) if p and not os.path.isabs(p) else p


def zone(p):
    """Where a write destination lands: IN-PLAY / SCRATCH / ELSEWHERE / UNDECIDED.

    IN-PLAY is the dangerous one and the reason this module exists.  A harness
    that writes into the repo must not be run unless live is byte-identical to
    its snapshot: the snapshot is a `jj restore` gun, and one silently put a
    dead 6,623-line `ops.bend` over the live 6,306-line one and destroyed
    committed work.
    """
    if not p:
        return "UNDECIDED"
    a = os.path.abspath(absolve(p))
    if a.startswith(SCRATCH_ROOT):
        return "SCRATCH"
    return "IN-PLAY" if a.startswith(ROOT) else "ELSEWHERE"


SOURCE_EXT = (".bend", ".py", ".c", ".h")


def _is_source(p):
    """Is this path a SOURCE file a mutation anchor could be searched in?

    The negative test is the load-bearing one: most of these harnesses bind
    `BEND` to the COMPILER (`bin/bend`), and picking it makes all 44 of
    `ag-mutate.py`'s anchors read STALE -- a fiction, because every one of them
    is present in `autogen.bend`.  `bin/bend` has no extension, which is what
    excludes it.
    """
    return os.path.splitext(p)[1] in SOURCE_EXT


def targets(tree, self_name=None, names=TARGET_NAMES):
    """`[(name, path)]` of every source file this harness declares, in priority order.

    Priority names first, then the rest, because a harness may patch a SNAPSHOT
    or a WORK copy whose NAME says nothing about it -- `dd-mutate.py` patches
    `FROZEN`, `nv_ip_mutate.py` patches `IP`, and neither is called `SRC`.  An
    anchor is therefore judged against ALL of them, which is also the only way a
    reader can tell "the literal moved" from "I was looking at the wrong file".
    """
    env = _bounds(tree, self_name)
    found = [(n, absolve(env[n])) for n in names if n in env] + \
            [(k, absolve(v)) for k, v in sorted(env.items()) if k not in names]
    return [(n, p) for n, p in found if _is_source(p) and os.path.isfile(p)]


def target_text(tree, self_name=None, names=TARGET_NAMES):
    """The first declared source file, or None."""
    t = targets(tree, self_name, names)
    return t[0][1] if t else None


def writes(tree, self_name=None):
    """`(zone, destination)` for every write this harness performs.

    `str.replace` is filtered for free: its receiver is a string constant, so
    `_path` returns None and it never appears.
    """
    env = _bounds(tree, self_name)
    out = []
    for n in ast.walk(tree):
        f = n.func if isinstance(n, ast.Call) else None
        if not (isinstance(f, ast.Attribute) and f.attr in WRITE_RECV + WRITE_LAST):
            continue
        dest = f.value if f.attr in WRITE_RECV else \
            (n.args[-1] if n.args else None)
        p = _path(dest, env, self_name)
        if p:
            out.append((zone(p), absolve(p)))
    return out


def anchor_column(rows, texts):
    """Which tuple position holds the anchor, decided by VOTE over the rows.

    The position differs between harnesses -- 2 in `ag-mutate.py`, 1 in
    `wgsl-mutate.py` -- and a reader that hard-codes one reports 29 of 36
    `wgsl-mutate.py` anchors STALE when every one is present.

    THE SIGNAL, and it is two-sided: an anchor column's cells are in the file and
    the NEXT cell -- the replacement -- is not.  Presence alone is useless,
    because an ID like `M1` and a prose cell are substrings of almost any file,
    and measured that way the ID column ties the anchor column in 8 of the
    harnesses here.  Absence alone is useless too, and dangerously so: for a
    table whose anchors have ALL moved, old and new are both absent and every
    column scores zero.

    So the vote is `in the file and its successor is not`, and a table that
    scores zero everywhere falls back to plain presence over the interior
    columns.  That fallback is also how a fully-stale table is RECOGNISED: its
    winner is the prose column, because a prose cell is a phrase and the literals
    are gone.  `usb-mutate.py`'s replacement is a LIST, not a string, so
    "successor is a string" is part of the test and its vote is uncontested.
    """
    def score(c):
        n = 0
        for row in rows:
            a = row[c] if c < len(row) else None
            b = row[c + 1] if c + 1 < len(row) else None
            if not (isinstance(a, str) and isinstance(b, str)) or a == b:
                continue
            if any(a in t for t in texts) and not any(b in t for t in texts):
                n += 1
        return n

    interior = [c for c in range(max(len(r) for r in rows) - 1) if c]
    ranked = sorted(((score(c), c) for c in interior), reverse=True)
    if ranked and ranked[0][0]:
        return ranked[0][1]
    present = dict((c, sum(1 for row in rows if isinstance(row[c] if c < len(row) else None, str)
                            and any(row[c] in t for t in texts))) for c in interior)
    best = max(present.values(), default=0)
    winners = [c for c, v in present.items() if v == best]
    return winners[0] if best and len(winners) == 1 else None


def anchors(tree, texts=()):
    """`{id: anchor}` from `mutations()`, keyed on the voted column.

    `texts` is the target file's content; without it no anchor can be voted for
    and every row is UNDECLARED, which is the honest answer rather than a guess
    at index 1.  A row with no string at the voted column (a prose-only id, a
    control) is None and stays out of the denominator.
    """
    v = mutations(tree)
    if v is None:
        return None
    col = anchor_column(v, texts) if texts else None
    out = {}
    for e in v:
        if len(e) > 1 and isinstance(e[0], str):
            c = e[col] if col is not None and col < len(e) else None
            out[e[0]] = c if isinstance(c, str) else None
    return out


def mutations(tree):
    """The LONGEST module-level literal list of tuples, or None.

    Longest, not first: `rf-mut.py` declares a one-row `MUTS` left over from an
    earlier experiment and then a twenty-row `MUTS` that replaced it, and a
    reader that takes the first audits the corpse.
    """
    best = None
    for n in tree.body:
        if not (isinstance(n, ast.Assign) and len(n.targets) == 1
                and isinstance(n.targets[0], ast.Name)):
            continue
        try:
            v = ast.literal_eval(n.value)
        except (ValueError, SyntaxError, TypeError):
            continue
        if isinstance(v, list) and v and isinstance(v[0], (tuple, list)) \
           and (best is None or len(v) > len(best)):
            best = v
    return best


