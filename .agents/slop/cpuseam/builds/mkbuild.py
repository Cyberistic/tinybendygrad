#!/usr/bin/env python3
"""BUILD A DAEMON FROM THE TREE'S OWN SOURCES, **RIGHT NOW**, AND NAME IT.

**A BUILD IS A SECOND SOURCE OF TRUTH** (`PARITY.md` §136): A `.js` FOUND LYING AROUND MAY BE
**STALE**, AND A STALE `.bc` WAS SERVED FOR **TWO RUNS** WITH THE SOURCE ALREADY FIXED. SO
**THE BUILD IS ALWAYS INSIDE THE MEASUREMENT**, AND **NEVER** A PATH FOUND ON DISK.

**THE BUILD IS `serve.bend` COMPILED BY `bin/bend`**, AND IT IS **RUN UNDER `bun`** AND NOT
AS A COMPILED `.bc` -- MEASURED, `bun build --compile --minify` **RELOCATES `require("fs")`**, WHICH
IS WHERE THE CLOCKS WRITE.

**THE OUTPUT IS A DERIVED ARTEFACT AND IS GITIGNORED** (`builds/.gitignore`): A COMMITTED
BUILD **ROTS**.
"""

import hashlib
import os
import pathlib
import subprocess
import sys

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
import portc  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"
HERE = R / ".agents/slop/cpuseam"

# **THE SOURCES THE DAEMON IS BUILT FROM.** THE STAMP IS **OVER THE SOURCES** AND NOT OVER THE
# OUTPUT, SO A STALE ARTEFACT CANNOT PASS FOR A FRESH BUILD.
SRCS = [
  HERE / "serve.bend",
  R / "tinybendygrad/renderer/live.bend",
  R / "tinybendygrad/renderer/cstyle.bend",
  R / "tinybendygrad/renderer/wire.js",
  R / "tinybendygrad/uop/ops.bend",
]


def stamp() -> str:
  h = hashlib.sha256()
  for s in SRCS:
    h.update(s.read_bytes())
  return h.hexdigest()[:16]


def build(out: pathlib.Path | None = None) -> pathlib.Path:
  """COMPILE `serve.bend` **NOW** AND RETURN THE PATH TO THE FRESH JS."""
  out = out or (BUILD / f"live-{stamp()}.js")
  env = dict(portc.ENV)
  b = subprocess.run([str(portc.BEND), str(HERE / "serve.bend"), "-o", str(out)],
                     capture_output=True, text=True, env=env)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"mkbuild: serve.bend did not build: {b.stderr.strip()[:600]}")
  return out


if __name__ == "__main__":
  out = build(pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None)
  print(out)
