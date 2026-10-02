#!/usr/bin/env python
"""Check that every composition offset in `uop/spec.bend` agrees with the table sizes.

The five tables are composed by COUNTING, and each composition spells its running total
TWICE -- once as `bump(N, ...)` where the table is built and once as `U32.sub(tag, N)`
in the matching dispatch ladder. Nothing in the type system ties the two together, so
renumbering one without the other is a SILENT change: a tag stops selecting the table it
was written for and lands in the next one. That is agent-core.md's worst failure, and it
happened here twice while deleting one duplicate rule:

  * `te_dispatch.go`'s ladder still read `case N: te_(N-1)` for every N from 5 up, so
    tag 5 answered te_4 and tag 21 answered te_20;
  * `full_dispatch` still subtracted 27 / 60 / 69 after `full_table.go` had been rebased
    to 26 / 59 / 68, so every tag past `full_own`'s four entered the WRONG table.

Both compiled, both ran, and neither raised anything.

  usage: python .agents/slop/spec-offsets.py
Exit 0 when every offset agrees, 1 when one disagrees, 2 when a table cannot be read.
"""
import pathlib
import re
import sys

SRC = pathlib.Path(__file__).resolve().parents[2] / "tinybendygrad/uop/spec.bend"
LINES = SRC.read_text().splitlines()
TABLES = ("shared_table", "tensor_own", "program_own", "hcq_own", "full_own")


def size(fn):
  """A table is the maximal run of `O.PMEntry{n,` lines right after `def fn(`."""
  i = next(k for k, l in enumerate(LINES) if l.startswith(f"def {fn}("))
  n = 0
  for l in LINES[i + 1:]:
    if re.match(r"\s*O\.PMEntry\{\d+,", l):
      n += 1
    elif n:
      break
  if not n:
    raise LookupError(fn)
  return n


def body(fn):
  """The whole def named `fn` -- from its `def` line to the next `def` line.

  A fixed line span is the wrong shape: `te_dispatch.go` puts its `U32.sub(tag, N)` on
  the line after its LAST case arm, twenty-five lines down, and a span that stops short
  reports every offset as absent."""
  i = next(k for k, l in enumerate(LINES) if l.startswith(f"def {fn}("))
  j = next((k for k in range(i + 1, len(LINES)) if LINES[k].startswith("def ")), len(LINES))
  return "\n".join(LINES[i:j])


def ints(pattern, text):
  return [int(m.group(1)) for m in re.finditer(pattern, text)]


def main():
  try:
    sh, te, pr, hq, fo = (size(f) for f in TABLES)
  except LookupError as e:
    print(f"cannot read table {e}", file=sys.stderr)
    return 2
  print(f"  sizes: shared={sh} tensor_own={te} program_own={pr} hcq_own={hq} full_own={fo}")

  bad = []

  def check(where, expect, got):
    ok = expect == got
    print(f"  {'OK  ' if ok else 'FAIL'} {where}: source={got} expected={expect}")
    if not ok:
      bad.append(where)

  def one(where, pattern, text, expect):
    got = ints(pattern, text)
    if len(got) != 1:
      print(f"  FAIL {where}: found {len(got)} matches, want 1")
      bad.append(where)
    else:
      check(where, expect, got[0])

  # a table's own builder bumps its OWN size to place the shared half
  one("tensor_table bump(shared)", r"bump\((\d+), shared_table", body("tensor_table"), te)
  one("program_table bump(shared)", r"bump\((\d+), shared_table", body("program_table"), pr)
  one("hcq_table bump(shared)", r"bump\((\d+), shared_table", body("hcq_table"), hq)

  # full_table composes four parts; each bump names the running total BEFORE that part
  full = ints(r"bump\((\d+),", body("full_table"))
  if len(full) != 4:
    print(f"  FAIL full_table: found {len(full)} bumps, want 4")
    bad.append("full_table bump count")
  else:
    for label, expect, got in (("tensor_own", fo, full[0]),
                               ("shared", fo + te, full[1]),
                               ("program_own", fo + te + sh, full[2]),
                               ("hcq_own", fo + te + sh + pr, full[3])):
      check(f"full_table bump({label})", expect, got)

  # and each dispatch ladder must subtract the SAME running total
  for disp, own in (("te_dispatch.go", te), ("pr_dispatch.go", pr), ("hq_dispatch.go", hq)):
    one(f"{disp} sub(shared)", r"U32\.sub\(tag, (\d+)\)", body(disp), own)

  subs = ints(r"U32\.sub\(tag, (\d+)\)", body("fu_dispatch.of"))
  if len(subs) != 4:
    print(f"  FAIL fu_dispatch.of: found {len(subs)} U32.sub, want 4")
    bad.append("fu_dispatch.of sub count")
  else:
    for label, expect, got in (("te_dispatch", fo, subs[0]),
                               ("sh_dispatch", fo + te, subs[1]),
                               ("pr_dispatch", fo + te + sh, subs[2]),
                               ("hq_dispatch", fo + te + sh + pr, subs[3])):
      check(f"fu_dispatch.of -> {label}", expect, got)

  # every dispatch ladder must map tag N to the def named N, with no off-by-one
  for disp, n in (("te_dispatch.go", te), ("pr_dispatch.go", pr), ("hq_dispatch.go", hq),
                  ("sh_dispatch.go", sh)):
    arms = [(int(a), int(b)) for a, b in
            re.findall(r"case (\d+): \w+?_(\d+)\(fx, self\)", body(disp))]
    if len(arms) != n:
      print(f"  FAIL {disp} ladder: {len(arms)} arms, want {n}")
      bad.append(f"{disp} ladder")
    elif [a for a, _ in arms] != list(range(n)) or [b for _, b in arms] != list(range(n)):
      print(f"  FAIL {disp} ladder: tags/defs are not `case N: _N` pairwise")
      bad.append(f"{disp} ladder")
    else:
      print(f"  OK   {disp} ladder: `case N: _N` for N in 0..{n-1}")

  print(f"  {len(bad)} problems")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())