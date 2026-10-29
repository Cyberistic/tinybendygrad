#!/usr/bin/env python3
"""gates/reachability-gate.py -- CAN A FRESH CLONE RUN A GATE, AND IS THAT GETTING WORSE?

    .venv/bin/python gates/reachability-gate.py                 # the census and the verdict
    .venv/bin/python gates/reachability-gate.py --plant          # the plant and its control
    .venv/bin/python gates/reachability-gate.py --write-ledger   # re-record the reachable set

WHAT THIS IS. `AGENTS.md` recorded, on 2026-10-20, that "13 FRESHNESS INSTRUMENTS, 0 REACHABLE
FROM ANY SURFACE": `.git/hooks/` held no non-`.sample` file, `core.hooksPath` was unset, the nine
files in `.github/workflows/` named no gate, and `gates/artifacts/` is gitignored -- so from a
fresh clone the questions "was this gate ever run?" and "does this gate exist?" had one answer
between them: nothing.

**THAT READING IS STALE AND THE STALE PART IS NAMED, NOT GUESSED.** `gates/edge-runner.py` and
`.github/workflows/edge-gates.yml` arrived after it. So this file re-measures rather than cites,
and it splits the question into the two halves that were being conflated:

  * **EXISTENCE** -- the POPULATION: the gates the tree carries, DISCOVERED by
    `gates/gates-pop.py` (`gate_homes()` and the entry-point classifiers), never listed.
  * **REACHABILITY** -- who NAMES whom, and from WHICH root. A name in a COMMENT is a mention,
    not an invocation, so the join reads CODE lines only, and the tree's own
    `gates/pincensus-pop.py` (`code_lines()`, `host_of()`) is what decides that.

**THE JOIN IS COMPONENT-WISE, AND THE COMPONENTS ARE THE POINT.** MEASURED on this tree, a
basename substring join answers `gates/edge-runner.py` as naming `gates/runner.py` and
`sh tools/get-bend.sh` as naming `checks/bend` -- both false, and both the shape `AGENTS.md`
records as **"A **TRUNCATED **TOKEN **IS **NOT **A **HARMLESS **ONE**, **IT **WROTE **FALSE **ROWS
**IN **BOTH **DIRECTIONS."** -- **WHICH **IS **THE **WORDING `checks/repro-paths.py` **USES **FOR
**THE **SAME **DEFECT, **AND **WHOSE **"A **PREFIX **OF **A **PATH **IS **READ **AS **THE **PATH"
**IS **THE **PHRASE `AGENTS.md` **CARRIES.** A path token is
therefore split into COMPONENTS and compared component-wise, so `edge-runner.py` and `runner.py`
are different components and never meet.

**A GATE NAMED BY A GATE THAT NOTHING RUNS IS STILL UNREACHABLE**, so the verdict is a
TRANSITIVE CLOSURE from the ROOTS, and the chains are printed: a chain that ends in nothing is
printed as such, with its length.

**THE ROOTS ARE THE SURFACES A FRESH CLONE CAN EXECUTE, AND THE HOOKS ARE NOT AMONG THEM.**
`.git/hooks/` is untracked and `git init` writes only `.sample` files, so a fresh clone has no
hook that names anything; the count of non-`.sample` hooks on THIS machine is reported, and the
hooks are NOT roots. `.github/workflows/**` is tracked and IS a root, and so is a `Makefile` at
the root. **AN EMPTY ROOT SET IS REFUSED (3), NEVER PASS (0)**: "no gate is run" and "all gates
are run" would otherwise look the same, and a gate that cannot tell them apart is a gate that
is trusted.

**THE TWO ARMS, AND THEY ARE DIFFERENT CLAIMS.** The JOIN says a gate is *named*; the TRACE
(`gates/edge-trace.rows`, in git, beside the edge that writes it) says a gate *ran*. Naming is
not running: `checks/gatesweep.py` names `gates/gates-pop.py` because it LOADS it, and the
edge does not run it. Both arms are reported with their denominators, and the trace is reported
with the HEAD it was taken at, because a trace of a different tree is a different answer.

**THE LEDGER IS THE MOVING BASELINE, AND IT RECORDS PATHS.** `gates/reachability.ledger.tsv`
holds one row per population path and whether it was reachable. A population that GROWS does not
make this gate red -- the tree is live and another unit's new gate is not a defect -- so the
comparison is over the RECORDED paths, and a path the ledger does not hold is NAMED, not
charged. **A RECORDED PATH THAT STOPPED BEING REACHABLE IS RED**, because that is a gate that
used to be run and is not any more. The write is explicit, it PRINTS the diff, and it REFUSES on
an empty population, because a ledger that can be emptied is a green that measured nothing.

VERDICTS are `gates/gatekit.py`'s, LOADED BY PATH: `PASS 0 · FAIL 1 · REFUSED 3 · SKIP 4 ·
DEAD 5`. **SKIP IS NOT PASS** and **DEAD IS NOT A ZERO**: a census that produced no rows has
measured nothing, and this file says DEAD rather than 0.
"""
import argparse
import importlib.util
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
LEDGER = HERE / "reachability.ledger.tsv"
TRACE = HERE / "edge-trace.rows"

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5

