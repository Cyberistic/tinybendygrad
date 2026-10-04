#!/usr/bin/env python3
"""One driver for the graphcmp corpus: every artifact, plus the two-run stability check.

It replaces `.agents/slop/graphcmp-run.sh` and `.agents/slop/graphcmp-repro.sh`, whose
artifacts under `runs/graphcmp/D/` it reproduces byte for byte; both `.sh` files stay on
disk as `exec` shims, and the shell's bodies are frozen in `.agents/slop/diffpy/` as the
ORACLE the port is diffed against.

Two gates, and WHAT EACH ONE CLAIMS, because a gate whose scope is a comment is a gate
nobody can check:

  run     the per-graph VERDICT line and its DENOMINATOR line for 16 graphs (14 AGREE;
          `lin` and `loop` DISAGREE for named measured causes), the canonical py-vs-bend
          byte identity of each graph, 5 same-side controls, 1 cross-graph comparison, 7
          plants that must DISAGREE and name something, the ordered/`--equiv` split on the
          same reordered pair, 4 conflations, the DEBUG-level comparison, 5 two-run
          stability pairs, the 0-row guard fired on purpose, the both-sides coverage census,
          the CPython `DEBUG>=1` reachability question, and the raw CPython ops probe.

  repro   that ONE run is reproducible: two clean runs, sha256 over the non-blank lines of
          every artifact, byte-compared. It first WAITS for the substrate (`--check-only`'s
          FIRST line, never its exit status) and then insists the run is HEALTHY -- pinned
          counts a silent step cannot imitate -- and that no artifact is malformed.

  snap    the snapshot primitive both of those are built from, so a third party can compare
          two runs of either driver without re-implementing the hashing.
"""
import argparse
import hashlib
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
D = ROOT / "runs/graphcmp/D"
PY, GCMP = ".venv/bin/python", ".agents/slop/graphcmp.py"
# `env -u PYTHONPATH` is REQUIRED (it contaminates a control) and `LC_ALL=C` is REQUIRED (a
# locale-colated sort fabricates diffs). `DEV=NULL` is the rebase gate's own setting;
# graphcmp.py overrides it from its own `--dev`, which is why every artifact names its device.
ENV = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"LC_ALL": "C", "DEV": "NULL"}

# THE FROZEN SHELL ORACLE IS PINNED HERE, IN CODE, AND CHECKED ON EVERY RUN.
#
# Both `.sh` shims carry a sha256 in a comment and claim the frozen copy "cannot drift
# unnoticed". MEASURED 2026-10-05: nothing read it. The pin was CORRECT -- it is the hash of the
# committed body -- and it was still a comment that added up, because a pin no code consults
# cannot fail, and this file's own docstring names that as the reason a gate must state what it
# CLAIMS. So the pins moved here, where `run` and `repro` both refuse to start on drift.
#
# The hash is of the ORACLE COPY. The copy differs from the committed body by exactly one
# documented edit -- a `GCMP_REPO` default in its first `cd`, so the copy can be run from
# anywhere -- and pinning the copy is what detects the copy drifting. Pinning the committed body
# instead would be a check against `git`, which is a dependency this file does not otherwise have.
ORACLE_PIN = {
    "diffpy/oracle-run.sh":
        "94e7108d428bae3fb211db5cce000819b63e2bfbfd51dad4c512e42626d15905",
    "diffpy/oracle-repro.sh":
        "a5d23505b3e93816370e67df130993e812abd2db7e5c6919d6e98d51af92d2ea",
}


def check_oracle() -> list[str]:
    """Every frozen oracle's actual sha against its pin. Empty list means intact.

    Named distinctly from the `oracle-selfcheck` this driver already reports, which is
    tinygrad's own oracle asserting about ITS rows. That one asks whether the PYTHON side is
    well-formed; this asks whether the SHELL side is still the thing the port was diffed
    against. Two different questions, and the previous spelling used one word for both.
    """
    bad = []
    for name, want in ORACLE_PIN.items():
        path = ROOT / ".agents/slop" / name
        if not path.exists():
            bad.append(f"{name}: MISSING -- the frozen oracle is gone")
            continue
        got = hashlib.sha256(path.read_bytes()).hexdigest()
        if got != want:
            bad.append(f"{name}: {got[:16]} != pinned {want[:16]}")
    return bad

