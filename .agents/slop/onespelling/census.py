#!/usr/bin/env python3
"""Census of the ONE-SPELLING class: a site that reads ONE spelling of a thing and reports the
result as the whole population.  Four instances were found in one day and they are one shape.

    a delimiter class in a regex  checks/repro-paths.py REF: `(?:^|\\s)` could not see a backticked path
                                  -- RESOLVED at 0895758717, which re-anchored it to `(?<![\\w/.])`
    a BARE BASENAME in prose      `differ.py` is four tracked files
    a single resolution root      .agents/slop/toolsledger/extract.py resolves every token under ROOT
    a MODULE-form call table      checks/sweep.py FS_WRITES, which has a method-form companion

THE DENOMINATOR IS THE RESULT.  A count of "the tree has N of these" means nothing without the
population it was drawn from, so the population is DISCOVERED and COUNTED, never listed: `*.py`
comes from a walk of the committed tree (`git ls-tree -r HEAD`) and the prose corpus is the
committed `*.md` set.  This file names no tracked path it did not find.

AST-SEEING IS THE WHOLE PROBLEM, SO IT IS ASSERTED, NOT ASSUMED.  `ast.Dict` carries `keys`/`values`
and no `elts`; `ast.Set`/`Tuple`/`List` carry `elts` and no `keys`.  An extractor written against the
wrong one either raises or, worse, is taught to skip what it cannot read -- and then skips the whole
table family under study without saying so.  The self-check asserts that every literal spelling
PRESENT in the tree yielded at least one extracted site, that the known positives are found, and
that the known negative is not charged; if any of that fails it exits 3 having written nothing.

VERDICTS are doctrine 2's, and SKIP IS NOT PASS:
  POSITIVE  a second spelling exists in this tree and this site cannot see it
  NEGATIVE  looked, and there is none -- a companion covers it, or nothing reads it
  UNKNOWN   not decidable from the tree; the evidence column says why

THE BLIND SPOT THIS FILE NOW HAS, MEASURED 2026-10-17 at HEAD `08554e409`: `widened()` recognises a
leading `(?:^|...)` and NOTHING else, so a LOOKBEHIND-anchored regex is never a `regex-anchor-set`
candidate.  `checks/repro-paths.py:64` is `(?<![\\w/.])(...)` and therefore yields ZERO rows -- so no
future one-spelling defect in that file can be found by this census, and the self-check CANNOT SEE THAT
IT CANNOT, because a control that asserts a POSITIVE at that path refuses rather than reports the loss.
Widening `widened()` to also match a leading `(?<!...)` is a change to the KIND DEFINITION, not a control
fix, and it needs its own brief.
"""
from __future__ import annotations

import argparse
import ast
import os
import re
import subprocess
import sys
import warnings
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
PROSE_EXT = ".md"  # the corpus this tree writes its claims into, discovered from the committed tree
CONTAINERS = ("set", "frozenset", "dict", "list", "tuple", "sorted")
COMPANION_MIN = 3  # a companion vocabulary is a table of names, not a one-entry special case
# A module-level candidate is an `Assign`/`AnnAssign` whose target is a bare name, and such a line
# begins at column 0 with an identifier and `=` or `:` -- NECESSARY from the grammar, not a guess, so
# dropping the rest cannot hide a candidate.  The count of dropped files is reported, never swallowed.
PARSE_GATE = re.compile(r"^[A-Za-z_]\w*(?:\s*:[^=\n]+)?\s*=[^=]", re.M)
EXTENSION = re.compile(r"^\.[A-Za-z0-9]{1,7}$")
BACKTICK = re.compile(r"`([^`\n]+)`")
TOKEN = re.compile(r"^[\w@+./-]+$")


def git(*args: str, stdin: bytes = b"") -> bytes:
    """git with the default INDEX scrubbed: it is chronically stale, and it is read silently."""
    env = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}
    return subprocess.run(["git", "-C", ROOT, *args], input=stdin,
                          capture_output=True, env=env, check=True).stdout


def committed(ext: str | None = None) -> list[tuple[str, str]]:
    """(path, blob) for the committed tree, filtered by extension.  Asked of HEAD, never the index."""
    out = []
    for line in git("ls-tree", "-r", "HEAD").decode("utf-8", "replace").splitlines():
        meta, path = line.split("\t", 1)
        if ext is None or path.endswith(ext):
            out.append((path, meta.split()[2]))
    return out


