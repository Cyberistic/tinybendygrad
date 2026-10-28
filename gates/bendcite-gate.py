#!/usr/bin/env python3
"""bendcite-gate.py -- THE PORT'S OWN POINTERS: every `.bend` -> `.bend` LINE citation, judged.

    .venv/bin/python gates/bendcite-gate.py
    .venv/bin/python gates/bendcite-gate.py --rows OUT.rows
    .venv/bin/python gates/bendcite-gate.py --report
    .venv/bin/python gates/bendcite-gate.py --plant
    .venv/bin/python gates/bendcite-gate.py --tree DIR      # judge a COPY of the port

ZERO `bend` LANES. The subject is a `.bend` file's own COMMENT, and a citation of a
line is not code, so a comment stripper makes every one of them vanish while reporting
rc=0 PASS -- the same asymmetry `gates/citations-census-gate.py` established for
MARKDOWN and `gates/header-census-gate.py` for the port's HEADERS. This file asks the
question neither of them asks: **the port's pointers to ITSELF.**

WHAT IS UNMEASURED TODAY, MEASURED 2026-10-25. `gates/todo-cite-gate.py` admits only
`TODO(pN)` markers and `symbol=` fields on `.py` subjects; `gates/pin-cite-gate.py` reads
the upstream HEADER blocks; `gates/header-census-gate.py` reads the port's header blocks.
**NOT ONE INSTRUMENT IN THIS TREE READS A `.bend`-TO-`.bend` LINE CITATION.** MEASURED on
the tree this file was written against: **1,251** such citations across **166** `.bend`
source files, and **NONE** of them was checked by anything. The pointers ROT every time
a `.bend` file's lines move, and they move constantly.

THE DURABLE FORM IS `symbol=<name>`, AND THIS FILE IS THE CASE FOR IT. A LINE NUMBER
rots and a NAME does not, so the defect this gate measures is the defect the tree's own
`symbol=` convention removes. Every row reports the construct that IS at the cited line,
so a later unit can convert a pointer to a name without re-deriving what it pointed at.

THE POPULATION IS DISCOVERED, NEVER NAMED. `os.walk` over `tinybendygrad/` plus
`endswith(".bend")`, because `glob('*.bend')` returns `[]` when the files ARE on disk --
the trap `AGENTS.md` records. **AND THE SCRATCH RULE IS THE TREE's OWN, LOADED BY PATH:**
`gates/header-census-gate.py`'s `is_scratch()`, because a mutation-probe scratch copy is
NOT a source file and a census that counted one would report a false citation NOBODY
COULD FIX. The rule is not re-spelled here: a second copy of a carve-out is a contract
with no generator.

THE CITED CORPUS IS BIGGER THAN THE CITING POPULATION, AND THE DIFFERENCE IS A
MEASUREMENT. The port cites the Bend COMPILER's own `references/bend/bend2/base.bend` --
`base.bend:1542` claims `U32.is_even`, and `tinybendygrad/base.bend` is a 56-LINE file
while `references/bend/bend2/base.bend` is 3,191 lines and declares `U32.is_even` at
:1648. **A POINTER CANNOT BE ABOUT A FILE THAT DOES NOT HAVE THE LINE**, so the two
`base.bend`s are told apart by WHICH ONE HAS THE CITED LINE, and the tie-break is
recorded in the row's `how`. The compiler's tree is a RESOLUTION corpus and not a
population: it is reported as its own stratum so a reader can subtract it.

HOW A CITED FILE IS RESOLVED. A `.bend` citation spells its subject four ways --
`ops.bend`, `uop/ops.bend`, `tinybendygrad/uop/ops.bend` and `LAWS/spec.bend` -- and the
corpus holds **seven** basenames that are NOT unique (`spec.bend` is `LAWS/spec.bend`
AND `uop/spec.bend`; `op.bend` is `codegen/decomp/op.bend` AND `mixin/op.bend`). A bare
basename is therefore AMBIGUOUS more often than it is not, and the disambiguator is the
citing file's OWN `import` list: the port writes `import ./../uop/ops.bend as O`, so the
import NAMES the path a bare `ops.bend` means. THE IMPORT IS THE ANSWER, AND IT IS
DISCOVERED.

THE CLAIM, AND WHAT MAKES ONE CHECKABLE. The port writes the thing it means in
BACKTICKS, and `gates/pin-cite-gate.py`'s `claim_tokens` -- LOADED BY PATH, not copied --
is the rule for reading them: a backticked span that IS a citation is the citation and
not the claim, and a name belongs to the NEAREST citation. A citation is CHECKABLE only
if one of its claim tokens is a CONSTRUCT the cited file DECLARES: a pointer whose line
names nothing the target holds makes no claim about that target, so it is COUNTED AND
NOT VERDICTED. An unfalsifiable claim is not a passing claim, and it is not a failing
one either.

**THE CLAIM TOKEN IS THE WHOLE DOTTED NAME, AND THAT IS LOAD-BEARING.** The port writes
`SInt.uop` for a `def SInt.uop(...)` and `F.alu_ds` for a `def alu_ds(...)` under the
alias `F`. MEASURED: splitting the dotted name into its components made `ops.bend:823`
READ AS RESOLVES, because the component `SInt` is a word on the cited line
(`def SInt.uop_of(...)`) -- and `ops.bend:823` is one of the pointers that is KNOWN to be
stale (`SInt.uop` is declared at :815). So the token is the dotted name, and the
LAST COMPONENT is used only when the dotted name is not a thing the target file says --
which is exactly the ALIAS case, because `F` is the citing file's alias and `F.alu_ds`
is not a name `fold.bend` contains.

THE VERDICTS, AND WHICH OF THEM IS A FAILURE.

  RESOLVES       the cited line (or range) HOLDS the claimed construct: it names it, it
                 DECLARES it, it is inside its body, or it is inside the comment run
                 that documents it. `how` says which.
  WRONG-LINE     the cited file holds the claimed construct ELSEWHERE. **THIS IS THE
                 ROT.** The row reports where the construct IS and by how many lines the
                 pointer moved. A FAIL.
  DANGLING-LINE  the cited line or range is OUTSIDE the cited file. A FAIL.
  ABSENT-FILE    the subject names a file the port HAS BY NAME and the cited path is
                 gone. A FAIL.
  AMBIGUOUS      the subject names more than one file and nothing settles it. Counted,
                 not failed: a refusal to guess is not a false claim.
  UNCLAIMED      the pointer resolves and lands in the file, but the citing text names
                 nothing the target holds -- so there is no claim to falsify. Counted and
                 REPORTED, with the construct that IS at the cited line.
  OUT-OF-CORPUS  the subject is not a `.bend` file this tree holds at all. Counted, not
                 failed.

**A VERDICT THAT FAILS ON A CLAIM IT CANNOT READ WOULD BE A FALSE ROW**, so the two
non-failing classes above are counted and PRINTED with their reason rather than dropped.
A rule that drops rows and does not say how many is indistinguishable from a rule that
never matched them.

THE EXITS ARE `gates/gatekit.py`'s five: 0 PASS, 1 FAIL, 3 REFUSED (a needed sibling
instrument will not load, or the port tree is absent), 4 SKIP, 5 DEAD (no row was
emitted).

THE GATE IS RED ON THIS TREE AND SAYS SO. A red gate is a list of defects to strike; a
green one that was green because it measured nothing is worse.
"""

