#!/usr/bin/env python3
"""gates/edge-runner.py -- THE EDGE: a COMMITTED surface that runs the gates and leaves a TRACE.

    .venv/bin/python gates/edge-runner.py              # run the edge, write the trace
    .venv/bin/python gates/edge-runner.py --plan       # the selection and the ledger, run NOTHING
    .venv/bin/python gates/edge-runner.py --measure    # (re)measure the cost ledger
    .venv/bin/python gates/edge-runner.py --plant      # the plant and its control
    .venv/bin/python gates/edge-runner.py --root DIR --trace PATH --cost PATH

WHAT THIS IS. `gates/pincensus-gate.py` measured that 60 pins in this tree CAN fail, that 0 are
stale, and that **nothing is wired to notice when one does**: `.git/hooks` holds 0 non-`.sample`
files, `core.hooksPath` is UNSET, the 9 files in `.github/workflows/` name 0 gates, and
`gates/artifacts/` holds 0 tracked paths (it is gitignored, `.gitignore:214`). **THE PINS AND THE
COMPARATORS ARE FINE. WHAT IS MISSING IS AN EDGE.** This file is that edge, and the companion
`.github/workflows/edge-gates.yml` is where it runs.

**WHAT THE EDGE CANNOT DO, STATED HERE BECAUSE A WORKFLOW THAT PROMISES MORE THAN IT DELIVERS IS
THE SAME DEFECT AS A PROSE PIN, ONE LAYER UP.**

  * It **cannot make a pin go red by itself.** The pins and the comparators are fine; a stale pin
    goes red because the gate that HOLDS it compares it and disagrees. What the edge adds is the
    moment somebody RUNS the gates, the result LEAVES A TRACE IN THE REPOSITORY.
  * It **runs on GitHub, not here.** Its value today is that it is REVIEWABLE and VISIBLE -- a
    committed file a reviewer can read -- and not that it has run.
  * **A green run is not a claim that the tree is good.** It is a claim that the gates that could
    run AGREED. The trace prints its denominator beside its tally, always.

**THE SELECTION IS DISCOVERED, AND THREE POPULATIONS ARE JOINED. NOT ONE NAME IS TYPED.**

  F1  THE POPULATION. `checks/gatesweep.py:population()` -- the derived gate homes from
      `gates/gates-pop.py:gate_homes()` plus `entry_reason()`, walked with `os.walk`. Never a
      suffix, never a glob, never a hand list. MEASURED 2026-10-20: **279** members.
  F2  THE PIN. The member's own source holds a pin that **its own code reads** -- the CAN-FAIL
      class -- by `gates/pincensus-pop.py`'s own `rule_a()` and `readers()`, LOADED BY PATH.
      MEASURED 2026-10-20: **17** members. (MEASURED, and the two filters coincide: every NAMED
      pin site in the gate population is read by its own code, so "holds a pin" and "holds a pin
      that can fail" are the same 17 here. `readers()` is scoped to the defining file, which is
      why a gate-scoped corpus answers the question -- the whole-tree census takes >6 minutes and
      a CI job may not.)
  F3  THE COST. `gates/edge-cost.rows`, the MEASURED cost ledger, beside this file and IN GIT.
      A candidate whose measured cost exceeds the budget is **NOT RUN** (`OVER-BUDGET`). A
      candidate with **no row is RUN** -- so a gate nobody measured yet is never silently
      skipped, and the ledger is a MEASUREMENT rather than a hand list of gates.

**WHY THE LEDGER IS IN GIT AND NOT UNDER `gates/artifacts/`.** `gates/artifacts/` is gitignored
and is where runs WRITE, so one `rm -rf gates/artifacts` deletes it and git cannot restore it. A
gate's REQUIRED INPUT belongs beside the gate in git; that is the rule `AGENTS.md` records after
`checks/sb-gate.sh` lost its fixture. The same rule is why the TRACE is written to
`gates/edge-trace.rows` and not into the artifact directory: **the trace is the answer to "was
this gate ever run?", and that answer has to survive a fresh clone.**

**THE VERDICTS ARE `gates/gatekit.py`'s, LOADED BY PATH: `PASS 0 · FAIL 1 · REFUSED 3 · SKIP 4 ·
DEAD 5`.** `SKIP IS NOT PASS` and `DEAD IS NOT A ZERO`, and the edge's own exit says which:
a gate that FAILed or DEADed charges the edge (exit 1 / exit 5); a gate that REFUSED or SKIPped
is COUNTED and does not, because "a precondition was absent" is not a finding about the tree;
and if NO gate answered at all the edge is DEAD (exit 5), because an edge that measured nothing
having exited 0 is worse than no edge, because it is trusted.

**WHAT THE EDGE DOES NOT CLAIM.** It does not cover the pins whose gate is not a candidate: the
whole-tree census finds 60 CAN-FAIL pins and the gate population holds 17 members of them. The
other 43 live in files the gate population does not reach, and this file does not pretend
otherwise. It prints the denominator.
"""
import argparse
import ast
import importlib.util
import os
import subprocess
import sys
import time
import warnings
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"

