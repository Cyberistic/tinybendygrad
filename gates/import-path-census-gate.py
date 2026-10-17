"""GATE on `.bend` IMPORT PATHS: every import must name a file that EXISTS **AND IS THE ONE THE
SOURCE MEANS**.

    .venv/bin/python gates/import-path-census-gate.py                # the census
    .venv/bin/python gates/import-path-census-gate.py --rows PATH    # the rows artifact
    .venv/bin/python gates/import-path-census-gate.py --plant        # plant, then census
    .venv/bin/python gates/import-path-census-gate.py --bend         # ALSO run bin/bend

**WHAT THIS IS FOR, MEASURED.** Six copies of one file -- `tinybendygrad/test/dtype_oracle.bend`
and five copies of it under `oracles/` -- were BYTE-IDENTICAL in `HEAD`, all at sha256
`f8ddaeceee7e0852`, and they carried OPPOSITE VERDICTS: the port's copy was WARM, the five
`oracles/` copies were COLD. A compile check that HASHES its input cannot see this. **ONLY THE PATH
CAN**, and no per-file compile gate looked at a path: `checks/compile-census.py:judge()` reads
bend's FIRST LINE and stops there.

    oracles/dtype_oracle.bend:12              import ../dtype.bend -> <repo>/dtype.bend  MISSING
    tinybendygrad/test/dtype_oracle.bend:12   import ../dtype.bend -> tinybendygrad/dtype.bend  OK

Same bytes, one level too shallow. **THAT WAS ONE FACT FIVE TIMES**, so a count of FILES overstated
the population by 4x and every number below is printed as `SITES` and `FILES` separately, because
conflating them is how `checks/sweep.py`'s removed `LIVE_UNITS` came to own 53% of a tree.

**AND THE FIX IS PROOF THAT THE PATH WAS THE ONLY DIFFERENCE.** After the import lines were
rewritten to each file's own depth, the five copies are no longer one file: `oracles/ddcheck/tree/
test/` and `oracles/render-wt/tinybendygrad/test/` are both at depth 4 and are byte-identical to
EACH OTHER at `23adacc37f023809`, and `oracles/proof-close/MUTANT{,2}/` are both at depth 5 and are
byte-identical to EACH OTHER at `73a9d77b4af07bba`. **Equal depth, equal bytes. Nothing else in the
file differed and hashing could not see it.**

**THE POPULATION IS DISCOVERED, LOADED BY PATH, AND IS NOT A LIST.** `checks/compile-census.py`
derives its population by importing `checks/substrate.py` and subtracting `substrate.POP_ROOT` from
an `os.walk(".")`, and `checks/compile-census.py:SKIP_DIRS` is where the exclusions live. All three
are READ OFF THOSE FILES, and the port is ADDED by asking `checks/substrate.py:discover(POP_ROOT)`
rather than being named. `AGENTS.md` doctrine 1: "Never list in this file what an instrument
discovers." **MEASURED, THE COST OF GETTING THIS WRONG IS ALREADY IN THIS TREE'S ROWS**:
`checks/compile-census.rows` line 1 says `the 87 .bend` and `discover()` hands **91**. The four that
account for the difference -- `gates/axisflip.bend`, `gates/groupflip.bend`,
`gates/mxgraph-fixture-rows.bend`, `gates/specreach.bend` -- are ALL IN `HEAD` (MEASURED:
`git cat-file -e HEAD:<each>`), so that header UNDER-COUNTS rather than the population having grown
since, and a reader who quoted it as the current population would be quoting a stale number for a
reason that has nothing to do with time. This gate prints the count it got.

**THE CHECK IS NOT "IS THE PATH CLEAN".** An import that resolves to an existing file the source
did not mean is EQUALLY invisible to hashing -- that is `MISDIRECTED` below, and it is the class a
"does it exist" check cannot see. `checks/c-context.bend:23` imports
`"../tinybendygrad/runtime/sz.c"`, which resolves, and the file is COLD **BY DESIGN**: a `bend`
driver for the C backend MUST import a `.c`, and `--check-only` answers `3 defs rely on unsafe or
foreign code`. **A GATE THAT TREATES `COLD` AS A VERDICT WILL DEMAND THE FIXING OF A CORRECT FILE**,
so this gate never asks bend at all unless `--bend` is passed, and a COLD file with no defective
import is never a path finding.

**THE SIX CLASSES, AND THE BOUNDARY BETWEEN "WRONG PATH" AND "WRONG CODE" IS DRAWN HERE.** A file is
`PATH` iff it has >=1 import site in `DEFECTIVE`. Everything else is not a path question at all. This
gate does not adjudicate whether a `CODE` coldness is anybody's fault -- it counts and names them.

    RESOLVED            the specifier names an existing file, and it is the one the source means
    RESOLVED-UNINDEXED  it names an existing file the INDEX does not carry, because a declared
                        `SKIP_DIRS` entry excludes it. MEASURED: 335 sites in 1 file --
                        `tinybendygrad/runtime/autogen/libclang.bend` imports
                        `../../../.agents/slop/clangshim/libclang-tramp.c` (207 KB, present). NOT a
                        defect, and not silently PASS either: it is its own class so the count is
                        visible.
    MISDIRECTED         names an EXISTING file that is NOT the one the source means -- resolves TOO
                        FAR. MEASURED: **0 sites in this tree**, and the tree cannot be shown to have
                        none by inspection, so the class is kept and the `misdirected` plant seed
                        drives it.
    UNRESOLVED-INSIDE   names a MISSING path INSIDE the repo -- one level too shallow
    UNRESOLVED-OUTSIDE   names a MISSING path OUTSIDE the repo -- a checkout that is not this tree
    UNANCHORED          names nothing AND no candidate can be derived, so the gate says so instead
                        of guessing. Refusing costs one row; guessing would cost a wrong edit.

**`UNANCHORED` IS NOT A BUCKET OF LAST RESORT, IT IS A DERIVATION FAILURE WITH A NAME.**
`oracles/dtype_oracle.bend:12`'s `../dtype.bend` matches **THREE** files (`tinybendygrad/dtype.bend`,
`tinybendygrad/mixin/dtype.bend`, `tinybendygrad/codegen/decomp/dtype.bend`), so the tail alone
cannot say which. It is derived from the file's OTHER imports: `../helpers.bend` and
`../LAWS/spec.bend` anchor at `tinybendygrad`, and exactly one candidate is a DIRECT CHILD of it --
`dtype.bend` sits BESIDE `helpers.bend`, not three directories down among the decoys. Where a file
offers no in-file signal at all -- every one of `oracles/proof-close/MUTANT{,2}/`'s three imports is
unresolvable -- the anchor comes from a BYTE-IDENTICAL COPY that resolves one. **IN BOTH CASES THE
ANCHOR IS DERIVED FROM THE TREE AND NEVER NAMED IN THIS FILE.**

THE FIVE EXITS COME FROM `gates/gatekit.py`, LOADED BY PATH, never re-spelled.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#: Both neighbours are NAMED BY PATH and LOADED BY PATH. The population, the excluded directories
#: and the port root all come off these two files; none of the three is written here.
CENSUS = "checks/compile-census.py"
SUBSTRATE = "checks/substrate.py"
GATEKIT = "gates/gatekit.py"

#: WHERE THE RUN WRITES ITS ROWS. `gates/artifacts/` IS `.gitignore`d BY DESIGN -- `AGENTS.md` records
#: that one `rm -rf gates/artifacts` deleted a gate's fixture and git could not restore it -- so this
#: is a RUN OUTPUT and is not committed, and `--rows PATH` overrides it when a caller wants the rows
#: beside something else.
ROWS = "gates/artifacts/import-path.rows"

#: `import X`, `import X as A`, `import "X"` -- with any indentation, because `checks/c-context.bend`
#: imports its `.c` from INSIDE a `def` body and an anchored-only regex would miss both of those
#: sites and report the file as clean. MEASURED that is the shape of this tree: 8 of the 22 COLD
#: files import at a non-zero indent.
IMPORT = re.compile(r"^[ \t]*import[ \t]+(.+?)[ \t]*$")

#: A specifier with no `/` and none of these is a BUILTIN, not a path -- `Base` is bend's own
#: prelude and there are 81 of them. Naming the SUFFIX SET rather than asking bend is deliberate:
#: `checks/repro-paths.py:64`'s five-item suffix set is the recorded instance of this class, and it
#: is narrowed here to the two extensions this tree actually imports foreign files in.
FOREIGN = (".bend", ".c", ".h")


def instrument(rel, name=None):
    """Load a module BY PATH. `gates/path-resolve-gate.py:instrument()` is this function; the copy
    is this tree's standing cost and is not repaid by re-inventing it differently."""
    spec = importlib.util.spec_from_file_location(name or rel.replace("/", "_")[:-3],
                                                  os.path.join(ROOT, rel))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


