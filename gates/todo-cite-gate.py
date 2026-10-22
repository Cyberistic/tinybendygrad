#!/usr/bin/env python3
"""todo-cite-gate.py -- THE PORT's `TODO(pN)` MARKERS ARE CITATIONS. DO THEY HOLD AT THE PIN?

    .venv/bin/python gates/todo-cite-gate.py
    .venv/bin/python gates/todo-cite-gate.py --rows OUT.rows
    .venv/bin/python gates/todo-cite-gate.py --report
    .venv/bin/python gates/todo-cite-gate.py --plant
    .venv/bin/python gates/todo-cite-gate.py --port DIR --upstream-dir DIR

THE PATCHES FOR THE FILES THIS GATE MAY NOT EDIT, AND WHERE THEY LIVE.  A citation that is
still false in a file another unit is holding is a FALSE CLAIM LEFT STANDING, so the gate
prints the patch for it.  **THE PRINTS GO TO `gates/todo-cite-HELD-PATCHES.md`, BESIDE THIS
GATE** -- and NOT under `.agents/slop/`, which is the directory this tree is pruning and where
the tree has already lost `worker_oracle.py` and had to recover it from a blob.

UPSTREAM IS THE PIN, AND THE PIN IS THE DECLARATION. `.agents/UPSTREAM-PIN.md`'s "OUR PIN"
row names the commit whose `tinygrad/` tree this repo vendored, and this gate verifies the
vendored bytes against that tree BEFORE it measures anything. The corpus is read from the
pin, not from the working tree, so a hand edit to a vendored file cannot make a false
citation true.

THE POPULATION IS DISCOVERED, NOT NAMED. `os.walk` over `tinybendygrad/` plus
`endswith(".bend")`, because `glob('*.bend')` returns `[]` when the files ARE on disk --
the trap `AGENTS.md` records. A census that names its population by hand is a list.

WHAT A MARKER IS. `TODO(pN)` in a `.bend` comment, where `pN` is the port's own priority
tag. A marker is not a note about the port: it is a CITATION of an upstream `.py` line,
and it sits in the same text as the claim it supports. `AGENTS.md`: "THE MARKERS ARE
CITATIONS, SO A RE-POINTED CITATION MUST BE CHECKED AGAINST THE PIN".

THE RESOLUTION IS BY SYMBOL WHERE THE MARKER NAMES ONE, AND BY LINE ONLY WHERE IT DOES
NOT. A marker's own words name the upstream symbol -- `TODO(p3) ops.py:93  def sym_infer`
names `sym_infer`, and `TODO(p3) x86.py:90` in a bullet about `extra_matcher` names
`extra_matcher` -- and a marker whose NAME is right and whose LINE is wrong is the common
case. So the gate reads the marker's TEXT, not just its number: the symbol candidates are
the backticked names in the marker line, then in the bullet the marker sits in, then in the
comment block, and the symbol that the upstream file actually DECLARES is the one the
citation is measured against.

THE FOUR VERDICTS, AND THEY ARE NOT FOUR NAMES FOR ONE.

  RESOLVES       the cited line holds what the marker claims: it names a claim token, or
                 it DECLARES the marker's symbol, or it is inside that symbol's body.
  WRONG-LINE     the symbol is RIGHT and the LINE is wrong. The gate prints BOTH lines.
  WRONG-SYMBOL   the marker names a function that is not the one it describes. The gate
                 prints what it should be and the evidence for that.
  UNRESOLVABLE   neither the line nor the symbol can be found. The gate says so rather
                 than guessing, because a guess is a false claim with a decimal in it.

A marker that cites NO upstream file is counted and not verdicted: `NO-CITATION` and
`PORT-CITATION` are results, not passes.

THE PLANT IS ON COPIES, AND IT HAS TWO ARMS AND AN UNBROKEN CONTROL. Arm one corrupts a
marker in a COPY of the port and asks the census to notice. Arm two MOVES A SYMBOL in a
COPY of the pinned upstream and asks the census to notice that the line no longer holds
the claim. The control is a byte-identical copy of the port, and it must produce the same
verdict as the tree it was copied from -- a plant whose control differs from the live tree
is measuring the difference between two trees, not the gate.

THE EXITS ARE `gatekit`'s. `REFUSED` (3) when the pin does not verify or the port tree is
absent -- an absent input is not a pass. `DEAD` (5) when no row was emitted. `FAIL` (1)
when a lane is red.
"""

from __future__ import annotations

import collections
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import traceback
import warnings
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

PORT_REL = "tinybendygrad"
DECLARATION = ROOT / ".agents" / "UPSTREAM-PIN.md"

#: The marker tag itself. `TODO(pN)` is the port's own spelling; `TODO(port)`,
#: `TODO(delete)` and `TODO(pN)` with a space are the other shapes present in the tree.
MARKER = re.compile(r"TODO\((p\d+)\)")
#: A citation with an explicit subject: `ops.py:93`, `runtime/ops_amd.py:558`,
#: `tinygrad/dtype.py:100`, `ops.py:9-18`. A SPACE is allowed before the number because the
#: port writes `ops.py: 95  def sym_infer`.
CITE = re.compile(r"([A-Za-z0-9_.\-/]*[A-Za-z0-9_]\.(?:py|bend))\s*:\s*(\d+)(?:\s*-\s*(\d+))?")
#: A BARE `:93`, which the port writes as a continuation of the file it just named.
BARE = re.compile(r"(?<![\w./-]):(\d+)(?:\s*-\s*(\d+))?(?![\w:])")
#: The upstream file's OWN declarations. `def`, `class`, and a module- or class-level
#: assignment. A name that is only ever ASSIGNED is still a declared thing upstream.
DECL = re.compile(r"^(\s*)(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)")
ASSIGN = re.compile(r"^(\s*)([A-Za-z_]\w*)\s*(?::[^=]+)?=")
#: A bare ANNOTATION: `lib: bytes`. That is how a dataclass declares a field, and a
#: rule that only knew about `=` would not see it.
ANNOT = re.compile(r"^(\s+)([A-Za-z_]\w*)\s*:\s*[^=]+$")
#: Words that are ASSIGNMENTS in a Python file but never a named thing.
NOT_A_NAME = frozenset("""and as assert async await break class continue def del elif else except
finally for from global if import in is lambda nonlocal not or pass raise return try while
with yield None True False self cls print""".split())
#: A backticked span. The port's own claim markers.
BACKTICK = re.compile(r"`([^`]+)`")
#: The SPANS of the backticked spans, which is what a marker-mention check needs.
BACKTICK_SPAN = re.compile(r"`[^`]*`")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
#: A DOTTED name: `UOp.param_like`. The port writes the class and the member together and
#: upstream declares the member, so the LAST component is the symbol.
DOTTED = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*")
#: A QUOTED SNIPPET: the run of characters the port copied out of the upstream line.
#: It must contain a bracket or an `=`, so a bare `def body` is not a snippet.
SNIPPET = re.compile(r"[A-Za-z0-9_.\[\]()'\"=+\-*/%<>!?:,~# ]*[()\[\]=][A-Za-z0-9_.\[\]()'\"=+\-*/%<>!?:,~# ]*")
#: The shortest snippet the gate will match. A truncated quote is still a quote.
SNIPPET_MIN = 10