def blobs(pairs: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """(path, text) for each blob, through one `git cat-file --batch`."""
    if not pairs:
        return []
    raw = git("cat-file", "--batch", stdin=("\n".join(h for _, h in pairs) + "\n").encode())
    out, i = [], 0
    for path, _ in pairs:
        j = raw.index(b"\n", i)
        size = int(raw[i:j].split()[2])
        out.append((path, raw[j + 1:j + 1 + size].decode("utf-8", "replace")))
        i = j + 1 + size + 1
    return out


# --- extraction ---------------------------------------------------------------------------------

def elements(node: ast.AST) -> tuple[list[ast.expr] | None, str]:
    """The members of a literal container, WHICHEVER SPELLING BUILT IT.  `Dict` stores `keys`;
    `Set`/`Tuple`/`List` store `elts`; `set()`/`dict()`/... wrap another literal.  All of those are
    answered here, because reading a `Dict` with `.elts` is the defect this instrument exists to
    catch and it must not commit the same one."""
    if isinstance(node, ast.Dict):
        return node.keys, "Dict"
    if isinstance(node, (ast.Set, ast.Tuple, ast.List)):
        return node.elts, type(node).__name__
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in CONTAINERS:
        for arg in node.args:
            inner, spelling = elements(arg)
            if inner is not None:
                return inner, f"{node.func.id}({spelling})"
    return None, ""


def members(node: ast.AST) -> tuple[list[str] | None, list[tuple[str, str]] | None, str]:
    """(members as strings, members as (a, b) string pairs, spelling).  Either list is None when the
    members are computed rather than written out, or are neither shape."""
    els, spelling = elements(node)
    if not els:
        return None, None, spelling
    consts = [e.value if isinstance(e, ast.Constant) and isinstance(e.value, str) else None for e in els]
    if all(c is not None for c in consts):
        return consts, None, spelling
    if all(isinstance(e, ast.Tuple) and len(e.elts) == 2 for e in els):
        rows = [[x.value if isinstance(x, ast.Constant) and isinstance(x.value, str) else None
                 for x in e.elts] for e in els]
        if all(all(c is not None for c in row) for row in rows):
            return None, [tuple(row) for row in rows], spelling
    return None, None, spelling


def compiled(node: ast.AST) -> str | None:
    """The source of a module-level `re.compile("...")`."""
    if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name) and node.func.value.id == "re"
            and node.func.attr == "compile" and len(node.args) == 1):
        return None
    src = node.args[0]
    return src.value if isinstance(src, ast.Constant) and isinstance(src.value, str) else None


def target(node: ast.AST) -> str | None:
    if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
        return node.targets[0].id
    if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
        return node.target.id
    return None


def os_dotted(node: ast.AST) -> str | None:
    """`os.chdir` -> `os.chdir`, `os.path.join` -> `os.path.join`, anything else -> None.  `os.path.dirname`
    is an attribute OF an attribute, so `func.value.id == "os"` is false for it: the second spelling of
    the same module is exactly the kind of thing this census must not miss."""
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    return f"os.{'.'.join(reversed(parts))}" if isinstance(node, ast.Name) and node.id == "os" else None


SUFFIX_TESTS = ("endswith", "fnmatch", "fnmatchcase")  # exact tail comparisons: they never truncate


def read_names(tree: ast.AST) -> tuple[Counter, set[str], set[str]]:
    """ONE walk over the module, yielding three things no literal can answer about itself: the names it
    READS; the names it HANDS to a call that takes a path (`os.chdir`, `os.path.join`); and the names it
    HANDS to a call that matches a SUFFIX.  A binding is ctx=Store so it never counts against itself,
    and a COMMENT is not an AST node at all -- which is why `FS_DELETES` scores 0 reads and is
    therefore not a live blind spot."""
    read: Counter = Counter()
    base: set[str] = set()
    suffix: set[str] = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Name):
            if isinstance(n.ctx, ast.Load):
                read[n.id] += 1
        elif isinstance(n, ast.Attribute):
            read[n.attr] += 1
        elif isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute):
            os_name = os_dotted(n.func)
            if os_name in ("os.chdir", "os.path.join"):
                base.update(a.id for a in n.args if isinstance(a, ast.Name))
            elif n.func.attr in SUFFIX_TESTS:
                suffix.update(a.id for a in n.args if isinstance(a, ast.Name))
    return read, base, suffix