# THE EDGE'S HOOK, DECLARED HERE AND READ BY THE EDGE (`gates/edge-runner.py:declares_edge_candidate`).
#
# **THE GATE THAT MEASURES REACHABILITY WAS ITSELF UNREACHABLE**, which is the sharpest instance
# of the class this tree keeps rediscovering: an instrument that is DISCOVERED and that nobody runs
# measures nothing, and the instrument that says so was among the ones nobody ran. MEASURED
# 2026-10-22: this file was in no `.github/workflows/`, held no pin the edge's selection rule could
# see, and had no row in `gates/edge-cost.rows` -- so the edge never ran it and its answer about
# the tree reached nobody.
#
# The tree's own mechanism is the fix, and it is the SAME one the compile-census gate and the
# oracle-pin gate use: declare it, and let the runner write the cost row and the trace row.
# **A HAND-WRITTEN ROW IN EITHER LEDGER WOULD BE A ROW THE RUNNER NEVER PRODUCED.** The cost is
# MEASURED: this gate takes 12.6 s against the edge's 30 s budget, so the edge can afford it.
EDGE_CANDIDATE = True

# A PATH TOKEN: a maximal run of the characters a path is made of. `.` and `-` are IN it, because
# `edge-runner.py` is one component and splitting it would make `runner.py` a component too --
# and a component that is not a component is how a basename join answers "yes" to the wrong gate.
TOKEN = re.compile(r"[A-Za-z0-9_.\-/]+")