# --------------------------------------------------------------------------- the tree's own pieces

def load_by_path(name: str, path: Path):
  """LOAD a sibling instrument BY PATH. A second copy of a rule is a contract with no
  generator: `gates/header-census-gate.py`'s parser and `gates/pin-cite-gate.py`'s content
  test are each bought with a measured fault, and this gate uses both."""
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    spec.loader.exec_module(mod)
  return mod


def git(*args: str) -> str:
  p = subprocess.run(("git", "--no-optional-locks",) + args, cwd=ROOT, capture_output=True, text=True)
  if p.returncode:
    raise RuntimeError(f"git {' '.join(args)}: rc={p.returncode} {p.stderr.strip()}")
  return p.stdout


def git_opt(*args: str) -> str:
  p = subprocess.run(("git", "--no-optional-locks",) + args, cwd=ROOT, capture_output=True, text=True)
  return p.stdout if p.returncode == 0 else ""


# --------------------------------------------------------------------------- the pin

def declared_pins() -> list[str]:
  """The shas on the declaration's OUR-PIN row. READ OUT OF THE DECLARATION, by the label
  the declaration itself uses, so a superseded pin elsewhere in the file is not mistaken
  for the pin."""
  out: list[str] = []
  for line in DECLARATION.read_text(encoding="utf-8").splitlines():
    if "OUR PIN" not in line:
      continue
    out.extend(re.findall(r"\b[0-9a-f]{7,40}\b", line))
  return out


def tree_of(rev: str) -> str:
  return git_opt("rev-parse", "--verify", "--quiet", f"{rev}:tinygrad").strip()


def verify_pin() -> tuple[str, str]:
  """`(pin, detail)`. THE PIN MUST VERIFY, and the vendored bytes must be its bytes.

  The vendored tree is compared BY BLOB, with `git hash-object`, because the tree's index
  is armed and `git diff` against it is not a statement about the working copy."""
  cands = declared_pins()
  if not cands:
    return ("", f"{DECLARATION.relative_to(ROOT)} names no sha on its OUR PIN row")
  trees = {}
  for c in cands:
    t = tree_of(c)
    if t:
      trees[c] = t
  if not trees:
    return ("", "no sha on the OUR PIN row resolves to a commit with a tinygrad/ tree")
  pin = next(iter(trees))
  pin_tree = trees[pin]
  listed = {}
  for line in git("ls-tree", "-r", pin, "--", "tinygrad/").splitlines():
    meta, path = line.split("\t", 1)
    listed[path] = meta.split()[2]
  on_disk = {}
  for dp, _dn, fn in os.walk(ROOT / "tinygrad"):
    for f in fn:
      p = Path(dp) / f
      on_disk[str(p.relative_to(ROOT))] = git_opt("hash-object", str(p)).strip()
  missing = sorted(set(listed) - set(on_disk))
  extra = sorted(set(on_disk) - set(listed))
  differ = sorted(p for p in set(listed) & set(on_disk) if listed[p] != on_disk[p])
  if missing or differ:
    return ("", f"the vendored tinygrad/ is not the pin's: {len(missing)} missing, "
                 f"{len(differ)} differing")
  return (pin, f"tinygrad/ tree {pin_tree[:12]}, {len(listed)} blobs match the vendored copy"
                 + (f", {len(extra)} local-only" if extra else ""))


# --------------------------------------------------------------------------- the population

def walk_bend(root: Path) -> list[Path]:
  """Every `.bend` file under `root`, DISCOVERED. `glob` is a trap here."""
  out: list[Path] = []
  for dp, dn, fn in os.walk(root):
    dn[:] = [d for d in dn if d not in {".git", "__pycache__", "node_modules"}]
    for f in fn:
      if f.endswith(".bend"):
        out.append(Path(dp) / f)
  return sorted(out, key=lambda p: str(p))


def comment_blocks(lines: list[str]) -> list[tuple[int, int]]:
  """`(first, last)` 1-based line numbers of every maximal run of comment lines.

  BLANKS ARE ALLOWED INSIDE a run, so a comment paragraph broken by a blank line is one
  block. The run ENDS at the first line that is neither a comment nor blank."""
  out: list[tuple[int, int]] = []
  i, n = 0, len(lines)
  while i < n:
    if lines[i].lstrip().startswith("#"):
      j = i
      while j < n and (lines[j].lstrip().startswith("#") or not lines[j].strip()):
        j += 1
      k = j - 1
      while k > i and not lines[k].strip():
        k -= 1
      out.append((i + 1, k + 1))
      i = j
      continue
    i += 1
  return out


def item_start(lines: list[str], at: int, block: tuple[int, int]) -> int:
  """The first line of the BULLET the marker at `at` sits in.

  A bullet is a comment line whose text after the `#` begins with `*` or `-`. The item is
  that line through the marker, and it is where the marker's subject usually lives."""
  first, last = block
  for i in range(min(at, last) - 1, first - 2, -1):
    body = lines[i].lstrip().lstrip("#").lstrip()
    if body.startswith("*") or body.startswith("-"):
      return i + 1
  return at


def subject_token(text: str) -> str:
  """The SYMBOL a marker's own line names, or "".

  IT IS THE FIRST TOKEN AND NOT A SEARCH DOWN THE LINE. A marker that says
  `ops.py:502  def ssimplify` names `ssimplify`; a marker that says
  `ops.py:503  -- the body is the line above` names NOTHING, and a rule that kept
  looking would find the word "body" -- which upstream happens to declare -- and report a
  symbol the marker never wrote. The marker's own words name the symbol, and the FIRST
  word after the citation is that word.

  `def` and `class` take the name that follows them."""
  toks = DOTTED.findall(text)
  if not toks:
    return ""
  if toks[0] in ("def", "class"):
    return toks[1] if len(toks) > 1 else ""
  return toks[0]


def is_continuation(text: str) -> bool:
  """Does the marker's own text NAME NOTHING, so it CONTINUES the entry before it?

  A work-queue list writes `TODO(p3) ops.py:502  def ssimplify` and then
  `TODO(p3) ops.py:503  -- the body is the line above`, and the second entry is about the
  first entry's subject. An entry whose text does not START with an identifier or a
  backtick is that kind of entry."""
  stripped = text.strip()
  if not stripped:
    return True
  return not re.match(r"[A-Za-z_`]", stripped)


