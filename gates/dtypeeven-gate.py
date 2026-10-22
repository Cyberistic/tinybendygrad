#!/usr/bin/env python3
"""dtypeeven-gate.py -- the port's `dtypes.*` NAMES, in BOTH directions, against upstream's.

    .venv/bin/python gates/dtypeeven-gate.py

THE CLAIM, IN ONE SENTENCE. The port may spell a `dtypes.<name>` accessor only for a name
upstream's `dtypes` spells, and every name upstream spells that the port does not spell must
fall in a class the port DECLARED it omits -- and the declaration is a RULE over upstream's
own source blocks, not a list of names.

THE SHAPE IS `gates/opseven-gate.py`'s, AND THAT IS THE POINT. That gate reads the port's
`type Op is Data:` block and upstream's `Ops` enum and COMPARES THE TWO SETS, in both
directions, with nothing transcribed. This gate reads the port's `dtypes.*` DEFS and
upstream's `dtypes` and compares the two sets the same way, so a name one side can spell and
the other cannot is a NAMED FINDING rather than a difference nobody looks at.

FOUR POPULATIONS, AND NONE OF THEM IS A LIST TYPED HERE.

  THE PORT'S ACCESSORS  the `def dtypes.<name>(` lines of `tinybendygrad/dtype.bend`. This is
                        the port's OWN declaration of what it can spell, read BY PATH.
  THE PORT'S SPELLINGS  the arms of the port's `to_dtype_of` table. Upstream's `to_dtype` is
                        `getattr(dtypes, name.lower())`, so the table's keys are the names
                        upstream's `dtypes` answers to, and the table is the port's own
                        NAME-LEVEL declaration of which of them the port takes.
  THE PORT'S POLICY    the `DTYPES-POLICY:` lines in the same file, next to the reason.
  UPSTREAM'S NAMES     `dir(tinygrad.dtypes)`, LIVE -- upstream's own object, not a
                        transcription of it -- and the CLASSES those names fall in, read out of
                        upstream's own `tinygrad/dtype.py`.

THE CLASSES ARE RULES AND NOT LISTS, AND THAT IS WHAT MAKES THEM CHECKABLE.

  canonical     upstream's `Final[DType]` block -- the dtype VALUES, named by upstream.
  legacy-alias  upstream's `# legacy dtype aliases` block -- the old spellings, named by
                upstream.
  grouping      upstream's tuple-valued class attributes -- `fp8s`, `floats`, `all`, ...
  helper        the RESIDUAL: whatever upstream's `dtypes` spells that is none of the above.

A LIST OF THE PORT'S OMISSIONS WOULD ROT THE MOMENT UPSTREAM MOVED, AND A GATE THAT READS A
ROT LIST CANNOT TELL A ROT LIST FROM A CORRECT ONE. SO THE THREE DISCOVERED CLASSES ARE READ
OUT OF UPSTREAM'S OWN BLOCKS, THE FOURTH IS COMPUTED AS THE RESIDUAL, AND THE GATE HOLDS
THAT THE THREE BLOCKS ARE STILL THERE AND STILL DISJOINT -- so a name upstream adds lands in
the residual BY ARITHMETIC, and a name upstream's own source stops marking leaves an empty
class, which is a rule that stopped describing upstream.

WHAT IS RED, AND IN WHICH DIRECTION. Both, and by name.

  DIVERGENCE   the port spells a name upstream cannot. `dtypes.index` was one: upstream's
               `dtypes` has no `index`, nothing in the tree called it, and the port's own
               rule says a def nothing calls is invisible to every check.
  OMISSION     upstream spells a name the port does not, and the port's declaration does not
               cover it -- or covers it in a class upstream NO LONGER HAS. A declaration that
               has stopped being true is a stale declaration, and a stale declaration is a
               lie the gate is being asked to believe. The port's `to_dtype_of` table is
               where that staleness shows up first, because it is a table of NAMES.

THE PLANT IS A TEXT EDIT AND IT LIVES BESIDE THIS FILE, in `gates/dtypeeven-plant.py`.
"""

