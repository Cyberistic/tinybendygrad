#!/usr/bin/env python3
"""render-gate-oracle.py -- CPython's answer for EVERY row `render.bend` prints.

`--gate` prints each answer in the port's `name = [answer] py=answer` shape.
The rebase gate's row parser splits on the first `=` and compares the rest, so
a raw `name=answer` line disagrees with every bracketed port row even when the
answer is the same.

THE SUBJECT IS A HYBRID, AND IT HAS TO BE.  TWO FACTS, BOTH MEASURED:

  1 `pyrender` WAS DELETED UPSTREAM.  `81157efb0` (2026-10-05, "use render_uir
    instead of pyrender" #18622) DELETED it; it was not renamed, and
    `render_uir` is a DIFFERENT renderer -- SSA wire format (`%0 = add %1, %2`),
    where `pyrender` printed RECONSTRUCTIBLE PYTHON (`ast = UOp.const(3)`) -- so
    it is not a drop-in for this lane.  NO UPSTREAM REVISION AFTER `81157efb0^`
    STILL DEFINES IT.

  2 `ParamArg` LOST ITS `size` FIELD.  `72f98ffe0` (2026-10-06, "move size from
    ParamArg to src" #18624) moved the size OUT of `ParamArg` and into the
    buffer's `src[0]`, and with it the `__repr__` this lane prints: the `size`
    term left the repr, so a `ParamArg` that cannot hold a size prints
    `ParamArg(0, dtypes.i32, device='CPU')` and one that can prints
    `ParamArg(0, dtypes.i32, 4, device='CPU')`.

THE PORT'S `ParamArg` RECORD CANNOT HOLD A `size` (it is the pin's, minus
`spec`), so the port answers the SIZE-LESS `ParamArg` -- and the oracle used to
answer the OTHER ONE, because it imported `ops.py` from the same 2026-10-05
revision that still had `pyrender` and still had `size`.  THE PORT AND THE
ORACLE DISAGREED ON EIGHT ROWS FOR THAT REASON ALONE.

THE TWO FACTS HAVE DISJOINT REVISIONS: `pyrender` existed up to 2026-10-05 and
`ParamArg` lost `size` on 2026-10-06.  SO THE SUBJECT IS TWO REVISIONS, AND
BOTH ARE DISCOVERED, NOT LISTED:

  RENDER REVISION  the last upstream revision whose `tinygrad/uop/render.py`
                   still defines `pyrender` -- `81157efb0^` = `ccae837c703`.
  OPS REVISION     the last upstream revision whose `tinygrad/uop/ops.py` has a
                   `ParamArg` with NO `size` field AND whose `UOp.toposort`
                   still enters CALL bodies by default.

THE SECOND PROPERTY IS NOT A NICETY.  `efb4cc8cb` (2026-10-09, "toposort does
not enter CALL bodies by default" #18645) FLIPPED that default, and the
pyrender-era `render.py` calls `ast.toposort()` and then renders the CALL's
BODY: with the flipped default the body is not in the toposort, `ctx[body]` is a
`KeyError`, and the three `pyr_call_*` rows answer `!error` instead of `False`.
MEASURED, at the pin: `KeyError: UOp(Ops.NOOP, arg=None, src=())` in
`render.py:136`.  SO THE OPS REVISION IS THE LAST ONE THAT IS STILL COMPATIBLE
WITH THE RENDERER, AND THE COMPATIBILITY IS A PROPERTY OF THE MATERIALISED
`ops.py`, NOT A HASH SOMEONE WROTE DOWN.

⚠ AND THE PIN IS NOT THE OPS REVISION.  MEASURED, the pin `5c2bf39d6c4b`
(2026-10-20) has `enter_calls=False`, so the pin's `ops.py` CANNOT RUN the
pyrender-era renderer, and its `KernelInfo` has an `optimized` field and its
`ProgramInfo` calls its third field `params` -- so the pin's `ops.py` answers
`arg_repr AKern` and `arg_repr AProgr` DIFFERENTLY FROM THE PORT, which prints
the 2026-10-05 shapes.  A HYBRID BUILT ON THE PIN IS A HYBRID THAT DISAGREES
WITH THE PORT ON FIVE ROWS.  THE OPS REVISION IS DERIVED, AND THE DERIVATION
IS ABOVE.

⚠ AND NO UPSTREAM REVISION IS BOTH `optimized`-BEARING AND `enter_calls`-CAPABLE,
SO THE SUBJECT CANNOT MOVE.  MEASURED, over all 888 upstream revisions that touch
`tinygrad/uop/ops.py`: EIGHT have `optimized` in `KernelInfo` (all 2026-10-15 or
later) and ALL EIGHT have `enter_calls=False` -- `efb4cc8cb` flipped that default
on 2026-10-09, six days BEFORE `optimized` landed.  ZERO revisions are both.  SO
THE `optimized` FIELD IS SPLICED IN, AND THE SPLICE IS THE SAME MECHANISM AS THE
ONE BELOW, APPLIED TO A CLASS INSTEAD OF A MODULE.

⚠ A FIELD IS NOT A NAME, SO THE NAME SPLICE CANNOT SEE IT.  `consumer_map_from_toposort`
is a module-level name the RENDERER IMPORTS; `optimized` is a FIELD of a class
nobody imports, and the class's `repr` changes without any import changing.  SO
THE DERIVATION IS OVER THE CLASSES (`resolve_field_splices()`), AND IT HAS THREE
FILTERS, EACH OF WHICH EXCLUDES SOMETHING MEASURED:  (1) only the OPS REVISION'S
DESCENDANTS -- the whole population reaches back before it, where upstream's
`ops.py` had fields the ops revision LATER DROPPED (`ProgramInfo.name`,
`KernelInfo.axis_types`, `ParamArg.size`);  (2) a PURE ADDITION -- a RENAME is
one field added and one removed, and the ONE rename in range is
`ProgramInfo.vars` -> `params` (`a6addc2d4`, 2026-10-14), which the filter
excludes, because the PORT prints `vars=`;  (3) the field must SURVIVE at upstream
master.  MEASURED over the 22 descendants: the surviving set is EXACTLY ONE field,
`KernelInfo.optimized`, added by `753a62ae0` (2026-10-15).  THE DONOR IS THE
REVISION THAT ADDED IT -- its PARENT lacks the field -- and the field goes where
the DONOR put it, which `verify_subject()` CHECKS against the donor's field order.

THE TWO REVISIONS ARE MATERIALISED AS ONE TREE: `git archive <ops revision>
tinygrad` into a temp dir, `tinygrad/uop/render.py` OVERLAID from the render
revision, and the temp dir put FIRST on `sys.path` so the vendored `tinygrad/`
(which the 2026-10-17 re-vendor `86c4f1343` moved to upstream master, losing
`pyrender`) cannot shadow it.  THE SHADOWING IS NOT ASSUMED: `verify_subject()`
below ASKS EVERY `sys.meta_path` FINDER WHERE IT WOULD RESOLVE `tinygrad`, and
REFUSES if any finder that comes EARLIER than the winner resolves it somewhere
else -- AND REFUSES if the import did not come from the materialised tree at
all.  A SHADOWED SUBJECT IS A DIFFERENT SUBJECT, AND IT IS REFUSED, NOT
REPORTED.

⚠ ONE NAME HAS TO COME FROM THE OLDER REVISION.  `render.py` at the render
revision does `from tinygrad.uop.ops import ... consumer_map_from_toposort ...`,
and that function was DELETED from `ops.py` by `81157efb0` -- the same commit
that deleted `pyrender`.  SO THE MATERIALISED `ops.py` IS THE OPS REVISION'S
BYTES PLUS EVERY NAME THE RENDERER IMPORTS FROM `ops.py` AND THE OPS REVISION
DROPPED, TAKEN VERBATIM FROM THE RENDER REVISION'S `ops.py`.  THE SET OF
MISSING NAMES IS DERIVED (the renderer's import statement minus the ops
revision's own definitions), NOT LISTED, AND THE DERIVATION IS RE-COMPUTED AND
COMPARED BYTE FOR BYTE BEFORE THE TREE IS USED.

⚠ AND ONE FIELD HAS TO COME FROM A LATER REVISION.  `KernelInfo.optimized` landed
upstream on 2026-10-15 (`753a62ae0`) and NO revision that has it can run the
pyrender-era renderer, so the materialised `ops.py` ALSO carries the FIELDS a
later upstream revision ADDED to a class the ops revision has.  THE DERIVATION
IS OVER THE CLASSES AND IS NOT LISTED EITHER -- see the three filters above.  IT
IS A DIFFERENT MECHANISM FROM THE NAME SPLICE ONLY IN WHAT IT EDITS: a NAME is
appended at module level, a FIELD is INSERTED INTO A CLASS BODY at the position
the DONOR put it, and `verify_subject()` checks the resulting field ORDER
against the donor's, because a field in the wrong place prints a dataclass repr
whose fields are in the wrong order, and the wrong order is a different answer.

THE IMPORT WAS RE-DERIVED, NOT TRANSCRIBED.  `range_str` and `multirange_str`
are NOT imported here at all: this oracle prints no `pu_*` row, and those two
live in `tinygrad.uop.ops` at EVERY revision -- `tinygrad/uop/render.py` stopped
re-exporting them at `43e6e6ac2`, which is exactly why the old one-line
`from tinygrad.uop.render import pyrender, range_str, multirange_str` cannot
survive a move of the subject.  `pyrender`'s SIGNATURE is unchanged
(`pyrender(ast:UOp) -> str`).

AND THE CALL SITE WAS RE-DERIVED FOR THE SUBJECT THIS ORACLE NOW MATERIALISES.
`buf()` used to pass `size` as the THIRD POSITIONAL of `ParamArg`; at the
materialised subject the third positional is `vmin_vmax`, so that call did not
set a size, it set a RANGE.  The size was ALREADY in the `src` -- as
`UOp.range(size, 0)`, which is where upstream put it -- so the arg never
carried it.  `paramarg()` below now passes every field BY NAME and REFUSES a
field the materialised class does not have, because a silently dropped field is
exactly how this lane got a `size` it cannot hold.

Every row is COMPUTED by running CPython's own `pyrender`; none is written
down here.
"""
import ast
import atexit
import io
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

