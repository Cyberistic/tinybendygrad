#!/usr/bin/env python3
"""amd_mutate.py -- the MEASURED mutation table for tinybendygrad/runtime/ops_amd.bend.

Applies one edit to a scratch copy, runs the INTERPRETED lane, and diffs the
`name=value` ROWS against the clean run. A mutation that moves nothing measures
what this gate does NOT see, and those are reported as BLIND SPOTS rather than
closed with a row that encodes the bug.

Usage: python3 .agents/slop/amd_mutate.py
"""
import os, re, subprocess, sys, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, 'bin', 'bend')
F = os.path.join(ROOT, 'tinybendygrad/runtime/ops_amd.bend')

# (id, regex, replacement, what it is testing)
MUTATIONS = [
 ("M1", r"Sig\{H\.round_up_u32\(off, k\), U32\.add\(H\.round_up_u32\(off, k\), k\)\}",
        "Sig{H.round_up_u32(off, k), U32.add(off, k)}",
  "sig.slot's ADVANCE. device.py:365's walrus REBINDS `offset`, so the advance is "
  "`round_up(off,k) + k`; this edits it to the UNROUNDED `off + k`, which is what "
  "`D.iter_sig` in device.bend does and the disagreement REPORTED in the header. "
  "Every layout row and every pack row moves."),
 ("M2", r"pack\.one\(U32\.is_eq\(A\.at\(a\), end\),", "pack.one(True{},",
  "pack_args' `if offset != end`: with the test forced True no interior pad is "
  "ever emitted, so every mixed fixture loses its `B` elements and the totals "
  "drop by the padding."),
 ("M3", r"pack\.tail\(pack_end\(ks\), size\)\)", "Nil{})",
  "the trailing blob of hcq2:83. Dropping it shortens every list by one element, "
  "which is what `amd_pack_n_*` and every `elrow` see."),
 ("M4", r"\[E\{1, U32\.sub\(size, end\)\}\]", "[E{0, U32.sub(size, end)}]",
  "the tail is a BLOB and not a WORD. The LENGTH and the TOTAL are unchanged, so "
  "only the element-kind rendering can see it -- and that is exactly the class of "
  "bug a byte total misses."),
 ("M5", r"U32\.and\(U32\.min\(nw, msw\), 4095\)", "U32.and(U32.min(nw, msw), 65535)",
  "tmpring's WAVES field is 12 bits and not 16."),
 ("M6", r"U32\.shln\(wsc, 12n\)\)", "U32.shln(wsc, 4n))",
  "the union's WAVESIZE sits at bit 12. The ctypes record declares width 13/15/18 "
  "at offset 4 and the EFFECTIVE layout -- measured by driving the record -- is "
  "12, so every tmpring row moves."),
 ("M7", r"Bool\.pick\(U32, U32\.is_eq\(t0, 9\),\s*\n?\s*MEM_ALIGN_GFX9\(\), MEM_ALIGN_NEW\(\)\)",
        "Bool.pick(U32, U32.is_eq(t0, 10),\n    MEM_ALIGN_GFX9(), MEM_ALIGN_NEW())",
  "scr_align's arch test is `target[0] != 9`. Off by one on the major."),
 ("M8", r"U32\.div\(U32\.div\(array_count, sae\), xccs\)", "U32.div(array_count, U32.mul(sae, xccs))",
  "se_cnt is TWO integer divisions and not one over the product. They disagree "
  "whenever the product does not divide."),
 ("M9", r"Bool\.or\(U32\.is_eq\(t0, 11\), U32\.is_eq\(t0, 12\)\)\), False\{\}\)",
        "Bool.or(U32.is_eq(t0, 11), U32.is_eq(t0, 13))), False{})",

  "the arch allow-list's second arm is `(11, 12)` and not `(11, 13)`: gfx12 is "
  "allowed and gfx13 is not."),
 ("M10", r"Bool\.or\(U32\.is_eq\(iface, IFACE_PCI\(\)\),\s*\n\s*Bool\.or\(U32\.is_eq\(iface, IFACE_USB\(\)\),\s*\n\s*Bool\.or\(U32\.is_eq\(iface, IFACE_MOCKPCI\(\)\), U32\.is_eq\(iface, IFACE_MOCKUSB\(\)\)\)\)\)",
         "U32.is_eq(iface, IFACE_PCI())",
  "is_am FOLLOWS THE INHERITANCE: `USBIface(PCIIface)` (:810) and both mock "
  "PCIIfaces (:846) are PCIIface subclasses, so four of the seven ifaces are AM. "
  "Reducing it to `== PCIIface` moves the USB and both mock rows -- and every "
  "`can_recover` row with them, which is the load-bearing consequence."),
 ("M11", r"U32\.is_lt\(v, 16\), \"\", hx\.digit", "U32.is_lt(v, 16), \"0\", hx.digit",
  "the LEADING hex digit is EMPTY below 16, which is what makes `%x` UNPADDED. A "
  "port that always emits it writes `gfx0942`-shaped strings for a five-digit "
  "minor, and `amd_arch_115501` is the only row that sees the difference."),
 ("M12", r"U32\.is_gt\(pd\.lds\(gs\), pd\.lds_cap\(lds_kb\)\)", "U32.is_ge(pd.lds(gs), pd.lds_cap(lds_kb))",
  "the LDS refusal is a STRICT `>`. 131072 granules is EXACTLY the 64KB cap, so "
  "`>=` refuses a request Python accepts; the 131072/131584 pair is the only "
  "thing that sees it."),
 ("M13", r"String\.starts_with\(tag, \"ring_\"\),\n\s*String\.starts_with\(tag, \"write_ptr_\"\)\)",
         "String.starts_with(tag, \"ring\"),\n    String.starts_with(tag, \"write_ptr\"))",
  "the trailing underscore is in EACH of the four prefixes: `ring` alone is not "
  "a match. Only the bare-`ring` fixture sees it, so this is a ONE-ROW mutation "
  "and it is called out as such."),
 ("M14", r"Bool\.and\(Bool\.and\(U32\.is_eq\(t0, 11\), U32\.is_eq\(t1, 5\)\), U32\.is_eq\(t2, 1\)\)",
         "Bool.and(Bool.and(U32.is_eq(t0, 11), U32.is_eq(t1, 5)), U32.is_eq(t2, 2))",
  "vgpr_size_per_cu's five-version set drops (11,5,1) for (11,5,2). It is a SET, "
  "so a port that tests four of the five versions moves the same rows."),
 ("M15", r"Bool\.pick\(U32, refused, next, U32\.add\(next, 1\)\)", "Bool.pick(U32, refused, next, next)",
  "the id the seam mints stops advancing. Only `amd_init_next` and "
  "`amd_init_ids_monotone` can see it, which is the honest width of that claim."),
 ("M16", r"pk_end\.go\(ks, 0\)", "pk_end.go(ks, 1)",
  "the trailing blob's base is the running offset; starting it at 1 makes every "
  "`B` one byte short. The element COUNT is unchanged, so only the `elrow` "
  "strings and the byte totals move."),
 ("M17", r"U32\.and\(raw, 536870911\)", "U32.and(raw, 536870895)",
  "the 29-bit mask loses its top bit. `amd_sq_wptr_536870911_64` is the only "
  "fixture at the mask boundary, so this is a ONE-ROW mutation."),
 ("M18", r"U32\.and\(U32\.div\(U32\.add\(base, off\), 32\), 536870911\)",
         "U32.and(U32.div(U32.add(base, off), 16), 536870911)",
  "the gfx11 wptr correction converts a BYTE offset to a DWORD index with //32. "
  "The correction's own value is not in the oracle -- only the wptr is -- so this "
  "is a BLIND SPOT and is reported as one."),
 ("M19", r"U32\.div\(spx, U32\.mul\(wsc, scr_align\(t0\)\)\)",
         "U32.div(spx, U32.mul(wsc, LDS_PER_CU_GFX9_5()))",
  "scr_num_waves' inner divisor is `wave_scratch * mem_alignment` and not a "
  "constant. The mem_alignment arm is a separate def, so this sees only that the "
  "divisor is read at all."),
 ("M20", r"U32\.mul\(H\.prod_u32\(\[xccs, inst, se, sa, wgp\]\), 8\)", "H.prod_u32([xccs, inst, se, sa, wgp])",
  "the PMC record size is `prod(...) * 8` and the 8 is the whole of the scaling. "
  "The SQ block counts and the record size are the two claims about :196, and "
  "this is the one that catches a dropped factor."),
 ("M21", r"U32\.max\(ps, PRIV_FLOOR\(\)\)", "ps",
  "tmpring's `max(private_segment_size, 128)` floor. Every fixture passes a size "
  "at or above 128 except the 0 one, so this is a ONE-ROW mutation."),
 ("M22", r"U32\.max\(U32\.max\(ps, PRIV_FLOOR\(\)\), prev\)", "U32.max(ps, PRIV_FLOOR())",
  "scratch_buffer's high-water mark is the CLASS attribute: a SMALLER request "
  "does not shrink the buffer. `amd_scr_max_4096_128` is the row that sees it."),
 ("M23", r"Bool\.and\(Bool\.and\(U32\.is_eq\(t0, 11\), U32\.is_eq\(t1, 0\)\), Bool\.or\(U32\.is_eq\(t2, 0\), U32\.is_eq\(t2, 1\)\)\)",
         "Bool.and(Bool.and(U32.is_eq(t0, 11), U32.is_eq(t1, 0)), U32.is_eq(t2, 0))",
  "the vgpr set's (11,0,x) arm is a two-version test and not a one-version one; "
  "this drops 11.0.1, so `amd_vgpr_11_0_1x` moves and nothing else."),
 ("M24", r"def Tr\.refuse\.go\(\+refused: Bool, \+nth: U32, \+at: U32\) -> Tr:\n  Tr\{Nil\{\}, 0, Bool\.or\(refused, U32\.is_eq\(U32\.add\(nth, 1\), at\)\),\n     Bool\.pick\(U32, refused, nth, U32\.add\(nth, 1\)\), at\}",
  "def Tr.refuse.go(+refused: Bool, +nth: U32, +at: U32) -> Tr:\n  Tr{Nil{}, 0, Bool.or(refused, U32.is_eq(nth, at)),\n     Bool.pick(U32, refused, nth, U32.add(nth, 1)), at}",
  "THE RAUSE is at ordinal `at` and the counter is incremented AFTER. Firing at "
  "`nth == at` instead of `nth + 1 == at` shifts every truncation by one site, and "
  "because `Tr.refuse` is idempotent the shift is SILENT: the same number of "
  "calls is recorded, from the wrong boundary. This is the row set that pins it."),
 ("M25", r"Bool\.and\(U32\.is_eq\(k1, k2\), U32\.is_eq\(a1, a2\)\)", "U32.is_eq(k1, k2)",
  "the subsequence matcher compares the ARG too, not just the tag. Dropping the "
  "arg makes `amd_init_order` and the three `amd_has_rejects_*` rows the only "
  "things that see it -- and they are the whole reason `Tr.has` compares both."),
 ("M26", r"Tr\.has\.go\(List\.length\(&2, Call, cs\), List\.length\(&2, Call, pat\), cs, pat, 0n\)",
          "Tr.has.go(List.length(&2, Call, pat), List.length(&2, Call, pat), cs, pat, 0n)",
  "THE FUEL IS THE TRACE LENGTH, measured in ops_webgpu.bend: with the fuel set to "
  "the PATTERN length, `case 0n:` fires after `patlen` trace entries and answers "
  "True without reading `at`, so a REVERSED pattern matches. `amd_has_rejects_*` "
  "is the row that catches it and it is duplicated here for that reason."),
 ("M27", r"(def esh2\(xs: List<&2, E>, \+acc: List<&2, String>\) -> List<&2, String>:\n  match xs:\n    case Nil\{\}: )acc",
         r"\1List.reverse(&2, String, acc)",
  "the element rendering APPENDS, so it must not reverse. Reversing it prints the "
  "pack backwards -- every length and every total still right, which is why the "
  "elrow strings and not the byte counts are the claim."),
 ("M28", r"U32\.mul\(U32\.mul\(se, xccs\), 512\)\)", "U32.mul(U32.mul(se, xccs), 256))",
  "the gfx9 wave_cnt arm is `min(cu_cnt*40, se_cnt*xccs*512)`. Dropping the 512 to "
  "256 halves the ceiling, and the two gfx9 wave_cnt rows are the only claim."),
 ("M29", r"U32\.mod\(U32\.add\(read, nprofiled\), slots\)", "U32.add(read, nprofiled)",
  "prof_start's slot is `(prof_log[0] + len(profiled)) % prof_slots` -- the MODULO "
  "is what makes the log a RING. Without it there is no wrap and the 31/33 "
  "fixtures see nothing different."),
 ("M30", r"U32\.shln\(lds_kb, 10n\)", "U32.shln(lds_kb, 20n)",
  "q_lds_per_cu's gfx9.5 arm shifts the LDS size by 10 and not by 20. Only the "
  "gfx9.5 fixture reaches it, so this is a THREE-ROW mutation."),
]

