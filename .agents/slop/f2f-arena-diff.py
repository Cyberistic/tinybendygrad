#!/usr/bin/env python3
"""f2f-arena-diff.py -- the PORT's arena against CPython's, SLOT FOR SLOT.

  f2f-arena-diff.py PORT.txt CPY.txt            the census, by fixture
  f2f-arena-diff.py PORT.txt CPY.txt --q4       one fixture, side by side

WHY SLOT FOR SLOT AND NOT `sig=`. `dd_cone` is a DEPTH-FIRST WALK FROM THE ROOT
(`dtype.bend`'s `dd_rs.go`, reversed), so it renumbers. A graph with a forward edge
walks differently from the same graph without one, and a wrong-but-well-formed graph walks
the same way as a right one -- which is exactly why `q1sig`'s first 18 nodes can be a
strict prefix of CPython's 27 and the port still be wrong. The arena is the INTERNING
ORDER, and the interning order is where an aliasing bug is visible: two builders handed
one arena write the same slot twice, and the loser is invisible in a cone.

⚠ BOTH SIDES ARE RE-BASED TO THE FIXTURE'S OWN PARAM, and neither side is zero-based.
`ops.bend`'s `Arena` carries a BOTTOM slot (slot 0 reads back `NOOP/0`) and CPython's
`ORDER` is a single growing list across all six fixtures, so CPython's `q7` starts at 188.
Comparing raw indices makes every row of `q2`..`q7` a disagreement -- a differ that
reports noise on 46 of 46 rows measures nothing. The PARAM is the re-base point because it
is the one node both sides mint first for the fixture, and the differ REFUSES to run if
either side has no `PARAM/0`: a mis-derived base is exactly the failure that reads as a
real bug on every row.

WHAT COUNTS AS A DISAGREEMENT. Three kinds, all printed, all counted:
  * SHAPE -- a node at a different op or a different label than CPython's at the aligned
    slot;
  * WIRE -- a `src` list that differs, which a `sig=` cannot see at all;
  * EXTRA -- a slot on one side with nothing on the other, which is the count.
`FORWARD` is counted SEPARATELY, because it is the structural claim and the rest is the
arithmetic.
"""
import sys


def parse(path):
    """-> {fixture: (rows, next)}; a row is (op, nsrc, label, srcs, fwd, root).

    ⚠ THE PORT PRINTS src0 AND src1 UNCONDITIONALLY, and `Arena.src` answers the arena
    BOTTOM (slot 0) for an index past the end -- so a `CONST/0` reads `<- 0,0` and a
    `CAST/1` reads `<- 3,0`. Taking the printed pair literally makes every src-less node
    disagree with CPython's, which reads `[]`. The `op/N` field is the arity and it is
    the only trustworthy count, so it truncates the pair; anything still below the
    fixture's PARAM is the bottom and is dropped, because no real node points at it.
    """
    out, cur = {}, None
    for ln in open(path):
        ln = ln.rstrip("\n")
        if ln.startswith("# "):
            f = ln.split()
            cur = f[1]
            out[cur] = ([], int(f[2].split("=")[1]))
        elif ln and ln[0].isdigit():
            p = ln.split("\t")
            op, nsrc = p[1].split("/")
            src = [] if p[3] == "<- " else [int(x) for x in p[3][3:].split(",")][:int(nsrc)]
            out[cur][0].append((op, int(nsrc), p[2], src,
                                len(p) > 4 and p[4] == "FORWARD",
                                len(p) > 5 and p[5] == "ROOT"))
    return out


def base_of(rows):
    for i, r in enumerate(rows):
        if r[0] == "PARAM":
            return i
    return None


def rebase(rows, b):
    return [(r[0], r[1], r[2], [s - b for s in r[3] if s - b >= 0], r[4], r[5])
            for r in rows[b:]]


def main():
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    only = next((x[4:] for x in sys.argv[1:] if x.startswith("--q=")), None)
    port, cpy = parse(a[0]), parse(a[1])

    tot_nodes = tot_shape = tot_wire = tot_extra = 0
    tot_fw_p = tot_fw_c = 0
    for fx in sorted(set(port) & set(cpy)):
        if only and fx != only:
            continue
        bp, bc = base_of(port[fx][0]), base_of(cpy[fx][0])
        if bp is None or bc is None:
            print(f"{fx}: NO PARAM on one side -- refusing, an unaligned diff is noise")
            return 2
        P, C = rebase(port[fx][0], bp), rebase(cpy[fx][0], bc)
        shape = wire = extra = 0
        fwp = sum(1 for r in P if r[4])
        fwc = sum(1 for r in C if r[4])
        tot_nodes += max(len(P), len(C))
        tot_fw_p += fwp
        tot_fw_c += fwc
        # `delta` is over the REBASED lengths, never over the two `next=` headers: CPython's
        # `ORDER` is one list across all six fixtures, so `cpy next=` for `q5` is 187 while
        # `q5` itself owns 39 slots. `port next=` carries the arena's own BOTTOM slot, so
        # the port's own count is one larger than the number of nodes it built.
        print(f"{fx}: port_nodes={len(P)} cpy_nodes={len(C)} delta={len(P) - len(C)} "
              f"(port next={port[fx][1]} cpy next={cpy[fx][1]}) FORWARD port={fwp} cpy={fwc}")
        if only:
            for i in range(max(len(P), len(C))):
                ps = f"{P[i][0]} {P[i][2]} <- {P[i][3]}" if i < len(P) else ""
                cs = f"{C[i][0]} {C[i][2]} <- {C[i][3]}" if i < len(C) else ""
                same = (i < len(P) and i < len(C) and P[i][:2] == C[i][:2])
                print(f"  {i:>4}  {ps:<36} | {cs:<36} {'' if same else '<<'}")
            continue
        for i in range(min(len(P), len(C))):
            p, c = P[i], C[i]
            if (p[0], p[2]) != (c[0], c[2]):
                shape += 1
                print(f"  SHAPE port[{i + bp}] {p[0]} {p[2]}  !=  cpy[{i + bc}] {c[0]} {c[2]}")
            if p[3] != c[3]:
                wire += 1
                print(f"  WIRE  port[{i + bp}] {p[0]} {p[2]} <- {p[3]}  !=  cpy[{i + bc}] "
                      f"{c[0]} {c[2]} <- {c[3]}")
        if len(P) > len(C):
            extra = len(P) - len(C)
            print(f"  EXTRA port has {extra} slot(s) CPython does not: "
                  + ", ".join(f"[{i + bp}]{P[i][0]}{P[i][2]}" for i in range(len(C), len(P))))
        if len(C) > len(P):
            extra = max(extra, len(C) - len(P))
            print(f"  EXTRA cpy has {len(C) - len(P)} slot(s) the port does not: "
                  + ", ".join(f"[{i + bc}]{C[i][0]}{C[i][2]}" for i in range(len(P), len(C))))
        tot_shape += shape
        tot_wire += wire
        tot_extra += extra
    print(f"TOTAL aligned_slots={tot_nodes} SHAPE={tot_shape} WIRE={tot_wire} "
          f"EXTRA={tot_extra} FORWARD port={tot_fw_p} cpy={tot_fw_c}")
    return 1 if (tot_shape or tot_wire or tot_extra or tot_fw_p or tot_fw_c) else 0


if __name__ == "__main__":
    sys.exit(main())