def load(name, path):
    """A MODULE, LOADED BY PATH. `gates/` is not a package, and a module loaded by a bindable
    name is a module whose population anybody can choose."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def instruments(root):
    """The three instruments this file uses, each LOADED BY PATH and each owned by the tree.

    `gates/gates-pop.py` owns the POPULATION and the tracked-path rule; `gates/pincensus-pop.py`
    owns the CODE/PROSE split; `gates/gatekit.py` owns the five verdicts. **THIS FILE HOLDS NO
    COPY OF ANY OF THE THREE**, because a second copy of a vocabulary is a second population with
    a different predicate -- one question, two answers."""
    g = load("reach_gatespop", Path(root) / "gates" / "gates-pop.py")
    p = load("reach_pincensus", Path(root) / "gates" / "pincensus-pop.py")
    k = load("reach_gatekit", Path(root) / "gates" / "gatekit.py")
    if g is None or p is None or k is None:
        return None, None, None
    return g, p, k


# ---- the join -----------------------------------------------------------------------------
# A PATH IS EVALUATED, NOT MATCHED. This is the whole instrument.
#
# **THE LEXICAL JOIN WAS WRONG THREE TIMES, AND EACH TIME IT WAS WRONG IN A DIRECTION THAT
# ADDS UP.** MEASURED 2026-10-21 on this tree:
#   * a basename-substring join named `gates/runner.py` from the token `edge-runner.py`, and
#     `checks/bend` from the token `get-bend.sh` -- the shape `checks/repro-paths.py` was
#     retracted for, a PREFIX OF A PATH READ AS THE PATH;
#   * a component-wise join then missed every SIBLING load -- `HERE / "pincensus-pop.py"` names
#     `gates/pincensus-pop.py`, and a lexical rule cannot know that `HERE` is `gates/`;
#   * and a bare-name rule named `checks/bend` from **19** files and `checks/differ.py` from
#     **26**, every one of them a WORD: `bend` is a LANE NAME here, and a workflow's
#     `python sz.py` is the ROOT's `sz.py`, not `checks/sz.py`.
#
# So the path CONSTANTS of each file are EVALUATED -- `HERE`, `ROOT`, `REPO`, `GATES` and every
# other name the file assigns -- and a path expression is resolved THROUGH them. That is the
# same move `gates/gates-pop.py:resolve_root` makes for a root constant, and the same reason:
# **a path a file computes is not a path a reader can see.**
FILE_HEAD = re.compile(r"^Path\(__file__\)\.resolve\(\)$")
FILE_DIR_HEAD = re.compile(r"^Path\(__file__\)\.resolve\(\)\.parent$")
PARENT = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\.parent$")
PARENTS = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\.parents\[(\d)\]$")
LITERAL = re.compile(r"""^["']([^"']*)["']$""")
ASSIGN = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$")
FILE_MARK = "\0file"        # the file ITSELF, as the last component of a `Path(__file__)`


def expand(parts):
    """-> the components with every `..` folded, or None when it climbs above the root."""
    out = []
    for p in parts:
        if p == "..":
            if not out:
                return None
            out.pop()
        elif p not in (".", ""):
            out.append(p)
    return out


def _part(part, known, own_dir):
    """-> the components ONE part of a path expression contributes, or None."""
    lit = LITERAL.match(part)
    if lit:
        return tuple(c for c in lit.group(1).split("/") if c not in (".", ""))
    if FILE_DIR_HEAD.match(part):
        return tuple(own_dir)
    if FILE_HEAD.match(part):
        return tuple(own_dir) + (FILE_MARK,)
    m = PARENT.match(part)
    if m:
        base = known.get(m.group(1))
        return None if base is None else tuple(base) + ("..",)
    m = PARENTS.match(part)
    if m:
        base = known.get(m.group(1))
        if base is None:
            return None
        # `parents[n]` COUNTS FROM THE DIRECTORY, and the two spellings differ by one -- the
        # off-by-one `gates/gates-pop.py:resolve_root` was written to get right. A base that
        # ends in the FILE mark is a FILE, and `parents[0]` of a file is its own directory.
        if base and base[-1] == FILE_MARK:
            return tuple(base[:-1]) + ("..",) * int(m.group(2))
        return tuple(base) + ("..",) * (int(m.group(2)) + 1)
    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", part):
        return known.get(part)
    return None


def constants(text, own_dir):
    """-> {NAME: components} for the path constants the file assigns, EVALUATED.

    **THE CONSTANTS ARE EVALUATED, NOT GUESSED AT BY NAME.** A name is a path only if the file
    ASSIGNS it a path, and the assignment is evaluated: `HERE = Path(__file__).resolve().parent`
    is this file's own directory, `ROOT = HERE.parent` is one level up, `GATES = ROOT / "gates"`
    is a join of the two. A name the file does not assign is not a path, which is why
    `HERE / "pincensus-pop.py"` resolves and `bend / "x.bend"` does not.

    The assignment list is read at EVERY indentation, because a path constant is sometimes
    local, and it is iterated to a FIXPOINT because a constant may be defined in terms of one
    defined later."""
    raw = []
    for line in text.splitlines():
        m = ASSIGN.match(line)
        if m:
            rhs = m.group(2).split("#")[0].strip()
            if rhs:
                raw.append((m.group(1), rhs))
    known = {}
    for _ in range(6):
        grew = False
        for name, rhs in raw:
            if name in known:
                continue
            parts = [p.strip() for p in re.split(r"[ \t]*/[ \t]*", rhs)]
            acc, ok = None, True
            for p in parts:
                v = _part(p, known, own_dir)
                if v is None:
                    ok = False
                    break
                acc = v if acc is None else acc + v
            if not ok or acc is None:
                continue
            e = expand(acc)
            if e is None:
                continue
            known[name] = tuple(e)
            grew = True
        if not grew:
            break
    return known


# THE FOUR JOIN SPELLINGS ARE ONE RULE, and the bare / bare spelling (`a / b`) is harmless:
# the result matters only when it resolves to a path the tree carries.
JOIN = (
    re.compile(r"""["']([A-Za-z0-9_.\-/]+)["'][ \t]*/[ \t]*["']([A-Za-z0-9_.\-/]+)["']"""),
    re.compile(r"""["']([A-Za-z0-9_.\-/]+)["'][ \t]*/[ \t]*([A-Za-z0-9_.\-]+)"""),
    re.compile(r"""([A-Za-z0-9_.\-]+)[ \t]*/[ \t]*["']([A-Za-z0-9_.\-/]+)["']"""),
    re.compile(r"""([A-Za-z0-9_.\-]+)[ \t]*/[ \t]*([A-Za-z0-9_.\-]+)"""),
)


