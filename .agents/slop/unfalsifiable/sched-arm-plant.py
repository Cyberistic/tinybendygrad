#!/usr/bin/env python3
"""sched-arm-plant.py -- PLANT AND DISARM THE UNCODED-OP HAZARD, END TO END.

THE HAZARD (audit 03). `sched-cmp.py` encodes op names with `dig`, which answers 0
for any name outside its 17-entry `DIG`. 0 is also `pack([])`. So a spec whose
compared field is built only from uncoded ops compares EQUAL to an empty field, on
both sides, and reads as agreement. The census of uncoded ops was a loop that
discarded its result (`sched-cmp.py:135`) while the docstring claimed it printed.

WHAT THIS DOES, IN ORDER. Nothing here is transcribed and nothing in the live tree is
written; every mutation is a COPY under $TMPDIR.

  0  FIDELITY. Bend the live fixture and compare with the committed
     `sched-port.txt`. A control on the substrate, so a later zero is not the
     substrate's fault.
  1  PRE-FIX, ARMED. Add a 7th spec `where` to BOTH generators (the oracle's SPECS
     is read by sched-emit.py and sched-fixture.py, so one edit flows to the port),
     rebuild the fixture in the copy, run bend, and run the PRE-FIX comparator.
     THE NUMBER TO READ: does it say `AGREE where_kmark=0` at rc=0 with no mention of
     an uncoded op?
  2  POST-FIX, ARMED. Same copy, the fixed comparator. THE NUMBER TO READ: the census
     names WHERE and the run is red.
  3  DISARM A (corpus). The live 6-spec tree: every packed name is coded, so the
     census must be 0 and the run must stay green.
  4  DISARM B (SCOPE -- the sharp one). Add an 8th spec `where_relu` whose GRAPH
     contains a WHERE but whose compared `_kmark` field does not. The census must
     still report ONE occurrence, not two: the census measures the COMPARED FIELDS,
     not the graph. A census that counted graph-level ops would go red on a spec that
     compares correctly, which would be its own unfalsifiable number.
  5  DISARM C (planted VALUE must still move the agreement)
  6  PLANT C  THE PORT ITSELF: a port edit in a COPY, with the snapshot REGENERATED
     from it. This is the case the committed comparator could not see at all.
  7  DISARM D  agent-core's `$TMPDIR` trap, deliberately: bend cannot resolve the
     fixture's relative imports and prints SOME PROOFS FAIL with 0 rows. The
     comparator must refuse to read that as agreement.

RUN:
  env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python \\
    .agents/slop/unfalsifiable/sched-arm-plant.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SLOP = os.path.join(REPO, ".agents/slop")
UNF = os.path.join(SLOP, "unfalsifiable")
PY = os.path.join(REPO, ".venv/bin/python")
BEND = os.path.join(REPO, "bin/bend")
TMP = os.path.join(tempfile.gettempdir(), "unfals")

PRE_FIX_COMPARATOR = open(os.path.join(SLOP, "unfalsifiable/pre-fix-sched-cmp.py")).read()

SPECS = '''
def s_where():
  """THE ARM: the compared `_kmark` field for this spec IS `['WHERE']`, an op
  `DIG` has no code for, so it packs to 0 -- which is also `pack([])`."""
  a, b, c = (Tensor.empty(4, 3) for _ in range(3))
  return Tensor.empty(4, 3).realize().assign(Tensor.where(a > b, a, c)).schedule_linear()

def s_where_relu():
  """DISARM B: the GRAPH contains a WHERE, but the STORE's value is a MAX, so no
  compared field is built from an uncoded name."""
  a, b, c = (Tensor.empty(4, 3) for _ in range(3))
  return Tensor.empty(4, 3).realize().assign(Tensor.where(a > b, a, c).relu()).schedule_linear()

'''


def env():
  e = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
  e["LC_ALL"] = "C"
  e["DEV"] = "NONE"
  return e


def sha(rows):
  import hashlib
  return hashlib.sha256("\n".join(r for r in rows if r.strip()).encode()).hexdigest()


def bend(fixture, out=None):
  r = subprocess.run([BEND, fixture], capture_output=True, text=True, env=env(),
                     cwd=REPO, timeout=3600)
  rows = r.stdout.splitlines()
  if out:
    with open(out, "w") as f:
      f.write("\n".join(rows) + "\n")
  return rows, r.returncode


def run_cmp(here):
  r = subprocess.run([PY, os.path.join(here, "sched-cmp.py")], capture_output=True,
                     text=True, env=env(), cwd=REPO, timeout=3600)
  return r.stdout + r.stderr, r.returncode


def show(label, text, rc, keys=("# port side", "# SNAPSHOT", "# specs_", "# denominator",
                               "# UNCODED", "# VERDICT")):
  print(f"  rc={rc}")
  for ln in text.splitlines():
    if ln.startswith(keys):
      print("   ", ln)


def add_specs(d, names):
  """Insert the specs into the COPY's oracle SPECS and re-run both generators."""
  here = os.path.join(d, ".agents/slop")
  p = os.path.join(here, "sched-oracle.py")
  src = open(p).read()
  assert "\nSPECS = [\n" in src and src.count("\nSPECS = [\n") == 1
  src = src.replace("\nSPECS = [\n", SPECS + "SPECS = [\n" +
                    "".join(f'  ("{n}", s_{n}),\n' for n in names))
  open(p, "w").write(src)
  r = subprocess.run([PY, os.path.join(here, "sched-fixture.py")], capture_output=True,
                     text=True, env=env(), cwd=REPO, timeout=3600)
  assert "wrote" in r.stdout, r.stdout + r.stderr
  return r.stdout.strip().splitlines()[-1]


