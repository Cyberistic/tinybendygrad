#!/usr/bin/env python3
"""PLANT AND DISARM `.agents/slop/e2estage8/verdicts.py` ON A FROZEN FIXTURE. Two defects, two
directions, and a negative for each.

    usage: .venv/bin/python gates/e2estage8-stage-selftest.py

NO substrate, no compiler, no port: every arm is a text edit of two committed fixtures into a
temporary directory, because a plant that needs the substrate cannot tell a defect from an outage --
which is exactly what the previous plant in this tree recorded, and why these fixtures exist.

**THE TWO DEFECTS THIS PLANTS, AND WHY EACH NEEDS ITS OWN PLANT.** The census read the `m` out of
`== n/m` and threw it away, so it was structurally unable to see a gate that prints a wrong
denominator; and `blocks()` re-opened a stage on ANY header-shaped line, including one printed by the
stage's OWN body, which reset its list and discarded what came before. **A PLANT ON THE DENOMINATOR
ALONE LEAVES THE SECOND ONE UNSEEN**, which is why arm 1 plants a re-open and then asserts the
denominator is still counted -- the re-open must cost the census its body lines and nothing else.

**NO ARM IS A NO-OP, AND NO ARM'S NEGATIVE IS VACUOUS.** Each `planted()` asserts the text it wrote
differs from the text it read, because `.agents/slop/e2estage8/plant.py` recorded an arm that "passed"
having patched nothing -- the shipped gate, against the same transcript, already produced the string
the arm expected. **AND EACH NEGATIVE DIFFERS FROM ITS PLANT IN THE ONE PLACE THE INSTRUMENT
LOOKS**, not in some unrelated corner: arm 4 keeps the digit, the slash and the digits, and moves the
line off column 0; arm 6 keeps `== 2/3` at column 0 and drops the space that follows the
denominator. A negative that differs everywhere flattens both sides to one constant and proves
nothing, and one such negative was recorded in this tree.
"""
from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT / "gates"
VERDICTS = ROOT / ".agents/slop/e2estage8/verdicts.py"
# THE PRE-FIX CENSUS, FROZEN AND BYTE-FOR-BYTE: `git cat-file blob eb67bf05`, which is
# `.agents/slop/e2estage8/verdicts.py` at HEAD, sha256 `c1c4d328...`. **EVERY PLANT BELOW IS RUN
# AGAINST IT, AND A PLANT THAT THE BLIND INSTRUMENT ALSO FAILS IS NOT A PLANT OF THIS DEFECT** -- it
# is a plant of something the old file could already see. Its own usage line names its old home; the
# selftest invokes it by absolute path, so that line is stale TEXT and nothing reads it.
LEGACY = HERE / "e2estage8-stage-legacy.py"
FIX_GATE = HERE / "e2estage8-stage-fixture.py"
FIX_TALK = HERE / "e2estage8-stage-fixture-transcript.out"


def census(talk: Path, gate: Path, tool: Path = VERDICTS) -> tuple[int, str]:
    """`(exit status, output)` of one census over one transcript and one gate. Both by path, so a
    plant can hand it a COPY with the defect planted in it and the fixtures are never written."""
    p = subprocess.run([sys.executable, str(tool), str(talk), str(gate)],
                       capture_output=True, text=True, cwd=ROOT)
    return p.returncode, p.stdout + p.stderr


def stage_row(out: str, n: int) -> str:
    """The census's one line for stage `n`, or `""`. `arm()` searches INSIDE it when a stage is
    named, because the claim is `stage 2's OWN row reads 24` -- and counting the padding spaces of a
    `{:<34}` field is a transcription of the LAYOUT, not of the claim."""
    return next((ln for ln in out.splitlines() if ln.startswith(f"  {n}  ")), "")