# THE GRAPHS AND THE VERDICT EACH MUST PRINT, IN ONE TABLE, in the order the shell listed
# them. Two lists can disagree, and a graph that runs but is not checked is a graph nobody
# looked at. No default verdict is available here: a claim with no denominator, or an
# expectation that reads a variable, is a claim nobody can check.
WANT = {
    "matmul": "AGREE", "reduce": "AGREE", "buffer": "AGREE", "sink": "AGREE",
    "range": "AGREE", "rangeflat": "AGREE", "cast": "AGREE", "special": "AGREE",
    "binblob": "AGREE", "group": "AGREE", "commute": "AGREE", "indexed": "AGREE",
    "sym": "AGREE",
    # `lin` DISAGREES on ONE node of 46 -- its SINK's `applied_opts`, which the port can only
    # answer with one `q` per option (`ops.bend:978` types them `List<U32>`; upstream's are
    # `Opt` dataclasses).
    "lin": "DISAGREE",
    # `loop` DISAGREES on ONE node of 25 -- its CALL, whose dtype the port reads from
    # `CallInfo.cdtype`, a field CPython's `CallInfo` does not have (`ops.py:130-131` reads
    # `src[0].dtype`). Both are MEASURED causes, not tolerances.
    "loop": "DISAGREE",
    "gate": "AGREE",
}
# THE PLANTS. Every one must DISAGREE and NAME something; a plant that agrees is a plant that
# is not load-bearing. `sym1` needs the `sym` graph and the others need the matmul, so they
# are not one loop. NOT the attributable measurement for the symbolic dim: a plant edits the
# PY side only (planting the bend side is six DAG rewrites in Bend -- the reason
# `--plant-side` was removed), so `D5-plant-sym1.txt` carries the plant's effect AND `sym`'s
# pre-existing `?` disagreements together.
PLANTS = tuple((p, "matmul") for p in ("dtype", "srcswap", "shape", "bytes", "pyuop", "opt")) \
    + (("sym1", "sym"),)
# THE CONTROLS: each side against ITSELF. A differ never seen to agree with itself is not
# known to work. `group` is the first DAG, so a control over a tree-only corpus is a control
# that has never met a two-parent node; `gate` and `loop` are the widest-fan-in and a
# disagreeing graph, so a control that only runs on AGREEing fixtures has never had to agree
# with itself WHILE disagreeing.
CONTROLS = ("matmul", "binblob", "group", "gate", "loop")
# THE STABILITY PAIRS, FIVE, because the interesting shapes differ. A 0-row side is a
# one-line `rc=N` file, which is why a pair is RE-RUN once and a side that is still one line
# is named FAILED rather than compared: two identical FAILURES compare equal.
STAB = tuple((g, ()) for g in ("group", "sym", "loop", "gate")) + (("commute", ("--plant", "srcswap")),)
# A HEALTHY RUN, not merely a FINISHED one. Every pin is matched BY CONTENT, never by line
# number. MEASURED: the shell pinned `graphs-agree=13`, then `14`, against a corpus reading
# `22`, so this gate reported a fully correct run unhealthy and sat retrying it -- a health
# gate pinned to a count can be wrong in the direction of refusing to measure. The first
# three are MEASURED against a run of THIS driver on 2026-10-05 (the shell's `24/22/21` were
# transcribed from a 24-graph corpus this driver does not run); the rest are the shell's.
PINS = {
    "graphs": "16", "graphs-agree": "14", "byte-identical": "14", "not-comparable": "0",
    "selfcheck": "# SELFCHECK: OK", "census-rc": "rc=0",
    # THE THREE COUNTS THAT KEEP A SILENT STEP FROM LOOKING HEALTHY. With the substrate
    # cold, BOTH members of a stability pair wrote the same one-line `0 rows after 5
    # attempts` file, so `cmp -s` called the pair BYTE-IDENTICAL and `stable-pairs` read 5 of
    # 5. **Two identical FAILURES compare equal.** So the gate reads the FAILED and DIFFER
    # counts, not the identical one.
    "stable-pairs": "5 of 5", "stable-failed": "0 of 5", "stable-differ": "0 of 5",
    "plants-disagree": "7 of 7", "cross": "1 of 1", "controls": "5 of 5",
    "conflations": "4 of 4", "oracle-selfcheck": "# ORACLE SELFCHECK: OK",
}


