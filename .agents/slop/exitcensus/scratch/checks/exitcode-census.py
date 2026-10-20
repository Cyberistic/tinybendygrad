#!/usr/bin/env python3
"""exitcode-census.py -- THE EXIT CODES OF EVERY INSTRUMENT IN checks/ AND gates/, PARSED NOT RUN.

    .venv/bin/python checks/exitcode-census.py
    .venv/bin/python checks/exitcode-census.py --selftest

THE POPULATION IS DISCOVERED, NOT LISTED (`AGENTS.md` doctrine 1): `os.walk` over `checks/`
and `gates/`, `filename.endswith(".py")`. No document's list is read, and no instrument is
executed -- importing a gate RUNS it (`gates/gate-surface.py`'s own docstring records
`gates/mixin-op-gate.py` and `gates/beautiful-mnist-gate.py` calling `sys.exit(2)` at module
scope), and a census that runs its population is not a census.

THE VOCABULARY IS LOADED BY PATH, never retyped: `gates/gatekit.py` through
`importlib.util.spec_from_file_location`.

THE EXIT CONTRACT, IN THREE NUMBERS, FROM `gates/gatekit.py`'s OWN five:

    0  PASS     the census measured and there is nothing to charge.
    1  FAIL     the census measured and it found something: a code the vocabulary does not
                name and no convention owns, or an instrument that hands a SENTENCE to the
                exit (CPython prints it and exits 1, so the token is the only witness).
    3  REFUSED  the census COULD NOT MEASURE: the vocabulary owner is missing, ambiguous, or
                unreadable, or an instrument in the population cannot be parsed.  A census
                that cannot classify says so and never guesses.

`--selftest` is its OWN lane with its OWN exit (0 all plants moved, 1 one did not), because
"do my plants still move?" is not the census's question -- `checks/cites-census.py` draws the
same line, and `checks/cites-census.py:879-881` is the precedent for the shape.

THE ROW FILE IS BESIDE THIS FILE AND IN GIT (`checks/exitcode-census.rows`), because
`gates/artifacts/` and `runs/` are BOTH `.gitignore`d, and a finding that lives in an ignored
directory is a finding that a fresh clone does not have.  `gates/edge-trace.rows` is the
precedent: a GENERATED trace, committed beside its generator, is the only trace that survives.
`AGENTS.md`: "A GATE'S REQUIRED INPUT BELONGS BESIDE THE GATE IN GIT -- AND NOT IN
`gates/artifacts/`, WHICH THIS FILE USED TO RECOMMEND."

WHAT COUNTS, AND WHY IT IS A SLICE AND NOT A SCAN. "An integer under a `return`" is not an exit
code: it read 2,689 rows on this tree, and 2,410 of them were `return self.rows` in a helper
returning to a caller. "Every `return` inside the functions `main()` calls" is closer and still
wrong -- 761 rows, 163 of them `return <Tuple>` from a helper returning DATA. The question is not
which functions are reachable FORWARD, it is which values reach the `sys.exit` argument BACKWARD.
So every `sys.exit`/`exit`/`raise SystemExit` site is a ROOT, and its argument is resolved:

    0 1 3 ...     an integer literal, or an `if/else` of them, or `ok and 1`
    NAMES          a local bound from a resolvable expression; followed
    a MODULE CALL  `sys.exit(main())` -> `main`'s resolved returns, transitively
    NOT-A-CODE     a dict, a comprehension, a tuple, a string: PROVABLY not an int
    UNDETERMINED   an attribute, a subscript, a foreign call, an unbound name: a code computed
                   at runtime or DELEGATED. Reported REFUSED, never guessed.

THE LIMITS ARE STATED, NOT HIDDEN. Resolution is same-module by NAME only, so `sys.exit(gatekit
.gate(GATE, ...))` -- the shape most gates in `gates/` use -- is UNDETERMINED, and the row NAMES
what it delegates to rather than leaving the reader to find it. Resolution is depth-limited.
An UNDETERMINED row is not a claim that the instrument has no other codes; it is a claim that
THIS instrument cannot see them.

`declared` IS A LEXICAL TEST, not a reading -- see `declared()` for exactly what it can and cannot
see. The UNOWNED and UNDECLARED classes are hand-read on top of it, and the report gives both
numbers.
"""
import ast
import io
import os
import re
import sys
import tempfile
import warnings
from pathlib import Path

# THE PROMOTED ROOT. `checks/exitcode-census.py` is ONE level below the root, and
# `Path(__file__).resolve().parents[1]` is the root OF A FILE -- `parents[0]` is the file's own
# DIRECTORY (`checks/`).  `gates/gates-pop.py`'s ROOT_CONST clause says this in prose and MEASURES
# that `checks/differ.py:41` and `checks/abi_gate.py:50` disagree about it while both being right:
# one counts from the FILE and one from the DIRECTORY.  THIS FILE COUNTS FROM THE FILE.
#
# THE SCRATCH COPY TAKES `--root` BECAUSE THE SCRATCH LIVES THREE LEVELS DEEPER, AND A CONSTANT
# THAT IS ONLY RIGHT IN ONE PLACE IS A CONSTANT THAT WILL BE WRONG SOMEWHERE ELSE.
def _default_root() -> Path:
    return Path(__file__).resolve().parents[1]


