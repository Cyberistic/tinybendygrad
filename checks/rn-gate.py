#!/usr/bin/env python3
"""rn-gate.py -- the gate for tinybendygrad/uop/render.bend, and for the `=`-bearing names.

    .venv/bin/python checks/rn-gate.py                # live port + live oracle
    .venv/bin/python checks/rn-gate.py --plant ROW    # corrupt ONE VALUE
    .venv/bin/python checks/rn-gate.py --plant-shape OLD NEW
    .venv/bin/python checks/rn-gate.py --plant-ansi   # the reader's COLOUR-INVARIANCE plant
    .venv/bin/python checks/rn-gate.py --selftest
    .venv/bin/python checks/rn-gate.py --names

THE ROW SHAPE, written by `py_row` at `render.bend:2148`:

    IO.print(String.concat([nm, " = [", pyrender(...), "]   py=[", py, "]"]))

and `nm` is a `String` PARAMETER, so a name MAY contain a space, and MAY contain an `=`.  What it
cannot do is contain a NEWLINE -- and that is the whole finding on this lane.

⚠ THERE ARE NO `=`-BEARING ROW NAMES ON THIS LANE, AND THE 31 THE CENSUS REPORTS ARE FALSE
POSITIVES.  MEASURED on both lanes, fresh captures:

    port    80 rows, 0 names containing `=`, 97 distinct keys of `rows()` over 140 accepted lines
    oracle  80 rows, 0 names containing `=`, 85 distinct keys of `rows()` over 124 accepted lines

`name-census.json` reports **31 `=`-names on the ORACLE lane and 0 on the PORT lane** -- 31 of
them spelled `pyrender const=[ast`, `pyrender buffer=[c1`, and so on.  Every one of those is a
reader that cut at the ` = ` **INSIDE THE VALUE** (`ast = UOp.const(3)`), and the port spells its
boundary ` = [` (render.bend:2148) while the oracle spells it `=[`, so the ` = ` its second reader
found was never a boundary on either lane.  `name-census.py`'s own header records the trap at
`:205-212` and then falls into it.  A detector that matches a form cannot see the instance that
lacks it: the detector looked for `" = "` and render's own VALUES are full of it.

⚠ THE REAL DEFECT ON THIS LANE IS A CONTINUATION LINE, AND NO SEPARATOR RENAME CAN TOUCH IT.
`pyrender` legitimately emits newlines -- `pyrender buffer` answers

    c1 = UOp.range(4, 0, AxisType.WEAK)
    ast = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, device='CPU'))

-- so ONE logical row is 2-4 PHYSICAL lines, and `rebase-gate.py:row()` cannot tell a continuation
from a row.  MEASURED: 49 continuation lines on the port lane and 44 on the oracle, costing **43**
and **39** rows respectively, landing on the keys `ast` (30x), `c3` (8x), `c2`, `c4`, `c5`, `py` (5x,
from FIVE HAND-WRITTEN WRAPS at render.bend:2809-2819).  The port also prints `py=` on its own line
where the oracle does not, so the two lanes disagree about one extra key: a `ghost`.

⚠ AND ON THIS LANE THE VALUE COMPARISON IS **NOT** A TAUTOLOGICAL ZERO -- the opposite of llvmir and
nir_llvmir.  MEASURED 2026-10-21: port stdout md5 `72eb3e28575c8f843ac5ae58d9afcc98` (161 physical
lines, STABLE across three consecutive runs), oracle stdout md5
`642f9770c558df0f1be03a8f67ac997e` (124 lines) -- and the ORACLE's md5 is a PIN, because the oracle
answers from an upstream REVISION, while the PORT's md5 is a MOVING reading: `tinybendygrad/uop/ops.bend`
is another live unit's and its edit REMOVED the `4` from the port's hand-written `py=` literal
between two runs of this gate on the same day, so the port's md5 moved `18b5e53f...` -> `72eb3e28...`
with no edit to THIS file.  The two sides print DIFFERENT bytes, so `disagree` is a real measurement
here and the value comparison is not decoration.  The port has 14 rows the oracle does not answer --
11 `rnd_*` and 3 `pu_*` -- which is `ghost`, not disagreement.

⚠ AND THE PORT LANE'S ANSI ESCAPES ARE A READER DEFECT, NOT A PORT DEFECT.  `print_uops` colours
its indices (`\x1b[31m0\x1b[0m`) and upstream colours them too, so a lane's bytes MAY carry escapes
and the reader has to cope.  ⚠ EVERY ESCAPE OPENS A `[` THAT NO `]` EVER CLOSES -- `\x1b[31m` is one
`[` and `\x1b[0m` is another -- so a reader that counts brackets without stripping them is defeated
by the FIRST coloured line and NEVER RECOVERS.  MEASURED 2026-10-21 on the live lane: 6 escapes on
3 of the port's 161 lines, and the unstripped lane reads as **2 rows where the stripped lane reads
94**, gates **0** rows, and reports a verdict about a lane it never read.  THE FIX IS IN THE
READER -- `plain()` strips the escapes ONCE, at the point where the lane text ENTERS the reader, so
the strict reader, the census's own measure and the shipped reader all see the same bytes -- and
NOT in the port, which is entitled to print colour.  The reader's colour-invariance is PLANTED:
`--plant-ansi` runs the arms, and the `colour` lane of `--selftest` is the same claim in the
gate's own selftest.

⚠ AND THE ELEVEN DISAGREEMENTS ARE TWO CAUSES, NOT ELEVEN BUGS.  MEASURED 2026-10-21 on the live
lane: 80 gated rows, 69 agree, 11 disagree, and every one is NAMED.

  FIVE are the HAND-WRITTEN `py=` WRAPS (render.bend:2809-2819) -- the port puts the `py=` column
  on its OWN physical line and the oracle does not reprint it, so the port's VALUE for those five
  carries an extra line: `arg_repr AKern`, `arg_repr AParam1`, `arg_repr AParam2`, `arg_repr
  AParam3`, `arg_repr AProgr`.  For `AKern`, `AParam2` and `AProgr` the `py=` wrap is the ONLY
  difference.  ⚠ THE CAPTURED PAIR DISAGREES ON EXACTLY THESE FIVE, and on nothing else.

  SIX are the `ParamArg` SHAPE, and they are REAL: the port's `arg_repr` renders upstream master's
  TWELVE-FIELD `ParamArg`, which has no `size`, so it answers `ParamArg(0, dtypes.i32,
  device='CPU')` where CPython -- answering from the pinned revision `81157efb0^`, whose `ParamArg`
  is `ParamArg(0, dtypes.i32, 4, device='CPU')` -- answers with the `4`: `pyrender buffer`,
  `pyrender bufimage`, `pyrender buflocal`, `pyrender bufnodev`, `pyrender copy`, `pyrender store`.
  ⚠ `AParam1` and `AParam3` carry BOTH causes, so the two groups overlap in 2 of the 11.  THIS IS
  A `.bend` FILE AND OUT OF THIS GATE'S GRANT: the port's `arg_repr` rules predate upstream's
  `ParamArg`, and the fix belongs in `tinybendygrad/uop/render.bend`, not in a reader.

⚠ AND THE PORT'S OWN `py=` LITERAL HAD NO READER AT ALL, SO THE STALE-LITERAL COUNT WAS 0
BECAUSE IT READ NOTHING.  `judge()` compares `split_py(pr[name])[0]` -- the producer's OWN answer
-- and its STALE-LITERAL count read `split_py(pr[name])[1]`, WHICH IS `None` FOR EVERY ROW ON
THIS LANE: `row_strict` splits the row at `]   py=[` and keeps the HEAD, so the literal is in
the TAIL, and the TAIL WAS DISCARDED.  ⚠ A COUNT OF 0 THAT IS 0 BECAUSE THE READER READ NOTHING
IS INDISTINGUISHABLE FROM A COUNT OF 0 THAT IS 0 BECAUSE THE TWO SIDES AGREE, and `cc2d21f6d`
PROVED THE PORT DID CONTRADICT ITSELF ON EXACTLY SIX ROWS -- the port's `pyrender` EMULATION
printed `ParamArg(0, dtypes.i32, device='CPU')` while the port's own `py=` LITERAL for the SAME
row printed `ParamArg(0, dtypes.i32, 4, device='CPU')`, a `size` the port's `ParamArg` record
CANNOT HOLD -- AND THIS GATE DID NOT NOTICE.  THE LITERAL IS NOW READ FROM WHERE IT IS: the
reader takes the ROW TEXT and returns the producer's own EMULATION and the `py=` LITERAL, and
the STALE-LITERAL count is the number of rows where THOSE TWO DISAGREE.  MEASURED 2026-10-21 on
the live lane: 80 of the port's 94 read rows carry a literal, and 0 of them disagree -- 0
BECAUSE THEY AGREE, and the denominator is PRINTED so a reader that read nothing could not print
it.  THE PLANT (`--plant-literal`) RESTORES ONE LITERAL'S `size` AND THE COUNT MOVES TO 1.

⚠ AND THE SUBSTRATE IS NOT STILL.  `tinybendygrad/uop/ops.bend` and `uop/fold.bend` are in this
file's 5-file import closure and belong to other live units.  MEASURED: the ORACLE and the PORT
disagree on 11 rows because `render.bend:2693-2703` gained its `rnd_*` rows at 11:46 today, AFTER
`name-census-lanes/*.txt` was captured at 11:08 -- so the CENSUS's render lane text is STALE, and a
census that reads its own cache without re-fetching reports a port that no longer exists.  Every
capture here goes through `.agents/slop/eq/lane.py`, which digests the whole closure before and
after.

TWO THINGS THIS GATE REFUSES TO DO.  It does not write to the tree: `--plant`, `--plant-shape` and
`--plant-ansi` rewrite CAPTURED BYTES in memory only, and `--plant-ansi`'s copy of the gate is made
in a TEMP DIRECTORY, outside it.  And it does not accept an ambiguous row boundary --
`row_strict` requires this lane's ` = [` to occur EXACTLY ONCE in the head, and it FOLDS a
continuation into the row above it rather than reading it as a row of its own.
"""
import argparse, hashlib, importlib.util, pathlib, re, shutil, subprocess, sys, tempfile
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent
# `parents[0]` IS the repo root, and the depth is PROVED by `refuse()` below, not assumed.
# `3f0e70ff1` MOVED this file from `.agents/slop/eq/` to `checks/`, ONE level shallower, and
# carried the constant across without recomputing it -- so `parents[2]` became
# `/Users/cyberistic/src`, which is where every `cwd=REPO` in this file pointed.  Note the trap:
# `parents[1]` is ALSO wrong -- it is `/Users/cyberistic/src/tries`.
REPO = HERE.parents[0]
SLOP = REPO / ".agents" / "slop"
PORT = "tinybendygrad/uop/render.bend"
ORACLE = ["checks/render-gate-oracle.py", "--gate"]
"""THE ORACLE, IN GIT BESIDE THE GATE.  ⚠ THE PATH THIS NAMED BEFORE WAS A PRUNED DIRECTORY
  (`.agents/slop/xd1/`), and a gate's input under `.agents/slop/` is exactly what deleted it: a
  gate's required input belongs beside the gate IN GIT, not in a swept tree.  The oracle is
  committed at `checks/render-gate-oracle.py` and it RUNS -- it resolves its subject by DISCOVERY
  (the last upstream revision whose `tinygrad/uop/render.py` still defines `pyrender`, materialised
  with `git archive` into a temp dir on `sys.path`) and prints 124 rows whose stdout md5 is
  `642f9770c558df0f1be03a8f67ac997e`, byte-identical to the committed capture `checks/rn-orc.rows`."""


