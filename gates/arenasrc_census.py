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

## THE PINS FILE PAIRED BY POSITION, AND WHY A KEY IS NOT A HAND LIST

The comparison used to be `zip(pinned.splitlines(), body.splitlines())`. `census()` sorts,
so ORDER IS DETERMINISTIC -- and that is exactly the trap: a deterministic order read as a
correspondence. ONE KEY LEAVING SHIFTED EVERY LATER ROW, so the diff named files whose rows
had not moved. MEASURED 2026-10-19T16:25Z against 43 pinned and 32 live, with eleven keys
gone: the positional diff printed 32 CHANGED pairs and 11 `(absent)` lines, named
`codegen/__init__.bend:339` as changed when nothing in that file had moved, and named
`uop/ops.bend:6302` as CHANGED *AND* AS ABSENT IN THE SAME RUN -- the padding tail is the
same misalignment read from the other end. Keyed on the `site <file>:<line>` field `render()`
already emits first, the same two files say 31 both, **0 CHANGED**, 12 LOST, 1 APPEARED, and
the one that appeared is `uop/fold.bend:5307` sitting 17 lines lower at `:5324` carrying a
byte-identical row.

**THE KEY IS A FIELD OF THE ROW, NOT A PATH LIST.** `render()` puts `site <file>:<line>`
first on every line, so matching on it needs nothing added to the format and nothing
maintained by hand -- which is the only kind of population `AGENTS.md`'s DOCTRINE 1 allows
in a pins file. A list of the eleven paths would have been the defect wearing a fix's
clothes.

## WHAT A `retired` ROW IS, AND WHAT IT IS NOT

`--accept` writes `retired <file>:<line> ...` for every key that left, computed from
`PINS - body` and carrying the class it had. So the movement is RECORDED, which is the
alternative to a snapshot that cannot say whether a site was fixed or deleted -- the
`artefacts_ok()` trade, and `AGENTS.md`'s "a number that goes down without a number that
says where it went is a deletion wearing a refactor's clothes".

**A TOMBSTONE IS NOT A REASON.** NOTHING IN THIS FILE CAN TELL A FIX FROM A DELETION: both
are a key the detector no longer returns, and the two leave different bytes in
`tinybendygrad/` and the same absence here. So the gate prints, LIVE and NEVER STORED, how
many rows each retired key's file carries now -- which answers "did the file die" and "did
other sites leave it too" -- and says outright that it is not a claim of a fix. THE INDEPENDENT
FACT FOR THIS RE-PIN IS NOT HERE AT ALL, and is in the commit message: the eleven sites now
spell `O.UOp.new.param(ar, op, Some{n}, ...)`, and `n` is the size (`UOp.new.param` is
`(+ar, +op, n: Maybe<&2, U32>, arg, tag)` and spends it on `shape_to_shape_arg.of`), which
`sed -n` on the file shows without consulting this one.

## WHAT THIS FILE STILL CANNOT SEE

`nil-src`'s population is `thread_src.calls`, the tree's own `UOp.new(` WRITE SITES. A
hand-written `Node{...}` arena literal is not a call, so it is invisible STRUCTURALLY, not
by a missed prefix: `s5.arena()` (`uop/ops.bend:6898`) and `s5.ga.arena()` (`:7215`) carry
SIX size-less `Node{Ops{BUFFER,ALLOC,PARAM}{}, Nil{}, ...}` literals between them -- THREE
each, at `ops.bend:6902/6903/6904` and `:7218/7219/7220` -- beside the two
`Node{OpsCONST{}, Nil{}}` at `:6901` and `:7227`, which are NOT in the class because the
class is a node whose ARG IS `AParam{...}` and a CONST's arg is `APy{...}`. MEASURED 16:41Z
by grepping the two function bodies. (SIX, not eight: the other two are the CONST literals.)
Closing that is a change to `tinybendygrad/uop/ops.bend`, which moves `substrate_digest()`
and invalidates the green corpus run, so it is named here and NOT made.
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


