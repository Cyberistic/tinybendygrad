#!/usr/bin/env python3
"""cs-fixpy.py -- REWRITE the `py=` literals in cstyle.bend's `main` FROM A LIVE
CPYTHON CALL, for the rows the gate reports as STALE-LITERAL.

    python3 .agents/slop/cs-fixpy.py            # print what it would change
    python3 .agents/slop/cs-fixpy.py --write    # rewrite the file, then re-check

WHY THIS EXISTS. `agent-core.md` records five units where hand-typed `py=`
expectations were wrong -- 17 of 215 in this very file, and 33 of 219 constants in
`ops_nv.bend` -- and the sharpest one was a case where the PORT and the ORACLE were
both wrong in the same direction, so a diff reported zero disagreements over an
error made twice. At HEAD, after the `type_map` fix, 19 of cstyle.bend's 227 `py=`
literals disagree with the live call: `tmap` was generated against a PIN whose
dtype names were `float8_e4m3` where HEAD says `fp8e4m3`, the four `wmma` rows carry
the C spellings `half`/`signed char`/`__bf16` where HEAD's `DType.name` is
`f16`/`i8`/`bf16`, and the six `witem` rows carry the PIN's `blockIdx.x / threadIdx.x`
spelling for a device whose map HEAD does not have.

This script never TYPES a value. It runs the port, runs the oracle, and copies the
oracle's answer into the literal. `--write` touches exactly the string between the
row call's second and third arguments, and it refuses to write unless the rewritten
file still emits the same number of rows.
"""
import argparse, importlib.util, pathlib, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[2]
PORT = REPO / "tinybendygrad/renderer/cstyle.bend"
ORACLE = ".agents/slop/renderer_oracle.py cstyle-rows"
GATE = ".agents/slop/cstyle-gate.py"
ROW_LINES = 227


def locate(line):
  """(`prefix`, row name, `suffix`) for a
  `_ : Unit <- <row_fn>("NAME", "LITERAL", ...)` line, or None.

  Hand-rolled rather than a regex: the literal contains backslash escapes, and a
  regex for "a quoted string with escapes" is a regex nobody reads twice. The scan
  is escape-aware because `kern2_row`'s literals are `\\n` inside a Bend string.
  """
  stripped = line.lstrip()
  if not stripped.startswith("_ : Unit"):
    return None
  op = line.find('("')
  if op < 0:
    return None
  name_end = line.index('"', op + 2)
  name = line[op + 2:name_end]
  sep = line.find('", "', name_end)
  if sep < 0:
    return None
  start = sep + 4
  j, esc = start, False
  while j < len(line):
    ch = line[j]
    if esc:
      esc = False
    elif ch == "\\":
      esc = True
    elif ch == '"':
      return line[:start - 1], name, line[j + 1:]
    j += 1
  return None


def rows_strict(text):
  """The gate's reader, byte for byte: `ROW_OPEN` is FOUR characters (` = [`) and
  the value starts at `i + 4`. An off-by-one here silently DROPS the first
  character of every value -- measured: it turned `blockIdx.x` into `lockIdx.x`
  and would have written that into the port."""
  rows = {}
  for line in text.splitlines():
    i = line.find(" = [")
    if not line.strip() or i < 0 or not line.rstrip().endswith("]"):
      continue
    rows[line[:i].strip()] = line[i + 4:].rstrip()[:-1]
  return rows