def refuse(*why):
  """exit 3 = REFUSED, and NOT a verdict.  `checks/abi_gate.py` rule, in this file's idiom.

  Placed BEFORE `load()` below, because both readers used to be SIBLINGS at `.agents/slop/eq/`
  and the move carried this file without them, so `load()` raised `FileNotFoundError` FIRST --
  and an assertion DOWNSTREAM of what it asserts cannot turn an exception into a refusal."""
  print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
  sys.exit(3)


# TWO TRACKED MARKERS, so a FURTHER relocation is a refusal rather than a traceback: the
# substrate this root claim rests on, then the readers this gate LOADS at import.
if not (REPO / "pyproject.toml").is_file() or not (REPO / "tinybendygrad").is_dir():
  refuse(f"REPO does not hold the tree: {REPO} is not the repo root "
         f"(is `parents[N]` stale after a move?)")
for _n in ("rebase-gate", "eq-census2"):
  _p = SLOP / "eq" / f"{_n}.py" if _n == "eq-census2" else SLOP / f"{_n}.py"
  if not _p.is_file():
    _rel = _p.relative_to(REPO).as_posix()
    refuse(f"input absent: {_p}"
           f"  (swept by 371cc64c9; recoverable from git at 371cc64c9^:{_rel})"
           "  This gate cannot produce a denominator without it.")
SEP = "]   py=["      # `py_row`'s own three-space literal (render.bend:2148)
PYCOL = "py="        # the `py=` COLUMN's own marker; `SEP` is this column's F2 SPELLING
ROW_OPEN = " = ["     # and its own name/value boundary, same line
DEPTH = {"[": 1, "]": -1}

ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
"""CSI ESCAPE SEQUENCES -- the SGR colour the port's `print_uops` emits and upstream emits too.
  ⚠ EVERY ESCAPE OPENS A `[` THAT NO `]` EVER CLOSES (`\x1b[31m` is one `[`, `\x1b[0m` is another),
  so a reader that counts brackets WITHOUT stripping them is defeated by the first coloured line
  and never recovers: MEASURED 2026-10-21, the unstripped port lane reads as 2 rows where the
  stripped lane reads 94, and gates 0."""


def plain(text):
  """The lane text with its ANSI escapes removed.  ONE function, called ONCE per lane, at the point
  where the text ENTERS the reader -- so the strict reader, the census's own measure and the
  shipped reader all see the SAME bytes and cannot disagree about what a row is.

  ⚠ IT IS NOT A COSMETIC FILTER.  An escape is a `[` to every bracket counter in this tree, so a
  lane whose depth never returns to zero has no rows at all, and a gate that reports a verdict over
  such a lane has reported a verdict about nothing.  THE PORT IS ENTITLED TO PRINT COLOUR: the fix
  belongs HERE and not in the `.bend` file."""
  return ANSI.sub("", text)


def escapes(text):
  """(n_sequences, n_lines) -- the lane's ANSI escapes, so the reader's strip is REPORTED rather
  than silent.  A strip nobody can see is a strip nobody can audit."""
  return len(ANSI.findall(text)), sum(1 for line in text.splitlines() if "\x1b" in line)


def load(name):
  """`rebase-gate.py` has a `-` in its name, so it does not import by name.  ONE loader for every
  reader this file uses.  `SLOP` rather than a HERE-relative search, because both readers were
  SIBLINGS at `.agents/slop/eq/` and `3f0e70ff1` carried this file to `checks/` without them;
  `refuse()` above has already asserted both exist, so there is no search left to fall through."""
  p = (SLOP / "eq" / f"{name}.py") if name == "eq-census2" else (SLOP / f"{name}.py")
  spec = importlib.util.spec_from_file_location(name, str(p))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


_rebase = load("rebase-gate")
rows_shipped, row_shipped = _rebase.rows, _rebase.row
"""THE PROJECT'S ONE ROW READER, IMPORTED, NEVER COPIED.  A second reader is how this project got a
  two-round contradiction between two gates, and 156 forked readers already exist."""

_census = load("eq-census2")
"""THE STRUCTURAL READER, IMPORTED from `.agents/slop/eq/eq-census2.py` -- the same one the re-census
  runs, so this gate's GUARD 0 and the census cannot disagree by construction.  It supplies
  `logical_rows`, `lane_shape`, `boundary` and the loss ATTRIBUTION, all of which are the same
  problem: telling a continuation from a row, and telling a producer's boundary from the prose
  inside a producer's value."""


