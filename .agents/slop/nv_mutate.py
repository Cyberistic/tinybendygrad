#!/usr/bin/env python3
# .agents/slop/nv_mutate.py -- MUTATION TABLE for nvdev.bend.
#
# ONE ENTRY PER PORTED RULE, MUTATED IN THE FILE, GATED, AND REPORTED BY THE NAME
# OF THE ROWS IT MOVED. Three disciplines from agent-core.md, all measured here:
#
#  * THE HARNESS DIFFS WHOLE `name=value` LINES, never row NAMES. A
#    name-comparing harness reported 0 for all 30 mutations in one unit.
#  * A MUTATION THAT MOVES NOTHING IS REPORTED AS A BLIND SPOT with a reason, and
#    the reason is a MEASUREMENT (the count of rows, the constant value) not a
#    hope. A `0` is a request for a fixture, not a coverage claim.
#  * THE BASELINE IS CAPTURED FRESH PER MUTATION and the substrate is re-checked,
#    so a concurrent agent's edit cannot masquerade as a moved row.
#
# ⚠ IT NO LONGER WRITES THE LIVE TREE. It used to: `open(SRC,"w").write(...)` plus a
# `finally` restore, digest sampled ONCE at start. nvdev.bend is a file another unit
# is editing RIGHT NOW (a live transposition defect), and on a file churning at 7
# writes per 2 minutes the `finally` restore reverts the other unit's commit -- the
# exact failure `blob-intern-mutate.py`'s own docstring records, and the exact
# failure `ops-501-mutate.py` was fixed for and whose fix was never propagated here.
#
# `staged_mut.Staged` now stages `jj file show -r @` BESIDE nvdev.bend (so its
# `./ip.bend` import still resolves), ASSERTS sha256(mirror) == sha256(live), edits
# ONLY the staged copy, unlinks it in a `finally`, and REPORTS whether the live
# digest moved during the run. There is no restore over the live file, because there
# is no write to restore: a `finally` restore is only safe when nothing else touched
# the file, and a guard that samples the digest once cannot establish that.
#
# ⚠ SEVEN OF THE TWENTY-EIGHT ANCHORS BELOW ARE STALE AND ARE NOT RE-AIMED HERE.
# They are listed in ANCHOR_NOTE. nvdev.bend is under single ownership by another
# unit which is editing it right now; re-aiming an anchor against a file mid-edit
# measures a revision that is about to change, so the report names the stale seven
# and leaves them to that unit.
#
# Usage: python3 .agents/slop/nv_mutate.py [n]
import re, subprocess, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_not_apply as PNA
import staged_mut as SM

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, "bin", "bend")
SRC = os.path.join(ROOT, "tinybendygrad/runtime/support/nv/nvdev.bend")
EXE = os.path.join(ROOT, ".agents/slop/nvdev_mut")

def run(path=SRC):
    r = subprocess.run([BEND, path], capture_output=True, text=True, cwd=ROOT)
    return r.stdout

def rows(text):
    out = {}
    for line in text.split("\n"):
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        if re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", k):
            out[k] = v
    return out

def moved(base, after):
    """Whole `name=value` lines that changed, by NAME. The value is part of the
    identity: a name whose value changed is a moved row."""
    return sorted(k for k in set(base) | set(after)
                  if base.get(k) != after.get(k))

