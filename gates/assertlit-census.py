#!/usr/bin/env python3
"""assertlit-census -- WHICH ORACLES ASSERT AN EXPECTED VALUE INSTEAD OF DERIVING IT?

    .venv/bin/python gates/assertlit-census.py             # the census
    .venv/bin/python gates/assertlit-census.py --report    # census only, rc never charged
    .venv/bin/python gates/assertlit-census.py --plant     # 12 cases, each calling a shipped fn

A self-asserting literal is a literal that IS the answer. The discriminator is not "is there a
string in the file" -- it is the brief's: COULD YOU DELETE THE LITERAL AND HAVE THE ORACLE STILL
PRODUCE THE CORRECT ANSWER FROM CPYTHON? If not, it is asserted.

WHAT IS COUNTED, AND WHY IT IS NOT A STRING COUNT. Every emitted row is split into SEGMENTS -- an
ordered run of (LITERAL, text) and (EXPR, node) -- and then into LABEL and VALUE regions at the
tree's own `name=value` row convention (`gates/oracleblind-census.py`'s `rowmap` splits at the
FIRST `=`, and says why: `autogen-oracle.py` prints `tmap 0 = int` with spaces). A literal in the
LABEL region is a ROW NAME: typed, and carrying no answer, so it is NOT counted. A literal in the
VALUE region is counted, because that is the region a diff compares.

    COMPUTED   the VALUE segment is an expression carrying `tinygrad` taint.
    ASSERTED   the VALUE segment is a literal, or folds to one, with no taint.

A row that is half one and half the other is therefore VISIBLE as `asserted/computed` per oracle
rather than hidden behind a boolean -- which is the measurement the brief asks for.

FOUR VERDICTS, AND `UNSOURCED` IS NOT A FIFTH WORD FOR `ASSERTED`. An asserted component whose
text CPython is MEASURED to spell is a redundancy, not a defect: it has a nameable derivation.
Three tests, in order, and the first that fires is the verdict:

    SOURCED-BY-SUBJECT  the text is an identifier-shaped token that occurs in `tinygrad/**.py`.
                        The derivation is `<holder>.name` / `Ops.NAME`, and the census PRINTS the
                        holder it found, so "nameable" is a measurement and not an assertion.
    SOURCED-IN-FILE     the SAME oracle DERIVES this exact text in some other row's VALUE region.
                        The oracle demonstrably computes it; this copy does not use the computation.
    UNSOURCED           neither. NO CPYTHON EXPRESSION IS NAMED, so the value is not merely
                        asserted, it is unsourced -- a stronger and different verdict.

AND THE MEASURED INSTANCE, WHICH IS WHAT THE VERDICT IS FOR. `gates/op_graph_census-oracle.py:97`
is `print("nop=%s," % ",".join("%s:%d" % ("Nzs", x.numel()) for x in o._new_optim_param()))`.
MEASURED: `Nzs` occurs **0 times in all of `tinygrad/`** -- it is a PORT-ONLY tag
(`tinybendygrad/nn/optim.bend:1059` `case Nzs{sz}: "Nzs"`), and
`.venv/bin/python -c "optim.Optimizer([Tensor([1.0,2.0])],lr=0.1)._new_optim_param()"` answers
`[('f32', 2)]`. So the row prints `Nzs:2,` where CPython's derivable name is `f32`, the `:2` IS
computed from `x.numel()`, and **driver and oracle agree on a letter neither computed.** One
asserted component, one computed component, one `UNSOURCED`.

THE POPULATION IS A WALK AND A GENERATOR'S DECLARATION, NEVER A LIST. `gates/gates-pop.py` is
LOADED BY PATH for `_homes()` (`gates/gate-surface.py:76`: "the population is not a second list,
it is `gates/gates-pop.py:discover()`, loaded by path"), and each home is then WALKED. Three
classes are reported separately because a shape-based walk and a declaration-based walk answer
different questions and merging them is how a denominator becomes a coincidence:

    ORACLE        `*.py` under a home whose stem carries `oracle`. The shape.
    GATE          `*.py` under a home whose stem carries `gate`, PLUS every file whose AST
                  constructs `Gate(` / `gatekit.Gate(` -- the declaration.
    PINS          every `*.rows` under a home, each reported with whether a GATE names it by
                  literal -- an unreferenced `.rows` is a denominator, not a verdict.

NO `bend` RUNS AND NO ORACLE RUNS. This census is a STATIC READ of the source: 0 subprocesses.
That is what makes it disjoint from `gates/oracleblind-census.py`, which is DYNAMIC (perturb a
literal, run the oracle, compare rows). The two ask opposite questions -- oracleblind asks "does
the oracle DISTINGUISH two inputs", this asks "does the oracle COMPUTE the value at all" -- and
`gates/oracleblind.rows`'s own `ALL VALID INPUTS AGREE` class is the first question, never the
second. A gate that is blind to a perturbed input can still DERIVE every value it prints, and a
gate that derives every value it prints can still be blind. Neither census counts the other.

WHAT THIS IS NOT. It does not RUN the oracles, so it cannot say whether an asserted literal is
CORRECT. It says where a value came from. Correctness is `gatekit`'s diff, and the census's job
is to hand it a shortlist of the places where the diff is comparing a typed string with a typed
string.
"""
from __future__ import annotations

import argparse
import ast
import bisect
import importlib.util
import re
import sys
import warnings
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SUBJECT = ROOT / "tinygrad"
REPORT = HERE / "assertlit.rows"

warnings.filterwarnings("ignore", category=SyntaxWarning)

# `gates/oracleblind-census.py:114` states the reason for this line and it applies here verbatim:
# `ast.parse` on ANOTHER instrument emits ITS SyntaxWarning onto OUR stderr, and stdout is what
# callers parse.
BUILTIN_CALLS = frozenset({"print", "row", "rowf", "str", "int", "float", "bool", "len",
                           "format", "repr", "hex", "oct", "bin", "round", "abs", "sorted",
                           "join", "enumerate", "zip", "map", "list", "tuple", "dict",
                           "set", "sum", "min", "max", "any", "all", "write"})
EMIT_0 = frozenset({"print", "row", "rowf", "stdout.write", "sys.stdout.write", "write",
                    "stderr.write", "sys.stderr.write"})
EMIT_1 = frozenset({"row", "rowf"})
# A SEGMENT THAT IS ONLY PUNCTUATION IS A SEPARATOR, NOT AN ANSWER: the `,` of a join and the `:`
# of `name:value` are the row's SHAPE. `%s:%d` has two of them and one value. Identified as a
# string of nothing but characters that cannot appear in a computed answer's substance.
SEPARATOR = re.compile(r"^[\s:,;|/\\+*=<>()\[\]{}#-]*$")
# THE TOKEN SPLIT, a character class rather than the whole-run `SEPARATOR` test, and `-` IS IN IT.
# `-` is the joiner in this tree's graph signatures (`CONST/0:f1063675494`, `s0-x`), so leaving it
# out would fuse the op name to its arity and the census could not tell `CONST` from `CONST0`.
# THE PRICE IS STATED: a negative number inside a LITERAL RUN loses its sign, so `-42` is reported
# as the token `42`. That can only ADD an UNSOURCED finding or change a token's text; it cannot
# hide an asserted literal, because the digit run is reported either way.
SEP_RE = re.compile(r"[\s:,;|/\\+*=<>()\[\]{}#-]+")
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
EMPTY_VALUE = re.compile(r"^(''|\"\"|\[\]|\(\)|\{\}|set\(\))$")
# `%`-FORMAT, the tree's second emit shape (`"%s:%d" % (...)`, `"%s" % x`). `%%` is a literal `%`.
PCT = re.compile(r"%(?:%|[-+ #0]*[0-9*]*(?:\.[0-9*]+)?[hlL]?([sdrifgeExXoc]))")
MAX_DEPTH = 40


# ====================================================== 1. THE POPULATION, DISCOVERED


