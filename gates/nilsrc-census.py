#!/usr/bin/env python3
"""nilsrc-census.py -- ONE ROW FOR EVERY `UOp` SITE WHOSE `src` IS EMPTY, AND A CLASS.

    .venv/bin/python gates/nilsrc-census.py            # the census + the diff against pins
    .venv/bin/python gates/nilsrc-census.py --rows     # rows only
    .venv/bin/python gates/nilsrc-census.py --plant    # the census made to MOVE, and moved

NO `bend`. THE CENSUS READS SOURCE, IT DOES NOT RUN THE PORT, so there is no lane to time out,
no 1.4 GB process to collide with, and nothing to wait for before reading an artefact.

## THE POPULATION, AND WHICH OF THE THREE KINDS IT IS

`AGENTS.md`'s DOCTRINE 1: a population is (a) a GENERATOR'S OWN DECLARATION LOADED BY PATH,
(b) a DIRECTORY WALK, or (c) a REGEX OVER THE TREE'S OWN WRITE SITES. IT IS **(b) AND (c)**,
and never (a)-by-hand:

  (b) `os.walk(ROOT)` -- the WHOLE repository, `.bend` by `endswith`, NOT `glob` (MEASURED in
      `AGENTS.md`: `glob('*.bend')` returns `[]` with `.bend` files on disk), intersected with
      `git ls-tree -r HEAD` and NEVER `git ls-files`, because `jj` colocation keeps git's index
      ARMED and `git ls-files` would then report the working copy as staged.
      The whole repository, not a root tuple. The 207 this file was asked for is
      `.agents/slop/sizetosrc/census.py`'s `DEFAULT_ROOTS`, a FIVE-NAME HAND LIST, and a hand
      list is precisely what DOCTRINE 1 records `gates/gates-pop.py:95 HOMES` and `AGENTS.md`
      itself getting wrong. A walk finds one more.
  (c) `thread_src.calls` -- the tree's own `UOp.new(` write sites, with `thread_src.KIND` for
      the BUFFER/ALLOC/PARAM op test and `thread_src.APARAM` for the `Arg` shape. IMPORTED BY
      PATH, never re-derived: `thread_src.py`'s own header says the splitter is the contract,
      and two copies of a split rule is a second contract with no generator.

## THE CLASS IS AN UPSTREAM FACT, AND IT IS READ FROM THE CPYTHON LANE

`72f98ffe0` ("move size from ParamArg to src") put a PARAM/BUFFER/ALLOC's element count in
`src[0]`, so `src == Nil{}` at such a site means the size node is ABSENT. That is a
(B) -- a sized buffer/alloc that LOST its size -- UNLESS the upstream shape was `()`, in which
case it is (A) and the empty src is the honest rendering. WHICH IS WHICH IS NOT DECIDED BY
LOOKING AT THE PORT. It is decided here from `tinygrad/`, and every row carries the lane fact
it was decided by:

  WRITERS   a regex over the CPython lane's OWN `src=` write sites for these three ops.
            `py_writers()` walks `tinygrad/**/*.py`; the count is printed, not assumed.
  FIELDS    the `ParamArg` field NAMES come from `ParamArg`'s own class-body annotations in
            `tinygrad/uop/ops.py`, and for the PRE-migration arity from the newest revision
            on that path whose annotations still carry `size`, found by walking `git log`
            (NOT transcribed). `size` sat at index 2 there, so a 13-field record's third value
            is the size and a 12-field record's third value is `vmin_vmax`.
  SHAPE     EXECUTED in a subprocess against the installed CPython lane, never transcribed:
            `shape_to_shape_arg(())`, `UOp.variable(...)`, `UOp._buffer(...)`, `UOp.alloc(...)`.
  VARIABLE  `UOp.is_variable`'s own source, read out of `tinygrad/uop/ops.py` at run time.
            It is `op is PARAM and vmin_vmax is not None and addrspace is ALU and
            _shape == ()`, so for a site whose `src` is empty the `vmin_vmax` and `addrspace`
            conjuncts decide it, and those are two values of the site's own `ParamArg`.

## WHAT THIS GATE CANNOT SEE, AND SAYS SO ON EVERY RELEVANT ROW

`ops.py:1222` spells a PARAM's shape `(prod(to_max_shape(shape)),) if shape else ()`, so a
PARAM that is not a variable is `()` exactly when its fixture passed an empty `shape`. THE
VENDORED LANE CANNOT ANSWER THAT: `tinygrad/test/` IS NOT VENDORED (MEASURED, and re-measured
by this gate on every run), so there is no upstream fixture here to read a `shape` off. Those
rows are class B on the WRITER, with `proof=writer` and `unproven=fixture-shape`, and the
count is printed. A row that hides that is a row that renders an unproven answer as a measured
one, which is the whole failure shape this project keeps meeting.

## THE RUNNING NUMBERS, AND THEY ARE A READING NOT A PROMISE

208 sites · A=21 · B=187 · 0 unclassified. 154 of the 208 are under `.agents/slop/` and only
43 are in `tinybendygrad/`. 163 of the 208 sit on the PRE-migration 13-field `ParamArg`, where
the size is still written down in the record -- which is why most of them are class B on the
STRONGEST possible evidence (`proof=record-size`) rather than on an inference.

## AND AN EXISTING GATE ALREADY SAW 38 OF THESE 43

`gates/arenasrc_census.py` has a `nil-src` class over `tinybendygrad/`, and its own header says
these nodes "simply HAVE NO SIZE" and that `nil-src` and `param_src` "both print `size=N`, and
the acceptance rows cannot tell them apart". MEASURED here: its 38 live rows are exactly these
43 minus 5, and 31 of them are class B. So a gate has been printing rows for 31 lost sizes and
nothing in those rows says so. The 5 it misses are `uop/ops.bend:6302/6303/8352` (the op is
spelled `OpsPARAM{}`, without the `O.` its class test requires) and `codegen/__init__.bend:339,
345` (the `Arg` is `ABad{}`, which fails its `"AParam" in args[3]` test).

## THE FIVE VERDICTS ARE `gatekit`'s AND NOT LOCAL CONSTANTS

`gates/README.md`: gatekit holds the plumbing and "nothing else", and `AGENTS.md` records two
instruments that invented a second vocabulary for an exit code. So `PASS/FAIL/REFUSED/SKIP/DEAD`
are IMPORTED, and `?` -- a site whose `ParamArg` could not be resolved -- is a FAIL and not a
silent skip. A census that prints only the defects is a list of suspects, so there is a row
per site and the acceptance test is `rows == sites`.
"""
from __future__ import annotations

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "gates"))
from gatekit import ART, PASS, FAIL, REFUSED, DEAD  # noqa: E402

