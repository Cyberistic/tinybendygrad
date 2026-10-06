#!/usr/bin/env python
"""Run EVERY gate twice -- once against the frozen OLD gatekit, once against the live NEW one.

    .venv/bin/python .agents/slop/stalefix/gate-matrix.py            # both sides
    .venv/bin/python .agents/slop/stalefix/gate-matrix.py old        # one side

WHY A SHADOW TREE RATHER THAN SWAPPING `gates/gatekit.py`. `gates/retention-check.py` reads
`gates/gatekit.py` as TEXT while it runs, and another unit is working in this tree. Replacing the
file for the duration of a measurement is a window in which a reader sees a gatekit that is not
the tree's. So the OLD side gets its own tree under the scratch directory:

    shadow/gates/gatekit.py  the frozen copy, named `gatekit.py` because every gate does
    shadow/gates/*.py        a copy of every gate file, and they each put their OWN directory on
    shadow/gates/*.bend      `sys.path` before importing, so `from gatekit import Gate` and the
                             gate's relative input paths both resolve inside the shadow
    shadow/.agents ->          SYMLINK to the real tree, because a gate names its driver as
    shadow/tinybendygrad ->    `.agents/slop/...` or `<root-relative>` and `gatekit._resolve` looks
    shadow/examples    ->      HERE then ROOT. `mixin-op-gate` and `beautiful-mnist-gate` name a
                               driver OUTSIDE `gates/`, so these two are load-bearing: without them
                               those gates fail on `no such file` and prove nothing about artifacts.
    shadow/bin         ->
    shadow/.venv        ->     ditto for `BEND` and `PY`

`gatekit.ART` is `HERE/"artifacts"`, so the old side's output lands in the shadow and the real
`gates/artifacts/` is not written by this file at all. The shadow therefore also answers a
question the repro cannot: what do EIGHT REAL gates leave on disk, which is the population the
RECOVERED report measured ("three gate dirs held exactly bd.out bn.out py.out gate.bin").

EVERY GATE IS RUN SEQUENTIALLY, and each is wrapped in `checks/bounded.py` because `sz.bend`
peaks at 1,468 MB and the measured gate peaks are 1,368 / 1,531 / 734 MB. `bounded.py` walks the
whole process tree, so the bend children are inside the ceiling. NO MEMORY BOUND IS ADDED TO
`gatekit` itself, deliberately: `bounded.py` returns 3 for memory and 4 for time, neither is a
status these lanes produce, and bounding inside a gate would be a verdict change dressed as
safety (TODO GXR-12). Here it is a MEASUREMENT HARNESS, which is the only place it belongs.
"""
import hashlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

FIX = Path(__file__).resolve().parent
ROOT = FIX.parent.parent.parent
SCRATCH = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/stalefix-matrix")
OLD = FIX / "gatekit-old.py"


def gates():
    """Every `gates/*.py` that constructs a Gate, DISCOVERED rather than listed. A hardcoded list
    went stale within the hour -- `gates/i64-shr-gate.py` appeared while this file was being
    written -- and a matrix that silently skips a gate reports a denominator it did not measure.
    `retention-check.py` is excluded because it constructs no Gate: it writes no gate artifact and
    runs no lane, it is the instrument that audits this output."""
    out = []
    for p in sorted((ROOT / "gates").glob("*.py")):
        if re.search(r"Gate\(\s*[\"']", p.read_text()):
            out.append(p.stem)
    return out


def shadow(names):
    """The OLD tree, built fresh every time so no run inherits another's output."""
    s = SCRATCH / "old"
    shutil.rmtree(s, ignore_errors=True)
    (s / "gates").mkdir(parents=True)
    for p in sorted((ROOT / "gates").iterdir()):
        if p.is_file() and p.suffix in (".py", ".bend"):
            shutil.copy(p, s / "gates" / p.name)
    shutil.copy(OLD, s / "gates" / "gatekit.py")
    for link, target in ((".agents", ROOT / ".agents"), ("bin", ROOT / "bin"),
                         (".venv", ROOT / ".venv"), ("examples", ROOT / "examples")):
        (s / link).symlink_to(target)
    # `tinybendygrad` IS COPIED, NOT SYMLINKED, and that is not tidiness. MEASURED: `gates/*.bend`
    # import it as `./../tinybendygrad/...`, and with that path a symlink `bend` answers
    #   - expected : an import path of plain names ...; the hub's files import the hub's
    # so FOUR of the gates failed in the shadow on a driver byte-identical to the one that passes
    # in the real tree. A shadow that changes the compiler's answer measures the shadow, not the
    # gates -- and it would have looked exactly like a gatekit verdict difference.
    shutil.copytree(ROOT / "tinybendygrad", s / "tinybendygrad",
                    ignore=shutil.ignore_patterns("__pycache__"))
    print(f"# shadow: {len(names)} gates; tinybendygrad COPIED; .agents/bin/.venv/examples symlinked")
    return s


