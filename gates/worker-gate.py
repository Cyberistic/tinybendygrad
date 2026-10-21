#!/usr/bin/env python3
"""worker-gate -- `tinybendygrad/engine/worker.bend` AGAINST CPython's `tinygrad/engine/worker.py`.

    .venv/bin/python gates/worker-gate.py           # the verdict
    .venv/bin/python gates/worker-gate.py --plant   # the plant, and its two controls

THE SUBJECT IS NINE ROWS AND THE OTHER SIXTY-TWO ARE REPORTED. The port prints 56 rows and
the CPython oracle prints 15, and they OVERLAP IN NINE: `init_allow_device_usage init_viz
init_sigint_ignored cleared_file cleared_spec after_spec_present spawnv_patched
maxtasks_default pool_init_name`. Those nine must be byte-identical on the two sides. The
other 47 are BEND-ONLY and the other 6 are ORACLE-ONLY, and NEITHER CLASS IS COMPARED: the
port has no `__main__` module, no `missing` sentinel object and no `daemon` flag to print,
so the oracle's six are rows the port CANNOT print rather than rows it got wrong. Both
classes are printed with their names, because a class nobody names is a number nobody checks.

THE ORACLE IS A RECOVERED FILE, AND A RECOVERED FILE CARRIES A PIN. `gates/worker-oracle.py`
is `.agents/slop/probe/jit_oracle.py`, recovered BYTE FOR BYTE from the blob
`0c8fcbe61c212ef9caa84e61216a2c105a153d46` (10894 B, sha256
`4e2e08a77c3a3d2df545284ff8217a7aed704cf677606d54a19b736da388a11b`), the tree of commit
`b551a234bd2c95048aa30cd247de7a177477bbae` (2026-10-04, an ancestor of HEAD). The mass
deletions of 2026-10-02 removed the file from the working tree and it was never restored,
while `tinybendygrad/engine/worker.bend` names a `.agents/slop/probe/worker_oracle.py` that
NEVER EXISTED in any ref. The pin is CHECKED ON EVERY RUN (`gatekit.oracle_drift`), because a
recovered file that can drift is not a recovery.

THE PORT'S OWN EXPECTED VALUES ARE ALREADY TRACKED AND THIS GATE READS THEM:
`oracles/tinybendygrad_engine_worker.bend.rows` is the port's 56 rows in the port's own
order, and it was an ORPHAN -- named by nothing, checked by nothing. **AN EXPECTATIONS FILE
MOVES WITH ITS SUBJECT:** a change to `worker.bend`'s rows must change that file in the same
commit, or this gate is red, and it is right to be.

WHY THIS IS NOT A `gatekit.Gate`. That class models ONE oracle and ONE driver whose rows
nest: the oracle's row count is DERIVED as `rows - len(port_only)`, so it cannot express an
oracle that prints rows the driver does not. This pair is the other shape -- 56 against 15,
overlapping in 9, with 6 rows on the oracle's side and 47 on the driver's -- and the model
would have to be given a second exclusion list to say so. The five verdicts and the watchdog
are still `gatekit`'s and `checks/bounded.py`'s, LOADED BY PATH and never re-spelled.
"""
import argparse
import hashlib
import importlib.util
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import gatekit  # noqa: E402  (the path has to exist before this line runs)
from gatekit import DEAD, FAIL, PASS, REFUSED, SKIP  # noqa: E402

BOUNDED = ROOT / "checks" / "bounded.py"
SECONDS = 600
MB = 2048

# THE DECLARATIONS. Each names a path in this repository and each is CHECKED, never trusted.
ORACLE = "gates/worker-oracle.py"
ORACLE_PIN = {ORACLE: "4e2e08a77c3a3d2df545284ff8217a7aed704cf677606d54a19b736da388a11b"}
DRIVER = "tinybendygrad/engine/worker.bend"
PORT_ROWS = "oracles/tinybendygrad_engine_worker.bend.rows"
ORACLE_MODE = "worker"