COST = HERE / "edge-cost.rows"        # the MEASURED cost ledger. In git, beside this file.
TRACE = HERE / "edge-trace.rows"      # the TRACE. In git, beside this file.

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
VERDICT = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP", DEAD: "DEAD"}
# THE SIXTH STATE IS NOT A VERDICT AND IS NOT COUNTED AS ONE. `UNASSIGNED` is a status the
# tree's vocabulary does not name -- `checks/differ.py` says so in its own source -- and the
# edge says which it is instead of folding it into REFUSED. It is COUNTED and it does not
# CHARGE, because "the tool has no such mode" is not a finding about the tree.
UNASSIGNED = "UNASSIGNED"

# THE BUDGET. Two numbers, both POLICY, both declared here rather than typed per gate.
#
# THE WALL BOUND is a third of the sweep's own default (`checks/gatesweep.py --seconds 600`),
# because the sweep's default is a per-gate bound for a HUMAN running a sweep, and this edge
# runs a SUBSET on a CI runner. MEASURED 2026-10-20: `checks/gatesweep.py` -- the gate that
# RUNS THE POPULATION -- did not finish in 30 s and was killed, and every other candidate
# finished inside 15 s.
#
# THE PEAK CEILING is NOT the sweep's default of 2048 MB, and the reason is a measurement:
# MEASURED 2026-10-20, `gates/onnx_census-gate.py` peaked at 2062 MB and
# `gates/ops_python_census-gate.py` at 2080 MB, so a 2048 MB ceiling KILLS TWO GATES THE TREE
# CAN ACTUALLY RUN -- and a ceiling that excludes gates the tree can run is not a ceiling, it is
# a filter nobody declared. 3072 MB is the next step up, and it is inside the sum-precondition
# `AGENTS.md` sets: the edge runs the gates SEQUENTIALLY, so the concurrently-running sum is ONE
# gate, and 3 GB is under 60% of this machine's 17.18 GB (`sysctl -n hw.memsize`).
BUDGET_SECONDS = 30
BUDGET_MB = 3072

# THE TREE IS PASSED IN, AND ITS NAME IS IN THE ENVIRONMENT. `gates/gatekit.py` reads it, and
# `PYTHONPATH` carries the tree's `gates/` directory so a gate COPIED OUT of the tree can still
# `import gatekit`. **THIS IS NOT "FIND THE TREE".** `gates/reporoot.py` is the tree's own
# shape for finding a root -- it walks UPWARD for a directory holding `pyproject.toml`,
# `tinybendygrad/` and `tinygrad/` -- and a copy in a temp directory has no such ancestor, so
# that shape answers `RootNotFound` for exactly the case that has to work. **A FIX THAT WORKS
# ONLY FROM THE REPO ROOT IS A FIX THAT WILL BE BROKEN BY THE NEXT COPY**, and the copy is not
# hypothetical: `gates/edge-plant.py` runs its synthetic gates in a temp directory, and
# `gates/ptx_render_census-mutate.py`'s M13 copies a gate out of the tree.
TREE_ENV = "TINYGRAD_ROOT"


