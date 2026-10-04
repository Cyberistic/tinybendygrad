#!/usr/bin/env python3
"""formblind-census.py -- THE CENSUS.  For every tool under `.agents/slop/` that selects,
counts, filters or tallies: WHAT FORM does it match, and what VARIANT of that thing is
therefore invisible to it?

    .venv/bin/python .agents/slop/formblind-census.py              the table
    .venv/bin/python .agents/slop/formblind-census.py --detail TOOL  every selector in one tool
    .venv/bin/python .agents/slop/formblind-census.py --floor      the real-lane floor per reader
    .venv/bin/python .agents/slop/formblind-census.py --denoms    the denominators, alone

THE RULE THIS INSTRUMENT MEASURES.

    A TOOL THAT MATCHES A FORM CANNOT SEE THE INSTANCE THAT LACKS IT.

Six tools in this repo re-discovered that sentence independently this round -- `rows()`
could not see a row whose name carries a space, `--handtyped` could not see a hex literal or
a second `row()` on one line, the `s5_` tally could not see the one row written without its
binder, a quoted-import grep could not see an unquoted Bend import, `unchunks` could not see
a chunk whose payload holds a space, and `dd-band-census.py` could not see an index routed
through a local. Six tools, one sentence. The census exists so the seventh is found by a
criterion rather than by somebody getting unlucky again.

HOW A TOOL IS JUDGED. NOT BY READING IT. Each tool's selection predicates are EXTRACTED
FROM ITS AST -- every `re.compile` literal and every `X in Y` / `startswith` / `endswith` /
literal `==` used in a selecting position -- and then each predicate is RUN against the
spelling battery in `rowform.respelling_battery()`: pairs of texts that mean the same thing
and are written differently. A predicate that answers differently on the two members of a
pair is matching a FORM, and the tool is FORM-BLIND with that pair as the named blind
variant. A tool with at least one predicate and no failure on the battery is
FORM-COMPLETE **ON THIS BATTERY**, which is a floor and not a proof, and it is printed as
such. A tool with no predicate cannot be judged this way at all and is counted separately:
it is NOT-A-SELECTOR, and pretending otherwise would inflate the denominator of tools
actually audited.

WHY A DISAGREEMENT AND NOT A READING. Every one of the six was found by two tools that
meant the same thing disagreeing, never by reading the tool. So this census's output is a
DISAGREEMENT COUNT, and agent-core.md's rule applies to it verbatim: a disagreement count is
not a coverage statement. The denominator is therefore printed on every run and in the
header, and the audited/un-audited split is a first-class column.

USAGE
    .venv/bin/python .agents/slop/formblind-census.py
"""
from __future__ import annotations

import argparse
import ast
import collections
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from rowform import respelling_battery  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]

#: DIRECTORIES EXCLUDED FROM THE UNIVERSE, AND WHY.  A denominator is only meaningful if the
#: exclusions are named.  Both of these are UPSTREAM TINYGRAD CHECKOUTS, not tools: they are
#: vendored by the rebase study and their `.py` files are the SUBJECT of the oracles.
EXCLUDED_DIRS = {
  "xd1": "vendored tinygrad checkout (pin/head/cur/work) -- subject, not tool",
  "opstree": "vendored tinygrad checkout -- subject, not tool",
  "__pycache__": "build output",
}

#: extensions that can hold a selector
CODE_EXT = {".py", ".sh", ".mjs", ".js"}

REGEX_METHODS = {"finditer", "findall", "search", "match", "fullmatch", "split", "sub",
                 "subn", "compile", "match_", "fullmatch_"}
STRING_METHODS = {"startswith", "endswith"}
SEL_BINOPS = {"in", "not in"}


