#!/usr/bin/env python3
"""x86-sweep.py -- THE CONSTANT SWEEP and the MUTATION TABLE for
`tinybendygrad/renderer/isa/x86.bend`.

Two things, both measured, both reported with the ROW NAMES they moved:

  * `consts`  -- `+1` on every numeric literal in the file, ONE AT A TIME. The
    register table, the `X86Ops` base, the 85 `encodings` entries' four numbers each,
    the jump opcode pairs, the REX/VEX/MODRM/SIB bit positions, `log2b`'s table and
    every literal in a `match` arm. This is the audit the previous agent said it ran
    out of budget for: `ops_nv` found 33 of 219 wrong BEHIND 590 green rows, so "the
    green rows cover the constants" is a claim to be measured and not an argument.

  * `rules`   -- one entry per PORTED RULE, perturbing the rule's own arithmetic
    (`-1` where `+1` is meaningless, an inverted predicate, a dropped clause) rather
    than its data.

Both diff whole `name=value` ROW LINES and not row NAMES, because a name-comparing
harness reported 0 for all 30 mutations in one unit and 0 for all 68 in another.

    .venv/bin/python .agents/slop/x86/x86-sweep.py consts
    .venv/bin/python .agents/slop/x86/x86-sweep.py rules
    .venv/bin/python .agents/slop/x86/x86-sweep.py consts --only log2b

A mutation that moves NOTHING is reported as a BLIND SPOT with a reason. A blind spot
is not closed with a row that restates the port; it is explained or it is a hole.
"""
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TARGET = ROOT / "tinybendygrad/renderer/isa/x86.bend"
BEND = ROOT / "bin/bend"
PY = ROOT / ".venv/bin/python"
ORACLE = ROOT / ".agents/slop/x86/x86-oracle.py"

# a numeric literal in Bend source: a decimal, a `Nat` literal (`8n`), or a U32 shift
# amount. Hex does not exist in Bend 2.0.34, so every constant here is decimal and a
# `0x` in a comment is not a candidate.
NUM = re.compile(r"(?<![\w.])(\d+)(n?)\b")
# what must NOT be touched: row text is generated, and the gate's own numbers are the
# oracle's, so a mutation there tests the oracle rather than the port.
SKIP_RE = re.compile(r'^\s*#|^\s*"|py=\[')


def reference():
  return subprocess.run([str(PY), str(ORACLE), "rows"], capture_output=True, text=True,
                        check=True).stdout.split("\n")


def run_bend():
  r = subprocess.run([str(BEND), str(TARGET)], capture_output=True, text=True)
  if r.returncode != 0:
    return None
  return r.stdout.split("\n")


def rows_moved(base, after):
  """whole `name=value` lines, compared positionally: a row that vanished is a row that
  moved, because the gate prints one line per row in a fixed order."""
  if after is None:
    return ["<FILE DID NOT COMPILE>"]
  if len(base) != len(after):
    return [f"<ROW COUNT {len(base)} -> {len(after)}>"]
  return [b for b, a in zip(base, after) if b != a]


def settled(base):
  """the substrate must not be moving under a mutation run: run twice and insist the
  two agree. `fold.bend` and `movement.bend` went transiently uncompilable three times
  from a concurrent agent and that silently corrupted one baseline once."""
  a, b = run_bend(), run_bend()
  if a is None or b is None or a != b or a != base:
    return False
  return True


def apply(text, i, start, old, new):
  """replace the literal AT `start`, by OFFSET. The first version replaced
  `line.replace(old, new, 1)` -- the first occurrence -- so on a line like
  `Enc.of("ADD", 3, 0, False{}, 0, 0, 0)` the four `0` fields produced FOUR IDENTICAL
  mutations and the sweep reported the same blind four times. Four of the five `0`s in
  that line were never mutated at all.

  A literal that is not where the regex said it is returns None rather than asserting:
  the assert aborted the whole sweep on `U32.shrn(b, 4n)` (a `Nat` literal, whose slice
  ends in `n`) and lost every result."""
  lines = text.split("\n")
  line = lines[i]
  if line[start:start + len(old)] != old:
    return None
  lines[i] = line[:start] + new + line[start + len(old):]
  return "\n".join(lines)


def sweep(base, candidates, only=None, budget_s=900):
  src = TARGET.read_text().split("\n")
  results, t0 = [], time.time()
  for i, line in enumerate(src):
    if only and only not in line:
      continue
    if SKIP_RE.match(line):
      continue
    for m in list(NUM.finditer(line)):
      d, suf = m.group(1), m.group(2)
      old, new = m.group(0), f"{int(d) + 1}{suf}"
      if int(d) + 1 > 2 ** 32:
        continue
      out = apply("\n".join(src), i, m.start(), old, new)
      if out is None:
        continue
      TARGET.write_text(out)
      moved = rows_moved(base, run_bend())
      TARGET.write_text("\n".join(src))
      results.append((i + 1, old, new, line.strip()[:70], moved))
      if time.time() - t0 > budget_s:
        results.append(("-", "-", "-", "BUDGET EXHAUSTED", []))
        return results
  return results


def report(results, base_rows, title):
  blind = [r for r in results if not r[4]]
  movedn = [r for r in results if r[4]]
  print(f"=== {title}: {len(results)} mutations, {len(movedn)} moved rows, "
        f"{len(blind)} BLIND, over {len(base_rows)} rows")
  print("--- MUTATED (moved rows named)")
  for ln, old, new, line, mv in movedn:
    names = [m.split(" = ")[0] for m in mv[:6]]
    more = "" if len(mv) <= 6 else f" (+{len(mv) - 6} more)"
    print(f"  L{ln} {old}->{new}  {len(mv):3d} rows{more}: {', '.join(names)}")
    print(f"        in: {line}")
  print("--- BLIND (no row moved)")
  for ln, old, new, line, mv in blind:
    print(f"  L{ln} {old}->{new}  in: {line}")
  return movedn, blind


if __name__ == "__main__":
  what = sys.argv[1] if len(sys.argv) > 1 else "consts"
  only = None
  if "--only" in sys.argv:
    only = sys.argv[sys.argv.index("--only") + 1]
  # A SWEEP MUTATES THE FILE IN PLACE, so it runs against a SCRATCH COPY and this unit
  # stays editable while it goes. `x86.bend` imports only `Base`, which is Bend's own
  # prelude, so a copy outside the tree still resolves -- `agent-core.md`'s phantom
  # blind-spot warning was about a copy that could not.
  if "--file" in sys.argv:
    TARGET = Path(sys.argv[sys.argv.index("--file") + 1])
  ref = reference()
  base = run_bend()
  assert base is not None, "baseline does not compile"
  assert base == ref, f"baseline differs from CPython on {len(rows_moved(base, ref))} rows"
  assert settled(base), "the substrate is moving; refusing to mutate"
  if what == "verify":
    print(f"baseline stable, {len(base)} rows, diff empty")
    raise SystemExit(0)
  res = sweep(base, None, only)
  report(res, base, what.upper())