def pass_the_tree_in(root):
    """Hand the tree to every gate this runner starts.

    `checks/gatesweep.py:run_one()` spawns the gate with `subprocess.run(cmd, ..., cwd=ROOT)` and
    no `env=`, so the child INHERITS this process's environment -- which is the channel, and the
    only one that does not need a copy to be in the right place. `TINYGRAD_ROOT` names the tree
    (`gates/gatekit.py` reads it for the compiler and the interpreter); `PYTHONPATH` carries the
    tree's `gates/` directory, so a gate that lives outside the tree can still find `gatekit`.

    **THE ENV IS RESTORED BY THE CALLER**, because the plant runs this inside a process that
    must not carry a fake tree into its next direction.
    """
    os.environ[TREE_ENV] = str(root)
    gates = str(root / "gates")
    parts = [p for p in os.environ.get("PYTHONPATH", "").split(os.pathsep) if p]
    if gates not in parts:
        parts.insert(0, gates)
    os.environ["PYTHONPATH"] = os.pathsep.join(parts)


def load(name, path):
    """A MODULE, LOADED BY PATH. Never imported by name: `gates/gates-pop.py` has a hyphen, and
    importing a gate RUNS it."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def modules():
    """The three instruments this file uses, each LOADED BY PATH and each owned by the tree.

    `checks/gatesweep.py` owns the population walk, the watchdog wrapper and the verdict
    classifier. `gates/pincensus-pop.py` owns the pin vocabulary. `gates/gatekit.py` owns the
    five verdicts. **THIS FILE HOLDS NO COPY OF ANY OF THE THREE**, because a second copy of a
    vocabulary is a second population with a different predicate -- one question, two answers.
    """
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        gs = load("edge_gatesweep", ROOT / "checks" / "gatesweep.py")
        pop = load("edge_pincensus_pop", HERE / "pincensus-pop.py")
        gk = load("edge_gatekit", HERE / "gatekit.py")
    return gs, pop, gk


def rel_of(path, root):
    """The path as the tree names it. `Path.relative_to` raises for a path outside the root, and
    the plant's synthetic gates live in a temp directory -- so this asks, and answers."""
    try:
        return str(Path(path).relative_to(root))
    except ValueError:
        return str(path)


def declares_red_is(path):
    """-> the gate's own `RED_IS`, read off its module body by `ast.literal_eval`.

    **THIS IS `gates/gate-surface.py`'s ESCAPE HATCH, AND THE EDGE HONOURS IT.** A gate that
    declares `RED_IS = "FINDING"` is saying, in its own source, that ITS red is its finding --
    and `gates/gate-surface.py`'s own docstring calls the alternative "a sixth verdict", which
    this tree does not have. **ABSENT MEANS "my red is about the tree"**, so a gate that says
    nothing is CHARGED, and a gate that says `FINDING` is COUNTED and not charged.

    WHY THE EDGE NEEDS IT AT ALL. MEASURED 2026-10-20: `gates/gate-surface.py` is red BY
    DESIGN and `checks/e2e.py` crashes. A gate that is red by design and a gate that is broken
    both arrive as a non-zero exit, and an edge that charges both would be permanently red --
    and *"a pre-commit gate that cannot pass teaches nothing and will be skipped"*, with the
    word "pre-commit" removed and nothing else changed. **THE ESCAPE HATCH IS THE TREE'S OWN,
    it is declared BY THE GATE, and it is the only way out.** A gate that wants out says so in
    its own source, where a reader can see it.
    """
    return _module_constant(path, "RED_IS")


