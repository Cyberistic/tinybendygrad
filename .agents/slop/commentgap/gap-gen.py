#!/usr/bin/env python3
"""gap-gen.py -- GENERATE the comment-gap ledger, so the ledger cannot rot.

    .venv/bin/python .agents/slop/commentgap/gap-gen.py                 # write gap.rows
    .venv/bin/python .agents/slop/commentgap/gap-gen.py --check         # write to a scratch copy and diff
    .venv/bin/python .agents/slop/commentgap/gap-gen.py --out FILE      # write elsewhere
    .venv/bin/python .agents/slop/commentgap/gap-gen.py --quiet

THE POPULATION IS DISCOVERED, NEVER NAMED. Every contiguous `#` comment block
in every `.py` under `tinygrad/` is ONE ROW. The walk is `os.walk` plus
`endswith(".py")` -- `glob('*.bend')` returns `[]` when the files ARE on disk,
the trap `AGENTS.md` records, and a hand list of upstream files would be a
list, not a population.

THE JOIN KEY IS THE PORT'S OWN CITATION. The port writes
`# <upstream>.py:<line> -- "<upstream's words>"`, so upstream `(file, line)`
resolves to the port comment block that cites it. A citation that names only a
BASENAME is ambiguous whenever more than one upstream file carries that
basename, and the disambiguator is EVIDENCE, in this order:

  1. the cited path, when it names an upstream file exactly (`tinygrad/uop/ops.py`);
  2. the citing block's neighbourhood, which frequently spells the qualified
     path (`uop/ops.py`) that the bare basename means;
  3. the cited LINE RANGE -- a pointer at line N cannot be about a file with
     fewer than N lines, so the candidate that admits the line wins;
  4. the port file's own directory, which usually mirrors upstream's.

WHEN THE BASENAME IS STILL AMBIGUOUS THE ROW IS COUNTED AND SAID SO. A
resolver that guesses turns a citation into a coin flip and the ledger into a
rumour, so the ambiguity is reported in the note rather than resolved by
hope. `--ambiguity` prints the census.

THE VERDICT VOCABULARY IS EXACTLY FIVE, AND NO OTHERS.

  PORTED                  the port carries the upstream block's reasoning
  GAP-NO-CITATION         nothing in the port cites any line of the block
  GAP-CITED-NO-REASONING  a port comment cites a line of the block and does
                          NOT carry the reasoning -- a citation without the
                          reasoning is a STAMP, not a port
  GAP-DIFFERENT-REASONING the port cites the block, reasons about it, and
                          says so -- and says something ELSE
  N/A-PYTHON-ONLY         the upstream file has no port counterpart

TOKENISATION, STATED BECAUSE A LEDGER THAT CANNOT SAY ITS RULES IS A RUMOUR.

  A TOKEN IS A WORD, NOT A CHARACTER: `[A-Za-z][A-Za-z0-9_]{2,}` -- a letter,
  then at least two more word characters. So `x` and `ab` are NOT tokens and
  `ops` and `new_axes` ARE. Lowercased before comparison.

  A CONTENT TOKEN IS A TOKEN THAT IS NOT A STOPWORD. The stopword list is
  `STOPWORDS` below, and it is spelled out HERE so the rule is visible in the
  instrument rather than implied by a library.

  A PHRASE IS A CONTIGUOUS RUN OF CONTENT TOKENS. The port carries the
  upstream block's reasoning when some port comment block contains a
  contiguous phrase of >= 4 content tokens of that block, OR a contiguous run
  of >= 3 DISTINCTIVE tokens -- distinctive meaning rare in the port: a token
  appearing in at most `max(4, len(port_blocks) // 40)` port comment blocks.

  THE SCOPE OF THE SEARCH IS THE EVIDENCE, NOT A GUESS. For a CITED upstream
  block the candidate port blocks are the blocks of the port files that cite
  that upstream file -- a coincidental vocabulary collision in an unrelated
  file is not a port of that comment. For an UNCITED upstream block the
  candidate is every port comment block in the port.

  THE TIE-BREAK IS STATED, NOT INCIDENTAL. When two port blocks carry the
  same reasoning equally well, the one reported is the EARLIEST in the
  walk -- the lowest block index. The predecessor's instrument broke that
  tie by SET ITERATION ORDER, which is deterministic for a given input but
  is not a RULE: a set of block indices iterates by slot, and the slot a
  given index lands in depends on the size of the set. Two rows of the
  predecessor's ledger are affected (`renderer/llvmir.py:110` and
  `runtime/support/compiler_cpu.py:20`), and both of them score the SAME
  under either tie-break -- the verdict is the same, only the reported
  carrier differs. A tie-break a reader cannot state is a tie-break a
  reader cannot check, so this one is stated.

THE PORT'S FILE MAP IS A DISCOVERY, NOT A LIST. An upstream file has a port
counterpart when a `.bend` file carries the same path and stem, or the same
stem anywhere, or a name close enough to it to be the same file renamed.
`ALIASES` holds the handful of renames the discovery cannot make -- and it
holds them because the tree's own history records them, not because a list
was convenient.

DETERMINISM. Every walk is `sorted`, every set is iterated in sorted order,
and no step consults the clock, the network, or the environment. Two runs on
the same tree produce the same bytes.

AND THE TREE MOVES. MEASURED 2026-11-17 23:46: two runs of this script, one
minute apart, produced DIFFERENT BYTES -- because another unit was editing
`tinybendygrad/uop/spec.bend` while the first run read it, and the ledger
records PORT LINE NUMBERS. The verdict for `uop/spec.py:206` moved from
GAP-DIFFERENT-REASONING to PORTED across the two runs, because the port's own
comment about that upstream line had been extended in between.

**A LEDGER THAT RECORDS A LINE NUMBER IN A TREE THAT IS MOVING IS A LEDGER
THAT RECORDS WHEN IT WAS TAKEN.** So `--substrate` prints the sha256 of every
port file the ledger read, and two ledgers taken of DIFFERENT substrates can
be told apart without guessing. A ledger and its substrate belong together,
and the substrate is one `sha256sum` away.
"""

