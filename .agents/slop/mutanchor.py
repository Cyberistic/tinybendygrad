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
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
# Scratch is the pre-approved external directory, not `$TMPDIR`: a `$TMPDIR`
# mirror cannot resolve a relative import, and that produced 22 phantom blind
# spots in one unit.
SCRATCH_ROOT = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"
TARGET_NAMES = ("SRC", "TARGET", "BEND", "F", "PORT", "FILE", "SOURCE")
WRITE_RECV = ("write_text", "write_bytes")     # X.write_text(...) writes to X
WRITE_LAST = ("copy", "copyfile", "copy2", "copymode", "replace", "rename")
# `os.remove`/`os.unlink`/`os.rename`/`shutil.move`/`shutil.rmtree` DESTROY a file
# under the repo exactly as surely as a write does, and the only one of them that
# destroys it irrecoverably.  A zone that counts writes but not DELETIONS reports
# a harness that unlinks the live tree as safe.
WRITE_DESTROY = ("remove", "unlink", "rmdir", "removedirs", "truncate", "rmtree")
# `os.rename`/`os.replace`/`shutil.move` name their DESTINATION LAST, and reading
# their first argument instead reports the SOURCE.  Measured: `shutil.move(A, SRC)`
# was classified from `A`, i.e. `/tmp/x`, and printed ELSEWHERE while it moved a
# scratch file ONTO the live tree.
WRITE_MOVE = ("move", "renames", "replace", "rename")
DESTROY_MODULE = ("os", "shutil", "nt", "posix")
# `open(P, 'w')` and its relatives.  The NAME is open for all of them: `io.open`,
# `codecs.open`, `gzip.open`, `bz2.open`, `lzma.open`, `tarfile.open`, `shelve.open`
# and `tempfile.NamedTemporaryFile` all return a writable handle over P.  Matching
# the name rather than the binding is deliberate -- a reader that resolved the
# module would have to know every one of those import styles, and missing one is
# the failure this table exists to remove.
OPENERS = ("open", "NamedTemporaryFile", "TemporaryFile", "SpooledTemporaryFile")
# `open(P, 'w').write(s)` -- THE SPELLING THAT WAS MISSED, measured on four live
# harnesses.  The destination is not a name at all: it is the opener CALL, so
# `_path` on `f.value` has no node to resolve and the write vanished.  Every one of
# the four read as safer than it was for exactly this reason.
HANDLE_METHODS = ("write", "writelines", "truncate", "flush", "close")
# Modes that can put bytes in the file.  `open(P)` and `open(P, 'rb')` are READS
# and are deliberately absent: reporting a read as a write would make every
# read-only harness look IN-PLAY, which is the same failure in the other
# direction.
WRITE_MODES = ("w", "a", "x", "+")


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


def _opened(call, env, self_name):
    """The path an `open(...)`-shaped call WRITES, or None.

    Two independent filters, both required, and the second one is the one that
    makes the detector usable: a mode.  `open(p).read()` is the most common call in
    these harnesses by a wide margin, and counting it would make a reader that
    writes nothing look like one that writes the live tree.

    `call.func` may be a Name (`open`) or an Attribute (`io.open`, `gzip.open`),
    because the module is the part a reader cannot afford to enumerate.
    """
    if not isinstance(call, ast.Call):
        return None
    f = call.func
    named = f.id if isinstance(f, ast.Name) else (f.attr if isinstance(f, ast.Attribute) else None)
    if named not in OPENERS or not call.args:
        return None
    mode = "r"
    if len(call.args) > 1 and isinstance(call.args[1], ast.Constant) \
       and isinstance(call.args[1].value, str):
        mode = call.args[1].value
    for kw in call.keywords:
        if kw.arg == "mode" and isinstance(kw.value, ast.Constant) \
           and isinstance(kw.value.value, str):
            mode = kw.value.value
    if not any(c in mode for c in WRITE_MODES):
        return None
    return _path(call.args[0], env, self_name)


