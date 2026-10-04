#!/usr/bin/env python3
"""rf2-mutate.py -- the MUTATION TABLE for `schedule/rangeify.bend`, measured.

THE HARNESS DIFFS WHOLE `name=value` LINES, NOT ROW NAMES.  A name-comparing
harness reported 0 for all 30 mutations in one unit and 0 for all 68 in another
(`agent-core.md`), because renaming a row hides every mutation of the def it
reads.  So this file parses both runs into `{name: value}` and reports the
SYMMETRIC DIFFERENCE OF THE WHOLE LINES.

EACH MUTATION IS ONE EDIT, applied to a scratch copy, checked, run, and reverted.
`ALL PROOFS CHECK` is required before the run: a mutation that stops compiling is
reported as COMPILE-FAIL and is not counted as a zero, because a type error is a
loud failure and a silent one is what a mutation table is for.

M1-M20 are the previous table, re-measured here because the substrate moved (the
`ct` table's op sets, the fixture, and two rule bodies).  M21-M35 are this unit's.
"""
import os, re, shutil, subprocess, sys, tempfile
import patch_not_apply as PNA

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, "bin", "bend")
WORK = os.path.join(ROOT, ".agents", "slop", "rf2root", "schedule", "rf2_work.bend")
ORIG = WORK + ".orig"

