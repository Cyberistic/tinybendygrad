#!/usr/bin/env python3
"""THREE PLANTS FOR `.agents/slop/graphcmp-oracle.py`, one per defect fixed in it.

EACH PLANT MUST BE ABLE TO MOVE, and each must be shown FAILING on the planted state before
it is shown PASSING on the fixed one -- in that ORDER, because the order is the proof. **A PLANT
THAT CANNOT MOVE IS A PLANT THAT PASSES**: the repros in this project's history read
`LEFT=NOTHING` on both sides because they `rmtree`'d the state under test between beats, so
they proved nothing twice. So every beat here names a BEFORE and an AFTER and requires them to
DIFFER, or names a before/after pair and requires them to be EQUAL *and* requires a third
measurement that says the quantity is not vacuous.

  PLANT 1  THE DEVICE -- and it is the plant that CHANGES THE DEVICE, because two of the three
           defects are device-dependent and a plant that only permutes bytes cannot see that.
           It moves four times:
             (a) the py-side corpus really is device-dependent (MEASURED: 313 nodes on NULL,
                 312 on CPU, 311 on METAL, and `late` is RECIPROCAL on one and FDIV on
                 another) -- so a census that does not NAME its device is unauditable, and the
                 non-vacuity half of this plant is that this quantity MOVES;
             (b) the census's device is graphcmp.py's OWN `--dev` default, read from its AST,
                 and it FOLLOWS a change to that default (proved on a TEMP COPY -- the real
                 graphcmp.py is never edited);
             (c) the census is IMMUNE to the ambient `DEV`: `differ.py:47` sets `DEV=NULL` for
                 every step, and that must no longer move any number here;
             (d) the device PRECONDITION FIRES: patch the bend side onto a different device and
                 `main()` must REFUSE with rc=1 and name both sets. The guard that catches this
                 lives in `graphcmp.py`'s `_dispatch`, which this file cannot reach, so a beat
                 that never showed the refusal firing is a guard that has never been tested.

  PLANT 2  THE DEVICE SPELLING -- direct calls to `atoms()`, NO TEXT MATCHING ANYWHERE IN IT.
           `al(`'s second field is EITHER a bare name `sCPU` OR a tuple `n(sCPU,sCPU)`, and the
           census must read both without inventing an atom. So `al(OADD,n(sCPU,sCPU))` must
           yield `Oas` -- the tuple opener `n` is NOT an atom -- while a BARE `al(OADD,CPU)`
           must STILL report `C`, which separates a scan that reads the grammar from one that
           stopped looking. The beat that proves DEFECT 28's form rule is GONE is the last: the
           FLATTENED `al(OADD,sCPU,CPU)` ADEV-1 abolished must now LEAK its `C`, i.e. be
           REJECTED rather than silently accepted.

  PLANT 3  THE HASH ORDER -- five `PYTHONHASHSEED` values over `main()`'s real
           `PY-BEND OPs DIFFER` row, which must come back as ONE rendering. Before the sort the
           same driver produced five distinct renderings of one fact, and `differ.py repro`
           reported `D0-coverage-census.txt: 2 runs DIFFER` on 1 of 196 files -- a lane that can
           never be green, and one that cannot be made green by a more correct port.

NO TWO PLANTS SHARE AN ASSERTION MECHANISM, because a belt whose two halves share an assumption
is one assumption. PLANT 1 reads a `# DEV=` line and an exit code; PLANT 2 compares returned
SETS and never looks at a character of text; PLANT 3 greps a `PY-BEND OPs DIFFER:` line. The
tokenizers are three and the needles are three and no plant can pass another's evidence.

  usage: .venv/bin/python .agents/slop/selfcheck/plants.py
"""
from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
PY = ROOT / ".venv/bin/python"
ORACLE = pathlib.Path(os.environ.get("ORACLE_UNDER_TEST")
                      or ROOT / ".agents/slop/graphcmp-oracle.py")
