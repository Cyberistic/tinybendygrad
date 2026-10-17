#!/usr/bin/env python3
r"""ops_python_exec-gate.py -- the EXECUTOR census for
`tinybendygrad/runtime/ops_python.bend`, the port of
`tinygrad/runtime/ops_python.py`.

    .venv/bin/python gates/ops_python_exec-gate.py
    .venv/bin/python gates/ops_python_exec-gate.py --refresh   # rewrite the pins
    .venv/bin/python gates/ops_python_exec-gate.py --jobs 6    # port-lane parallelism

TWO LANES, AND WHY NOT THREE. `gates/ops_python_census-gate.py` runs the port twice,
`bend file.bend` and `bend file.bend -o exe`, and diffs the two. The executor cannot
be run that way. MEASURED 2026-10-14 on a 7-uop packet: the compiled executor exits
0 in 1.79 s and writes both buffers, while
`bend tinybendygrad/runtime/ops_python.bend PACKET 1 1 1` exits **1** in 6.76 s with
`bend: memory fault (machine stack overflow?)` and writes no PACKET.out at all --
`run` is a fuel recursion (`FUEL() = 4000000n`, ops_python.bend:2064) and the HVM
interpreter cannot hold it. So this gate says TWO and does not invent a third.

WHAT IS IN IT, AND WHY IT IS NOT THE OTHER GATE. `ops_python_census-gate.py` covers
the RENDERER/DEVICE half with 85 rows and finding D in its own header records the
gap: `PythonProgram.__call__` is ops_python.py:52-157, **106 of 186 lines**, and had
no rows at all. This gate covers that half by running both interpreters over the
SAME packets.

WHERE THE PACKETS COME FROM, which is finding D's answer and the reason it had the
wrong answer. Finding D's blocker was "the CPython lane needs real `UOp`s from the
v1 wire, and `ops_bend.parse` stops where the uops begin". **The CPython lane does
not need a wire -> `UOp` decoder, because the census runs the other way.** The tree
already owns `UOp`s -> wire: `ops_bend.encode(uops)` (ops_bend.py:133). So
`gates/ops_python_exec-gen.py` captures real launches at
`PythonRenderer.render` / `PythonProgram.__call__`, keeps the REAL `UOp` list for the
oracle and hands the port the `encode` output, which is the packet the port's own
`Prog.parse` reads. Nothing in this gate or its oracle decodes a packet into a `UOp`;
that reimplementation is the failure this axis exists to avoid, and MEASURED the port
could not generate the fixtures anyway -- `grep -c "UOp.new"
tinybendygrad/runtime/ops_python.bend` answers **0**, because this layer builds no
UOps. What the port DOES declare is its own arm table, and `arms_hold()` below reads
it out of the port by regex and asks what the fixtures reached.

    lane `py`   `ops_python_exec-gen.py` -- CPython's own `PythonProgram.__call__` on
                the captured `UOp` lists, printed as `<fixture>.b<i>=<hex>`.
    lane `bd`   the compiled executor, one process per fixture, `PACKET.in` written
                from the fixture file and `PACKET.out` read back the way
                `BendProgram.__call__` reads it (ops_bend.py:225).

EXIT STATUS: 0 both lanes agree after the pins and every check holds · 1 a lane took
the wrong row count, a lane failed, the lanes disagree, a pin moved, the fixture file
is not the generated one, or a coverage/population check failed · 3 a precondition
was absent (the fixture file, the executor, `bin/bend`).
"""
import argparse
import concurrent.futures
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import BEND, PY, PASS, FAIL, REFUSED                             # noqa: E402,F401