def arm(name: str, want_rc: int, want: str, talk: Path, gate: Path, stage: int | None = None,
        legacy_rc: int = 0, legacy_says: str | None = None, legacy_lacks: str | None = None) -> None:
    """One arm, scored TWICE: against the census as it now stands, and against the FROZEN PRE-FIX one.
    The second score is what makes the first a plant. `legacy_rc` is the status the pre-fix census must
    return; `legacy_lacks` is a claim it must NOT have printed anywhere in its output (that is what
    BLIND means here -- not an exit code); `legacy_says` is a claim it MUST have printed, for the one
    defect it noticed but explained wrongly."""
    rc, out = census(talk, gate)
    hay = stage_row(out, stage) if stage is not None else out
    seen = rc == want_rc and want in hay
    lrc, lout = census(talk, gate, LEGACY)
    blind = (lrc == legacy_rc
             and (legacy_says is None or legacy_says in lout)
             and (legacy_lacks is None or legacy_lacks not in lout))
    results.extend([seen, blind])
    print(f"  {'OK  ' if seen else 'FAIL'} {name:<50} rc={rc} (want {want_rc})")
    for ln in out.splitlines():
        if want in ln:
            print(f"         {ln}")
    if not seen:
        print(f"         *** expected {want!r} in "
              f"{'stage %d row: ' % stage if stage is not None else 'the output: '}{hay!r}")
    note = "" if legacy_says is None and legacy_lacks is None else \
        f"  [{'says ' + legacy_says if legacy_says else ''}{'; ' if legacy_says and legacy_lacks else ''}" \
        f"{'never says ' + legacy_lacks if legacy_lacks else ''}]"
    print(f"  {'OK  ' if blind else 'FAIL'} {'  the PRE-FIX census, same input' + note:<50} "
          f"rc={lrc} (want {legacy_rc})")
    if not blind:
        print("         *** pre-fix output: " + " | ".join(l for l in lout.splitlines() if "FAIL" in l))


def planted(frozen: Path, name: str, mutate) -> Path:
    """A COPY of a fixture with `mutate` applied. The write-back is asserted, never trusted."""
    tmp = Path(tempfile.mkdtemp(prefix="stage8-")) / name
    shutil.copy(frozen, tmp)
    before = tmp.read_text()
    after = mutate(before)
    assert after != before, f"the plant changed nothing: {name}"
    tmp.write_text(after)
    return tmp


def legacy_blocks(text: str) -> dict[int, list[str]]:
    """`blocks()` AS IT WAS at 2026-10-19T04:24Z, transcribed so the fix is falsifiable forever
    without a `git show` that a future rebase could rewrite. It re-opened on ANY header-shaped line
    and RESET the list, so a stage printing its own banner inside its own body lost everything above
    it. MEASURED on the live artifact: stage 6 kept 153 of its 156 body lines."""
    out: dict[int, list[str]] = {}
    for ln in text.splitlines():
        if m := VERDICTS_MODULE.HEADER.match(ln):
            out[int(m.group(1))] = []
        elif out:
            out[max(out)] += [ln]
    return out


def _load() -> object:
    spec = importlib.util.spec_from_file_location("e2estage8_verdicts", VERDICTS)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


VERDICTS_MODULE = _load()

results: list[bool] = []


def no_loss(text: str) -> bool:
    """EVERY LINE FROM THE FIRST BANNER ON IS ACCOUNTED FOR EXACTLY ONCE: either inside one stage's
    body, or as a stage's FIRST banner. A re-open banner is BOTH -- it is a body line of the stage
    that printed it -- so it is counted once, as the body line it is. A silently dropped line, which
    is the whole defect, makes this false."""
    bodies, banners = VERDICTS_MODULE.blocks(text)
    lines = text.splitlines()
    first = min(hs[0][0] for hs in banners.values())
    return sum(len(b) for b in bodies.values()) + len(banners) == len(lines) - first + 1


