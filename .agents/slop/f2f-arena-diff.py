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

THE OFFSET IS 1 AND IT IS MEASURED, NOT ASSUMED. `ops.bend`'s `Arena` carries a bottom
slot (slot 0 reads back `NOOP/0`), and CPython's `ORDER` does not. So port slot `p` and
CPython slot `c` describe the same node iff `p == c + 1`. The differ RE-DERIVES the offset
by matching the fixture's PARAM -- slot 0 on CPython's side is a `PARAM/0` and the port's
slot 0 is `NOOP/0` -- and refuses to run if it cannot find one, because a wrong offset
turns every row into a disagreement and a differ that cannot fail is a gate that says
PASS.

WHAT COUNTS AS A DISAGREEMENT. Three kinds, all printed, all counted:
  * a NODE that is at a different op or a different label than CPython's at the aligned
    slot -- the shape;
  * a `src` that differs -- the wiring, which a `sig=` cannot see at all;
  * a slot on one side with nothing on the other -- the count.
And `FORWARD` is counted separately, because it is the structural claim and the rest is
the arithmetic.
"""
import sys


def parse(path):
    """-> {fixture: [(slot, op, label, srcs, fwd, root)]}, plus the `next=` each side read."""
    out, cur, nxt = {}, None, {}
    for ln in open(path):
        ln = ln.rstrip("\n")
        if ln.startswith("# "):
            f = ln.split()
            cur = f[1]
            nxt[cur] = int(f[f.index("next=") + 1].split("=")[1]) if "next=" in f else None
            # `next=` is printed as `next=27`, so `f[2]` is the value's key
            nxt[cur] = int(f[2].split("=")[1])
            out[cur] = []
        elif ln and ln[0].isdigit():
            p = ln.split("\t")
            src = [] if p[3] in ("<- ", "") else [int(x) for x in p[3].split(",")]
            out[cur].append((int(p[0]), p[1], p[2], src,
                             len(p) > 4 and p[4] == "FORWARD",
                             len(p) > 5 and p[5] == "ROOT"))
    return out, nxt


def param_slot(rows):
    for i, r in enumerate(rows):
        if r[1] == "PARAM/0":
            return r[0]
    return None


def main():
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    only = next((x[4:] for x in sys.argv[1:] if x.startswith("--q")), None)
    port, pn = parse(a[0])
    cpy, cn = parse(a[1])

    tot_nodes = tot_diff = tot_fw_p = tot_fw_c = 0
    for fx in sorted(set(port) & set(cpy)):
        if only and fx != only:
            continue
        P, C = port[fx], cpy[fx]
        off = param_slot(P) - param_slot(C)
        if off is None:
            print(f"{fx}: NO PARAM on one side -- refusing, an unaligned diff is noise")
            return 2
        shape = wire = extra_p = extra_c = 0
        fwp = sum(1 for r in P if r[4])
        fwc = sum(1 for r in C if r[4])
        tot_nodes += len(P)
        tot_diff += shape + wire + abs(extra_p) + abs(extra_c)
        tot_fw_p += fwp
        tot_fw_c += fwc
        head = f"{fx}: port next={pn[fx]} cpy next={cn[fx]} offset={off}"
        print(f"{head} FORWARD port={fwp} cpy={fwc} delta_nodes={pn[fx] - cn[fx]}")
        if only:
            print(f"  {'slot':>4}  {'port':<34} {'| cpy':<34}")
            for i in range(max(len(P), len(C))):
                ps = f"{P[i][0]} {P[i][1]} {P[i][2]} <- {P[i][3]}" if i < len(P) else ""
                cs = f"{C[i][0]} {C[i][1]} {C[i][2]} <- {C[i][3]}" if i < len(C) else ""
                same = (i < len(P) and i < len(C) and P[i][1] == C[i][1]
                        and P[i][2] == C[i][2])
                print(f"  {i:>4}  {ps:<34} | {cs:<34} {'' if same else '<<'}")
            continue
        for i in range(min(len(P), len(C))):
            p, c = P[i], C[i]
            if p[1] != c[1] or p[2] != c[2]:
                shape += 1
                print(f"  SHAPE port[{p[0]}] {p[1]} {p[2]}  !=  cpy[{c[0]}] {c[1]} {c[2]}")
            ps = [s - off for s in p[3]]
            if ps != c[3]:
                wire += 1
                print(f"  WIRE  port[{p[0]}] {p[1]} {p[2]} <- {ps}  !=  cpy[{c[0]}] "
                      f"{c[1]} {c[2]} <- {c[3]}")
        if len(P) > len(C):
            extra_p = len(P) - len(C)
            print(f"  EXTRA port has {extra_p} slot(s) CPython does not: "
                  + ", ".join(f"[{P[i][0]}]{P[i][1]}{P[i][2]}" for i in range(len(C), len(P))))
        if len(C) > len(P):
            extra_c = len(C) - len(P)
            print(f"  EXTRA cpy has {extra_c} slot(s) the port does not: "
                  + ", ".join(f"[{C[i][0]}]{C[i][1]}{C[i][2]}" for i in range(len(P), len(C))))
    print(f"TOTAL slots={tot_nodes} disagreements={tot_diff} FORWARD port={tot_fw_p} "
          f"cpy={tot_fw_c}")
    return 1 if (tot_diff or tot_fw_p or tot_fw_c) else 0


if __name__ == "__main__":
    sys.exit(main())