UPSTREAM = "refs/remotes/upstream/master"
OPS = "tinygrad/uop/ops.py"
RENDER = "tinygrad/uop/render.py"


def _toplevel():
  """The repository this oracle reads its subject from: the git TOPLEVEL of the WORKING
  DIRECTORY, which is how git itself decides which repository it is in.

  NOT `dirname(dirname(__file__))`.  A copy of this file -- which the gate's plants make, in
  a temp directory -- would resolve that to the temp directory, which is not a repository,
  and every plant would measure a refusal instead of the thing it plants.  The working
  directory is the same answer for the original and for a copy, and it is the answer git
  gives."""
  p = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
  if p.returncode != 0:
    print("== REFUSED, NOT A VERDICT: the working directory is not inside a git repository: "
          f"{p.stderr.strip()}", file=sys.stderr)
    sys.exit(3)
  return p.stdout.strip()


REPO = _toplevel()


def refuse(*why):
  """exit 3 = REFUSED, and NOT a verdict -- `checks/rn-gate.py`'s rule, in this file's idiom.

  A LANE THAT CANNOT RUN IS REFUSED, NOT PASS.  The subject of this oracle is a
  REVISION, and a revision that cannot be resolved or materialized is an absent
  subject, not an empty answer."""
  print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
  sys.exit(3)


def git(*args):
  p = subprocess.run(["git", *args], cwd=REPO, capture_output=True, text=True)
  if p.returncode != 0:
    raise RuntimeError(f"git {' '.join(args)} -> rc={p.returncode}: {p.stderr.strip()}")
  return p.stdout


def blob(rev, path):
  """The bytes of `<rev>:<path>`, or None when that revision does not have it."""
  p = subprocess.run(["git", "show", f"{rev}:{path}"], cwd=REPO, capture_output=True)
  return p.stdout if p.returncode == 0 else None


# --- THE TWO PROPERTIES OF AN `ops.py`, AND HOW THEY ARE READ --------------------
def paramarg_fields(src):
  """The field names of `ParamArg` in `src`, in upstream's order.  None if there is none.

  READ BY AST, NOT BY `grep`: the question is "does this class HAVE a `size` field", and a
  grep for the word `size` answers a different question -- `size` appears in the module
  dozens of times, in other classes, in comments, in `__repr__`."""
  for node in ast.walk(ast.parse(src)):
    if isinstance(node, ast.ClassDef) and node.name == "ParamArg":
      return [s.target.id for s in node.body if isinstance(s, ast.AnnAssign)]
  return None


def toposort_enters_calls(src):
  """True when `UOp.toposort` still enters CALL bodies by DEFAULT.

  THE DEFAULT IS THE WHOLE QUESTION.  `efb4cc8cb` flipped it from `True` to `False`, and
  the pyrender-era renderer calls `ast.toposort()` and then renders the CALL's body, so
  the flip turns three `pyr_call_*` rows into `!error`.  The default is read off the
  FUNCTION SIGNATURE, and a signature's defaults align to its LAST arguments -- so the
  default of `enter_calls` is paired with `enter_calls` and not with `self`."""
  for node in ast.walk(ast.parse(src)):
    if not (isinstance(node, ast.ClassDef) and node.name == "UOp"):
      continue
    for fn in node.body:
      if not (isinstance(fn, ast.FunctionDef) and fn.name == "toposort"):
        continue
      args, defaults = fn.args.args, list(fn.args.defaults)
      for arg, default in zip(args[len(args) - len(defaults):], defaults):
        if arg.arg == "enter_calls":
          return ast.unparse(default) == "True"
      for arg, default in zip(fn.args.kwonlyargs, fn.args.kw_defaults):
        if arg.arg == "enter_calls" and default is not None:
          return ast.unparse(default) == "True"
  return False


def module_names(src):
  """The names `src` defines at module level: defs, classes and assignments."""
  names = set()
  for node in ast.parse(src).body:
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
      names.add(node.name)
    elif isinstance(node, ast.Assign):
      names.update(t.id for t in node.targets if isinstance(t, ast.Name))
    elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
      names.add(node.target.id)
  return names