ROOT = _default_root()
HOMES = ("checks", "gates")
GATEKIT = ROOT / "gates" / "gatekit.py"
HERE = Path(__file__).resolve().parent
# THE ROW FILE, BESIDE THIS FILE, IN GIT.  NOT `runs/` and NOT `gates/artifacts/`: both are
# `.gitignore`d (`.gitignore:262` and `.gitignore:214`), so a finding written there is a finding
# a fresh clone does not have.  `gates/edge-trace.rows` is the precedent -- a GENERATED trace
# committed beside its generator.
OUT = HERE / "exitcode-census.rows"
DEPTH = 14

# THE ROOT IS ASSERTED, NOT ASSUMED.  `gates/gates-pop.py:679-680` looks for a `refuse(` guarded
# by a marker-file test, and `gates/gates-pop.py:2468-2470` refuses when the marker is absent.
# A census that walks the WRONG tree and reports "the tree is clean" is the worst failure there
# is, so the root is CHECKED before anything is counted.
MARKERS = ("pyproject.toml", "tinybendygrad")

# THE CONVENTIONS, AND THEY ARE CODES, NOT INSTRUMENTS.  A code the tree uses that the vocabulary
# does not name is UNOWNED -- unless it is a CONVENTION whose meaning is fixed by something
# outside this tree.  Two such conventions exist and both are DECLARED here rather than inferred:
#
#   2    argparse's own USAGE code, and it counts ONLY in an instrument that imports argparse.
#        In an instrument that does NOT import argparse, a `2` is a CHOSEN number and the census
#        charges it -- because the argument for "2 is argparse's" is STRUCTURAL (the file imports
#        argparse) and a file that does not import argparse has no such argument.
#   126  POSIX: the command was found and is not executable.
#   127  POSIX: the command was not found.
#
# A CODE-LEVEL LIST, NOT A LIST OF INSTRUMENTS: it says what a NUMBER means, and it cannot go
# stale by an instrument moving, because it names no instrument.
CONVENTIONS = {126: "NOT-EXECUTABLE", 127: "NOT-FOUND"}

# A number in one of these shapes is a CODE the prose says something ABOUT.  The shapes are
# stated here, in the reader, rather than in a second copy of anybody's prose.
#
# *** THE VERDICT WORDS ARE NOT A LIST.  THEY ARE DISCOVERED.  ***
# The word set this test recognises is the OWNER's words (read from `gates/gatekit.py` by path)
# UNION the words the TREE's own `VERDICTS` tables use (read from every instrument's module body
# by `ast.literal_eval`, the same shape `gates/gate-surface.py` reads).  A census that retyped
# `REFUSED|SKIP|DEAD|PASS|FAIL|USAGE|VERDICT|GREEN|RED` would be a SECOND COPY of a vocabulary
# that can change under it: rename `DEAD` to `DROPPED` in the owner and the copy would stop
# recognising a declaration that the owner still makes.  `selftest()` PLANTS that drift.
DECLARING = (
    r"\b(?:exit|exits|exit\s+code|return|returns|returned|code|rc|status|verdict|die|dead)"
    r"\w*\s*(?:=|:|is|of|as)?\s*{d}\b"
    r"|\b{d}\b\s*(?:=|:)\s*(?:is\s+)?(?:{w})"
    r"|\b{d}\s*[-\u2013]\s*(?:{w})"
    r"|\b(?:{w})\b[^.\n]{{0,40}}\b{d}\b"
)


def vocabulary(owner=None):
    """`{code: NAME}` from the vocabulary OWNER, PARSED -- never executed, never retyped.

    *** THE SHAPE IS `gates/gate-surface.py`'s, AND IT IS THE RIGHT ONE. ***  That file parses the
    owner's module body for a name<-code UNPACK and REFUSES when there is not exactly one; it does
    NOT import the owner.  The previous version of this file did `importlib` and read
    `mod.VERDICT`, which couples the census to the ATTRIBUTE NAME: rename the dict in the owner
    and the census raises `AttributeError` and DIES, when the honest answer is a REFUSAL.  A
    census that executes its own vocabulary owner also executes whatever side effects that file
    has, and `gates/gate-surface.py`'s own docstring records that importing a gate RUNS it.

    The owner is `gates/gatekit.py`, whose `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5` is
    the tree's five verdicts.  `gates/gate-surface.py:270` refuses an AMBIGUOUS owner (zero or two
    unpacks) rather than picking one, and so does this.
    """
    p = Path(owner) if owner else GATEKIT
    if not p.is_file():
        raise Refused(f"{p} is gone -- it OWNS the exit vocabulary and this file has no second "
                      f"copy of it by design")
    found = []
    for node in ast.parse(p.read_text(errors="replace")).body:
        targets = node.targets if isinstance(node, ast.Assign) else []
        for tgt in targets:
            if not (isinstance(tgt, ast.Tuple) and len(tgt.elts) > 1
                    and all(isinstance(e, ast.Name) for e in tgt.elts)):
                continue
            try:
                codes = ast.literal_eval(node.value)
            except (ValueError, SyntaxError, TypeError):
                continue
            if isinstance(codes, tuple) and len(codes) == len(tgt.elts):
                found.append(dict(zip(codes, (e.id for e in tgt.elts))))
    if len(found) != 1:
        raise Refused(f"{p} holds {len(found)} module-level name<-code unpack(s); exactly 1 is "
                      f"required for there to be an owner of the exit vocabulary, and an ambiguous "
                      f"owner is REFUSED rather than guessed")
    return found[0]


