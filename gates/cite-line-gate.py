#!/usr/bin/env python3
"""cite-line-gate.py -- THE PORT'S OWN CITATIONS, judged against the upstream they name.

    .venv/bin/python gates/cite-line-gate.py
    .venv/bin/python gates/cite-line-gate.py --rows OUT.rows
    .venv/bin/python gates/cite-line-gate.py --report
    .venv/bin/python gates/cite-line-gate.py --plant
    .venv/bin/python gates/cite-line-gate.py --tree DIR      # judge a COPY of the port

ZERO `bend` LANES. The subject is a `.bend` file's own COMMENT, and a citation of a
line is not code, so a comment stripper makes every one of them vanish while reporting
rc=0 PASS.

WHAT THIS GATE IS ABOUT, AND WHY IT IS NOT `gates/bendcite-gate.py`. That gate judges
the port's pointers to ITSELF -- `.bend` -> `.bend`. This gate judges the port's
pointers to UPSTREAM -- `.bend` -> `tinygrad/**/*.py`. They are different questions and
they have different failure modes: a `.bend`->`.bend` pointer rots when the port's own
file moves, and an UPSTREAM pointer rots when the VENDORED UPSTREAM moves, which is a
re-vendor and not an edit the port made. The 2026-11-03 re-vendor moved upstream and
left the port's line-number citations where they were, so this class of pointer is the
one that actually went stale.

THE SUBJECT IS DISCOVERED, NEVER NAMED. `os.walk` over `tinybendygrad/` plus
`endswith(".bend")`, because `glob('*.bend')` returns `[]` when the files ARE on disk --
the trap `AGENTS.md` records. **AND THE SCRATCH RULE IS THE TREE's OWN, LOADED BY PATH:**
`gates/header-census-gate.py`'s `is_scratch()`, because a mutation-probe scratch copy is
NOT a source file and a census that counted one would report a false citation NOBODY
could fix. The rule is not re-spelled here: a second copy of a carve-out is a contract
with no generator.

THE THREE BAD CLASSES, AND THEY ARE THE THREE THINGS A CITATION CAN CLAIM.

  OUT-OF-RANGE   the cited line number is past the end of the upstream file. The
                 pointer names a line that DOES NOT EXIST, so it names nothing.
  NO-SUCH-FILE   the cited path names no upstream file at all. The port's own tools
                 (`ops_bend.py`, `test_validate_oob.py`, `nvdriver.py`) are the port's
                 files and not upstream claims, so they are COUNTED AND REPORTED
                 SEPARATELY rather than failed -- a reader must be able to tell
                 "the port points at a file that does not exist" from "the port
                 points at ITS OWN tool and says so".
  QUOTE-MISMATCH the port quotes upstream's words at that line (`-- "..."`) and the
                 cited line does not contain them. This is the class that cannot be
                 argued with: the port says "upstream says X" and upstream does not.

RESOLUTION IS DELIBERATELY GENEROUS, AND THE REASON IS STATED. A bare basename names
more than one upstream file -- `dtype.py` is `tinygrad/dtype.py`, `tinygrad/mixin/dtype.py`
AND `tinygrad/codegen/decomp/dtype.py`, and `__init__.py` names twenty-nine files -- so
the resolver takes the evidence in this order:

  1. the cited path, when it names an upstream file exactly (`tinygrad/uop/ops.py`);
  2. the port's own directory tree, because the port mirrors upstream's
     (`runtime/support/nv/ip.py` from `runtime/support/nv/ip.bend`);
  3. the cited LINE RANGE -- a pointer at line N cannot be about a file with fewer
     than N lines, so the candidate that admits the line wins;
  4. the port's own neighbourhood, which frequently spells the qualified path.

A citation that survives that is NOT bad. **A RESOLVER THAT GUESSES MAKES A CITATION A
COIN FLIP**, so when the basename is STILL ambiguous the resolution is said so in the
row's `how`, and the row is counted as AMBIGUOUS rather than as bad.

THE EXITS ARE `gates/gatekit.py`'s five: 0 PASS, 1 FAIL, 3 REFUSED (the tree or the
upstream corpus is absent), 4 SKIP, 5 DEAD (no row was emitted).
"""

from __future__ import annotations

import argparse
import collections
import importlib.util
import os
import re
import shutil
import sys
import tempfile
import warnings
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, SKIP, VERDICT  # noqa: E402

