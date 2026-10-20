#!/usr/bin/env python3
"""banner-emit-plant.py -- A BANNER THAT LOOKS LIKE A REAL ONE, AND THE HOLE IT WALKED INTO.

    .venv/bin/python gates/banner-emit-plant.py            # the arms; exit 0 iff all held
    .venv/bin/python gates/banner-emit-plant.py --falsify  # ARM 1's expectation INVERTED; must exit 1

**THE PLANT NEVER WRITES THE TREE.** Every arm is run in a `tempfile.mkdtemp()` scratch tree that
mirrors the layout the two gates resolve against -- `pyproject.toml`, `checks/e2e.py`, `gates/`, the
six lanes `checks/e2e.py` names, `.agents/slop/e2estage8/verdicts.py` and the census's own `DEFAULT`
artifact -- because both gates compute `ROOT` as their own file's parent's parent and `banner-gate.py`
REFUSES without a `pyproject.toml`. `checks/e2e.py` and the six lanes are copied BYTE-FOR-BYTE, so the
population the arms measure is the real population and not a spelling of it.

**THE ARMS, AND EACH ONE NAMES WHAT IT IS FOR.** `banner-gate.py`'s C1 reads quoted LITERALS; this
plant exists because "C1 is a static read" was a claim in that gate's docstring rather than a
measurement. `N` below is what the arms measured on 2026-10-20, and it is the whole receipt:

| arm | what is planted into the lane copy | `banner-gate.py` C1 | `banner-emit-gate.py` C1' | the lane's REAL bytes match `HEADER` |
|---|---|---|---|---|
| 0 CONTROL | nothing | **PASS** | **PASS** | no |
| 1 POSITIVE | `say "== 6/6 PLANTED LITERAL"` | **FAIL**, naming the line | **FAIL**, naming the line | **yes** |
| 2 HEREDOC | a `== 6/6 PLANTED HEREDOC` line INSIDE `cat <<'BANNERPLANT'` | **PASS** -- THE HOLE | **FAIL**, naming the line | **yes** |
| 3 CONCAT | `d=6` then `say "== $d/6 PLANTED CONCAT"` | **PASS** -- THE RESIDUAL | **PASS** -- THE RESIDUAL | **yes** |
| 4 NEGATIVE | `d=6` then `say "== $d PLANTED NOT A BANNER"` | **PASS** | **PASS** | **no** |

ARM 0 IS THE UNBROKEN CONTROL and ARM 4 IS THE UNBROKEN CONTROL FOR ARM 3: the same mechanism, a
line that is not banner-shaped, and a green from both gates. Without ARM 4 a reader could not tell
ARM 3's PASS from "this plant greens everything".

**ARM 3'S FORM IS `d=6` AND NOT `say "== 6/" "6 …"`, AND THE SECOND FORM WAS MEASURED TO BE WORTHLESS.**
The argument-split version was the first plant written here and it does not print a banner at all:
MEASURED 2026-10-20T00:20Z, zsh's `print -r -- "$@"` JOINS its arguments with a space and prints
`== 6/ 6 PLANTED CONCAT`, while `printf '%s\n' "$@"` prints `== 6/` and then `6 PLANTED CONCAT` on
two lines -- so the two shells disagree on the bytes and neither is banner-shaped. A shape that is not
the same string in the two shells that declare this tree's lanes is not a shape, and planting it would
have been a plant that emitted nothing and scored green. `printed()` REFUSES on any such disagreement
rather than picking a winner, which is how that was caught. The variable form is stable in both.

**ARM 3 IS NOT A PASS, IT IS A RECORD.** The last column is the falsification clause for the hole: the
lane's own printed bytes DO match `verdicts.HEADER` while BOTH static gates answer PASS, so the hole is
a banner that exists and is invisible, measured rather than asserted. **NO STATIC READ OF A SOURCE TEXT
CAN CLOSE IT** -- the banner is assembled when the shell runs, and the text does not contain it. The
thing that does close it is `.agents/slop/e2estage8/verdicts.py` itself, on the artifact, as a `RE-OPEN`
row and a non-zero exit -- which is a real gate, and means the hole costs a run rather than a
detection. `gates/banner-emit-gate.py`'s docstring says so, and this plant is the receipt for it.

**AND `banner-gate.py`'s EXIT CODE IS NEVER READ.** Its C2 is a claim about `live.port.out`'s mtime and
is FAIL or DEAD in the scratch tree regardless of C1, and `DEAD` outranks `FAIL` -- so the arm reads
the `(C1 PASS` / `(C1 FAIL` token out of the summary line. Reading the exit code would have scored
ARM 2 as "the gate fired" on a claim that had nothing to do with the plant.

`--falsify` INVERTS ARM 1's expectation and MUST exit 1. That is how this plant is shown to be able to
fail: a plant whose expectations cannot be violated proves nothing, and one arm of it going red for the
wrong reason would otherwise read as success.
"""
from __future__ import annotations

