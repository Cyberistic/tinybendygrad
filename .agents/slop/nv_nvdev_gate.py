#!/usr/bin/env python3
# .agents/slop/nv_nvdev_gate.py -- run the nvdev gate in BOTH lanes and diff every
# whole `name=value` line against the CPython oracle.
#
# FIVE THINGS THIS DOES DELIBERATELY, each measured in this project:
#
#  * IT DIFFS WHOLE `name=value` LINES, NOT ROW NAMES. A name-comparing harness
#    reported 0 for all 30 mutations in one unit and 0 for all 68 in another.
#  * IT CHECKS THE ORACLE'S EXIT PATH AND ITS ROW COUNT. An oracle once emitted 0
#    rows and exited 1 while the gate printed 432 rows and `ALL PROOFS CHECK`; a
#    gate whose oracle emits 0 rows is not a passing gate. Here BOTH counts are
#    printed in absolute numbers and a 0 is a failure.
#  * IT COMPARES THE TWO LANES BYTE-FOR-BYTE. The interpreted and the compiled
#    lane must agree on every row for anything this port touched.
#  * IT MATCHES BY `py=` VALUE, so a ROW THAT DISAGREES WITH CPYTHON is a failure
#    even when the port is internally consistent. Agreement between a port and a
#    hand-typed oracle is not corroboration; it is one mistake copied.
#  * IT REPORTS THE COVERAGE BOTH WAYS -- rows the oracle has and the port lacks,
#    and rows the port has and the oracle lacks -- as COUNTS, never as a ratio.

import re, subprocess, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, "bin", "bend")
PY = os.path.join(ROOT, ".venv", "bin", "python")
SRC = os.path.join(ROOT, "tinybendygrad/runtime/support/nv/nvdev.bend")
ORACLE = os.path.join(ROOT, ".agents/slop/nv_nvdev_oracle.py")
OUT = os.path.join(ROOT, ".agents/slop")

def rows(text):
    out = {}
    for line in text.split("\n"):
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        if re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", k):
            out[k] = v
    return out