# --------------------------------------------------------------------------- the markers

def marker_records(path: Path, rel: str, census_mod=None) -> list[dict]:
  """Every `TODO(pN)` marker in one file, with the citations it carries."""
  lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
  blocks = comment_blocks(lines)
  # THE PORT FILE'S DECLARED UPSTREAM TARGET, which is what disambiguates a bare
  # `__init__.py` (28 upstream files) or `dtype.py` (3). READ OUT OF THE HEADER by the
  # census's own reader, not remembered.
  prefer_dir = ""
  if census_mod is not None:
    _first, _last, blk = census_mod.header_block(lines)
    tgt = census_mod.declared_target(blk)
    rel_tgt = tgt[len("tinygrad/"):] if tgt.startswith("tinygrad/") else tgt
    prefer_dir = rel_tgt.rsplit("/", 1)[0] if "/" in rel_tgt else ""
  out: list[dict] = []
  for i, ln in enumerate(lines, 1):
    if "TODO(" not in ln:
      continue
    for m in MARKER.finditer(ln):
      # A MARKER INSIDE BACKTICKS IS USUALLY A MARKER MENTIONED, not a marker: the port
      # writes "three `TODO(p3)`s" to talk about the queue, and a census that counted
      # those would count a sentence as a work item. A backticked span that CARRIES A
      # CITATION is a quoted marker -- `# TODO(p3) ops.py:581 def index` -- and that one
      # makes the same claim about upstream, so it stays in the population.
      quoted = [sp for sp in BACKTICK_SPAN.finditer(ln)
                if sp.start() <= m.start() < sp.end()]
      if quoted and not CITE.search(quoted[0].group(0)):
        continue
      rest = ln[m.end():]
      cites: list[dict] = []
      own = CITE.match(rest.strip())
      if own:
        lo = int(own.group(2))
        hi = int(own.group(3)) if own.group(3) else lo
        cites.append({"subject": own.group(1), "lo": lo, "hi": hi,
                      "where": "own", "span": own.span()})
        for b in BARE.finditer(rest):
          if own.start() <= b.start() < own.end():
            continue
          blo = int(b.group(1))
          bhi = int(b.group(2)) if b.group(2) else blo
          cites.append({"subject": own.group(1), "lo": blo, "hi": bhi,
                        "where": "bare-continuation", "span": b.span()})
      blk = next((b for b in blocks if b[0] <= i <= b[1]), (i, i))
      after_cite = ""
      if not cites:
        # THE MARKER'S OWN LINE NAMES NO LINE, so the citation is the one the PROSE it
        # sits in last named. A marker with no prose citation at all is NO-CITATION.
        cands = [(mm.start(), mm) for mm in CITE.finditer("\n".join(lines[blk[0] - 1:blk[1]]))]
        cands = [c for c in cands if c[0] <= i - blk[0]]
        if cands:
          mm = cands[-1][1]
          lo = int(mm.group(2))
          hi = int(mm.group(3)) if mm.group(3) else lo
          cites.append({"subject": mm.group(1), "lo": lo, "hi": hi,
                        "where": "prose", "span": mm.span()})
      item = item_start(lines, i, blk)
      if cites and cites[0]["where"] == "own":
        # THE TEXT AFTER THE CITATION, and the citation is what separates the file from
        # the subject: `TODO(p3) ops.py:502  def ssimplify` says `ssimplify`, and the
        # text after the MARKER says `ops.py`, which names nothing upstream.
        after_cite = rest.strip()[own.end():].strip()
      out.append({
        "rel": rel, "at": i, "line": ln.strip(), "tag": m.group(1),
        "after": rest.strip(), "after_cite": after_cite,
        "before": ln[:m.start()].strip(),
        "cites": cites, "block": blk, "item": item,
        "prefer_dir": prefer_dir,
        "item_text": "\n".join(lines[item - 1:i]),
        "block_text": "\n".join(lines[blk[0] - 1:blk[1]]),
      })
  # THE SUBJECT OF EACH MARKER, AND THE INHERITANCE. A work-queue list writes
  # `TODO(p3) ops.py:502  def ssimplify` and then `TODO(p3) ops.py:503  -- the body is the
  # line above`, and the second entry is about the first entry's subject. So an entry whose
  # own text does not START with an identifier INHERITS the subject of the entry before it
  # in the same comment block.
  by_block: dict[tuple[int, int], list[dict]] = collections.defaultdict(list)
  for rec in out:
    by_block[rec["block"]].append(rec)
  for recs in by_block.values():
    last = ""
    for rec in recs:
      if is_continuation(rec["after_cite"]):
        rec["subject_name"] = last
        rec["subject_kind"] = "inherited" if last else "none"
      else:
        name = subject_token(rec["after_cite"])
        rec["subject_name"] = name
        rec["subject_kind"] = "own" if name else "none"
        if name:
          last = name
  return out


# --------------------------------------------------------------------------- the upstream

class Corpus:
  """The pinned upstream, read as BLOBS.

  `--upstream-dir` points the corpus at a COPY of the tree, which is how the plant moves a
  symbol and watches the citations move with it."""

  def __init__(self, pin: str = "", root: Path | None = None):
    self.pin = pin
    self.root = root
    self._files: list[str] = []
    self._suffix: dict[str, list[str]] = collections.defaultdict(list)
    self._blobs: dict[str, str] = {}
    if root is not None:
      for dp, _dn, fn in os.walk(root):
        for f in fn:
          if f.endswith(".py"):
              p = Path(dp) / f
              rel = str(p.relative_to(root))
              self._files.append(rel)
    else:
      for line in git("ls-tree", "-r", "--name-only", self.pin, "--", "tinygrad/").splitlines():
        if line.endswith(".py"):
          self._files.append(line[len("tinygrad/"):])
    for path in self._files:
      self._suffix[path].append(path)
      j = path.find("/")
      while j != -1:
        self._suffix[path[j + 1:]].append(path)
        j = path.find("/", j + 1)

  def resolve(self, subject: str, prefer_dir: str = "") -> tuple[str, str]:
    """A cited subject -> `(upstream path, how)`. AMBIGUOUS IS A REFUSAL, NEVER `absent`.

    `prefer_dir` is the AMBIENT DISAMBIGUATOR: a bare `__init__.py` names 28 upstream
    files and a bare `dtype.py` names 3, and the port file's own DECLARED UPSTREAM TARGET
    has already said which directory it means."""
    if self.root is not None:
      hits = self._suffix.get(subject, [])
      if len(hits) > 1 and prefer_dir:
        near = [h for h in hits if h.rsplit("/", 1)[0].endswith(prefer_dir)]
        if len(near) == 1:
          return near[0], "suffix-in-declared-dir"
        if near:
          hits = near
      if len(hits) == 1:
        return hits[0], "unique"
      if len(hits) > 1:
        return "", f"ambiguous:{len(hits)}"
      return "", "absent"
    if subject.startswith("tinygrad/"):
      rel = subject[len("tinygrad/"):]
      return (rel, "exact") if rel in self._files else ("", "absent")
    hits = self._suffix.get(subject, [])
    if len(hits) > 1 and prefer_dir:
      near = [h for h in hits if h.rsplit("/", 1)[0].endswith(prefer_dir)]
      if len(near) == 1:
        return near[0], "suffix-in-declared-dir"
      if near:
        hits = near
    if len(hits) == 1:
      return hits[0], "unique"
    if len(hits) > 1:
      return "", f"ambiguous:{len(hits)}"
    return "", "absent"

  def text(self, path: str) -> str:
    if path not in self._blobs:
      if self.root is not None:
        self._blobs[path] = (self.root / path).read_text(encoding="utf-8", errors="replace")
      else:
        self._blobs[path] = git_opt("show", f"{self.pin}:tinygrad/{path}")
    return self._blobs[path]

  def lines(self, path: str) -> list[str]:
    return self.text(path).splitlines()


