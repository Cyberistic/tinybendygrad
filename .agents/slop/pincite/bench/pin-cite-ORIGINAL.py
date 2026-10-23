#!/usr/bin/env python3
"""pin-cite-gate.py -- DOES THE PORT'S DECLARED PIN MATCH WHAT THE PORT'S CITATIONS RESOLVE AT?

    .venv/bin/python gates/pin-cite-gate.py
    .venv/bin/python gates/pin-cite-gate.py --rows OUT.rows
    .venv/bin/python gates/pin-cite-gate.py --no-report
    .venv/bin/python gates/pin-cite-gate.py --plant

`--rows OUT.rows` WRITES the rows file and still prints the report. `--no-report` prints
the rows alone. (The header census's `--rows` means "rows alone"; this file separates the
two so that a run that saves its rows also shows the reader its numbers.)

UPSTREAM IS THE LOCAL REF `refs/remotes/upstream/master`. This file does not fetch.

THE QUESTION, AND WHY IT IS NOT RHETORICAL. The tree declares a pin -- a commit the vendored
`tinygrad/` is *based on* -- and the port's own `.bend` headers cite upstream `file:line`
positions. Those are two claims about one relationship, and they can disagree: the pin says
"we are at revision R" and the headers say "line N of `ops.py` is the thing I am talking
about". If the headers' line numbers are R's, the two agree. If they are an older
revision's, the port mirrors an OLDER upstream than the pin names.

MEASURED 2026-10-21 ON THIS TREE, AND THE ANSWER IS NOT "THE PORT IS BEHIND". A port
mirrors upstream's BEHAVIOUR; it does not have to mirror upstream's LINE NUMBERS. Each
`.bend` file was ported at a time, and its header cites the line numbers as they stood
then. `AGENTS.md` says the shape out loud for a pin: "the pin's job is to compare a file
against that revision, and 'behind HEAD' is what a pin-for-a-past-revision looks like by
construction. This is not staleness." **SO A CITATION THAT RESOLVES AT AN OLDER REVISION
IS A ROW AND NOT A FAILURE.** It is a header pinned to the revision it was written
against. What IS a failure is a claim true at NO upstream revision (a dangling claim), a
claim true only at a revision NEWER than the pin (the port cites content it does not
have), and a declaration whose OUR PIN no longer names the tree that is vendored.

WHAT THIS ADDS TO THE GATES THAT EXIST. `gates/header-census-gate.py` measures the port's
headers and answers "IS THE CITED LINE INSIDE ITS FILE" -- a LINE-IN-RANGE question, and
it says so: "line-in-range, not a claim that the prose was authored there". This file
asks the CONTENT question: does the cited line HOLD what the port's comment says it
holds, at the declared pin and at the revision the citation actually resolves at. Those
are different questions, and a gate that answers one does not answer the other.
`gates/pinned-tree-gate.py` owns the TREE IDENTITY (`HEAD:tinygrad` vs
`refs/remotes/upstream/master:tinygrad`); this file owns the PIN-vs-CITATIONS relation,
which is a different question about a different pair of objects.

THE POPULATION IS DISCOVERED, NOT NAMED. `os.walk` over `tinybendygrad/` plus
`endswith(".bend")`, and the header/citation PARSER IS `gates/header-census-gate.py`'s,
LOADED BY PATH rather than copied -- one parser, one set of rules, one place a rule
changes.

THE CONTENT TEST, AND IT IS A MARKER AND NOT A STOPLIST. The port writes the thing it
means in BACKTICKS -- `` `pm_device_to_var` ``, `` `PI_A` ``, `` `assert` `` -- and that is
a MARKER the port itself supplies, so the claim tokens are discovered, not listed. A
citation HOLDS at a revision when a claim token is a word on the cited line, or names the
construct DECLARED at the cited line (`def X`, `class X`, `X = ...`), or names the
construct a DECORATOR at the cited line decorates, or (for a range) names a construct
whose body spans the cited range. A header line with no backticked token makes no
CHECKABLE content claim, and it is counted and not verdicted -- an unfalsifiable claim is
not a passing claim.

ONE SUBJECT RULE THE HEADER CENSUS CANNOT APPLY, AND IT IS A DEFECT IN THAT GATE. A bare
`:N` is attributed to the header's declared upstream target, but a header line may name a
file of ANOTHER extension -- `tinybendygrad/base.bend` cites `comp.ts:391`, and `comp.ts`
is a TypeScript file in the bend2 reference, not an upstream `.py`. Attributing its `:391`
to `tinygrad/dtype.py` reports a DANGLING line in a file that was never cited, and
reports that header as resolving at an OLDER REVISION for a reason that has nothing to do
with upstream. This file treats a bare cite on a line that names a non-`.py`/non-`.bend`
file as LOCAL-SIDED and takes it out of the upstream population.

THE EXITS ARE `gatekit`'s. `REFUSED` (3) when a precondition was absent -- the upstream
ref, the port tree, the declaration, or the pin record's own derivation. `DEAD` (5) when
no row was emitted. `FAIL` (1) when a lane is red.
"""

