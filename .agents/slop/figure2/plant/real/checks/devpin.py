#!/usr/bin/env python3
"""`checks/devpin.py` -- the DEVICE is a DECLARED PRECONDITION of the graphcmp comparison,
and this is the code that can fail when it is not.

    usage: .venv/bin/python checks/devpin.py [--pin DEV] [--plant satisfied|moved]

WHAT IT CLAIMS, AND WHY THE CLAIM IS WORTH A GATE.  `runs/graphcmp/D` was taken under
`DEV=CPU`, MEASURED three independent ways (`.agents/slop/devpin/00-device.md`).  `lin`'s
verdict turned out not to depend on it (`.agents/slop/devpin/02-lin-decision.md`), but
**14 of the 25 graphs' recorded py artifacts do** -- they are byte-identical records whose
py half moves the moment `--dev` is anything else, and they are recorded `AGREE`, so a device
change fires `expect-moved`/`byte-identical` and the failure reads as a PORT REGRESSION.
`checks/differ.py` does not pass `--dev` and is therefore protected by an argparse DEFAULT in
a third file (`graphcmp.py:2839`/`:2853`) that it does not know exists.  **A PRECONDITION
NOBODY DECLARED IS A PRECONDITION NOBODY CAN AUDIT; THIS IS THE DECLARATION AND THE AUDIT.**

TWO METHODS THAT SHARE NO ASSUMPTION, because SELF-CONSISTENCY IS NOT INDEPENDENCE and a
belt built on the same regex as the thing it checks catches nothing:

  M1  NAME.  Read the device out of the run's OWN artifacts: the `# devices py=[...]` header
      (52 files) and the `SGLOBAL,s<DEV>` `ParamArg` field (all 50 `D2-canon-*.txt`).  A
      STRING method -- it asks what the bytes SAY.

  M2  BYTES.  Re-emit one recorded graph under the pinned device and byte-compare against
      the recorded artifact.  A BYTE method -- it asks whether the bytes REPRODUCE, and it
      shares no token, no regex and no grammar with M1.  `--dev CPU` re-emits
      `D2-canon-py-lin.txt` byte for byte; `--dev METAL` does not (MEASURED, 44 rows and two
      `Opt`s against 46 and one).

EVERY VALUE IS PRINTED **BEFORE** THE EXIT.  MEASURED WHY: a gate elsewhere reported
`DID NOT REFUSE` for a CORRECT refusal, because the refusal exited before printing the value
being asserted, so the marker found nothing to match.  A refusal you cannot read is a
refusal you cannot test.
"""
from __future__ import annotations
import argparse
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
D = ROOT / "runs/graphcmp/D"
GCMP = ROOT / ".agents/slop/graphcmp.py"
PY = str(ROOT / ".venv/bin/python")

# THE PIN. A constant in code, because `checks/differ.py:46` already learned that lesson the
# expensive way: "The pin was CORRECT -- it is the hash of the committed body -- and it was
# still a comment that added up, because a pin no code consults cannot fail."
PINNED_DEV = "CPU"

# M1's two readings. TWO regexes that are not one regex: the header names a device LIST and
# the `ParamArg` names a SCALAR device, and a single pattern spanning both would pass when
# one of them is empty, which is the exact shape of the `D7`/`D8` artifacts.
DEV_HEADER = re.compile(r"^# devices py=(\[.*?\])\s", re.M)
# NOT `^`-anchored and NOT after a comma: the field sits mid-row inside a `P(...)` arg, and an
# anchored pattern finds NOTHING -- which the `satisfied` plant caught, because a method that
# reads zero values and reports them as "no device named at all" refuses for the wrong reason.
DEV_FIELD = re.compile(r"SGLOBAL,s([A-Za-z0-9_]+)\b")
# `N` is graphcmp's ABSENCE atom (`ATOMS["none"]`, graphcmp.py:324), not a device called N.
# Four artifacts carry `py=['N', 'sCPU']` for a graph with an unrealized PARAM, so reading `N`
# as a device would make every run look like it was taken on two machines.
ABSENCE = "N"


def _names(listed: str) -> set[str]:
    """`['sCPU']` -> {'CPU'}. Quotes stripped, brackets stripped, `N` dropped."""
    return {tok.strip().strip("'\"").lstrip("s") for tok in listed.strip("[]").split(",")
            if tok.strip().strip("'\"") not in ("", ABSENCE)}


