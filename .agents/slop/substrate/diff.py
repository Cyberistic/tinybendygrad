#!/usr/bin/env python3
"""Per-file diff of the shell oracle and the Python port: verdict, denominators, exit status,
and the WHOLE output stream, on every input class, plus two plants that must DISAGREE.

    usage: .venv/bin/python .agents/slop/substrate/diff.py [--sets smoke route pop] [--plants]

A GATE IS A TEXT, NOT AN EXIT STATUS. So the comparison is byte identity of STDOUT plus equality
of the exit status, and the artifacts are kept under `.agents/slop/substrate/artifacts/<set>/`:
a gate whose report is missing its last line has lost reproducibility without saying so.

**ONE NORMALISATION, AND IT IS THE PROGRAM'S OWN NAME.** The refusal's usage line prints `$0` --
the path the driver was invoked as -- because that is what the shell did. Comparing `zsh <oracle>`
against `checks/substrate.py` would fail on the NAME, not on a verdict, so the self-path token is
replaced by `<SELF>` on both sides and nothing else is touched. STDERR IS NOT COMPARED: the port
reports a killed-or-timed-out instrument on its own channel, which the shell could not do at all,
and mixing that into the comparison would fail every run for a difference the port was asked to
make. It is reported beside the verdict instead.

**ONE `bend` PROCESS AT A TIME, ALWAYS.** Two of them at once took this machine's memory to zero
on 2026-10-05 (`PEAKRSS.md`: 1,152 MB + 1,108 MB). Every run here is sequential and every one of
them goes through `checks/bounded.py`.

EXCLUDED: `.agents/slop/differverdict/root/` is a FULL COPY OF THE REPOSITORY made by a live unit
(75 `.sh` under its own `.agents/slop/` alone), so any `find` that walks it reports hundreds of
files that are not this project's. Nothing in this directory walks it; `walk.sh` and `find` calls
are pruned, and the input sets are named explicitly rather than discovered.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ART = ROOT / ".agents/slop/substrate/artifacts"
ORACLE = ".agents/slop/substrate/oracle-check.sh"
PORT = "checks/substrate.py"
PY = ".venv/bin/python"
ENV = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"SUBSTRATE_REPO": str(ROOT)}
SELF = (f"zsh {ORACLE}", PORT, "<SELF>")
FX = ".agents/slop/substrate/fixtures"

# EVERY INPUT CLASS THE ROUTER CLAIMS, ONE FILE EACH. A diff over a class that has no fixture is a
# diff over a class nobody looked at: MISSING, EMPTY, and NO INSTRUMENT are three verdicts that are
# not `WARM` and not `COLD`, and each of them once shipped as a silent green.
SMOKE = [
    f"{FX}/tiny.bend",                      # a WARM `.bend`
    f"{FX}/broken.bend",                    # a COLD `.bend` with a real message
    f"{FX}/empty.bend",                     # EMPTY, and `bend --check-only` answers ALL PROOFS CHECK
    f"{FX}/bare.txt",                       # NO INSTRUMENT: a class with no instrument
    f"{FX}/no-such-file.bend",              # MISSING
    "tinybendygrad/runtime/dtype.c",        # the `.c` route
    "tinybendygrad/runtime/dtype.js",       # the node route
]
# EVERY ROUTE, PLUS THE THREE `.bend` FILES THAT DECIDE WHETHER THE CEILING CHANGES A VERDICT:
# `renderer/nir.bend` peaked at 1,152 MB and `sz.bend` at 1,108 MB -- BOTH KILLED at the census's
# 1 GB ceiling -- so at the port's 2,048 MB they are the two rows that justify the number.
ROUTE = [
    "tinybendygrad/device.bend",
    "tinybendygrad/helpers.bend",
    "tinybendygrad/runtime/dtype.bend",
    "tinybendygrad/sz.bend",
    "tinybendygrad/renderer/nir.bend",
    "tinybendygrad/uop/validate.bend",      # 41 of the 46 UNRESOLVED sites are here
    "tinybendygrad/runtime/dtype.c",
    "tinybendygrad/runtime/dtype.js",
    f"{FX}/bare.txt",
]
POP = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "tinybendygrad").rglob("*")
             if p.is_file())
# `-n` IS A DIFFERENT GATE, not a quieter one: it judges nothing, and a `NO INSTRUMENT` file is
# NOT skipped by it, so the two together are the only way to see that `-n` suppresses verdicts and
# not verdicts-plus-instruments.
NAMES = ([f"{FX}/tiny.bend", f"{FX}/broken.bend", f"{FX}/bare.txt",
          "tinybendygrad/runtime/dtype.c"], ["-n"])
# ONE ARGUMENT CONTAINING AN EMBEDDED NEWLINE. The shell feeds HALF 2 through `print -l -- "$@"`,
# which SPLITS such an argument into two paths, while HALF 1 iterates the raw arguments and sees
# one. So a single argument is judged as ONE absent file and name-checked as TWO real ones, and
# `MISSING` sits beside two `NAMES` lines. That asymmetry is the shell's, and a diff never saw it
# until this set existed.
NEWLINE = (["tinybendygrad/device.bend\ntinybendygrad/helpers.bend"], [])
# ZERO ARGUMENTS. The refusal, diffed through the same harness as everything else, because a
# refusal that is only ever checked by hand is a refusal nobody checked.
REFUSED = ([], [])
SETS = {"smoke": (SMOKE, []), "names": NAMES, "newline": NEWLINE, "route": (ROUTE, []),
        "refused": REFUSED, "pop": (POP, [])}


def self_norm(text: str) -> str:
    """`$0` is the invocation path BY DESIGN in the refusal's usage lines, so the one token that
    cannot agree between a zsh oracle and a python port is the program's own name."""
    for token in SELF:
        text = text.replace(token, "<SELF>")
    return text