# --------------------------------------------------------------------------- the upstream's declarations

def decls(lines: list[str]) -> list[tuple[str, int, int]]:
  """`(name, line, indent)` for every `def`/`class`/assignment in an upstream file."""
  out: list[tuple[str, int, int]] = []
  for i, raw in enumerate(lines, 1):
    t = raw.strip()
    if not t or t.startswith("#"):
      continue
    m = DECL.match(raw)
    if m:
      out.append((m.group(2), i, len(m.group(1))))
      continue
    m = ASSIGN.match(raw)
    if m and m.group(2) not in NOT_A_NAME:
      out.append((m.group(2), i, len(m.group(1))))
  return out


def declared_names(lines: list[str]) -> dict[str, int]:
  """`name -> line` for the things an upstream file NAMES, and only those.

  A LOCAL VARIABLE IS NOT A NAMED THING. `shape = tuple(s if ax in axis_ else 1 ...)` four
  lines inside a method is a local, and a census that treated it as the declaration of
  `shape` would point a reader at a line that has nothing to do with the property they
  asked about. So an assignment counts only when it is at MODULE level or in a CLASS
  body."""
  class_names = {n for n, l, _i in decls(lines)
                 if lines[l - 1].strip().startswith("class ")}
  out: dict[str, int] = {}
  for name, line, indent in decls(lines):
    if name in out:
      continue
    if indent == 0 or DECL.match(lines[line - 1]):
      out[name] = line
      continue
    owner = enclosing(lines, line)
    if owner and owner[0] in class_names:
      out[name] = line
  return out


def enclosing(lines: list[str], at: int) -> tuple[str, int, int, int] | None:
  """`(name, decl line, first body line, last body line)` of the construct the 1-based line
  `at` sits INSIDE, or None."""
  stack: list[tuple[str, int, int, int]] = []
  for i in range(1, at):
    m = DECL.match(lines[i - 1])
    if not m:
      continue
    indent = len(m.group(1))
    while stack and stack[-1][3] >= indent:
      stack.pop()
    stack.append((m.group(2), i, i, len(lines)))
  if not stack:
    return None
  name, decl, _first, _last = stack[-1]
  for other in stack:
    if other[0] == name:
      return other
  end = len(lines)
  for j in range(decl, len(lines)):
    s = lines[j]
    if not s.strip() or s.strip().startswith("#"):
      continue
    if len(s) - len(s.lstrip()) <= len(lines[decl - 1]) - len(lines[decl - 1].lstrip()):
      end = j
      break
  return (name, decl, decl, end)


def body_spans(lines: list[str]) -> dict[str, list[tuple[int, int, int, str]]]:
  """`name -> [(decl line, first body line, last body line, kind)]` for every `def`/`class`.

  THE SPAN IS WHAT MAKES A CITATION OF A BODY LINE LEGITIMATE. A marker that says
  "the float64 arm of `cody_waite_reduction`" names a FUNCTION and cites a line INSIDE
  it, and that is a true citation; a marker that says "`def sym_infer`" names a function
  and cites its DEF line, and that is the other true citation. The gate accepts both and
  rejects a line that is in neither.

  A NAME MAY BE DECLARED MORE THAN ONCE -- `ops.py` declares `ssimplify` at 94 (a module
  function) and at 502 (the `UOp` method) -- so a name maps to a LIST and the gate asks
  the LIST, not the first entry."""
  out: dict[str, list[tuple[int, int, int, str]]] = collections.defaultdict(list)
  for i, raw in enumerate(lines, 1):
    m = DECL.match(raw)
    if not m:
      continue
    name, indent = m.group(2), len(m.group(1))
    kind = "class" if raw.strip().startswith("class ") else "def"
    end = len(lines)
    for j in range(i, len(lines)):
      s = lines[j]
      if not s.strip() or s.strip().startswith("#"):
        continue
      if len(s) - len(s.lstrip()) <= indent:
        end = j
        break
    out[name].append((i, i, end, kind))
  # A TABLE IS A NAMED THING WITH A BODY. `pm_lower_weak = PatternMatcher([` opens a
  # table, and a marker that says "pm_lower_weak rule 1" is pointing at an ENTRY of it --
  # so the table's span covers its entries, and a citation of one of them is a citation
  # of the table.
  for name, line in declared_names(lines).items():
    if name in out:
      continue
    raw = lines[line - 1]
    if not ASSIGN.match(raw):
      continue
    value = raw.split("=", 1)[1] if "=" in raw else ""
    if "([" not in value:
      continue
    indent = len(raw) - len(raw.lstrip())
    end = len(lines)
    for j in range(line, len(lines)):
      s = lines[j]
      if not s.strip() or s.strip().startswith("#"):
        continue
      if len(s) - len(s.lstrip()) <= indent:
        end = j
        break
    out[name].append((line, line, end, "table"))
  return dict(out)


def backticked(text: str) -> list[str]:
  """The identifiers the port put in BACKTICKS, in order, without repeats."""
  out: list[str] = []
  for span in BACKTICK.findall(text):
    if re.search(r":[0-9]+", span):
      continue
    for t in IDENT.findall(span):
      if len(t) < 3 or t.lower() in NOT_A_NAME or t in out:
        continue
      out.append(t)
  return out