def widened(src: str) -> str | None:
    """A leading `(?:^|...)` anchor dropped.  The result matches a strict SUPERSET -- the anchor only
    ever demanded a delimiter in front -- so every match the original makes the widened one makes too,
    and the difference is precisely the spelling the anchor cannot see."""
    m = re.match(r"\(\?:\^\|([^)]*)\)", src)
    return src[m.end():] if m else None


# --- probes -------------------------------------------------------------------------------------

def probe_table(site: dict, siblings: list[dict]) -> tuple[str, str, str]:
    """A (module, attribute) table.  NEGATIVE when nothing reads it, or when a same-file bare-name
    companion SHARES one of its attribute names -- that overlap is the proof the two tables are the two
    spellings of one vocabulary rather than two unrelated lists.  UNKNOWN otherwise, because whether
    `os.remove` has a `Path` spelling needs a subject oracle this instrument does not have, and
    guessing here would be the confident wrong answer."""
    n, reads, attrs = len(site["pairs"]), site["reads"], {a for _, a in site["pairs"]}
    best = max(((len(attrs & set(c["strings"])), c["name"], attrs & set(c["strings"]))
                for c in siblings
                if c["name"] != site["name"] and c["strings"] and len(c["strings"]) >= COMPANION_MIN
                and all("." not in s for s in c["strings"]) and c["reads"]), default=(0, "", set()))
    if reads == 0:
        return "NEGATIVE", "yes", (f"{n} (module, attr) entries, 0 reads: DEAD, and a table nothing reads "
                                   "cannot mislead a reader")
    if best[0]:
        return "NEGATIVE", "yes", (f"{n} (module, attr) entries read {reads}x; {best[1]} is the method-form "
                                   f"companion, sharing {', '.join(sorted(best[2]))}")
    return "UNKNOWN", "?", (f"{n} (module, attr) entries read {reads}x and no bare-name companion shares a "
                            "name with it; whether these operations have a method spelling is not decidable "
                            "from the tree")


ALTERNATION = re.compile(r"\((?:\?::?|\?=|:)?([A-Za-z0-9*?+.\-{}|\\]{2,})\)")
TERMINATORS = ("$", r"\b", r"(?=", r"(?!", r"\Z", r"\W")


def rx_extensions(src: str) -> list[str]:
    r"""The extensions a pattern spells as an ALTERNATION -- `(?:py|sh)` and `(?:\.py|\.sh)` both
    count, `(?:\.agents|slop)` does not.  Harvesting every `\.word` instead charges a directory for
    being one, which is how an instrument becomes a confident wrong answer."""
    out: set[str] = set()
    for m in ALTERNATION.finditer(src):
        branches = [b.strip() for b in m.group(1).split("|")]
        if len(branches) < 2 or not all(re.fullmatch(r"\.?[A-Za-z0-9]{1,7}", b) for b in branches):
            continue
        if src[:m.start()].endswith("\\."):  # the dot is outside the group, so the branches must not carry it
            if not all(not b.startswith(".") and not b.isdigit() for b in branches):
                continue
            out.update(f".{b}" for b in branches)
        elif any(b.startswith(".") for b in branches):
            out.update(b if b.startswith(".") else f".{b}" for b in branches)
    return sorted(out)


