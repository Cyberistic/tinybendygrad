#!/usr/bin/env python3
"""THE MUTATION SET for `.agents/slop/sched-fixture.bend`.

WHY THIS FILE EXISTS RATHER THAN A SHELL LOOP. The first version of this harness
was a shell loop with `python - <<PY` inside it, and it reported **60/60 AGREE for
a mutation that never applied**. The heredoc's `AssertionError` went to stderr,
`set -e` was not on, `cp` restored the file, and the comparator then measured the
UNMUTATED fixture and printed a green 60. That is precisely the shape agent-core
warns about -- "Never report an unexplained zero, or an unexplained success, as a
result" -- committed by the harness itself, one layer below where anyone was
looking.

So every mutation here is checked THREE ways before its number is printed:
  1. the pattern must be PRESENT (else the whole run fails),
  2. the pattern must be ABSENT afterwards (else the whole run fails),
  3. the mutant must have PRODUCED PARSEABLE ROWS (else the whole run fails).

A mutation that moves nothing is reported as a blind spot with a reason, not as a
zero.

RUN:  ./bin/bend .agents/slop/sched-fixture.bend | grep '=' > .agents/slop/sched-port.txt
      env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python .agents/slop/sched-mut.py
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
FIX = os.path.join(HERE, "sched-fixture.bend")
PORT = os.path.join(HERE, "sched-port.txt")
BEND = os.path.join(ROOT, "bin", "bend")
PY = os.path.join(ROOT, ".venv", "bin", "python")

# (id, what it breaks, pattern, replacement)
MUTS = [
  ("M1", "every ksrc digit shifted by 1",
   "case s <> rest : srcs.of(ar, rest, List.append(&2, U32, acc, [dig(SC.sc_op(ar, s))]))",
   "case s <> rest : srcs.of(ar, rest, List.append(&2, U32, acc, [U32.add(dig(SC.sc_op(ar, s)), 1)]))"),
  ("M2", "ktop reads the kernel op instead of the BODY op (k.src[0])",
   "[dig(SC.sc_op(ar, SC.sc_src0(ar, k)))]))",
   "[dig(SC.sc_op(ar, k))]))"),
  ("M3", "kmark answers 0 unconditionally",
   "def kmark(+ar: O.Arena, ks: List<&2, U32>) -> U32:\n  pack(kmark.go1(ar, ks), 0)",
   "def kmark(+ar: O.Arena, ks: List<&2, U32>) -> U32:\n  0"),
  ("M4", "the gated toposort is replaced by the UNGATED one (enters CALL bodies)",
   "U32.from_nat(List.length(&2, U32, SC.sc_topo_of(O.Arena.budget(ar), ar, t)))",
   "U32.from_nat(List.length(&2, U32, O.UOp.toposort(O.Arena.budget(ar), ar, t)))"),
  ("M5", "the root's arity is dropped from the linear count",
   "def lin_nsrc(l: SC.Lin) -> U32:\n  U32.from_nat(List.length(&2, U32, SC.Lin.out(l)))",
   "def lin_nsrc(l: SC.Lin) -> U32:\n  0"),
  ("M6", "a digest of the whole graph is off by one",
   "case O.OpsLINEAR{} : 9",
   "case O.OpsLINEAR{} : 8"),
]


def run_bend():
  out = subprocess.run([BEND, FIX], capture_output=True, text=True, cwd=ROOT)
  rows = []
  for ln in (out.stdout or "").splitlines():
    if re.match(r"^[A-Za-z_][A-Za-z_0-9]*=\d+$", ln.strip()):
      rows.append(ln.strip())
  return out, rows


def comparator():
  e = dict(os.environ)
  for k in ("PYTHONPATH",):
    e.pop(k, None)
  e["LC_ALL"] = "C"
  e["DEV"] = "NONE"
  r = subprocess.run([PY, os.path.join(HERE, "sched-cmp.py")], capture_output=True, text=True, cwd=ROOT, env=e)
  head = [l for l in r.stdout.splitlines() if l.startswith("# specs_attempted")]
  moved = [l.split()[1] for l in r.stdout.splitlines() if l.startswith("DISAGREE")]
  return (head[0] if head else "NO COMPARATOR OUTPUT"), moved


def main():
  orig = open(FIX).read()
  out, rows = run_bend()
  with open(PORT, "w") as f:
    f.write("\n".join(rows) + "\n")
  baseline, base_moved = comparator()
  if len(rows) != 60:
    print(f"FATAL: baseline produced {len(rows)} rows, expected 60", file=sys.stderr)
    return 2
  print(f"BASELINE {baseline}")
  print(f"{'id':4} {'moved':5} {'rows':4}  what")
  blind = []
  for mid, what, pat, rep in MUTS:
    if pat not in orig:
      print(f"FATAL {mid}: PATTERN NOT PRESENT -- {what!r}", file=sys.stderr)
      return 2
    open(FIX, "w").write(orig.replace(pat, rep, 1))
    if pat in open(FIX).read():
      print(f"FATAL {mid}: PATTERN STILL PRESENT after replace", file=sys.stderr)
      return 2
    mout, mrows = run_bend()
    with open(PORT, "w") as f:
      f.write("\n".join(mrows) + "\n")
    if len(mrows) != 60:
      print(f"FATAL {mid}: mutant produced {len(mrows)} rows, not 60 -- "
            f"it did not run: {(mout.stdout or mout.stderr).splitlines()[:2]}", file=sys.stderr)
      open(FIX, "w").write(orig)
      return 2
    line, moved = comparator()
    n = int(re.search(r"fields_disagree=(\d+)", line).group(1))
    print(f"{mid:4} {n:5} {len(mrows):4}  {what}")
    if n == 0:
      blind.append((mid, what))
    open(FIX, "w").write(orig)
  # restore + re-verify
  out, rows = run_bend()
  with open(PORT, "w") as f:
    f.write("\n".join(rows) + "\n")
  line, _ = comparator()
  print(f"RESTORED {line}")
  if blind:
    print("BLIND SPOTS (moved nothing), with reasons:")
    for mid, what in blind:
      print(f"  {mid}: {what}")
  return 0


if __name__ == "__main__":
  sys.exit(main())