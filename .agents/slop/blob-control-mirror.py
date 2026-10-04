#!/usr/bin/env python3
"""blob-control-mirror.py -- the control for the `ABlob` intern fix, run on a MIRROR.

    .venv/bin/python .agents/slop/blob-control-mirror.py

WHAT IT IS. The control for the nine `blob_*` rows: mutate `eq_arg.ABlob` back to the
LENGTH comparison and show the rows MOVE to the values the defect produces. Without this,
"9 rows, 3 lanes identical" is only a statement that the harness agrees with itself.

WHY NOT `.agents/slop/blob-intern-mutate.py`. That harness mutates
`tinybendygrad/uop/ops.bend` IN PLACE and restores it from a snapshot in a `finally`. Its
stale-snapshot guard runs ONCE, at start, so a concurrent edit that lands mid-run is
silently reverted when the run ends -- and that is not hypothetical: its own docstring
records a restore putting a dead 6623-line file back over the live 6306-line one. On this
tree today `ops.bend` was observed at FOUR digests inside twenty minutes by another unit,
so an in-place harness here is a live weapon aimed at someone else's commit. This file
therefore mutates ONLY `.agents/slop/mirror/`, and asserts the live digest is unchanged
before, between and after every step.

WHY THE MIRROR RESOLVES IMPORTS. `.agents/slop/agent-core.md`: "A `$TMPDIR` scratch copy
cannot resolve a relative import." The mirror is inside the repo and preserves
`tinybendygrad/`'s internal layout, so `import ./../helpers.bend` and
`import ./../LAWS/spec.bend` resolve exactly as they do in the live tree.
"""
import hashlib
import os
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIVE = os.path.join(REPO, 'tinybendygrad/uop/ops.bend')
MIRROR = os.path.join(REPO, '.agents/slop/mirror')
MUX = os.path.join(MIRROR, 'tinybendygrad/uop/ops.bend')
BEND = os.path.join(REPO, 'bin/bend')

# The comparator under test, as it stands in the FIXED tree.
FIXED_DEF = """def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: eq_u32(bs, y1)
    case _: False{}"""

# M1 IS THE BUG, restated in the new representation: compare the LENGTH.
LEN = """def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: U32.is_eq(U32.from_nat(List.length(&2, U32, bs)), U32.from_nat(List.length(&2, U32, y1)))
    case _: False{}"""

# M2: the first byte only -- separates most pairs, misses the rest.
HEAD1 = """def eq_head(bs: List<&2, U32>, y1: List<&2, U32>) -> Bool:
  match bs y1:
    case Nil{} Nil{}: True{}
    case b <> _ w <> _: U32.is_eq(b, w)
    case _ _: False{}

def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: eq_head(bs, y1)
    case _: False{}"""

# M3: separates everything. M4: separates nothing.
NEVER = FIXED_DEF.replace('case ABlob{y1}: eq_u32(bs, y1)', 'case ABlob{y1}: False{}')
ALWAYS = FIXED_DEF.replace('case ABlob{y1}: eq_u32(bs, y1)', 'case ABlob{y1}: True{}')

MUTATIONS = [
  ("M1", "content -> LENGTH (THE ORIGINAL BUG, restated)", LEN),
  ("M2", "content -> FIRST BYTE ONLY", HEAD1),
  ("M3", "content -> NEVER EQUAL (separates everything)", NEVER),
  ("M4", "content -> ALWAYS EQUAL (separates nothing)", ALWAYS),
]

live_digest_at_entry = None


def digest(path: str) -> str:
  return hashlib.sha256(open(path, 'rb').read()).hexdigest()


def fence(where: str) -> None:
  """The live tree must not move UNDER this harness, and must never be written at all."""
  d = digest(LIVE)
  if live_digest_at_entry is None:
    return
  if d != live_digest_at_entry:
    print(f"  !! LIVE ops.bend MOVED at {where}: {live_digest_at_entry[:12]} -> {d[:12]}")
    print("     another unit is editing it; this run's comparison is void.", file=sys.stderr)
    sys.exit(2)
  print(f"  fence@{where}: live ops.bend unchanged ({d[:12]})")


