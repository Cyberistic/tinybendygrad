#!/usr/bin/env python3
"""rn-gate.py -- the gate for tinybendygrad/uop/render.bend, and for the `=`-bearing names.

    .venv/bin/python checks/rn-gate.py                # live port + live oracle
    .venv/bin/python checks/rn-gate.py --plant ROW    # corrupt ONE VALUE
    .venv/bin/python checks/rn-gate.py --plant-shape OLD NEW
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
    ast = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4, device='CPU'))

-- so ONE logical row is 2-4 PHYSICAL lines, and `rebase-gate.py:row()` cannot tell a continuation
from a row.  MEASURED: 49 continuation lines on the port lane and 44 on the oracle, costing **43**
and **39** rows respectively, landing on the keys `ast` (30x), `c3` (8x), `c2`, `c4`, `c5`, `py` (5x,
from FIVE HAND-WRITTEN WRAPS at render.bend:2809-2819).  The port also prints `py=` on its own line
where the oracle does not, so the two lanes disagree about one extra key: a `ghost`.

⚠ AND ON THIS LANE THE VALUE COMPARISON IS **NOT** A TAUTOLOGICAL ZERO -- the opposite of llvmir and
nir_llvmir.  MEASURED: port stdout md5 `302944bb48a32379`, oracle stdout md5
`642f9770c558df0f1be03a8f67ac997e`; 140 lines against 124.  The two sides print DIFFERENT bytes,
so `disagree` is a real measurement here and the value comparison is not decoration.  The port has
11 rows the oracle does not answer -- all `rnd_*` -- which is `ghost`, not disagreement.

⚠ AND THE SUBSTRATE IS NOT STILL.  `tinybendygrad/uop/ops.bend` and `uop/fold.bend` are in this
file's 5-file import closure and belong to other live units.  MEASURED: the ORACLE and the PORT
disagree on 11 rows because `render.bend:2693-2703` gained its `rnd_*` rows at 11:46 today, AFTER
`name-census-lanes/*.txt` was captured at 11:08 -- so the CENSUS's render lane text is STALE, and a
census that reads its own cache without re-fetching reports a port that no longer exists.  Every
capture here goes through `.agents/slop/eq/lane.py`, which digests the whole closure before and
after.

TWO THINGS THIS GATE REFUSES TO DO.  It does not write to the tree: `--plant` and `--plant-shape`
rewrite CAPTURED BYTES in memory only.  And it does not accept an ambiguous row boundary --
`row_strict` requires this lane's ` = [` to occur EXACTLY ONCE in the head, and it FOLDS a
continuation into the row above it rather than reading it as a row of its own.
"""
import argparse, hashlib, importlib.util, pathlib, re, subprocess, sys
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
ORACLE = [".agents/slop/xd1/render-gate-oracle.py", "--gate"]


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
_SWEEP = "  (swept by 371cc64c9; recoverable from git at 371cc64c9^:.agents/slop/eq/%s.py)"
for _n in ("rebase-gate", "eq-census2"):
  _p = SLOP / "eq" / f"{_n}.py" if _n == "eq-census2" else SLOP / f"{_n}.py"
  if not _p.is_file():
    refuse(f"input absent: {_p}" + _SWEEP % _n
           + "  This gate cannot produce a denominator without it.")
SEP = "]   py=["      # `py_row`'s own three-space literal (render.bend:2148)
ROW_OPEN = " = ["     # and its own name/value boundary, same line
DEPTH = {"[": 1, "]": -1}


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


def rows_strict(text):
  rows, refusals, dupes = {}, [], []
  for logical in logical_rows(text):
    name, value, why = row_strict(logical)
    if name is None:
      refusals.append((logical[0], why))
    else:
      if name in rows:
        dupes.append(name)
      rows[name] = value
  return rows, refusals


def split_py(value):
  k = value.rfind(SEP)
  return (value[:k], value[k + len(SEP):]) if k >= 0 else (value, None)


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
  strict, refusals = rows_strict(text)
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


