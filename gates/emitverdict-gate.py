#!/usr/bin/env python3
"""WHAT THE TWO SIDES OF THE graphcmp CORPUS ACTUALLY AGREE ON.

`checks/differ.py` reports TWO different numbers over the same 34 graphs and they disagree
about which graphs are broken:

  `graphs-agree=31`   counts `D1-graph-*.txt`'s `VERDICT:` -- graphcmp's own STRUCTURAL
                      differ, which `.agents/slop/graphcmp.py:1986` documents as keying on
                      structure and NOT on ids.
  `byte-identical=20` counts `D2-canon-*` BYTES, and the same comment says the ids "are
                      REPORTING ONLY and the differ never keys on them".

SO `byte-identical` COMPARES A COLUMN THE PROJECT ITSELF DECLARES REPORTING-ONLY, and
MEASURED 2026-10-18 it disagrees with the structural verdict on 11 of 34 graphs. This gate
exists to say WHICH of the two numbers is measuring a port defect, per graph, by name.

THE QUESTION IT ANSWERS, PER GRAPH: are the two sides THE SAME GRAPH?

THE ANSWER IS NOT "ARE THE BYTES EQUAL", and this file is the reason. `.agents/slop/graphcmp.py:1999-2001`
numbers the CPython side by TOPOSORT POSITION -- `for i, n in enumerate(ast.toposort(...))`
-- while `tinybendygrad`'s `i` is an ARENA INDEX: `tinybendygrad/uop/ops.bend:1322`
("the arena starts with the bottom at index 0"), i.e. hash-consing order. THOSE ARE
DIFFERENT QUANTITIES WITH THE SAME SPELLING, so a byte comparison of that column is
comparing two addresses. MEASURED, this file's own `--why`: py's emitted id sequence is
MONOTONIC in 34 of 34 graphs (it must be -- it is `enumerate` over the toposort) and bend's
is non-monotonic in exactly the 11 that byte-differ yet structurally agree.

THE METHOD IS BISIMULATION, NOT A REGEX. Each row is eight `<len>:<value>` fields, and the
LENGTH PREFIX MAKES THE PARSE EXACT -- no field can contain a space, so the parse needs no
pattern at all. Then the decisive property, which cost two wrong instruments to find:

    A NODE REFERENCE APPEARS ONLY IN FIELD 7, `src`.

`arg` is a `P(...)` whose `i12`/`i64` are buffer SIZES and whose `i0` is a buffer NUMBER,
`depth` is the constant `i0`, and `shape` is `l0:4`. Reading node ids out of any of them is
how a first attempt at this file reported `bw`/`cdiv`/`commute`/`late`/`threefry` as
CONTENT-divergent when they are byte-equal up to numbering: `i12` matched the pattern for
"a node whose id is 12". FIELDS, NOT PATTERNS.

So: label every node by (op, dtype, shape, depth, tag), then refine until fixpoint with
the `src` children folded in. Two sides describe the same graph iff their final label
MULTISETS are equal. That is identity, modulo ids and modulo emit order, and it is the
right question because ids and emit order are exactly the two things the two implementations
are documented to disagree about.

FIVE VERDICTS, `gates/gatekit.py`'s OWN EXITS, because `DEAD` is the one nobody writes
down and A 0-ROW SIDE IS NOT AGREEMENT:
  IDENTICAL      bytes equal. Trivially the same graph.
  NUMBERING-ONLY bytes differ, graphs are the same. `i`/emit order only -- NOT a defect.
  CONTENT        graphs differ. A REAL defect, and this is what the gate exists to name.
  DEAD           one side emitted 0 rows. NOT agreement; NOT a zero.
  REFUSED        the artifacts are missing or unreadable, so nothing was measured.

POPULATION BY DISCOVERY, per `AGENTS.md` doctrine 1: the graphs are whatever
`runs/graphcmp/D/D2-canon-py-*.txt` names, read by a directory walk. This file names no graph.
"""
from __future__ import annotations