from __future__ import annotations

import collections
import importlib.util
import re
import shlex
import subprocess
import sys
import tempfile
import traceback
import warnings
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
# THE BENCH COPY SITS AT .agents/slop/pincite/bench/, FOUR LEVELS BELOW THE REPO
# ROOT, AND IT MUST JUDGE THE REPO'S GIT AND THE REPO'S DECLARATION.
ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

PORT_REL = "tinybendygrad"
UPSTREAM = "refs/remotes/upstream/master"
DECLARATION = ROOT / ".agents" / "UPSTREAM-PIN.md"

#: A dated record, in the shape `gates/rotclaim-gate.py` reads: `*_RECORD_DATE` and
#: `*_RECORD_DERIVE` are a pair, the command must name a commit, and a second git call
#: reads that commit's date and compares it to the recorded one. `sha256(x) == sha256(x)`
#: CANNOT FAIL; this can, because the date and the object store are different values.
#:
#: THE DERIVE IS BY CONTENT AND NOT BY ASSUMPTION. The pin is the commit whose `tinygrad/`
#: TREE is the tree this repo vendored, and the newest upstream commit that TOUCHED
#: `tinygrad/` is the commit that last changed that content. The tip of `upstream/master`
#: need not be the same commit -- MEASURED, `5c2bf39d6c4b` (a benchmarks commit) does not
#: touch `tinygrad/` at all, and `45fc5ae734a2` is the upstream commit that last did. Both
#: carry the SAME `tinygrad/` tree, `6c91e897`, and the tree is what the port vendored.
#: THE DATE BOUNDS THE DERIVE, so a later upstream commit cannot silently move the record.
PIN_RECORD_DATE = "2026-10-19T22:06:46+08:00"
PIN_RECORD_DERIVE = "git --no-optional-locks log -1 --format=%H refs/remotes/upstream/master -- tinygrad/"

#: The upstream `.py` this header says it is a port of, or "". READ OUT OF THE HEADER by
#: the census's own reader, not remembered.
#: A filename of ANY extension, so the LOCAL-SIDED rule below can see `comp.ts`.
ANY_FILE = re.compile(r"(?<![\w./-])((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.[A-Za-z0-9]+)\b")
BACKTICK = re.compile(r"`([^`]+)`")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
#: A backticked span that IS a citation is the citation, not the claim.
CITE_SPAN = re.compile(r":[0-9]+")
#: Python keywords, which are words in a header and name nothing.
KEYWORDS = frozenset("""and as assert async await break class continue def del elif else except
finally for from global if import in is lambda nonlocal not or pass raise return try while
with yield None True False self cls""".split())
#: The row of the declaration that says which sha is THE pin.
OUR_PIN = "OUR PIN"
#: How far, in characters, a backticked name may sit from a citation and still belong to
#: it. A name and the citation it belongs to are usually adjacent ("`dedup`
#: (search.py:89-90)"), and the port also writes a claim and its citation a clause apart
#: ("(`dtype.py:100-104`) returns ONLY `bool`"). A name FARTHER than this from every
#: other citation belongs to none of them.
_NEAREST = 40


def load_census():
  """`gates/header-census-gate.py` BY PATH. ONE parser, so a rule changes in one place."""
  spec = importlib.util.spec_from_file_location("pin_cite_census", HERE / "header-census-gate.py")
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


def same_instant(a: str, b: str) -> bool:
  def parse(s: str):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc).replace(microsecond=0)
  try:
    return parse(a) == parse(b)
  except ValueError:
    return False


def tree_of(rev: str) -> str:
  return git_opt("rev-parse", "--verify", "--quiet", f"{rev}:tinygrad").strip()


# --------------------------------------------------------------------------- lane P: the pin