# ============================================================ the population: DISCOVERED, BY PATH
def population(census):
    """`(.bend files, every foreign file in the tree, the derivation)`.

    `census.discover()` is the SAME walk `checks/compile-census.py` runs, so this gate and that one
    can never disagree about what the population is -- one of them changed and the other did not is
    a finding, not a nuisance. The port is ADDED, not substituted, because `checks/substrate.py`
    grades the port for COMPILE and no instrument grades it for PATHS: `tinybendygrad/` was never
    in scope for the defect this gate exists to find.
    """
    pop, _dropped = census.discover()
    # THE PORT IS ADDED, NOT SUBSTITUTED, AND IT IS ADDED BY ASKING THE INSTRUMENT THAT OWNS IT.
    # `checks/substrate.py:discover(POP_ROOT)` grades the port for COMPILE and no instrument graded it
    # for PATHS, so the port's 134 `.bend` would otherwise be outside the population entirely -- and
    # `tinybendygrad/test/dtype_oracle.bend` is the WARM half of the six byte-identical copies, so
    # excluding it would put the file that PROVES the fix outside the census that reports the fix.
    sub = instrument(SUBSTRATE, "substrate_pop")
    port = [p for p in sub.discover(sub.POP_ROOT) if p.endswith(".bend")]
    bend = sorted(set(pop) | set(port))
    index = []
    for d, dirs, fs in os.walk(ROOT):
        dirs[:] = sorted(x for x in dirs if x not in census.SKIP_DIRS)
        for f in sorted(fs):
            if f.endswith(FOREIGN):
                index.append(os.path.relpath(os.path.join(d, f), ROOT).replace(os.sep, "/"))
    return bend, sorted(set(index)), {"source": f"{CENSUS}:discover()", "skip_dirs": len(census.SKIP_DIRS)}