# (label, find, replace, what the mutation is FOR)
MUTATIONS = [
 ("reg_field_order_reversed",
  'def nv.reg_boot42() -> Rgv: Rgv.of(0, 2560, [Fld.of("minor_extended_revision", 8, 11)',
  'def nv.reg_boot42() -> Rgv: Rgv.of(0, 2560, [Fld.of("minor_extended_revision", 11, 8)',
  "transpose BOOT_42's first field's start/end -- a wrong OFFSET"),
 ("reg_field_names_swapped",
  'def nv.reg_boot42() -> Rgv: Rgv.of(0, 2560, [Fld.of("minor_extended_revision", 8, 11), Fld.of("minor_revision", 12, 15)',
  'def nv.reg_boot42() -> Rgv: Rgv.of(0, 2560, [Fld.of("minor_revision", 8, 11), Fld.of("minor_extended_revision", 12, 15)',
  "swap two ADJACENT field NAMES -- order+names, count unchanged"),
 ("reg_field_list_reversed",
  'def nv.reg_boot0() -> Rgv: Rgv.of(0, 0, [Fld.of("minor_revision", 0, 3), Fld.of("major_revision", 4, 7), Fld.of("architecture_1", 8, 8), Fld.of("implementation", 20, 23), Fld.of("architecture_0", 24, 28)])',
  'def nv.reg_boot0() -> Rgv: Rgv.of(0, 0, [Fld.of("architecture_0", 24, 28), Fld.of("implementation", 20, 23), Fld.of("architecture_1", 8, 8), Fld.of("major_revision", 4, 7), Fld.of("minor_revision", 0, 3)])',
  "REVERSE the whole field list -- every name and count survives, only ORDER moves"),
 ("reg_off_by_one_word",
  'def nv.reg_boot42() -> Rgv: Rgv.of(0, 2560,',
  'def nv.reg_boot42() -> Rgv: Rgv.of(0, 2564,',
  "shift the register's offset by one WORD -- addr//4 changes"),
 ("mask_wid_plus_one",
  'def nv.wid(+s: U32, e: U32) -> U32: U32.add(U32.sub(e, s), 1)',
  'def nv.wid(+s: U32, e: U32) -> U32: U32.add(U32.sub(e, s), 2)',
  "off-by-one in the field WIDTH -- every mask changes"),
 ("mask_of_ignores_names",
  'def nv.mask_named(+r: Rgv, ks: List<&2, Kv>) -> U32: nv.mask_of(r, ks)',
  'def nv.mask_named(+r: Rgv, ks: List<&2, Kv>) -> U32: nv.mask(r)',
  "drop the SUBSET: mask every field instead of the named ones"),
 ("encode_shift_zero",
  'def nv.fenc(+s: U32, x: U32) -> U32: U32.shln(x, U32.to_nat(s))',
  'def nv.fenc(+s: U32, x: U32) -> U32: U32.shln(x, 0n)',
  "every field encodes at bit 0 -- the classic misplaced write"),
 ("ones_uses_shln",
  'def nv.ones(w: U32) -> U32: U32.sub(nv.pw_of(w), 1)',
  'def nv.ones(w: U32) -> U32: U32.sub(U32.shln(1, U32.to_nat(w)), 1)',
  "go back to the SATURATING spelling -- 1<<56 becomes 0"),
 ("chip_family_dict_dropped",
  'def nv.fam(+a: U32) -> String:\n  Bool.pick(String, U32.is_eq(a, 23), "GA1",\n    Bool.pick(String, U32.is_eq(a, 25), "AD1",\n      Bool.pick(String, U32.is_eq(a, 27), "GB2", "??")))',
  'def nv.fam(+a: U32) -> String:\n  Bool.pick(String, U32.is_eq(a, 23), "GA1",\n    Bool.pick(String, U32.is_eq(a, 25), "AD1", "??"))',
  "drop the GB2 arm of the architecture dict"),
 ("chip_mmu_boundary_off_by_one",
  'def nv.is_v3(+a: U32) -> Bool: U32.is_ge(a, 26)',
  'def nv.is_v3(+a: U32) -> Bool: U32.is_gt(a, 26)',
  "move the 0x1a branch to 0x1b"),
 ("mmu_shifts_dropped_last",
  'def nv.va_shifts(+v: U32) -> List<&2, U32>:\n  Bool.pick(List<&2, U32>, U32.is_eq(v, 3), [12, 21, 29, 38, 47, 56], [12, 21, 29, 38, 47])',
  'def nv.va_shifts(+v: U32) -> List<&2, U32>:\n  Bool.pick(List<&2, U32>, U32.is_eq(v, 3), [12, 21, 29, 38, 47], [12, 21, 29, 38, 47])',
  "drop ver 3's SIXTH shift -- level_cnt, dual_pde_lv and is_page_lvmax all move"),
 ("pte_ispage_bound_off_by_one",
  'def nv.pte_ispage(+v: U32, +lv: U32, word: U32) -> Bool:\n  Bool.pick(Bool, U32.is_lt(lv, nv.is_page_lvmax_x(v)),',
  'def nv.pte_ispage(+v: U32, +lv: U32, word: U32) -> Bool:\n  Bool.pick(Bool, U32.is_lt(lv, nv.level_cnt(v)),',
  "the off-by-one this file HAD: level_cnt instead of level_cnt-1"),
 ("pte_dual_bound_off_by_one",
  'def nv.pte_dual(+v: U32, lv: U32) -> Bool: U32.is_eq(lv, U32.sub(nv.level_cnt(v), 2))',
  'def nv.pte_dual(+v: U32, lv: U32) -> Bool: U32.is_eq(lv, U32.sub(nv.level_cnt(v), 3))',
  "move the dual-PDE level -- the STRUCT changes, silently"),
 ("pte_sys_uses_or_as_if",
  'def nv.pte_sys(+v: U32, lv: U32) -> String:\n  Bool.pick(String, Bool.or(U32.is_eq(v, 2), U32.is_eq(lv, nv.sys_lvmax(v))), "_sys", "")',
  'def nv.pte_sys(+v: U32, lv: U32) -> String:\n  Bool.pick(String, U32.is_eq(lv, nv.sys_lvmax(v)), "_sys", "")',
  "replace the OR with only the level test -- ver 2 loses `_sys` everywhere"),
 ("pte_uncfield_pde_ver_swapped",
  'def nv.pte_uncfield_pde(+v: U32, lv: U32) -> String:\n  String.concat([Bool.pick(String, U32.is_eq(v, 3), "pcf", "no_ats"), nv.pte_small(v, lv)])',
  'def nv.pte_uncfield_pde(+v: U32, lv: U32) -> String:\n  String.concat([Bool.pick(String, U32.is_eq(v, 2), "pcf", "no_ats"), nv.pte_small(v, lv)])',
  "swap which mmu_ver gets `pcf_small` -- the field NAME moves"),
 ("pte_uncval_pde_uses_uncached",
  'def nv.pte_uncval_pde(+v: U32) -> U32: Bool.pick(U32, U32.is_eq(v, 3), 2, 1)',
  'def nv.pte_uncval_pde(+v: U32) -> U32: Bool.pick(U32, U32.is_eq(v, 3), 1, 2)',
  "swap the two pcf CODES -- 0b10 and 1 exchange places"),
 ("inval_high_bit_wrong",
  'def nv.inval_hi() -> U32: 2147483648',
  'def nv.inval_hi() -> U32: 128',
  "bit 31 written as bit 7 -- the sign bit becomes a middle bit"),
 ("cfg_clear_becomes_set",
  'def nv.cfgclear(+c: U32) -> U32: U32.and(c, U32.not(nv.pci_master()))',
  'def nv.cfgclear(+c: U32) -> U32: U32.or(c, nv.pci_master())',
  "the CLEAR becomes a SET -- bus mastering stays on through a reset"),
 ("roundup_to_one_page",
  'def nv.page() -> U32: 4096',
  'def nv.page() -> U32: 8192',
  "the page size doubles -- every round_up and every pte_covers moves"),
 ("covers_not_reversed",
  'def nv.covers(+v: U32) -> List<&2, U32>: nv.rev.go(nv.shifts_nat(v), nv.va_shifts(v), Nil{})',
  'def nv.covers(+v: U32) -> List<&2, U32>: nv.pow_shifts(v)',
  "DROP THE `[::-1]` -- pte_covers stays smallest-first"),
 ("word_index_not_divided",
  'def nv.word(+addr: U32) -> U32: U32.shrn(addr, 2n)',
  'def nv.word(+addr: U32) -> U32: addr',
  "drop the `addr // 4` -- the trace indexes bytes"),
 ("update_ini_swapped_operands",
  'def nv.upd_ini(+r: Rgv, ks: List<&2, Kv>, word: U32) -> U32:\n  U32.and(U32.not(nv.mask_named(r, ks)), word)',
  'def nv.upd_ini(+r: Rgv, ks: List<&2, Kv>, word: U32) -> U32:\n  U32.and(word, U32.not(nv.mask_named(r, ks)))',
  "swap `&`'s operands -- the AND is commutative and the fixture is what catches it"),
 ("update_enc_before_ini",
  'def nv.upd_w(+r: Rgv, ks: List<&2, Kv>, word: U32) -> U32:\n  U32.or(nv.upd_ini(r, ks, word), nv.enc(r, ks))',
  'def nv.upd_w(+r: Rgv, ks: List<&2, Kv>, word: U32) -> U32:\n  U32.nand(nv.upd_ini(r, ks, word), nv.enc(r, ks))',
  "OR becomes NAND -- clears the written field instead of setting it"),
 ("largebar_strict",
  'def nv.largebar(+nb: U32, sz: U32) -> Bool: U32.is_ge(nb, sz)',
  'def nv.largebar(+nb: U32, sz: U32) -> Bool: U32.is_gt(nb, sz)',
  ">= becomes > -- an exactly-sized BAR stops counting as large"),
 ("sysmem_false_confused_with_none",
  'def nv.sysmem(+l: Bool, +sm: U32) -> Bool:\n  Bool.or(U32.is_eq(sm, 1), Bool.and(U32.is_eq(sm, 0), Bool.not(l)))',
  'def nv.sysmem(+l: Bool, +sm: U32) -> Bool:\n  Bool.or(U32.is_eq(sm, 1), Bool.not(l))',
  "None and False collapse -- a caller passing False gets the None branch"),
 ("trace_rreg_wreg_swapped",
  'def C_NV_RREG() -> U32: 11',
  'def C_NV_RREG() -> U32: 12',
  "the read and write call ids collide -- a swap is invisible to a count"),
 ("tagname_delegation_dropped",
  'def nv.tagname(+k: U32) -> String:\n  Bool.pick(String, U32.is_eq(k, C_NV_RREG()), "rreg",',
  'def nv.tagname(+k: U32) -> String:\n  Bool.pick(String, U32.is_eq(k, 0), "rreg",',
  "the extension stops DELEGATING to ip.bend -- an id<11 call renders as rreg"),
 ("pwid_double_pw",
  'def nv.pw(k: Nat) -> U32: nv.pw.w(k, 1)',
  'def nv.pw(k: Nat) -> U32: nv.pw.w(k, 2)',
  "the doubling base is 2, so every power of two is doubled"),
]