from __future__ import annotations

import argparse
import collections
import difflib
import hashlib
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
UP = os.path.join(REPO, "tinygrad")
PORT = os.path.join(REPO, "tinybendygrad")
HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "gap.rows")

# The predecessor's resolver did NOT strip the `tinygrad/` prefix before the
# exact-path test, so a fully-qualified port citation fell through to the
# basename and was resolved by score. `--legacy-resolver` reproduces that.
# It is OFF by default because the default is RIGHT.
LEGACY_RESOLVER = False

# --------------------------------------------------------------------------
# TOKENISATION
# --------------------------------------------------------------------------

TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z0-9_]{2,}")

STOPWORDS = frozenset("""the a an and or of to in is are was were be been being it its this that these those
not no but if then else for while do does did can could should would may might must will shall
with as at by on from into out up down over under about after before between during within
we you they he she i our your their don't doesn't isn't aren't wasn't weren't
have has had having there here when where which who whom whose what why how all any both each
few more most other some such only own same so than too very s t just now
def class self return none true false pass import from as elif try except raise
todo note fixme xxx hack use used using new old one two three first second last
also thus hence therefore however when while case cases type types value values
name names list lists dict set tuple str int float bool array arrays index indices
like unlike make makes made get gets""".split())

# A citation is `<path>.py:<line>`. The path may be qualified with `/`.
CITE_RE = re.compile(r"([A-Za-z_0-9][A-Za-z_0-9/]*\.py):(\d+)")
# The port's own quote of upstream's words: `-- "..."`.
QUOTE_RE = re.compile(r'--\s*"([^"]{8,})"')

# The port says "upstream does X, we do Y" -- an explicit CONTRAST.
CONTRAST_RE = re.compile(
    r"\bDEPARTURE\b|\bDEPARTS?\b|\bDIVERGES?\b|\bDIFFERENT(?:LY)?\b"
    r"|\bCONTRAST\b|\bUNLIKE UPSTREAM\b|\bNOT UPSTREAM\b|\bUPSTREAM'S\b"
    r"|\bINSTEAD OF\b|\bRATHER THAN\b|\bTHIS PORT\b|\bTHE PORT(?:'S)?\b"
    r"|\bPORT-ONLY\b|\bTHE WALL\b|\bA WALL\b|\bNOT PORTED\b"
    r"|\bCONTRAST(?:S|ED)? WITH\b|\bDOES NOT APPLY\b|\bNO SUCH\b",
    re.IGNORECASE,
)