import ast
import importlib.util
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "gates"))
from gatekit import DEAD, REFUSED  # noqa: E402

GATES = ("banner-gate.py", "banner-emit-gate.py", "gatekit.py")
LANE = ".agents/slop/e2e_port/run-port-mm.sh"
CENSUS = ".agents/slop/e2estage8/verdicts.py"
# THE FOUR PLANTS, AND THE THREE COLUMNS EACH ONE IS JUDGED ON. `want_c1` is what `banner-gate.py`'s
# C1 MUST answer; `want_emit` is what `banner-emit-gate.py` C1' must answer; `want_bytes` is whether
# the lane's REAL output matches `verdicts.HEADER`, which is the falsification clause for a PASS.
ARMS: tuple[tuple[str, str, str, bool, bool], ...] = (
    ("1 POSITIVE", 'say "== 6/6 PLANTED LITERAL"', "FAIL", True, True),
    ("2 HEREDOC", "cat <<'BANNERPLANT'\n== 6/6 PLANTED HEREDOC\nBANNERPLANT", "PASS", True, True),
    ("3 CONCAT", 'd=6\nsay "== $d/6 PLANTED CONCAT"', "PASS", True, False),
    ("4 NEGATIVE", 'd=6\nsay "== $d PLANTED NOT A BANNER"', "PASS", False, False),
)
SAY = {"zsh": 'say() { print -r -- "$@" }', "/bin/sh": 'say() { printf \'%s\\n\' "$@"; }'}


def sibling_of(root: Path) -> object:
    """`banner-gate.py` under `root`, loaded BY PATH. The HYPHEN is why `import` cannot be spelled."""
    spec = importlib.util.spec_from_file_location(f"banner_gate_{root.name}", root / "gates/banner-gate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def scratch() -> tuple[Path, int]:
    """`(mirror, lane count)`: a byte-for-byte mirror of the paths both gates resolve against.
    Nothing here is spelled -- the lanes are the ones `banner-gate.py`'s OWN walk finds, and the count
    comes back so the 'population is whole' control compares against the SAME walk and not against a
    number written down here. **EVERY LANE IS COPIED**: `repo_path()` answers `None` for a token whose
    file is absent, so a scratch holding only the planted lane would measure a population of ONE and
    that control would be checking an absence."""
    tmp = Path(tempfile.mkdtemp(prefix="bannerplant."))
    bg = sibling_of(ROOT)
    lanes = sorted({p for argv in bg.lane_argv(ast.parse((ROOT / "checks/e2e.py").read_text()))
                    for p in (bg.repo_path(t) for t in argv) if p is not None})
    for rel in ("checks/e2e.py", CENSUS, ".agents/slop/e2epy/artifacts/live.port.out",
                *(str(p.relative_to(ROOT)) for p in lanes)):
        dst = tmp / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / rel, dst)
    (tmp / "gates").mkdir(parents=True, exist_ok=True)
    for g in GATES:
        shutil.copyfile(ROOT / "gates" / g, tmp / "gates" / g)
    (tmp / "pyproject.toml").write_text("# the scratch root's only job is to exist\n")
    return tmp, len(lanes)


def read_out(tmp: Path, gate: str) -> tuple[int, str]:
    """`(exit, stdout+stderr)` of one gate, run IN the scratch tree under this interpreter."""
    p = subprocess.run([sys.executable, str(tmp / "gates" / gate)], capture_output=True, text=True,
                       cwd=str(tmp))
    return p.returncode, p.stdout + p.stderr


def c1_of(out: str) -> str:
    """`banner-gate.py`'s C1 VERDICT TOKEN, out of its summary line -- never its exit code."""
    for line in out.splitlines():
        if line.startswith("banner-gate:") and "(C1 " in line:
            return line.split("(C1 ")[1].split(",")[0].strip()
    return "?"


def emit_of(out: str) -> str:
    """`banner-emit-gate.py` has ONE claim, so its EXIT is that claim; the token is read off the
    summary line rather than inferred from the presence of the word FAIL, because a DEAD or REFUSED
    run says nothing about the claim and `SKIP IS NOT PASS`."""
    for line in out.splitlines():
        if line.startswith("banner-emit-gate: ") and " -- " in line:
            return line.split("banner-emit-gate: ")[1].split(" -- ")[0]
    return "?"


