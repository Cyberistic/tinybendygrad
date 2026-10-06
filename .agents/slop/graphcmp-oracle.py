#!/usr/bin/env python3
"""graphcmp-oracle.py -- THE COVERAGE DENOMINATOR, TABULATED. Nothing here is typed.

Answers the question a verdict line cannot: for each `--graph`, how many NODES, how many
distinct OPS, how many distinct `arg` ATOM LETTERS, how many distinct SHAPE texts, and
which of the eight ledger markers are LIVE. `AGREE` on 18 nodes over 7 distinct ops with 6
atom letters is a different claim from `AGREE` on 2 nodes over 2 ops with 3 letters, and
the two must not be reported in the same way.

It emits BOTH sides and tabulates the union, so a port op or atom the py side never
produces shows up as a per-side difference rather than being absorbed into an AGREE.

IT RUNS ON graphcmp.py's OWN DEVICE, and prints which one on the first line. A coverage
denominator computed on a device no artifact records is a number nobody can re-derive, and
MEASURED the two are not interchangeable: the corpus is 313 py-side nodes on `NULL` and 312
on `CPU`, and `late` is `RECIPROCAL` (13 nodes) on one and `FDIV` (12) on the other.

    env -u PYTHONPATH LC_ALL=C .venv/bin/python .agents/slop/graphcmp-oracle.py
"""
from __future__ import annotations

import ast
import collections
import os
import pathlib
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import graphcmp as G  # noqa: E402

# THE WHOLE MARKERS, DERIVED FROM `graphcmp.py`'s OWN LEDGER. A LEDGER entry that is not an
# atom letter is a multi-character TOKEN, not a letter: `BAD` the port's arena bottom, `X!` a
# dead AxisType member, `?` the fold's absence. The LEDGER is the generator that DECLARES the
# marker vocabulary, so the set is asked of it by path -- never a second copy of the
# three-element tuple `graphcmp.py:2610` keeps in its own selfcheck, which is the exact fault
# `AGENTS.md` names. MEASURED before this: `atoms("BAD")` was `{B}`, so `--graph getaddr`
# reported `unmapped arg atom letters: B` and the census went rc=1 over a string the renderer
# emitted correctly.
WHOLE = tuple(m for m, _, _, _ in G.LEDGER if m not in set(G.ATOMS.values()))


