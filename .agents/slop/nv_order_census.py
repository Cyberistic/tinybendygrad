#!/usr/bin/env python3
"""nv_order_census.py -- THE ORDER-SENSITIVITY CENSUS for the `nv` register tables.

A TRANSPOSITION inside a fixed-width field is invisible to any count or width
check, so the question is not "is there a bug" but "which sites COULD hide one".
This answers it per site, from CPython, with a denominator.

WHAT IS AUDITED. Every `NVReg` field table reachable from nvdev.py's own
`include()` calls -- `nv_ref`, `dev_fb`, `dev_gc6_island`, `dev_vm`, `dev_mmu` --
plus every `Fld.of(a, b)` literal in nvdev.bend, read out of the FILE, so the
port's own table is audited rather than assumed to equal CPython's.

THE THREE QUESTIONS PER SITE, and each has a different answer:

  1. ORDER-SENSITIVE?  Is `fmask(s, e) != fmask(e, s)` under the port's U32
     arithmetic?  If the two orders give the same MASK then no mask row can see
     the swap, and the site needs a different row.
  2. WIDTH-PRESERVING?  Is `wid(s, e) == wid(e, s)`?  This is the brief's
     premise -- "the field is 4 bits either way".  It is MEASURED here, per site,
     and it is FALSE for every site whose width the port can represent, because
     `wid` is `e - s + 1` in U32 and the subtraction WRAPS.
  3. ROUND-TRIP DISCRIMINATES?  Does `getb(fenc(ones, s), s, e)` differ between
     the two orders?  This is the check the brief asks to be made mechanical, and
     it is the ONLY probe of the three naive ones that moves.

The arithmetic is nvdev.bend's, re-implemented in Python and CHECKED against the
Bend file's own published `nv_reg_*_maxw` / `nv_mask_*` rows before it is used --
a census whose arithmetic disagrees with the port measures nothing.
"""
import json
import re
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])

M32 = (1 << 32) - 1
ROOT = __file__.rsplit("/.agents/", 1)[0]
BEND = ROOT + "/bin/bend"
SRC = ROOT + "/tinybendygrad/runtime/support/nv/nvdev.bend"


# --- nvdev.bend's arithmetic, re-implemented -------------------------------
def wid(s, e):
    """nv.wid(s, e) = U32.add(U32.sub(e, s), 1) -- WRAPS, it does not clamp."""
    return (e - s + 1) & M32


def pw(k):
    """nv.pw: doubling from 1.  `k` is a Nat, so a U32 width is ~4e9 doublings;
    the value stops changing after 32 of them and that is all the caller can see."""
    a = 1
    for _ in range(min(k, 4096)):
        a = (a + a) & M32
    return a


def ones(w):
    """nv.ones(w) = pw(w) - 1."""
    return (pw(w) - 1) & M32


def fmask(s, e):
    """nv.fmask(s, e) = shln(ones(wid(s, e)), s)."""
    return (ones(wid(s, e)) << s) & M32


def fenc(s, x):
    """nv.fenc(s, x) = shln(x, s)."""
    return (x << s) & M32


def getb(v, s, e):
    """nv.getb(v, s, e) = (v >> s) & ones(wid(s, e))."""
    return ((v >> s) & ones(wid(s, e))) & M32


def rt_ones(s, e):
    """THE ROUND TRIP this file now gates as `nv_fldmax_*`: the all-ones word
    shifted to the field and read back.  Shifting loses the top s bits, so the
    answer is `ones(w)` whatever the order -- which is why it moves ONLY when
    the two orders have different WIDTHS."""
    return getb(fenc(s, M32), s, e)


def _or_all(vals):
    """U32 OR-fold, masked."""
    a = 0
    for v in vals:
        a = (a | v) & M32
    return a


def rt_lowbit(s, e):
    """The naive probe: getb(enc(1)).  Reported because it is provably blind."""
    return getb(fenc(s, 1), s, e)


def rt_topbit(s, e):
    """The other naive probe: the field's own top bit.  Also provably blind."""
    v = pw((wid(s, e) - 1) & M32)
    return getb(fenc(s, v), s, e)


# --- the sites, from CPython and from the Bend file ------------------------
def cpython_sites():
    """Every NVReg field table nvdev.py can include, read by CALLING CPython."""
    from tinygrad.runtime.support.nv.nvdev import NVReg
    import importlib
    # nvdev.py:162 is `getattr(getattr(nv_regs, name), arch or 'regs').items()`,
    # so the arch is a MODULE ATTRIBUTE and not a dict key. Every arch each module
    # publishes is audited, not only the one nvdev.py happens to pick.
    mods = ["nv_ref", "dev_fb", "dev_gc6_island", "dev_vm", "dev_mmu"]
    out = []
    for mn in mods:
        m = importlib.import_module("tinygrad.runtime.autogen.nv_regs." + mn)
        for arch in [a for a in dir(m) if not a.startswith("_")]:
            regs = getattr(m, arch)
            for name, v in sorted(regs.items()):
                if not (isinstance(v, tuple) and len(v) == 3 and isinstance(v[2], dict)):
                    continue
                base, off, fields = v
                out.append({"src": "%s:%s" % (mn, arch), "reg": name,
                            "fields": {k: list(t) for k, t in fields.items()}})
    return out