# ---------------------------------------------------------------- the pins file
#
# THE KEY IS THE `site <file>:<line>` FIELD `render()` ALREADY EMITS FIRST ON EVERY ROW, so
# nothing has to be added to the row format to match on it and no list of paths has to be
# written down. MEASURED UNIQUE on both sides, 2026-10-19T16:26Z, `.venv/bin/python
# gates/arenasrc_census.py --rows` and `gates/arenasrc_census.rows`: 43 distinct keys over
# 43 pinned rows, 32 over 32 live, zero collisions -- which is what `census()`'s sort on
# `(file, line, class)` buys, and a collision would be a site the census cannot tell apart
# from its own neighbour on one line.
#
# A ROW THAT MOVED IS A ROW WHOSE KEY MATCHED AND WHOSE BYTES DIFFERED. A KEY THAT IS
# ABSENT FROM ONE SIDE LEFT. Those are DIFFERENT CLAIMS AND THE POSITIONAL COMPARATOR THIS
# REPLACES COULD NOT TELL THEM APART, because `zip(pins, body)` pairs by ORDINAL: ONE KEY
# LEAVING SHIFTS EVERY LATER ROW.

SITE_FIELD = "site"
RETIRED_FIELD = "retired"


def verb(row: str) -> str:
  """`site` or `retired`. Which of the two is the whole difference between a row that is
  in the population and a row that was and is not, and it is a WORD so the file reads."""
  return row.split(" ", 1)[0]


def key_of(row: str) -> str:
  """The `<file>:<line>` a row is ABOUT, verb stripped. A line without a verb is its OWN
  key rather than `None`, so a hand-mangled pins line cannot silently merge into another
  row's bucket -- it fails as itself, named, on the first line of the diff."""
  parts = row.split(" ")
  return parts[1] if len(parts) > 2 and parts[0] in (SITE_FIELD, RETIRED_FIELD) else row


def live_of(rows: list[str]) -> str | None:
  return next((r for r in rows if verb(r) == SITE_FIELD), None)


def dead_of(rows: list[str]) -> list[str]:
  return [r for r in rows if verb(r) == RETIRED_FIELD]


def index(rows: list[str]) -> dict[str, list[str]]:
  """{key: [rows naming it]} -- a LIST, because one key may be BOTH `retired` and `site`.
  That is a site that left the population and came back, and the two events are separate
  facts; a map holding one of them would drop the record of the first on the very re-pin
  that noticed the second, which is the defect this file was corrected for, one level
  down."""
  out: dict[str, list[str]] = {}
  for row in rows:
    out.setdefault(key_of(row), []).append(row)
  return out


def retire(row: str) -> str:
  """The same row, said to have LEFT. Only the verb changes: the key and the classification
  it carried are carried over verbatim, so a tombstone still names what it was."""
  return RETIRED_FIELD + row[len(SITE_FIELD):]


def class_of(row: str | None) -> str:
  return row.split(" class=", 1)[1].split(" ", 1)[0] if row else "?"


def tally(rows: list[str]) -> Counter:
  """{class: n}. THE TRUSTWORTHY NUMBER. A positional diff reports how many LINES differ,
  which is a fact about the ALPHABET and not about the population; this counts classes on
  each side, so 11 BUFFER/ALLOC sites leaving reads as what it is."""
  return Counter(class_of(r) for r in rows if " class=" in r)


