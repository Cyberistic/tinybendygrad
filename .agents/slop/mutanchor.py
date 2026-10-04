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
# `H = [open(P,'w')]` / `H = {'f': open(P,'w')}` -- the handle in a CONTAINER.  The
# name `H` holds no path, so `H[0].write(s)` has no receiver to resolve and the write
# vanished.  Only a LITERAL subscript is resolvable (`H[0]`, `H['f']`): `H[i]` for a
# variable `i` is a name whose value is not in this file, and guessing an index would
# be the reader inventing a measurement.
CONTAINERS = ("List", "list", "Tuple", "tuple", "Dict", "dict")
# A HANDLE PASSED AS AN ARGUMENT: `dump(x, f)` where `f = open(P,'w')`.  Here the
# writer is the CALLEE and there is no `.write` anywhere in this file to hang a branch
# on, so it can only be reported as a MAY-write.  It is reported rather than omitted
# because the two failure directions are not symmetric here: a harness that writes the
# live tree through a callee is the thing this module exists to name, and a reader who
# is told `dump(x, f)` MIGHT write can open the callee -- whereas a reader told nothing
# cannot.  The spelling string says MAY, so the column is never claiming a certainty
# it does not have.
# A name bound to a writable handle, passed as a positional argument or as a keyword
# value.  A method CALL is excluded: `f.write(s)` is already caught by
# `HANDLE_METHODS`, and counting it twice would inflate the count.
#
# SHELL REDIRECTION: `subprocess.run('cat > %s' % SRC, shell=True)`.  The `>` is not a
# Python write and no AST walk of assignments finds it, so it is read out of the COMMAND
# STRING instead.  Only `>` and `>>` are read, only when the target is a resolvable path
# expression, and only for the four runners that actually take a command.
RUNNERS = ("run", "Popen", "call", "check_call", "check_output", "getoutput", "getstatusoutput")
SHELLS = ("bash", "sh", "zsh", "dash", "ksh")
REDIRECT = (">>", ">")


def parse(path):
    """The harness's AST, or None.  A harness that will not parse is UNREADABLE."""
    try:
        return ast.parse(open(path, errors="replace").read())
    except (OSError, SyntaxError):
        return None


def _path(node, env, self_name=None):
    """The filesystem path a path-EXPRESSION denotes, or None.

    Handles the idioms these harnesses actually use -- a literal, `a / b`,
    `Path(...)`, `os.path.join(...)`, and the `os.path.dirname` chain that every
    one of them uses to find the repo root -- plus the three FORMS a rewrite
    introduces, each of which cost a real audit:

      * `Path(__file__).resolve().parent.parent.parent` -- a `resolve()` CHAIN, not
        the `os.path.realpath` call the first version knew.  Without it
        `ra-mutate.py`, `ra-mutate2.py` and `rf-mut.py` all read NO-SUBSTRATE: their
        anchor check was silently disabled, which is worse than reporting the
        harness as unreadable because nothing looks wrong.
      * `Path(...).parent` -- the pathlib spelling of `dirname`.
      * `LATE / ("%s.bend" % f)` -- a `%`-formatted filename.  Only the single-`%s`
        case is resolved, and only when the literal has no directory part, because
        a general format evaluator would be a second Python in a hazard detector.

    The `os.path.dirname` chain is RESOLVED rather than approximated:
    `dirname(dirname(dirname(__file__)))` from `.agents/slop/x.py` is the repo root,
    so counting the `dirname`s names it exactly.  Anything else is None and callers
    report UNDECIDED rather than guessing -- a wrong path turns an ANCHOR-GONE
    verdict into a fiction.
    """
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        # `__file__` is this harness's own path, which is what makes the
        # `dirname(dirname(__file__))` climb resolvable rather than a guess.
        return os.path.join(HERE, self_name) \
            if node.id == "__file__" and self_name else env.get(node.id)
    if isinstance(node, ast.Attribute) and node.attr == "parent":
        return os.path.dirname(_path(node.value, env, self_name) or "") or None
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        return _join(_path(node.left, env, self_name), _path(node.right, env, self_name))
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Mod):
        return _fmt(node.left, _path(node.right, env, self_name))
    if isinstance(node, ast.Call):
        return _call(node, env, self_name)
    return None


