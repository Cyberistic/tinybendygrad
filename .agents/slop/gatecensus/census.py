#!/usr/bin/env python3
"""Tree-wide gate census. MEASURE ONLY -- this file never edits a gate or a .bend.

    .venv/bin/python .agents/slop/gatecensus/census.py --dry-run   # enumerate only
    .venv/bin/python .agents/slop/gatecensus/census.py             # run the census

WHY THIS FILE IS STRICT ABOUT ITS OWN VERDICTS
-----------------------------------------------
The failure mode this instrument must not have is a census that examines nothing
and reports all-clear. `substrate-check.sh` printed `SUBSTRATE CLEAN: 0 file(s)`
with no arguments for the life of the project. So, mechanically:

  PASS     rc == 0 AND stdout+stderr non-empty AND a verdict token was seen.
  FAIL     rc not in (0, 124, 142) AND output non-empty.
  NOT-RUN  our own alarm fired, or ZERO bytes on both streams, or rc==0 with output
           but no verdict token. A zero-byte run is a REFUSAL here
           (`graphcmp.py:2869` refuses `--dev NULL` with 0 bytes on stdout), not a
           pass. Five differ runs once returned rc=0 with zero bytes on both
           streams; running them plainly surfaced the error underneath.
  SKIP     the gate declared it needs arguments. Bare is a DIFFERENT instrument
           from "run with its population", and that is a different verdict from red.
  NOT-ATTEMPTED
           excluded by NAME because executing it would edit a tree that six units
           are writing into, or because it builds a gate's input rather than
           testing the port. Counted beside the attempted count, never green.

CLASSIFICATION IS EVIDENCE-BASED, NOT NAME-BASED. The only thing decided by name is
the SAFETY EXCLUSION, which must be decided before running. Whether a script is a
gate that passed or a one-shot measurement is decided by what it PRINTED. Name-based
classification of the verdict would be a rule compressed from an observation, and
the compression is where this tree's errors enter.

DEDUPLICATION IS A FINDING, NOT A CONVENIENCE. Five units wrote `probe-*.py` and
`norm()` variants. Byte-identical content collapses to one representative with its
aliases listed; near-identical content does NOT collapse, because under-counting
the suite is the same error as over-counting it.

VENDORED TREES ARE NOT GATES. `xd1/` alone holds four checked-out tinygrad
checkouts; `opstree/` another. A .py inside one is a COPY. Counting copies is how
a denominator inflates itself.

TREE-MUTATION TRIPWIRE. Every `*.bend`/`*.c`/`*.js` mtime+size under
`tinybendygrad/` is snapshotted before and after, so a gate that writes to the port
is REPORTED rather than silently tolerated. This instrument reports what the suite
does to the tree, it does not merely what the tree does to the suite.
"""
from __future__ import annotations

import concurrent.futures as cf
import hashlib
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
SLOP = os.path.join(ROOT, ".agents/slop")
OUT = os.path.join(SLOP, "gatecensus")
RUNS = os.path.join(OUT, "runs")
PY = os.path.join(ROOT, ".venv/bin/python")

VENDOR = {"xd1", "opstree", "references", "__pycache__", "_cleanup", "gatecensus"}

# SAFETY EXCLUSION. These either edit the tree (so running them against a
# concurrently-edited port is out of the question for a measuring instrument) or
# manufacture a gate's input rather than testing the port. Decided BEFORE running,
# because it has to be, and counted apart -- never reported green.
WRITES = re.compile(r"(mut|mutat|plant|arm|disarm|inject|corrupt|break|fixup|repair|"
                    r"^fix|\bfix\b|fix-|patch|hoist|build|^gen|_gen|writer|emit|"
                    r"mirror|plumb|apply|splice|replace|rewrite|sed-|stamp)", re.I)

ENTRY_POINTS = ["substrate-check.sh", "e2e.sh", "graphcmp-run.sh", "graphcmp-repro.sh",
                "graphcmp.py", "graphcmp-oracle.py", "tree-verdict.py"]

# Tiered leashes. A short NOT-RUN is not a claim of the same strength as a long one,
# so the leash in force is recorded per row.
TIER = [(300, 1), (90, 2), (25, 3)]

# A verdict token is a WORD that says a decision was made. The boundaries matter: an
# unbounded `FAIL` matches `FAILSAFE` and `MISMATCH` matches inside a path, so an
# unanchored list would mint PASSes out of prose. `\b` around each alternative.
VERDICT = re.compile(
    r"\b(PASS|PASSED|FAIL|FAILED|ERROR|ERR\b|WARM|COLD|CLEAN|DIRTY|MATCH|MISMATCH|"
    r"AGREE|DISAGREE|UNRESOLVED|UNJUDGED|OK\b|BAD\b|VERDICT|RED\b|GREEN)\b"
    r"|\b\d+\s+rows?\b"
    r"|^\s*total\b", re.I | re.M)


