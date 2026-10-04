#!/usr/bin/env python3
"""dd-stalearena.py -- STATIC census of the "one arena, two builders" class in a Bend
file. Chasing it one FORWARD edge at a time finds the SYMPTOMS.

  dd-stalearena.py FILE.bend

THE CLASS. A node builder grows its arena and answers a `Found`. When the NEXT builder
is handed an arena that is not the one the last builder grew, the new node OVERWRITES the
old one and any `src` the old builder recorded now points at the wrong slot. `Arena` is
an immutable record, so this is not a memory error -- it is a VALUE that reads as a
plausible graph, which is what makes it expensive: nothing fails, and `ALL PROOFS CHECK`
says nothing.

THREE RULES, because the three shapes leave different evidence.

  R1  SAME-LINE DOUBLE USE. One line hands the same `ar` twice: once nested in an
      earlier argument, once as a later argument.
          f.down.norm.g(rne(ar, i(ns), s), tudt, ar, fr, to)
      `rne` grew ITS copy; `ar` the name is unchanged, so the second use writes over
      rne's nodes. THE DETECTOR CANNOT SEE THIS: rne's own edges all still point
      backwards and the only symptom is a node COUNT. This is how the twelve-node `rne`
      subtree of `f2f.down.norm` was found.

  R2  STALE `Found`. A line passes `O.Found.ar(x)` where the PREVIOUS arena-carrying
      line bound something else.
          +n1 = dd_wkf(O.Found.ar(ne), -1.0)   # interns the CONST
          +nm = dd_mul(O.Found.ar(ne), ...)    # `ne` is one node stale: writes over n1
      This is what produced `MUL <- 4,6` on `q3`, slot 6 pointing at ITSELF.

  R3  BARE `ar` TWICE IN A STRAIGHT LINE.
          +z = dd_wk(ar, 0)
          +a = dd_ne(ar, i(sg), i(z))
      R3 is the only shape the FORWARD detector reliably sees, because `a`'s src1 is
      `z`'s slot and `a` was written to that same slot.

WHAT THIS IS NOT. Every rule is a REQUEST FOR A LOOK, and the false-positive rate is
printed so it can be read rather than assumed. The dominant false positive is a `match`
ARM: mutually exclusive arms each legitimately pass the incoming `ar`, so arm-to-arm
"staleness" is not staleness. R3 therefore resets at every `case`, and R2/R1 do not fire
on printer/reader defs (`dd_lab`, `dd_esig`, `dd_eck`, `dd_tree`) because those only
READ the arena -- no rule can see that, so those names are listed as a denominator, not
excluded, and the reader has to know the difference.
"""
import re
import sys

DEF = re.compile(r"^def ([\w.]+)\(")
BIND = re.compile(r"^\s*\+(\w+) = ")
CASE = re.compile(r"^\s*case ")
CARRIES = re.compile(r"[\w.]+\((?:O\.Found\.ar\(\w+\)|ar)\s*,")
READONLY = ("dd_lab", "dd_sig1", "dd_esig", "dd_eck", "dd_tree", "dd_sh1", "dd_sfx",
            "dd_ck", "dd_census", "dd_rows", "dd_fuel", "dd_seen", "dd_rs", "dd_cone",
            "dd_gap", "dd_ref", "dd_gp")


def scan(path):
    name, prev_binder, bare_run, hits = None, None, False, []
    ndef = ncarry = 0
    for i, ln in enumerate(open(path)):
        ln = ln.rstrip("\n")
        m = DEF.match(ln)
        if m:
            name, prev_binder, bare_run = m.group(1), None, False
            ndef += 1
            continue
        if not name or ln.lstrip().startswith("#"):
            continue
        if CASE.match(ln):
            prev_binder, bare_run = None, False
        if not CARRIES.search(ln):
            continue
        ncarry += 1
        b = BIND.match(ln)
        binder = b.group(1) if b else None
        tag = f"+{binder}" if binder else ln.strip()[:30]
        # R1: the same line hands the arena to TWO builders. `A` is a call taking the
        # arena as its FIRST argument (a builder's shape) and `B` is the arena as a
        # LATER direct argument. One `B` alone is a reader (`String.concat([s,
        # dd_gap(ar, ...)]`) and one `A` alone is the ordinary threading; R1 is two
        # builders, which is `A` twice or an `A` followed by a `B`.
        A = list(re.finditer(r"[\w.]+\(\s*(?:O\.Found\.ar\(\w+\)|ar)\s*,", ln))
        B = list(re.finditer(r",\s*(?:O\.Found\.ar\(\w+\)|ar)\s*[,)]", ln))
        if len(A) >= 2 or (A and B and B[0].start() > A[0].start()):
            hits.append((i + 1, name, "R1", "one line, two builders handed the arena", tag))
        # R2: a Found that is not the previous binder
        stale = re.search(r"O\.Found\.ar\((\w+)\)", ln)
        if stale and prev_binder is not None and stale.group(1) != prev_binder:
            hits.append((i + 1, name, "R2", f"`O.Found.ar({stale.group(1)})` but the "
                                           f"previous binder is `+{prev_binder}`", tag))
        # R3: bare `ar` again, in the same straight line
        if re.search(r"[\w.]+\(ar\s*,", ln):
            if bare_run:
                hits.append((i + 1, name, "R3", "bare `ar` after a bare `ar`", tag))
            bare_run = True
        elif bare_run:
            bare_run = False
        if binder:
            prev_binder = binder
    return ndef, ncarry, hits


def main():
    ndef, ncarry, hits = scan(sys.argv[1])
    ro = sum(1 for h in hits if any(h[1].startswith(r) for r in READONLY))
    for h in hits:
        mark = "  (read-only def -- expected)" if any(h[1].startswith(r) for r in READONLY) else ""
        print(f"{sys.argv[1]}:{h[0]}  {h[1]}  {h[2]}  {h[3]}  ->  {h[4]}{mark}")
    print(f"defs={ndef} arena_carrying_lines={ncarry} flagged={len(hits)} "
          f"of_which_read_only_defs={ro} actionable={len(hits) - ro}")
    return 1 if (len(hits) - ro) else 0


if __name__ == "__main__":
    sys.exit(main())
