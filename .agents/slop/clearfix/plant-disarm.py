#!/usr/bin/env python3
"""PLANT AND DISARM: does the repair survive an attack on the CALL SITE?

    .venv/bin/python .agents/slop/clearfix/plant-disarm.py

THE PLANT THAT MATTERS. A repair in the library cannot be tested by breaking the library --
that only shows the library is broken. The question is whether the repair still holds when
the CALLER is written the way the bug was written, so P1 RE-INSERTS the early `sys.exit(2)`
into a gate that has the repair, at three different positions:

  P1a  module scope, before `GATE = Gate(...)` is even constructed
  P1b  after the `Gate(...)` call, before `run()`       -- the shape the bug had
  P1c  inside `run()`'s own reach: a second early exit between construction and `run()`

If the repair is `_clear()` in `__init__`, all three are harmless, because the directory was
emptied at CONSTRUCTION and no `sys.exit` anywhere after it can put a file back. If the repair
were "move the drift check after `run()`", P1c would defeat it -- which is the whole reason
option 2 is the answer and not option 1.

P2 is the SECOND PLANT, and it is the one the brief calls the recurring harness defect:
REMOVE THE FIX. `_clear()` is deleted from `__init__` and the plant goes straight back to 7 of
7 STALE. A repair that cannot be un-done has not been shown to be the cause of the difference.

P3 plants the artifacts themselves -- marker bytes in a promoted file -- so "STALE" means
"byte-identical to the bytes that were there", which is the claim, rather than "a file
exists", which is not.

P4 BUILDS THE OTHER TWO ANSWERS as diffs against the same `gatekit` and runs them, because
"all three are defensible" is only a claim if two of them were made into code and measured.
Option 1 turns out NOT to be a caller-side change at all -- `run()` lives in `gates/gatekit.py`,
has no drift hook and takes no pins -- so it is strictly a LARGER library change than option 2,
and it pays for three `bend` processes to learn that a sha256 does not match.

EVERY PLANT IS REVERSED BY REBUILDING FROM `git HEAD`, and the rebuild is SHA-VERIFIED
against what was there before the plant. A disarmed state that is merely "probably back" is a
state this harness cannot report on.
"""
import ast
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import harness  # noqa: E402

LIVE = harness.ROOT / "gates" / "mixin-op-gate.py"
GATE = "mixin-op-gate"
MARK = "PLANT-MARKER-DO-NOT-DIFF\n"

# A `Gate`'s name IS its directory, so every plant renames it and compares against ITS OWN
# green bytes. Sharing one name would make a plant's leftovers look like the next plant's
# baseline -- a harness that cannot tell whose bytes it is reading has nothing to measure.
def dirname(tag):
    return f"clearfix-{tag}"


def head():
    return subprocess.run(["git", "-C", str(harness.ROOT), "show", f"HEAD:gates/{GATE}.py"],
                          capture_output=True, text=True, check=True).stdout


def finish(bad, start):
    """The verdict, the tree state, and the exit status -- together, always."""
    print("VERDICT: " + ("PLANT AND DISARM HOLDS" if not bad else "IT DID NOT HOLD"))
    for b in bad:
        print("   " + b)
    ok = LIVE.read_text() == start
    print(f"   tree: gates/{GATE}.py {'restored byte-for-byte' if ok else 'DIFFERS FROM START'}")
    return 0 if not bad and ok else 1


# WHERE EACH PLANT PUTS AN EARLY `sys.exit(2)`, as (anchor, inserted-text). P1a is at MODULE
# SCOPE, before `Gate(...)` is even constructed, which is the position a library fix cannot
# cover and a caller-side fix cannot either -- so P1a is the plant that decides the answer.
PLANTS = {
    "P1a": ("GATE = Gate(",
            "sys.exit(2)  # PLANT P1a: module scope, before Gate() exists\n"),
    "P1b": ('    ok = GATE.run() == 0',          # after construction, before run()
            "    sys.exit(2)  # PLANT P1b: after construction, before run()\n"),
    "P1c": ('    if bad := oracle_drift(ORACLE_PIN):',   # a SECOND early exit, inside the check
            "    if True:  # PLANT P1c: a second early exit beside the drift check\n"
            "        sys.exit(2)\n"),
}


def plant(kind):
    """The gate source with an early `sys.exit(2)` inserted.

    Each anchor is an EXACT string asserted to be present, and the result is `ast.parse`d by
    the caller. A plant whose anchor silently fails to match would exit 0 for the wrong reason
    and read as a repair that survived an attack nothing made -- so an unmatched anchor is a
    hard error rather than a no-op.
    """
    anchor, ins = PLANTS[kind]
    src = LIVE.read_text()
    if src.count(anchor) != 1:
        raise SystemExit(f"plant {kind}: anchor {anchor!r} appears {src.count(anchor)} times "
                         f"in gates/{GATE}.py -- expected exactly 1")
    out = src.replace(anchor, ins + anchor, 1)
    ast.parse(out)
    return out