sys.path.insert(0, str(ROOT / ".agents" / "slop" / "sizetosrc"))
import thread_src as ts  # noqa: E402
import census as cs  # noqa: E402

PINS = HERE / "nilsrc-census.rows"
NAME = "nilsrc-census"
OPSDIR = ROOT / "tinygrad"
ANNOT = re.compile(r"^  ([a-z_][a-z0-9_]*)\s*:", re.M)
WRITER = re.compile(r"UOp\(\s*Ops\.(BUFFER|ALLOC|PARAM)\b")
DEFBY = re.compile(r"^def ([A-Za-z_][\w.]*)\(", re.M)


class Refused(Exception):
  """A precondition this gate will not guess past. NEVER a silent skip."""


# ---------------------------------------------------------------- the CPython lane


def paramarg_fields(src: str, where: str) -> list[str]:
  """`ParamArg`'s own field order, from its class-body annotations.

  NOT a hand list and NOT `inspect.signature`: the record is a dataclass-shaped class whose
  `__init__` is generated, and the annotations are the declaration both lanes can read.
  """
  m = re.search(r"^class ParamArg:\n((?:.|\n)*?)(?=\n\nclass |\n\n@|\Z)", src, re.M)
  if not m:
    raise Refused(f"{where}: no `class ParamArg`")
  names = ANNOT.findall(m.group(1))
  if not names:
    raise Refused(f"{where}: `class ParamArg` has no annotations")
  return names


