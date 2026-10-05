#!/usr/bin/env python3
"""nl-gate.py -- the gate for tinybendygrad/renderer/nir_llvmir.bend, and the `=`-bearing names.

    .venv/bin/python checks/nl-gate.py                  # live port + live oracle
    .venv/bin/python checks/nl-gate.py --unrename       # put the `=` back, in BYTES
    .venv/bin/python checks/nl-gate.py --compare A B    # the rename audit
    .venv/bin/python checks/nl-gate.py --plant ROW      # corrupt ONE VALUE
    .venv/bin/python checks/nl-gate.py --plant-shape OLD NEW   # rename a NAME
    .venv/bin/python checks/nl-gate.py --selftest
    .venv/bin/python checks/nl-gate.py --names

THE ROW SHAPE, WHICH IS WHY A NAME MAY CONTAIN A SPACE BUT NOT AN `=`:

    NAME = [<the producer's own answer>]   py=[<the other lane's answer>]

written by `r` at `nir_llvmir.bend:125`: `String.concat([nm, " = [", got, "]   py=[", want, "]\n"])`.
`rebase-gate.py:row` -- IMPORTED below, NEVER copied -- splits a row line at its FIRST `=`, so a
name carrying one has ONE NAME PER READER and the set of COMPARABLE rows becomes a property of the
reader rather than of the tree.  MEASURED on this lane before the rename, on BOTH lanes:

    205 rows -> 201 names.  8 names contained `=`, over 4 keys of 2 rows each
    (`sd cpullvm {LLVM,x86_64,arm,riscv64} osx`), so 4 rows could not be addressed by ANY name and
    4 were merely misnamed.  `rows()` keeps the LAST row on a key, so a key holding n rows costs
    n-1: 4 lost, 4 reachable.

⚠ AND THE VALUE COMPARISON ON THIS LANE IS A TAUTOLOGICAL ZERO, so THE BYTE DIFF IS THE GATE and
GUARD 0 is the only thing in this file that can be red.  MEASURED, both before and after the
rename: the port's stdout and `.agents/slop/nl/nl-oracle.py rows`'s stdout are BYTE-IDENTICAL
(md5 `1dbc8e00d43e927e34a7c358793410af` before, `4f221ed74bc5633a534bfd5d30619328` after).  Two
sides that print the same bytes agree on every value by construction, so `disagree` is 0 no matter
what the port computes, and `nir_llvmir.bend`'s own header says the same thing ("Both lanes were
measured byte-identical to each other AND to the oracle").  A name plant therefore leaves the byte
diff EMPTY and every value EQUAL, and only the name sets move -- which is exactly what
`--plant-shape` does, and why `--plant` (a value plant) is the FALSIFICATION of the name check and
not evidence for it.  The gate prints this on every run rather than leaving it to be inferred.

⚠ AND THE SUBSTRATE ON THIS LANE IS NOT STILL.  `tinybendygrad/uop/ops.bend` is in this file's
import closure (6 files) and is owned by another live unit: MEASURED, two consecutive captures of
this very port printed 206 rows and then ZERO with rc=1, naming `vd_text` (`ops.bend:7837`) and
then `vd_dbg.of` (`ops.bend:7874` -- a different line, so the file moved between the failures).
So every capture here goes through `.agents/slop/eq/lane.py`, which digests the whole closure
before and after, and a run that prints nothing is a REQUEST FOR A RETRY, never a result.

TWO THINGS THIS GATE REFUSES TO DO.  It does not write to the tree: `--plant`, `--plant-shape` and
`--unrename` rewrite CAPTURED BYTES in memory only.  And it does not accept an ambiguous row
boundary -- `row_strict` requires this lane's ` = [` to occur EXACTLY ONCE in the head and counts a
row that fails as `unreadable`, because a reader that guesses is a second reader and 156 forked
readers already exist on this project.  MEASURED on both captures of this lane: the histogram of
`head.count(" = [")` is `{1: 205}` and nothing else.
"""
import argparse, hashlib, importlib.util, pathlib, re, subprocess, sys
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
PORT = "tinybendygrad/renderer/nir_llvmir.bend"
ORACLE = [".agents/slop/nl/nl-oracle.py", "rows"]
SEP = "]   py=["      # `rebase-gate.py`'s spelling, and `r`'s own (nir_llvmir.bend:125)
ROW_OPEN = " = ["     # THIS LANE'S OWN name/value boundary, verbatim from `r`