def path_exprs(line):
    """-> the path expressions in `line`, as component lists.

    **A PATH EXPRESSION IS A JOIN, AND THE SOURCE HAS TO BE NORMALIZED FIRST.** A path is
    spelled `ROOT / "gates" / "edge-runner.py"`, or `ROOT / "checks/differ.py"`, or
    `"bin" / "bend"`. **A reader that takes one token at a time sees three tokens where the
    source means one path**, and the three are indistinguishable from three unrelated words.
    So the source is normalized into single tokens FIRST, and the normalization is a FIXPOINT:
    `ROOT / "a" / "b" / "c"` is three joins deep and one pass does two of them.

    The four spellings are ONE rule, and the bare / bare spelling (`a / b`) is harmless: the
    result matters only when it resolves to a path the tree carries."""
    out = line
    for _ in range(8):
        before = out
        for pat in JOIN:
            out = pat.sub(lambda m: m.group(1) + "/" + m.group(2), out)
        if out == before:
            break
    for m in TOKEN.finditer(out):
        t = m.group(0)
        if t in (".", "..", "-", "/"):
            continue
        comps = [c for c in t.split("/") if c not in (".",)]
        if comps:
            yield comps


def resolve(comps, known):
    """-> (tree path, how) for the path a path expression names, or (None, None).

    **A SCOPE-ANCHORED EXPRESSION AND A REPO-RELATIVE ONE ARE DIFFERENT CLAIMS, AND THE
    DIFFERENCE IS THE ANSWER.** A path expression whose FIRST component is a name the file
    ASSIGNS is resolved THROUGH that constant -- `HERE / "pincensus-pop.py"` is
    `gates/pincensus-pop.py`, and no lexical rule can know that. An expression whose first
    component is not such a name is REPO-RELATIVE, because a command line's relative path is
    relative to the reader's working directory and the reader's working directory is the repo
    root. **A workflow's `python sz.py` is therefore the ROOT's `sz.py`, and not
    `checks/sz.py`** -- which is the difference between a workflow that runs a gate and a
    workflow that runs a script that is not one."""
    if not comps:
        return None, None
    head = comps[0]
    if head in known:
        base = tuple(known[head])
        rest = tuple(c for p in comps[1:] for c in p.split("/") if c not in (".", ""))
        e = expand(base + rest)
        return ("/".join(e), "scope") if e else (None, None)
    e = expand(tuple(c for p in comps for c in p.split("/") if c not in (".",)))
    return ("/".join(e), "relative") if e else (None, None)


def code_lines(path, pin):
    """-> [(lineno, line)] the lines a reader could EXECUTE. Comments and docstrings are out.

    `gates/pincensus-pop.py` owns the rule and is loaded by path. **A YAML FILE IS PROSE TO IT**
    -- `host_of` answers `prose` for anything `ast.parse` rejects -- and a workflow is not
    Python, so a workflow's CODE is its uncommented lines, and the tree's own `cut_comment`
    is what strips them. A workflow that mentions a gate in a COMMENT has not invoked it."""
    text = path.read_text(errors="replace")
    if path.suffix in (".yml", ".yaml"):
        return [(i, pin.cut_comment(l)) for i, l in enumerate(text.splitlines(), 1)]
    host = pin.host_of(text)
    if host == "prose":
        return []
    return pin.code_lines(text, host)


# ---- the census ---------------------------------------------------------------------------
class Census:
    """One measurement of one tree: the population, the roots, the join, the reachability."""

    def __init__(self, **kw):
        self.__dict__.update(kw)

    def line(self):
        return (f"population {len(self.population)}  roots {len(self.roots)}  "
                f"reachable {len(self.reachable)}  unreachable {len(self.unreachable)}  "
                f"named-by-a-root {len(self.root_named)}")