from __future__ import annotations

import collections
import importlib.util
import os
import re
import shutil
import sys
import tempfile
import traceback
import warnings
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

PORT_REL = "tinybendygrad"
#: THE COMPILER's OWN TREE. The port cites into it (`base.bend:1542` is the compiler's
#: `U32.is_even`, not the port's 56-line `base.bend`), so it is a RESOLUTION corpus and
#: not a population. Its absence changes the resolution of the `base.bend` pointers and
#: is reported when it happens.
COMPILER_REL = "references/bend/bend2"


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


# --------------------------------------------------------------------------- the shapes

#: A `.bend` citation: `ops.bend:823`, `fold.bend:1620-1626`, `uop/ops.bend:1167`.
CITE = re.compile(r"([A-Za-z0-9_./-]*[A-Za-z0-9_]\.bend)\s*:\s*(\d+)(?:\s*-\s*(\d+))?")
#: The port's own import line: `import ./../uop/ops.bend as O`.
IMPORT = re.compile(r"^\s*import\s+(\S+)(?:\s+as\s+(\S+))?")
#: A DOTTED NAME, whole: `SInt.uop`, `eq_const.CFloat`, `Arena`.
DOTTED = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*")
#: A `.bend` DECLARATION, at column 0: `def X`, `def Owner.member`, `type X is`, `law X`.
BEND_DECL = re.compile(r"^(?:def|type|law)\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)")
#: An ADT VARIANT: an indented `AInk{ins: String, dt: S.Dt}` inside a `type X is Data:`.
BEND_VARIANT = re.compile(r"^\s+([A-Z][A-Za-z0-9_]*)\{")
#: THE `symbol=` FIELD, the tree's own durable form. `gates/todo-cite-gate.py` spells it
#: the same way; a field NAME is a lexical shape and not a population, so it is not
#: loaded by path -- but the tree's rule of one rule in one place is why this line says
#: where its twin is.
SYMBOL_FIELD = re.compile(r"\bsymbol\s*=\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)")
#: WORDS THAT NAME NOTHING. `pin-cite-gate.py`'s KEYWORDS holds `None`, `True` and
#: `False` in CAPITAL form and compares them against a lowercased token, so they are NOT
#: filtered there; in a `.bend` file `None{}` is a literal and a claim about it is about
#: a VALUE. Measured: `codegen/decomp/op.bend:264` cites `spec.bend:207` and backticks
#: `None{}`, and `None` is not a construct.
NOT_A_NAME = frozenset("""none some true false def type law import export match case else if then
else elif return let var fn struct enum impl trait use mod pub const static mut move ref self super where
loop while for in break continue as and or not is has been null undefined void nil true""".split())


def bend_constructs(body: list[str]) -> list[tuple[str, int, int, int]]:
  """`(name, decl line, span start, span end)` for every construct a `.bend` file declares.

  FOUR FORMS, AND THE PORT USES ALL FOUR: `def X(...)`, `def Owner.member(...)`,
  `type X is Data:` and `law X:` at column 0, plus the ADT VARIANTS (`AInk{...}`) that
  live inside a `type` block. A variant is a named thing and a claim may name it.

  THE SPAN INCLUDES THE COMMENT RUN THAT DOCUMENTS THE DECLARATION. **A POINTER AT THE
  DOC COMMENT ABOVE A `def` IS A POINTER AT THAT `def`**, and in this port the comment
  above a `def` is part of the `def` -- it carries the upstream citation the `def` was
  ported from. Without this, every pointer at a doc comment reads as stale, and the
  gate's red would be a list of pointers that are RIGHT.
  """
  out: list[tuple[str, int, int, int]] = []
  decls: list[tuple[int, str]] = []
  for i, raw in enumerate(body, 1):
    m = BEND_DECL.match(raw)
    if m:
      decls.append((i, m.group(1)))
  for k, (decl, name) in enumerate(decls):
    nxt = decls[k + 1][0] if k + 1 < len(decls) else len(body) + 1
    end = decl
    for j in range(decl, nxt - 1):
      if body[j].strip() and not body[j].startswith(" "):
        break
      if body[j].strip():
        end = j + 1
    start = decl
    j = decl - 2
    while j >= 0 and body[j].lstrip().startswith("#"):
      start = j + 1
      j -= 1
    out.append((name, decl, start, end))
  in_type = False
  for i, raw in enumerate(body, 1):
    if raw.startswith("type ") and " is" in raw:
      in_type = True
      continue
    if raw and not raw.startswith(" "):
      in_type = False
      continue
    if in_type:
      m = BEND_VARIANT.match(raw)
      if m:
        out.append((m.group(1), i, i, i))
  return out


def bend_names(span: str) -> list[str]:
  """The DOTTED names a backticked span names, whole.

  **THE HEAD ONLY.** The port writes `Arena{nodes: List<Node>}` to mean the TYPE
  `Arena` and `AInk{ins: String, dt: S.Dt}` to mean the variant `AInk`; the braces carry
  FIELDS, and a field is not a construct. MEASURED: taking the whole span put `Node` --
  a real construct of `uop/ops.bend` -- into the claim set of a pointer about `Arena`,
  and the pointer was then judged against the wrong construct."""
  head = re.split(r"[{(]", span, 1)[0]
  head = head.strip().strip("`")
  if not head or ":" in head:
    return []
  return DOTTED.findall(head)


