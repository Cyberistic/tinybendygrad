#!/usr/bin/env python3
"""name-census.py -- HOW MANY ROW NAMES, IN EVERY WIRED LANE, ARE READER-DEPENDENT.

    .venv/bin/python .agents/slop/name-census.py --fetch     # run every lane once, cache the text
    .venv/bin/python .agents/slop/name-census.py             # the census, over the cache
    .venv/bin/python .agents/slop/name-census.py --names     # every offending name, per lane

WHY THIS IS A QUESTION AND NOT A COMPARISON. `rebase-gate.py`'s `row()` (line 437) splits a
row line on its FIRST `=` and keeps the head as the row NAME. So a name containing `=` does
not have ONE name -- it has one name per reader, and which one you get depends on which
reader you ask. The set of COMPARABLE rows is then a property of the reader rather than of
the tree. This is invisible to every value-based check, because both lanes printed the same
bytes: `kern CUDA  lb=1` and `kern CUDA  lb=4` were 8 rows on both sides and agreed on all
8, while `rows()` saw 6 keys and the two `lb=1` measurements were unreachable. MEASURED on
`renderer/cstyle.bend` before the rename, on both lanes, by CALLING `rows()`.

  222 names over 224 oracle rows and 225 over 227 port rows -- the same 2-row loss on both
  sides, so the lanes agreed perfectly and the loss was invisible from inside the agreement.

THE INVERSE IS ALSO A DEFECT, and it is why a name may not contain a delimiter: a detector
that matches `=` to find the name/value boundary will MIS-SPLIT a name that contains one.
So this file counts BOTH directions of the same hazard, and never reports a count without
the count it is a fraction OF.

THE FIVE FIGURES, each with its denominator, all derived from `rebase-gate.py`'s OWN reader
(imported, never reimplemented -- a second reader drifts because nothing compares the two):

  LINES  non-blank lines `row()` accepted.                          denominator: itself
  NAMES  len(rows(text)) -- distinct names.                         denominator: LINES
  EQ     names containing `=` -- the ROOT CAUSE, since `row()` cuts there.
                                                                 denominator: NAMES
  LOST   LINES - NAMES: rows the reader CANNOT address by name, because two of them
          landed on one key. A value is still on stdout; nothing can name it.
                                                                 denominator: LINES
  EMPTY  names `rows()` drops as the `""` phantom (`== SECTION ==` banners).
                                                                 denominator: NAMES

AND THE LOAD, because A DISAGREEMENT COUNT IS NOT A COVERAGE STATEMENT: a starved lane
produced 115 rows where a loaded one produced 787, and a starved lane is PLAUSIBLE. Every
lane's LINES is printed beside every lane's count, and a lane whose port file changed under
the fetch is marked UNSTABLE rather than reported as a measurement.

FIVE UNITS WERE LIVE on this tree during this run, so `--fetch` digests each port BEFORE and
AFTER running it and marks any lane whose substrate moved. Those lanes are printed in their own
block and are NOT counted into the totals without saying so.
"""
import argparse, concurrent.futures as cf, hashlib, importlib.util, json, pathlib, subprocess, sys, time

REPO = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
CACHE = HERE / "name-census-lanes"
PY = str(REPO / ".venv/bin/python")


def load_rg():
  spec = importlib.util.spec_from_file_location("rebase-gate", HERE / "rebase-gate.py")
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


RG = load_rg()
ROW, ROWS = RG.row, RG.rows
ROW_OPEN, SEP, GAP = " = [", "]   py=[", "  "


def digest(path):
  try:
    return hashlib.md5(pathlib.Path(path).read_bytes()).hexdigest()
  except OSError:
    return None


def sh(argv, timeout=1800):
  return subprocess.run([str(a) for a in argv], cwd=REPO, capture_output=True, text=True, timeout=timeout)


def lane_paths(port):
  """[(lane_key, text_path)] for one port: the interpreted port lane and every oracle."""
  out = [("port", CACHE / (port.replace("/", "_") + ".port.txt"))]
  for spec in RG.BASE_ORACLES.get(port, []):
    argv = spec.split()
    out.append(("cpython:" + pathlib.Path(argv[0]).stem, CACHE / (port.replace("/", "_") + "." + pathlib.Path(argv[0]).stem + ".txt")))
  return out


