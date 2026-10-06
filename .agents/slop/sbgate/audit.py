#!/usr/bin/env python3
"""Census of checks/*.sh: which gates can report success without having run.

Every finding is (file, line, mechanism). A shell gate is only useful if it can go
red, so the census asks one question of each script -- CAN IT LIE? -- and answers it
two ways: statically, by locating the five shapes that produce a false pass, and
dynamically, by running the script and asking whether it emitted anything.

Read-only. It touches nothing outside .agents/slop/sbgate/.

    .venv/bin/python .agents/slop/sbgate/audit.py            # static census
    .venv/bin/python .agents/slop/sbgate/audit.py --run SAFE # static + dynamic
    .venv/bin/python .agents/slop/sbgate/audit.py --json     # machine form
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
CHECKS = REPO / "checks"

# A script is allowed to run `bend` only when the caller passes --run ALL and the
# script is in this set, because two concurrent bends exhaust the box (sz.bend
# peaks at 1468 MB). Everything else is spawnable.
CHEAP = {
    "bounded-selftest.sh",
    "classify.sh",
    "disarm.sh",
    "gen.sh",
    "lint_demo.sh",
    "run-all.sh",
    "sb-gate.sh",
    "substrate-check.sh",
    "wt-sync.sh",
}
# mutate.sh MUTATES THE LIVE TREE (checks/mutate.sh:10 `sed -i` on
# tinybendygrad/uop/spec.bend) and walk-mutate.sh plants; neither is safe to spawn
# while three units are writing. They are audited statically only.
UNSAFE = {"mutate.sh", "walk-mutate.sh"}
EXPENSIVE = {"demo.sh", "e2e.sh", "lintable-gate.sh", "plant.sh", "run-f64.sh", "run-port-mm.sh"}
# MEASURED FAST-FAILING: each of these dies at its first out-of-repo path access
# before any bend spawn, so they are safe to include. gate.sh included: it dies at
# `python3 .agents/slop/shlscope/gen.py`, which is absent, so its trap (gates/
# README.md shape #2) is exercised WITHOUT a compiler running.
CHEAP |= {"demo.sh", "lintable-gate.sh", "plant.sh", "run-f64.sh", "run-port-mm.sh", "gate.sh"}
# e2e.sh is the 8-stage end-to-end gate: it would run REAL bend, and the brief is
# explicit that it must be run with nothing else compiling. Three units are writing.
NEVER_RUN = {"e2e.sh"}
# gen.sh is MEASURED, NOT SPAWNED. `cd "$(dirname "$0")/../../.."` puts it in
# /Users/cyberistic/src and its `mkdir -p "$D"` then writes 7 .bend files THERE,
# outside the repo, on every run. The audit must not be the thing that pollutes
# the parent directory, so its one measurement is recorded below and it is never
# spawned again. (checks/gen.sh:36-38, verified.)
GEN_EVIDENCE = """\
$ sh checks/gen.sh ; echo "EXIT=$?"
DIED     k=0  checks/gen.sh: line 78: ./bin/bend: No such file or directory|
DIED     k=1  ... (k=2 .. k=6 identical) ...
--- controls ---
CONTROL must-survive (k=0, 2^48-2^16) exit=127 (want 0)
CONTROL must-die     (k=3, 2^48)       exit=127 (want nonzero)
EXIT=0
  -> wrote /Users/cyberistic/src/.agents/slop/w64/cands/cand{0..6}.bend
"""

# Shape 1 of gates/README.md, verbatim, with its mechanism attached.
SHAPE1 = r"""a failing producer is not the script's exit status"""
SHAPE2 = r"""an EXIT trap's last command becomes the script's"""
SHAPE3 = r"""the script does not parse under sh"""


@dataclass
class Finding:
    file: str
    line: int
    shape: str
    text: str
    detail: str

    def __str__(self) -> str:
        return f"{self.file}:{self.line}  [{self.shape}]  {self.text}"


@dataclass
class Row:
    name: str
    cwd: str = "-"
    cwd_ok: str = "-"
    findings: list[Finding] = field(default_factory=list)
    ran: str = "not-run"
    exit_status: str = "-"
    stdout_lines: int = -1
    stdout_head: str = ""
    stderr_head: str = ""
    claims: int = -1
    cwd_line: int = -1
    outside_cds: list = field(default_factory=list)
    verdict: str = "?"


# ---------------------------------------------------------------- static layer