ROOT = Path(os.environ.get("TINYGRAD_ROOT", HERE.parent)).resolve()
PORT_REL = "tinybendygrad"
UP_REL = "tinygrad"
ART = HERE / "artifacts"

#: A citation of an upstream `.py`: `ops.py:1790`, `uop/ops.py:26`,
#: `tinygrad/runtime/support/memory.py:23`.
CITE = re.compile(r"((?:[A-Za-z_0-9][A-Za-z_0-9-]*/)*[A-Za-z_0-9][A-Za-z_0-9-]*\.py):(\d+)")
#: The port's own quote of upstream's words: `-- "..."`.
QUOTE = re.compile(r'--\s*"([^"]{8,})"')

BAD = ("OUT-OF-RANGE", "NO-SUCH-FILE", "QUOTE-MISMATCH")
#: The port's OWN tools. They live in the PORT, not in upstream, so a citation of one
#: is the port naming its own instrument -- NOT a bad upstream citation. They are
#: counted and reported as their own class so that a reader can tell them apart from
#: a citation that names a file upstream does not have.
PORT_OWN_TOOLS = frozenset({"ops_bend.py", "test_validate_oob.py", "nvdriver.py"})


def load_sibling(name: str, filename: str):
    """LOAD a sibling instrument BY PATH. A second copy of a rule is a contract with no
    generator: `gates/header-census-gate.py`'s scratch rule and `gates/pin-cite-gate.py`'s
    claim-token rules are each bought with a measured fault, and this file uses both."""
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    mod = importlib.util.module_from_spec(spec)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        spec.loader.exec_module(mod)
    return mod


def norm(s: str) -> str:
    """A citation's quoted words and an upstream line, COMPARED. Case and punctuation
    are dropped, because the port's quote drops them too."""
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


class Upstream:
    """The upstream corpus: every `.py` under `tinygrad/`, PLUS the repo-root upstream
    that lives BESIDE `tinygrad/` in this repo (`extra/`, `examples/`). A citation of
    `examples/train_resnet.py` is an upstream citation and not a port-file one."""

    def __init__(self, base: Path) -> None:
        self.base = base
        # THE CORPUS IS KEYED RELATIVE TO THE REPO ROOT, and the `tinygrad/`
        # PREFIX IS KEPT. A key relative to `tinygrad/` would make
        # `tinygrad/__init__.py` and `tinygrad/renderer/__init__.py` share the
        # key `__init__.py`, and a bare `__init__.py` citation would then
        # resolve to the WRONG ONE BY ACCIDENT rather than by evidence --
        # and `__init__.py` names FORTY-FIVE upstream files.
        self.lines: dict[str, list[str]] = {}
        for rel in self._py_files(base / UP_REL):
            self.lines[f"{UP_REL}/{rel}"] = self._read(base / UP_REL / rel)
        for sub in ("extra", "examples"):
            d = base / sub
            if d.is_dir():
                for rel in self._py_files(d):
                    self.lines.setdefault(f"{sub}/{rel}", self._read(d / rel))
        self.bybase: dict[str, list[str]] = collections.defaultdict(list)
        for rel in sorted(self.lines):
            self.bybase[os.path.basename(rel)].append(rel)

    @staticmethod
    def _py_files(root: Path) -> list[str]:
        """The `.py` files under `root`, keyed RELATIVE TO `root`. The key is what
        the port's citation resolves to, so it is relative to the corpus root and
        not to the repository."""
        out = []
        for dp, dn, fn in os.walk(root):
            dn[:] = [d for d in dn if d != "__pycache__"]
            for f in sorted(fn):
                if f.endswith(".py"):
                    out.append(os.path.relpath(os.path.join(dp, f), root))
        return sorted(out)

    @staticmethod
    def _read(p: Path) -> list[str]:
        return p.read_text(encoding="utf-8", errors="replace").splitlines()

    def read(self, rel: str) -> list[str] | None:
        return self.lines.get(rel)


def port_files(base: Path, is_scratch) -> list[Path]:
    """The port's `.bend` SOURCE files. DISCOVERED, NOT NAMED."""
    out = []
    root = base / PORT_REL
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for n in sorted(fn):
            if n.endswith(".bend") and not is_scratch(n):
                out.append(Path(dp) / n)
    return out