def declares_edge_candidate(path):
    """-> whether the gate declares `EDGE_CANDIDATE = True` in its own source.

    **A GATE THAT COVERS ANOTHER GATE'S PIN HOLDS NO PIN OF ITS OWN, AND THE EDGE'S
    SELECTION RULE WOULD NOT SEE IT.** `gates/edge-oracle-pin-gate.py` compares the subjects
    of OTHER gates' pins -- the ones whose subject lives in the pruned tree -- and holds no
    pin itself, so the rule "a member that holds a pin its own code reads" does not select
    it. The gate says so in its own source, where a reader can see it, and the edge reads it
    by the same AST pass that reads `RED_IS`."""
    value = _module_constant(path, "EDGE_CANDIDATE")
    return value is True


def _module_constant(path, name):
    """-> the value of a module-level constant, read off the module body by `ast.literal_eval`,
    or None when the module does not declare it (or does not parse)."""
    try:
        tree = ast.parse(Path(path).read_text(errors="replace"))
    except (OSError, SyntaxError, ValueError):
        return None
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                and isinstance(node.targets[0], ast.Name) and node.targets[0].id == name:
            try:
                return ast.literal_eval(node.value)
            except (ValueError, SyntaxError):
                return None
    return None


def covers_of(path):
    """-> the paths whose pins this gate compares, read by CALLING its own `edge_covers()`.

    **THE GATE SAYS WHAT IT COVERS, IN ITS OWN SOURCE, AND THE EDGE ASKS.** A candidate that
    compares another gate's pins may name the gates it covers, and the edge asks it rather
    than keeping a list of its own -- a list of its own would be a second population with a
    different predicate, which is the defect this whole file exists to avoid."""
    try:
        mod = load("edge_covers_" + Path(path).stem, Path(path))
    except Exception:                                            # noqa: BLE001 - a gate that
        return []                                                 # cannot be loaded covers nothing
    fn = getattr(mod, "edge_covers", None)
    if not callable(fn):
        return []
    try:
        return [str(x) for x in fn()]
    except Exception:                                            # noqa: BLE001
        return []


# ---------------------------------------------------------------------------------------------
# F2: THE PIN. A member is a CANDIDATE iff its own source holds a pin its own code reads.
def candidates(gs, popmod, root=ROOT):
    """-> (members, {member path -> [(pin name, [readers])]}) for the members holding a CAN-FAIL pin.

    **THE CORPUS IS THE GATE POPULATION, NOT THE TREE.** `gates/pincensus-pop.py:load()` walks
    every tracked file in the tree -- MEASURED 2026-10-20, the whole-tree census takes MORE THAN
    SIX MINUTES, so a CI job cannot run it. The gate-scoped corpus answers the same question
    because `readers()` is SCOPED TO THE FILE THAT DEFINES THE CONSTANT: the lexical arm (the
    same file reads its own name) is the arm that decides, and `gates/pincensus-pop.py`'s own
    docstring says so -- *"this tree's constants are nearly all file-local and the lexical arm is
    the one that decides"*. The import arm is kept, and it is kept OVER THE SAME CORPUS, so a
    pin read by an import from OUTSIDE the gate population is not counted here. **THAT IS A
    MEASURED LIMITATION AND IT IS STATED RATHER THAN HIDDEN**: the whole-tree census counts
    those, and `gates/pincensus-gate.py` is the instrument for that question.
    """
    members = gs.population(root)
    corpus, host = {}, {}
    for path, _reason in members:
        try:
            corpus[rel_of(path, root)] = path.read_text(errors="replace")
        except (OSError, ValueError):
            continue
    for rel, text in corpus.items():
        host[rel] = popmod.host_of(text)
    code = {t: popmod.code_lines(corpus[t], host[t]) for t in corpus if host[t] != "prose"}
    out = {}
    for site in popmod.rule_a(corpus, host):
        if site["host"] == "prose":
            continue
        read = popmod.readers(site["name"], code, (site["file"], site["line"], site["end"]))
        if read:
            out.setdefault(site["file"], []).append((site["name"], read))
    # A GATE THAT COVERS ANOTHER GATE'S PIN IS A CANDIDATE EVEN THOUGH IT HOLDS NO PIN.
    for rel in corpus:
        if rel in out:
            continue
        if declares_edge_candidate(ROOT / rel):
            out.setdefault(rel, []).append(("EDGE_CANDIDATE", []))
    return members, out