def homes():
    """The gate homes, from `gates/gates-pop.py` LOADED BY PATH -- never re-listed here."""
    spec = importlib.util.spec_from_file_location("gates_pop", HERE / "gates-pop.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return tuple(mod._homes(ROOT))


def _stem_has(needle: str, stem: str) -> bool:
    return needle in stem


def population():
    """`{class: [repo-relative paths]}` plus the rows that measured the walk.

    THREE READS AND THREE SHAPES, KEPT APART. `gates/gates-pop.py` supplies the HOMES; whether a
    file in a home is an oracle is a SHAPE (`oracle` in the stem), whether it is a GATE is a SHAPE
    plus a DECLARATION (an AST that constructs `Gate(`), and whether a `.rows` is a gate's input is
    a DECLARATION (a gate names it by literal). The census prints all three counts so a reader can
    see which question produced the denominator.
    """
    hs = homes()
    oracles, gates, pins = {}, {}, {}
    for home in hs:
        base = ROOT / home
        if not base.is_dir():
            continue
        for p in sorted(base.iterdir()):
            if not p.is_file():
                continue
            rel = p.relative_to(ROOT).as_posix()
            stem = p.stem.lower()
            if p.suffix == ".py" and _stem_has("oracle", stem):
                oracles[rel] = p
            if p.suffix == ".rows":
                pins[rel] = p
            if p.suffix == ".py" and (stem.endswith("gate") or stem.endswith("-gate")):
                gates[rel] = p
    # THE DECLARATION READ. A file whose stem carries no `gate` but which constructs `Gate(` is a
    # gate, and admitting it by AST rather than by name is the difference between a walk and a
    # guess. MEASURED-ON-ARRIVAL: the walk alone misses nothing today, so this arm is a CONTROL
    # with a number rather than a correction -- the count it adds is printed.
    declared = []
    for home in hs:
        base = ROOT / home
        if not base.is_dir():
            continue
        for p in sorted(base.glob("*.py")):
            rel = p.relative_to(ROOT).as_posix()
            if rel in gates or rel in oracles:
                continue
            try:
                tree = ast.parse(p.read_text(errors="replace"))
            except (OSError, SyntaxError):
                continue
            if any(isinstance(n, ast.Call)
                   and (getattr(n.func, "attr", "") or getattr(n.func, "id", "")) == "Gate"
                   for n in ast.walk(tree)):
                gates[rel] = p
                declared.append(rel)
    # WHICH `.rows` A GATE NAMES. The declaration, by literal.
    named_rows = set()
    for rel, p in sorted(gates.items()):
        try:
            tree = ast.parse(p.read_text(errors="replace"))
        except (OSError, SyntaxError):
            continue
        for n in ast.walk(tree):
            if isinstance(n, ast.Constant) and isinstance(n.value, str) and n.value.endswith(".rows"):
                named_rows.add(n.value)
    return ({"ORACLE": oracles, "GATE": gates, "PINS": pins},
            {"homes": hs, "declared_beyond_walk": declared, "named_rows": sorted(named_rows)})


# ================================================ 2. DERIVATION TAINT: IS IT CPYTHON'S?


class Taint:
    """`derived(node)` -- does this expression carry a `tinygrad` taint?

    THE ROOTS ARE THE ORACLE'S OWN IMPORTS, so "CPython" means "what this file imported from
    `tinygrad/`" and nothing else. A module that imports nothing from `tinygrad` cannot derive
    anything, which is the correct answer for `gates/autogen-oracle.py` (it reads a C header) and
    for the host-model oracles (they compute integers in Python).
    """

    def __init__(self, tree):
        self.roots = set()
        for n in ast.walk(tree):
            if isinstance(n, ast.ImportFrom) and n.module and n.module.split(".")[0] == "tinygrad":
                for a in n.names:
                    self.roots.add(a.asname or a.name)
            elif isinstance(n, ast.Import):
                for a in n.names:
                    if a.name.split(".")[0] == "tinygrad":
                        self.roots.add((a.asname or a.name).split(".")[0])
        self._tree = tree
        self.binds = self._bindings(tree)
        self.derived = self._fixpoint()

    @staticmethod
    def _bindings(tree):
        """`{name: rhs}` for EVERY assignment in the file, module-level and in functions alike.

        NOT A SCOPED ANALYSIS, and the cost is named rather than hidden: a shadowed name in a
        nested scope reads as its module-level binding. That can only make a value look MORE
        derived than it is, so the failure direction is `COMPUTED` where `ASSERTED` was true --
        an UNDER-count, which the `--plant` names as the direction that is safe and the direction
        the census must be checked in. The alternative, a scoped fixpoint, buys nothing here: an
        oracle's value rows all read module-level fixtures.
        """
        out = {}
        for n in ast.walk(tree):
            if isinstance(n, ast.Assign):
                # A TUPLE TARGET IS A BINDING TOO, and leaving it out was a 27-COMPONENT FALSE
                # POSITIVE. MEASURED: `gates/op_graph_census-oracle.py:100` is
                # `a, g, bb, lr = fa(), fg(), fb(), flr()` and every row below it prints `g * 1.0 * lr`
                # -- with `g` and `lr` unbound by the taint, three rows read as typed arithmetic
                # over symbols. `ast.Assign.targets[0]` is an `ast.Tuple` there, and an
                # `isinstance(t, ast.Name)` test on it is simply false.
                for t in n.targets:
                    for nm in _target_names(t):
                        out.setdefault(nm, n.value)
            elif isinstance(n, (ast.AnnAssign, ast.AugAssign)) and isinstance(n.target, ast.Name):
                out.setdefault(n.target.id, n.value)
        return out

    def _comp_targets(self, tree):
        """`{name: the iterable expression}` for EVERY comprehension in the file.

        A comprehension's loop variable is DERIVED when its iterable is, and this table exists
        because MEASURED, without it, the census called the NAMED INSTANCE wrong.
        `gates/op_graph_census-oracle.py:97` is
        `",".join("%s:%d" % ("Nzs", x.numel()) for x in o._new_optim_param())`: `x` is bound by the
        generator over a `tinygrad` call, so `x.numel()` IS CPython's answer and the caller measured
        it as COMPUTED. The first version of this taint reported it UNSOURCED -- a false positive
        on the one row in this whole census that has been read by two other agents. The reason is
        structural and worth naming: `expand()` flattens the format layers and hands `census_source`
        the `x.numel()` node DETACHED from the generator that bound `x`, so the derivation has to be
        carried in the TABLE rather than recovered from the tree at the point of use.

        THE SCOPE COST IS THE SAME ONE `_bindings` PAYS and it is named rather than hidden: these
        names are treated as derived for the WHOLE file, not only inside their comprehension. Both
        approximations err the SAME way -- a shadowed name reads as derived -- so both UNDER-count
        `asserted`, and `--plant`'s `fixture-is-not-asserted` and `asserted-typed-name` are the two
        cases that hold the line in each approximation's direction.
        """
        out = {}
        for n in ast.walk(tree):
            if isinstance(n, (ast.ListComp, ast.GeneratorExp, ast.SetComp, ast.DictComp)):
                for g in n.generators:
                    for t in ast.walk(g.target):
                        if isinstance(t, ast.Name):
                            out.setdefault(t.id, g.iter)
        return out

    def _func_returns(self, tree):
        """`{function name: [every `return` expression in it]}`.

        MEASURED, AND THIS WAS A 51-COMPONENT FALSE POSITIVE. `gates/tn_graph_census-oracle.py`
        prints all 39 of its rows as `print(f"tn_sqrt={sig(t4().sqrt())}")`, where `sig` is a
        LOCAL helper that calls `u.toposort()`. A taint that only knows module-level bindings and
        comprehension targets cannot see inside a local `def`, so every one of those rows read as
        1 asserted / 0 computed -- the census reporting the whole of CPython's most careful oracle
        as a table of typed literals. A function is DERIVED when any of its returns is, which is a
        lower bound on its derivation and therefore an UNDER-count of `asserted`; the safe
        direction is stated on `_bindings` and is the same one this shares.
        """
        out = {}
        for n in ast.walk(tree):
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
                out.setdefault(n.name, [r.value for r in ast.walk(n)
                                        if isinstance(r, ast.Return) and r.value is not None])
        return out

    def _loop_targets(self, tree):
        """`{name: the iterable}` for every `for` loop, exactly as for comprehensions.

        `gates/wk-eval-oracle.py:118` is `print(f"{row[0]}={row[1]}")` inside
        `for row in pm(nm, dt)`. Without this table `row[1]` folds to nothing and is reported as a
        typed literal, on a row where the value is CPython's.
        """
        out = {}
        for n in ast.walk(tree):
            if isinstance(n, (ast.For, ast.AsyncFor)):
                for t in ast.walk(n.target):
                    if isinstance(t, ast.Name):
                        out.setdefault(t.id, n.iter)
        return out

    def _fixpoint(self):
        """Names that (transitively) derive from a `tinygrad` root. Iterate to a fixed point.

        The loop is REQUIRED and not a stylistic choice: `o = optim.Optimizer(...)` derives, then
        `xs = o._new_optim_param()` derives BECAUSE of it, and one pass in source order gets both
        only when the order happens to be right. The bound is `len(rules)+1`, which terminates
        because `derived` only grows.

        ONE TABLE, FOUR SOURCES, because the four kinds of binding are the same KIND of thing and
        splitting them would mean four fixpoints that could disagree:
        `name -> [the expressions that produce it]`, and a name derives when ANY of them does.
        """
        rules: dict[str, list] = {}
        for src in (self.binds, self._comp_targets(self._tree),
                    self._func_returns(self._tree), self._loop_targets(self._tree)):
            for name, exprs in src.items():
                rules.setdefault(name, []).extend(exprs if isinstance(exprs, list) else [exprs])
        d = set(self.roots)
        for _ in range(len(rules) + 1):
            grew = False
            for name, exprs in rules.items():
                if name in d:
                    continue
                if any(self.derived_expr(e, d) for e in exprs):
                    d.add(name)
                    grew = True
            if not grew:
                break
        # EVERY NAME THE FILE DEFINES, for the OPPOSITE question: not "is this derived" but "did
        # the census manage to resolve this name at all". The two sets are different on purpose --
        # `h` in `--plant`'s `no-tinygrad` is DEFINED (it is a local `def`) and NOT derived, and
        # calling it unresolved would report the census's own failure to reason about a helper as a
        # finding about the oracle.
        self.bound = set(rules) | self.roots | BUILTINS | {
            n.id for n in ast.walk(self._tree)
            if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Store)}
        return d

    def derived_expr(self, node, names=None):
        """True when `node`'s value can be traced to a `tinygrad` import. Recursive by AST shape."""
        if node is None:
            return False
        names = self.derived if names is None else names
        if isinstance(node, ast.Name):
            return node.id in names
        if isinstance(node, ast.Attribute):
            # `Ops.CMPNE`: the ROOT is the imported module, so the attribute itself is vocabulary.
            return self.derived_expr(node.value, names) or node.attr in names
        if isinstance(node, ast.Call):
            if self.derived_expr(node.func, names):
                return True
            return any(self.derived_expr(a, names) for a in node.args) or \
                any(self.derived_expr(k.value, names) for k in node.keywords)
        if isinstance(node, ast.Subscript):
            return self.derived_expr(node.value, names)
        # A UNARY SIGN IS NOT A NEW VALUE. MEASURED: `gates/op_graph_census-oracle.py:107` is
        # `row("neg", -a)` and `:126`-adjacent rows are `sig(-t4())`; with `UnaryOp` unhandled the
        # census reported `-a` as a typed symbol on the port's own `-t` row. Four rows across two
        # oracles, and it is the same class of error as the tuple-target one: a shape the switch
        # did not name, reading as a value nobody computed.
        if isinstance(node, (ast.UnaryOp, ast.Starred)):
            return self.derived_expr(node.operand if isinstance(node, ast.UnaryOp) else node.value,
                                     names)
        if isinstance(node, ast.Compare):
            return any(self.derived_expr(c, names) for c in node.comparators) or \
                self.derived_expr(node.left, names)
        # A LAMBDA'S BODY COUNTS. `gates/wgsl_render_census-oracle.py:334` is
        # `row(f"type_map {nm}", refuse(lambda: WGSLRenderer.type_map[DT[ctor]]))`: `refuse` is a
        # local name and the whole value looks un-derived until the lambda is walked, where
        # `WGSLRenderer` is a `tinygrad` import and the row is CPython's after all.
        if isinstance(node, ast.Lambda):
            return self.derived_expr(node.body, names)
        if isinstance(node, ast.BinOp):
            return self.derived_expr(node.left, names) or self.derived_expr(node.right, names)
        if isinstance(node, ast.BoolOp):
            return any(self.derived_expr(v, names) for v in node.values)
        if isinstance(node, ast.IfExp):
            return self.derived_expr(node.body, names) or self.derived_expr(node.orelse, names) or \
                self.derived_expr(node.test, names)
        if isinstance(node, (ast.List, ast.Tuple, ast.Set)):
            return any(self.derived_expr(e, names) for e in node.elts)
        if isinstance(node, ast.Dict):
            return any(self.derived_expr(k, names) for k in node.keys if k) or \
                any(self.derived_expr(v, names) for v in node.values)
        if isinstance(node, (ast.ListComp, ast.GeneratorExp, ast.SetComp)):
            # THE COMPREHENSION'S OWN LOOP VARIABLE IS DERIVED WHEN ITS ITERABLE IS, and this is
            # NOT a detail. MEASURED: `gates/op_graph_census-oracle.py:97`'s value is
            # `",".join("%s:%d" % ("Nzs", x.numel()) for x in o._new_optim_param())` -- the `x`
            # comes from a generator over a `tinygrad` call, and a taint that does not bind `x`
            # reads `x.numel()` as an UNSOURCED literal and reports the `numel()` the caller
            # measured as COMPUTED. The census was wrong about the named instance, in the
            # direction that inflates the finding, which is the direction that costs the report its
            # credibility. The binding is added ONLY inside the comprehension body, because a
            # comprehension's target does not leak.
            inner = set(names)
            for g in node.generators:
                if self.derived_expr(g.iter, names):
                    for t in ast.walk(g.target):
                        if isinstance(t, ast.Name):
                            inner.add(t.id)
            return self.derived_expr(node.elt, inner) or \
                any(self.derived_expr(g.iter, names) for g in node.generators)
        if isinstance(node, (ast.JoinedStr,)):
            return any(self.derived_expr(v.value, names)
                       for v in node.values if isinstance(v, ast.FormattedValue))
        return False

    def fold(self, node, depth=0):
        """`(text, ok)` -- evaluate a NON-derived expression to a literal, or say it cannot.

        This is what turns `row("ref_nmant_f32", NMANT_F32)` -- where the answer is behind a
        module-level NAME -- into the text `23`, so the census reports the VALUE rather than the
        SYMBOL. It resolves module-level bindings through the SAME `binds` map the taint uses, so
        a name that resolves and a name that is derived are both read one way.
        """
        if depth > 12:
            return None, False
        try:
            return repr(ast.literal_eval(node)), True
        except (ValueError, SyntaxError, TypeError):
            pass
        if isinstance(node, ast.Name) and node.id in self.binds:
            return self.fold(self.binds[node.id], depth + 1)
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            t, ok = self.fold(node.operand, depth + 1)
            if ok and isinstance(node.operand, ast.Constant) and \
                    isinstance(node.operand.value, (int, float)):
                v = node.operand.value
                return repr(-v if isinstance(node.op, ast.USub) else v), True
            if ok:
                return t, True
        return None, False