def symbol_candidates(rec: dict) -> list[str]:
  """The upstream symbols this marker might be about, MOST LIKELY FIRST.

  1. a `def X` / `class X` the marker itself spells out after the citation,
  2. the identifiers the marker writes after the citation, in the order it writes them,
     with a DOTTED name contributing its LAST component first -- the port writes
     `UOp.param_like` and upstream declares `param_like`,
  3. the backticked names of the bullet the marker sits in,
  4. the backticked names of the comment block.

  The candidate list is NOT the verdict: the verdict asks the UPSTREAM FILE which of
  these names it declares, so a marker that names the wrong function is caught by the
  file rather than by a rule about the marker's prose."""
  out: list[str] = []

  def add(t: str) -> None:
    if t and t not in out:
      out.append(t)

  m = re.search(r"\b(?:def|class)\s+([A-Za-z_]\w*)", rec["after"])
  if m:
    add(m.group(1))
  for t in DOTTED.findall(rec["after"]):
    if t in ("def", "class") or t.lower() in NOT_A_NAME:
      continue
    if "." in t:
      add(t.rsplit(".", 1)[1])
    add(t)
  for t in backticked(rec["item_text"]):
    if "." in t:
      add(t.rsplit(".", 1)[1])
    add(t)
  for t in backticked(rec["block_text"]):
    if "." in t:
      add(t.rsplit(".", 1)[1])
    add(t)
  for t in backticked(rec["before"]):
    add(t)
  return out


# --------------------------------------------------------------------------- the census

def census(port: Path, corpus: Corpus, pin_cite, census_mod=None) -> list[dict]:
  """One row per MARKER CITATION, with its verdict."""
  rows: list[dict] = []
  for p in walk_bend(port):
    rel = str(p.relative_to(port.parent)) if port.parent != port else str(p)
    for rec in marker_records(p, rel, census_mod):
      rec["portrel"] = str(p.relative_to(port))
      if not rec["cites"]:
        rows.append({**rec, "subject": "", "lo": 0, "hi": 0, "verdict": "NO-CITATION",
                     "why": "the marker names no upstream line", "up": "", "decl": 0,
                     "symbol": ""})
        continue
      for c in rec["cites"]:
        row = {**rec, **c}
        row.update(judge(row, corpus, pin_cite))
        rows.append(row)
  return rows


def judge(row: dict, corpus: Corpus, pin_cite) -> dict:
  """The verdict for one citation, as the row's fields.

  THE FIX IS PART OF THE VERDICT, and it is part of it because a verdict that says
  "WRONG-LINE" and not "WRONG-LINE TO WHERE" sends a reader to the same place twice. The
  fix is the symbol's DECLARATION line -- or the ONE line the quoted snippet is on -- and
  a RANGE is shifted with the same delta, because a range that names a function's body
  moved with it.

  `confident` says whether the fix is UNIQUE: a symbol declared once, or a snippet that
  appears once in the file. A fix that is a nearest-of-N is a guess, and the gate reports
  the guess and says so rather than dressing it up."""
  subject = row["subject"]
  lo, hi = row["lo"], row["hi"]
  out = {"verdict": "", "why": "", "up": "", "decl": 0, "symbol": "", "new_lo": 0,
         "new_hi": 0, "confident": False}
  if not subject.endswith(".py"):
    out.update({"verdict": "PORT-CITATION",
                "why": f"the marker cites the port's own `{subject}`"})
    return out
  path, how = corpus.resolve(subject, prefer_dir=row.get("prefer_dir", ""))
  if not path:
    out.update({"verdict": "UNRESOLVABLE",
                "why": f"`{subject}` names no upstream file at the pin ({how})"})
    return out
  lines = corpus.lines(path)
  out["up"] = path
  if not lines:
    out.update({"verdict": "UNRESOLVABLE", "why": f"`{path}` is empty at the pin"})
    return out
  declared = decls_of(lines)
  spans = body_spans(lines)
  # THE SYMBOL THE MARKER NAMES. The marker's OWN line names it, or -- for an entry that
  # continues the one before it -- the entry before it named it. It is NOT a search down
  # the line: the word "body" in `-- the body is the line above` is prose, and upstream
  # happens to declare a `body`, and a rule that took it would report a symbol the marker
  # never wrote.
  sym, sym_decl, sym_n = resolve_symbol(lines, spans, declared,
                                        row.get("subject_name", ""), lo)
  out["symbol"] = sym
  if lo < 1 or lo > len(lines):
    if sym:
      out.update({"verdict": "WRONG-LINE", "decl": sym_decl, "new_lo": sym_decl,
                  "new_hi": sym_decl + (hi - lo), "confident": sym_n == 1,
                  "why": f"the file has {len(lines)} lines and the marker cites :{lo}; "
                         f"`{sym}` is declared at :{sym_decl}"})
      return out
    out.update({"verdict": "UNRESOLVABLE",
                "why": f"the file has {len(lines)} lines and the marker cites :{lo}"})
    return out
  inside = enclosing(lines, lo)
  snip = snippet_of(row)
  hits = [i for i, l in enumerate(lines, 1) if snip and snip in l]
  # ---- THE HOLDS. A citation HOLDS when the cited line holds what the marker claims.
  if snip and (lo in hits or any(lo <= h <= hi for h in hits)):
    out.update({"verdict": "RESOLVES",
                "why": f"the cited line holds the quoted snippet {snip[:44]!r}"})
    return out
  if sym:
    if sym_decl == lo:
      out.update({"verdict": "RESOLVES", "decl": sym_decl,
                  "why": f"the cited line declares `{sym}`"})
      return out
    if lo <= sym_decl <= hi:
      out.update({"verdict": "RESOLVES", "decl": sym_decl,
                  "why": f"the cited range covers the declaration of `{sym}` at :{sym_decl}"})
      return out
    for decl, first, last, kind in spans.get(sym.split(".")[-1], []):
      if kind in ("def", "table") and first <= lo and hi <= last:
        out.update({"verdict": "RESOLVES", "decl": decl,
                    "why": f"the cited line is inside `{sym}` (declared at :{decl})"})
        return out
    # THE MARKER NAMES A SHORT FORM OF THE FUNCTION THE CITED LINE IS IN. The port writes
    # "payne_hanek intermediate_dtype" and upstream spells the function
    # `payne_hanek_reduction`; the citation is at the right place and only the NAME is
    # short, and a rule that called that a wrong line would send a reader to rewrite a
    # citation that is already true.
    if inside and (inside[0].startswith(sym) or sym.startswith(inside[0])):
      out.update({"verdict": "RESOLVES", "decl": inside[1],
                  "why": f"the cited line is inside `{inside[0]}` (declared at :{inside[1]}), "
                         f"which upstream spells with the marker's `{sym}`"})
      return out
  # THE SAME TEST ON THE MARKER'S OWN WORDS, for a name upstream does not declare here.
  # The port writes "payne_hanek intermediate_dtype" and upstream spells the function
  # `payne_hanek_reduction`; the citation is at the right place and only the NAME is
  # short, and a rule that called that a wrong line would send a reader to rewrite a
  # citation that is already true.
  raw = row.get("subject_name", "")
  if raw and not sym and inside and (inside[0].startswith(raw) or raw.startswith(inside[0])):
    out.update({"verdict": "RESOLVES", "decl": inside[1],
                "why": f"the cited line is inside `{inside[0]}` (declared at :{inside[1]}), "
                       f"which upstream spells with the marker's `{raw}`"})
    return out
  loose = [t for t in backticked(row["line"]) if t not in declared]
  if loose:
    for i in range(lo, min(hi, len(lines)) + 1):
      for t in loose:
        if re.search(rf"\b{re.escape(t)}\b", lines[i - 1]):
          out.update({"verdict": "RESOLVES",
                      "why": f"the cited line names `{t}`"})
          return out
  # ---- IT DOES NOT HOLD. The symbol is RIGHT and the LINE is wrong, or nothing is known.
  if snip and len(hits) == 1:
    out.update({"verdict": "WRONG-LINE", "decl": hits[0], "new_lo": hits[0],
                "new_hi": hits[0] + (hi - lo), "confident": True,
                "why": f"the cited line does not hold the quoted snippet {snip[:44]!r}; "
                       f"the snippet is at :{hits[0]}"})
    return out
  # THE MARKER NAMES A FUNCTION THAT IS NOT THE ONE IT DESCRIBES. The evidence is that
  # the QUOTED SNIPPET is in the enclosing construct's body AND IS NOT in the named
  # symbol's body: a marker that says "def variable" and quotes `is_variable`'s body
  # names the wrong function, and the fix is to name the one it quotes. A snippet that
  # is in BOTH bodies is not evidence of that -- the marker quoted a line of the
  # function it names, and only its LINE is wrong.
  sym_spans = spans.get(sym.split(".")[-1], []) if sym else []
  sym_body = [(s[1], s[2]) for s in sym_spans]
  if sym and inside and inside[0] != sym and hits and \
          any(inside[1] <= h <= inside[3] for h in hits) and \
          not any(first <= h <= last for h in hits for first, last in sym_body):
    out.update({"verdict": "WRONG-SYMBOL", "decl": inside[1], "new_lo": inside[1],
                "new_hi": inside[1],
                "why": f"the marker names `{sym}` but the quoted snippet is inside "
                       f"`{inside[0]}` (declared at :{inside[1]})"})
    return out
  if sym:
    out.update({"verdict": "WRONG-LINE", "decl": sym_decl, "new_lo": sym_decl,
                "new_hi": sym_decl + (hi - lo), "confident": sym_n == 1,
                "why": f"the cited line does not hold the claim; `{sym}` is declared at "
                       f":{sym_decl}" + ("" if sym_n == 1 else
                                         f" (one of {sym_n} declarations; the nearest)")})
    return out
  if inside:
    out.update({"verdict": "UNRESOLVABLE", "decl": inside[1],
                "why": f"the cited line is inside `{inside[0]}` (declared at :{inside[1]}) "
                       f"and the marker names no symbol this file declares"})
    return out
  out.update({"verdict": "UNRESOLVABLE",
              "why": f"the cited line does not hold the claim and no symbol in the marker "
                     f"is declared in `{path}`"})
  return out


