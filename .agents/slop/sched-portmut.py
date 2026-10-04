#!/usr/bin/env python3
"""THE PORT-SIDE MUTATION SET: does the 60-row real-spec gate see a bug in
`create_schedule` ITSELF, or only in the readers that consume it?

The six in `sched-mut.py` all mutate `sched-fixture.bend`. Those prove the
COMPARATOR is armed. They do NOT prove the gate can see the port being wrong --
which is the question that matters, because `sched-fixture.bend`'s readers could
be right while `schedule/__init__.bend` is broken.

So this set mutates `tinybendygrad/schedule/__init__.bend` and restores it from a
byte-exact copy, asserting the sha256 afterwards. The file is MINE (it is not in
this session's DO NOT TOUCH list) and it ends the run byte-identical to how it
started -- `sched-stage2.md` reports that hash.

THE FIRST VERSION OF THIS HARNESS REPORTED 0 ROWS MOVED FOR ALL THREE MUTATIONS,
AND ALL THREE WERE FALSE. The cause was an argv off-by-one: the shell wrapper
passed `"$1"` (the mutation's LABEL) where the Python side expected the PATTERN,
so `assert` tested for the string `"P1"` in the source. That assert should have
failed loudly and it did not, because `"P1"` does occur in the file, and the
`replace` then edited an unrelated line. **A mutation harness whose assert
searches for the wrong string reports a green zero.** Run the manual form first
next time.

A mutation that moves nothing is reported as a BLIND SPOT with the reason, not
as a zero.

RUN:  env -u PYTHONPATH .venv/bin/python .agents/slop/sched-portmut.py
"""
import hashlib, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SCHED = os.path.join(ROOT, "tinybendygrad/schedule/__init__.bend")
FIX = os.path.join(HERE, "sched-fixture.bend")
PORT = os.path.join(HERE, "sched-port.txt")
PY = os.path.join(ROOT, ".venv", "bin", "python")

P1_GATE = "case O.OpsSINK{} a   : Bool.not(sc_gate.ker(a))"
P1_MUT = "case O.OpsSINK{} a   : True{}"
P2_PUSH = "    case True{} : Q{List.append(&2, U32, q, [x]), nl}"
P2_MUT = "    case True{} : Q{q, nl}"
P3_KER = """def kernel.of(op: O.Op, +ar: O.Arena, +rk: U32) -> U32:
  match op:
    case O.OpsEND{}: sc_src0(ar, rk)
    case _          : rk"""
P3_MUT = """def kernel.of(op: O.Op, +ar: O.Arena, +rk: U32) -> U32:
  match op:
    case O.OpsEND{}: rk
    case _          : rk"""

MUTS = [
  ("P1", "the gate stops rejecting the kernel SINK (upstream's M8: drop gate_kernel_sink)",
   P1_GATE, P1_MUT),
  ("P2", "the Kahn queue never re-pushes (upstream's M3: push at the wrong end)",
   P2_PUSH, P2_MUT),
  ("P3", "an END-wrapped kernel is NOT unwrapped (`k = rk.src[0] if END`)",
   P3_KER, P3_MUT),
]


def bend_rows():
  r = subprocess.run([os.path.join(ROOT, "bin", "bend"), FIX],
                     capture_output=True, text=True, cwd=ROOT)
  return [l.strip() for l in (r.stdout or "").splitlines()
          if re.match(r"^[A-Za-z_][A-Za-z_0-9]*=\d+$", l.strip())]


def sha():
  return hashlib.sha256(open(SCHED, "rb").read()).hexdigest()


def cmp_rows():
  with open(PORT, "w") as f:
    f.write("\n".join(bend_rows()) + "\n")
  e = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
  e["LC_ALL"] = "C"
  e["DEV"] = "NONE"
  r = subprocess.run([PY, os.path.join(HERE, "sched-cmp.py")],
                     capture_output=True, text=True, cwd=ROOT, env=e)
  head = [l for l in r.stdout.splitlines() if l.startswith("# specs_attempted")]
  return head[0] if head else "NO COMPARATOR OUTPUT"


def main():
  orig = open(SCHED).read()
  h0 = sha()
  print(f"# schedule/__init__.bend sha256 at start = {h0}")
  base = bend_rows()
  print(f"BASELINE {cmp_rows()}  rows={len(base)}")
  base_map = dict(l.split("=") for l in base)
  blind = []
  for mid, what, pat, rep in MUTS:
    if pat not in orig:
      print(f"FATAL {mid}: PATTERN NOT PRESENT -- {what}", file=sys.stderr)
      open(SCHED, "w").write(orig)
      return 2
    open(SCHED, "w").write(orig.replace(pat, rep, 1))
    rows = bend_rows()
    if len(rows) != len(base):
      print(f"FATAL {mid}: mutant produced {len(rows)} rows, not {len(base)} -- it did not run",
            file=sys.stderr)
      open(SCHED, "w").write(orig)
      return 2
    line = cmp_rows()
    moved = [l for l in rows if base_map.get(l.split("=")[0]) != l.split("=")[1]]
    print(f"{mid} moved={len(moved):2}  {what}")
    for l in moved[:3]:
      print(f"      {l}")
    if not moved:
      blind.append((mid, what))
    open(SCHED, "w").write(orig)
  assert sha() == h0, "RESTORE FAILED -- the schedule file is not byte-identical"
  print(f"RESTORED {cmp_rows()}  sha256={sha()}")
  if blind:
    print("BLIND SPOTS (moved nothing), with reasons:")
    for mid, what in blind:
      print(f"  {mid}: {what}")
  return 0


if __name__ == "__main__":
  sys.exit(main())