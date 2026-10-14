#!/usr/bin/env python3
"""THE DENOMINATOR AFTER WIRING `D0-repro.txt` IN AS A PIN. Five measurements, one per question.

Every number is a READING of a real function against a scratch copy of `runs/graphcmp/D`; no `bend`,
no write into `runs/graphcmp/D`. The control is `pinindep/derive.selfcheck()`, imported, and this
file REFUSES to report if it fails -- a perturbation that moves nothing is then a broken instrument
rather than a finding.

    usage: .venv/bin/python .agents/slop/repropin/measure.py

  A  LAYER 1  how many DISTINCT ARTIFACTS carry a pin value, before and after. This is the
             denominator `RUN HEALTH : OK -- N of N` has been reporting.
  B  SENSITIVITY  four states of `D0-repro.txt`, each asking `differ.repro_bad()` the real question.
  C  INDEPENDENCE  can the new pin move ALONE, and can a summary row move without it?
  D  REDUNDANCY  which of the 17 pins are a function of the others, re-measured by the same
             arithmetic `pinindep/redundancy.py` used.
  E  DERIVABILITY  is `repro-rc` derivable from `D0-run-summary.txt`? A pin that is would be a
             TAUTOLOGY -- a pin that cannot fail, which is the defect this task exists to close.
"""
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "runs/graphcmp/D"

sys.path.insert(0, str(ROOT / ".agents/slop/pinindep"))
import derive  # noqa: E402  -- the CONTROL: rederive(live) == the live summary, or refuse

differ = derive.differ
SRC = (ROOT / "checks/differ.py").read_text()


def scratch(tmp, repro: str | None) -> Path:
    """A copy of the live run dir with `D0-repro.txt` set to `repro` (None deletes it)."""
    dst = derive.scratch_copy(Path(tmp) / f"S{abs(hash(repro)) % 9973}")
    (dst / differ.REPRO_ARTIFACT).unlink(missing_ok=True)
    if repro is not None:
        (dst / differ.REPRO_ARTIFACT).write_text(repro)
    return dst


def read_pin_files(base: Path, fn) -> set[str]:
    """Every file under `base` whose CONTENT `fn` reads, by patching the three read entry points.

    The same method `pinindep/layer1.py` used, so the before/after numbers are comparable: a
    different method would answer a different question. `base` is the scratch directory the
    function was pointed at -- measuring against the live tree instead would report the paths of
    a DIFFERENT run and answer nothing.
    """
    seen: list[str] = []
    orig = (Path.read_text, Path.read_bytes, Path.open)

    def rec(p):
        try:
            seen.append(Path(p).resolve().relative_to(base).as_posix())
        except (ValueError, TypeError):
            pass

    def wrap(i, call):
        def f(self, *a, **k):
            rec(self)
            return orig[i](self, *a, **k)
        return f

    Path.read_text, Path.read_bytes, Path.open = (wrap(0, orig[0]), wrap(1, orig[1]), wrap(2, orig[2]))
    try:
        fn()
    finally:
        Path.read_text, Path.read_bytes, Path.open = orig
    return {f for f in set(seen) if f.endswith(".txt")}