import hashlib
import re
import sys
import tempfile
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gatekit  # noqa: E402

D = Path(__file__).resolve().parent.parent / "runs/graphcmp/D"
PY_ART = "D2-canon-py-{}.txt"
BEND_ART = "D2-canon-bend-{}.txt"
# `i` followed by digits, used ONLY inside a `src` field (see the module docstring).
REF = re.compile(r"i(\d+)")


def fields(line: str) -> list[str]:
    """The eight `<len>:<value>` fields. The length prefix is the parse: a field cannot
    contain a space, so nothing here can be confused for a delimiter."""
    out, i = [], 0
    while i < len(line):
        j = line.index(":", i)
        n = int(line[i:j])
        out.append(line[j + 1:j + 1 + n])
        i = j + 1 + n
    return out


def parse(rows: list[str]) -> list[tuple]:
    """`(id, op, dtype, shape, depth, tag, arg, src_refs)` per row, in EMIT order.

    `src_refs` are NODE REFERENCES ONLY -- see the module docstring for why reading them out
    of `arg` is a category error that this file already made once.

    THE `id` IS CARRIED AND MUST NOT BE ASSUMED. Both sides number from 1, but only one side's
    numbers are EMIT POSITIONS: CPython enumerates its toposort, while the port emits in the
    arena's order. `where` emits `i9` FIRST on the bend side. Resolving a reference by list
    position therefore reads `i9` as the ninth row emitted -- which is `CMPLT`, not the `STACK`
    it names -- and reports the whole graph as CONTENT-divergent. MEASURED: that mistake made
    this gate report 14 of 34 graphs as CONTENT when 11 are the same graph renumbered."""
    out = []
    for ln in rows:
        f = fields(ln)
        if len(f) != 8:
            raise ValueError(f"expected 8 fields, got {len(f)}: {ln[:70]!r}")
        out.append((f[0].removeprefix("i"), f[1], f[2], f[3], f[4], f[5], f[6],
                    tuple(REF.findall(f[7]))))
    return out


def labels(parsed: list[tuple]) -> tuple[Counter, bool]:
    """Canonical hash of each node's whole subtree. Returns `(multiset, usable)`.

    **THREE WRONG CANONICAL FORMS GOT HERE FIRST, AND EACH REPORTED 14 OF 34 GRAPHS AS
    CONTENT-DIVERGENT WHEN 11 OF THEM ARE THE SAME GRAPH UNDER A DIFFERENT `i`.** They are
    recorded because every failure was SILENT -- the answer looked plausible:

      * Refining on the previous round's LITERAL label never settles: a leaf's label becomes
        `id(k,())`, then `id(id(k,()),())`, a new integer every round, forever.
      * Re-ranking to FIRST-APPEARANCE order settles, and is worse: py's `CONST` and bend's
        `AFTER` are both the first op each side emits, so both become rank 0 and `CONST`
        compares EQUAL to `AFTER`. **A CANONICAL FORM MUST BE INJECTIVE IN THE LABELS, NOT IN
        THEIR ARRIVAL ORDER.**
      * Iterating a SHA over the previous round's hash never settles either, for the same
        reason the literal labels did not: the digest is rebuilt from a value that changed.

    Hashing the recursion BOTTOM-UP is injective in the structure (up to a collision) and is
    order-independent, so the two multisets compare with no shared state at all.

    **THE TOPOLOGICAL PRECONDITION IS CHECKED, NOT ASSUMED.** A dangling reference, or a child
    emitted at or after its parent, returns `usable=False` and `classify` reports CONTENT for
    it: a graph whose shape this gate cannot decide must never read as agreement."""
    at = {nid: i for i, (nid, *_r) in enumerate(parsed)}
    h: list = [None] * len(parsed)
    for i in range(len(parsed) - 1, -1, -1):
        nid, op, dt, sh, dp, tg, ag, srcs = parsed[i]
        kids = []
        for k in srcs:
            j = at.get(k)
            if j is None or j >= i:
                return Counter(), False
            kids.append(h[j])
        h[i] = hashlib.sha256(repr((op, dt, sh, dp, tg, ag, tuple(kids))).encode()).digest()
    return Counter(h), True