def run(cmd: list[str], dest: Path, env: dict | None = None) -> int:
    """ONE FILE, ONE WRITE: stdout, stderr and the exit status are three separate artifacts,
    because `$?` after a pipe is the LAST command's status and this project has measured a gate
    printing ORACLE DRIFT while reporting exit 0."""
    with (dest.with_suffix(".out")).open("wb") as out, \
         (dest.with_suffix(".err")).open("wb") as err:
        rc = subprocess.run(cmd, cwd=ROOT, env=env or ENV, stdout=out, stderr=err).returncode
    (dest.with_suffix(".rc")).write_text(f"{rc}\n")
    return rc


def demanded(ok: bool, expected: bool, name: str) -> bool:
    """`True` when the result is the one this harness DEMANDED of it, and it says so out loud.

    Both halves matter. The first version printed the expectation in the LABEL only, so the
    `refused` set agreeing and the ceiling plant disagreeing printed the same bare word `AGREE`
    vs `DISAGREE` and the reader had to know which was which -- and `plants()` then folded its
    result into the same boolean the sets used, which is why a run in which every plant had just
    fired printed `VERDICT: DISAGREEMENT`. A plant that disagrees is the gate WORKING.
    """
    print(f"  {name:<16} {'OK' if ok == expected else 'UNEXPECTED -- the harness is broken'} "
          f"(got {ok}, wanted {expected})")
    return ok == expected


def verdict_lines(text: str) -> list[str]:
    """THE VERDICT AND THE DENOMINATOR, on their own, so a failure names WHICH of them moved.
    A diff of two whole streams that differ on line 400 tells a reader nothing about line 2."""
    keys = ("MISSING", "EMPTY", "WARM", "COLD", "NO INSTRUMENT", "SKIP-VERDICT",
            "ROUTE", "PROVENANCE", "PORT ALARM", "DENOMINATOR", "TOTALS", "BAD",
            "NAMES", "SUBSTRATE", "NAMES CLEAN")
    return [ln for ln in text.splitlines() if ln.startswith(keys)]


def stamp(paths: list[str]) -> dict[str, tuple[int, int] | None]:
    """`(size, mtime_ns)` per input, or `None` if absent.

    **THE TREE IS EDITED BY OTHER UNITS WHILE THIS RUNS, AND A DIFF THAT CANNOT SEE IT REPORTS A
    DISAGREEMENT THAT IS NOT ONE.** MEASURED 2026-10-05 on the whole-tree run: the oracle finished
    at 15:27 and the port at 15:30, and in that window a live unit created and then deleted
    `tinybendygrad/runtime/support/rdma/bnxtdev.bend.sweep`. Both drivers were handed the IDENTICAL
    argv -- the population is enumerated once, before either -- so the disagreement was
    `PORT ALARM 1` vs `2` on a file neither of them had anything to do with. A harness that
    reports that as a port bug is measuring the other units' clock. **IT HAS SINCE FIRED TWICE**,
    the second time on `tinybendygrad/mixin/elementwise.bend`, which grew 83,515 -> 85,060 bytes
    mid-run, so this is not a one-off.

    So the population is stamped before and after BOTH runs, and a change is reported as its own
    verdict, `CONCURRENT-EDIT`, which is neither agreement nor disagreement and is the one thing
    this harness must never resolve in the port's favour.
    """
    out = {}
    for p in paths:
        try:
            st = os.stat(p)
            out[p] = (st.st_size, st.st_mtime_ns)
        except OSError:
            out[p] = None
    return out


