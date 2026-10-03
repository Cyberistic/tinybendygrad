#!/usr/bin/env python3
"""wire-snapshot.py -- write the measurements behind a BASE_ORACLES claim to a dated file, so
the claim has a snapshot that can be DIED against rather than only re-derived.

A number typed into a comment rots silently: the comment is not re-checked, so a port that
loses rows keeps its old count forever. This re-measures and prints the DELTA against what the
comment says, which is the only form of the claim that notices.

  usage: python3 .agents/slop/wire-snapshot.py [OUT]
"""
import json, os, pathlib, subprocess, sys, tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]
BEND = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "rebase-wired-rows"
PAIRS = [
  ("tinybendygrad/runtime/support/elf.bend", ".agents/slop/elf_rows.py", 353),
  ("tinybendygrad/renderer/amd/sqtt.bend", ".agents/slop/sqtt_spec.py", 1015),
]


def rows(t):
  out = {}
  for line in t.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k.strip()] = v.strip()
  return out


def lanes(port):
  i = rows(subprocess.run(["./bin/bend", port], cwd=REPO, capture_output=True, text=True,
                         timeout=1800).stdout)
  with tempfile.TemporaryDirectory() as td:
    b = pathlib.Path(td) / "o.bin"
    c = subprocess.run(["./bin/bend", port, "-o", str(b)], cwd=REPO, capture_output=True, text=True)
    n = rows(subprocess.run([str(b)], cwd=REPO, capture_output=True, text=True).stdout) \
        if not c.returncode and b.exists() else None
  return i, n


def main():
  out = [f"# wire-snapshot, measured by wire-snapshot.py on {' '.join(os.environ.get('SNAPDATE', '2026-10-03').split())}",
         "#",
         "#   rows   interpreted / native / oracle / shared / disagree / claimed",
         ""]
  for port, ora, claimed in PAIRS:
    i, n = lanes(port)
    o = rows(subprocess.run([sys.executable, *ora.split()], cwd=REPO, capture_output=True,
                            text=True, env={k: v for k, v in os.environ.items()
                                            if k != "PYTHONPATH"} | {"DEV": "NULL"},
                            timeout=1800).stdout)
    sh = set(o) & set(i)
    dis = sum(1 for k in sh if o[k] != i[k])
    out.append(f"{port}")
    out.append(f"  interpreted={len(i)} native={len(n) if n is not None else 'NONE'} "
               f"oracle={len(o)} shared={len(sh)} disagree={dis} claimed={claimed} "
               f"{'OK' if len(sh) == claimed and dis == 0 else 'CHANGED -- the comment is stale'}")
    out.append(f"  port rows outside the oracle: {len(set(i) - set(o))}")
  text = "\n".join(out) + "\n"
  dest = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else \
      REPO / ".agents/slop/rebase/wired-snapshot.txt"
  dest.write_text(text)
  print(text)
  return 0


if __name__ == "__main__":
  sys.exit(main())