# (id, a unique substring of the line to replace, the replacement, what it is for)
MUT = [
 # ---- the previous table, re-measured ---------------------------------------
 ("M1", "    case True{} : M.Hop{M.hop_ar(r), 0}\n    case False{}: r",
         "    case True{} : r\n    case False{}: M.Hop{M.hop_ar(r), 0}",
         "`rf_self` KEEPS self -- the `ret is not uop` inversion"),
 ("M2", "  U32.is_eq(M.mp_src(ar, self, 0), M.mp_src(ar, self, 1))", "  True{}",
         "`rb_ident` always True -- upat.py:100-105 gone"),
 ("M3", "    case o <> t: Bool.and(O.op_in(have, o), rf_early.go(have, t))",
         "    case o <> t: Bool.or(O.op_in(have, o), rf_early.go(have, t))",
         "`rf_early`'s subset test and -> or"),
 ("M4", "   O.PMEntry{3, [O.OpsINDEX{}],  [O.OpsPARAM{}]},            # 319  INDEX(PARAM) -> PARAM",
         "   O.PMEntry{3, [O.OpsINDEX{}],  [O.OpsRANGE{}]},            # M4: reject set misspelled",
         "`dg_3` reject set {PARAM} misspelled as {RANGE}"),
 ("M5", "  Bool.and(M.mp_is(ar, self, O.OpsNOOP{}), M.mp_nsrc_is(ar, self, 0))",
         "  M.mp_is(ar, self, O.OpsNOOP{})",
         "`noopf.at`'s `len(x.src)==0` conjunct removed"),
 ("M6", "  raf.keep.go(ar, O.Arena.src_from(ar, self, 1), [M.mp_src0(ar, self)])",
         "  raf.keep.go(ar, M.mp_srcs(ar, self), Nil{})",
         "`raf.keep_srcs` filters src[0] as well"),
 ("M7", "  Nat.is_eq(List.length(&2, U32, kept), 1n)", "  False{}",
         "`raf_one` never True -- always rebuilds"),
 ("M8", "              Bool.and(M.mp_is(ar, self, O.OpsSHRINK{}), rf_zero_off.go(rf_offsets(ar, self))),",
         "              rf_zero_off.go(rf_offsets(ar, self)),",
         "`rf_strip`'s SHRINK test dropped"),
 ("M9", "    case True{} : List.append(&2, U32, acc, [M.mp_src0(ar, x)])\n    case False{}: match sh:",
         "    case True{} : List.append(&2, U32, acc, [x])\n    case False{}: match sh:",
         "`nic.of`'s INDEX arm turned into pass-through"),
 ("M10", "  Bool.and(M.mp_is(ar, self, O.OpsPARAM{}), rf_addr_eq(fx, self, S.Aalu{}))",
         "  rf_addr_eq(fx, self, S.Aalu{})",
         "`rf_alu_param`'s `op is Ops.PARAM` conjunct removed"),
 ("M11", "  rf_renumber.of(rf_tag_is_empty(ar, self), ar, self, n)",
         "  rf_renumber.of(Bool.not(rf_tag_is_empty(ar, self)), ar, self, n)",
         "`rf_renumber`'s `r.tag != ()` guard inverted"),
 ("M12", "                                    O.ARange{[n], rf_axis(ar, self)}, rf_no_tag()))",
         "                                    O.ARange{[n], O.AXIS_WEAK{}}, rf_no_tag()))",
         "`rf_renumber` rebuilds the AxisType as AXIS_WEAK instead of reading it"),
 ("M13", "  Bool.and(M.mp_is(ar, self, O.OpsSTAGE{}), M.mp_nsrc_is(ar, self, 2))",
         "  Bool.and(M.mp_is(ar, self, O.OpsSTAGE{}), M.mp_nsrc_ge(ar, self, 1))",
         "`ab_4_claim`'s `len(x.src)==2` relaxed to `>= 2`"),
 ("M14", "  U32.is_eq(M.mp_nsrc(ar, self), 2)", "  U32.is_eq(M.mp_nsrc(ar, self), 3)",
         "`rf_fb_two`'s `len(x.src)==2` test inverted"),
 ("M15", "  O.eq_arg(M.mp_arg(ar, x), O.APy{O.CInvalid{}})",
         "  M.mp_is(ar, x, O.OpsCONST{})",
         "`ab_8.pat`'s `arg == Invalid` weakened to `op is CONST`"),
 ("M16", "    case O.OpsAFTER{}  : True{}\n    case O.OpsPARAM{}  : True{}\n    case O.OpsUNSHARD{}: True{}\n    case O.OpsMSTACK{} : True{}\n    case O.OpsBUFFER{} : True{}\n    case O.OpsALLOC{}  : True{}",
         "    case O.OpsBUFFER{} : True{}",
         "`rf_is_bufid5`'s op set reduced to {BUFFER}"),
 ("M17", "  dg_3.of(rf_addr_eq(fx, M.mp_src0(ar, self), S.Aalu{}), ar, self)",
          "  dg_3.of(rf_addr_eq(fx, M.mp_src0(ar, self), S.ALocal{}), ar, self)",
         "`dg_3`'s `addrspace is ALU` test changed to LOCAL"),
 ("M18", "def t_claim_ab_stg3() -> U32: claim_full(ab_table(), G.fx(g()), g_ar(g()), g_st3(g()))",
         "def t_claim_ab_stg3() -> U32: claim_n(ab_table(), g_ar(g()), g_st3(g()))",
         "`claim_full` replaced by `claim_n` for stg3"),
 ("M19", "   O.PMEntry{6, [O.OpsRANGE{}],  Nil{}}]                     # 327  r -> renumber_range",
         "   O.PMEntry{6, [O.OpsCONST{}],  Nil{}}]                     # 327  r -> renumber_range",
         "`dg_6`'s RANGE rule given the WRONG op set"),
 ("M20", "   O.PMEntry{7, [O.OpsINDEX{}],   [O.OpsAFTER{}]},          # 124  AFTER.f(INDEX) -- root INDEX\n"
         "   O.PMEntry{8, [O.OpsINDEX{}],   [O.OpsMSTACK{}]}]         # 127  MSTACK.f(INDEX) -- root INDEX",
         "   O.PMEntry{7, [O.OpsINDEX{}],   [O.OpsAFTER{}]}]          # M20: ct_8's ENTRY DELETED",
         "`ct_8`'s rule DELETED from the table -- only the count row can see this"),
 ("M20b", "   O.PMEntry{8, [O.OpsINDEX{}],   [O.OpsMSTACK{}]}]         # 127  MSTACK.f(INDEX) -- root INDEX",
          "   O.PMEntry{8, [O.OpsINDEX{}],   Nil{}}]         # M20b: reject set dropped",
          "`ct_8`'s REJECT SET dropped -- a THEOREM, see the note"),
 # ---- this unit's ------------------------------------------------------------
 ("M21", "   O.PMEntry{4, [O.OpsSTAGE{}],   [O.OpsINDEX{}]},          # 118  INDEX.f(STAGE) -- root STAGE",
         "   O.PMEntry{4, [O.OpsINDEX{}],   [O.OpsINDEX{}]},          # M21: THE ORIGINAL DEFECT",
         "ct_4's op set back to the CHILD's -- the bug this unit was given"),
 ("M22", "   O.PMEntry{8, [O.OpsINDEX{}],   [O.OpsMSTACK{}]}]         # 127  MSTACK.f(INDEX) -- root INDEX",
         "   O.PMEntry{8, [O.OpsMSTACK{}],   [O.OpsMSTACK{}]}]         # M22: THE ORIGINAL DEFECT",
         "ct_8's op set back to the CHILD's"),
 ("M23", "   O.PMEntry{5, [O.OpsSTAGE{}],   Nil{}},                   # 120  CONST.f(STAGE) -- root STAGE",
         "   O.PMEntry{5, [O.OpsCONST{}, O.OpsCAST{}], Nil{}},          # M23: THE ORIGINAL DEFECT",
         "ct_5's op set back to the CHILD's"),
 ("M24", "def MOPS_ROOT_FB() -> List<&2, O.Op>: [O.OpsINDEX{}]", "def MOPS_ROOT_FB() -> List<&2, O.Op>: [O.OpsRESHAPE{}, O.OpsPERMUTE{}, O.OpsEXPAND{}, O.OpsPAD{}, O.OpsSHRINK{}, O.OpsFLIP{}]",
         "pm_mops tag 0's op set back to the CHILD's"),
 ("M24b", "def MOPS_ROOT_AF() -> List<&2, O.Op>: [O.OpsAFTER{}]", "def MOPS_ROOT_AF() -> List<&2, O.Op>: [O.OpsRESHAPE{}, O.OpsPERMUTE{}, O.OpsEXPAND{}, O.OpsPAD{}, O.OpsSHRINK{}, O.OpsFLIP{}, O.OpsINDEX{}]",
         "pm_mops tag 1's op set back to the CHILD's"),
 ("M24c", "def MOPS_ROOT_EN() -> List<&2, O.Op>: [O.OpsEND{}]", "def MOPS_ROOT_EN() -> List<&2, O.Op>: [O.OpsRESHAPE{}, O.OpsPERMUTE{}, O.OpsEXPAND{}, O.OpsPAD{}, O.OpsSHRINK{}, O.OpsFLIP{}]",
         "pm_mops tag 2's op set back to the CHILD's"),
 ("M25", "  Bool.and(M.mp_is(ar, M.mp_src0(ar, self), O.OpsINDEX{}), rf_stage_tail(ar, self, M.mp_src0(ar, self)))",
         "  Bool.and(M.mp_is(ar, self, O.OpsINDEX{}), rf_stage_tail(ar, M.mp_src0(ar, self), self))",
         "`rf_same_tail` back to reading the OUTER node's op"),
 ("M26", "def ct_6.of(alt: Bool, +ar: O.Arena, +self: U32) -> M.Hop:\n"
         "  match alt:\n    case True{} : M.Hop{ar, M.mp_src0(ar, self)}\n    case False{}: M.Hop{ar, 0}",
         "def ct_6.of(alt: Bool, +ar: O.Arena, +self: U32) -> M.Hop:\n"
         "  match alt:\n    case True{} : M.Hop{ar, M.mp_src0(ar, self)}\n    case False{}: M.Hop{ar, M.mp_src(ar, self, 0)}",
         "`ct_6` given the ELSE arm back -- the catch-all defect"),
 ("M27", "def dev_none_shape(d: S.Dev) -> Bool: True{}", "def dev_none_shape(d: S.Dev) -> Bool: False{}",
         "`dev_none_shape` back to False -- ct_8 fires on a device-bearing MSTACK"),
 ("M28", "    case 0: mop\n    case 4: tail", "    case 0: True{}\n    case 4: tail",
         "`ct_src.of`'s tag-0 body test dropped"),
 ("M29", "    case 6: cvar2", "    case 6: True{}", "`ct_src.of`'s tag-6 body test dropped"),
 ("M30", "    case 7: after", "    case 7: True{}", "`ct_src.of`'s tag-7 body test dropped"),
 ("M31", "                               List.append(&2, U32, [M.mp_src(ar, M.mp_src0(ar, self), 0)], O.Arena.src_from(ar, self, 1)))",
         "                               [M.mp_src(ar, M.mp_src0(ar, self), 0)])",
         "`ct_8`'s rebuild drops `idx.src[1:]`"),
 ("M32", "def ct_8.of(devless: Bool, +ar: O.Arena, +self: U32) -> M.Hop:\n"
         "  match devless:\n    case True{} : M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, self), ar, self,",
         "def ct_8.of(devless: Bool, +ar: O.Arena, +self: U32) -> M.Hop:\n"
         "  match devless:\n    case True{} : M.mp_replace(M.mp_op(ar, self), O.ANone{}, ar, self,",
         "`ct_8` hardcodes ANone -- THE ARG DEFECT the old gate could not see"),
 ("M32b", "def ab_7(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:\n"
          "  M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, self), ar, self, ab_7_srcs(ar, self))",
          "def ab_7(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:\n"
          "  M.mp_replace(M.mp_op(ar, self), O.ANone{}, ar, self, ab_7_srcs(ar, self))",
          "`ab_7` hardcodes ANone -- the original arg defect, on the CALL site"),
 ("M36", "  ct_8.of(Bool.and(ct_8_claim(ar, self),\n                   rf_dev_is_none(fx, M.mp_src(ar, M.mp_src0(ar, self), 0))), ar, self)",
          "  ct_8.of(rf_dev_is_none(fx, M.mp_src(ar, M.mp_src0(ar, self), 0)), ar, self)",
          "`ct_8` loses its OWN pattern re-check -- the claim then lives only in the table"),
 ("M38", "    case o <> t: Bool.and(O.op_in(have, o), rf_early.go(have, t))" + chr(10) + chr(10) +
          "def rf_early(ar: O.Arena, self: U32, rej: List<&2, O.Op>) -> Bool:",
          "    case o <> t: Bool.or(O.op_in(have, o), rf_early.go(have, t))" + chr(10) +
          "" + chr(10) + "def rf_early(ar: O.Arena, self: U32, rej: List<&2, O.Op>) -> Bool:",
          "M3 AND M36 TOGETHER: the reject test goes vacuous AND `ct_8` has no self-check"),
 ("M37", "  ct_6.of(M.mp_is(ar, M.mp_src0(ar, self), O.OpsCONST{}), ar, self)",
          "  ct_6.of(Bool.not(M.mp_is(ar, M.mp_src0(ar, self), O.OpsCONST{})), ar, self)",
          "`ct_6`'s claim INVERTED -- the const branch and the pass-through swapped"),
 ("M33", "                    Bool.or(M.mp_is(ar, M.mp_src0(ar, self), O.OpsCONST{}),\n                            ct_6_casted(ar, M.mp_src0(ar, self)))))",
         "                    True{}))",
         "`ct_5_claim`'s child-op test replaced by True"),
 ("M34", "def hop_srcops(+r: M.Hop) -> String: srcops_n(M.hop_ar(r), M.hop_ix(r))",
         "def hop_srcops(+r: M.Hop) -> String: \"\"",
         "`hop_srcops` answers the empty string for everything"),
 ("M35", "    case +x <> t  : srcops.go(ar, t, String.concat([acc, \".\", U32.show(O.Ops.value(M.mp_op(ar, x)))]))",
         "    case +x <> t  : srcops.go(ar, t, acc)",
         "`srcops.go` drops the element -- the sequnence gate is dead"),
]

