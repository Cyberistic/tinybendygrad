#!/usr/bin/env python3
"""eq-census2.py -- RE-CENSUS of the `=`-bearing row-name class, FROM DATA, over EVERY lane.

    .venv/bin/python .agents/slop/eq/eq-census2.py             # the census over every cached lane
    .venv/bin/python .agents/slop/eq/eq-census2.py --names      # every offending NAME, per lane
    .venv/bin/python .agents/slop/eq/eq-census2.py --one FILE [FILE...]

THE QUESTION. `rebase-gate.py:row()` splits a row line at its FIRST `=` and keeps the head as the
row NAME. So a name carrying one `=` does not have ONE name -- it has one name per reader -- and
the set of COMPARABLE rows becomes a property of the reader rather than of the tree. MEASURED on
`renderer/cstyle.bend` before its rename: 8 names, 8 rows unaddressable on BOTH lanes, under
`AGREE` with `disagree=[]`.

WHAT THIS DOES DIFFERENTLY FROM `name-census.py`, AND WHY THE DIFFERENCE IS THE WHOLE POINT.

  (a) THE BOUNDARY IS LOCATED STRUCTURALLY, NOT BY A SUBSTRING SEARCH.  The writer's boundary is
      the FIRST depth-0 `=` whose REMAINDER, after stripping spaces, begins with `[` -- because a
      bracketed value is what the writer emits.  `name-census.py` searched for `" = "` anywhere in
      the line and found it INSIDE render's VALUE (`ast = UOp.const(3)`), then reported
      `pyrender const=[ast` as a "name".  Its own header records the trap at
      `name-census.py:205-212` and it still shipped 31 false positives on
      `uop/render.bend`'s ORACLE lane and 0 on its PORT lane -- the WRONG SIDE of a two-sided
      lane, because the port prints `nm + " = ["` (render.bend:2148) and the oracle prints
      `nm + "=["`.  So its 31 are an artefact and a rename driven by them is driven by nothing.

  (b) A NAME MAY CONTAIN `[` AND `]`, so bracket depth is tracked over the SUFFIX AFTER the
      boundary, never over the whole line.  `renderer/llvmir.bend` prints
      `br2 load vol=False f32 [0] = [...]`: a name with brackets in it, which a whole-line depth
      scan reads as an unclosed value.

  (c) A PHYSICAL LINE THAT STARTS INSIDE A VALUE IS A CONTINUATION, not a row.  `render.bend`'s
      `py_row` (render.bend:2148) concatenates `pyrender(...)` and `py`, both of which contain
      `\\n`, so one logical row is 2-4 physical lines.  This is a DIFFERENT defect with the same
      arithmetic as an `=` in a name -- a row nothing can address -- and no separator rename can
      fix it.  It is counted apart on every run, with its own line numbers.

THE CLASS, STATED SO IT CAN BE FALSIFIED.  A name is reader-dependent iff TWO things hold: the
writer's boundary is NOT the first `=` on the line (otherwise the writer cannot express `=` in a
name at all -- structural immunity, not a pass), AND the name field before that boundary contains
another `=`.  Both are computed, and the immunity case is printed with its denominator so "0" can
be read as a fact about the writer rather than as a detector that found nothing to match.

THE METHOD'S OWN CONTROL, PRINTED EVERY RUN.  A lane whose producer emits no newline inside a
value must return ZERO continuations.  If the tracker returns any on such a lane, the TRACKER is
wrong -- so the control is available without a second implementation, which is the only kind of
control this tree has ever had for a reader.

TWO THINGS A COUNT MUST CARRY.  Its DENOMINATOR, because "31 `=`-names" and "31 of 124" are
different claims; and its LOAD, because `rows()` keeps the LAST row on a key, so a key holding n
rows costs n-1 MEASUREMENTS and leaves 1 merely MISNAMED.  The two are reported apart, and a
disagreement count is not a coverage statement: every one of these lanes can print `disagree=[]`.
"""
import argparse, importlib.util, json, pathlib, sys
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
CACHE = REPO / ".agents/slop/name-census-lanes"


def load(name):
  """`rebase-gate.py` has a `-`, so it does not import by name.  ONE loader, used by every row
  reader here: a second reader is how this project got a two-round contradiction between gates."""
  spec = importlib.util.spec_from_file_location(name, str(HERE.parent / f"{name}.py"))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