class Refused(Exception):
    """A precondition of THIS census was absent.  It reaches the exit as 3."""


def verdict_words(vocab):
    """The words the DECLARING test recognises: the owner's, plus the tree's own `VERDICTS`.

    The second half is DISCOVERED, not listed: every instrument's module body is read for a
    `VERDICTS` / `VERDICT` mapping and its VALUES are the words the tree actually uses.  A gate
    that says `4: "NO-ROW"` contributes `NO-ROW`; one that says `2: "USAGE"` contributes `USAGE`.
    """
    words = set(vocab.values())
    for rel, src in _sources():
        try:
            body = ast.parse(src).body
        except SyntaxError:
            continue
        for node in body:
            if not isinstance(node, ast.Assign):
                continue
            names = [t.id for t in node.targets if isinstance(t, ast.Name)]
            if not any(n in ("VERDICTS", "VERDICT") for n in names):
                continue
            try:
                table = ast.literal_eval(node.value)
            except (ValueError, SyntaxError, TypeError):
                continue
            if isinstance(table, dict):
                words |= {str(v) for v in table.values()}
    return words


def _sources():
    """`(rel, source)` for every `.py` under the homes -- the walk, ONCE."""
    out = []
    for home in HOMES:
        base = ROOT / home
        if not base.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in sorted(filenames):
                if fn.endswith(".py"):
                    p = Path(dirpath) / fn
                    out.append((str(p.relative_to(ROOT)), p.read_text(errors="replace")))
    return sorted(out)


def prose(path):
    """`(module_docstring + leading comment block)`, the instrument's OWN header.

    The block stops at the first line that is neither a comment nor blank, so a `VERDICTS = {...}`
    sixty lines down is NOT read as prose -- only what a reader sees before any code.
    """
    src = path.read_text(errors="replace")
    try:
        doc = ast.get_docstring(ast.parse(src), clean=False) or ""
    except SyntaxError:
        doc = ""
    block = []
    for l in src.splitlines():
        if l.strip() == "":
            continue
        if l.strip().startswith(("#", '"""', "'''")):
            block.append(l)
            continue
        break
    return doc + "\n" + "\n".join(block)


# ---- the slice -----------------------------------------------------------------------
def own(node):
    """Nodes of `node`'s body, NOT descending into a nested `def`/`class`/`lambda`.

    `ast.walk(f)` visits every return in every NESTED function, so a gate whose `main()` closes
    over three helpers reported their returns as its own.
    """
    stack = list(getattr(node, "body", []))
    while stack:
        n = stack.pop()
        yield n
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda, ast.ClassDef)):
            continue
        stack += list(ast.iter_child_nodes(n))


def bindings(fnode):
    """`{local name: [bound expressions]}`, from assigns, annotated assigns, for-targets,
    with-items and walruses. A name bound twice by two different expressions is resolved as both,
    because which one runs is a control-flow question this file does not answer."""
    out = {}
    for n in own(fnode):
        tgts = []
        if isinstance(n, ast.Assign):
            tgts = n.targets + [t for t in n.targets]
        elif isinstance(n, ast.AnnAssign):
            tgts = [n.target]
        elif isinstance(n, ast.AugAssign):
            tgts = [n.target]
        elif isinstance(n, (ast.For, ast.AsyncFor)):
            tgts = [n.target]
        elif isinstance(n, (ast.With, ast.AsyncWith)):
            tgts = [i.optional_vars for i in n.items if i.optional_vars]
        elif isinstance(n, ast.NamedExpr):
            tgts = [n.target]
        for t in tgts:
            if isinstance(t, ast.Name) and getattr(n, "value", None) is not None:
                out.setdefault(t.id, []).append(n.value)
            elif isinstance(t, ast.Name):
                out.setdefault(t.id, [])          # a `for` target: bound at runtime, no expression
    return out


NOTCODE = "NOT-A-CODE"