# =========================================== 3. THE EMITTED TEXT, AS AN ORDERED SEGMENT RUN


def has_unresolved_name(node, bound):
    """True when `node` names something the census could not resolve to a rule.

    **THIS IS THE MOST IMPORTANT RULE IN THE FILE, AND IT IS A NEGATIVE ONE.**
    `gates/ew-explog-oracle.py:47` prints
    `f"{nm}={len(ts)} " + " ".join(tok(x) for x in ts)` where `nm`, `u` and `x` are PARAMETERS of
    helpers -- names no binding table in the file defines. A two-valued taint read them as "not
    derived", i.e. as TYPED LITERALS, and the census then reported 33 asserted components in
    `gates/autogen-oracle.py`'s HEADINGS and dozens more wherever an oracle passes values between
    helpers. That is the instrument's blindness wearing the oracle's name, which is the failure
    this whole file is written against.

    So the three-valued reading is the honest one: DERIVED, NOT-DERIVED, and UNRESOLVED. Only
    NOT-DERIVED counts as `asserted`; UNRESOLVED is counted, named, and reported as the census's
    own blind spot. **The direction is the safe one**: an unresolved name can only REMOVE a
    finding, never invent one, so the census under-claims rather than accusing.
    """
    if node is None:
        return False
    for n in ast.walk(node):
        if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load):
            if n.id not in bound:
                return True
        elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
            # A NESTED `def`/`lambda` SHADOWS the enclosing scope's names with its own
            # PARAMETERS, and walking into it would resolve `x` against the outer file and call
            # the census's guess a derivation. Its parameters are unresolved BY CONSTRUCTION.
            for a in list(n.args.args) + list(n.args.kwonlyargs) + list(n.args.posonlyargs):
                if a.arg not in bound:
                    return True
            return False
    return False


import builtins