def compare(name: str, files: list[str], label: str, extra: list[str] = (),
            port_extra: list[str] = ()) -> bool:
    """`extra` reaches BOTH drivers; `port_extra` reaches the PORT only. The split exists because
    a plant of the port must not also plant the oracle -- and the first version of this harness did
    exactly that, passing `--mb 1` to a script that has no `--mb`, so the ORACLE answered
    `MISSING --mb` / `MISSING 1` and the diff passed for the wrong reason. It passed, but it was
    comparing two different arguments. (It did buy a control for free: the oracle treats an
    unknown `-x` as a FILENAME, which is the rule `split_leading` reproduces.)"""
    dest = ART / name
    dest.mkdir(parents=True, exist_ok=True)
    # ONE argv, PASSED AS ONE argv. `xargs` and `for f in $(...)` would re-split the embedded
    # newline in the `newline` set and destroy the very thing that set measures.
    # SEQUENTIAL. Never `&`, never `xargs -P`: two `bend` processes is the crash.
    before = stamp(files)
    rc_o = run(["zsh", ORACLE, *extra, *files], dest / "oracle")
    rc_p = run([PY, PORT, *extra, *port_extra, *files], dest / "python")
    after = stamp(files)
    moved = [f"{p} {before[p]} -> {after[p]}" for p in files if before[p] != after[p]]
    o = self_norm((dest / "oracle.out").read_text(errors="replace"))
    p = self_norm((dest / "python.out").read_text(errors="replace"))
    (dest / "oracle.norm").write_text(o)
    (dest / "python.norm").write_text(p)
    vo, vp = verdict_lines(o), verdict_lines(p)
    movedv = [f"  ORACLE only: {ln}" for ln in vo if ln not in vp] \
        + [f"  PORT   only: {ln}" for ln in vp if ln not in vo]
    same_rc = rc_o == rc_p
    same_txt = o == p
    # A MOVED FILE MAKES THE COMPARISON VACUOUS, so it is refused rather than resolved. TWO
    # IDENTICAL FAILURES COMPARE EQUAL, and here two DIFFERENT POPULATIONS compare unequal: both
    # shapes are ways of reading a verdict off a run that did not measure what it claims to.
    if moved:
        print(f"CONCURRENT-EDIT  {name:<22} {len(moved)} input(s) changed WHILE the two drivers "
              f"ran -- this comparison is VOID, not a disagreement:")
        for m in moved[:6]:
            print(f"    {m}")
        print("           re-run. Do NOT read this as the port being wrong: both drivers were "
              "handed the same argv and saw a different tree.")
        (dest / "diff.out").write_text("\n".join([
            f"label={label}",
            f"VOID -- the population changed under the two runs: {len(moved)} file(s)",
            *moved]) + "\n")
        return False
    # A 0-BYTE SIDE IS A FAILURE, NOT A PASS. `cmp -s` on two empty files succeeds, and a run
    # killed mid-write produces exactly that -- so the shapes are asserted, not just compared.
    # (This harness was bitten by the same shape one level down: the plant-literal mutant printed
    # ZERO BYTES because its ORACLE PIN could not resolve from `artifacts/mutant/`, and a bare
    # `o != p` called that a passing plant.)
    # THE `refused` SET HAS AN EMPTY STDOUT ON BOTH SIDES -- a refusal is four lines, so this shape
    # guard was flagging the ONE set whose whole point is a short output, and `ok` came back False
    # for a set whose stdout is byte-identical. So the guard is scoped to what it is for: a
    # VERDICT-BEARING stream with no verdict line in it. That is the 0-row failure shape, and it
    # is invisible to a byte compare precisely because two empty files are equal.
    shapes = [f"EMPTY {dest.name}/{side}.out" for side in ("oracle", "python")
              if (dest / f"{side}.out").stat().st_size == 0 and files] \
        + [f"NO VERDICT LINE {side}" for side, v in (("oracle", vo), ("port", vp)) if not v and files]
    body = [f"label={label}", f"inputs={len(files)}", f"exit=oracle:{rc_o} port:{rc_p}",
            f"stdout={'IDENTICAL' if same_txt else 'DIFFERS'} "
            f"({len(o.splitlines())} lines vs {len(p.splitlines())})",
            f"verdict+denominator lines={'IDENTICAL' if vo == vp else 'DIFFER'} "
            f"({len(vo)} each)",
            *(f"SHAPE: {s}" for s in shapes),
            *movedv]
    if not same_txt:
        body.append("--- STREAM DIFF (first 60 lines) ---")
        q = subprocess.run(["diff", str(dest / "oracle.norm"), str(dest / "python.norm")],
                           capture_output=True, text=True)
        body += q.stdout.splitlines()[:60]
    (dest / "diff.out").write_text("\n".join(body) + "\n")
    ok = same_rc and same_txt and vo == vp and not shapes
    # THE STREAM, not the one-word summary. `AGREE` was printed for the `refused` set while the
    # two drivers' exit statuses were 3 and 3 and stdout was byte-identical, because `ok` was
    # computed from `same_txt` -- and then `demanded()` called it UNEXPECTED against its own
    # report. `stdout=IDENTICAL` with `exit=oracle:3 port:3` beside it is the fact; the word is
    # the interpretation. Both are printed, and the interpretation names which of the three
    # sub-checks moved when one did.
    print(f"{'AGREE  ' if ok else 'DISAGREE'}  {name:<22} {body[2]}  {body[3]}")
    if not ok:
        print("           moved: " + "; ".join(
            f"{k}={'ok' if v else 'MOVED'}" for k, v in
            (("exit", same_rc), ("stdout", same_txt), ("verdicts", vo == vp),
             ("shapes", not shapes))) + ("" if not shapes else f"  {[s for s in shapes]}"))
    return ok


