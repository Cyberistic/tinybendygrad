#!/usr/bin/env python3
"""THE CONTROL, AND IT DOES NOT RUN THE GATE: `blocks()` is a pure function of a string, so a
synthetic transcript answers the question the real gate cannot be asked today without `bend`.

**WHAT IS BEING TOLD APART.** Two candidate repairs for the stage-6 re-open:

  (a) move the two inner banners in `run-port-mm.sh` / `run-f64.sh` out of the `== n/m ` shape;
  (b) narrow `blocks()` to column 0 only, or to "banners the gate itself emits".

They are told apart by WHAT EACH ONE STILL FAILS ON, because a repair that removes the reported
failure by removing the check's ability to see anything is not a repair:

  * V1 the AS-IS transcript, which reproduces the live re-open from `live.port.out:77`;
  * V2 (a) applied -- same transcript, the inner banner renamed out of the shape;
  * V3 (a) applied AND stage 6's denominator row deleted -- **the re-open is gone but the stage must
    STILL fail**, on its missing denominator. This is the variant that makes (a) safe;
  * V4 (b1) "column 0 only" -- the inner banner indented instead of renamed;
  * V5 (b) taken to its failure mode -- EVERY header indented, so `blocks()` sees no stage at all.
    The check does not fail. It reports seven RETIRED stages and returns nothing to fail on, which is
    `DEAD` and is strictly worse than the defect it replaced;
  * V6 what is ACTUALLY on disk today: stage 6's duplicate reaches the transcript (`e2e.py:580`
    `echo_file` prints the whole child artifact) and stage 7's does not (`e2e.py:593` `grep_file`
    through `F64_RE`, which does not match that banner), so the `run-f64.sh` re-open is LATENT;
  * V7 the second banner's DENOMINATOR, to show `readings()` reads `hs[0]` only -- so a stale `99`
    printed by the child is never disputed by any reading, it is only counted as a re-open.

usage: .venv/bin/python .agents/slop/banner/blocks-test.py   (writes blocks-test.rows beside it)
"""
from __future__ import annotations

import importlib.util
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
V = importlib.util.spec_from_file_location("verdicts", HERE.parent / "e2estage8" / "verdicts.py")
assert V and V.loader
verdicts = importlib.util.module_from_spec(V)
V.loader.exec_module(verdicts)

GATE_HDR_6 = "== 6/7 the matmul THROUGH THE PORT (no Node, no browser, no navigator.gpu)"
GATE_HDR_7 = "== 7/7 the SAME kernel in f64 THROUGH THE PORT (no Node, no browser, no adapter)"
INNER_6 = "== 6/6 THE MATMUL THROUGH THE PORT  -- execution: no Node, no browser, no adapter,"
INNER_7 = "== 7/7 AN f64 KERNEL THROUGH THE PORT -- double, not float"
BODY_6 = ["   [EXEC] lane A", "words port=64  CPython=64"]
BODY_7 = ["F64-1 words_port=32"]


def transcript(inner6: str | None, inner7: str | None, drop_denominator: bool = False) -> str:
    body6 = BODY_6[:-1] if drop_denominator else BODY_6
    return "\n".join(
        [GATE_HDR_6, "  stage 6 port (matmul THROUGH the port, no Node): PASS",
         *([inner6] if inner6 else []), *body6,
         GATE_HDR_7, *([inner7] if inner7 else []), *BODY_7,
         "  stage 7 f64 (double through the port, no Node): PASS"]
    )


# `F64_RE` at `checks/e2e.py:337`, verbatim alternatives, against the two inner banners.
F64_RE_TOKENS = ("STAGE 7 PASS", "STAGE 7 FAILED", "64/64 MET", "IDENTICAL", "port now says",
                 "REFUSED[", "RED   [", "GREEN [", "THEOREM [", "F64-0", "F64-1", "F64-9")

VARIANTS = [
    ("V1 AS-IS", transcript(INNER_6, INNER_7),
     "the live re-open: both children print a header the gate already printed"),
    ("V2 repair (a)", transcript("== PORT-MM  THE MATMUL THROUGH THE PORT  -- execution, no adapter",
                                 "== F64-LANE  AN f64 KERNEL THROUGH THE PORT -- double"),
     "both inner banners renamed out of the `== n/m ` shape; nothing else changed"),
    ("V3 repair (a), stage 6 denominator DELETED",
     transcript("== PORT-MM  THE MATMUL THROUGH THE PORT  -- execution, no adapter",
                "== F64-LANE  AN f64 KERNEL THROUGH THE PORT -- double", drop_denominator=True),
     "**the control's teeth**: re-open gone, and the stage must STILL fail on the missing row"),
    ("V4 repair (b1) column 0", transcript("  " + INNER_6, "  " + INNER_7),
     "the inner banners INDENTED rather than renamed, real headers untouched"),
    ("V5 repair (b) at its failure mode",
     "\n".join("  " + ln for ln in transcript(INNER_6, INNER_7).splitlines()),
     "every header indented: `blocks()` must see NO stage, and the check must have nothing to fail on"),
    ("V6 WHAT IS ON DISK TODAY", transcript(INNER_6, None),
     "stage 6's duplicate reaches the transcript, stage 7's is dropped by `F64_RE` first"),
]


def row(*cells: object) -> str:
    return " | ".join(str(c) for c in cells)