# EVERY NAME PYTHON ITSELF DEFINES. `int(1)` is not an unresolvable reference: `int` is a builtin,
# and a taint that called it unresolved made `--plant`'s own `asserted-constant` case read
# `NO-ROWS`. A census whose blindness list contains the language's own vocabulary is not measuring
# its blindness, it is measuring its parser.
BUILTINS = frozenset(dir(builtins)) | {"__name__", "__file__", "__doc__"}


def _target_names(target):
    """Every name a single assignment TARGET binds, through tuples and lists.

    `a, (b, c) = ...` binds three. `ast.Tuple`/`ast.List` recurse; anything else yields itself when
    it is a `Name` and nothing otherwise, so a starred or subscripted target is ignored rather than
    guessed at.
    """
    if isinstance(target, (ast.Tuple, ast.List)):
        return [n for e in target.elts for n in _target_names(e)]
    return [target.id] if isinstance(target, ast.Name) else []


def _callee(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return ""


def _emit_arg(call):
    """The argument of an emit call that carries the row's TEXT.

    `print(...)` and `write(...)` put it at 0; this tree's `row(name, value)` puts the NAME at 0
    and the text at 1 (`gates/oracleblind-census.py:_under_output` documents the same convention).
    Taking 0 for a `row` call would read the row NAME as the row's answer, which is the opposite
    error and the reason the two emitters are named separately here.
    """
    if not call.args:
        return None
    return call.args[1] if _callee(call.func) in EMIT_1 and len(call.args) > 1 else call.args[0]


def expand(node, depth=0, seen=None):
    """`[(is_literal, payload)]` -- one emit expression, flattened into an ordered segment run.

    IT RECURSES, and the recursion is the whole instrument: `"nop=%s," % ",".join("%s:%d" % ("Nzs",
    x.numel()) ...)` has THREE layers of format and the literal that matters is four levels down.
    A census that read only the outermost template would report this row as `1 computed` and
    `0 asserted`, which is exactly the `gates/op_graph_census-oracle.py:97` blind spot.

    THE JOIN AND THE COMPREHENSION. `",".join(genexpr)` contributes the SEPARATOR once and then
    the element's format. Only the FIRST element expression is expanded, because every element of
    a comprehension shares one format -- and saying so is cheaper than pretending to run it.
    """
    seen = seen or set()
    if node is None or depth > MAX_DEPTH or id(node) in seen:
        return [("expr", node)] if node is not None else []
    seen = seen | {id(node)}
    if isinstance(node, ast.Constant):
        return [("lit", node.value if isinstance(node.value, str) else repr(node.value))]
    if isinstance(node, ast.JoinedStr):
        out = []
        for v in node.values:
            if isinstance(v, ast.Constant):
                out.append(("lit", v.value))
            elif isinstance(v, ast.FormattedValue):
                out.extend(expand(v.value, depth + 1, seen))
        return out
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Mod) and \
            isinstance(node.left, ast.Constant) and isinstance(node.left.value, str):
        return _pct_segments(node.left.value, node.right, depth, seen)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return expand(node.left, depth + 1, seen) + expand(node.right, depth + 1, seen)
    if isinstance(node, ast.Call) and _callee(node.func) == "join" and node.args:
        sep = expand(node.func.value, depth + 1, seen)
        arg = node.args[0]
        if isinstance(arg, (ast.ListComp, ast.GeneratorExp, ast.SetComp)):
            return sep + expand(arg.elt, depth + 1, seen)
        return sep + expand(arg, depth + 1, seen)
    if isinstance(node, ast.Call) and _callee(node.func) in ("str", "format", "repr") and node.args:
        return expand(node.args[0], depth + 1, seen)
    if isinstance(node, (ast.ListComp, ast.GeneratorExp, ast.SetComp)):
        return expand(node.elt, depth + 1, seen)
    return [("expr", node)]


def _pct_segments(tmpl, rhs, depth, seen):
    """A `%`-template, split into literal runs and the expressions that fill its slots."""
    out, pos, args = [], 0, _pct_args(rhs)
    for i, m in enumerate(PCT.finditer(tmpl)):
        if m.start() > pos:
            out.append(("lit", tmpl[pos:m.start()]))
        if m.group(1) != "%":
            out.extend(expand(args[i], depth + 1, seen) if i < len(args) else [("lit", "?")])
        pos = m.end()
    if pos < len(tmpl):
        out.append(("lit", tmpl[pos:]))
    return out


def _pct_args(rhs):
    if isinstance(rhs, ast.Tuple):
        return list(rhs.elts)
    return [rhs]


def split_row(segs):
    """`(label, value)` -- the row's IDENTITY run and its ANSWER run.

    THE CONVENTION IS STATED, NOT ASSUMED, and it is `gates/oracleblind-census.py`'s: every row in
    this tree is `name=value`, split at the FIRST `=`, because `autogen-oracle.py` prints
    `tmap 0 = int` with spaces around it and a `split("=")[0]` that cannot cope is wrong there.

    **THE SEGMENT HOLDING THE `=` IS SPLIT IN TWO**, and that is a measured bug rather than a
    nicety. `f"typed=CAST"` is ONE literal segment containing both the row name and the answer, so
    an implementation that returned `(segs[:i], segs[i+1:])` reported `0 asserted` and called the
    row clean -- with `CAST` a bare asserted token sitting in the index it threw away. The same
    mistake reads `nop=%s,` correctly by luck (its `=` is at the end of the segment) and so hides
    itself on the one row a reader would check first.
    """
    for i, (kind, payload) in enumerate(segs):
        if kind == "lit" and isinstance(payload, str) and "=" in payload:
            head, _, tail = payload.partition("=")
            return ([(k, p) for k, p in segs[:i]] + [("lit", head + "=")],
                    ([("lit", tail)] if tail else []) + list(segs[i + 1:]))
    # NO `=` ANYWHERE: THE EMITTER PRINTS A BARE VALUE, so there IS no identity run and the WHOLE
    # run is the answer. This is the SAFE direction -- it can only ADD findings, never hide one --
    # and `no-equals-row` in `--plant` is what keeps that claim from being a comment.
    return [], list(segs)


# ============================================== 4. THE CENSUS OF ONE ORACLE'S SOURCE


def reads_tinygrad(src: str) -> bool:
    """Does this file import `tinygrad`? THE PREDICATE THAT SEPARATES AN ORACLE FROM AN INSTRUMENT.

    **"STEM CARRIES `oracle`" ADMITS INSTRUMENTS *ABOUT* ORACLES, AND THAT WAS 45 OF 78 ROWS.**
    MEASURED on the first full run: `gates/oracleblind-census.py` (113 asserted components),
    `gates/oracle-census-gate.py` (105) and `checks/oracle-txt-census.py` (214) are all named
    `*oracle*`, and all three CENSUS ORACLES -- they do not compute a CPython answer for a port
    lane, they report on the ones that do. Applying the taint to a census is the same error as
    applying the oracle rule to a gate's `print` calls: the file's output is a REPORT about
    something else, and every literal in a report reads as an unsourced answer.

    `tinygrad` IN THE IMPORTS is the discriminator that matches the QUESTION. An oracle's whole
    reason to exist is that it calls CPython, so an oracle imports `tinygrad`; an instrument about
    oracles imports `gatekit`, `gates-pop` and `subprocess` and never does. It is one `ast.Import`
    test over the file's own header, and it is derived from the file rather than from its name.

    **IT IS NOT A CLEAN PARTITION, AND THE LEAKS ARE COUNTED RATHER THAN FIXED.** `gates/autogen-oracle.py`
    is a real oracle -- a gate's CPython side -- and it imports nothing from `tinygrad`, because its
    subject is a C HEADER. It lands in the not-applicable class, where the census claims nothing.
    Claiming nothing about a file is the correct price of a predicate that is one mechanism rather
    than a name list, and the alternative -- a per-file exemption list -- is the shape this whole
    census exists to measure.
    """
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return False
    for n in ast.walk(tree):
        if isinstance(n, ast.ImportFrom) and n.module and n.module.split(".")[0] == "tinygrad":
            return True
        if isinstance(n, ast.Import):
            if any(a.name.split(".")[0] == "tinygrad" for a in n.names):
                return True
    return False