def input_plants() -> bool:
    """TWO PLANTS ON THE FIXTURES THEMSELVES, and they are here because the first two plants only
    exercise the PORT'S OWN CODE PATH -- they cannot tell whether the fixtures still MEAN what the
    set claims they mean.

    PLANT 3, THE COLD FIXTURE GOES GREEN. `fixtures/broken.bend` is `def f(:`, a syntax error. If
    it ever stops being one, `smoke` loses its only COLD row and the set passes while judging
    nothing -- the "a gate that measures nothing must not report agreement" failure, one level
    below the empty-argument refusal.

    PLANT 4, THE EMPTY FIXTURE IS THE TRAP THIS GATE EXISTS FOR. `--check-only` answers
    `ALL PROOFS CHECK` for a 0-byte file, so the ONLY thing standing between an empty file and a
    green run is the EMPTY verdict. Making the empty fixture non-empty must move the output, and
    making it empty again must move it back -- a paired arm/disarm in the strict sense, with both
    directions asserted.
    """
    # **THESE PLANTS COMPARE AGAINST THE BASELINE, NOT AGAINST THE ORACLE.** The first version
    # demanded they DISAGREE with the oracle and both answered AGREE -- correctly, and for a
    # reason worth stating: planting a defect in a fixture makes the ORACLE report it too, so
    # oracle-vs-port is still identical. A fixture plant answers a DIFFERENT question: "does the
    # set still MEASURE what it claims to measure". The test is that the set's own output MOVED,
    # which is why the baseline is compared to the planted run and the oracle is carried along
    # only to prove the two drivers still track each other.
    broken, empty = ROOT / f"{FX}/broken.bend", ROOT / f"{FX}/empty.bend"
    good, hollow = b"def f(:\n", b""
    base = (ART / "smoke" / "oracle.out").read_text(errors="replace")
    base_port = (ART / "smoke" / "python.out").read_text(errors="replace")
    ok = True
    for label, body, path in (("broken.bend green", b"def f(x: U32) -> U32:\n  return x\n", broken),
                              ("empty.bend non-empty", good, empty)):
        path.write_bytes(body)
        compare(f"plant-{path.stem}", SMOKE, f"plant: {label}")
        after = (ART / f"plant-{path.stem}" / "oracle.out").read_text(errors="replace")
        after_p = (ART / f"plant-{path.stem}" / "python.out").read_text(errors="replace")
        ok &= demanded(after != base and after_p != base_port, True, f"{path.stem} moved")
    broken.write_bytes(good)
    empty.write_bytes(hollow)
    print(f"DISARMED  fixtures restored: broken={broken.read_bytes()!r} empty={len(empty.read_bytes())}B")
    ok &= demanded(compare("disarmed-smoke", SMOKE, "disarm: fixtures restored"), True, "smoke")
    return ok