# THE TWO DENOMINATORS, DECLARED AND THEN DERIVED. `ORACLE_ROWS` is how many rows the CPython
# lane prints and `SHARED_ROWS` is how many of them the port also prints; both are ASSERTED
# against the live lanes, so a lane that loses a row is RED rather than quietly a smaller
# comparison. **A GATE THAT COMPARES NOTHING IS NOT A PASS**, and the way to stop that is a
# declared denominator the derived one has to equal.
ORACLE_ROWS = 15
SHARED_ROWS = 9

# THE ROW GRAMMAR, the tree's own (`gates/lane-census.py:ROW`): `name=value`, no spaces.
ROW = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

# THE TWO PLANT EDITS, each a TEXT SUBSTITUTION in a COPY of the oracle. The first moves a
# SHARED row's value; the second moves a row the port CANNOT print, and the pair of them is
# what separates "the gate is red because a SHARED row disagrees" from "the gate is red
# because anything changed".
SHARED_EDIT = ('rows.append(("maxtasks_default", str(H.getenv("BEAM_MAX_TASKS_PER_CHILD", 16))))',
               'rows.append(("maxtasks_default", str(H.getenv("BEAM_MAX_TASKS_PER_CHILD", 8))))')
ORACLE_ONLY_EDIT = ('rows.append(("lane", "script" if with_file else "dash-c"))',
                    'rows.append(("lane", "dash-c"))')


def load(name, path):
    """A MODULE, LOADED BY PATH, and never re-derived here."""
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


WATCHDOG = load("bounded_for_worker_gate", BOUNDED)


def rows_of(text):
    """`(rows, junk)`: the `name=value` rows of a lane's stdout, and the lines that are not."""
    lines = [l for l in (text or "").splitlines() if l.strip()]
    return [l for l in lines if ROW.match(l)], [l for l in lines if not ROW.match(l)]


def said(stderr):
    """What the lane SAID, without the watchdog's own record and without bend's notice."""
    text = "\n".join(l for l in (stderr or "").splitlines()
                     if not WATCHDOG.RECORD.match(l.strip()))
    return gatekit._said(text)


def names(rows):
    """`({name: line}, duplicates)` -- a dict alone would collapse a repeated row silently."""
    out, dup = {}, []
    for l in rows:
        k = l.split("=", 1)[0]
        if k in out:
            dup.append(k)
        out[k] = l
    return out, dup


def lane(argv, name):
    """`(code, out, note)` for ONE lane, under the watchdog.

    **THE TOKEN IS THE VERDICT AND NEVER THE EXIT STATUS.** `checks/bounded.py`'s own header
    records a unit that lost 425 rows by believing the status, and `checks/gatesweep.py`'s
    `classify()` is the tree's mapping of the five watchdog tokens onto the five verdicts: a
    kill is a SKIP, a lane that could not start is a REFUSED, and a lane that ran and emitted
    nothing is a DEAD. A lane that FAILED is a REFUSED when it named its own failure, because
    that names an absent precondition, and a DEAD otherwise.

    **THE ROW COUNT IS NOT CHECKED HERE.** This function answers a question about the
    PROCESS; whether the lane printed rows is the caller's question, and the warm check asks
    a third one -- the first LINE -- which is not a row at all.
    """
    r = subprocess.run([str(gatekit.PY), str(BOUNDED), "--seconds", str(SECONDS),
                        "--mb", str(MB), "--", *argv],
                       capture_output=True, text=True, cwd=str(ROOT))
    m = WATCHDOG.RECORD.search(r.stderr or "")
    token = m.group(1) if m else "NO-RECORD"
    if token == WATCHDOG.UNSTARTED:
        return REFUSED, r.stdout, f"{name}: the watchdog could not start the lane"
    if token in (WATCHDOG.MEMORY, WATCHDOG.TIMEOUT):
        return SKIP, r.stdout, f"{name}: {token} -- this run proves nothing"
    if token == WATCHDOG.NOVERDICT:
        return DEAD, r.stdout, f"{name}: the lane ran and said nothing"
    if r.returncode != 0:
        why = said(r.stderr)
        return (REFUSED if why else DEAD), r.stdout, (
            f"{name}: {why}" if why else f"{name}: exited {r.returncode} and said nothing")
    return PASS, r.stdout, f"{name}: token {token}"