def compare(pins: str, body: str) -> tuple[int, list[str]]:
  """(PASS|FAIL, the movements, in the order a reader needs them). KEYED, NEVER POSITIONAL.

  FOUR MOVEMENTS, FOUR CLAIMS. `LOST` and `APPEARED` are POPULATION -- a key is on one side
  and not the other. `CHANGED` is CLASSIFICATION -- a key is on both sides and its bytes
  differ. `BACK` is A RETIREMENT REVERSED -- a key this file called `retired` is in the
  population again. The positional comparator had no key to tell them by, and MEASURED what
  that costs: 43 pinned against 32 live on 2026-10-19T16:25Z, eleven keys gone, it printed
  32 CHANGED PAIRS and 11 `(absent)` lines -- naming `codegen/__init__.bend:339` as changed
  when nothing in that file moved, and naming `uop/ops.bend:6302` as CHANGED *AND* AS
  ABSENT IN THE SAME RUN, because the `(absent)` tail is the same misalignment seen from
  the other end. Keyed, the same two files say 31 both, 0 CHANGED, 12 LOST, 1 APPEARED,
  and the one that appeared is `uop/fold.bend:5307` sitting 17 lines lower at `:5324`
  carrying a BYTE-IDENTICAL row."""
  was, now = index(pins.splitlines()), index(body.splitlines())
  lost = sorted(k for k in was if live_of(was[k]) and not now.get(k))
  gained = sorted(k for k in now if not was.get(k))
  back = sorted(k for k in now if dead_of(was.get(k, [])))
  changed = sorted(k for k in was.keys() & now.keys()
                   if live_of(was[k]) and live_of(was[k]) != live_of(now[k]))
  why = []
  if lost:
    why.append(f"LOST   {len(lost)} key(s) LEFT the population: {lost}")
  if gained:
    why.append(f"APPEARED {len(gained)} key(s) NOT in the pins: {gained}")
  if back:
    why.append(f"BACK   {len(back)} RETIRED key(s) are in the population AGAIN: {back}")
  for k in changed:
    why.append(f"CHANGED {k}  class {class_of(live_of(was[k]))} -> {class_of(live_of(now[k]))}")
  return (FAIL if why else PASS), why


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


