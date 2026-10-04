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


def measure(text):
  """The five figures, from `rebase-gate.py`'s own reader and nothing else."""
  lines = [l for l in text.splitlines() if l.strip()]
  read = [l for l in lines if ROW(l)]
  names = ROWS(text)
  eq = sorted(n for n in names if "=" in n)
  empty = sorted(n for n in names if not n)
  return {"lines": len(lines), "read": len(read), "names": len(names),
          "eq": eq, "eq_n": len(eq), "lost": len(read) - len(names), "empty": len(empty)}


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--fetch", action="store_true")
  ap.add_argument("--names", action="store_true")
  a = ap.parse_args()
  CACHE.mkdir(exist_ok=True)
  ports = sorted(RG.BASE_ORACLES)

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

  print(f"{'lane':<28} {'port':<34} {'LINES':>6} {'NAMES':>6} {'EQ':>4} {'LOST':>5}  load")
  for m in sorted(rows, key=lambda r: (-r["eq_n"], -r["lost"], r["port"])):
    mark = "" if m["eq_n"] == 0 else "  <== NAME CONTAINS '='"
    print(f"{m['lane']:<28} {m['port']:<34} {m['lines']:6} {m['names']:6} "
          f"{m['eq_n']:4} {m['lost']:5}  {m['read']}/{m['lines']} lines read{mark}")
  TL = sum(r["lines"] for r in rows)
  TN = sum(r["names"] for r in rows)
  TE = sum(r["eq_n"] for r in rows)
  TLOST = sum(r["lost"] for r in rows)
  print()
  print(f"TOTAL over {len(rows)} cached lane texts of {len(ports)} wired ports: "
        f"{TL} lines, {TN} names, {TE} names containing `=`, {TLOST} rows the reader "
        f"cannot address by name")
  print(f"  `=` names as a fraction of NAMES: {TE}/{TN} = "
        f"{(100.0 * TE / TN if TN else 0):.2f}%")
  print(f"  unaddressable rows as a fraction of LINES the reader accepted: "
        f"{TLOST}/{sum(r['read'] for r in rows)} = "
        f"{(100.0 * TLOST / max(1, sum(r['read'] for r in rows))):.2f}%")
  starved = [r for r in rows if r["read"] == 0]
  print(f"  STARVED lanes (0 rows read of {len(rows)} texts): {len(starved)} -- "
        f"{[r['port'] for r in starved]}  a starved lane is PLAUSIBLE, not a defect")
  if missing:
    print(f"  NOT FETCHED: {len(missing)} lane text(s) -- {[m[1] for m in missing]}")
  if unstable:
    print(f"  ports with no .bend on disk now: {sorted(set(unstable))}")
  if a.names:
    print()
    for r in sorted(rows, key=lambda r: -r["eq_n"]):
      if r["eq_n"] or r["lost"]:
        print(f"{r['port']}  [{r['lane']}]  LINES={r['lines']} NAMES={r['names']} "
              f"EQ={r['eq_n']} LOST={r['lost']}")
        for n in r["eq"]:
          print(f"    EQ  {n!r}")
  (HERE / "name-census.json").write_text(json.dumps(rows, indent=1))
  return 0


if __name__ == "__main__":
  sys.exit(main())