def resolve_cd(script: Path, raw: str, vars_: dict[str, Path]) -> tuple[str, bool]:
    """Resolve the `cd` a script performs, and say whether it lands inside REPO.

    `dirname "$0"` is checks/, so `../..` is the repo root and `../../..` is two
    levels ABOVE it. That is the sb-gate.sh bug: every relative path after the cd
    then names a file that does not exist, and only the comparison notices.

    Three forms are NOT defects and must not be reported as findings, because an
    audit that cries wolf is the very failure this census is looking for:
    `cd "$(dirname "$0")"` lands on checks/ (legitimate -- a script reaching its own
    siblings), and `cd "$ROOT"` lands wherever an earlier `ROOT=$(cd .. && pwd)`
    already put it. Both are resolved, not assumed.
    """
    if re.fullmatch(r'cd\s+"?\$\{(?:\w+)\}?"?', raw.strip()) and re.search(r'cd\s+"?\$\{(\w+)\}?"?$', raw.strip()):
        name = re.search(r'cd\s+"?\$\{(\w+)\}?"?$', raw.strip()).group(1)
        if name in vars_:
            real = vars_[name]
            return (str(real), real == REPO or REPO in real.parents)
    m = re.search(r'\$\(dirname "?\$0"?\)([/.][^"\')\s]*|"[^"]*")?', raw)
    if m:
        tail = m.group(1).strip('"') if m.group(1) else ""
        # tail is RELATIVE to the script's own directory ("/.." is how a shell spells
        # one level up). Path.__truediv__ with a leading-slash operand REPLACES the
        # left side, so the slash has to come off or every cd resolves to "/".
        target = script.parent / tail.lstrip("/") if tail not in ("", ".") else script.parent
    elif re.search(r'\$\(dirname "?\$0"?\)\s*&&', raw):
        target = script.parent
    else:
        vd = re.search(r'cd\s+"?\$\{?(\w+)\}?/', raw)
        # `_d=${0%/*}` is the POSIX spelling of dirname; `$d` is the zsh one.
        if vd and vd.group(1) in ("_d", "d", "HERE", "here"):
            # `_d=${0%/*}` IS the script's own directory, so `_d/../..` is two levels
            # above it -- do not strip the first component as though it were a
            # `$(dirname)` prefix, or every such cd loses a level and reads INSIDE.
            tail = re.split(r'\s|["\'|;&]', raw.split(vd.group(1) + "/", 1)[1], 1)[0]
            target = script.parent / tail.lstrip("/")
        else:
            arg = re.search(r'cd\s+"?([^"\'\s]+)', raw)
            if not arg:
                return ("unresolved", False)
            word = arg.group(1)
            target = Path(word) if word.startswith("/") else REPO / word
    try:
        real = Path(str(target.resolve()))
    except OSError:
        return (f"unresolvable:{target}", False)
    inside = real == REPO or REPO in real.parents
    return (str(real), inside)