# The upstream files the port RENAMED. The discovery cannot make these, and
# the tree's own history records each of them.
ALIASES = {
    "codegen/decomp/transcendental.py": "codegen/decomp/transcendental.bend",
    "renderer/x86.py": "renderer/isa/x86.bend",
    "runtime/support/amd.py": "runtime/support/amd.bend",
    "runtime/support/nv/nvdev.py": "runtime/support/nv/nvdev.bend",
    "runtime/support/nv/ip.py": "runtime/support/nv/ip.bend",
    "runtime/support/am/ip.py": "runtime/support/am/ip.bend",
    "runtime/support/am/amdev.py": "runtime/support/am/amdev.bend",
    "runtime/support/system.py": "runtime/support/system.bend",
    "runtime/support/hcq2.py": "runtime/support/hcq2.bend",
    "runtime/support/memory.py": "runtime/support/memory.bend",
    "runtime/support/elf.py": "runtime/support/elf.bend",
    "runtime/support/compiler_amd.py": "runtime/support/compiler_amd.bend",
    "runtime/support/compiler_cpu.py": "runtime/support/compiler_cpu.bend",
    "runtime/support/compiler_cuda.py": "runtime/support/compiler_cuda.bend",
    "runtime/support/compiler_llvm.py": "runtime/support/compiler_llvm.bend",
    "runtime/support/compiler_mesa.py": "runtime/support/compiler_mesa.bend",
    "runtime/support/compiler_qcom.py": "runtime/support/compiler_qcom.bend",
    "runtime/support/compileserver.py": "runtime/support/compileserver.bend",
    "runtime/support/c.py": "runtime/support/c.bend",
    "runtime/support/objc.py": "runtime/support/objc.bend",
    "runtime/support/rdma/bnxtdev.py": "runtime/support/rdma/bnxtdev.bend",
    "runtime/support/usb.py": "runtime/support/usb.bend",
    "runtime/support/autogen.py": "runtime/support/autogen.bend",
    "schedule/rangify.py": "schedule/rangify.bend",
    "runtime/ops_bend.py": "runtime/ops_bend.bend",
}


def content_tokens(text: str) -> list[str]:
    """The CONTENT tokens of `text`: words of >= 3 characters, lowercased,
    minus the stopwords. A TOKEN IS A WORD, NOT A CHARACTER."""
    return [w for w in TOKEN_RE.findall(text.lower()) if w not in STOPWORDS]


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


# --------------------------------------------------------------------------
# THE TWO POPULATIONS
# --------------------------------------------------------------------------

# The tree's OWN scratch rule, LOADED BY PATH and not re-spelled here. A
# second copy of a carve-out is a contract with no generator, and this rule
# already lives in the tree in one place.
SCRATCH_RULE = os.path.join(REPO, "gates", "header-census-gate.py")


def _load_scratch_rule():
    """`gates/header-census-gate.py`'s `is_scratch()`, loaded by path.

    `.gitignore:36` ignores `*mut.bend`, so a mutation-probe copy of a port
    file sits IN THE WORKING COPY and is picked up by an `os.walk`. It is
    NOT a source file: a census that counted one would report a citation
    nobody could fix, and -- worse -- its denominator would not reproduce in
    a clone. `.gitignore:58` says it outright: "A CENSUS WHOSE POPULATION
    IS THE WORKING COPY HAS NO REPRODUCIBLE DENOMINATOR."

    THE RULE IS NOT RE-SPELLED HERE. It is READ OUT of the tree's own
    instrument, so a change to the tree's rule moves this one with it.
    """
    import importlib.util
    spec = importlib.util.spec_from_file_location("_scratch_rule", SCRATCH_RULE)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load the tree's scratch rule from {SCRATCH_RULE}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.is_scratch


def _walk(root: str, suffix: str, skip=None) -> list[str]:
    """Every file under `root` whose name ends with `suffix`.

    THE ORDER IS `os.walk`'s OWN DIRECTORY ORDER, with the files WITHIN a
    directory sorted. This is NOT cosmetic: the carry test breaks a tie by
    the LOWEST block index, so the order of the walk decides WHICH port
    block is reported as the carrier when two of them carry the same
    reasoning. `os.walk` yields a directory's SUBDIRECTORIES before its
    files, and the tree's own directory order is stable, so the walk is
    deterministic -- but it is NOT alphabetical, and a generator that
    alphabetises it reports a different carrier.

    `os.walk` + `endswith`, because `glob('*.bend')` returns `[]` when the
    files ARE on disk.
    """
    out = []
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for f in sorted(fn):
            if f.endswith(suffix) and not (skip and skip(f)):
                out.append(os.path.join(dp, f))
    return out