def logical_rows(text):
  """[(first_lineno, n_lines, joined_text)] -- ONE entry per LOGICAL row, continuations folded in.

  The fold is by bracket depth over the whole line, which is the one rule that tells a continuation
  from a row without asking any producer what it meant, PLUS the one hand-written wrap this lane
  has: `render.bend:2809-2819` prints five rows as two `IO.print`s each and puts the `py=` column on
  its own line.  A line at depth 0 whose first non-space text is `py=` therefore continues the row
  above it.  IT IS NOT A SUBSTITUTE FOR `rebase-gate.py:row()`: `reshape()` below reports what the
  SHIPPED reader does with these same bytes, and the difference between the two counts is the
  finding."""
  out, depth, start, buf = [], 0, 0, []
  for n, line in enumerate(text.splitlines(), 1):
    if not line.strip():
      continue
    wrapped = buf and depth == 0 and line.lstrip().startswith("py=")
    if depth == 0 and not wrapped:
      if buf:
        out.append((start, len(buf), "\n".join(buf)))
      start, buf = n, [line]
    else:
      buf.append(line)
    for c in line:
      depth += DEPTH.get(c, 0)
  if buf:
    out.append((start, len(buf), "\n".join(buf)))
  return out


def row_strict(logical):
  """(name, value, why) for ONE LOGICAL row, or (None, None, why).

  Ambiguity is REFUSED: `head.count(ROW_OPEN) != 1` returns the reason rather than a guess.

  ⚠ A ROW WITH NO `py=` COLUMN IS A ROW, NOT A REFUSAL.  `rebase-gate.py:row()` handles it
  (`if i < 0: v = value.strip(); return name, v, v`) and 46 of render's own rows rely on it --
  `sint_show 0 = [0]   py=0`, `prec_of MUL = [1]   py=1`, `sint_show -3 = [...] py=-3` (ONE space,
  render.bend:2763).  A strict reader that demands the full eight-character column refused 59 of
  96 logical rows on this lane and reported `gated 0`, which reads as "the two lanes share no row
  NAME" -- a green-looking BROKEN that was entirely the reader's own strictness."""
  first, nlines, text = logical
  head, sep, tail = text.rpartition(SEP)
  probe = head if sep else text
  # ⚠ THIS LANE PRINTS THREE DIFFERENT BOUNDARY SPELLINGS, and that is a FINDING rather than a
  # nuisance.  `py_row` writes `nm + " = ["` (render.bend:2148); the oracle writes `nm + "=["`;
  # and `rnd_row` -- render.bend:2693-2703, ELEVEN rows the census's cached lane text does not
  # even contain -- writes `nm + "="` glued, i.e. an F1 row on an otherwise F2 lane.  So the shape
  # CANNOT be decided once for the lane, and `eq-census2.lane_shape`'s majority rule would have
  # classified `rnd_param_named=i` as F2 and cut it at the wrong place.  Three candidates are tried
  # in order and AMBIGUITY IS REFUSED rather than resolved.
  for rx in (ROW_OPEN, "=["):
    # A candidate is a depth-0 `=` whose remainder, after spaces, opens a bracket, and which is
    # either SPACED (` = [`) or GLUED (`=[`).  ⚠ The glued form is `= [`-shaped too, so testing
    # `rx[-2:]` against `probe[i:i+len(rx)]` is off by one -- `probe[i:]` STARTS at the `=`, not
    # before it -- and it silently rejected every candidate on this lane, which then fell through
    # to the `eqs[0]` fallback and named every planted row `pyrender co`.  A reader whose candidate
    # test rejects all candidates looks exactly like a lane with no ambiguous rows.
    cands = [i for i in _census.depth0_eq(probe)
             if probe[i + 1:].lstrip(" ").startswith("[")
             and (rx is not ROW_OPEN or probe[i - 1:i] == " " or rx == "=[")]
    if len(cands) == 1:
      i = cands[0]
      return probe[:i].strip(), probe[i + 1:].strip(), None
    if len(cands) > 1:
      return None, None, (f"L{first}: {len(cands)} `{rx.strip()}` boundary candidates at "
                          f"{cands[:4]} -- REFUSED, not resolved")
  eqs = _census.depth0_eq(probe)
  if eqs:
    return probe[:eqs[0]].strip(), probe[eqs[0] + 1:].strip(), None
  return None, None, f"L{first}: no depth-0 `=` at all -- REFUSED"


def value_span(text):
  """(i, j) -- the span of the producer's BRACKETED VALUE in `text`, or None.

  THE VALUE IS ONE BRACKETED THING, so the pair has to be MATCHED.  ⚠ NOT `text.index("[")` AND
  NOT `text.rfind("]")`: a value may hold brackets of its own (`[(1, 2)]`), and a reader that
  cuts at the wrong bracket compares two different strings and calls the difference a
  disagreement."""
  d = 0
  for i, c in enumerate(text):
    if c == "[" and d == 0:
      dd = 0
      for j in range(i, len(text)):
        dd += DEPTH.get(text[j], 0)
        if dd == 0:
          return i, j
      return None
    d += DEPTH.get(c, 0)
  return None


def py_span(text):
  """(marker, start, end) -- where the `py=` column is in ONE LOGICAL ROW's text, or None.

  THE MARKER IS THE LAST DEPTH-0 `py=`.  ⚠ `rfind` AND NOT `find`: the row's own NAME can carry
  the marker -- MEASURED on the oracle lane, whose boundary is GLUED and whose `pyrender copy`
  row therefore holds a `copy=` -- and the column is always the LAST one.  ⚠ AND DEPTH 0, so a
  `py=` inside the producer's bracketed value is part of the value and not a column.
  ⚠ THE SPAN, NOT THE TEXT: a plant has to REWRITE the literal IN PLACE, and a reader that
  returns only the text cannot say where the text was -- a plant that replaced the first
  occurrence of a string would have replaced the EMULATION's occurrence of it, which is the very
  column the plant is not measuring."""
  marks, d, i = [], 0, 0
  while i < len(text):
    if d == 0 and text.startswith(PYCOL, i):
      marks.append(i)
    d += DEPTH.get(text[i], 0)
    i += 1
  if not marks:
    return None
  marker = marks[-1]
  tail = text[marker + len(PYCOL):]
  start = marker + len(PYCOL) + (len(tail) - len(tail.lstrip()))
  lit = tail.strip()
  if lit.startswith("["):
    span = value_span(lit)
    if span and span[1] == len(lit) - 1:
      return marker, start + span[0] + 1, start + span[1]
  return marker, start, start + len(lit)


def py_column(text):
  """(emulation, literal, why) for ONE LOGICAL ROW's text, or (None, None, None).

  THE PRODUCER'S OWN TWO COLUMNS, READ FROM THE ROW TEXT.
  THE EMULATION  the producer's own answer -- the content of its bracketed value.
  THE LITERAL    the `py=` column -- the transcription, hand-written in the `.bend` file.
  ⚠ THE LITERAL IS NOT READ OUT OF THE VALUE SLOT: `row_strict` cuts the row at `]   py=[` and
  keeps the head, so the literal is in the tail and the tail was DISCARDED -- a reader that
  looked for it in the value could only ever answer `None`, and a count of 0 that is 0 because
  the reader read NOTHING is indistinguishable from a count of 0 that is 0 because the two sides
  AGREE."""
  span = py_span(text)
  if span is None:
    return None, None, None
  marker, a, b = span
  head = text[:marker].rstrip()
  vs = value_span(head)
  if vs is None:
    return None, None, "the `py=` column has no bracketed value in front of it"
  return head[vs[0] + 1:vs[1]].strip(), text[a:b].strip(), None


def rows_strict(text):
  """(rows, refusals, columns) -- `columns` maps a row NAME to (emulation, literal).

  THE THIRD THING IS THE `py=` COLUMN, and it is read from the ROW TEXT because the row's
  name/value cut DISCARDED it: `row_strict` splits the row at `]   py=[` and keeps the head, so
  the literal was never in the value at all.  ⚠ A ROW WHOSE COLUMN CANNOT BE READ IS REFUSED, not
  guessed: it leaves the comparison AND it is named in the refusals, because a row that is
  compared without its literal is a row whose SELF-CONSISTENCY was never measured, and a count
  that silently skips the rows it could not read is a count with a denominator nobody can see."""
  rows, refusals, dupes, columns = {}, [], [], {}
  for logical in logical_rows(text):
    name, value, why = row_strict(logical)
    if name is None:
      refusals.append((logical[0], why))
      continue
    emu, lit, why2 = py_column(logical[2])
    if why2:
      refusals.append((logical[0], f"L{logical[0]}: {name}: {why2}"))
      continue
    if name in rows:
      dupes.append(name)
    rows[name] = value
    columns[name] = (emu, lit)
  return rows, refusals, columns