def atoms(arg: str) -> set:
  """The ATOM LETTERS in an arg, from the grammar and NOT from any form's field layout, so a
  spelling change cannot quietly become a change to what counts as an atom. Three conditions,
  and the first versions had fewer and were visibly wrong on screen.
    * MEASURED, the first counted the SECOND character of every atom and the `)` of the
      `n()` empty-list spelling -- it reported `34DNPSbils` for a `ParamArg` and `)` for a
      `KernelInfo` -- so the letter sits where a VALUE starts: offset 0, or right after
      `( , : =`, and the `D` inside `sDefault` is not an atom;
    * the letter is a LETTER and is followed by alnum/underscore or by nothing, and the scan
      then SKIPS the rest of the token, so `i0` contributes `i` and `Df32` contributes `D`.
      That also stops `n()` contributing its `n` or its `)`: the tuple opener `n` is always
      followed by `(`, which is why `n(..)` needs no prefix table.
    * DEFECT 21 (2026-10-04, `--graph lin`): a token whose LAST character is followed by
      `=` is a FIELD NAME and not a value, and the two conditions above do not separate
      them. So the census counted `o` from `Opt(op=EOptOps.SPLIT,axis=i2,...)` and `a` from
      `axis`, and the coverage report then printed `an unmapped value: o` -- warning about
      an UNMAPPED ATOM over a string the differ had just rendered correctly. It is the same
      shape as defect 20 in this same file: correct content under a printing that is wrong,
      and found only by the widening that produced the corpus's first `Opt`.

      THE `=` IS AT THE END OF THE TOKEN (`op=`, not `=op`), so the test has to run AFTER
      the token is skipped. MEASURED: the first version tested `arg[i+1] != "="` at the
      token's FIRST character and changed nothing, because `arg[i+1]` is `p`. The assertion
      at the bottom of this file is what made that visible in one run instead of one
      reading.

  DEFECT 28 (2026-10-06, `--graph allred`) WAS A FORM-SPECIFIC RULE HERE AND IS DELETED. The
  ALLREDUCE device is a UNION whose two arms render differently -- a bare name `sCPU` and a
  tuple `n(sCPU,sCPU)` -- and the port once FLATTENED the tuple to `sCPU,CPU`, whose trailing
  `CPU` re-opened the offset-0 rule and leaked a `C`. `PAYLOAD_LAST_FIELD = ("al(",)"` hid that
  `C` by reading only the field's first letter; ADEV-1 abolished the flattened spelling, so the
  rule then turned the tuple opener `n` into an unmapped atom and became the defect itself.
  With no form-specific knowledge, `al(OADD,n(sCPU,sCPU))` reads `{a,O,s}` and the bare
  `al(OADD,CPU)` still reads a `C`; the bottom of this file asserts both."""
  out, i = set(), 0
  while i < len(arg):
    c = arg[i]
    if c.isalpha() and (i == 0 or arg[i - 1] in "(,:=") and (
        i + 1 == len(arg) or arg[i + 1].isalnum() or arg[i + 1] == "_"):
      j = i
      while j + 1 < len(arg) and (arg[j + 1].isalnum() or arg[j + 1] == "_"):
        j += 1
      if not (j + 1 < len(arg) and arg[j + 1] == "="):
        out.add(c)
      i = j
    i += 1
  return out


def census(lines: list[str]) -> dict:
  ops, res, shapes, depths, atom = set(), set(), set(), set(), set()
  per_op: collections.Counter = collections.Counter()
  for ln in lines:
    f = G.unchunks(ln)
    ops.add(f[1])
    per_op[f[1]] += 1
    shapes.add(f[3])
    depths.add(f[4])
    atom |= atoms(f[6])
    for m, fis, _, _ in G.LEDGER:
      if any(G.at_value(f[fi], m) for fi in fis):
        res.add(m)
  return {"nodes": len(lines), "ops": ops, "residual": res, "shapes": shapes,
          "depths": depths, "atoms": atom, "symdims": symdim_rows(lines),
          "devs": G.devnames(lines), "per_op": per_op}


def graphcmp_dev() -> str:
  """The device `graphcmp.py` ITSELF runs on, read out of its own `--dev` default.

  THE CENSUS AND THE GRAPH ARTIFACTS HAVE TO BE ABOUT THE SAME GRAPH, and one run had them
  about two. `checks/differ.py:47` puts `DEV=NULL` in the ENV every step gets at `:314`, and
  `graphcmp.py:2853` OVERWRITES `os.environ["DEV"]` with its own `--dev`, so the graph
  artifacts were CPU while the census was whatever the environment said. This function's
  predecessor was `os.environ.setdefault("DEV", "CPU")`, which cannot repair that:
  `setdefault` is a no-op EXACTLY when the caller set the variable, and `differ.py` always
  does. MEASURED, and it is not a rounding difference -- see the module docstring.

  AND THE BEND SIDE IGNORES `dev` WHATEVER IT IS HANDED. MEASURED: `emit_bend("NULL", g)`
  still reports `devnames() == {'sCPU'}`, because a device is the port's own arena tag 0
  (`uop/render.bend:363`) and there is nothing in `DEV` for it to read. So a census that
  asks the environment gets two sides on two devices, and passing the right string to
  `emit_bend` does not repair it -- which is why the device comes from `graphcmp.py` and why
  `main()` asserts the two sides' `devnames` AGREE instead of trusting the plumbing.

  READ FROM THE AST AND NOT COPIED: a third literal `CPU` in this file would recreate this
  exact defect as a silent drift the day `graphcmp.py`'s default moved, which is the failure
  this whole function exists to remove. A copy of a constant is a check against a stale file.
  """
  tree = ast.parse((G.SLOP / "graphcmp.py").read_text())
  for node in ast.walk(tree):
    if isinstance(node, ast.Call) and getattr(node.func, "attr", "") == "add_argument" \
        and node.args and getattr(node.args[0], "value", None) == "--dev":
      return ast.literal_eval(next(k.value for k in node.keywords if k.arg == "default"))
  raise SystemExit("graphcmp.py declares no --dev default, so the census cannot name the "
                   "device it ran on -- a denominator whose device is unnamed is unauditable")