SELF = pathlib.Path(__file__).resolve()
SEEDS = ("0", "1", "2", "3", "4")

# THE INTERNAL MODE. `--row` drives the oracle's REAL `main()` with the bend side replaced by a
# synthetic one, so a plant can reach a print in `main()` without running `bend` 25 times and
# so it can put the two sides on DIFFERENT devices on purpose. `--bend-dev` retags the synthetic
# bend rows' device; `--retag` replaces their op column outright, which is what makes the
# symmetric difference non-empty and therefore what makes the hash-order row print at all.
BEND_ARG = re.compile(r"(?<=,)(s)[A-Z]+(?=,)")

# PLANT 2's OLD FOURTH BEAT WAS TAUTOLOGICAL AND IT IS RECORDED BECAUSE IT IS THE CLASS THIS
# WHOLE TASK IS ABOUT: it asserted `atoms(x) == {"n","s"} | atoms(x)`, which is `x == x` for
# every `x`, so it could not fail and had never been tested. The measured truth it was reaching
# for is different from the one it claimed: `n(` is a TUPLE OPENER, not an atom, and the scan
# requires a letter to be followed by an alnum or the end of the string, so `n` is never counted
# -- identically on both sides. The beat below asserts the thing that is actually true.

# `graphcmp` ALWAYS comes from the real slop dir: `ORACLE_UNDER_TEST` names the file under
# test and nothing else, so pointing the plants at a pre-fix COPY (jj: `jj file show -r @-`) has
# to test that copy's oracle against the SAME generator, not against a second graphcmp.
sys.path.insert(0, str(ROOT / ".agents/slop"))
import graphcmp as G  # noqa: E402


def load_oracle():
    spec = importlib.util.spec_from_file_location("census", ORACLE)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def retag(rows: list[str], op: str) -> list[str]:
    """The same rows with field 1 replaced. Keeps every other field -- and so the device names,
    the shapes and the ledger positions -- byte-for-byte, so a plant that wants the two sides to
    DISAGREE about ops is not accidentally making them disagree about anything else."""
    return _rewrite(rows, {1: op})


def redevice(rows: list[str], dev: str) -> list[str]:
    """The same rows with the DEVICE renamed inside their `arg` column. Through
    `G.unchunks`/`G.chunk` and NOT a `str.replace` over the line: MEASURED, substituting into
    the joined wire text changes a chunk's byte count and `unchunks` then walks off the end of
    the count field and dies with `invalid literal for int() with base 10: 'N) 3'`."""
    out = []
    for ln in rows:
        f = G.unchunks(ln)
        f[6] = re.sub(r"(?<=,)(s)[A-Z]+(?=,)", lambda m: m.group(1) + dev, f[6])
        out.append(" ".join(G.chunk(x) for x in f))
    return out


def _rewrite(rows: list[str], fields: dict[int, str]) -> list[str]:
    out = []
    for ln in rows:
        f = G.unchunks(ln)
        for i, v in fields.items():
            f[i] = v
        out.append(" ".join(G.chunk(x) for x in f))
    return out


def run_row(dev_env: str | None, bend_dev: str | None, retag_to: str | None) -> tuple[int, str]:
    """`main()`'s exit code and its whole stdout, with `emit_bend` replaced. Run in THIS
    process, so `PYTHONHASHSEED` has to come from the environment the caller was born with --
    which is why PLANT 3 shells out rather than calling this in a loop.

    NOTHING IS IMPORTED HERE BEFORE `main()` RUNS. MEASURED, the reason is not tidiness:
    `tinygrad.Device.DEFAULT` is frozen at import, so a caller that calls `load_tinygrad()`
    first pins the census to the ambient device while `main()` prints `--dev`'s -- the exact
    split the device fix exists to close, reintroduced from the other direction. `main()`
    refuses that ordering, and these plants exercise the refusal rather than working around it.
    """
    o = load_oracle()
    real_py = o.G.emit_py
    state: dict[str, str | None] = {"dev": None, "retag": None}

    def fake_bend(dev, graph, tries=5, probe=None):
        rows = real_py(graph, None)
        out = retag(rows, state["retag"]) if state["retag"] else list(rows)
        if state["dev"]:
            out = redevice(out, state["dev"])
        return out, []

    o.G.emit_bend = fake_bend
    if dev_env is not None:
        os.environ["DEV"] = dev_env
    state["dev"] = bend_dev
    state["retag"] = retag_to
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            rc = o.main()
    finally:
        o.G.emit_bend = G.emit_bend
    return rc, buf.getvalue()