def site(rel, line, raw):
    """`(specifier, resolved, inside, exists)` for one `import` line.

    THE RESOLUTION IS `bend`'s OWN: the specifier is joined to the DECLARING FILE'S DIRECTORY, not
    to the process CWD. MEASURED, that is the whole defect -- `checks/gate.bend` writes
    `../../../tinybendygrad/uop/fold.bend`, and joined against the repo ROOT (the CWD every gate
    runs from) it names `<parent-of-repo>/tinybendygrad/uop/fold.bend`, which is the same wrong file
    by a different accident. `bin/bend`'s own header says it in so many words: "`bin/bend` resolves
    `import ./x.bend` relative to the FILE's own directory."
    """
    spec = raw.split(" as ")[0].strip().strip('"').strip("'")
    resolved = os.path.normpath(os.path.join(os.path.dirname(rel), spec)).replace(os.sep, "/")
    inside = not (resolved.startswith("..") or os.path.isabs(resolved))
    exists = os.path.exists(resolved if inside else os.path.join(ROOT, resolved.lstrip("/")))
    return spec, resolved, inside, exists


def is_builtin(spec):
    return "/" not in spec and not spec.endswith(FOREIGN)


def tail(spec):
    """The specifier with every `.` and `..` component dropped -- the part that survives a change of
    depth. `../../../tinybendygrad/uop/fold.bend` and `./../tinybendygrad/uop/fold.bend` have the
    SAME tail, which is what makes them the same import written at two wrong depths."""
    return "/".join(p for p in spec.split("/") if p not in (".", "..", ""))


def anchor_candidates(t, index):
    """Every indexed file whose repo-relative path ENDS WITH the tail. **A SUFFIX MATCH AGAINST A
    DISCOVERED INDEX, NOT AGAINST A LIST** -- doctrine 1 again: a hand list of "where `dtype.bend`
    lives" is exactly the defect `gates/gates-pop.py:95` admits against itself."""
    return [p for p in index if p == t or p.endswith("/" + t)]


def twins_of(rel, index_by_hash):
    """Every byte-identical copy of `rel`. **CONTENT, NOT A LIST** -- the six `dtype_oracle.bend`
    copies are six DIRECTORIES and one fact, and a hand list of them would rot the moment a seventh
    appears.

    **AN UNREADABLE FILE HAS NO TWINS, AND SAY SO INSTEAD OF RAISING.** MEASURED: the plant drives a
    synthetic declaring path that is deliberately never written to disk, and this raised
    `FileNotFoundError` out of `--plant` -- which means a plant that cannot run is a gate that
    cannot be shown to work, on the one code path whose whole job is to be run."""
    try:
        h = hashlib.sha256(open(os.path.join(ROOT, rel), "rb").read()).hexdigest()
    except OSError:
        return []
    return [p for p in index_by_hash.get(h, []) if p != rel]


def anchor_from_twin(rel, line_no, tail, by_hash):
    """The anchor a byte-identical copy PROVES by resolving the same import line.

    `oracles/ddcheck/tree/test/dtype_oracle.bend` offers no in-file signal at all -- every one of
    its three imports is unresolvable -- so the only derivation that reaches it is the copy at
    `tinybendygrad/test/dtype_oracle.bend`, where `../dtype.bend` resolves. What it resolves TO is
    the anchor, read off a file that COMPILES rather than picked out of three same-named decoys."""
    for twin in twins_of(rel, by_hash):
        try:
            lines = open(os.path.join(ROOT, twin), errors="replace").read().splitlines()
        except OSError:
            continue
        if line_no - 1 >= len(lines):
            continue
        m = IMPORT.match(lines[line_no - 1])
        if not m:
            continue
        s2 = m.group(1).split(" as ")[0].strip().strip('"').strip("'")
        if s2.split("/")[-1] != tail.split("/")[-1]:
            continue
        r2 = os.path.normpath(os.path.join(os.path.dirname(twin), s2)).replace(os.sep, "/")
        if not r2.startswith("..") and os.path.exists(os.path.join(ROOT, r2)):
            return r2, twin
    return None, None