# THE RENAME, REVERSED.  Anchored on the ROW-NAME field, so neither direction can move a value or a
# comment.  `^` plus `(?=True$|False$)`-style lookahead is not enough on its own -- a value can
# begin `True` -- so the anchor is the FULL name up to the boundary, which the lane guarantees to be
# unique per row (205 distinct names over 205 rows, measured by `--compare`).
REVERSE = (re.compile(r"^(sd cpullvm \w+ osx) (?=[A-Za-z])"), r"\1=")
REVERSE_NAME = re.compile(r"^(sd cpullvm \w+ osx) ")


def load(name):
  """`rebase-gate.py` has a `-` in its name, so it does not import by name.  ONE loader."""
  spec = importlib.util.spec_from_file_location(name, str(HERE.parent / f"{name}.py"))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


_rebase = load("rebase-gate")
rows_shipped, row_shipped = _rebase.rows, _rebase.row
"""THE PROJECT'S ONE ROW READER, IMPORTED.  `rows()` is what `rebase-scan-oracles.py` calls, so scan
  and gate cannot disagree by construction.  `row_shipped` is the PER-LINE rule `rows()` is built
  from, and the coverage delta needs it because `rows()` returns a dict and reports nothing about
  which physical line became which key -- so measuring the loss needs the rule."""


def row_strict(line):
  """(name, value, why) for ONE physical row of this lane, or (None, None, why).

  The boundary is located with `rfind`, never `find`: a name containing ` = ` would be mis-split by
  `find`, and on a lane whose value is bracketed and `py=`-delimited `rfind` cannot be.
  Ambiguity is REFUSED, not resolved -- `head.count(ROW_OPEN) != 1` returns the reason, so the
  caller prints a NUMBER instead of quietly reading a different row."""
  if not line.strip():
    return None, None, "blank"
  head, sep, tail = line.rpartition(SEP)
  if not sep:
    return None, None, "carries no `py=` column"
  if not line.rstrip().endswith("]"):
    return None, None, "does not end in `]`"
  i = head.rfind(ROW_OPEN)
  if i < 0:
    return None, None, f"no {ROW_OPEN!r} boundary"
  if head.count(ROW_OPEN) != 1:
    return None, None, f"{head.count(ROW_OPEN)} `{ROW_OPEN.strip()}` boundaries in one row"
  return head[:i].strip(), head[i + len(ROW_OPEN):].strip(), None


def rows_strict(text):
  """(rows, unreadable, duplicate names).  A duplicate name is REPORTED, never silently overwritten."""
  rows, unread, dups = {}, [], []
  for ln, line in enumerate(text.splitlines(), 1):
    if not line.strip():
      continue
    name, value, why = row_strict(line)
    if name is None:
      unread.append((ln, why, line))
    else:
      if name in rows:
        dups.append(name)
      rows[name] = value
  return rows, unread, dups


def split_py(value):
  """(the producer's own answer, its `py=` literal).  `rfind`, not `find`: a value's own closing
  bracket can precede the boundary -- `gep %v3 f32x1 i32`'s answer is
  `  %v3 = getelementptr inbounds float, float* %data0, i32 %v2`, and the row carries two
  brackets."""
  k = value.rfind(SEP)
  return (value[:k], value[k + len(SEP):]) if k >= 0 else (value, None)