def gc(*args, **kw):
    """`graphcmp.py` under the two required env settings, with no timeout of our own."""
    return subprocess.run([PY, GCMP, *args], cwd=ROOT, env=ENV, **kw)


def run(out, *args):
    """ONE FILE, ONE WRITE, ONE ATOMIC MOVE, and the artifact carries its own `rc=` stamp.

    MEASURED 2026-10-04, and the SECOND time this project has been bitten by it: the version
    that appended `rc=` to the SAME file the child had just written left a window between the
    two, and a run killed in that window produced a report MISSING its last line and with no
    `rc=` at all -- which the stability step then reported as `2 runs DIFFER`, i.e. a
    reproducibility difference whose difference was "the second file is shorter". The temp is
    dot-named and inside the artifact dir, so the rename is same-directory (atomic) and no
    snapshot can see a temp a kill left behind.
    """
    tmp = D / f".tmp.{out}"
    with tmp.open("wb") as f, (D / f"{out}.err").open("wb") as err:
        rc = gc(*args, stdout=f, stderr=err).returncode
    with tmp.open("ab") as f:
        f.write(b"rc=%d\n" % rc)
    os.replace(tmp, D / out)


def capture(out, script, stamp_rc=False):
    """The oracle/probe steps: BOTH streams are the artifact, so they are merged into it.
    `stamp_rc` is the census's, because a step whose output is a TABLE must say whether the
    table is finished -- `graphcmp-oracle.py` calls `emit_bend`, so when a concurrent edit to
    `tinybendygrad/uop/ops.bend` made every bend emission 0 rows the oracle DIED at
    `rangeflat`, printing a nine-row census and nothing about the seven graphs after it."""
    with (D / out).open("wb") as f:
        rc = subprocess.run([PY, script], cwd=ROOT, env=ENV, stdout=f, stderr=f).returncode
    if stamp_rc:
        with (D / out).open("ab") as f:
            f.write(b"rc=%d\n" % rc)


def text(out):
    return (D / out).read_text(errors="replace")


def write(out, body):
    """Verbatim: a `> file` from a block of `echo`s ends in a newline and a `cat` of nothing
    is 0 bytes, and an artefact's size is one of the things `repro` checks."""
    (D / out).write_text(body)


def lines_with(out, needle):
    """`grep -c`: the number of LINES containing `needle`, not the number of occurrences."""
    return sum(needle in ln for ln in text(out).splitlines())


def anchored(out, regex):
    return sum(re.search(regex, ln) for ln in text(out).splitlines())


def files_with(pattern, needle):
    """`grep -l ... | wc -l`. The counting form; `grep -c` over a GLOB prints ONE COUNT PER
    FILE and does not total them, which once made the summary's own total line five lines
    long."""
    return sum(needle in f.read_text(errors="replace") for f in D.glob(pattern))


def grep_line(out, needle):
    return "\n".join(ln for ln in text(out).splitlines() if needle in ln)


def conjoin(xs):
    return xs[0] if len(xs) == 1 else " and ".join(xs) if len(xs) == 2 \
        else ", ".join(xs[:-1]) + " and " + xs[-1]


def byte_diff(a, b, n):
    """The SYSTEM `diff`, on purpose. The DIFFERS branch is an artifact, and difflib spells
    the same difference differently, so a re-spelling would make every failing artifact
    differ for a reason that is the PORT's."""
    p = subprocess.run(["diff", a, b], cwd=ROOT, capture_output=True, text=True)
    return "".join(p.stdout.splitlines(keepends=True)[:n])