def reshape(lane, text):
  """GUARD 0.  THE COVERAGE DELTA OF ONE LANE, PER LANE, BEFORE any value is compared.

  THE MEASUREMENT IS IMPORTED from `eq-census2.measure`, so the gate's coverage statement and the
  re-census's cannot drift apart -- and so the loss ATTRIBUTION, which is the part that has to
  reconcile, is the same code on both.

  THE POINT OF THIS GUARD ON THIS LANE IS THE CONTINUATION COUNT, because there is no `=` here:

    cont      physical lines `row()` reads as rows that are really the TAIL of the row above.  This
              is the defect, and it is invisible to a name-set check because the names it invents
              (`ast`, `c3`, ...) are perfectly good names -- of nothing.
    eq        names containing `=`      the ROOT CAUSE on llvmir / cstyle / nir_llvmir.  0 here.
    lost      rows no name can address, SPLIT into a continuation, a reshape and a duplicate name.
  """
  strict, refusals, _columns = rows_strict(text)
  c = _census.measure(text, lane)
  m = {"lane": lane, "physical": c["accepted"], "logical": len(strict), "cont": c["cont"],
       "shipped_keys": c["shipped_names"], "lost": c["lost_reader"],
       "lost_cont": c["lost_cont"], "lost_reshape": c["lost_reshape"], "lost_dupe": c["lost_dupe"],
       "manufactured": sorted(set(rows_shipped(text)) - set(strict)), "refusals": refusals,
       "eq": sorted(n for n in strict if "=" in n), "strict": set(strict)}
  bad = []
  if not c["accepted"]:
    bad.append(f"{lane}: 0 physical rows read, so the name set is EMPTY and says nothing about "
               f"coverage. This is not a pass.")
  if m["eq"]:
    bad.append(f"{lane}: {len(m['eq'])}/{len(strict)} row NAME(S) CONTAIN `=`, so rebase-gate.row "
               f"cuts the name there and the two readers name {len(m['eq'])} row(s) differently: "
               f"{m['eq'][:6]}")
  if m["cont"]:
    top = sorted(((len(v), k) for k, v in c["collide"].items()), reverse=True)[:4]
    bad.append(f"{lane}: {m['cont']}/{c['accepted']} PHYSICAL LINE(S) ARE THE TAIL OF THE ROW ABOVE "
               f"THEM (`pyrender` answers contain newlines, render.bend:2148, and five rows put the "
               f"`py=` column on its own line, render.bend:2809-2819), and `rebase-gate.py:row()` "
               f"reads every one as a row of its own. {m['lost']} of {c['accepted']} rows therefore "
               f"cannot be addressed by ANY name ({m['lost_cont']} of them because of these "
               f"continuations), and {len(m['manufactured'])} of the shipped reader's names "
               f"({m['manufactured'][:4]}) are MANUFACTURES from a continuation, which NO producer "
               f"printed. NO `=` IS INVOLVED, so no separator rename can fix this. "
               f"(rows per key: {[(k, n) for n, k in top]})")
  if m["lost"] != m["lost_cont"] + m["lost_reshape"] + m["lost_dupe"]:
    bad.append(f"{lane}: the loss does not decompose: {m['lost']} lost against "
               f"{m['lost_cont']}+{m['lost_reshape']}+{m['lost_dupe']}")
  if refusals:
    bad.append(f"{lane}: {len(refusals)} LOGICAL row(s) REFUSED as ambiguous: {refusals[:4]}")
  m["bad"] = bad
  return m


def report_reshape(rs):
  print(f"{'lane':<7} {'phys lines':>10} {'logical rows':>13} {'cont lines':>11} "
        f"{'keys (shipped)':>15} {'`=`':>4} {'unaddressable':>13} {'=cont':>6} {'refused':>8}")
  for m in rs:
    print(f"{m['lane']:<7} {m['physical']:10} {m['logical']:13} {m['cont']:11} "
          f"{m['shipped_keys']:15} {len(m['eq']):4} {m['lost']:13} {m['lost_cont']:6} "
          f"{len(m['refusals']):8}")
  for m in rs:
    for b in m["bad"]:
      print(f"  {b}")


def plant_value(text, name):
  """Corrupt ONE captured VALUE.  On this lane the value may be MULTI-LINE, so the plant edits the
  `py=` literal of the FIRST physical line of the row and leaves every continuation line alone --
  a control must not perturb the thing it is not measuring."""
  out, hits = [], 0
  # ⚠ NOT `line.startswith(name + ROW_OPEN)`.  This lane PADS its names to a column --
  # `pyrender const    = [`, `sint_show 0      = [` -- so an exact-prefix plant hits NOTHING and
  # a control that reports 0 hits and no change is indistinguishable from a control that did not
  # run.  `PLANT_HIT` is printed on every run so a missed plant cannot read as a clean cell.
  rx = re.compile(r"^" + re.escape(name) + r"\s*=")
  for line in text.splitlines():
    if not hits and rx.match(line):
      line = line.replace(SEP, "PLANTED" + SEP, 1) if SEP in line else line + "PLANTED"
      hits += 1
    out.append(line)
  if not hits:
    print(f"[plant WARNING] the value plant on {name!r} matched NO line -- this cell measured "
          f"nothing and proves nothing.")
  return "\n".join(out) + "\n", hits


def plant_literal(text, name, old, new):
  """A COPY of the lane text with ONE row's `py=` LITERAL rewritten.

  ⚠ THE PLANT IS APPLIED TO THE STRIPPED TEXT, and the reason is the READER: the row boundaries
  are read by bracket DEPTH, and an ANSI escape is a `[` to every bracket counter (see `plain()`),
  so on the RAW text the `pu_*` rows' escapes leave the depth ABOVE ZERO and the fold swallows the
  rest of the lane -- MEASURED, the live lane reads 10 logical rows raw and 105 stripped.  The
  planted lane is therefore THE LANE THE READER SEES, with one literal rewritten, and the escapes
  are not part of the subject.

  ⚠ THE SUBSTITUTION IS SCOPED TO THE LITERAL, and the literal is LOCATED BY ITS SPAN, because
  the string being replaced is in the row's EMULATION as well: `ParamArg(0, dtypes.i32,
  device='CPU')` is in BOTH columns of the `pyrender buffer` row, and a plant that replaced the
  first occurrence would have changed the EMULATION and left the LITERAL alone -- which is the
  exact opposite of the plant, and would have read as a clean 0.

  ⚠ AND THE PLANT IS IN THE LANE TEXT, NOT IN THE COMPARED SLOT: it rewrites what the PORT
  PRINTS, so the gate reads the planted lane the way it reads any other lane."""
  stripped = plain(text)
  lines = stripped.split("\n")
  for logical in logical_rows(stripped):
    if row_strict(logical)[0] != name:
      continue
    start, n, joined = logical
    span = py_span(joined)
    if span is None:
      break
    _, a, b = span
    lit = joined[a:b]
    if old not in lit:
      break
    lines[start - 1:start - 1 + n] = (joined[:a] + lit.replace(old, new) + joined[b:]).split("\n")
    return "\n".join(lines), 1
  print(f"[plant WARNING] the literal plant on {name!r} matched NO literal -- this cell measured "
        f"nothing and proves nothing.")
  return stripped, 0