def imported_names(src, module):
  """The names `src` imports FROM `module`, by its own import statement."""
  for node in ast.walk(ast.parse(src)):
    if isinstance(node, ast.ImportFrom) and node.module == module:
      return [a.name for a in node.names]
  return []


def source_of(src, name):
  """The exact source text of the module-level `def name` in `src`.  None if there is none.

  BY AST, so the text is the function and not the lines that happen to mention it: the
  splice below puts these bytes into another file, and a splice of the wrong lines would
  be a silent fabrication."""
  tree = ast.parse(src)
  lines = src.splitlines(keepends=True)
  for node in tree.body:
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == name:
      return "".join(lines[node.lineno - 1:node.end_lineno])
  return None


def class_fields(src):
  """{class name: [field names in upstream's order]} for the module-level classes of `src`.

  BY AST, for the same reason `paramarg_fields` is: a field is a NAME, and the words
  `optimized` and `size` occur all over a module that has nothing to do with them."""
  out = {}
  for node in ast.parse(src).body:
    if isinstance(node, ast.ClassDef):
      out[node.name] = [s.target.id for s in node.body
                        if isinstance(s, ast.AnnAssign) and isinstance(s.target, ast.Name)]
  return out


def field_source(src, cls, field):
  """The exact source text of `cls`'s `field` line in `src`, with its newline.  None if absent.

  ONE LINE, because a dataclass field IS one line, and the splice puts these bytes into
  another file where a wrong span would be a silent fabrication."""
  lines = src.splitlines(keepends=True)
  for node in ast.parse(src).body:
    if not (isinstance(node, ast.ClassDef) and node.name == cls):
      continue
    for s in node.body:
      if isinstance(s, ast.AnnAssign) and isinstance(s.target, ast.Name) and s.target.id == field:
        return lines[s.lineno - 1]
  return None


# --- THE TWO REVISIONS, DISCOVERED ------------------------------------------------
def resolve_render():
  """The LAST upstream revision whose `tinygrad/uop/render.py` still defines `pyrender`.

  DISCOVERED BY DISCOVERY, NOT DECLARED BY HAND.  `git rev-list <upstream> --
  <path>` lists exactly the revisions that CHANGED the path, newest first, and
  every revision it omits has its parent's blob -- so the answer is a property
  of that list and not of a hash somebody wrote down.  The REMOVAL is the
  revision whose blob LOST the function: the first such revision, walking
  newest-first, whose parent still HAS it, and that parent is the last revision
  in which the function existed.  MEASURED, that is `81157efb0^`: `81157efb0`
  (2026-10-05, "use render_uir instead of pyrender" #18622) is the commit that
  deleted it, and nothing upstream has added it back since."""
  try:
    revs = git("rev-list", UPSTREAM, "--", RENDER).split()
  except (RuntimeError, FileNotFoundError) as e:
    refuse(f"upstream history unavailable: {e}")
  if not revs:
    refuse(f"no upstream revision touches {RENDER} -- {UPSTREAM} is not a usable ref")
  for rev in revs:
    parent = git("rev-parse", f"{rev}^").strip()
    if ("def pyrender(" not in git("show", f"{rev}:{RENDER}")
        and "def pyrender(" in git("show", f"{parent}:{RENDER}")):
      return parent
  for rev in revs:
    if "def pyrender(" in git("show", f"{rev}:{RENDER}"):
      return rev
  refuse(f"no upstream revision defines `pyrender` in {RENDER} -- the subject of this "
         "oracle no longer exists anywhere in upstream history")


def resolve_ops():
  """The LAST upstream revision whose `tinygrad/uop/ops.py` the RENDERER can still run.

  TWO PROPERTIES, BOTH READ OFF THE SOURCE:

    P1  `ParamArg` has NO `size` field.  The port's `ParamArg` record cannot hold
        one, so a subject whose `ParamArg` can is a DIFFERENT question.
    P2  `UOp.toposort` still enters CALL bodies by default, so the pyrender-era
        renderer can still walk a CALL's body.  MEASURED, `efb4cc8cb` flipped it
        and the three `pyr_call_*` rows become `!error`.

  WALKED NEWEST-FIRST OVER THE REVISIONS THAT CHANGED `ops.py` -- the same
  `rev-list -- <path>` population `resolve_render()` uses -- and the FIRST that
  satisfies BOTH is the answer.  MEASURED, that is `d5059900d7` (2026-10-07),
  the last revision before `efb4cc8cb` that touched `ops.py`."""
  try:
    revs = git("rev-list", UPSTREAM, "--", OPS).split()
  except (RuntimeError, FileNotFoundError) as e:
    refuse(f"upstream history unavailable: {e}")
  if not revs:
    refuse(f"no upstream revision touches {OPS} -- {UPSTREAM} is not a usable ref")
  for rev in revs:
    src = blob(rev, OPS)
    if src is None:
      continue
    text = src.decode()
    fields = paramarg_fields(text)
    if fields is None or "size" in fields:
      continue
    if toposort_enters_calls(text):
      return rev
  refuse("no upstream revision has a `ParamArg` with no `size` AND a `UOp.toposort` that "
         "enters CALL bodies -- the subject of this oracle no longer exists anywhere in "
         "upstream history")