def probe_ext(site: dict, tracked_ext: set[str], basenames: list[str]) -> tuple[str, str, str]:
    """One question only: is a REAL tracked filename read by this site as one of its members followed
    by a tail?  A set is never rewritten by `endswith` -- `"x.cpp".endswith(".c")` is False -- so the
    only shape that does it is a pattern, and a pattern is answered by RUNNING it over the tracked
    filenames rather than by reading its source, because `\b` and `["']` terminate an extension and a
    syntactic rule cannot tell them from `|`.  COMPLETENESS, a member the subject needed and the set
    lacks, is out of scope and is UNKNOWN for every row: without the subject a missing `.md` is
    indistinguishable from a deliberate scope."""
    long = sorted(c for c in tracked_ext for e in site["strings"] if c.startswith(e) and len(c) > len(e))
    risk = f"{len(long)} TRACKED extension(s) are longer and start with a member: " + ", ".join(long[:6])
    if site["spelling"] == "re.compile":
        try:
            rx = re.compile(site["extra"]["pattern"])
        except re.error as exc:
            return "UNKNOWN", "?", f"pattern does not compile: {exc}"
        hit = next((b for b in basenames
                    if (m := rx.search(b)) and len(b) > m.end()
                    and any(b[:m.end()].endswith(e) for e in site["strings"])
                    and (b[m.end()].isalnum() or b[m.end()] in "._-")), "")
        if hit:
            return "UNKNOWN", "yes", (f"{len(site['strings'])} extension(s) inside a pattern; applied to "
                                       f"{len(basenames)} tracked filenames it reads {hit} as a member plus "
                                       f"the tail {hit[hit.rindex('.'):]!r}. The second spelling EXISTS; whether "
                                       "reading it is wrong depends on the subject, which the tree does not state")
        return "NEGATIVE", "no", (f"{len(site['strings'])} extension(s) inside a pattern; applied to "
                                  f"{len(basenames)} tracked filenames it reads none of them as a member "
                                  "plus a tail, so none is rewritten")
    if site["suffix_tested"]:
        return "NEGATIVE", "no", (f"{len(site['strings'])} extensions handed to endswith/fnmatch, which compare "
                                  f"the tail exactly, so none of the {len(long)} longer tracked extension(s) is "
                                  "rewritten. A use site that builds a pattern from this set was not excluded")
    return "UNKNOWN", "?", (f"{len(site['strings'])} extensions; {risk}, but the call this set is used at was "
                          "not located, so truncation is unproven")


def probe_regex(site: dict, prose: list[str]) -> tuple[str, str, str]:
    src = site["extra"]["pattern"]
    wide = widened(src)
    if wide is None:
        return "UNKNOWN", "?", "no leading `(?:^|...)` anchor; not a delimiter-set regex"
    try:
        old_re, new_re = re.compile(src), re.compile(wide)
    except re.error as exc:
        return "UNKNOWN", "?", f"pattern does not compile: {exc}"
    old: set[str] = set()
    new: set[str] = set()
    delims: Counter = Counter()
    for text in prose:
        old |= {m.group(1) for m in old_re.finditer(text) if m.groups()}
        for m in new_re.finditer(text):
            if not m.groups():
                continue
            new.add(m.group(1))
            delims["^" if not m.start() else text[m.start() - 1]] += 1
    if len(new) <= len(old):
        return "NEGATIVE", "no", (f"anchored pattern names {len(old)} distinct group-1 matches over "
                                  f"{len(prose)} committed {PROSE_EXT} files; dropping the anchor adds none")
    hist = " ".join(f"{c!r}x{n}" for c, n in delims.most_common(5))
    return "POSITIVE", "yes", (f"over {len(prose)} committed {PROSE_EXT} files: anchored names {len(old)}, "
                               f"anchor dropped names {len(new)}. {len(new) - len(old)} spellings invisible. "
                               f"Preceding delimiter: {hist}")


def probe_base(site: dict, under: set[str], roots: list[str], prose: dict[str, str]) -> tuple[str, str, str]:
    """One base resolves every token.  The test: a token that does NOT resolve under that base, and
    DOES resolve under a root the tree itself contains.  `under` holds every committed path and every
    directory prefix of one, so both questions are set lookups and not a scan per token."""
    corpus = site["extra"].get("corpus", "")
    if corpus not in prose:
        return "UNKNOWN", "?", f"input corpus {corpus!r} is not a committed {PROSE_EXT} file"
    lost = []
    for tok in sorted({t.strip().strip("*_[]()`").rstrip(".,;:)(\"") for t in BACKTICK.findall(prose[corpus])}):
        if "/" not in tok or not TOKEN.match(tok) or tok in under:
            continue
        lost += [(tok, d) for d in roots if f"{d}/{tok}" in under][:1]
    if lost:
        return "POSITIVE", "yes", (f"{site['name']} resolves every token under one base; {len(lost)} of the "
                                   f"'/'-bearing tokens {corpus} writes resolve only under a different root, "
                                   "e.g. " + ", ".join(f"{t} -> {d}/{t}" for t, d in lost[:3]))
    return "NEGATIVE", "no", f"{site['name']}: every '/'-bearing token of {corpus} resolves under this base"


