#!/usr/bin/env python3
"""plant.py -- THE PLANT FOR THIS SLICE'S FIX, on a COPY of the port.

The built-in `gates/bendcite-gate.py --plant` moves a line that a POINTER names.
THIS ONE moves a line that a `symbol=` FIELD names -- the form this slice
introduced -- because that is the form the fix rests on and the form that must
be shown to ROT.

TWO ARMS.
  ARM ONE (MOVED)   a COPY of the port with ONE LINE INSERTED above the construct
                    a `symbol=` field names, so that pointer is now stale.
  ARM TWO (CONTROL) a BYTE-IDENTICAL COPY of the SAME snapshot, unedited, so the
                    gate's verdict on it must be the control's verdict exactly.

The subject is a COPY ON DISK, edited as TEXT.  NEVER `git show HEAD:` -- a
copy taken from git would prove the instrument reads a tree nobody works on.

Usage:  .venv/bin/python .agents/slop/barecite/plant.py
"""
from __future__ import annotations
import collections, importlib.util, os, shutil, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
spec = importlib.util.spec_from_file_location("bcg", ROOT / "gates" / "bendcite-gate.py")
bcg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bcg)
PORT_REL = bcg.PORT_REL


def main() -> int:
    bad: list[str] = []
    with tempfile.TemporaryDirectory(prefix="barecite-plant-") as raw:
        td = Path(raw)
        snap = td / "snap"
        snap.mkdir(parents=True)
        shutil.copytree(ROOT / PORT_REL, snap / PORT_REL)
        shutil.copytree(ROOT / "references" / "bend" / "bend2", snap / "references" / "bend" / "bend2")

        base_rows, corpus = bcg.census(snap)

        # THE POINTER THE PLANT MOVES IS DISCOVERED, NOT NAMED: a row whose claim
        # names a construct BY ITS `symbol=` FIELD -- the durable form this slice
        # introduced -- and whose cited line IS that construct's declaration.
        def by_symbol(r):
            claims = r.get("claims") or []
            if not r.get("decl") or not claims:
                return False
            return any(c.split("=", 1)[-1] == c.split("=", 1)[0] for c in claims) \
                and r.get("tier") == "the citation's own line" \
                and int(r["lo"]) == int(r["decl"])

        target_row = next((r for r in base_rows
                           if r["verdict"] == "RESOLVES" and by_symbol(r)
                           and r.get("target", "").startswith(PORT_REL + "/")), None)
        if target_row is None:
            print("PLANT REFUSED: the copy resolved no symbol= pointer", file=sys.stderr)
            return bcg.REFUSED

        print(f"PLANT the pointer moved is {target_row['rel']}:{target_row['at']} -> "
              f"{target_row['subject']}:{target_row['lo']}, and the construct its `symbol=` "
              f"names is declared at {target_row['target']}:{target_row['decl']}")
        print(f"PLANT the claim is {target_row.get('claims')}")

        # ---- ARM ONE: MOVED.  ONE CODE BLOCK inserted ABOVE the construct, so the
        # pointer is now one line too high -- which is the rot a line-number citation
        # rots into.
        # IT GOES ABOVE THE CONSTRUCT'S SPAN START AND IT IS **CODE**, NOT A COMMENT.
        # A construct's SPAN INCLUDES THE COMMENT RUN THAT DOCUMENTS IT
        # (`bendcite-gate.py`'s own docstring), and `bend_constructs` walks UP from the
        # declaration over any comment lines -- so a planted COMMENT is absorbed into
        # the construct's doc run, the span start moves with it, and THE POINTER STAYS
        # INSIDE THE SPAN AND THE ROW STILL RESOLVES. MEASURED, this plant's first
        # form: `:284-284 is inside `M.mo_dims` (declared at :285)` -- RESOLVES, not
        # red. THE GATE'S OWN PLANT SAYS THE SAME THING ("The plant inserts CODE,
        # which is what a unit editing the port actually does").
        moved = td / "moved"
        shutil.copytree(snap, moved)
        victim = moved / target_row["target"]
        body = victim.read_text(encoding="utf-8").splitlines()
        decl = int(target_row["decl"])
        # THE SPAN START: the construct's own `span` in the corpus.
        span_start = decl
        for (name, d, s, e) in corpus.constructs.get(target_row["target"], []):
            if d == decl:
                span_start = s
                break
        victim.write_text("\n".join(
            body[:span_start - 1]
            + ["def plant_probe(z: U32) -> U32:", "  z", ""]
            + body[span_start - 1:]) + "\n")
        moved_rows, _mc = bcg.census(moved)
        after = next((r for r in moved_rows
                      if r["rel"] == target_row["rel"] and r["at"] == target_row["at"]
                      and r["subject"] == target_row["subject"]
                      and r["lo"] == target_row["lo"]), None)
        print(f"PLANT the CODE was inserted above the construct's SPAN start :{span_start} "
              f"(its declaration is :{decl})")
        print(f"PLANT arm-one control : {target_row['verdict']}  (the pointer holds)")
        print(f"PLANT arm-one moved   : {after['verdict'] if after else '(the row is gone)'}"
              f"  {after['why'] if after else ''}")
        if after is None or after["verdict"] != "WRONG-LINE":
            bad.append("arm one did not go red")

        # ---- ARM TWO: CONTROL.  A BYTE-IDENTICAL COPY of the SAME snapshot.
        twin = td / "twin"
        shutil.copytree(snap, twin)
        same = all((snap / p).read_bytes() == (twin / p).read_bytes()
                   for p in (target_row["target"],))
        twin_rows, _tc = bcg.census(twin)
        tv = [r["verdict"] for r in twin_rows]
        bv = [r["verdict"] for r in base_rows]
        print(f"PLANT arm-two twin    : reproduces the control exactly = {tv == bv}  "
              f"byte-identical={same}")
        if not same or tv != bv:
            bad.append("arm two byte-identical twin did not reproduce the control")

        base_c = collections.Counter(r["verdict"] for r in base_rows)
        moved_c = collections.Counter(r["verdict"] for r in moved_rows)
        print(f"PLANT arm-one counts  : {dict(base_c)}")
        print(f"PLANT arm-one moved   : {dict(moved_c)}")
        if moved_c.get("WRONG-LINE", 0) <= base_c.get("WRONG-LINE", 0):
            bad.append("arm one did not ADD a stale pointer")

    if bad:
        print("PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
        return bcg.FAIL
    print("PLANT OK: a moved line makes the `symbol=` pointer stale, a byte-identical "
          "copy does not, and the copy's control is the control's verdict exactly")
    return bcg.PASS


if __name__ == "__main__":
    sys.exit(main())