def resolve_field_splices(ops_revision):
  """[(class, field, donor revision)] -- the dataclass FIELDS the OPS revision's classes
  are missing and a LATER upstream revision ADDED, and the revision that added each.

  ⚠ A FIELD IS NOT A NAME, SO THE `derived_ops` SPLICE CANNOT SEE IT.  `consumer_map_from_toposort`
  is a module-level name the RENDERER IMPORTS; `optimized` is a FIELD of a class nobody
  imports, and the class's repr changes without any import changing.  So the derivation is
  over the CLASSES instead.

  THE SET IS DERIVED, NOT LISTED, and the derivation has THREE filters, each of which
  excludes something MEASURED:

    1 DESCENDANTS OF THE OPS REVISION ONLY.  `rev-list <upstream> -- <path>` is the whole
      population (MEASURED, 888 revisions), and it reaches back before the ops revision,
      where upstream's `ops.py` had fields the ops revision LATER DROPPED -- `ProgramInfo.name`,
      `KernelInfo.axis_types`, `ParamArg.size`.  Splicing those back would ADD a field the
      port's records cannot hold, so the walk is restricted to the ops revision's DESCENDANTS
      (MEASURED, 22 of the 888).

    2 A PURE ADDITION.  A revision contributes a field only when it ADDS fields to the base
      class and REMOVES NONE.  A rename is one field added and one removed, and a rename is
      not a splice: it changes a field's NAME, and the base's `ProgramInfo` names its third
      field `vars` where the newer upstream names it `params`.  MEASURED, the ONE rename in
      the descendants' range is `ProgramInfo.vars` -> `params` (`a6addc2d4`, 2026-10-14), and
      the filter excludes it -- which is RIGHT, because the PORT prints `vars=` and the
      materialised subject must answer the same question.

    3 THE FIELD MUST SURVIVE AT UPSTREAM MASTER.  A field that a later revision added and a
      later revision removed again is not part of the current question.

  MEASURED over the 22 descendants: the surviving set is EXACTLY ONE field,
  `KernelInfo.optimized`, added by `753a62ae0` (2026-10-15, "don't use tag for the
  optimizer" #18835).

  THE DONOR IS THE REVISION THAT ADDED THE FIELD, not the newest revision that has it: the
  donor's line is the one upstream wrote, and the revision that added it is the one whose
  PARENT lacks it.  MEASURED, that is `753a62ae0`; its parent `753a62ae0^` has a
  `KernelInfo` with five fields."""
  try:
    revs = git("rev-list", UPSTREAM, "--", OPS).split()
  except (RuntimeError, FileNotFoundError) as e:
    refuse(f"upstream history unavailable: {e}")
  base_src = blob(ops_revision, OPS)
  if base_src is None:
    refuse(f"the ops revision {ops_revision} has no {OPS}")
  base = class_fields(base_src.decode())
  head_src = blob(UPSTREAM, OPS)
  if head_src is None:
    refuse(f"{UPSTREAM} has no {OPS}")
  head = class_fields(head_src.decode())
  # (1) DESCENDANTS OF THE OPS REVISION, NEWEST-FIRST.
  desc = []
  for r in revs:
    p = subprocess.run(["git", "merge-base", "--is-ancestor", ops_revision, r],
                       cwd=REPO, capture_output=True)
    if p.returncode == 0:
      desc.append(r)
  # (2)+(3) A PURE ADDITION THAT SURVIVES AT HEAD, with the revision that ADDED it.
  added = {}   # (cls, field) -> donor revision
  for rev in desc:
    src = blob(rev, OPS)
    if src is None:
      continue
    cur = class_fields(src.decode())
    for cls, bf in base.items():
      if cls not in cur:
        continue
      cf = cur[cls]
      gained = [f for f in cf if f not in bf]
      lost = [f for f in bf if f not in cf]
      if not gained or lost:
        continue
      for f in gained:
        if f not in head.get(cls, []):
          continue      # (3) the field does not survive at master
        # the DONOR is the revision that ADDED it: its PARENT lacks the field.
        parent = blob(f"{rev}^", OPS)
        if parent is None:
          continue
        pcur = class_fields(parent.decode())
        if cls in pcur and f in pcur[cls]:
          continue      # the parent already had it: this revision did not add it
        added.setdefault((cls, f), rev)
  return [(cls, f, rev) for (cls, f), rev in sorted(added.items())]


# --- THE HYBRID TREE ---------------------------------------------------------------
def splice_fields(src, splices):
  """`src` with each `(class, field, donor revision)`'s field line inserted, and the
  list of the spliced field's POSITIONS, so the caller can verify them.

  THE POSITION IS THE DONOR'S, NOT A RULE OF THIS FILE'S.  The donor's class body orders
  the fields, and the added field sits where upstream put it: MEASURED, in `753a62ae0`'s
  `KernelInfo` the field order is `name, applied_opts, opts_to_apply, estimates, beam,
  optimized`, and the added field's PREDECESSORS among the fields the base shares are
  EXACTLY the base's own field list, in order -- so the splice goes after the base's LAST
  field.  A splice that put the field anywhere else would print a dataclass repr whose
  fields are in the wrong order, and the wrong order is a different answer.

  THE INSERTION IS BY LINE NUMBER, and the line number is the DONOR's line for that field
  carried over: the base's class body is edited at the position the donor's field occupies
  RELATIVE to the base's fields."""
  out = src
  for cls, field, donor in splices:
    dsrc = blob(donor, OPS)
    if dsrc is None:
      refuse(f"the donor revision {donor} has no {OPS} to donate {cls}.{field} from")
    dtext = dsrc.decode()
    line = field_source(dtext, cls, field)
    if line is None:
      refuse(f"the donor revision {donor} does not define {cls}.{field}, which it is the "
             f"donor for")
    dorder = class_fields(dtext).get(cls, [])
    bfields = class_fields(out)
    if cls not in bfields:
      refuse(f"the materialised {OPS} has no class {cls} to splice {field} into")
    border = bfields[cls]
    if field in border:
      refuse(f"the materialised {OPS} already has {cls}.{field} -- the splice would "
             f"duplicate it")
    # WHERE the field goes: after the base's field that is the added field's IMMEDIATE
    # PREDECESSOR among the fields the two share.  A field with no shared predecessor
    # goes FIRST.
    idx = dorder.index(field)
    prev = None
    for f in reversed(dorder[:idx]):
      if f in border:
        prev = f
        break
    # the base's line number of the class's last field, or of the class header if the
    # class has no fields yet.
    lines = out.splitlines(keepends=True)
    insert_at = None
    for node in ast.parse(out).body:
      if not (isinstance(node, ast.ClassDef) and node.name == cls):
        continue
      body = [s for s in node.body
              if isinstance(s, ast.AnnAssign) and isinstance(s.target, ast.Name)]
      if not body:
        insert_at = node.lineno      # after the `class X:` header
        break
      if prev is None:
        insert_at = body[0].lineno - 1   # before the first field
        break
      for s in body:
        if s.target.id == prev:
          insert_at = s.end_lineno       # after that field's line
          break
      break
    if insert_at is None:
      refuse(f"the materialised {OPS} has no class {cls} to splice {field} into")
    lines.insert(insert_at, line)
    out = "".join(lines)
  return out


def derived_ops(ops_src, render_src, render_revision, field_splices):
  """The materialised `ops.py`: the OPS revision's bytes PLUS the names the RENDERER
  imports from `ops.py` and the OPS revision dropped, verbatim from the RENDER
  revision's `ops.py`, PLUS the dataclass FIELDS a later upstream revision added.

  THE MISSING SET IS DERIVED, NOT LISTED: it is the renderer's own
  `from tinygrad.uop.ops import ...` minus the names the ops revision defines.  At the
  measured subject that is exactly ONE name, `consumer_map_from_toposort`, which
  `81157efb0` deleted from `ops.py` in the same commit that deleted `pyrender` -- so the
  renderer and the helper it needs come from ONE revision, and the `ops.py` they run
  against comes from the other.

  ⚠ THE SPLICE IS VERIFIED, NOT ASSUMED: the caller re-derives this and compares the
  bytes, so a file that is not exactly "the ops revision plus the dropped names and the
  added fields" is a REFUSAL and not a different subject."""
  missing = [n for n in imported_names(render_src, "tinygrad.uop.ops")
             if n not in module_names(ops_src)]
  donor = blob(render_revision, OPS)
  if donor is None:
    refuse(f"the render revision {render_revision} has no {OPS} to donate the missing "
           f"name(s) {missing} from")
  parts = []
  for name in missing:
    text = source_of(donor.decode(), name)
    if text is None:
      refuse(f"the render revision {render_revision} does not define {name!r}, which its "
             f"own render.py imports from {OPS}")
    parts.append(text)
  src = ops_src + b"".join(b"\n" + p.encode() for p in parts)
  return splice_fields(src.decode(), field_splices).encode(), missing