# --- census -------------------------------------------------------------------------------------

def literal_sites(py: list[tuple[str, str]]) -> tuple[list[dict], dict[str, list[dict]], dict]:
    """Every module-level literal and every module-level regex in the committed .py population, each
    with its AST spelling and its read count.  Returns (candidate sites, literals grouped by file,
    stats).  Only a file that yielded a site keeps its group, because the group is read only as
    companion evidence for a site in that same file."""
    sites: list[dict] = []
    by_file: dict[str, list[dict]] = {}
    spellings: Counter = Counter()
    tables: Counter = Counter()
    parsed = dropped = literals = 0
    for path, src in blobs(py):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            if not PARSE_GATE.search(src):
                dropped += 1
                continue
            parsed += 1
            try:
                tree = ast.parse(src)
            except SyntaxError:
                dropped += 1
                continue
        group = []
        imported = imported_modules(tree)
        for node in tree.body:
            name = target(node)
            if name is None:
                continue
            strs, prs, spelling = members(node.value)
            rx = compiled(node.value)
            entry = dict(site=f"{path}:{node.lineno}:{name}", name=name, path=path, kind=None,
                         spelling=spelling or ("re.compile" if rx else ""), strings=strs, pairs=prs,
                         reads=0, suffix_tested=False, extra={})
            if prs and any(m in imported for m, _ in prs):
                entry["kind"] = "module-attr-table"
            elif strs and all(EXTENSION.match(s) for s in strs):
                entry["kind"] = "extension-set"
            elif rx is not None and widened(rx) is not None:
                entry["kind"], entry["extra"]["pattern"] = "regex-anchor-set", rx
            elif rx is not None and (exts := rx_extensions(rx)):
                entry["kind"], entry["strings"] = "extension-set", exts
                entry["extra"]["pattern"] = rx
            elif root_constant(node.value):
                entry["kind"] = "single-base-resolver"
            literals += 1
            group.append(entry)
        # The walk is most of the census, so it runs only where a verdict needs it: a read count, an
        # os-argument census and a suffix-test census are the three things a literal cannot answer.
        if any(e["kind"] in ("module-attr-table", "extension-set", "single-base-resolver") for e in group):
            read, base, suffix = read_names(tree)
            for e in group:
                e["reads"] = read[e["name"]]
                e["suffix_tested"] = e["name"] in suffix
                if e["kind"] == "single-base-resolver":
                    e["extra"]["corpus"] = opens(tree) if e["name"] in base else ""
                    e["kind"] = e["kind"] if e["extra"]["corpus"] else None
        found = [e for e in group if e["kind"]]
        if found:
            sites += found
            by_file[path] = group
        spellings.update(e["spelling"] for e in group if e["spelling"])
        tables.update(e["spelling"] for e in group if e["pairs"])
    return sites, by_file, dict(parsed=parsed, dropped=dropped, literals=literals,
                                spellings=spellings, tables=tables)


def imported_modules(tree: ast.AST) -> set[str]:
    """The modules this file imports.  A `(module, attribute)` table is a table of CALLS only if at
    least one of its modules is one this file could call through -- without that test,
    `PF_DTS = [("uchar", "uint8"), ...]` in `gates/wgsl_render_census-oracle.py` reads as a call table
    and its neighbour `DT` reads as its method-form companion, which is two confident wrong answers
    out of one unexamined shape."""
    names = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            names.update(a.name.split(".")[0] for a in n.names)
        elif isinstance(n, ast.ImportFrom) and n.module:
            names.add(n.module.split(".")[0])
    return names


def root_constant(node: ast.AST) -> bool:
    """A string constant that NAMES A DIRECTORY, or a computed `os.path.dirname`/`abspath` chain --
    the two spellings of a single base, and the defect is having only one of them.  Only a Constant or
    a Call can be either, so everything else is answered without looking inside it: a walk per literal
    is quadratic over the 100k autogen dicts, which hold register names and no paths at all."""
    if isinstance(node, ast.Constant):
        return isinstance(node.value, str) and ("/" in node.value or node.value.startswith(".")) \
               and os.path.isdir(os.path.join(ROOT, node.value))
    if not isinstance(node, ast.Call):
        return False
    return any(isinstance(n, ast.Call) and os_dotted(n.func) in ("os.path.dirname", "os.path.abspath",
                                                                  "os.path.realpath")
               for n in ast.walk(node))