def anchor(candidates, prefix):
    """Narrow `candidates` to the ONE the file's other imports point at, or `[]` when there is no
    unique answer -- and an empty answer is the SAFE one.

    **THE ORDER IS THE WHOLE DERIVATION, AND THE FIRST VERSION GOT IT BACKWARDS.** MEASURED: a plain
    "keep the candidates under `prefix`" filter cannot separate `tinybendygrad/dtype.bend` from
    `tinybendygrad/mixin/dtype.bend` from `tinybendygrad/codegen/decomp/dtype.bend` -- all three are
    UNDER `tinybendygrad` -- so `tinybendygrad/test/dtype_oracle.bend`, a file that COMPILES, came
    out UNANCHORED and the gate would have demanded an edit to a correct file. The discriminator is
    **DIRECT CHILD** of the derived prefix: `tinybendygrad/helpers.bend` and
    `tinybendygrad/LAWS/spec.bend` share the prefix `tinybendygrad`, and `dtype.bend` sits BESIDE
    `helpers.bend`, not beside `LAWS/spec.bend` and not three directories down. So:

        1 candidates that are DIRECT CHILDREN of the prefix -- this is what makes the port's own
          `dtype.bend` unique against two decoys that live deeper inside the port
        2 failing that, candidates UNDER the prefix at any depth
        3 failing that, every candidate -- the tail was unique, so there is nothing to choose

    and `[]` at the end, which the caller reports as `UNANCHORED` rather than guessing."""
    if not prefix or not candidates:
        return []
    pre = prefix.rstrip("/")
    direct = [p for p in candidates if os.path.dirname(p) == pre]
    if len(direct) == 1:
        return direct
    under = [p for p in candidates if p.startswith(pre + "/")]
    if len(under) == 1:
        return under
    return direct or under if len(direct or under) == 1 else []


# ============================================================ the census
CLASSES = ("RESOLVED", "RESOLVED-UNINDEXED", "MISDIRECTED", "UNRESOLVED-INSIDE",
           "UNRESOLVED-OUTSIDE", "UNANCHORED")
#: The classes that make the gate FAIL, named once so `main()` reports all of them and the verdict
#: sentence and the printed tally can never disagree about which classes count.
DEFECTIVE = ("MISDIRECTED", "UNRESOLVED-INSIDE", "UNRESOLVED-OUTSIDE", "UNANCHORED")


def census(root=ROOT):
    """`(rows, tally, derivation)`. One row per IMPORT SITE: `(class, rel, line, spec, resolved,
    anchor)`. No row is ever dropped -- including the ones that are fine, so `--rows` carries a
    denominator and not only the findings. A census that prints only its hits cannot be asked what
    fraction of the population it looked at, which is the question `AGENTS.md` keeps asking.

    **THE CLASSIFICATION IS `bend`'s OWN IMPORT SEMANTICS, NOT A HEURISTIC ABOUT `../` COUNTS.**
    MEASURED, the first version of this function ranked anchor candidates by "direct child of the
    prefix the file's other imports imply" and reported **346 MISDIRECTED sites in 11 files** --
    every one of them a FALSE POSITIVE on a file that compiles. The shape: `tinybendygrad/mixin/
    creation.bend:184` writes `import ./dtype.bend`, which resolves to `tinybendygrad/mixin/
    dtype.bend`, and the heuristic preferred `tinybendygrad/dtype.bend` because the file's other
    imports put it at `tinybendygrad/`. **`./x.bend` NAMES A SIBLING. That is not a guess to be
    scored, it is what the dot means**, and no amount of evidence about the file's other imports
    outvotes it. So:

        NO `..` IN THE SPECIFIER   the meaning is the declaring file's own directory. It resolves or
                                   it does not. No anchor is consulted and none is needed.
        A `..` IN THE SPECIFIER   the resolution is the author's stated intent, and it is only
                                   suspicious when the TAIL is ambiguous -- several files in the
                                   tree carry that name. Then the anchor is derived, and if the
                                   derived anchor is not where the path landed, that is
                                   `MISDIRECTED`: an existing file the source does not mean, which
                                   is the class a `does it exist` check cannot see at all.

    `RESOLVED-UNINDEXED` IS ITS OWN CLASS AND NOT A DEFECT. `tinybendygrad/runtime/autogen/
    libclang.bend` imports `../../../.agents/slop/clangshim/libclang-tramp.c`, which EXISTS; the
    index has no entry for it because `checks/compile-census.py:SKIP_DIRS` excludes `.agents`. The
    first version called that `MISDIRECTED` and would have demanded an edit to a working file. The
    exclusion is DECLARED by the instrument, so the honest answer is a named non-defective class
    whose count is printed, not a silent PASS and not an invented defect."""
    cc = instrument(CENSUS, "cc")
    bend, index, deriv = population(cc)
    by_hash = {}
    for rel in bend:
        try:
            by_hash.setdefault(hashlib.sha256(
                open(os.path.join(root, rel), "rb").read()).hexdigest(), []).append(rel)
        except OSError:
            pass
    rows, tally = [], {c: 0 for c in CLASSES}

    for rel in bend:
        try:
            lines = open(os.path.join(root, rel), errors="replace").read().splitlines()
        except OSError:
            rows.append(("UNANCHORED", rel, 0, "", "", "UNREADABLE"))
            tally["UNANCHORED"] += 1
            continue
        sites = []
        for n, raw in enumerate(lines, 1):
            m = IMPORT.match(raw)
            if not m:
                continue
            spec, resolved, inside, exists = site(rel, n, m.group(1))
            if not is_builtin(spec):
                sites.append((n, spec, resolved, inside, exists,
                              anchor_candidates(tail(spec), index)))
        # THE ANCHOR PREFIX, derived from THIS FILE's own uniquely-resolving imports.
        # `oracles/dtype_oracle.bend` cannot say what `../dtype.bend` means on its own -- the tail
        # matches THREE files, two of them decoys deeper inside the port -- but `../helpers.bend`
        # and `../LAWS/spec.bend` anchor at `tinybendygrad`, and exactly one candidate is a DIRECT
        # CHILD of it. READ OFF THE FILE, NEVER OFF A LIST.
        uniq = [s[5][0] for s in sites if len(s[5]) == 1 and s[4]]
        prefix = common_prefix([os.path.dirname(p) for p in uniq]) if uniq else None
        for n, spec, resolved, inside, exists, cands in sites:
            climbs = ".." in spec.split("/")
            if not climbs:
                # `./x` and bare `x` are FILE-RELATIVE: the declaring directory decides, full stop.
                cls = "RESOLVED" if exists else "UNRESOLVED-INSIDE"
                anch = cands[0] if len(cands) == 1 else (sorted(cands) or None)
                if not exists and anch is None and len(cands) == 1:
                    cls, anch = "UNRESOLVED-INSIDE", cands[0]
            else:
                if len(cands) == 1:
                    anch = cands[0]
                elif prefix:
                    anch = (anchor(cands, prefix) or [None])[0]
                else:
                    anch, _twin = anchor_from_twin(rel, n, tail(spec), by_hash)
                if exists:
                    cls = "RESOLVED" if (anch is None or anch == resolved) else "MISDIRECTED"
                    if not cands:
                        cls = "RESOLVED-UNINDEXED"
                elif not inside:
                    cls, anch = "UNRESOLVED-OUTSIDE", anch or (sorted(cands) or None)
                elif anch is not None:
                    cls = "UNRESOLVED-INSIDE"
                else:
                    cls, anch = "UNANCHORED", sorted(cands) or None
            tally[cls] += 1
            rows.append((cls, rel, n, spec, resolved, anch))
    return rows, tally, deriv


