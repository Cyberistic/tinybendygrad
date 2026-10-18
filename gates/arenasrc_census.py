"""arenasrc_census.py -- THE POPULATION: EVERY WAY THE PORT PUTS A SIZE INTO A NODE.

    .venv/bin/python gates/arenasrc_census.py            # classes, MEMBERSHIP, the verdict
    .venv/bin/python gates/arenasrc_census.py --rows     # one row per site
    .venv/bin/python gates/arenasrc_census.py --accept   # re-pin gates/arenasrc_census.rows
    .venv/bin/python gates/arenasrc_census.py --plant    # the census made to MOVE, and moved

THIS FILE IS ALSO THE LEXER. `gates/arenasrc_probe-check.py` and the one-shot migration
tool import `lex`, `statements`, `enclosing` and `span_of` from here rather than keeping a
second copy: the tree already lost two of nine gate drivers to a prune because an
instrument's parser lived somewhere the tree was clearing. `SITE`, `CONSTRUCTOR` and
`census()` are imported by the same file's `plant()`, so their shapes are its business.

## WHAT THE `nil-src` CLASS WAS, AND WHICH VERDICT IT SHOULD HAVE BEEN EMITTING

Its own header, verbatim:

    `nil-src`    a param-shaped node (`AParam{...}` is its arg) built with `Nil{}` as `src`.
                 Not a self-loop: `nsrc == 0`, so `ParamArg.size(ar, i)` -- which reads
                 `src[0]` -- answers `None` and the node simply HAS NO SIZE. Both print
                 `size=N`, and the acceptance rows cannot tell them apart, so the census
                 has to. The `AParam` test is structural: a node owns a size only if its
                 arg is the port's param record, so a new param-shaped kind is picked up
                 without editing a list here.

"A NODAL CLASS THAT CANNOT TELL ITS TWO CASES APART IS DEAD, NOT A CLASS" -- and `DEAD` is
exit 5 in `gates/gatekit.py`, which this file imports rather than redeclaring. So the class's
verdict was `DEAD` and the gate's could not have been `PASS`: it ran, printed rows, and the
thing the rows existed to carry -- WHICH CASE -- was emitted by nothing. MEASURED what that
cost, by joining these rows to the census that does know (`gates/nilsrc-census.rows`,
`1f891dc3366b`): 31 of the 38 live rows are class B, a SIZED BUFFER/ALLOC/PARAM that LOST
ITS SIZE in the `src[0]` migration, printed beside 7 class-A rows with nothing in the row to
say which was which. The class was not a class. It was a count of suspects wearing a class's
name, and `AGENTS.md`'s DOCTRINE 2 -- "A GATE THAT EXITS 0 HAVING MEASURED NOTHING IS WORSE
THAN NO GATE, BECAUSE IT IS TRUSTED" -- is what makes that worse than having no class.

IT ALSO COULD NOT SEE ITS OWN POPULATION, which is a SECOND defect and a different one, so
they are counted separately. The test was a prefix-shaped one -- `CONSTRUCTOR` requires a
module qualifier (`O.UOp.new(`) and membership required `"AParam" in args[3]` -- and it
MISSED 5 of the 43 sites, because `uop/ops.bend:6302/6303/8352` spell the constructor BARE
(`UOp.new(`, no module prefix) and `codegen/__init__.bend:339/345` pass `O.ABad{}`. FIXING
THE COUNT WITHOUT THE MEMBERSHIP LEAVES A GATE UNDER-COUNTING AND LOOKING FIXED, and
`AGENTS.md` records the shape under `checks/repro-paths.py`, which "STOPPED AT A *REMEMBERED*
EXTENSION, SO A PREFIX OF A PATH WAS READ AS THE PATH". **`args[1]` -- the op -- was NEVER
TESTED BY THAT CLASS AT ALL** (it only labelled `per_class`), so the earlier report of these
three as "the op is spelled `OpsPARAM{}`, without the `O.` its class test requires" names the
wrong test; the cause is the bare `UOp.new(`, and no `O.` on an op has ever been required.

## THE FOUR EXITS THIS FILE CAN REACH, AND WHY NOT FIVE

`PASS 0`, `FAIL 1` (a pin diff, a `?` the CPython lane could not classify, or membership
that does not hold), `REFUSED 3` (the imported census is absent, refuses, or there is no
baseline), `DEAD 5` (it ran and emitted no rows). **`SKIP 4` IS UNREACHABLE HERE AND THAT IS
A CLAIM, NOT AN OMISSION**: a census that walked the tree and classified every site it found
did not skip anything -- there is no lane that could have declined to run, and a site nilsrc
could not resolve arrives as `?`, which is a FAIL here and not a skip. `SKIP` is not the right
word for a hole in this instrument, and using it would be the DEAD-shaped error of reporting
an unmeasured thing as a measured one.

## THE POPULATION, AND WHICH OF THE THREE KINDS EACH CLASS IS

  `param_src`  (c) A REGEX OVER THE TREE'S OWN WRITE SITES -- `SITE`, admitted here. It needs
               the enclosing CALLEE, which is what the backward bracket walk is for, and the
               class is 0 today.
  `nil-src`    (a) A GENERATOR'S OWN DECLARATION, LOADED BY PATH -- `nilsrc.sites()` and
               `nilsrc.census()` from `gates/nilsrc-census.py`, which owns the CPython-lane
               facts (the writers, `ParamArg`'s field order, the pre-migration revision, the
               EXECUTED shapes) and answers A-vs-B per site. NOT RE-DERIVED HERE: a second
               copy of a population is a list that rots silently, and `AGENTS.md`'s DOCTRINE 1
               records SIX instruments in this repo getting exactly that wrong, `AGENTS.md`
               itself the seventh. The site detector is nilsrc's, the ARITY test is
               `thread_src.KIND`'s, and the split is `thread_src.split_top`'s.
  the WIDENER  (b) A DIRECTORY WALK, `port_paths()`, and it is used ONLY to hand nilsrc a
               wider `owned` set so the UNTRACKED scratch can be named. It never finds a site.

`ROOT` is `tinybendygrad/`, so this gate's population is the PORT and the whole-repository
figure belongs to `gates/nilsrc-census.rows`. THE TWO ARE ONE ARTEFACT, and the split is
reported by this file rather than left to a reader's arithmetic: 208 sites over the whole
repository, 154 of them under `.agents/slop/` (scratch and fixtures), 10 under `gates/`, 1
under `oracles/`, and **43 in `tinybendygrad/` -- A=8, B=35**. The headline number is 35.

## MEMBERSHIP IS REPORTED AS A NUMBER OF ITS OWN, NOT AS A TOTAL

`census rows == declared sites` is an ASSERTION, and it is printed next to the count it
holds down (`nilsrc-census.py`'s own acceptance test). `UNTRACKED` is the difference in the
other direction and it is never dropped silently: 15 `*-mut.bend` scratch sites sit on disk,
beside the file their harness mutated, and the declared population excludes them because
`nilsrc.tracked()` reads `git ls-tree -r HEAD` -- so `rows 43 + UNTRACKED 15 = the 58 this
census sees`, of which 5 were invisible before. A number that goes down without a number that
says where it went is a deletion wearing a refactor's clothes.

## WHY LINE-LOCAL LEXING

The first version kept one bracket stack per FILE and it was wrong:
`tinybendygrad/codegen/decomp/dtype-mut.bend:2646` carries the string `"# l2i\\n"`, a `#`
INSIDE a string, and a file-global pass whose string state is shifted by one quote swallows
the closing `"])`, leaving the stack open to EOF and refusing a file that parses.
`statements()` groups lines until the RUNNING bracket depth returns to 0, so a multi-line
call is one unit and a line that will not lex is a REFUSED STATEMENT, COUNTED, never a
silent skip.

MEASURED, Bend accepts BOTH quote characters: `tinybendygrad/uop/upat.bend:1426` is
`String.split(p, '}')`, and scanning that `}` as a bracket refuses the file.
"""
from __future__ import annotations