# ---------------------------------------------------------------------------------------------
# THE LEDGER AND THE TRACE. Two files, two jobs, both IN GIT beside this file.
LEDGER_COLUMNS = ["gate", "seconds", "peak-mb", "verdict", "token", "measured-at"]
TRACE_COLUMNS = ["gate", "status", "verdict", "token", "rc", "seconds", "peak-mb", "measured-at"]


def read_rows(path):
    """-> {first column: [fields]} for a generated `.rows` file. A MISSING file is `{}`, and a
    missing ledger is not an error: it means nothing has been measured yet, and the edge runs
    what it has not measured rather than skipping it.

    **THE COLUMN NAMES LIVE IN THE `#` HEADER AND NOT IN A LINE OF THEIR OWN**, and that is a
    FIX, not a style. MEASURED 2026-10-20: with the column line written as data, this reader
    parsed it as a row whose key was the literal string `gate`, and the edge's plan then
    reported `STALE gate` -- a gate that does not exist, named by the file's own vocabulary.
    The house style agrees: `gates/crp_graph_census-pins.rows` puts its column names in the
    `#` header and writes no column line at all.
    """
    if not path.is_file():
        return {}
    out = {}
    for line in path.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        f = line.split("\t")
        if f:
            out[f[0]] = f
    return out


def write_rows(path, columns, rows, header, root=ROOT):
    """Write a generated `.rows` file. The header names the generator and the columns, because a
    file whose own writer it does not name is a file a reader cannot check."""
    path.parent.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with path.open("w") as fh:
        fh.write(f"# {header}\n")
        fh.write(f"# columns: {', '.join(columns)}\n")
        fh.write(f"# written {stamp} HEAD={git_head(root)}\n")
        for r in rows:
            fh.write("\t".join(str(x).replace("\t", " ") for x in r) + "\n")
    return stamp


def git_head(root=ROOT):
    r = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=str(root),
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else "unknown"


# ---------------------------------------------------------------------------------------------
# THE RUN. One gate, under the tree's own watchdog, and the watchdog's TOKEN is the verdict.
def consumed_lanes(gs, root=ROOT):
    """-> the lane filenames some `Gate` names. `checks/gatesweep.py:gate_names()` reads it off
    the AST of the walk the sweep already holds -- it is a full AST pass, so it is computed ONCE
    per run rather than once per gate."""
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        return gs.gate_names(gs.population(root))


def run_one(gs, gate, reason, seconds, mb, consumed=frozenset()):
    """-> (verdict, token, rc, seconds, peak-mb). `checks/gatesweep.py:run_one()` is the tree's
    own wrapper around `checks/bounded.py`, and its classifier maps the watchdog's 3/4/5 onto
    `gates/gatekit.py`'s five -- **THE TOKEN, NEVER THE EXIT CODE**, because a unit in this tree
    lost 425 rows by believing the status."""
    return gs.run_one(gate, reason, seconds, mb, consumed)


def measure(members, cands, gs, seconds, mb, root=ROOT):
    """Measure the cost of every CANDIDATE and return the ledger rows. **THIS IS THE ONLY
    WRITER OF `gates/edge-cost.rows`.** Each candidate runs ONCE, under the watchdog, and the
    wall clock and the peak are what it cost."""
    consumed = consumed_lanes(gs, root)
    rows = []
    for path, reason in members:
        rel = rel_of(path, root)
        if rel not in cands:
            continue
        verdict, token, rc, took, peak = run_one(gs, path, reason, seconds, mb, consumed)
        rows.append([rel, f"{took:.2f}", peak, verdict, token,
                     time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())])
    return rows