RG = load("rebase-gate")
ROW, ROWS = RG.row, RG.rows
DEPTH = {"[": 1, "]": -1}
PY_TAIL = RG.PY_TAIL     # `]   py=[`, IMPORTED, never re-spelled: it is the column `row()` splits
PYCOL = PY_TAIL[:len("]   py=")]   # the SIGNATURE, which is the column's HEAD


def depth0_eq(line):
  """[index] of every `=` at bracket depth 0.  Depth, not position, because a name may contain
  brackets -- `llvmir` prints `br2 load vol=False f32 [0] = [...]`."""
  out, d = [], 0
  for i, c in enumerate(line):
    if c == "=" and d == 0:
      out.append(i)
    else:
      d += DEPTH.get(c, 0)
  return out


def row_open_at_depth0(line):
  """The index of the `]   py=` that CLOSES A VALUE, or None.  THE F2 SIGNATURE, and a signature
  rather than a guess: that column is how `row()` separates a producer's own answer from its
  transcription, so a lane that prints it is a lane whose values are bracketed and whose boundary
  can be a bare `=`.

  ⚠ TWO PLACES THIS IS EASY TO GET WRONG, AND BOTH READ AS A CLEAN ZERO.
  (1) THE DEPTH TEST IS `== 1` AT THE `]`, NOT `== 0`.  The `]` that closes the value is itself at
      depth 1 -- it is what brings the depth back to zero -- so testing depth 0 there finds nothing
      on any F2 lane in this tree and classifies every lane F1.
  (2) THE SIGNATURE IS `]   py=`, NOT `]   py=[`.  107 of render's own rows carry a BARE literal
      there (`sint_show 0 = [0]   py=0`, `prec_of MUL = [1]   py=1`), so requiring the `[` scores
      that lane 22/129 and a 50% rule then calls it ambiguous.
  A detector that finds no instances of the class it was built for reports a number, and the
  number is 0."""
  d = 0
  for i in range(len(line)):
    if d == 1 and line.startswith(PYCOL, i):
      return i
    d += DEPTH.get(line[i], 0)
  return None


def lane_shape(lines):
  """`F2` / `F1` / `F3` for a WHOLE lane, plus the share it was decided on.

  ⚠ THE SHAPE IS A PROPERTY OF THE LANE, NOT OF THE ROW, AND DECIDING IT PER ROW IS A BUG I MADE
  TWICE.  `engine/jit.bend`'s row is

      msg_dtype_mismatch=args mismatch in JIT: ...expected_input_info=[(UOp(...)] != expected...

  and `= [` occurs at depth 0 TWICE on it -- once in the producer's own boundary, once INSIDE the
  producer's own value, in `] != expected_input_info=[`.  No local rule separates those: both are a
  depth-0 `=` followed by `[`, both balance, both are preceded by a space, so a first attempt
  (bracketed remainder) and a second (spaced) each picked the `=` inside the value and reported
  three `=`-names that DO NOT EXIST.  What separates them is that this lane never prints the
  `py=` column and every F2 lane in this tree does, so the shape is read off the LANE.

  The share is returned and PRINTED for every lane, because a majority rule that can be wrong is
  only useful if the reader can see how close it came."""
  n2 = sum(1 for l in lines if "=" in l and row_open_at_depth0(l) is not None)
  n = sum(1 for l in lines if "=" in l)
  if not n:
    return "F3", n2, n
  if n2 == 0:
    return "F1", n2, n
  return ("F2" if 2 * n2 >= n else "F1"), n2, n