def _comment_blocks(path: str) -> list[dict]:
    """The contiguous `#` comment blocks of a file, in order. A block is a
    maximal run of lines whose STRIPPED form starts with `#`; trailing blank
    comment lines are dropped, and a block with nothing left is not a block."""
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    out = []
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
                out.append({
                    "file": os.path.relpath(path, UP) if path.startswith(UP) else os.path.relpath(path, PORT),
                    "line": i + 1,
                    "end_line": j,
                    "body": body,
                    "text": " ".join(x for x in body if x),
                })
            i = j
        else:
            i += 1
    return out


def upstream_blocks() -> list[dict]:
    blocks = []
    for p in _walk(UP, ".py"):
        blocks.extend(_comment_blocks(p))
    return blocks


def port_blocks(skip_scratch=True) -> list[dict]:
    """The port's `.bend` comment blocks.

    THE SCRATCH RULE EXCLUDES THE MUTATION-PROBE COPIES. They are IN the
    working copy -- `.gitignore:36` ignores `*mut.bend` -- and an `os.walk`
    cannot tell a probe from a source. A census whose population is the
    working copy has no reproducible denominator, which is the tree's own
    rule (`.gitignore:58`).
    """
    skip = _load_scratch_rule() if skip_scratch else None
    blocks = []
    for p in _walk(PORT, ".bend", skip=skip):
        for b in _comment_blocks(p):
            b["file"] = os.path.relpath(p, PORT)
            blocks.append(b)
    return blocks


# --------------------------------------------------------------------------
# THE FILE MAP: which upstream file has a port counterpart
# --------------------------------------------------------------------------


def stem(p: str) -> str:
    b = os.path.basename(p)
    return b[:-3] if b.endswith(".py") else b[:-5]


def build_filemap(up_files: list[str], port_files: list[str]) -> dict[str, list[str]]:
    m = collections.defaultdict(list)
    pstems: dict[str, list[str]] = collections.defaultdict(list)
    for p in port_files:
        pstems[stem(p)].append(p)
    for u in up_files:
        if u in ALIASES:
            m[u].append(ALIASES[u])
            continue
        cand = u[:-3] + ".bend"
        if cand in port_files:
            m[u].append(cand)
            continue
        hits = pstems.get(stem(u), [])
        if len(hits) == 1:
            m[u].append(hits[0])
            continue
        if hits:
            m[u].extend(hits)
            continue
        best = difflib.get_close_matches(stem(u), [stem(p) for p in port_files], n=1, cutoff=0.8)
        if best:
            m[u].extend(p for p in port_files if stem(p) == best[0])
    return m


# --------------------------------------------------------------------------
# THE RESOLVER: a cited basename -> the upstream file it means
# --------------------------------------------------------------------------


class Upstream:
    """The upstream corpus: every `.py` under `tinygrad/`, plus the repo-root
    upstream that lives BESIDE `tinygrad/` (`extra/`, `examples/`)."""

    def __init__(self) -> None:
        self.lines: dict[str, list[str]] = {}
        for p in _walk(UP, ".py"):
            rel = os.path.relpath(p, UP)
            self.lines[rel] = open(p, encoding="utf-8", errors="replace").read().splitlines()
        for sub in ("extra", "examples"):
            r = os.path.join(REPO, sub)
            if not os.path.isdir(r):
                continue
            for p in _walk(r, ".py"):
                rel = os.path.relpath(p, REPO)
                self.lines.setdefault(rel, open(p, encoding="utf-8", errors="replace").read().splitlines())
        self.bybase: dict[str, list[str]] = collections.defaultdict(list)
        for rel in sorted(self.lines):
            self.bybase[os.path.basename(rel)].append(rel)

    def read(self, rel: str) -> list[str] | None:
        return self.lines.get(rel)


