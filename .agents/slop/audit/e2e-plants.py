#!/usr/bin/env python3
"""e2e-plants.py -- can "E2E PASS, 64/64 u32 words" go RED?

SUBJECT:    the GPU's 64 u32 output words for a real (A@B)@C on a real WebGPU
            adapter, against CPython's 64.
INSTRUMENT: `.agents/slop/e2e_mm_gate.py`'s `main()`, which prints
              mm_e2e_out_bits_equal / mm_e2e_out_words / mm_e2e_walk_completed
              / mm_e2e_failed  and PASS/FAIL.

`ORACLE` and `GPU` are MODULE GLOBALS (`e2e_mm_gate.py:44-45`), not paths derived
from the argument, so a $TMPDIR copy is not picked up automatically -- the first
attempt at PLANT 1 was green for exactly that reason. Both are reassigned here
and the plant is ASSERTED to have landed before the verdict is read.

Nothing is written to the repo: the oracle and the GPU result are copied to $TMPDIR
and mutated there.
"""
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import shutil
import tempfile

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
GATE = os.path.join(REPO, ".agents/slop/e2e_mm_gate.py")
RUNS = os.path.join(REPO, "runs/e2e")
TMP = os.path.join(tempfile.gettempdir(), "e2eaudit")
KEEP = ("mm_e2e_out_bits_equal", "mm_e2e_out_words",
        "mm_e2e_walk_completed", "mm_e2e_failed")


def load():
    spec = importlib.util.spec_from_file_location("e2egate", GATE)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def run(g, bend_rows):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        g.main(pathlib.Path(bend_rows))
    out = buf.getvalue()
    return "  ".join(l for l in out.splitlines() if any(l.startswith(k + "=") for k in KEEP))


if __name__ == "__main__":
    shutil.rmtree(TMP, ignore_errors=True)
    os.makedirs(TMP)
    for f in os.listdir(RUNS):
        shutil.copy(os.path.join(RUNS, f), os.path.join(TMP, f))
    bend = os.path.join(TMP, "e2e-mm-bend.txt")
    g = load()

    print("BASELINE (live oracle, live GPU result)")
    print("  ", run(g, bend))

    # ---------------------------------------------------------- PLANT 1
    # ONE BIT of ONE of the 64 words. This is the plant that matters: 63 of 64
    # words correct is not a partial pass, it is a failure.
    p = os.path.join(TMP, "oracle-bitflip.json")
    o = json.load(open(os.path.join(RUNS, "e2e-mm-oracle.json")))
    before = list(o["answer_u32"])
    o["answer_u32"][0] = (o["answer_u32"][0] + 1) % (2 ** 32)
    json.dump(o, open(p, "w"))
    n_diff = sum(1 for a, b in zip(before, o["answer_u32"]) if a != b)
    assert n_diff == 1, f"plant did not land ({n_diff} words differ)"
    print(f"\nPLANT 1  oracle answer_u32[0] += 1   ({n_diff} of 64 words differ, "
          f"{before[0]} -> {o['answer_u32'][0]})")
    g.ORACLE = pathlib.Path(p)
    print("  ", run(g, bend))

    # ---------------------------------------------------------- PLANT 2
    # THE WALK DIES. `main()` reads `g.get("result") or {}` and writes every row
    # against an empty result, so this is a FAIL and not a traceback -- the exact
    # fix the file records for a version that read a crash as a pass.
    g.ORACLE = pathlib.Path(os.path.join(RUNS, "e2e-mm-oracle.json"))
    d = json.load(open(os.path.join(RUNS, "e2e-mm-gpu.json")))
    d["result"] = {"ok": False, "error": "PLANT: the walk was killed"}
    p2 = os.path.join(TMP, "gpu-dead.json")
    json.dump(d, open(p2, "w"))
    g.GPU = pathlib.Path(p2)
    print("\nPLANT 2  the GPU walk does not complete")
    print("  ", run(g, bend))

    # ---------------------------------------------------------- DISARM
    g.GPU = pathlib.Path(os.path.join(RUNS, "e2e-mm-gpu.json"))
    p3 = os.path.join(TMP, "oracle-rewritten.json")
    o2 = json.load(open(os.path.join(RUNS, "e2e-mm-oracle.json")))
    o2["per_launch"] = o2["per_launch"]  # no-op rewrite, same content
    json.dump(o2, open(p3, "w"))
    g.ORACLE = pathlib.Path(p3)
    print("\nDISARM  the oracle re-serialised with identical content")
    print("  ", run(g, bend))