def reshape(lane, text):
  """GUARD 0.  THE COVERAGE DELTA OF ONE LANE, PER LANE, and whether it is BROKEN.  Called BEFORE
  any value is compared, so a name reshape can never be reported as a value verdict.

  SIX FACTS, six different failures, each carrying the count it is a fraction OF:

    eq         names containing `=`      the ROOT CAUSE: `row` cuts there.        /physical
    reshaped   keys fed >1 DIFFERENT row two names, one key: an `=` did this.      /physical
    repeated   keys fed >1 IDENTICAL row one name printed twice: NO `=` involved. /physical
    gate_only  rows the shipped reader   a measurement no name can reach AT ALL.    /physical
               CANNOT READ AT ALL        The strongest form of the defect.
    only_*     the two readers disagree about the NAME SET, BOTH directions.        /physical
    unread     lines matching NEITHER row shape.                                   /lines
  """
  strict, unread_lines, dups = rows_strict(text)
  strict_names = set(strict)
  keys, physical, gate_only = {}, 0, []
  for line in text.splitlines():
    mine, theirs = row_strict(line)[0], row_shipped(line)
    if mine is None:
      continue
    physical += 1
    if theirs is None:
      gate_only.append(mine)            # COUNTED, NOT SKIPPED
    else:
      keys.setdefault(theirs[0], []).append(mine)
  shared = set(keys)
  # TWO KINDS OF KEY WITH MORE THAN ONE ROW, and they are different defects with the same
  # arithmetic. `reshape` = two DIFFERENT physical names landed on one key, which is what an `=`
  # in a name does. `repeated` = one physical name printed twice, which no `=` can cause and which
  # no separator change can fix. `lost` COUNTS ROWS (a key holding FOUR rows costs THREE), not
  # keys -- the census shipped a KEYS count where the quantity is rows and it read 0 on the very
  # lane where the loss was largest.
  counts = {k: len(v) for k, v in keys.items()}
  reshaped = {k: sorted(set(v)) for k, v in keys.items() if len(v) > 1 and len(set(v)) > 1}
  repeated = {k: n for k, n in counts.items() if n > 1 and len(set(keys[k])) == 1}
  lost = sum(n - 1 for n in counts.values())
  m = {"lane": lane, "physical": physical, "strict": strict_names, "shared": shared,
       "eq": sorted(n for n in strict_names if "=" in n), "reshaped": reshaped,
       "repeated": repeated, "dups": dups, "gate_only": sorted(set(gate_only)), "lost": lost,
       "unread": unread_lines, "only_shared": sorted(shared - strict_names),
       "only_strict": sorted(strict_names - shared),
       "addressable": physical - lost - len(gate_only)}
  bad = []
  if physical == 0:
    bad.append(f"{lane}: 0 rows read, so the name set is EMPTY and says nothing about coverage. "
               f"This is not a pass.")
  if m["gate_only"]:
    bad.append(f"{lane}: {len(m['gate_only'])}/{physical} row(s) the shipped reader CANNOT READ AT "
               f"ALL -- it is looking at a different row shape: {m['gate_only'][:6]}")
  if m["eq"]:
    bad.append(f"{lane}: {len(m['eq'])}/{physical} row NAME(S) CONTAIN `=`, so rebase-gate.row cuts "
               f"the name there and the two readers name {len(m['eq'])} row(s) differently: "
               f"{m['eq'][:6]}")
  if reshaped:
    top = sorted(((len(v), k) for k, v in reshaped.items()), reverse=True)
    bad.append(f"{lane}: {lost}/{physical} row(s) CANNOT BE ADDRESSED BY NAME -- two DIFFERENT "
               f"physical names landed on one key of the shipped reader and the later one silently "
               f"overwrote the earlier. (rows per key: {[(k, n) for n, k in top]})")
  if repeated:
    bad.append(f"{lane}: {sum(repeated.values()) - len(repeated)}/{physical} row(s) share a key "
               f"with another row of the SAME name -- one name printed "
               f"{max(repeated.values())}x: "
               f"{sorted(k for k, n in repeated.items() if n > 1)}. NO `=` IS INVOLVED, so this is "
               f"NOT what the separator rename fixes.")
  if m["only_shared"] or m["only_strict"]:
    bad.append(f"{lane}: the two readers disagree about the NAME SET -- {len(m['only_strict'])}/"
               f"{physical} physical names the shipped reader RESHAPES ({m['only_strict'][:6]}), and "
               f"{len(m['only_shared'])}/{physical} names the shipped reader MANUFACTURES out of a "
               f"reshape, which NO producer printed ({m['only_shared'][:6]}); the comparable rows "
               f"depend on which reader is asked, and a manufactured name must never be counted as "
               f"a row that exists")
  if unread_lines:
    bad.append(f"{lane}: {len(unread_lines)} line(s) match NEITHER row shape; first is "
               f"L{unread_lines[0][0]} ({unread_lines[0][1]}) {unread_lines[0][2].strip()[:60]!r}")
  m["bad"] = bad
  return m