def common_prefix(dirs):
    """The longest directory prefix shared by `dirs`, or `None`. `tinybendygrad` for
    `['tinybendygrad', 'tinybendygrad/LAWS']`."""
    parts = [d.split("/") for d in dirs]
    out = []
    for i in range(min(len(p) for p in parts)):
        head = parts[0][:i + 1]
        if all(p[:i + 1] == head for p in parts):
            out = head
        else:
            break
    return "/".join(out) or None


def files_of(rows):
    """`(class -> sorted files)` with >=1 site of that class, and `path_files` -- the set this gate
    exists for. Printed as FILES beside SITES because five of the thirteen are one file five times
    and a reader who is handed only `13` will believe there are thirteen independent defects."""
    byc: dict[str, set] = {}
    for cls, rel, *_ in rows:
        byc.setdefault(cls, set()).add(rel)
    path = byc.get("MISDIRECTED", set()) | byc.get("UNRESOLVED-INSIDE", set()) \
        | byc.get("UNRESOLVED-OUTSIDE", set()) | byc.get("UNANCHORED", set())
    return {c: sorted(v) for c, v in byc.items()}, path


# ============================================================ the plant
#: TWO SEEDS, AND EACH ONE DECLARES **THE CLASS IT MUST BE GIVEN**. `want` is the claim; the
#: classifier is not asked whether it is "red" or "green" because a `../` one level too shallow and
#: a by-design `.c` import are OPPOSITE findings and a shared polarity would test nothing. A plant
#: that can only go red is a change-detector and `AGENTS.md` calls those harmful; a plant that CANNOT
#: go red on a by-design import will, one day, be satisfied by deleting `checks/c-context.bend`'s
#: `.c` import, because the gate insisted.
PLANT = (
    ("wrong-depth", "UNRESOLVED-INSIDE",
     "a `../` one level too shallow is a defect, whatever else it looks like. The two sibling "
     "imports are the file's CURRENT ones and they RESOLVE, which is what makes `tinybendygrad` "
     "derivable; the third is the defective line, reproduced from `oracles/dtype_oracle.bend:12` "
     "as it was",
     "import ../tinybendygrad/helpers.bend as H\n"
     "import ../tinybendygrad/LAWS/spec.bend as S\n"
     "import ../dtype.bend as D\n", "oracles"),
    ("by-design", "RESOLVED",
     "`checks/c-context.bend`'s `.c` import RESOLVES, and a C driver MUST import a .c",
     'import "../tinybendygrad/runtime/sz.c"\n', "oracles"),
    ("misdirected", "MISDIRECTED",
     "a `..` that lands on an EXISTING file the source does not mean is MISDIRECTED -- the class a "
     "`does it exist` check cannot see. Line 1 resolves and puts the file's anchor at "
     "`tinybendygrad`; line 2 resolves onto `oracles/dtype_oracle.bend`, WHICH EXISTS, and the "
     "anchor says the source means `tinybendygrad/test/dtype_oracle.bend`. Four `..` on line 1 "
     "because the seed sits at depth 4 -- MEASURED: three `..` there lands on `oracles/` rather "
     "than the repo root, the anchor never establishes, and the seed reads RESOLVED",
     "import ../../../../tinybendygrad/helpers.bend as H\n"
     "import ../../../dtype_oracle.bend as D\n", "oracles/ddcheck/tree/test"),
)