import importlib.util
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REAL_ROOT = HERE.parent
# THE TREE IS PASSED IN, NOT FOUND. `TINYGRAD_ROOT` names it, so the plant can point this
# gate at a MIRROR tree whose `tinybendygrad/dtype.bend` carries the defect and leave this
# tree alone. `gates/gatekit.py` reads the same variable, but it resolves its own `__file__`
# FIRST, so a `gates/` directory that is a symlink defeats it -- and a mirror is exactly
# that shape. Hence the local read.
ROOT = Path(os.environ.get("TINYGRAD_ROOT") or REAL_ROOT).resolve()
PORT = ROOT / "tinybendygrad" / "dtype.bend"
UP_SRC = ROOT / "tinygrad" / "dtype.py"

# THE FIVE VERDICTS, AS EXITS. Restated rather than imported from `gates/gatekit.py`, and
# the reason is the same one `gates/pinned-tree-gate.py` gives: a NUMBER is a convention the
# file owns, and this file needs no gate plumbing.
PASS, FAIL, REFUSED, DEAD = 0, 1, 3, 5
VERDICT = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", DEAD: "DEAD"}

# THE CLASSES THE PORT'S POLICY TALKS ABOUT, and the MODES a policy line may carry.
CLASSES = ("canonical", "legacy-alias", "grouping", "helper")
MODES = ("ALL", "NONE", "PARTIAL")

_STRIPPER = None


# --------------------------------------------------------------------------- the port's own source