def build_copy(tag, names, comparator_from="fixed", plant_port=None,
               plant_snapshot=None):
  """A FULL copy root -- `.agents/slop/` AND `tinybendygrad/`, because the fixture's
  imports are `./../../tinybendygrad/...`. A flat copy cannot resolve them and
  prints `SOME PROOFS FAIL` with 0 rows; that is agent-core's `$TMPDIR` trap, and it
  is hit here on purpose once (case 5b) to show the comparator refuses to call that
  agreement."""
  d = os.path.join(TMP, tag)
  shutil.rmtree(d, ignore_errors=True)
  os.makedirs(os.path.join(d, ".agents/slop"))
  shutil.copytree(os.path.join(REPO, "tinybendygrad"), os.path.join(d, "tinybendygrad"))
  for f in ("sched-oracle.py", "sched-emit.py", "sched-fixture.py", "sched-port.txt"):
    shutil.copy(os.path.join(SLOP, f), os.path.join(d, ".agents/slop", f))
  print("   ", add_specs(d, names))
  if plant_port:
    p = os.path.join(d, "tinybendygrad/schedule/__init__.bend")
    src = open(p).read()
    mut = src.replace(*plant_port)
    assert mut != src, f"the port text to plant in was not found verbatim: {plant_port}"
    open(p, "w").write(mut)
    print(f"    PORT PLANTED in the COPY: {plant_port[0]!r} -> {plant_port[1]!r}")
  src = (open(os.path.join(SLOP, "sched-cmp.py")).read() if comparator_from == "fixed"
         else PRE_FIX_COMPARATOR)
  open(os.path.join(d, ".agents/slop/sched-cmp.py"), "w").write(src)
  # The fixture was just regenerated by sched-fixture.py in this copy. Do NOT copy
  # the live one over it -- that silently reverts the added specs, which is what
  # case 4 did on its first run and produced a 60-row port against an 8-spec oracle.
  rows, brc = bend(os.path.join(d, ".agents/slop/sched-fixture.bend"))
  snap_path = os.path.join(d, ".agents/slop/sched-port.txt")
  snap = "\n".join(ln for ln in rows if ln.strip()) + "\n"
  if plant_snapshot:
    mut = snap.replace(*plant_snapshot)
    assert mut != snap, f"the snapshot field to plant in was not found verbatim: {plant_snapshot}"
    snap = mut
    print(f"    SNAPSHOT PLANTED: {plant_snapshot[0]!r} -> {plant_snapshot[1]!r}")
  open(snap_path, "w").write(snap)
  print(f"    bend rc={brc}, {len([r for r in rows if '=' in r])} rows, "
        f"sha={sha(rows)[:16]}")
  return d