def decl_line_of(name: str, spans: dict, declared: dict, near: int) -> int:
  """The line a symbol is DECLARED at, for the report.

  A NAME MAY BE DECLARED MORE THAN ONCE, and then the nearest declaration to the cited
  line is the one the marker meant -- and the report says so, because a nearest-of-N is a
  weaker claim than a unique one and must not read like it."""
  if name in spans:
    best = min(spans[name], key=lambda s: (abs(s[0] - near), s[0]))
    return best[0]
  return declared.get(name, 0)


def decls_of(lines: list[str]) -> dict[str, int]:
  """`name -> line`, FIRST declaration wins."""
  return declared_names(lines)


def snippet_of(rec: dict) -> str:
  """The longest QUOTED SNIPPET the marker carries, or "".

  A marker that quotes upstream's code is claiming "this code is at that line", and the
  snippet is the claim. The port truncates the quote, so the snippet is a PREFIX of the
  upstream line, which is why the test is `snippet in line` and not equality."""
  best = ""
  for m in SNIPPET.finditer(rec.get("after_cite", "")):
    s = m.group(0).strip()
    # THE PORT'S SENTENCE-PUNCTUATION IS NOT PART OF THE QUOTE. The port writes
    # "`self.ring[off:off + len(data)] = data.`" and upstream's line has no full stop, so
    # a snippet that keeps it matches nothing and the marker is judged on the wrong
    # evidence.
    s = s.rstrip(".,;:")
    if len(s) > len(best):
      best = s
  return best if len(best) >= SNIPPET_MIN else ""


def resolve_symbol(lines: list[str], spans: dict, declared: dict, token: str,
                   near: int) -> tuple[str, int, int]:
  """`(display name, decl line, number of declarations)` for the symbol a marker names, or
  `("", 0, 0)`.

  A DOTTED NAME IS SCOPED, AND IT IS SCOPED OR IT IS NOTHING. The port writes
  `Buffer.profile_events` and `TinyELF.lib`, and upstream declares those as members of
  those classes; an UNSCOPED search finds the module-level `lib` in another class and
  reports a line that is a different thing entirely. And `UOp.sink` names a method of
  `UOp`, which is NOT in the file the marker cites -- so when the QUALIFIER is not a
  class of this file, the name is not resolvable here at all, and the gate says so
  instead of pointing at some other `sink`.

  A NAME MAY BE DECLARED MORE THAN ONCE, and then the declaration NEAREST the cited line
  is the one the marker meant -- the count is reported, because a nearest-of-N is a weaker
  claim than a unique one and must not read like it."""
  if not token:
    return ("", 0, 0)
  parts = token.split(".")
  if len(parts) == 2:
    cls, member = parts
    classes = [s for s in spans.get(cls, []) if s[3] == "class"]
    if classes:
      for cdecl, first, last, _kind in classes:
        line = member_line(lines, first, last, member)
        if line:
          return (f"{cls}.{member}", line, 1)
      return ("", 0, 0)
    # THE QUALIFIER IS NOT A CLASS OF THIS FILE. A Capitalised qualifier is a class
    # FROM ANOTHER FILE -- `UOp.sink` in `codegen/__init__.py` is a CALL, not a
    # declaration here -- and the marker is about the call, not about a symbol. A
    # lowercase qualifier is an INSTANCE -- `x.layernorm` -- and the member is the
    # symbol, so it is looked for unscoped.
    if cls[:1].isupper():
      return ("", 0, 0)
    name = member
  else:
    name = parts[-1]
  if name in spans:
    best = min(spans[name], key=lambda s: (abs(s[0] - near), s[0]))
    return (name, best[0], len(spans[name]))
  if name in declared:
    return (name, declared[name], 1)
  return ("", 0, 0)