def shebang(path: str) -> str:
    try:
        with open(path, "rb") as fh:
            return fh.readline(200).decode("utf-8", "replace").strip()
    except OSError:
        return ""


def snapshot_port() -> dict:
    """mtime+size of every source file under tinybendygrad/ -- the tripwire."""
    snap = {}
    for base in ("tinybendygrad",):
        for dp, _d, fs in os.walk(os.path.join(ROOT, base)):
            for f in fs:
                p = os.path.join(dp, f)
                try:
                    st = os.stat(p)
                    snap[os.path.relpath(p, ROOT)] = (st.st_mtime_ns, st.st_size)
                except OSError:
                    pass
    return snap


def candidates() -> list[dict]:
    found: list[dict] = []
    for dirpath, dirs, files in os.walk(SLOP):
        dirs[:] = [d for d in dirs if d not in VENDOR]
        for name in files:
            if name.endswith((".pyc", ".pyo", ".bin", ".so", ".dylib", ".exe")):
                continue
            if not name.endswith((".sh", ".py")):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT)
            stem = name.rsplit(".", 1)[0]
            sb = shebang(path)
            toks = sb.split()
            found.append({
                "rel": rel, "base": name, "stem": stem,
                "sh": name.endswith(".sh"), "py": name.endswith(".py"),
                "exec": os.access(path, os.X_OK),
                "interp": toks[1] if sb.startswith("#!") and len(toks) > 1 else "",
                "bytes": os.path.getsize(path),
                "writes": bool(WRITES.search(stem)),
                "entry": name in ENTRY_POINTS,
            })
    return sorted(found, key=lambda r: r["rel"])


def group_by_content(cands: list[dict]) -> list[list[dict]]:
    buckets: dict[str, list[dict]] = {}
    for c in cands:
        with open(os.path.join(ROOT, c["rel"]), "rb") as fh:
            buckets.setdefault(hashlib.md5(fh.read()).hexdigest(), []).append(c)
    return [sorted(v, key=lambda c: c["rel"]) for v in buckets.values()]


def tier_of(rel: str, entry: bool) -> int:
    if entry:
        return 1
    low = rel.lower()
    if re.search(r"(gate|check|verdict|compare|cmp|diff|rows|sweep|census|liveness|"
                 r"reach|audit|prove|substrate|e2e|graphcmp)", low):
        return 2
    return 3


def clean_env() -> dict:
    return {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"NO_COLOR": "1"}


def first_verdict(text: str) -> str:
    for line in text.splitlines():
        s = line.strip()
        if s and VERDICT.search(s):
            return s[:200]
    return ""


def run_one(c: dict, timeout: int) -> dict:
    path = os.path.join(ROOT, c["rel"])
    if c["sh"] and c["exec"]:
        cmd, how = ["./" + c["base"]], "./x"
    elif c["sh"]:
        cmd, how = ["zsh", path], "zsh"
    else:
        cmd, how = [PY, path], "venv-py"
    c.update(cmd=" ".join(cmd), how=how, leash=timeout)
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=ROOT, env=clean_env(), timeout=timeout,
                           capture_output=True, text=True, errors="replace")
        rc, out, err, timed_out = p.returncode, p.stdout, p.stderr, False
    except subprocess.TimeoutExpired as e:
        def dec(x):
            return (x.decode("utf-8", "replace") if isinstance(x, bytes) else x) or ""
        rc, out, err, timed_out = 124, dec(e.stdout), dec(e.stderr), True
    except OSError as e:
        return {**c, "status": "NOT-RUN", "rc": None, "secs": 0.0, "verdict": "",
                "why": f"could not exec: {e}", "stdout": "", "stderr": ""}
    c.update(rc=rc, stdout=out, stderr=err, secs=round(time.time() - t0, 2))
    blob = out + "\n" + err
    c["verdict"] = first_verdict(out) or first_verdict(err)
    # ORDER MATTERS AND WAS WRONG ONCE. `rc != 0` was tested before the usage test, so a
    # gate that prints its usage and exits 1 was recorded FAIL. It is not red: it is a gate
    # that refused to run without its population, which is a DIFFERENT instrument from
    # "run with its population" and a different verdict from broken.
    if timed_out or rc == 142:
        c.update(status="NOT-RUN", why=f"OUR alarm at {timeout}s (rc={rc})")
    elif not blob.strip():
        c.update(status="NOT-RUN", why="zero bytes on both streams -- a refusal, not a pass")
    elif re.search(r"^\s*usage\b|^\s*\S+:\s+usage|\busage:\s", blob, re.I | re.M):
        c.update(status="SKIP", why="needs arguments; bare is a different instrument")
    elif rc != 0:
        c.update(status="FAIL", why=f"rc={rc}")
    elif c["verdict"]:
        c.update(status="PASS", why="rc=0, output present, verdict token seen")
    else:
        c.update(status="NOT-RUN", why="rc=0 with output but NO verdict token -- not a green I vouch for")
    return c