def plants() -> bool:
    """TWO PLANTS, BOTH OF WHICH MUST DISAGREE, chosen for what they would catch if they were
    broken. A plant that agrees is a plant that is not load-bearing.

    PLANT 1, THE BOUND. `--mb 1` caps every instrument at 1 MB, which kills each `bend` run on
    memory. The oracle has no memory bound at all, so it says WARM and the port says COLD. This is
    THE failure mode this port is most able to commit: a ceiling set for safety that silently
    changes verdicts instead of stopping a runaway. It must be caught.

    PLANT 2, THE LITERAL. The `ALL PROOFS CHECK` comparison with ONE trailing space added, in a
    copy of the port. Every WARM file becomes COLD, and the port's verdict line then reads
    `:: ALL PROOFS CHECK` -- a COLD that NAMES THE VERDICT IT FAILED TO MATCH, which is the shape
    of this class of bug. The exit status moves from 0 to 1, so a gate that diffed only exit codes
    would see it, but a gate that diffed only "did both fail" would not: on a cold file both sides
    exit 1 and agree perfectly.

    Then DISARM: the copy is deleted and the real port is re-diffed on the same input, which must
    AGREE. A plant that is never disarmed leaves the tree holding a broken gate."""
    # `sz.bend` AND NOT `device.bend`. The first version of this plant used `device.bend` with a
    # 1 MB ceiling and the two sides AGREED -- because `device.bend` peaks at 0 MB, so no ceiling
    # above zero can ever kill it, and a plant that cannot fail proves nothing. `sz.bend` peaks at
    # 1,468 MB (measured today, `runs/peakrss.json` says 1,108 at the census), so a 1 GB ceiling
    # kills it and the disagreement is real.
    warm, heavy = ["tinybendygrad/device.bend"], ["tinybendygrad/sz.bend"]
    p1 = demanded(compare("plant-bound", heavy, "plant: ceiling below the population's max",
                        port_extra=["--mb", "1"]), False, "plant-bound")
    print("           (`device.bend` at a 1 MB ceiling CANNOT disagree: it peaks at 0 MB, so a "
          "ceiling plant must be set against a file that actually allocates)")
    # PLANT 2 NEEDS THE ORACLE ON THE SAME INPUT, and must not depend on the `disarmed` run
    # having happened first -- so it asks for its own.
    # NOTE THE INVERTED WORD. `run_mutant` answers "did the two DISAGREE", so its True is the plant
    # WORKING, and `demanded(..., False)` was scoring a success as a failure. It cost one
    # confusing run and it is exactly the shape `checks/disarm.sh` warns about -- a paired control
    # whose off-switch is never exercised reads as broken in one direction and as working in the
    # other. `compare` answers "did the two AGREE", so it is demanded True; `run_mutant` answers
    # the other question, so it is demanded True TOO, and the two helpers do not share a polarity.
    p2 = demanded(run_mutant(warm), True, "plant-literal")
    print(f"DISARMED  the mutant copy is deleted: {not (ART / 'mutant').exists()}")
    p3 = demanded(compare("disarmed", heavy + warm, "disarm: the real port, same inputs"),
                  True, "disarmed")
    p4 = input_plants()          # FIXTURE-side, same polarity question, same reporting
    return p1 and p2 and p3 and p4   # reported by main(); see the note there