def premigration_fields() -> tuple[str, list[str]]:
  """`ParamArg`'s field order from the newest revision that still had `size`.

  DISCOVERED by walking `git log upstream -- tinygrad/uop/ops.py` and taking the first
  revision whose annotations contain `size`. Transcribing `72f98ffe0` here would be a
  citation; this is a measurement, and it survives the lane being re-vendored.
  """
  revs = subprocess.run(["git", "log", "--format=%H", "upstream", "--", "tinygrad/uop/ops.py"],
                        cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
  for rev in revs:
    src = subprocess.run(["git", "show", f"{rev}:tinygrad/uop/ops.py"],
                         cwd=ROOT, capture_output=True, text=True).stdout
    m = re.search(r"^class ParamArg:\n((?:.|\n)*?)(?=\n\nclass |\n\n@|\Z)", src, re.M)
    if m and "size" in ANNOT.findall(m.group(1)):
      return rev, ANNOT.findall(m.group(1))
  raise Refused("no revision on tinygrad/uop/ops.py carries a `size` ParamArg field")


def py_writers() -> list[tuple[str, int, str, str]]:
  """(file, line, op, text) for every `UOp(Ops.BUFFER|ALLOC|PARAM` in the CPython lane."""
  if not OPSDIR.is_dir():
    raise Refused("tinygrad/ is absent -- the lane this census reads does not exist here")
  rows = []
  for dp, dn, fn in os.walk(OPSDIR):
    dn[:] = sorted(d for d in dn if d != "__pycache__")
    for f in sorted(fn):
      if not f.endswith(".py"):
        continue
      p = pathlib.Path(dp) / f
      rel = str(p.relative_to(ROOT))
      for i, ln in enumerate(p.read_text().splitlines(), 1):
        m = WRITER.search(ln)
        if m:
          rows.append((rel, i, m.group(1), ln.strip()))
  if not rows:
    raise Refused("the CPython lane has no Ops.BUFFER|ALLOC|PARAM construction to read")
  return rows


def is_variable_src() -> tuple[str, int, str]:
  src = (OPSDIR / "uop" / "ops.py").read_text()
  m = re.search(r"^  def is_variable\(.*?(?=\n  @|\n  def |\nclass )", src, re.M | re.S)
  if not m:
    raise Refused("tinygrad/uop/ops.py has no `is_variable`")
  return "tinygrad/uop/ops.py", src[:m.start()].count("\n") + 1, " ".join(m.group(0).split())


PROBE = r"""
import json
from tinygrad.uop.ops import UOp, Ops, shape_to_shape_arg
from tinygrad.dtype import dtypes
dev = __import__("tinygrad").device
out = {}
s0 = shape_to_shape_arg(())
out["empty"] = [str(s0.op), len(s0.src), list(s0.as_shape)]
s1 = shape_to_shape_arg((4,))
out["one"] = [str(s1.op), len(s1.src), list(s1.as_shape)]
v = UOp.variable("i", 0, 10)
out["variable"] = [str(v.op), len(v.src), list(v._shape), v.is_variable]
b = UOp._buffer(4, dtypes.int32, dev)
out["buffer"] = [str(b.op), len(b.src), list(b._shape)]
a = UOp.alloc((0,), dtypes.int32, dev)
out["alloc"] = [str(a.op), len(a.src), list(a._shape)]
print(json.dumps(out))
"""


def py_facts() -> dict:
  """The shapes, EXECUTED against the installed lane. Never transcribed."""
  r = subprocess.run([str(ROOT / ".venv/bin/python"), "-c", PROBE],
                     cwd=ROOT, capture_output=True, text=True)
  if r.returncode != 0 or not r.stdout.strip():
    raise Refused(f"the CPython-lane probe did not run: {r.stderr.strip()[:160]}")
  import json
  return json.loads(r.stdout)


def test_dir_present() -> bool:
  return (OPSDIR / "test").is_dir()


# ---------------------------------------------------------------- the port's sites


def tracked() -> set[str]:
  """`git ls-tree -r HEAD`. NEVER `git ls-files`: the index is ARMED (`jj` colocation)."""
  return {ln for ln in subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD"],
                                      cwd=ROOT, capture_output=True, text=True,
                                      check=True).stdout.split("\n") if ln}


def bend_files(owned: set[str], root: pathlib.Path | None = None) -> list[pathlib.Path]:
  """(b) THE DIRECTORY WALK. `root` overrides the tree root so `--plant` can census a copy."""
  base = root or ROOT
  out = []
  for dp, dn, fn in os.walk(base):
    dn[:] = sorted(d for d in dn if d not in cs.SKIP)
    for f in sorted(fn):
      if not f.endswith(".bend"):
        continue
      p = pathlib.Path(dp) / f
      if str(p.relative_to(base)) in owned:
        out.append(p)
  return out


def sites(owned: set[str], root: pathlib.Path | None = None) -> list[dict]:
  """Every BUFFER/ALLOC/PARAM node construction whose `src` is the empty list.

  (b) the walk and (c) `thread_src.calls`. `root` overrides the tree root so `--plant` can
  census a temp copy of the repository WITHOUT the port itself being writable.
  """
  base = root or ROOT
  out = []
  for p in bend_files(owned, base):
    s = p.read_text()
    for start, _end, args in ts.calls(s, p):
      if len(args) != 5 or not ts.KIND.match(args[1]):
        continue
      if args[2].strip() != "Nil{}":
        continue
      out.append({"file": str(p.relative_to(base)),
                  "line": s[:start].count("\n") + 1,
                  "op": ts.KIND.match(args[1]).group(2),
                  "arg": args[3].strip()})
  return out