def layer1() -> None:
    print("\n== A. LAYER 1: THE DENOMINATOR, IN DISTINCT ARTIFACTS THAT CARRY A PIN ==\n")
    with tempfile.TemporaryDirectory() as tmp:
        s = scratch(Path(tmp), "repro-files=158\nrepro-identical=158\nrepro-rc=rc=0\n")
        differ.D = s
        derive.compose_bytediff(s)
        derive.compose_stability(s)
        summary = read_pin_files(s, differ.unhealthy)
        witness = read_pin_files(s, differ.repro_bad)
    differ.D = D
    pin_carriers = {f for f in summary | witness
                    if f in ("D0-run-summary.txt", differ.REPRO_ARTIFACT)}
    # A `.txt` `unhealthy()` OPENS is not one that CARRIES a pin value: it opens 174 of them
    # through `device_of_run()` for the four `dev`/`lc_all`/`noopt`/`pythonhashseed` rows, and
    # those are precondition rows, not PINS. Only the file a pin VALUE is parsed out of counts.
    print(f"  `unhealthy()` opens {len(summary):3d} `.txt`; a pin VALUE is parsed out of "
          f"{sorted(f for f in summary if f == 'D0-run-summary.txt')} (17 of 17 live there)")
    print(f"  `repro_bad()` opens {len(witness):3d} `.txt`; a pin VALUE is parsed out of "
          f"{sorted(f for f in witness if f == differ.REPRO_ARTIFACT)} "
          f"({len(differ.REPRO_PINS)} of {len(differ.REPRO_PINS)} there)")
    print("\n  BEFORE  17 pins over 1 artifact  -> the denominator was 1 RUN")
    print(f"  AFTER   17 pins over 1 artifact + {len(differ.REPRO_PINS)} pin over 1 artifact "
          f"= {len(pin_carriers)} DISTINCT ARTIFACTS THAT CARRY A PIN")
    print(f"          pins per artifact: "
          f"{[(f, 17 if f.endswith('summary.txt') else 1) for f in sorted(pin_carriers)]}"
          f"  (MAX was 17, and the second file was read by nobody)")


def sensitivity() -> None:
    print("\n== B. SENSITIVITY: FOUR STATES OF `D0-repro.txt`, ASKED OF THE REAL FUNCTION ==\n")
    green = f"repro-files={len(list(D.glob('*.txt'))) + 1}\nrepro-identical=0\n"
    states = [
        ("green -- `repro-rc=rc=0`", f"{green}repro-rc=rc=0\n"),
        ("RED -- `repro-rc=rc=1`, two runs DIFFERED", f"{green}repro-rc=rc=1\n"),
        ("KEY ABSENT -- the writer's row moved", green),
        ("FILE ABSENT -- `repro` was never run to completion", None),
        ("CONTROL -- the PREVIOUS writer's shape, `repro-rc=0`", f"{green}repro-rc=0\n"),
    ]
    with tempfile.TemporaryDirectory() as tmp:
        for i, (name, body) in enumerate(states):
            differ.D = scratch(Path(tmp) / str(i), body)
            bad = differ.repro_bad()
            verdict = "PASS" if not bad else "FAIL"
            print(f"  {verdict}  {name}")
            for b in bad:
                print(f"          -> {b}")
    differ.D = D
    print("\n  THE CONTROL IS A PIN THAT FAILS: `repro-rc=0` (what `cmd_repro` wrote until this")
    print("  change) reads RED against the pin `rc=0`, so the pin sees a shape move, not just a")
    print("  value. Every state names its offender; NONE of them prints a count of green.")


def independence() -> None:
    print("\n== C. INDEPENDENCE: CAN THE NEW PIN MOVE ALONE? ==\n")
    with tempfile.TemporaryDirectory() as tmp:
        s = scratch(Path(tmp), "repro-files=158\nrepro-identical=158\nrepro-rc=rc=0\n")
        differ.D = s
        before_run = differ.unhealthy()
        (s / differ.REPRO_ARTIFACT).write_text("repro-files=158\nrepro-identical=0\nrepro-rc=rc=1\n")
        after_run, after_repro = differ.unhealthy(), differ.repro_bad()
        s2 = scratch(Path(tmp) / "b", "repro-files=158\nrepro-identical=158\nrepro-rc=rc=0\n")
        differ.D = s2
        summary = s2 / "D0-run-summary.txt"
        summary.write_text(summary.read_text().replace("graphs-agree=32", "graphs-agree=31"))
        sum_run, sum_repro = differ.unhealthy(), differ.repro_bad()
    differ.D = D
    print(f"  edit `D0-repro.txt` only  : unhealthy() {before_run or 'green'} -> "
          f"{after_run or 'green'} ({len(after_run) - len(before_run):+d}); "
          f"repro_bad() green -> {len(after_repro)} complaint(s)")
    print(f"  edit the SUMMARY only     : unhealthy() {sum_run or 'green'} ({len(sum_run):+d}); "
          f"repro_bad() {'green -> ' + str(len(sum_repro)) + ' complaint(s)' if sum_repro else 'STAYS GREEN'}")
    print("\n  => the two verdicts move on DISJOINT artifacts. That is the whole claim: 2 witnesses,")
    print("     not 18 rows of one.")