def run_mutant(files: list[str]) -> bool:
    mutant = ART / "mutant" / "substrate.py"
    mutant.parent.mkdir(parents=True, exist_ok=True)
    src = (ROOT / PORT).read_text()
    mutated = src.replace('first == "ALL PROOFS CHECK"', 'first == "ALL PROOFS CHECK "')
    assert mutated != src and mutated.count('ALL PROOFS CHECK "') == 1, "plant did not apply"
    mutant.write_text(mutated)
    dest = ART / "plant-literal"
    dest.mkdir(parents=True, exist_ok=True)
    rc_o = run(["zsh", ORACLE, *files], dest / "oracle")
    # **TWO IDENTICAL FAILURES COMPARE DIFFERENT ONLY BY ACCIDENT.** The mutant lives at
    # `artifacts/mutant/substrate.py`, so `ROOT = parents[1]` is `artifacts/`, the oracle pin
    # resolves to nothing, and the mutant refuses with `ORACLE DRIFT` on EVERY input -- including
    # the ones the plant is about. That is exit 3 and an empty stdout, which differs from the
    # oracle, so `o != p` said the plant fired while it had proved only that the PIN works.
    # The pin is passed explicitly here, and the verdict is read from the artifacts: a plant that
    # cannot be shown to have changed the thing it names is not load-bearing.
    env = dict(ENV, SUBSTRATE_ROOT=str(ROOT))
    rc_p = run([PY, str(mutant), *files], dest / "python", env)
    shutil.rmtree(mutant.parent, ignore_errors=True)
    o = self_norm((dest / "oracle.out").read_text(errors="replace"))
    p = self_norm((dest / "python.out").read_text(errors="replace"))
    vo, vp = verdict_lines(o), verdict_lines(p)
    # A PLANT IS SUPPOSED TO CHANGE THE EXIT STATUS, so requiring the two to AGREE here would be the
    # "two identical failures" guard applied to the wrong side of the comparison. What the plant
    # must show is that the port's verdict lines CARRY ITS OWN SIGNATURE -- a WARM line became
    # COLD -- and not merely that some byte moved.
    named = any("COLD" in ln and "WARM" not in ln for ln in vp if ln not in vo)
    ok = o != p and named
    (dest / "plant.txt").write_text("\n".join([
        "label=plant: one trailing space in the WARM literal",
        f"exit=oracle:{rc_o} port:{rc_p} (equal: {rc_o == rc_p})",
        f"the plant's OWN signature present -- a WARM line became COLD: {named}",
        f"stdout={'DIFFERS, and for the stated reason' if ok else 'PLANT NOT LOAD-BEARING'}",
        f"verdict lines={'DIFFER' if vo != vp else 'IDENTICAL -- THE PLANT IS NOT LOAD-BEARING'}",
        # TWO IDENTICAL FAILURES COMPARE EQUAL. Were the port to refuse on EVERY input (which it
        # did, when the mutant could not resolve the oracle pin) BOTH sides would exit non-zero,
        # `cmp` would call them identical, and a diff reading only the exit status would report a
        # passing plant. Recorded so the next reader knows why exit equality is printed here and
        # is not the test.
        "note: exit equality is printed but is NOT the test -- two failures compare equal.",
        *(f"  ORACLE only: {ln}" for ln in vo if ln not in vp),
        *(f"  PORT   only: {ln}" for ln in vp if ln not in vo)]) + "\n")
    print(f"{'DISAGREE' if ok else 'AGREE  '}  {'plant-literal':<22} "
          f"exit=oracle:{rc_o} port:{rc_p}  "
          f"stdout={'DIFFERS (as it must)' if ok else 'IDENTICAL -- PLANT NOT LOAD-BEARING'}")
    return ok


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sets", nargs="*", default=["smoke", "names", "newline", "refused", "route"],
                    choices=sorted(SETS), help="which input sets to diff")
    ap.add_argument("--plants", action="store_true", help="also run the two plants and disarm")
    a = ap.parse_args()
    shutil.rmtree(ART, ignore_errors=True)
    ART.mkdir(parents=True, exist_ok=True)
    print(f"population: tinybendygrad has {len(POP)} files on disk "
          f"({sum(1 for f in POP if f.endswith('.bend'))} .bend)")
    if a.plants and "smoke" not in a.sets:
        # `plants()` -> `input_plants()` compares each planted run against the `smoke` ARTIFACT, so
        # `smoke` has to exist. Without this the fixture plants read a missing file and the
        # comparison `after != base` is True for the wrong reason -- the same 0-byte-compares-equal
        # trap, one level up.
        raise SystemExit("--plants needs `smoke` in --sets (it is the fixture plants' baseline)")
    results = [(n, demanded(compare(n, SETS[n][0], f"set {n}", extra=SETS[n][1]),
                            True, f"set {n}")) for n in a.sets]
    ok = all(ok for _, ok in results)
    print(f"VERDICT: {sum(ok for _, ok in results)} of {len(results)} set(s) AGREE with the "
          f"oracle" + ("" if ok else " -- SEE diff.out"))
    if a.plants:
        # A PLANT'S SUCCESS IS A DISAGREEMENT, so `plants()` reports its own expectation against
        # each result and must NOT be folded into the sets' `ok`. The first version did fold it in
        # and printed `VERDICT: DISAGREEMENT` on a run where every plant had just done its job --
        # the report said the gate was broken at the moment the gate was proven load-bearing.
        # IT IS STILL AN EXIT STATUS THOUGH: a plant that did NOT fire leaves the harness broken,
        # and a run that ends `AGREE` with a dead plant is not a pass.
        if not plants():
            print("VERDICT: A PLANT DID NOT FIRE -- the diff is not load-bearing")
            return 1
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())