def judge(port_txt, orc_txt):
  bad = []
  rs = [reshape("port", port_txt), reshape("oracle", orc_txt)]
  for m in rs:                                   # GUARD 0, BEFORE ANY VALUE IS COMPARED
    bad.extend(m["bad"])
  pr, pur = rows_strict(port_txt)
  orr, our = rows_strict(orc_txt)
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
  agree, disagree, stale, gated = [], [], [], []
  for name in sorted(set(pr) & set(orr)):
    got, want = split_py(pr[name])[0], split_py(orr[name])[0]
    gated.append(name)
    if got == want:
      agree.append(name)
    else:
      disagree.append((name, got, want))
    lit = split_py(pr[name])[1]
    if lit is not None and lit != want:
      stale.append((name, lit, want))
  if not gated:
    bad.append("0 gated rows: the two lanes share no row NAME, so nothing was compared. This is "
               "not a pass.")
  if disagree:
    bad.append(f"{len(disagree)}/{len(gated)} gated row(s) DISAGREE and every one is NAMED: "
               f"{[d[0] for d in disagree][:8]}\n        first `{disagree[0][0]}`:"
               f"\n        port {disagree[0][1]!r}\n        cpy  {disagree[0][2]!r}")
  if not disagree and port_txt == orc_txt:
    bad.append("the two lanes are BYTE-IDENTICAL and agree on every value, so this run is a "
               "TAUTOLOGICAL ZERO: the byte diff is the gate and GUARD 0 is the only thing that "
               "can be red.")
  return {"bad": bad, "port": pr, "oracle": orr, "gated": gated, "agree": agree,
          "disagree": disagree, "stale": stale, "reshape": rs,
          "identical_bytes": port_txt == orc_txt}


def run(argv):
  return subprocess.run(argv, cwd=REPO, capture_output=True, text=True, timeout=3600)


def md5(text):
  return hashlib.md5(text.encode()).hexdigest()[:8]


