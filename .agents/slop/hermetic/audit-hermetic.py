#!/usr/bin/env python3
"""audit-hermetic.py -- a PLANT and a DISARM for each of the three defects, plus a
site-wide auditor for the late-`DEV` class.

A RED WITH NO PAIRED DISARM PROVES NOTHING ABOUT WHERE IT LANDED, so every control below is a
pair: the same edit with the meaning removed, which must go GREEN. Three controls in this
project were found disarmed. Each control prints PLANT and DISARM and FAILS if either half
misbehaves; the script exits non-zero if any control fails, so it cannot report a green it did
not earn.

  C1  process independence -- PLANT: the same graph built after different predecessors gets
      different bytes. DISARM: the fix makes `late`'s bytes identical whether it is emitted
      first or last, AND the parent's `UOp.unique_num` is still 0 afterwards, which is
      unreachable if any graph had been built in the parent.
  C2  the cache -- PLANT: the REAL stale artifact on disk (arith's, 15 named). DISARM: the same
      check over a freshly published artifact. Plus a synthetic single-byte corruption, whose
      null is a rewrite of IDENTICAL bytes: content is compared, metadata is not.
  C3  `DEV` -- PLANT: setting DEV after the import yields METAL while NULL was asked for.
      DISARM: DEV inherited from the environment at process birth yields NULL. Plus a
      corpus-wide scan: no row set may carry a device other than the requested one.
"""
from __future__ import annotations
import sys, os, pathlib, subprocess, argparse, hashlib

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
SLOP = REPO / ".agents" / "slop"
sys.path.insert(0, str(HERE)); sys.path.insert(0, str(SLOP)); sys.path.insert(0, str(REPO))
import graphcmp as G
import isolate

FAIL: list[str] = []


def check(name: str, ok: bool, detail: str) -> None:
  print(f"  {'PASS' if ok else 'FAIL'}  {name}: {detail}")
  if not ok: FAIL.append(name)


def md5(rows: list[str]) -> str:
  return hashlib.md5("\n".join(rows).encode()).hexdigest()


# THE DELIBERATELY LEAKY EMITTER. This is the defect, so it is a different function from the
# fix and is NOT shared with `isolate.py`: one process, several graphs, target last.
LEAKY = r'''
import sys, pathlib, hashlib
REPO = pathlib.Path("%s")
sys.path.insert(0, str(REPO / ".agents" / "slop")); sys.path.insert(0, str(REPO))
import graphcmp as G
G.os.environ["DEV"] = "CPU"; G.load_tinygrad(); G.COMM = G.commutative()
names = sys.argv[1].split(",")
with G.Context(NO_COLOR=1):
    for n in names[:-1]: G.base(n)                 # the predecessors -- THIS is the defect
    rows = G.emit_py(names[-1], None)
sys.stdout.write("\n".join(rows))
''' % REPO


def leaky(names: str) -> list[str]:
  c = subprocess.run([isolate.PY, "-c", LEAKY, names], cwd=REPO, capture_output=True, text=True,
                     env=G.clean_env("CPU"))
  rows = [ln for ln in c.stdout.splitlines() if ln.strip()]
  if not rows:
    raise SystemExit(f"audit: leaky emitter produced 0 rows, rc={c.returncode}, "
                     f"stderr={' '.join(c.stderr.split())[-200:]}")
  return rows