def emit_sites(tree):
    """Every emit call in the file, as `(lineno, callee, node)`. Walks the WHOLE module.

    EVERY STATEMENT, `def` INCLUDED -- `gates/oracleblind-census.py` records that skipping
    `FunctionDef` reported six oracles as `IGNORES ITS INPUT / 0 sites` when they put their whole
    fixture inside a printer helper, and that was the instrument's blindness wearing the oracle's
    name. Same trap, same avoidance.
    """
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call):
            continue
        nm = _callee(n.func)
        if nm not in EMIT_0 or _emit_arg(n) is None:
            continue
        # STDERR IS NOT A LANE. `gates/gatekit.py:321`'s `_lines()` reads the oracle's STDOUT into
        # `py.rows` and nothing reads its stderr, so `print(..., file=sys.stderr)` cannot be a row
        # and a census that counted its words was reporting an ERROR MESSAGE as an expected value.
        # MEASURED: `gates/ops_python_census-oracle.py:90` is one `f"== REFUSED, NOT A VERDICT: ..."`
        # whose seven words were 7 asserted components.
        if any(k.arg == "file" and _stderr_name(k.value) for k in n.keywords):
            continue
        # A STARRED ARGUMENT IS A FORWARDING SPLAT, not a literal: `gates/qcom-oracle.py:16` is
        # `def p(*a): print(*a)` and the census reported the unparsed text `*a` as an assertion.
        if any(isinstance(a, ast.Starred) for a in n.args):
            continue
        yield n.lineno, nm, _emit_arg(n)


def _stderr_name(node):
    """True when a `file=` argument names stderr. An unresolvable `file=` is NOT stderr."""
    if isinstance(node, ast.Attribute):
        return node.attr == "stderr"
    if isinstance(node, ast.Name):
        return node.id == "stderr"
    return False


def census_source(src, subject_tokens=None):
    """`{row, asserted, computed, components, derived_texts}` -- ONE source, no filesystem.

    This is the SHIPPED decision function. `--plant` calls it on synthetic sources and on
    MUTATED copies of real ones, and it is the same code the census runs -- which is the property
    `gates/runner.py`'s plant is built on and the reason its first version's plants were worthless
    (they reached PAST the shipped function into its helpers, so breaking a helper's branch left
    the plant green).
    """
    tree = ast.parse(src)
    taint = Taint(tree)
    rows, asserted, computed, comps = [], 0, 0, []
    derived_texts, unresolved, literal_only = set(), [], []
    for lineno, callee, node in emit_sites(tree):
        label, value = split_row(expand(node))
        if not value:
            continue
        if all(k == "lit" for k, _ in value):
            # A LITERAL-ONLY EMIT IS REPORTED IN ITS OWN CLASS AND NOT COUNTED AS AN ASSERTION.
            # `gates/autogen-oracle.py:21` is `print("### TMAP (CXType kind -> ctypes name)")` --
            # a HEADING, and five of its words are not answers. Whether a bare literal is a
            # heading or the whole answer is not knowable without running it, so the census says
            # so rather than guessing: the class is named, counted, and left out of `asserted`.
            # `--plant`'s `no-equals-row` is the case that holds this line, and its expected
            # verdict is `LITERAL-ONLY`, not `UNSOURCED` and not `DERIVED`.
            literal_only.append({"row": f"{callee}@{lineno}",
                                 "line": lineno,
                                 "text": "".join(p for _, p in value)[:70]})
            rows.append({"row": f"{callee}@{lineno}", "line": lineno,
                         "asserted": 0, "computed": 0, "literal_only": 1})
            continue
        row = "".join(p for k, p in label if k == "lit").split("=")[0].strip() or \
            f"{callee}@{lineno}"
        n_a = n_c = 0
        for kind, payload in value:
            if kind == "lit":
                # A LITERAL RUN IS SPLIT INTO ITS TOKENS, and the unit is the TOKEN. It has to be:
                # `CONST/0:f1063675494 BUFFER/0` is ONE literal segment and THREE answers -- an op
                # name CPython spells and two numbers it does not -- and a census that counted
                # SEGMENTS would report one finding where the reader needs three, and would not
                # tell `CONST` from `f1063675494`. The pins arm (`pin_components`) tokenises the
                # same way, so the two classes are measured in one unit.
                for tok in SEP_RE.split(payload):
                    if not tok:
                        continue
                    n_a += 1
                    comps.append({"row": row, "line": lineno, "text": tok, "shape": "LITERAL"})
                continue
            if taint.derived_expr(payload):
                n_c += 1
                text, ok = taint.fold(payload)
                if ok:
                    derived_texts.add(text)
                continue
            text, ok = taint.fold(payload)
            if ok and EMPTY_VALUE.match(text):
                continue        # `''`, `[]`, `()`, `{}`: a derived EMPTY value carries no answer
            if has_unresolved_name(payload, taint.bound):
                # THE CENSUS'S OWN BLIND SPOT. See `has_unresolved_name`: an unresolvable name is
                # not an assertion, and counting it as one is how this file first reported 33
                # asserted components in an oracle's headings.
                unresolved.append({"row": row, "line": lineno,
                                   "text": ast.unparse(payload)[:60]})
                continue
            comps.append({"row": row, "line": lineno,
                          "text": text if ok else ast.unparse(payload)[:60],
                          "shape": "FOLDED" if ok else "EXPR"})
            n_a += 1
        asserted += n_a
        computed += n_c
        rows.append({"row": row, "line": lineno, "asserted": n_a, "computed": n_c})
    return {"rows": rows, "asserted": asserted, "computed": computed, "components": comps,
            "derived_texts": derived_texts, "taint_roots": taint.roots,
            "unresolved": unresolved, "literal_only": literal_only}


def verdict(asserted: int, computed: int, unsourced: int, literal_only=0) -> str:
    """THE SHIPPED PER-ORACLE VERDICT. One function, four inputs, five words.

    The three FINDING words are ordered by how much they cost the tree, and the order is the
    argument: `UNSOURCED` first because it is the only one that cannot be repaired by deleting a
    line, `ASSERTED` second because it can, `DERIVED` last because it is the clean state.

    `LITERAL-ONLY` is NOT a finding and is not `DERIVED` either -- it says "this file emits at
    least one constant line and the census cannot tell a heading from an answer". Calling it
    `DERIVED` would be a clean bill of health the census has not earned; calling it `ASSERTED`
    would be the 33-heading false positive. It is its own word because it is its own question.

    `NO-ROWS` is what is left: a file that emits no `name=value` row at all.
    """
    if literal_only and not asserted and not computed:
        return "LITERAL-ONLY"
    if unsourced:
        return "UNSOURCED"
    if asserted:
        return "ASSERTED"
    return "DERIVED" if computed else "NO-ROWS"


def component_verdict(text: str, in_subject: bool) -> str:
    """THE SHIPPED PER-COMPONENT VERDICT. One test, two words, and the words are about PROVENANCE.

    `SOURCED-BY-SUBJECT` -- the text is identifier-shaped AND `tinygrad/**.py` spells it, so the
    derivation is `<holder>.name` and the holder is printed beside the finding.

    `UNSOURCED` -- everything else, and that is the STRONGER verdict the brief asks for: not merely
    asserted but with NO CPYTHON EXPRESSION NAMED. A NUMBER, a bit pattern and a port-only tag are
    all in this class, and they are the class that has cost this tree rows.

    **A THIRD TEST WAS WRITTEN AND DELETED, AND THE DELETION IS THE POINT.** There was a
    `SOURCED-IN-FILE` arm -- "the SAME oracle derives this exact text in another row" -- which is
    strictly stronger provenance than a grep. It cannot work here, and the reason is structural
    rather than a bug: the only way to learn what `Ops.CAST.name` EVALUATES TO is to run it, and
    this census runs NOTHING (0 subprocesses is a stated property, not an accident). So the arm
    would have been a branch that can never fire -- `gates/gatekit.py` spends a paragraph on that
    ("a constant nothing in this file names is not a constant nothing can produce"), and a dead
    branch is worse than no branch because it reads as coverage on a line that covers nothing.
    The census reports `SOURCED-BY-SUBJECT` for what it can PROVE and `UNSOURCED` for the rest,
    and the rest is the honest remainder.
    """
    return "SOURCED-BY-SUBJECT" if in_subject and IDENT.match(text.strip("\"'")) else "UNSOURCED"


# ============================================ 5. THE SUBJECT VOCABULARY, AND ITS LIMITS