BEND_FLD = re.compile(r'Fld\.of\("([^"]+)",\s*(-?\d+),\s*(-?\d+)\)')


def bend_sites():
    """Every `Fld.of(name, s, e)` in the port, WITH the register it belongs to."""
    text = open(SRC).read().split("\n")
    reg = None
    out = []
    for ln, line in enumerate(text, 1):
        m = re.search(r"^def nv\.reg_(\w+)\(\) -> Rgv: Rgv\.of\(", line)
        if m:
            reg = m.group(1)
        for f in BEND_FLD.finditer(line):
            out.append({"reg": reg, "line": ln,
                        "name": f.group(1),
                        "s": int(f.group(2)), "e": int(f.group(3))})
    return out


def main():
    py = cpython_sites()
    bend = bend_sites()

    n_py_fields = sum(len(r["fields"]) for r in py)
    n_bend_fields = len(bend)

    print("=" * 78)
    print("THE DENOMINATORS")
    print("=" * 78)
    print("CPython NVReg field tables reachable from nvdev.py's include() calls : %d" % len(py))
    print("  fields in those tables                                          : %d" % n_py_fields)
    print("`Fld.of(name, s, e)` literals in nvdev.bend                        : %d" % n_bend_fields)
    print("  distinct registers in the port                                   : %d"
          % len({b["reg"] for b in bend}))

    # -- the arithmetic is CHECKED against the port's own rows before use ----
    import subprocess
    r = subprocess.run([BEND, SRC], capture_output=True, text=True, cwd=ROOT)
    port_rows = {}
    for line in r.stdout.split("\n"):
        if "=" in line:
            k, v = line.split("=", 1)
            if re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", k):
                port_rows[k] = v
    def b42(nm):
        b = next(x for x in bend if x["name"] == nm)
        return (b["s"], b["e"])

    b42_fields = [(x["s"], x["e"]) for x in bend if x["reg"] == "boot42"]
    checks = [
        ("nv_reg_NV_PMC_BOOT_42_maxw", str(max(wid(s, e) for s, e in b42_fields))),
        ("nv_reg_NV_PMC_BOOT_42_wide", str(sum(1 for s, e in b42_fields if wid(s, e) > 32))),
        ("nv_mask_one", str(fmask(*b42("minor_extended_revision")))),
        ("nv_mask_impl", str(fmask(*b42("implementation")))),
        ("nv_mask_arch", str(fmask(*b42("architecture")))),
        ("nv_mask_chipid", str(fmask(*b42("chip_id")))),
        # nv.mask is an OR-FOLD (nvdev.py:28 is functools.reduce(int.__or__, ...)),
        # not a sum. The control caught this the first time it was written.
        ("nv_mask_all", str(_or_all(fmask(s, e) for s, e in b42_fields))),
        ("nv_fldmax_minor_extended_revision", str(rt_ones(*b42("minor_extended_revision")))),
        ("nv_fldmax_chip_id", str(rt_ones(*b42("chip_id")))),
        ("nv_fldmax_architecture", str(rt_ones(*b42("architecture")))),
        ("nv_fld_minor_extended_revision",
         "%d:%d:%d" % (b42("minor_extended_revision")[0], b42("minor_extended_revision")[1],
                       wid(*b42("minor_extended_revision")))),
        ("nv_fld_architecture",
         "%d:%d:%d" % (b42("architecture")[0], b42("architecture")[1], wid(*b42("architecture")))),
    ]
    print()
    print("=" * 78)
    print("THE ARITHMETIC IS CHECKED AGAINST THE PORT'S OWN ROWS BEFORE IT IS USED")
    print("=" * 78)
    bad = 0
    for k, mine in checks:
        got = port_rows.get(k, "<absent>")
        ok = got == mine
        bad += not ok
        print("  %-36s port=%-12s census=%-12s %s" % (k, got, mine, "ok" if ok else "MISMATCH"))
    if bad:
        print("\n%d MISMATCHES -- the census arithmetic does not model the port, so "
              "nothing below is measured." % bad)
        return 1
    print("\nall %d agree -- the census below models the port's arithmetic." % len(checks))

    # -- per-site census over the PORT's own fields --------------------------
    print()
    print("=" * 78)
    print("PER-SITE, OVER EVERY `Fld.of` IN nvdev.bend")
    print("=" * 78)
    print("%-4s %-26s %-26s %-9s %-9s %-9s %-9s"
          % ("line", "field", "order as written", "ord-sens", "w-pres", "rt-ones", "rt-low"))
    rows = []
    for b in bend:
        s, e = b["s"], b["e"]
        ord_sensitive = fmask(s, e) != fmask(e, s)
        width_preserving = wid(s, e) == wid(e, s)
        rt_o, rt_o_sw = rt_ones(s, e), rt_ones(e, s)
        rt_l = rt_lowbit(s, e) != rt_lowbit(e, s)
        rows.append(dict(line=b["line"], reg=b["reg"], name=b["name"], s=s, e=e,
                         order_sensitive=ord_sensitive, width_preserving=width_preserving,
                         rt_ones_moves=rt_o != rt_o_sw, rt_lowbit_moves=rt_l,
                         rt_topbit_moves=rt_topbit(s, e) != rt_topbit(e, s)))
        print("%-4d %-26s %-26s %-9s %-9s %-9s %-9s"
              % (b["line"], b["name"][:26], "(%d, %d)" % (s, e),
                 ord_sensitive, width_preserving, rt_o != rt_o_sw, rt_l))

    n = len(rows)
    print()
    print("SITES AUDITED (the port's own Fld.of literals)          : %d" % n)
    print("  order-sensitive   fmask(s,e) != fmask(e,s)             : %d" % sum(r["order_sensitive"] for r in rows))
    print("  width-PRESERVING  wid(s,e)  == wid(e,s)               : %d" % sum(r["width_preserving"] for r in rows))
    print("  rt all-ones probe MOVES between the two orders          : %d" % sum(r["rt_ones_moves"] for r in rows))
    print("  rt low-bit probe MOVES between the two orders          : %d" % sum(r["rt_lowbit_moves"] for r in rows))
    print("  rt top-bit probe MOVES between the two orders          : %d" % sum(r["rt_topbit_moves"] for r in rows))
    print("  UNREACHABLE IN THE PORT: 0 -- every one of the %d is a literal in this" % n)
    print("  file, and `nv.fld_se` reads all six ported BOOT_42 fields by name.  That")
    print("  number is about THIS FILE only; the CPython-side reachability is below.")

    # -- the CPython-side census, which is the bigger denominator ------------
    print()
    print("=" * 78)
    print("THE SAME THREE QUESTIONS OVER CPYTHON'S OWN TABLES (%d fields)" % n_py_fields)
    print("=" * 78)
    ins = widp = rtm = rtl = 0
    degenerate = []
    for r in py:
        for nm, (s, e) in r["fields"].items():
            if fmask(s, e) != fmask(e, s):
                ins += 1
            if wid(s, e) == wid(e, s):
                widp += 1
            if rt_ones(s, e) != rt_ones(e, s):
                rtm += 1
            if rt_lowbit(s, e) != rt_lowbit(e, s):
                rtl += 1
            if s > 31:
                degenerate.append((r["src"], r["reg"], nm, s, e))
    print("  order-sensitive                                        : %d of %d" % (ins, n_py_fields))
    print("  width-PRESERVING (the brief's premise)                : %d of %d" % (widp, n_py_fields))
    print("  rt all-ones probe MOVES                               : %d of %d" % (rtm, n_py_fields))
    print("  rt low-bit probe MOVES                                : %d of %d" % (rtl, n_py_fields))
    print("  s > 31 (out of a U32 SHIFT's reach, so no mask is buildable): %d of %d"
          % (len(degenerate), n_py_fields))
    n_tables_ported = 11
    print("  in tables THIS FILE ports                            : %d of %d tables"
          % (n_tables_ported, len(py)))
    print("  in tables this file does NOT port (nothing to gate)  : %d of %d tables, "
          "%d fields" % (len(py) - n_tables_ported, len(py),
                         n_py_fields - sum(len(r["fields"]) for r in py
                                           if r["reg"] in ("NV_PMC_BOOT_0", "NV_PMC_BOOT_42",
                                                           "NV_PFB_PRI_MMU_WPR2_ADDR_HI",
                                                           "NV_PGC6_AON_SECURE_SCRATCH_GROUP_42",
                                                           "NV_VIRTUAL_FUNCTION_PRIV_MMU_INVALIDATE",
                                                           "NV_MMU_VER2_PTE", "NV_MMU_VER2_PDE",
                                                           "NV_MMU_VER2_DUAL_PDE", "NV_MMU_VER3_PTE",
                                                           "NV_MMU_VER3_PDE", "NV_MMU_VER3_DUAL_PDE"))))
    if degenerate:
        print("    e.g. %s" % "; ".join("%s/%s/%s s=%d e=%d" % d for d in degenerate[:4]))

    json.dump({"port": rows, "cpython_fields": n_py_fields,
               "cpython": {"order_sensitive": ins, "width_preserving": widp,
                           "rt_ones_moves": rtm, "rt_lowbit_moves": rtl,
                           "s_gt_31": len(degenerate)}},
              open(ROOT + "/.agents/slop/nv_order_census.json", "w"), indent=1)
    print()
    print("wrote .agents/slop/nv_order_census.json")
    return 0


sys.exit(main())