def main():
  os.makedirs(TMP, exist_ok=True)

  print("=" * 78)
  print("0  FIDELITY CONTROL -- bend the LIVE fixture, compare with the committed")
  print("   sched-port.txt. If this is not equal, every later number is suspect.")
  print("   COMPARED ON CONTENT, NOT BYTES: bend prints a blank line after every row")
  print("   (120 lines) and the committed snapshot has them stripped (60 lines), so a")
  print("   byte compare reports a difference that is not one. Same sha256 as")
  print("   sched-stage2.md publishes: 207ee494251e3dcde...")
  live, brc = bend(os.path.join(SLOP, "sched-fixture.bend"))
  committed = [ln.strip() for ln in
               open(os.path.join(SLOP, "sched-port.txt")).read().splitlines() if ln.strip()]
  rows = [ln.strip() for ln in live if ln.strip()]
  same = rows == committed
  print(f"    bend rc={brc}, {len(rows)} rows, sha={sha(rows)[:16]}")
  print(f"    live == committed snapshot (non-blank lines): {same}")
  assert same, "the committed snapshot does not match a live run -- stop"

  print("=" * 78)
  print("1  PLANT  -- 7th spec `where`, PRE-FIX comparator (the file as committed)")
  d1 = build_copy("arm-prefix", ["where"], comparator_from="prefix")
  text, rc = run_cmp(os.path.join(d1, ".agents/slop"))
  show("PRE-FIX ARMED", text, rc)
  print(f"    'AGREE where_kmark=0' present: {'AGREE where_kmark=0' in text}")
  print(f"    the word 'UNCODED' in the output: {'UNCODED' in text}")
  print(f"    the op name 'WHERE' anywhere in the output: {'WHERE' in text}")
  print("    ^ a SILENT ZERO: the field says 0, the run says rc=0, and nothing in")
  print("      the output says the 0 stands for an op neither side has code for.")

  print("=" * 78)
  print("1b THE SAME 7th SPEC, SEEN BY THE ORACLE'S OWN HEADER. Pre-fix the oracle")
  print("   read `scheduled_calls=25` -- 25 BLOCK KEYS, not 25 calls; the true count")
  print("   is 12. Both sides must now be computed from the same `SPECS` source.")
  for label, path in (("LIVE  (6 specs)", os.path.join(SLOP, "sched-oracle.py")),
                      ("ARMED (7 specs)", os.path.join(d1, ".agents/slop/sched-oracle.py"))):
    r = subprocess.run([PY, path], capture_output=True, text=True, env=env(), cwd=REPO,
                       timeout=3600)
    hdr = [ln for ln in r.stdout.splitlines() if ln.startswith("# specs_attempted")]
    print(f"  {label:16s} {hdr[0] if hdr else '(no header)'}")

  print("=" * 78)
  print("2  THE FIX, SAME COPY -- only the comparator differs")
  shutil.copy(os.path.join(SLOP, "sched-cmp.py"),
              os.path.join(d1, ".agents/slop/sched-cmp.py"))
  text, rc = run_cmp(os.path.join(d1, ".agents/slop"))
  show("POST-FIX ARMED", text, rc)
  print(f"    census names WHERE: {'WHERE=1' in text}")
  print(f"    'AGREE where_kmark=0' still present (the row is unchanged, only "
        f"reported): {'AGREE where_kmark=0' in text}")
  print("    ^ the fix makes the SAME comparison say what the 0 was. It does not")
  print("      invent a disagreement: both sides really do answer 0.")

  print("=" * 78)
  print("3  DISARM A -- the live 6-spec tree: every packed name is coded")
  print("   DISARMED BY 6 SPECS. The live tree, run twice, must read 6 and must stay")
  print("   green -- otherwise the fix would be a constant red, which proves nothing.")
  for _ in range(2):
    text, rc = run_cmp(SLOP)
  show("LIVE x2 (last run)", text, rc)

  print("=" * 78)
  print("4  DISARM B -- SCOPE. 8 specs; `where` ARMS, `where_relu` does NOT, though")
  print("   both graphs contain a WHERE. The census must report ONE occurrence.")
  d2 = build_copy("arm-disarm", ["where", "where_relu"])
  text, rc = run_cmp(os.path.join(d2, ".agents/slop"))
  show("DISARM B", text, rc)
  for n in ("where_kmark", "where_relu_kmark"):
    print("    ", [ln for ln in text.splitlines() if n in ln])

  print("=" * 78)
  print("5  PLANT B -- THE AUDIT'S PLANT 1: one port ROW changed in the SNAPSHOT only.")
  print("   Pre-fix this was `DISAGREE` (60 -> 59). Post-fix the port side is what")
  print("   THIS RUN produced, so the planted snapshot is reported as STALE instead --")
  print("   still red, and for the truer reason.")
  d3 = build_copy("arm-snapplant", [], plant_snapshot=("matmul_ktop=5", "matmul_ktop=9"))
  text, rc = run_cmp(os.path.join(d3, ".agents/slop"))
  show("PLANT B", text, rc)
  print("     DISAGREE lines:", [ln for ln in text.splitlines() if ln.startswith("DISAGREE")])

  print("=" * 78)
  print("6  PLANT C -- THE STALENESS WINDOW, CLOSED. Mutate the PORT in the COPY")
  print("   (`Lin.out` -> `List.drop(out, 1n)`, the audit's own plant), regenerate the")
  print("   snapshot FROM IT, and re-run. Pre-fix the committed comparator reported")
  print("   60/60 rc=0 over this because it never ran the port.")
  d4 = build_copy("arm-portplant", [],
                  plant_port=("    case Lin{ar, c, out}: out",
                              "    case Lin{ar, c, out}: List.drop(&2, U32, out, 1n)"))
  text, rc = run_cmp(os.path.join(d4, ".agents/slop"))
  show("PLANT C", text, rc)
  dis = [ln for ln in text.splitlines() if ln.startswith("DISAGREE")]
  print(f"    DISAGREE rows: {len(dis)}; first 4: {dis[:4]}")

  print("=" * 78)
  print("7  DISARM D -- agent-core's `$TMPDIR` trap, on purpose: a copy WITHOUT the")
  print("   tinybendygrad tree beside it cannot resolve the fixture's imports, so bend")
  print("   prints SOME PROOFS FAIL and 0 rows. The comparator must refuse to call")
  print("   that agreement.")
  d5 = os.path.join(TMP, "arm-norelative")
  shutil.rmtree(d5, ignore_errors=True)
  os.makedirs(d5)
  for f in ("sched-cmp.py", "sched-oracle.py", "sched-fixture.bend", "sched-port.txt"):
    shutil.copy(os.path.join(SLOP, f), os.path.join(d5, f))
  text, rc = run_cmp(d5)
  show("DISARM D (no relative imports resolvable)", text, rc)
  return 0


if __name__ == "__main__":
  sys.exit(main())