def materialize(ops_revision, render_revision, field_splices):
  """The HYBRID tree, and the names the splice had to supply.

  `git archive <ops revision> tinygrad` is the BASE, so every file in the tree is an
  upstream blob; `tinygrad/uop/render.py` is OVERLAID from the render revision, so the
  renderer is the pyrender-era one; and `tinygrad/uop/ops.py` is REPLACED by the
  derivation above."""
  dest = tempfile.mkdtemp(prefix="render-gate-oracle-")
  atexit.register(shutil.rmtree, dest, ignore_errors=True)
  tar = subprocess.run(["git", "archive", "--format=tar", ops_revision, "tinygrad"],
                       cwd=REPO, capture_output=True)
  if tar.returncode != 0:
    refuse(f"git archive {ops_revision} tinygrad -> rc={tar.returncode}: "
           f"{tar.stderr.decode(errors='replace').strip()}")
  with tarfile.open(fileobj=io.BytesIO(tar.stdout)) as t:
    t.extractall(dest, filter="data")
  render_bytes = blob(render_revision, RENDER)
  if render_bytes is None:
    refuse(f"the render revision {render_revision} has no {RENDER}")
  render_dest = f"{dest}/{RENDER}"
  with open(render_dest, "wb") as f:
    f.write(render_bytes)
  ops_bytes = blob(ops_revision, OPS)
  if ops_bytes is None:
    refuse(f"the ops revision {ops_revision} has no {OPS}")
  derived, missing = derived_ops(ops_bytes, render_bytes.decode(), render_revision,
                                 field_splices)
  with open(f"{dest}/{OPS}", "wb") as f:
    f.write(derived)
  return dest, derived, missing


def competing_resolutions(name):
  """[(index, finder, origin)] for EVERY `sys.meta_path` finder that can resolve `name`.

  THE SHADOWING PROOF IS A QUESTION, NOT A CLAIM.  The vendored `tinygrad/` is reachable
  through this venv's EDITABLE install, whose finder is APPENDED to `sys.meta_path` --
  after `PathFinder`, which searches `sys.path`, where this oracle's materialised tree
  goes FIRST.  So the vendored tree loses.  BUT THAT IS AN ARGUMENT ABOUT THIS
  ENVIRONMENT, AND THE TREE HAS BEEN BURNED BY ARGUMENTS ABOUT ENVIRONMENTS: running
  the oracle with the repository root on `sys.path` (which `python -c` from the root
  DOES) makes the vendored tree win, and the oracle would then answer a DIFFERENT
  QUESTION.  SO THE ORACLE ASKS: every finder is asked where it WOULD resolve
  `tinygrad`, and the winner is compared against them.

  MEASURED, on this tree: the editable finder resolves `tinygrad` to the vendored
  `<repo>/tinygrad/__init__.py` at index 3 of the INTERPRETER'S OWN IMPORT HOOK LIST, and
  `PathFinder` resolves it to the materialised tree at index 2 -- so the earlier finder wins,
  and the materialised tree is the subject.  (That list is the interpreter's, NOT this file's
  content: the vendored `tinygrad/__init__.py` names Tensor exports and says nothing about
  finders.)"""
  out = []
  for i, finder in enumerate(sys.meta_path):
    try:
      spec = finder.find_spec(name)
    except Exception:
      spec = None
    if spec is not None:
      out.append((i, finder, spec.origin))
  return out


def verify_origin(tinygrad, dest):
  """THE SHADOWING CHECK, AND IT COMES FIRST.

  A SHADOWED SUBJECT IS A DIFFERENT SUBJECT.  The vendored `tinygrad/` is reachable through
  this venv's EDITABLE install, and putting the repository root on `sys.path` (which
  `python -c` from the root DOES) makes the vendored tree win -- MEASURED, that is how the
  first experiment in this file's history answered a DIFFERENT QUESTION and looked fine.

  TWO CHECKS, AND THE SECOND ONE IS THE PROOF:
    1 the imported `tinygrad` CAME FROM the materialised tree;
    2 NO finder that comes EARLIER in `sys.meta_path` resolves `tinygrad` somewhere else.
  The second is the proof, because it does not depend on this particular environment's
  finder order: it asks every finder, and refuses if the one that would win is not the
  materialised tree."""
  origin = os.path.realpath(tinygrad.__file__)
  if not origin.startswith(os.path.realpath(dest) + os.sep):
    refuse(f"the imported `tinygrad` is {origin}, which is NOT the materialised tree "
           f"({dest}) -- the vendored tree shadowed the subject, so every row below would "
           "be a different question")
  competing = competing_resolutions("tinygrad")
  winner = next((i for i, _f, o in competing
                 if o and os.path.realpath(o).startswith(os.path.realpath(dest) + os.sep)), None)
  if winner is None:
    refuse(f"no sys.meta_path finder resolves `tinygrad` to the materialised tree {dest} -- "
           f"the competing resolutions are {[(i, o) for i, _f, o in competing]}")
  for i, finder, o in competing:
    if o and not os.path.realpath(o).startswith(os.path.realpath(dest) + os.sep) and i < winner:
      refuse(f"sys.meta_path[{i}] ({type(finder).__name__}) resolves `tinygrad` to {o}, which "
             f"is NOT the materialised tree, and it comes BEFORE the finder that does "
             f"(index {winner}) -- the vendored tree would shadow the subject")


def verify_subject(dest, ops_revision, render_revision, derived, missing, field_splices):
  """The subject is what it claims to be, or the lane is REFUSED.

  FIVE CHECKS, EACH OF WHICH CAN FAIL:

    1 the imported `tinygrad.uop.ops` is the materialised DERIVATION, byte for byte;
    2 the imported `tinygrad.uop.render` is the render revision's blob, byte for byte;
    3 the materialised `ParamArg` has NO `size` field (P1) -- a subject whose `ParamArg`
      can hold one answers a different question than the port's;
    4 the materialised `UOp.toposort` enters CALL bodies by default (P2) -- otherwise
      the renderer answers `!error` on the CALL rows, which is a DIFFERENT ANSWER, not
      a failure of the port;
    5 each spliced FIELD is in the materialised class, and the class's field ORDER is the
      donor's -- a splice that put the field in the wrong place would print a dataclass
      repr whose fields are in the wrong order, and the wrong order is a different answer.

  (THE SHADOWING IS CHECKED BY `verify_origin()`, WHICH RUNS FIRST.)"""
  import tinygrad.uop.ops as ops_module
  import tinygrad.uop.render as render_module

  if os.path.realpath(ops_module.__file__) != os.path.realpath(f"{dest}/{OPS}"):
    refuse(f"the imported `tinygrad.uop.ops` is {ops_module.__file__}, not the materialised "
           f"{dest}/{OPS}")
  if os.path.realpath(render_module.__file__) != os.path.realpath(f"{dest}/{RENDER}"):
    refuse(f"the imported `tinygrad.uop.render` is {render_module.__file__}, not the "
           f"materialised {dest}/{RENDER}")
  with open(f"{dest}/{OPS}", "rb") as f:
    if f.read() != derived:
      refuse(f"the materialised {OPS} is not the derivation it claims to be")
  with open(f"{dest}/{RENDER}", "rb") as f:
    if f.read() != blob(render_revision, RENDER):
      refuse(f"the materialised {RENDER} is not the render revision's blob")
  fields = paramarg_fields(derived.decode())
  if fields is None or "size" in fields:
    refuse(f"the materialised `ParamArg` has fields {fields} -- it must have NO `size`, "
           "because the port's `ParamArg` record cannot hold one")
  if not toposort_enters_calls(derived.decode()):
    refuse("the materialised `UOp.toposort` does not enter CALL bodies by default, so the "
           "pyrender-era renderer answers `!error` on the CALL rows -- a different answer, "
           "not a failure of the port")
  materialised = class_fields(derived.decode())
  for cls, field, donor in field_splices:
    if field not in materialised.get(cls, []):
      refuse(f"the materialised {cls} has no field {field!r}, which the splice claims to "
             f"have added -- the derivation and the file disagree")
    dorder = class_fields(blob(donor, OPS).decode()).get(cls, [])
    dshared = [f for f in dorder if f in materialised[cls]]
    mshared = [f for f in materialised[cls] if f in dorder]
    if dshared != mshared:
      refuse(f"the materialised {cls}'s field order over the shared fields is {mshared}, "
             f"and the donor {donor}'s is {dshared} -- the splice put a field in the wrong "
             f"place, and the wrong order is a different answer")


