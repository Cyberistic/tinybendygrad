#!/usr/bin/env python3
"""THE MECHANICAL CHECK ON THE `arg` PAYLOAD: THE PAYLOAD TEXT IS THE ONLY THING INSERTED.

    .venv/bin/python .agents/slop/realizegaps/beforeafter.py

Four lanes read by path -- the two BEFORE ones captured from `HEAD` and the two AFTER ones
from the working tree. The claim is not "the diff is small". It is, per row:

    skeleton(AFTER) == skeleton(BEFORE)

where `skeleton(AFTER)` DELETES every `[...]` group and `skeleton(BEFORE)` rewrites
`CONST(v)` to `CONST/0[v]` and then deletes every `[...]`. So what is compared is the
OP/ARITY SEQUENCE, ITS ORDER, every `@<slot>` VALUE, every separator and every literal the
payload does not own. A row that changed for any other reason fails here.

Also reported, because they are the numbers a reviewer asks for first: rows added, rows
dropped, rows changed on each side, and the number of DISTINCT node tokens per lane -- which
is what says the payload carries information rather than length.

A throwaway probe whose reading goes into the commit message and the report. It reads lane
files, not the gate, and it says nothing about the port.
"""
import re
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
LANES = {"py-BEFORE": "ORC-BEFORE.rows", "py-AFTER": "ORC3.rows",
         "bd-BEFORE": "BD-BEFORE.rows", "bd-AFTER": "BD3.rows"}
PAYLOAD = re.compile(r"\[[^\]]*\]")
CONSTV = re.compile(r"CONST\((-?\d+)\)")
TOKEN = re.compile(r"[A-Z][A-Z_]+/[0-9]+")


def rows(name):
    out = {}
    for ln in (HERE / LANES[name]).read_text().splitlines():
        if "=" in ln:
            k, v = ln.split("=", 1)
            out[k] = v
    return out


def skel_after(v):
    return PAYLOAD.sub("", v)


def skel_before(v):
    return PAYLOAD.sub("", CONSTV.sub(lambda m: "CONST/0[%s]" % m.group(1), v))


def main():
    lanes = {k: rows(k) for k in LANES}
    base = set(lanes["py-BEFORE"])
    print("rows per lane            :", {k: len(v) for k, v in lanes.items()})
    print("rows ADDED vs py-BEFORE  :", {k: len(set(v) - base) for k, v in lanes.items()})
    print("rows DROPPED vs py-BEFORE:", {k: len(base - set(v)) for k, v in lanes.items()})
    bad = 0
    for k in ("py", "bd"):
        b, a = lanes[k + "-BEFORE"], lanes[k + "-AFTER"]
        both = sorted(set(b) & set(a))
        wrong = [r for r in both if skel_before(b[r]) != skel_after(a[r])]
        chg = [r for r in both if b[r] != a[r]]
        toks = Counter(t for r in both for t in TOKEN.findall(a[r]))
        print(f"\n{k}: {len(chg)} of {len(both)} rows changed; "
              f"{len(wrong)} of them changed by something OTHER than the payload text"
              + (f"  <-- {wrong[:6]}" if wrong else ""))
        for r in wrong[:6]:
            print(f"    {r}\n      before {b[r]!r}\n      after  {a[r]!r}")
        print(f"   distinct node TOKENS in the AFTER lane: {len(toks)}"
              f" (most common: {toks.most_common(4)})")
        bad += len(wrong)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())