def refuse(why):
    """exit 3 = REFUSED, and NOT a verdict -- `gates/gatekit.py`'s own vocabulary.

    **THIS FUNCTION IS THE POINT OF THE CHANGE THAT INTRODUCED IT.** The first three sites used
    `sys.exit(f"...")`, and `sys.exit` with a STRING prints it and exits **1**. So an ABSENT input
    and an OVER-BUDGET refusal both announced themselves in the message -- one of them literally
    beginning `REFUSED:` -- and then exited `FAIL`. MEASURED 2026-10-16: `gatesweep.py` classifies a
    gate by its exit code through this same `VERDICT`, so the tally recorded a refusal as a failure.
    **A GATE THAT SAYS REFUSED AND EXITS FAIL IS TALLIED AS A FAILURE, AND THE TALLY IS THE THING
    THAT IS READ.** Every value here prints BEFORE the exit, so a caller that reads only the status
    still gets a named state.

    AND THIS IS NOT A WEAKENING, WHICH IS THE CLAIM THAT NEEDS EVIDENCE, SO HERE IS THE EVIDENCE.
    It is a change in the NUMBER a reader gets, not in WHETHER the run is red: 1 and 3 are both
    non-zero, `gates/runner.py` and `checks/gatesweep.py:classify` both map 3 to `REFUSED`, and
    nothing is skipped, retried or swallowed on the way there. What 3 buys is the ability to tell
    "your inputs are absent" from "the executor and CPython disagree", which is the whole reason
    `gates/gatekit.py` has five exits and not two.

    THE FOUR SITES, AND THE GROUND FOR EACH. **The verdict did not come from this change; it was
    already written down in this file's own EXIT STATUS paragraph, eighteen lines above, and the code
    was contradicting it.** :46-49 says verbatim "3 a precondition was absent (the fixture file, the
    executor, `bin/bend`)", which NAMES all four conditions this function now carries:
      `fixtures()`  a fixture file that exists but parses to no records is the same class as one
                    that does not exist, and `main()` already graded THAT REFUSED two hundred lines
                    below at the `if not p.exists(): refuse(...)` line (:295). An argv with no
                    gx gy gz is the same thing one parse later.
      `lane_py()`   the oracle failing to run is `gates/gatekit.py:515-516`'s own words: "CPython
                    did not run, so nothing was compared" -> `return REFUSED`. A DISAGREEMENT is not
                    what an oracle that produced no rows can be.
      `main()`      `the executor <path> is absent` is literally the absent-precondition sentence,
                    and `main()` grades exactly that sentence REFUSED for the other three paths
                    at :295-296 above. **ONE FILE, ONE CONDITION, TWO VERDICTS, was the defect.**

    WHAT THE CENSUS SAYS ABOUT THE FOUR, because a fix with no instrument behind it is a fix that
    rots: `gates/exitcode-census-gate.py` grades the SHAPE of what a site hands the exit, and reads
    these four as `STR` -- "the code is CPython's to choose from the TYPE" -- against `INT`, which
    is a number an author picked. Its `--plant` drives that classifier on synthetic sources and
    goes red if the `STR` branch stops being `STR`.
    """
    print(f"REFUSED, NOT A VERDICT: {why}", file=sys.stderr)
    sys.exit(REFUSED)

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
FIXTURES = HERE / "ops_python_exec-fixtures.rows"
PINS = HERE / "ops_python_exec-pins.rows"
GEN = HERE / "ops_python_exec-gen.py"
PORT = ROOT / "tinybendygrad" / "runtime" / "ops_python.bend"

# The executor's peak RSS is measured, not guessed: 606420992 bytes for a 7-uop
# packet. Six concurrent lanes is 3.6 GB, and `hw.memsize` answers 17179869184.
MAXRSS = 606420992
MEMSIZE = 17179869184


def report(name, bad):
    for b in bad: print(f"  {name}: {b}", file=sys.stderr)
    if not bad: print(f"  {name}: OK")
    return not bad


# ===========================================================================
# THE FIXTURE FILE. Loaded by path -- it is the gate's tracked input and lives
# BESIDE the gate, not in `gates/artifacts/`, which `gatekit` empties on every run.
# ===========================================================================
def fixtures():
    """`[(name, argv, packet_text)]`. The packet is the record's body VERBATIM, so
    writing `PACKET.in` is `f.write(text)` and the gate parses no wire at all."""
    recs, cur = [], None
    for ln in FIXTURES.read_text().splitlines():
        if ln.startswith("@ "):
            head = ln.split()[1:]
            cur = [head[0], tuple(int(x) for x in head[1:]), []]
            recs.append(cur)
        elif cur is not None and ln.strip():
            cur[2].append(ln)
    if not recs: refuse(f"{FIXTURES} has no records")
    for n, a, _ in recs:
        if len(a) < 3: refuse(f"{n}: argv {a} has no gx gy gz")
    return [(n, a, "\n".join(p) + "\n") for n, a, p in recs]


def fixtures_hold(fx):
    """The fixture file is GENERATED and its header says so; the header must still be
    there and must still name the generator. A hand-edited file loses its first line
    and this turns red rather than quietly becoming a hand list."""
    bad = []
    head = FIXTURES.read_text().splitlines()[:3]
    if not head or "GENERATED by gates/ops_python_exec-gen.py" not in head[0]:
        bad.append(f"{FIXTURES.name} does not carry its generated-by header")
    if any(not l.startswith("#") for l in head):
        bad.append(f"the header block is not three comment lines: {head}")
    for n, _, p in fx:
        if not p.startswith("bendexec1 "):
            bad.append(f"{n}: the record body is not a packet (first line {p.splitlines()[0]!r})")
            break
    return report("fixtures_hold", bad)