class Resolver:
    def __init__(self, funcs):
        self.funcs = funcs
        self.delegated = set()

    def codes(self, fnode, depth=0):
        """`(set_of_codes, list_of_(line, description))` for everything `fnode` can RETURN."""
        found, undetermined = set(), []
        if depth > DEPTH:
            return found, [(fnode.lineno, "depth limit reached; the chain continues past it")]
        binds = bindings(fnode)
        for n in own(fnode):
            if isinstance(n, ast.Return) and n.value is not None:
                c, u = self.expr(n.value, binds, depth)
                found |= c
                undetermined += u
        return found, undetermined

    def expr(self, node, binds, depth):
        """`(codes, undetermined)` for ONE expression -- the recursive step of the slice."""
        if isinstance(node, ast.Constant):
            if isinstance(node.value, bool) or not isinstance(node.value, int):
                return set(), []
            return {node.value}, []
        if isinstance(node, (ast.Dict, ast.Tuple, ast.List, ast.Set, ast.ListComp,
                             ast.SetComp, ast.DictComp, ast.GeneratorExp, ast.JoinedStr,
                             ast.Lambda, ast.Await)):
            return set(), []                          # provably not an int literal
        if isinstance(node, ast.IfExp):
            a = self.expr(node.body, binds, depth)
            b = self.expr(node.orelse, binds, depth)
            return a[0] | b[0], a[1] + b[1]
        if isinstance(node, ast.BoolOp):              # `ok and 1`, `1 if ... else ...` folds here
            c, u = set(), []
            for v in node.values:
                a, b = self.expr(v, binds, depth)
                c |= a
                u += b
            return c, u
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            a, b = self.expr(node.operand, binds, depth)
            return {-x for x in a}, b
        if isinstance(node, ast.Name):
            if node.id in binds and binds[node.id]:
                c, u = set(), []
                for v in binds[node.id]:
                    if v is None:
                        continue
                    a, b = self.expr(v, binds, depth)
                    c |= a
                    u += b
                if c or not u:
                    return c, u
            return set(), [(node.lineno, f"the name `{node.id}` is bound at runtime")]
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) \
                and node.func.id in self.funcs:
            self.delegated.add(node.func.id)
            return self.codes(self.funcs[node.func.id], depth + 1)
        if isinstance(node, ast.Call):
            t = callee(node)
            self.delegated.add(t)
            return set(), [(node.lineno, f"a FOREIGN call: `{t}` -- its value is not in this "
                                         f"module and is not guessed")]
        return set(), [(node.lineno, f"a runtime value of type `{type(node).__name__}`")]


def callee(node):
    """`module.attr` / `name` for a Call target, so a DELEGATION can be NAMED in its row."""
    fn = getattr(node, "func", None)
    if isinstance(fn, ast.Attribute):
        return f"{fn.attr}() on {ast.unparse(fn.value)}"
    return fn.id if isinstance(fn, ast.Name) else ast.unparse(fn)[:40]


def is_exit_call(node):
    return isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
        and node.func.attr == "exit"


def exit_roots(tree):
    """Every `sys.exit(...)` / `exit(...)` / `raise SystemExit(...)` site in the module."""
    out = []
    for n in ast.walk(tree):
        if isinstance(n, ast.Raise) and isinstance(n.exc, ast.Call):
            fn = n.exc.func
            if (isinstance(fn, ast.Name) and fn.id == "SystemExit") or \
               (isinstance(fn, ast.Attribute) and fn.attr == "SystemExit"):
                args = n.exc.args + [kw.value for kw in n.exc.keywords]
                out.append((n.lineno, args[0] if args else ast.Constant(value=0), "SystemExit"))
        elif is_exit_call(n):
            args = n.args + [kw.value for kw in n.keywords]
            out.append((n.lineno, args[0] if args else None, "sys.exit"))
    return out