def boundary(line, shape):
  """(index of the writer's `=`, kind) for one row line, or (None, why).

  F2  the FIRST depth-0 `=` whose remainder begins with `[`.  The name is everything before it and
      MAY contain `=`, spaces and brackets -- the whole population in which the class can exist.
  F1  the FIRST `=`: the producer glued its value on, so a name cannot contain one.  STRUCTURAL
      IMMUNITY, reported as such and not as a pass.  The `=` in a F1 "name-looking prefix" is in
      the VALUE (`msg_dtype_mismatch=args mismatch in JIT: ...`).
  F3  no `=` anywhere: `row()` falls back to two spaces and a ONE-TOKEN head.
  AMBIGUOUS  refused, with the number of candidates, rather than resolved."""
  if "=" not in line:
    return None, "F3: no `=` on the line"
  eqs = depth0_eq(line)
  if shape == "F1":
    return eqs[0], "F1"
  # THE `=` INSIDE `]   py=` IS A DEPTH-0 `=` FOLLOWED BY `[`, and it is the COLUMN's boundary, not
  # the row's.  ⚠ Counting it made every F2 row in this tree AMBIGUOUS with two candidates and the
  # census read 0 F2 rows -- the same tautological zero by another route, and one that looks like
  # a green tree.  The row's boundary is the one BEFORE the marker.
  mk = row_open_at_depth0(line)
  cands = [i for i in eqs if line[i + 1:].lstrip(" ").startswith("[")
           and (mk is None or i < mk)]
  if not cands:
    return eqs[0], "F1 on an F2-shaped lane -- no bracketed `=` before the `py=` column"
  if len(cands) > 1:
    return None, f"AMBIGUOUS: {len(cands)} depth-0 `= [` candidates at {cands[:4]}"
  return cands[0], "F2"


def scan(text):
  """[(lineno, kind, name, why)] for every non-blank physical line.

  `kind` is `row`, `continuation`, `no-boundary` or `end-unbalanced`.  Depth is accumulated over
  the SUFFIX AFTER each row's boundary and carried across physical lines, which is what tells a
  continuation from a row without asking any producer what it meant."""
  src = text.splitlines()
  # PASS 1: which physical lines are CONTINUATIONS.  This pass counts brackets over the WHOLE line
  # and carries the depth forward, and it must not know anything about the boundary -- otherwise the
  # lane's shape would be decided by a rule that already assumed a shape.  A name may contain
  # BALANCED brackets (`llvmir`'s `br2 load vol=False f32 [0]`) and those net to zero, which is
  # why a whole-line count is right; an UNBALANCED bracket in a name would be a finding, and the
  # TRACKER'S CONTROL (73 of 78 lane texts report zero continuations, and every lane whose producer
  # emits no newline inside a value must be among them) is what would catch it.
  cont, depth, opened = set(), 0, None
  for n_, line in enumerate(src, 1):
    if not line.strip():
      continue
    if depth > 0:
      cont.add(n_)
      for c in line:
        depth += DEPTH.get(c, 0)
      if depth <= 0:
        opened = None
      continue
    for c in line:
      depth += DEPTH.get(c, 0)
    opened = n_ if depth > 0 else None
  shape, n2, n = lane_shape([l for i, l in enumerate(src, 1) if i not in cont and "=" in l])
  # PASS 2, and it exists because of ONE HAND-WRITTEN WRAP IN `render.bend`.  `render.bend:2809-2819`
  # prints five rows as TWO `IO.print`s each, because the `arg_repr` values are long enough that
  # the author put the `py=` column on its own line:
  #     IO.print("arg_repr AKern   = [" ++ arg_repr(...) ++ "]")
  #     IO.print("                     py=KernelInfo(name='test', ...)")
  # Pass 1 cannot see that: both physical lines are bracket-balanced.  So on an F2 lane a line
  # whose FIRST non-space text is `py=` is a continuation of the previous row's `py=` column --
  # on an F2 lane a row's own name always precedes its ` = [`, so a line can only START with the
  # column.  ⚠ MEASURED WITHOUT IT: the port lane's loss read 43 with 39 attributed, and the four
  # missing rows were exactly these, read as a row named `py`.  The oracle does not wrap, so the
  # lane pair also disagreed about a row name -- a `ghost` the value comparison never sees.
  if shape == "F2":
    for n_, line in enumerate(src, 1):
      if line.lstrip().startswith("py=") and n_ not in cont:
        cont.add(n_)
  out, opened = [], None
  for n_, line in enumerate(src, 1):
    if not line.strip():
      continue
    if n_ in cont:
      out.append((n_, "continuation", None,
                  f"inside the value of the row opened at L{opened}"))
      continue
    i, kind = boundary(line, shape)
    if i is None:
      out.append((n_, "no-boundary", None, kind))
      continue
    out.append((n_, kind, line[:i].strip(), "row"))
  if depth != 0:
    out.append((len(src), "end-unbalanced", None,
                f"LANE ENDS {depth:+d} bracket(s) UNCLOSED over L{opened} -- either a producer "
                f"prints an unbalanced value or the tracker is wrong; both are findings"))
  return out, shape, n2, n


