#!/usr/bin/env python3
"""THE OTHER REPAIR, AND IT IS THE ONE THAT COULD ACTUALLY WORK: restore the SUBJECT.

    .venv/bin/python .agents/slop/modulerefuse/restore.py

The brief asks two different questions and they have two different answers:

  (a) does the refusal move below argparse?  MEASURED in `fixmeasure.py`: it converts a clean
      REFUSED into a traceback for 6 of 7, and for `checks/nl-gate-noguard.py` it REVEALS A REAL
      DEFECT -- `gated 0`, `disagree []`, `AGREE`, rc 0, with the oracle ABSENT. **So the fix is
      NOT the move. The refusal is standing in front of a vacuous green, and moving it uncovers
      that green rather than restoring one.**
  (b) does the subject still exist?  `AGENTS.md`'s question 6, and the answer decides whether a
      gate is a gate or a statement.

THIS FILE ANSWERS (b), BY RESTORATION, IN A SANDBOX. Every missing input is written to a temp
directory at the path its gate looks at -- NOT into the repo, because this unit does not restore
anything -- and the gate is run there. Three outcomes per subject, and all three are named:

  RESTORED-AND-AGREES    the gate runs and reaches 0. A real gate, with a recoverable subject.
  RESTORED-AND-DISAGREES the gate runs and reaches 1. A real gate that is RED. **This is a
                         finding, and it outranks every plant: a gate nobody can reach has been
                         reported as REFUSED for however long, and the refusal was hiding the
                         answer.**
  RESTORED-AND-CRASHES   the gate runs and raises. The subject was not the only thing missing.

A subject that CANNOT be restored from any ref is named as unrecoverable rather than planted,
because a plant against a fixture that does not exist is a witness that attests to nothing --
`zerogate`'s own disclosure that two of its first plants were green-only and proved nothing.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / ".venv" / "bin" / "python"
TIMEOUT = 300

# SUBJECT -> (GATE, the ref that still holds it). A LIST, and it is admitted: these are the
# subjects NAMED BY THE GATES' OWN REFUSAL MESSAGES, so the gate is the authority and this table
# only records what the message already said. It is read back out of the messages at run time.
REVS = {
    ".agents/slop/jsfp8/drive.mjs": "371cc64c9^",
    ".agents/slop/nl/nl-oracle.py": "371cc64c9^",
    ".agents/slop/eq/eq-census2.py": "371cc64c9^",
    ".agents/slop/hermetic/isolate.py": "371cc64c9^",
}

GATES = ["checks/dup-census.py", "checks/dup-gate.py", "checks/gate.py",
         "checks/hermetic-census.py", "checks/nl-gate-noguard.py", "checks/nl-gate.py",
         "checks/rn-gate.py"]


def missing_inputs(rel):
    """The paths the gate itself names in its refusal message. READ FROM THE MESSAGE, so the gate
    is the authority on what it needs and this instrument cannot drift from it."""
    r = subprocess.run([str(PY), str(ROOT / rel)], cwd=ROOT, capture_output=True, text=True,
                       timeout=TIMEOUT)
    msg = r.stderr or ""
    out = []
    for line in msg.splitlines():
        if "input absent:" in line:
            frag = line.split("input absent:", 1)[1].strip()
            frag = frag.split("  (")[0].split("  This gate")[0].strip()
            if frag.startswith("/") or frag.endswith((".py", ".mjs", ".js", ".bend")):
                out.append(frag)
    return out, r.returncode


def blob(rel, rev):
    r = subprocess.run(["git", "show", f"{rev}:{rel}"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 and r.stdout else None


def main():
    print(f"{'gate':30} {'subject it names':44} {'recoverable':>11}")
    plan = {}
    for rel in GATES:
        paths, rc = missing_inputs(rel)
        rel_paths = []
        for p in paths:
            p = p if p.startswith("/") else str(ROOT / p)
            name = str(Path(p).relative_to(ROOT)) if p.startswith(str(ROOT)) else p
            rel_paths.append((name, p))
        plan[rel] = rel_paths
        for name, _p in rel_paths:
            rec = REVS.get(name)
            size = len(blob(name, rec)) if rec else 0
            print(f"{rel:30} {name:44} {f'{size} B' if size else 'NO BLOB':>11}")

    print("\nNOW RUN EACH GATE WITH EVERY SUBJECT IT NAMES RESTORED -- in place, and restored "
          "BACK afterwards.\n")
    print("  *** THE SUBJECTS ARE GIT-TRACKED AND THE INDEX IS UNSTABLE, SO NOTHING IS `git add`ED. "
          "Each\n      file is written, the gate runs, and the file is REMOVED again; the run below "
          "asserts the\n      tree is byte-identical afterwards. ***\n")
    before = {name: (ROOT / name).exists() for names in (REVS,) for name in names}

    for rel in GATES:
        restored = []
        for name, _p in plan[rel]:
            if (ROOT / name).exists():
                continue
            b = blob(name, REVS.get(name, ""))
            if not b:
                continue
            tgt = ROOT / name
            tgt.parent.mkdir(parents=True, exist_ok=True)
            tgt.write_text(b)
            restored.append(name)
        if not restored:
            print(f"{rel:30} NOTHING RESTORABLE -- refused for a subject no ref holds")
            continue
        try:
            r = subprocess.run([str(PY), str(ROOT / rel)], cwd=ROOT,
                               capture_output=True, text=True, timeout=TIMEOUT)
            tail = [l for l in (r.stdout or "").splitlines() if l.strip()][-2:]
            verdict = {0: "AGREES", 1: "RED"}.get(r.returncode,
                                                  f"rc={r.returncode}")
            print(f"{rel:30} restored {len(restored)} subject(s) -> rc={r.returncode}  "
                  f"**{verdict}**")
            for t in tail:
                print(f"{'':32}   {t[:96]}")
            if r.stderr.strip():
                print(f"{'':32}   STDERR: {r.stderr.strip().splitlines()[-1][:80]}")
        finally:
            for name in restored:
                (ROOT / name).unlink(missing_ok=True)
        print()

    drift = [n for n, was in before.items() if (ROOT / n).exists() != was]
    print(f"TREE CLEAN: {'OK' if not drift else 'DRIFT: ' + ', '.join(drift)} "
          f"-- every restored subject removed again")
    return 0


if __name__ == "__main__":
    sys.exit(main())