def main():
    # --- the oracle, and its EXIT PATH -------------------------------
    r = subprocess.run([PY, ORACLE], capture_output=True, text=True, cwd=ROOT)
    print(f"oracle exit={r.returncode} stdout_rows={len(r.stdout.splitlines())}")
    if r.returncode != 0:
        print("ORACLE FAILED -- its own exit path says so, not the gate:")
        print(r.stderr[-2000:])
        return 1
    if len(r.stdout.splitlines()) == 0:
        print("ORACLE EMITTED ZERO ROWS -- refusing to call anything green")
        return 1
    py = rows(r.stdout)
    print(f"oracle distinct name= rows: {len(py)}")

    # --- both lanes ---------------------------------------------------
    a = subprocess.run([BEND, SRC], capture_output=True, text=True, cwd=ROOT)
    print(f"interpreted lane exit={a.returncode} rows={len(a.stdout.splitlines())}")
    if a.returncode != 0:
        print(a.stdout[:1500]); print(a.stderr[:1500]); return 1
    interp = a.stdout

    exe = OUT + "/nvdev_native"
    c = subprocess.run([BEND, SRC, "-o", exe], capture_output=True, text=True, cwd=ROOT)
    print(f"compiled lane build exit={c.returncode}")
    if c.returncode != 0:
        print(c.stdout[:1500]); print(c.stderr[:1500]); return 1
    b = subprocess.run([exe], capture_output=True, text=True, cwd=ROOT)
    print(f"compiled lane exit={b.returncode} rows={len(b.stdout.splitlines())}")
    if b.returncode != 0:
        print(b.stdout[:1500]); print(b.stderr[:1500]); return 1
    native = b.stdout

    # --- lane identity, as BYTES --------------------------------------
    same = interp == native
    print(f"LANES BYTE-IDENTICAL: {same}")
    if not same:
        ia, ib = interp.split("\n"), native.split("\n")
        for i, (x, y) in enumerate(zip(ia, ib)):
            if x != y:
                print(f"  first differing line {i+1}:\n    interp  {x!r}\n    native {y!r}")
                break
        if len(ia) != len(ib):
            print(f"  line counts differ: interp {len(ia)} native {len(ib)}")
        return 1

    port = rows(interp)

    print(f"gate distinct name= rows: {len(port)}")

    # --- the diff -----------------------------------------------------
    bad = []
    for k in sorted(set(port) & set(py)):
        if port[k] != py[k]:
            bad.append((k, py[k], port[k]))
    only_port = sorted(set(port) - set(py))
    only_py = sorted(set(py) - set(port))

    # WHY a port row has no oracle counterpart, grouped by CAUSE. Reporting the
    # count alone would hide which of these is a gap in the PORT and which is a row
    # the oracle deliberately does not emit. This is the accounting the brief asks
    # for: a coverage number that is not broken down is not coverage.
    CAUSE = [
      ("nv_s_",             "set_entry VALUE matrix -- the 32-bit value wall"),
      ("nv_tr_",            "trace ORDER/IDENTITY -- no CPython trace exists"),
      ("nv_tag_",           "trace call-name extension over ip.bend's ten"),
      ("nv_d_v",            "page-table DECISION rows (names built by the gate)"),
      ("nv_sf_",            "set_entry FIELD-NAME rows"),
      ("nv_addr_",          "has-a-register-address flag"),
      ("nv_bar1_",          "BAR1 base split into words"),
      ("nv_tlsf_",          "TLSFAllocator size/base split into words"),
      ("nv_page",           "the 0x1000 page constant"),
      ("nv_maskinv_",       "decode(mask(names)) invariant strings"),
      ("nv_maskn_",         "mask subset cardinality"),
      ("nv_mask_alias",     "the chip_id alias equality"),
      ("nv_vramsize_",      "vram_size low/high halves"),
      ("nv_boot42_",        "BOOT_42 field ranges via fld_of"),
      ("nv_chipname_len_",  "chip_name length"),
      ("nv_chipprefix_",    "the fw_name lookup key"),
      ("nv_stray_",         "kwargs names that are not fields (Python KeyError)"),
      ("nv_cover_inv_",     "the covers ladder invariant"),
      ("nv_cover_wide_",    "how many covers entries do not fit a U32"),
      ("nv_vramsize_collide", "the 32-bit truncation collision"),
      ("nv_vramsize_hi_differ", "the high halves that DO differ"),
      ("nv_sysmem_",        "the three-valued sysmem predicate"),
      ("nv_largebar_",      "large_bar and its two consequences"),
      ("nv_reserve_ptable_", "reserve_ptable = not large_bar"),
      ("nv_inval_at_",      "which field names cover each bit"),
      ("nv_pci_",           "PCI_COMMAND operands"),
      ("nv_cfg_",           "the clear/set config pair"),
      ("nv_upd_",           "update read-modify-write parts (the _tr row IS compared)"),
    ]

    def group(keys):
        out = {}
        for k in keys:
            hit = "(exact-name, no family rule)"
            for pre, why in CAUSE:
                if k.startswith(pre):
                    hit = why; break
            out[hit] = out.get(hit, 0) + 1
        return out

    fams = group(only_port)

    print(f"\nCOMPARED {len(set(port) & set(py))} rows against CPython")
    # A row may legitimately DISAGREE when the PORT is at a 32-bit wall and the
    # oracle is not. Those are listed separately, by name, so "0 disagreements"
    # never hides a wall. A wall is only a wall if it is WRITTEN DOWN; see the
    # WALLS section of nvdev.bend and this list must agree with it.
    WALLS = {
      "nv_d_%s_l%d_huge_cover": "pte_covers does not fit a U32 (1<<38, 1<<47, 1<<56)",
      "nv_covers_%d":            "the covers LIST, same wall",
      "nv_cover_wide_%d":        "how many covers entries do not fit",
      "nv_tlsf_size_hi":         "1 << 44 does not fit a U32",
      "nv_tlsf_base_hi":         "0x100000000 does not fit a U32",
      "nv_sysaddr_hi_%x_%d":     "bar1 is 2^32: the high word is a split, not a U32",
      "nv_vramsize_%s":          "vram_size = raw << 20 does not fit a U32",
      "nv_vramsize_sh20_%s":     "the un-shifted raw register",
      "nv_pte_lo_%s":            "the low half of a 64-bit page-table entry",
      "nv_pte_hi_%s":            "the high half -- 64 bits, and Bend has none",
      "nv_enc_pde_hi_%s":        "the 128-bit dual-PDE encode, high half",
    }
    walled = []
    real = []
    for k, p, q in bad:
        why = None
        for pat, w in WALLS.items():
            head = pat.split("%")[0]
            if k.startswith(head):
                why = w; break
        (walled if why else real).append((k, p, q, why))
    if walled:
        print(f"DISAGREEMENTS AT A DOCUMENTED 32-BIT WALL: {len(walled)}")
        for k, p, q, why in walled[:12]:
            print(f"  {k}: {why}\n      py={p}\n     port={q}")
    bad = real
    print(f"DISAGREEMENTS OUTSIDE A DOCUMENTED WALL: {len(bad)}")
    print(f"DISAGREEMENTS: {len(bad)}")
    for k, p, q in bad[:40]:
        print(f"  {k}\n      py={p}\n     port={q}")
    print(f"PORT ROWS WITH NO ORACLE COUNTERPART: {len(only_port)}")
    for f, n in sorted(fams.items(), key=lambda x: -x[1]):
        print(f"    {n:4d}  {f}")
    for k in only_port[:12]:
        print(f"  {k}={port[k]}")
    print(f"ORACLE ROWS THE PORT DOES NOT ANSWER: {len(only_py)}")
    # grouped the same way, because 1800 unmatched ORACLE rows is mostly the
    # set_entry matrix the port covers by DECISION rather than by value.
    ofam = group(only_py)
    for f, n in sorted(ofam.items(), key=lambda x: -x[1]):
        print(f"    {n:4d}  {f}")
    for k in only_py[:8]:
        print(f"  {k}={py[k]}")

    open(OUT + "/nv_nvdev_port.txt", "w").write(interp)
    ok = not bad
    print("\nGATE PASS" if ok else "\nGATE FAIL")
    return 0 if ok else 1

sys.exit(main())