def printed(tmp: Path, plant: str) -> tuple[dict[str, str], bool]:
    """`(bytes per shell, matches_HEADER)`: the plant EXECUTED under the lane's declared shell AND
    under `/bin/sh`, byte-compared, and asked against the census's own `HEADER`."""
    ns: dict = {"__file__": str(tmp / CENSUS), "__name__": "census"}
    exec(compile((tmp / CENSUS).read_text(), "verdicts.py", "exec"), ns)   # noqa: S102 -- the tree's own
    got: dict[str, str] = {}
    for shell in ("zsh", "/bin/sh"):
        f = tmp / f"snippet{abs(hash(shell))}.sh"
        f.write_text(f"{SAY[shell]}\n{plant}\n")
        r = subprocess.run([shell, str(f)], capture_output=True, text=True, check=True)
        got[shell] = r.stdout
    if got["zsh"] != got["/bin/sh"]:
        raise AssertionError(f"the two shells disagree on the plant's bytes: {got!r}")
    return got, any(ns["HEADER"].match(ln) for ln in got["zsh"].splitlines())


def row(ok: bool, label: str) -> bool:
    """ONE arm line, and the row IS the record: the verdict token goes in the label and the boolean
    is returned so `main` can fold it into the count. Written as a helper because an f-string
    replacement field holding an implicit concatenation is 3.12-ONLY syntax (`ruff`'s
    `invalid-syntax` on 3.11), which is how three arms of this file were briefly unparseable
    anywhere but the venv."""
    print(f"  {'OK  ' if ok else 'FAIL'} {label:<62}")
    return ok


def main() -> int:
    falsify = "--falsify" in sys.argv[1:]
    results: list[bool] = []
    tmp, n_lanes = scratch()
    try:
        lane = tmp / LANE
        base = lane.read_text()

        c, out = read_out(tmp, "banner-emit-gate.py")
        results.append(row(c == 0, f"CONTROL the unplanted tree is clean (exit {c})"))

        for name, plant, want_c1, want_bytes, want_emit in ARMS:
            lane.write_text(base + "\n" + plant + "\n")
            _, bout = read_out(tmp, "banner-gate.py")
            _, eout = read_out(tmp, "banner-emit-gate.py")
            _, matches = printed(tmp, plant)
            ok_b = c1_of(bout) == want_c1
            ok_e = emit_of(eout) == ("FAIL" if want_emit else "PASS")
            ok_x = matches == want_bytes
            if falsify and name == "1 POSITIVE":           # THE PLANT, SHOWN ABLE TO FAIL
                ok_b, ok_e, ok_x = not ok_b, not ok_e, not ok_x
            results += [ok_b, ok_e, ok_x]
            row(ok_b and ok_e and ok_x,
                f"{name} -> banner-gate C1={c1_of(bout)} (want {want_c1}), "
                f"banner-emit={emit_of(eout)} (want {'FAIL' if want_emit else 'PASS'}), "
                f"real bytes match HEADER={matches} (want {want_bytes})")

        lane.write_text(base)
        code, out = read_out(tmp, "banner-emit-gate.py")
        n_rows = len([ln for ln in out.splitlines() if ln.startswith("---   ")])
        results.append(row(code == 0 and n_rows == n_lanes,
                           f"CONTROL the lane was restored; the walk reports {n_rows} of {n_lanes} "
                           f"lane(s)"))

        # THE TWO EXITS NOBODY READS, RUN. `banner-emit-gate.py` writes a DEAD branch and a REFUSED
        # branch and nothing in this tree can reach either: the walk only comes up empty if
        # `checks/e2e.py` loses its `stage([...])` call sites, and the REFUSED guard only fires away
        # from a repo root. **A BRANCH THAT HAS NEVER RUN IS NOT A VERDICT, IT IS A COMMENT**, so both
        # are provoked here in the scratch and the exits are exercised rather than quoted.
        e2e = tmp / "checks/e2e.py"
        kept = e2e.read_text()
        e2e.write_text("# a gate with no `stage([...])` call site in it at all\n")
        bcode, _ = read_out(tmp, "banner-gate.py")
        ecode, eout = read_out(tmp, "banner-emit-gate.py")
        results.append(row(bcode == DEAD and ecode == DEAD and emit_of(eout) == "DEAD"
                           and "compared nothing" in eout,
                           "DEAD no `stage([...])` call site: both gates exit DEAD, not PASS"))
        e2e.write_text(kept)
        (tmp / "pyproject.toml").unlink()
        bcode, bout = read_out(tmp, "banner-gate.py")
        ecode, eout = read_out(tmp, "banner-emit-gate.py")
        results.append(row(bcode == REFUSED and ecode == REFUSED
                           and "NOT A VERDICT" in bout and "NOT A VERDICT" in eout,
                           "REFUSED not at a repo root: both gates exit REFUSED, not FAIL"))
        (tmp / "pyproject.toml").write_text("# the scratch root's only job is to exist\n")
        code, _ = read_out(tmp, "banner-emit-gate.py")
        results.append(row(code == 0, "CONTROL restored: the scratch is back to a clean PASS"))

        results.append(row((ROOT / LANE).read_text() == base,
                           "CONTROL the REAL tree was never written"))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"--- {sum(results)} of {len(results)} arm(s) behaved as required"
          + ("   [FALSIFY: ARM 1's expectation was inverted, so the failures below are required]"
             if falsify else ""))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())