def plant(root=ROOT):
    """`(name, want, claim, got, src)` for each seed, driven through THIS gate's OWN `site()`,
    `anchor_candidates()`, `common_prefix()` and `anchor()`.

    **NO FILE IS WRITTEN.** The classifier's inputs are the specifier text, the declaring file's
    REPO-RELATIVE path, and the discovered index -- and only the middle one has to be synthetic. The
    first version built a temp tree and copied the index into it, and MEASURED what that costs:
    `site()` resolved against the declaring path while the existence check ran against the REAL
    root, so the by-design seed read `oracles/tinybendygrad/runtime/sz.c` as MISSING and the plant
    went red on a CORRECT import. **A PLANT THAT FAILS BECAUSE ITS OWN FIXTURE IS IN THE WRONG PLACE
    IS INDISTINGUISHABLE FROM ONE THAT CAUGHT A DEFECT, AND IS WORSE**, because it will be "fixed" by
    weakening the claim. So the seeds are driven in place, against the real index.

    **THE LAST IMPORT LINE IS THE ONE JUDGED AND THE EARLIER ONES ONLY ESTABLISH THE ANCHOR.** The
    `misdirected` seed needs a second line to exist: without a first import that pins the prefix to
    `tinybendygrad`, the third candidate set is ambiguous in a different way and the seed would be
    testing the tiering rather than the claim."""
    cc = instrument(CENSUS, "cc_plant")
    _bend, index, _d = population(cc)
    by_hash = {}
    out = []
    for name, want, claim, src, seed_dir in PLANT:
        rel = f"{seed_dir}/seed.bend"
        sites = []
        for n, raw in enumerate(src.splitlines(), 1):
            m = IMPORT.match(raw)
            if not m:
                continue
            spec, resolved, inside, exists = site(rel, n, m.group(1))
            sites.append((n, spec, resolved, inside, exists,
                          anchor_candidates(tail(spec), index)))
        uniq = [s[5][0] for s in sites[:-1] if len(s[5]) == 1 and s[4]]
        prefix = common_prefix([os.path.dirname(p) for p in uniq]) if uniq else None
        n, spec, resolved, inside, exists, cands = sites[-1]
        if ".." not in spec.split("/"):
            cls = "RESOLVED" if exists else "UNRESOLVED-INSIDE"
        else:
            if len(cands) == 1:
                anch = cands[0]
            elif prefix:
                anch = (anchor(cands, prefix) or [None])[0]
            else:
                anch, _t = anchor_from_twin(rel, n, tail(spec), by_hash)
            if exists:
                cls = "RESOLVED" if (anch is None or anch == resolved) else "MISDIRECTED"
                if not cands:
                    cls = "RESOLVED-UNINDEXED"
            elif not inside:
                cls = "UNRESOLVED-OUTSIDE"
            else:
                cls = "UNRESOLVED-INSIDE" if anch is not None else "UNANCHORED"
        out.append((name, want, claim, cls, f"{rel}: {src.strip().splitlines()[-1]}"))
    return out


def plant_bad(root=ROOT):
    """Seeds whose classifier answer is not the class they declare. `None` is a broken seed and is
    itself a failure: a seed that classified nothing would read as agreement with anything."""
    return [f"seed {name} must be {want} ({claim}) and the classifier said {got}"
            for name, want, claim, got, _src in plant(root) if got != want]