def one_line(out):
    return (D / out).read_bytes().count(b"\n") <= 1


def cmd_run(_a):
    D.mkdir(parents=True, exist_ok=True)
    for tmp in D.glob(".tmp.*"):
        tmp.unlink()

    run("D0-selfcheck.txt", "selfcheck")

    # ONE LINE OF SUBSTANCE PER GRAPH: `diff --graph NAME` prints exactly one `# VERDICT:`
    # line and its `# DENOMINATOR:` line, and NAME is the only argument. The verdict step
    # ASSERTS each graph rather than leaving a reader to check sixteen files by eye.
    for g in WANT:
        run(f"D1-graph-{g}.txt", "diff", "--graph", g)
    moved = [f"{g}: VERDICT={v} EXPECTED={WANT[g]}" for g in WANT
             if (v := verdict(f"D1-graph-{g}.txt")) != WANT[g]]
    ng, na = len(WANT), sum(v == "AGREE" for v in WANT.values())
    bad = [g for g, v in WANT.items() if v != "AGREE"]
    write("D1-verdicts.txt", "\n".join(moved + [
        "AT LEAST ONE GRAPH'S VERDICT MOVED" if moved else
        f"all {ng} graphs: verdict as expected ({na} AGREE; {conjoin(bad)} DISAGREE, each "
        f"with a named cause in the WANT comment above)"]) + "\n")

    # THE CANONICAL FILES ARE BYTE-IDENTICAL, the cheapest check here: it fails first when an
    # atom letter moves. THIS STEP WAS A VACUOUS PASS until 2026-10-04: it ran `emit py` /
    # `emit bend`, which argparse rejects (`--side` is a FLAG, not a positional), so both
    # children exited 2 having written ZERO BYTES and `cmp -s` on two empty files returns
    # success. Hence the byte-count guard: a verdict line cannot tell an empty comparison
    # from a satisfied one.
    for g in WANT:
        # A BARE redirect, deliberately not `run()`: this step needs stdout in two files at
        # once, so neither is staged and either can be left 0 bytes.
        sides = {}
        for side in ("py", "bend"):
            with (D / f"D2-canon-{side}-{g}.txt").open("wb") as f:
                gc("emit", "--side", side, "--graph", g, stdout=f, stderr=subprocess.DEVNULL)
            sides[side] = (D / f"D2-canon-{side}-{g}.txt").read_bytes()
        py, bend = sides["py"], sides["bend"]
        if not py or not bend:
            report = (f"{g} NOT COMPARED: py={len(py)} bytes bend={len(bend)} bytes "
                      "(a 0-byte side is a FAILURE, not a pass)")
        elif py == bend:
            report = f"{g} BYTE-IDENTICAL ({len(py)} bytes both sides)"
        else:
            report = f"{g} DIFFERS:\n" + byte_diff(
                D / f"D2-canon-py-{g}.txt", D / f"D2-canon-bend-{g}.txt", 20)
        write(f"D2-cmp-{g}.txt", report + "\n")
    # PER-GRAPH FILE, THEN CONCATENATED ONCE, in glob order. Both wrong shapes were tried:
    # `>>` accumulates until the file reads like a coverage table when it is one line
    # repeated, and `>` inside the loop leaves only the LAST graph's line.
    write("D2-bytediff.txt",
          "".join(f.read_text(errors="replace") for f in sorted(D.glob("D2-cmp-*.txt"))))

    for g in CONTROLS:
        run(f"D3-control-{g}.txt", "control", "--graph", g)
    run("D4-cross-range.txt", "cross", "--graph", "range")
    for plant, g in PLANTS:
        run(f"D5-plant-{plant}.txt", "diff", "--graph", g, "--plant", plant)
    # THE ORDERED / EQUIV SPLIT on the same reordered pair. Same fixture, two answers, and
    # both are results. It runs on `commute` too, which is the point: `--equiv` used to be
    # measured on ONE commutative op (a MUL), and here it is six of them in one graph.
    for g in ("matmul", "commute"):
        run(f"D6-{g}-ordered.txt", "diff", "--graph", g, "--plant", "srcswap")
        run(f"D6-{g}-equiv.txt", "diff", "--graph", g, "--plant", "srcswap", "--equiv")
    run("D7-conf.txt", "conf")
    run("D8-dbg-012.txt", "dbg", "--levels", "0,1,2")
    run("D8-dbg-03.txt", "dbg", "--levels", "0,3")

    for g, extra in STAB:
        for side in "ab":
            run(f"D9-stability-{g}-{side}.txt", "diff", "--graph", g, *extra)
    report = []
    for g, extra in STAB:
        a, b = f"D9-stability-{g}-a.txt", f"D9-stability-{g}-b.txt"
        if one_line(a) or one_line(b):
            for side in "ab":
                run(f"D9-stability-{g}-{side}.txt", "diff", "--graph", g, *extra)
        if one_line(a) or one_line(b):
            report.append(f"{g}: ONE SIDE IS A 0-ROW FAILURE after a retry -- NOT a "
                          "reproducibility result")
        elif (D / a).read_bytes() == (D / b).read_bytes():
            report.append(f"{g}: 2 runs BYTE-IDENTICAL")
        else:
            report.append(f"{g}: 2 runs DIFFER\n" + byte_diff(D / a, D / b, 20))
    write("D9-stability.txt", "\n".join(report) + "\n")

    # THE 0-ROW GUARD, FIRED ON PURPOSE. `graphcmp-empty.bend` prints nothing, so
    # `emit --side bend` must RAISE rather than answer.
    run("D10-zerorow-guard.txt", "emit", "--side", "bend",
        "--bend-probe", ".agents/slop/graphcmp-empty.bend")
    # THE COVERAGE DENOMINATOR, tabulated, emitting BOTH sides so an op or atom the py side
    # never produces shows up as a per-side difference rather than an absorbed AGREE.
    capture("D0-coverage-census.txt", ".agents/slop/graphcmp-oracle.py", stamp_rc=True)
    # WHETHER CPYTHON's OWN `DEBUG >= 1` SITE CAN BE REACHED HERE. It cannot, on 13 real
    # graphs, which is why `dbg` is port-vs-port and says so in its own output.
    capture("D8b-cpython-dbg1-reachability.txt", ".agents/slop/graphcmp-dbg-oracle.py")
    # THE OPS PROBE: the raw CPython measurements every coverage claim rests on. It asks
    # CPython DIRECTLY -- does GROUP carry a `params` list, which Tensor op emits which NODE
    # op -- and those questions have no answer a port-vs-port diff can produce.
    capture("D0-ops-probe.txt", ".agents/slop/graphcmp-p13-ops.py")

    # REMOVE THE STALE FILES no command here produces. The byte-identity step used to run four
    # graphs, and an earlier unquoted `for c in $STAB` split on the space in
    # `--plant srcswap` and produced a SIXTH pair named `srcswap`, which is not a graph. A
    # directory carrying a PASS-shaped file that no command produces is exactly what this
    # prevents -- and `D1-verdicts.txt` is the only thing that caught it, because it does not
    # look at file NAMES.
    for stale in ("D9-stability-a.txt", "D9-stability-b.txt"):
        (D / stale).unlink(missing_ok=True)
    for stale in D.glob("D9-stability-srcswap-*"):
        stale.unlink()

    write("D0-run-summary.txt", "\n".join([
        f"graphs={len(list(D.glob('D1-graph-*.txt')))}",
        f"graphs-agree={files_with('D1-graph-*.txt', 'VERDICT: AGREE')}",
        f"graphs-disagree={files_with('D1-graph-*.txt', 'VERDICT: DISAGREE')}",
        f"byte-identical={lines_with('D2-bytediff.txt', 'BYTE-IDENTICAL')}",
        f"not-comparable={lines_with('D2-bytediff.txt', 'NOT COMPARED')}",
        f"stable-pairs={anchored('D9-stability.txt', r': 2 runs BYTE-IDENTICAL$')} of 5",
        f"stable-failed={lines_with('D9-stability.txt', 'ONE SIDE IS A 0-ROW FAILURE')} of 5",
        f"stable-differ={anchored('D9-stability.txt', r': 2 runs DIFFER$')} of 5",
        # SEVEN, NOT SIX, and the seventh is `sym1` -- the plant that needs the `sym` graph
        # rather than the matmul, so it is not in the six-above loop.
        f"plants-disagree={files_with('D5-plant-*.txt', 'VERDICT: DISAGREE')} of 7",
        f"cross={lines_with('D4-cross-range.txt', 'CROSS VERDICT: OK')} of 1",
        f"selfcheck={first_line('D0-selfcheck.txt')}",
        f"conflations={lines_with('D7-conf.txt', 'VERDICT: OK')} of 4",
        f"controls={files_with('D3-control-*.txt', 'CONTROL VERDICT: OK')} of 5",
        # The oracle's own assertions ride in the same summary as the differ's, because a
        # coverage claim whose printer is broken is a coverage claim about the printer.
        f"oracle-selfcheck={grep_line('D0-coverage-census.txt', 'ORACLE SELFCHECK')}",
        f"census-rc={last_line('D0-coverage-census.txt')}"]) + "\n")
    print(f"wrote {D.relative_to(ROOT)}")
    return 0