def static_findings(script: Path) -> tuple[Row, list[Finding]]:
    row = Row(name=script.name)
    lines = script.read_text(errors="replace").splitlines()
    row.cwd_ok = "no-cd"
    # `VAR=$(cd .. && pwd)` assignments, so a later `cd "$VAR"` is resolved rather
    # than reported as a relative path. Scanned first, in file order.
    vars_: dict[str, Path] = {}
    for raw in lines:
        a = re.match(r'\s*(\w+)=.*cd\s', raw)
        if a:
            dest, _ = resolve_cd(script, raw, vars_)
            if not dest.startswith("un"):
                vars_[a.group(1)] = Path(dest)

    for n, raw in enumerate(lines, 1):
        s = raw.strip()

        # (1) where does the cd land? A `cd` inside a comment is prose ABOUT a cd,
        #     and sb-gate.sh's own header quotes the bad line it was fixed for --
        #     reading that as a finding is the audit reporting itself.
        if s.startswith("#"):
            continue
        # The FIRST one defines the working root and is
        #     the one that decides; later ones (`cd "$ROOT"`) only follow it, so they
        #     are not counted again. Reporting the last one instead let e2e.sh,
        #     run-all.sh and substrate-check.sh read INSIDE -- their own `cd "$ROOT"`
        #     overwrote a `../..` that had already landed outside the repo.
        if re.match(r"^cd\s", s) or 'cd "$(dirname' in s or "cd \"$" in s:
            dest, inside = resolve_cd(script, s, vars_)
            if not inside:
                row.outside_cds.append((n, s, dest))
                if row.cwd_ok in ("no-cd", "INSIDE"):
                    row.cwd = dest
                    row.cwd_ok = "OUTSIDE-REPO"
                    row.cwd_line = n
            elif row.cwd_ok == "no-cd":
                row.cwd, row.cwd_ok, row.cwd_line = dest, "INSIDE", n
        if re.search(r'\$\(cd "?\$\{?_?d', s) or 'dirname "$0"/..' in s:
            pass

        # (2) swallowed failure around a comparison / producer
        if re.search(r"\|\|\s*(true|:)\s*$", s):
            row.findings.append(
                Finding(
                    script.name,
                    n,
                    "S2 ||-swallow",
                    s,
                    "the producer's status is discarded; the comparison below sees "
                    "whatever it got and cannot report the producer dying",
                )
            )
        if re.search(r"^\s*set \+e\b", s):
            row.findings.append(
                Finding(
                    script.name,
                    n,
                    "S2 set +e",
                    s,
                    "errexit is off from here to the next `set -e`; any command in "
                    "that window may fail silently",
                )
            )

        # (3) missing input read as a pass: `if [ -f X ]` guarding only the pass
        if re.match(r"^if \[ -[efs] ", s) or re.search(r"if \[ ! -[efs] ", s):
            body = "\n".join(lines[n : n + 8])
            if "exit" not in body and re.search(r"\b(then)?\s*$", s):
                row.findings.append(
                    Finding(
                        script.name,
                        n,
                        "S3 guarded-absent",
                        s,
                        "no else arm: a MISSING input skips the comparison entirely "
                        "and the script continues to a clean exit",
                    )
                )

        # (5) early exit 0
        if re.match(r"^exit 0\s*$", s):
            row.findings.append(
                Finding(
                    script.name,
                    n,
                    "S5 exit 0",
                    s,
                    "unconditional success; check what guarded the line above it",
                )
            )

        # shapes already recorded in gates/README.md
        if re.search(r"^trap .*EXIT", s):
            row.findings.append(
                Finding(
                    script.name,
                    n,
                    "R2 trap-EXIT",
                    s,
                    SHAPE2,
                )
            )
        if re.search(r"\$\{=\w+\}", s):
            row.findings.append(Finding(script.name, n, "R4 zsh-array", s, "zsh-only ${=}"))
        if "<(" in s:
            row.findings.append(Finding(script.name, n, "R3 process-sub", s, "bashism <( )"))

        # (4) reads a path nobody writes. Only READ verbs count: an OUTPUT the script
        #     itself writes cannot be a missing input, and flagging those is the noise
        #     that lets a real finding hide. A $RUN/$W/$TMP path is by construction an
        #     output, so it is out of scope for this shape entirely.
        if ">" in s and not re.search(r"(cat|wc\s+-l|cmp|grep)\b[^>]*<", s):
            continue
        if s.startswith("#"):
            continue  # prose about a path is not a read of it
        reads = re.search(r"\b(cat|cmp|wc|grep|diff|test|\[)\b", s)
        if not reads:
            continue
        # A `$VAR/...` prefix is an OUTPUT this script creates (mktemp dirs, $RUN,
        # $OUT), so it can never be a missing INPUT. Without the `$` in the
        # lookbehind the regex re-anchors on `RUN/...` and reports 59 phantom
        # findings, which is how a real one gets lost.
        for path in re.findall(r'(?<![\w./$-])((?:[\w.-]+/)*[\w.-]+\.(?:txt|tsv|json|rows|out|err|md|bend|log))(?![\w/])', s):
            if any(cand.exists() for cand in (REPO / path, script.parent / path, REPO / ".agents/slop" / path)):
                continue
            row.findings.append(
                Finding(
                    script.name,
                    n,
                    "S4 read-missing",
                    s,
                    f"{path} exists nowhere under the repo: an input the comparison "
                    f"names but the tree does not hold",
                )
            )

    for n, src, dest in row.outside_cds:
        row.findings.append(
            Finding(
                script.name, n, "S1 cd-outside-repo", src,
                f"resolves to {dest}, which is not under the repo root {REPO}; "
                f"every relative path after this line names nothing",
            )
        )
    return row, row.findings


# --------------------------------------------------------------- dynamic layer


def dynamic(script: Path) -> tuple[str, str, str, str]:
    """Run a script from a neutral cwd and report (status, stdout lines, heads).

    `timeout` is not installed here; perl's alarm is the port. rc=142 is MY alarm
    and is recorded as TIMEOUT, never as a verdict.
    """
    # Under the interpreter the shebang names: running a zsh gate under sh is
    # gates/README.md shape #3 (a gate that cannot parse is a gate nobody reads)
    # and would be a finding about my harness rather than about the gate.
    shell = script.read_text(errors="replace").splitlines()[0].lstrip("#!").strip() or "sh"
    cmd = ["perl", "-e", "alarm shift; exec @ARGV", "45", shell, str(script)]
    try:
        p = subprocess.run(cmd, cwd="/", capture_output=True, text=True, timeout=90)
    except subprocess.TimeoutExpired:
        return ("TIMEOUT(alarm)", "", "", "")
    return (str(p.returncode), p.stdout + p.stderr, (p.stdout.strip().splitlines() or [""])[0][:160], "")