def c1_process(dev: str) -> None:
  print("C1 process independence (the slot leak)")
  G.os.environ["DEV"] = dev
  G.load_tinygrad()
  G.COMM = G.commutative()
  n0 = next(G.UOp.unique_num)

  # THE FIRST VERSION OF THIS PLANT WAS A TAUTOLOGY AND IT IS THE POINT OF THIS FILE.
  # It compared `late` after `matmul` against `late` after `reduce,cast` and they came out
  # BYTE-IDENTICAL -- because those two predecessor sets consume exactly TWO slots each, so
  # `late` lands on 2/3 either way. MEASURED slot consumption per predecessor set is what
  # exposed it, and it is the same shape as the `lin`/`loop` and `flip` lessons: two
  # spellings that agree for a reason nobody chose. So the plant is stated on the FIELD
  # (`slot`) and over predecessor sets whose sizes differ, and it prints both.
  before = isolate.emit("late", "py", dev)                   # no predecessors: slots 0/1
  many = ",".join(sorted(G.GRAPHS)[:8]) + ",late"
  after = leaky(many)
  # The full slot token, not a fixed-width slice: a 2-char slice reported `i1` for BOTH
  # two-digit slots (`i10`,`i11` -> `i1`,`i1`), which reads as a collision that is not there.
  slots = lambda rs: [ln[ln.index("P(") + 2:].split(",")[0] for ln in rs if "P(" in ln]
  check("C1 PLANT  predecessors move `late`'s slot", md5(before) != md5(after)
        and slots(before) != slots(after),
        f"alone slots={slots(before)} md5={md5(before)[:12]} vs after 8 graphs "
        f"slots={slots(after)} md5={md5(after)[:12]}")

  last = isolate.emit("late", "py", dev)                        # emitted AFTER everything
  check("C1 DISARM first == last under isolate", md5(before) == md5(last),
        f"both md5={md5(last)[:12]}; the leaking run above differs, so the check has teeth")

  # THE CONDITION THAT PROVABLY CANNOT TRIGGER: the parent minted nothing. `unique_num` is a
  # bare `itertools.count`, so reading it CONSUMES one -- the instrument perturbs what it
  # measures unless the baseline is accounted for. The start read returning 0 proves nothing
  # minted before it; the end read returning 1 therefore proves nothing minted in between,
  # because the only consumer since is the start read itself. A counter RESET could not
  # assert this, only re-establish it, which is the whole difference between the two designs.
  n1 = next(G.UOp.unique_num)
  check("C1 DISARM parent minted no slot", n0 == 0 and n1 == 1,
        f"UOp.unique_num: start read 0 (nothing minted before), end read {n1} (only the start "
        f"read consumed since) -- unreachable if any graph had been built in this process")


def c2_cache(names: list[str], dev: str) -> None:
  print("C2 the cache")
  rc_arith = subprocess.run([isolate.PY, str(HERE / "hermetic-census.py"), "--check",
                             "--dev", dev, "--out", str(SLOP / "arith")],
                            cwd=REPO, capture_output=True, text=True, env=G.clean_env(dev))
  n_stale = sum(1 for ln in rc_arith.stdout.splitlines() if ln.startswith("# STALE"))
  check("C2 PLANT  arith's own artifact is stale", rc_arith.returncode == 3 and n_stale == 15,
        f"rc={rc_arith.returncode}, {n_stale} named STALE (the real corruption, not a synthetic one)")

  rc_own = subprocess.run([isolate.PY, str(HERE / "hermetic-census.py"), "--check",
                           "--dev", dev, "--out", str(HERE / "rows")],
                          cwd=REPO, capture_output=True, text=True, env=G.clean_env(dev))
  check("C2 DISARM freshly published artifact", rc_own.returncode == 0, f"rc={rc_own.returncode}")

  # SYNTHETIC PLANT, and its null is the SAME FILE with IDENTICAL BYTES REWRITTEN: content is
  # compared and metadata is not, so `write_text` of the same text must not be a difference.
  victim = HERE / "rows" / f"rows-{names[0]}-py.txt"
  original = victim.read_text()
  try:
    victim.write_text(original.replace("ALLOC", "ALLOCX", 1))
    rc_bad = subprocess.run([isolate.PY, str(HERE / "hermetic-census.py"), "--check", "--only",
                             names[0], "--dev", dev, "--out", str(HERE / "rows")],
                            cwd=REPO, capture_output=True, text=True, env=G.clean_env(dev))
    check("C2 PLANT  one byte flipped is caught", rc_bad.returncode == 3,
          f"rc={rc_bad.returncode}: {rc_bad.stdout.strip().splitlines()[0][:90]}")
  finally:
    victim.write_text(original)                    # restored byte-for-byte, in a `finally`
  rc_null = subprocess.run([isolate.PY, str(HERE / "hermetic-census.py"), "--check", "--only",
                            names[0], "--dev", dev, "--out", str(HERE / "rows")],
                           cwd=REPO, capture_output=True, text=True, env=G.clean_env(dev))
  check("C2 DISARM identical bytes rewritten", rc_null.returncode == 0,
        f"rc={rc_null.returncode}; content is the comparison, not mtime")