def verify_record(date: str, derive: str) -> tuple[str, str, str]:
  """`(state, commit, detail)` for a dated record. A WRONG DATE IS REFUSED."""
  argv = shlex.split(derive)
  if not argv or argv[0] != "git":
    return ("REFUSED", "", "the derivation is not a git command")
  ran = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True)
  parts = ran.stdout.strip().split()
  commit = parts[0] if parts else ""
  if ran.returncode or not commit:
    return ("REFUSED", "", "the derivation named no commit")
  if git_opt("cat-file", "-t", commit).strip() != "commit":
    return ("REFUSED", "", "the derivation named no commit object")
  when = git_opt("log", "-1", "--format=%aI", commit).strip()
  if not when or not same_instant(when, date):
    return ("REFUSED", "", f"commit date {when or 'absent'} != record date {date}")
  return ("VERIFIED", commit, f"date matches ({when})")


def our_pin_shas(text: str) -> list[str]:
  """The hex runs on the declaration's OUR-PIN row. READ OUT OF THE DECLARATION, by the
  label the declaration itself uses, so a superseded pin elsewhere in the file is not
  mistaken for the pin."""
  out: list[str] = []
  for line in text.splitlines():
    if OUR_PIN not in line:
      continue
    out.extend(re.findall(r"\b[0-9a-f]{7,40}\b", line))
  return out


# --------------------------------------------------------------------------- lane C: the citations

def claim_tokens(line: str, subject: str) -> list[str]:
  """The identifiers the port put in BACKTICKS, minus the citation spans and the cited
  file's own stem. DISCOVERED BY A MARKER, not listed."""
  stem = set(IDENT.findall(subject))
  out: list[str] = []
  for span in BACKTICK.findall(line):
    if CITE_SPAN.search(span):
      continue
    for t in IDENT.findall(span):
      if len(t) < 3 or t.lower() in KEYWORDS or t in stem:
        continue
      if t not in out:
        out.append(t)
  return out


def window_tokens(line: str, spans: list[tuple[int, int]], i: int) -> list[str]:
  """The claim tokens that belong to citation `i` on a line that carries several.

  A header line often holds SEVERAL citations and SEVERAL backticked names, and a name
  that belongs to a DIFFERENT citation on the same line must not make this one look like
  it holds. **SO A BACKTICKED NAME BELONGS TO THE NEAREST CITATION.** The port writes
  "`l2i_cdiv.abs` (dtype.py:58-61)", and the name belongs to the citation it sits beside,
  not to the one before it. A citation no name is near makes no CHECKABLE claim, and it is
  counted and not verdicted.
  """
  if i >= len(spans):
    return []
  pos = sorted(enumerate(spans), key=lambda t: t[1][0])
  out: list[str] = []
  for m in BACKTICK.finditer(line):
    if CITE_SPAN.search(m.group(1)):
      continue
    if len(pos) > 1:
      gap = min(max(0, s - m.end(), m.start() - e) for j, (s, e) in pos if j != i)
      if gap > _NEAREST:
        continue
    for t in IDENT.findall(m.group(1)):
      if len(t) < 3 or t.lower() in KEYWORDS:
        continue
      if t not in out:
        out.append(t)
  return out


def declared_at(lines: list[str], idx: int) -> str:
  """The name DECLARED on line `idx` (0-based): `def X`, `class X`, or `X = ...`."""
  t = lines[idx].strip()
  m = re.match(r"(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", t)
  if m:
    return m.group(1)
  m = re.match(r"([A-Za-z_]\w*)\s*(?::[^=]+)?=", t)
  if m:
    return m.group(1)
  return ""


def decorator_target(lines: list[str], idx: int) -> str:
  """The name a DECORATOR on line `idx` decorates, or ""."""
  if not lines[idx].strip().startswith("@"):
    return ""
  for j in range(idx + 1, min(idx + 6, len(lines))):
    name = declared_at(lines, j)
    if name:
      return name
  return ""


def spans_of(lines: list[str], name: str) -> list[tuple[int, int]]:
  """`(first, last)` line numbers of every `def name`/`class name` block, 1-based."""
  starts: list[tuple[int, int, str]] = []
  for i, raw in enumerate(lines):
    t = raw.strip()
    if not t or t.startswith("#"):
      continue
    m = re.match(r"(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", t)
    if m:
      starts.append((i + 1, len(raw) - len(raw.lstrip()), m.group(1)))
  out: list[tuple[int, int]] = []
  for start, indent, nm in starts:
    if nm != name:
      continue
    end = len(lines)
    for j in range(start, len(lines)):
      raw = lines[j]
      if not raw.strip() or raw.strip().startswith("#"):
        continue
      if len(raw) - len(raw.lstrip()) <= indent:
        end = j
        break
    out.append((start, end))
  return out