class Defs:
  """`def` name -> the `(file, body)` of every def with that name, over the WHOLE tree.

  A DIRECTORY WALK over the tracked `.bend` files, so a helper used in `gates/wk-eval.bend`
  and defined in `tinybendygrad/uop/fold.bend` resolves -- `F.mw_pa` IS `def mw_pa(`, in
  another file, and a same-file-only index calls a defined helper undefined. The LOOKUP is
  same-file first and tree-wide second, and a name with more than one tree-wide def is a
  `?` rather than a coin flip: `g_buf` is a 12-field record in `uop/fold.bend` and a
  13-field one in the `.agents/slop/strays/` archives, and the two classify DIFFERENTLY.
  """

  def __init__(self, owned: set[str], root: pathlib.Path | None = None):
    base = root or ROOT
    self.by_name: dict[str, list[tuple[str, str]]] = {}
    for p in bend_files(owned, base):
      s = p.read_text()
      rel = str(p.relative_to(base))
      for m in re.finditer(r"^def ([A-Za-z_][\w]*(?:\.[\w]+)*)\(", s, re.M):
        st = m.start()
        nxt = re.search(r"\n(?=def )", s[st + 1:])
        self.by_name.setdefault(m.group(1), []).append(
          (rel, s[st: st + 1 + (nxt.start() if nxt else len(s))]))

  def get(self, name: str, same_file: str) -> list[tuple[str, str]]:
    """Same-file defs first; otherwise every tree-wide def with this name.

    A LIST, because a name with several tree-wide defs is a real ambiguity -- `g_buf` is a
    12-field record in `uop/fold.bend` and a 13-field one in the `.agents/slop/strays/`
    archives and the two classify DIFFERENTLY -- and the caller resolves all of them and
    accepts only an agreement. A coin flip would be a guess with a census's authority.
    """
    cands = self.by_name.get(name, [])
    local = [c for c in cands if c[0] == same_file]
    if local:
      return local
    return list(cands)


def _params(body: str) -> list[str]:
  lp, d = body.index("("), 0
  for rp in range(lp, len(body)):
    if body[rp] == "(":
      d += 1
    elif body[rp] == ")":
      d -= 1
      if d == 0:
        return [a.split(":")[0].strip().lstrip("+")
                for a in ts.split_top(body[lp + 1:rp]) if a.strip()]
  return []


def _record(body: str) -> list[str] | None:
  """The `ParamArg` record a helper BUILDS -- a construction, not a `case` pattern.

  `UOp.variable.pa.of` has both: a `case ParamArg{...}` destructuring and a `ParamArg{...}`
  construction, and they have the same arity and different meanings, so taking the first
  match reads a match binder as a value. The `case` guard is the whole difference.
  """
  for m in re.finditer(r"(?<!case )ParamArg\{", body):
    _e, inner = cs.span(body, m.end() - 1)
    return ts.split_top(re.sub(r"#[^\n]*", "", inner))
  return None


def _bind(v: str, sub: dict[str, str]) -> str:
  v = v.strip()
  inner = re.fullmatch(r"(?:Some|Nil)\{(.*)\}", v)
  if inner and inner.group(1).strip() in sub:
    return f"{v[:v.index('{')]}{{{sub[inner.group(1).strip()]}}}"
  return sub.get(v, v)


def _call(text: str, at: int = 0) -> tuple[str, list[str]] | None:
  m = re.search(r"\b([A-Za-z_][\w]*(?:\.\w+)*)\(", text[at:])
  if not m:
    return None
  name, lp = m.group(1), at + m.end() - 1
  d = 0
  for rp in range(lp, len(text)):
    if text[rp] == "(":
      d += 1
    elif text[rp] == ")":
      d -= 1
      if d == 0:
        return name, [a.strip() for a in ts.split_top(text[lp + 1:rp]) if a.strip()]
  return name, []