def plant_shape(text, pairs):
  """A row NAME given an `=`, values untouched, tail verbatim.  Applied on BOTH lanes: renaming
  one side alone trips `stray`/`ghost` and proves only that the reader reads names."""
  out, hits = [], 0
  # The padding trap again: this lane pads names to a column, so the match is a regex on the NAME
  # followed by `\s*=`, and the replacement REPLACES THE NAME while leaving the boundary and every
  # byte after it verbatim.
  rxs = [(re.compile(r"^" + re.escape(old) + r" +(?==)"), old, new) for old, new in pairs]
  for line in text.splitlines():
    for rx, old, new in rxs:
      m = rx.match(line)
      if m:
        line = new + " " + line[m.end():]   # the boundary `= [` and every byte after it, verbatim
        hits += 1
    out.append(line)
  if not hits:
    print(f"[plant WARNING] the shape plant on {pairs} matched NO line -- this cell measured "
          f"nothing and proves nothing.")
  return "\n".join(out) + "\n", hits


def plant_ansi(text):
  """A COPY of the lane text with the port's own colour form wrapped around every row's VALUE.

  THE PORT EMITS COLOUR AND UPSTREAM DOES TOO, so the reader has to be COLOUR-INVARIANT: the same
  bytes with the escapes and without must read as the same rows.  The copy differs from the
  original ONLY by the escape sequences, so the claim is about the READER and not about the bytes.

  ⚠ THE ESCAPES GO WHERE THE PORT PUTS THEM -- INSIDE THE VALUE, AFTER THE ROW BOUNDARY -- and not
  around the whole line, because a reader that only copes with a leading escape is a reader that
  copes with one producer's spelling.  The boundary is found with the CENSUS's own `depth0_eq`, on
  the PLAIN line, so the escape cannot hide the `=` it is measured against."""
  out = []
  for line in text.splitlines():
    eqs = _census.depth0_eq(line)
    i = eqs[0] if eqs else None
    out.append(f"{line[:i + 1]}\x1b[31m{line[i + 1:]}\x1b[0m" if i is not None else line)
  return "\n".join(out) + "\n"


def plant_refusal():
  """A COPY of this gate whose ORACLE PATH DOES NOT RESOLVE must REFUSE, not PASS.

  THE COPY IS A REAL TREE SHAPE: `pyproject.toml`, `tinybendygrad/` and `.agents/` are SYMLINKS to
  this repo's, so the copy's `REPO` resolves, its readers LOAD, and the ONLY thing missing is the
  oracle.  So the refusal the guard produces is the refusal about the ORACLE and not about a tree
  that is not there -- which is the whole difference between a subject that is absent and a subject
  that is broken."""
  with tempfile.TemporaryDirectory(prefix="rn-gate-plant-") as td:
    root = pathlib.Path(td)
    (root / "checks").mkdir()
    shutil.copy2(HERE / "rn-gate.py", root / "checks" / "rn-gate.py")
    for name in ("pyproject.toml", "tinybendygrad", ".agents"):
      (root / name).symlink_to(REPO / name)
    return subprocess.run([sys.executable, str(root / "checks" / "rn-gate.py")],
                          cwd=root, capture_output=True, text=True, timeout=600)


def plant_ansi_run():
  """THE PLANT, ITS CONTROL, ITS FALSIFICATION, AND THE REFUSAL.  Every arm is a CLAIM the gate
  makes about its own reading, and every arm can fail.

    CONTROL      the coloured copy ROUND-TRIPS: `plain(coloured) == plain`, byte for byte.  So a
                 difference measured on the coloured copy is the READER's behaviour and not the
                 copy's -- without this arm the plant could report a difference of its own making.
    PLANT        the reader is COLOUR-INVARIANT: the rows read from the coloured copy are the rows
                 read from the plain one.  ⚠ THIS ARM FAILS ON THE READER THAT COUNTED BRACKETS
                 WITHOUT STRIPPING: MEASURED, that reader reads 1 row off the coloured copy where
                 it reads 94 off the plain one, and gates 0.
    FALSIFY      the SAME reader, with the strip OMITTED, must NOT read the plain copy's rows from
                 the coloured one.  Without this arm the plant could pass on a reader that ignores
                 colour because the coloured text happened to be colourless.
    VERDICT      the gate's OWN verdict is colour-invariant: the same gated rows, the same
                 agreements and the same disagreements, on the coloured copy and on the plain one.
    REFUSAL      a copy of this gate whose oracle path does not resolve EXITS 3 and says REFUSED.

  THE PLANT RUNS ON THE LIVE LANES, because the port's real bytes are part of the subject: a
  reader that copes with a synthetic escape but not with the producer's own is not colour-
  invariant, it is escape-flavour-invariant."""
  p, o = run(["./bin/bend", PORT]), run([sys.executable] + ORACLE)
  if p.returncode or o.returncode:
    print(f"[plant:ansi] the live lanes did not run: bend rc={p.returncode}, oracle "
          f"rc={o.returncode} -- this cell measured nothing and proves nothing.")
    return 1
  n_seq, n_line = escapes(p.stdout)
  base_txt, coloured = plain(p.stdout), plant_ansi(p.stdout)
  base = rows_strict(base_txt)[0]
  fixed = rows_strict(plain(coloured))[0]     # the reader, WITH the strip
  blind = rows_strict(coloured)[0]             # the SAME reader, WITHOUT it
  v_plain, v_col = judge(p.stdout, o.stdout), judge(coloured, o.stdout)
  arms = {
      "CONTROL ": (plain(coloured) == base_txt, "EQUAL",
                   "the coloured copy round-trips byte for byte"),
      "PLANT   ": (fixed == base, "EQUAL",
                   f"the reader is colour-invariant ({len(fixed)} rows vs {len(base)})"),
      "FALSIFY ": (blind != base, "DIFFERENT",
                   f"the ANSI-blind reading is defeated ({len(blind)} rows vs {len(base)})"),
      "VERDICT ": ((v_col["gated"], v_col["agree"], [d[0] for d in v_col["disagree"]])
                   == (v_plain["gated"], v_plain["agree"], [d[0] for d in v_plain["disagree"]]),
                   "EQUAL",
                   f"the gate's verdict is colour-invariant (gated {len(v_col['gated'])}, "
                   f"agree {len(v_col['agree'])}, disagree {len(v_col['disagree'])})"),
  }
  ref = plant_refusal()
  arms["REFUSAL "] = (ref.returncode == 3 and "REFUSED" in ref.stderr and "gated " not in ref.stdout,
                      "EXIT 3",
                      f"a copy whose oracle path does not resolve exits {ref.returncode} and says "
                      f"REFUSED")
  print(f"[plant:ansi] the live port lane carries {n_seq} ANSI escape(s) on {n_line} of its "
        f"{len(p.stdout.splitlines())} lines")
  ok = True
  for name, (good, relation, why) in arms.items():
    ok &= good
    print(f"[plant:ansi] {name} {'ok  ' if good else 'FAIL'} {relation:<9} {why}")
  print(f"[plant:ansi] the blind reader's names on the coloured copy: {sorted(blind)[:4]}")
  print("PLANT", "OK -- the reader is colour-invariant, the blind reading is caught, and a copy "
        "whose oracle path does not resolve refuses" if ok else "FAILED")
  return 0 if ok else 1