def member_line(lines: list[str], first: int, last: int, member: str) -> int:
  """The line inside `[first, last]` that DECLARES `member`, or 0.

  A CLASS BODY holds a member three ways: a `def`, an assignment, and a bare
  ANNOTATION -- `lib: bytes` -- which is how a dataclass declares a field, and a rule
  that only knew about `=` would not see it."""
  for i in range(first, min(last, len(lines)) + 1):
    raw = lines[i - 1]
    t = raw.strip()
    if not t or t.startswith("#"):
      continue
    m = DECL.match(raw)
    if m and m.group(2) == member:
      return i
    m = ASSIGN.match(raw)
    if m and m.group(2) == member:
      return i
    m = ANNOT.match(raw)
    if m and m.group(2) == member:
      return i
  return 0


# --------------------------------------------------------------------------- the report

VERDICT_ORDER = ("RESOLVES", "WRONG-LINE", "WRONG-SYMBOL", "UNRESOLVABLE",
                 "PORT-CITATION", "NO-CITATION")


def report(rows: list[dict], pin: str, detail: str) -> None:
  counts = collections.Counter(r["verdict"] for r in rows)
  nfiles = len({r["rel"] for r in rows})
  print(f"PIN        : {pin[:12]} -- {detail}")
  print(f"POPULATION : {len(rows)} marker citations in {nfiles} `.bend` files")
  print()
  for v in VERDICT_ORDER:
    print(f"  {counts.get(v, 0):5d}  {v}")
  print()
  for v in ("WRONG-LINE", "WRONG-SYMBOL", "UNRESOLVABLE"):
    bad = [r for r in rows if r["verdict"] == v]
    if not bad:
      continue
    print(f"--- {v} ({len(bad)}) ---")
    for r in sorted(bad, key=lambda r: (r["rel"], r["at"])):
      print(f"  {r['rel']}:{r['at']}  {r['subject']}:{r['lo']}"
            + (f"-{r['hi']}" if r["hi"] != r["lo"] else "")
            + f"  symbol={r['symbol'] or '-'}  {r['why']}")
      print(f"      {r['line'][:150]}")
    print()


# --------------------------------------------------------------------------- the plant

def plant(port: Path, corpus: Corpus, pin_cite, census_mod=None) -> int:
  """Two arms, one control, all on COPIES. A plant that matches nothing proves nothing."""
  try:
    return _plant(port, corpus, pin_cite, census_mod)
  except Exception:
    print("PLANT FAILED: a crash is not a pass", file=sys.stderr)
    traceback.print_exc()
    return FAIL


def _plant(port: Path, corpus: Corpus, pin_cite, census_mod=None) -> int:
  rows = census(port, corpus, pin_cite, census_mod)
  # THE ROW THE PLANT ACTS ON. It must be a row whose claim is the DECLARATION of a
  # symbol AT the cited line, because that is the claim both arms can break: pointing
  # the marker one line off, and moving the symbol one line down. A row that resolves
  # because a QUOTE happens to be on that line cannot be broken by moving the symbol,
  # and a plant that cannot be broken proves nothing.
  good = [r for r in rows if r["verdict"] == "RESOLVES" and r["up"] and r["symbol"]
          and r["where"] == "own" and r["decl"] == r["lo"] and r["lo"] > 1
          and r["subject"].endswith(".py")]
  if not good:
    print("PLANT REFUSED: no RESOLVES row whose symbol is declared AT its cited line",
          file=sys.stderr)
    return REFUSED
  target = good[0]
  up_path = target["up"]
  up_text = corpus.text(up_path)
  up_lines = up_text.splitlines()
  decl_line = target["decl"]

  with tempfile.TemporaryDirectory(prefix="todo-cite-plant-") as raw:
    td = Path(raw)
    # ---- ARM 1: a COPY of the PORT with ONE marker pointed at a wrong line.
    port_copy = td / "port"
    shutil.copytree(port, port_copy)
    victim = port_copy / target["portrel"]
    vraw = victim.read_text(encoding="utf-8", errors="replace")
    vlines = vraw.splitlines()
    vline = vlines[target["at"] - 1]
    moved = fix_citation(vline, target["subject"], target["lo"] + 1, target["lo"] + 1)
    if moved == vline:
      print("PLANT REFUSED: the victim marker does not carry its line in the text",
            file=sys.stderr)
      return REFUSED
    vlines[target["at"] - 1] = moved
    victim.write_text("\n".join(vlines) + ("\n" if vraw.endswith("\n") else ""),
                      encoding="utf-8")
    # ---- ARM 2: a COPY of the PINNED UPSTREAM with the symbol MOVED.
    up_copy = td / "upstream"
    (up_copy / Path(up_path).parent).mkdir(parents=True, exist_ok=True)
    shifted = up_lines[:decl_line - 1] + ["# PLANT: a line inserted above the symbol"] + \
        up_lines[decl_line - 1:]
    (up_copy / up_path).write_text("\n".join(shifted) + "\n", encoding="utf-8")
    # ---- THE CONTROL: a BYTE-IDENTICAL copy of the port.
    control = td / "control"
    shutil.copytree(port, control)
    if (control / target["portrel"]).read_bytes() != (port / target["portrel"]).read_bytes():
      print("PLANT FAILED: the control is not a byte copy", file=sys.stderr)
      return FAIL

    live = census(port, corpus, pin_cite, census_mod)
    ctl = census(control, corpus, pin_cite, census_mod)
    arm1 = census(port_copy, corpus, pin_cite, census_mod)
    arm2 = census(port, Corpus(root=up_copy), pin_cite, census_mod)

    def pick(rs: list[dict], rel: str, at: int) -> dict | None:
      for r in rs:
        if r["portrel"] == rel and r["at"] == at and r["subject"] == target["subject"]:
          return r
      return None

    l0 = pick(live, target["portrel"], target["at"])
    c0 = pick(ctl, target["portrel"], target["at"])
    a1 = pick(arm1, target["portrel"], target["at"])
    a2 = pick(arm2, target["portrel"], target["at"])
    if not (l0 and c0 and a1 and a2):
      print("PLANT FAILED: the planted rows are not in the censuses", file=sys.stderr)
      return FAIL
    print(f"PLANT target    : {target['rel']}:{target['at']}  {target['subject']}:{target['lo']} "
          f"symbol=`{target['symbol']}` in {up_path}")
    print(f"PLANT live      : {l0['verdict']}  -- {l0['why']}")
    print(f"PLANT control   : {c0['verdict']}  -- {c0['why']}")
    print(f"PLANT arm1(port): {a1['verdict']}  -- {a1['why']}")
    print(f"PLANT arm2(up)  : {a2['verdict']}  -- {a2['why']}")
    bad: list[str] = []
    if l0["verdict"] != c0["verdict"]:
      bad.append("the byte-identical control did not reproduce the live verdict")
    if a1["verdict"] == "RESOLVES":
      bad.append("arm 1: a marker pointed at the wrong line still RESOLVED")
    if a2["verdict"] == "RESOLVES":
      bad.append("arm 2: a moved symbol still RESOLVED at the old line")
    if arm1 == live:
      bad.append("arm 1: the corrupted copy produced the identical census")
    if arm2 == live:
      bad.append("arm 2: the moved upstream produced the identical census")
    if bad:
      for b in bad:
        print(f"PLANT BAD: {b}", file=sys.stderr)
      return FAIL
    print("PLANT OK: the census noticed both arms and the control was unchanged")
    return PASS