def main():
    """THE CENSUS, AND THEN THE EXIT.

    THE ROW FILE IS THE REPORT AND THE EXIT IS ITS `worst()` -- the same shape
    `checks/cites-census.py` uses, and the same reason: a census whose printed verdict and its
    exit code can disagree is a census whose reader cannot tell what it measured.
    """
    args = _parse()
    if args.root:
        globals()["ROOT"] = Path(args.root).resolve()
        globals()["GATEKIT"] = ROOT / "gates" / "gatekit.py"
    if args.owner:
        globals()["GATEKIT"] = Path(args.owner).resolve()
    if args.selftest:
        return selftest(args.root)
    # THE ROOT IS ASSERTED BEFORE ANY MEASUREMENT.  A census that walked the WRONG tree and
    # printed "nothing to charge" would be a green about a tree that does not exist -- the exact
    # failure `gates/gate-surface.py`'s docstring records for `checks/citation-gate.py`, "a plant
    # that exits 0 having read nothing is indistinguishable, from the exit status alone, from a
    # plant that agreed".
    missing = [m for m in MARKERS if not (ROOT / m).exists()]
    if missing:
        print(f"== REFUSED, NOT A VERDICT: the repo root is not here: {', '.join(missing)} is "
              f"absent at {ROOT}")
        return 3
    try:
        vocab = vocabulary(args.owner)
    except (Refused, SyntaxError) as e:
        print(f"== REFUSED, NOT A VERDICT: {e}")
        return 3
    try:
        with warnings.catch_warnings():
            # other people's SyntaxWarnings are not our verdicts -- `checks/cites-census.py:903-904`
            # draws the same line, and a census that prints another file's warning on its own
            # stderr teaches a reader to ignore its stderr.
            warnings.simplefilter("ignore")
            words = verdict_words(vocab)
            rows, stats = census(vocab, words)
    except Refused as e:
        print(f"== REFUSED, NOT A VERDICT: {e}")
        return 3
    if args.rows:
        out = Path(args.rows)
    else:
        out = OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    w = io.StringIO()
    w.write("instrument\tcode\tverdict\tdeclared_in_own_prose\tnote\n")
    for r in rows:
        w.write("\t".join(str(x) for x in r) + "\n")
    out.write_text(w.getvalue())

    print(f"population   {stats['files']} .py under {'/'.join(HOMES)}/ (os.walk + endswith('.py'))")
    print(f"tracked      {stats['tracked']} in HEAD; {stats['untracked']} on disk only "
          f"(NOT in HEAD, not charged): {', '.join(stats['untracked_names']) or 'none'}")
    print(f"rows         {len(rows)}")
    print(f"distinct     {len(stats['codes'])} exit codes: {sorted(stats['codes'])}")
    print(f"CONVENTION   {stats['convention']} row(s) -- a code the tree uses that the vocabulary "
          f"does not name, with a meaning fixed outside this tree")
    print(f"CLAIMED      {stats['claimed']} row(s) -- the instrument names the number in its own "
          f"header, so the tree is not silent about it (NOT charged).  THE SHORTLIST FOR HAND "
          f"ADJUDICATION, because the excuse is a LEXICAL LOWER BOUND and it has a false "
          f"positive: {', '.join(sorted(stats['claimed_names'])) or 'none'}")
    print(f"UNOWNED      {stats['unowned']} row(s) over {len(stats['unowned_files'])} instrument(s) "
          f"-- CHARGED")
    print(f"MESSAGE-EXIT {stats['message']} instrument(s) -- CHARGED")
    print(f"UNDETERMINED {stats['undetermined']} instrument(s) -- NOT charged: a declared limit of "
          f"a static reader, not an absent precondition")
    print(f"NO-EXIT-PATH {stats['no_path']} instrument(s) -- modules, not entry points")
    print(f"UNDECLARED   {stats['undeclared']} row(s) over {len(stats['undeclared_files'])} "
          f"instrument(s) -- NOT charged: a LEXICAL LOWER BOUND, and a gate cannot charge a lower "
          f"bound.  The names are in the row file: column 4 reads 'no'.")
    print(f"wrote        {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out}")
    return stats["exit"]


def _parse():
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--root", default=None, help="the tree to census (the scratch copy only)")
    ap.add_argument("--owner", default=None, help="the vocabulary owner (default gates/gatekit.py)")
    ap.add_argument("--rows", default=None, help="write the rows here (.rows)")
    return ap.parse_args()