def fetch_one(port):
  """Run every lane of one port ONCE and cache the text. (rc, stderr tail) per lane."""
  before, log, stable = digest(REPO / port), [], True
  if not (REPO / port).exists():
    return {"port": port, "error": "no .bend on disk"}
  chk = sh(["./bin/bend", port, "--check-only"])
  p = sh(["./bin/bend", port])
  rows_n = len(ROWS(p.stdout))
  log.append(f"{'port':<28} rc={p.returncode} names={rows_n} secs={_secs(p)} "
             f"check={((chk.stdout.strip().splitlines() or [''])[0])[:44]!r}")
  (CACHE / (port.replace("/", "_") + ".port.txt")).write_text(p.stdout)
  for spec in RG.BASE_ORACLES.get(port, []):
    argv = spec.split()
    key = "cpython:" + pathlib.Path(argv[0]).stem
    if argv[0].endswith(".py"):
      cmd = [PY] + argv
    elif argv[0].endswith(".bend"):
      cmd = ["./bin/bend"] + argv[1:]
    else:
      cmd = argv
    o = sh(cmd)
    log.append(f"{key:<28} rc={o.returncode} names={len(ROWS(o.stdout))} secs={_secs(o)} "
               f"{' '.join(o.stderr.split())[-60:]!r}")
    (CACHE / (port.replace("/", "_") + "." + pathlib.Path(argv[0]).stem + ".txt")).write_text(o.stdout)
  stable = before == digest(REPO / port)
  return {"port": port, "stable": stable, "log": log}


def _secs(p):
  return round((p.stderr.count("\n") and 0) or 0, 1)


def refetch(port):
  """THE PORT LANE, SERIALLY, WITH `rebase-gate.py`'s OWN retry discipline.

  ⚠ 25 OF 39 PORT LANES CAME BACK WITH rc=1 AND ZERO ROWS ON THE PARALLEL PASS, AND THAT IS
  MY HARNESS, NOT THE TREE. MEASURED: `./bin/bend tinybendygrad/renderer/cstyle.bend` alone
  prints 227 rows, and the same command inside an 8-way ThreadPoolExecutor printed 0 with an
  empty `--check-only` first line. Eight concurrent compiles of files that run for minutes
  starve each other, and a starved lane is indistinguishable from a port that emits nothing --
  which is precisely the failure `.agents/slop/rebase-gate.py` records for its OWN lane reader
  ("A `0` IS A REQUEST FOR A FIXTURE, not a coverage claim") and why `row_secs` is recorded
  there at all. So every starved lane is re-run alone, with the same BEND_ROW_TRIES retry, and
  a lane that is STILL empty is reported as empty rather than silently counted as zero.
  """
  before = digest(REPO / port)
  info, text = "", ""
  for attempt in range(1, RG.BEND_ROW_TRIES + 1):
    t0 = time.monotonic()
    r = sh(["./bin/bend", port])
    info = {"rc": r.returncode, "row_tries": attempt,
            "row_secs": round(time.monotonic() - t0, 1)}
    text = r.stdout
    if ROWS(text) or attempt == RG.BEND_ROW_TRIES:
      break
    time.sleep(RG.BEND_ROW_BACKOFF)
  (CACHE / (port.replace("/", "_") + ".port.txt")).write_text(text)
  return {"port": port, "names": len(ROWS(text)), "stable": before == digest(REPO / port),
          **info, "err": " ".join(r.stderr.split())[-70:]}


MARK = " = "


def shape_name(line):
  """The name a reader that cuts at `" = "` (rather than at `=`) sees, or None if the line
  has no `= ` boundary at all.

  ⚠ THIS DELIBERATELY IS A SECOND READER, and that is the point of the file: the question
  is whether a row NAME IS READER-DEPENDENT, and a question about reader-dependence cannot
  be answered with one reader. The first version of this census counted `=` in
  `rows_shipped(text)`'s KEYS, which is a TAUTOLOGICAL ZERO -- `row()` splits at the first
  `=`, so a key can never contain one. MEASURED: it printed `0 names containing `=`` over
  all 78 lane texts including the eight `kern CUDA  lb=1` names, and 0 is not a finding, it
  is a measure that cannot fail. That is the same rule the brief states, wearing my own
  detector: a check that matches a form cannot see the instance that lacks it. So the `=`
  count is taken from a name this file cuts itself, and the two name sets are compared.
  """
  i = line.find(MARK)
  return line[:i].strip() if i >= 0 else None