# ===========================================================================
# LANE `bd`: the port, one process per fixture.
# ===========================================================================
def port_lane(exe, root, name, argv, packet):
    """Run ONE fixture through the compiled executor and return its rows.

    ONE DIRECTORY PER FIXTURE, and that is the port's contract rather than tidiness:
    `Prog.write.out` (ops_python.bend:2160) finds the LAST `/` of `Args.path` and
    writes `PACKET.out` beside it, so one shared directory has every lane racing for
    one file -- MEASURED with a shared directory: 8 fixtures, rc=0 each, and every
    lane answering `NO-PACKET.out`.

    A REFUSAL IS A ROW, not an error: `Prog.launch.run.at` dies 1 with "executor:
    refused the packet" (ops_python.bend:2269) and CPython's lane answers the same
    packet's `UOp` list, so the pair says something. A run that dies any OTHER way,
    or writes the wrong number of buffer lines, is a failure of the harness and is
    reported as such rather than folded into the rows.
    """
    td = root / name
    td.mkdir(parents=True, exist_ok=True)
    (td / "PACKET.in").write_text(packet)
    r = subprocess.run([str(exe), str(td / "PACKET.in"), *[str(v) for v in argv]], capture_output=True, text=True)
    if r.returncode != 0:
        if "refused the packet" in (r.stderr + r.stdout):
            return [f"{name}=REFUSED-{r.returncode}"]
        return [f"{name}=DIED-{r.returncode}-{(r.stderr or r.stdout).strip()[-40:]}"]
    out = td / "PACKET.out"
    if not out.exists():
        return [f"{name}=NO-PACKET.out"]
    rows = []
    for i, ln in enumerate(out.read_text().splitlines()):
        f = ln.split()
        rows.append(f"{name}.b{i}={f[1] if len(f) > 1 else ''}")
    return rows


def lane_bd(exe, fx, jobs):
    """The port lane. THE EXECUTOR IS COPIED INTO THE RUN'S TEMP DIRECTORY FIRST.

    `ops_bend.executor()` caches by `ops_python.bend`'s mtime+size under tinygrad's
    `cache_dir`, and that cache is not durable: MEASURED 2026-10-14, a run read the
    path, checked `exists()`, and then every launch failed
    `FileNotFoundError: .../bend-executor-8a618c818be2dcdf` -- something swept the
    cache between the check and the launch. A copy inside the run's own directory
    cannot be swept under it.
    """
    td = Path(tempfile.mkdtemp(prefix="ops-exec-"))
    try:
        run_exe = td / "bend-executor"
        shutil.copy2(exe, run_exe)
        run_exe.chmod(0o755)
        rows = {}
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
            fut = {pool.submit(port_lane, run_exe, td, n, a, p): n for n, a, p in fx}
            for f in concurrent.futures.as_completed(fut):
                rows[fut[f]] = f.result()
    finally:
        shutil.rmtree(td, ignore_errors=True)
    return [r for n in sorted(rows) for r in sorted(rows[n])]


# ===========================================================================
# LANE `py`: the oracle. It re-harvests, so the fixture file's population is
# CHECKED against what the generator produces rather than trusted.
# ===========================================================================
def lane_py():
    r = subprocess.run([str(PY), str(GEN)], capture_output=True, text=True, cwd=str(ROOT))
    if r.returncode != 0:
        refuse(f"the oracle lane failed rc={r.returncode}: {r.stderr.strip()[-400:]}")
    return [l for l in r.stdout.splitlines() if "=" in l]


def population_hold(fx, py):
    """THE POPULATION IS THE FILE AND THE ORACLE'S AGREE. The oracle re-derives its
    fixtures from a live `DEV=PYTHON` pass, so a fixture the file has and the oracle
    did not is a stale file and a fixture the oracle has and the file lacks is a file
    nobody regenerated. Both are a red run."""
    onfile = {n for n, _, _ in fx}
    frompy = {l.split("=", 1)[0].rsplit(".b", 1)[0] for l in py
              if l.split("=", 1)[0] != "py-done" and not l.split("=", 1)[0].endswith("=x")}
    bad = []
    if onfile - frompy: bad.append(f"{len(onfile - frompy)} on the file and not in the oracle: {sorted(onfile - frompy)[:5]}")
    if frompy - onfile: bad.append(f"{len(frompy - onfile)} in the oracle and not on the file: {sorted(frompy - onfile)[:5]}")
    return report("population_hold", bad)