def symdim_rows(lines: list[str]) -> list[str]:
  """The ids of the nodes whose `shape` column carries a symbolic dim. `symdims` counts
  over built `Node`s, which needs the whole differ; this reads the same `U` at a dim
  position straight off the wire so the census has no dependency on `build`."""
  return [G.unchunks(ln)[0][1:] for ln in lines
          if G.unchunks(ln)[3].startswith("(") and "U" in G.split_top(G.unchunks(ln)[3][1:-1])]


# THE DENOMINATOR, BY DISCOVERY RATHER THAN BY COUNT. `len(list(Ops)) == 77` is a true count
# of the ENUM and a false count of the OPERATIONS: the enum's own comment sections say which
# members are not graph nodes at all. So the section structure is PARSED out of the enum's
# source -- the same declaration the oracle already imports for its names -- and the
# complement is computed, never typed:
#   1 defines/special · 2 non op uops · 3 load/store · 4 math · 5 control flow/consts/custom
#   · 6 ops that don't exist in programs · 7 pattern compiler IR (used in upat.py)
# FROM `61 of 77` TO THREE ACTABLE NUMBERS. The old line folded two different failures into
# one: members that CANNOT be a program node however many graphs you write, and members that
# merely have no graph yet. Only the second is a coverage gap. A member is EXCLUDED from the
# program-op denominator when its section title or its own comment declares it not a rendered
# node -- one of the five markers below. The corpus is the SECOND witness and it only ever
# RESCUES: an op a graph reaches is demonstrably a program node, so NOOP, LINEAR and BINARY,
# which the same comments cover, stay in the denominator. NOTHING is added to the exclusion
# set by the corpus, so the unexercised count is not derived from the very table it reports.
#   MEASURED, DEV=CPU: 77 enum members -> 70 program ops; 7 excluded by construction
#   (REWRITE_ERROR PROGRAM SOURCE PYLITERAL CUSTOM CUSTOMI INS); 61 reached; 9 unexercised
#   (GETADDR WMMA THREEFRY MULACC STAGE MSELECT MSTACK CUSTOM_FUNCTION UNSHARD). 61 of 70 IS
#   the corrected figure; 61 of 77 is kept BESIDE it, not replaced, because it is the honest
#   count of the enum and the two answer different questions.
NON_NODE_MARKERS = ("aren't rendered", "renderer", "pattern compiler IR",
                    "output strings into codegen", "machine instruction")
SECTION_RE = re.compile(r"^\s*# \*\* (\d+) -- (.+?) \*\*\s*$")
ASSIGN_RE = re.compile(r"\b([A-Z][A-Z0-9_]*)\s*=\s*auto\(\)")
CLASS_RE = re.compile(r"^class Ops\(FastEnum\):")


