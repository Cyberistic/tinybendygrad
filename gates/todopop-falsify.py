#!/usr/bin/env python3
"""todopop-falsify.py -- prove that `todopop-gate.py` can FAIL, by breaking it on purpose.

    .venv/bin/python gates/todopop-falsify.py

A PLANT THAT CANNOT FAIL IS NOT A PLANT. Two of this project's earlier checks were retired for
exactly that: one "made the lane emit nothing while the check scored it as a successful plant",
and a first negative was vacuous because it flattened both sides to one constant. So this file
takes a COPY of the gate, the unit, the census, `gatekit.py` and the subject into a temporary tree
and breaks one thing at a time, and it FAILS if any break leaves the gate green.

THE REAL FILES ARE NEVER TOUCHED. `todo-census.py` is an existing gate and is not this unit's to
edit, so every break is applied to `tmp/gates/todo-census.py` -- which is possible because
`todopop-gate.py` finds its census, its declaration and its subject relative to its own location.
That self-location is what makes the gate falsifiable at all.

THE FIVE BREAKS, AND THE EXIT EACH MUST PRODUCE.

  DECLARATION-DRIFT   the census's SITE token becomes the substring unit -> 1, and lane 1 must name
                      the two patterns. This is the check that makes "they share one declaration"
                      structural: with it, a one-character edit to either file is caught.
  POPULATION-DRIFT    the census silently stops walking one file -> 1, and lane 2 must name the rows
                      only one side has. A count difference without the rows named is unreadable.
  ONE-ROW-PER-FILE    the declaration counts a file once, keeping its token -> 1, and the output
                      must carry BOTH lane 2's disagreement AND the vacuity complaint. This is the
                      case a constant-flipping negative would have passed: the planted line lands
                      in a file that already has rows, so a file-counting unit moves by 0, exactly
                      as the near-miss control does, and "the count did not change" would look
                      identical to a clean plant without the `d_rows == c_rows` complaint.
  EMPTY-UNIT          the declaration's token matches nothing -> 3 (REFUSED), because no file
                      carries a row and so the plant has no target. It raised StopIteration and
                      exited 1 until this case was run, which is 1 = FAIL.
  SUBJECT-MOVED       a `.bend` file appears between the gate's two digests -> 3 (REFUSED), because
                      a reading of a tree that changed under it is a reading of two subjects.

EACH CASE CARRIES ITS OWN UNBROKEN CONTROL -- the same staged tree with the break absent -- and
the case passes only if the control is PASS and the broken run is the expected non-PASS. A case
with no control would only prove that something exited non-zero, which is the vacuous negative.
"""
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
PY = REPO / ".venv" / "bin" / "python"
CARRY = ("gatekit.py", "todopop-gate.py", "todopop-unit.py", "todo-census.py")
PASS, FAIL, REFUSED = 0, 1, 3


def stage(root):
    """A self-contained tree: the four files and a copy of the subject.

    `.venv` is symlinked, not copied: the gate resolves its interpreter relative to ITS OWN
    location, so without it every case measures a missing-precondition refusal instead of the
    break it was staged to make.
    """
    (root / "gates").mkdir(parents=True)
    for name in CARRY:
        shutil.copy2(HERE / name, root / "gates" / name)
    shutil.copytree(REPO / "tinybendygrad", root / "tinybendygrad")
    (root / ".venv").symlink_to(REPO / ".venv")
    return root / "gates" / "todopop-gate.py"


def run(gate):
    proc = subprocess.run([str(PY), str(gate)], capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def break_token(census):
    text = census.read_text()
    census.write_text(text.replace('SITE = re.compile(r"\\bTODO\\b")',
                                   'SITE = re.compile("TODO")'))


def break_walk(census):
    """Drop one file from the census's walk, so the two row sets differ by that file's rows."""
    text = census.read_text()
    census.write_text(text.replace(
        '  return sorted(found)',
        '  return sorted(p for p in found if not p.endswith("LAWS.bend"))'))


def break_unit(unit):
    """One row per FILE instead of one per line: the token still agrees, the unit does not.

    This is the mutation the vacuity check exists for. The planted line lands in a file that
    already has rows, so a file-counting unit moves by 0 -- exactly like the near-miss control
    does -- and a gate without the `d_rows == c_rows` complaint would score it as a clean plant.
    """
    text = unit.read_text()
    unit.write_text(text.replace(
        "                if TOKEN.search(line):\n"
        "                    out.append((key(path, repo, root), number))",
        "                if TOKEN.search(line):\n"
        "                    out.append((key(path, repo, root), number))\n"
        "                    break"))


def break_empty_unit(unit):
    """A token that matches nothing anywhere: the gate must REFUSE, not raise."""
    text = unit.read_text()
    unit.write_text(text.replace('TOKEN = re.compile(r"\\bTODO\\b")',
                                 'TOKEN = re.compile(r"\\bNOSUCHTOKEN\\b")'))


def move_subject(subject, gate):
    """Write a new `.bend` file into the staged subject while the gate is measuring it."""
    time.sleep(0.4)
    (subject / "zz-todopop-falsify.bend").write_text(
        "# TODO(p3) falsify.py planted a site mid-read\n", encoding="utf-8")


CASES = (
    # name, breaker, file it breaks, exit before, exit after, tokens the output must carry
    ("DECLARATION-DRIFT", break_token, "todo-census.py", PASS, FAIL, ("LANE1",)),
    ("POPULATION-DRIFT", break_walk, "todo-census.py", PASS, FAIL, ("LANE2",)),
    ("ONE-ROW-PER-FILE", break_unit, "todopop-unit.py", PASS, FAIL, ("LANE2", "LANE4", "VACUOUS")),
    ("EMPTY-UNIT", break_empty_unit, "todopop-unit.py", PASS, REFUSED, ("REFUSED",)),
    ("SUBJECT-MOVED", None, "", PASS, REFUSED, ("REFUSED",)),
)


def main():
    results = []
    for name, breaker, victim, want_before, want_after, tokens in CASES:
        with tempfile.TemporaryDirectory(prefix=f"todopop-{name}-") as tmp:
            root = Path(tmp)
            gate = stage(root)
            if breaker:
                breaker(root / "gates" / victim)
            thread = None
            if name == "SUBJECT-MOVED":
                thread = threading.Thread(target=move_subject, args=(root / "tinybendygrad", gate))
                thread.start()
            code, out = run(gate)
            if thread:
                thread.join()

            # The un-broken gate on the same staged tree, as the control for THIS case. Without it
            # a case proves only that something exited non-zero, which is the vacuous negative.
            control_code = None
            if breaker:
                with tempfile.TemporaryDirectory(prefix=f"todopop-{name}-ctl-") as tmp2:
                    control_code = run(stage(Path(tmp2)))[0]

            ok = (code == want_after
                  and all(t in out for t in tokens)
                  and (control_code == want_before if breaker else True))
            results.append((name, control_code, code, want_after, ok, out))

    width = max(len(n) for n, *_ in results)
    for name, control, code, want, ok, _ in results:
        print(f"{name:<{width}}  control={control}  broken={code}  want={want}  "
              f"{'OK' if ok else 'NOT FALSIFIED'}")
    bad = [r for r in results if not r[4]]
    for name, control, code, want, ok, out in bad:
        print(f"\n--- {name} was not falsified (control={control} broken={code} want={want}) ---\n{out}")
    if bad:
        return FAIL
    print(f"todopop-falsify PASS -- {len(results)}/{len(results)} breaks each turned the gate from "
          f"PASS to its expected exit, on copies; the real census was not edited")
    return PASS


if __name__ == "__main__":
    sys.exit(main())