def report_reshape(rs):
  """THE NAME SETS, EVERY RUN, WITH THE DENOMINATORS.  A reshaping name must be a COVERAGE DELTA
  that changes the answer, not a line of decoration above a verdict."""
  print(f"{'lane':<7} {'rows read':>9} {'names (gate)':>13} {'names (shipped)':>16} {'`=`':>4} "
        f"{'unaddressable':>13} {'unreadable':>11} {'dup names':>10}   name sets")
  for m in rs:
    same = "IDENTICAL" if not (m["shared"] ^ m["strict"]) else "DIFFER"
    print(f"{m['lane']:<7} {m['physical']:9} {len(m['strict']):13} {len(m['shared']):16} "
          f"{len(m['eq']):4} {m['lost']:13} {len(m['gate_only']):11} {len(m['dups']):10}   {same} "
          f"({len(m['strict'] & m['shared'])} shared)")
  for m in rs:
    for b in m["bad"]:
      print(f"  {b}")


def plant_value(text, name):
  """Append `PLANTED` to ONE captured VALUE, tail kept VERBATIM.  Invisible to a name-set check BY
  CONSTRUCTION -- which is why it is the falsification of the name check, not evidence."""
  out, hits = [], 0
  for line in text.splitlines():
    if not hits and line.startswith(name + ROW_OPEN):
      line = line.replace(SEP, "PLANTED" + SEP, 1)   # the FIRST `]   py=[` is the boundary
      hits += 1
    out.append(line)
  return "\n".join(out) + "\n", hits


def plant_shape(text, pairs):
  """A ROW **NAME** RENAMED, VALUES UNTOUCHED, tail kept VERBATIM.  The control `--plant` cannot
  express.  Applied on BOTH lanes: renaming one side alone trips `stray`/`ghost` and proves only
  that the reader reads names, not that the two sides' names are reader-independent.

  ⚠ AN EARLIER CONTROL REBUILT THE LINE FROM THE READER'S OWN VALUE and lost a `]`, so the row
  became a shred and the lane LOST a row for a reason that had nothing to do with the shape being
  planted.  A control must not perturb the thing it is not measuring."""
  out, hits = [], 0
  for line in text.splitlines():
    for old, new in pairs:
      if line.startswith(old + ROW_OPEN):
        line = new + line[len(old):]
        hits += 1
    out.append(line)
  return "\n".join(out) + "\n", hits


def unrename(text):
  """THE RENAME REVERSED in the CAPTURED BYTES, so the control is reproducible from the live tree
  with no second oracle and no checked-in pre-rename copy.  Anchored on the row-name field, so no
  value and no comment can move."""
  out = []
  for line in text.splitlines():
    name = row_strict(line)[0]
    if name is None:
      out.append(line)
      continue
    new = REVERSE[0].sub(r"\1=", name)
    out.append(new + line[len(name):] if new != name else line)
  return "\n".join(out) + ("\n" if text.endswith("\n") else "")


