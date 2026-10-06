#!/usr/bin/env python3
"""mmfold-plant.py -- THE PLANT AND THE DISARM, both run, so the verdict is a measurement.

    .venv/bin/python .agents/slop/mmfold/mmfold-plant.py

EVERY MUTATION HAPPENS IN A THROWAWAY COPY OF THE TREE under $TMPDIR. The live
`tinybendygrad/uop/fold.bend` is read and never written, and this is not a style preference: six
units are live on it, and `agent-core.md` records one unit's `cp -R src "$W/tree/"` with no
destination RENAMING the directory so that its empty hashes looked like a concurrent edit.

WHAT EACH ONE IS PROVING, and the pair is the point -- a red with no paired disarm says nothing
about where the verdict landed, and three controls in this project were found disarmed:

  PLANT   Drop the carry out of `mm.u64.add`. It is a SEMANTIC mutation in the port's own
          arithmetic, not a changed string, and it has a PREDICTABLE set of victims: only the
          three `add` fixtures whose LOW word overflows (`add_carrylo`, `add_carryhi`,
          `add_maxmax`). The lane must report exactly those three and no others.

  DISARM  Swap two INDEPENDENT row lines. Every value is unchanged and only the order moves, so
          the set of `name -> value` answers must be byte-identical and the verdict must not
          move. This is what makes the plant's redness attributable to a VALUE rather than to
          any difference at all -- and it is the check a "change detector" fails, which
          `agent-core.md` names as a harmful kind of test.

THREE PRECONDITIONS PER MUTATION, all of them inherited failures:

  1. THE MUTANT APPLIED. The target substring must occur EXACTLY ONCE. `nv_mutate.py` had two
     valid anchors whose mutants did not compile and had been reporting 19 of 28 entries as the
     whole; "the harness reported 0" and "the harness never applied anything" print the same.
  2. THE MUTANT COMPILES. `bend --check-only` must be clean for the changed file, or the port
     lane dies and a DIED verdict would be read as a measurement.
  3. THE PORT'S OUTPUT MOVED. sha256 over the port's stdout, before and after. A vacuous plant
     is the sharpest trap recorded here: flipping a value whose other operand was already `True`
     left a lane's sha256 IDENTICAL, and reading that unchanged verdict as "the gate is blind"
     would have been a false finding.
"""
import hashlib
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[3]
SLOP = REPO / ".agents" / "slop"
BEND = REPO / "bin" / "bend"
LIVE = REPO / "tinybendygrad"
TARGET = "uop/fold.bend"

# `+hi = U32.add(U32.add(ah, bh), mm.u32c(al, bl))` -> the carry is replaced by 0. This is the
# whole mutation: one call, one substitution, and the rows it can reach are enumerable by hand.
PLANT = ("  +hi = U32.add(U32.add(ah, bh), mm.u32c(al, bl))",
         "  +hi = U32.add(U32.add(ah, bh), 0)", "mm.u64.add: drop the low-word carry")

# Two `bl_row` lines that share nothing. Reordering them cannot change any answer, so a lane that
# reports a movement here is reporting a difference that does not exist.
A = '    bl_row("bl_3", U32.show(mm.bl64(0, 3)))'
B = '    bl_row("bl_4", U32.show(mm.bl64(0, 4)))'
DISARM = (A + "\n" + B, B + "\n" + A, "swap two independent bl_row lines")

# THE VICTIMS, DERIVED AND THEN MEASURED -- and the derivation was WRONG twice, which is why the
# measurement is the number below and not the prose. Dropping the carry reaches exactly the ADD
# fixtures whose LOW word wraps, i.e. `U32.add(al, bl) < al`:
#
#     add_carrylo (2**32-1, 1)        lo wraps, hi gains the carry   VICTIM
#     add_carryhi (1, 2**32-1)        lo wraps, hi gains the carry   VICTIM
#     add_2p31    (2**31, 2**31)      2**31+2**31 IS 2**32, so it wraps too   VICTIM
#     add_maxmax  (2**64-1, 2**64-1)  NOT A VICTIM, and it is the interesting one: with the carry
#                                    `hi` is 2**32-1 and without it 2**32-2, but BOTH spellings
#                                    overflow, so both print `OVER`. A row that cannot fail is not
#                                    a row; this one is exercised and not discriminating.
#     add_zero/add_small/add_hilo/add_over64   no low-word wrap, so the carry is 0 either way
#
# I first predicted {carrylo, carryhi, maxmax} and the run said otherwise: the plant moved
# `add_2p31` and NOT `add_maxmax`. Prose about arithmetic is not a measurement.
VICTIMS = {"mm_add_2p31", "mm_add_carryhi", "mm_add_carrylo"}


def port_stdout(port):
  r = subprocess.run([str(BEND), str(port)], capture_output=True, text=True,
                     timeout=3600, cwd=str(REPO))
  if r.returncode != 0:
    raise SystemExit(f"port lane died: {port}\n{r.stderr[-2000:]}")
  return r.stdout