def warm(driver):
    """`bend <driver> --check-only`, and its FIRST LINE -- never its exit status.

    `gatekit.Gate._warm` says why: an EMPTY file typechecks, and `helpers.bend` has been
    truncated to 0 bytes four times in this tree, each time by a unit that then saw green. A
    COLD driver is an absent precondition (REFUSED), not a wrong answer (FAIL).
    """
    code, out, note = lane([str(gatekit.BEND), str(driver), "--check-only"], "warm")
    if code != PASS:
        return code, note
    first = (out or "").splitlines()[:1]
    if not first or first[0].strip() != gatekit.WARM:
        return REFUSED, f"warm: --check-only's first line is {first!r}, not {gatekit.WARM!r}"
    return PASS, note


def compare(oracle_rows, port_rows, port_expected):
    """`(code, lines)` -- THE CLAIMS, and the classes they are about.

    `port_expected` is the port's expected values, or None to leave that claim out. The
    comparisons are over the two lanes' LIVE rows, so a lane that drifts is caught whichever
    side of the expectation files moved.
    """
    on, on_dup = names(oracle_rows)
    pn, pn_dup = names(port_rows)
    shared = sorted(set(on) & set(pn))
    bend_only = sorted(set(pn) - set(on))
    oracle_only = sorted(set(on) - set(pn))
    diffs = [(k, on[k], pn[k]) for k in shared if on[k] != pn[k]]
    bad = []
    if on_dup:
        bad.append(f"the CPython lane prints {sorted(set(on_dup))} twice")
    if pn_dup:
        bad.append(f"the port prints {sorted(set(pn_dup))} twice")
    if len(oracle_rows) != ORACLE_ROWS:
        bad.append(f"the CPython lane printed {len(oracle_rows)} rows, expected {ORACLE_ROWS}")
    if len(shared) != SHARED_ROWS:
        bad.append(f"the two lanes share {len(shared)} rows, expected {SHARED_ROWS}")
    if diffs:
        bad.append(f"{len(diffs)} of {len(shared)} shared rows disagree: "
                   + "; ".join(f"{k}: cp={a} port={b}" for k, a, b in diffs[:4]))
    if port_expected is not None and list(port_rows) != list(port_expected):
        bad.append(f"the port's {len(port_rows)} rows differ from {PORT_ROWS}")
    port_match = "not checked" if port_expected is None else (
        "match" if list(port_rows) == list(port_expected) else "DIFFER")
    lines = [
        f"CLAIM cpython-rows   {len(oracle_rows)} of {ORACLE_ROWS}",
        f"CLAIM shared-rows    {len(shared)} of {SHARED_ROWS}, {len(diffs)} disagreeing",
        f"CLAIM port-expected  {port_match} ({PORT_ROWS})",
        f"CLASS  shared        {len(shared)}  " + " ".join(shared),
        f"CLASS  bend-only     {len(bend_only)}  " + " ".join(bend_only),
        f"CLASS  oracle-only   {len(oracle_only)}  " + " ".join(oracle_only),
    ]
    return (FAIL if bad else PASS), lines + [f"  FAIL  {b}" for b in bad]