def main() -> int:
    print("PLANT AND DISARM -- the stage census on a frozen fixture")
    talk0, gate0 = FIX_TALK.read_text(), FIX_GATE.read_text()

    # --- THE CONTROL. Every arm below is scored against THIS, so it has to be green first: a fixture
    # already red would score a plant that planted nothing as a success.
    arm("CONTROL frozen fixture, nothing planted", 0, "census FOUND 3 stage call site(s)",
        FIX_TALK, FIX_GATE)
    results.append(no_loss(talk0))
    print(f"  {'OK  ' if results[-1] else 'FAIL'} {'CONTROL every line accounted for exactly once':<50}")

    # --- PLANT 1, THE RE-OPEN. The banner goes BETWEEN stage 2's countable row and its verdict, which
    # is where the old shape did its damage. **MEASURED 2026-10-19T04:28Z: THE PRE-FIX CENSUS IS NOT
    # BLIND TO THIS ONE, IT IS WRONG ABOUT IT** -- it exits 1 with `no denominator counted`, because
    # the reset destroyed the very row the stage printed. The defect did not merely escape the old
    # census, it made the old census accuse the port of a stage 2 that DID print its denominator. The
    # new shape must (a) go red on the re-open, (b) STILL COUNT 24, and (c) never blame the stage.
    reopened = planted(FIX_TALK, "reopen.out", lambda t: t.replace(
        "bend: 24 rows\n", "bend: 24 rows\n== 2/3 THE LANE RE-PRINTS ITS OWN BANNER\n"))
    arm("PLANT a stage's own body re-opens its banner", 1,
        "RE-OPEN    stage 2 was ALREADY OPEN", reopened, FIX_GATE,
        legacy_rc=1, legacy_says="no denominator counted", legacy_lacks="RE-OPEN")
    arm("PLANT ...and its DENOMINATOR is still counted", 1,
        "DENOMINATOR   24", reopened, FIX_GATE, stage=2, legacy_rc=1)
    old, new = legacy_blocks(reopened.read_text()), VERDICTS_MODULE.blocks(reopened.read_text())[0]
    old_d, new_d = VERDICTS_MODULE.denominator(2, old[2]), VERDICTS_MODULE.denominator(2, new[2])
    trunc = old_d is None and new_d == 24 and len(old[2]) < len(new[2])
    results.append(trunc)
    print(f"  {'OK  ' if trunc else 'FAIL'} {'PLANT ...legacy drops the row, new keeps it':<50} "
          f"legacy denominator={old_d} over {len(old[2])} line(s); "
          f"new denominator={new_d} over {len(new[2])} line(s)")
    results.append(no_loss(reopened.read_text()))
    print(f"  {'OK  ' if results[-1] else 'FAIL'} {'PLANT ...no line lost to the re-open':<50}")

    # --- PLANT 2, THE DECLARED DENOMINATOR AGAINST THE POPULATION. The gate emits three stages and
    # writes `/2` on one of them; `census FOUND` counts the call sites and does not care what they say.
    # MEASURED 2026-10-19T04:28Z: the pre-fix census exits 0 on this input.
    lying = planted(FIX_GATE, "lying.py",
                    lambda t: t.replace('say("== 2/3 port', 'say("== 2/2 port'))
    arm("PLANT the gate's banner says /2, the gate emits 3", 1,
        "the gate's own banner says `== 2/2` and the gate emits 3 stage(s)", FIX_TALK, lying,
        legacy_lacks="banner says")

    # --- PLANT 3, THE SAME LINE READ TWICE. The gate says 3, the artifact says 5, and the gate's own
    # population is not consulted -- this is the disagreement the old file could not see at all.
    # MEASURED 2026-10-19T04:28Z: the pre-fix census exits 0 on this input too.
    skewed = planted(FIX_TALK, "skewed.out", lambda t: t.replace("== 3/3 gate", "== 3/5 gate"))
    arm("PLANT the transcript prints /5 where the gate says /3", 1,
        "the gate SAYS its denominator is 3 and this transcript PRINTED 5", skewed, FIX_GATE,
        legacy_lacks="PRINTED")

    # --- NEGATIVE 4, ON THE RE-OPEN. One space, at the front: same digits, same slash, same text --
    # off column 0, which is the only thing `HEADER` anchors. It must NOT be a banner and must NOT
    # move the verdict, or the detector is "any line mentioning a stage number".
    indented = planted(FIX_TALK, "indented.out", lambda t: t.replace(
        "bend: 24 rows\n", "bend: 24 rows\n == 2/3 indented, so not a banner\n"))
    arm("NEGATIVE a banner-shaped line one space off column 0", 0,
        "DENOMINATOR   24", indented, FIX_GATE, stage=2)

    # --- NEGATIVE 6, THE OTHER END OF THE SAME ANCHOR. `== 2/3` at column 0 with no space after the
    # denominator is not a banner either, and the re-open must not fire on it.
    nospace = planted(FIX_TALK, "nospace.out", lambda t: t.replace(
        "bend: 24 rows\n", "bend: 24 rows\n== 2/3no space after the denominator\n"))
    arm("NEGATIVE `== 2/3` with no space after the denominator", 0,
        "DENOMINATOR   24", nospace, FIX_GATE, stage=2)

    # --- NEGATIVE 7, ON THE DENOMINATOR. A reworded PROSE row changes the input and must not change
    # the verdict; a census that fails on any edit is a change-detector, and those are harmful.
    reworded = planted(FIX_GATE, "reworded.py",
                       lambda t: t.replace("  2  port (pure bend, no GPU)",
                                           "  2  port (the pure-bend lane)"))
    arm("NEGATIVE a reworded PROSE row", 0, "census FOUND 3 stage call site(s)", FIX_TALK, reworded)

    for talk in (reopened, indented, nospace, skewed):
        results.append(no_loss(talk.read_text()))
    print(f"  {'OK  ' if all(results[-4:]) else 'FAIL'} {'NEGATIVE no line lost on any planted variant':<50}")

    # --- AND THE FIXTURES THEMSELVES ARE UNPLANTED: the arms above must be reversible edits, or a
    # green control proves that the fixture was already green for a reason no arm removed.
    results.append(FIX_TALK.read_text() == talk0 and FIX_GATE.read_text() == gate0)
    print(f"  {'OK  ' if results[-1] else 'FAIL'} {'CONTROL the frozen fixtures were never written':<50}")

    print(f"--- {sum(results)} of {len(results)} arm(s) behaved as required")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())