def select(cands, ledger, seconds):
    """-> (selected, skipped). A candidate is SELECTED iff the ledger has no row for it (nothing
    measured yet -- run it and find out) or its measured wall clock fits the budget.

    **THE BUDGET IS THE WHOLE OF THE EXCLUSION, AND IT IS A MEASUREMENT, NOT A SPELLING.**
    MEASURED 2026-10-20: of the 17 candidates, `checks/e2e.py` and `checks/gatesweep.py` cost
    more than 30 s -- they RUN THE POPULATION, so an edge that ran them would be an edge running
    itself -- and the other 15 cost 126.15 s in total. **THE EDGE PRINTS BOTH NUMBERS**, so the
    exclusion is visible on the trace rather than implied by an absence.
    """
    selected, skipped = [], []
    for rel in sorted(cands):
        row = ledger.get(rel)
        if row is None:
            selected.append(rel)
            continue
        try:
            cost = float(row[1])
        except (IndexError, ValueError):
            selected.append(rel)
            continue
        (selected if cost <= seconds else skipped).append(rel)
    return selected, skipped


def trace_rows(members, cands, selected, ledger, gs, seconds, mb, root=ROOT):
    """Run the SELECTED candidates and build the trace rows. **THE LEDGER IS NOT REWRITTEN
    HERE** -- the trace records what this run cost, and `--measure` owns the ledger. A cost that
    moved is visible as a difference between the two files."""
    consumed = consumed_lanes(gs, root)
    by_rel = {rel_of(p, root): (p, r) for p, r in members}
    rows = []
    for rel in sorted(cands):
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        if rel not in selected:
            row = ledger.get(rel) or []
            cost = row[1] if len(row) > 1 else "?"
            rows.append([rel, "OVER-BUDGET", "SKIP", f"MEASURED-{cost}s", "", "", "", stamp])
            continue
        path, reason = by_rel[rel]
        verdict, token, rc, took, peak = run_one(gs, path, reason, seconds, mb, consumed)
        if token.startswith("UNASSIGNED"):
            # **A STATUS NO VOCABULARY NAMES IS NOT A PRECONDITION THAT WAS ABSENT.** The
            # tree's five are PASS 0, FAIL 1, REFUSED 3, SKIP 4, DEAD 5, and `checks/differ.py`
            # says so in its own source: "argparse would exit 2 on a name that is not a plant,
            # and 2 IS A CODE NO VOCABULARY NAMES". MEASURED 2026-10-20: bare `differ.py`
            # exits 2 because it has NO BARE MODE -- it is a mode selector with four -- and
            # the edge's classifier folded that usage error into REFUSED, which means "a
            # precondition was absent". **THOSE ARE DIFFERENT THINGS**, and folding them is
            # how "the tool has no such mode" reads as "the tree is not ready". It is
            # COUNTED and it does not CHARGE, and it says which it is.
            status, verdict = "RAN-UNASSIGNED", "UNASSIGNED"
        else:
            status, verdict = "RAN", verdict
        finding = declares_red_is(path) == "FINDING" and verdict in ("FAIL", "DEAD")
        rows.append([rel, "RAN-FINDING" if finding else status, verdict, token, rc,
                     f"{took:.2f}", peak, stamp])
    return rows


def tally(rows):
    """-> (counts by verdict, denominator). The denominator is printed beside the tally ALWAYS:
    a verdict with no denominator is a claim nobody can check."""
    counts = {v: 0 for v in (*VERDICT.values(), UNASSIGNED)}
    for r in rows:
        if r[1] in ("RAN", "RAN-FINDING", "RAN-UNASSIGNED"):
            counts[r[2]] = counts.get(r[2], 0) + 1
    return counts, sum(counts.values())


