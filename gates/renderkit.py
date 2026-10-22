#!/usr/bin/env python3
"""renderkit.py -- the plumbing the two RENDER gates share.

    from renderkit import render_gate

A RENDER GATE compares a PORT's row lane against a CPython ORACLE's row lane, byte
for byte, where a row is

    <name> = [<the port's value>]   py=[<the same value>]

THE `py=` HALF IS DERIVED, AND THAT IS THE POINT.  It used to be a LITERAL -- text
transcribed once from what CPython said -- and a transcription has no generator: it
cannot see CPython move, and it cannot see the PORT move either.  MEASURED 2026-10-22
on `ops_dsp.bend`, THIRTY of its rows carried a `py=` half that was RIGHT while the
`got=` half beside it was WRONG: the file agreed with itself and was wrong on thirty
rows.  The `py=` half is now the port's own value, re-read, so the row cannot
disagree with itself; and the ASSERTION is the byte diff against CPython's lane,
which is where the value now lives.

THE THREE LANES, AND WHY THREE.

    py   CPython, from the recovered oracle, at the PINNED upstream
    bd   the port, interpreted by `bin/bend`
    bn   the port, compiled by `bin/bend -o` and run

Two lanes would measure the port against CPython and the port against itself; the
compiled lane is what catches a difference between the interpreter and the
compiler, which is a class of defect the interpreted lane cannot see at all.

THE PIN, AND WHY IT IS ONE COMMIT AND NOT A LIST OF ROWS.  Both ports track an
upstream that has since moved -- `tinygrad/renderer/llvmir.py` was 286 lines at the
pin and is 309 at the tree's HEAD, and 409 of the lane's lines differ.  Measuring
against the tree's HEAD would be RED on every row that moved, and the only way to
say which side is right would be to list them -- and a hand list of differing rows
is a SECOND COPY OF THE ANSWER, which is the failure this whole change removes.  So
the oracle runs against the upstream the port was WRITTEN AGAINST, and the pin is
ONE commit id, extracted from git at run time.  MEASURED: the two commits that
could have been the pin (`192142295` and `813bbec3e`) give BYTE-IDENTICAL oracle
output for BOTH oracles, so the pin is not a choice between two answers.

THE FIVE VERDICTS, AND THEY ARE `gatekit`'s: PASS 0, FAIL 1, REFUSED 3, SKIP 4,
DEAD 5.  A lane that emitted no rows is DEAD, not PASS, and a file that is not
there is REFUSED, not FAIL.  "A GATE THAT EXITS 0 HAVING MEASURED NOTHING IS WORSE
THAN NO GATE."
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"
LOCK = ROOT / "checks" / "bendlock.sh"
ART = HERE / "artifacts"

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
VERDICT = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP", DEAD: "DEAD"}

# THE PIN: the upstream these two ports were written against.  `813bbec3e` is the
# commit that last carried BOTH port files, and its `tinygrad/` tree carries the same
# `llvmir.py` and `ops_dsp.py` blobs as `192142295`, the commit that made the
# `ops_dsp` rows compared -- and MEASURED, both commits give the same oracle output.
PIN = "813bbec3ee1b7113d93bde1376d431d0b82b0658"

# A ROW IS `<name> = [<value>]   py=[<value>]`, and a row's END is the `]` that
# closes its `py=[`.  A VALUE may contain newlines -- `dsp_link_script` is 31 lines
# of a linker script -- so a row is split at its END and not at its start, and a
# row's NAME is everything before its first ` = [`.  Splitting at the start instead
# needs a rule about what a continuation line may look like, and this one does not.
ROW_END = re.compile(r"py=\[")

WARM = "ALL PROOFS CHECK"


def say(name, msg):
    print(f"{name}: {msg}", file=sys.stderr)


def refuse(name, why):
    print(f"== REFUSED, NOT A VERDICT: {name}: {why}", file=sys.stderr)
    return REFUSED


def split_rows(text):
    """[(name, row_text)] for every row in a lane."""
    out, pos = [], 0
    for m in ROW_END.finditer(text):
        end = text.find("]", m.end())
        if end < 0:
            raise ValueError(f"a row has no closing `]`: {text[m.start():m.start() + 60]!r}")
        row = text[pos:end + 1]
        pos = end + 1
        while pos < len(text) and text[pos] == "\n":
            pos += 1
        out.append((row.split(" = [", 1)[0], row))
    if text[pos:].strip():
        raise ValueError(f"the lane has text after its last row: {text[pos:][:60]!r}")
    return out


def pinned_root():
    """A directory holding the PINNED `tinygrad/` and this tree's `tinybendygrad/`.

    REFUSES by raising: a gate that cannot get the pinned tree must not measure
    against the live one, because a red gate and a gate measuring the wrong tree
    look the same to a reader.
    """
    d = Path(tempfile.mkdtemp(prefix="renderpin-"))
    a = subprocess.run(["git", "archive", PIN, "tinygrad"], cwd=str(ROOT),
                       capture_output=True)
    if a.returncode != 0:
        shutil.rmtree(d, ignore_errors=True)
        raise RuntimeError(f"git archive {PIN} tinygrad failed: "
                           f"{a.stderr.decode(errors='replace')[:200]}")
    t = subprocess.run(["tar", "-x", "-C", str(d)], input=a.stdout, capture_output=True)
    if t.returncode != 0:
        shutil.rmtree(d, ignore_errors=True)
        raise RuntimeError(f"tar failed: {t.stderr.decode(errors='replace')[:200]}")
    (d / "tinybendygrad").symlink_to(ROOT / "tinybendygrad")
    return d


def _warm(bendfile):
    """`--check-only`'s FIRST LINE, never its exit status (`gatekit._warm`'s rule)."""
    r = subprocess.run([str(BEND), str(bendfile), "--check-only"],
                       capture_output=True, text=True, cwd=str(ROOT))
    first = (r.stdout or "").splitlines()[:1]
    return bool(first) and first[0].strip() == WARM


def render_gate(name, port, oracle, rows, diverges=None):
    """The whole gate.  `port` and `oracle` are paths; `rows` is the row count BOTH
    lanes must print; `diverges` maps a row name to (the ORACLE's row, the PORT's row)
    for the rows where the two sides are KNOWN to differ, each pinned on BOTH sides.

    A divergence is excluded from the diff and PINNED: an excluded-and-unpinned row
    is how a divergence stops being a claim, and a pin of one side can only ever
    describe half of it.
    """
    diverges = dict(diverges or {})
    port, oracle = Path(port), Path(oracle)
    for p in (port, oracle, BEND, PY, LOCK):
        if not p.exists():
            return refuse(name, f"an input is absent: {p}")
    out = ART / name
    if out.exists():
        for p in out.iterdir():
            p.unlink()
    out.mkdir(parents=True, exist_ok=True)
    if not _warm(port):
        return refuse(name, f"{port} is not warm (`--check-only`'s first line is not "
                            f"{WARM!r})")

    try:
        pin = pinned_root()
    except RuntimeError as e:
        return refuse(name, str(e))

    # ---- the ORACLE's lane, at the pin
    env = {"PORT_ROOT": str(pin), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
           "HOME": str(Path.home())}
    orc = subprocess.run([str(PY), str(oracle), "rows"], capture_output=True, text=True,
                         cwd=str(ROOT), env=env)
    if orc.returncode != 0:
        return refuse(name, f"the oracle failed rc={orc.returncode}: "
                             f"{(orc.stderr or '').strip()[:200]}")
    if not orc.stdout.strip():
        return refuse(name, "the oracle emitted no rows")
    (out / "py.rows").write_text(orc.stdout)

    # ---- the PORT's lane, interpreted, THROUGH THE LOCK
    bd = subprocess.run([str(LOCK), "--", str(BEND), str(port)], capture_output=True,
                        text=True, cwd=str(ROOT))
    if bd.returncode != 0:
        return refuse(name, f"the interpreted lane failed rc={bd.returncode}: "
                             f"{(bd.stderr or '').strip()[:200]}")
    if not bd.stdout.strip():
        return refuse(name, "the interpreted lane emitted no rows")
    (out / "bd.out").write_text(bd.stdout)

    # ---- the PORT's lane, compiled
    binp = out / "gate.bin"
    c = subprocess.run([str(BEND), str(port), "-o", str(binp)], capture_output=True,
                       text=True, cwd=str(ROOT))
    if c.returncode != 0:
        return refuse(name, f"the native compile failed: {(c.stderr or '').strip()[:200]}")
    bn = subprocess.run([str(binp)], capture_output=True, text=True, cwd=str(ROOT))
    if bn.returncode != 0 or not bn.stdout.strip():
        return refuse(name, "the compiled lane emitted no rows")
    (out / "bn.out").write_text(bn.stdout)

    # ---- the row counts, and the DIFF
    lanes = {t: split_rows((out / f).read_text())
             for t, f in (("py", "py.rows"), ("bd", "bd.out"), ("bn", "bn.out"))}
    for tag, rs in lanes.items():
        if len(rs) != rows:
            say(name, f"the {tag} lane has {len(rs)} rows, expected {rows}")
            return DEAD if not rs else FAIL
    names = [n for n, _ in lanes["py"]]
    for tag in ("bd", "bn"):
        if [n for n, _ in lanes[tag]] != names:
            say(name, f"the {tag} lane's ROW NAMES differ from the oracle's")
            return FAIL
    # THE PINNED DIVERGENCES, on BOTH sides, before the diff.
    for row, (want_oracle, want_port) in diverges.items():
        for tag, want in (("py", want_oracle), ("bd", want_port), ("bn", want_port)):
            got = dict(lanes[tag]).get(row)
            if got != want:
                say(name, f"the {tag} lane's {row} is not {want!r} -- it is {got!r}. "
                          f"If the divergence is fixed, drop it; if it moved, update the pin.")
                return FAIL
    skip = set(diverges)
    for tag in ("py", "bd", "bn"):
        kept = [(n, t) for (n, t) in lanes[tag] if n not in skip]
        (out / f"{tag}.cmp").write_text("".join(t for _, t in kept))
    for tag in ("bd", "bn"):
        a = [(n, t) for (n, t) in lanes[tag] if n not in skip]
        b = [(n, t) for (n, t) in lanes["py"] if n not in skip]
        if a != b:
            bad = [(x[0], x[1], y[1]) for x, y in zip(a, b) if x[1] != y[1]]
            say(name, f"DISAGREE ({tag}): {len(bad)} of {len(b)} rows differ; "
                      f"first: {[(n, o.strip()[:60], p.strip()[:60]) for n, o, p in bad[:2]]}")
            return FAIL
    print(f"  {name}: {rows} rows, {len(diverges)} declared divergences, "
          f"{rows - len(diverges)} compared, THREE LANES BYTE-IDENTICAL")
    return PASS