def holds(lines: list[str], lo: int, hi: int, toks: list[str]) -> tuple[bool, str]:
  """Does the citation HOLD at this revision's content? `(ok, why)`."""
  if not (0 < lo <= len(lines)):
    return (False, f"the file has {len(lines)} lines, the citation is at :{lo}")
  cited = lines[lo - 1]
  for t in toks:
    if re.search(rf"\b{re.escape(t)}\b", cited):
      return (True, f"the cited line names `{t}`")
  name = declared_at(lines, lo - 1)
  if name and name in toks:
    return (True, f"the cited line declares `{name}`")
  deco = decorator_target(lines, lo - 1)
  if deco and deco in toks:
    return (True, f"the cited line decorates `{deco}`")
  if hi > lo:
    for t in toks:
      for start, end in spans_of(lines, t):
        if start <= lo and end >= hi:
          return (True, f"`{t}` spans :{start}-{end}, the cited range is inside it")
  return (False, f"the cited line is {cited.strip()[:48]!r}")


def batch_blobs(specs: list[str]) -> dict[str, str]:
  """`spec` -> text, for many specs, in ONE `git cat-file --batch`."""
  if not specs:
    return {}
  p = subprocess.run(["git", "--no-optional-locks", "cat-file", "--batch"], cwd=ROOT,
                     input=("\n".join(specs) + "\n").encode(), capture_output=True)
  out: dict[str, str] = {}
  buf, pos = p.stdout, 0
  for spec in specs:
    nl = buf.find(b"\n", pos)
    if nl < 0:
      break
    parts = buf[pos:nl].decode("utf-8", "replace").split()
    pos = nl + 1
    if len(parts) < 3 or parts[1] == "missing":
      continue
    size = int(parts[2])
    out[spec] = buf[pos:pos + size].decode("utf-8", "replace")
    pos += size + 1
  return out


# --------------------------------------------------------------------------- the census

def local_sided(line: str) -> bool:
  """Does this line name a file that is NEITHER `.py` NOR `.bend`? Then a bare `:N` on it
  is about that file and not about the header's declared upstream target."""
  for m in ANY_FILE.finditer(line):
    if m.group(1).rsplit(".", 1)[-1].lower() not in ("py", "bend"):
      return True
  return False


def line_spans(census, line: str) -> list[tuple[int, int]]:
  """The char spans of every citation on one header line, in the census's own order:
  the EXPLICIT `file.ext:NN` cites first, then the BARE `:NN` ones. The census's
  `citation_claims` emits them in that order too, so the two lists pair up by index."""
  explicit = [m.span() for m in census.CITE_RE.finditer(line)]
  bare = [m.span() for m in census.BARE_RE.finditer(line)
          if not any(a <= m.start() < b for a, b in explicit)]
  return explicit + bare


def collect(census, base: Path) -> tuple[list[dict], list[dict]]:
  """`(upstream citations, local-sided citations)` over the `.bend` tree at `base`."""
  up: list[dict] = []
  local: list[dict] = []
  for p in sorted(census.walk_bend(base / PORT_REL), key=lambda q: str(q.relative_to(base))):
    rel = str(p.relative_to(base))
    body = p.read_text(encoding="utf-8", errors="replace").splitlines()
    first, _last, blk = census.header_block(body)
    if not first:
      continue
    tgt = census.declared_target(blk)
    cites = census.citation_claims(blk, first, rel, tgt)
    up_dir = tgt.rsplit("/", 1)[0] if "/" in tgt else ""
    by_line: dict[int, list[dict]] = collections.defaultdict(list)
    for c in cites:
      by_line[c["at"]].append(c)
    for at, group in by_line.items():
      spans = line_spans(census, body[at - 1])
      for i, c in enumerate(group):
        c["toks"] = window_tokens(c["line"], spans, i) if i < len(spans) else []
        c["span"] = spans[i] if i < len(spans) else (0, 0)
    for c in cites:
      c["prefer_dir"] = up_dir
      if c["kind"] != census.SUBJECT_UPSTREAM:
        continue
      explicit = f"{c['subject']}:{c['lo']}" in c["line"]
      if not explicit and local_sided(c["line"]):
        local.append({"rel": rel, "at": c["at"], "subject": c["subject"], "line": c["line"]})
        continue
      up.append({**c, "explicit": explicit, "target": tgt})
  return (up, local)