def judge(port_txt, orc_txt):
  """The verdict over TWO lane texts.  ⚠ THE ANSI ESCAPES ARE STRIPPED HERE, ONCE, AT THE POINT
  WHERE THE TEXT ENTERS THE READER -- so `reshape()`'s census measure, `rows_strict()` and the
  shipped reader all see the same bytes and cannot disagree about what a row is.  A strip applied
  to one reader and forgotten for another is how a lane reads 94 rows on one side and 2 on the
  other."""
  bad = []
  port_txt, orc_txt = plain(port_txt), plain(orc_txt)
  rs = [reshape("port", port_txt), reshape("oracle", orc_txt)]
  for m in rs:                                   # GUARD 0, BEFORE ANY VALUE IS COMPARED
    bad.extend(m["bad"])
  pr, pur, pcols = rows_strict(port_txt)
  orr, our, _ocols = rows_strict(orc_txt)
  if not pr:
    bad.append("the port lane produced ZERO rows")
  if not orr:
    bad.append("the oracle lane produced ZERO rows")
  stray = sorted(set(orr) - set(pr))
  if stray:
    bad.append(f"oracle rows matching no port row ({len(stray)}): {stray[:8]}")
  ghost = sorted(set(pr) - set(orr))
  if ghost:
    bad.append(f"port rows the oracle did not answer ({len(ghost)}): {ghost[:8]}")
  agree, disagree, gated = [], [], []
  for name in sorted(set(pr) & set(orr)):
    # ⚠ THE COMPARED BYTES ARE THE VALUE SLOT, AND THEY ARE WHAT THEY ALWAYS WERE: the old
    # `split_py(v)[0]` was a NO-OP on this lane -- MEASURED on all three lanes, `split_py(v)[0] == v`
    # for EVERY row, because the `]   py=[` cut leaves the value with no `py=` left to split on --
    # so reading `pr[name]` and `orr[name]` directly compares the same bytes the gate compared
    # before.  ⚠ THE COMPARISON ITSELF IS UNCHANGED: the producer's own answer against the
    # oracle's.
    got, want = pr[name], orr[name]
    gated.append(name)
    if got == want:
      agree.append(name)
    else:
      disagree.append((name, got, want))
  # ⚠ THE PORT'S OWN TWO COLUMNS AGAINST EACH OTHER.  THIS IS NOT THE GATE'S COMPARISON -- that is
  # the port's answer against the oracle's, above, and it is untouched -- it asks whether the
  # port's EMULATION and the port's own `py=` LITERAL agree, which is the question a human reads a
  # row to answer.  ⚠ AND IT IS OVER EVERY PORT ROW THAT CARRIES A LITERAL, not over the GATED
  # rows: a row the oracle does not answer can still contradict itself.
  stale, literals = [], 0
  for name, (emu, lit) in pcols.items():
    if lit is None:
      continue
    literals += 1
    if emu != lit:
      stale.append((name, emu, lit))
  if not gated:
    bad.append("0 gated rows: the two lanes share no row NAME, so nothing was compared. This is "
               "not a pass.")
  if not literals:
    bad.append("the port lane's `py=` column was read on ZERO rows, so the STALE-LITERAL count is "
               "0 because the reader read NOTHING. This is not a pass.")
  if disagree:
    bad.append(f"{len(disagree)}/{len(gated)} gated row(s) DISAGREE and every one is NAMED: "
               f"{[d[0] for d in disagree][:8]}\n        first `{disagree[0][0]}`:"
               f"\n        port {disagree[0][1]!r}\n        cpy  {disagree[0][2]!r}")
  if stale:
    bad.append(f"{len(stale)}/{literals} row(s) whose `py=` LITERAL disagrees with the PORT'S OWN "
               f"answer -- the port CONTRADICTS ITSELF, and every one is NAMED: "
               f"{[s[0] for s in stale][:8]}\n        first `{stale[0][0]}`:"
               f"\n        emulation {stale[0][1]!r}\n        literal   {stale[0][2]!r}")
  if not disagree and port_txt == orc_txt:
    bad.append("the two lanes are BYTE-IDENTICAL and agree on every value, so this run is a "
               "TAUTOLOGICAL ZERO: the byte diff is the gate and GUARD 0 is the only thing that "
               "can be red.")
  # ⚠ `identical_bytes` IS OVER THE TEXT THE READER SAW (the escapes stripped).  Colour is not a
  # claim, so a lane that differs from the oracle ONLY by colour is not a tautological zero -- and
  # the RAW bytes are reported by `main()` beside this, so the strip is never invisible.
  return {"bad": bad, "port": pr, "oracle": orr, "gated": gated, "agree": agree,
          "disagree": disagree, "stale": stale, "literals": literals, "reshape": rs,
          "identical_bytes": port_txt == orc_txt}


def run(argv):
  return subprocess.run(argv, cwd=REPO, capture_output=True, text=True, timeout=3600)


def md5(text):
  return hashlib.md5(text.encode()).hexdigest()[:8]


