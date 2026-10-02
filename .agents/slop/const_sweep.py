#!/usr/bin/env python3
"""THE CONSTANT SWEEP for a .bend file: `+1` on every numeric constant def, ONE
AT A TIME, and report which move no gate row.

WHY IT IS WORTH RUNNING. `ops_metal`'s sweep found 30 blind out of 111. A blind
spot is not automatically a bug -- `ops_metal`'s 29 were `CALL_*` tags with no
Python counterpart at all, correctly left blind -- but it is a place where the
gate says nothing, and saying where is the whole value. A constant that moves
nothing AND has a Python authority is either an unused constant (the dead-def
audit says so) or a gate hole.

IN PLACE, NOT IN A TEMPFILE. `ops_webgpu.bend` does `import ../helpers.bend`, and
a copy under `$TMPDIR` cannot resolve it: one unit lost 22 phantom blind spots to
exactly that (bend2-constraints, "a `$TMPDIR` scratch copy cannot resolve a
relative import"). So the file is rewritten in place and restored in a `finally`,
from bytes read once at the start. The restore is unconditional.

The harness diffs WHOLE `name=value` LINES and reports the rows BY NAME -- never
row indices, and never row names as the unit of comparison (a name-comparing
harness reported 0 for all 30 mutations in one unit).

    .venv/bin/python .agents/slop/const_sweep.py <file.bend> <baseline.txt> [out.tsv]
"""
import re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BEND_CONST = re.compile(r"^(def\s+([A-Za-z_][A-Za-z_0-9]*)\(\)\s*->\s*\w+:\s*)(-?\d+)(\s*)$")
ROW = re.compile(r"^([A-Za-z_][A-Za-z_0-9]*)=(.+)$")


def run(path):
  r = subprocess.run(["./bin/bend", str(path)], capture_output=True, text=True, cwd=ROOT)
  if r.returncode != 0:
    return None, (r.stdout or "") + (r.stderr or "")
  out = {}
  for line in (r.stdout or "").splitlines():
    m = ROW.match(line.strip())
    if m: out[m.group(1)] = m.group(2)
  return out, ""


def parse(txt):
  out = {}
  for line in txt.splitlines():
    m = ROW.match(line.strip())
    if m: out[m.group(1)] = m.group(2)
  return out


def main():
  src, base_txt = Path(sys.argv[1]), Path(sys.argv[2])
  outp = Path(sys.argv[3]) if len(sys.argv) > 3 else None
  ORIG = src.read_bytes()
  base = parse(base_txt.read_text())
  assert base, f"{base_txt} has no name=value rows"
  lines = ORIG.decode().splitlines(keepends=True)
  consts = [(i, m.group(2), int(m.group(3))) for i, l in enumerate(lines)
            if (m := BEND_CONST.match(l.rstrip("\n")))]
  print(f"{src.name}: {len(consts)} numeric constants, {len(base)} baseline rows", flush=True)
  blind, moved, failed = [], [], []
  try:
    for n, (i, name, val) in enumerate(consts, 1):
      new = list(lines)
      new[i] = BEND_CONST.sub(lambda m: f"{m.group(1)}{int(m.group(3)) + 1}{m.group(4)}",
                              new[i].rstrip("\n")) + "\n"
      src.write_text("".join(new))
      got, err = run(src)
      if got is None:
        failed.append((name, val, (err.strip().splitlines() or ["no output"])[0]))
      else:
        diff = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
        (moved if diff else blind).append((name, val, diff))
      print(f"  [{n}/{len(consts)}] {name}", flush=True)
  finally:
    src.write_bytes(ORIG)
  assert src.read_bytes() == ORIG, "the sweep did not restore the file"
  print(f"\n  moved >= 1 row : {len(moved)}")
  print(f"  BLIND (0 rows) : {len(blind)}")
  print(f"  RUN FAILED     : {len(failed)}  (a mutation the type checker refused is a weaker kill)")
  for n, v, e in failed: print(f"    FAILED {n}={v} -> {e}")
  print("\n== BLIND, one per line")
  for n, v, _ in blind: print(f"    BLIND {n}={v}")
  print("\n== moved, with the rows BY NAME")
  for n, v, d in moved:
    print(f"  {n}={v}+1 moved {len(d)}: {', '.join(d[:12])}" + (f" (+{len(d) - 12} more)" if len(d) > 12 else ""))
  if outp:
    outp.write_text("\n".join(
      f"{n}\t{v}\t{'BLIND' if (n, v, _) in [(b[0], b[1], b[2]) for b in blind] else 'moved'}"
      for n, v, _ in consts) + "\n")
  return 0


if __name__ == "__main__":
  sys.exit(main())