def enum_sections(path: str) -> list[tuple[int, str, list[tuple[str, str]]]]:
  """The `Ops` class body, split by its own `# ** N -- title **` headers, each member paired
  with the comment block above it (or its trailing comment). Comments are a DECLARATION and
  this reads them instead of transcribing them; `main()` then checks the parse against the
  live `Ops` instead of trusting it. A blank line ends a comment block, and an assignment can
  hold several members (`BUFFER = auto(); ALLOC = auto()`), so the line is scanned for every
  `NAME = auto()` it carries."""
  lines = pathlib.Path(path).read_text().splitlines()
  start = next(i for i, l in enumerate(lines) if CLASS_RE.match(l))
  sections: list[tuple[int, str, list[tuple[str, str]]]] = []
  cur: tuple[int, str, list[tuple[str, str]]] | None = None
  pending: list[str] = []
  for l in lines[start + 1:]:
    if l and not l.startswith(" "):
      break                                              # end of the class body
    s = l.strip()
    m = SECTION_RE.match(l)
    if m:
      cur = (int(m.group(1)), m.group(2), [])
      sections.append(cur)
      pending = []
    elif s.startswith("#"):
      pending.append(s.lstrip("# ").strip())
    elif s == "":
      pending = []
    elif cur is not None:
      comment = s.split("#", 1)[1].strip() if "#" in s else " ".join(pending)
      cur[2].extend((name, comment) for name in ASSIGN_RE.findall(s))
      pending = []
  return sections


def program_op_split(sections, reached: set) -> dict:
  """The three numbers, from the parse plus the reached set. `by_construction` is the
  declared-non-node set MINUS anything a graph reached (a reached op is proof the comment
  is about rendering, not membership); `unexercised` is the rest of the program ops with no
  graph; `program` is the corrected denominator. Pure, so `main()` prints and asserts the
  same values it computes."""
  declared = {n for _, title, ops in sections for n, c in ops
              if any(m in f"{title} {c}" for m in NON_NODE_MARKERS)}
  by_construction = declared - reached
  program = {n for _, _, ops in sections for n, _ in ops} - by_construction
  return {"by_construction": by_construction, "program": program,
          "unexercised": program - reached}