def selftest():
  """SEVEN LANES OVER THE REAL CAPTURED PAIR.  The BASE DISAGREEMENT COUNT IS MEASURED, NOT
  TYPED -- this lane's real pair already disagrees on 5 rows (the hand-written `py=` wraps), so a
  hardcoded 0 would be a claim about a lane that does not exist.  The property asserted is the one
  that separates the three plants:

      a VALUE plant RAISES `disagree` by exactly 1;
      a NAME  plant leaves `disagree` at the base count and moves `eq`/the name sets;
      a LITERAL plant RAISES the STALE-LITERAL count by exactly 1, and its CONTROL -- the same
      copy with a plant that matches nothing -- leaves it at the base count.

  On llvmir and nir_llvmir the base count is 0 and the two are equally distinguishable; here the
  base is 5, and a control that hardcoded 0 would have read `value` as a FAILURE of the
  instrument.

  ⚠ THE `shape` PLANT PUTS THE `=` INSIDE THE NAME (`pyrender const` -> `pyrender co=nst`), NOT
  AFTER IT.  A trailing `=` does not work on this lane and the first two attempts showed why: with
  ` = [` as the boundary, a name of `pyrender const=` reads as F2-TIGHT (a glued `=`) and the
  writer's own ` = [` is then the second candidate, so a strict reader either mis-picks or -- with
  `eqs[0]` as the fallback -- silently truncates the name back to `pyrender const` and reports
  `eq=0`.  A control that cannot express the thing it is testing will report a clean 0."""
  # THE CAPTURED PAIR IS TWO MORE DECLARED INPUTS, AND NEITHER IS GUARDED. MEASURED 2026-10-15:
  # `checks/rn-port.txt` and `checks/rn-orc.txt` are absent from disk, absent from HEAD, and **0
  # commits in the whole history touch either** -- so `read_text()` raised `FileNotFoundError` and
  # `--selftest` exited 1, which reads as a FAILURE OF THE PORT rather than as an absent subject.
  # **THE SAME CLASS AS THE ORACLE, IN THE SAME FILE, GUARDED IN TWO PLACES AND MISSED IN THE
  # THIRD.** The guard is a hand list of what this file happens to read; the file's own inputs are
  # wherever it says they are. Refusing here keeps the lane a lane: `DEAD` is not a `PASS`, and an
  # unrunnable selftest that exits 1 will be read as a red port by anything that trusts `$?`.
  for _cap in ("rn-port.rows", "rn-orc.rows"):
    if not (HERE / _cap).is_file():
      refuse(f"selftest input absent: {HERE / _cap} -- the captured pair this lane judges is not "
             f"here. IT IS NOT LOST: `checks/rn-port.rows` is lines 22..161 of the tracked "
             f"`.agents/slop/flipthird/base-render.err` and `checks/rn-orc.rows` is the tracked "
             f"`oracles/tinybendygrad_uop_render.bend.render-gate-oracle.rows`, and BOTH are "
             f"byte-verified against the md5s this file's header records. THE NAMES CHANGED, "
             f"NOT THE CONTENT.")
  live = (HERE / "rn-port.rows").read_text()
  orc = (HERE / "rn-orc.rows").read_text()
  base = judge(live, orc)
  n0 = len(base["disagree"])
  s0 = len(base["stale"])
  print(f"[selftest base] the REAL captured pair: {len(base['gated'])} gated rows, "
        f"{len(base['agree'])} agree, {n0} disagree "
        f"{[d[0] for d in base['disagree']]} -- MEASURED, and it is NOT 0: the port puts the "
        f"`py=` column on its own physical line on five rows (render.bend:2809-2819) and the "
        f"oracle does not, so the port's VALUE for those five carries an extra line. A `clean` "
        f"lane that quietly is not the real lane is the failure this work is about, so the base is "
        f"the real pair and the number is printed.")
  print(f"[selftest base] the port's OWN `py=` LITERAL against the port's own EMULATION: "
        f"{s0}/{base['literals']} row(s) disagree -- MEASURED, and the DENOMINATOR is the point: "
        f"a count of 0 with no denominator is a count that read NOTHING, and this one is 0 over "
        f"{base['literals']} rows that were READ.")
  lanes = {
    "base": (live, orc),
    "value": (plant_value(live, "pyrender const")[0], orc),
    "colour": (plant_ansi(live), orc),
    "shape": (plant_shape(live, [("pyrender const", "pyrender co=nst")])[0],) * 2,
    "collide": (plant_shape(live, [("pyrender const", "pyrender ast"),
                                   ("pyrender cast", "pyrender ast")])[0],) * 2,
    # ⚠ THE LITERAL LANE: THE FALSIFICATION OF "0 BECAUSE THEY AGREE".  The capture is the port
    # BEFORE `cc2d21f6d`, so its EMULATION and its LITERAL BOTH carry the same `4` and the two
    # AGREE; taking that `4` out of the LITERAL alone makes the capture contradict ITSELF, which
    # is the same shape of defect the live plant makes.  ⚠ AND THE SUBSTITUTION IS SCOPED TO THE
    # LITERAL: the same `UOp.range(4, ...)` string is in the row's EMULATION, and a plant that
    # changed both would have left the port self-consistent and read as a clean 0.
    # ⚠ AND THE `4` MOVED.  THIS PLANT USED TO REWRITE `ParamArg(0, dtypes.i32, 4, device='CPU')`
    # -> `ParamArg(0, dtypes.i32, device='CPU')`, BECAUSE THE `4` USED TO BE **INSIDE** THE
    # `ParamArg`.  IT IS NOT: MEASURED, THE CAPTURE'S `pyrender buffer` LITERAL IS
    #     c1 = UOp.range(4, 0, AxisType.WEAK)
    #     ast = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, device='CPU'))
    # -- THE `4` IS IN THE **RANGE**, AND THE `ParamArg` CARRIES NO SIZE.  SO THE OLD PLANT
    # MATCHED NO LITERAL, PRINTED "this cell measured nothing and proves nothing", AND LEFT
    # `stale` AT 0 -- **A PLANT THAT MEASURED NOTHING READ AS A CLEAN 0**, WHICH IS EXACTLY THE
    # FAILURE THIS LANE EXISTS TO RULE OUT.  THE PLANT IS RE-AIMED AT THE `4` THAT IS THERE.
    "literal": (plant_literal(live, "pyrender buffer",
                               "UOp.range(4, 0, AxisType.WEAK)",
                               "UOp.range(5, 0, AxisType.WEAK)")[0], orc),
    # THE UNBROKEN CONTROL: a copy of the port with a plant that matches NOTHING must be
    # BYTE-IDENTICAL to the lane it was copied from, so the literal lane's difference is the
    # PLANT's and not the copying's.
    "control": (plant_literal(live, "pyrender buffer", "NO-SUCH-LITERAL", "x")[0], orc),
  }
  want = {"base": (True, n0, s0), "value": (True, n0 + 1, s0 + 1), "colour": (True, n0, s0),
          "shape": (True, 0, s0), "collide": (True, 0, s0), "literal": (True, n0, s0 + 1),
          "control": (True, n0, s0)}
  ok = True
  for name, (ptxt, otxt) in lanes.items():
    r = judge(ptxt, otxt)
    want_broken, want_dis, want_stale = want[name]
    good = (bool(r["bad"]) == want_broken and len(r["disagree"]) == want_dis
            and len(r["stale"]) == want_stale)
    ok &= good
    print(f"  {name:<8} {'BROKEN' if r['bad'] else 'AGREE  '}  cont={r['reshape'][0]['cont']} "
          f"eq={len(r['reshape'][0]['eq'])} unaddressable={r['reshape'][0]['lost']} "
          f"disagree={len(r['disagree'])} {[d[0] for d in r['disagree']][:4]}  "
          f"stale={len(r['stale'])}/{r['literals']} {[s[0] for s in r['stale']][:4]}  "
          f"{'ok' if good else 'SELFTEST FAIL'}")
  print(f"  NOTE every lane is BROKEN, and that is CORRECT: `cont` > 0 on the real lane and the "
        f"real pair really does disagree, so this lane's honest verdict is BROKEN and `base` "
        f"asserts BROKEN rather than AGREE. The two plants are still told apart by `disagree`.")
  print(f"  NOTE the `colour` lane is the READER'S OWN PLANT: the captured port output with the "
        f"port's escape form around every value must read as the same rows.  It FAILS on a reader "
        f"that counts brackets without stripping -- MEASURED, that reader reads 2 rows where the "
        f"stripped lane reads {len(base['port'])}, and gates 0.")
  print(f"  NOTE the `literal` lane is the ONE THAT PROVES THE `py=` COLUMN IS READ: its stale "
        f"count is {s0 + 1} against the base's {s0}, and the `control` lane -- a copy of the SAME "
        f"port with a plant that matches nothing -- is byte-identical and reads {s0}.  ⚠ A COUNT "
        f"THAT IS 0 BECAUSE THE READER FOUND NOTHING IS INDISTINGUISHABLE FROM A COUNT THAT IS 0 "
        f"BECAUSE THE TWO COLUMNS AGREE, and this lane is what tells the two apart.")
  print(f"  NOTE the `value` lane ALSO reads a stale literal, and that is CORRECT rather than "
        f"noise: `plant_value` puts `PLANTED` INSIDE the value's brackets, so it corrupts the "
        f"EMULATION and leaves the LITERAL alone -- and a lane whose emulation and literal "
        f"disagree IS a self-contradicting lane, whatever put it there.  ⚠ AND THE `literal` lane "
        f"moves ONLY the stale count: its `disagree` is the base's {n0}, because the literal is "
        f"NOT the column the gate compares.")
  print("SELFTEST", "OK -- a planted VALUE raises `disagree` by one; a planted NAME leaves "
        "`disagree` at the base count and moves the name sets; and a planted LITERAL raises the "
        "stale count by one, so the two are distinguishable"
        if ok else "FAILED")
  return 0 if ok else 1


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--selftest", action="store_true")
  ap.add_argument("--plant", default=None)
  ap.add_argument("--plant-shape", nargs=2, action="append", metavar=("OLD", "NEW"))
  ap.add_argument("--plant-literal", nargs=3, action="append", metavar=("ROW", "OLD", "NEW"),
                  help="rewrite ONE row's `py=` literal, in the literal and nowhere else")
  ap.add_argument("--plant-ansi", action="store_true")
  ap.add_argument("--names", action="store_true")
  ap.add_argument("--port-stdout", default=None)
  ap.add_argument("--oracle-stdout", default=None)
  ap.add_argument("--oracle", default=None,
                  help="the oracle script to run; the default is the committed one")
  a = ap.parse_args()
  if a.selftest:
    return selftest()
  if a.plant_ansi:
    return plant_ansi_run()
  if a.port_stdout or a.oracle_stdout:
    print("!! CAPTURED LANE INPUT. Not a live run. A verdict over a capture is evidence about the "
          "CAPTURE, never about the tree as it is now.")
  # ⚠ THE ORACLE IS A DECLARED INPUT, SO IT CAN BE NAMED.  The committed one is the default and the
  # only one a verdict over this tree may be read as; naming another is how the REFUSAL stays
  # REACHABLE BY ARGV now that the committed oracle EXISTS -- a gate whose only exit 3 needs a
  # missing FILE cannot plant its own surface.  The guard below fires for the named path exactly as
  # it fires for the default, so naming a path that does not resolve is a REFUSAL and not a lane.
  oracle_argv = [a.oracle, "--gate"] if a.oracle else list(ORACLE)
  if a.oracle:
    print(f"!! ORACLE OVERRIDE: running `{a.oracle}` instead of the committed `{ORACLE[0]}`. A "
          f"verdict over a substituted oracle is evidence about THAT ORACLE, not about this tree.")
  # AN ABSENT ORACLE IS REFUSED, NOT A LANE FAILURE, and this gate's OWN guard list is why it was
  # not. The two readers this file LOADS are checked at import by a hand-list of two names, and
  # `ORACLE` -- this file's own third declared input -- was never in it. MEASURED 2026-10-15:
  # `.agents/slop/xd1/` is GONE, so the oracle is absent from disk AND from HEAD, and the live lane
  # ran a script that is not there. The only signal it produced was `lane failure`, which is a
  # **FAIL for what is an absent subject** -- a gate that cannot tell "my fixture is missing" from
  # "my fixture behaved" is the defect this file's own `refuse()` was written to remove.
  # IT IS GUARDED HERE, AT THE POINT OF USE, NOT AT IMPORT: `--oracle-stdout` reads a captured
  # file and never needs the script, so a guard at import would take away a path that works. And it
  # sits BEFORE the `bend` call so a refused gate costs nothing.
  if not a.oracle_stdout and not (REPO / oracle_argv[0]).is_file():
    # The count is the log's, not a transcription. `git log --all -- <path>` is a path query;
    # `git rev-list --all` is not, and is not asked. A non-empty log must not read as 0.
    _asked = ["git", "log", "--all", "--format=%H", "--", oracle_argv[0]]
    _log = subprocess.run(_asked, cwd=REPO, capture_output=True, text=True, timeout=120)
    if _log.returncode != 0:
      _touched = f"{' '.join(_asked)} did not answer (rc={_log.returncode})"
    else:
      _n = len([ln for ln in _log.stdout.splitlines() if ln])
      _touched = f"{_n} commits ever touched ({' '.join(_asked)})"
    refuse(f"oracle absent: {REPO / oracle_argv[0]} -- an absent oracle is an ABSENT SUBJECT, not a "
           f"failing lane, so this lane is REFUSED rather than judged. THE ORACLE THIS PROJECT "
           f"SHIPS IS `checks/render-gate-oracle.py`, AND IT RUNS: it resolves its subject by "
           f"DISCOVERY (the last upstream revision whose `tinygrad/uop/render.py` still defines "
           f"`pyrender`, materialised with `git archive` into a temp dir on `sys.path`) and prints "
           f"124 rows whose stdout md5 is `642f9770c558df0f1be03a8f67ac997e` -- byte-identical to "
           f"the committed capture `checks/rn-orc.rows`. The path this gate names is {_touched}. "
           f"The CAPTURED pair this gate judges is NOT lost -- see the selftest lane, whose "
           f"captures are byte-verified against the md5s this file's header records.")
  p = (subprocess.CompletedProcess([], 0, pathlib.Path(a.port_stdout).read_text(), "")
       if a.port_stdout else run(["./bin/bend", PORT]))
  o = (subprocess.CompletedProcess([], 0, pathlib.Path(a.oracle_stdout).read_text(), "")
       if a.oracle_stdout else run([sys.executable] + oracle_argv))
  print(f"{'CAPTURED' if a.port_stdout else 'live'} port rc={p.returncode} md5={md5(p.stdout)}   "
        f"{'CAPTURED' if a.oracle_stdout else 'live'} oracle rc={o.returncode} "
        f"md5={md5(o.stdout)}")
  _pe, _pl = escapes(p.stdout)
  _oe, _ol = escapes(o.stdout)
  print(f"reader: ANSI escapes stripped before reading -- port {_pe} on {_pl} line(s), oracle "
        f"{_oe} on {_ol} line(s).  ⚠ AN ESCAPE IS A `[` TO EVERY BRACKET COUNTER, SO A LANE THAT "
        f"IS NOT STRIPPED HAS NO ROWS AT ALL.")
  if p.returncode or o.returncode:
    print(f"lane failure: bend {' '.join(p.stderr.split())[-140:]} | oracle "
          f"{' '.join(o.stderr.split())[-140:]}")
    print("   ⚠ `tinybendygrad/uop/ops.bend` and `uop/fold.bend` are in this port's 5-file import "
          "closure and belong to other live units. A zero on this lane is a REQUEST FOR A RETRY "
          "through `.agents/slop/eq/lane.py`, never a result.")
    return 1
  if a.plant_shape:
    pt, ph = plant_shape(p.stdout, a.plant_shape)
    ot, oh = plant_shape(o.stdout, a.plant_shape)
    p, o = (subprocess.CompletedProcess([], 0, pt, p.stderr),
            subprocess.CompletedProcess([], 0, ot, o.stderr))
    print(f"[planted SHAPE] {ph}/{oh} row NAME(S) reshaped on BOTH lanes, values untouched: "
          f"{a.plant_shape}. No file on disk was touched.")
  if a.plant:
    p = subprocess.CompletedProcess([], 0, plant_value(p.stdout, a.plant)[0], p.stderr)
    print(f"[planted] `{a.plant}` corrupted on the PORT LANE ONLY, in the CAPTURED OUTPUT; every "
          f"continuation line of that row is left verbatim.")
  for row, old, new in (a.plant_literal or []):
    pt, ph = plant_literal(p.stdout, row, old, new)
    p = subprocess.CompletedProcess([], 0, pt, p.stderr)
    print(f"[planted LITERAL] {ph} literal(s) rewritten in `{row}`'s `py=` column, on the PORT LANE "
          f"ONLY: {old!r} -> {new!r}.  ⚠ THE SUBSTITUTION IS SCOPED TO THE LITERAL: the same "
          f"string is in the row's EMULATION, and a plant that changed both would have left the "
          f"port self-consistent and read as a clean 0. No file on disk was touched.")
  res = judge(p.stdout, o.stdout)
  print(f"port logical rows: {len(res['port'])}   oracle logical rows: {len(res['oracle'])}   the "
        f"two lanes are BYTE-IDENTICAL (AS THE READER SAW THEM, i.e. escapes stripped): "
        f"{res['identical_bytes']}"
        + ("   <- TAUTOLOGICAL ZERO" if res["identical_bytes"] else
           "   <- so the value comparison below is a REAL measurement on this lane"))
  report_reshape(res["reshape"])
  if a.names:
    for m in res["reshape"]:
      print(f"  {m['lane']} MANUFACTURES by the shipped reader, printed by NO producer "
            f"({len(m['manufactured'])}): {m['manufactured'][:12]}")
  print(f"gated {len(res['gated'])}   agree {len(res['agree'])}   disagree "
        f"{[d[0] for d in res['disagree']][:8]}")
  print(f"STALE-LITERAL {len(res['stale'])}/{res['literals']} `py=` literal(s) disagree with the "
        f"PORT'S OWN answer: {[s[0] for s in res['stale']][:8]}"
        + ("   <- THE DENOMINATOR IS THE POINT: 0 over 0 rows is a reader that read NOTHING"
           if not res["literals"] else ""))
  print(("BROKEN" if res["bad"] else "AGREE"), *(["\n  - " + b for b in res["bad"]]))
  return 1 if res["bad"] else 0