def handles(tree, self_name=None, env=None):
    """`{handle name: path}` for names bound to a WRITABLE file, and only those.

    Separate from `_bounds` on purpose.  `env` holds path CONSTANTS, so resolving a
    bare `f.write(s)` against it would report any name that happens to be a path,
    and a false IN-PLAY is the mirror image of a false SCRATCH: both teach a reader
    to stop believing the column.
    """
    env = _bounds(tree, self_name) if env is None else env
    out = {}
    for _ in range(4):
        grown = dict(out)
        for n in ast.walk(tree):
            if isinstance(n, ast.Assign) and len(n.targets) == 1 \
               and isinstance(n.targets[0], ast.Name):
                p = _opened(n.value, env, self_name)
                if p:
                    grown.setdefault(n.targets[0].id, p)
            elif isinstance(n, (ast.With, ast.AsyncWith)):
                for item in n.items:
                    if isinstance(item.optional_vars, ast.Name):
                        p = _opened(item.context_expr, env, self_name)
                        if p:
                            grown.setdefault(item.optional_vars.id, p)
        if grown == out:
            return out
        out = grown
    return out


def _bounds(tree, self_name=None):
    """`{name: path}` for every path-ish module constant AND every writable handle,
    to a fixpoint.

    The fixpoint is load-bearing and short: `ROOT = dirname(dirname(__file__))`
    must resolve before `WORK = os.path.join(ROOT, "...")` can, and `WORK` must
    resolve before a mutation's destination can.  One pass finds none of those
    three, and a reader that stops at the first pass declares
    `ops-python-mutate.py`'s target UNDECLARED -- which is what the earlier
    sweep did, silently disabling its own ANCHOR-GONE check for that harness.

    The fixpoint is also what lets a HANDLE ALIAS resolve in either direction:
    `f = open(SRC, 'w')` on one line and `f.write(src)` on the next is invisible to
    a single pass, because the reader resolves against the PREVIOUS pass's `env`.
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


def write_spellings(tree, self_name=None):
    """`(zone, destination, spelling)` for every write or destruction.

    The spelling is returned rather than discarded because a detector that
    cannot say HOW it found a write cannot be argued with: every claim in this
    list is checkable by reading the call at the cited line.

    `str.replace` is filtered for free: its receiver is a string constant, so
    `_path` returns None and it never appears.
    """
    env = _bounds(tree, self_name)
    hd = handles(tree, self_name, env)
    out = []
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call):
            continue
        f = n.func
        mod = f.value.id if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) else None
        # 1. X.write_text / X.write_bytes -- the receiver IS the destination.
        if isinstance(f, ast.Attribute) and f.attr in WRITE_RECV:
            p = _path(f.value, env, self_name)
            if p:
                out.append((zone(p), absolve(p), f.attr))
        # 2. shutil.copy(BAK, LIVE) -- the LAST argument is the destination.
        elif isinstance(f, ast.Attribute) and f.attr in WRITE_LAST and n.args:
            p = _path(n.args[-1], env, self_name)
            if p:
                out.append((zone(p), absolve(p), "%s.%s" % (mod or "shutil", f.attr)))
        # 3. open(P, 'w').write(s) AND f.write(s) where f = open(P, 'w') -- the
        #    SPELLINGS THAT WERE MISSED.  The receiver is either the opener CALL
        #    itself or a name bound to one; neither resolves as a path expression.
        elif isinstance(f, ast.Attribute) and f.attr in HANDLE_METHODS:
            p = _opened(f.value, env, self_name) or \
                (hd.get(f.value.id) if isinstance(f.value, ast.Name) else None)
            if p:
                out.append((zone(p), absolve(p), "open(...).%s" % f.attr))
        # 4. os.remove(P) / shutil.rmtree(P) -- a DELETION of the live tree.
        elif isinstance(f, ast.Attribute) and f.attr in WRITE_DESTROY \
                and mod in DESTROY_MODULE and n.args:
            p = _path(n.args[0], env, self_name)
            if p:
                out.append((zone(p), absolve(p), "%s.%s" % (mod, f.attr)))
        # 5. os.rename(A, B) / shutil.move(A, B) -- B is the destination.
        elif isinstance(f, ast.Attribute) and f.attr in WRITE_MOVE \
                and mod in DESTROY_MODULE and len(n.args) > 1:
            p = _path(n.args[-1], env, self_name)
            if p:
                out.append((zone(p), absolve(p), "%s.%s" % (mod, f.attr)))
        # 6. the opener NESTED as an argument -- `json.dump(x, open(P, 'w'))` and
        #    `print(x, file=open(P, 'w'))`.  Here the file is written by the
        #    CONSUMER, so no `.write` attribute exists anywhere to hang a branch
        #    on, and `print`'s callee is a Name rather than an Attribute, so this
        #    has to sit OUTSIDE the attribute chain.  It is the one remaining
        #    spelling a single-file reader can close without dataflow.
        for sub in list(n.args) + [k.value for k in n.keywords]:
            p = _opened(sub, env, self_name) if isinstance(sub, ast.Call) else None
            if p:
                out.append((zone(p), absolve(p), "nested open as %s argument"
                            % (f.id if isinstance(f, ast.Name) else f.attr)))
    return out


def writes(tree, self_name=None):
    """`(zone, destination)` for every write this harness performs."""
    return [(z, d) for z, d, _ in write_spellings(tree, self_name)]


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


def transform(tree, self_name=None):
    """The harness's OWN anchor transform, or None.

    `ra-mutate.py` and `ra-mutate2.py` post-process every anchor and every
    replacement through `q()` before searching, because the 1:1 file split forced an
    `LT.` qualifier onto cross-file names.  A reader that compares the RAW literal
    against the file is therefore searching for a string the harness never uses, and
    reports 20 and 8 anchors STALE that are all present -- measured, and the error is
    the same shape as the mirror-stale one: the reader held a copy of the substrate
    that was not the substrate.

    So the transform is EXECUTED, from the harness's own AST, rather than
    transcribed.  A transcription would be a second copy of the qualification list,
    which is the thing most likely to drift, and this is the harness's rule about
    names -- the one place where inheriting a value is worse than deriving it.
    """
    names = {}
    for n in tree.body:
        if isinstance(n, ast.Assign) and len(n.targets) == 1 \
           and isinstance(n.targets[0], ast.Name):
            names[n.targets[0].id] = n
        elif isinstance(n, ast.FunctionDef) and n.name == "q":
            names.setdefault("q", n)
    if "q" not in names:
        return None
    qdef = names["q"]
    # ONLY the globals `q` actually reads are executed.  The alternative -- exec
    # every module-level assignment -- runs the harness's own I/O, and
    # `ra-mutate.py` reads a baseline file that does not exist, so the reader died
    # with a FileNotFoundError raised from inside a file it claimed only to read.
    free = {n2.id for n2 in ast.walk(qdef) if isinstance(n2, ast.Name)}
    ns = {"re": re}
    for key, node in names.items():
        if key == "q" or key not in free:
            continue
        try:
            exec(compile(ast.Module([node], []), self_name or "?", "exec"), ns)
        except Exception:
            return None                 # a transform that cannot be reproduced is
    try:                             # NOT a transform the reader may invent
        exec(compile(ast.Module([qdef], []), self_name or "?", "exec"), ns)
    except Exception:
        return None
    return ns.get("q")


def anchors(tree, texts=(), self_name=None):
    """`{id: anchor}` from `mutations()`, keyed on the voted column, WITH the
    harness's own transform applied.

    `texts` is the target file's content; without it no anchor can be voted for
    and every row is UNDECLARED, which is the honest answer rather than a guess
    at index 1.  A row with no string at the voted column (a prose-only id, a
    control) is None and stays out of the denominator.
    """
    v = mutations(tree)
    if v is None:
        return None
    q = transform(tree, self_name)
    col = anchor_column(v, texts) if texts else None
    out = {}
    for e in v:
        if len(e) > 1 and isinstance(e[0], str):
            c = e[col] if col is not None and col < len(e) else None
            if isinstance(c, str) and q is not None:
                c = q(c)
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