def key_collision(names):
  """Σ(rows on a key − 1) over `names`, i.e. how many rows a reader cannot address.  COUNTED FROM
  THE LIST, so a name printed twice costs one -- the census's own `lost` used a `set()` and read
  0 on the one lane in this tree that has a duplicate."""
  return sum(n - 1 for n in Counter(names).values() if n > 1)


def measure(text, label=""):
  """The figures.  Every count carries its denominator; the two kinds of lost row are counted
  apart because they have different fixes and different owners."""
  src = text.splitlines()
  sc, shape, n2, n = scan(text)      # ONE shape decision, made inside `scan` over the rows it found
  rows = [(n_, nm) for n_, k, nm, _ in sc if k in ("F1", "F2")]
  cont = [(n, w) for n, k, _, w in sc if k == "continuation"]
  nob = [(n, w) for n, k, _, w in sc if k == "no-boundary"]
  unbal = [(n, w) for n, k, _, w in sc if k == "end-unbalanced"]
  kinds = Counter(k for _, k, _, _ in sc)
  shipped = Counter(ROW(l)[0] for l in src if ROW(l))
  refuse = [n_ for n_, _ in rows if ROW(src[n_ - 1]) is None]
  # MY name vs the shipped reader's name for the SAME physical row.  A disagreement IS the class.
  cut = {nm: ROW(src[n_ - 1])[0] for n_, nm in rows if ROW(src[n_ - 1]) is not None}
  differ = sorted(nm for nm, s in cut.items() if nm != s)
  eq = sorted(nm for nm in differ if "=" in nm)
  # A key fed >1 row: two DIFFERENT physical names is the reshape class, ONE name twice is a
  # duplicate and NO `=` is involved in it.
  # A key fed >1 row: two DIFFERENT physical names is the reshape class, ONE name twice is a
  # duplicate and NO `=` is involved in it.  ⚠ THE LIST KEEPS MULTIPLICITY.  Deduplicating here is
  # the mistake `llvmir-nameshape-control.md` §3 records against the census itself -- a set has
  # already overwritten the duplicate, so the one lane in this tree that HAS one printed `none`.
  # Counted from the LINES it is 1.  So: `by_key` is a list, and `lost` is Σ(n-1) over KEYS.
  behind = {}
  for n_, nm in rows:
    r = ROW(src[n_ - 1])
    if r is not None:
      behind.setdefault(nm, []).append(r[0])
  by_key = {}
  for nm, ks in behind.items():
    # ⚠ `extend([nm]*len(ks))`, NOT `append(nm)`: `behind[nm]` holds ONE ENTRY PER PHYSICAL ROW,
    # so a name printed twice must land on its key twice or the duplicate is invisible -- which is
    # what this line got wrong first, and the reconciliation line caught it.
    by_key.setdefault(ks[0], []).extend([nm] * len(ks))
  collide = {k: v for k, v in by_key.items() if len(v) > 1}
  reshape = {k: v for k, v in collide.items() if len(set(v)) > 1}
  dupes = {k: v for k, v in collide.items() if len(set(v)) == 1}   # ⚠ keeps MULTIPLICITY: a set
  # here read 0 for the one duplicate in this tree, twice, because both dedups above had already
  # erased it.  `lost` is Σ(rows on a key − 1), and it must reconcile with `phys - shipped_names`.
  lr = sum(len(v) - 1 for v in reshape.values())
  ld = sum(len(v) - 1 for v in dupes.values())
  # THE READER'S OWN TOTAL, over the lines `row()` ACCEPTS -- which includes continuation lines,
  # because it cannot tell them from rows either.  That inclusion is the point: the loss is a
  # property of the reader, so it is measured where the reader lives and attributed afterwards.
  ck = key_collision([ROW(l)[0] for l in src if ROW(l) is not None])
  # THE ATTRIBUTION, per KEY and never per line: a key holding n accepted lines costs n−1, and it
  # costs n−1 to exactly ONE cause.  A key touched by a continuation line is charged to the
  # continuation -- the earlier row on it was the real row the continuation truncated -- and only
  # then, over the REAL rows left, to a reshape or a duplicate.  ⚠ The first version counted
  # continuation LINES rather than continuation COLLISIONS and read 127 on `engine_jit`, whose
  # 127 continuation lines each land on a key of their OWN (137 accepted lines, 137 keys, total
  # loss 0).  A count of lines is not a count of losses; the reconciliation is what caught it.
  cont_keys = {ROW(src[n_ - 1])[0] for n_, _ in cont if ROW(src[n_ - 1]) is not None}
  allk = Counter(ROW(l)[0] for l in src if ROW(l) is not None)
  lc = sum(allk[k] - 1 for k in cont_keys if allk[k] > 1)
  return {"label": label, "phys": len(rows), "F1": kinds["F1"], "F2": kinds["F2"],
          "lane_shape": shape, "lane_n2": n2, "lane_n": n,
          "lost_reader": ck, "lost_cont": lc,
          "F3": kinds["F3"], "cont": len(cont), "nob": nob, "unbal": unbal,
          "names": len(behind), "shipped_names": len(shipped), "refuse": refuse,
          "accepted": sum(1 for l in src if ROW(l) is not None),
          "eq": eq, "eq_n": len(eq), "differ": differ, "collide": collide,
          "reshape": reshape, "dupes": dupes, "lost_reshape": lr, "lost_dupe": ld, "lost": lr + ld,
          "cont_lines": cont, "immune": kinds["F1"] + kinds["F3"]}


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--names", action="store_true")
  ap.add_argument("--one", nargs="+")
  a = ap.parse_args()
  texts = ([(p, pathlib.Path(p).read_text()) for p in a.one] if a.one
           else [(p.name, p.read_text()) for p in sorted(CACHE.glob("*.txt"))])
  ms = [measure(t, lb) for lb, t in texts]
  print(f"{'lane':<50} {'phys':>5} {'shape':>5} {'py=':>7} {'F1':>5} {'F2':>5} {'cont':>5} "
        f"{'names':>6} {'ship':>6} {'`=`':>4} {'LOST':>5} {'reshp':>6} {'dupe':>5} {'contL':>6}")
  for m in ms:
    if m["eq_n"] or m["lost"] or m["cont"] or m["nob"] or m["unbal"] or m["F3"]:
      print(f"{m['label']:<50} {m['phys']:5} {m['lane_shape']:>5} {m['lane_n2']:>7} {m['F1']:5} "
            f"{m['F2']:5} {m['cont']:5} {m['names']:6} {m['shipped_names']:6} {m['eq_n']:4} "
            f"{m['lost_reader']:5} {m['lost_reshape']:6} {m['lost_dupe']:5} {m['lost_cont']:6}")
  g = lambda k: sum(m[k] for m in ms)
  P, F1, F2, F3, C = g("phys"), g("F1"), g("F2"), g("F3"), g("cont")
  E, LR, LD, N, S = g("eq_n"), g("lost_reshape"), g("lost_dupe"), g("names"), g("shipped_names")
  A = sum(sum(ROW(l) is not None and 1 or 0 for l in t.splitlines()) for _, t in texts)
  print()
  print(f"TOTAL over {len(ms)} lane texts of {len({m['label'].split('.bend')[0] for m in ms})} "
        f"ports")
  print(f"  ROWS the writer emitted (a line with a boundary): {P}")
  print(f"  LANE SHAPE, which is what decides whether the class CAN exist:")
  print(f"      F1 {F1}  the writer glued the value on, so the FIRST `=` IS the boundary and a "
        f"name cannot contain one -- STRUCTURALLY IMMUNE ({100.0*F1/max(1,P):.1f}% of rows)")
  print(f"      F2 {F2}  the boundary is ` = [` or `=[`, so a name MAY contain `=` -- the only "
        f"population in which the class exists ({100.0*F2/max(1,P):.1f}% of rows)")
  print(f"      F3 {F3}  no `=` at all; `row()` needs two spaces and a ONE-TOKEN head")
  print(f"  ROW NAMES CONTAINING `=`: {E} of the {F2} F2 rows that can carry one "
        f"({100.0*E/max(1,F2):.2f}%)")
  print(f"  NAMES AS A PRODUCER PRINTED THEM: {N}   LINES `row()` ACCEPTS: {A}   DISTINCT KEYS "
        f"`rows()` PRODUCES: {S}   so a name can address {S} of {A} lines "
        f"({100.0*S/max(1,A):.1f}%)")
  print(f"  CONTINUATION lines `row()` reads as rows of their own: {C} -- a physical line inside "
        f"a bracketed value. A DIFFERENT defect with the same arithmetic; no separator rename "
        f"touches it")
  print(f"  and, over MY rows only (continuations excluded), {LR} to a reshape (an `=` in a name) "
        f"+ {LD} to a duplicate name (one name printed twice, NO `=` involved)")
  # THE RECONCILIATION, IN THE READER'S OWN ARITHMETIC, and it can fail.  `rows()` loses a row
  # whenever two lines it ACCEPTS land on one key, whatever produced either of them.  So the loss
  # is computed over the accepted lines alone, and then ATTRIBUTED by cause -- a continuation line,
  # an `=` in a name, or a name printed twice -- and the attribution must sum to the total.  The
  # first version computed the total over MY rows and the causes over the reader's, and they read
  # 302 against 429 with no explanation.  A split that does not reconcile is not a census.
  tot = g("lost_reader")
  att = g("lost_cont") + LR + LD
  print(f"  ROWS `row()` ACCEPTS THAT NO NAME CAN ADDRESS: {tot} = (accepted {A} − distinct keys "
        f"{S})")
  print(f"      {g('lost_cont'):4} a CONTINUATION line landed on a key another line already held "
        f"(a multi-line value; NO `=` involved)")
  print(f"      {LR:4} an `=` in a NAME put two differently-named rows on one key (THE CLASS)")
  print(f"      {LD:4} one NAME printed twice (NO `=` involved, and no separator change fixes it)")
  print(f"      attribution {g('lost_cont')} + {LR} + {LD} = {att} against a measured total of "
        f"{tot}: {'RECONCILES' if att == tot else 'DOES NOT RECONCILE -- the split is NOT a census'}")
  if att != tot:
    for m in ms:
      if m["lost_reader"] != m["lost_cont"] + m["lost_reshape"] + m["lost_dupe"]:
        print(f"      {m['label']}: total {m['lost_reader']} vs attributed "
              f"{m['lost_cont']}+{m['lost_reshape']}+{m['lost_dupe']} over {m['accepted']} accepted "
              f"lines and {m['shipped_names']} keys")
  multi = [m for m in ms if m["cont"]]
  print(f"  THE TRACKER'S CONTROL: {len(multi)}/{len(ms)} texts report a continuation and "
        f"{len(ms)-len(multi)}/{len(ms)} report none. The {len(multi)} are "
        f"{sorted(m['label'] for m in multi)}")
  for m in ms:
    if m["nob"]:
      print(f"  !! {m['label']}: {len(m['nob'])} line(s) the writer's boundary is not on: "
            f"{m['nob'][:2]}")
    if m["unbal"]:
      print(f"  !! {m['label']}: {m['unbal'][0][1]}")
  if a.names:
    print()
    for m in sorted(ms, key=lambda r: (-r["eq_n"], -r["lost"], r["label"])):
      if not (m["eq_n"] or m["lost"] or m["cont"]):
        continue
      print(f"{m['label']}  rows={m['phys']} F1={m['F1']} F2={m['F2']} F3={m['F3']} "
            f"cont={m['cont']} names={m['names']} eq={m['eq_n']} LOST={m['lost']} "
            f"(reshape {m['lost_reshape']}, dupe {m['lost_dupe']})")
      for n in m["eq"]:
        print(f"    EQ-NAME {n!r}")
      for k, v in sorted(m["collide"].items(), key=lambda kv: -len(kv[1])):
        print(f"    KEY {k!r} <- {len(v)} row(s): {sorted(set(v))[:4]}")
      for n, w in m["cont_lines"][:3]:
        print(f"    CONT L{n}: {src_line(texts, m['label'], n)!r}")
  (HERE / "eq-census2.json").write_text(json.dumps(
    [{k: v for k, v in m.items() if k != "cont_lines"} for m in ms], indent=1))
  return 0


def src_line(texts, label, n):
  for lb, t in texts:
    if lb == label:
      return t.splitlines()[n - 1]
  return ""


if __name__ == "__main__":
  sys.exit(main())