import importlib.util
import pathlib
import re
import shutil
import sys
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent / "tinybendygrad"
REPO = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import ART, PASS, FAIL, REFUSED, DEAD  # noqa: E402  -- one vocabulary

QUOTES = "\"'"
OPEN = {"(": ")", "[": "]", "{": "}"}
CLOSE = {v: k for k, v in OPEN.items()}
SITE = re.compile(r"\bparam_src\(")
CONSTRUCTOR = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*\.UOp\.new(?:\.\w+)?\(")

PINS = HERE / "arenasrc_census.rows"
NILSRC = HERE / "nilsrc-census.py"
NAME = "arenasrc-census"
#: the repo-relative prefix this gate's population is. `nilsrc`'s paths are repo-relative and
#: these are `ROOT`-relative, so this is the one translation between the two -- a string
#: comparison, not a rule.
PORT_REL = ROOT.relative_to(REPO).as_posix()


class Refused(Exception):
  """A precondition this gate will not guess past. NEVER a silent skip."""


def rel(p: pathlib.Path) -> str:
  """`p` against the repo root when it is under it, and AS GIVEN when it is not.

  A refusal message that raises while it is being built is a traceback where the caller
  wanted a REFUSED, and `Path.relative_to` raises on exactly the paths a refusal is about."""
  try:
    return p.relative_to(REPO).as_posix()
  except ValueError:
    return str(p)


def nilsrc():
  """`gates/nilsrc-census.py`, LOADED BY PATH. Its `sites`, `census`, `tracked` and `PLANTS`.

  By path and not by `import` because the filename carries a hyphen, and by path rather than
  re-derived because it IS the population: it holds the five discovered CPython writers, the
  `ParamArg` field names read out of the annotations, the pre-migration revision found by
  walking `git log`, and the shapes it EXECUTES against the installed lane.
  """
  spec = importlib.util.spec_from_file_location("nilsrc_census", NILSRC)
  if spec is None or spec.loader is None:
    raise Refused(f"{rel(NILSRC)} is not loadable")
  mod = importlib.util.module_from_spec(spec)
  sys.modules.setdefault("nilsrc_census", mod)
  try:
    spec.loader.exec_module(mod)
  except (OSError, ImportError, SyntaxError) as e:
    raise Refused(f"{rel(NILSRC)} did not load: {type(e).__name__}: {e}") from e
  return mod


def port_paths(port: pathlib.Path = ROOT) -> set[str]:
  """Every `.bend` under the port, TRACKED OR NOT, as repo-relative paths.

  A DIRECTORY WALK, and its ONLY use is to WIDEN the `owned` set handed to `nilsrc.sites` so
  the untracked scratch can be named and counted. It never finds a site: `nilsrc`'s detector
  does, which is what keeps a prefix-shaped test out of this file.
  """
  return {p.relative_to(REPO).as_posix() for p in port.rglob("*.bend")}


def lex(line: str) -> tuple[str, str | None]:
  """(code, refusal). `code` is the line with any trailing `#` comment blanked. A quote
  span is consumed left to right and a `#` outside one starts the comment, so an
  apostrophe inside a COMMENT is never mistaken for a literal. A quote with no partner on
  the line is a refusal, because guessing would move a bracket."""
  out: list[str] = []
  i, n = 0, len(line)
  while i < n:
    ch = line[i]
    if ch in QUOTES:
      j = i + 1
      while j < n and line[j] != ch:
        j += 2 if line[j] == "\\" else 1
      if j >= n:
        return "".join(out), f"UNTERMINATED {ch!r}"
      out.append(line[i:j + 1])
      i = j + 1
      continue
    if ch == "#":
      out.append(" " * (n - i))
      return "".join(out), None
    out.append(ch)
    i += 1
  return "".join(out), None


def depth_of(code: str) -> int:
  """Bracket depth of CODE. It SKIPS string spans: `uop/upat.bend:1437` is
  `fmt.go(String.split(fmt, '{'), ...)` and a naive character count reads that `'{'` as
  an opener."""
  d, i, n = 0, 0, len(code)
  while i < n:
    ch = code[i]
    if ch in QUOTES:
      i += 1
      while i < n and code[i] != ch:
        i += 2 if code[i] == "\\" else 1
      i += 1
      continue
    if ch in OPEN:
      d += 1
    elif ch in CLOSE:
      d -= 1
    i += 1
  return d


def split_top(body: str) -> list[str]:
  """top-level comma split of an argument list. `<`/`>` nest because `Maybe<&2, U32>`
  holds one; a string span is opaque."""
  out, cur, stack, i, n = [], [], [], 0, len(body)
  while i < n:
    ch = body[i]
    if ch in QUOTES:
      j = i + 1
      while j < n and body[j] != ch:
        j += 2 if body[j] == "\\" else 1
      cur.append(body[i:j + 1])
      i = j + 1
      continue
    if ch in OPEN:
      stack.append(OPEN[ch])
    elif ch in CLOSE and stack and stack[-1] == ch:
      stack.pop()
    elif ch == "<":
      stack.append(">")
    elif ch == ">" and stack and stack[-1] == ">":
      stack.pop()
    if ch == "," and not stack:
      out.append("".join(cur))
      cur = []
    else:
      cur.append(ch)
    i += 1
  out.append("".join(cur))
  return out


def norm(s: str) -> str:
  return " ".join(s.split())


def span_of(code: str, at: int) -> tuple[int, list[str]]:
  """(offset just past the closer, top-level args) for the call whose `(` is at `at`."""
  d, i, n = 0, at, len(code)
  while i < n:
    ch = code[i]
    if ch in QUOTES:
      j = i + 1
      while j < n and code[j] != ch:
        j += 2 if code[j] == "\\" else 1
      i = j + 1
      continue
    if ch in OPEN:
      d += 1
    elif ch in CLOSE:
      d -= 1
      if d == 0:
        return i + 1, split_top(code[at + 1:i])
    i += 1
  raise ValueError("UNBALANCED")


def enclosing(code: str, at: int) -> tuple[int, str] | None:
  """(offset of the enclosing call's `(`, its callee name), by a BACKWARD bracket walk
  over CODE only. The `(` is FOUND by the walk, never by `rindex("(", ...)`: the last `(`
  before a site belongs to whatever call sits inside the src expression
  (`O.Arena.empty()`), which is how a first draft read every five-argument call as a
  one-argument one."""
  debt = 0
  for i in range(at - 1, -1, -1):
    ch = code[i]
    if ch in CLOSE:
      debt += 1
    elif ch in OPEN:
      if debt == 0:
        j = i - 1
        while j >= 0 and (code[j].isalnum() or code[j] in "._"):
          j -= 1
        return i, code[j + 1:i]
      debt -= 1
  return None


def statements(lines: list[str]):
  """[(first, last, code, refusals)] -- 1-based, inclusive. The depth is the RUNNING
  TOTAL, not the line's own: `uop/weak.bend:287` opens `Bool.pick(` and closes it on
  292, and a per-line test breaks on 293's blank line."""
  out, i, n = [], 0, len(lines)
  while i < n:
    first = i
    code, refusals, total = "", [], 0
    while i < n:
      c, why = lex(lines[i])
      refusals += [f"line {i + 1}: {why}"] if why else []
      code += " " * len(lines[i]) if why else c
      i += 1
      if why:
        break
      total += depth_of(c)
      if total <= 0:
        break
    if total > 0:
      refusals.append(f"statement opens {total} bracket(s) and never closes them")
    out.append((first + 1, i, code, refusals))
  return out


def walk(port: pathlib.Path = ROOT):
  """[(path, rel, first_line, code, refusals)] for every statement of every `.bend` file.

  `port` is a PARAMETER and not a global so `--plant` can census a copy of the tree without
  this file's own population moving under it."""
  for p in sorted(port.rglob("*.bend")):
    for first, last, code, why in statements(p.read_text().split("\n")):
      yield p, str(p.relative_to(port)), first, code, why


# ---------------------------------------------------------------- the two classes


def param_src_rows(port: pathlib.Path):
  """[(row, refusals_count, refusals_carrying_a_site)] over (c) `SITE`.

  A COUNT AND NOT A CLASS: `param_src` is a helper call, and its defect is that the helper
  interned the size node into a THROWAWAY arena and handed back only the index, so the node
  ends up its OWN parent. There is no upstream fact to look up and nothing to discriminate."""
  out, refused, carrying = [], 0, 0
  for _p, where, first, code, why in walk(port):
    if why:
      refused += len(why)
      if SITE.search(code):
        carrying += 1
      continue
    for m in SITE.finditer(code):
      if code[:m.start()].rstrip().endswith("def"):
        continue
      found = enclosing(code, m.start())
      who = found[1] if found else "<toplevel>"
      txt = (norm(code[found[0] - len(who):code.index(")", found[0]) + 1])[:76]
             if found else "")
      out.append({"file": where, "line": code.count("\n", 0, m.start()) + first,
                  "op": who, "class": "param_src", "proof": "", "shape": "",
                  "writer": "", "vmin_vmax": "", "addrspace": "", "unproven": "", "txt": txt})
  return out, refused, carrying


def nil_src_rows(nils, owned, repo: pathlib.Path):
  """(rows, untracked_sites, whole_repo_rows) -- `nil-src` at last told A from B.

  `rows` is nilsrc's OWN census, narrowed to the port. Every field the class was decided by
  is carried onto the row, because a class with no receipt on it is a class nobody can
  re-derive later -- and `proof` names the CPython-lane fact, `writer` the line that fact
  came from, and `unproven` the thing the vendored lane cannot answer."""
  whole = _call(nils, nils.census, owned, repo)
  pop = [r for r in whole if r["file"].startswith(PORT_REL + "/")]
  live = {(r["file"], r["line"]) for r in pop}
  wide = _call(nils, nils.sites, owned | port_paths(repo / PORT_REL), repo)
  untracked = [s for s in wide
               if s["file"].startswith(PORT_REL + "/") and (s["file"], s["line"]) not in live]
  rows = [{"file": r["file"][len(PORT_REL) + 1:], "line": r["line"],
           "op": r["op"], "class": f"nil-src/{r['class']}", "proof": r["proof"],
           "shape": nils.norm(str(r["shape"])), "writer": r["writer"],
           "vmin_vmax": r.get("vmin_vmax", ""), "addrspace": r.get("addrspace", ""),
           "unproven": r.get("unproven", ""), "txt": r["arg"]} for r in pop]
  return rows, untracked, whole


def _call(nils, fn, *args):
  """`fn(*args)` with nilsrc's two refusal shapes as THIS gate's `Refused`.

  `nils.Refused` says a precondition was absent and `thread_src.calls` -- which `sites()`
  drives -- `sys.exit`s with a message on an unbalanced call. Both are REFUSED here, and
  neither is allowed to reach a caller as a traceback or as an `exit 1` that reads FAIL."""
  try:
    return fn(*args)
  except nils.Refused as e:
    raise Refused(str(e)) from e
  except SystemExit as e:
    raise Refused(f"the imported census refused: {e}") from e


def census(port: pathlib.Path = ROOT, repo: pathlib.Path | None = None) -> tuple[list, dict]:
  """(rows, totals). `rows` is one dict per site carrying `file`, `line` and every field the
  class was decided by, sorted by `(file, line)`. `totals` carries BOTH membership numbers
  and the refusal counts, so a caller cannot report a green number without also reporting
  the holes.

  `port`/`repo` are parameters so `--plant` can run this over a COPY: the tree is the
  subject, and a census that fixed a defect before counting it would turn 43 into 42 with
  nobody able to say which row went."""
  repo = repo or REPO
  nils = nilsrc()
  rows, refused, carrying = param_src_rows(port)
  nrows, untracked, whole = nil_src_rows(nils, nils.tracked(), repo)
  rows += nrows
  rows.sort(key=lambda r: (r["file"], r["line"], r["class"]))
  per_class, per_file = Counter(), Counter()
  for r in rows:
    per_class[r["class"] if r["class"] == "param_src" else
              f"{r['class']}/{r['op']}"] += 1
    per_file[r["file"]] += 1
  tally = Counter(r["class"] for r in whole)
  totals = {"files": len(list(port.rglob("*.bend"))),
            "refused_statements": refused, "refused_carrying_a_site": carrying,
            "classes": per_class, "per_file": per_file,
            "declared_sites": len(nrows), "rows": len(rows), "untracked": len(untracked),
            "repo_sites": len(whole), "repo_tally": tally,
            "repo_outside": len(whole) - len(nrows),
            "repo_slop": sum(1 for r in whole if r["file"].startswith(".agents/slop/"))}
  return rows, totals


def render(rows: list) -> str:
  """The `.rows` bytes. Deterministic: `census()` sorts and no set is iterated.

  A `nil-src` row is `nilsrc-census.rows`'s OWN row format minus `src=`, so the two artefacts
  cannot drift in shape and this file's pin is a filtered projection of the census it calls:
  drop the `tinybendygrad/` prefix and the `src=` field and the rows are the same lines. A
  `param_src` row is a COUNT and not a class, so it carries no `proof`/`shape`/`writer`."""
  out = []
  for r in rows:
    parts = [f"site {r['file']}:{r['line']}", f"op={r['op']}", f"class={r['class']}"]
    if r["class"] == "param_src":
      out.append(" ".join(parts))
      continue
    parts += [f"proof={r['proof']}", f"shape={r['shape']}", f"writer={r['writer']}"]
    if r["vmin_vmax"]:
      parts += [f"vmin_vmax={r['vmin_vmax']}", f"addrspace={r['addrspace']}"]
    if r["unproven"]:
      parts.append(f"unproven={r['unproven']}")
    out.append(" ".join(parts))
  return "\n".join(out) + ("\n" if out else "")


#: the fields that say WHICH SITE a row is. The other fields -- `class`, `proof`, `shape`,
#: `writer`, `vmin_vmax`, `addrspace`, `unproven` -- are the CLASSIFICATION and its evidence,
#: and a plant's whole purpose is to move them together: `nilsrc.PLANTS` rewrites the
#: `ParamArg` fields that `is_variable` reads, so `addrspace` moving is the plant working.
#: A comparator that demanded every other field stay still would reject a correct plant.
IDENT = ("op", "txt")


# ---------------------------------------------------------------- the plant


def _verdict(base_map: dict, got_map: dict, want: tuple[str, str]) -> tuple[int, dict, list]:
  """(PASS|FAIL, the class movement, what else moved if anything).

  THE COMPARATOR, IN ONE PLACE, because the negative below calls it with the OPPOSITE
  expectation and a second copy of a comparison is a second contract: a plant that scores
  against a hand-written twin proves nothing about the one that runs.

  IT READS THE SITE IDENTITY TOO, NOT JUST `class`. A MALFORMED SPLICE -- the failure this
  tree's prior plant suffered, and the one that made a lane emit NOTHING while the check
  scored it as a SUCCESSFUL PLANT -- moves a line number, drops a row or rewrites the Arg,
  and a comparator that only looked at `class` would call that a clean movement. Those are
  the `IDENT` fields plus the row set itself."""
  moved = {k: (base_map[k]["class"], got_map[k]["class"])
           for k in base_map.keys() & got_map.keys()
           if base_map[k]["class"] != got_map[k]["class"]}
  lost = sorted(base_map.keys() - got_map.keys())
  gained = sorted(got_map.keys() - base_map.keys())
  collateral = sorted(k for k in base_map.keys() & got_map.keys()
                      if any(base_map[k][f] != got_map[k][f] for f in IDENT))
  why = [f"{len(lost)} row(s) lost {[k.split(':')[-1] for k in lost[:4]]}"] if lost else []
  why += [f"{len(gained)} row(s) appeared {gained[:3]}"] if gained else []
  why += [f"{len(collateral)} row(s) changed their SITE ({', '.join(IDENT)}) {collateral[:3]}"] \
    if collateral else []
  if not moved and not why:
    why = ["no row's class moved -- the plant is planted where this census cannot see it"]
  if moved and set(moved.values()) != {want}:
    why.append(f"moved {sorted(set(moved.values()))}, want {{{want}}}")
  return (PASS if moved and not why else FAIL), moved, why


def plant() -> int:
  """Move one site's upstream shape and require this file's rows to move with it.

  THE PLANTS ARE `nilsrc.PLANTS`, IMPORTED. Copying them here would be a second list of
  fixtures with no generator, and they are fixtures about a lane this gate does not own.

  **THE NEGATIVE IS PROVEN FIRST, IN THE SAME RUN, BECAUSE THE PRIOR ART IN THIS TREE IS
  BRUTAL.** A plant here once FAILED FOUR TIMES, and the worst was a MALFORMED SPLICE that
  made the lane emit NOTHING while the check scored it as a SUCCESSFUL PLANT. So every
  plant is scored TWICE: once against its real expectation, and once against the OPPOSITE
  one, which MUST come back FAIL. A check that cannot say no is a check that cannot mean
  yes, and the second score is what makes the first one mean anything."""
  nils = nilsrc()
  tmp = ART / NAME / "plant"
  key = lambda rows: {f"{r['file']}:{r['line']}": r for r in rows}  # noqa: E731
  base, base_totals = census()
  base_map = key(base)
  bad = []
  for rel, defname, frm, to, want_from, want_to in nils.PLANTS:
    shutil.rmtree(tmp, ignore_errors=True)
    shutil.copytree(ROOT, tmp / PORT_REL)
    dst = tmp / rel
    text = dst.read_text()
    hit = None
    for m in re.finditer(r"^def %s\(" % re.escape(defname), text, re.M):
      seg = text[m.start(): m.start() + 900]
      if frm in seg:
        hit = m.start() + seg.index(frm)
        break
    if hit is None:
      bad.append(f"{rel}: `def {defname}` carrying {frm!r} is absent -- the plant is stale")
      continue
    dst.write_text(text[:hit] + to + text[hit + len(frm):])
    rows, totals = census(port=tmp / PORT_REL, repo=tmp)
    if not rows:
      bad.append(f"{rel}: the census returned NO rows from the copy -- it is not reading "
                 "`port`, so nothing it reports can be evidence of anything")
      continue
    got_map = key(rows)
    want = f"nil-src/{want_from}", f"nil-src/{want_to}"
    code, moved, why = _verdict(base_map, got_map, want)
    # THE OPPOSITE EXPECTATION, THROUGH THE SAME COMPARATOR.
    red, _m, _w = _verdict(base_map, got_map, (want[1], want[0]))
    if red != FAIL:
      bad.append(f"{rel}: the comparator returned {red} for the OPPOSITE expectation "
                 f"{want[1]}->{want[0]}, so it cannot fail and a {PASS} below proves nothing")
    if totals["declared_sites"] != base_totals["declared_sites"]:
      why.append(f"membership moved {base_totals['declared_sites']} -> "
                 f"{totals['declared_sites']}")
      code = FAIL
    print(f"--plant {rel} `def {defname}`: {frm} -> {to}  rows={len(rows)} moved={len(moved)} "
          f"opposite-expectation={red}  {'OK' if code == PASS else 'FAILED ' + '; '.join(why)}")
    for k, (a, b) in sorted(moved.items()):
      print(f"    {k}: {a} -> {b}")
    if code != PASS:
      bad.append(f"{rel}: {'; '.join(why)}")
  shutil.rmtree(tmp, ignore_errors=True)
  if bad:
    print("PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
    return FAIL
  print(f"--plant: {len(nils.PLANTS)} direction(s) moved, and every opposite-expectation "
        f"score came back FAIL")
  return PASS


# ---------------------------------------------------------------- main


def report(rows: list, totals: dict) -> None:
  print(f"population   : (b) os.walk over {PORT_REL}/ for `param_src`  AND  "
        f"(a) nilsrc-census.sites() over the whole repo for `nil-src`")
  print(f"  {PORT_REL}/*.bend      {totals['files']} files, "
        f"{totals['refused_statements']} refused statement(s), "
        f"{totals['refused_carrying_a_site']} of them carrying a `param_src` site")
  t = totals["repo_tally"]
  print(f"  whole repo nil-src     {totals['repo_sites']} sites  "
        + "  ".join(f"{k}={v}" for k, v in sorted(t.items())))
  print(f"    of which .agents/slop/ {totals['repo_slop']}   "
        f"outside {PORT_REL}/ {totals['repo_outside']}")
  print(f"MEMBERSHIP   declared sites {totals['declared_sites']}   "
        f"census rows {totals['rows']}   UNTRACKED(not in the population) {totals['untracked']}")
  print(f"  the PORT-SIDE figure is the {totals['declared_sites']}; the {totals['repo_sites']} is "
        f"this tree's fixtures included and is not a defect count")
  for k, v in sorted(totals["classes"].items()):
    print(f"CLASS\t{k}\t{v}")
  print("--- per file ---")
  for k, v in sorted(totals["per_file"].items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"FILE\t{k}\t{v}")


def main() -> int:
  argv = sys.argv[1:]
  if "--plant" in argv:
    return plant()
  rows_arg, accept = "--rows" in argv, "--accept" in argv
  try:
    rows, totals = census()
  except Refused as e:
    print(f"{NAME}: REFUSED: {e}", file=sys.stderr)
    return REFUSED
  if not rows:
    print(f"{NAME}: DEAD: the census emitted no rows", file=sys.stderr)
    return DEAD
  body = render(rows)
  if rows_arg:
    sys.stdout.write(body)
    return PASS
  report(rows, totals)
  unasked = [r for r in rows if r["class"] == "nil-src/?"]
  holes = []
  if totals["declared_sites"] != len([r for r in rows if r["class"].startswith("nil-src/")]):
    holes.append("the census dropped a declared site")
  if unasked:
    holes.append(f"{len(unasked)} site(s) the CPython lane could not classify -- FAIL, not skip")
    for r in unasked[:10]:
      print(f"  {r['file']}:{r['line']} op={r['op']} proof={r['proof']}")
  if accept:
    PINS.write_text(body)
    print(f"re-pinned {len(rows)} rows into {rel(PINS)}")
    return PASS
  pins = PINS.read_text() if PINS.exists() else ""
  if not pins:
    print(f"{NAME}: REFUSED: {rel(PINS)} is absent, so there is nothing to hold "
          f"this census to -- run with --accept to create it", file=sys.stderr)
    return REFUSED
  if body != pins:
    print(f"{NAME}: FAIL: {len(rows)} rows do not match {rel(PINS)} "
          f"({len(body.splitlines())} now, {len(pins.splitlines())} pinned)")
    now = body.splitlines()
    was = pins.splitlines()
    for a, b in zip(was + [""] * len(now), now + [""] * len(was)):
      if a != b:
        print(f"  pin  {a or '(absent)'}\n  now  {b or '(absent)'}")
    return FAIL
  for hole in holes:
    print(f"{NAME}: FAIL: {hole}", file=sys.stderr)
  if holes:
    return FAIL
  print(f"{NAME}: PASS {len(rows)} rows, membership "
        f"{totals['declared_sites']}/{totals['declared_sites']}, "
        f"{totals['untracked']} untracked scratch site(s) named, pins agree")
  return PASS


if __name__ == "__main__":
  sys.exit(main())