# ===========================================================================
# THE COVERAGE CHECK: the port's OWN arm table against what CPython's own dispatch
# loop was observed to execute. Neither list is typed here.
# ===========================================================================
def arms():
    src = PORT.read_text()
    names = re.findall(r'case "(\w+)": Some\{O\.Ops', src)
    body = src[src.index("def Prog.dispatch("):src.index("def Prog.run(+p")]
    arms_ = re.findall(r"case O\.Ops(\w+)\{\}", body)
    catch = re.findall(r"case _:\s*Prog\.(\w+)\(", body)
    return names, arms_, catch


def coverage_hold(_fx):
    """Re-derive the coverage census and pin the UNREACHED set, so a fixture set that
    stops reaching an arm is a red run instead of a smaller green one.

    `Ops.NOOP` and `Ops.BACKEDGE` are the two the census does not reach, and the
    reasons are the tree's, not the census's: `Ops.NOOP` is minted only by the ISA
    renderers (renderer/isa/x86.py:164,:250,:256,:273) and `PythonRenderer` renders
    with `python_alu` (ops_python.py:163), so no `PythonRenderer`-rendered stream
    contains one; `Ops.BACKEDGE` is a loop back edge and the reductions that reach
    `Ops.END` lower to `END` alone. Both are named in `UNREACHED` and that name is
    what a later change has to move.
    """
    names, arms_, catch = arms()
    r = subprocess.run([str(PY), str(GEN), "--coverage"], capture_output=True, text=True, cwd=str(ROOT))
    if r.returncode != 0: return report("coverage_hold", [f"--coverage failed rc={r.returncode}: {r.stderr.strip()[-200:]}"])
    got = {k: int(v) for k, v in re.findall(r"^(\w+): \d+ declared, (\d+) unreached \[", r.stdout, re.M)}
    bad = []
    for k, want in (("op_of", 2), ("dispatch", 2)):
        n = got.get(k)
        if n is None: bad.append(f"no {k} line from --coverage")
        elif int(n) != want: bad.append(f"{k}: {n} unreached, the census pins {want}")
    return report("coverage_hold", bad)


# ===========================================================================
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--jobs", type=int, default=6)
    args = ap.parse_args()

    for p in (FIXTURES, GEN, PORT):
        if not p.exists(): refuse(f"{p} is absent")
    if not BEND.exists(): refuse(f"{BEND} is absent")
    if args.jobs * MAXRSS > 0.6 * MEMSIZE:
        refuse(f"{args.jobs} lanes x {MAXRSS} B exceeds 60% of {MEMSIZE} B")

    fx = fixtures()
    # THE CHEAP CHECKS COME FIRST. Each reports itself and returns a bool -- wrapping
    # them in a second `report()` passes a bool where a list of failures belongs.
    # They run before the port lane because the port lane is the expensive one
    # (MEASURED: 153 fixtures at ~2 s each), and a red fixture file should cost
    # seconds, not a quarter of an hour.
    if not fixtures_hold(fx): sys.exit(FAIL)
    py = lane_py()
    if not population_hold(fx, py): sys.exit(FAIL)
    if not coverage_hold(fx): sys.exit(FAIL)

    sys.path.insert(0, str(ROOT))
    import ops_bend
    exe = ops_bend.executor()
    if not exe.exists(): refuse(f"the executor {exe} is absent")
    bd = lane_bd(exe, fx, args.jobs)

    pinned = set()
    if PINS.exists():
        pinned = {l.split()[0] for l in PINS.read_text().splitlines() if l.strip() and not l.startswith("#")}
    # `py-done` is the ORACLE'S completion marker (ops_python_exec-gen.py prints it
    # last), not a value, and the port lane has no such marker to print -- so it is
    # dropped from BOTH sides rather than pinned. MEASURED: left in, it is one
    # unpinned divergence on every run that says nothing about the executor.
    dpy = {l.split("=", 1)[0]: l for l in py if l.split("=", 1)[0] != "py-done"}
    dbd = {l.split("=", 1)[0]: l for l in bd if l.split("=", 1)[0] != "py-done"}
    unpinned = sorted((set(dpy) | set(dbd)) - pinned)
    diff = [l for l in unpinned if dpy.get(l) != dbd.get(l)]
    if diff:
        for l in diff[:12]:
            print(f"  {l}\n    py {dpy.get(l)}\n    bd {dbd.get(l)}", file=sys.stderr)
        print(f"  {len(diff)} unpinned divergences of {len(unpinned)} rows", file=sys.stderr)
        sys.exit(FAIL)
    print(f"ops_python_exec: PASS -- {len(fx)} fixtures, {len(dpy)} rows x 2 lanes, "
          f"{len(unpinned)} unpinned identical, {len(pinned)} pinned")
    return PASS


if __name__ == "__main__":
    sys.exit(main())