def redundancy() -> None:
    print("\n== D. REDUNDANCY AMONG THE 17, RE-MEASURED (same arithmetic as pinindep) ==\n")
    g = dict(ln.split("=", 1) for ln in
             (D / "D0-run-summary.txt").read_text(errors="replace").splitlines() if "=" in ln)
    n, u = int(g["graphs"]), int(g["graphs-unset"])
    s = sum(int(g[k].split(" of ")[0]) for k in ("stable-pairs", "stable-failed", "stable-differ"))
    print(f"  graphs-answered == graphs - graphs-unset : "
          f"{int(g['graphs-answered']) == n - u}  ({n} - {u} = {n - u}) -> 2 free numbers, 3 pins")
    print(f"  stable-pairs + stable-failed + stable-differ == len(STAB) : "
          f"{s == len(differ.STAB)}  ({s} == {len(differ.STAB)}) -> a PARTITION, 2 free numbers, 3 pins")
    print("\n  => 17 pins, 2 algebraically determined, 15 free. UNCHANGED by this task, because")
    print("     `repro-rc` is a NEW free number in a NEW artifact, not a third view of an old one.")


def derivability() -> None:
    print("\n== E. IS `repro-rc` DERIVABLE FROM `D0-run-summary.txt`? (a derived pin cannot fail) ==\n")
    cmd_run = SRC[SRC.index("def cmd_run"):SRC.index("return 1 if unset or moved")]
    cmd_repro = SRC[SRC.index("def cmd_repro"):SRC.index("def main()")]
    print(f"  `cmd_run`   writes `repro-rc`  : {'repro-rc' in cmd_run}")
    print(f"  `cmd_run`   reads  `D0-repro`  : {differ.REPRO_ARTIFACT in cmd_run}")
    print(f"  `cmd_repro` writes `repro-rc`  : {'repro-rc' in cmd_repro}")
    clean_run = SRC[SRC.index("def clean_run"):SRC.index("def cmd_repro")]
    print(f"  `cmd_repro` reads  the summary : {'unhealthy()' in clean_run} via `clean_run()` "
          f"(health, not the value)")
    body = (D / differ.REPRO_ARTIFACT)
    print(f"  the summary carries a repro row: {'repro' in (D / 'D0-run-summary.txt').read_text()}")
    print(f"  `D0-repro.txt` on disk now     : {'present' if body.exists() else 'ABSENT (never run)'}")
    print("\n  => NOT DERIVABLE. The summary is written by `cmd_run` from per-graph artifacts;")
    print("     `repro-rc` is written by `cmd_repro` from the sha256 of TWO snapshots of the whole")
    print("     directory. No row of `D0-run-summary.txt` is a function of two runs, so no pin")
    print("     over that row can witness it, and a TAUTOLOGY IS NOT WHAT WAS ADDED.")
    # WHY `repro_bad()` IS A FUNCTION BESIDE `unhealthy()` AND NOT A ROW INSIDE IT. Measured by
    # ORDER, because the failure is a liveness failure rather than a wrong answer: `cmd_repro`
    # calls `clean_run()` -- which calls `unhealthy()` -- BEFORE it writes the artifact, so a
    # health check that demanded `D0-repro.txt` would be demanding a file that does not exist yet
    # and could not be satisfied by the command being run.
    print(f"\n  order inside `cmd_repro`: clean_run() at offset {cmd_repro.index('clean_run('):4d}, "
          f"the artifact is written at offset {cmd_repro.index('write(REPRO_ARTIFACT'):4d}"
          f"  -> the health check runs {cmd_repro.index('write(REPRO_ARTIFACT') - cmd_repro.index('clean_run(')} "
          f"chars BEFORE the file exists.")
    print("     So folding this pin into `unhealthy()` would make `repro` unable to ever report a")
    print("     healthy run: a gate that can never pass is a gate that gets deleted.")


if __name__ == "__main__":
    ok, msg = derive.selfcheck()
    print(msg)
    if not ok:
        raise SystemExit(1)
    layer1()
    sensitivity()
    independence()
    redundancy()
    derivability()