# THE VERDICT SURFACE, DECLARED. `gates/gate-surface.py` reads these by AST -- never by import,
# because import RUNS a gate.
#
# ⚠ THE SURFACE MOVED WHEN THE ORACLE PATH DID.  The refusal used to be the only state argv could
# reach, because the oracle was ABSENT -- the path named a pruned directory -- and a missing
# subject is a REFUSAL.  Now that the oracle is committed and RUNS, the refusal is reachable only
# by NAMING an oracle that does not resolve, so the plant is `--oracle <a path that is not there>`
# and the refusal is STILL reachable by argv.  A gate whose exit 3 needs a missing FILE cannot
# plant its own surface, and a declared surface that no argv reaches is a label.
#
#   0  `--selftest` -- the gate's own seven lanes over the captured pair, and they hold.
#   1  the captured pair itself -- it really does disagree on five rows (the hand-written `py=`
#      wraps), so the honest verdict over the capture is BROKEN, and no `bend` and no oracle
#      subprocess is spent to learn it.
#   3  `--oracle <a path that does not resolve>` -- an absent subject is REFUSED, not judged.
#
# ⚠ `--plant-literal` IS NOT IN `PLANTS`, AND NEITHER ARE `--plant`, `--plant-shape` NOR
# `--plant-ansi`: `PLANTS` IS THE VERDICT SURFACE -- THE ARGV THAT REACH EACH DECLARED EXIT
# CODE -- and a plant that CORRUPTS A LANE reaches the same verdict the lane already reaches, so
# listing it would claim a second way to reach a code that has one.  THE PLANTS ARE REACHABLE
# ARGV ALL THE SAME, and the literal one is exercised by the selftest's `literal` lane, which
# runs the SAME CODE over the capture.
EXIT_SURFACE = VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}  # VERDICTS: legacy alias of EXIT_SURFACE
PLANTS = {0: ["--selftest"],
          1: ["--port-stdout", "checks/rn-port.rows", "--oracle-stdout", "checks/rn-orc.rows"],
          3: ["--oracle", "checks/__no_such_oracle__.py"]}

if __name__ == "__main__":
  sys.exit(main())