# ==================================================================== bend, OPT-IN
def bend_of(root, files, mb=2048, seconds=300):
    """`{rel: (state, token, first_stderr_line)}` for `files`, ONE bend at a time, through
    `checks/bounded.py`. **OPT-IN BEHIND `--bend` BECAUSE `bend` IS MEMORY-HEAVY AND A PATH CENSUS
    DOES NOT NEED IT**: every conclusion in the docstring is reachable from the static rows alone,
    and a gate that spends 1.4 GB to learn something it can read off a path is a gate that will be
    skipped. The TOKEN is read and `$?` is discarded, because `checks/bounded.py`'s own header
    records a unit that lost 425 rows by believing the status."""
    import subprocess
    gk = instrument(GATEKIT, "gk_bend")
    tok = re.compile(r"\[bounded\] (?P<t>\S+)\s+rc=(?P<rc>\d+)")
    rows = {}
    for rel in files:
        env = {**os.environ, "DEV": "CPU", "SPEC": "1", "PYTHONPATH": ""}
        p = subprocess.run([sys.executable, "checks/bounded.py", "--mb", str(mb),
                            "--seconds", str(seconds), "--", "./bin/bend", rel, "--check-only"],
                           cwd=root, capture_output=True, text=True, env=env)
        m = next((m for m in (tok.search(ln) for ln in p.stderr.split("\n")) if m), None)
        if m is None:
            rows[rel] = ("NO-MEASUREMENT", "NO-TOKEN", "")
            continue
        said = [l.strip() for l in p.stderr.split("\n")
                if l.strip() and not gk.NOTICE.match(l.strip()) and not l.startswith("[bounded]")]
        first = next((l for l in said if not l.startswith(" ")), "")
        rows[rel] = ("WARM" if first.startswith(gk.WARM) else "COLD", m.group("t"), first[:150])
    return rows


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    try:
        gk = instrument(GATEKIT)
    except Exception as exc:
        print(f"REFUSED {GATEKIT} did not load: {exc}", file=sys.stderr)
        return 3, f"{GATEKIT} did not load: {exc}"
    if "--plant" in argv:
        for name, want, claim, got, src in plant():
            print(f"PLANT {'ok  ' if got == want else 'RED '} {name:<12} want={want:<12} got={got}")
            print(f"       {src}")
            print(f"       {claim}")
        bad_plant = plant_bad()
        return (gk.FAIL, "plant claims no longer hold: " + "; ".join(bad_plant)) if bad_plant \
            else (gk.PASS, "plant: a wrong depth is NOT-RESOLVED and a by-design .c import is RESOLVED")

    rows, tally, deriv = census()
    byc, path_files = files_of(rows)
    sites = sum(tally.values())
    nfiles = len({rel for _c, rel, *_ in rows})
    if not sites:
        return gk.DEAD, "0 import sites over a non-empty population is DEAD, not PASS"
    if not rows:
        return gk.REFUSED, "the population is empty, so a census of it proves nothing"

    if "--rows" in argv or ROWS:
        p = argv[argv.index("--rows") + 1] if "--rows" in argv else ROWS
        with open(os.path.join(ROOT, p), "w") as fh:
            fh.write(f"# import-path-census: {sites} import sites over {nfiles} .bend files.\n"
                     f"# population = {CENSUS}:discover() PLUS {SUBSTRATE}:discover(POP_ROOT); "
                     f"{deriv['skip_dirs']} excluded directories, read off the instrument.\n"
                     f"# class= {'|'.join(CLASSES)}\n"
                     "# anchor= the file the source MEANS. Derived from the tail suffix against the\n"
                     "#         discovered index, then from this file's other uniquely-resolving\n"
                     "#         imports. Empty means NOT DERIVABLE, which is reported, never guessed.\n"
                     "class\tfile\tline\tspecifier\tresolved\tanchor\n")
            for cls, rel, n, spec, resolved, anch in rows:
                a = anch if isinstance(anch, str) else ",".join(anch or [])
                fh.write(f"{cls}\t{rel}\t{n}\t{spec}\t{resolved}\t{a}\n")
        print(f"ARTIFACT    {p}")

    print(f"POPULATION  .bend={nfiles}  import_sites={sites}  "
          f"(= {CENSUS}:discover() + {SUBSTRATE}:discover(POP_ROOT); discovered, not a list)")
    for c in CLASSES:
        print(f"CENSUS      {c}={tally[c]:<5} sites  {len(byc.get(c, [])):<4} files")
    print(f"PATH-FILES  {len(path_files)} -- "
          + ", ".join(f"{len(byc.get(c, []))} {c}" for c in DEFECTIVE))
    for c in DEFECTIVE:
        for rel in byc.get(c, []):
            print(f"  {c:<18} {rel}")
    if "--why" in argv:
        for cls, rel, n, spec, resolved, anch in rows:
            if cls != "RESOLVED":
                a = anch if isinstance(anch, str) else ",".join(anch or [])
                print(f"  {cls:<18} {rel}:{n}  {spec}  -> {resolved}   meant={a or 'NOT DERIVABLE'}")
    if "--bend" in argv:
        for rel in sorted(path_files):
            state, token, first = bend_of(ROOT, [rel])[rel]
            print(f"  BEND {state:<6} {rel:<52} [{token}] {first}")
    if "--self-test" in argv:
        return self_test_main(gk)

    bad = plant_bad()
    if bad:
        return gk.FAIL, "the plant no longer proves: " + "; ".join(bad)
    # EVERY DEFECTIVE CLASS IS REPORTED, NOT THE FIRST ONE. The first version returned inside the
    # loop, so the verdict sentence named whichever class came last in `DEFECTIVE` and the census
    # printed 3 defective files under a message about 1 -- a report whose denominator and its
    # subject were different numbers, which is the shape `AGENTS.md` keeps finding.
    found = {c: (tally[c], len(byc.get(c, []))) for c in DEFECTIVE if tally[c]}
    if found:
        return gk.FAIL, ("; ".join(f"{n} site(s) in {f} file(s) {c}" for c, (n, f) in found.items())
                        + f"; {sites} sites judged over {nfiles} .bend")
    return gk.PASS, (f"{sites} import sites over {nfiles} discovered .bend files, all RESOLVED "
                     f"(the file EXISTS and is the one the source MEANS); MISDIRECTED={tally['MISDIRECTED']}, "
                     f"UNANCHORED={tally['UNANCHORED']}")


# ==================================================================== the self-test
#: THREE WEAKENINGS, EACH THE OBVIOUS WRONG VERSION OF ONE RULE, EACH A ONE-LINE REINTRODUCTION.
#: `gates/path-resolve-gate.py:REGRESSIONS` is the precedent and the reason these exist: "A GATE THAT
#: HAS NEVER BEEN SEEN TO GO RED IS A GATE WHOSE PASS IS A COINCIDENCE WITH THE DISPATCH ORDER."
#:
#:     exists-only    a RESOLVED site is any site whose path EXISTS -- the anchor is dropped, so a
#:                    path that resolves TOO FAR is called correct. This is the class hashing cannot
#:                    see and it is the one this gate was written to catch, so a self-test that did
#:                    not drive it would test nothing this file exists for.
#:     dir-climb      the leading `../` run is IGNORED and the tail is resolved from the REPO ROOT.
#:                    This is the "is the path clean" instinct: `../dtype.bend` from `oracles/` and
#:                    `tinybendygrad/dtype.bend` would be the same site, which is the whole defect.
#:     anchored-is-ok a site with no derivable anchor is called RESOLVED instead of UNANCHORED,
#:                    i.e. "I cannot name it" is reported as "it is fine". This is the
#:                    `checks/pathresolve.py` refusal contract dropped on the floor.
#:
#: NONE OF THEM IS AN EDIT ON DISK. Each is applied by monkeypatching this module's own classifier
#: for the duration of one call, so the tree is never in a broken state and the gate is never
#: measured against a tree somebody has to remember to restore.
REGRESSIONS = ("exists-only", "dir-climb", "anchored-is-ok")