def edge_verdict(rows):
    """The edge's OWN exit, from `gates/gatekit.py`'s five.

    **A GATE THAT REFUSED OR SKIPPED IS COUNTED AND DOES NOT CHARGE**, because "a precondition
    was absent" is not a finding about the tree. A gate that FAILed or DEADed DOES charge --
    because both are the gate having run and NOT agreed -- **UNLESS THE GATE DECLARED
    `RED_IS = "FINDING"`**, which is the tree's own escape hatch and is read from the gate's own
    source (`declares_red_is()` above).

    **AND AN EDGE THAT MEASURED NOTHING IS DEAD, NEVER PASS.** A gate that exits 0 having
    measured nothing is worse than no gate, because it is trusted.
    """
    counts, denom = tally(rows)
    charged = [r for r in rows if r[1] == "RAN" and r[2] in ("FAIL", "DEAD")]
    if denom == 0:
        return DEAD, counts
    if any(r[2] == "DEAD" for r in charged):
        return DEAD, counts
    if any(r[2] == "FAIL" for r in charged):
        return FAIL, counts
    return PASS, counts


def coverage(members, cands, root=ROOT):
    """-> (population_sites, outside_hosts) -- the COVERAGE of the CAN-FAIL pin sites, with
    its denominator.

    **THE DENOMINATOR IS THE POPULATION'S OWN SITES, AND THE GAP IS NAMED SEPARATELY.**
    The whole-tree census -- the one that finds the pins in files the gate population does
    not reach -- takes MORE THAN SIX MINUTES, so an edge that plans a run in seconds cannot
    compute it, and a denominator nobody can compute is a denominator nobody can check. So
    the edge prints the population's own coverage with its denominator, and it prints the
    hosts OUTSIDE the population whose pins a candidate compares -- which is the part of
    the gap the edge can reach. **THE COUNTING OF THOSE OUTSIDE SITES IS THE COVERING
    GATE'S OWN LEDGER, not this file's, and the ledger says so on its header.**

    **A CANDIDATE MAY COVER ANOTHER GATE'S PINS, AND IT SAYS SO IN ITS OWN SOURCE**
    (`edge_covers()`, read by path). A pin whose host is such a gate is COVERED even though
    the host is not a candidate itself, and that is how the edge reaches the copies of
    `checks/differ.py` that live under the pruned tree.
    """
    hosts = set(cands)
    outside = set()
    for rel in cands:
        for covered in covers_of(root / rel):
            if covered not in hosts:
                hosts.add(covered)
                outside.add(covered)
    return sum(len(v) for v in cands.values()), sorted(outside)


