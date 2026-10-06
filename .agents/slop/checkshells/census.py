#!/usr/bin/env python3
"""Census of checks/*.sh: population BY DISCOVERY (os.walk + endswith), then per-file
facts. Writes SHELLS.tsv and a runs/ tree of captured stdout/stderr.

The population is discovered, never listed. The DRIVER table below is a hand-list and
is admitted: it maps each script to the paths it names, and existence is checked with
os.path.exists, so a stale name is visible as GONE rather than assumed.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CHECKS = os.path.join(ROOT, "checks")
RUNS = os.path.join(ROOT, ".agents", "slop", "checkshells", "runs")
STATIC = "--static" in sys.argv  # reuse captures in runs/, run nothing

# driver table -- ADMITTED hand-list of what each script names. Not the population.
DRIVERS = {
    "bounded-selftest.sh": ["checks/bounded.py"],
    "classify.sh": [".agents/slop/mutledger/BLOBHIST.tsv"],
    "demo.sh": [".agents/slop/substrate-check.sh"],
    "disarm.sh": [".agents/slop/substrate-check.sh"],
    "e2e.sh": [".agents/slop/e2e_mm.py", ".agents/slop/e2e_mm.bend",
               ".agents/slop/e2e_mm_run.mjs", ".agents/slop/e2e_mm_gate.py",
               ".agents/slop/opsbend-milestone.sh",
               ".agents/slop/e2e_port/run-port-mm.sh", ".agents/slop/f64/run-f64.sh"],
    "gate.sh": [".agents/slop/shlscope/gen.py", "bin/bend"],
    "gen.sh": ["bin/bend"],
    "lint_demo.sh": [".agents/slop/norm/lint_norm.py", ".agents/slop/mm-dt-gate.py"],
    "lintable-gate.sh": [".agents/slop/lintable/lintable-oracle.py",
                         ".agents/slop/lintable/lintable-probe.bend", "bin/bend"],
    "plant.sh": ["checks/derive.py", "checks/measure.py", "checks/convert2.py",
                 "checks/agree.py", "bin/bend"],
    "run-all.sh": ["checks/derive.py", "checks/measure.py", "checks/empty-probe.py",
                   "checks/preamble-oracle.py", "checks/convert2.py", "checks/agree.py",
                   "bin/bend"],
    "run-f64.sh": [".agents/slop/portexec/run-kernel.sh", ".agents/slop/f64/oracle_f64.py",
                   ".agents/slop/f64/emit-f64.bend", ".agents/slop/f64/repair-dupes.py"],
    "run-port-mm.sh": [".agents/slop/portexec/run-kernel.sh",
                       ".agents/slop/e2e_port/coverage.py", ".agents/slop/e2e_port/plant.py"],
    "sb-gate.sh": ["oracles/schedule-bodies/BEFORE-rows.rows",
                   ".agents/slop/schedule-bodies/sb-oracle.py",
                   ".agents/slop/schedule-bodies/sb-diff.py", "bin/bend"],
    "substrate-check.sh": ["checks/substrate.py"],
    "walk-mutate.sh": ["bin/bend"],
    "wt-sync.sh": [],
}

# what each script DRIVES, in one phrase
DRIVES = {
    "bounded-selftest.sh": "exec .venv/bin/python checks/bounded.py --selftest",
    "classify.sh": "classify a mutation sandbox against the live tree + git blob history",
    "demo.sh": "the substrate PROVENANCE split, with a probe planted and removed",
    "disarm.sh": "the paired disarm of the substrate PORT ALARM via git update-index",
    "e2e.sh": "the seven-stage end-to-end gate",
    "gate.sh": "the shlscope SHIFT-AMOUNT gate: CPython vs Bend, two lanes",
    "gen.sh": "the W-2 ladder generator + driver around ./bin/bend",
    "lint_demo.sh": "show both branches of .agents/slop/norm/lint_norm.py",
    "lintable-gate.sh": "the ops.py linear-rule-table gate: CPython vs interpreted vs native",
    "plant.sh": "plant one token in cstyle.bend's fixture and count rows moved",
    "run-all.sh": "every number in CSTYLE2.md from a $TMPDIR snapshot",
    "run-f64.sh": "an f64 kernel through the port (e2e stage 7)",
    "run-port-mm.sh": "the matmul through the port (e2e stage 6)",
    "sb-gate.sh": "the rule-body gate: base rows + CPython oracle vs the port",
    "substrate-check.sh": "exec .venv/bin/python checks/substrate.py",
    "walk-mutate.sh": "arm a plant/disarm and diff whole name=value rows",
    "wt-sync.sh": "mirror tinybendygrad/ into the workaround tree",
}

# which scripts invoke ./bin/bend (directly or through bounded.py) -> READ-ONLY here
COMPILES_BEND = {
    "e2e.sh", "gate.sh", "gen.sh", "lintable-gate.sh", "plant.sh", "run-all.sh",
    "run-f64.sh", "run-port-mm.sh", "walk-mutate.sh",
    "disarm.sh", "substrate-check.sh",
    # NOT obvious: this SHIM execs `checks/bounded.py --selftest`, and the selftest's
    # case 12 runs `./bin/bend <0-byte file> --check-only`. So it DOES invoke bend,
    # twice (subprocess + guard). It was run once before that was discovered.
    "bounded-selftest.sh",
}
NOTES = {
    "bounded-selftest.sh": "ran once, before the bend case was found: bounded.py --selftest "
                           "case 12 runs ./bin/bend --check-only (x2)",
}
# sb-gate.sh names bin/bend but REFUSES before it while ORACLE/DIFFER are absent, so the
# two invocations below never reach the compile. If those are restored, move it back to
# COMPILES_BEND and do not run it here.

# scripts this unit may run without compiling bend
RUNNABLE = {
    "sb-gate.sh": [["sh", "checks/sb-gate.sh"], ["sh", "checks/sb-gate.sh", "--substrate"]],
    "bounded-selftest.sh": [["sh", "checks/bounded-selftest.sh"]],
    "classify.sh": [["zsh", "checks/classify.sh", ".agents/slop/checkshells/emptysandbox"]],
    "demo.sh": [["zsh", "checks/demo.sh"]],
    "lint_demo.sh": [["zsh", "checks/lint_demo.sh"]],
    "wt-sync.sh": [["sh", "checks/wt-sync.sh"]],
}


def class_of(name: str, text: str) -> str:
    if re.search(r"^\s*exec\s+.*\.venv/bin/python\s+checks/", text, re.M):
        return "SHIM"
    if name in ("gate.sh", "sb-gate.sh", "lintable-gate.sh", "e2e.sh",
                "run-f64.sh", "run-port-mm.sh", "lint_demo.sh"):
        return "GATE"
    return "DRIVER"


def token_of(out: str) -> str:
    if "REFUSED, NOT A VERDICT" in out:
        return "REFUSED"
    for pat in ("selftest PASS", "selftest FAIL", "BOTH BRANCHES MEASURED",
                "DID NOT FLIP", "THE LINT DID NOT FLIP"):
        if pat in out:
            return pat
    if re.search(r"^helpers=.*ops=", out, re.M):
        return "SUBSTRATE"
    lines = [l for l in out.splitlines() if l.strip()]
    return (lines[-1][:70] if lines else "(no stdout)")


def load_rcs() -> dict:
    d = {}
    p = os.path.join(RUNS, "rc.tsv")
    if os.path.exists(p):
        for line in open(p):
            if "\t" in line:
                k, v = line.rstrip("\n").split("\t", 1)
                d[k] = v
    return d


def save_rcs(d: dict) -> None:
    with open(os.path.join(RUNS, "rc.tsv"), "w") as fh:
        for k in sorted(d):
            fh.write(f"{k}\t{d[k]}\n")


def main() -> int:
    os.makedirs(RUNS, exist_ok=True)
    os.makedirs(os.path.join(ROOT, ".agents/slop/checkshells/emptysandbox"), exist_ok=True)
    rcs_all = load_rcs()

    # ---------------- POPULATION BY DISCOVERY ----------------
    found = []
    for dirpath, _dirs, files in os.walk(CHECKS):
        for f in files:
            if f.endswith(".sh"):
                found.append(os.path.relpath(os.path.join(dirpath, f), ROOT))
    found.sort()

    agents = open(os.path.join(ROOT, "AGENTS.md")).read()

    rows = []
    for rel in found:
        name = os.path.basename(rel)
        text = open(os.path.join(ROOT, rel)).read()
        drivers = DRIVERS.get(name, [])
        present = {d: os.path.exists(os.path.join(ROOT, d)) for d in drivers}
        # NAMED BY PATH (the count AGENTS.md's own critic used) vs by BARE BASENAME.
        # Word-boundary matched so `sb-gate.sh` does not falsely "name" `gate.sh`.
        named_path = bool(re.search(r"(?:^|[\s`(])checks/" + re.escape(name) + r"(?![\w.-])",
                                    agents))
        named_base = bool(re.search(r"(?<![\w-])" + re.escape(name) + r"(?![\w-])", agents))
        cls = class_of(name, text)
        # the FOUR RECORDED ways a shell gate lied here (gatekit's README, not a vibe):
        #   1 `&&` consuming a diff's status under `set -e`
        #   2 an `EXIT` trap whose exit status becomes rm's
        #   3 `<( )` process substitution, which POSIX sh cannot parse
        #   4 `${=VAR}` zsh word-split, which never expands under sh
        h_amp = bool(re.search(r"diff[^\n]*&&", text))
        h_trap = bool(re.search(r"trap\s+[^\n]*\bEXIT\b", text))
        h_proc = "<(" in text
        h_zsplit = "${=" in text

        rc, token, note = "(read-only)", "(not run)", "compiles bend"
        if STATIC and (name + ".0") in rcs_all:
            rcs, toks = [], []
            i = 0
            while f"{name}.{i}" in rcs_all:
                rcs.append(rcs_all[f"{name}.{i}"])
                toks.append(token_of(open(os.path.join(RUNS, f"{name}.{i}.out")).read()))
                i += 1
            rc, token, note = " ; ".join(rcs), " | ".join(toks), "captured earlier"
        elif name not in COMPILES_BEND:
            note = ""
            invs = RUNNABLE.get(name, [])
            rcs, toks = [], []
            for i, inv in enumerate(invs):
                tag = f"{name}.{i}"
                try:
                    p = subprocess.run(inv, cwd=ROOT, capture_output=True, text=True,
                                       timeout=900)
                    out, err, r = p.stdout, p.stderr, p.returncode
                except subprocess.TimeoutExpired as e:
                    out, err, r = (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or ""), "", "TIMEOUT"
                open(os.path.join(RUNS, tag + ".out"), "w").write(out)
                open(os.path.join(RUNS, tag + ".err"), "w").write(err)
                rcs_all[tag] = str(r)
                rcs.append(str(r))
                toks.append(token_of(out))
            rc = " ; ".join(rcs)
            token = " | ".join(toks)

        note = NOTES.get(name, note)
        rows.append({
            "path": rel, "class": cls,
            "drives": DRIVES.get(name, ""),
            "drivers": ";".join(f"{d}{'' if present[d] else ' [GONE]'}" for d in drivers) or "(none)",
            "rc": rc, "token": token,
            "agents_named": ("path" if named_path else "") + ("+base" if named_base else "") or "no",
            "hazards": "".join(k for k, v in (
                ("&&-diff", h_amp), ("trap-EXIT-rm", h_trap),
                ("<( )", h_proc), ("${=}", h_zsplit)) if v) or "none",
            "note": note,
        })

    cols = ["path", "class", "drives", "drivers", "rc", "token", "agents_named", "hazards", "note"]
    save_rcs(rcs_all)
    with open(os.path.join(ROOT, ".agents/slop/checkshells/SHELLS.tsv"), "w") as fh:
        fh.write("\t".join(cols) + "\n")
        for r in rows:
            fh.write("\t".join(str(r[c]).replace("\t", " ") for c in cols) + "\n")

    counts = {}
    for r in rows:
        counts[r["class"]] = counts.get(r["class"], 0) + 1
    print(json.dumps({"denominator": len(found), "classes": counts,
                      "found": found}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