def compare(a_path, b_path):
  """THE RENAME AUDIT, BY MULTISET AND NOT BY EYE.  Four questions, each with its own count: did
  the row COUNT move; did any VALUE move (the multiset of the compared column); did any name
  COLLIDE (a name printed more than once on either side); is every renamed name exactly the old
  name with ONE separator moved.

  ⚠ THREE PLACES A NAIVE VERSION OF THIS REPORTS A NUMBER THAT CANNOT FAIL:
    * the `=` count must come from `rows_strict`'s names, NEVER from `rows_shipped`'s KEYS --
      `row()` cuts at the first `=`, so a key can never contain one and the count is a tautological
      0 over lane text that HAS the defect;
    * COLLISIONS must be counted from the LINES, never from `rows_strict`'s dict, which has already
      overwritten the duplicate;
    * "how many names were renamed" must be a name in ONE set whose one-separator partner is in the
      OTHER.  `x in A|B and reverse(x) in A|B` is true for every name when both sets agree.
  """
  A, B = pathlib.Path(a_path).read_text(), pathlib.Path(b_path).read_text()
  phys = lambda t: [row_strict(l)[0] for l in t.splitlines() if row_strict(l)[0] is not None]
  na, nb = Counter(phys(A)), Counter(phys(B))
  eq_a = sorted(n for n in na if "=" in n)
  eq_b = sorted(n for n in nb if "=" in n)
  va = Counter(split_py(v)[0] for v in rows_strict(A)[0].values())
  vb = Counter(split_py(v)[0] for v in rows_strict(B)[0].values())
  ka, kb = set(rows_shipped(A)), set(rows_shipped(B))
  only_a, only_b = set(na) - set(nb), set(nb) - set(na)
  pairs = {n for n in only_b if REVERSE_NAME.sub(r"\1=", n) in only_a}
  stray = (only_a - {REVERSE_NAME.sub(r"\1=", n) for n in pairs}) | (only_b - pairs)
  coll = {n: c for n, c in list(na.items()) + list(nb.items()) if c > 1}
  print(f"ROWS       {len(A.splitlines())} -> {len(B.splitlines())} lines; {sum(na.values())} -> "
        f"{sum(nb.values())} read; {len(na)} -> {len(nb)} distinct names -- EQUAL distinct counts "
        f"is the collision check: the rename created no name")
  print(f"VALUES     same multiset: {va == vb}   distinct {len(va)} -> {len(vb)}   only in BEFORE "
        f"{sorted((va - vb).elements())[:4]}   only in AFTER {sorted((vb - va).elements())[:4]}")
  print(f"RENAME     {len(pairs)} PAIR(S), each one name whose `X=` form is the other side's name "
        f"with a single space in place of the `=`; {len(stray)} name(s) on either side have no such "
        f"partner, and a rename that is not of this shape would be a FINDING: "
        f"{sorted(stray)[:4] or 'none'}")
  print(f"COLLISIONS {len(coll)} name(s) printed more than once, counted from the LINES and not "
        f"from `rows_strict`'s dict (which has already overwritten them): {coll or 'none'}")
  print(f"`=` NAMES  {len(eq_a)} -> {len(eq_b)}, counted from `rows_strict`'s names and NEVER from "
        f"`rows_shipped`'s keys, which cannot contain one by construction: {eq_a[:3] or 'none'} -> "
        f"{eq_b[:3] or 'none'}")
  print(f"SHIPPED    {len(ka)} -> {len(kb)} keys of `rebase-gate.py:rows()`, i.e. the rows a name "
        f"can actually address: {len(kb) - len(ka)} more")
  ok = va == vb and sum(na.values()) == sum(nb.values()) and len(na) == len(nb) and not stray
  print("AUDIT", ("OK on the RENAME -- same rows, same values, same number of distinct names, "
                 "every renamed name a one-separator move of its old name"
                 if ok else "BROKEN -- see the lines above"))
  return 0 if ok else 1