def main() -> int:
    if "--timeout" in sys.argv:
        TIER[0] = (int(sys.argv[sys.argv.index("--timeout") + 1]), 1)
    workers = 8
    for i, a in enumerate(sys.argv):
        if a == "-j":
            workers = int(sys.argv[i + 1])
    os.makedirs(RUNS, exist_ok=True)

    cands = candidates()
    groups = group_by_content(cands)
    excluded = [g for g in groups if all(c["writes"] for c in g)]
    attempted = [g for g in groups if not all(c["writes"] for c in g)]

    blob = ""
    for doc in ("AGENTS.md", ".agents/slop/agent-core.md"):
        try:
            blob += open(os.path.join(ROOT, doc)).read()
        except OSError:
            pass
    named = sum(1 for c in cands if c["base"] in blob or c["rel"] in blob)

    print(f"# DENOMINATOR")
    print(f"#   .sh/.py files under .agents/slop/ (vendored trees excluded)  {len(cands)}")
    print(f"#   DISTINCT by byte content (aliases collapsed)                  {len(groups)}"
          f"   [{len(cands) - len(groups)} aliases]")
    print(f"#   ATTEMPTED                                                  {len(attempted)}")
    print(f"#   NOT ATTEMPTED (writes/edits tree, or builds a gate's input)  {len(excluded)}")
    print(f"#   named in AGENTS.md or agent-core.md                          {named} of {len(cands)}")

    if "--dry-run" in sys.argv:
        for g in sorted(groups, key=lambda g: g[0]["rel"]):
            tag = "NOT-ATT" if all(c["writes"] for c in g) else f"T{tier_of(g[0]['rel'], g[0]['entry'])}   "
            al = "" if len(g) == 1 else f"  (+{len(g)-1} byte-identical)"
            print(f"  {tag}  {g[0]['rel']}{al}")
        return 0

    before = snapshot_port()
    jobs = [(g[0], TIER[tier_of(g[0]["rel"], g[0]["entry"]) - 1][0]) for g in attempted]
    print(f"# RUNNING {len(jobs)} gates, {workers} at a time. Leash by tier: "
          f"T1={TIER[0][0]}s T2={TIER[1][0]}s T3={TIER[2][0]}s")
    results: list[dict] = []
    t0 = time.time()
    with cf.ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {ex.submit(run_one, dict(c), t): c for c, t in jobs}
        for i, fut in enumerate(cf.as_completed(futs), 1):
            r = fut.result()
            results.append(r)
            print(f"[{i:4d}/{len(jobs)}] {r['status']:11s} rc={str(r['rc']):>4s} "
                  f"{r['secs']:7.2f}s leash={r['leash']:<4d} {r['rel']}  :: "
                  f"{(r.get('verdict') or r.get('why', ''))[:100]}", flush=True)
    after = snapshot_port()
    touched = sorted(k for k in before if k in after and before[k] != after[k])
    gone = sorted(k for k in before if k not in after)
    new = sorted(k for k in after if k not in before)

    results.sort(key=lambda r: (r["status"], r["rel"]))
    tally: dict[str, int] = {}
    for r in results:
        tally[r["status"]] = tally.get(r["status"], 0) + 1
    nonpass = sum(v for k, v in tally.items() if k != "PASS")
    print(f"#\n# VERDICTS over the {len(results)} ATTEMPTED   ({time.time()-t0:.0f}s wall)")
    for k, v in sorted(tally.items(), key=lambda kv: -kv[1]):
        print(f"#   {k:11s} {v:4d} / {len(results)}")
    print(f"#   PASS {tally.get('PASS',0)}   NON-PASS {nonpass}   NOT-ATTEMPTED {len(excluded)}"
          f"   COVERAGE {len(results)}/{len(groups)}")
    print(f"# TREE-MUTATION TRIPWIRE: {len(touched)} modified, {len(gone)} deleted, "
          f"{len(new)} appeared under tinybendygrad/ during {len(results)} runs")
    for k in (touched + gone + new)[:40]:
        print(f"#     {k}")

    with open(os.path.join(OUT, "manifest.json"), "w") as fh:
        json.dump({"generated": time.time(), "leash": dict(TIER), "workers": workers,
                   "candidates": cands,
                   "groups": [[c["rel"] for c in g] for g in groups],
                   "results": [{k: v for k, v in r.items() if k not in ("stdout", "stderr")}
                               for r in results],
                   "excluded": [g[0]["rel"] for g in excluded],
                   "tally": tally, "coverage": f"{len(results)}/{len(groups)}",
                   "tree_touched": touched, "tree_gone": gone, "tree_new": new},
                  fh, indent=1)
    for r in results:
        with open(os.path.join(RUNS, r["rel"].replace("/", "%") + ".json"), "w") as fh:
            json.dump(r, fh, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