def artdir(gate):
    """The artifact DIRECTORY's name, which is `Gate("<name>", ...)` and is not always the gate
    FILE's stem: `gates/i64-shl-gate.py` publishes into `gates/artifacts/i64-shl/`. Read from the
    source rather than guessed, because guessing it made one gate's row report 0 files."""
    src = (ROOT / "gates" / f"{gate}.py").read_text()
    return re.search(r'Gate\(\s*"([^"]+)"', src).group(1)


def run(gate, cwd, art):
    """One gate, bounded. Returns (rc, bounded-verdict-token, peak-MB, seconds, tail-of-output)."""
    py = ROOT / ".venv" / "bin" / "python"
    # bounded.py is not executable in this tree, so it is invoked THROUGH the interpreter.
    argv = [str(py), str(ROOT / "checks" / "bounded.py"), "--seconds", "900", "--mb", "2048",
            "--", str(py), str(cwd / "gates" / f"{gate}.py")]
    p = subprocess.run(argv, cwd=cwd, capture_output=True, text=True)
    token = next((w for w in ("WITHIN-LIMITS", "KILLED ON MEMORY", "KILLED ON TIME",
                              "TIMED OUT") if w in p.stdout), "NO-TOKEN")
    peak = next((l.split("peak-RSS=")[1].split()[0] for l in p.stdout.splitlines()
                 if "peak-RSS=" in l), "?")
    return p.returncode, token, peak, (p.stdout + p.stderr).strip().splitlines()


def holdings(art):
    """name -> sha256[:12] for every file, so STALE and FRESH can be told apart later."""
    return {q.name: hashlib.sha256(q.read_bytes()).hexdigest()[:12]
            for q in sorted(art.iterdir()) if q.is_file()} if art.is_dir() else {}


def matrix(label, cwd, art_root, before):
    print(f"\n{'=' * 78}\n{label}\n{'=' * 78}")
    print(f"  {'gate':26} {'rc':>3}  {'bounded':14} {'peak MB':>8}  {'left on disk':>12}  "
          f"{'stale from the green run':>26}")
    for gate in gates():
        art = art_root / artdir(gate)
        rc, token, peak, out = run(gate, cwd, art)
        now = holdings(art)
        stale = sorted(n for n, h in now.items() if before.get((gate, n)) == h)
        print(f"  {gate:26} {rc:>3}  {token:14} {peak:>8}  {len(now):>12}  "
              f"{('|'.join(stale) or 'none')[:26]:>26}")
        for line in out[-3:]:
            print(f"      | {line[:150]}")
    return {gate: holdings(art_root / artdir(gate)) for gate in gates()}


def main():
    want = sys.argv[1] if len(sys.argv) > 1 else "both"
    names = gates()
    s = shadow(names)
    green = matrix("OLD gatekit (frozen) -- FIRST RUN, each dir empty", s, s / "gates" / "artifacts", {})
    if want == "old":
        return 0
    # The SECOND run against the same old gatekit, with the first run's output still in place.
    # Every artifact that survives unchanged is the previous run's bytes -- which is the bug,
    # on the real population, and not on a synthetic three-row fixture.
    stale = matrix("OLD gatekit -- SECOND RUN, first run's artifacts still on disk",
                   s, s / "gates" / "artifacts",
                   {g: n for g, fs in green.items() for n, h in fs.items()})
    print(f"\n  OLD, after a second run of the SAME gates: "
          f"{sum(1 for fs in stale.values() for _ in fs)} files held, "
          f"{sum(len(fs) for fs in stale.values())} unchanged from the previous run's")
    if want == "shadow":
        return 0
    matrix("NEW gates/gatekit.py -- the real tree, every dir already populated",
           ROOT, ROOT / "gates" / "artifacts", {})
    return 0


if __name__ == "__main__":
    sys.exit(main())