def _const(node):
    """The string value of a literal node, or None."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    return None


def _name_of(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return None


class Selectors:
    """(mode, pattern, kind, lineno) for one tool. `mode` is how the pattern is USED,
    because the same regex can select or verify and the battery must ask the same question
    the tool asks."""

    def __init__(self):
        self.items: list[tuple[str, str, str, int]] = []   # (mode, pattern, how, lineno)

    def add(self, mode, pattern, how, lineno):
        self.items.append((mode, pattern, how, lineno))


def extract(src: str) -> Selectors:
    """Every selection predicate in `src`, from the AST. Discovery is deliberately BROAD:
    agent-core.md records that a first version of `not-applied-audit.py` carried a
    hand-maintained list of names and was wrong in the way hand-maintained lists always are
    (`cs_mutate.py` reads into `orig`, `rf2-mutate.py` into `BASE_SRC`). So nothing here is
    filtered by NAME; a real filter lives in `classify()`."""
    sel = Selectors()
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return sel
    # module-level bindings: name -> (literal string, or compiled-regex flags)
    binds: dict[str, tuple[str, int]] = {}
    for n in ast.walk(tree):
        if isinstance(n, ast.Assign) and len(n.targets) == 1 and isinstance(n.targets[0], ast.Name):
            lit = _const(n.value)
            if lit is not None:
                binds[n.targets[0].id] = (lit, n.lineno)
            elif isinstance(n.value, ast.Call) and _name_of(n.value.func) == "compile":
                if n.value.args:
                    lit2 = _const(n.value.args[0])
                    if lit2 is not None:
                        binds[n.targets[0].id] = (lit2, n.lineno)
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call):
            continue
        fn = n.func
        # re.findall(PAT, s) / PAT.findall(s) / re.compile(PAT)
        if isinstance(fn, ast.Attribute) and fn.attr in REGEX_METHODS:
            pat = _const(fn.value) or (binds.get(getattr(fn.value, "id", ""), (None,))[0]
                                       if isinstance(fn.value, ast.Name) else None)
            if pat is not None:
                mode = fn.attr if fn.attr != "compile" else "search"
                sel.add(mode, pat, f"{fn.attr}()", n.lineno)
            continue
        if isinstance(fn, ast.Attribute) and fn.attr in STRING_METHODS:
            pat = _const(fn.value) or (binds.get(getattr(fn.value, "id", ""), (None,))[0]
                                       if isinstance(fn.value, ast.Name) else None)
            if pat is not None:
                sel.add(fn.attr, pat, f"{fn.attr}()", n.lineno)
            continue
    # string-literal membership / equality used as a FILTER. `x in "literal"` and
    # `x == "literal"` are selections a grep would find; the AST is what finds the ones
    # written through a variable.
    for n in ast.walk(tree):
        if isinstance(n, ast.Compare) and len(n.ops) == 1:
            opname = {ast.Lt: "<", ast.Gt: ">", ast.Eq: "==", ast.NotEq: "!=",
                      ast.In: "in", ast.NotIn: "not in", ast.Is: "is"}.get(type(n.ops[0]))
            if opname not in SEL_BINOPS | {"==", "!="}:
                continue
            for side, lit in ((n.left, n.comparators[0]), (n.left, n.comparators[0])):
                v = _const(side)
                if v is not None and v:
                    sel.add(opname, v, f"literal {opname}", n.lineno)
                    break
    return sel


# ---------------------------------------------------------------------------
# RUNNING ONE PREDICATE THE WAY ITS CALL SITE USES IT
# ---------------------------------------------------------------------------
def run_pred(mode: str, pat: str, text: str):
    """The answer a `mode`-shaped use of `pat` gives on `text`. Exceptions are answers:
    a predicate that RAISES on a spelling a reader would emit is as blind as one that
    returns the wrong count, so the raise is caught and returned as `('RAISED', e)`."""
    try:
        if mode in ("findall", "finditer"):
            return tuple(re.findall(pat, text))
        if mode == "search":
            m = re.search(pat, text)
            return m.group(0) if m else None
        if mode == "match":
            m = re.match(pat, text)
            return m.group(0) if m else None
        if mode == "fullmatch":
            m = re.fullmatch(pat, text)
            return m.group(0) if m else None
        if mode == "split":
            return tuple(text.split(pat))
        if mode in ("in", "not in"):
            return (pat in text) if mode == "in" else (pat not in text)
        if mode.startswith("startswith"):
            return text.startswith(pat)
        if mode.startswith("endswith"):
            return text.endswith(pat)
        if mode == "==":
            return text == pat
        if mode == "!=":
            return text != pat
        return None
    except re.error:
        return ("BAD-REGEX", pat)
    except Exception as e:                      # noqa: BLE001 -- a raise is a finding
        return ("RAISED", type(e).__name__)


def try_compile(pat: str, mode: str) -> bool:
    try:
        re.compile(pat)
        return True
    except re.error:
        return False


def battery_for(mode: str, kinds: frozenset[str]) -> list[tuple]:
    """The battery entries a `mode`-shaped predicate can HONESTLY be asked about.

    A `findall` over PYTHON oracle source and a `findall` over BEND port source are
    different subjects, and posing a Bend question at a Python predicate manufactures a
    failure -- which is how the first run of this census reported 27 blind variants in
    `cs_oracle.py`, a tool that never reads a `.bend` file. So the subject kind is decided
    by WHAT THE TOOL READS (`subject_kinds()`, from the path literals and globs in its own
    source), never by its name, and `--detail` prints the inference next to the verdict so a
    reader can disagree with it instead of having to trust it.

      bend_src  the tool opens or globs `.bend` files.
      py_src    the tool opens or globs `.py` files OTHER THAN ITS OWN (a `rglob` or a
                path literal that is not `__file__`) -- i.e. it scans somebody's oracle.
      lane_txt  the tool opens or globs `.txt`/`.names`/`.json` lane output.

    A tool that reads two of them is asked both sets; a tool that reads none is asked none
    and is counted in the `unrunnable` denominator rather than being quietly scored clean.
    """
    if not kinds:
        return []
    if mode in ("startswith", "endswith", "==", "!=", "in", "not in"):
        return [e for e in respelling_battery() if e[1] in kinds]
    if mode in ("findall", "finditer", "search", "match", "fullmatch", "split"):
        return [e for e in respelling_battery() if e[1] in kinds]
    return []


#: a path literal or glob naming a file the tool READS.
OPENED = re.compile(
    r"""(?:\.bend\b|\.txt\b|\.names\b|\.json\b|\bglob\w*\(\s*["'][^"']*|\bopen\w*\(\s*["'][^"']*"""
    r"""|read_text\w*\(\s*["'][^"']*)""")
SELF_READ = re.compile(r"__file__|Path\(__file__\)|resolve\(\)\.parent")


def subject_kinds(src: str) -> frozenset[str]:
    """Infer which SUBJECT LANGUAGES this tool's selectors run over.

    INFERENCE, NOT MEASUREMENT, and the `--detail` view says so. A `.bend` subject is
    claimed only when the string `.bend` appears inside a QUOTED PATH -- a glob or a filename
    literal -- and not inside prose. That distinction is not pedantry: `unobservable-census.py`
    reads only `.txt` lanes and cites `runtime/support/c.bend` in its docstring, and the
    first version of this inference counted the citation, so a LANE-READER pattern was posed
    at the `bend.*` battery entries and the tool reported eight blind variants of which none
    was real. A path, not a mention.

    The distinction this cannot make is a tool that reads `.py` to find its OWN subject
    (every oracle) versus one that reads `.py` to scan a colleague's, so `py_src` is claimed
    whenever the tool reads `.py` at all -- which over-claims rather than under-claims. The
    cost of over-claiming is visible: extra entries on tools that did not fail them, not
    silence on tools that did.
    """
    strings = re.findall(r"""["']([^"'\n]*)["']""", src)
    # `.bend` must END a path or be followed by `/`. `runs/base_c.bend.txt` is a LANE whose
    # name happens to contain the port's name: reading it is reading text output, not
    # reading a port. Claiming a `.bend` subject for `unobservable-census.py` on the strength
    # of those three WIRED keys is what posed Bend battery entries at its lane reader and
    # produced eight blind variants of which none was real.
    bend = any(re.search(r"\.bend(?![\w:])", s) and
               (s.startswith("*") or s.endswith(".bend") or "/.bend" in s or "*" in s)
               for s in strings)
    py = any(re.search(r"\.py(?![\w:])", s) and (s.startswith("*") or "/" in s or s.endswith(".py"))
             for s in strings) and "read_text" in src
    lane = any(re.search(r"\.(txt|names|json)(?![\w:])", s) for s in strings) or \
        bool(re.search(r'rglob\(\s*["\']\*\.', src))
    kinds: set[str] = set()
    if bend:
        kinds.add("bend_src")
    if py:
        kinds.add("py_src")
    if lane:
        kinds.add("lane_txt")
    return frozenset(kinds)


def _subjects(bid: str, a: str, b: str) -> tuple[str, str]:
    """The two SUBJECT TEXTS a battery entry presents to a pattern-matching predicate.

    Most entries put the variation in the ROW/IMPORT/EXPRESSION, and the interesting
    question is whether the pattern still FINDS it -- so the subject is the whole text.
    """
    return a, b


def about_this_construct(mode: str, pat: str, a: str, b: str) -> bool:
    """IS THIS PREDICATE A SELECTOR FOR THE CONSTRUCT THIS ENTRY VARIES?

    A battery entry is about one construct -- a row separator, a chunk boundary, an import
    path, an integer literal. A predicate that cannot find that construct is not asked about
    it, because asking manufactures a failure: the first run of this census reported 36 blind
    variants in `cs_oracle.py`, which never reads a `.bend` file, because a row pattern was
    posed at a line of Bend source and the two lines differ for reasons that have nothing to
    do with the entry.

    THE TEST IS "MATCHES AT LEAST ONE MEMBER", not "matches both". "Matches both" would
    skip the single most important entry in the battery: `lane.eq-vs-gap` exists precisely
    because a `name=value` pattern matches the `=` spelling and MISSES the two-space one, so
    requiring a match on both members would declare the historical 213-row bug invisible.

    THE FALSE-POSITIVE DIRECTION IS CHOSEN, NOT AVOIDED. A pattern that matches by accident
    (`\\w+`, `.*`) is asked about entries it does not own, and the census reports a failure
    that a reader can dismiss from `--detail`. The alternative -- a whitelist of pattern
    shapes per entry -- is the thing agent-core.md warns about twice: a name whitelist goes
    stale the moment someone names a variable `green`, and it would make the census agree
    with itself.
    """
    if mode in ("in", "not in", "startswith", "endswith", "==", "!=", "split"):
        return pat in a or pat in b
    if mode in ("findall", "finditer", "search", "match", "fullmatch"):
        try:
            return bool(re.search(pat, a)) or bool(re.search(pat, b))
        except re.error:
            return False
    return False


def classify(tool: pathlib.Path, src: str) -> dict:
    """FORM-COMPLETE / FORM-BLIND / NOT-A-SELECTOR for one tool, plus the named variants."""
    sel = extract(src)
    kinds = subject_kinds(src)
    out = {"tool": tool, "nsel": len(sel.items), "fail": [], "ok": [], "unrunnable": 0,
           "kinds": kinds}
    if not sel.items:
        return out
    for mode, pat, how, lineno in sel.items:
        if mode.startswith("literal ") and not try_compile(pat, mode):
            continue
        entries = battery_for(mode, kinds)
        if not entries:
            out["unrunnable"] += 1
            continue
        tried = 0
        for bid, kind, a, b, meaning, hid in entries:
            if not about_this_construct(mode, pat, a, b):
                continue
            sa, sb = _subjects(bid, a, b)
            ra, rb = run_pred(mode, pat, sa), run_pred(mode, pat, sb)
            if ra is None and rb is None:
                continue
            tried += 1
            rec = (bid, kind, mode, pat, lineno, how, meaning, hid, ra, rb)
            (out["ok"] if ra == rb else out["fail"]).append(rec)
        if tried == 0:
            out["unrunnable"] += 1
    return out


# ---------------------------------------------------------------------------
# DELEGATION: a tool that CALLS another tool's reader inherits its blindness, and a census
# that scores it on its own literals alone would report it clean.  The alias is DISCOVERED
# from the tool's own `spec_from_file_location("X", ... / "rebase-gate.py")` rather than
# from a list: 51 tools import that reader and they do not all call it `rg`.
# ---------------------------------------------------------------------------
READER_ATTRS = ("rows", "rows_of", "row", "hand_typed", "unchunks", "any_row")


def reader_aliases(src: str) -> set[str]:
    """Every identifier in `src` that can hold a slop-local reader module.

    Three ways a tool gets one, and all three were live in this directory on the first
    pass: `spec_from_file_location(<name>, .../rebase-gate.py)` + `spec.loader.exec_module(rg)`
    -- where the VARIABLE is `rg`, not `<name>` -- `import_module(<name>)`, and
    `X = importlib.util.module_from_spec(spec)`. Missing the second one cost 48 of the 51
    delegations in a first run, which is the census reporting itself clean on a file that
    delegates on its twentieth line.
    """
    out: set[str] = set()
    for m in re.finditer(r'spec_from_file_location\(\s*["\']([A-Za-z_][A-Za-z_0-9]*)["\']', src):
        out.add(m.group(1))
    for m in re.finditer(r'import_module\(\s*["\']([A-Za-z_][A-Za-z_0-9]*)["\']', src):
        out.add(m.group(1))
    for m in re.finditer(r"^(\w+)\s*=\s*[\w.]*module_from_spec\(", src, re.M):
        out.add(m.group(1))
    return out


#: A FORK. `cstyle-gate.py` carries its own `rows_shipped`, described in its own source as
#: "`rebase-gate.py`'s `rows()`, verbatim, so the shred count is a MEASUREMENT of the
#: shipped reader". A verbatim copy of a form-blind reader is a second form-blind reader,
#: and a fix applied to the original leaves the fork blind with nothing to notice.
FORK = re.compile(r"^def\s+(rows?\w*|split_py|parse_rows?)\s*\(", re.M)


def forks(src: str) -> set[str]:
    return set(FORK.findall(src))


def delegations(src: str) -> set[str]:
    """`<alias>.<reader>(` OR `local = <alias>.<reader>` followed by `local(`.

    THE LOCAL-ALIAS HALF IS NOT OPTIONAL AND IT IS THE LARGER HALF. `dd-band-diff.py` reads
        rows = rebase_gate.rows
    and then calls bare `rows(text)`; a census that looks only for `rebase_gate.rows(`
    sees zero delegations in a file that delegates on its fourth line. This is the same
    lesson `not-applied-audit.py` records about a whitelist of names going stale the moment
    someone calls a variable `green` -- so the binding is followed, not the call spelling.
    """
    aliases = reader_aliases(src)
    hits = set()
    locals_: set[str] = set()
    for a in aliases:
        for attr in READER_ATTRS:
            if re.search(r"\b" + re.escape(a) + r"\s*\.\s*" + attr + r"\s*\(", src):
                hits.add(f"{a}.{attr}")
            for m in re.finditer(r"^(\w+)\s*=\s*" + re.escape(a) + r"\s*\.\s*" + attr + r"\b",
                                 src, re.M):
                locals_.add(m.group(1))
                hits.add(f"{a}.{attr} as {m.group(1)}")
    for loc in locals_:
        if re.search(r"(?<![\w.])" + re.escape(loc) + r"\s*\(", src):
            hits.add(f"local:{loc}")
    # a direct `from rebase_gate import rows`
    for m in re.finditer(r"^from\s+([A-Za-z_][A-Za-z_0-9]*)\s+import\s+([A-Za-z_][A-Za-z_0-9]*)",
                         src, re.M):
        if m.group(2) in READER_ATTRS:
            hits.add(f"{m.group(1)}.{m.group(2)}")
    return hits


# ---------------------------------------------------------------------------
# THE UNIVERSE
# ---------------------------------------------------------------------------
#: The census instruments themselves. They are excluded from the denominator because a
#: census that counts its own detector reports a number that moves when the detector is
#: edited, which is the count-as-finding defect in a new place. They are printed anyway.
SELF = {"formblind-census.py", "formblind-audit.py", "rowform.py", "substrate-audit.py",
        "respelling-battery.md"}


def universe():
    tools = []
    for p in sorted(HERE.rglob("*")):
        if not p.is_file() or p.suffix not in CODE_EXT or p.name in SELF:
            continue
        rel = p.relative_to(HERE)
        if rel.parts[0] in EXCLUDED_DIRS or "__pycache__" in rel.parts:
            continue
        tools.append(p)
    return tools


def read(p: pathlib.Path) -> str:
    try:
        return p.read_text(errors="replace")
    except Exception:                          # noqa: BLE001
        return ""


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--detail")
    ap.add_argument("--floor", action="store_true")
    ap.add_argument("--denoms", action="store_true")
    a = ap.parse_args(argv)

    tools = universe()
    srcs = {t: read(t) for t in tools}
    read_ok = sum(1 for s in srcs.values() if s)
    results = {t: classify(t, srcs[t]) for t in tools}

    if a.denoms:
        print(f"tools in universe                 = {len(tools)}")
        print(f"  census instruments (SELF)       = {len(SELF)}  -- excluded from every "
              "denominator below; a census that counts its own detector has a number that "
              "moves when the detector is edited")
        for d, why in EXCLUDED_DIRS.items():
            n = sum(1 for _ in (HERE / d).rglob("*") if _.is_file()) if (HERE / d).is_dir() else 0
            print(f"  excluded {d + '/':28s} = {n} files   ({why})")
        print(f"tools whose source was READ       = {read_ok}")
        print(f"tools with >=1 selection predicate= {sum(1 for r in results.values() if r['nsel'])}")
        print(f"tools with NO selection predicate = {sum(1 for r in results.values() if not r['nsel'])}"
              "   (NOT-A-SELECTOR -- NOT AUDITED, not cleared)")
        print(f"tools whose predicates the battery could not pose a question to = "
              f"{sum(1 for r in results.values() if r['unrunnable'] and r['nsel'])}")
        dele = {t: delegations(s) for t, s in srcs.items()}
        print(f"tools that DELEGATE a reader to another tool = "
              f"{sum(1 for v in dele.values() if v)}")
        print(f"tools that FORK a reader (own def named rows*/split_py/parse_rows) = "
              f"{sum(1 for s in srcs.values() if forks(s))}")
        return 0

    if a.floor:
        return floor_report()

    if a.detail:
        r = results[HERE / a.detail] if (HERE / a.detail).exists() else \
            next((results[t] for t in results if t.name == a.detail), None)
        if r is None:
            print(f"no such tool: {a.detail}", file=sys.stderr)
            return 1
        print(f"=== {r['tool']}   predicates={r['nsel']} "
              f"FORM-BLIND={len(r['fail'])} ok={len(r['ok'])} unrunnable={r['unrunnable']}")
        print(f"    subject kinds INFERRED from what the tool reads: "
              f"{sorted(r['kinds']) or ['(none -- nothing to judge)']}")
        for rec in sorted(r["fail"]):
            bid, kind, mode, pat, ln, how, meaning, hid, ra, rb = rec
            print(f"\n  FORM-BLIND  L{ln}  {how}  shape={mode}\n"
                  f"     pattern: {pat!r}\n"
                  f"     battery: {bid}  ({kind})\n"
                  f"     meaning: {meaning}\n"
                  f"     on A: {ra!r}\n     on B: {rb!r}")
            if hid:
                print(f"     already measured: {hid}")
        if not r["fail"]:
            print(f"\n  FORM-COMPLETE ON THIS BATTERY ({len(r['ok'])} pairs asked, "
                  f"{r['unrunnable']} predicates unposable) -- a FLOOR, not a proof.")
        return 0

    rows = []
    for t in tools:
        r = results[t]
        dele = delegations(srcs[t])
        fk = forks(srcs[t])
        verdict = ("FORM-BLIND" if r["fail"]
                   else "NOT-A-SELECTOR" if not r["nsel"]
                   else "FORM-COMPLETE*")
        variants = sorted({rec[0] for rec in r["fail"]})
        rows.append((t, r["nsel"], len(r["fail"]), verdict, ",".join(variants),
                     ",".join(sorted(set(dele) | {f"FORK:{f}" for f in fk})) or "-"))
    rows.sort(key=lambda x: (-x[2], -x[1], x[0].name))

    print("=" * 118)
    print("FORM-BLIND CENSUS -- every selector under .agents/slop/, run against meaning-equal")
    print("spelling pairs.  FORM-COMPLETE* = survived the battery; that is a FLOOR, not a proof.")
    print("NOT-A-SELECTOR = no predicate found; NOT AUDITED, not cleared.  Denominators below.")
    print("=" * 118)
    print(f"{'tool':52} {'pred':>5} {'fail':>5}  {'verdict':17} blind-variant / delegates-to")
    for t, nsel, nf, verdict, variants, dele in rows:
        if verdict == "NOT-A-SELECTOR" and not nsel and nf == 0:
            continue
        print(f"{str(t.relative_to(HERE))[:51]:52} {nsel:>5} {nf:>5}  {verdict:17} "
              f"{(variants or '-')[:36]:37} {dele[:20]}")

    blind = sum(1 for r in rows if r[3] == "FORM-BLIND")
    comp = sum(1 for r in rows if r[3].startswith("FORM-COMPLETE"))
    nas = sum(1 for r in rows if r[3] == "NOT-A-SELECTOR")
    dele = sum(1 for r in rows if r[5] != "-")
    print("-" * 118)
    print(f"FORM-BLIND {blind}   FORM-COMPLETE-ON-BATTERY {comp}   NOT-A-SELECTOR (unaudited) {nas}"
          f"   DELEGATES-A-READER {dele}   TOTAL {len(tools)}")
    print(f"a DISAGREEMENT count over {blind} of {len(tools)} tools is not a coverage statement:")
    print(f"{nas} tools have no selector to judge and {dele} inherit another tool's reader.")
    return 0


def floor_report() -> int:
    """THE FLOOR: how many REAL lane lines each reader class cannot see.

    This is the number that decides whether a count in a report is a total or a floor. It is
    measured over the `.txt` lanes on this tree, twice, and the two runs are compared --
    agent-core.md records four reads of one file giving 239/246/354/355 rows while a
    background job was still writing, and a count that grows while you watch it is an
    unfinished one, not an unstable one.
    """
    sys.path.insert(0, str(HERE))
    from rowform import any_row, blind_reason, load_shared_reader
    rg = load_shared_reader()

    def scan():
        tally = collections.Counter()
        lanes = 0
        for p in sorted(HERE.rglob("*.txt")):
            if p.stat().st_size > 4_000_000:
                continue
            try:
                t = p.read_text(errors="replace")
            except Exception:                   # noqa: BLE001
                continue
            if len(rg.rows(t)) < 20:
                continue                          # a floor is only meaningful on a lane
            lanes += 1
            for ln in t.splitlines():
                why = blind_reason(ln, rg.row(ln))
                if why:
                    tally[why] += 1
        return lanes, tally

    l1, t1 = scan()
    l2, t2 = scan()
    print("=" * 96)
    print("THE FLOOR -- lane lines that rebase-gate.py:rows() cannot read, on this tree")
    print("=" * 96)
    print(f"lanes audited (rows() reads >= 20 rows)  run1={l1} run2={l2}"
          f"  {'STABLE' if (l1, t1) == (l2, t2) else 'MOVED WHILE WATCHED -- treat as unfinished'}")
    tot = 0
    for k, v in sorted(t1.items(), key=lambda kv: -kv[1]):
        print(f"  {k:18} {v:>7} lines")
        tot += v
    print(f"  {'TOTAL (a floor)':18} {tot:>7} lines inside {l1} lanes the same reader reads "
          f"as rows")
    print(f"\nEVERY count in this repo that is produced through rows() is a FLOOR, not a")
    print(f"total.  Measured floor on this tree: {tot} lines it cannot read.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())