def verdict(out):
    """`grep -o 'VERDICT: [A-Z]*' ... | tail -1 | cut -d' ' -f2`. The LAST one, because a
    report carries the verdict twice and the operative line is the one at the bottom."""
    found = re.findall(r"VERDICT: [A-Z]*", text(out))
    return found[-1].split()[1] if found else ""


def first_line(out):
    return text(out).split("\n", 1)[0]


def last_line(out):
    return text(out).rstrip("\n").split("\n")[-1]


def snap(stream=sys.stdout):
    """sha256 over the NON-BLANK lines of every artifact, dotfiles pruned.

    The exclusion is not cosmetic: `run()` stages each output as `.tmp.<name>` inside this
    directory, so a run killed mid-write leaves a temp whose presence in one snapshot and
    absence in the other is a difference in the HARNESS's staging and not in the artifact.
    Dropping blank lines is load-bearing rather than fussy: a trailing BLANK LINE is a real
    difference this project has already paid for (a count-based diff reported 16 apparent
    deltas that were 16 blank lines), while a hash of the whole file would call a blank line
    a difference too. This form asks whether any CONTENT moved, which is the question.
    """
    for p in sorted((q for q in D.rglob("*")
                     if q.is_file() and not q.is_symlink()
                     and not any(part.startswith(".") for part in q.relative_to(D).parts)),
                    key=lambda q: q.relative_to(ROOT).as_posix()):
        body = b"".join(ln + b"\n" for ln in p.read_bytes().split(b"\n")[:-1] if ln.strip())
        print(f"{hashlib.sha256(body).hexdigest()}  {p.relative_to(ROOT)}", file=stream)