def census(root):
    """-> a `Census` of `root`, or None when the tree cannot be measured."""
    root = Path(root).resolve()
    g, pin, k = instruments(root)
    if g is None or pin is None or k is None:
        return None
    homes, derivation = g.gate_homes(root)
    entries, _libs = g.discover(root)
    population = sorted(str(p.relative_to(root)) for p in entries)
    by_rel = {p: p for p in population}
    tracked = set(g._tree_paths(root)[0])

    # THE ROOTS: the surfaces a FRESH CLONE can execute. A workflow file is tracked and is a
    # root; a `Makefile` at the root is tracked and is a root. `.git/hooks/` is NOT: it is
    # untracked, `git init` writes only `.sample` files, and a fresh clone has no hook that
    # names anything. Its count on THIS machine is reported separately.
    roots = []
    wf = root / ".github" / "workflows"
    if wf.is_dir():
        for dp, _dn, fn in os.walk(wf):
            for f in fn:
                rel = str((Path(dp) / f).relative_to(root))
                if rel in tracked:
                    roots.append(rel)
    for name in ("Makefile", "makefile", "GNUmakefile"):
        if name in tracked and (root / name).is_file():
            roots.append(name)
    roots.sort()

    hooks = root / ".git" / "hooks"
    hook_files, hook_live = [], []
    if hooks.is_dir():
        for dp, _dn, fn in os.walk(hooks):
            for f in fn:
                rel = str((Path(dp) / f).relative_to(root))
                hook_files.append(rel)
                if not f.endswith(".sample"):
                    hook_live.append(rel)
    hook_live.sort()

    # THE JOIN, ONE PASS PER SOURCE. The expensive half of a code-line filter is the tokenize,
    # so a file that names nothing at all is never tokenized: the RAW text is swept for path
    # expressions first, and only a file that named something in prose is resolved precisely.
    #
    # **A GATE NAMING ITSELF IS NOT A NAMING.** `gates/edge-runner.py` mentions its own path in
    # a dozen places, and a self-reference cannot make a gate reachable -- it is a loop, and a
    # loop adds nothing to a closure that starts at the roots.
    #
    # **WHAT THE ROOTS NAME THAT IS NOT A GATE** is collected in the same pass, because the
    # question "does this gate exist?" has a sibling -- "what DOES the workflow run?" -- and
    # the two are not the same list. MEASURED 2026-10-21: `.github/workflows/szdiff.yml` and
    # `test.yml` run `python sz.py`, and the tree's `sz.py` is at the ROOT, not in `checks/` --
    # so the workflow runs the root's script and NO gate, and a join that read the bare name
    # `sz.py` as `checks/sz.py` would have said otherwise.
    named_by = {p: [] for p in population}
    root_nonnames = {r: [] for r in roots}
    sources = list(roots) + population
    for rel in sources:
        path = root / rel
        if not path.is_file():
            continue
        try:
            raw = path.read_text(errors="replace")
        except OSError:
            continue
        own_dir = tuple(c for c in rel.split("/")[:-1] if c)
        known = constants(raw, own_dir)
        rough = set()
        for comps in path_exprs(raw):
            named, _how = resolve(comps, known)
            if named:
                rough.add(named)
        if not rough:
            continue
        for lineno, line in code_lines(path, pin):
            for comps in path_exprs(line):
                named, how = resolve(comps, known)
                if not named or named == rel or named not in tracked:
                    continue
                if named in by_rel:
                    named_by[named].append((rel, lineno, how, line.strip()[:96]))
                elif rel in root_nonnames and named not in root_nonnames[rel]:
                    root_nonnames[rel].append(named)
    # ONE name per (gate, namer) pair: a file that names a gate on nine lines names it once.
    named_by = {p: list({n[0]: n for n in v}.values()) for p, v in named_by.items()}
    root_nonnames = {r: sorted(v) for r, v in root_nonnames.items()}

    # THE CLOSURE, FROM THE ROOTS. A gate named by a gate that nothing runs is UNREACHABLE, and
    # the chains are kept so a reader can see the ends that go nowhere.
    adj = {r: set() for r in roots}
    for gate, namers in named_by.items():
        for namer, _ln, _how, _text in namers:
            adj.setdefault(namer, set()).add(gate)
    depth = {r: 0 for r in roots}
    chain = {r: [r] for r in roots}
    queue = list(roots)
    while queue:
        n = queue.pop(0)
        for m in sorted(adj.get(n, ())):
            if m not in depth:
                depth[m] = depth[n] + 1
                chain[m] = chain[n] + [m]
                queue.append(m)
    reachable = {g for g in population if g in depth}
    root_named = {g for g in population
                  if any(n[0] in depth for n in named_by.get(g, ()))}
    return Census(root=root, homes=homes, derivation=derivation, population=population,
                  roots=roots, hooks=len(hook_files), hooks_live=len(hook_live),
                  hook_live_paths=hook_live, named_by=named_by, adj=adj, depth=depth,
                  chain=chain, reachable=reachable, root_named=root_named,
                  root_nonnames=root_nonnames,
                  unreachable=set(population) - reachable, VERDICT=k.VERDICT)