def child(args: list[str], env_extra: dict[str, str]) -> tuple[int, str]:
    e = {k: v for k, v in os.environ.items() if k not in ("DEV", "PYTHONHASHSEED")}
    e.update(env_extra)
    r = subprocess.run([str(PY), str(SELF), *args], cwd=ROOT, env=e,
                       capture_output=True, text=True, timeout=600)
    return r.returncode, r.stdout + r.stderr


def line_with(text: str, prefix: str) -> str:
    hits = [ln for ln in text.splitlines() if ln.startswith(prefix)]
    return hits[0] if hits else ""


def report(name: str, ok: bool, detail: str) -> bool:
    print(f"  {'PASS' if ok else 'FAIL'}  {name}\n        {detail}")
    return ok


def py_side_total(dev: str) -> tuple[int, str]:
    """`(py-side node count, the ops of `late`)` under ONE device, in a child process, because a
    device is resolved at import and two devices cannot be live in one interpreter."""
    script = (
      "import os,sys;sys.path.insert(0,%r)\n"
      "import graphcmp as G\nG.load_tinygrad()\n"
      "t=0\n"
      "for g in sorted(G.GRAPHS):\n"
      "    rows=G.emit_py(g,None)\n"
      "    t+=len(rows)\n"
      "print('TOTAL=%%d late=%%s' %% (t, ','.join(sorted({G.unchunks(l)[1] for l in G.emit_py('late',None)}))))\n"
      % str(ROOT / ".agents/slop"))
    r = subprocess.run([str(PY), "-c", script], cwd=ROOT,
                       env={k: v for k, v in os.environ.items() if k != "DEV"} | {"DEV": dev},
                       capture_output=True, text=True, timeout=600)
    return int(re.search(r"TOTAL=(\d+)", r.stdout).group(1)), \
        re.search(r"late=(\S*)", r.stdout).group(1)