def resolve_helper(defs: Defs, helper: str, args: list[str], same_file: str,
                   depth: int = 0) -> tuple[list[str] | None, str]:
  """`helper(args)` -> the `ParamArg` field values, following the helper's own forwarding.

  THE ARGUMENTS TRAVEL WITH THE LOOKUP. `dcp` is `def dcp(dt, mult, nm): dcp.range(dt, mult,
  nm, 0, 100)` and `dm_param` is the same shape, so resolving the forwarded def WITHOUT
  binding the outer's arguments first compares 3 call arguments against 5 parameters and
  refuses a helper that is right there in the file.

  THE NAME LOSES ITS LAST COMPONENT BEFORE IT LOSES ITS FIRST. `tn_as_param.of` is not a def
  and `tn_as_param` is, and `O.ParamArg.of` is `def ParamArg.of` in another file -- the
  port namespaces a call it does not define.
  """
  if depth > 8:
    return None, f"forward-depth>{depth}:{helper}"
  # THE PORT NAMESPACES CALLS IT DOES NOT DEFINE: `c2d_pa` is `O.ParamArg.of(slot, dtype)`
  # and `def ParamArg.of` lives in `uop/ops.bend`. A leading `O.`/`F.` is a MODULE qualifier
  # on the call, not part of the def's name, so it comes off before the lookup.
  if re.match(r"^[A-Z]\.", helper):
    helper = helper[2:]
  names = [n for n in (helper, *helper.split(".")[:-1], helper.split(".")[-1]) if n]
  got, seen = [], []
  for n in names:
    got = [g for g in defs.get(n, same_file) if g not in seen]
    if got:
      seen += got
      break
  if not got:
    return None, f"no-def-for:{helper}"
  answers = []
  for rel, body in got:
    sub = dict(zip(_params(body), args))
    rec = _record(body)
    if rec is not None:
      answers.append(([_bind(f, sub) for f in rec], f"{rel}:{body.split('(')[0][4:]}"))
      continue
    fwd = _call(body, body.index("(") + 1)
    answers.append(resolve_helper(defs, fwd[0], [_bind(a, sub) for a in fwd[1]], rel, depth + 1)
                   if fwd else (None, f"no-record-in:{rel}"))
  # A FORWARD THAT ITSELF FORWARDED answers with a LIST; splice it so a candidate is always
  # one `(fields, how)` pair and `how` is always a string.
  flat: list = []
  for a in answers:
    flat.extend(a[1] if isinstance(a[1], list) else [a])
  answers = flat
  return answers[0] if len(answers) == 1 else (None, answers)


APARMW = re.compile(r"^\s*(?:[A-Z]\.)?AParam\{")


def resolve_arg(defs: Defs, rel: str, arg: str) -> tuple[list, bool]:
  """(`ParamArg` field values per CANDIDATE def, and whether the Arg is a ParamArg at all).

  CANDIDATES, NOT ONE ANSWER. A name may be defined in three files and the three records may
  disagree -- `mw_pa` is a 12-field record in `uop/fold.bend` and a 13-field one in the
  `.agents/slop/strays/` archives -- so every def is resolved and the caller requires the
  CLASSES to agree. They need not: `g_buf` classifies A on one spelling and B on the other.
  Agreement on the class is what decides a row; disagreement is a `?`.

  THE SECOND RETURN IS A CLASS, NOT A DETAIL. CPython's `is_variable` reads `self.arg.
  vmin_vmax`, and an `Arg` that is not a `ParamArg` (this port's `ABad{}`) cannot answer it
  -- which decides the class as firmly as reading it could.
  """
  arg = " ".join(arg.split())
  if not APARMW.match(arg):
    return [(None, "arg-not-AParam")], False
  _e, payload = cs.span(arg, arg.index("{"))
  payload = payload.strip()
  for lead in ("O.", "F."):
    if payload.startswith(lead):
      payload = payload[len(lead):]
  if payload.startswith("ParamArg{"):
    _e2, inner = cs.span(payload, payload.index("{"))
    return [(ts.split_top(re.sub(r"#[^\n]*", "", inner)), f"{rel}:inline-ParamArg")], True
  call = _call(payload)
  if call is None:
    return [((None, "arg-not-a-call"),)], False
  helper, call_args = call
  got = resolve_helper(defs, helper, call_args, rel)
  if got[1] is None or not isinstance(got[1], list):
    return [got], True
  return got[1], True


def norm(v: str) -> str:
  return "_".join(v.split())