def regressed(name):
    """A `census()` that has been weakened by `name`, run over the REAL tree, plus the plant under
    the same weakening. Returns `(verdict_would_be, defective_files, tally, plant_failures, why)`.

    The verdict is read off this module's own `DEFECTIVE` rule, because a self-test that
    re-implements the decision is testing itself.

    **`globals()` AND NOT ASSIGNMENT.** The first version wrote `site = patched`, which made `site`
    a LOCAL for the whole function, so the `real_site` capture on the line above raised
    `UnboundLocalError` before the weakening was ever applied -- and MEASURED, a self-test that dies
    before it measures is indistinguishable from one that found nothing."""
    g = globals()
    real_site, real_cands = g["site"], g["anchor_candidates"]

    def dir_climb(rel, line, raw):
        spec, _r, _i, _e = real_site(rel, line, raw)
        resolved = os.path.normpath("/".join(p for p in spec.split("/") if p not in (".", "..")))
        return spec, resolved, True, os.path.exists(resolved)

    if name == "dir-climb":
        g["site"] = dir_climb
    elif name == "exists-only":
        g["anchor_candidates"] = lambda spec, index: []   # the anchor is dropped; existence is all
    elif name == "anchored-is-ok":
        def no_anchor(spec, index):
            return [f"GUESSED/{spec}"]     # unanchorable, and the weakened rule calls a guess FINE
        g["anchor_candidates"] = no_anchor
    try:
        rows, tally, _d = census()
        _byc, path_files = files_of(rows)
        sites = sum(tally.values())
        found = {c: tally[c] for c in DEFECTIVE if tally[c]}
        codes = gk_of()
        return (codes["FAIL"] if found else codes["PASS"], sorted(path_files), found,
                plant_bad(), f"sites={sites} defective={found or 'none'}")
    finally:
        g["site"], g["anchor_candidates"] = real_site, real_cands


def gk_of():
    gk = instrument(GATEKIT, "gk_st")
    return {"PASS": gk.PASS, "FAIL": gk.FAIL}


def self_test_main(gk):
    """Print every weakening's effect and FAIL if any of them would have PASSED. **A SELF-TEST THAT
    CANNOT FAIL IS NOT A SELF-TEST**, and the failure it looks for is the interesting direction.

    **AND IT SAYS WHICH INSTRUMENT CAUGHT IT, BECAUSE ON THIS TREE THE TWO DISAGREE AND BOTH ARE
    RIGHT.** The census already FAILS on the three real path defects, so for `exists-only` -- whose
    only difference is dropping the anchor -- the census's verdict is `FAIL` before and `FAIL` after
    and it catches NOTHING; the CENSUS has 0 MISDIRECTED sites to expose it with. The PLANT catches
    it, via the `misdirected` seed. Printing one undifferentiated `CAUGHT` would credit the census
    with the plant's work, which is the same conflation `AGENTS.md` records as `AGENTS.md` naming
    three `checks/*.sh` out of seventeen."""
    base_rows, base_tally, _d = census()
    base = {c: base_tally[c] for c in DEFECTIVE if base_tally[c]}
    print(f"SELF-TEST, each weakening applied in memory over the real tree "
          f"(baseline defective={base or 'none'}):")
    missed = []
    for name in REGRESSIONS:
        code, files, found, bad, why = regressed(name)
        moved = found != base
        by = []
        if code == gk.FAIL and moved:
            by.append("census")
        if bad:
            by.append("plant")
        if code == gk.FAIL and not moved and not bad:
            by.append("NOTHING")
        caught = bool(by) and "NOTHING" not in by
        print(f"  {'CAUGHT ' if caught else 'MISSED '} {name:<16} verdict={code} "
              f"by={'+'.join(by) or 'nothing':<12} defective={found or 'none'}")
        print(f"           {why}")
        if files:
            print(f"           would flag {len(files)} file(s): {', '.join(files[:4])}"
                  + (f" (+{len(files) - 4})" if len(files) > 4 else ""))
        if not caught:
            missed.append(name)
    if missed:
        print(f"  the gate does NOT catch: {', '.join(missed)}", file=sys.stderr)
        return gk.FAIL, "the gate does not catch " + ", ".join(missed)
    return gk.PASS, f"all {len(REGRESSIONS)} weakenings are caught"


if __name__ == "__main__":
    code, why = main()
    print(f"{instrument(GATEKIT).verdict_of(code)}  {why}")
    sys.exit(code)