def _stripper():
  """`checks/port-compile-gate.py`'s own `strip_comments()`, imported BY PATH.

  THE HOUSE'S STRIPPER, AND NOT A SECOND ONE: it knows that a `#` inside a string is not
  a comment, and a second stripper here would be a second copy of that knowledge.  It is
  loaded ONCE and cached, because it is a module import and an import is not free.
  """
  global _STRIPPER
  if _STRIPPER is None:
    spec = importlib.util.spec_from_file_location(
      "port_compile", REAL_ROOT / "checks" / "port-compile-gate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    _STRIPPER = mod
  return _STRIPPER


def _code_lines(text: str) -> list[str]:
  """The port's RAW lines that are CODE, with the comment-only lines dropped.

  THE HOUSE'S STRIPPER FINDS WHICH LINES ARE CODE AND THE RAW LINE IS KEPT.  The two
  halves are both needed: the stripper knows a `#` inside a string is not a comment, and
  it blanks the STRING LITERALS -- so the port's `to_dtype` table, which IS a table of
  strings, cannot be read from the stripped text.  A comment-only line strips to blank,
  so dropping the blank ones removes every commented-out `case` arm from the population.
  """
  stripped = _stripper().strip_comments(text).split("\n")
  return [raw for raw, s in zip(text.split("\n"), stripped) if s.strip()]


def _def_body(text: str, header: str) -> str:
  """The body of one `def` in the port's own file, BY ITS OWN SIGNATURE.

  `gates/opseven-gate.py`'s `_body`, for the same reason it gives: a locator that a rename
  invalidates is not a locator, and a file that grows above the def moves nothing.
  """
  m = re.search(header + r"[^\n]*:\n(.*?)\n(?=\S)", text, re.S)
  if m is None:
    raise ValueError(f"no `{header}` in {PORT}")
  return m.group(1)


def _port_accessors(lines: list[str]) -> list[str]:
  """The `dtypes.<name>` DEFS the port declares -- its own declaration of what it spells."""
  return re.findall(r"^def dtypes\.(\w+)\(", "\n".join(lines), re.M)


def _port_spellings(lines: list[str]) -> list[tuple[str, str]]:
  """`(name, S-constructor)` per arm of the port's `to_dtype_of` table, IN TABLE ORDER.

  The table IS the port's name-level declaration of upstream's spellings: upstream's
  `to_dtype` is `getattr(dtypes, name.lower())`, so every key here is a name upstream's
  `dtypes` answers to, and the table says which of them the port takes. The second half of
  each pair is the port's own `S.<name>()` constructor, and it is what lets the GROUPINGS
  below be read in upstream's names without this file inventing a mapping.
  """
  return re.findall(r'case "([^"]+)": Some\{S\.(\w+)\(\)\}',
                     _def_body("\n".join(lines), r"def to_dtype_of\("))


def _port_policy(text: str) -> dict[str, str]:
  """The port's own OMISSION DECLARATION: one `DTYPES-POLICY: <class>=<mode>` per class.

  READ BY PATH, NEXT TO THE REASON, because a declaration in a file the gate does not read
  is a declaration nobody checks.
  """
  out: dict[str, str] = {}
  for cls, mode in re.findall(r"^#\s*DTYPES-POLICY:\s*(\S+)\s*=\s*(\S+)\s*$", text, re.M):
    if cls in out:
      raise ValueError(f"{PORT} declares the class {cls!r} twice")
    out[cls] = mode
  return out


# --------------------------------------------------------------------------- the port's groupings

_TOKEN = re.compile(r"List\.append\(|\[|\]|\)|,|&2|[A-Za-z_][A-Za-z_0-9.]*(?:\(\))?")


def _tokens(body: str) -> list[str]:
  """The tokens of a grouping body. `List.append(` is matched BEFORE the identifier rule,
  or the `(` is left behind and the call never closes."""
  out, i = [], 0
  while i < len(body):
    m = _TOKEN.match(body, i)
    if m is None:
      if body[i].isspace():
        i += 1
        continue
      raise ValueError(f"cannot tokenise {body[i]!r} in {body!r}")
    out.append(m.group(0))
    i = m.end()
  return out


def _is_operand(tok: str) -> bool:
  """A grouping expression starts with a list opener, a `List.append(`, or a call.

  THE TYPE ARGUMENTS ARE NOT EXPRESSIONS. `List.append(&2, S.Dt, X, Y)` carries two of them
  and `&2` has no parentheses, so a reader that skips "the token with no `(`" SKIPS THE
  LIST LITERAL TOO -- and the literal is the one that holds the dtypes.  Measured: the
  first version of this file answered `dtypes.floats` with the LAST TWO of the four
  dtypes it spells, because the literal was skipped and its four elements were read as
  four separate arguments of which the last two were concatenated.
  """
  return tok == "[" or tok == "List.append(" or tok.endswith("()")


def _parse(toks: list[str], i: int, invert: dict[str, str], groups) -> tuple[list[str], int]:
  """One grouping expression -> the upstream names it spells, and the next token index.

  FOUR SHAPES, AND THE EVALUATOR READS THEM RATHER THAN GUESSING AT THEM: a literal list,
  `List.append` of two lists, another grouping, and one `S.<name>()`.
  """
  tok = toks[i]
  if tok == "[":
    names, i = [], i + 1
    while toks[i] != "]":
      if toks[i] == ",":
        i += 1
        continue
      sub, i = _parse(toks, i, invert, groups)
      names += sub
    return names, i + 1
  if tok == "List.append(":
    args, i = [], i + 1
    while toks[i] != ")":
      if toks[i] == ",":
        i += 1
        continue
      if not _is_operand(toks[i]):
        i += 1
        continue
      sub, i = _parse(toks, i, invert, groups)
      args.append(sub)
    if len(args) < 2:
      raise ValueError(f"`List.append` with {len(args)} list argument(s) in {toks}")
    return args[-2] + args[-1], i + 1
  if tok.startswith("dtypes."):
    return list(groups(tok[len("dtypes."):-2])), i + 1
  if tok.startswith("S."):
    ctor = tok[2:-2]
    if ctor not in invert:
      raise ValueError(f"{ctor!r} is not a dtype the port's own `to_dtype_of` table names")
    return [invert[ctor]], i + 1
  raise ValueError(f"unexpected token {tok!r}")


def _port_groupings(text: str, invert: dict[str, str]):
  """`<grouping>` -> the upstream names its body spells, IN ORDER.

  A closure, because the groupings compose: `dtypes.floats` is `dtypes.fp8s` plus four
  dtypes, so the evaluator follows the references. The `S.<name>()` spelling becomes
  upstream's name through the port's OWN `to_dtype_of` table -- anchored to upstream's
  CANONICAL class and not to the table's order, because the table carries the legacy
  aliases too and `S.half()` answers to both `f16` and `half`.

  THE TEXT IS THE COMMENT-STRIPPED ONE.  A grouping body is code, and a comment inside
  one is not code -- and the tokeniser has no comment, so a body carrying one is a body
  this gate cannot read.  MEASURED: the plant's CONTROL, a whole-line comment at column 0
  above a grouping body, made the gate RED with "cannot tokenise '#'" -- a gate that
  answers a COMMENT is a gate that reads prose.
  """
  bodies = {m.group(1): m.group(2) for m in
            re.finditer(r"^def dtypes\.(\w+)\(\) -> List<&2, S\.Dt>:\n(.*?)(?=\n\S|\Z)",
                        text, re.S | re.M)}
  memo: dict[str, list[str]] = {}
  busy: set[str] = set()

  def contents(name: str) -> list[str]:
    if name in memo:
      return memo[name]
    if name in busy:
      raise ValueError(f"the port's groupings are cyclic at {name!r}")
    if name not in bodies:
      raise ValueError(f"no `dtypes.{name}()` grouping in {PORT}")
    busy.add(name)
    toks = _tokens(bodies[name])
    names, _ = _parse(toks, 0, invert, contents)
    busy.discard(name)
    memo[name] = names
    return names

  return contents, set(bodies)


# --------------------------------------------------------------------------- upstream's own source


def _upstream_legacy(block: str) -> list[str]:
  """The names in upstream's `# legacy dtype aliases` block, ALL of them.

  THE SEMICOLONS, AND THIS IS THE SAME TRAP `gates/opseven-gate.py` documents for the
  `Ops` enum: upstream writes `float16 = half = f16; bfloat16 = bf16; ...` -- SEVERAL names
  on ONE line -- so a reader that takes one name per line takes a third of them. Every
  TARGET of every chained assignment is a name, so the LEFT of each `=` is split on `=`.
  """
  m = re.search(r"^\s*# legacy dtype aliases\n(.*?)(?=^\s*\n|^\s*@|^\s*def |^\s*\w+:)",
                block, re.S | re.M)
  if m is None:
    raise ValueError(f"no `# legacy dtype aliases` block in {UP_SRC}")
  names: list[str] = []
  for ln in m.group(1).splitlines():
    for part in ln.split("#")[0].split(";"):
      if "=" not in part:
        continue
      for nm in part.rsplit("=", 1)[0].split("="):
        if nm.strip():
          names.append(nm.strip())
  return names


def _upstream_classes(src: str) -> dict[str, list[str]]:
  """Upstream's `dtypes` names, in the three classes upstream's own source marks.

  `canonical` is upstream's `Final[DType]` block, `legacy-alias` is upstream's
  `# legacy dtype aliases` block, and `grouping` is the tuple-valued class attributes --
  the class-body assignments that are neither of the two blocks. `helper` is NOT here: it
  is the residual, and it is computed against the LIVE name set, so a name upstream adds
  lands in it by arithmetic and not by a list.
  """
  m = re.search(r"class DTypes:(.*?)\n(?=dtypes = DTypes\(\))", src, re.S)
  if m is None:
    raise ValueError(f"no `class DTypes:` block in {UP_SRC}")
  block = m.group(1)
  legacy = _upstream_legacy(block)
  return {
    "canonical": re.findall(r"^\s*(\w+):\s*Final\[DType\]", block, re.M),
    "legacy-alias": legacy,
    "grouping": [n for n, _ in re.findall(r"^  (\w+)\s*=\s*(.+)$", block, re.M)
                 if n not in set(legacy)],
  }


def _upstream_dtypes():
  """Upstream's own `dtypes` object -- LIVE, not a transcription of it."""
  from tinygrad import dtypes
  return dtypes


def _upstream_names(dtypes) -> list[str]:
  return sorted(n for n in dir(dtypes) if not n.startswith("__"))


def _upstream_grouping(dtypes, name: str) -> list[str]:
  """The upstream names a grouping holds, IN ORDER."""
  return [d.name for d in getattr(dtypes, name)]


# --------------------------------------------------------------------------- the readings


def _read():
  """Everything the checks read, gathered once.  Returns `(world, code, why)`.

  NOTHING IS EVALUATED HERE.  The port's groupings are read by `_check_grouping_contents`
  and a body this file cannot parse is a FINDING (FAIL) and not a DEAD: the subject is
  the port, and a port whose grouping body this gate cannot read is a port defect, not a
  gate that measured nothing.
  """
  try:
    text = PORT.read_text()
    src = UP_SRC.read_text()
  except OSError as exc:
    return None, REFUSED, f"a file the gate reads is absent: {exc}"
  try:
    dtypes = _upstream_dtypes()
  except Exception as exc:
    return None, DEAD, f"upstream's `dtypes` did not import: {type(exc).__name__}: {exc}"
  try:
    classes = _upstream_classes(src)
    stripped = _stripper().strip_comments(text)
    lines = _code_lines(text)
    spellings = _port_spellings(lines)
    policy = _port_policy(text)
    accessors = _port_accessors(lines)
  except ValueError as exc:
    return None, DEAD, f"the gate could not read a population: {exc}"
  names = _upstream_names(dtypes)
  helper = [n for n in names
            if n not in set(classes["canonical"]) | set(classes["legacy-alias"]) |
            set(classes["grouping"])]
  classes["helper"] = helper
  return {"port": {"text": stripped, "accessors": accessors, "spellings": spellings,
                   "policy": policy},
          "up": {"names": names, "classes": classes, "dtypes": dtypes}}, PASS, ""


def _invert(w) -> dict[str, str]:
  """`S.<ctor>()` -> upstream's canonical name, FROM THE PORT'S OWN TABLE.

  ANCHORED TO UPSTREAM'S CANONICAL CLASS, AND NOT TO THE TABLE'S ORDER.  The table
  carries the legacy aliases as well, so `S.half()` answers to `f16` AND to `half`, and
  an inversion built by "last one wins" would name the dtype `half` -- which is not a
  dtype at all, it is an alias for one.  So the arm of each CANONICAL name is the one
  that counts, and a canonical name the port's table does not carry has no constructor
  here.
  """
  arms = dict(w["port"]["spellings"])
  out: dict[str, str] = {}
  for name in w["up"]["classes"]["canonical"]:
    if name not in arms:
      continue
    ctor = arms[name]
    if ctor in out:
      raise ValueError(f"the port's table gives {name!r} and {out[ctor]!r} the same constructor "
                       f"{ctor!r}, so the port's constructors do not name the dtypes one for one")
    out[ctor] = name
  return out


# --------------------------------------------------------------------------- the checks


def _check_divergence(w) -> bool:
  """A name the port spells that upstream cannot. THE FIRST DIRECTION."""
  extra = sorted(set(w["port"]["accessors"]) - set(w["up"]["names"]))
  if extra:
    print(f"dtypeeven-gate: DIVERGENCE -- the port spells dtypes.{extra} and upstream's `dtypes` "
          f"has no such name. A def nothing calls is invisible to every check, and upstream's "
          f"namespace is the only one the port may spell.")
    return False
  return True


def _check_canonical(w) -> bool:
  """Every upstream canonical dtype has an accessor. THE PORT'S OWN RULE."""
  missing = [n for n in w["up"]["classes"]["canonical"] if n not in w["port"]["accessors"]]
  if missing:
    print(f"dtypeeven-gate: the port spells no accessor for the canonical dtype(s) {missing} -- a "
          f"canonical name the port cannot spell is a dtype the port cannot name.")
    return False
  return True


def _check_no_legacy(w) -> bool:
  """The port spells no accessor for a name in upstream's legacy alias block."""
  spelled = sorted(set(w["port"]["accessors"]) & set(w["up"]["classes"]["legacy-alias"]))
  if spelled:
    print(f"dtypeeven-gate: the port spells an accessor for the legacy alias(es) {spelled} -- "
          f"upstream keeps them only in a block it labels `# legacy dtype aliases`, and a def "
          f"nothing calls is invisible to every check.")
    return False
  return True


def _check_no_helper(w) -> bool:
  """The port spells no accessor for one of upstream's helper attributes."""
  spelled = sorted(set(w["port"]["accessors"]) & set(w["up"]["classes"]["helper"]))
  if spelled:
    print(f"dtypeeven-gate: the port spells an accessor for the helper attribute(s) {spelled} -- "
          f"they are predicates, properties and functions upstream, not dtypes.")
    return False
  return True


def _check_spellings(w) -> bool:
  """The port's `to_dtype` table against upstream's dtype-valued attribute names.

  BOTH DIRECTIONS, BY NAME.  This is where a DECLARED OMISSION THAT IS NO LONGER TRUE
  shows up: a name the port's table still accepts after upstream dropped it is a stale
  declaration, and a name upstream has that the port's table does not accept is a
  missing one.  The wanted set is upstream's `canonical` and `legacy-alias` classes --
  the two upstream marks itself -- and NOT everything `dtypes` answers to: upstream's two
  `default_*` properties answer a DType too, and they are helpers, not spellings.
  """
  want = set(w["up"]["classes"]["canonical"]) | set(w["up"]["classes"]["legacy-alias"])
  have = {name for name, _ in w["port"]["spellings"]}
  stale, gone = sorted(have - want), sorted(want - have)
  if stale or gone:
    if stale:
      print(f"dtypeeven-gate: the port's `to_dtype` still accepts {stale} and upstream's `dtypes` "
            f"does not spell them -- a declared omission that is no longer true is a stale "
            f"declaration, and a stale declaration is a lie the gate is asked to believe.")
    if gone:
      print(f"dtypeeven-gate: the port's `to_dtype` does not accept {gone} and upstream's `dtypes` "
            f"does spell them -- upstream's `to_dtype` is `getattr(dtypes, name.lower())`, so "
            f"every one of them is a name the port must take or decline.")
    return False
  return True


def _check_classes(w) -> bool:
  """The three classes upstream's own source marks are DISJOINT and NOT EMPTY.

  This is the "does the rule still describe upstream" check for the classes that are
  anchored to a block: if upstream stops marking a legacy alias block, or stops
  annotating its dtypes `Final[DType]`, or restructures its tuple attributes, the class
  this file reads comes back EMPTY -- and an empty class is a rule that stopped matching
  upstream, which is a lie the gate is asked to believe.
  """
  for cls in ("canonical", "legacy-alias", "grouping"):
    if not w["up"]["classes"][cls]:
      print(f"dtypeeven-gate: the class {cls!r} is EMPTY -- upstream's own source no longer "
            f"marks it, so the port's rule about it has stopped describing upstream.")
      return False
  seen: set[str] = set()
  for cls in ("canonical", "legacy-alias", "grouping"):
    members = set(w["up"]["classes"][cls])
    if seen & members:
      print(f"dtypeeven-gate: the class {cls!r} overlaps another at {sorted(seen & members)} -- "
            f"the classes must be DISJOINT or a name cannot be classified.")
      return False
    seen |= members
  return True


def _check_policy(w) -> bool:
  """The port's own DECLARATION, read by path, against the tree.

  Four things, each of which can fail: the declared classes must be exactly the classes
  upstream has (a class upstream no longer has is a stale declaration, and an UNDECLARED
  class is a name the port has no opinion about); the modes must be ones this gate knows;
  and the tree must SATISFY each declared mode -- `ALL` means the port spells every name
  of the class, `NONE` means it spells none, `PARTIAL` means it spells some and not all.
  """
  policy = w["port"]["policy"]
  unknown = sorted(set(policy) - set(CLASSES))
  if unknown:
    print(f"dtypeeven-gate: the port declares the class(es) {unknown} and this gate does not "
          f"know what they are -- a declaration the gate cannot read is not a declaration.")
    return False
  undeclared = sorted(set(CLASSES) - set(policy))
  if undeclared:
    print(f"dtypeeven-gate: the port declares no policy for the class(es) {undeclared} -- "
          f"upstream has them and the port has no opinion, which is how an omission becomes "
          f"an accident.")
    return False
  spelled = set(w["port"]["accessors"])
  for cls, mode in sorted(policy.items()):
    if mode not in MODES:
      print(f"dtypeeven-gate: the port declares {cls}={mode} and {mode} is not one of {MODES}.")
      return False
    members = set(w["up"]["classes"][cls])
    hit = members & spelled
    if mode == "ALL" and hit != members:
      print(f"dtypeeven-gate: the port declares {cls}=ALL and spells no accessor for "
            f"{sorted(members - hit)} -- the declaration and the tree disagree.")
      return False
    if mode == "NONE" and hit:
      print(f"dtypeeven-gate: the port declares {cls}=NONE and spells an accessor for "
            f"{sorted(hit)} -- the declaration and the tree disagree.")
      return False
    if mode == "PARTIAL" and not (hit and hit != members):
      print(f"dtypeeven-gate: the port declares {cls}=PARTIAL and spells {len(hit)} of "
            f"{len(members)} -- the declaration and the tree disagree.")
      return False
  return True


def _check_grouping_contents(w) -> bool:
  """Every grouping the port spells holds upstream's dtypes, IN ORDER.

  The port's grouping bodies are read and EVALUATED, not pattern-matched: `dtypes.floats`
  is `dtypes.fp8s` plus four dtypes, and the answer has to be the sixteen upstream holds.
  A body this gate cannot read is a FINDING and not a crash.
  """
  try:
    invert = _invert(w)
    groups, names = _port_groupings(w["port"]["text"], invert)
    spelled = {n: groups(n) for n in sorted(names)}
  except ValueError as exc:
    print(f"dtypeeven-gate: the port's grouping bodies could not be read: {exc}")
    return False
  w["port"]["groupings"] = spelled
  for name, port_names in sorted(spelled.items()):
    if name not in w["up"]["classes"]["grouping"]:
      print(f"dtypeeven-gate: the port spells the grouping `dtypes.{name}` and upstream's "
            f"`dtypes` has no such tuple-valued attribute.")
      return False
    up_names = _upstream_grouping(w["up"]["dtypes"], name)
    if port_names != up_names:
      print(f"dtypeeven-gate: the port's `dtypes.{name}` holds {port_names} and upstream's holds "
            f"{up_names}.")
      return False
  return True


def _check_omitted_groupings(w) -> bool:
  """Every grouping the port does NOT spell is EXPLAINED, and the explanation is a rule.

  A grouping the port omits is either CONTAINED -- every dtype it holds is in a grouping
  the port spells -- or OUTSIDE `all` -- the port's `all` IS upstream's `all`, and it does
  not reach it.  An omission with neither is an accident wearing the port's rule, and it
  is RED.
  """
  spelled = w["port"].get("groupings", {})
  if not spelled:
    return True
  covered = [set(names) for names in spelled.values()]
  up_all = set(_upstream_grouping(w["up"]["dtypes"], "all")) \
    if "all" in w["up"]["classes"]["grouping"] else set()
  unexplained = []
  for name in w["up"]["classes"]["grouping"]:
    if name in spelled:
      continue
    members = set(_upstream_grouping(w["up"]["dtypes"], name))
    if any(members <= c for c in covered):
      continue
    if members and not (members <= up_all):
      continue
    unexplained.append(name)
  if unexplained:
    print(f"dtypeeven-gate: the port omits the grouping(s) {unexplained} and neither "
          f"explanation holds -- their dtypes are in no grouping the port spells, and they are "
          f"not outside upstream's `all` either, so the omission is an accident and not a "
          f"declaration.")
    return False
  return True


# --------------------------------------------------------------------------- the run


def _census(w) -> None:
  """The measured shape of both sides, printed so the numbers live in the output."""
  up = w["up"]
  port = w["port"]
  print(f"dtypeeven-gate: census -- port accessors={len(port['accessors'])} "
        f"port spellings={len(port['spellings'])} port groupings={len(port.get('groupings', {}))} | "
        f"upstream names={len(up['names'])} "
        + " ".join(f"{c}={len(up['classes'][c])}" for c in CLASSES))


def _check_vendored_is_upstream(w) -> bool:
  """The vendored `tinygrad/dtype.py` must be upstream's OWN bytes.

  This gate reads upstream's names from the vendored tree and upstream's classes from the
  same file, so the two agree BY CONSTRUCTION -- which means the gate measures upstream
  only as far as the vendored tree IS upstream.  `gates/pinned-tree-gate.py` holds the
  tree's identity as a whole; this is the narrow check this gate needs.  It REFUSES and
  does not FAIL: a drifted vendor is an untrustworthy ORACLE, not a defect in the port,
  and a gate that calls an untrustworthy oracle a defect is a gate that lies about which
  side is wrong.  An absent `upstream` ref is not a drift -- the vendored tree is then the
  tree's own upstream and the check says so.
  """
  rel = "tinygrad/dtype.py"
  try:
    p = subprocess.run(["git", "--no-optional-locks", "show", f"upstream:{rel}"],
                       cwd=REAL_ROOT, capture_output=True, text=True)
  except OSError as exc:
    print(f"dtypeeven-gate: the `upstream` ref could not be read: {exc}")
    return False
  if p.returncode != 0:
    print(f"dtypeeven-gate: UPSTREAM-REF-ABSENT -- there is no `upstream` ref in this tree, so "
          f"the vendored {rel} is read as the upstream it is.")
    return True
  if p.stdout.encode() != UP_SRC.read_bytes():
    print(f"dtypeeven-gate: REFUSED -- the vendored {rel} is not upstream's bytes at "
          f"`upstream:{rel}`, so the names this gate reads are not upstream's names.")
    return False
  return True


def main() -> int:
  world, code, why = _read()
  if world is None:
    print(f"dtypeeven-gate: {VERDICT[code]} -- {why}", file=sys.stderr)
    return code
  checks = (_check_vendored_is_upstream, _check_divergence, _check_canonical,
            _check_no_legacy, _check_no_helper, _check_spellings, _check_classes,
            _check_policy, _check_grouping_contents, _check_omitted_groupings)
  bad = []
  for check in checks:
    if not check(world):
      bad.append(check.__name__)
  _census(world)
  if bad:
    print(f"dtypeeven-gate: FAIL -- {bad}")
    return FAIL
  print("dtypeeven-gate: PASS -- the port spells no name upstream's `dtypes` cannot spell, every "
        "name upstream spells that the port does not falls in a class the port declared, the "
        "declared classes still describe upstream, and every grouping the port spells holds "
        "upstream's dtypes in order.")
  return PASS


if __name__ == "__main__":
  sys.exit(main())
