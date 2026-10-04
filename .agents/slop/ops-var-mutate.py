#!/usr/bin/env python3
"""Mutation table for `UOp.expr` (tinygrad/uop/ops.py:1030).

    .venv/bin/python .agents/slop/ops-var-mutate.py

A row is evidence only if the FIXTURE REACHES THE BRANCH it names. `expr` has one
`match` with two arms and three outcomes, so the table is three mutations -- one
per outcome -- plus TWO controls. A mutation that moves no row is a hole: either
the def is not what the row reads, or the row does not reach the thing it names.

The controls are the reason this file exists rather than a `grep`. M1 makes the
`AParam` arm return the wrong FIELD; if the gate were reading something other than
`name` -- say the whole `ParamArg` -- M1 would move nothing and the table would
read as a pass. The controls are mutations that must move nothing, and a control
that MOVES is the finding, because it means the diff is not reading the value.
"""
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
OPS = REPO / "tinybendygrad" / "uop" / "ops.bend"
BASELINE = REPO / ".agents/slop/ops-var-gate-py.txt"

F13 = "{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}"

# (label, the exact string to replace, its replacement, the rows that MUST move)
MUTATIONS = [
  # 1. The `AParam` arm answers a value that is not `name`. Every mutation here must
  #    be TYPE-PRESERVING: the arm yields a `Maybe<&2, String>`, so a mutation that
  #    hands it a `U32` field does not move a row, it stops the file compiling, and a
  #    table that reports that as "the row did not move" is measuring the type
  #    checker. The first draft swapped in `slot` and measured nothing else.
  ("expr_answers_a_leak",
   f"        case ParamArg{F13}: name",
   f"        case ParamArg{F13}: Bool.pick(Maybe<&2, String>, True{{}}, Some{{\"leaked\"}}, None{{}})",
   ["vr_expr_param", "vr_expr_buffer", "vr_expr_unnamed"]),
  # 2. The FALLBACK arm stops refusing. It moves `vr_expr_nonparam` and NOT
  #    `vr_expr_unnamed`, and that asymmetry is a fact about the PORT, measured by
  #    this table rather than assumed: `vr_expr_unnamed` is a `ParamArg` whose `name`
  #    is already `None`, so it never reaches this arm -- it takes the `AParam` arm
  #    and its `None` comes out of the DATA.
  #
  #    So the two `none` rows are NOT two paths to one refusal. CPython refuses the
  #    unnamed PARAM inside `unwrap`; the port has no `unwrap` to fail, because
  #    `ParamArg.name` is already a `Maybe`. Same answer, different reason, and this
  #    table is what noticed: the first draft listed both rows here and was wrong.
  ("expr_never_refuses",
   """    case _: None{}

def UOp.expr(+ar: Arena, +self: U32)""",
   """    case _: Some{"leaked"}

def UOp.expr(+ar: Arena, +self: U32)""",
   ["vr_expr_nonparam"]),
  # 3. CONTROL, and it is the reason the other two mean anything: add a conjunct
  #    that is true and changes nothing. `vr_expr_param` and `vr_expr_buffer` are the
  #    SAME arm of the arg sum, so if the gate were reading the op -- or anything
  #    else that separates them -- the two would come apart, and they do not. A
  #    control that MOVED is the finding.
  ("ctl_extra_conjunct",
   f"        case ParamArg{F13}: name",
   f"        case ParamArg{F13}: Bool.pick(Maybe<&2, String>, True{{}}, name, None{{}})",
   []),
]


def read_rows() -> dict:
  out = subprocess.run([str(REPO / "bin/bend"), str(OPS)],
                       capture_output=True, text=True, cwd=REPO)
  rows = {}
  for line in out.stdout.split("\n"):
    if line.startswith("vr_") and "=" in line:
      k, v = line.split("=", 1)
      rows[k] = v
  return rows


def rows_moved(base: dict, got: dict) -> set:
  return {k for k in base if k in got and base[k] != got[k]}


def main() -> int:
  if not OPS.exists():
    print("ops.bend is gone", file=sys.stderr)
    return 1
  base = read_rows()
  if not BASELINE.exists():
    print(f"{BASELINE.relative_to(REPO)} does not exist -- run ops-var-gate.sh, "
          f"which writes the CPython lane this table measures against", file=sys.stderr)
    return 1
  want = [l.split("=", 1)[0] for l in BASELINE.read_text().split("\n") if l.startswith("vr_")]
  if sorted(base) != sorted(want):
    print(f"ops-var-mutate: the port answers {sorted(base)} and the gate's CPython "
          f"baseline {sorted(want)}. Run ops-var-gate.sh.", file=sys.stderr)
    return 1

  print(f"{'mutation':22} {'rows that moved':34} verdict")
  bad = 0
  for label, old, new, must in MUTATIONS:
    text = OPS.read_text()
    if text.count(old) != 1:
      print(f"{label:22} {'PATTERN NOT UNIQUE (' + str(text.count(old)) + ')':34} NOT MEASURED")
      bad += 1
      continue
    OPS.write_text(text.replace(old, new, 1))
    try:
      got = read_rows()
      moved = rows_moved(base, got)
    finally:
      OPS.write_text(text)
    if len(got) != len(base):
      print(f"{label:22} {'RUN BROKE (' + str(len(got)) + ' rows)':34} NOT A ROW MOVE")
      bad += 1
      continue
    # EXACT, not a subset. A subset check passes when a mutation moves the rows it
    # names PLUS three others, and "moves three others" is the interesting half:
    # M1 also moves `vr_expr_unnamed`, because the replacement ignores `name`
    # entirely rather than corrupting it, so the unnamed row goes `none` ->
    # `some:leaked` too. A subset check would have called that a pass and thrown
    # away the only thing the mutation told us.
    want_moved = set(must)
    ok = (moved == want_moved) if must else not moved
    if not ok:
      bad += 1
    names = ",".join(sorted(moved)) or "-"
    print(f"{label:22} {names:34} {'ok' if ok else 'MOVED ' + str(sorted(want_moved))}")

  print(f"\n{len(MUTATIONS) - bad}/{len(MUTATIONS)} mutations behaved as the table claims")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())