def _fmt(template, tail):
    """`DIR + ("%s.bend" % name)` -> `DIR/name.bend`, or None.

    Only `DIR/<literal>` is resolved: the format must hold exactly one `%`
    conversion and carry no `/` of its own.  A wider rule here would let a
    `%`-containing path be resolved to something a human would not recognise,
    which is the failure mode this whole module is about.
    """
    if not (isinstance(template, ast.Constant) and isinstance(template.value, str)):
        return None
    t, tail = template.value, tail or ""
    if t.count("%") != 1 or "/" in t or not tail or os.path.isabs(tail):
        return None
    d = os.path.dirname(t)
    return (os.path.join(d, tail) if d else tail)


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
    # `Path(x).resolve()` / `.absolute()` take NO ARGUMENTS -- they resolve the
    # Path they are called on -- so the RECEIVER is the whole of it.  Reading
    # `node.args` here returned None for `resolve`, which is why three harnesses
    # silently read NO-SUBSTRATE.
    if f.attr in ("resolve", "absolute"):
        return _path(f.value, env, self_name)
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
    """Where a write destination lands: IN-PLAY / RECORD / SCRATCH / ELSEWHERE /
    UNDECIDED.

    IN-PLAY is the dangerous one and the reason this module exists.  A harness
    that writes into the repo must not be run unless live is byte-identical to
    its snapshot: the snapshot is a `jj restore` gun, and one silently put a
    dead 6,623-line `ops.bend` over the live 6,306-line one and destroyed
    committed work.

    RECORD exists because EVERY harness writes its result table under
    `.agents/slop/`, and calling that IN-PLAY put the four guarded harnesses back
    in the danger column after they had been fixed -- a false positive in the
    alarm teaches a reader to ignore the column, which is the same failure as
    missing a spelling.  A record is a write into the repo that nobody runs.
    """
    if not p:
        return "UNDECIDED"
    a = os.path.abspath(absolve(p))
    if a.startswith(SCRATCH_ROOT):
        return "SCRATCH"
    if a.startswith(os.path.join(ROOT, ".agents")):
        return "RECORD"
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


def containers(tree, self_name=None, env=None):
    """`{(container name, literal subscript): path}` for handles stored in a container.

    `H = [open(P,'w')]` binds `H` to nothing `path` understands, so `H[0].write(s)`
    has no receiver to resolve and the write vanished -- one of the holes the
    `mutanchor-writes-selftest.py` STILL list names.  Only a LITERAL subscript is
    resolved.  `H[i]` for a variable `i` would need that variable's value, and a
    reader that guessed an index would be inventing the measurement.
    """
    env = _bounds(tree, self_name) if env is None else env
    out = {}
    for _ in range(3):
        grown = dict(out)
        for n in ast.walk(tree):
            if not (isinstance(n, ast.Assign) and len(n.targets) == 1
                    and isinstance(n.targets[0], ast.Name)):
                continue
            if isinstance(n.value, (ast.List, ast.Tuple)):
                pairs = list(enumerate(n.value.elts))
            elif isinstance(n.value, ast.Dict):
                # A dict is keyed, and the key is what the reader will write: `H['f']`.
                # An UNRESOLVABLE key is recorded under its index so the handle is still
                # attributed to the container, which is the conservative direction.
                pairs = []
                for i, (k, v) in enumerate(zip(n.value.keys, n.value.values)):
                    pairs.append((k.value if isinstance(k, ast.Constant)
                                  and isinstance(k.value, (int, str)) else i, v))
            else:
                pairs = []
            for k, it in pairs:
                p = _opened(it, env, self_name)
                if p:
                    grown.setdefault((n.targets[0].id, k), p)
        if grown == out:
            return out
        out = grown
    return out


def _subscript(node, ct):
    """The path a literal `H[0]` / `H['f']` denotes in a container, or None."""
    if not (isinstance(node, ast.Subscript) and isinstance(node.value, ast.Name)):
        return None
    ix = node.slice
    k = ix.value if isinstance(ix, ast.Constant) and isinstance(ix.value, (int, str)) else None
    return None if k is None else ct.get((node.value.id, k))