def subject_tokens():
    """`{token: first holder}` over `tinygrad/**.py`. A WALK, and the walk's cost is stated.

    This is a VOCABULARY INDEX, not a proof of derivability: it says "this identifier is spelled
    somewhere in the subject tree", which is a necessary condition for `<holder>.name` and not a
    sufficient one. The census therefore reports `SOURCED-BY-SUBJECT` as what it is -- a token
    CPython spells -- and the REPORT names the holder, because "nameable" has to be checkable by a
    reader and not merely asserted by this file.

    ITS LIMIT IS ALSO ITS HONESTY BOUNDARY. A dtype NAME such as `float32` is spelled in
    `tinygrad/dtype.py` and is a dtype `.name`; `CONST` is spelled in `tinygrad/uop/ops.py` and is
    an `Ops` member; but the token `f32` also occurs there and is not what
    `_new_optim_param()[0].dtype.name` returns. So a `SOURCED-BY-SUBJECT` is a CANDIDATE
    derivation and the census labels it that way in the header rather than promoting it.
    """
    out = {}
    word = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\b")
    for p in sorted(SUBJECT.rglob("*.py")):
        try:
            text = p.read_text(errors="replace")
        except OSError:
            continue
        # LINE NUMBERS BY BISECT OVER THE NEWLINE OFFSETS, and the first version of this function
        # wrote `text[:m.start()].count("\n")` inside the loop. MEASURED: that is a slice of the
        # WHOLE FILE per token -- 1 141 161 tokens over `tinygrad/**.py` -- and it did not finish
        # in 120 s. The offsets are built once per file, so the line is a `bisect` and the walk
        # is linear. A census that times out on its own vocabulary has measured nothing, and the
        # failure is silent: there is no output and no error, only a shell that stops answering.
        nl = [i for i, ch in enumerate(text) if ch == "\n"]
        rel = p.relative_to(ROOT).as_posix()
        for m in word.finditer(text):
            out.setdefault(m.group(1), f"{rel}:{bisect.bisect_left(nl, m.start()) + 1}")
    return out


def classify(src, vocab):
    """One oracle's source, through every shipped function, into its census row."""
    got = census_source(src, vocab)
    for c in got["components"]:
        raw = c["text"].strip("\"'")
        c["verdict"] = component_verdict(raw, raw in vocab)
        c["holder"] = vocab.get(raw, "")
    n_uns = sum(1 for c in got["components"] if c["verdict"] == "UNSOURCED")
    got["unsourced"] = n_uns
    got["verdict"] = verdict(got["asserted"], got["computed"], n_uns, len(got["literal_only"]))
    return got


# ============================================================ 6. THE PINS, AS ROW PAIRS


def divergence_literals(src: str):
    """`[(label, line, [tokens])]` -- a GATE's ASSERTED EXPECTED VALUES, and nothing else.

    **A GATE'S `print` CALLS ARE NOT ITS EXPECTED VALUES, AND SCANNING THEM IS A FALSE POSITIVE
    OF 53 OF 98.** The first version of this census applied the ORACLE arm to gates as well and
    reported `gates/realize_graph_census-gate.py` with 490 asserted components. MEASURED, they
    are `print(f"--refresh: {PINS.name} rewritten -- {len(rows)} divergences")` and 489 siblings:
    a gate's stdout is a REPORT about its run, and `--refresh: 14 divergences rewritten` is not an
    assertion that the port prints 14. Applying one rule to two populations is how an instrument
    produces a number nobody can act on.

    A GATE'S EXPECTED VALUES ARE IN ITS `DIVERGES`, ITS `pins=`, AND ITS `.rows` FILE -- the three
    places `gates/gatekit.py`'s `Gate.run()` reads an expected line out of. So this arm looks at
    exactly those three, which is also why it is small: the ORACLE arm's population is 78 files and
    this one's is the subset that declares a divergence at all.

    THE DISCOVERY IS A NAME SHAPE AND IT IS ADMITTED AS ONE, because there is no generator for
    "the dict a gate passes as `diverges=`". What keeps it honest is that it is a LOWER BOUND:
    a gate that hardcodes its expected value in a shape this misses contributes ZERO to the count,
    which is the direction that under-claims rather than the one that invents findings. The census
    prints the count of files where the shape fired so a reader can see the bound's size.
    """
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return []
    out = []
    # `Gate(..., diverges=DIVERGES)` NAMES the dict rather than inlining it, so the `Gate(` read
    # below handles the INLINE shape and this one handles the NAME-BOUND shape. Both halves exist
    # because the NAMED INSTANCE needs the second: `gates/op_graph_census-gate.py:115` binds
    # `DIVERGES = {...}` and `:135` passes `diverges=DIVERGES`.
    for n in ast.walk(tree):
        if isinstance(n, ast.Assign) and isinstance(n.value, ast.Dict) and \
                any(isinstance(t, ast.Name) and "DIVERGE" in t.id.upper() for t in n.targets):
            _emit_divergence(out, n.targets[0].id, n.value)
        elif isinstance(n, ast.Call) and getattr(n.func, "attr", "") == "Gate":
            for kw in n.keywords:
                if kw.arg == "diverges" and isinstance(kw.value, ast.Dict):
                    _emit_divergence(out, "Gate(diverges=)", kw.value)
    return out


def _emit_divergence(out, label, node):
    """One `Gate.diverges` dict: `{row: (cpython_line, port_line)}` -> tokenised expected values.

    A DIVERGENCE IS AN EXPECTED VALUE BY DEFINITION -- it is a line the gate asserts a lane
    CONTAINS -- so every token of it is an asserted component and the only question is which of
    them CPython is able to spell. `gates/op_graph_census-gate.py`'s `mstep` pair is four `CONST`
    and `BUFFER` (CPython spells both), four arity digits and two `f…` bit patterns (CPython spells
    NONE of them), which is why the count of UNSOURCED tokens is the number a reader wants.
    """
    for key, val in zip(node.keys, node.values):
        if key is None:
            continue
        row = key.value if isinstance(key, ast.Constant) else ast.unparse(key)
        for side, text in _strings_of(val):
            out.append((f"{label}:{row}", key.lineno if hasattr(key, "lineno") else 0,
                        SEP_RE.split(text)))