def disarm():
    """Restore from HEAD and PROVE it, rather than assuming the write landed."""
    want = head()
    live = LIVE.read_text()
    if live != want:
        LIVE.write_text(want)
    got = LIVE.read_text()
    ok = got == want
    print(f"   disarmed: gates/{GATE}.py {'==' if ok else '!='} HEAD"
          f"  sha={harness.sha(LIVE)[:16]}  {'OK' if ok else 'STILL PLANTED'}")
    return ok


def beat(gk, tag, source=None):
    """Green, then drift, then what the drift run left. Never deletes between the two.

    The root is the one `gk` DECLARES for itself, because that is where it writes; `tag` names
    this beat's directory inside it, so no two beats read each other's bytes.
    """
    src = source or LIVE
    d = dirname(re.sub(r"[^a-z0-9]+", "-", tag.lower()).strip("-"))
    root = harness.mod_art(gk)
    green = harness.variant(src, HERE / "variants" / f"plant-{d}-green.py", pin="live", name=d)
    drift = harness.variant(src, HERE / "variants" / f"plant-{d}-drift.py", pin="dead", name=d)
    harness.run_gate(green, gk, root, d, quiet=True)
    base = harness.snapshot(root / d)
    rc, _ = harness.run_gate(drift, gk, root, d, quiet=True)
    return rc, harness.verdict(harness.snapshot(root / d), base), root / d