def ids(rows: list[str]) -> list[int]:
    """The emitted id column, in emit order. Monotonicity is the `i`-MEANING probe."""
    return [int(ln.split(" ", 1)[0].split(":")[1][1:]) for ln in rows]


def read(art: Path) -> list[str] | None:
    return [ln for ln in art.read_text(errors="replace").splitlines() if ln.strip()] \
        if art.exists() else None


def split_top(s: str) -> list[str]:
    """Comma split at bracket depth 0 -- `P(...)`'s own rule for its eleven fields."""
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    return out


def devices(parsed: list[tuple]) -> set[str]:
    """The DEVICE each row's `ParamArg` carries -- `graphcmp.py:devnames`' own field 7.

    Read here rather than imported so this gate does not take a substrate input as a
    dependency (and so it stays a second opinion on the SAME rule, not a copy of a rule)."""
    out = set()
    for _i, _o, _d, _s, _p, _t, arg, _srcs in parsed:
        if arg.startswith("P("):
            out.add(split_top(arg[2:-1])[7])
    return out


def classify(name: str) -> str:
    py, bd = read(D / PY_ART.format(name)), read(D / BEND_ART.format(name))
    if py is None or bd is None:
        return "REFUSED"
    if not py or not bd:
        return "DEAD"
    if (D / PY_ART.format(name)).read_bytes() == (D / BEND_ART.format(name)).read_bytes():
        return "IDENTICAL"

    lp, cp = labels(parse(py))
    lb, cb = labels(parse(bd))
    if not cp or not cb:
        return "CONTENT"  # a cycle is never agreement; say CONTENT and name it below
    return "NUMBERING-ONLY" if lp == lb else "CONTENT"


def population() -> list[str]:
    """Every graph the generator wrote a `D2-canon-py-` artifact for. A DIRECTORY WALK."""
    return sorted(p.name[len("D2-canon-py-"):-len(".txt")] for p in D.glob("D2-canon-py-*.txt"))


def summarise() -> tuple[int, str]:
    """Every graph, classified ONCE -- `classify` re-reads and re-refines, and calling it
    three times per graph is three times the work for one answer."""
    verdicts = {n: classify(n) for n in population()}
    tally = Counter(verdicts.values())
    detail = " ".join(f"{k}={v}" for k, v in sorted(tally.items()))
    bad = [f"{n}:{v}" for n, v in sorted(verdicts.items())
           if v in ("CONTENT", "DEAD", "REFUSED")]
    print(f"emit-verdict graphs={len(verdicts)} {detail}")
    if bad:
        print("NOT THE SAME GRAPH " + " ".join(bad))
    return (gatekit.FAIL if bad else gatekit.PASS), f"emit-verdict {detail}"


def why() -> int:
    """The `i`-MEANING probe: is each side's emitted id column monotonic?

    `emit_py` enumerates the toposort, so py's MUST be; the arena's need not be. That
    difference is the whole of why `byte-identical` and `graphs-agree` disagree."""
    mono_p = [n for n in population() if ids(read(D / PY_ART.format(n)) or []) != sorted(ids(read(D / PY_ART.format(n)) or []))]
    mono_b = [n for n in population() if ids(read(D / BEND_ART.format(n)) or []) != sorted(ids(read(D / BEND_ART.format(n)) or []))]
    print(f"py  non-monotonic ids: {len(mono_p)} of {len(population())}")
    print(f"bend non-monotonic ids: {len(mono_b)} of {len(population())} {mono_b}")
    dev = {n: (devices(parse(read(D / PY_ART.format(n)) or [])),
               devices(parse(read(D / BEND_ART.format(n)) or [])))
           for n in population()}
    for n, (p, b) in dev.items():
        if p != b:
            print(f"devices py={sorted(p)} bend={sorted(b)} -- {n}")
    return 0