def gate(oracle=ORACLE, pin=None, driver=DRIVER, port_rows=PORT_ROWS):
    """THE WHOLE GATE, WITH ITS INPUTS AS PARAMETERS.

    The parameters exist for the PLANT: a perturbed COPY of the oracle is driven through THIS
    function, so the plant exercises the shipped decision end to end and never touches the
    substrate. `gates/worker-mutate.py` rewrites `worker.bend` IN PLACE and restores it from
    `/tmp`, and a crash there leaves the substrate mutated, so that is not a shape to copy.
    """
    pin = ORACLE_PIN if pin is None else pin
    drift = gatekit.oracle_drift(pin)
    if drift:
        return REFUSED, [f"  REFUSED  the oracle is not the pinned file: {drift[0]}"]
    opath, dpath, ppath = ROOT / oracle, ROOT / driver, ROOT / port_rows
    for p, what in ((opath, "the CPython oracle"), (dpath, "the driver"),
                    (ppath, "the port's expected values")):
        if not p.is_file():
            return REFUSED, [f"  REFUSED  absent: {what} -- {p}"]
    expected = [l for l in ppath.read_text().splitlines() if l.strip()]
    code, note = warm(dpath)
    if code != PASS:
        return code, [f"  {gatekit.verdict_of(code)}  {note}"]
    ocode, oout, onote = lane([str(gatekit.PY), str(opath), ORACLE_MODE], "cpython")
    if ocode != PASS:
        return ocode, [f"  {gatekit.verdict_of(ocode)}  {onote}"]
    orows, _ojunk = rows_of(oout)
    if not orows:
        return DEAD, ["  DEAD  the CPython lane printed no rows"]
    pcode, pout, pnote = lane([str(gatekit.BEND), str(dpath)], "port")
    if pcode != PASS:
        return pcode, [f"  {gatekit.verdict_of(pcode)}  {pnote}"]
    prows, _pjunk = rows_of(pout)
    if not prows:
        return DEAD, ["  DEAD  the port lane printed no rows"]
    code, lines = compare(orows, prows, expected)
    return code, [f"  {onote}", f"  {pnote}"] + lines


def plant():
    """THE PLANT, AND ITS TWO CONTROLS -- three end-to-end runs of the SHIPPED gate.

    The perturbation is a TEXT SUBSTITUTION in a COPY of the oracle, written to a temp dir and
    pinned with its OWN sha256, so the pin check still runs and still passes. Nothing under
    `tinybendygrad/` is written, and the substrate is not moved: this file never edits a
    `.bend`, and `substrate_digest()` does not cover `gates/`, so the corpus is untouched.
    """
    src = (ROOT / ORACLE).read_text()
    cases = [
        ("PLANT   a SHARED row disagrees", SHARED_EDIT, FAIL, "maxtasks_default"),
        ("CONTROL the same file, unperturbed", None, PASS, None),
        ("CONTROL a row the PORT CANNOT print disagrees", ORACLE_ONLY_EDIT, PASS, None),
    ]
    checks = []
    for label, edit, want, names_row in cases:
        if edit is not None and edit[0] not in src:
            print(f"  REFUSED  {label}: the oracle does not contain the text to perturb")
            return REFUSED
        text = src if edit is None else src.replace(*edit)
        with tempfile.TemporaryDirectory() as td:
            copy = Path(td) / "worker-oracle.py"
            copy.write_text(text)
            pin = {str(copy): hashlib.sha256(text.encode()).hexdigest()}
            code, lines = gate(oracle=str(copy), pin=pin)
        said_row = " ".join(lines)
        ok = code == want and (names_row is None or names_row in said_row)
        detail = f"rc={code} (want {want})" + ("" if names_row is None
                                                else f", names {names_row!r}: {names_row in said_row}")
        print(f"  {'OK  ' if ok else 'FAIL'}  {label:<52} {detail}")
        checks.append(ok)
    ok_all = all(checks)
    print(f"--plant: {'GREEN' if ok_all else 'RED'} ({sum(checks)}/{len(checks)})")
    return PASS if ok_all else FAIL


def main(argv):
    ap = argparse.ArgumentParser(prog="gates/worker-gate.py",
                                 description=__doc__.split("\n")[0])
    ap.add_argument("--plant", action="store_true",
                    help="the plant, and its two controls")
    a = ap.parse_args(argv)
    if a.plant:
        return plant()
    code, lines = gate()
    for l in lines:
        print(l)
    print(f"worker-gate: {gatekit.verdict_of(code)}")
    return code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