def resolve_all(census, up: list[dict]) -> None:
  """Attach the upstream path and the CONTENT-REVISION to every citation."""
  corpus = census.Upstream(UPSTREAM)
  blobs_cache: dict[str, dict[str, str]] = {}

  def blobs_for(path: str) -> tuple[list[str], dict[str, str]]:
    if path not in blobs_cache:
      corpus.load(path)
      pairs = corpus._steps.get(path) or []
      revs = [corpus.order[gi] for gi, _c in pairs]      # NEWEST FIRST
      blobs_cache[path] = (revs, batch_blobs([f"{r}:{path}" for r in revs]))
    return blobs_cache[path]

  def eval_path(path: str, c: dict) -> tuple[str, str, str, str]:
    """`(newest_rev, why, at_pin, pin_why)` for one citation against ONE upstream path."""
    revs, blobs = blobs_for(path)
    toks = c["toks"]
    newest, why = "", ""
    for r in revs:
      ok, w = holds(blobs.get(f"{r}:{path}", "").splitlines(), c["lo"], c["hi"], toks)
      if ok:
        newest, why = r, w
        break
    # THE PIN'S OWN CONTENT, which the newest touching commit may predate.
    pin_lines = blobs.get(f"{revs[0]}:{path}", "").splitlines() if revs else []
    ok, w = holds(pin_lines, c["lo"], c["hi"], toks)
    return (newest, why, "HOLDS" if ok else "NO", w)

  by_path: dict[str, list[dict]] = collections.defaultdict(list)
  for c in up:
    c.setdefault("toks", [])
    c["newest_rev"] = ""
    c["why"] = ""
    c["at_pin"] = "NO"
    c["pin_why"] = "the cited upstream file does not resolve"
    c["relocated_to"] = ""
    path, how = corpus.resolve(c["subject"], history=True, prefer_dir=c.get("prefer_dir", ""))
    c["path"], c["how"] = path, how
    if path:
      by_path[path].append(c)
  for path, cs in by_path.items():
    for c in cs:
      c["newest_rev"], c["why"], c["at_pin"], c["pin_why"] = eval_path(path, c)

  # THE AMBIENT MIS-RESOLUTION, AND IT IS A DEFECT IN THE HEADER CENSUS, NOT IN THE PORT.
  # A bare basename is ambiguous upstream (`dtype.py` is three files) and the census
  # disambiguates it with the header's DECLARED TARGET's directory. That is right for the
  # header's own subject and WRONG for a citation to a DIFFERENT upstream file that
  # happens to share the basename: `tinybendygrad/codegen/decomp/dtype.bend` cites
  # `float_to_fp16` at `dtype.py:225`, and `float_to_fp16` is in the TOP-LEVEL
  # `tinygrad/dtype.py` and NOT in `tinygrad/codegen/decomp/dtype.py` at all. The census
  # therefore reports a DANGLING line in a file the header never cited. THIS ROW NAMES
  # THE CASE, so the defect is visible in the population that has it.
  for c in up:
    if c["newest_rev"] or "/" in c["subject"] or not c["path"]:
      continue
    for cand in corpus.files().get(c["subject"], []):
      if cand == c["path"]:
        continue
      newest, _why, at_pin, _pw = eval_path(cand, c)
      if newest:
        c["relocated_to"] = cand
        break


# --------------------------------------------------------------------------- the plant

def plant() -> int:
  """A plant that can fail, with an unbroken control, on COPIES."""
  try:
    return _plant()
  except Exception:
    print("PLANT FAILED: a crash is not a pass", file=sys.stderr)
    traceback.print_exc()
    return FAIL