# ---- the ledger ----------------------------------------------------------------------------
LEDGER_COLUMNS = ["path", "named-by", "chain", "at"]


def read_ledger(path):
    """-> {path: (path, named_by, chain, at)}, or None when the file is absent.

    **THE COLUMN NAMES LIVE IN THE `#` HEADER AND NOT IN A LINE OF THEIR OWN**, and that is a
    FIX, not a style: `gates/edge-cost.rows`'s own reader says so in its own docstring, and
    this file's first version consumed the FIRST DATA ROW as a header -- so the ledger read
    **19 of its own 20 rows**, and the one it dropped was reported as "IMPROVED: became
    reachable and is not in the ledger". **A LEDGER THAT SILENTLY DROPS A ROW IS A LEDGER
    THAT CANNOT BE CHECKED**, and the row it dropped was the one a reader would have checked
    first. Every non-comment line is a row; a row whose arity is wrong is not a row."""
    p = Path(path)
    if not p.is_file():
        return None
    rows = {}
    for line in p.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        f = line.split("\t")
        if len(f) == len(LEDGER_COLUMNS):
            rows[f[0]] = tuple(f)
    return rows


def write_ledger(path, c):
    """WRITE the REACHABLE SET, and PRINT the diff. **A WRITE NAMES ITS PATHS.**

    **THE LEDGER HOLDS THE REACHABLE SET AND NOT THE POPULATION, AND THAT IS A DELIBERATE
    DIFFERENCE FROM `gates/gates-pop.py`'s.** Its ledger mirrors the whole population, and the
    population GROWS as other units add gates, so that file churns. **THE THING THAT CAN SHRINK
    IS THE REACHABLE SET**, so that is what is recorded: a small, reviewable, stable file whose
    every row is a claim that a fresh clone can reach that gate.

    The write is EXPLICIT and it PRINTS what it added and what it dropped, because a write that
    does not name its paths is a write nobody can check. An EMPTY reachable set is REFUSED: a
    ledger that can be emptied is a green that measured nothing, and the next run would compare
    nothing against nothing and pass."""
    if not c.population:
        return None
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    old = read_ledger(path) or {}
    rows = []
    for p in sorted(c.reachable):
        namers = sorted({n[0] for n in c.named_by.get(p, ()) if n[0] in c.depth})
        rows.append((p, ",".join(namers) or "-", " -> ".join(c.chain.get(p, [p])), stamp))
    body = [f"# {Path(path).name} -- GENERATED by `gates/reachability-gate.py --write-ledger`, "
            f"which is its ONLY writer.",
            "# columns: " + ", ".join(LEDGER_COLUMNS),
            "# THE REACHABLE SET: every gate a FRESH CLONE can reach -- named, in a CODE line, by",
            "# something reachable from a ROOT (a tracked workflow file, or a Makefile at the root).",
            "# The chain is the path the naming took, so a reader can see WHY a gate is reachable.",
            "# THE COMPARISON IS OVER THE RECORDED PATHS, because the POPULATION grows as other",
            "# units add gates and that is not a defect: a path the ledger does not hold is NAMED,",
            "# never charged. A recorded path that STOPPED being reachable is RED."]
    body += ["\t".join(r) for r in rows]
    Path(path).write_text("\n".join(body) + "\n")
    new = {r[0]: r for r in rows}
    added = sorted(set(new) - set(old))
    dropped = sorted(set(old) - set(new))
    print(f"LEDGER: {len(rows)} row(s) written to {path} at {stamp}")
    print(f"  added   {len(added)}" + ("" if not added else ": " + ", ".join(added[:20])))
    print(f"  dropped {len(dropped)}" + ("" if not dropped else ": " + ", ".join(dropped[:20])))
    return added, dropped


