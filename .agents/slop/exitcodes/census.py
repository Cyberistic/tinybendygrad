#!/usr/bin/env python3
"""census.py -- EXIT CODES OF EVERY INSTRUMENT IN checks/ AND gates/, PARSED NOT RUN.

    .venv/bin/python .agents/slop/exitcodes/census.py

THE POPULATION IS DISCOVERED, NOT LISTED (`AGENTS.md` doctrine 1): `os.walk` over `checks/`
and `gates/`, `filename.endswith(".py")`. No document's list is read, and no instrument is
executed -- importing a gate RUNS it (`gates/gate-surface.py`'s own docstring records
`gates/mixin-op-gate.py` and `gates/beautiful-mnist-gate.py` calling `sys.exit(2)` at module
scope), and a census that runs its population is not a census.

THE VOCABULARY IS LOADED BY PATH, never retyped: `gates/gatekit.py` through
`importlib.util.spec_from_file_location`.

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
import importlib.util
import io
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HOMES = ("checks", "gates")
GATEKIT = ROOT / "gates" / "gatekit.py"
HERE = Path(__file__).resolve().parent
OUT = HERE / "codes.rows"
DEPTH = 14

# A number in one of these shapes is a CODE the prose says something ABOUT. The shapes are
# stated here, in the reader, rather than in a second copy of anybody's prose.
DECLARING = (
    r"\b(?:exit|exits|exit\s+code|return|returns|returned|code|rc|status|verdict|die|dead)"
    r"\w*\s*(?:=|:|is|of|as)?\s*%d\b"
    r"|\b%d\b\s*(?:=|:)\s*(?:is\s+)?(?:REFUSED|SKIP|DEAD|PASS|FAIL|USAGE|VERDICT|GREEN|RED)"
    r"|\b%d\s*[-\u2013]\s*(?:REFUSED|SKIP|DEAD|PASS|FAIL|USAGE)"
    r"|\b(?:REFUSED|SKIP|DEAD|USAGE)\b[^.\n]{0,40}\b%d\b"
)


def vocabulary():
    """`{code: NAME}` from `gates/gatekit.py`, IMPORTED BY PATH -- never retyped here."""
    spec = importlib.util.spec_from_file_location("gk", GATEKIT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return dict(mod.VERDICT)


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
    vocab = vocabulary()
    rows = []
    files = []
    for home in HOMES:
        for dirpath, dirnames, filenames in os.walk(ROOT / home):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            files += [Path(dirpath) / fn for fn in filenames if fn.endswith(".py")]
    files.sort()

    undetermined_files, no_path = [], []
    for p in files:
        rel = str(p.relative_to(ROOT))
        src = p.read_text(errors="replace")
        head = prose(p)
        uses_argparse = bool(re.search(r"^\s*import\s+argparse|^\s*from\s+argparse\s+import",
                                       src, re.M))
        try:
            tree = ast.parse(src)
        except SyntaxError as e:
            rows.append((rel, "?", "UNPARSED", "na", f"REFUSED: SyntaxError: {e.msg} "
                                                      f"at line {e.lineno}"))
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

        # ONE ROW PER (instrument, code). Sites are MERGED, not emitted one row each: the row file
        # is keyed by the pair, and 57 sites of `sys.exit(<message>)` across 24 instruments is 24
        # rows carrying 57 line numbers, not 57 rows of the same fact.
        if msg_sites:
            rows.append((rel, "str", "MESSAGE-EXIT", "na",
                         f"{len(msg_sites)} site(s) hand a NON-INT to the exit: "
                         + "; ".join(f"line {l} {k}" for l, k in msg_sites)
                         + ". CPython prints it to stderr and exits 1, so to `$?` every one of "
                           "them IS FAIL, whatever the text says -- the token is the only witness"))
        if nondet:
            undetermined_files.append(rel)
            rows.append((rel, "?", "UNDETERMINED", "na",
                         f"{len(nondet)} site(s) whose code is computed at runtime or delegated: "
                         + "; ".join(f"line {l} {d}" for l, d in nondet)
                         + ". REFUSED, not guessed"))
        for code in sorted(direct):
            lines, forms = direct[code]
            nt = (f"{'/'.join(sorted(forms))} at line{'s' if len(lines) > 1 else ''} "
                  f"{','.join(str(l) for l in lines)}")
            if uses_argparse and code == 2:
                nt += "; the file uses argparse, so 2 is USAGE here"
            rows.append((rel, str(code), "UNOWNED" if code not in vocab else vocab[code],
                         declared(head, code), nt))
        if not direct and not nondet and not msg_sites:
            no_path.append(rel)
            rows.append((rel, "-", "NO-EXIT-PATH", "na",
                         "no sys.exit/exit/SystemExit anywhere: a MODULE, not an entry point"))

    w = io.StringIO()
    w.write("instrument\tcode\tverdict\tdeclared_in_own_prose\tnote\n")
    for r in rows:
        w.write("\t".join(str(x) for x in r) + "\n")
    OUT.write_text(w.getvalue())

    codes = sorted({int(r[1]) for r in rows if r[1].isdigit()})
    unowned = [r for r in rows if r[2] == "UNOWNED"]
    undet = sorted({r[0] for r in rows if r[2] == "UNDETERMINED"})
    print(f"population   {len(files)} .py under {'/'.join(HOMES)}/ (os.walk + endswith('.py'))")
    print(f"rows         {len(rows)}")
    print(f"distinct     {len(codes)} exit codes: {codes}")
    print(f"UNOWNED      {len(unowned)} rows over {len({r[0] for r in unowned})} files")
    print(f"UNDETERMINED {len(undet)} files")
    print(f"NO-EXIT-PATH {len(no_path)} files")
    print(f"wrote        {OUT.relative_to(ROOT)}")


def declared(head, code):
    """`yes` if the instrument's own PROSE says something ABOUT THIS NUMBER.

    A LEXICAL TEST, NAMED AS ONE, and the LOWER BOUND of declaration: a row read `no` may still
    have its meaning stated in a shape this does not know, and a row read `yes` may be counting
    rows or bytes. The report carries this class's size AND the hand-read adjudication of the
    UNOWNED and UNDECLARED classes, and the difference between them is itself reported.
    """
    return "yes" if re.search(DECLARING % ((code,) * 4), head) else "no"


if __name__ == "__main__":
    main()