def _plant() -> int:
  if not git_opt("rev-parse", "--verify", UPSTREAM):
    print(f"PLANT REFUSED: {UPSTREAM} is absent. This file does not fetch.", file=sys.stderr)
    return REFUSED
  census = load_census()
  corpus = census.Upstream(UPSTREAM)
  # A CITED FILE DISCOVERED FROM THE CORPUS, not remembered. `helpers.py` is seven upstream
  # files, so a basename is a refusal; a full path is not. The file must also DECLARE
  # something, so the claim is about a construct and not about a comment.
  path, lines, decl, name = "", [], None, ""
  for paths in corpus.files().values():
    for cand in paths:
      if not cand.startswith("tinygrad/") or cand.count("/") != 1:
        continue
      body = git("show", f"{UPSTREAM}:{cand}").splitlines()
      if len(body) < 3:
        continue
      at = next((i for i, l in enumerate(body)
                 if re.match(r"(?:def|class)\s+([A-Za-z_]\w*)", l.strip())), None)
      if at is None:
        continue
      path, lines, decl = cand, body, at
      name = re.match(r"(?:def|class)\s+([A-Za-z_]\w*)", body[at].strip()).group(1)
      break
    if path:
      break
  if not path:
    print("PLANT REFUSED: no top-level tinygrad/*.py declares anything", file=sys.stderr)
    return REFUSED
  n = decl + 1
  # THE HALF-LIE'S LINE: a line that does not name the thing and does not declare it.
  off = next((i for i, l in enumerate(lines)
              if i != decl and name not in l and not declared_at(lines, i) and not decorator_target(lines, i)),
             None)
  if off is None:
    print("PLANT REFUSED: no line to move the citation to", file=sys.stderr)
    return REFUSED
  m = off + 1

  true_src = (f"# synthetic -- port of {path}\n"
              f"# the thing is `{name}`, and it is declared at {path}:{n}.\n")
  half_src = (f"# synthetic -- port of {path}\n"
              f"# the thing is `{name}`, and it is declared at {path}:{m}.\n")
  gone_src = (f"# synthetic -- port of {path}\n"
              f"# the thing is `no_such_symbol_9f3a2c`, and it is declared at {path}:{n}.\n")

  def write(root: Path, src: str) -> None:
    dest = root / PORT_REL / "plant.bend"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(src)

  def judge(root: Path) -> list[dict]:
    cites, _local = collect(census, root)
    resolve_all(census, cites)
    return cites

  with tempfile.TemporaryDirectory(prefix="pin-cite-plant-") as raw:
    td = Path(raw)
    control, control2 = td / "control", td / "control-copy"
    half, gone = td / "half", td / "gone"
    write(control, true_src)
    write(control2, true_src)
    write(half, half_src)
    write(gone, gone_src)
    a, b = control / PORT_REL / "plant.bend", control2 / PORT_REL / "plant.bend"
    if a.read_bytes() != b.read_bytes():
      print("PLANT FAILED: the unbroken control is not a byte copy", file=sys.stderr)
      return FAIL
    if (half / PORT_REL / "plant.bend").read_bytes() == a.read_bytes():
      print("PLANT DEAD: the half-lie copy is identical to the control", file=sys.stderr)
      return DEAD
    ca, cb = judge(control), judge(control2)
    ch, cg = judge(half), judge(gone)
    print(f"PLANT file {path} declares `{name}` at :{n} (local ref, not fetched)")
    for label, cs in (("control", ca), ("control-copy", cb), ("half-lie", ch), ("gone-name", cg)):
      for c in cs:
        print(f"PLANT {label:12s} {c['subject']}:{c['lo']} at_pin={c['at_pin']} "
              f"newest={(c['newest_rev'] or 'NONE')[:12]} -- {c['pin_why']}")
    bad: list[str] = []
    if len(ca) != 1 or len(cb) != 1:
      bad.append(f"the control did not produce exactly one citation: {len(ca)} / {len(cb)}")
    elif ca[0]["at_pin"] != "HOLDS" or not ca[0]["newest_rev"]:
      bad.append(f"the control did not hold at the pin: {ca[0]['at_pin']} {ca[0]['pin_why']}")
    elif [(c["at_pin"], c["newest_rev"]) for c in ca] != [(c["at_pin"], c["newest_rev"]) for c in cb]:
      bad.append("the unbroken control moved")
    if ch and ch[0]["at_pin"] == "HOLDS":
      bad.append(f"the moved line still holds at the pin: {ch[0]['pin_why']}")
    if cg and (cg[0]["at_pin"] == "HOLDS" or cg[0]["newest_rev"]):
      bad.append(f"a name that exists nowhere was reported as holding: {cg[0]['pin_why']}")
    # A WRONG DATE ON THE RECORD IS REFUSED.
    fresh = Path(__file__).read_text()
    broken = fresh.replace(f'PIN_RECORD_DATE = "{PIN_RECORD_DATE}"',
                           'PIN_RECORD_DATE = "1999-01-01T00:00:00Z"', 1)
    if broken == fresh:
      print("PLANT DEAD: the date mutation is a no-op", file=sys.stderr)
      return DEAD
    state, _commit, detail = verify_record("1999-01-01T00:00:00Z", PIN_RECORD_DERIVE)
    if state != "REFUSED":
      bad.append(f"a wrong date was not REFUSED: {state} {detail}")
    state, _commit, detail = verify_record(PIN_RECORD_DATE, PIN_RECORD_DERIVE)
    if state != "VERIFIED":
      bad.append(f"the record did not verify: {state} {detail}")
    if bad:
      print("PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
      return FAIL
    print("PLANT OK: the control holds at the pin, its byte copy holds, the moved line is "
          "seen, a name that exists nowhere is not held, and a wrong date is REFUSED")
    return PASS


# --------------------------------------------------------------------------- main

def main(argv: list[str]) -> int:
  if "--plant" in argv:
    return plant()
  rows_only = "--no-report" in argv
  report_only = "--report" in argv
  rows_out = argv[argv.index("--rows") + 1] if "--rows" in argv else None
  tree_root = Path(argv[argv.index("--tree") + 1]).resolve() if "--tree" in argv else ROOT

  port_root = tree_root / PORT_REL
  if not port_root.is_dir():
    print(f"REFUSED  the port tree {port_root} is ABSENT", file=sys.stderr)
    return REFUSED
  if not git_opt("rev-parse", "--verify", UPSTREAM):
    print(f"REFUSED  {UPSTREAM} is ABSENT", file=sys.stderr)
    return REFUSED
  if not DECLARATION.is_file():
    print(f"REFUSED  the declaration {DECLARATION} is ABSENT", file=sys.stderr)
    return REFUSED

  # ---- lane P -----------------------------------------------------------------
  state, pin_commit, detail = verify_record(PIN_RECORD_DATE, PIN_RECORD_DERIVE)
  pin_tree = tree_of(pin_commit) if state == "VERIFIED" else ""
  head_tree = tree_of("HEAD")
  up_tree = tree_of(UPSTREAM)
  decl_text = DECLARATION.read_text(errors="replace")
  decl_shas = our_pin_shas(decl_text)
  if not decl_shas:
    print(f"REFUSED  {DECLARATION.relative_to(ROOT)} declares no OUR PIN", file=sys.stderr)
    return REFUSED
  decl_trees = {s: tree_of(s) for s in decl_shas}
  agreeing = [s for s, t in decl_trees.items() if t and t == pin_tree]
  disagreeing = [s for s, t in decl_trees.items() if t and t != pin_tree]
  unnamed = [s for s, t in decl_trees.items() if not t]

  # ---- lane C -----------------------------------------------------------------
  census = load_census()
  up, local = collect(census, tree_root)
  resolve_all(census, up)
  if not up:
    print("DEAD  no upstream citation was collected", file=sys.stderr)
    return DEAD

  checkable = [c for c in up if c["toks"]]
  uncheckable = [c for c in up if not c["toks"]]
  at_pin = [c for c in checkable if c["at_pin"] == "HOLDS"]
  only_older = [c for c in checkable if c["at_pin"] == "NO" and c["newest_rev"]]
  nowhere = [c for c in checkable if c["at_pin"] == "NO" and not c["newest_rev"]]
  relocated = [c for c in nowhere if c["relocated_to"]]
  # THE FAIL CLASS IS THE ONE THE AMBIENT CANNOT REACH. A citation whose subject is a
  # FULL PATH names one upstream file, so the census's directory ambient cannot have
  # pointed it at the wrong one, and a claim that holds at NO upstream revision is a
  # DANGLING CLAIM. A bare basename is not in this class: the ambient may have pointed it
  # at a file the header never meant, and that is a defect in the CENSUS, reported as
  # `cite.ambient_relocated` and not as a defect in the port.
  dangling = [c for c in nowhere if c["explicit"] and "/" in c["subject"] and not c["relocated_to"]]
  revs = collections.Counter(c["newest_rev"][:12] for c in only_older)

  rows = {
    "pin.record_state": state,
    "pin.commit": pin_commit,
    "pin.tree": pin_tree,
    "head.tinygrad_tree": head_tree,
    "upstream.tinygrad_tree": up_tree,
    "pin.declared_shas": len(decl_shas),
    "pin.declaration_agrees": len(agreeing),
    "pin.declaration_disagrees": len(disagreeing),
    "pin.declaration_unresolvable": len(unnamed),
    "cite.total": len(up),
    "cite.checkable": len(checkable),
    "cite.uncheckable_no_claim_token": len(uncheckable),
    "cite.at_pin": len(at_pin),
    "cite.only_older_revision": len(only_older),
    "cite.at_no_revision": len(nowhere),
    "cite.at_no_revision_dangling": len(dangling),
    "cite.ambient_relocated": len(relocated),
    "cite.local_sided_excluded": len(local),
    "cite.distinct_older_revisions": len(revs),
  }
  if not rows_only:
    print(f"UPSTREAM   : {UPSTREAM} (local ref, not fetched)")
    print(f"PIN RECORD : {state}  {pin_commit[:12] if pin_commit else '(none)'}  {detail}")
    print(f"           tree {pin_tree[:12] if pin_tree else '(none)'}  "
          f"HEAD {head_tree[:12] if head_tree else '(none)'}  "
          f"upstream {up_tree[:12] if up_tree else '(none)'}")
    print(f"DECLARATION: {DECLARATION.relative_to(ROOT)} names {len(decl_shas)} sha(s) on its "
          f"OUR PIN row; {len(agreeing)} carry the pin's tree, {len(disagreeing)} carry another, "
          f"{len(unnamed)} name no tinygrad/ tree at all")
    print()
    print("LANE C -- THE PORT'S UPSTREAM CITATIONS, BY CONTENT.")
    print(f"           {len(up)} citations, {len(checkable)} with a checkable claim, "
          f"{len(uncheckable)} without one (counted, not verdicted)")
    print(f"           {len(at_pin):5d} HOLD AT THE DECLARED PIN")
    print(f"           {len(only_older):5d} hold ONLY AT AN OLDER REVISION "
          f"({len(revs)} distinct revisions)")
    print(f"           {len(nowhere):5d} hold AT NO UPSTREAM REVISION "
          f"({len(dangling)} of them name one upstream file outright)")
    print(f"           {len(relocated):5d} of those hold at ANOTHER upstream file with the same "
          f"basename (the census's directory ambient pointed them at the wrong one)")
    print(f"           {len(local):5d} bare cites taken out of the upstream population "
          f"(they name a file that is not a .py)")
    print()
    print("THE DANGLING CLAIMS, the ones whose subject names ONE upstream file outright:")
    for c in sorted(dangling, key=lambda c: (c["rel"], c["at"]))[:40]:
      print(f"  {c['rel']}:{c['at']}  {c['subject']}:{c['lo']}  -- {c['pin_why']}")
      print(f"        {c['line'][:110]}")
    print()
    print("THE REVISIONS THE CITATIONS RESOLVE AT, the top twenty:")
    for k, n in revs.most_common(20):
      print(f"  {k}  {n}")

  for k, v in rows.items():
    print(f"{k}={v}")

  if rows_out:
    head = "rel\tat\tsubject\tlo\thi\texplicit\tat_pin\tnewest_rev\tclaim\tline\n"
    body = []
    for c in up:
      body.append(f"{c['rel']}\t{c['at']}\t{c['subject']}\t{c['lo']}\t{c['hi']}\t"
                  f"{int(c['explicit'])}\t{c['at_pin']}\t{c['newest_rev']}\t"
                  f"{','.join(c['toks'])}\t{c['line']}\n")
    Path(rows_out).write_text(head + "".join(body))
    print(f"ROWS       : {len(up)} -> {rows_out}")

  if report_only:
    print("(REPORT: exit 0 by request; the numbers above are the census, not a verdict)")
    return PASS

  if state != "VERIFIED":
    print(f"# pin-cite-gate: REFUSED -- the pin record does not verify: {detail}")
    return REFUSED
  failed: list[str] = []
  if head_tree != pin_tree:
    failed.append(f"the vendored tree {head_tree[:12]} is not the pin's tree {pin_tree[:12]}")
  if not agreeing:
    failed.append(f"the OUR PIN row of {DECLARATION.relative_to(ROOT)} names no sha whose "
                  f"tinygrad/ tree is the pin's {pin_tree[:12]}")
  if disagreeing:
    failed.append(f"{len(disagreeing)} sha(s) on the OUR PIN row carry a different tinygrad/ "
                  f"tree: {', '.join(s[:12] for s in disagreeing)}")
  if dangling:
    failed.append(f"{len(dangling)} citations name ONE upstream file and hold at NO upstream "
                  f"revision (a dangling claim)")
  if failed:
    print(f"# pin-cite-gate: FAIL -- {'; '.join(failed)}")
    return FAIL
  print("# pin-cite-gate: PASS")
  return PASS

if __name__ == "__main__":
  print(f"# exit vocabulary: {VERDICT}", file=sys.stderr)
  raise SystemExit(main(sys.argv[1:]))