def blob_rows(path: str, attempt_cap: int = 8) -> list[str]:
  """`blob_*` rows of `path`, retried on a 0-row run.

  A 0-row result is INDISTINGUISHABLE from "never started": bend's machine stack overflows
  ~1 run in 20 and sometimes prints nothing. `--check-only` also exits 1 on a file with
  unfilled laws, so the EXIT STATUS is never read; only rows are.
  """
  for n in range(1, attempt_cap + 1):
    r = subprocess.run([BEND, path], cwd=REPO, capture_output=True, text=True, timeout=1800)
    rows = sorted(ln for ln in r.stdout.splitlines() if ln.startswith('blob_'))
    if rows:
      return rows
    print(f"     (0 rows on attempt {n}; retrying)", file=sys.stderr)
  raise SystemExit(f"no blob rows after {attempt_cap} attempts on {path}")


def swap(cur: str, new: str) -> None:
  """Replace `cur` with `new` in the MIRROR, asserting `cur` occurs exactly once.

  Swapping in BOTH directions matters: restoring by searching for FIXED_DEF fails the
  moment a mutation body does not itself contain FIXED_DEF, which is every one of M1..M4.
  """
  s = open(MUX, encoding='utf-8').read()
  n = s.count(cur)
  if n != 1:
    raise SystemExit(f"expected {cur.splitlines()[0]!r} exactly once in the mirror, found {n}")
  open(MUX, 'w', encoding='utf-8').write(s.replace(cur, new))


def provision_mirror() -> None:
  """Build the mirror from the LIVE tree, asserting the two agree before anything runs.

  Regenerable on every invocation rather than kept on disk: it is 11 MB of duplicated
  source, and a STALE mirror is exactly the failure this harness exists to avoid.
  """
  root = os.path.join(REPO, 'tinybendygrad')
  if os.path.exists(MIRROR):
    shutil.rmtree(MIRROR)
  os.makedirs(MIRROR, exist_ok=True)
  shutil.copytree(root, os.path.join(MIRROR, 'tinybendygrad'))
  if digest(LIVE) != digest(MUX):
    raise SystemExit("mirror did not reproduce the live tree; refusing to mutate")


def main() -> None:
  global live_digest_at_entry
  provision_mirror()
  live_digest_at_entry = digest(LIVE)
  mux_digest_at_entry = digest(MUX)
  if live_digest_at_entry != mux_digest_at_entry:
    raise SystemExit("mirror is not in sync with live; re-copy before mutating")
  print(f"live  ops.bend sha256 {live_digest_at_entry[:16]}")
  print(f"mirror ops.bend sha256 {mux_digest_at_entry[:16]}  (in sync)")
  fence("entry")

  before = blob_rows(MUX)
  print(f"\nbaseline: {len(before)} blob rows")
  for row in before:
    print(f"    {row}")

  try:
    for mid, label, body in MUTATIONS:
      fence(f"before {mid}")
      swap(FIXED_DEF, body)
      fence(f"after writing {mid}")
      after = blob_rows(MUX)
      moved = [(b, a) for b, a in zip(before, after) if b != a]
      print(f"\n{mid}: {label}")
      if len(after) != len(before):
        print(f"    ROW COUNT MOVED {len(before)} -> {len(after)}")
      if not moved:
        print("    MOVED NOTHING -- blind spot, and here that is the finding")
      for b, a in moved:
        print(f"    {b}  ->  {a}")
      names = sorted({b.split('=', 1)[0] for b, _ in moved})
      print(f"    rows moved by name: {names if names else 'NONE'}")
      # put the FIXED comparator back before the next mutation, swapping the MUTATED
      # body out -- M1..M4 none of them contain FIXED_DEF as a substring
      swap(body, FIXED_DEF)
  finally:
    cur = open(MUX, encoding='utf-8').read()
    if FIXED_DEF not in cur:
      for _mid, _label, body in MUTATIONS:
        if body in cur:
          swap(body, FIXED_DEF)
          break
    print("\nmirror restored to the fixed comparator")
    fence("exit")
    if digest(MUX) != mux_digest_at_entry:
      print("  !! mirror digest differs from entry", file=sys.stderr)


if __name__ == '__main__':
  main()