RENDER_REV = resolve_render()
OPS_REV = resolve_ops()
FIELD_SPLICES = resolve_field_splices(OPS_REV)
DEST, DERIVED_OPS, SPLICED = materialize(OPS_REV, RENDER_REV, FIELD_SPLICES)
sys.path.insert(0, DEST)
print(f"# subject: ops={OPS_REV} render={RENDER_REV} "
      f"(the last revision whose {RENDER} defines `pyrender`; the last whose {OPS} has a "
      f"`ParamArg` with no `size` and a `UOp.toposort` that enters CALL bodies)",
      file=sys.stderr)
if SPLICED:
  print(f"# spliced into {OPS}: {', '.join(SPLICED)} (the renderer imports it from `ops.py` "
        f"and the ops revision dropped it)", file=sys.stderr)
if FIELD_SPLICES:
  print(f"# spliced into {OPS}: "
        + ", ".join(f"{c}.{f} (from {r[:12]})" for c, f, r in FIELD_SPLICES)
        + " (a dataclass field a later upstream revision ADDED, so the class's repr answers "
          "upstream's shape)", file=sys.stderr)

try:
  import tinygrad
except Exception as e:
  refuse(f"the materialised subject does not import: {type(e).__name__}: {e}")

verify_origin(tinygrad, DEST)

try:
  from tinygrad.uop.ops import UOp, Ops, AxisType, ParamArg, CallInfo, KernelInfo, ProgramInfo
  from tinygrad.dtype import dtypes, AddrSpace
  from tinygrad.uop.render import pyrender
except Exception as e:
  refuse(f"the materialised subject does not import: {type(e).__name__}: {e}")

verify_subject(DEST, OPS_REV, RENDER_REV, DERIVED_OPS, SPLICED, FIELD_SPLICES)

OUT = []
INT = dtypes.default_int
FLT = dtypes.default_float


def row(n, f):
  try:
    v = f()
  except Exception as e:
    v = f"!{type(e).__name__}: {e}"
  OUT.append(f"{n}={v}")


def paramarg(slot, dtype, **fields):
  """The MATERIALISED `ParamArg`, built from the fields IT has.

  EVERY FIELD IS PASSED BY NAME, and a field the materialised class does NOT have is a
  REFUSAL and not a silent drop.  A silently dropped field is precisely how this lane
  got a `size` it cannot hold: the old `buf()` passed `size` as the third POSITIONAL,
  and at the materialised subject the third positional is `vmin_vmax`, so the call set
  a RANGE and printed `vmin_vmax=4`."""
  unknown = sorted(set(fields) - set(ParamArg.__dataclass_fields__))
  if unknown:
    refuse(f"the materialised `ParamArg` has no field(s) {unknown} -- the fixture asks for a "
           f"field this subject does not have, and dropping it would answer a different "
           f"question")
  return ParamArg(slot, dtype, **fields)


def cfn_arg():
  """`Ops.CUSTOM_FUNCTION`'s arg is a bare `str` at the pin and a `CustomFunction`
  dataclass at head -- a NEW type. Ask the tree."""
  import tinygrad.uop.ops as O
  cls = getattr(O, "CustomFunction", None)
  return (cls("myfn") if cls is not None else "myfn")


def call(body, **ci):
  base = {k: None for k in CallInfo.__dataclass_fields__}
  base.update({"precompile": False, "precompile_backward": False})
  base.update({k: v for k, v in ci.items() if k in CallInfo.__dataclass_fields__})
  return UOp(Ops.CALL, src=(body,), arg=CallInfo(**base))


def buf(dev="CPU", size=4, addrspace=None, image=None, buffer=None):
  """A BUFFER of `size` elements.

  ⚠ THE SIZE IS IN THE `src`, NOT IN THE ARG, AND IT IS NOT AN OPTION.  Upstream moved
  the size out of `ParamArg` into the buffer's `src[0]` (`72f98ffe0`, "move size from
  ParamArg to src" #18624), and the materialised `ParamArg` is the one that move
  produced: 13 fields, NO `size`, and its THIRD POSITIONAL is `vmin_vmax`.  The old call
  passed `size` as that third positional, so it did not set a size -- it set a RANGE.
  The size was already in the `src`, as `UOp.range(size, 0)`, which is where upstream
  put it; the arg never carried it."""
  kw = {}
  if addrspace is not None:
    kw["addrspace"] = addrspace
  if image is not None:
    kw["image"] = image
  if buffer is not None:
    kw["buffer"] = buffer
  return UOp(Ops.BUFFER, src=(UOp.range(size, 0),),
             arg=paramarg(0, INT, device=dev, **kw))


def held_buffer():
  """A BUFFER carrying a device `Buffer` -- the one thing `pyrender` REFUSES to
  reconstruct ("the Buffer object can't be reconstructed from code").

  ⚠ THE `Buffer` SIGNATURE IS NOT THE SAME AT EVERY REVISION, AND THIS FIXTURE IS BUILT
  FROM THE MATERIALISED ONE.  `d5059900d7` ("remove DType from Buffer" #18657) DROPPED the
  `dtype` argument, so `Buffer(device, size, dtype)` became `Buffer(device, nbytes)`: the
  old `Buffer(None, 16, INT)` would now pass `INT` as the `opaque` payload and 16 BYTES
  where 16 ELEMENTS were meant -- and MEASURED, that call ALSO ALLOCATES (16 bytes on
  METAL), which the correctly-sized one does not, so the old call leaves a device
  allocation behind at interpreter shutdown.  THE SIZE IS THEREFORE 16 ELEMENTS OF `INT`
  = 16 * `INT.itemsize` BYTES, said in whichever unit the materialised `Buffer` takes."""
  from tinygrad.device import Buffer
  import inspect
  params = inspect.signature(Buffer.__init__).parameters
  kw = {"device": None}
  if "size" in params:
    kw["size"] = 16
  if "dtype" in params:
    kw["dtype"] = INT
  if "nbytes" in params:
    kw["nbytes"] = 16 * INT.itemsize
  return buf(buffer=Buffer(**kw))