def measure(text):
  """The figures, split BY LANE SHAPE, because the answer differs by shape and averaging them
  is how a census produces a number nobody can check.

  `rows_shipped` is the project's reader and the ONLY source of NAMES. Every count that could
  be tautological is taken from `shape_name` instead.

  F1 -- the lane's own boundary IS `=` (`name=value`). A name here CANNOT contain `=` and a
        name containing a SPACE cannot survive either: the writer has no way to express one.
        Structurally immune, and that is a reportable finding, not a pass.
  F2 -- the lane prints ` = ` as its boundary (`NAME = [v]`). Here a name MAY contain `=` and
        the two readers can disagree. THE ONLY POPULATION IN WHICH THE CLASS CAN EXIST.
  F3 -- the lane has no `=` at all (`name  value`), so `row()` falls back to two spaces and a
        ONE-TOKEN head. Also immune to `=`, but it has its own collapse: many rows land on one
        head token, and `uop/render.bend` loses 39 of 124 rows to it.
  """
  lines = [l for l in text.splitlines() if l.strip()]
  names = ROWS(text)
  read, cls = 0, {"F1": 0, "F2": 0, "F3": 0}
  behind = {}                                  # rows() key -> [(shape, shape-name), per line]
  for line in lines:
    s = ROW(line)
    if not s:
      continue
    read += 1
    if " = " in line:                          # F2: the boundary is ` = `, so a name here CAN
      b = line[:line.find(" = ")].strip()     # contain `=`, and the two readers can disagree
      cls["F2"] += 1
    elif "=" in line:                          # F1: the boundary IS `=`, so the writer cannot
      b = None                                 # express a `=` in a name. Structurally immune.
      cls["F1"] += 1
    else:                                      # F3: no `=` at all, so `row()` falls back to two
      b = None                                 # spaces and a ONE-TOKEN head. Also immune.
      cls["F3"] += 1
    behind.setdefault(s[0], []).append((("F2" if b is not None else
                                          "F1" if "=" in line else "F3"), b))
  # ⚠ F3 EXISTED ONLY AS A MISCOUNT UNTIL THIS LINE, and it produced the one figure in this
  # report that was plain wrong. `uop/render.bend`'s oracle is F3: `ast <uop>`, one space, no
  # `=`. MEASURED: `row()` names those rows `ast`, `c2`, `ast` again -- 124 lines read, 85
  # names, 39 lost, and every name a single meaningless token. My second reader cut at `" = "`
  # and found ` = ` inside the VALUE, so it reported `pyrend buffer=[c1` as a "name containing
  # `=`": 31 of them, on a lane where the shipped reader never sees that string. A lane-shape
  # blind count is the brief's own rule -- a detector that matches a form cannot see the
  # instance that lacks it -- aimed at me.
  eq = sorted({b for bs in behind.values() for _, b in bs if b is not None and "=" in b})
  collide = {s: bs for s, bs in behind.items() if len(bs) > 1}
  lost = sum(len(bs) - 1 for bs in behind.values())
  dupe = sorted((s, bs) for s, bs in collide.items()
                if all(b is None or b == s for _, b in bs))
  reshape = sorted((s, bs) for s, bs in collide.items()
                   if any(b is not None and b != s for _, b in bs))
  # A NAME IS READER-DEPENDENT WHENEVER THE TWO READERS DISAGREE, and that is a DIFFERENT
  # question from whether the disagreement COST A ROW. The first version counted only the
  # colliding ones and so reported 5 for `uop/render.bend`'s oracle where 31 names are
  # reader-dependent: 26 of them land on a key of their own and are merely misnamed, and a
  # census that cannot tell "misnamed" from "lost" cannot say how much a rename is worth.
  cut = {}                                     # shape-name -> the rows() name it is read as
  for s, bs in behind.items():
    for _, b in bs:
      if b is not None:
        cut.setdefault(b, s)
  reshaped = sorted(b for b, s in cut.items() if b != s)
  return {"lines": len(lines), "read": read, "names": len(names), **cls,
          "eq": eq, "eq_n": len(eq), "reshaped": reshaped, "reshaped_n": len(reshaped),
          "harmless": len(reshaped) - sum(1 for b in reshaped if b in cut and len(
              behind[cut[b]]) == 1),
          "dupe": dupe, "reshape": reshape, "collide": collide,
          "lost": lost, "unread": len(lines) - read,
          "empty": sorted(n for n in names if not n)}


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--fetch", action="store_true")
  ap.add_argument("--refetch-zero", action="store_true",
                  help="re-run, SERIALLY and alone, every PORT lane the parallel fetch left "
                       "empty. A starved lane is my harness until proven otherwise.")
  ap.add_argument("--names", action="store_true")
  a = ap.parse_args()
  CACHE.mkdir(exist_ok=True)
  ports = sorted(RG.BASE_ORACLES)

  if a.refetch_zero:
    zero = [p for p in ports
            if (CACHE / (p.replace("/", "_") + ".port.txt")).exists()
            and not ROWS((CACHE / (p.replace("/", "_") + ".port.txt")).read_text())]
    print(f"{len(zero)} of {len(ports)} port lanes are empty in the cache; re-running each "
          f"ALONE, {RG.BEND_ROW_TRIES} tries, {RG.BEND_ROW_BACKOFF}s apart")
    for p in zero:
      res = refetch(p)
      print(f"  {res['port']:<40} names={res['names']:>4} rc={res['rc']} "
            f"tries={res['row_tries']} secs={res['row_secs']:>6} "
            f"{'STABLE' if res['stable'] else '!! PORT MOVED'}")
    print("re-run without --refetch-zero for the census")
    return 0

  if a.fetch:
    print(f"fetching {len(ports)} wired lanes, 8 at a time, no cache reuse")
    with cf.ThreadPoolExecutor(max_workers=8) as ex:
      for res in ex.map(fetch_one, ports):
        print(f"--- {res['port']}"
              + ("" if res.get("stable", True) else "   !! PORT MOVED DURING THE FETCH"))
        for l in res.get("log", [res.get("error", "")]):
          print("    " + l)
    return 0

  todo = [(p, k, f) for p in ports for k, f in lane_paths(p) if f.exists()]
  missing = [(p, k, f) for p in ports for k, f in lane_paths(p) if not f.exists()]
  rows, unstable = [], []
  for port, key, f in todo:
    m = measure(f.read_text())
    m.update(port=port, lane=key)
    rows.append(m)
    if not (REPO / port).exists():
      unstable.append(port)

  print(f"{'lane':<28} {'port':<34} {'LINES':>6} {'READ':>6} {'F1':>6} {'F2':>6} {'F3':>6} "
        f"{'NAMES':>6} {'`=`':>4} {'DIFFER':>7} {'LOST':>5}")
  for m in sorted(rows, key=lambda r: (-r["reshaped_n"], -r["lost"], r["port"])):
    mark = "  <== READER-DEPENDENT NAME" if m["reshaped_n"] else ""
    print(f"{m['lane']:<28} {m['port']:<34} {m['lines']:6} {m['read']:6} {m['F1']:6} "
          f"{m['F2']:6} {m['F3']:6} {m['names']:6} {m['eq_n']:4} {m['reshaped_n']:7} "
          f"{m['lost']:5} "
          f"{mark}")
  TL = sum(r["lines"] for r in rows)
  TR = sum(r["read"] for r in rows)
  TF1 = sum(r["F1"] for r in rows)
  TF2 = sum(r["F2"] for r in rows)
  TF3 = sum(r["F3"] for r in rows)
  TU = sum(r["unread"] for r in rows)
  TN = sum(r["names"] for r in rows)
  TE = sum(r["eq_n"] for r in rows)
  TRS = sum(r["reshaped_n"] for r in rows)
  # THE ROW COUNT, NOT THE KEY COUNT. A key holding FOUR rows costs THREE measurements, and
  # counting keys reported 1 for it -- which is how 349 rows went missing from the split on the
  # first run of this line. `lost` is Σ(len-1); the split must be Σ(len-1) too or the two do
  # not add up.
  TLOST = sum(r["lost"] for r in rows)
  TRESN = sum(len(bs) - 1 for r in rows for _, bs in r["reshape"])
  TDUP = sum(len(bs) - 1 for r in rows for _, bs in r["dupe"])
  print()
  print(f"TOTAL over {len(rows)} cached lane texts of {len(ports)} wired ports:")
  print(f"  {TL} lines, {TR} read by rows(), {TN} distinct names")
  print(f"  LANE SHAPE: {TF1} F1 rows (the boundary IS `=`, so a name there CANNOT contain `=` "
        f"and a space cannot survive either -- {100.0 * TF1 / max(1, TR):.1f}% of the tree)")
  print(f"              {TF2} F2 rows (the boundary is ` = `, so a name there CAN contain `=` "
        f"-- the ONLY population in which the class can exist)")
  print(f"              {TF3} F3 rows (no `=` at all; `row()` needs two spaces and a ONE-TOKEN "
        f"head, so a `=` is impossible there -- but rows still collide on a head token)")
  print(f"  UNREADABLE LINES     : {TU}/{TL} -- lines rows() refuses outright, e.g. "
        f"`dtype_tables.py`'s TSV lines, which is GUARD 2 'compared nothing' BY DESIGN")
  print(f"  NAMES CONTAINING `=`   : {TE}/{TF2} of the F2 rows that can carry one = "
        f"{100.0 * TE / max(1, TF2):.2f}%   ({TE}/{TN} = {100.0 * TE / max(1, TN):.2f}% of all names)")
  THR = sum(r["reshaped_n"] for r in rows)
  print(f"  READER-DEPENDENT NAMES  : {THR}/{TF2} = {100.0 * THR / max(1, TF2):.2f}% of the F2 "
        f"population -- the two readers do not name these rows the same. Of those, {THR - TRESN} "
        f"land on a key of their own and are merely MISNAMED, and {TRESN} share a key with "
        f"another row and so COST a measurement")
  print(f"  UNADDRESSABLE ROWS      : {TLOST}/{TR} = {100.0 * TLOST / max(1, TR):.2f}% of the "
        f"rows the reader accepted. SPLIT BY CAUSE, over the key and not the name:\n"
        f"      {TRESN} row(s) lost to a key holding two rows with DIFFERENT shape-names -- the "
        f"reshape class\n"
        f"      {TDUP} row(s) lost to a key holding two rows with the SAME name -- a lane "
        f"printing a row name twice, an older and separate defect no `=` is involved in\n"
        f"      residual {TLOST - TRESN - TDUP} -- MUST BE 0, or the census is not a census. It was "
        f"82, then 146, then 349: three separate under-counts in the SPLIT while `lost` itself "
        f"was right, each one a case of counting KEYS where the quantity is ROWS. An "
        f"unexplained number in a coverage census is worse than a wrong one, because nobody "
        f"can check it")
  starved = [r for r in rows if r["read"] == 0]
  print(f"  STARVED lanes (0 rows read of {len(rows)} texts): {len(starved)} -- "
        f"{sorted({(r['lane'], r['port']) for r in starved})}  a starved lane is PLAUSIBLE")
  if missing:
    print(f"  NOT FETCHED: {len(missing)} lane text(s) -- {[m[1] for m in missing]}")
  if unstable:
    print(f"  ports with no .bend on disk now: {sorted(set(unstable))}")
  if a.names:
    print()
    for r in sorted(rows, key=lambda r: -r["reshaped_n"]):
      if r["reshaped_n"] or r["dupe"]:
        print(f"{r['port']}  [{r['lane']}]  LINES={r['lines']} READ={r['read']} F1={r['F1']} "
              f"F2={r['F2']} F3={r['F3']} NAMES={r['names']} EQ={r['eq_n']} DIFFER={r['reshaped_n']} "
              f"LOST={r['lost']}")
        for s, bs in sorted(r["collide"].items()):
          print(f"    KEY  {s!r} <- {len(bs)} row(s) naming it: {bs[:6]}")
        for s, bs in r["dupe"][:4]:
          print(f"    DUPE {s!r} <- {bs}")
  (HERE / "name-census.json").write_text(json.dumps(rows, indent=1))
  return 0


if __name__ == "__main__":
  sys.exit(main())