def plant1() -> bool:
    """THE DEVICE, changed four times."""
    print("\nPLANT 1 -- THE DEVICE (beat a: does the corpus really depend on it?)")
    checks = []
    n_null, ops_null = py_side_total("NULL")
    n_cpu, ops_cpu = py_side_total("CPU")
    n_metal, _ = py_side_total("METAL")
    moved = len({n_null, n_cpu, n_metal})
    checks.append(report("plant1a: the py-side corpus MOVES with the device, so a census that "
                         "does not NAME its device is unauditable",
                         moved == 3, f"NULL={n_null} CPU={n_cpu} METAL={n_metal} nodes"))
    checks.append(report("plant1a: `late` is not merely a different SIZE on the other device, it "
                         "is a different GRAPH",
                         ("RECIPROCAL" in ops_null) != ("RECIPROCAL" in ops_cpu),
                         f"NULL has RECIPROCAL={('RECIPROCAL' in ops_null)}, "
                         f"CPU has RECIPROCAL={('RECIPROCAL' in ops_cpu)}"))

    print("\nPLANT 1 -- THE DEVICE (beat b: does the census follow graphcmp's OWN default?)")
    o = load_oracle()
    # A PLANT THAT CANNOT BE ASKED IS A PLANT THAT CANNOT PASS. MEASURED, the first attempt at
    # this beat raised `AttributeError: module 'census' has no attribute 'graphcmp_dev'` on the
    # PRE-FIX file and took the whole run down with it -- which is the shape the brief names,
    # "a gate that stops reporting the moment it cannot answer one question". The absence of the
    # symbol IS the finding, so it is reported as one.
    if not hasattr(o, "graphcmp_dev"):
        checks.append(report("plant1b: the census reads graphcmp.py's OWN `--dev` default",
                             False, "NO `graphcmp_dev()` in the file under test -- the pre-fix "
                                    "oracle calls `os.environ.setdefault(\"DEV\", \"CPU\")`, a "
                                    "no-op whenever the caller set DEV, which differ.py always "
                                    "does"))
        checks.append(report("plant1b: and it FOLLOWS a change to that default", False,
                             "not measurable: there is nothing to follow a change with"))
    else:
        real_slop, real_dev = G.SLOP, o.graphcmp_dev()
        with tempfile.TemporaryDirectory() as td:
            mutated = pathlib.Path(td) / "graphcmp.py"
            mutated.write_text(real_slop.joinpath("graphcmp.py").read_text().replace(
                'ap.add_argument("--dev", default="CPU",',
                'ap.add_argument("--dev", default="ZZTOP",'))
            try:
                G.SLOP = pathlib.Path(td)
                drifted = o.graphcmp_dev()
            finally:
                G.SLOP = real_slop
        checks.append(report("plant1b: the census's device IS graphcmp.py's `--dev` default",
                             real_dev == "CPU", f"read from the AST: {real_dev!r}"))
        checks.append(report("plant1b: and it FOLLOWS a change to that default, so it is a "
                             "reading and not a third literal (real graphcmp.py never touched)",
                             drifted == "ZZTOP" and real_dev == "CPU",
                             f"mutated temp copy -> {drifted!r}; the real file still -> "
                             f"{real_dev!r}"))

    print("\nPLANT 1 -- THE DEVICE (beat c: is the census immune to the ambient DEV?)")
    rc_n, out_n = child(["--row"], {"DEV": "NULL"})
    rc_m, out_m = child(["--row"], {"DEV": "METAL"})
    rc_u, out_u = child(["--row"], {})
    devlines = {line_with(out_n, "# DEV="), line_with(out_m, "# DEV="), line_with(out_u, "# DEV=")}
    tot_n = line_with(out_n, "# TOTAL:")
    checks.append(report("plant1c: three DIFFERENT ambient DEV values all census on the SAME "
                         "device, and it is graphcmp.py's",
                         len(devlines) == 1 and line_with(out_n, "# DEV=").startswith("# DEV=CPU")
                         and (rc_n, rc_u, rc_m) == (0, 0, 0),
                         f"ambient NULL/METAL/unset -> {sorted({l.split(' --')[0] for l in devlines})}"))
    checks.append(report("plant1c: and the node TOTAL is the CPU one (312), NOT the NULL one "
                         f"({n_null}) that differ.py's ENV would have produced",
                         f"{n_cpu} nodes per side" in tot_n,
                         tot_n.strip()[:88]))

    print("\nPLANT 1 -- THE DEVICE (beat d: does the precondition FIRE?)")
    # THE CONTROL BEAT FIRST, AND IT IS THE POINT. The pre-fix file returns rc=1 on this corpus
    # for an UNRELATED reason (`unmapped arg atom letters: C`), so a beat that asserted only
    # "rc=1 after planting a second device" would PASS on the broken file for the wrong reason --
    # the same class as the gate that reported `DID NOT REFUSE` for a correct refusal. So the
    # plant is a PAIR: the identical command with the bend side left ALONE must return 0, and
    # only the planted one may return 1. A refusal that cannot be told from a coincidence is
    # not a refusal.
    rc_ok, out_ok = child(["--row"], {"DEV": "CPU"})
    rc_bad, out_bad = child(["--row", "--bend-dev", "METAL"], {"DEV": "CPU"})
    checks.append(report("plant1d CONTROL: the same command with the bend side ALONE is clean, "
                         "so the rc=1 below is the device and not something else",
                         rc_ok == 0 and "DIFFERENT devices" not in out_ok,
                         f"rc={rc_ok}"))
    checks.append(report("plant1d: two sides on DIFFERENT devices are REFUSED, rc=1",
                         rc_bad == 1 and rc_ok == 0, f"planted rc={rc_bad}, control rc={rc_ok}"))
    checks.append(report("plant1d: and the refusal NAMES both device sets and says why",
                         "sCPU" in out_bad and "sMETAL" in out_bad
                         and "DIFFERENT devices" in out_bad,
                         [ln.strip() for ln in out_bad.splitlines() if "DIFFERENT devices" in ln][:1]))
    return all(checks)