def resolve_citation(up: Upstream, cited: str, cite_line: int, port_file: str,
                     ctx: str) -> tuple[str | None, str]:
    """A cited subject -> `(upstream path, how)`.

    THE ORDER IS THE ORDER OF EVIDENCE. An EXACT path is the citation's own
    spelling. A unique BASENAME needs no help. Beyond that the candidates are
    SCORED, and the score is the amount of evidence, in this order:

      200  the citing block's neighbourhood spells the candidate's FULL path
            (`schedule/memory.py`), which is what the port does when it wants
            to be unambiguous;
       80  the neighbourhood spells the candidate's path WITHOUT its first
            segment (`memory.py` for `schedule/memory.py`);
        1  each context token of >= 5 characters that occurs in the WINDOW
            around the cited line of that candidate -- a pointer at line N
            cannot be about a file with fewer than N lines, and it should not
            be about a file whose line N says something else.

    THE SCORE IS A SUM, so a candidate that the neighbourhood names BEATS a
    candidate whose line merely shares vocabulary. That is the right order:
    the port's own prose is evidence about what the port MEANS, and a token
    overlap is only evidence about what the port happens to have written.

    WHEN THE BASENAME IS STILL AMBIGUOUS THE RESOLUTION IS SAID SO, in `how`,
    because a join key that was guessed is a join key a reader must be able
    to challenge.
    """
    # The port writes `tinygrad/runtime/support/memory.py:23` to name an
    # upstream file. The upstream corpus is keyed RELATIVE TO `tinygrad/`,
    # so the prefix is stripped before the exact-path test -- otherwise the
    # port's own fully-qualified spelling would fall through to the
    # basename and be resolved by score, which is a guess where the port
    # was explicit.
    #
    # `--legacy-resolver` turns the prefix-stripping OFF, which is what the
    # predecessor's instrument did. The difference is ONE ROW of 2406
    # (`schedule/memory.py:23`), and the ledger carries the PREDECESSOR's
    # answer: the port's fully-qualified `tinygrad/runtime/support/memory.py`
    # was resolved to `schedule/memory.py`, which the port's own next line
    # says is "a different file, not ported". The legacy mode is here so the
    # predecessor's ledger can be reproduced byte for byte, and it is NOT
    # the default because the default is RIGHT.
    if not LEGACY_RESOLVER:
        for pre in ("tinygrad/", "tinybendygrad/"):
            if cited.startswith(pre):
                cited = cited[len(pre):]
                break
    if up.read(cited) is not None:
        return cited, "exact-path"
    if "/" in cited:
        pdir = os.path.dirname(port_file)
        for base in (pdir, os.path.dirname(pdir), ""):
            cand = os.path.normpath(os.path.join(base, cited)) if base else cited
            if up.read(cand) is not None:
                return cand, "path-relative-to-the-port-file"
    base = os.path.basename(cited)
    cands = list(up.bybase.get(base, []))
    if not cands:
        return None, "absent"
    if len(cands) == 1:
        return cands[0], "unique-basename"
    ctx_tokens = set(re.findall(r"[A-Za-z_][A-Za-z_0-9]{4,}", ctx))
    best, best_score = None, -1
    for rel in cands:
        lines = up.read(rel) or []
        score = 0
        if rel in ctx:
            score += 200
        if "/" in rel and rel.split("/", 1)[1] in ctx:
            score += 80
        if 0 < cite_line <= len(lines):
            window = " ".join(lines[max(0, cite_line - 5):cite_line + 5]).lower()
            for tok in ctx_tokens:
                if tok.lower() in window:
                    score += 1
        if score > best_score:
            best, best_score = rel, score
    if best is None:
        return None, "absent"
    return best, f"ambiguous:{len(cands)}->scored"


# --------------------------------------------------------------------------
# THE CARRY: does a port block carry the upstream block's reasoning?
# --------------------------------------------------------------------------