def opens(tree: ast.AST) -> str:
    """The FIRST file this module opens, in SOURCE order: `ast.walk` yields no order, and taking the
    last one would read a module's OUTPUT as its input."""
    hits = [(n.lineno, n.args[0].value) for n in ast.walk(tree)
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == "open"
            and n.args and isinstance(n.args[0], ast.Constant) and isinstance(n.args[0].value, str)]
    return min(hits)[1] if hits else ""


def ambiguous_basenames(prose: list[str], paths: list[str]) -> tuple[dict[str, list[str]], int]:
    """A backticked token with no '/' that several tracked files answer to.  Returns the hits and the
    DENOMINATOR -- every distinct bare basename cited -- so a count of 3 is a count of 3 OF N."""
    by_name: dict[str, list[str]] = {}
    for p in paths:
        by_name.setdefault(os.path.basename(p), []).append(p)
    cited = {t for text in prose for t in BACKTICK.findall(text)
             if "/" not in t and re.fullmatch(r"[\w.+-]*\.[A-Za-z0-9]+", t)}
    hits = {t: sorted(by_name[t]) for t in cited if t in by_name and len(by_name[t]) > 1}
    return hits, len(cited)


def build() -> tuple[list[dict], dict]:
    py, md = committed(".py"), committed(PROSE_EXT)
    prose_list = blobs(md)
    prose = dict(prose_list)
    paths = [p for p, _ in committed()]
    roots = sorted({p.split("/", 1)[0] for p in paths if "/" in p})
    under = {p for p in paths} | {q for p in paths for q in prefixes(p)}
    tracked_ext = {os.path.splitext(p)[1] for p in paths if "." in os.path.basename(p)}
    basenames = sorted({os.path.basename(p) for p in paths})

    sites, by_file, stats = literal_sites(py)
    probe = {"module-attr-table": lambda s: probe_table(s, by_file[s["path"]]),
             "extension-set": lambda s: probe_ext(s, tracked_ext, basenames),
             "regex-anchor-set": lambda s: probe_regex(s, [t for _, t in prose_list]),
             "single-base-resolver": lambda s: probe_base(s, under, roots, prose)}
    rows = []
    for site in sites:
        verdict, found, evidence = probe[site["kind"]](site)
        rows.append(dict(site=site["site"], kind=site["kind"], verdict=verdict,
                         second_spelling_found=found, evidence=evidence, spelling=site["spelling"]))

    hits, cited = ambiguous_basenames([t for _, t in prose_list], paths)
    rows += [dict(site=f"{PROSE_EXT}:{b}", kind="prose-basename-citation", verdict="POSITIVE",
                  second_spelling_found="yes", spelling="backtick token",
                  evidence=f"{len(c)} tracked files share this basename: " + ", ".join(c[:4]))
              for b, c in sorted(hits.items())]
    stats.update(py=len(py), md=len(md), paths=len(paths), sites=len(rows), basenames_cited=cited)
    return rows, stats


def prefixes(path: str) -> list[str]:
    """Every directory prefix of a committed path, so a token naming a DIRECTORY resolves too."""
    return [path[:i] for i, c in enumerate(path) if c == "/"]


# --- self-check ---------------------------------------------------------------------------------

# pos1's path pin died with the defect it named: 0895758717 re-anchored `checks/repro-paths.py:64 REF`
# to `(?<![\w/.])`, and a POSITIVE asserts a defect that EXISTS -- a repaired site has none left to miss.
# `None` asks the population question the control was always for: does this KIND still yield this verdict?
# It still catches a broken `widened()` or an inverted `probe_regex`.  Full argument, with the numbers:
# .agents/slop/onespelling-control/decision.md.
CONTROLS = (
    ("pos1 anchored path regex", "regex-anchor-set", "POSITIVE", None),
    ("pos2 bare basename differ.py", "prose-basename-citation", "POSITIVE", "differ.py"),
    ("pos2 bare basename gatekit.py", "prose-basename-citation", "POSITIVE", "gatekit.py"),
    ("pos2 bare basename extract.py", "prose-basename-citation", "POSITIVE", "extract.py"),
    ("pos3 single base", "single-base-resolver", "POSITIVE", ".agents/slop/toolsledger/extract.py"),
    ("neg live table has companion", "module-attr-table", "NEGATIVE", "checks/sweep.py"),
)