def classify(site: dict, defs: Defs, names: dict[int, list[str]],
             writers: dict[str, tuple[str, int, str]], facts: dict,
             has_tests: bool) -> dict:
  """The class, and the CPython-lane fact it was decided by.

  EVERY CANDIDATE DEF IS CLASSIFIED AND THE CLASSES MUST AGREE. A record that disagrees with
  itself about the answer is a `?`, and a `?` is a FAIL here -- a census that quietly took the
  first candidate would be a census whose authority is the order of a directory walk.
  """
  cands, is_pa = resolve_arg(defs, site["file"], site["arg"])
  out = [_one(site, f, how, is_pa, names, writers, facts, has_tests) for f, how in cands]
  if len({r["class"] for r in out}) != 1:
    return {**site, "class": "?", "shape": "?", "writer": "?", "how": "; ".join(
      r["how"] for r in out), "proof": f"{len(out)}-defs-disagree:"
               + ",".join(sorted(r["class"] for r in out))}
  first = dict(out[0])
  first["how"] = "; ".join(r["how"] for r in out)
  first["proof"] = out[0]["proof"] + (f"(+{len(out) - 1}-agreeing-defs)"
                                      if len(out) > 1 else "")
  return first


def _one(site: dict, fields: list[str] | None, how: str, is_pa: bool,
         names: dict[int, list[str]], writers: dict[str, tuple[str, int, str]],
         facts: dict, has_tests: bool) -> dict:
  w = writers.get(site["op"])
  wref = f"{w[0]}:{w[1]}" if w else "?"
  if site["op"] == "PARAM" and not is_pa:
    fac = facts.get("param", ["?", "?", "?"])
    return {**site, "class": "B", "proof": "is_variable:arg-is-not-a-ParamArg",
            "shape": f"is_variable-reads-arg.vmin_vmax;src0={fac[0]}/as_shape={fac[2]}",
            "writer": wref, "how": how, "unproven": "" if has_tests else "fixture-shape"}
  if fields is None:
    if site["op"] in ("BUFFER", "ALLOC"):
      # THE OP DECIDES AND THE ARG DOES NOT CARRY THE SHAPE. `UOp._buffer` and `UOp.alloc`
      # both take the size as a SEPARATE argument (`ops.py:829`, `ops.py:1187`), so an
      # unreadable `Arg` -- this port's `ABad{}` -- leaves the class untouched. Saying `?`
      # here would be refusing a question the writer already answered.
      fac = facts.get(site["op"].lower(), ["?", "?", "?"])
      return {**site, "class": "B", "proof": f"writer(arg-unreadable:{how})",
              "shape": f"src0={fac[0]}/nsrc={fac[1]}/as_shape={fac[2]}",
              "writer": wref, "how": how, "unproven": ""}
    return {**site, "class": "?", "proof": how, "shape": "?", "writer": "?", "how": how}
  order = names.get(len(fields))
  if order is None:
    return {**site, "class": "?", "proof": f"arity-{len(fields)}-is-not-a-ParamArg-arity",
            "shape": "?", "writer": "?", "how": how}
  f = dict(zip(order, (norm(x) for x in fields)))

  # `size` IN THE RECORD is the strongest evidence there is: the shape is written down.
  if "size" in f:
    empty = f["size"] in ("None{}", "None")
    return {**site, "class": "A" if empty else "B", "proof": "record-size",
            "shape": "()" if empty else f"size={f['size']}",
            "writer": f"pre-migration-ParamArg.size@{len(fields)}-field;" + wref,
            "how": how, "vmin_vmax": f["vmin_vmax"], "addrspace": f["addrspace"],
            "unproven": ""}

  # No `size` in the record: the shape can only have come from `src[0]`, and it did not.
  # The op picks the writer, and the writer is what decides.
  if site["op"] == "PARAM":
    is_var = f["vmin_vmax"].startswith("Some{") and f["addrspace"] == "S.Aalu{}"
    key = "variable" if is_var else "param"
  else:
    key = site["op"].lower()
  fac = facts.get(key, ["?", "?", "?"])
  is_a = (key == "variable") or fac[2] == "[]"
  unproven = ""
  if site["op"] == "PARAM" and key == "param" and not has_tests:
    unproven = "fixture-shape"
  return {**site, "class": "A" if is_a else "B",
          "proof": "is_variable" if key == "variable" else "writer",
          "shape": f"src0={fac[0]}/nsrc={fac[1]}/as_shape={fac[2]}",
          "writer": (f"{writers['VAR'][0]}:{writers['VAR'][1]}" if key == "variable"
                     else wref),
          "how": how, "unproven": unproven,
          "vmin_vmax": f["vmin_vmax"], "addrspace": f["addrspace"]}