def run(path):
  p = subprocess.run([BEND, path], capture_output=True, text=True, timeout=600)
  if p.returncode != 0 and not p.stdout.strip():
    return None, (p.stdout + p.stderr).strip().splitlines()[:6]
  d = {}
  for line in p.stdout.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      d[k.strip()] = v.strip()
  return d, None

def check(path):
  p = subprocess.run([BEND, path, "--check-only"], capture_output=True, text=True, timeout=600)
  return p.stdout.splitlines()[0] if p.stdout.splitlines() else "?"

if not os.path.exists(ORIG):
  shutil.copy(WORK, ORIG)
BASE_SRC = open(ORIG).read()

base, err = run(ORIG)
if base is None:
  print("BASELINE DOES NOT RUN:\n" + "\n".join(err)); sys.exit(1)
print(f"baseline: {len(base)} rows, {check(ORIG)}")

rows = []
for mid, old, new, what in MUT:
  if BASE_SRC.count(old) != 1:
    rows.append((mid, what, PNA.not_applied("pattern occurs %dx"
                                             % BASE_SRC.count(old)), [])); continue
  open(WORK, "w").write(BASE_SRC.replace(old, new))
  st = check(WORK)
  if st != "ALL PROOFS CHECK":
    rows.append((mid, what, "COMPILE-FAIL", [])); continue
  got, err = run(WORK)
  if got is None:
    rows.append((mid, what, "RUN-FAIL", [])); continue
  moved = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
  rows.append((mid, what, f"{len(moved)} moved", moved))

open(WORK, "w").write(BASE_SRC)
print(f"{'id':5} {'n':>3}  what moved")
sharp = 0
for mid, what, verdict, moved in rows:
  sharp += 1 if moved else 0
  print(f"{mid:5} {verdict:>10}  {what}")
  for k in moved: print(f"{'':19}{k}: {base.get(k)} -> {got.get(k) if False else ''}")
open(os.path.join(ROOT, ".agents", "slop", "rf2-mutations.txt"), "w").write(
  "".join(f"{mid}\t{verdict}\t{what}\t{','.join(m)}\n" for mid, what, verdict, m in rows))
print(f"\n{sharp}/{len(rows)} sharp")