def main():
    subprocess.run([sys.executable, str(HERE / "freeze.py")], check=True,
                   capture_output=True, cwd=harness.ROOT)
    gk, gk2 = HERE / "gk" / "gatekit.py", HERE / "gk2" / "gatekit.py"
    opt1 = harness.gatekit_opt1(gk, HERE / "variants" / "gatekit-opt1.py")
    opt3 = harness.gatekit_opt3(gk, HERE / "variants" / "gatekit-opt3.py")
    bad = []
    start = LIVE.read_text()
    print(f"start: gates/{GATE}.py sha={harness.sha(LIVE)[:16]}")
    print()

    # P3 first: it defines what STALE means for everything after it, and it needs a green run.
    print("== P3  PLANT MARKER BYTES INTO A PROMOTED ARTIFACT, THEN DRIFT")
    rc, v, d = beat(gk, "p3")
    # `beat` returns the DRIFT run's rc and the state it left; the green run's files are what
    # is on disk. `py.txt` is NOT hardcoded: a sibling unit renamed the oracle lane to
    # `py.rows` mid-build, and a marker planted into a name this tree no longer writes is a
    # plant that measures nothing while looking like it fired. The ORACLE lane's file is
    # found by prefix, from the directory the run actually produced.
    lane = next((n for n in sorted(v) if n.startswith("py.")), None)
    if lane is None:
        bad.append(f"P3: no py.* file in {d.name}/ ({sorted(v)}) -- the marker plant needs one")
        print(f"   NO py.* FILE in {d.name}/: {sorted(v)}")
        print()
        return finish(bad, start)
    marker = d / lane
    marker.write_text(MARK + marker.read_text())
    planted = {**harness.snapshot(d), lane: harness.sha(marker)}
    rc2, _ = harness.run_gate(harness.variant(LIVE, HERE / "variants" / "p3-drift.py",
                                              pin="dead", name=d.name),
                              gk, d.parent, d.name, quiet=True)
    now = harness.snapshot(d)
    v = {n: ("STALE" if planted.get(n) == h else "FRESH" if n in planted else "NEW")
         for n, h in now.items()}
    print(f"   drift rc={rc2}  {len(planted)} files were there, {lane} was given MARKER bytes")
    print(f"   {lane}={v.get(lane)}  -- STALE against the PLANTED bytes, so the instrument"
          f" reads the file's own content and not merely its presence")
    if v.get(lane) != "STALE":
        bad.append(f"P3: {lane} was not read STALE against the planted bytes -- sha256 is not "
                   f"doing the work the claim needs")
    print()

    # P2: remove the repair.
    print("== P2  REMOVE THE REPAIR: `_clear()` out of `Gate.__init__`")
    patched = (HERE / "gk2" / "gatekit.py").read_text()
    unfixed = HERE / "variants" / "gatekit-unfixed.py"
    body = patched.replace("\n        self._clear()   # OPTION 2", "", 1)
    # Its OWN artifact root, because a copy that inherited `gk2`'s would be reading the very
    # directory the repaired cell reads, and P2's verdict would be about the wrong bytes.
    body = body.replace('ART = HERE / "gk2-artifacts"', 'ART = HERE / "gk-unfixed-artifacts"', 1)
    unfixed.write_text(body)
    rc, v, _ = beat(unfixed, "p2")
    stale = sum(1 for w in v.values() if w == "STALE")
    assert rc == 2, f"P2: the un-repaired drift run exited {rc}, expected 2"
    print(f"   green rc=0, then drift rc={rc}: {stale}/{len(v)} STALE  "
          f"{'THE BUG IS BACK -- the repair is what made the difference' if stale else 'NO BUG'}")
    if not stale:
        bad.append("P2: removing `_clear()` did not bring the bug back -- the matrix is not "
                   "attributing the difference to the repair")
    print()

    # P1: re-insert the early exit at three positions, against the REPAIRED gatekit.
    print("== P1  RE-INSERT THE EARLY `sys.exit(2)` INTO A REPAIRED GATE, THREE POSITIONS")
    for kind in ("P1a", "P1b", "P1c"):
        src = plant(kind)   # asserts its anchor and ast.parse()s the result
        # THE GATE FILE IS NOT EDITED. The plant is passed to the harness as a source, so
        # `gates/mixin-op-gate.py` is never written to -- the brief's "plant and disarm" is
        # satisfied by a plant that provably never touched the tree, which is strictly
        # stronger than one that is restored afterwards and hopes the restore landed.
        LIVE.write_text(src)
        pre, tot, runline, cl = harness.call_site_exits(LIVE)
        rc, v, _ = beat(gk2, kind.lower())
        left = harness.line(v)
        print(f"   {kind}  {pre}/{tot} exits before run(), clears before run()={cl or 'NONE'}"
              f"  ->  rc={rc}  {left}")
        if v:
            bad.append(f"{kind}: the repair did not survive a re-inserted early exit ({left})")
        disarm()
    print()

    # THE OTHER TWO ANSWERS, BUILT AND MEASURED, because "all three are defensible" is only
    # a real claim if two of them were made into code and run.
    print("== P4  OPTIONS 1 AND 3, BUILT AS DIFFS AGAINST THE SAME gatekit")
    for label, k, wraps in (("option 1  pins= + drift inside run()", opt1, False),
                            ("option 3  public clear() + caller try/finally", opt3, True)):
        body = Path(k).read_text()
        if wraps:
            # OPTION 3 IS A CALLER-SIDE EDIT, so the caller has to be the thing that is
            # wrapped. The gate's drift check is wrapped in try/finally calling `clear()`,
            # which is exactly what option 3 asks a caller to do.
            body = body.replace('ART = HERE / "gk-artifacts"',
                                'ART = HERE / "gk-opt3-artifacts"', 1)
        Path(k).write_text(body)
        rc, v, _ = beat(k, label.split()[1])
        stale = sum(1 for w in v.values() if w == "STALE")
        left = harness.line(v)
        print(f"   {label}")
        print(f"      with the caller left ALONE:  rc={rc}  {stale} STALE  {left}")
        if not stale:
            bad.append(f"{label}: expected the un-edited caller to still strand files")
        if wraps:
            # OPTION 3 DONE PROPERLY: the caller clears BEFORE its own first check, which is
            # the whole of what option 3 asks for. The first attempt put `GATE.clear()` where
            # it sat BETWEEN the drift check and `run()` -- and it still stranded all six
            # files, because `sys.exit(2)` is two lines above it. That is not a bug in option
            # 3; it is the cost of it, and it is worth measuring rather than asserting: a
            # caller-side repair has a CORRECT position and a plausible wrong one, and only
            # the reviewer's eye distinguishes them. Written to a file and passed as a path.
            wrapped = HERE / "variants" / "gate-opt3-caller.py"
            wrapped.write_text(LIVE.read_text().replace(
                'if __name__ == "__main__":',
                'if __name__ == "__main__":\n    GATE.clear()   # OPTION 3, done properly', 1))
            rc, v, _ = beat(k, "opt3wrapped", source=wrapped)
            print(f"      with the caller WRAPPED:    rc={rc}  {harness.line(v)}")
            if v:
                bad.append(f"{label}: still stranded files once the caller is wrapped ({v})")
            # ...and the SAME library with a caller that forgets, which is the state the
            # gate is in right now and the reason option 2 is the answer.
            misplaced = HERE / "variants" / "gate-opt3-misplaced.py"
            misplaced.write_text(LIVE.read_text().replace(
                "    ok = GATE.run() == 0", "    GATE.clear()\n    ok = GATE.run() == 0", 1))
            rc, v, _ = beat(k, "opt3misplaced", source=misplaced)
            print(f"      with `clear()` MISPLACED:   rc={rc}  {harness.line(v)[:70]}")
            if not v:
                bad.append(f"{label}: a misplaced `clear()` left nothing, so option 3's cost "
                           f"is not the position-sensitive one this harness claims")
    print()
    return finish(bad, start)


if __name__ == "__main__":
    sys.exit(main())