def census(owned: set[str], root: pathlib.Path | None = None) -> list[dict]:
  live = paramarg_fields((OPSDIR / "uop" / "ops.py").read_text(), "tinygrad/uop/ops.py")
  rev, pre = premigration_fields()
  names = {12: live[:12], 13: pre[:13]}
  allw = py_writers()
  # ONE WRITER PER OP, CHOSEN BY THE SHAPE EXPRESSION IT PASSES -- and the second rule is
  # `variable`, the one writer that writes a src-less STACK instead of calling
  # `shape_to_shape_arg`. Both are picked off the discovered list, so a re-vendored lane
  # moves the row rather than invalidating it.
  writers: dict[str, tuple[str, int, str]] = {}
  for f, ln, op, tx in allw:
    # `src=` MATTERS: `tinygrad/renderer/isa/x86.py` builds a BUFFER with NO `src=` at all, so
    # a walk that took the FIRST writer per op would cite a spill slot that never had a size
    # node as the authority for every BUFFER row. The writer that WRITES `src[0]` is the one
    # a `Nil{}` src is a statement about.
    if "src=" in tx and "shape_to_shape_arg" in tx and op not in writers:
      writers[op] = (f, ln, tx)
  for f, ln, op, tx in allw:
    if "src=" in tx and "Ops.STACK" in tx and "shape_to_shape_arg" not in tx:
      writers.setdefault("VAR", (f, ln, tx))
  facts = py_facts()
  has_tests = test_dir_present()
  base = root or ROOT
  defs = Defs(owned, base)
  return [classify(s, defs, names, writers, facts, has_tests)
          for s in sites(owned, base)]


# ---------------------------------------------------------------- rows


def row(r: dict) -> str:
  parts = [f"file={r['file']}", f"line={r['line']}", f"op={r['op']}",
           f"class={r['class']}", f"proof={r['proof']}",
           f"shape={norm(str(r['shape']))}", f"writer={r['writer']}",
           f"src={r['how']}"]
  if r.get("vmin_vmax"):
    parts += [f"vmin_vmax={r['vmin_vmax']}", f"addrspace={r['addrspace']}"]
  if r.get("unproven"):
    parts.append(f"unproven={r['unproven']}")
  return "site " + " ".join(parts)


def report(r: dict, writers: list, names: dict, facts: dict, rev: str, has_tests: bool) -> None:
  print("population   : (b) os.walk(ROOT) *.bend  AND  (c) thread_src.calls -> UOp.new( write sites")
  print("             : src == Nil{} and op in (BUFFER, ALLOC, PARAM)")
  print(f"cpython lane : {OPSDIR.relative_to(ROOT)}  writers={len(writers)}  "
        f"tinygrad/test present={has_tests}")
  for f, ln, op, tx in writers:
    print(f"  writer {op:<6} {f}:{ln}  {norm(tx)[:96]}")
  nosrc = [(f, ln, op) for f, ln, op, tx in writers if "src=" not in tx]
  for f, ln, op in nosrc:
    port = ROOT / (f.replace("tinygrad/", "tinybendygrad/").replace(".py", ".bend"))
    hit = "present" if port.exists() and "Ops%s{" % op.capitalize() in port.read_text() \
        else "NOT PORTED"
    print(f"  writer {op:<6} {f}:{ln}  writes NO src=  -> {port.relative_to(ROOT)}: {hit}")
  print(f"  ParamArg fields  arity-12 <- live {names[12][:4]}...   "
        f"arity-13 <- {rev[:10]} {names[13][:4]}...")
  for k, v in facts.items():
    print(f"  executed {k:<9} {v}")
  where, ln, src = is_variable_src()
  print(f"  is_variable {where}:{ln}  {src[:150]}")
  print("classes      : " + "  ".join(f"{k}={v}" for k, v in
                                       sorted(Counter(x["class"] for x in r).items())))


def diff(pins: list[str], rows: list[str]) -> list[str]:
  if not pins:
    return ["no baseline: gates/nilsrc-census.rows is absent or empty"]
  base = {ln.split()[1]: ln for ln in pins if ln.startswith("site ")}
  now = {ln.split()[1]: ln for ln in rows if ln.startswith("site ")}
  out = []
  for k in sorted(set(base) | set(now)):
    if base.get(k) != now.get(k):
      out.append(f"{k}\n    pin  {base.get(k, '(absent)')}\n    now  {now.get(k, '(absent)')}")
  return out


# ---------------------------------------------------------------- the plant


#: (file, the def whose record is perturbed, the value it carries, the value planted,
#:  the class that leaves, the class that arrives). TWO STATES BOTH WAYS, because a
#: detector proven only on one direction is a direction, not a class.
PLANTS = [("tinybendygrad/engine/realize.bend", "var_arg", "S.Aalu{}", "S.AGlobal{}", "A", "B"),
          ("tinybendygrad/uop/divandmod.bend", "dm_param.range", "S.AGlobal{}", "S.Aalu{}",
           "B", "A")]


