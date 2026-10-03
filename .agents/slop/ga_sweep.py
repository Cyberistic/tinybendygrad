#!/usr/bin/env python3
"""CACHE every wired gate's lane output, so a rows() change can be MEASURED instead of
guessed.  Run once; the parsers are then applied to the cache offline.

Nothing here judges anything.  It only runs lanes and writes stdout to
.agents/slop/ga_cache/<port>/<lane>.txt plus a lanes.json of rc/first-line, so a
sweep never re-runs bend for every candidate parser.

Run:  python3 .agents/slop/ga_sweep.py [--only PORT_SUBSTR] [--no-native]
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys

SLOP = pathlib.Path(__file__).resolve().parent
REPO = SLOP.parents[1]
CACHE = SLOP / "ga_cache"


def load_base_oracles():
  """BASE_ORACLES is rebase-gate.py's DATA.  It is read as text and exec'd, not
  imported, so the sweep cannot drift from the dict the gate actually uses."""
  src = (SLOP / "rebase-gate.py").read_text()
  start = src.index("BASE_ORACLES = {")
  body = src[start:]
  ns = {}
  exec(body[:body.index("\n}\n") + 3], {}, ns)  # noqa: S102 -- data, read literally
  return ns["BASE_ORACLES"]


def sh(*a, timeout=1800):
  return subprocess.run(a, cwd=REPO, capture_output=True, text=True, timeout=timeout)


# `sys.executable` is whatever ran the sweep, and the oracles need the VENV:
# measured, 10 of 38 CPython lanes exit non-zero under a bare `python3` and their
# cached rows are EMPTY, which silently understates every shared count computed
# from this cache.  An empty oracle lane reads as "this gate compares nothing",
# which is the very shape the sweep exists to disprove.
VENV = REPO / ".venv" / "bin" / "python"
PY = str(VENV) if VENV.exists() else sys.executable


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--only", default=None)
  ap.add_argument("--no-native", action="store_true")
  a = ap.parse_args()

  oracles = load_base_oracles()
  ports = sorted(p for p in oracles if not a.only or a.only in p)
  print(f"{len(ports)} wired gates", flush=True)
  # MERGE into the existing manifest.  A `--only` run used to REPLACE it, so a
  # one-gate refresh left `ga_rows_blast.py` reporting one gate and every other
  # gate silently absent -- which reads as "the other 37 gates are fine" when it
  # means "they were not looked at".  A missing measurement and a clean one must be
  # different bytes.
  mpath = CACHE / "lanes.json"
  manifest = json.loads(mpath.read_text()) if mpath.exists() else {}
  for i, port in enumerate(ports, 1):
    bend = REPO / port
    out_dir = CACHE / port.replace("/", "_")
    out_dir.mkdir(parents=True, exist_ok=True)
    lanes = {}
    if not bend.exists():
      manifest[port] = {"MISSING": True}
      print(f"[{i}/{len(ports)}] MISSING {port}", flush=True)
      continue

    if (out_dir / "interpreted.txt").exists():
      interp = (out_dir / "interpreted.txt").read_text()
      irc = json.loads((out_dir / "interpreted.rc").read_text())
    else:
      p = sh("./bin/bend", port)
      irc = p.returncode
      (out_dir / "interpreted.txt").write_text(p.stdout)
      (out_dir / "interpreted.rc").write_text(json.dumps(irc))
      (out_dir / "interpreted.err").write_text(p.stderr[-2000:])
    lanes["interpreted"] = {"rc": irc}

    if not a.no_native:
      binp = out_dir / "lane.bin"
      if (out_dir / "native.txt").exists():
        native = (out_dir / "native.txt").read_text()
        nrc = json.loads((out_dir / "native.rc").read_text())
      else:
        binp.unlink(missing_ok=True)
        b = sh("./bin/bend", port, "-o", str(binp))
        if b.returncode or not binp.exists():
          nrc, native = (b.returncode or 1), ""
          (out_dir / "native.err").write_text(b.stderr[-2000:])
        else:
          binp.chmod(0o755)
          n = sh(str(binp))
          nrc, native = n.returncode, n.stdout
          (out_dir / "native.err").write_text(n.stderr[-2000:])
        (out_dir / "native.txt").write_text(native)
        (out_dir / "native.rc").write_text(json.dumps(nrc))
      lanes["native"] = {"rc": nrc}

    for spec in oracles[port]:
      argv = spec.split()
      key = "cpython:" + pathlib.Path(argv[0]).stem
      fp = out_dir / (key.replace(":", "_") + ".txt")
      if fp.exists():
        rcp = json.loads((out_dir / (key.replace(":", "_") + ".rc")).read_text())
      else:
        env = dict(os.environ, DEV="NULL")
        c = subprocess.run([PY, *argv], cwd=REPO, capture_output=True,
                           text=True, env=env, timeout=1800)
        fp.write_text(c.stdout)
        (out_dir / (key.replace(":", "_") + ".rc")).write_text(json.dumps(c.returncode))
        (out_dir / (key.replace(":", "_") + ".err")).write_text(c.stderr[-2000:])
        rcp = c.returncode
      lanes[key] = {"rc": rcp}

    manifest[port] = lanes
    mpath.write_text(json.dumps(manifest, indent=1, sort_keys=True))
    print(f"[{i}/{len(ports)}] {port}  rc=" +
          " ".join(f"{k}:{v['rc']}" for k, v in sorted(lanes.items())), flush=True)
  print(f"cached -> {CACHE}", flush=True)
  return 0


if __name__ == "__main__":
  sys.exit(main())