def observed() -> tuple[set[str], set[str], int, int]:
    """M1: (devices named by the headers, devices named by the ParamArg fields, files read,
    files that said nothing)."""
    heads: set[str] = set()
    fields: set[str] = set()
    read = silent = 0
    for p in sorted(D.glob("D*.txt")):
        t = p.read_text(errors="replace")
        h, f = DEV_HEADER.findall(t), DEV_FIELD.findall(t)
        if not h and not f:
            continue
        read += 1
        heads |= set().union(*(_names(x) for x in h)) if h else set()
        fields |= set(f)
    for p in sorted(D.glob("D1-graph-*.txt")):
        if not DEV_HEADER.search(p.read_text(errors="replace")):
            silent += 1
    return heads, fields, read, silent


def reproduce(dev: str, graph: str = "lin") -> tuple[bool, str]:
    """M2: bytes. Nothing here knows what a device NAME looks like."""
    rec = D / f"D2-canon-py-{graph}.txt"
    if not rec.exists():
        return False, f"{rec.name} is MISSING"
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"LC_ALL": "C"}
    got = subprocess.run([PY, str(GCMP), "emit", "--side", "py", "--graph", graph,
                          "--dev", dev], env=env, capture_output=True)
    if got.returncode != 0:
        return False, f"emit rc={got.returncode}: {got.stderr.decode(errors='replace')[-200:]}"
    same = got.stdout == rec.read_bytes()
    return same, (f"re-emitted {got.stdout.count(chr(10).encode())} rows under --dev {dev}; "
                  f"recorded {rec.read_bytes().count(chr(10).encode())}")


def verdict(dev: str) -> tuple[bool, list[str]]:
    """Run BOTH methods. Returns (ok, lines). Prints nothing -- see `main` for the ordering
    that the module docstring explains."""
    heads, fields, read, silent = observed()
    lines = [
        f"pin (declared)     : --dev {dev}   (checks/devpin.py's PINNED_DEV={PINNED_DEV!r})",
        f"M1 headers say     : {sorted(heads) or 'NOTHING'}   from {read} artifacts",
        f"M1 ParamArg fields : {sorted(fields) or 'NOTHING'}",
        f"M1 per-graph files with NO device line : {silent}",
    ]
    ok = True
    for got, what in ((heads, "# devices headers"), (fields, "ParamArg device field")):
        if not got:
            lines.append(f"REFUSE: {what} named no device at all -- nothing to audit against")
            ok = False
        elif got != {dev}:
            lines.append(f"REFUSE: {what} names {sorted(got)}, the pin is {dev!r} -- "
                         f"the run was NOT taken under the pinned device")
            ok = False
    same, why = reproduce(dev)
    lines.append(f"M2 byte reproduction: {'REPRODUCES' if same else 'DOES NOT REPRODUCE'} -- {why}")
    ok = ok and same
    lines.append(f"\nDEVICE PIN          : {'SATISFIED' if ok else 'VIOLATED'}")
    return ok, lines


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pin", default=PINNED_DEV, help="the device the repo declares")
    ap.add_argument("--plant", choices=["satisfied", "moved"], default=None,
                    help="self-test: assert the OPPOSITE outcome and exit 0 only if seen")
    args = ap.parse_args()

    if args.plant is None:
        ok, lines = verdict(args.pin)
        print("\n".join(lines))            # PRINT BEFORE EXIT -- see the module docstring
        return 0 if ok else 1

    # ---- THE PLANTS. Each asserts an OUTCOME, and each looks for its marker with its OWN
    # token, never with a regex borrowed from `verdict`.
    ok, lines = verdict(args.pin)
    body = "\n".join(lines)
    if args.plant == "satisfied":
        # The pin as the repo stands must PASS.  A gate that cannot pass is not a gate, and
        # two today failed exactly this half -- one never refused, one refused correctly and
        # was scored wrong for it.
        seen = ok and "DEVICE PIN          : SATISFIED" in body
        print(f"PLANT satisfied: expected PASS, got {'PASS' if ok else 'FAIL'}")
        print(body)
        return 0 if seen else 1
    # `moved` is the load-bearing half: a pin that is not the device the run was taken under
    # MUST be caught.  `METAL` is the right mover -- MEASURED, it re-emits `lin` with 44 rows
    # and two `Opt`s against the recorded 46 and one, so both methods have something to see.
    seen = (not ok) and "DEVICE PIN          : VIOLATED" in body
    print(f"PLANT moved: expected REFUSE, got {'REFUSE' if not ok else 'PASS'}")
    print(body)
    return 0 if seen else 1


if __name__ == "__main__":
    sys.exit(main())