def plant() -> int:
  """Move one site's upstream shape each way and require the class to move with it.

  A TEMP COPY, AND THE COPY IS THE WHOLE TREE THIS RUN READS. `tinybendygrad/` IS READ-ONLY
  FOR THIS UNIT and a census that fixed a defect before counting it would turn 208 into 207
  with nobody able to say which row went.

  THE EDIT IS CPYTHON'S `is_variable` AND NOT A RENAME: the third conjunct is `_shape == ()`,
  and a PARAM carrying a value range is only a variable while its addrspace is ALU. Flipping
  ALU to GLOBAL says, in the lane's own vocabulary, "this PARAM is a buffer param now", and
  its shape is no longer `()`. So the class has to move or the census is not reading the lane.
  """
  tmp = ART / NAME / "plant"
  shutil.rmtree(tmp, ignore_errors=True)
  owned = tracked()
  base = {f"{r['file']}:{r['line']}": r["class"] for r in census(owned)}
  bad = []
  for rel, defname, frm, to, want_from, want_to in PLANTS:
    # CLEARED PER PLANT, not once for the loop: `census(owned, tmp)` walks the copy, so a
    # copy left over from the previous iteration is censused AGAIN and its rows move a
    # second time -- which is a plant measuring the previous plant.
    shutil.rmtree(tmp, ignore_errors=True)
    dst = tmp / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / rel, dst)
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
    rows = census(owned, tmp)
    if not rows:
      bad.append(f"{rel}: the census returned NO rows from the copy -- it is not reading "
                 f"`root`, so nothing it reports can be evidence of anything")
      continue
    moved = {f"{r['file']}:{r['line']}": r["class"] for r in rows}
    diffs = {k: (base.get(k), v) for k, v in moved.items() if base.get(k) != v}
    ok = bool(diffs) and all(a == want_from and b == want_to for a, b in diffs.values())
    print(f"--plant {rel} `def {defname}`: {frm} -> {to}  rows={len(rows)} moved={len(diffs)}  "
          f"{'OK' if ok else 'FAILED ' + str(sorted(diffs.values()))}")
    for k, (a, b) in sorted(diffs.items()):
      print(f"    {k}: {a} -> {b}")
    if not ok:
      bad.append(f"{rel}: moved {len(diffs)} rows, none of them {want_from}->{want_to}")
  shutil.rmtree(tmp, ignore_errors=True)
  if bad:
    print("PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
    return FAIL
  print("--plant: both directions moved")
  return PASS


# ---------------------------------------------------------------- main


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--rows", action="store_true")
  ap.add_argument("--plant", action="store_true")
  ap.add_argument("--accept", action="store_true")
  a = ap.parse_args()
  if a.plant:
    return plant()
  try:
    live = paramarg_fields((OPSDIR / "uop" / "ops.py").read_text(), "tinygrad/uop/ops.py")
    rev, pre = premigration_fields()
    allw = py_writers()
    facts = py_facts()
  except Refused as e:
    print(f"{NAME}: REFUSED: {e}", file=sys.stderr)
    return REFUSED
  rows = census(tracked())
  if not rows:
    print(f"{NAME}: DEAD: the census emitted no rows", file=sys.stderr)
    return DEAD
  lines = [row(r) for r in rows]
  if a.rows:
    print("\n".join(lines))
    return PASS
  names = {12: live[:12], 13: pre[:13]}
  report(rows, allw, names, facts, rev, test_dir_present())
  print("\n".join(lines))
  out = ART / NAME / "site-rows.rows"
  out.parent.mkdir(parents=True, exist_ok=True)
  out.write_text("\n".join(lines) + "\n")
  if a.accept:
    PINS.write_text("\n".join(lines) + "\n")
    print(f"re-pinned {len(lines)} rows into {PINS.relative_to(ROOT)}")
    return PASS
  pins = PINS.read_text().splitlines() if PINS.exists() else []
  d = diff(pins, lines)
  unresolved = [r for r in rows if r["class"] == "?"]
  for line in d[:20]:
    print(line)
  if unresolved:
    print(f"{len(unresolved)} site(s) could not be classified -- that is a FAIL, not a skip")
    for r in unresolved[:10]:
      print("  " + row(r))
  if not pins:
    return REFUSED
  if d or unresolved:
    return FAIL
  print(f"{NAME}: PASS {len(lines)} rows, 0 unclassified, pins agree")
  return PASS


if __name__ == "__main__":
  sys.exit(main())