# ---- the verdict ---------------------------------------------------------------------------
def verdict(c, ledger):
    """-> (rc, charges, notes). The charges are the reasons for a red; the notes are movements
    that are NOT defects, and a note never turns a green red.

    **THE FIVE VERDICTS ARE `gates/gatekit.py`'s** -- 0 PASS, 1 FAIL, 3 REFUSED, 4 SKIP, 5 DEAD
    -- and this file does not re-spell them into a second vocabulary.

    **THE TWO CHARGES, AND WHAT IS NOT ONE.**
      * a gate the ledger records as REACHABLE and that is not any more -- a gate that used to
        be run and is not;
      * the NUMBER of unreachable gates, computed over the RECORDED set: a recorded-reachable
        gate that stopped being reachable is a gate that joined the unreachable, and the count
        is the aggregate of the first charge. **THE LIVE UNREACHABLE COUNT IS NOT CHARGED**, and
        the reason is the tree's own: the POPULATION grows as other units add gates, so the live
        count moves for a reason that is not a defect. It is REPORTED, with its denominator.
    **THE DIRECTION MATTERS.** Fewer reachable is a defect. MORE reachable is an improvement,
    and a gate that goes red when the tree gets BETTER is a gate that gets deleted."""
    charges, notes = [], []
    if not c.roots:
        return REFUSED, ["the root set is EMPTY: no tracked workflow file and no Makefile. "
                         "'no gate is run' and 'all gates are run' would look the same, so this "
                         "is REFUSED and not PASS"], []
    if not c.population:
        return REFUSED, ["the population is EMPTY: the tree carries no gate"], []
    if ledger is None:
        return REFUSED, ["no ledger: there is no baseline to measure a movement against. Write "
                         "one with `--write-ledger`"], []
    if not ledger:
        return REFUSED, ["the ledger is EMPTY: a comparison against no rows measures nothing"], []
    if not c.root_named:
        charges.append("a root exists and names NO gate in a code line: a fresh clone runs "
                       "nothing")
    lost = sorted(p for p in ledger if p in c.population and p not in c.reachable)
    if lost:
        charges.append(f"{len(lost)} recorded-reachable gate(s) are no longer reachable: "
                       + ", ".join(lost[:10]))
    rec = len(ledger)
    still = sum(1 for p in ledger if p in c.population and p in c.reachable)
    if still < rec:
        charges.append(f"the number of unreachable gates moved: {rec - still} of the {rec} "
                       f"recorded reachable gate(s) joined the unreachable ({still} still "
                       f"reachable)")
    gained = sorted(p for p in c.reachable if p not in ledger)
    if gained:
        notes.append(f"IMPROVED: {len(gained)} gate(s) became reachable and are not in the "
                     f"ledger: " + ", ".join(gained[:10]))
    gone = sorted(p for p in ledger if p not in c.population)
    if gone:
        notes.append(f"NOTE: {len(gone)} recorded gate(s) are no longer in the population: "
                     + ", ".join(gone[:10]))
    return (FAIL if charges else PASS), charges, notes