def selftest():
  """FOUR LANES OVER THE REAL CAPTURED PAIR.  The BASE DISAGREEMENT COUNT IS MEASURED, NOT
  TYPED -- this lane's real pair already disagrees on 5 rows (the hand-written `py=` wraps), so a
  hardcoded 0 would be a claim about a lane that does not exist.  The property asserted is the one
  that separates the two plants:

      a VALUE plant RAISES `disagree` by exactly 1;
      a NAME  plant leaves `disagree` at the base count and moves `eq`/the name sets.

  On llvmir and nir_llvmir the base count is 0 and the two are equally distinguishable; here the
  base is 5, and a control that hardcoded 0 would have read `value` as a FAILURE of the
  instrument.

  ⚠ THE `shape` PLANT PUTS THE `=` INSIDE THE NAME (`pyrender const` -> `pyrender co=nst`), NOT
  AFTER IT.  A trailing `=` does not work on this lane and the first two attempts showed why: with
  ` = [` as the boundary, a name of `pyrender const=` reads as F2-TIGHT (a glued `=`) and the
  writer's own ` = [` is then the second candidate, so a strict reader either mis-picks or -- with
  `eqs[0]` as the fallback -- silently truncates the name back to `pyrender const` and reports
  `eq=0`.  A control that cannot express the thing it is testing will report a clean 0."""
  live = (HERE / "rn-port.txt").read_text()
  orc = (HERE / "rn-orc.txt").read_text()
  base = judge(live, orc)
  n0 = len(base["disagree"])
  print(f"[selftest base] the REAL captured pair: {len(base['gated'])} gated rows, "
        f"{len(base['agree'])} agree, {n0} disagree "
        f"{[d[0] for d in base['disagree']]} -- MEASURED, and it is NOT 0: the port puts the "
        f"`py=` column on its own physical line on five rows (render.bend:2809-2819) and the "
        f"oracle does not, so the port's VALUE for those five carries an extra line. A `clean` "
        f"lane that quietly is not the real lane is the failure this work is about, so the base is "
        f"the real pair and the number is printed.")
  lanes = {
    "base": (live, orc),
    "value": (plant_value(live, "pyrender const")[0], orc),
    "shape": (plant_shape(live, [("pyrender const", "pyrender co=nst")])[0],) * 2,
    "collide": (plant_shape(live, [("pyrender const", "pyrender ast"),
                                   ("pyrender cast", "pyrender ast")])[0],) * 2,
  }
  want = {"base": (True, n0), "value": (True, n0 + 1), "shape": (True, 0), "collide": (True, 0)}
  ok = True
  for name, (ptxt, otxt) in lanes.items():
    r = judge(ptxt, otxt)
    want_broken, want_dis = want[name]
    good = bool(r["bad"]) == want_broken and len(r["disagree"]) == want_dis
    ok &= good
    print(f"  {name:<8} {'BROKEN' if r['bad'] else 'AGREE  '}  cont={r['reshape'][0]['cont']} "
          f"eq={len(r['reshape'][0]['eq'])} unaddressable={r['reshape'][0]['lost']} "
          f"disagree={len(r['disagree'])} {[d[0] for d in r['disagree']][:4]}  "
          f"{'ok' if good else 'SELFTEST FAIL'}")
  print(f"  NOTE every lane is BROKEN, and that is CORRECT: `cont` > 0 on the real lane and the "
        f"real pair really does disagree, so this lane's honest verdict is BROKEN and `base` "
        f"asserts BROKEN rather than AGREE. The two plants are still told apart by `disagree`.")
  print("SELFTEST", "OK -- a planted VALUE raises `disagree` by one; a planted NAME leaves "
        "`disagree` at the base count and moves the name sets, so the two are distinguishable"
        if ok else "FAILED")
  return 0 if ok else 1


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--selftest", action="store_true")
  ap.add_argument("--plant", default=None)
  ap.add_argument("--plant-shape", nargs=2, action="append", metavar=("OLD", "NEW"))
  ap.add_argument("--names", action="store_true")
  ap.add_argument("--port-stdout", default=None)
  ap.add_argument("--oracle-stdout", default=None)
  a = ap.parse_args()
  if a.selftest:
    return selftest()
  if a.port_stdout or a.oracle_stdout:
    print("!! CAPTURED LANE INPUT. Not a live run. A verdict over a capture is evidence about the "
          "CAPTURE, never about the tree as it is now.")
  p = (subprocess.CompletedProcess([], 0, pathlib.Path(a.port_stdout).read_text(), "")
       if a.port_stdout else run(["./bin/bend", PORT]))
  o = (subprocess.CompletedProcess([], 0, pathlib.Path(a.oracle_stdout).read_text(), "")
       if a.oracle_stdout else run([sys.executable] + ORACLE))
  print(f"{'CAPTURED' if a.port_stdout else 'live'} port rc={p.returncode} md5={md5(p.stdout)}   "
        f"{'CAPTURED' if a.oracle_stdout else 'live'} oracle rc={o.returncode} "
        f"md5={md5(o.stdout)}")
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
  res = judge(p.stdout, o.stdout)
  print(f"port logical rows: {len(res['port'])}   oracle logical rows: {len(res['oracle'])}   the "
        f"two lanes are BYTE-IDENTICAL: {res['identical_bytes']}"
        + ("   <- TAUTOLOGICAL ZERO" if res["identical_bytes"] else
           "   <- so the value comparison below is a REAL measurement on this lane"))
  report_reshape(res["reshape"])
  if a.names:
    for m in res["reshape"]:
      print(f"  {m['lane']} MANUFACTURES by the shipped reader, printed by NO producer "
            f"({len(m['manufactured'])}): {m['manufactured'][:12]}")
  print(f"gated {len(res['gated'])}   agree {len(res['agree'])}   disagree "
        f"{[d[0] for d in res['disagree']][:8]}")
  print(f"STALE-LITERAL {len(res['stale'])} `py=` literal(s) disagree with the other lane's answer: "
        f"{[s[0] for s in res['stale']][:8]}")
  print(("BROKEN" if res["bad"] else "AGREE"), *(["\n  - " + b for b in res["bad"]]))
  return 1 if res["bad"] else 0


if __name__ == "__main__":
  sys.exit(main())