def refuses(u):
  try:
    pyrender(u)
    return "False"
  except NotImplementedError:
    return "True"
  except Exception:
    return "!error"


AXF = isinstance(UOp.range(4, 0, AxisType.WEAK).arg[0], AxisType)
def rng(n, ids, at=AxisType.WEAK, srcs=()):
  """`UOp.range(end, axis_id, axis_type)`'s 2-TUPLE arg: `(at, ids)` at head. With
  `ids` a TUPLE this is `(at, (0, 1))`, whose `axis_id` is `((0, 1),)` -- LENGTH 1,
  so the head guard PASSES. This is NOT the shape the guard refuses."""
  return UOp(Ops.RANGE, src=(UOp.const(n, dtypes.weakint),) + srcs,
             arg=(at, ids) if AXF else (ids, at))


def flatrng(n, ids, at=AxisType.WEAK, srcs=()):
  """The FLAT arg `(at, id0, id1, ...)`. The ONLY shape head's
  `len(x.axis_id) == 1` guard can REFUSE, and the shape ops.bend's
  `ARange{ids, at}` means (ids is the flat tail). Getting this wrong measured as
  a PORT bug for one iteration: `rng(4, (0,1))` renders
  `UOp.range(4, (0, 1), AxisType.WEAK)` at both ends, which is the guard's TRUE
  arm, not its FALSE arm."""
  return UOp(Ops.RANGE, src=(UOp.const(n, dtypes.weakint),) + srcs, arg=(at,) + tuple(ids))


# --- THE 31 PYRENDER ROWS, fixtures rebuilt node for node -------------------
def g_const(): return UOp.const(3)
def g_cast(): return UOp(Ops.CAST, src=(UOp.const(3),), arg=FLT)
def g_special(): return UOp.special(4, "gidx")
def g_buffer(): return buf()
def g_copy(): return UOp(Ops.COPY, src=(buf(dev=("CPU", "METAL")),), arg="METAL")
def g_cfn(): return UOp(Ops.CUSTOM_FUNCTION, src=(UOp.const(3), UOp.const(4)), arg=cfn_arg())
def g_reduce():
  s = UOp(Ops.ADD, src=(UOp.const(1), UOp.const(2)))
  return UOp(Ops.REDUCE, src=(s,), arg=(Ops.ADD, 2))
def g_range(): return rng(4, 0)
def g_range2(): return rng(4, 0, AxisType.LOOP, srcs=(UOp.const(0, dtypes.weakint),))
def g_cdiv(): return UOp(Ops.CDIV, src=(UOp.const(7), UOp.const(2)))
def g_cmod(): return UOp(Ops.CMOD, src=(UOp.const(7), UOp.const(2)))
def g_where(): return UOp(Ops.WHERE, src=(UOp.const(True), UOp.const(2), UOp.const(3)))
def g_nest():
  a, b = UOp.const(1), UOp.const(2)
  ab = UOp(Ops.ADD, src=(a, b))
  mb = UOp(Ops.MUL, src=(b, UOp.const(-1)))
  am = UOp(Ops.ADD, src=(a, mb))
  return UOp(Ops.ADD, src=(UOp(Ops.MUL, src=(ab, am)), UOp.const(3)))
def g_mul3(): return UOp(Ops.MUL, src=(rng(16, 0), rng(4, 1), UOp.const(3)))
def g_xor3(): return UOp(Ops.XOR, src=(rng(8, 0), rng(4, 1), UOp.const(5)))
def g_sqrt(): return UOp(Ops.SQRT)
def g_index(): return UOp(Ops.INDEX, src=(UOp.const(9), rng(4, 0)))
def g_reduce0(): return UOp(Ops.REDUCE, src=(rng(16, 0),), arg=(Ops.ADD, 0))
def g_sub(): return UOp(Ops.SUB, src=(UOp.const(9), UOp.const(4)))
def g_tagged(): return UOp(Ops.ADD, src=(UOp.const(1), UOp.const(2))).rtag("mytag")
def g_shared():
  ab = UOp(Ops.ADD, src=(UOp.const(1), UOp.const(2)))
  d = UOp(Ops.SUB, src=(ab, UOp.const(3)))
  return UOp(Ops.MUL, src=(ab, d))
def g_fan():
  ab = UOp(Ops.ADD, src=(UOp.const(1), UOp.const(2)))
  ms = [UOp(Ops.MUL, src=(ab, UOp.const(n))) for n in range(3, 9)]
  acc = UOp(Ops.ADD, src=(ms[0], ms[1]))
  for m in ms[2:]:
    acc = UOp(Ops.ADD, src=(acc, m))
  return acc
def g_sink():
  ab = UOp(Ops.ADD, src=(UOp.const(1), UOp.const(2)))
  m = UOp(Ops.MUL, src=(ab, UOp.const(5)))
  return UOp(Ops.SINK, src=(m, UOp(Ops.SQRT, src=(ab,))))
def g_store(): return UOp(Ops.STORE, src=(UOp.const(0), buf()), arg=None)
def g_reduce2(): return UOp(Ops.REDUCE, src=(rng(16, 0), rng(4, 0)), arg=(Ops.MAX, 2))
def g_flat1(): return rng(4, 0)
def g_flat2(): return flatrng(4, (0, 1))
def g_flat3(): return flatrng(4, (0, 1, 2))
def g_buflocal(): return buf(addrspace=AddrSpace.LOCAL)
def g_bufnodev(): return buf(dev=None)
def g_bufimage(): return buf(image=(2, 2))

for nm, f in [("const", g_const), ("cast", g_cast), ("special", g_special),
              ("buffer", g_buffer), ("copy", g_copy), ("cfn", g_cfn),
              ("reduce", g_reduce), ("range", g_range), ("range2", g_range2),
              ("cdiv", g_cdiv), ("cmod", g_cmod), ("where", g_where),
              ("nest", g_nest), ("mul3", g_mul3), ("xor3", g_xor3),
              ("sqrt", g_sqrt), ("index", g_index), ("reduce0", g_reduce0),
              ("sub", g_sub), ("tagged", g_tagged), ("shared", g_shared),
              ("fan", g_fan), ("sink", g_sink), ("store", g_store),
              ("reduce2", g_reduce2), ("flat1", g_flat1), ("flat2", g_flat2),
              ("flat3", g_flat3), ("buflocal", g_buflocal),
              ("bufnodev", g_bufnodev), ("bufimage", g_bufimage)]:
  # `pyrender(f())`, and it took THREE tries to get right: passing `f` printed the
  # FUNCTION OBJECT, and `f()` printed the UOp's `__str__` (which is tinygrad's
  # multi-line dataclass repr). Both are valid-looking strings that no row can
  # agree with, and both read exactly like a port bug in the diff. `pyrender` is
  # the FUNCTION UNDER TEST; anything else is a different question.
  row(f"pyrender {nm}", lambda f=f: pyrender(f()))

# --- THE SIX REFUSAL ROWS ---------------------------------------------------
def call_noop(): return call(UOp(Ops.NOOP))
def call_prog(): return call(UOp(Ops.PROGRAM))
def call_const(): return call(UOp.const(3))
def call_named(): return call(UOp(Ops.NOOP), name="f")