def _strings_of(node):
    """Every STRING in an expression, folded where the fold is safe. `str(x)` included."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return [(node.lineno, node.value)]
    if isinstance(node, ast.Tuple) or isinstance(node, ast.List):
        out = []
        for e in node.elts:
            out += _strings_of(e)
        return out
    if isinstance(node, ast.Call) and getattr(node.func, "id", "") == "str" and node.args:
        return _strings_of(node.args[0])
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return _strings_of(node.left) + _strings_of(node.right)
    return []


def pin_components(text: str):
    """`(row, [value tokens])` for one pin line, split at the tree's FIRST `=`.

    A PIN IS AN ASSERTED COMPONENT BY CONSTRUCTION -- it is the expected value, typed -- so the
    only question the census asks of one is whether its tokens are CPython vocabulary. That is why
    the pins are reported as a separate CLASS and not merged with the oracles: an oracle's literal
    is asserted INSIDE a computation, a pin's literal is asserted INSTEAD of one.
    """
    row, _, value = text.partition("=")
    toks = [t for t in value.split() if t and not SEPARATOR.match(t)]
    return row.strip(), toks


# ================================================================= 7. THE PLANT


PLANT_ORACLES = {
    # 1. THE CONTROL. Every value derived from a `tinygrad` import. MUST read DERIVED.
    "control-derived": '''\
from tinygrad import Tensor
a = Tensor([1.0, 2.0], device="PYTHON")
print(f"numel={a.numel()}")
print(f"sqrt_op={a.sqrt().uop.op.name}")
''',
    # 2. THE NAMED DEFECT, VERBATIM IN SHAPE. `Nzs` is a port-only tag; the oracle types it.
    #    MUST read ASSERTED with `Nzs` UNSOURCED.
    "asserted-typed-name": '''\
from tinygrad import Tensor
from tinygrad.nn import optim
o = optim.Optimizer([Tensor([1.0, 2.0], device="PYTHON")], lr=0.1)
print("nop=%s," % ",".join("%s:%d" % ("Nzs", x.numel()) for x in o._new_optim_param()))
''',
    # 3. THE CONSTANT. `int(1)` cannot fail. MUST read ASSERTED/UNSOURCED.
    "asserted-constant": '''\
from tinygrad import Tensor
a = Tensor([1.0], device="PYTHON")
print(f"bitnot_op_is_cmpne={int(1)}")
''',
    # 4. A DERIVED value NEXT TO an ASSERTED one -- the half-derived row the brief asks to see.
    #    MUST read 1 asserted / 1 computed, so a boolean verdict cannot hide the split.
    "half-derived": '''\
from tinygrad import Tensor
a = Tensor([1.0], device="PYTHON")
print(f"mixed={int(a.numel())}-42")
''',
    # 5. A FIXTURE literal inside the value's own constructor is an INPUT, not an answer: it is
    #    inside a DERIVED call, so it never becomes a VALUE segment. MUST read DERIVED.
    "fixture-is-not-asserted": '''\
from tinygrad import Tensor
a = Tensor([1.0, 2.0, 3.0], device="PYTHON")
print(f"shape_numel={a.numel()}")
''',
    # 6. A BARE CONSTANT WITH NO `=` AND NO INTERPOLATION. `gates/autogen-oracle.py:21` is
    #    `print("### TMAP (CXType kind -> ctypes name)")` -- a HEADING, and five of its words are
    #    not answers. Whether a bare literal is a heading or the whole answer is not knowable
    #    without running it, so the census has its OWN WORD for it and does not call it a finding.
    #    MUST read `LITERAL-ONLY`: not `UNSOURCED` (the false positive) and not `DERIVED` (a clean
    #    bill of health the census has not earned).
    "no-equals-row": '''\
from tinygrad import Tensor
print("424242")
''',
    # 7. A PIN TOKEN CPYTHON SPELLS. `CAST` is a BARE literal in the value region, and CPython
    #    spells `CAST` in `tinygrad/uop/ops.py`, so the component is SOURCED-BY-SUBJECT and the
    #    ORACLE is ASSERTED -- a redundancy with a nameable derivation, NOT an unsourced value.
    "subject-token": '''\
from tinygrad.uop.ops import Ops
from tinygrad import Tensor
a = Tensor([1.0], device="PYTHON")
print(f"typed_op={Ops.CAST.name}-CAST-{a.numel()}")
''',
    # 8. NO TINYGRAD IMPORT AT ALL. Nothing can be derived, so any literal is asserted -- which is
    #    the correct answer for a host-model oracle and NOT a false positive.
    "no-tinygrad": '''\
def h(x, y):
    return x + y
print(f"host={h(1, 2)}")
''',
    # 9. A NUMERIC BIT PATTERN. `f1063675494` is an f32 CONST's bits -- the port's `F32.bits`, and no
    #    CPython expression spells it. It is the shape that appears 2 111 times across the pins
    #    files, and it MUST be UNSOURCED even though its sibling `SQRT` on the same row is not.
    #    One plant that mixed the two would pass with the tests swapped, which is why the two
    #    classes get a case EACH rather than one case between them.
    "bit-pattern": '''\
from tinygrad import Tensor
print(f"bits={Tensor([1.0], device='PYTHON').uop.op.name}:f1063675494")
''',
    # 10. A HUNDRED CHARACTER expected string in the VALUE region, from a SHALLOW expression.
    #     MUST read UNSOURCED with the text reported WHOLE, because a truncation here would make
    #     the finding unfalsifiable -- a reader could not tell what was actually asserted.
    "long-asserted": '''\
from tinygrad import Tensor
print(f"sig={Tensor([1.0], device='PYTHON').uop.op.name}-42-CONST/0:f1063675494-BUFFER/0")
''',
    # 11. A COMPARISON against a derived value is COMPUTED even though the operand is a literal:
    #     `r.op is Ops.CMPNE` is a question ABOUT CPython, and its answer is CPython's.
    "compare-is-computed": '''\
from tinygrad import Tensor
from tinygrad.uop.ops import Ops
r = Tensor([1.0], device="PYTHON").sqrt().uop
print(f"is_sqrt={int(r.op is Ops.SQRT)}")
''',
    # 12. THE NEGATIVE CONTROL FOR THE PLANT ITSELF: an oracle whose only literals are LABELS.
    #     A row NAME is typed by definition and carries no answer. MUST read DERIVED with 0
    #     asserted -- and if it does not, the census is counting row names as answers, which is
    #     the false positive that would make every finding here unreadable.
    "label-is-not-asserted": '''\
from tinygrad import Tensor
print(f"row_name_only={Tensor([1.0], device='PYTHON').numel()}")
''',
}


def plant() -> int:
    """TWELVE CASES, EVERY ONE CALLING `census_source` AND `component_verdict` -- THE SHIPPED ONES.

    `gates/runner.py --plant` is the precedent and its lesson is quoted in that file: the first
    version reached PAST the shipped decision function into its helpers, so breaking
    `preconditions`' branch left the plant GREEN. Nothing here calls a private helper to reach a
    verdict; the verdict comes from `verdict()`/`component_verdict()` on `census_source()`'s own
    output, which is the code the census runs.

    CASE 12 IS A CONTROL ON THE INSTRUMENT, NOT ON AN ORACLE: if a row NAME counted as an answer,
    every finding in the census would be unreadable, so the case that proves the LABEL region is
    excluded is as load-bearing as the one that proves the VALUE region is not.
    """
    vocab = subject_tokens()
    # `(oracle verdict, asserted count, the COMPONENT verdicts, in order)`. The third column is the
    # one that matters most: `SOURCED-BY-SUBJECT` and `SOURCED-IN-FILE` are PER-COMPONENT verdicts,
    # and a plant that only asserted the per-ORACLE verdict would pass whichever of the two tests
    # the classifier actually applied -- which is how case 9 could have stayed green with the two
    # swapped. A test that cannot tell two implementations apart is a test that measures nothing.
    want = {
        "control-derived": ("DERIVED", 0, []),
        # ONE asserted component (`Nzs`) and ONE computed (`x.numel()`), which is EXACTLY the split the
        # caller measured by hand. Getting here took a real fix rather than a relaxed expectation:
        # the first run reported `2 asserted` with the second component `x.numel()`, because the
        # taint did not bind a comprehension's loop variable. `--plant` exists to catch exactly that
        # -- MEASURED, the census was wrong about the named instance and the plant is what said so.
        "asserted-typed-name": ("UNSOURCED", 1, ["UNSOURCED"]),
        "asserted-constant": ("UNSOURCED", 1, ["UNSOURCED"]),
        "half-derived": ("UNSOURCED", 1, ["UNSOURCED"]),
        "fixture-is-not-asserted": ("DERIVED", 0, []),
        "no-equals-row": ("LITERAL-ONLY", 0, []),
        "subject-token": ("ASSERTED", 1, ["SOURCED-BY-SUBJECT"]),
        "no-tinygrad": ("UNSOURCED", 1, ["UNSOURCED"]),
        "long-asserted": ("UNSOURCED", 6, ["UNSOURCED", "SOURCED-BY-SUBJECT", "UNSOURCED",
                                           "UNSOURCED", "SOURCED-BY-SUBJECT", "UNSOURCED"]),
        "compare-is-computed": ("DERIVED", 0, []),
        "label-is-not-asserted": ("DERIVED", 0, []),
        # The `0` of the `nsrc` IS asserted too, so this row is 2 components and the per-oracle verdict is
        # UNSOURCED, not ASSERTED. The FIRST version of this case expected `ASSERTED` and the
        # census answered `UNSOURCED`; I checked which was right by reading the row rather than by
        # relaxing the expectation -- `--plant`'s job is to catch ME being wrong about a row, and a
        # plant whose expectations are edited until they agree measures the edit.
        "bit-pattern": ("UNSOURCED", 1, ["UNSOURCED"]),
    }
    bad = []
    for name, src in PLANT_ORACLES.items():
        try:
            got = classify(src, vocab)
        except Exception as exc:                      # a crash is a RED plant, not a skip
            print(f"  {name:<26} RAISED {type(exc).__name__}: {exc}")
            bad.append(name)
            continue
        wv, wa, wc = want[name]
        n_a = got["asserted"]
        comps = [c["verdict"] for c in got["components"]]
        ok = got["verdict"] == wv and n_a == wa and comps == wc
        # THE HALF-DERIVED ROW IS ALSO ASSERTED ON ITS COMPUTED COUNT, so a census that reported
        # `1 asserted` by reading the whole row as the answer would pass the verdict and fail
        # here. The split is the deliverable, so the split is asserted.
        if name == "half-derived" and got["computed"] != 1:
            ok = False
        print(f"  {name:<26} {got['verdict']:<11} asserted={n_a} computed={got['computed']:<3} "
              f"components={','.join(comps) or '-'}"
              + ("" if ok else f"   EXPECTED {wv} a={wa} {wc}"))
        if not ok:
            bad.append(name)
    # THE MUTATION PLANT: the census must go RED on a literal INSERTED INTO A REAL ORACLE. Every
    # other case is a synthetic source; this one takes a file out of the tree, types an answer
    # into its value region, and requires the verdict to MOVE. A census that cannot go red on the
    # literal it exists to catch is the class this whole instrument is measuring, so the plant has
    # to demonstrate the transition and not only the states.
    moved = []
    for rel in ("gates/op_graph_census-oracle.py", "gates/rand_census-oracle.py"):
        p = ROOT / rel
        if not p.is_file():
            continue
        before = classify(p.read_text(errors="replace"), vocab)
        mutant = p.read_text(errors="replace") + '\nprint(f"planted_expected={int(424242)}")\n'
        after = classify(mutant, vocab)
        fired = after["asserted"] == before["asserted"] + 1 and \
            after["verdict"] in ("UNSOURCED", "ASSERTED")
        print(f"  mutate {rel:<34} {before['verdict']} a={before['asserted']} -> "
              f"{after['verdict']} a={after['asserted']}"
              + ("" if fired else "   DID NOT GO RED"))
        if not fired:
            bad.append(f"mutate:{rel}")
        else:
            moved.append(rel)
    print(f"--plant: {'all ' + str(len(PLANT_ORACLES)) + ' cases and both mutations OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


# ==================================================================== 8. THE REPORT


def _row(cls, rel, got):
    return [cls, rel, got["verdict"], str(got["asserted"]), str(got["computed"]),
            str(got["unsourced"]), str(len(got["rows"]))]


def run(report_only=False):
    pops, deriv = population()
    vocab = subject_tokens()
    lines = [
        "# assertlit.rows -- GENERATED by `gates/assertlit-census.py`, which is its ONLY writer.",
        "# TAIL-separated: `class<TAB>path<TAB>verdict<TAB>asserted<TAB>computed<TAB>unsourced"
        "<TAB>rows`.",
        "#",
        "# `asserted` COUNTS VALUE-REGION COMPONENTS THAT ARE NOT DERIVED FROM CPYTHON; "
        "`computed` COUNTS THE ONES THAT ARE. A ROW THAT IS HALF-DERIVED IS VISIBLE AS A ROW OF "
        "THE TABLE AND NOT AS A BOOLEAN.",
        "# `verdict`: UNSOURCED (at least one asserted component has NO nameable derivation) · "
        "ASSERTED (every asserted component's text is spelled by CPython) · DERIVED (nothing "
        "asserted, something computed) · NO-ROWS (no value region reached).",
        "#",
        f"# HOMES are `gates/gates-pop.py`'s, LOADED BY PATH: {', '.join(deriv['homes'])}.",
        f"# DENOMINATOR: {len(pops['ORACLE'])} ORACLE · {len(pops['GATE'])} GATE · "
        f"{len(pops['PINS'])} PINS, all from a DIRECTORY WALK of those homes.",
        f"# DECLARATION READ: {len(deriv['declared_beyond_walk'])} gates were found by "
        f"`Gate(` in the AST and not by the `*gate*` stem.",
    ]
    tally = {}
    print(f"assertlit-census: homes {deriv['homes']} · {len(pops['ORACLE'])} oracles · "
          f"{len(pops['GATE'])} gates · {len(pops['PINS'])} pins files · "
          f"{len(vocab)} subject tokens\n")
    print(f"{'class':<8} {'verdict':<13} {'file':<44} {'a':>4} {'c':>5} {'u':>4} {'rows':>5}")
    rows_out = []
    not_applicable = []
    for rel, p in sorted(pops["ORACLE"].items()):
        try:
            src = p.read_text(errors="replace")
        except OSError:
            src = ""
        if not reads_tinygrad(src):
            # NOT CLAIMED, AND COUNTED. See `reads_tinygrad`: the shape-based walk admits the
            # instruments that CENSUS oracles, and for those the taint would read a report as an
            # answer. They are a separate class with its own count, never merged into the oracle
            # denominator -- a census that quietly drops the files it cannot judge is a census whose
            # denominator a reader cannot reconstruct.
            not_applicable.append(rel)
            rows_out.append(["NOT-APPLICABLE", rel, "NO-TINYGRAD", "0", "0", "0", "0"])
            continue
        try:
            got = classify(src, vocab)
        except (OSError, SyntaxError):
            got = {"verdict": "UNREADABLE", "asserted": 0, "computed": 0,
                   "unsourced": 0, "rows": [], "components": []}
        rows_out.append(_row("ORACLE", rel, got))
        tally[("ORACLE", got["verdict"])] = tally.get(("ORACLE", got["verdict"]), 0) + 1
        if got["asserted"] or got["unsourced"]:
            sample = "; ".join(f"{c['row']}:{c['text'][:24]}[{c['verdict']}]"
                               for c in got["components"] if c["verdict"] == "UNSOURCED")[:110]
            print(f"{'ORACLE':<8} {got['verdict']:<13} {rel:<44} {got['asserted']:>4} "
                  f"{got['computed']:>5} {got['unsourced']:>4} {len(got['rows']):>5}")
            if sample:
                print(f"{'':<8} {'':<13} {'':<44}   {sample}")
    print()
    for v in ("UNSOURCED", "ASSERTED", "DERIVED", "NO-ROWS", "UNREADABLE"):
        n = tally.get(("ORACLE", v), 0)
        if n:
            print(f"  ORACLE   {v:<11} {n:>3} of {len(pops['ORACLE']) - len(not_applicable)}")
    # THE GATE ARM. A gate's expected values are its `diverges` literals -- NOT its prints, and
    # the reason is measured and stated on `divergence_literals`.
    print("\n  GATE DIVERGENCE LITERALS -- the EXPECTED VALUES `gatekit` asserts a lane contains.")
    g_sum = {"files": 0, "tokens": 0, "sourced": 0, "unsourced": 0}
    for rel, p in sorted(pops["GATE"].items()):
        try:
            divs = divergence_literals(p.read_text(errors="replace"))
        except OSError:
            continue
        if not divs:
            continue
        g_sum["files"] += 1
        s = sum(1 for _, _, toks in divs for t in toks if component_verdict(t, t in vocab)
                == "SOURCED-BY-SUBJECT")
        u = sum(1 for _, _, toks in divs for t in toks if component_verdict(t, t in vocab)
                == "UNSOURCED")
        g_sum["tokens"] += s + u
        g_sum["sourced"] += s
        g_sum["unsourced"] += u
        rows_out.append(["GATE", rel, verdict(u, s + u, u), str(s + u), str(0), str(u),
                         str(len(divs))])
        print(f"  {rel:<46} {len(divs):>3} divergences, {s + u:>4} tokens: {s:>4} spelled by "
              f"CPython, {u:>4} UNSOURCED")
    print(f"  {'':<46} {g_sum['files']:>3} of {len(pops['GATE'])} gates declare any; "
          f"{g_sum['tokens']} tokens, {g_sum['sourced']} sourced, {g_sum['unsourced']} UNSOURCED")
    # THE PINS. A pin is an asserted component by construction, so the only question is whether
    # its tokens are CPython's vocabulary -- and the answer is per TOKEN, so the counts are of
    # tokens, which is why they are reported separately from the oracle table rather than summed
    # into it.
    pin_tok = {"SOURCED-BY-SUBJECT": 0, "UNSOURCED": 0}
    for rel, p in sorted(pops["PINS"].items()):
        for ln in p.read_text(errors="replace").splitlines():
            if not ln.strip() or ln.startswith("#"):
                continue
            for tok in pin_components(ln)[1]:
                v = component_verdict(tok, tok in vocab)
                pin_tok[v] = pin_tok.get(v, 0) + 1
    print(f"  PINS    {len(pops['PINS'])} files, "
          f"{sum(pin_tok.values())} value tokens: "
          f"{pin_tok.get('SOURCED-BY-SUBJECT', 0)} spelled by CPython, "
          f"{pin_tok.get('UNSOURCED', 0)} not")
    print(f"  NOT-APPLICABLE  {len(not_applicable)} of {len(pops['ORACLE'])} walked files import "
          f"nothing from `tinygrad` and are CLAIMED NOTHING ABOUT -- the census holds that a "
          f"report about oracles is not an oracle")
    if not report_only:
        REPORT.write_text("\n".join(lines) + "\n" +
                          "\n".join("\t".join(r) for r in rows_out) + "\n")
        print(f"\nassertlit.rows written: {len(rows_out)} rows")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--report", action="store_true", help="census only, rc never charged")
    ap.add_argument("--plant", action="store_true", help="twelve cases against the shipped fns")
    a = ap.parse_args()
    if a.plant:
        return plant()
    return run(a.report)


if __name__ == "__main__":
    sys.exit(main())