# A section banner (`### A.`, `---`, `====`) is not a verdict. What counts is a line
# that MAKES A CLAIM about the thing being gated: a denominator, a verdict word, a
# row count, a status, or a diff. Printing banners and exiting 0 is the shape this
# census is hunting, so "printed something" is explicitly not good enough.
VERDICT = re.compile(
    r"(DENOMINATOR|VERDICT|MATCHES|DIVERGES|GREEN|RED |NOT GREEN|REFUS|PASS|FAIL|"
    r"INCONCLUSIVE|DIED|SURVIVED|IDENTICAL|STALE|PLANT|NOREF|rows|exit=|rc=|CONTROL|"
    r"ROUTE|ALARM|OK\b|unchanged|NOTHING MOVED|rows that MOVED|moved \d)",
    re.I,
)
BANNER = re.compile(r"^\s*(#|-{3,}|={3,}|\*{3,}|###?\s|step\s|note\s|\d+\s+of\s|\s*$)")


def classify(row: Row, status: str, out: str) -> str:
    """A gate lies if it is green and made no claim. Silence is the tell."""
    if status.startswith("TIMEOUT"):
        return "unsettled (my alarm)"
    claims = [l for l in out.splitlines() if not BANNER.match(l) and VERDICT.search(l)]
    row.claims = len(claims)
    if status != "0":
        return f"red on exit {status} (NOT a false pass)"
    if not claims:
        return "LIES: exit 0, ZERO verdict lines"
    if row.cwd_ok == "OUTSIDE-REPO" or row.cwd_ok == "no-cd":
        return f"green, {len(claims)} claim(s) -- but cwd is {row.cwd_ok}"
    return f"green, {len(claims)} claim(s)"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run", choices=["SAFE", "ALL"], help="actually spawn the scripts")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    scripts = sorted(CHECKS.glob("*.sh"))
    rows: list[Row] = []
    for script in scripts:
        row, _ = static_findings(script)
        rows.append(row)

    if args.run:
        for row in rows:
            if row.name in NEVER_RUN:
                row.ran = "skipped (racing another unit)"
                continue
            if row.name == "gen.sh":
                # MEASURED ONCE, NEVER SPAWNED. Its `cd` lands in /Users/cyberistic/src
                # and `mkdir -p "$D"` (checks/gen.sh:38) then writes seven .bend files
                # THERE, outside the repo, on every run. The audit must not be the thing
                # that pollutes the parent directory, so the measurement is recorded and
                # the script is not run again.
                row.ran = "measured once, NOT spawned: it writes outside the repo"
                row.exit_status, row.claims = "0", 9
                row.verdict = "LIES: exit 0, 9 claims, every one FALSE (GEN_EVIDENCE)"
                continue
            if args.run == "SAFE" and row.name not in CHEAP:
                row.ran = (
                    "skipped (UNSAFE: mutates the live tree)"
                    if row.name in UNSAFE
                    else "skipped (expensive: spawns bend)"
                )
                continue
            status, out, head, _ = dynamic(CHECKS / row.name)
            row.ran, row.exit_status, row.stdout_lines = status, status, len(out.splitlines())
            row.stdout_head = head
            row.verdict = classify(row, status, out)

    if args.json:
        print(json.dumps([r.__dict__ for r in rows], indent=2, default=str))
        return 0

    print(f"DENOMINATOR: {len(rows)} shell files under checks/\n")
    hdr = f"{'file':<22} {'cd lands':<14} {'exit':<5} {'clm':<4} verdict"
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        print(f"{r.name:<22} {r.cwd_ok:<14} {r.exit_status:<5} {r.claims:<4} {r.verdict}")

    print("\n== FINDINGS ==")
    by_file: dict[str, list[Finding]] = {}
    for r in rows:
        for f in r.findings:
            by_file.setdefault(r.name, []).append(f)
    for r in rows:
        fs = by_file.get(r.name, [])
        if not fs:
            continue
        print(f"\n-- {r.name}")
        for f in fs:
            print(f"   {f.file}:{f.line}  [{f.shape}]")
            print(f"       src: {f.text}")
            print(f"       why: {f.detail}")

    lies = sum(1 for r in rows if r.verdict.startswith("LIES"))
    unreachable = sum(1 for r in rows if r.cwd_ok == "OUTSIDE-REPO")
    print(f"\nCAN EXIT 0 WITHOUT HAVING RUN (dynamic, SAFE set): {lies}/{len(rows)}")
    print(f"cd RESOLVES OUTSIDE THE REPO (static, all files): {unreachable}/{len(rows)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())