def port_blocks(base: Path, is_scratch) -> list[dict]:
    """The port's contiguous `#` comment blocks."""
    out = []
    for p in port_files(base, is_scratch):
        rel = os.path.relpath(p, base / PORT_REL)
        lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        i = 0
        while i < len(lines):
            if lines[i].strip().startswith("#"):
                j = i
                while j < len(lines) and lines[j].strip().startswith("#"):
                    j += 1
                body = [lines[k].strip()[1:].strip() for k in range(i, j)]
                while body and not body[-1]:
                    body.pop()
                if body:
                    out.append({"file": rel, "line": i + 1, "body": body,
                                "text": " ".join(x for x in body if x)})
                i = j
            else:
                i += 1
    return out


def resolve(up: Upstream, cited: str, cite_line: int, port_file: str,
            ctx: str) -> tuple[str | None, str]:
    """A cited subject -> `(upstream path, how)`.

    THE ORDER IS THE ORDER OF EVIDENCE. An EXACT path is the citation's own
    spelling, relative to the REPO ROOT -- so `tinygrad/uop/ops.py` names
    upstream's `uop/ops.py` and `uop/ops.py` names it too. The PORT's OWN
    DIRECTORY TREE is next, because the port mirrors upstream's
    (`runtime/support/nv/ip.py` from `runtime/support/nv/ip.bend`). The cited
    LINE RANGE is next, because a pointer at line N CANNOT BE ABOUT A FILE WITH
    FEWER THAN N LINES -- that is a fact about the file and not a guess about the
    prose. The PORT's NEIGHBOURHOOD is last, because the port writes the
    qualified path right next to the bare one.

    A BARE BASENAME NEVER RESOLVES BY ACCIDENT. `__init__.py` names forty-five
    upstream files, so the corpus key carries the `tinygrad/` prefix and a bare
    `__init__.py` can only resolve through the directory rules below.
    """
    orig = cited
    if up.read(cited) is not None:
        return cited, "exact-path"
    # The `tinygrad/`-relative test applies ONLY to a citation that CARRIES A
    # PATH. A bare basename is NOT `tinygrad/<basename>` by default --
    # `__init__.py` names forty-five upstream files and `dtype.py` names three,
    # and a bare basename that is resolved to one of them by ACCIDENT is a
    # citation that was never checked.
    if "/" in cited and up.read(f"{UP_REL}/{cited}") is not None:
        return f"{UP_REL}/{cited}", "exact-path-relative-to-tinygrad"
    if "/" in cited:
        # The port writes a path RELATIVE TO ITS OWN DIRECTORY sometimes
        # (`isa/__init__.py` from `codegen/late/regalloc.bend` is really
        # `renderer/isa/__init__.py`), so the port's own tree is tried
        # BEFORE the basename fallback. A citation that names a path no
        # upstream file has is a NO-SUCH-FILE, and the port's own comment
        # about it is the evidence that it is not a resolution problem.
        pdir = os.path.dirname(port_file)
        for base_dir in (pdir, os.path.dirname(pdir), ""):
            cand = os.path.normpath(os.path.join(base_dir, cited)) if base_dir else cited
            for key in (cand, f"{UP_REL}/{cand}"):
                if up.read(key) is not None:
                    return key, "path-relative-to-the-port-file"
    base = os.path.basename(cited)
    cands = list(up.bybase.get(base, []))
    if not cands:
        return None, "absent"
    # THE PORT MIRRORS `tinygrad/`, NOT `examples/`. So when a bare basename
    # names a file in BOTH corpora and the port's own directory settles
    # nothing, the `tinygrad/` one is the subject -- a citation of
    # `helpers.py` from `schedule/memory.bend` is upstream's `helpers.py`,
    # and `examples/openpilot/helpers.py` is a DIFFERENT file that happens to
    # share a basename.
    if len(cands) > 1:
        tin = [c for c in cands if c.startswith(f"{UP_REL}/")]
        if tin and len(tin) < len(cands):
            cands = tin
    if len(cands) == 1:
        return cands[0], "unique-basename"
    # THE PORT SPELLED OUT A PATH, AND THE PORT'S OWN NEIGHBOURHOOD IS THE
    # STRONGEST EVIDENCE AFTER THE EXACT PATH. The port writes
    # `tinygrad/renderer/isa/__init__.py:9-16` next to its own
    # `isa/__init__.py:9`, and the port's own comment says that directory is
    # EMPTY -- so the subject is a path upstream does not have, and the
    # citation is NO-SUCH-FILE rather than a resolution puzzle. The
    # neighbourhood comes BEFORE the directory rule because the port states
    # what it means, while the directory rule only guesses.
    named_all = [c for c in cands if c in ctx]
    if len(named_all) == 1:
        return named_all[0], "the-port-neighbourhood-names-it"
    # THE PORT SPELLED OUT A PATH THAT DOES NOT EXIST. A citation like
    # `isa/__init__.py:9` from `codegen/late/regalloc.bend` is really about
    # `tinygrad/renderer/isa/__init__.py`, and the port's own neighbourhood
    # SAYS SO -- and that file does not exist upstream (the directory is
    # EMPTY). A citation that names a path the port itself spells out and
    # that upstream does not have is NO-SUCH-FILE, not a resolution puzzle,
    # and the port's own comment about the empty directory is the evidence.
    #
    # THE SPELLED-OUT PATH IS FOUND IN THE NEIGHBOURHOOD, so it is a
    # DISCOVERY and not a hand list -- but the spelling must carry the WHOLE
    # cited path, INCLUDING ITS DIRECTORY. A neighbourhood that mentions
    # some other `dtype.py` says nothing about `dtype.py`, and a rule that
    # fires on the basename alone would call nine healthy citations bad.
    #
    # AND THE SPELLED-OUT PATH MUST BE ONE THAT DOES NOT EXIST. A candidate
    # that IS in the corpus is a candidate, whatever the neighbourhood says.
    #
    # THIS COMES BEFORE THE DIRECTORY RULE, because the port STATES what it
    # means and the directory rule only GUESSES. A directory that happens to
    # hold an `__init__.py` is not a reason to read the port's citation as
    # being about it.
    if "/" in orig:
        for spelled in sorted(set(re.findall(r"[A-Za-z_0-9][A-Za-z_0-9./-]*\.py", ctx))):
            if not spelled.endswith("/" + orig):
                continue
            if up.read(spelled) is None:
                return None, f"the-port-names-it-and-it-does-not-exist:{spelled}"
    # The port's own directory tree. THE PORT MIRRORS UPSTREAM's, so the
    # citing file's directory is a STRONG signal a bare basename has -- but
    # it is a GUESS, and it is refused when the port names a different path.
    pdir = os.path.dirname(port_file)
    if not named_all:
        exact = [c for c in cands if os.path.dirname(c) == f"{UP_REL}/{pdir}"]
        if len(exact) == 1:
            return exact[0], "the-port-file's-own-directory"
        suf = [c for c in cands if os.path.dirname(c).endswith(f"{UP_REL}/{pdir}")]
        if len(suf) == 1:
            return suf[0], "the-port-file's-own-directory-suffix"
        pseg = pdir.split("/")[0] if pdir else ""
        seg = [c for c in cands if pseg and f"/{pseg}/" in c]
        if len(seg) == 1:
            return seg[0], "the-port-file's-own-top-directory"
    fits = [c for c in cands if (L := up.read(c)) and 1 <= cite_line <= len(L)]
    if len(fits) == 1:
        return fits[0], "the-only-candidate-that-has-the-line"
    if fits:
        cands = fits
    return sorted(cands, key=len)[-1], f"ambiguous:{len(cands)}->guessed"