def census(vocab, words):
    """`(rows, stats)` -- the reading, and the numbers the exit is computed from."""
    rows = []
    files = []
    for home in HOMES:
        base = ROOT / home
        if not base.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            files += [Path(dirpath) / fn for fn in filenames if fn.endswith(".py")]
    files.sort()
    head = _committed()
    undetermined_files, no_path, untracked_names = [], [], []
    stats = dict(files=len(files), tracked=0, untracked=0, untracked_names=untracked_names,
                 codes=set(), convention=0, claimed=0, claimed_names=set(), unowned=0,
                 unowned_files=set(), message=0,
                 undetermined=0, no_path=0, undeclared=0, undeclared_files=set(), exit=0)
    for p in files:
        rel = str(p.relative_to(ROOT))
        src = p.read_text(errors="replace")
        head_prose = prose(p)
        tracked = head is None or rel in head
        if tracked:
            stats["tracked"] += 1
        else:
            stats["untracked"] += 1
            untracked_names.append(rel)
        uses_argparse = bool(re.search(r"^\s*import\s+argparse|^\s*from\s+argparse\s+import",
                                       src, re.M))
        try:
            tree = ast.parse(src)
        except SyntaxError as e:
            rows.append((rel, "?", "UNPARSED", "na", f"REFUSED: SyntaxError: {e.msg} "
                                                      f"at line {e.lineno}"
                                 + ("" if tracked else " -- NOT in HEAD, so not charged")))
            continue
        r = Resolver({n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)})
        direct, msg_sites, nondet = {}, [], []
        for line, arg, form in exit_roots(tree):
            if arg is None:
                msg_sites.append((line, f"{form}() with NO ARGUMENT"))
                continue
            if isinstance(arg, ast.Constant) and not (isinstance(arg.value, int)
                                                      and not isinstance(arg.value, bool)) \
                    or isinstance(arg, ast.JoinedStr):
                kind = "an f-string" if isinstance(arg, ast.JoinedStr) else \
                    ("the string None" if arg.value is None else "a string")
                msg_sites.append((line, f"{form}({kind})"))
                continue
            c, u = r.expr(arg, {}, 0)
            for code in c:
                direct.setdefault(code, ([], set()))
                direct[code][0].append(line)
                direct[code][1].add(form)
            nondet += [(line, d) for _c, d in u]

        if msg_sites:
            rows.append((rel, "str", "MESSAGE-EXIT", "na",
                         f"{len(msg_sites)} site(s) hand a NON-INT to the exit: "
                         + "; ".join(f"line {l} {k}" for l, k in msg_sites)
                         + ". CPython prints it to stderr and exits 1, so to `$?` every one of "
                           "them IS FAIL, whatever the text says -- the token is the only witness"
                         + ("" if tracked else " -- NOT in HEAD, so not charged")))
            if tracked:
                stats["message"] += 1
        if nondet:
            undetermined_files.append(rel)
            rows.append((rel, "?", "UNDETERMINED", "na",
                         f"{len(nondet)} site(s) whose code is computed at runtime or delegated: "
                         + "; ".join(f"line {l} {d}" for l, d in nondet)
                         + ". REFUSED, not guessed"))
            stats["undetermined"] += 1
        for code in sorted(direct):
            lines, forms = direct[code]
            nt = (f"{'/'.join(sorted(forms))} at line{'s' if len(lines) > 1 else ''} "
                  f"{','.join(str(l) for l in lines)}")
            stats["codes"].add(code)
            dec = declared(head_prose, code, words)
            if code in vocab:
                verdict = vocab[code]
            elif code == 2 and uses_argparse:
                verdict = "CONVENTION"
                nt += ("; 2 is argparse's own USAGE code here -- the file imports argparse, so "
                       "the number is INHERITED, not chosen")
                stats["convention"] += 1
            elif code in CONVENTIONS:
                verdict = "CONVENTION"
                nt += f"; {code} is POSIX {CONVENTIONS[code]}"
                stats["convention"] += 1
            elif dec == "yes":
                # *** THE INSTRUMENT CLAIMS THE NUMBER, AND A CLAIM IS NOT A FINDING. ***
                # Its own header says what the number means, so the tree is not silent about it.
                # This test is a LEXICAL LOWER BOUND, which is why it is safe HERE and unsafe as
                # a CHARGE: it can only UNDER-report (a meaning stated without the digit is
                # missed, so the row stays UNOWNED), and a census that under-reports is a census
                # with false negatives, which is the safe direction to be wrong in.
                verdict = "CLAIMED"
                nt += ("; the instrument names this number in its own header, so the tree is not "
                       "silent about it -- the SUBSET declared in a `VERDICTS` table is already "
                       "charged by `gates/gate-surface.py` and is not charged twice here")
                stats["claimed"] += 1
                stats["claimed_names"].add(f"{rel} code {code}")
            else:
                verdict = "UNOWNED"
                if tracked:
                    stats["unowned"] += 1
                    stats["unowned_files"].add(rel)
                nt += ("; a code the vocabulary does not name, and not a convention this file "
                       "inherits, and this file's own header does not claim -- a reader "
                       "aggregating this instrument is guessing"
                       + ("" if tracked else " -- NOT in HEAD, so not charged"))
            dec = declared(head_prose, code, words)
            if verdict in vocab.values() and dec == "no":
                stats["undeclared"] += 1
                stats["undeclared_files"].add(rel)
            rows.append((rel, str(code), verdict, dec, nt))
        if not direct and not nondet and not msg_sites:
            no_path.append(rel)
            rows.append((rel, "-", "NO-EXIT-PATH", "na",
                         "no sys.exit/exit/SystemExit anywhere: a MODULE, not an entry point"))
            stats["no_path"] += 1

    # THE EXIT, IN ONE PLACE.  `checks/cites-census.py:625` is the precedent and the reason:
    # a census whose printed verdict and its exit code can disagree is a census whose reader
    # cannot tell what it measured.
    charged = [r for r in rows if r[2] in ("UNOWNED", "MESSAGE-EXIT")]
    unparsed = [r for r in rows if r[2] == "UNPARSED"]
    if unparsed:
        stats["exit"] = 3
    elif charged:
        stats["exit"] = 1
    else:
        stats["exit"] = 0
    return rows, stats


def _committed():
    """The COMMITTED paths, by `git ls-tree -r HEAD` -- git's own declaration of the tree.

    `git ls-files` reads the INDEX, which this repo arms with intent-to-add placeholders BY DESIGN
    (`jj git colocation`), so it answers hundreds of paths HEAD does not contain.

    `None` means THERE IS NO HEAD -- the tree is not a git repository -- and then every file on
    disk IS the population.  The distinction matters because the census CHARGES only instruments
    that are IN HEAD: an untracked file is a staging temp or a half-written gate, and a gate whose
    verdict depends on one is a gate whose verdict moves with the working tree.  `checks/cites-
    census.py` draws the same line and NAMES the ones it leaves out.

    A git that FAILS for any OTHER reason is a REFUSAL, not an empty population: `checks/cites-
    census.py:60-64` exits 3 when `git ls-tree` does not succeed, and a census that silently
    treats a broken git as "everything is tracked" would charge the tree for its own temp files.
    """
    import subprocess
    r = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                       capture_output=True, text=True)
    if r.returncode == 0:
        return set(r.stdout.splitlines())
    if "not a git repository" in r.stderr:
        return None
    raise Refused(f"git ls-tree -r HEAD failed (rc={r.returncode}): {r.stderr.strip()} -- the "
                  f"committed population cannot be read, so what is charged cannot be decided")