def plant2() -> bool:
    """THE DEVICE SPELLING. No text matching: this plant compares RETURNED SETS."""
    print("\nPLANT 2 -- THE DEVICE SPELLING (returned sets only; this plant matches no text)")
    o = load_oracle()
    checks = []
    two = o.atoms("al(OADD,n(sCPU,sCPU))")
    four = o.atoms("al(OADD,n(sCPU,sCPU,sMETAL,sMETAL))")
    bare = o.atoms("al(OADD,CPU)")
    flat = o.atoms("al(OADD,sCPU,CPU)")
    checks.append(report("plant2: the field-wise device tuple yields the form prefix, the op "
                         "atom and `s` -- and the tuple opener `n` is NOT an atom",
                         two == {"a", "O", "s"} and "n" not in two,
                         f"al(OADD,n(sCPU,sCPU)) -> {sorted(two)}; "
                         f"`n` counted={('n' in two)}"))
    checks.append(report("plant2: a 4-element device tuple behaves the SAME, so nothing here is "
                         "a two-element special case",
                         four == {"a", "O", "s"}, f"al(OADD,n(sCPU,sCPU,sMETAL,sMETAL)) -> "
                         f"{sorted(four)}"))
    checks.append(report("plant2: A BARE device name is STILL an unmapped atom -- the beat that "
                         "separates a scan that reads the grammar from one that stopped looking",
                         "C" in bare and bare != two, f"al(OADD,CPU) -> {sorted(bare)}"))
    checks.append(report("plant2: and the FLATTENED spelling ADEV-1 abolished is now REJECTED "
                         "(its `C` leaks, i.e. the census refuses it) rather than silently "
                         "accepted -- the whole point of deleting the form rule",
                         "C" in flat and flat != {"a", "O", "s"},
                         f"al(OADD,sCPU,CPU) -> {sorted(flat)}"))
    param = "P(i0,Df32,i8,N,N,sp0,SGLOBAL,sCPU,b0,N,N,b0,N)"
    checks.append(report("plant2: a plain ParamArg scan is unchanged and PRECISE, not a "
                         "passthrough comparison with itself",
                         o.atoms(param) == {"i", "D", "s", "S", "b"},
                         f"P(...) -> {sorted(o.atoms(param))}"))
    checks.append(report("plant2: `C` is NOT in ATOMS, which is what makes the flattened leak a "
                         "LEAK and not a second spelling of a real atom",
                         "C" not in set(G.ATOMS.values()) and two == {"a", "O", "s"},
                         f"ATOMS values = {''.join(sorted(set(G.ATOMS.values())))} "
                         f"(no `C`: {'C' not in set(G.ATOMS.values())}); "
                         f"al(OADD,n(sCPU,sCPU)) -> {sorted(two)}"))
    return all(checks)