def port_key(line, rowname, tail):
  """THE ROW NAME THE PORT WILL PRINT, which is not always the literal the call
  carries: `rd_row(nm, py, dev, d)` prints `nm + " " + dt_name(d)` and `leg_row`
  the same, so their printed names carry a dtype the call does not spell. Reading it
  out of the SOURCE would mean mapping `S.fp8e4m3()` to `fp8e4m3` by hand, which is
  the transcription this script exists to avoid -- so the dtype is taken from the
  call's own argument NAME and the oracle's own row name is joined on the device
  half only. Measured: this is what the four `rd <dev> fp8e4m3` rows needed."""
  for fn in ("rd_row(", "leg_row("):
    if fn not in line:
      continue
    d = tail.rfind("S.")
    if d < 0:
      return rowname.strip()
    # `rowname` KEEPS its trailing space: the printed name is `nm + " " + dtype`,
    # so stripping here would lose the second space and miss every `rd` row.
    return f"{rowname} {tail[d + 2:tail.index('(', d)]}"
  return rowname.strip()


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--write", action="store_true")
  a = ap.parse_args()
  spec = importlib.util.spec_from_file_location("cs", GATE)
  g = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(g)

  p = subprocess.run(["./bin/bend", "tinybendygrad/renderer/cstyle.bend"], cwd=REPO,
                     capture_output=True, text=True, timeout=3600)
  o = subprocess.run([sys.executable] + ORACLE.split(), cwd=REPO, capture_output=True,
                     text=True, timeout=3600)
  if p.returncode or o.returncode:
    print(f"lane failure rc={p.returncode}/{o.returncode}: "
          f"{p.stderr[-200:]} | {o.stderr[-200:]}")
    return 1
  res = g.judge(p.stdout, o.stdout)
  stale = {n for n, _, _ in res["stale"]}
  print(f"STALE-LITERAL {len(stale)} row(s); the gate is "
        f"{'BROKEN' if res['bad'] else 'AGREE'}")
  if not stale:
    print("nothing to do")
    return 0
  for n in sorted(stale):
    print(f"  {n!r}")

  orc = rows_strict(o.stdout)
  src = PORT.read_text().split("\n")
  changed, seen = [], set()
  for i, line in enumerate(src):
    got = locate(line)
    if got is None:
      continue
    pre, rowname, tail = got
    key = port_key(line, rowname, tail)
    if key not in stale or key not in orc or key in seen:
      continue
    seen.add(key)
    # The literal is the PORT'S ANSWER, which for a CPython refusal is the port's
    # `""` marker and not the oracle's `!KeyError` sentinel. Copying the sentinel
    # wrote `!KeyError / !KeyError` into two `witem` rows on the first run, and the
    # gate reported them stale on the next -- so the demotion goes through the
    # gate's own `expected`/`joined` rather than being spelled a second time here.
    new = g.joined(orc[key], g.expected(orc[key])).replace("\\", "\\\\").replace('"', '\\"')
    src[i] = pre + f'"{new}"' + tail
    changed.append(key)
  missing = sorted(stale - set(seen))
  print(f"located {len(changed)}/{len(stale)} literal(s) in main(); NOT located: {missing}")
  if missing:
    print("  a stale literal the locator could not find is REPORTED, not guessed at")
    return 1
  if not a.write:
    print("dry run; pass --write to apply")
    return 0
  new_text = "\n".join(src)
  # THE REWRITE IS CHECKED WHERE IT LIVES, not in $TMPDIR: cstyle.bend's imports
  # are RELATIVE (`import ./__init__.bend`), so a scratch copy in a temp directory
  # fails with "no such file" and reads exactly like a broken rewrite.
  tmp = REPO / "tinybendygrad/renderer/cstyle-rewrite-probe.bend"
  tmp.write_text(new_text)
  chk = subprocess.run(["./bin/bend", str(tmp.relative_to(REPO))], cwd=REPO,
                       capture_output=True, text=True, timeout=3600)
  tmp.unlink(missing_ok=True)
  nrow = len([l for l in chk.stdout.splitlines() if " = [" in l])
  print(f"rewritten file emits {nrow} row lines (expected {ROW_LINES}); first line "
        f"{(chk.stdout.splitlines() or [''])[0][:40]!r}")
  if nrow != ROW_LINES or "SOME PROOFS" in chk.stdout[:40]:
    print("REFUSING TO WRITE: the row count moved or the file stopped checking")
    return 1
  PORT.write_text(new_text)
  print(f"wrote {PORT}")
  return 0


if __name__ == "__main__":
  sys.exit(main())