def _command_text(node, env, self_name):
    """The command string a subprocess argument denotes, or None.

    Four spellings and all four are in the census, because each is a way of naming a
    destination that `ast.Constant` alone does not see:

      * `'cat > p'`                             a literal
      * `'cat > %s' % SRC`                      the `%`-form, resolved through `_path`
      * `'cat > ' + SRC`                        string concatenation
      * `['bash', '-c', 'cat > p']`             the list form, joined with spaces

    Folding is done on the STRING, not on the AST, and it stops the moment a part is
    unresolvable -- a command that mixes a literal path with a computed one returns
    None rather than a partially-known string, because a half-resolved redirect target
    is a destination nobody can act on.
    """
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, (ast.List, ast.Tuple)):
        parts = [_command_text(e, env, self_name) for e in node.elts]
        return " ".join(parts) if all(p is not None for p in parts) else None
    if isinstance(node, ast.BinOp):
        left, right = node.left, node.right
        if isinstance(node.op, ast.Mod):
            t, p = _command_text(left, env, self_name), _path(right, env, self_name)
            if t is not None and p is not None and t.count("%") == 1:
                return t % p
            return None
        if isinstance(node.op, ast.Add):
            a, b = _command_text(left, env, self_name), _command_text(right, env, self_name)
            return a + b if a is not None and b is not None else None
    return None


def _redirect_targets(node, env, self_name):
    """Paths named after a `>` or `>>` in a command STRING, or None.

    `2>` and `&>` are NOT read: those redirect a DESCRIPTOR rather than the command's
    stdout, and their target is usually `/dev/null` or a log rather than source.  This
    is a shape check on a string, not a shell parser, and it is the only shell
    knowledge here on purpose -- a shell parser here would be a second language in a
    hazard detector, which is the failure `mutanchor.py` exists to prevent.
    """
    text = _command_text(node, env, self_name)
    if text is None:
        return None
    toks = text.split()
    hits = []
    for i, t in enumerate(toks[:-1]):
        if not t.startswith(REDIRECT) or t.endswith("&") or set(t) - set("><"):
            continue
        hits.append(_target(toks[i + 1], env, self_name))
    return [h for h in hits if h]


def _target(tok, env, self_name):
    """The path a redirection target TOKEN names, or None.

    THE TOKEN IS NOT ROUND-TRIPPED THROUGH `ast.parse` FIRST, and that ordering is the
    whole fix.  `tinybendygrad/uop/ops.bend` parses as an EXPRESSION only by way of the
    attribute `ops.bend`, so `ast.parse` + `_path` returns None for a perfectly ordinary
    path and the redirect is missed -- which is what happened on the first attempt at
    every one of the three shell cases.  A redirect target is a STRING before it is an
    expression, so it is resolved as one:

      1. exactly a bound constant name (`> SRC`);
      2. a quoted literal, unquoted (`> "p"`);
      3. otherwise, parsed as an expression -- which is how `> %s/../x` would arrive.

    A token that does not parse is not a path, and `None` is the answer.  Raising would
    be the wrong direction: a census that crashes on a sibling harness's odd quoting has
    told the reader nothing about any file.
    """
    if tok in env:
        return env[tok]
    if len(tok) > 1 and tok[0] == tok[-1] and tok[0] in "\"'":
        return tok[1:-1]
    try:
        return _path(ast.parse(tok, mode="eval").body, env, self_name)
    except SyntaxError:
        return None


def _shell_spellings(n, env, self_name):
    """`[(path, spelling)]` for every redirection destination in a subprocess call.

    A command is SHELL-SHAPED when `shell=True` is passed, or when the first list
    element is one of the shells.  `run(['cat','>',SRC])` with neither is an argv
    vector naming a file called `>`, and reading it as a redirect is the false
    IN-PLAY that teaches a reader to stop believing the column.
    """
    f = n.func
    named = f.attr if isinstance(f, ast.Attribute) else (f.id if isinstance(f, ast.Name) else None)
    if named not in RUNNERS:
        return []
    first_is_shell = bool(n.args) and isinstance(n.args[0], (ast.List, ast.Tuple)) \
        and n.args[0].elts and isinstance(n.args[0].elts[0], ast.Constant) \
        and n.args[0].elts[0].value in SHELLS
    if not (first_is_shell or any(k.arg == "shell" for k in n.keywords)):
        return []
    out = []
    for a in list(n.args) + [k.value for k in n.keywords]:
        for p in _redirect_targets(a, env, self_name) or []:
            out.append((p, "shell redirect in %s" % named))
    return out