def census(base: Path, is_scratch) -> list[dict]:
    """Every citation in the port's comment blocks, with its verdict."""
    up = Upstream(base)
    pblocks = port_blocks(base, is_scratch)
    byfile: dict[str, list[dict]] = collections.defaultdict(list)
    for pb in pblocks:
        byfile[pb["file"]].append(pb)

    rows = []
    for pb in pblocks:
        sibs = byfile[pb["file"]]
        idx = sibs.index(pb)
        ctx = "\n".join(b["text"] for b in sibs[max(0, idx - 3):idx + 4])
        for k, ln in enumerate(pb["body"]):
            for m in CITE.finditer(ln):
                cited, cite_line = m.group(1), int(m.group(2))
                rel, how = resolve(up, cited, cite_line, pb["file"], ctx)
                row = {
                    "port_file": pb["file"], "port_line": pb["line"] + k,
                    "cited": cited, "cite_line": cite_line,
                    "resolved": rel or "", "how": how,
                    "verdict": "OK", "why": "", "text": ln,
                }
                if rel is None:
                    base_name = os.path.basename(cited)
                    if base_name in PORT_OWN_TOOLS:
                        row["verdict"] = "PORT-OWN-TOOL"
                        row["why"] = "the port names its own tool, not an upstream file"
                    else:
                        row["verdict"] = "NO-SUCH-FILE"
                        row["why"] = f"{cited} names no upstream file"
                    rows.append(row)
                    continue
                lines = up.read(rel) or []
                if not (1 <= cite_line <= len(lines)):
                    row["verdict"] = "OUT-OF-RANGE"
                    row["why"] = (f"{rel} has {len(lines)} lines and the citation names "
                                  f"{cite_line}")
                    rows.append(row)
                    continue
                qm = QUOTE.search(ln)
                if qm:
                    want = norm(qm.group(1))
                    got = norm(lines[cite_line - 1])
                    win = norm(" ".join(lines[max(0, cite_line - 3):cite_line + 2]))
                    if want and want not in got and want not in win:
                        row["verdict"] = "QUOTE-MISMATCH"
                        row["why"] = (f"the quote {qm.group(1)[:60]!r} is not at "
                                      f"{rel}:{cite_line}")
                        rows.append(row)
                        continue
                row["verdict"] = "OK"
                rows.append(row)
    return rows


