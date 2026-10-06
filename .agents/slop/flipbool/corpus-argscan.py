#!/usr/bin/env python3
""".agents/slop/flipbool/corpus-argscan.py -- STATIC. The DENOMINATOR behind `flip`.

THE QUESTION. `flip`'s row 6 differs on ONE chunk, its `arg`: the py column reads
`n(b1,b0)` and the bend column `n(i1,i0)` -- a `bool` where the other side has an `int`.
`ATOMS` says `b` and `i` are DIFFERENT KINDS, so this is a KIND disagreement and not a
spelling. This file counts how WIDE that class is: every `arg` in the corpus that is a
`n(...)` TUPLE, split by the KIND PREFIX each element carries, on BOTH sides.

THE POPULATION IS A DIRECTORY WALK (`runs/graphcmp/D/D2-canon-{py,bend}-*`), not a hand
list (`AGENTS.md` doctrine 1). Row fields are `row_of`'s eight chunks
(`.agents/slop/graphcmp.py:831`), so field index 1 is the OP and index 6 is the ARG; the
walker is `unchunks`'s count-stepping rule (spaces are not format), inlined so this scan
does NOT import `graphcmp` and therefore does NOT load tinygrad.

Output is `.rows`/`.md`, never `.txt`."""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
RUN = HERE.parents[2] / "runs" / "graphcmp" / "D"


def unchunks(line: str) -> list[str]:
  """`graphcmp.unchunks`, copied to avoid importing tinygrad. `<n>:<bytes>`, one optional
  space between chunks; the count is authoritative, so a space is not structure."""
  out, i = [], 0
  while i < len(line):
    j = line.index(":", i)
    n, k = int(line[i:j]), j + 1
    out.append(line[k:k + n])
    i = k + n
    if i < len(line) and line[i] == " ":
      i += 1
  return out


def tuple_kinds(arg: str) -> tuple[str, ...] | None:
  """The kind letters of a `n(...)` arg's top-level elements, or None if not a tuple.
  A bare `N` (absence) is not a tuple. An element starts with its kind letter; `i`/`b`/
  `f`/`l` are the four ATOMS this scan asks about, and any other opener is kept verbatim
  so an unseen kind shows up rather than being silently dropped."""
  if not arg.startswith("n("):
    return None
  inner = arg[2:-1]
  if inner == "":
    return ()
  return tuple(e[0] if e else "?" for e in inner.split(","))


def scan(side: str) -> dict[str, dict[tuple[str, ...], int]]:
  by_op: dict[str, dict[tuple[str, ...], int]] = {}
  for p in sorted(RUN.glob(f"D2-canon-{side}-*")):
    for raw in p.read_text().splitlines():
      if not raw.strip():
        continue
      f = unchunks(raw.lstrip("# ").strip())
      if len(f) != 8:
        continue
      op, arg = f[1], f[6]
      ks = tuple_kinds(arg)
      if ks is None:
        continue
      by_op.setdefault(op, {})
      by_op[op][ks] = by_op[op].get(ks, 0) + 1
  return by_op


def main() -> int:
  if not RUN.is_dir():
    print(f"== REFUSED, NOT A VERDICT: run dir absent: {RUN}", file=sys.stderr)
    return 3
  lines = ["# corpus tuple-arg kinds, by side and op -- STATIC (no bend run)",
           "# population: %s/D2-canon-{py,bend}-* (directory walk, %d + %d files)" % (
               RUN, len(list(RUN.glob("D2-canon-py-*"))), len(list(RUN.glob("D2-canon-bend-*"))))]
  for side in ("py", "bend"):
    by_op = scan(side)
    lines.append(f"# --- {side} ---")
    total = 0
    for op in sorted(by_op):
      for ks, n in sorted(by_op[op].items()):
        kinds = ",".join(k if k else "()" for k in ks) or "(empty)"
        lines.append(f"{side:<4} {op:<14} kinds=({kinds}) n={n}")
        total += n
    lines.append(f"{side:<4} {'TOTAL':<14} tuple-args={total}")
  print("\n".join(lines))
  return 0


if __name__ == "__main__":
  sys.exit(main())