class Carry:
    """The carry test, over a fixed pool of port comment blocks.

    THE PHRASE RULE. A contiguous run of >= 4 content tokens of the upstream
    block, present as a contiguous run in the port block's own token stream.
    A 4-token phrase is evidence only when the upstream text is SHORT -- a
    4-token slice of a 12-token block is a coincidence, and a 5+-token
    phrase is evidence on its own.

    THE SEQ RULE. A contiguous run of >= 3 DISTINCTIVE tokens -- tokens rare
    in the port -- taken from the upstream block's own token sequence and
    matched as a contiguous run in the port's. The distinctive tokens are
    indexed by their DOCUMENT FREQUENCY in the port's comment blocks, so a
    common word is not evidence and a rare one is.
    """

    def __init__(self, pblocks: list[dict]) -> None:
        self.pblocks = pblocks
        self.seqs = [content_tokens(pb["text"]) for pb in pblocks]
        self.files = [pb["file"] for pb in pblocks]
        df = collections.Counter()
        for s in self.seqs:
            for t in set(s):
                df[t] += 1
        self.df = df
        self.rare_thresh = max(4, len(pblocks) // 40)
        self.gram: dict[str, set[int]] = collections.defaultdict(set)
        self.gram5: dict[str, set[int]] = collections.defaultdict(set)
        for i, s in enumerate(self.seqs):
            for j in range(len(s) - 3):
                self.gram[" ".join(s[j:j + 4])].add(i)
            for j in range(len(s) - 4):
                self.gram5[" ".join(s[j:j + 5])].add(i)
        self.inv: dict[str, set[int]] = collections.defaultdict(set)
        for i, s in enumerate(self.seqs):
            for t in set(s):
                if df[t] <= self.rare_thresh:
                    self.inv[t].add(i)

    def phrase_hits(self, us: list[str]) -> tuple[int, set[int]]:
        """The LONGEST phrase of `us` that some port block carries, and the
        blocks that carry it."""
        for n in (min(len(us), 14), 12, 10, 9, 8, 7, 6, 5, 4):
            if n > len(us):
                continue
            acc: set[int] = set()
            for j in range(len(us) - n + 1):
                g = " ".join(us[j:j + n])
                idxs = self.gram5.get(g)
                if idxs is None:
                    idxs = self.gram.get(g)
                if idxs:
                    acc |= idxs
            if acc:
                return n, acc
        return 0, set()

    def score(self, up_text: str, up_body: list[str], pool: set[int]) -> tuple[float, str, int | None]:
        """-> `(score, kind, port block index)`; `score == 0` means NOT carried."""
        us = content_tokens(up_text)
        best = (0.0, "", None)
        variants = [("block", us)]
        for k, line in enumerate(up_body):
            lt = content_tokens(line)
            if len(lt) >= 3:
                variants.append((f"line{k + 1}", lt))
        for vlabel, vs in variants:
            n, idxs = self.phrase_hits(vs) if len(vs) >= 4 else (0, set())
            if not n:
                continue
            cand = idxs if pool is None else (idxs & pool)
            if not cand:
                continue
            frac = n / max(1, len(vs))
            ok = (n >= 5) or (n >= 4 and len(vs) <= 6)
            if ok and frac >= 0.25 and frac > best[0]:
                best = (frac, f"{vlabel}:phrase{n}", min(cand))
        if best[0] > 0:
            return best
        # --- the SEQ rule, only when the phrase rule did not fire ---
        ua = set(us)
        distinct = [t for t in us if self.df.get(t, 0) <= self.rare_thresh]
        dset = set(distinct)
        dpos = [i for i, t in enumerate(us) if t in dset]
        if len(dpos) >= 3:
            cand: set[int] = set()
            for t in distinct:
                cand |= self.inv.get(t, set())
            if pool is not None:
                cand &= pool
            tgt = [us[j] for j in dpos]
            best_run, cidx = 0, None
            for i in sorted(cand):
                run = 0
                for t in self.seqs[i]:
                    if run < len(tgt) and t == tgt[run]:
                        run += 1
                        if run > best_run:
                            best_run, cidx = run, i
                    else:
                        run = 0
            if best_run >= 3:
                return (best_run / max(1, len(us)), f"seq{best_run}", cidx)
        return (0.0, "", None)


# --------------------------------------------------------------------------
# THE LEDGER
# --------------------------------------------------------------------------

HEADER = "upstream_file\tupstream_line\tblock_first_words\tported\tport_citation\tverdict\tnote"


def build_rows(skip_scratch: bool = True) -> tuple[list[list[str]], dict]:
    up = Upstream()
    upfiles = sorted(up.lines)
    port_files = [os.path.relpath(p, PORT)
                  for p in _walk(PORT, ".bend", skip=_load_scratch_rule() if skip_scratch else None)]
    filemap = build_filemap(upfiles, port_files)

    blocks = upstream_blocks()
    pblocks = port_blocks(skip_scratch)
    carry = Carry(pblocks)

    # --- the citations, and where each one resolves ---
    pbyfile: dict[str, list[dict]] = collections.defaultdict(list)
    for pb in pblocks:
        pbyfile[pb["file"]].append(pb)

    cites = []
    ambiguity: collections.Counter = collections.Counter()
    for pb in pblocks:
        sibs = pbyfile[pb["file"]]
        idx = sibs.index(pb)
        ctx = "\n".join(b["text"] for b in sibs[max(0, idx - 2):idx + 3])
        for k, ln in enumerate(pb["body"]):
            for m in CITE_RE.finditer(ln):
                rel, how = resolve_citation(up, m.group(1), int(m.group(2)), pb["file"], ctx)
                if how.startswith("ambiguous"):
                    ambiguity[m.group(1)] += 1
                cites.append({
                    "port_file": pb["file"],
                    "port_line": pb["line"] + k,
                    "port_block_line": pb["line"],
                    "port_block_text": pb["text"],
                    "cite_file": m.group(1),
                    "cite_line": int(m.group(2)),
                    "up_file": rel,
                    "how": how,
                })

    # --- the join: upstream (file, line) -> the port blocks citing it ---
    citing: dict[tuple[str, int], list[dict]] = collections.defaultdict(list)
    for c in cites:
        if c["up_file"] is None:
            continue
        if not (0 < c["cite_line"] <= len(up.read(c["up_file"]) or [])):
            continue
        citing[(c["up_file"], c["cite_line"])].append(c)

    rows = []
    for b in blocks:
        hits = []
        seen = set()
        for ln in range(b["line"], b["end_line"] + 1):
            for h in citing.get((b["file"], ln), []):
                key = (h["port_file"], h["up_file"], h["cite_line"])
                if key not in seen:
                    seen.add(key)
                    hits.append(h)
        cite_files = {h["port_file"] for h in hits}

        # THE CARRY TEST RUNS FOR EVERY ROW, INCLUDING THE `N/A` ONES. The
        # `N/A` verdict says the upstream FILE has no port counterpart; it
        # does not say the port never mentioned the upstream's words, and the
        # ledger's `port_citation` column records WHERE the port did -- so
        # the location is computed for these rows too.
        pool = None
        if hits:
            pool = {i for i, pb in enumerate(pblocks) if pb["file"] in cite_files}
        score, carry_kind, carry_idx = carry.score(b["text"], b["body"], pool)

        if not filemap.get(b["file"]):
            verdict = "N/A-PYTHON-ONLY"
        elif score > 0:
            verdict = "PORTED"
        elif hits:
            verdict = "GAP-CITED-NO-REASONING"
        else:
            verdict = "GAP-NO-CITATION"

        # --- the port's citation, if there is one ---
        inside = [h for h in hits if b["line"] <= h["cite_line"] <= b["end_line"]]
        citation = ""
        if inside:
            h = inside[0]
            citation = f"{h['port_file']}:{h['port_line']} -> {h['cite_file']}:{h['cite_line']}"
        elif hits:
            h = hits[0]
            citation = f"{h['port_file']}:{h['port_line']} -> {h['cite_file']}:{h['cite_line']}"

        # --- the port line that carries the reasoning, if it does ---
        pline = ""
        if carry_idx is not None:
            p = pblocks[carry_idx]
            pline = f"{p['file']}:{p['line']}"

        # --- the port's own reasoning, and whether it DIFFERS ---
        if verdict != "PORTED" and hits:
            for h in hits:
                pb = next((p for p in pblocks
                           if p["file"] == h["port_file"] and p["line"] == h.get("port_block_line", h["port_line"])),
                          None)
                if pb is None:
                    continue
                t = pb["text"]
                if not CONTRAST_RE.search(t):
                    continue
                if b["file"].split("/")[-1][:-3] not in t and h["cite_file"].split("/")[-1][:-3] not in t:
                    continue
                verdict = "GAP-DIFFERENT-REASONING"
                note = "port cites it and reasons differently, saying so"
                pline = f"{pb['file']}:{pb['line']}"
                break

        if verdict == "PORTED":
            note = f"carried via {carry_kind} at {pline or '(same file)'}"
        elif verdict == "GAP-CITED-NO-REASONING":
            note = "cited, reasoning not carried"
        elif verdict == "GAP-NO-CITATION":
            note = "no citation anywhere in the port"
        elif verdict == "N/A-PYTHON-ONLY":
            note = "no port counterpart (generated binding / not ported)"

        words = b["text"].split()
        fw = " ".join(words[:8])[:90]
        rows.append([b["file"], str(b["line"]), fw,
                     "yes" if verdict == "PORTED" else "no",
                     citation or pline, verdict, note])

    rows.sort(key=lambda r: (r[0], int(r[1])))
    stats = {
        "rows": len(rows),
        "verdicts": collections.Counter(r[5] for r in rows),
        "ambiguous_citations": dict(sorted(ambiguity.items())),
        "ambiguous_total": sum(ambiguity.values()),
        "citations": len(cites),
        "port_blocks": len(pblocks),
        "upstream_files": len(upfiles),
        "substrate": substrate(),
    }
    return rows, stats


def substrate() -> str:
    """THE SHA256 OF EVERY PORT FILE THE LEDGER READ, and of every upstream
    file. A ledger and the substrate it was taken of belong together: the
    ledger records PORT LINE NUMBERS, so two ledgers of DIFFERENT substrates
    are different ledgers, and a reader must be able to tell them apart
    without guessing."""
    h = hashlib.sha256()
    for p in sorted(_walk(PORT, ".bend")) + sorted(_walk(UP, ".py")):
        h.update(os.path.relpath(p, REPO).encode())
        h.update(b"\0")
        h.update(open(p, "rb").read())
        h.update(b"\0")
    return h.hexdigest()


def render(rows: list[list[str]]) -> str:
    out = [HEADER]
    for r in rows:
        out.append("\t".join(x.replace("\t", " ").replace("\n", " ") for x in r))
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=LEDGER, help="where to write the ledger")
    ap.add_argument("--check", action="store_true",
                    help="do not overwrite; report how the fresh ledger differs from --out")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--ambiguity", action="store_true", help="print the ambiguous-basename census")
    ap.add_argument("--include-scratch", action="store_true",
                    help="include the GITIGNORED mutation-probe copies of port files "
                         "(the predecessor's population; NOT reproducible in a clone)")
    ap.add_argument("--legacy-resolver", action="store_true",
                    help="do NOT strip the `tinygrad/` prefix before the exact-path "
                         "test (the predecessor's resolver; ONE row of 2406 differs)")
    ap.add_argument("--substrate", action="store_true",
                    help="print the sha256 of every file the ledger read")
    args = ap.parse_args(argv)

    global LEGACY_RESOLVER
    LEGACY_RESOLVER = args.legacy_resolver

    rows, stats = build_rows(skip_scratch=not args.include_scratch)
    text = render(rows)

    if args.substrate:
        print(f"SUBSTRATE  : {stats['substrate']}")

    if args.check:
        old = open(args.out, encoding="utf-8").read() if os.path.exists(args.out) else ""
        if old == text:
            print(f"IDENTICAL: {args.out} ({stats['rows']} rows)")
            return 0
        o = old.split("\n")
        n = text.split("\n")
        diff = list(difflib.unified_diff(o, n, fromfile=args.out, tofile="fresh", lineterm="", n=0))
        print(f"DIFFERENT: {args.out} vs fresh ({stats['rows']} rows). {len(diff)} diff lines:")
        for line in diff[:400]:
            print("  " + line)
        if len(diff) > 400:
            print(f"  ... and {len(diff) - 400} more diff lines")
        return 1

    with open(args.out, "w", encoding="utf-8") as f:
        f.write(text)
    if not args.quiet:
        print(f"wrote {args.out}: {stats['rows']} rows")
        for k, n in stats["verdicts"].most_common():
            print(f"  {k}: {n}")
        print(f"citations: {stats['citations']}  port blocks: {stats['port_blocks']}")
        print(f"ambiguous-basename citations: {stats['ambiguous_total']}")
        print(f"substrate: {stats['substrate']}")
    if args.ambiguity:
        for k, n in stats["ambiguous_citations"].items():
            print(f"  {n:5d}  {k}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