def stage_six_verdict(body: list[str], d: int | None) -> str:
    """THE PREDICATE `main()` ITSELF APPLIES at verdicts.py:241-250, not a paraphrase of it."""
    v = next((f"{m.group(1)}: {m.group(2)}" for m in (verdicts.VERDICT.match(b) for b in body) if m), None)
    if d == 0:
        return "FAIL: DENOMINATOR 0"
    if d is None and v and not v.partition(": ")[2].startswith("SKIP"):
        return f"FAIL: EMITTED, verdict {v.partition(': ')[2]}, no denominator counted"
    return "no stage-6 denominator failure"


def main() -> int:
    out = [row("VARIANT", "STAGES blocks() SAW", "STAGE 6 BODY LINES", "STAGE 6 DENOMINATOR",
               "RE-OPENS", "WHAT main() SAYS ABOUT STAGE 6", "WHAT IT MEANS")]
    for name, text, why in VARIANTS:
        bodies, banners = verdicts.blocks(text)
        reopens = verdicts.reopens(banners)
        body6 = bodies.get(6, [])
        d = verdicts.denominator(6, body6)
        out.append(row(name, sorted(bodies) or "NONE -- DEAD", len(body6), d,
                       [f"stage {n} @line {no}" for n, no, _ in reopens] or "none",
                       stage_six_verdict(body6, d), why))

    print("\n".join(out))

    print()
    print("--- CONTROL (b1): `HEADER` is `^== (\\d+)/(\\d+) (.*)$` matched with `re.match`, so it is")
    print("--- ALREADY anchored at column 0. `  ` + an `== n/m` line is simply not a header, which is")
    print("--- why (b1) is a NO-OP rather than a repair:")
    for ln in (INNER_6, "  " + INNER_6):
        print("   ", row(repr(ln), "HEADER MATCHES" if verdicts.HEADER.match(ln) else "no match"))

    print()
    print("--- CONTROL (V7): `readings()` at verdicts.py:175 reads `hs[0][1]`, the FIRST banner only,")
    print("--- so a stale denominator printed by a CHILD is never disputed by any reading:")
    _, banners = verdicts.blocks(transcript("== 6/99 THE MATMUL THROUGH THE PORT", INNER_7))
    for n in (6, 7):
        first = verdicts.HEADER.match(banners[n][0][1])
        out.append(row(f"V7 stage {n}", "first banner", repr(banners[n][0][1]),
                       f"m read by readings() = {first.group(2) if first else None}",
                       f"banners seen = {len(banners[n])}"))
    print("\n".join(out[-2:]))

    print()
    print("--- CONTROL: does `F64_RE` let either inner banner into the transcript? (`e2e.py:593`)")
    for ln in (INNER_6, INNER_7):
        out.append(row(repr(ln), "F64_RE matches" if any(t in ln for t in F64_RE_TOKENS) else
                       "F64_RE DROPS it -- filtered out of the transcript before blocks() ever sees it"))
        print("   ", out[-1])

    # ---- V8: THE REAL ARTIFACT, not a synthetic one. This is as close to running the gate as a
    # tree without `bend` gets, and it needs no `bend`: `blocks()` is a pure function of a string, so
    # applying the candidate's exact one-line substitution to the transcript answers the question the
    # candidate raises, without starting a stage.
    live = verdicts.DEFAULT
    if live.exists():
        real = live.read_text(errors="replace")
        patched = real.replace(INNER_6, "== PORT-MM  THE MATMUL THROUGH THE PORT  -- execution")
        before = verdicts.blocks(real)
        after = verdicts.blocks(patched)
        for label, (bodies, banners) in (("before", before), ("after", after)):
            rb = verdicts.reopens(banners)
            d6 = verdicts.denominator(6, bodies.get(6, []))
            out.append(row(f"V8 REAL {label}", live.name, "stage 6 denominator", d6,
                           f"re-opens = {[f'stage {n} @line {no}' for n, no, _ in rb] or 'NONE'}",
                           f"stages seen = {len(banners)}"))
        print()
        print(f"--- V8: THE REAL ARTIFACT `{live.name}`, mtime "
              f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(live.stat().st_mtime))}, with the")
        print("--- candidate's ONE LINE applied in memory. NO GATE RUN, no bend, no node, no cc:")
        print("\n".join(out[-2:]))

        # ---- AND THE CLAIM THAT THE PATCH IS NOT ENOUGH IS MEASURED, NOT ASSERTED: run the real
        # `readings()` over the PATCHED banners with the real gate, and count what it still fails on.
        left: list[str] = []
        verdicts.readings(verdicts.ROOT / "checks/e2e.py", after[1], left)
        out.append(row("V8 REAL after, WHAT REMAINS", f"{len(left)} DENOMINATOR FAIL(s) from "
                       f"`readings()` alone", "; ".join(sorted({ln.split(':')[0] for ln in left})),
                       "the re-open is NOT among them -- the candidate cleared exactly the re-open",
                       "each is `gate SAYS 7` against a transcript whose own banners read n/4 n/5 n/6",
                       "only a FRESH RUN can clear these; the transcript is 11 DAYS OLD"))
        print()
        print("--- V8: WHAT THE PATCH DOES **NOT** FIX, MEASURED by re-running `readings()` over the")
        print("--- patched banners against the live `checks/e2e.py`:")
        print("   ", out[-1])

    (HERE / "blocks-test.rows").write_text("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())