# ---- the trace ------------------------------------------------------------------------------
def trace_rows(path):
    """-> (rows, head) from the edge's committed trace, or (None, None).

    **THE TRACE IS A RECORD, NOT A MEASUREMENT**, and it says so: it is what the edge wrote at
    the HEAD it names. Naming a gate is not running it, and running it is not running it NOW, so
    the trace is reported with the HEAD it was taken at and a FRESH flag, and it is never a
    charge."""
    p = Path(path)
    if not p.is_file():
        return None, None
    rows, head = [], None
    for line in p.read_text().splitlines():
        if line.startswith("#"):
            if "HEAD=" in line:
                head = line.split("HEAD=")[-1].strip()
            continue
        if line.strip():
            rows.append(line.split("\t"))
    return rows, head


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--root", default=str(ROOT), help="the tree to measure")
    ap.add_argument("--ledger", default=str(LEDGER), help="the ledger to read and write")
    ap.add_argument("--trace", default=str(TRACE), help="the edge's committed trace")
    ap.add_argument("--write-ledger", action="store_true", help="re-record the reachable set")
    ap.add_argument("--plant", action="store_true", help="the plant and its control")
    a = ap.parse_args()

    if a.plant:
        plant = load("reach_plant", HERE / "reachability-plant.py")
        if plant is None:
            print("== REFUSED, NOT A VERDICT: gates/reachability-plant.py is gone", file=sys.stderr)
            return REFUSED
        return plant.plants()

    root = Path(a.root).resolve()
    c = census(root)
    if c is None:
        print("== REFUSED, NOT A VERDICT: the tree's own instruments are not here "
              "(gates/gates-pop.py, gates/pincensus-pop.py, gates/gatekit.py)", file=sys.stderr)
        return REFUSED
    if not c.population:
        print("== REFUSED, NOT A VERDICT: the population is empty", file=sys.stderr)
        return REFUSED

    if a.write_ledger:
        if not c.reachable:
            print("== REFUSED, NOT A VERDICT: the reachable set is EMPTY. A ledger that can be "
                  "emptied is a green that measured nothing.\n   The tree has "
                  f"{len(c.population)} gate(s) and a root names none of them, and that is the "
                  "finding, not a baseline.", file=sys.stderr)
            return REFUSED
        write_ledger(a.ledger, c)
        return PASS

    ledger = read_ledger(a.ledger)
    rc, charges, notes = verdict(c, ledger)

    print("REACHABILITY: can a fresh clone run a gate, and is that getting worse?")
    print(f"  {c.line()}")
    print(f"  homes {c.homes}  (derived: {c.derivation['source']})")
    print(f"  roots {len(c.roots)}: " + (", ".join(c.roots) if c.roots else "-"))
    print(f"  .git/hooks: {c.hooks} file(s), {c.hooks_live} non-'.sample' -- a fresh clone has "
          f"none of them, so they are NOT roots")
    print(f"  gates named by a ROOT: {len(c.root_named)} of {len(c.population)}")
    for g in sorted(c.root_named):
        namers = sorted({n[0] for n in c.named_by.get(g, ()) if n[0] in c.depth})
        print(f"    {g:46} <- {', '.join(namers)}")
    print("  what the ROOTS name that is NOT a gate (a workflow that runs a thing outside the "
          "derived gate homes runs no gate):")
    for r, names in sorted(c.root_nonnames.items()):
        if names:
            print(f"    {r:44} -> {', '.join(names[:6])}")
    print("  THE CHAINS (a chain that ends in nothing is a gate nothing runs):")
    for g in sorted(c.depth, key=lambda x: (c.depth[x], x)):
        if g in c.population:
            print(f"    depth {c.depth[g]}  {' -> '.join(c.chain[g])}")
    ends = sorted(g for g in c.population
                  if c.named_by.get(g) and all(n[0] not in c.depth for n in c.named_by[g]))
    print(f"  chains that end in nothing: {len(ends)} of {len(c.population)}")
    for g in ends[:20]:
        namers = sorted({n[0] for n in c.named_by[g]})
        print(f"    {g:46} named only by {', '.join(namers[:3])}")
    if len(ends) > 20:
        print(f"    ... and {len(ends) - 20} more")

    rows, head = trace_rows(a.trace)
    if rows is None:
        print("  TRACE: absent -- nothing has ever run the edge, so 'was this gate ever run?' "
              "still has no answer")
    else:
        ran = [r for r in rows if r[1].startswith("RAN")]
        live = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=str(c.root),
                              capture_output=True, text=True)
        live_head = live.stdout.strip() if live.returncode == 0 else "?"
        anc = subprocess.run(["git", "merge-base", "--is-ancestor", head or "HEAD", "HEAD"],
                              cwd=str(c.root), capture_output=True, text=True)
        fresh = anc.returncode == 0
        print(f"  TRACE {len(rows)} row(s) at HEAD={head} (live HEAD={live_head}); "
              f"{len(ran)} say RAN")
        print(f"  the trace's HEAD is {'an ancestor of' if fresh else 'NOT an ancestor of'} the "
              f"live HEAD, so it describes {'this tree' if fresh else 'a DIFFERENT tree'}")
        print("  THE JOIN says a gate is NAMED; the TRACE says a gate RAN. Naming is not running.")

    for r in charges:
        print(f"  CHARGE: {r}")
    for r in notes:
        print(f"  note: {r}")
    print(f"REACHABILITY: {c.VERDICT.get(rc, 'DEAD')} (exit {rc})")
    return rc


if __name__ == "__main__":
    sys.exit(main())