def digest(text):
  return hashlib.sha256(text.encode()).hexdigest()[:16]


def compile_check(path):
  r = subprocess.run([str(BEND), str(path), "--check-only"], capture_output=True, text=True,
                     timeout=3600, cwd=str(REPO))
  noise = ("2.0.35 is available",)
  bad = [l for l in r.stderr.splitlines() if l.strip() and not any(n in l for n in noise)]
  return r.returncode == 0 and not bad, bad[:4]


def apply_once(text, old, new, label):
  n = text.count(old)
  if n != 1:
    raise SystemExit(f"MUTANT NEVER APPLIED ({label}): anchor occurs {n} times, want 1")
  return text.replace(old, new, 1)


def mutated_tree(old, new, label):
  td = tempfile.mkdtemp(dir=pathlib.Path(tempfile.gettempdir()))
  dst = pathlib.Path(td) / "tinybendygrad"
  shutil.copytree(LIVE, dst, symlinks=True)
  f = dst / TARGET
  base = f.read_text()
  f.write_text(apply_once(base, old, new, label))
  ok, bad = compile_check(f)
  if not ok:
    raise SystemExit(f"MUTANT DOES NOT COMPILE ({label}): {bad}")
  return f


def lane(port):
  r = subprocess.run([sys.executable, str(SLOP / "mmfold" / "mmfold-lane.py"),
                      "--port", str(port)], capture_output=True, text=True, timeout=3600)
  return r.returncode, r.stdout


def parse(out):
  d = {}
  for key in ("COMPARED", "DISAGREEMENTS", "MISSING FROM PORT"):
    m = re.search(rf"{key} (\d+)", out)
    d[key] = int(m.group(1)) if m else None
  d["verdict"] = "GREEN" if re.search(r"^VERDICT GREEN", out, re.M) else "NOT GREEN"
  m = re.search(r"^LANE INTEGRITY (.*)$", out, re.M)
  d["integrity"] = m.group(1).strip() if m else "?"
  return d


def disagreeing(out):
  return set(re.findall(r"^  DISAGREE (\S+):", out, re.M))


def verdict_line(d):
  return (f"    COMPARED {d['COMPARED']}  DISAGREEMENTS {d['DISAGREEMENTS']}  "
          f"MISSING FROM PORT {d['MISSING FROM PORT']}  -> {d['verdict']}"
          f"\n    INTEGRITY: {d['integrity']}")


def main():
  base_out = port_stdout(LIVE / TARGET)
  base = parse(lane(LIVE / TARGET)[1])
  print("BASELINE (live tree, never written)")
  print(f"    port stdout sha256[:16] = {digest(base_out)}")
  print(verdict_line(base))
  if base["verdict"] != "GREEN":
    print("    NOTE: the baseline's OWN scope is not green; the run below still reports what MOVED.")

  print("\nPLANT: " + PLANT[2])
  f = mutated_tree(*PLANT)
  out = port_stdout(f)
  print(f"    precondition 3 -- port stdout sha256[:16] = {digest(out)} "
        f"({'MOVED' if digest(out) != digest(base_out) else 'DID NOT MOVE -- VACUOUS PLANT'})")
  if digest(out) == digest(base_out):
    raise SystemExit("VACUOUS PLANT: the mutation changed no output, so a green verdict below "
                     "would prove nothing.")
  rc, lo = lane(f)
  p = parse(lo)
  moved = disagreeing(lo)
  print(verdict_line(p))
  print(f"    rows it moved by name: {sorted(moved)}")
  print(f"    expected victims     : {sorted(VICTIMS)}")
  print(f"    PLANT {'PASS' if moved == VICTIMS and p['DISAGREEMENTS'] == len(VICTIMS) and rc else 'FAIL'}"
        f" (lane rc={rc})")

  print("\nDISARM: " + DISARM[2])
  g = mutated_tree(*DISARM)
  out2 = port_stdout(g)
  print(f"    port stdout sha256[:16] = {digest(out2)} "
        f"({'same bytes, different order' if digest(out2) != digest(base_out) else 'IDENTICAL'})")
  rc2, lo2 = lane(g)
  d = parse(lo2)
  print(verdict_line(d))
  same = all(d[k] == base[k] for k in ("COMPARED", "DISAGREEMENTS", "MISSING FROM PORT"))
  print(f"    measurement identical to baseline: {same}   lane rc={rc2}")
  print(f"    DISARM {'PASS' if same and not disagreeing(lo2) else 'FAIL'} -- a lane that moved here "
        f"would be a change detector, and agent-core.md names that as a harmful test. rc is NOT part "
        f"of this check: the baseline is already non-green on a defect OUTSIDE these two oracles.")


if __name__ == "__main__":
  main()