def c3_dev(dev: str, names: list[str]) -> None:
  print("C3 DEV, and the late-`DEV` class")
  # TWO TEMPLATES, NOT ONE WITH A FLAG. The first version substituted the DEV line into the
  # same slot in both runs, so both were EARLY and the "plant" reported the disarm's answer.
  ask = '''
import sys, os, pathlib
REPO = pathlib.Path("%s")
sys.path.insert(0, str(REPO / ".agents" / "slop")); sys.path.insert(0, str(REPO))
import graphcmp as G
%s
G.load_tinygrad()
from tinygrad import Device
print(Device.DEFAULT)
'''
  EARLY, LATE = 'os.environ["DEV"]="NULL"', 'pass  # DEV not set yet -- applied after the import'
  # The child's env must NOT already carry DEV, or `clean_env` has resolved the device at
  # process birth and the late assignment is INERT (measured: it yields CPU, no error) --
  # a third failure mode, checked separately just below.
  bare = {k: v for k, v in os.environ.items() if k != "DEV"}
  late = subprocess.run([isolate.PY, "-c", ask % (REPO, LATE) + '\nos.environ["DEV"]="NULL"'],
                        cwd=REPO, capture_output=True, text=True, env=bare)
  early = subprocess.run([isolate.PY, "-c", ask % (REPO, EARLY)],
                         cwd=REPO, capture_output=True, text=True, env=bare)
  inert = subprocess.run([isolate.PY, "-c", ask % (REPO, LATE) + '\nos.environ["DEV"]="NULL"'],
                         cwd=REPO, capture_output=True, text=True, env=G.clean_env(dev))
  check("C3 PLANT  DEV applied after the import", late.stdout.strip() == "METAL",
        f"asked NULL, applied late -> {late.stdout.strip()} (the wall, reproduced)")
  check("C3 DISARM DEV inherited at process birth", early.stdout.strip() == "NULL",
        f"asked NULL, inherited -> {early.stdout.strip()}; this is the shape `isolate.emit` uses")
  # THE THIRD MODE, and the nastiest: with DEV already inherited, a late source assignment is
  # SILENTLY INERT. No exception, no warning -- it reads as if it took effect and did not.
  check("C3 PLANT  late DEV under an inherited DEV is inert, not an error",
        inert.stdout.strip() == dev,
        f"asked NULL after inheriting {dev} -> {inert.stdout.strip()}, silently, which is why "
        f"source order cannot be left to a reader")

  # CORPUS-WIDE: a flag that landed for one graph proves nothing about the other 23.
  want = f"s{dev}"
  bad = []
  for n in names:
    for which in ("py", "bend"):
      f = HERE / "rows" / f"rows-{n}-{which}.txt"
      if not f.exists(): continue
      found = {w for ln in f.read_text().splitlines() for w in ("sCPU", "sMETAL", "sNULL",
                                                                "sPYTHON") if w in ln}
      if found and found != {want}: bad.append(f"{n}/{which}={sorted(found)}")
  check("C3 every published row set carries ONLY the requested device", not bad,
        f"want {want} only; {len(bad)} offending {bad[:4]}")