def declared(head, code, words):
    """`yes` if the instrument's own PROSE says something ABOUT THIS NUMBER.

    A LEXICAL TEST, NAMED AS ONE, and the LOWER BOUND of declaration: a row read `no` may still
    have its meaning stated in a shape this does not know, and a row read `yes` may be counting
    rows or bytes. **The report carries this class's size AND the hand-read adjudication of the
    UNOWNED and MESSAGE-EXIT classes, and the difference between them is itself reported.**

    *** AND IT IS NOT CHARGED, BECAUSE IT IS A LOWER BOUND. ***  A gate cannot charge a
    measurement its own instrument says is not a reading: the test can be fooled by a row count
    and can miss a meaning stated without the digit, so a red on it would be a red on the
    LEXICON, not on the tree.  `checks/cites-census.py` draws the same line -- its lane E is
    "mentions -- COUNTED, NEVER A VERDICT", and it prints "3547 claims PASS on EXISTENCE and
    check nothing else -- they CANNOT FAIL".
    """
    alts = "|".join(re.escape(w) for w in sorted(words))
    return "yes" if re.search(DECLARING.format(d=re.escape(str(code)), w=alts), head) else "no"


# ---------------------------------------------------------------- the self-test
def selftest(root=None):
    """THE HARNESS COMES FIRST, AND ITS SUBJECT IS THE DRIFT.

    A census of the tree's exit vocabulary is COUPLED to the tree's exit vocabulary, and a
    coupling that cannot fail is a coupling that is not there.  Every plant below asserts that
    the census's GRAMMAR FOLLOWS the live owner: change the owner and the census must change
    with it, or the selftest FAILS.

    THE PLANTS:
      1  the owner GAINS a code -- the census must SEE the new code as owned, so a census that
         hard-coded "2 is UNOWNED" fails here.
      2  the owner RENAMES a verdict -- the DECLARING grammar must follow, so a prose that says
         "5 is DROPPED" must read as DECLARED under a DROPPED owner.
      3  the owner is AMBIGUOUS (two unpacks) -- the census must REFUSE (3), never pick one.
      4  the owner is GONE -- the census must REFUSE (3), never fall back to a typed copy.
      5  a MESSAGE-EXIT site is CHARGED (exit 1).
      6  an argparse instrument's `2` is a CONVENTION and is NOT charged; the same `2` in an
         instrument that does NOT import argparse IS charged.
      7  an UNPARSED instrument is REFUSED and REACHES THE EXIT (3).
      8  the tree's OWN `gates/gatekit.py` is READABLE by this census.
      9  no code is BOTH in the live vocabulary and in this file's `CONVENTIONS` -- a code the
         owner names cannot also be "a convention outside the tree".
    """
    cases = []
    with tempfile.TemporaryDirectory(prefix="exitcode-census-") as tmp:
        d = Path(tmp)
        tree = d / "tree"
        (tree / "checks").mkdir(parents=True)
        (tree / "gates").mkdir(parents=True)
        owner = tree / "gates" / "gatekit.py"
        owner.write_text("PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5\n")
        (tree / "checks" / "argparse-one.py").write_text(
            "import argparse\nimport sys\ndef main():\n    if len(sys.argv) != 2:\n"
            "        return 2\n    return 0\nif __name__ == '__main__':\n    sys.exit(main())\n")
        (tree / "checks" / "chosen-two.py").write_text(
            "import sys\ndef main():\n    return 2\nif __name__ == '__main__':\n    sys.exit(main())\n")
        (tree / "checks" / "message.py").write_text(
            "import sys\ndef main():\n    sys.exit('a message')\n"
            "if __name__ == '__main__':\n    sys.exit(main())\n")

        cases.append(("CONTROL: the owner is READ, and the census runs",
                      _run(tree, owner)[0], 1))
        # 1 -- THE OWNER GAINS A CODE.
        owner.write_text("PASS, FAIL, REFUSED, SKIP, DEAD, USAGE = 0, 1, 3, 4, 5, 2\n")
        cases.append(("DRIFT 1: the owner GAINS `2` -- the CHOSEN `2` is now OWNED and must "
                      "STOP being charged", _charged(tree, owner), ["checks/message.py"]))
        # 2 -- THE OWNER RENAMES A VERDICT.  TWO SIDES, because a one-sided plant cannot tell
        # "the grammar followed the owner" from "the prose is declared by anything".
        (tree / "checks" / "prose-one.py").write_text(
            '"""5: DROPPED -- the lane ran and emitted nothing."""\n'
            "import sys\ndef main():\n    return 5\nif __name__ == '__main__':\n    sys.exit(main())\n")
        owner.write_text("PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5\n")
        cases.append(("DRIFT 2a: under a DEAD owner, a prose that says '5: DROPPED' is NOT a "
                      "declaration", _declared_of(tree, owner, "checks/prose-one.py", "5"), "no"))
        owner.write_text("PASS, FAIL, REFUSED, SKIP, DROPPED = 0, 1, 3, 4, 5\n")
        cases.append(("DRIFT 2b: under a DROPPED owner, the SAME prose IS a declaration -- the "
                      "grammar follows the owner",
                      _declared_of(tree, owner, "checks/prose-one.py", "5"), "yes"))
        # 3 -- THE OWNER IS AMBIGUOUS.
        owner.write_text("PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5\n"
                         "GREEN, RED = 0, 1\n")
        cases.append(("DRIFT 3: the owner holds TWO unpacks -- REFUSED, never a guess",
                      _run(tree, owner)[0], 3))
        # 4 -- THE OWNER IS GONE.
        owner.unlink()
        cases.append(("DRIFT 4: the owner is GONE -- REFUSED, never a typed fallback",
                      _run(tree, owner)[0], 3))
        owner.write_text("PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5\n")
        # 5 -- A MESSAGE-EXIT SITE IS CHARGED.
        cases.append(("MESSAGE-EXIT: `sys.exit('a message')` is CHARGED (exit 1)",
                      _run(tree, owner)[0], 1))
        # 6 -- argparse's 2 IS A CONVENTION; A CHOSEN 2 IS NOT.
        cases.append(("CONVENTION: an argparse instrument's `2` is INHERITED and is NOT charged; "
                      "the same `2` in an instrument that does NOT import argparse IS charged",
                      _charged(tree, owner),
                      ["checks/chosen-two.py", "checks/message.py"]))
        # 7 -- AN UNPARSED INSTRUMENT IS REFUSED AND REACHES THE EXIT.
        (tree / "checks" / "broken.py").write_text("def main(:\n")
        cases.append(("UNPARSED: an instrument that cannot be parsed is REFUSED, and the refusal "
                      "REACHES THE EXIT", _run(tree, owner)[0], 3))
        (tree / "checks" / "broken.py").unlink()
        # 8, 9 -- THE LIVE OWNER.  The plants above are all SYNTHETIC, and a synthetic owner
        # cannot catch a drift the real one has ALREADY undergone.  These two read the tree's
        # OWN `gates/gatekit.py`.
        live = Path(root) / "gates" / "gatekit.py" if root else GATEKIT
        cases.append(("LIVE: the tree's own owner is READABLE and the census does not REFUSE it",
                      _live_vocab_ok(live), True))
        cases.append(("LIVE: no code is BOTH in the live vocabulary and in this file's "
                      "CONVENTIONS -- a code the owner names cannot also be 'a convention "
                      "outside the tree'",
                      _live_shadow(live), []))
    fails = 0
    for why, got, want in cases:
        ok = got == want
        fails += not ok
        print(f"[{'   PASS' if ok else '   FAIL'}] {why}\n          got {got}, want {want}")
    print(f"\n=== selftest {'PASS' if not fails else 'FAIL'}: {len(cases)} case(s) run, "
          f"{fails} failed ===")
    return 0 if not fails else 1


