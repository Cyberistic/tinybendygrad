#!/usr/bin/env python3
"""THE FAR-VALUE CONSTANT SWEEP: set every numeric constant to a value that
collides with NOTHING in the file, and report which rows move.

WHY `+1` IS NOT ENOUGH, MEASURED. The ordinary `+1` sweep reports `CALL_CREATE`
as moving 11 rows. It does not: `CALL_CREATE+1 == CALL_WAIT`, so every
`Tr.args(CALL_CREATE, ...)` starts counting the WAITs too, and a row moves because
two tags now name the same thing. That is a COLLISION, not a pin. A tag space
whose only live property is mutual distinctness cannot be value-pinned by `+1`,
and reporting "moved 11 rows" would be reporting the wrong reason.

So this sweep writes `12345678`, which is not any constant, tag, bit flag, enum
value or field index in either file. A row that moves under THAT mutation reads
the constant's NUMERIC VALUE, independently of every other constant. A row that
does not move reads the constant only as an opaque tag, and the tag's value is
then pinned by nothing except the CPython authority this project audits against.

IN PLACE, NOT IN A TEMPFILE (a `$TMPDIR` copy cannot resolve `import
../helpers.bend`), restored in a `finally` from bytes read once.

    .venv/bin/python .agents/slop/const_sweep_far.py <file.bend> <baseline.txt> [out.tsv]
"""
import re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BEND_CONST = re.compile(r"^(def\s+([A-Za-z_][A-Za-z_0-9]*)\(\)\s*->\s*\w+:\s*)(-?\d+)(\s*)$")
ROW = re.compile(r"^([A-Za-z_][A-Za-z_0-9]*)=(.+)$")
FAR = "12345678"          # measured absent from both files' constants and rows


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
  return {m.group(1): m.group(2) for m in (ROW.match(l.strip()) for l in txt.splitlines()) if m}


def main():
  src, base_txt = Path(sys.argv[1]), Path(sys.argv[2])
  outp = Path(sys.argv[3]) if len(sys.argv) > 3 else None
  ORIG = src.read_bytes()
  base = parse(base_txt.read_text())
  assert base
  assert FAR not in base.values() and FAR not in base, f"{FAR} already appears in the baseline"
  lines = ORIG.decode().splitlines(keepends=True)
  consts = [(i, m.group(2), int(m.group(3))) for i, l in enumerate(lines)
            if (m := BEND_CONST.match(l.rstrip("\n")))]
  print(f"{src.name}: {len(consts)} constants -> {FAR}", flush=True)
  blind, moved, failed = [], [], []
  try:
    for n, (i, name, val) in enumerate(consts, 1):
      new = list(lines)
      new[i] = BEND_CONST.sub(lambda m: f"{m.group(1)}{FAR}{m.group(4)}",
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
  print(f"  RUN FAILED     : {len(failed)}")
  for n, v, e in failed: print(f"    FAILED {n}={v} -> {e}")
  print("\n== BLIND under a collision-free value (opaque tags)")
  for n, v, _ in blind: print(f"    BLIND {n}={v}")
  print("\n== moved, with the rows BY NAME")
  for n, v, d in moved:
    print(f"  {n}={v} moved {len(d)}: {', '.join(d[:12])}" + (f" (+{len(d) - 12})" if len(d) > 12 else ""))
  if outp:
    bs = {(b[0], b[1]) for b in blind}
    outp.write_text("\n".join(f"{n}\t{v}\t{'BLIND' if (n, v) in bs else 'moved'}" for n, v, _ in consts) + "\n")
  return 0


if __name__ == "__main__":
  sys.exit(main())