def report(rows: list[dict]) -> None:
    vc = collections.Counter(r["verdict"] for r in rows)
    print(f"citations examined : {len(rows)}")
    for k, n in vc.most_common():
        print(f"  {k:16s} {n}")
    amb = collections.Counter(r["how"] for r in rows if r["how"].startswith("ambiguous"))
    if amb:
        print(f"ambiguous basenames: {sum(amb.values())}")
        for k, n in amb.most_common():
            print(f"  {n:5d}  {k}")
    for cls in BAD:
        sel = [r for r in rows if r["verdict"] == cls]
        if not sel:
            continue
        print(f"\n-- {cls} ({len(sel)}) --")
        byfile = collections.Counter(r["resolved"] or r["cited"] for r in sel)
        for f, n in byfile.most_common(30):
            print(f"  {n:4d}  {f}")
    sel = [r for r in rows if r["verdict"] == "PORT-OWN-TOOL"]
    if sel:
        print(f"\n-- PORT-OWN-TOOL ({len(sel)}): the port names its own tool --")
        for f, n in collections.Counter(r["cited"] for r in sel).most_common():
            print(f"  {n:4d}  {f}")


def plant() -> int:
    """BREAK A CITATION AND CONFIRM THE GATE GOES RED.

    THE PLANT IS THE DELIVERABLE, NOT A COMMENT. A gate that has never been shown to
    go red is a gate that has never been tested: it may be green because it measures
    nothing, and `AGENTS.md` says "A GATE THAT EXITS 0 HAVING MEASURED NOTHING IS WORSE
    THAN NO GATE, BECAUSE IT IS TRUSTED."

    THE PLANT WORKS ON A COPY. The live tree moves under the gate's feet, and a
    control taken from it would compare two different trees.

    THE PLANT BREAKS A CITATION IN THE WAY THE TREE ACTUALLY BREAKS THEM. A citation
    goes stale when the file it names MOVES -- a re-vendor, or an edit that grows the
    upstream file. So the plant appends lines to an upstream `.py` and checks that the
    citation that named a line near the END of it is now OUT OF RANGE. It also breaks
    a QUOTE: the port says `upstream.py:N -- "words"` and the plant changes those
    words, so the quote no longer matches.
    """
    bad = []
    is_scratch = load_sibling("_scratch", "header-census-gate.py").is_scratch
    with tempfile.TemporaryDirectory(prefix="citeline-plant-") as raw:
        td = Path(raw)
        snap = td / "snap"
        snap.mkdir(parents=True)
        shutil.copytree(ROOT / PORT_REL, snap / PORT_REL)
        shutil.copytree(ROOT / UP_REL, snap / UP_REL)
        # The repo-root upstream lives BESIDE `tinygrad/`, and a citation of it
        # is an upstream citation. The plant copies it too, so the control and
        # the broken copy differ ONLY in the one citation the plant breaks.
        for sub in ("extra", "examples"):
            if (ROOT / sub).is_dir():
                shutil.copytree(ROOT / sub, snap / sub)
        # THE PRISTINE SNAPSHOT. Arm one breaks `snap`, and the twin control
        # has to be a copy of the UNBROKEN tree -- a twin taken from a broken
        # tree would be the broken tree, and the control would compare it
        # with itself and pass for the wrong reason.
        snap0 = td / "snap0"
        shutil.copytree(snap, snap0)
        base_rows = census(snap, is_scratch)
        base_v = collections.Counter(r["verdict"] for r in base_rows)
        print(f"PLANT control : {dict(base_v)}")

        # --- arm one: the upstream file GROWS and a citation goes out of range ---
        target = next((r for r in base_rows
                       if r["verdict"] == "OK" and r["resolved"]
                       and (snap / r["resolved"]).exists()
                       and r["resolved"].startswith(f"{UP_REL}/")),
                      None)
        if target is None:
            print("PLANT arm-one REFUSED: no citation resolves to an upstream file",
                  file=sys.stderr)
            return REFUSED
        up_path = snap / target["resolved"]
        original = up_path.read_text(encoding="utf-8").splitlines()
        # The citation must name a line that is IN RANGE now and will NOT be after the
        # growth: so it must name a line near the END of the file.
        n_up = len(original)
        print(f"PLANT arm-one the citation is {target['port_file']}:{target['port_line']} -> "
              f"{target['resolved']}:{target['cite_line']} and the upstream file has {n_up} lines")
        # Rewrite the citation to a line that will be past the end after the growth,
        # by growing the file by ONE line and pointing the citation past the end.
        grown = original + ["# PLANT: a line appended to the upstream file"]
        up_path.write_text("\n".join(grown) + "\n", encoding="utf-8")
        # Now point the SAME citation one line past the new end.
        port_path = snap / PORT_REL / target["port_file"]
        plines = port_path.read_text(encoding="utf-8").splitlines()
        old = f"{target['cited']}:{target['cite_line']}"
        new = f"{target['cited']}:{len(grown) + 1}"
        patched = []
        hit = False
        for ln in plines:
            if not hit and old in ln and ln.strip().startswith("#"):
                patched.append(ln.replace(old, new))
                hit = True
            else:
                patched.append(ln)
        if not hit:
            print("PLANT arm-one REFUSED: the citation's text was not found in the port",
                  file=sys.stderr)
            return REFUSED
        port_path.write_text("\n".join(patched) + "\n", encoding="utf-8")
        moved_rows = census(snap, is_scratch)
        moved_v = collections.Counter(r["verdict"] for r in moved_rows)
        after = next((r for r in moved_rows
                      if r["port_file"] == target["port_file"]
                      and r["port_line"] == target["port_line"]), None)
        print(f"PLANT arm-one control : {target['verdict']}  (the citation holds)")
        print(f"PLANT arm-one broken  : {after['verdict'] if after else '(the row is gone)'}"
              f"  {after['why'] if after else ''}")
        print(f"PLANT arm-one census  : {dict(moved_v)}")
        if after is None or after["verdict"] != "OUT-OF-RANGE":
            bad.append("arm one did not make the citation out of range")
        if moved_v.get("OUT-OF-RANGE", 0) <= base_v.get("OUT-OF-RANGE", 0):
            bad.append("arm one did not add an out-of-range citation")

        # --- arm two: the port's QUOTE of upstream's words stops matching ---
        snap2 = td / "snap2"
        shutil.copytree(snap0, snap2)
        qtarget = next((r for r in census(snap2, is_scratch)
                        if r["verdict"] == "OK" and r["resolved"]
                        and QUOTE.search(r["text"])), None)
        if qtarget is None:
            print("PLANT arm-two REFUSED: no citation quotes upstream's words", file=sys.stderr)
            return REFUSED
        qport = snap2 / PORT_REL / qtarget["port_file"]
        qlines = qport.read_text(encoding="utf-8").splitlines()
        qm = QUOTE.search(qtarget["text"])
        oldq = qm.group(1)
        newq = "PLANT words that upstream does not say at that line"
        out = []
        done = False
        for ln in qlines:
            if not done and oldq in ln:
                out.append(ln.replace(oldq, newq))
                done = True
            else:
                out.append(ln)
        if not done:
            print("PLANT arm-two REFUSED: the quote's text was not found in the port",
                  file=sys.stderr)
            return REFUSED
        qport.write_text("\n".join(out) + "\n", encoding="utf-8")
        q_rows = census(snap2, is_scratch)
        q_v = collections.Counter(r["verdict"] for r in q_rows)
        after2 = next((r for r in q_rows
                       if r["port_file"] == qtarget["port_file"]
                       and r["port_line"] == qtarget["port_line"]), None)
        print(f"PLANT arm-two control : {qtarget['verdict']}  (the quote holds)")
        print(f"PLANT arm-two broken  : {after2['verdict'] if after2 else '(the row is gone)'}"
              f"  {after2['why'] if after2 else ''}")
        print(f"PLANT arm-two census  : {dict(q_v)}")
        if after2 is None or after2["verdict"] != "QUOTE-MISMATCH":
            bad.append("arm two did not make the quote mismatch")
        if q_v.get("QUOTE-MISMATCH", 0) <= base_v.get("QUOTE-MISMATCH", 0):
            bad.append("arm two did not add a quote mismatch")

        # --- the CONTROL: a byte-identical twin must reproduce the control census ---
        # THE TWIN IS TAKEN FROM A PRISTINE SNAPSHOT, not from `snap` -- arm one
        # has already broken `snap`, so a twin copied from it would be the
        # BROKEN tree and the control would compare a broken tree with itself.
        twin = td / "twin"
        shutil.copytree(snap0, twin)
        twin_rows = census(twin, is_scratch)
        if [r["verdict"] for r in twin_rows] != [r["verdict"] for r in base_rows]:
            bad.append("the byte-identical twin did not reproduce the control")
        else:
            print("PLANT twin      : reproduces the control exactly")

    if bad:
        print("PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
        return FAIL
    print("PLANT OK: a stale citation goes OUT-OF-RANGE, a changed quote goes "
          "QUOTE-MISMATCH, and a byte-identical copy does neither")
    return PASS


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--plant", action="store_true", help="break a citation and confirm the gate goes red")
    ap.add_argument("--report", action="store_true", help="print the census; exit 0 by request")
    ap.add_argument("--rows", help="write the rows to this .rows file")
    ap.add_argument("--tree", help="judge a COPY of the port at this directory")
    args = ap.parse_args(argv)

    if args.plant:
        return plant()

    base = Path(args.tree).resolve() if args.tree else ROOT
    if not (base / PORT_REL).is_dir():
        print(f"== REFUSED, NOT A VERDICT: {base / PORT_REL} is absent", file=sys.stderr)
        return REFUSED
    if not (base / UP_REL).is_dir():
        print(f"== REFUSED, NOT A VERDICT: {base / UP_REL} is absent", file=sys.stderr)
        return REFUSED
    is_scratch = load_sibling("_scratch", "header-census-gate.py").is_scratch
    rows = census(base, is_scratch)
    if not rows:
        print("== DEAD: no upstream citation was found; the census measured nothing",
              file=sys.stderr)
        return DEAD
    report(rows)

    if args.rows:
        ART.mkdir(parents=True, exist_ok=True)
        out = Path(args.rows)
        out.parent.mkdir(parents=True, exist_ok=True)
        head = ("port_file\tport_line\tcited\tcite_line\tresolved\thow\tverdict\twhy\ttext\n")
        body = "".join(
            f"{r['port_file']}\t{r['port_line']}\t{r['cited']}\t{r['cite_line']}\t"
            f"{r['resolved']}\t{r['how']}\t{r['verdict']}\t{r['why']}\t"
            f"{r['text'].replace(chr(9), ' ')}\n" for r in rows)
        out.write_text(head + body, encoding="utf-8")
        print(f"ROWS       : {len(rows)} -> {out}")

    bad = [r for r in rows if r["verdict"] in BAD]
    if args.report:
        print("(REPORT: exit 0 by request; the numbers above are the census, not a verdict)")
        return PASS
    if bad:
        print(f"# cite-line-gate: FAIL -- {len(bad)} of {len(rows)} upstream citations do not hold")
        return FAIL
    print("# cite-line-gate: PASS")
    return PASS


if __name__ == "__main__":
    print(f"# exit vocabulary: {VERDICT}", file=sys.stderr)
    raise SystemExit(main(sys.argv[1:]))