def audit_dev_sites() -> None:
  """The CLASS, not this one file: every script that ASSIGNS DEV and reaches tinygrad.

  TWO FALSE POSITIVES FOUND IN THE FIRST VERSION, both worth naming because either would
  have made this auditor a green that meant nothing:
    * it matched `DEV` in ANY line with `environ`, so upstream's own `tinygrad/device.py`
      (`DEV = ContextVar(...)`, or `os.getenv("DEV")` at line 59) counted as an ASSIGNMENT.
      A read is not a write; this now matches the assignment spellings only.
    * it walked VENDORED trees (`xd1/*/tinygrad/*`, `opstree/tinygrad/*`), where line 6 is
      upstream's own import and the DEV read is upstream's own contract. Those are counted and
      reported separately rather than flagged as this project's defects."""
  print("C3b late-DEV site audit (source order, per file)")
  skip = (".BASELINE", ".pre-reach", "__pycache__")
  SET = ('environ["DEV"]', "environ['DEV']", 'setdefault("DEV"', "setdefault('DEV'",
         'putenv("DEV"', "environ.update")
  VENDORED = ("/tinygrad/", "xd1/", "opstree/", "references/")
  # THE GATE IS SCOPED TO WHAT THIS CENSUS DEPENDS ON, not to the whole tree. Scoping it to the
  # whole tree produced a permanent red on `oracles/mm-range.py` -- a real defect, in another
  # unit's oracle, which agent-core.md says to REPORT rather than fix. A gate that can never go
  # green is a gate nobody reads, so findings outside the corpus path are reported with
  # file:line and do not gate. The corpus path is `graphcmp`, `isolate`, `hermetic-census`, and
  # `arith/both-census` (whose `ops_of` this census imports).
  GATE_SCOPE = ("graphcmp.py", "graphcmp-oracle.py", "hermetic/", "checks/both-census.py",
                "reach/census.py", "reach/rows.py")
  mine, theirs, checked = [], [], 0
  for f in sorted(SLOP.rglob("*.py")):
    if any(s in str(f) for s in skip): continue        # hermetic/ is IN scope now: it is on
                                                      # the corpus path, so it gates itself
    L = f.read_text(errors="replace").splitlines()
    if not any("tinygrad" in ln for ln in L): continue
    dev = [i for i, ln in enumerate(L, 1) if "environ" in ln and any(s in ln for s in SET)]
    imp = [i for i, ln in enumerate(L, 1)
           if ln.startswith("import tinygrad") or ln.startswith("from tinygrad")]
    lt = [i for i, ln in enumerate(L, 1) if ln.strip().startswith("load_tinygrad(")]
    if not dev or not (imp or lt): continue
    checked += 1
    rel = str(f.relative_to(REPO))
    if min(dev) > (imp + lt)[0]:
      hit = f"{rel}: DEV at {min(dev)} AFTER tinygrad at {(imp + lt)[0]}"
      in_scope = any(g in rel for g in GATE_SCOPE) and not any(v in rel for v in VENDORED)
      (mine if in_scope else theirs).append(hit)
  check("C3b GATE nothing ON THE CORPUS PATH assigns DEV after tinygrad", not mine,
        f"{checked} scripts assign DEV and load tinygrad; {len(mine)} in-scope offenders {mine}")
  # REPORTED, NOT GATING. Findings in other units' trees, carried with file:line. MEASURED, not
  # read: `oracles/mm-range.py` asks for NULL at :59 and `Device.DEFAULT` is METAL there.
  print(f"       reported (off the corpus path, NOT gating): {len(theirs)}")
  for h in theirs: print(f"         {h}")


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--dev", default="CPU")
  ap.add_argument("--only", default="cdiv,late")
  a = ap.parse_args()
  names = sorted(G.GRAPHS) if a.only == "ALL" else a.only.split(",")
  c1_process(a.dev)
  c2_cache(names, a.dev)
  c3_dev(a.dev, names)
  audit_dev_sites()
  print(f"\n{'AUDIT OK' if not FAIL else 'AUDIT FAILED: ' + ', '.join(FAIL)}")
  return 0 if not FAIL else 1


if __name__ == "__main__":
  sys.exit(main())