def plan_coverage_line(members, cands, root=ROOT):
    """-> the ONE line the edge prints about coverage, with its denominator."""
    sites, outside = coverage(members, cands, root)
    return (f"  COVERAGE    {sites} of {sites} CAN-FAIL pin site(s) in the gate population are "
            f"held by a candidate;\n              {len(outside)} host(s) OUTSIDE the population have "
            f"their pins compared by a candidate: "
            + (", ".join(outside) if outside else "-"))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--root", default=str(ROOT), help="the tree to select in")
    ap.add_argument("--trace", default=str(TRACE), help="where the trace is written")
    ap.add_argument("--cost", default=str(COST), help="the cost ledger")
    ap.add_argument("--seconds", type=int, default=BUDGET_SECONDS)
    ap.add_argument("--mb", type=int, default=BUDGET_MB)
    ap.add_argument("--plan", action="store_true", help="print the selection, run nothing")
    ap.add_argument("--measure", action="store_true", help="(re)measure the cost ledger")
    ap.add_argument("--plant", action="store_true", help="the plant and its control")
    a = ap.parse_args()

    if a.plant:
        plant = load("edge_plant", HERE / "edge-plant.py")
        return plant.plants()

    gs, popmod, gk = modules()
    root = Path(a.root).resolve()
    pass_the_tree_in(root)
    members, cands = candidates(gs, popmod, root)
    ledger = read_rows(Path(a.cost))

    if a.plan:
        selected, skipped = select(cands, ledger, a.seconds)
        print(f"EDGE: population {len(members)}   candidates (hold a CAN-FAIL pin, or declare "
              f"EDGE_CANDIDATE) {len(cands)}")
        print(plan_coverage_line(members, cands, root))
        print(f"  selected {len(selected)}   over-budget {len(skipped)}   budget "
              f"{a.seconds}s / {a.mb} MB")
        for rel in selected:
            row = ledger.get(rel)
            cost = row[1] if row else "NOT-MEASURED"
            print(f"    RUN  {rel:46} cost={cost}")
        for rel in skipped:
            row = ledger.get(rel)
            print(f"    SKIP {rel:46} cost={row[1] if row else '?'}s (over budget)")
        stale = sorted(set(ledger) - set(cands))
        if stale:
            print(f"  ledger rows for gates that are NOT candidates (the ledger and the live "
                  f"population disagree, and it is said here): {len(stale)}")
            for rel in stale:
                print(f"    STALE {rel}")
        return PASS

    if a.measure:
        rows = measure(members, cands, gs, a.seconds, a.mb, root)
        stamp = write_rows(Path(a.cost), LEDGER_COLUMNS, rows,
                           "gates/edge-cost.rows -- TAB separated. Generated; the generator is "
                           "`gates/edge-runner.py --measure`, the ONLY writer.", root)
        total = sum(float(r[1]) for r in rows)
        peak = max((int(r[2]) for r in rows if r[2].isdigit()), default=0)
        print(f"EDGE-COST: measured {len(rows)} candidate(s) at {stamp}; "
              f"{total:.2f}s of wall clock, peak {peak} MB")
        for r in rows:
            print(f"  {r[3]:8} {r[4]:16} {r[1]:>8}s {r[2]:>6} MB  {r[0]}")
        return PASS

    selected, skipped = select(cands, ledger, a.seconds)
    rows = trace_rows(members, cands, selected, ledger, gs, a.seconds, a.mb, root)
    stamp = write_rows(Path(a.trace), TRACE_COLUMNS, rows,
                       "gates/edge-trace.rows -- TAB separated. Generated; the generator is "
                       "`gates/edge-runner.py`. THE TRACE: it says which gates RAN and what they "
                       "said, and it is IN GIT so the answer survives a fresh clone.", root)
    rc, counts = edge_verdict(rows)
    denom = sum(counts.values())
    print("EDGE: a committed surface that runs the gates and leaves a trace")
    print(f"  population {len(members)}   candidates {len(cands)}   selected {len(selected)}   "
          f"over-budget {len(skipped)}")
    print(plan_coverage_line(members, cands, root))
    print(f"  trace written {stamp} -> {Path(a.trace)}")
    print(f"  TALLY (of {denom} that ran): " +
          "  ".join(f"{k} {counts.get(k, 0)}" for k in
                   ("PASS", "FAIL", "REFUSED", "SKIP", "DEAD", UNASSIGNED)))
    for r in rows:
        print(f"    {r[1]:12} {r[2]:8} {r[3]:22} {r[5] or '-':>8}s {r[6] or '-':>6}MB  {r[0]}")
    print("  THE EDGE CANNOT make a pin go red by itself. It makes a RUN leave a trace.")
    if rc == DEAD:
        print("EDGE: DEAD -- nothing answered, or a gate ran and emitted nothing", file=sys.stderr)
    elif rc == FAIL:
        print("EDGE: FAIL -- a gate ran and disagreed", file=sys.stderr)
    return rc


if __name__ == "__main__":
    sys.exit(main())