def selfcheck(rows: list[dict], stats: dict) -> list[str]:
    """The control.  Returns its failures; an empty list means the census may be reported."""
    bad = []
    for label, kind, verdict, frag in CONTROLS:
        found = [r for r in rows if r["kind"] == kind and r["verdict"] == verdict
                 and (frag is None or frag in r["site"])]
        if not found:
            bad.append(f"{label}: no {verdict} {kind} site" + (f" matching {frag}" if frag else ""))
    # THE TRAP: FS_DELETES is keyed module-form only, and that is NOT a live blind spot -- nothing
    # reads it, and checks/sweep.py:270-284 says so.  Charging it would be a false charge.
    fd = next((r for r in rows if r["site"].endswith(":FS_DELETES")), None)
    if fd is None:
        bad.append("trap: FS_DELETES was not extracted at all")
    elif fd["verdict"] != "NEGATIVE" or "0 reads" not in fd["evidence"]:
        bad.append(f"trap: FS_DELETES charged {fd['verdict']} without the unread proof: {fd['evidence']}")
    # THE PRIOR FAILURE: an extractor that only reads `.elts` skips every Dict, and a `Dict` carries
    # `keys` while a `Set` carries `elts`.  Assert from the POPULATION, not from a fixture: both
    # families of (a, b) table were read, and both families of literal were read.
    if not stats["tables"].get("Dict"):
        bad.append("ast-spelling: no (a, b) table was read from a Dict literal (`.keys`)")
    if not any(stats["tables"].get(s) for s in ("Set", "List", "Tuple", "frozenset(Set)")):
        bad.append("ast-spelling: no (a, b) table was read from a Set/List/Tuple literal (`.elts`)")
    for want in ("Dict", "Set", "frozenset(Set)"):
        if not stats["spellings"].get(want):
            bad.append(f"ast-spelling: no module-level literal of spelling {want} was read at all")
    if stats["basenames_cited"] == 0:
        bad.append("ast-spelling: zero bare basenames cited, so the basename probe compared nothing")
    return bad


# --- main ---------------------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selfcheck", action="store_true", help="run only the control; exit 3 if it fails")
    ap.add_argument("--rows", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "findings.rows"))
    args = ap.parse_args()

    rows, stats = build()
    print(f"HEAD {git('rev-parse', 'HEAD').decode().strip()}")
    print(f"population : {stats['py']} committed .py, {stats['md']} committed {PROSE_EXT}, "
          f"{stats['paths']} committed paths -- every one from `git ls-tree -r HEAD`")
    print(f"module-level literals examined : {stats['literals']}  (from {stats['parsed']} .py parsed; "
          f"{stats['dropped']} dropped by the column-0 grammar gate)")
    print(f"CANDIDATE SITES : {stats['sites']}   "
          + "  ".join(f"{k}={v}" for k, v in sorted(Counter(r['kind'] for r in rows).items())))
    print(f"bare basenames cited : {stats['basenames_cited']}, ambiguous "
          f"{sum(1 for r in rows if r['kind'] == 'prose-basename-citation')}")
    print("VERDICTS : " + "  ".join(f"{k}={v}" for k, v in sorted(Counter(r["verdict"] for r in rows).items())))

    failures = selfcheck(rows, stats)
    if failures:
        print("SELFCHECK REFUSED -- nothing written:", file=sys.stderr)
        for f in failures:
            print(f"  {f}", file=sys.stderr)
        return 3
    spellings = ", ".join(f"{k}={v}" for k, v in stats["spellings"].most_common())
    print(f"selfcheck : OK -- {len(CONTROLS)} controls, the FS_DELETES trap, and every literal spelling "
          f"read: {spellings}")
    if args.selfcheck:
        return 0
    with open(args.rows, "w") as fh:
        for r in sorted(rows, key=lambda r: (r["kind"], r["site"])):
            fh.write("\t".join([r["site"], r["kind"], r["verdict"], r["second_spelling_found"],
                                r["evidence"].replace("\t", " ")]) + "\n")
    print(f"wrote {args.rows}")
    return 0


if __name__ == "__main__":
    sys.exit(main())