# --------------------------------------------------------------------------- the fixer

def held_paths() -> set[str]:
  """The port paths ANOTHER UNIT IS HOLDING, from `git status --porcelain`.

  A file that is staged-and-modified or modified is somebody else's work in progress,
  and a fixer that rewrites it would land on top of them. The gate REFUSES those files
  and prints the patch for them instead, because a citation that is still false in a file
  the fixer did not touch is a false claim left standing -- and it has to be visible."""
  out: set[str] = set()
  for line in git_opt("status", "--porcelain", "--", PORT_REL).splitlines():
    if len(line) < 4:
      continue
    path = line[3:].strip()
    if " -> " in path:
      path = path.split(" -> ", 1)[1]
    out.add(path)
  return out


def fix_citation(line: str, subject: str, new_lo: int, new_hi: int) -> str:
  """The marker line with its OWN citation's line numbers replaced.

  ONLY THE FIRST CITATION AFTER THE `TODO(pN)` TAG IS TOUCHED, because that is the one
  the marker makes its claim with; a later `elementwise.py:101` in the same line is a
  different claim about a different file."""
  m = MARKER.search(line)
  if not m:
    return line
  tail = line[m.end():]
  cm = CITE.search(tail)
  if not cm or cm.group(1) != subject:
    return line
  if cm.group(3):
    repl = f"{subject}:{new_lo}-{new_hi}"
  else:
    repl = f"{subject}:{new_lo}"
  return line[:m.end()] + tail[:cm.start()] + repl + tail[cm.end():]


def apply_fixes(rows: list[dict], port: Path) -> tuple[int, list[dict]]:
  """Rewrite the citations the census resolved, and report the ones it did not.

  ONLY CONFIDENT ROWS ARE REWRITTEN, and only a row whose fix is UNIQUE: a symbol
  declared once in the file, or a quoted snippet that appears once. A nearest-of-N is a
  guess and the gate reports the guess instead of making it."""
  held = held_paths()
  by_file: dict[str, list[dict]] = collections.defaultdict(list)
  for r in rows:
    if r["verdict"] != "WRONG-LINE" or not r["confident"] or r["where"] != "own":
      continue
    by_file[r["rel"]].append(r)
  applied = 0
  skipped: list[dict] = []
  for rel, rs in sorted(by_file.items()):
    if rel in held:
      skipped.extend(rs)
      continue
    path = ROOT / rel
    raw = path.read_text(encoding="utf-8", errors="replace")
    # THE FILE'S ENDING IS NOT THE FIXER'S BUSINESS. A file with no trailing newline must
    # keep having none, and a fixer that adds one is a fixer that changed a byte it was
    # not asked to change.
    trailing = raw.endswith("\n")
    lines = raw.splitlines()
    for r in rs:
      i = r["at"] - 1
      new = fix_citation(lines[i], r["subject"], r["new_lo"], r["new_hi"])
      if new == lines[i]:
        skipped.append(r)
        continue
      lines[i] = new
      applied += 1
    path.write_text("\n".join(lines) + ("\n" if trailing else ""), encoding="utf-8")
  return applied, skipped


# --------------------------------------------------------------------------- main

def main(argv: list[str]) -> int:
  report_only = "--report" in argv
  rows_out = None
  if "--rows" in argv:
    rows_out = Path(argv[argv.index("--rows") + 1])
  port = ROOT / PORT_REL
  if "--port" in argv:
    port = Path(argv[argv.index("--port") + 1])
  if not port.is_dir():
    print(f"# todo-cite-gate: REFUSED -- the port tree {port} is absent", file=sys.stderr)
    return REFUSED
  pin_cite = load_by_path("todo_cite_pin", HERE / "pin-cite-gate.py")
  census_mod = pin_cite.load_census()
  if "--upstream-dir" in argv:
    corpus = Corpus(root=Path(argv[argv.index("--upstream-dir") + 1]))
    pin, detail = "COPY", "the corpus is a COPY of the pinned upstream"
  else:
    pin, detail = verify_pin()
    if not pin:
      print(f"# todo-cite-gate: REFUSED -- the pin does not verify: {detail}", file=sys.stderr)
      return REFUSED
    corpus = Corpus(pin=pin)
  if "--plant" in argv:
    return plant(port, corpus, pin_cite, census_mod)
  rows = census(port, corpus, pin_cite, census_mod)
  if not rows:
    print("# todo-cite-gate: DEAD -- no row was emitted", file=sys.stderr)
    return DEAD
  if "--fix" in argv:
    applied, skipped = apply_fixes(rows, port)
    print(f"FIXED      : {applied} citations rewritten")
    if skipped:
      print(f"SKIPPED    : {len(skipped)} rows -- a file another unit is holding, or a "
            f"citation this gate did not recognise")
      for r in skipped:
        print(f"  {r['rel']}:{r['at']}  {r['subject']}:{r['lo']} -> {r['new_lo']}  "
              f"[{r['symbol']}]  {r['why']}")
    return PASS
  report(rows, pin, detail)
  if rows_out:
    head = "rel\tat\tsubject\tlo\thi\tverdict\tsymbol\tdecl_line\tupstream\tline\n"
    body = "".join(
      f"{r['rel']}\t{r['at']}\t{r['subject']}\t{r['lo']}\t{r['hi']}\t{r['verdict']}\t"
      f"{r['symbol']}\t{r['decl']}\t{r['up']}\t{r['line']}\n" for r in rows)
    rows_out.write_text(head + body)
    print(f"ROWS       : {len(rows)} -> {rows_out}")
  if report_only:
    print("(REPORT: exit 0 by request; the numbers above are the census, not a verdict)")
    return PASS
  bad = [r for r in rows if r["verdict"] in ("WRONG-LINE", "WRONG-SYMBOL", "UNRESOLVABLE")]
  if bad:
    print(f"# todo-cite-gate: FAIL -- {len(bad)} of {len(rows)} marker citations are false")
    return FAIL
  print("# todo-cite-gate: PASS")
  return PASS


if __name__ == "__main__":
  print(f"# exit vocabulary: {VERDICT}", file=sys.stderr)
  raise SystemExit(main(sys.argv[1:]))