def plant3() -> bool:
    """THE HASH ORDER. Five seeds, one rendering."""
    print("\nPLANT 3 -- THE HASH ORDER (five PYTHONHASHSEED values, one rendering)")
    checks = []
    rows, ops = {}, {}
    for seed in SEEDS:
        rc, out = child(["--row", "--retag", "ALLREDUCE"], {"PYTHONHASHSEED": seed})
        row = line_with(out, "  allred ")
        rows[seed] = row[row.find("PY-BEND"):] if "PY-BEND" in row else ""
        ops[seed] = diff_ops(rows[seed])
    seen = {r for r in rows.values() if r}
    checks.append(report("plant3: all five seeds printed a `PY-BEND OPs DIFFER` row at all -- "
                         "the symmetric difference is 6 ops wide, which is what makes a set "
                         "print's order visible at all",
                         len(seen) == 1 and all(rows[s] for s in SEEDS) and
                         len(next(iter(ops.values()))) == 6,
                         f"{len(seen)} distinct rendering(s) of {len(next(iter(ops.values())))} "
                         f"ops over {len(SEEDS)} seeds"))
    o = next(iter(ops.values()))
    checks.append(report("plant3: the ONE rendering is in ASCENDING order, which a set literal "
                         "is not under a randomised string hash",
                         o == sorted(o), f"{o}"))
    # THE THIRD BEAT IS THE ONE THAT SEPARATES A SORT FROM A PIN. A pin is a seed and a sort is
    # a law: on a seed that HAPPENS to agree with `sorted`, an unsorted set print is
    # indistinguishable from a sorted one, so "one seed agreed" is not evidence of anything. The
    # evidence is that the order equals `sorted` on EVERY seed, and that the seeds were chosen
    # to include one where a small-string set and a large-string set disagree -- which is the
    # measured shape of the three renderings before the fix.
    checks.append(report("plant3: and the order equals `sorted` on ALL FIVE seeds, which is what "
                         "a law looks like and what a single agreeing seed cannot show",
                         all(ops[s] == sorted(ops[s]) and ops[s] for s in SEEDS),
                         f"seeds {list(SEEDS)}: " +
                         "; ".join(f"{s}={'S' if ops[s] == sorted(ops[s]) else 'H'}"
                                   for s in SEEDS) +
                         f"  (S=sorted, H=hash order). Distinct renderings: {len(seen)}. "
                         f"seed {SEEDS[0]}: {next(iter(ops.values()))}"))
    return all(checks)


def diff_ops(rendered: str) -> list[str]:
    """The op names out of one rendered `PY-BEND OPs DIFFER:` fragment, IN THE ORDER THEY WERE
    PRINTED. NOT SORTED -- and that is load-bearing: the first version of this function ended in
    `sorted(...)`, which made every assertion built on it compare `sorted(x)` with `sorted(x)`
    and pass on the pre-fix file with an EMPTY list. MEASURED, the plants reported PASS for
    "the order equals `sorted`" on a file whose print is an unsorted set, because the plant had
    sorted the evidence itself. **AN ASSERTION THAT CANNOT FAIL HAS NOT BEEN TESTED**, and the
    way this one could not fail was by tidying its own input.

    It reads BOTH spellings on purpose -- `{...}` is the pre-fix set literal and `[...]` is the
    sorted list -- so the assertion is about the ORDER and not about the delimiters, and so the
    pre-fix file can be measured by the same parser rather than being excused for not matching.
    """
    for opener, closer in (("[", "]"), ("{", "}")):
        if opener in rendered and closer in rendered:
            inner = rendered.split(opener, 1)[1].split(closer, 1)[0]
            return [x.strip().strip("'\"") for x in inner.split(",") if x.strip()]
    return []


def main() -> int:
    print("PLANTS FOR .agents/slop/graphcmp-oracle.py -- three defects, three plants")
    ok1 = plant1()
    ok2 = plant2()
    ok3 = plant3()
    print(f"\n  {'ALL PLANTS PASS' if ok1 and ok2 and ok3 else 'PLANT FAILURE'}")
    return 0 if ok1 and ok2 and ok3 else 1


if __name__ == "__main__":
    if "--row" in sys.argv:
        i = sys.argv.index("--row")
        get = lambda f: sys.argv[sys.argv.index(f) + 1] if f in sys.argv else None  # noqa: E731
        rc, out = run_row(os.environ.get("DEV"), get("--bend-dev"), get("--retag"))
        sys.stdout.write(out)
        sys.exit(rc)
    sys.exit(main())