PLANT = {
    # Each plant must move the verdict OFF its current word. A plant that leaves the
    # classification alone proves nothing, which is how a lane once scored a successful
    # plant while emitting nothing at all.
    "number": "permute the bend id column -- must stay NUMBERING-ONLY, never CONTENT",
    "content": "flip one op on the bend side -- must become CONTENT",
    "dead": "truncate the bend side to 0 rows -- must become DEAD, never IDENTICAL",
}


def mutate(rows: list[str], kind: str) -> list[str]:
    """One graph's rows, re-emitted after the plant's edit. Pure; writes nothing."""
    if kind == "dead":
        return []
    n = len(rows)
    perm = {i: (i + 3) % n + 1 for i in range(1, n + 1)}
    out = []
    for r in rows:
        f = fields(r)
        if kind == "content" and f[1] == "CONST":
            f[1] = "AFTER"
        if kind == "number":
            # A ROTATION of the id set, applied to the node id AND every `src` reference. A
            # bijection is the whole point: renumbering "by first appearance" was tried and it
            # is NOT one -- the id field and the references are consumed in different orders,
            # so a reference can be handed a number that some other node then claims, and the
            # result is a DANGLING reference that reads as a graph defect (KeyError).
            f[0] = REF.sub(lambda m: f"i{perm[int(m.group(1))]}", f[0])
            f[7] = REF.sub(lambda m: f"i{perm[int(m.group(1))]}", f[7])
        out.append(" ".join(f"{len(x)}:{x}" for x in f))
    return out


def plant(kind: str) -> int:
    """Classify ONE graph against a MUTATED COPY of itself and require the word to move.

    The copy lives in a scratch directory and `classify` is pointed at it by rebinding the
    module's own `D`, so nothing under `runs/graphcmp/D/` is written and a plant cannot damage
    the run that measured us. The NEGATIVE case is the assertion that matters: `dead` must
    read DEAD and NOT IDENTICAL, because a lane that emits nothing while the check scores it a
    success is the failure mode this whole file is about."""
    global D
    if kind not in PLANT:
        print(f"plant: no such plant {kind!r}; have {sorted(PLANT)}")
        return gatekit.REFUSED
    name = next((n for n in population() if classify(n) == "IDENTICAL"), None)
    if name is None:
        print("plant: no IDENTICAL graph to mutate -- NOT RUN")
        return gatekit.SKIP
    rows = read(D / PY_ART.format(name)) or []
    want = {"number": "NUMBERING-ONLY", "content": "CONTENT", "dead": "DEAD"}[kind]
    real = D
    try:
        with tempfile.TemporaryDirectory() as td:
            scratch = Path(td)
            (scratch / PY_ART.format(name)).write_text("\n".join(rows) + "\n")
            (scratch / BEND_ART.format(name)).write_text(
                "".join(f"{r}\n" for r in mutate(rows, kind)))
            D = scratch
            got = classify(name)
    finally:
        D = real
    ok = got == want
    print(f"plant {kind}: {name} -> {got} (expected {want}) {'OK' if ok else 'PLANT FAILED'}")
    return gatekit.PASS if ok else gatekit.FAIL


class Gate:
    name = "emitverdict"

    def run(self) -> int:
        args = sys.argv[1:]
        if args[:1] == ["--why"]:
            return why()
        if args[:1] == ["--plant"] and len(args) > 1:
            return plant(args[1])
        if args[:1] == ["--plant"]:
            print("plants: " + " | ".join(f"{k} -- {v}" for k, v in PLANT.items()))
            return gatekit.PASS
        # NOT `gatekit.gate(self, ...)`: that calls `g.run()`, which would call this again.
        code, summary = summarise()
        print(summary if code == gatekit.PASS else f"{self.name}: {gatekit.verdict_of(code)}")
        return code


if __name__ == "__main__":
    sys.exit(Gate().run())