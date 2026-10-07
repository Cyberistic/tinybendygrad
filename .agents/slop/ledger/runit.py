#!/usr/bin/env python3
"""RUN AN INSTRUMENT AND REPORT, PER PROCESS, WHICH FILES IT READ AND WHICH IT WROTE.

The unit of the diary test is the PROCESS. `discover.py` reads source and
attributes a write to a line; that is a claim about text. This runs the
instrument and lets CPython's audit hook answer `open()` calls, so a
SAME-RUN verdict is a measurement and not an inference.

    .venv/bin/python .agents/slop/ledger/runit.py <argv...>

Prints, for each instrument run:
  READ  <path>      opened for reading
  WROTE <path>      opened for writing
  DIARY <path>      BOTH -- consulted and produced in the SAME PROCESS

A DIARY is only reported when the process also READ it, because a process that
writes a file it never consults is a producer, not a diary.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SITE = os.path.join(HERE, "tracesite")

# Written by the harness, not by the instrument under test; excluded so the
# trace does not report itself.
SELF = ("tracesite", "runit.py")


def run(argv, timeout=600):
    fd, out = tempfile.mkstemp(suffix=".jsonl")
    os.close(fd)
    os.remove(out)
    env = dict(os.environ)
    env["PYTHONPATH"] = SITE + os.pathsep + env.get("PYTHONPATH", "")
    env["LEDGER_TRACE_OUT"] = out
    # Widenable so a synthetic tree outside the repo (gates-pop.py --plant builds
    # one in $TMPDIR) is visible; paths outside the root stay absolute.
    env["LEDGER_TRACE_ROOT"] = os.environ.get("LEDGER_TRACE_ROOT", ROOT)
    try:
        p = subprocess.run(argv, cwd=ROOT, env=env, capture_output=True,
                           text=True, timeout=timeout)
        rc, so, se = p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        rc, so, se = "TIMEOUT", "", ""
    reads, writes, modes = set(), {}, {}
    if os.path.exists(out):
        for ln in open(out, encoding="utf-8"):
            try:
                rec = json.loads(ln)
            except ValueError:
                continue
            p_ = rec["p"]
            if any(s in p_ for s in SELF):
                continue
            if rec["w"]:
                writes.setdefault(p_, set()).add(rec.get("m", ""))
            else:
                reads.add(p_)
    os.path.exists(out) and os.remove(out)
    return rc, so, se, reads, writes


# A TRUNCATING write can launder: it replaces the consulted bytes with whatever
# this run concluded. An APPEND cannot -- it can only add, never delete or
# alter a row it read. So the two are different verdicts, and collapsing them
# is what makes a detector a change-detector.
TRUNCATING = ("w", "x", "r+", "w+")


def classify(path, wmodes):
    if any(any(t in m for t in TRUNCATING) for m in wmodes):
        return "DIARY-REWRITE"
    return "DIARY-APPEND"


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    print(f"$ {' '.join(argv[1:])}\n")
    rc, so, se, reads, writes = run(argv[1:])
    if so.strip():
        print(so.rstrip())
    if se.strip():
        print("--- stderr ---")
        print(se.rstrip()[:4000])
    print(f"\n[rc={rc}]  read {len(reads)} file(s), wrote {len(writes)} file(s) under {ROOT}")
    diary = []
    for p in sorted(writes):
        tag = classify(p, writes[p]) if p in reads else "WROTE"
        if p in reads:
            diary.append((p, tag))
        print(f"  {tag:14} {p}   modes={sorted(writes[p])}")
    for p in sorted(reads - set(writes)):
        print(f"  {'PIN (read, never written here)':14} {p}")
    print(f"\nDIARY COUNT {len(diary)}"
          + (f": {', '.join(f'{p} [{t}]' for p, t in diary)}" if diary else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))