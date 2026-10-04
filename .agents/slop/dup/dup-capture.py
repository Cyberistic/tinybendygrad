#!/usr/bin/env python3
"""dup-capture.py -- RE-CAPTURE EVERY LANE OF THE DUPLICATE CENSUS, LIVE, BOTH SIDES.

    .venv/bin/python .agents/slop/dup/dup-capture.py --ports
    .venv/bin/python .agents/slop/dup/dup-capture.py --oracles

WHY A RE-CAPTURE AND NOT THE CACHE.  `.agents/slop/eq/lanes/` is documented stale by the unit
that wrote it -- `uop/render.bend`'s cached text is 129 lines where the live one is 140 -- and a
census that reads a stale cache reports a revision nobody has.  So every lane text this census
uses is produced HERE, now, by the real process.

THE PORT LANES GO THROUGH `.agents/slop/eq/lane.py`, IMPORTED, because that file exists for one
reason: every closure of these lanes contains `tinybendygrad/uop/ops.bend`, another live unit's
file, and three captures on this tree have gone from 206 rows to ZERO by naming two DIFFERENT
lines of it.  `lane.py` digests the whole import closure before and after, prints the load, and
exits non-zero on a zero-row or mid-edit capture.  **A ZERO HERE IS A RETRY REQUEST, NOT A
RESULT**, and this driver retries, because the alternative -- reporting a starved lane -- is the
failure this whole unit is about.

THE ORACLE LANES RUN CPYTHON.  The port/oracle argv comes from `rebase-gate.py`'s own
`BASE_ORACLES`, IMPORTED, so the pairing is not re-typed here: two entry tables for one
question is how a lane ends up comparing a port against the wrong oracle.
"""
import argparse, importlib.util, json, pathlib, shlex, subprocess, sys, time

HERE = pathlib.Path(__file__).resolve().parent
SLOP = HERE.parent
REPO = HERE.parents[2]
OUT = HERE / "lanes"
TRIES = 3


def load(path, name):
  spec = importlib.util.spec_from_file_location(name, str(path))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


RG = load(SLOP / "rebase-gate.py", "rebase_gate")
LANE = load(SLOP / "eq" / "lane.py", "eq_lane")


def key_of(port):
  """`BASE_ORACLES`'s keys are REPO-RELATIVE, so `.resolve()` first: `relative_to()` on a
  relative path raises, and a capture driver that dies on the first port reports zero lanes
  covered rather than zero lanes found."""
  return str(pathlib.Path(port).resolve().relative_to(REPO)).replace("/", "_")


def oracles_list(entry):
  """`BASE_ORACLES` values are a STRING containing the whole command line (`tcptx-oracle.py
  stage2`, `render-gate-oracle.py --gate`), not a list of argv -- except two entries, which are
  one-element lists.  Iterating a string yields CHARACTERS, so the first version of this driver
  ran `python .` 39 times and reported "no oracle answered" for every lane in the tree: a
  plausible-looking table of 39 FAILs that is entirely a bug in the driver.  Both shapes are
  accepted and the shape is PRINTED, because "the oracle died" and "the driver passed a
  character" are different failures with the same symptom."""
  if isinstance(entry, str):
    return [shlex.split(entry)]
  return [list(x) if isinstance(x, (list, tuple)) else shlex.split(x) for x in entry]


def capture_port(port, tries=TRIES):
  """`lane.py` is driven in-process, because it is the shared closure-digesting capture and
  importing it is the whole point -- a second capture driver would be a second reader."""
  out = OUT / f"{key_of(port)}.port.txt"
  last = ""
  for k in range(tries):
    r = subprocess.run([sys.executable, str(SLOP / "eq" / "lane.py"), "--port", str(port),
                        "--out", str(out.with_suffix(""))], cwd=REPO, capture_output=True, text=True)
    last = r.stdout.strip()
    if r.returncode == 0 and out.exists() and out.stat().st_size:
      return True, k + 1, last
    time.sleep(2 * (k + 1))
  return False, tries, last


def capture_oracle(argv, out, tries=TRIES):
  for k in range(tries):
    p = subprocess.run([sys.executable] + argv, cwd=REPO, capture_output=True, text=True)
    if p.returncode == 0 and p.stdout.strip():
      out.write_text(p.stdout)
      return True, k + 1, ""
    time.sleep(1 * (k + 1))
  out.write_text(p.stdout)
  return False, tries, " ".join(p.stderr.split())[-160:]


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--ports", action="store_true")
  ap.add_argument("--oracles", action="store_true")
  ap.add_argument("--only", nargs="+")
  a = ap.parse_args()
  do_p, do_o = a.ports or not a.oracles, a.oracles or not a.ports
  OUT.mkdir(exist_ok=True)
  rec = []
  for port, oracles in sorted(RG.BASE_ORACLES.items()):
    if a.only and not any(o in port for o in a.only):
      continue
    if not (REPO / port).exists():
      rec.append({"port": port, "skipped": "no .bend on disk"})
      continue
    k = key_of(port)
    e = {"port": port, "key": k, "closure": len(LANE.closure(REPO / port))}
    if do_p:
      ok, tries, log = capture_port(port)
      e["port_ok"], e["port_tries"], e["port_log"] = ok, tries, log
    for i, argv in enumerate(oracles_list(oracles)):
      o = OUT / f"{k}.oracle{i}.txt"
      ok, tries, err = capture_oracle(list(argv), o)
      e.setdefault("oracles", []).append({"argv": argv, "ok": ok, "tries": tries, "err": err,
                                          "lines": len(o.read_text().splitlines()) if o.exists() else 0})
    rec.append(e)
    bad = [x for x in (e.get("oracles", [])) if not x["ok"]] + ([] if e.get("port_ok", True) else ["PORT"])
    print(f"{'ok ' if not bad else 'FAIL'} {port:<52} closure={e['closure']:>2}"
          + (f"  port_tries={e['port_tries']}" if do_p else "")
          + "  " + "  ".join(f"{' '.join(x['argv'][0].split('/')[-1:])}:"
                              f"{x['lines']}l" + ("" if x["ok"] else "!FAIL") for x in e.get("oracles", []))
          + ("" if not bad else f"   <<< {bad}"))
  (HERE / "dup-capture.json").write_text(json.dumps(rec, indent=1))
  return 0


if __name__ == "__main__":
  sys.exit(main())