def imports(tree):
    """`{module name}` for every sibling harness this file imports AT MODULE SCOPE.

    NOT a write detector, and deliberately not offered as one.  A sibling harness's
    import-time side effect is the one hole on that list a single-file AST cannot
    close: the write lives in the OTHER file, and closing it needs either cross-file
    dataflow or executing the import, and this module executes nothing by design.

    What IS closeable is the EDGE.  A census can enumerate which harnesses import
    which, and the writer is then one `--read` away.  Reporting the edge AS IF it were
    a write would be the worse failure, because a false IN-PLAY is indistinguishable
    from a real one once the column has been believed for long enough.
    """
    out = set()
    for n in tree.body:                       # MODULE SCOPE ONLY, on purpose
        if isinstance(n, ast.Import):
            out.update(a.name for a in n.names)
        elif isinstance(n, ast.ImportFrom) and n.module:
            out.add(n.module)
    return out


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
    ct = containers(tree, self_name, env)
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
        #    `H[0].write(s)` adds the container case: a literal subscript resolves.
        elif isinstance(f, ast.Attribute) and f.attr in HANDLE_METHODS:
            p = _opened(f.value, env, self_name) or \
                (hd.get(f.value.id) if isinstance(f.value, ast.Name) else None) or \
                _subscript(f.value, ct)
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
        # 7. a WRITABLE HANDLE PASSED AS AN ARGUMENT -- `dump(x, f)`.  The callee
        #    writes and this file cannot see it, so the claim is a MAY and the
        #    spelling says so.  A method CALL is excluded because `HANDLE_METHODS`
        #    already caught it and double-counting inflates the number.
        if not isinstance(f, ast.Attribute) or f.attr not in HANDLE_METHODS:
            for sub in list(n.args) + [k.value for k in n.keywords]:
                p = hd.get(sub.id) if isinstance(sub, ast.Name) else None
                if p:
                    out.append((zone(p), absolve(p),
                                "MAY write: %s passed a writable handle"
                                % (f.id if isinstance(f, ast.Name) else f.attr)))
        # 8. SHELL REDIRECTION -- `run('cat > %s' % SRC, shell=True)`.  The `>` is not
        #    a Python write, so no branch on a call's own attributes can see it.
        for p, spelling in _shell_spellings(n, env, self_name):
            out.append((zone(p), absolve(p), spelling))
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

    THE VOTE runs on the TRANSFORMED rows and the RESULT is the RAW cell, because
    those are two different questions.  The vote asks "which cell will the harness
    search", and that is the transformed text.  The report asks "what does the
    harness declare", and that is the literal in the table -- and `present()` is
    what decides whether the declared anchor is findable, in either spelling.
    Returning the transformed cell from here made `present()` transform it a SECOND
    time, and since `q()` is idempotent on an already-qualified name the raw
    spelling was never reachable: one anchor stayed STALE while the harness applied
    it.
    """
    v = mutations(tree)
    if v is None:
        return None
    q = transform(tree, self_name)
    voted = [[q(c) if (q is not None and isinstance(c, str)) else c for c in e]
             for e in v]
    col = anchor_column(voted, texts) if texts else None
    out = {}
    for e in v:
        if len(e) > 1 and isinstance(e[0], str):
            c = e[col] if col is not None and col < len(e) else None
            out[e[0]] = c if isinstance(c, str) else None
    return out


def present(tree, anchor, texts, self_name=None):
    """Is `anchor` in ANY of `texts`, in EITHER spelling the harness would try?

    Two spellings, because a harness transform like `q()` is right for a CALL site
    and wrong for a `def`'s own header in the file that defines it: `tb_pset.put` is
    spelled bare in `linearizer.bend` and `q` turns it into a spelling that is
    nowhere.  `StagedSet` tries transformed-first-then-raw for exactly this reason,
    and a reader that checked only the transformed form reported that anchor
    STALE while the harness applied it -- the reader and the tool disagreeing about
    the same string, which is the failure mode of every other false report here.
    """
    if not anchor:
        return False
    q = transform(tree, self_name)
    for text in ([q(anchor), anchor] if q else [anchor]):
        if any(text in t for t in texts):
            return True
    return False


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


