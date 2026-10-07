#!/usr/bin/env python3
"""FOUR PLANTS. Each asserts a property, and each is asserted so that a detector which only
DIFFED would pass the first and fail the rest.

    .venv/bin/python .agents/slop/ledger/plants.py

  1 SILENT GROWTH -- a ledger appended by ANOTHER process must be QUIET. A detector that
    flags "the ledger moved" is a change-detector, which `AGENTS.md` calls harmful.
  2 BYTE-IDENTICAL, OPPOSITE VERDICTS -- two runs leave the ledger with THE SAME BYTES. One
    only reads it, the other reads and rewrites it. This is the falsifier: a diff cannot tell
    them apart, so a detector that reports "0 disagreements" over them is measuring nothing.
  3 SELF-REWRITE -- the run that consults a ledger and truncates it IS a diary.
  4 APPEND IS NOT A REWRITE -- a run that reads and APPENDS cannot delete what it read, so it
    is a CACHE. Flagging it is the false positive item 5 forbids.
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from runit import classify, run  # noqa: E402

LEDGER = "pin.rows"


def body(rows):
    return "".join(f"{r}\n" for r in rows)


def verdict(tree, script, *args):
    """(verdict-token, ledger-bytes-after). Runs `script` in `tree` under the audit hook."""
    out = os.path.join(tree, "trace.jsonl")
    if os.path.exists(out):
        os.remove(out)
    env = dict(os.environ, PYTHONPATH=os.path.join(HERE, "tracesite"),
               LEDGER_TRACE_OUT=out, LEDGER_TRACE_ROOT=tree)
    subprocess.run([sys.executable, os.path.join(tree, script), *args],
                   cwd=tree, env=env, capture_output=True, text=True)
    reads, writes = set(), {}
    if os.path.exists(out):
        import json
        for ln in open(out, encoding="utf-8"):
            rec = json.loads(ln)
            if os.path.basename(rec["p"]) in ("trace.jsonl", script):
                continue
            (writes.setdefault(rec["p"], set()).add(rec.get("m", "")) if rec["w"]
             else reads.add(rec["p"]))
    tok = "PIN"
    for p, modes in writes.items():
        if p in reads:
            tok = classify(p, modes)
    led = os.path.join(tree, LEDGER)
    return tok, (open(led, "rb").read() if os.path.exists(led) else b"")


READER = """import os
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pin.rows")
rows = [l for l in open(p).read().splitlines() if l.strip()] if os.path.exists(p) else []
print("READ", len(rows))
"""

REWRITER = """import os
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pin.rows")
rows = [l for l in open(p).read().splitlines() if l.strip()] if os.path.exists(p) else []
open(p, "w").write("".join(r + "\\n" for r in rows))
print("READ", len(rows), "REWROTE", len(rows))
"""

APPENDER = """import os
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pin.rows")
rows = [l for l in open(p).read().splitlines() if l.strip()] if os.path.exists(p) else []
open(p, "a").write("gate-c.py\\tpy-main\\n")
print("READ", len(rows), "APPENDED 1")
"""


def tree(script):
    td = tempfile.mkdtemp()
    open(os.path.join(td, script), "w").write(
        {"reader.py": READER, "rewriter.py": REWRITER, "appender.py": APPENDER}[script])
    return td


def main():
    checks = []

    # PLANT 1 -- SILENT GROWTH. Another process appended a row; this run only reads.
    t = tree("reader.py")
    open(os.path.join(t, LEDGER), "w").write(body(["a.py", "b.py", "c.py", "d.py"]))
    tok, after = verdict(t, "reader.py")
    checks.append(("1: a ledger another process GREW is read quietly (PIN, not a diary)",
                   tok == "PIN" and len(after.splitlines()) == 4, f"verdict={tok}"))

    # PLANT 2 -- BYTE-IDENTICAL, OPPOSITE VERDICTS. THE FALSIFIER.
    t1 = tree("reader.py")
    open(os.path.join(t1, LEDGER), "w").write(body(["a.py", "b.py", "c.py"]))
    tok1, bytes1 = verdict(t1, "reader.py")
    t2 = tree("rewriter.py")
    open(os.path.join(t2, LEDGER), "w").write(body(["a.py", "b.py", "c.py"]))
    tok2, bytes2 = verdict(t2, "rewriter.py")
    checks.append(("2: two runs leave BYTE-IDENTICAL ledgers and get DIFFERENT verdicts, so the "
                   "detector reads the WRITER and not the diff",
                   bytes1 == bytes2 and tok1 == "PIN" and tok2 == "DIARY-REWRITE",
                   f"bytes_equal={bytes1 == bytes2} reader={tok1} rewriter={tok2}"))

    # PLANT 3 -- SELF-REWRITE IS A DIARY.
    t3 = tree("rewriter.py")
    open(os.path.join(t3, LEDGER), "w").write(body(["a.py"]))
    tok3, _ = verdict(t3, "rewriter.py")
    checks.append(("3: the run that reads AND truncates the ledger is a DIARY",
                   tok3 == "DIARY-REWRITE", f"verdict={tok3}"))

    # PLANT 4 -- APPEND IS NOT A REWRITE. The false positive item 5 forbids.
    t4 = tree("appender.py")
    open(os.path.join(t4, LEDGER), "w").write(body(["a.py", "b.py"]))
    tok4, after4 = verdict(t4, "appender.py")
    checks.append(("4: read+APPEND is a CACHE, not a diary -- it cannot delete what it read",
                   tok4 == "DIARY-APPEND" and len(after4.splitlines()) == 3,
                   f"verdict={tok4} rows_after={len(after4.splitlines())}"))

    # PLANT 5 -- DEAD DETECTOR. An instrument that measures nothing must not report a diary.
    # A detector that cannot see a single ledger reports `PIN` for everything, which is the
    # vacuous-plant class `AGENTS.md` warns about: 0 disagreements over 0 comparisons.
    t5 = tree("reader.py")
    open(os.path.join(t5, LEDGER), "w").write(body(["a.py", "b.py", "c.py"]))
    out5 = os.path.join(t5, "trace.jsonl")
    env = dict(os.environ, LEDGER_TRACE_OUT=out5, LEDGER_TRACE_ROOT=t5)
    env.pop("PYTHONPATH", None)          # the hook is NOT installed
    subprocess.run([sys.executable, os.path.join(t5, "reader.py")], cwd=t5, env=env,
                   capture_output=True, text=True)
    seen = os.path.exists(out5) and len(open(out5).read().splitlines()) > 0
    checks.append(("5: with the hook ABSENT the detector observes 0 opens -- so `PIN` on a real "
                   "instrument is a MEASUREMENT and not an unobserved run",
                   not seen, f"hook_installed_and_saw_opens={seen}"))

    print("DIARY PLANTS")
    ok = 0
    for name, passed, note in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name}\n         {note}")
        ok += bool(passed)
    print(f"\n{ok}/{len(checks)} GREEN")
    return 0 if ok == len(checks) else 1


if __name__ == "__main__":
    sys.exit(main())