def run(path):
    r = subprocess.run([BEND, path], capture_output=True, text=True, cwd=ROOT)
    out = r.stdout + r.stderr
    if 'SOME PROOFS FAIL' in out:
        return None, out
    rows = {}
    for line in out.split('\n'):
        if '=' in line and not line.startswith(('ALL ', 'Use ')):
            k, v = line.split('=', 1)
            rows[k] = v
    return rows, out

def main():
    base, out = run(F)
    if base is None:
        print("CLEAN LANE FAILED:\n", out[:2000]); return 1
    print(f"clean rows: {len(base)}")
    print(f"| # | rows moved | the edit | what it is testing |")
    print(f"| --- | --- | --- | --- |")
    for mid, pat, rep, why in MUTATIONS:
        if why is None: continue
        src = open(F).read()
        new_src, n = re.subn(pat, rep, src, count=1)
        if n == 0:
            print(f"| {mid} | NO-TEXT | `{pat}` | the pattern did not match |")
            continue
        tmp = F + '.mut'
        shutil.copy(F, tmp)
        open(tmp, 'w').write(new_src)
        got, out2 = run(tmp)
        os.remove(tmp)
        if got is None:
            print(f"| {mid} | FAILS-CHECK | `{pat}` | {why} |")
            continue
        moved = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
        print(f"| {mid} | {len(moved)} | `{pat}` | {why} |")
        if moved:
            print(f"| | | | moved: {', '.join(moved[:12])}{' ...+' + str(len(moved)-12) if len(moved) > 12 else ''} |")
    return 0

sys.exit(main())