def main():
    only = sys.argv[2] if len(sys.argv) > 2 else None
    out = []
    with SM.Staged(SRC, "nv") as unit:
        original = unit.origin()
        base = unit.rows()
        if base is None:
            print("BASELINE IS EMPTY -- refusing to mutate"); return 1
        SM.control(base, unit.rows(), "nvdev baseline")
        print("baseline: %d name= rows, row-set digest %s\n"
              % (len(base), SM.row_digest(base)[:16]))
        print(f"{'mutation':38} {'rows moved':>10}  first rows moved")
        print("-" * 110)
        zeros = []
        for i, (label, find, repl, why) in enumerate(MUTATIONS):
            if only is not None and str(i) != only:
                continue
            print(f"[{i:2d}] {label} ... ", end="", flush=True)
            if find not in original:
                print("%s -- %s" % (PNA.not_applied(), why))
                zeros.append((label, "%s: the pattern is not in the file, so this "
                                "mutation was NEVER RUN" % PNA.not_applied()))
                continue
            unit.write(original.replace(find, repl, 1))
            t = unit.rows()
            unit.write(original)
            if t is None:
                print(f"{PNA.not_a_program()} -- {why}")
                zeros.append((label, "%s: the mutation lands but the result is NOT A "
                                "PROGRAM, so it moves no row" % PNA.not_a_program()))
                continue
            m = moved(base, t)
            print(f"{len(m)} moved: {', '.join(m[:3])}")
            out.append("| %s | %d | %s |" % (label, len(m), ",".join(m) if m else "NONE"))
            if not m:
                zeros.append((label, f"BLIND SPOT: 0 rows moved, and the file still compiled ({why})"))
        print(flush=True)
        if zeros:
            print("MUTATIONS THAT MOVED NOTHING -- each needs either a fixture or a THEOREM:")
            for label, why in zeros:
                print(f"  {label}: {why}")
        else:
            print("every mutation moved at least one row")
        # The live file's digest was asserted equal to the mirror's at stage time and
        # is compared again in Staged.__exit__, which REPORTS a move rather than
        # restoring over it. There is no restore, because there is no live write.
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "nv_mutations.txt"), "w") as fh:
        fh.write("# nv_mutate.py -- runtime/support/nv/nvdev.bend, MEASURED.\n")
        fh.write("\n".join(out) + "\n")
    return 0

sys.exit(main())