def judge(port_txt, orc_txt):
  """BROKEN wins over everything and every reason carries the NUMBER that produced it."""
  bad = []
  rs = [reshape("port", port_txt), reshape("oracle", orc_txt)]
  for m in rs:                                   # GUARD 0, BEFORE ANY VALUE IS COMPARED
    bad.extend(m["bad"])
  pr, pur, pdup = rows_strict(port_txt)
  orr, our, odup = rows_strict(orc_txt)
  if not pr:
    bad.append("the port lane produced ZERO rows")
  if not orr:
    bad.append("the oracle lane produced ZERO rows")
  for lane, u in (("port", pur), ("oracle", our)):
    if u:
      bad.append(f"{lane} lane has {len(u)} line(s) matching NEITHER row shape; first is L{u[0][0]} "
                 f"({u[0][1]}) {u[0][2].strip()[:60]!r}")
  for lane, text, rows_ in (("port", port_txt, pr), ("oracle", orc_txt, orr)):
    if rows_ and ROW_OPEN not in text:
      bad.append(f"{lane} lane produced {len(rows_)} row names but none carries `{ROW_OPEN!r}`, so "
                 f"the reader and the writer disagree about the row shape")
  stray = sorted(set(orr) - set(pr))
  if stray:
    bad.append(f"oracle rows matching no port row: {stray[:8]}")
  ghost = sorted(set(pr) - set(orr))
  if ghost:
    bad.append(f"port rows the oracle did not answer: {ghost[:8]}")
  agree, disagree, stale, gated = [], [], [], []
  for name in sorted(set(pr) & set(orr)):
    got, want = split_py(pr[name])[0], split_py(orr[name])[0]
    gated.append(name)
    (agree if got == want else disagree).append((name, got, want) if got != want else name)
    lit = split_py(pr[name])[1]
    if lit is not None and lit != want:
      stale.append((name, lit, want))
  if not gated:
    bad.append("0 gated rows: the two lanes share no row NAME, so nothing was compared. This is "
               "not a pass.")
  if disagree:
    bad.append(f"{len(disagree)} gated row(s) DISAGREE and every one is NAMED: "
               f"{[d[0] for d in disagree][:8]}\n        first `{disagree[0][0]}`:"
               f"\n        port {disagree[0][1]!r}\n        cpy  {disagree[0][2]!r}")
  return {"bad": bad, "port": pr, "oracle": orr, "gated": gated, "agree": agree,
          "disagree": disagree, "stale": stale, "reshape": rs,
          "identical_bytes": port_txt == orc_txt}


def run(argv):
  return subprocess.run(argv, cwd=REPO, capture_output=True, text=True, timeout=3600)


def md5(text):
  return hashlib.md5(text.encode()).hexdigest()[:8]