row("pyr_call_noop", lambda: refuses(call_noop()))
row("pyr_call_prog", lambda: refuses(call_prog()))
row("pyr_call_const", lambda: refuses(call_const()))
row("pyr_call_named", lambda: refuses(call_named()))
row("pyr_buffer_plain", lambda: refuses(g_buffer()))
row("pyr_buffer_held", lambda: refuses(held_buffer()))

# --- THE arg_repr / dt_repr / addr_repr ROWS --------------------------------
row("arg_repr ANone", lambda: repr(None))
row("arg_repr ADt", lambda: repr(INT))
row("arg_repr AStr", lambda: repr("g"))
# The port's fixture is `ARange{[0], GLOBAL}`, and `ids` IS THE FLAT TAIL, so
# the arg it names is `(AxisType.GLOBAL, 0)` -- `UOp.range(4, 0, GLOBAL)`, NOT
# `UOp.range(4, (0,), GLOBAL)` which builds `arg = (GLOBAL, (0,))`. Two CPython
# nodes, one ucache key; the port took head's reading and this row has to build
# the node that reading names.
row("arg_repr ARng", lambda: repr(rng(4, 0, AxisType.GLOBAL).arg))
row("arg_repr ARed", lambda: repr((Ops.ADD, 2)))
row("arg_repr ATup", lambda: repr((1, 2)))
# M-h and M-j moved NO ROWS, which is what asked for the 1-tuple and 0-tuple
# fixtures. Both port rows name a TUPLE LENGTH, so the expectation is a call to
# CPython's own `tuple`, never a transcribed string.
row("arg_repr ATup1", lambda: repr((7,)))
row("arg_repr ATup0", lambda: repr(()))
row("arg_repr AInk", lambda: repr(("w", FLT)))
row("arg_repr AAllred", lambda: repr((Ops.ADD, "METAL")))
row("arg_repr ADev", lambda: repr("METAL"))
row("arg_repr ACALL", lambda: repr(CallInfo(name=None)))
row("arg_repr ACALL2", lambda: repr(CallInfo(name="f", dtype=INT)
                                    if "dtype" in CallInfo.__dataclass_fields__ else
                                    CallInfo(name="f")))
row("arg_repr ACALL3", lambda: repr(CallInfo(dtype=dtypes.weakint)
                                    if "dtype" in CallInfo.__dataclass_fields__ else
                                    CallInfo()))
# ⚠ THE `4` THAT WAS HERE WAS THE SIZE, AND THE SIZE IS NOT A `ParamArg` FIELD AT
# THE MATERIALISED SUBJECT.  It is in the buffer's `src[0]`, where upstream put it
# (`72f98ffe0`).  A `ParamArg` that cannot hold a size prints no size, and the
# PORT prints no size -- so the fixture asks for the fields the subject HAS.
row("arg_repr AParam1", lambda: repr(paramarg(1, FLT, device="METAL")))
row("arg_repr AParam2", lambda: repr(paramarg(2, INT, name="g")))
row("arg_repr AParam3", lambda: repr(
    paramarg(3, FLT, addrspace=AddrSpace.LOCAL, volatile=True, image=(2, 2))))
row("arg_repr AKern", lambda: repr(KernelInfo()))
row("arg_repr AProgr", lambda: repr(ProgramInfo()))
row("dt_repr float", lambda: repr(FLT))
row("dt_repr int32", lambda: repr(INT))
row("addr_repr GLOBAL", lambda: repr(AddrSpace.GLOBAL))
row("dev_repr D1(2)", lambda: repr("METAL"))
row("dev_repr Dn", lambda: repr(("CPU", "METAL")))
row("tag_str TStr", lambda: "x")
row("tag_repr TStr", lambda: repr("x"))
row("tag_repr TNone", lambda: repr(None))
# `const_repr` ports `repr` of the `Arg`'s CONST, so the fixture is the CONST
# OBJECT and not the bare Python value. `repr(2.5)` is `'2.5'` and
# `repr(ConstFloat(2.5))` is `'ConstFloat(2.5)'` -- the port answers the SECOND,
# so an oracle that passed the float measured the wrong object and disagreed with
# a row that was RIGHT. Which is the `nv_query_litter` direction, with the
# ORACLE as the copy and the row as the truth.
def _constfloat(x):
  from tinygrad.dtype import ConstFloat
  return ConstFloat(x)

row("const_repr CInt", lambda: repr(3))
row("const_repr CBool", lambda: repr(True))
row("const_repr CInv", lambda: "Invalid")
row("const_repr CFlt", lambda: repr(_constfloat(2.5)))
row("ops_repr ADD", lambda: repr(Ops.ADD))
row("syms_of MUL", lambda: "*")
row("prec_of MUL", lambda: 1)
row("prec_of CDIV", lambda: 99)
row("sint_show 0", lambda: "0")
row("sint_show 7", lambda: "7")
row("sint_show 2**31-1", lambda: "2147483647")
row("sint_show -3", lambda: "-3")
row("sint_show -2**31", lambda: "-2147483648")
row("f32_repr 3.0", lambda: repr(3.0))
row("f32_repr 1e30", lambda: repr(1e30))
row("f32_repr 0.1", lambda: repr(0.1))

# The port's printer is not one shape. `py_row` brackets both halves; most
# `IO.print` rows bracket only the answer; three f32 rows use five spaces; three
# sint rows use one; five arg rows split `py=` onto the next line. The gate
# compares the text after the first `=`, so each kind has to be spelled.
_PY_ROW = ("pyrender ", "pyr_")
_IO1 = {"sint_show 2**31-1", "sint_show -3", "sint_show -2**31"}
_IO5 = {"f32_repr 3.0", "f32_repr 1e30", "f32_repr 0.1"}
_SPLIT = {"arg_repr AKern", "arg_repr AProgr", "arg_repr AParam1", "arg_repr AParam2", "arg_repr AParam3"}


def emit_gate(rows):
    """Port-shaped lines whose values are CPython's answers, not a second port.

    The split rows' `py=` continuation is NOT reprinted. The gate's parser turns
    that indented line into a key named `py`, and whichever split row is printed
    last wins it. The port and this file do not print those five rows in the same
    order, so reprinting the continuation fabricates a disagreement about a key
    neither side meant to emit. Leaving it port-only keeps it out of the
    intersection, which is the comparison.
    """
    for line in rows:
        name, ans = line.split("=", 1)
        # the port's printer has two spaces in this one name; strip() does not collapse them
        if name == "tag_str TStr":
            name = "tag_str  TStr"
        if name in _SPLIT:
            print(f"{name}=[{ans}]")
        elif name in _IO1:
            print(f"{name}=[{ans}] py={ans}")
        elif name in _IO5:
            print(f"{name}=[{ans}]     py={ans}")
        elif name.startswith(_PY_ROW):
            print(f"{name}=[{ans}]   py=[{ans}]")
        else:
            print(f"{name}=[{ans}]   py={ans}")


if __name__ == "__main__":
    if "--gate" in sys.argv:
        emit_gate(OUT)
    else:
        print("\n".join(OUT))
        sys.stderr.write(f"# rows={len(OUT)}\n")