def main() -> int:
  # ONE DEVICE, CHOSEN ONCE, EXPORTED TO BOTH SIDES, AND PRINTED. `os.environ["DEV"]` (not
  # `setdefault`) because `emit_py` runs in THIS process and the census must be about the
  # device it says it is about; the `dev=` argument is the same string, so `emit_bend` cannot
  # disagree by construction. `checks/differ.py:47` setting `DEV=NULL` no longer reaches here.
  #
  # AND THE EXPORT HAS TO HAPPEN BEFORE TINYGRAD EXISTS, WHICH IS AN ORDERING NOBODY CAN SEE.
  # MEASURED: `tinygrad.Device.DEFAULT` is resolved at IMPORT -- after `load_tinygrad()`,
  # `os.environ["DEV"] = "CPU"` changes nothing at all, the corpus stays 313 nodes on the
  # device that was in the environment when tinygrad was first imported, and the census prints
  # a device it is not running on. `graphcmp.py` imports no tinygrad at module scope (which is
  # why `differ.py` can import it for `corpus()`), so the order below is correct -- and a
  # correct order that only correctness depends on is an order a later edit can break in one
  # line. So it is REFUSED rather than assumed.
  if any(m == "tinygrad" or m.startswith("tinygrad.") for m in sys.modules):
    raise SystemExit("tinygrad is already imported, so `DEV` can no longer choose this census's "
                     "device: `Device.DEFAULT` is frozen at import. A census that prints one "
                     "device and runs on another is a number about a graph no artifact holds.")
  DEV = graphcmp_dev()
  os.environ["DEV"] = DEV
  G.load_tinygrad()
  G.COMM = G.commutative()
  import tinygrad
  print(f"# tree={tinygrad.__file__}")
  print(f"# DEV={DEV} -- graphcmp.py's own `--dev` default, exported to BOTH sides. Every count "
        f"below is about this device and about no other.")
  print(f"# {'graph':<10} {'nodes':>5} {'cnt':>4} {'ops':>4} {'arg-atoms':>9} "
        f"{'shapes':>6} {'depths':>6} {'sym':>5}  live-ledger")
  tot_nodes = 0
  tot_ops: set[str] = set()
  tot_atoms: set[str] = set()
  tot_comm: set[str] = set()
  tot_sym = 0
  tal: collections.Counter = collections.Counter()
  graphs_of: collections.Counter = collections.Counter()
  all_res: collections.Counter = collections.Counter()
  bad: list[str] = []
  for g in sorted(G.GRAPHS):
    py = census(G.emit_py(g, None))
    bd = census(G.emit_bend(DEV, g)[0])
    tot_nodes += py["nodes"]
    tot_ops |= py["ops"] | bd["ops"]
    tot_atoms |= py["atoms"] | bd["atoms"]
    tot_comm |= py["ops"] & G.COMM
    tot_sym += len(py["symdims"])
    # THE PRECONDITION `graphcmp.py` ALREADY HAS AND THIS FILE COULD NOT REACH. It lives in
    # `_dispatch` (:2958), which checks `pdev != bdev` and calls it "NOT WELL-POSED, and this
    # is NOT a verdict" -- and this file calls `emit_py` and `emit_bend` DIRECTLY, so the
    # guard sat on a path the guarded thing never takes. An ALLOC's device selects its `core`,
    # which propagates to every consumer, so a two-device census is a number about a graph no
    # artifact contains. It is a FAILURE and not a note: the only channel this file has is `bad`.
    if py["devs"] != bd["devs"]:
      bad.append(f"{g}: the two sides opened DIFFERENT devices -- py {sorted(py['devs'])} "
                 f"against bend {sorted(bd['devs'])} -- so this row's node/op/shape/atom "
                 f"counts are about two different graphs")
    tal.update(py["per_op"])
    graphs_of.update(py["ops"])
    for m in py["residual"] | bd["residual"]:
      all_res[m] += 1
    same = ("same" if py["ops"] == bd["ops"]
            else f"PY-BEND OPs DIFFER: {sorted(py['ops'] ^ bd['ops'])}")
    print(f"  {g:<10} {py['nodes']:>2}/{bd['nodes']:<2} {'ok' if py['nodes'] == bd['nodes'] else 'BAD':>4} "
          f"{len(py['ops']):>4} {''.join(sorted(py['atoms'])) or '-':>9} "
          f"{len(py['shapes']):>6} {len(py['depths']):>6} "
          f"{len(py['symdims']):>2}/{len(bd['symdims']):<2} "
          f"{','.join(sorted(py['residual'] | bd['residual'])) or '-'}  [{same}]")
  print(f"# TOTAL: {len(G.GRAPHS)} graphs, {tot_nodes} nodes per side, "
        f"{len(tot_ops)} distinct ops: {' '.join(sorted(tot_ops))}")
  print(f"# FIELDS COMPARED PER NODE: {len(G.WIRE)} on the wire, {len(G.FIELDS)} in the "
        f"equality decision ({', '.join(G.FIELDS)}); `id` is reporting-only by R1")
  comp = set(c[0] for c in G.COMPOSITE)
  unknown = tot_atoms - set(G.ATOMS.values()) - comp
  print(f"# COMPOSITE ARG FORMS SPELLED BY BOTH SIDES: {list(G.COMPOSITE)}")
  print(f"# DISTINCT ARG ATOM LETTERS REACHED: {''.join(sorted(tot_atoms))} "
      f"({len(tot_atoms)} distinct = {len(tot_atoms - comp)} atom letters + "
      f"{len(tot_atoms & comp)} composite-form prefixes; a letter that is NEITHER an atom "
      f"nor a composite prefix would be an unmapped value: {''.join(sorted(unknown)) or 'none'})")
  # DEFECT 21, ASSERTED so it cannot come back. `atoms()` counted the FIELD NAMES of a
  # dataclass arg -- `op` and `axis` of `Opt(...)` -- as atom letters, so the coverage
  # report warned about an unmapped value `o` over a string that is itself correct. An
  # assertion is the only thing that stops a PRINTING defect from being re-introduced by a
  # fixture change, and `selfcheck`'s `?`-ledger row is the precedent: measured, then
  # asserted to be able to fire.
  opt_atoms = atoms("Opt(op=EOptOps.SPLIT,axis=i2,arg=n(i0,XUPCAST))")
  if {"o", "a"} & opt_atoms:
    bad.append(f"atoms() counts a dataclass FIELD NAME as an atom letter: {sorted(opt_atoms)}")
  if "E" not in opt_atoms:
    bad.append("atoms() lost the ENUM atom `E` after the field-name fix")
  if unknown:
    bad.append(f"unmapped arg atom letters: {''.join(sorted(unknown))}")
  # THE DEVICE SPELLING, ASSERTED BOTH WAYS, because a scan that only ever fires has not been
  # shown to still bite. `al(`'s second field is a device that is EITHER a bare name (`sCPU`)
  # OR a tuple spelled field-wise (`n(sCPU,sCPU)`); the census must read both without inventing
  # an atom. The nested form's `n` is the tuple opener, followed by `(`, so the scan never
  # counts it -- which is why DEFECT 28's form-specific `PAYLOAD_LAST_FIELD` is gone -- and the
  # bare name's `C` still IS one atom letter. The FLATTENED `al(OADD,sCPU,CPU)` that ADEV-1
  # abolished is deliberately NOT asserted here: it is exactly a leaked `C`, and the
  # corpus-wide `unknown` check above is what refuses it.
  if atoms("al(OADD,n(sCPU,sCPU))") != {"a", "O", "s"}:
    bad.append(f"the field-wise device tuple `al(OADD,n(sCPU,sCPU))` does not read as three "
               f"letters: {sorted(atoms('al(OADD,n(sCPU,sCPU))'))}")
  if "n" in atoms("al(OADD,n(sCPU,sCPU))"):
    bad.append("the tuple opener `n` is being counted as an atom, so the census accepts a "
               "spelling the renderers do not emit")
  if atoms("al(OADD,n(sCPU,sCPU,sMETAL,sMETAL))") != {"a", "O", "s"}:
    bad.append(f"a 4-element device tuple does not behave as the 2-element one: "
               f"{sorted(atoms('al(OADD,n(sCPU,sCPU,sMETAL,sMETAL))'))}")
  if "C" not in atoms("al(OADD,CPU)"):
    bad.append("a BARE device name (no `s` prefix) is no longer an unmapped atom, so the "
               "scan has stopped looking at real device names")
  print(f"# LEDGER MARKERS LIVE ON AT LEAST ONE GRAPH: "
        f"{dict(sorted(all_res.items())) or 'none'} of {len(G.LEDGER)} markers")
  print("#   ^ SORTED, and that is DEFECT 20 (2026-10-04, found by the two-run byte check "
        "and by nothing else). `all_res` is a `Counter` whose insertion order is the order "
        "the markers were first seen, and it is fed by `py['residual'] | bd['residual']` -- "
        "a SET UNION, whose iteration order over STRINGS follows the per-process string hash "
        "and is therefore randomized by `PYTHONHASHSEED`. MEASURED: three consecutive runs "
        "of this oracle gave three answers, "
        "`{'y': 1, 'z': 1, 'q': 1, 'E': 1, '?': 2}` against "
        "`{'y': 1, 'z': 1, 'E': 1, 'q': 1, '?': 2}` against the first again, and the "
        "two-run sha256 check over `runs/graphcmp/D` caught it on `D0-coverage-census.txt` "
        "as the ONLY differing file out of 158.\n"
        "#   It is the exact class the brief names: a COUNT that is right and an ORDER that "
        "is not, printed where a reader will read it as one line of fact. That is why 157 of "
        "158 files were stable and this one was not.\n"
        "#   AND THE CLASS HAD A SECOND MEMBER IN THIS FILE, WHICH THE PARAGRAPH ABOVE USED "
        "TO\n"
        "#   DENY: 'Every OTHER iteration of a set in this file is already `sorted(...)`'. That "
        "sentence was\n"
        "#   FALSE -- the `PY-BEND OPs DIFFER` row printed a SET LITERAL, `{py['ops'] ^ "
        "bd['ops']}` -- so the\n"
        "#   sort and the correction are in ONE edit, because a comment that has stopped "
        "describing the code\n"
        "#   is a pin that has stopped pinning. MEASURED, with no `bend` at all: three seeds "
        "gave\n"
        "#   `{'PERMUTE','RANGE','REDUCE','COPY','ALLREDUCE','MUL'}`, "
        "`{'RANGE','COPY','MUL','REDUCE','PERMUTE','ALLREDUCE'}\n"
        "#   and `{'MUL','COPY','ALLREDUCE','PERMUTE','REDUCE','RANGE'}` -- THREE renderings "
        "of ONE fact, and a\n"
        "#   `repro` lane that reported `D0-coverage-census.txt: 2 runs DIFFER` on 1 of 196.\n"
        "#   WHY SORTING AND NOT PINNING A SEED: a PIN IS A SEED AND A SORT IS A LAW. A seed "
        "fixes the order on\n"
        "#   THIS interpreter and buys nothing on the next one, while the claim being "
        "protected -- 'the port and\n"
        "#   CPython disagree' -- must survive a Python upgrade. An oracle whose set print "
        "follows the hash is a lane\n"
        "#   that can never be green, and no amount of correctness in the port makes it so.")
  print(f"# LEDGER MARKERS NEVER LIVE ON ANY GRAPH: "
        f"{[m for m, _, _, _ in G.LEDGER if m not in all_res] or 'none'}")
  print(f"# COMMUTATIVE OPS (read from CPython): {sorted(G.COMM)}")
  print(f"# COMMUTATIVE OPS REACHED BY A NODE: {len(tot_comm)}/{len(G.COMM)} "
        f"{sorted(tot_comm)}; NOT REACHED {sorted(G.COMM - tot_comm)} "
        f"(--equiv is MEASURED on {len(tot_comm)} of {len(G.COMM)})")
  print(f"# SYMBOLIC-DIM NODES: {tot_sym} of {tot_nodes} py-side nodes carry a `U` dim "
        f"(MEASURED off the shape column of every graph above)")
  print(f"# FIELD-RECORDS PER SIDE: {tot_nodes} nodes x {len(G.FIELDS)} compared fields = "
        f"{tot_nodes * len(G.FIELDS)}")
  print("# PER-OP NODE COUNTS ACROSS THE CORPUS -- the denominator for every op claim:")
  print("#   " + "  ".join(f"{op} {tal[op]}/{graphs_of[op]}" for op in sorted(tal))
          + "   (nodes/graphs)")
  # THE DENOMINATOR, SPLIT. The old line `NOT REACHED (16 of 77)` is kept -- it is the
  # honest count of the ENUM -- and the two numbers a reader can act on are printed beside
  # it: the members no graph could ever contain, and the members a graph has not contained
  # YET. See `NON_NODE_MARKERS` for the exclusion rule and why the corpus only rescues.
  ops_path = sys.modules[G.Ops.__module__].__file__
  sections = enum_sections(ops_path)
  known_ops = {o.name for o in G.Ops}
  split = program_op_split(sections, set(tal))
  by_construction, program, unexercised = (split["by_construction"], split["program"],
                                           split["unexercised"])
  print("# OPS PER ENUM SECTION (parsed from " + ops_path + "): "
        + "; ".join(f"{n} {t}: {len(ops)}" for n, t, ops in sections))
  print(f"# NOT REACHED ({len(known_ops) - len(tal)} of {len(known_ops)} ENUM MEMBERS): "
        + " ".join(o.name for o in G.Ops if o.name not in tal))
  print(f"#   OF WHICH {len(by_construction)} CANNOT APPEAR IN A PROGRAM GRAPH AT ALL "
        f"(by construction): " + " ".join(sorted(by_construction)))
  print(f"#   AND {len(unexercised)} ARE PROGRAM OPS NO GRAPH DRIVES YET (unexercised): "
        + " ".join(sorted(unexercised)))
  print(f"# DENOMINATOR: {len(known_ops)} enum members -> {len(program)} PROGRAM OPS "
        f"({len(by_construction)} excluded by the enum's own markers: "
        + ", ".join(NON_NODE_MARKERS) + ")")
  print(f"# COVERAGE: {len(tal)} of {len(program)} program ops === {len(tal)} of "
        f"{len(known_ops)} enum members (the denominators answer different questions)")
  # THE SPLIT, ASSERTED. The parse is checked against the live `Ops` rather than trusted,
  # and the three-way partition is checked to be total and disjoint, so a future enum edit
  # that a comment does not describe fails HERE instead of printing a smaller denominator
  # over a corpus that did not change.
  parsed = [n for _, _, ops in sections for n, _ in ops]
  if sorted(parsed) != sorted(known_ops):
    bad.append(f"the enum parse and the live Ops disagree: {len(parsed)} parsed against "
               f"{len(known_ops)} members; symmetric difference "
               f"{sorted(set(parsed) ^ known_ops)}")
  if by_construction & set(tal):
    bad.append(f"a graph reached an op the enum calls a non-node: "
               f"{sorted(by_construction & set(tal))} -- the exclusion rule is wrong")
  if by_construction & program or (len(program) + len(by_construction) != len(known_ops)):
    bad.append("the program-op partition is not total and disjoint: "
               f"{len(program)} + {len(by_construction)} != {len(known_ops)}")
  if len(by_construction) + len(unexercised) != len(known_ops) - len(tal):
    bad.append("the NOT-REACHED split does not sum: "
               f"{len(by_construction)} by-construction + {len(unexercised)} unexercised "
               f"!= {len(known_ops) - len(tal)} not reached")
  # THE VOCABULARY OF THE COVERAGE NUMBER, ASSERTED. `tot_ops` is a `set[str]` of
  # whatever `unchunks(ln)[1]` yields, from BOTH sides, so an op name that is not a
  # member of `Ops` used to be counted as reached: MEASURED, a well-formed wire line
  # naming `INVENTED` took the census from 34 to 35 and this SELFCHECK stayed OK, rc=0.
  # "N of 77 ops" therefore could not tell you that the 77 were the vocabulary at all --
  # a name that is in neither `Ops` nor reality moves the numerator and nothing else.
  # Measured, not assumed: every name in the corpus IS an `Ops` member today, so this
  # is a guard on the number's own meaning, and it is planted on every run below.
  unknown_ops = sorted(tot_ops - known_ops)
  if unknown_ops:
    bad.append(f"the op census counted {len(unknown_ops)} name(s) that are NOT "
               f"members of Ops, so '{len(tot_ops)} distinct ops' is not a count over "
               f"the {len(known_ops)}-op vocabulary: {unknown_ops}")
  print(f"# OP NAMES ALL IN Ops: {len(tot_ops) - len(unknown_ops)}/{len(tot_ops)}"
        + (f"   UNKNOWN: {unknown_ops}" if unknown_ops else "   (the census's "
           "vocabulary is verified against Ops, not assumed)"))
  print("# ORACLE SELFCHECK: " + ("OK" if not bad else "FAIL"))
  for b in bad:
    print("#   " + b)
  return 0 if not bad else 1


if __name__ == "__main__":
  sys.exit(main())