class Corpus:
  """THE `.bend` FILES A POINTER MAY NAME, indexed the ways a citation can spell one.

  THE INDEX IS BUILT FROM THE WALK, so a `.bend` file that appears on disk is in it
  without an edit here, and a file that does not is not. `git ls-files` is NOT consulted:
  it reads the INDEX, and this tree arms that index with intent-to-add placeholders by
  design (`jj git colocation`), so it would answer a different population than the one
  the port is made of.
  """

  def __init__(self, base: Path):
    self.base = base
    self.port: list[str] = []
    self.extra: list[str] = []
    self.bodies: dict[str, list[str]] = {}
    self.by_name: dict[str, list[str]] = collections.defaultdict(list)
    self.imports: dict[str, list[str]] = {}
    self.aliases: dict[str, dict[str, str]] = {}
    self.constructs: dict[str, list[tuple[str, int, int, int]]] = {}
    self.words: dict[str, set[str]] = {}
    self.excluded: list[str] = []
    self.is_scratch = load_sibling("bendcite_census", "header-census-gate.py").is_scratch
    self._scan()

  def _walk(self, root: Path, into: list[str]) -> None:
    for dp, dn, fn in os.walk(root):
      dn[:] = [d for d in dn if d not in {".git", "__pycache__", "node_modules"}]
      for name in sorted(fn):
        if not name.endswith(".bend"):
          continue
        p = Path(dp) / name
        if self.is_scratch(name):
          if into is self.port:
            self.excluded.append(str(p.relative_to(self.base)))
          continue
        into.append(str(p.relative_to(self.base)))

  def _scan(self) -> None:
    port_root = self.base / PORT_REL
    if port_root.is_dir():
      self._walk(port_root, self.port)
    comp_root = self.base / COMPILER_REL
    if comp_root.is_dir():
      self._walk(comp_root, self.extra)
    # TWO PASSES, AND THE SECOND ONE IS THE FIX.  `_import_target` answers "does the file this
    # import names exist?" by asking `cand in self.bodies`, and `self.bodies` was filled in the
    # SAME loop that computed the aliases -- so an import pointing at a file LATER IN THE WALK
    # ORDER resolved to `None`.  MEASURED: `os.walk` visits `schedule/` before `uop/`, so
    # **69 of the 170 files had a `None` alias**, and `O.GroupOp.movement` never resolved
    # against `uop/ops.bend`.  **⇒ A RESOLVER THAT DEPENDS ON WHAT ELSE IS LOADED **AND **ON THE
    # ORDER IT WAS LOADED **IN** IS **A **RESOLVER **WITH **A **HIDDEN **RULE.**  **⇒ SO **THE
    # BODIES **GO **IN **FIRST**, **AND **THE **ALIASES **ARE **COMPUTED **AFTER**, **WHEN **EVERY
    # **BODY **IS **PRESENT** **AND **THE **ORDER **OF **THE **WALK **CANNOT **CHANGE **THE
    # ANSWER.**
    for rel in self.port + self.extra:
      body = (self.base / rel).read_text(encoding="utf-8", errors="replace").splitlines()
      self.bodies[rel] = body
      self.by_name[rel.rsplit("/", 1)[-1]].append(rel)
      self.imports[rel] = [m.group(1) for m in
                            (IMPORT.match(l) for l in body) if m]
      self.constructs[rel] = bend_constructs(body)
      self.words[rel] = {w for l in body
                         for w in re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\b", l)}
    for rel in self.port + self.extra:
      body = self.bodies[rel]
      self.aliases[rel] = {m.group(2): self._import_target(rel, m.group(1))
                            for m in (IMPORT.match(l) for l in body)
                            if m and m.group(2)}

  # ---- the resolver ------------------------------------------------------------

  def resolve(self, subject: str, citing: str, lo: int, hi: int) -> tuple[str | None, str]:
    """A cited subject -> `(path, how)`. AMBIGUOUS IS A REFUSAL, NEVER `absent`.

    THE ORDER IS THE ORDER OF EVIDENCE. An EXACT path is the citation's own spelling.
    A PATH-SUFFIX is the port-relative spelling. A unique BASENAME is the only bare
    spelling that needs no help. **THE LINE RANGE COMES BEFORE THE IMPORT, because a
    pointer at line N CANNOT BE ABOUT A FILE WITH FEWER THAN N LINES** -- that is a fact
    about the file and not a guess about the prose. MEASURED:
    `tinybendygrad/dtype.bend:658` cites `base.bend:1251` and the port's `base.bend` is
    56 lines while the compiler's `references/bend/bend2/base.bend` is 3,191; the
    import rule picked the port's file and reported a DANGLING line for a pointer that
    is about the COMPILER's `base.bend`. And `tinybendygrad/schedule/__init__.bend:1390`
    cites `spec.bend:3121` where `LAWS/spec.bend` is 869 lines and `uop/spec.bend` is
    3,473. The citing file's OWN IMPORTS settle a bare basename the range does not:
    the port writes `import ./../uop/ops.bend as O`, so the import NAMES the path a bare
    `ops.bend` means.
    """
    if subject.startswith(PORT_REL + "/"):
      return (subject, "root-relative") if subject in self.bodies else (None, "absent")
    if subject.startswith("."):
      # A SUBJECT SPELLED RELATIVE TO THE CITING FILE, the way the port spells its
      # IMPORTS: `runtime/ops_python.bend` cites `../base.bend:54` for the file it
      # imports as `./../base.bend`.
      stack = citing.split("/")[:-1]
      for part in [p for p in subject.split("/") if p not in ("", ".")]:
        if part == "..":
          if not stack:
            return None, "absent"
          stack.pop()
        else:
          stack.append(part)
      cand = "/".join(stack)
      return (cand, "relative-to-the-citing-file") if cand in self.bodies else (None, "absent")
    if "/" in subject:
      hits = [p for p in self.port + self.extra
              if p == subject or p.endswith("/" + subject)]
      if len(hits) == 1:
        return hits[0], "path-suffix"
      if len(hits) > 1:
        return None, f"ambiguous:{len(hits)}"
      return None, "absent"
    hits = self.by_name.get(subject, [])
    if not hits:
      return None, "absent"
    if len(hits) == 1:
      return hits[0], "unique-basename"
    inrange = [h for h in hits if len(self.bodies[h]) >= hi]
    if len(inrange) == 1:
      return inrange[0], "the-only-candidate-that-has-the-line"
    named = {p for imp in self.imports.get(citing, []) for p in [self._import_target(citing, imp)] if p}
    by_import = [h for h in hits if h in named]
    if len(by_import) == 1:
      return by_import[0], "the-citing-file's-import"
    return None, f"ambiguous:{len(hits)}"

  def _import_target(self, citing: str, imp: str) -> str | None:
    """`import ./../uop/ops.bend` seen FROM `tinybendygrad/nn/layers.bend` ->
    `tinybendygrad/uop/ops.bend`. The port's imports are RELATIVE."""
    parts = [p for p in imp.split("/") if p not in ("", ".")]
    if not parts:
      return None
    stack = citing.split("/")[:-1]
    for part in parts:
      if part == "..":
        if not stack:
          return None
        stack.pop()
      else:
        stack.append(part)
    cand = "/".join(stack)
    return cand if cand in self.bodies else None

  # ---- the constructs ----------------------------------------------------------

  def construct_at(self, rel: str, line: int) -> str:
    """THE NAME OF THE CONSTRUCT AT `line` of `rel`, or what is there instead.

    THIS IS THE COLUMN THE REPORT NEEDS: a stale pointer must say what it landed on,
    so a reader can see that `:1620` is `sym_dim.end` and not the deferral it claimed.
    """
    body = self.bodies.get(rel, [])
    if not body or line < 1 or line > len(body):
      return "(outside the file)"
    best = None
    for name, decl, lo, hi in self.constructs.get(rel, []):
      if lo <= line <= hi and (best is None or decl > best[1]):
        best = (name, decl)
    if best:
      return best[0]
    text = body[line - 1]
    if not text.strip():
      return "(blank)"
    if text.lstrip().startswith("#"):
      return "(comment)"
    return "(top-level statement)"

  def declares(self, rel: str, token: str) -> list[tuple[int, int, int]]:
    """`(decl, span_start, span_end)` for every declaration of `token` in `rel`.

    **THE NAME IS MATCHED WHOLE, AND THE LAST COMPONENT IS A FALLBACK FOR A NAME THE
    FILE DOES NOT SAY.** `SInt.uop` is the `def SInt.uop` and not the `def SInt.uop_of`
    beside it, so a name the file says is matched whole. A name the file does NOT say
    -- the ALIAS case, where the port writes `F.alu_ds` and `F` is its import alias --
    is matched on its last component, because that is the only way to find `alu_ds`."""
    out = [(d, s, e) for (n, d, s, e) in self.constructs.get(rel, []) if n == token]
    if out:
      return out
    if token not in self.words.get(rel, ()):
      last = token.rsplit(".", 1)[-1]
      return [(d, s, e) for (n, d, s, e) in self.constructs.get(rel, []) if n == last]
    return []

  def strip_alias(self, citing: str, target: str, token: str) -> str:
    """The construct name `token` names IN `target`, with the citing file's IMPORT ALIAS
    removed -- or "" when the token names a construct of ANOTHER file.

    **THE PORT'S ALIASES ARE ITS OWN VOCABULARY AND THE CLAIM USES THEM.** The port
    writes `import ./../uop/ops.bend as O` and then says `O.Sint.uop` for a construct
    `uop/ops.bend` declares. The alias is the FIRST component of the dotted name, and
    it is DISCOVERED from the citing file's own import lines. An alias that points at a
    DIFFERENT file makes the claim about that other file, so the name is "" here and
    the row is not checkable against this target."""
    if "." not in token:
      return token
    head, rest = token.split(".", 1)
    alias = self.aliases.get(citing, {}).get(head)
    if alias is None:
      return token           # not an alias: the dotted name is the construct's own name
    if alias != target:
      return ""              # the alias points at ANOTHER file
    return rest


# --------------------------------------------------------------------------- the judge

class Judge:
  """THE CITATION RULES, LOADED BY PATH, AND THE PORT's OWN `.bend` DECLARATIONS.

  `gates/pin-cite-gate.py` is the instrument that reads the port's UPSTREAM citations
  with the same content test; it is loaded rather than copied because its claim-token
  rules were each bought with a measured fault.
  """

  def __init__(self, corpus: Corpus):
    self.corpus = corpus
    pc = load_sibling("bendcite_pincite", "pin-cite-gate.py")
    self.claim_tokens = pc.claim_tokens
    self.comment_blocks = load_sibling("bendcite_todo", "todo-cite-gate.py").comment_blocks
    self._decl_cache: dict[tuple[str, str], list[tuple[int, int, int]]] = {}
    self._blocks: dict[str, list[tuple[int, int]]] = {}

  def declares(self, rel: str, token: str) -> list[tuple[int, int, int]]:
    key = (rel, token)
    if key not in self._decl_cache:
      self._decl_cache[key] = self.corpus.declares(rel, token)
    return self._decl_cache[key]

  def rows(self) -> list[dict]:
    out: list[dict] = []
    for rel in sorted(self.corpus.port):
      body = self.corpus.bodies[rel]
      blocks = self.comment_blocks(body)
      self._blocks[rel] = blocks
      for at, line in enumerate(body, 1):
        if ".bend" not in line:
          continue
        spans = [(m.start(), m.end()) for m in CITE.finditer(line)]
        if not spans:
          continue
        for i, m in enumerate(CITE.finditer(line)):
          subject = m.group(1)
          lo = int(m.group(2))
          hi = int(m.group(3)) if m.group(3) else lo
          toks = self._tokens(line, spans, i, subject)
          out.append({"rel": rel, "at": at, "subject": subject, "lo": lo, "hi": hi,
                      "toks": toks, "line": line.strip(),
                      "comment": line.lstrip().startswith("#")})
    return out

  def _tokens(self, line: str, spans: list[tuple[int, int]], i: int, subject: str) -> list[str]:
    """The DOTTED names this citation claims, on its OWN line.

    **A BACKTICKED NAME BELONGS TO THE NEAREST CITATION, AND THIS FILE IMPLEMENTS THAT
    RULE ITSELF.** `gates/pin-cite-gate.py`'s `window_tokens` says the same thing in its
    docstring and implements the OPPOSITE: it keeps a name for citation `i` when the
    name is within 40 characters of some OTHER citation, so on a line with two
    citations the name goes to the FARTHER one. MEASURED:
    `tinybendygrad/extra/models/clip.bend:105` reads
    `"mixin/elementwise.bend:772 has the CONSTANT ew_k.gelu and :1217 has
    `def ew_quick_gelu`"` -- and the shared rule gave `ew_quick_gelu` to `:772`, which
    is TRUE of neither, and the pointer read as stale. The rule is NOT copied here
    because it is not the rule; the shared rule's own docstring is right and its code
    is what is wrong. `gates/pin-cite-gate.py` is NOT edited by this file.

    **THE DOTTED NAME IS KEPT WHOLE.** The port writes `SInt.uop` for a
    `def SInt.uop(...)`, and the COMPONENTS alone lose it: the component `SInt` is a
    word on `def SInt.uop_of(...)`, so splitting the name made `ops.bend:823` READ AS
    RESOLVES when `SInt.uop` is declared at :815 and the pointer names :823.

    **A LINE WITH AN ODD NUMBER OF BACKTICKS IS SKIPPED.** Its backtick spans are
    MISALIGNED -- the span that opens on the previous line closes here -- so the names
    this rule would read are garbage. MEASURED: 27 of the 1,251 citations sit on such a
    line, and the tier-two block reading covers them with the spans ALIGNED OVER THE
    BLOCK."""
    if line.count("`") % 2:
      return []
    out: list[str] = []
    for span_text in self._nearest_spans(line, spans).get(i, []):
      # `claim_tokens` reads BACKTICK SPANS, so the span is handed back WITH ITS
      # DELIMITERS -- handing it the bare text makes the reader find no span at all and
      # answer with an empty set.
      comps = set(self.claim_tokens(f"`{span_text}`", subject))
      for name in bend_names(span_text):
        last = name.rsplit(".", 1)[-1]
        if last not in comps or last.lower() in NOT_A_NAME:
          continue
        if name not in out:
          out.append(name)
    for name in SYMBOL_FIELD.findall(line):
      if name not in out:
        out.append(name)
    return out

  def _nearest_spans(self, line: str, spans: list[tuple[int, int]]) -> dict[int, list[str]]:
    """`{citation index: [the backticked spans that belong to it]}`.

    A NAME BELONGS TO THE NEAREST CITATION, and a TIE BELONGS TO BOTH -- a name exactly
    between two citations is about both, and dropping it from one of them would make
    that citation's claim unverifiable."""
    out: dict[int, list[str]] = collections.defaultdict(list)
    for m in re.finditer(r"`([^`]+)`", line):
      if re.search(r":[0-9]+", m.group(1)):
        continue           # the span IS a citation, not a claim
      s, e = m.start(), m.end()
      gaps = [max(0, cs - e, s - ce) for cs, ce in spans]
      if not gaps:
        continue
      best = min(gaps)
      for i, g in enumerate(gaps):
        if g == best:
          out[i].append(m.group(1))
    return out

  def _block_tokens(self, rel: str, at: int, subject: str) -> list[str]:
    """The DOTTED names the ENCLOSING COMMENT BLOCK names, for the rows whose own line
    names none.

    **THIS IS TIER TWO, AND IT IS A FALLBACK, NOT A REPLACEMENT.** A row's own line is
    the tight claim and is used whenever it names something the target holds. Only when
    it does not is the enclosing comment block read, because the port's prose often puts
    the name on the line BEFORE the pointer: MEASURED,
    `tinybendygrad/uop/fold.bend:1661` writes "(ops.bend:823) has been for with no caller"
    and the lines above it name `O.Sint.uop` -- the construct `ops.bend:823` used to be.
    A block is a WIDER claim than a line, so the row records WHICH tier decided it and a
    reader can see the difference.

    **THE SPANS ARE ALIGNED OVER THE BLOCK, NOT OVER THE LINE.** A backticked name that
    opens on one line and closes on the next is ONE name, and reading the block as one
    text is what finds it."""
    body = self.corpus.bodies[rel]
    stem = {p for p in re.split(r"[/.]", subject) if p}
    blk = next((b for b in self._blocks.get(rel, []) if b[0] <= at <= b[1]), None)
    if blk is None:
      return []
    text = "\n".join(body[blk[0] - 1:blk[1]])
    out: list[str] = []
    for m in re.finditer(r"`([^`]+)`", text):
      if re.search(r":[0-9]+", m.group(1)):
        continue
      for name in bend_names(m.group(1)):
        last = name.rsplit(".", 1)[-1]
        if last in stem or last.lower() in NOT_A_NAME or len(last) < 3:
          continue
        if name not in out:
          out.append(name)
    return out

  def judge(self, r: dict) -> tuple[str, str, dict]:
    """`(verdict, why, extra)` for one citation."""
    corpus = self.corpus
    path, how = corpus.resolve(r["subject"], r["rel"], r["lo"], r["hi"])
    if path is None:
      if how.startswith("ambiguous"):
        return ("AMBIGUOUS", f"{r['subject']!r} names {how.removeprefix('ambiguous:')} "
                             f"files and nothing settles it", {})
      stem = r["subject"].rsplit("/", 1)[-1]
      if stem in corpus.by_name:
        return ("ABSENT-FILE", f"the tree has a {stem} and {r['subject']!r} is not it", {})
      return ("OUT-OF-CORPUS", f"{r['subject']!r} is not a `.bend` file this tree holds", {})
    body = corpus.bodies[path]
    extra = {"target": path, "how": how,
             "at_line": corpus.construct_at(path, r["lo"])}
    if r["lo"] < 1 or r["hi"] > len(body):
      extra["at_line"] = "(outside the file)"
      return ("DANGLING-LINE", f"{path} has {len(body)} lines, cited at :{r['lo']}"
              + (f"-{r['hi']}" if r["hi"] != r["lo"] else ""), extra)
    if not r["toks"]:
      toks: list[tuple[str, str]] = []
    else:
      toks = self._resolve_names(r["rel"], path, r["toks"])
    tier = "the citation's own line"
    if not toks:
      # TIER TWO: the ENCLOSING COMMENT BLOCK. The port's prose often puts the name on
      # the line BEFORE the pointer, and the block is the unit the tree's own
      # `todo-cite-gate.py` reads for a marker's subject.
      block = self._resolve_names(r["rel"], path,
                                  self._block_tokens(r["rel"], r["at"], r["subject"]))
      if block:
        toks = block
        tier = "the enclosing comment block"
    extra["tier"] = tier
    extra["claims"] = [f"{raw}={n}" if raw != n else raw for raw, n in toks]
    if not toks:
      return ("UNCLAIMED", f"neither the citing line nor its comment block names anything "
              f"{path} HOLDS IN CODE, so there is no claim to falsify", extra)
    holds, why, decl = self._holds(path, body, r, toks)
    extra["decl"] = decl
    if holds is None:
      return ("UNCLAIMED", why, extra)
    if holds:
      return ("RESOLVES", why, extra)
    extra["delta"] = r["lo"] - decl if decl else 0
    # **THE CLAIM'S STRENGTH IS THE VERDICT'S NAME.** A claim read off the POINTER'S OWN
    # LINE is a claim about that pointer; a claim read off the enclosing COMMENT BLOCK
    # is a claim about the paragraph, and the paragraph names things the pointer is not
    # about. MEASURED, of 12 sampled tier-two rows, at least 4 are pointers that are
    # RIGHT -- `tinybendygrad/uop/render.bend:422` cites `ops.bend:1036-1090` and says
    # "ops.bend:1036-1090 already has the `ops.ParamArg` pattern with 13 fields", and
    # `ops.bend:1036` IS inside the `ParamArg` arm; the block's names include
    # `ParamArg`, whose DECLARATION is at :869, and the pointer was called stale on it.
    # Of 12 sampled tier-ONE rows, 0 were wrong. **A FALSE FAILURE IS WORSE THAN A
    # MISSED ROW**, so the two strengths are two verdicts and only the strong one fails.
    if tier == "the citation's own line":
      return ("WRONG-LINE", why, extra)
    return ("WRONG-LINE-BY-BLOCK", why, extra)

  def _resolve_names(self, citing: str, target: str,
                     raw: list[str]) -> list[tuple[str, str]]:
    """`(as written, as the target names it)` for every claim name.

    **THE ALIAS IS THE FIRST COMPONENT AND IT IS THE CITING FILE's OWN.** The port
    writes `import ./../uop/ops.bend as O` and then says `O.Sint.uop`; the target file
    says `SInt.uop` and never `O.Sint.uop`. A name whose alias points at ANOTHER file
    is about that other file and is DROPPED here, so a pointer about `uop/ops.bend` is
    not judged against a name that lives in `LAWS/spec.bend`."""
    out: list[tuple[str, str]] = []
    for t in raw:
      n = self.corpus.strip_alias(citing, target, t)
      if n and (t, n) not in out:
        out.append((t, n))
    return out

  def _holds(self, path: str, body: list[str], r: dict,
             toks: list[tuple[str, str]]) -> tuple[bool | None, str, int]:
    """`(holds, why, decl)` for one citation. `holds is None` means "NO CLAIM TO
    FALSIFY", which is not a failure.

    **ONLY A CONSTRUCT THE TARGET DECLARES CAN FALSIFY A POINTER.** A name the target
    merely MENTIONS -- a local, a type from another module, an English word in a
    comment -- is not "the thing the pointer is about", and a pointer that fails to land
    on it is not thereby stale. MEASURED: `tinybendygrad/nn/layers.bend:533` cites
    `mixin/op.bend:60-70` and says "(W4) calls it 'BUILDABLE but not CHECKABLE'", and
    `mixin/op.bend:60-70` SAYS EXACTLY THAT -- the pointer is RIGHT. The block's names
    included `Maybe`, a type `mixin/op.bend` does not declare, and the pointer read as
    stale on it. **A FALSE FAILURE IS WORSE THAN A MISSED ROW**, so a claim the target
    does not declare is REPORTED and not verdicted.

    FOUR WAYS A CONSTRUCT CLAIM HOLDS, AND THE ORDER IS THE ORDER OF STRENGTH. A cited
    line that NAMES the construct is a call or a mention; a cited line that DECLARES it
    is the construct; a cited line INSIDE its body is the construct's code; and a cited
    RANGE that names it is a range about it. A cited range INSIDE the construct's span
    is the fourth and weakest, and it is the one the port's own doc-comment pointers
    rely on."""
    lo, hi = r["lo"], r["hi"]
    cited = body[lo - 1]
    span = "\n".join(body[lo - 1:hi]) if hi > lo else ""
    # THE MENTION TEST COMES FIRST, AND IT IS THE ONLY TEST A NAME THE TARGET DOES NOT
    # DECLARE CAN PASS.
    for raw, name in toks:
      if re.search(rf"\b{re.escape(name)}\b", cited):
        return (True, f":{lo} names `{name}`", 0)
      if span and re.search(rf"\b{re.escape(name)}\b", span):
        return (True, f":{lo}-{hi} names `{name}`", 0)
    declared = [(raw, name) for raw, name in toks if self.declares(path, name)]
    if not declared:
      return (None, f"the citing text names {[n for _r, n in toks]} and {path} DECLARES "
                    f"none of them, so there is no construct for the pointer to point at",
              0)
    for raw, name in declared:
      for decl, start, end in self.declares(path, name):
        if decl == lo:
          return (True, f":{lo} declares `{name}`", decl)
        if decl < lo <= end:
          return (True, f":{lo} is inside `{name}` (declared at :{decl})", decl)
        if start <= lo and hi <= end:
          return (True, f":{lo}-{hi} is inside `{name}` (declared at :{decl})", decl)
    # IT DOES NOT HOLD. Say where EVERY claimed construct IS, and by how much the
    # pointer moved. ONE construct and a list of them are different reports: the row
    # for `ops.bend:940` claims `Arg` AND `AInk`, and naming only the nearer one would
    # send a reader to the wrong construct.
    where = []
    best = None
    for raw, name in declared:
      decl = self.declares(path, name)[0][0]
      where.append(f"`{name}` is declared at :{decl}")
      if best is None or abs(decl - lo) < abs(best[0] - lo):
        best = (decl, name)
    decl, name = best
    return (False, f"the pointer says :{lo} and " + "; ".join(where)
                   + f" -- the nearest is {lo - decl:+d} lines away", decl)


# --------------------------------------------------------------------------- the report

BAD = ("WRONG-LINE", "DANGLING-LINE", "ABSENT-FILE")
VIEWS = ("RESOLVES", "WRONG-LINE", "WRONG-LINE-BY-BLOCK", "DANGLING-LINE", "ABSENT-FILE",
         "AMBIGUOUS", "UNCLAIMED", "OUT-OF-CORPUS")


def census(base: Path) -> tuple[list[dict], Corpus]:
  corpus = Corpus(base)
  judge = Judge(corpus)
  rows = judge.rows()
  for r in rows:
    r["verdict"], r["why"], extra = judge.judge(r)
    r.update(extra)
  return rows, corpus


def report(rows: list[dict], corpus: Corpus) -> None:
  by = collections.Counter(r["verdict"] for r in rows)
  files = collections.Counter(r["rel"] for r in rows)
  stale = [r for r in rows if r["verdict"] in BAD]
  soft = [r for r in rows if r["verdict"] == "WRONG-LINE-BY-BLOCK"]
  per_file = collections.Counter(r["rel"] for r in stale)
  print(f"POPULATION : {len(corpus.port)} .bend source files under {PORT_REL}/ "
        f"(os.walk + endswith('.bend'), minus {len(corpus.excluded)} scratch copies)")
  for name in corpus.excluded:
    print(f"             scratch, excluded: {name}")
  print(f"CITED CORPUS: {len(corpus.port)} port files + {len(corpus.extra)} compiler files "
        f"under {COMPILER_REL}/" + ("" if corpus.extra else "  (ABSENT)"))
  print(f"CLAIMS     : {len(rows)} `.bend`-to-`.bend` line citations in {len(files)} files")
  print(f"             {sum(1 for r in rows if r['comment'])} in comment lines, "
        f"{sum(1 for r in rows if not r['comment'])} in code (a string literal)")
  print()
  print("LANE -- VERDICTS.  A FAIL is a claim the tree cannot support.")
  for v in VIEWS:
    n = by.get(v, 0)
    if n:
      mark = "  <-- FAIL" if v in BAD else ""
      print(f"           {v:20s} {n:6d}{mark}")
  print(f"           {'THE STALE ONES BY CLAIM STRENGTH':20s}")
  for tier, n in sorted(collections.Counter(r.get("tier", "") for r in stale + soft).items()):
    print(f"           {tier:20s} {n:6d} stale")
  print()
  print(f"THE STALE POINTERS, EVERY ONE ({len(stale)}), because a stale pointer looks fine "
        f"to a reader:")
  for r in stale:
    span = f"{r['subject']}:{r['lo']}" if r["lo"] == r["hi"] else f"{r['subject']}:{r['lo']}-{r['hi']}"
    decl = r.get("decl", 0)
    print(f"  {r['rel']}:{r['at']}  ->  {span}  [{r.get('how','')}]")
    print(f"        claims {', '.join(r.get('claims') or []) or '(no claim token)'}"
          f"   -- read from {r.get('tier','?')}")
    print(f"        {r['why']}")
    print(f"        the construct AT the cited line is {r.get('at_line','?')!r}"
          + (f"; the construct is declared at :{decl}" if decl else ""))
    print(f"        {r['line'][:120]}")
  print()
  print(f"THE POINTERS STALE BY A COMMENT-BLOCK CLAIM ({len(soft)}).  **THESE DO NOT FAIL.**")
  print("           The claim was read off the enclosing paragraph, and a paragraph names")
  print("           things the pointer is not about; the rows are printed so a reader can")
  print("           see how many a stronger reading would add.")
  for r in soft:
    span = f"{r['subject']}:{r['lo']}" if r["lo"] == r["hi"] else f"{r['subject']}:{r['lo']}-{r['hi']}"
    print(f"  {r['rel']}:{r['at']}  ->  {span}  [{r.get('how','')}]")
    print(f"        claims {', '.join(r.get('claims') or []) or '(no claim token)'}")
    print(f"        {r['why']}")
    print(f"        the construct AT the cited line is {r.get('at_line','?')!r}")
    print(f"        {r['line'][:120]}")
  print()
  print("THE SPREAD OF THE STALE POINTERS, BY THE FILE THAT MAKES THE CLAIM:")
  for rel, n in sorted(per_file.items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"  {n:4d}  {rel}")
  print()
  print("THE SPREAD OF THE STALE POINTERS, BY THE FILE THAT IS POINTED AT:")
  for tgt, n in sorted(collections.Counter(r.get("target", "") for r in stale
                                           if r.get("target")).items(),
                        key=lambda kv: (-kv[1], kv[0])):
    print(f"  {n:4d}  {tgt}")
  print()
  print("THE UNCLAIMED, AMBIGUOUS AND OUT-OF-CORPUS POINTERS, COUNTED AND NOT DROPPED.")
  print("           Each one resolves; the citing text names nothing the target holds, so")
  print("           there is no claim to falsify.  The construct AT the cited line is given,")
  print("           because a reader who wants to convert a pointer to a `symbol=` needs it:")
  for r in rows:
    if r["verdict"] not in ("UNCLAIMED", "AMBIGUOUS", "OUT-OF-CORPUS"):
      continue
    span = f"{r['subject']}:{r['lo']}" if r["lo"] == r["hi"] else f"{r['subject']}:{r['lo']}-{r['hi']}"
    print(f"  {r['verdict']:12s} {r['rel']}:{r['at']} -> {span}  at {r.get('at_line','?')!r}"
          f"  -- {r['why']}")
  print()


# --------------------------------------------------------------------------- the plant

def plant() -> int:
  """A TEXT EDIT on a COPY that MOVES a cited line, and a byte-identical copy.

  NEVER `git show HEAD:`. The subject of the plant is a COPY of the port tree on disk,
  edited as TEXT, so the plant proves the instrument reads the tree it is pointed at --
  and a copy taken from git would prove it reads a tree that is not the one anybody works
  on.

  TWO ARMS. ARM ONE is a SYNTHETIC port with one pointer, so the judge's verdict is
  decidable from literals. ARM TWO is a COPY OF THE REAL PORT with lines inserted at the
  top of the file the most pointers name, so the pointers that name it all move -- which
  is the rot this gate exists to measure, produced on demand.
  """
  try:
    return _plant()
  except Exception:
    print("PLANT FAILED: a crash is not a pass", file=sys.stderr)
    traceback.print_exc()
    return FAIL



def _claimed_name(row) -> str:
    """The construct a row claims, from the verdict's OWN WORDS.

    THE ROW DOES NOT CARRY **THE **NAME** **AS **A **FIELD**, **AND **THIS **PLANT **NEEDS **IT
    **TO **FIND **THE **CONSTRUCT's **SPAN **START** — **SO **IT **IS **READ **OUT **OF **THE
    **VERDICT's **`why`**, **WHICH **NAMES **IT**: **":1530 **is **inside **`t_softmax3.go` **(declared
    **at **:1529)"**.  **⇒ AND **THIS **IS **A **READ **OF **THE **GATE's **OWN **OUTPUT**, **NOT **A
    **SECOND **LIST** — **THE **VERDICT **TEXT **IS **WHERE **THE **NAME **LIVES.**
    """
    m = re.search(r"`([^`]+)`", row.get("why", ""))
    return m.group(1) if m else ""

def _plant() -> int:
  bad: list[str] = []

  # ---- ARM ONE: a synthetic port, one pointer, literals for everything.
  with tempfile.TemporaryDirectory(prefix="bendcite-plant-") as raw:
    td = Path(raw)
    src = td / "src" / PORT_REL
    src.mkdir(parents=True)
    # THE PORTED DEF HAS NO DOC COMMENT, and that is load-bearing: a construct's span
    # INCLUDES the comment run above it, so a pointer at a doc comment still holds --
    # and a plant that inserted a COMMENT above the def would then not go red. The
    # plant inserts CODE, which is what a unit editing the port actually does.
    (src / "base.bend").write_text(
      "def alpha(x: U32) -> U32:\n"
      "  x\n"
      "\n"
      "def beta(y: U32) -> U32:\n"
      "  y\n")
    (src / "nn").mkdir()
    (src / "nn" / "cites.bend").write_text(
      "# `alpha` lives at base.bend:1 and this pointer says so.\n")
    control = td / "control"
    shutil.copytree(td / "src", control)
    rows, _corpus = census(control)
    verdict = [r["verdict"] for r in rows]
    print(f"PLANT arm-one control : {verdict}")
    if verdict != ["RESOLVES"]:
      bad.append(f"arm one control did not resolve: {verdict}")
    moved = td / "moved"
    shutil.copytree(td / "src", moved)
    target = moved / PORT_REL / "base.bend"
    target.write_text("def gamma(z: U32) -> U32:\n  z\n\n" + target.read_text())
    rows2, _c2 = census(moved)
    verdict2 = [r["verdict"] for r in rows2]
    print(f"PLANT arm-one moved   : {verdict2}")
    if verdict2 != ["WRONG-LINE"]:
      bad.append(f"arm one did not go red: {verdict2}")
    twin = td / "twin"
    shutil.copytree(control, twin)
    same = all((control / p).read_bytes() == (twin / p).read_bytes()
               for p in (PORT_REL + "/base.bend", PORT_REL + "/nn/cites.bend"))
    rows3, _c3 = census(twin)
    print(f"PLANT arm-one twin    : {[r['verdict'] for r in rows3]}  byte-identical={same}")
    if not same or [r["verdict"] for r in rows3] != verdict:
      bad.append("arm one byte-identical twin did not reproduce the control")

  # ---- ARM TWO: a COPY of the real port, with a cited line MOVED by a text edit.
  with tempfile.TemporaryDirectory(prefix="bendcite-plant2-") as raw:
    td = Path(raw)
    snap = td / "snap"
    snap.mkdir(parents=True)
    shutil.copytree(ROOT / PORT_REL, snap / PORT_REL)
    base_rows, corpus = census(snap)
    # THE POINTER THE PLANT MOVES IS DISCOVERED, NOT NAMED: the first row whose verdict
    # is RESOLVES **BY A DECLARATION OR BY THE CONSTRUCT's BODY** -- a pointer that says
    # "the construct is AT line N" and not "the construct is MENTIONED at line N". A
    # mention-pointer does not break when the file moves, and a plant that asserted
    # otherwise would be asserting a property the instrument does not have.
    target_row = next((r for r in base_rows
                       if r["verdict"] == "RESOLVES" and r.get("decl")
                       and r.get("tier") == "the citation's own line"
                       and int(r["lo"]) >= int(r["decl"])
                       and ("declares `" in r["why"] or "is inside `" in r["why"])
                       and r.get("target", "").startswith(PORT_REL + "/")), None)
    if target_row is None:
      print("PLANT arm-two REFUSED: the copy resolved no declaration-pointer", file=sys.stderr)
      return REFUSED
    # THE EDIT MOVES THE CONSTRUCT PAST THE POINTER, which is what a unit inserting a
    # block at the top of a file does: the construct's declaration line grows by `k` and
    # the pointer, which was inside the construct, is now ABOVE it.
    #
    # **⇒ AND `k` **IS **COMPUTED **FROM **THE **SPAN **START**, **NOT **FROM **THE
    # **DECLARATION** — **AND **THAT **IS **THE **THIRD **REASON **THIS **PLANT **DID **NOT **GO
    # **RED. **A **CONSTRUCT's **SPAN **INCLUDES **THE **COMMENT **RUN **ABOVE **IT** (**THIS
    # **FILE'S **OWN **RULE**, **`:178-182`**: **"A **POINTER **AT **THE **DOC **COMMENT **ABOVE **A
    # **`def` **IS **A **POINTER **AT **THAT **`def`"**), **SO **MOVING **THE **DECLARATION **DOWN
    # **BY **`k`** **MOVES **THE **SPAN's **START **DOWN **BY **`k`** **TOO**, **AND **THE
    # **POINTER **CAN **STILL **LAND **ON **THE **DOC **COMMENT **OF **THE **MOVED **CONSTRUCT.**
    # **⇒ SO **THE **PLANT **INSERTS **ENOUGH **LINES **THAT **THE **POINTER **LANDS **ABOVE **THE
    # **WHOLE **SPAN**, **DOC **COMMENT **INCLUDED.**
    # THE PATH IS **RELATIVE **TO **THE **ROOT** — `corpus.declares` **KEYS **ON **IT**, **AND **AN
    # **ABSOLUTE **PATH **IS **NOT **A **KEY** — **SO **THE **LOOKUP **WAS **SILENTLY **MISSING**.
    target_path = target_row["target"]
    span_start = int(target_row["decl"])
    for decl, start, _end in corpus.declares(target_path, _claimed_name(target_row)):
      if decl == int(target_row["decl"]):
        span_start = min(span_start, start)
        break
    k = int(target_row["lo"]) - span_start + 1
    print(f"PLANT arm-two the pointer moved is {target_row['rel']}:{target_row['at']} -> "
          f"{target_row['subject']}:{target_row['lo']}, and the construct it names is "
          f"declared at {target_row['target']}:{target_row['decl']} (its span starts at "
          f":{span_start}); {k} lines are inserted above it")
    moved = td / "moved"
    shutil.copytree(snap, moved)
    victim = moved / target_row["target"]
    body = victim.read_text(encoding="utf-8").splitlines()
    # **⇒ THE **PLANT **INSERTS **CODE, **NOT **A **COMMENT** — **AND **THIS **ARM **USED **TO
    # **INSERT **A **COMMENT**, **WHICH **IS **EXACTLY **WHAT **THE **GATE's **OWN **ARM-ONE
    # **DOCSTRING **SAYS **CANNOT **WORK**: **"A **CONSTRUCT's **SPAN **INCLUDES **THE **COMMENT **RUN
    # **ABOVE **IT**, **SO **A **POINTER **AT **A **DOC **COMMENT **STILL **HOLDS."**  **⇒ MEASURED:
    # **ARM **TWO **DID **NOT **GO **RED** — **THE **PLANT **MOVED **THE **CONSTRUCT **BY **A **COMMENT
    # **RUN **THE **READER **ABSORBED.**
    # **⇒ AND **THE **INSERTED **BLOCK **IS **EXACTLY **`k` **LINES** **AND **IT **IS **NOT **A
    # **CONSTRUCT** — **THE **FIRST **ATTEMPT **REPEATED **A **`def`/`z` **PAIR **`k` **TIMES**, **WHICH
    # **IS **A **NESTED **DEF **AND **A **MALFORMED **ONE**, **AND **IT **MOVED **THE **DECLARATION
    # **BY **`2k`** **LINES **RATHER **THAN **`k`**; **THE **SECOND **ATTEMPT **USED **ONE **VALID
    # **`def`, **AND **THE **POINTER **THEN **LANDED **INSIDE **THAT **`def`'s **BODY** — **BECAUSE
    # **A **CONSTRUCT's **SPAN **RUNS **TO **THE **NEXT **DECLARATION**, **SO **THE **INSERTED
    # **BLOCK **WAS **A **CONSTRUCT **AND **THE **POINTER **FELL **INSIDE **IT.**
    # **⇒ SO **THE **INSERTED **LINES **ARE **PLAIN **STATEMENTS** (A **BARE **CALL), **WHICH **ARE
    # **NOT **A **CONSTRUCT** **AT **ALL** — **AND **THE **POINTER **THEN **LANDS **ON **A **LINE
    # **THAT **HOLDS **NO **CONSTRUCT**, **WHICH **IS **EXACTLY **WHAT **THE **PLANT **NEEDS **TO
    # **PROVE: **THAT **THE **READER **DISTINGUISHES **"THE **CONSTRUCT **IS **HERE" **FROM **"IT
    # **WAS **HERE".**  **⇒ AND **IT **IS **STILL **CODE**, **NOT **A **COMMENT** — **WHICH **IS **THE
    # **THING **THE **ARM-ONE **DOCSTRING **INSISTS **ON** (**"A **COMMENT **RUN **IS **ABSORBED
    # **INTO **THE **CONSTRUCT's **SPAN"**).**
    shift = ["IO.print(String.concat([\"PLANT: a line inserted above the construct the pointer \"," +
              " \"names\"]))"] + ["IO.print(String.concat([\"PLANT: shift\"]))"] * (k - 1)
    victim.write_text("\n".join(shift + body) + "\n")
    moved_rows, _mcorpus = census(moved)
    after = next((r for r in moved_rows
                  if r["rel"] == target_row["rel"] and r["at"] == target_row["at"]
                  and r["subject"] == target_row["subject"] and r["lo"] == target_row["lo"]), None)
    print(f"PLANT arm-two control : {target_row['verdict']}  (the pointer holds)")
    print(f"PLANT arm-two moved   : {after['verdict'] if after else '(the row is gone)'}")
    if after is None or after["verdict"] != "WRONG-LINE":
      bad.append("arm two did not make the moved pointer stale")
    base_v = collections.Counter(r["verdict"] for r in base_rows)
    moved_v = collections.Counter(r["verdict"] for r in moved_rows)
    print(f"PLANT arm-two control : {dict(base_v)}")
    print(f"PLANT arm-two moved   : {dict(moved_v)}")
    if moved_v.get("WRONG-LINE", 0) <= base_v.get("WRONG-LINE", 0):
      bad.append("arm two did not add a stale pointer")
    # THE CONTROL IS A SECOND COPY OF THE SAME SNAPSHOT, NOT THE LIVE TREE: the live
    # tree moves under the gate's feet, and a control taken from it would compare two
    # different trees.
    twin = td / "twin"
    shutil.copytree(snap, twin)
    twin_rows, _tcorpus = census(twin)
    if [r["verdict"] for r in twin_rows] != [r["verdict"] for r in base_rows]:
      bad.append("arm two byte-identical twin did not reproduce the control")
    else:
      print("PLANT arm-two twin    : reproduces the control exactly")

  if bad:
    print("PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
    return FAIL
  print("PLANT OK: a moved line makes the pointer stale, a byte-identical copy does not, "
        "and both arms agree with their controls")
  return PASS


# --------------------------------------------------------------------------- main

def main(argv: list[str]) -> int:
  if "--plant" in argv:
    return plant()
  report_only = "--report" in argv
  rows_out = argv[argv.index("--rows") + 1] if "--rows" in argv else None
  base = ROOT
  if "--tree" in argv:
    base = Path(argv[argv.index("--tree") + 1]).resolve()
  if not (base / PORT_REL).is_dir():
    print(f"== REFUSED, NOT A VERDICT: {base / PORT_REL} is absent", file=sys.stderr)
    return REFUSED
  rows, corpus = census(base)
  if not rows:
    print("== DEAD: no `.bend`-to-`.bend` citation was found; the census measured nothing",
          file=sys.stderr)
    return DEAD
  report(rows, corpus)
  if rows_out:
    head = ("rel\tat\tsubject\tlo\thi\tverdict\tclaim\ttier\tat_line\ttarget\tdecl\t"
            "delta\twhy\tline\n")
    body = "".join(
      f"{r['rel']}\t{r['at']}\t{r['subject']}\t{r['lo']}\t{r['hi']}\t{r['verdict']}\t"
      f"{','.join(r.get('claims') or [])}\t{r.get('tier','')}\t{r.get('at_line','')}\t"
      f"{r.get('target','')}\t{r.get('decl','')}\t{r.get('delta','')}\t{r['why']}\t"
      f"{r['line']}\n" for r in rows)
    Path(rows_out).write_text(head + body)
    print(f"ROWS       : {len(rows)} -> {rows_out}")
  bad = [r for r in rows if r["verdict"] in BAD]
  if report_only:
    print("(REPORT: exit 0 by request; the numbers above are the census, not a verdict)")
    return PASS
  if bad:
    print(f"# bendcite-gate: FAIL -- {len(bad)} of {len(rows)} internal pointers do not hold")
    return FAIL
  print("# bendcite-gate: PASS")
  return PASS


if __name__ == "__main__":
  print(f"# exit vocabulary: {VERDICT}", file=sys.stderr)
  raise SystemExit(main(sys.argv[1:]))