def _run(tree, owner):
    """`(exit, rows)` for one run of the census over a synthetic tree."""
    global ROOT, GATEKIT
    saved_root, saved_owner = ROOT, GATEKIT
    ROOT = Path(tree).resolve()
    GATEKIT = Path(owner).resolve()
    try:
        try:
            vocab = vocabulary(GATEKIT)
        except (Refused, SyntaxError) as e:
            return 3, []
        rows, stats = census(vocab, verdict_words(vocab))
        return stats["exit"], rows
    finally:
        ROOT, GATEKIT = saved_root, saved_owner


def _charged(tree, owner):
    """The instruments with a CHARGED finding, sorted."""
    _exit, rows = _run(tree, owner)
    return sorted({r[0] for r in rows if r[2] in ("UNOWNED", "MESSAGE-EXIT")})


def _declared_of(tree, owner, rel, code):
    _exit, rows = _run(tree, owner)
    for r in rows:
        if r[0] == rel and r[1] == code:
            return r[3]
    return None


def _live_vocab_ok(owner):
    """Is the tree's OWN owner readable by this census?  A census that cannot read the owner
    would charge nothing and say nothing, so this must be a hard assertion, not a warning."""
    try:
        vocabulary(owner)
    except (Refused, SyntaxError, OSError):
        return False
    return True


def _live_shadow(owner):
    """The codes that are BOTH in the live vocabulary and in this file's `CONVENTIONS`.

    Empty is the only correct answer: a code the owner NAMES is owned, and a code this file
    calls "a convention outside the tree" is one the owner does not name.  A code in both is
    SHADOWED -- the owner would name it and this file would still call it a convention, which
    is the coupling failing in the one direction a synthetic owner cannot show.
    """
    try:
        vocab = vocabulary(owner)
    except (Refused, SyntaxError, OSError):
        return ["the owner could not be read"]
    return sorted(set(vocab) & set(CONVENTIONS))


if __name__ == "__main__":
    sys.exit(main())