def selftest():
  """FOUR LANES OVER THE REAL 205-ROW PORT TEXT: clean / value / shape / collide.  The instrument's
  own control, so the real run's verdict can never be mistaken for the gate being broken.  `shape`
  and `collide` are BROKEN with `disagree=[]` -- EVERY VALUE AGREES -- which is the property a
  value plant cannot have."""
  live = (HERE / "nl-port-post.txt").read_text()
  if not rows_strict(live)[0]:
    print("SELFTEST ABORTED: the captured port lane is empty or unreadable, so a 'clean' lane "
          "would not be the real lane. Re-capture it; a control over a fixture that is not the "
          "fixture proves nothing.")
    return 1
  base = live
  lanes = {
    "clean": (base, base),
    "value": (plant_value(base, "ldt f32")[0], base),
    "shape": (plant_shape(base, [("ldt f32", "ldt f3=2")])[0],) * 2,
    "collide": (plant_shape(base, [("ldt f32", "ldt f=a"), ("ldt f64", "ldt f=b")])[0],) * 2,
  }
  want = {"clean": (False, 0), "value": (True, 1), "shape": (True, 0), "collide": (True, 0)}
  ok = True
  for name, (ptxt, otxt) in lanes.items():
    r = judge(ptxt, otxt)
    eq, lost = len(r["reshape"][0]["eq"]), r["reshape"][0]["lost"]
    want_broken, want_dis = want[name]
    good = bool(r["bad"]) == want_broken and len(r["disagree"]) == want_dis
    ok &= good
    print(f"  {name:<8} {'BROKEN' if r['bad'] else 'AGREE  '}  names eq={eq} unaddressable={lost} "
          f"disagree={[d[0] for d in r['disagree']]}  {'ok' if good else 'SELFTEST FAIL'}")
  print("SELFTEST", "OK -- a planted VALUE leaves the name sets identical (so the name check is "
        "not a value check in disguise) and a planted NAME is BROKEN with every value agreeing"
        if ok else "FAILED")
  return 0 if ok else 1


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--selftest", action="store_true")
  ap.add_argument("--plant", default=None, help="corrupt ONE captured VALUE (the falsification)")
  ap.add_argument("--plant-shape", nargs=2, action="append", metavar=("OLD", "NEW"),
                  help="rename a row NAME on BOTH captured lanes, values untouched. Repeatable.")
  ap.add_argument("--unrename", action="store_true",
                  help="put the `=` back in the CAPTURED BYTES, row-name field only")
  ap.add_argument("--compare", nargs=2, metavar=("BEFORE", "AFTER"))
  ap.add_argument("--names", action="store_true")
  ap.add_argument("--port-stdout", default=None)
  ap.add_argument("--oracle-stdout", default=None)
  a = ap.parse_args()
  if a.selftest:
    return selftest()
  if a.compare:
    return compare(*a.compare)
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
  if (p.returncode or o.returncode) and not (a.port_stdout or a.oracle_stdout):
    print(f"lane failure: bend {' '.join(p.stderr.split())[-140:]} | oracle "
          f"{' '.join(o.stderr.split())[-140:]}")
    print("   ⚠ `tinybendygrad/uop/ops.bend` is in this port's 6-file import closure and is owned "
          "by another live unit. MEASURED here: two captures of this port printed 206 rows and "
          "then ZERO, naming `vd_text` (ops.bend:7837) and then `vd_dbg.of` (ops.bend:7874). A "
          "zero on this lane is a REQUEST FOR A RETRY through `.agents/slop/eq/lane.py`, never a "
          "result.")
    return 1
  if not (p.stdout.strip() and o.stdout.strip()):
    print("a lane printed NOTHING, so nothing was compared. NOT a pass.")
    return 1
  if a.unrename:
    p = subprocess.CompletedProcess([], 0, unrename(p.stdout), p.stderr)
    o = subprocess.CompletedProcess([], 0, unrename(o.stdout), o.stderr)
    print(f"[unrenamed] the `=` is BACK in the row-name field of the CAPTURED BYTES "
          f"({len(REVERSE)} anchored pattern(s)). No value and no comment moved, and no file on "
          f"disk was touched.")
  if a.plant_shape:
    pt, ph = plant_shape(p.stdout, a.plant_shape)
    ot, oh = plant_shape(o.stdout, a.plant_shape)
    p, o = (subprocess.CompletedProcess([], 0, pt, p.stderr),
            subprocess.CompletedProcess([], 0, ot, o.stderr))
    print(f"[planted SHAPE] {ph}/{oh} row NAME(S) reshaped on BOTH lanes, values untouched: "
          f"{a.plant_shape}. Both lanes still agree on every value, so only a NAME-SET check can "
          f"see it. No file on disk was touched.")
  if a.plant:
    p = subprocess.CompletedProcess([], 0, plant_value(p.stdout, a.plant)[0], p.stderr)
    print(f"[planted] `{a.plant}` corrupted on the PORT LANE ONLY, in the CAPTURED OUTPUT; the "
          f"tail of the row is kept verbatim and no file on disk was touched")
  res = judge(p.stdout, o.stdout)
  print(f"port rows (rows_strict): {len(res['port'])}   oracle rows (rows_strict): "
        f"{len(res['oracle'])}   the two lanes are BYTE-IDENTICAL: {res['identical_bytes']}"
        + ("   <- the value comparison below is therefore a TAUTOLOGICAL ZERO and the BYTE DIFF "
           "is this lane's gate" if res["identical_bytes"] else ""))
  report_reshape(res["reshape"])
  if a.names:
    for m in res["reshape"]:
      for tag, s in (("GATE", m["strict"]), ("SHIP-RESIDUE", m["shared"])):
        print(f"  {m['lane']} name set, {tag} ({len(s)}):")
        for n in sorted(s):
          print(f"    {tag} {n!r}")
      manu = [n for n in sorted(m["shared"]) if n not in m["strict"]]
      if manu:
        print(f"    ^^ {len(manu)} of the {tag} names are MANUFACTURED by `row()` and were printed "
              f"by NO producer: {manu[:6]}")
  print(f"gated {len(res['gated'])}   agree {len(res['agree'])}   disagree "
        f"{[d[0] for d in res['disagree']][:8]}")
  print(f"STALE-LITERAL {len(res['stale'])} `py=` literal(s) disagree with the other lane's answer: "
        f"{[s[0] for s in res['stale']][:8]}")
  print(("BROKEN" if res["bad"] else "AGREE"), *(["\n  - " + b for b in res["bad"]]))
  return 1 if res["bad"] else 0


if __name__ == "__main__":
  sys.exit(main())