def settled():
    """ONE probe line, and it is `--check-only`'s FIRST line only: agent-core.md's trap is
    that it exits 1 even on a clean file (`dtype.bend`'s 14 permanently-red laws), so the exit
    status is not the signal and the text is."""
    p = subprocess.run(["./bin/bend", ".agents/slop/graphcmp.bend", "--check-only"],
                       cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return p.stdout.split("\n", 1)[0]


def ready(wait):
    for probe in range(wait):
        if settled() == "ALL PROOFS CHECK":
            return True
        if probe + 1 < wait:
            time.sleep(60)
    return False


def unhealthy():
    """Every pin matched BY CONTENT, and a FAILING PIN NAMED.

    The shell's `healthy()` answered one boolean, so a stale pin was indistinguishable from a
    broken run. That is the whole reason this returns the offenders: a health gate that says
    only "not healthy" has spent an hour of wall clock saying nothing about why.
    """
    got = dict(ln.split("=", 1) for ln in text("D0-run-summary.txt").splitlines() if "=" in ln)
    return [f"{k}={v} (expected {PINS[k]})" for k, v in got.items() if k in PINS and v != PINS[k]] \
        + [f"{k} ABSENT" for k in PINS if k not in got]


def artefacts_ok():
    """THE ARTEFACTS THEMSELVES, not the summary about them.

    A gate that reads the summary trusts that the summary and the files were written at the
    same time by the same attempt, and they were not when a step can fail. So this counts the
    SHAPE of every artifact: no `.txt` may be empty, and no diff REPORT may be a single
    `rc=` line -- the 0-row failure shape, and two of them compared equal. `*.err` files are
    legitimately empty and are excluded: a rule that flags a correct file is a rule that
    always fails, and then it is not a rule.
    """
    bad = [f"EMPTY {p.relative_to(ROOT)}" for p in sorted(D.glob("*.txt")) if not p.stat().st_size]
    reports = {p for pattern in ("D1-graph-*.txt", "D3-control-*.txt", "D5-plant-*.txt",
                                 "D6-*.txt", "D9-stability-*.txt") for p in D.glob(pattern)}
    bad += [f"ONE-LINE {p.relative_to(ROOT)}" for p in sorted(reports) if one_line(p.name)]
    return bad


def clean_run(label, wait):
    """Run until healthy, bounded. `ready && <run>` is the SHELL's order, defect included:
    when the substrate never settles the runner is not executed and `unhealthy()` then reads
    the PREVIOUS run's summary. Reported, not fixed -- see DIFFPY.md."""
    for attempt in range(wait):
        if ready(wait):
            subprocess.run([sys.executable, str(Path(__file__).resolve()), "run"], cwd=ROOT,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if bad := unhealthy():
            print(f"# {label}: run {attempt + 1} summary was NOT healthy -- waiting: "
                  + "; ".join(bad))
        elif bad := artefacts_ok():
            print(f"# {label}: summary healthy but {len(bad)} malformed artefact(s): "
                  + " ".join(bad[:2]))
        else:
            print(f"# {label}: healthy run, and every artefact has a body")
            return True
        time.sleep(30)
    print(f"# {label}: no healthy run in {wait} attempts -- this is NOT a measurement")
    return False


def cmd_repro(a):
    with tempfile.TemporaryDirectory() as tmp:
        shots = {}
        for label, run_label in (("A", "run A"), ("B", "run B")):
            if not clean_run(run_label, a.wait):
                return 2
            path = Path(tmp) / f"gcrepro{label}.sha"
            with path.open("w") as f:
                snap(f)
            shots[label] = path
            print(f"# run {label} done: {len(path.read_text().splitlines())} files snapshotted")
        n = len(shots["B"].read_text().splitlines())
        if shots["A"].read_bytes() == shots["B"].read_bytes():
            print(f"REPRO: {n} of {n} files identical across two clean runs "
                  "(sha256 over non-blank lines)")
            return 0
        print(f"REPRO: NOT IDENTICAL -- {n} files:")
        sys.stdout.write(byte_diff(shots["A"], shots["B"], 40))
        return 1


def main():
    ap = argparse.ArgumentParser(
        prog="checks/differ.py", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("run", help="write every graphcmp artifact under runs/graphcmp/D")
    r = sub.add_parser("repro", help="two clean runs of `run`, byte-compared (the gate)")
    r.add_argument("wait", nargs="?", type=int, default=9,
                   help="attempts per run, and 60s substrate probes per attempt "
                        "(the shell's WAIT; default 9)")
    sub.add_parser("snap", help="print the snapshot both gates are built from")
    a = ap.parse_args()
    D.mkdir(parents=True, exist_ok=True)
    drift = check_oracle()
    if drift:
        # Refuse, loudly, and name the file. A driver that diffs against a moved oracle would
        # report a verdict about a comparison nobody is making.
        for line in drift:
            print(f"ORACLE DRIFT: {line}", file=sys.stderr)
        print("  the frozen shell oracle moved, so this run would compare against nothing. "
              "Restore it from the commit that froze it, or re-freeze it deliberately and "
              "update ORACLE_PIN here -- do not delete the pin.", file=sys.stderr)
        return 3
    return {"run": cmd_run, "repro": cmd_repro, "snap": lambda _: (snap(), 0)[1]}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