def pin_plants(body: str) -> int:
  """Three movements of the PINS FILE ALONE, scored through `compare`, which is the
  comparator that runs -- not a hand-written twin of it, which would prove nothing about
  the one the gate uses.

  **THE REORDER IS THE PLANT THE POSITIONAL DEFECT OWNS.** `zip(pins, body)` reads ORDER as
  a claim, so REVERSING the rows of a pins file whose CONTENT did not change at all makes
  it report that every row moved. A comparator that survives this cannot be pairing by
  position, whatever it says in a comment.

  **THE OTHER THREE ARE WHAT MAKES THE FIRST ONE MEAN ANYTHING.** A comparator that answered
  PASS to everything would pass the reorder, and this tree's prior art is a plant that
  emitted NOTHING while the check scored it a successful plant. So the SAME comparator, on
  the SAME rows, must ALSO name a key the census has and the pins do not, a key the pins
  have and the census does not, and a changed class -- and the suite has no verdict if any
  of those goes quiet: `always-PASS` fails the last three, `always-FAIL` fails the first.
  The two DROPS ARE THE SAME ONE-ROW EDIT DONE TO OPPOSITE SIDES, which is the whole point:
  `LOST` and `APPEARED` are different CLAIMS and the positional comparator had no key to
  tell them by. There is no constant here to flatten -- every plant is the real rows, one row
  apart. `RECLASS` mutates the PINS side and therefore expects the message in `compare`'s
  direction, PIN THEN NOW, so the plant pins the ORDER OF THE CLAIM as well as its content."""
  rows = body.splitlines()
  if len(rows) < 3:
    print("--plant: the census emitted too few rows to move one", file=sys.stderr)
    return FAIL
  drop, cls = rows[-1], rows[0]
  head, _, tail = cls.partition(" class=")
  old, _, rest = tail.partition(" ")
  new = "nil-src/B" if old == "nil-src/A" else "nil-src/A"
  # (name, the PINS side, the CENSUS side, the verdict wanted, what the ONE movement must name)
  cases = [("REORDER every row, change nothing", "\n".join(reversed(rows)), body, PASS, None),
           ("DROP one row FROM THE PINS", "\n".join(rows[:-1]), body, FAIL, key_of(drop)),
           ("DROP one row FROM THE CENSUS", body, "\n".join(rows[:-1]), FAIL, key_of(drop)),
           ("RECLASS one row", "\n".join(f"{head} class={new} {rest}" if r == cls else r
                                         for r in rows), body, FAIL,
            f"{key_of(cls)}  class {new} -> {old}")]
  bad = []
  for name, pins, census, want, named in cases:
    code, why = compare(pins, census)
    ok = code == want and (named is None or (len(why) == 1 and named in why[0]))
    print(f"--plant {name}: scored {code} naming {len(why)} movement(s) -- {'OK' if ok else 'FAILED'}")
    for w in why:
      print(f"    {w}")
    if not ok:
      bad.append(f"{name}: scored {code} naming {len(why)}, want {want}"
                 + (f" naming {named!r}" if named else " naming nothing"))
  if bad:
    print("PIN PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
    return FAIL
  print("--plant: order is not a claim; a key only one side has is, and so is a changed class")
  return PASS


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
  # FIRST, AND CHEAP: the pins-file plants need no tree copy, so a `copytree` failure must
  # not be what decides whether the COMPARATOR was ever shown to be able to say no.
  pinbad = pin_plants(render(base))
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
  if bad or pinbad != PASS:
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
    # A RE-PIN THAT HIDES A COMPLAINT IS THE ONE MOVE THIS GATE MUST NOT MAKE, so the
    # holes are checked BEFORE the write and not after it. MEASURED: the ordering this
    # replaces returned PASS from `--accept` on a census carrying `nil-src/?` rows, which
    # is the whole population the CPython lane could not classify, and wrote them into the
    # pins where the next run compared them like any other row.
    for hole in holes:
      print(f"{NAME}: REFUSED: {hole}", file=sys.stderr)
    if holes:
      return REFUSED
    # A KEY THAT LEFT IS WRITTEN DOWN AS ONE. `--accept` computes the tombstones from
    # `PINS - body`, so no path is typed and the list cannot rot: it is this file's own
    # diff, which is the only kind of population a pins file may hold.
    was, live = index(PINS.read_text().splitlines()) if PINS.exists() else {}, index(body.splitlines())
    gone = [live_of(was[k]) for k in sorted(was) if live_of(was[k]) and k not in live]
    PINS.write_text(body + "".join(retire(r) + "\n" for r in gone))
    print(f"re-pinned {len(rows)} row(s) into {rel(PINS)}"
          + (f"; {len(gone)} key(s) RETIRED, not dropped: "
             f"{[key_of(r) for r in gone]}" if gone else "; 0 retired"))
    return PASS
  pins = PINS.read_text() if PINS.exists() else ""
  if not pins:
    print(f"{NAME}: REFUSED: {rel(PINS)} is absent, so there is nothing to hold "
          f"this census to -- run with --accept to create it", file=sys.stderr)
    return REFUSED
  code, why = compare(pins, body)
  if code == FAIL:
    print(f"{NAME}: FAIL: {len(rows)} rows against {rel(PINS)} -- "
          f"{len(body.splitlines())} now, {len(pins.splitlines())} pinned, and these MOVEMENTS:")
    for w in why:
      print(f"  {w}")
    return FAIL
  for hole in holes:
    print(f"{NAME}: FAIL: {hole}", file=sys.stderr)
  if holes:
    return FAIL
  was = index(pins.splitlines())
  dead = [r for rs in was.values() for r in dead_of(rs)]
  print(f"{NAME}: PASS {len(rows)} rows, membership "
        f"{totals['declared_sites']}/{totals['declared_sites']}, "
        f"{totals['untracked']} untracked scratch site(s) named, pins agree")
  if dead:
    # LIVE-DERIVED, NEVER STORED: a tombstone carries no reason, because a pins file CANNOT
    # TELL A FIX FROM A DELETION -- both are a key that is no longer detected. So the gate
    # prints what it can measure about each, and says plainly what it cannot.
    print(f"  {len(dead)} RETIRED key(s) in the pins -- each one a site this file once saw and "
          f"does not see now. IT IS NOT A CLAIM THAT IT WAS FIXED:")
    for r in dead:
      here = totals["per_file"].get(key_of(r).rsplit(":", 1)[0], 0)
      print(f"    {key_of(r)}  retired class={r.split('class=', 1)[1].split(' ', 1)[0]}  "
            f"{key_of(r).rsplit(':', 1)[0]} now has {here} row(s)")
  return PASS


if __name__ == "__main__":
  sys.exit(main())