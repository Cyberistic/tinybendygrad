#!/usr/bin/env bash
# The MUTATION RUNNER for tinybendygrad/runtime/support/am/ip.bend.
#
# One edit per row of the mutation table at the foot of the .bend file, applied
# to a SCRATCH COPY, and the INTERPRETED lane re-run. The useful column is "rows
# MOVED", because a mutation that moves nothing measures what this gate does NOT
# see. It is reported as a blind spot, never closed with a row that encodes it.
set -uo pipefail
cd "$(dirname "$0")/../.."
F=tinybendygrad/runtime/support/am/ip.bend
# the scratch MUST live BESIDE the real file at the SAME depth: the relative
# imports are three levels up and a copy anywhere else cannot resolve them.
SCRATCH="tinybendygrad/runtime/support/am/ip_scratch_mut.bend"
TMP="${TMPDIR:-/tmp}/ip_mut.$$"
mkdir -p "$TMP"
trap 'rm -f "$SCRATCH"' EXIT
cp "$F" "$SCRATCH"

run() { # $1 = label, $2 = python edit expression operating on `src`
  if ! python3 - "$SCRATCH" "$2" <<'PY'
import io, sys
p, expr = sys.argv[1], sys.argv[2]
# A typo'd separator must NOT read as "rows moved = 0": a mutation that never
# applied prints the BASE output and is indistinguishable from a genuine
# equivalence. M44 once shipped a single `|` instead of `|||` and reported 0.
parts = expr.split('|||')
assert len(parts) == 2 and all(parts), f'BAD MUTATION EXPRESSION, want old|||new: {expr[:70]}'
s = io.open(p, encoding='utf-8').read()
old, new = parts
assert old in s, f'MUTATION TARGET NOT FOUND: {old[:70]}'
io.open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
  then echo "$1|||HARNESS-FAIL"; return; fi
  ./bin/bend "$SCRATCH" > "$TMP/out.txt" 2>&1
  if ! grep -q 'ip-done=1' "$TMP/out.txt"; then
    echo "$1|||COMPILE-FAIL"
  else
    # Diff the WHOLE `name=value` line, positionally. Two earlier metrics were
    # wrong here: `cut -d= -f2-` throws the name away, so a mutation that SWAPS
    # two adjacent values becomes a delete+insert pair that `grep -c '^<'`
    # counts once instead of twice; and comparing the multiset of values cannot
    # tell a swap at all. `ip_sweep.py` compares positionally and is correct.
    n=$(diff "$TMP/base.txt" "$TMP/out.txt" | grep -c '^<')
    echo "$1|||$n"
  fi
  cp "$F" "$SCRATCH"
}

./bin/bend "$F" > "$TMP/base.txt" 2>&1
echo "base rows: $(wc -l < "$TMP/base.txt")"
echo "label|||rows moved"

run M01 'U32.is_ne(kiq_xcc, NO_XCC())|||U32.is_ne(kiq_xcc, 0)'
run M02 'V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 15)))|||V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 17)))'
run M03 'def pte.page.gfx10(pte_lv: U32) -> H.I64:
  Bool.pick(H.I64, pte.page.is_not_ptb(pte_lv), pte.pde_10(), i64_lit(0, 0))|||def pte.page.gfx10(pte_lv: U32) -> H.I64:
  Bool.pick(H.I64, pte.page.is_not_ptb(pte_lv), pte.pde_10(), pte.pde_10())'
run M04 'def pte.of.mt(gc0: U32, uncached: U32, mtype_uc: U32) -> H.I64:
  Bool.pick(H.I64, U32.is_eq(uncached, 1), pte.mtype(gc0, mtype_uc), i64_lit(0, 0))|||def pte.of.mt(gc0: U32, uncached: U32, mtype_uc: U32) -> H.I64:
  pte.mtype(gc0, mtype_uc)'
run M05 'def MTYPE_SHIFT_GFX12() -> U32: 54|||def MTYPE_SHIFT_GFX12() -> U32: 50'
run M06 'def PDE_BFS_SHIFT() -> U32: 59|||def PDE_BFS_SHIFT() -> U32: 56'
run M07 'def PTE_FRAG_MASK() -> U32: 31|||def PTE_FRAG_MASK() -> U32: 255'
run M08 'def pte.rwe() -> H.I64:
  i64_lit(0, U32.or(PTE_WRITEABLE(), U32.or(PTE_READABLE(), PTE_EXECUTABLE())))|||def pte.rwe() -> H.I64:
  i64_lit(0, U32.or(PTE_WRITEABLE(), U32.or(PTE_EXECUTABLE(), PTE_READABLE())))'
run M09 '[pm4.write_data(3), U32.shln(1, 16n), req_addr, 0, req]|||[pm4.write_data(3), U32.shln(1, 17n), req_addr, 0, req]'
run M10 'U32.shln(1, U32.to_nat(vmid)),
    U32.shln(1, U32.to_nat(vmid)), 32,|||U32.shln(1, U32.to_nat(vmid)),
    0, 32,'
run M11 'def sdma.chan(+idx: U32) -> U32: U32.add(sdma.pipe(idx), U32.mul(sdma.queue(idx), 4))|||def sdma.chan(+idx: U32) -> U32: U32.add(sdma.queue(idx), U32.mul(sdma.pipe(idx), 4))'
run M12 'U32.add(DOORBELL_SDMA_ENGINE0(), U32.mul(sdma.chan(idx), SDMA_ENGINE_STRIDE()))|||U32.add(DOORBELL_SDMA_ENGINE0(), U32.mul(sdma.chan(idx), U32.add(SDMA_ENGINE_STRIDE(), 1)))'
run M13 '    SDMA_ENGINE_STRIDE())), DOORBELL_OFFSET_SCALE())|||    SDMA_ENGINE_STRIDE())), U32.sub(DOORBELL_OFFSET_SCALE(), 1))'
run M14 'U32.to_nat(U32.add(U32.mul(dev_inst, 4), col))|||U32.to_nat(U32.add(U32.mul(col, 4), dev_inst))'
# `sdma.rbsize` is defined AFTER `mqd.qsize`, and Bend rejects the forward
# reference, so the wrong formula is INLINED: that is exactly the mutation
# "qsize is really rbsize", off by the 1 in the subtract.
run M15 'def mqd.qsize(ring_size: U32) -> U32: mqd.size(ring_size)|||def mqd.qsize(ring_size: U32) -> U32: U32.sub(mqd.bits(U32.div(ring_size, 4)), 1)'
run M16 '  Bool.pick(U32, U32.is_zero(x), 0, U32.add(U32.from_nat(U32.log2(x)), 1))|||  Bool.pick(U32, U32.is_zero(x), 1, U32.add(U32.from_nat(U32.log2(x)), 1))'
run M17 'def pm4.packet3(sel: U32, count: U32) -> U32:
  U32.or(U32.shln(PM4_TYPE3(), PM4_TYPE3_SHIFT()),
    U32.or(U32.shln(U32.and(sel, PM4_SEL_MASK()), PM4_SEL_SHIFT()),
      U32.shln(U32.and(count, PM4_COUNT_MASK()), PM4_COUNT_SHIFT())))|||def pm4.packet3(sel: U32, count: U32) -> U32:
  U32.or(U32.shln(PM4_TYPE3(), PM4_TYPE3_SHIFT()),
    U32.or(U32.shln(U32.and(count, PM4_SEL_MASK()), PM4_SEL_SHIFT()),
      U32.shln(U32.and(sel, PM4_COUNT_MASK()), PM4_COUNT_SHIFT())))'
run M18 'def PM4_DST_SEL_SHIFT() -> Nat: 8n|||def PM4_DST_SEL_SHIFT() -> Nat: 16n'
run M19 'List.reverse(&2, U32, psp.sos_components(mp0_0, mp0_1, mp0_2)), 0n), 0)|||List.reverse(&2, U32, psp.sos_components(mp0_0, mp0_1, mp0_2)), 1n), 0)'
run M20 '   PSP_FW_INTF_DRV(), BL_LOAD_INTFDRV(),
   PSP_FW_DBG_DRV(), BL_LOAD_DBGDRV(),|||   PSP_FW_DBG_DRV(), BL_LOAD_DBGDRV(),
   PSP_FW_INTF_DRV(), BL_LOAD_INTFDRV(),'
run M21 'def psp.boot_time_tmr(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> Bool:
  Bool.or(V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 6), Bool.or(
    V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 14), Bool.or(
      V.eq(mp0_0, mp0_1, mp0_2, 14, 0, 2), V.eq(mp0_0, mp0_1, mp0_2, 14, 0, 3))))|||def psp.boot_time_tmr(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> Bool:
  Bool.or(V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 6), Bool.or(
    V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 14), Bool.or(
      V.eq(mp0_0, mp0_1, mp0_2, 14, 0, 2), False{})))'
run M22 'def smu.arch(+mp1_0: U32, +mp1_1: U32, +mp1_2: U32) -> U32:
  Bool.pick(U32, U32.is_eq(mp1_0, 14), 2,
    Bool.pick(U32, Bool.or(V.ge(mp1_0, mp1_1, mp1_2, 13, 0, 6),
      Bool.or(V.eq(mp1_0, mp1_1, mp1_2, 13, 0, 7), V.eq(mp1_0, mp1_1, mp1_2, 13, 0, 10))), 1, 0))|||def smu.arch(+mp1_0: U32, +mp1_1: U32, +mp1_2: U32) -> U32:
  Bool.pick(U32, U32.is_eq(mp1_0, 14), 2,
    Bool.pick(U32, Bool.or(V.ge(mp1_0, mp1_1, mp1_2, 13, 0, 6),
      False{}), 1, 0))'
run M23 'def ih.getbits(entry: List<&2, U32>, +start: Nat, +end: Nat) -> U32:
  H.getbits(ih.word(entry, start), Nat.mod(start, 32n), Nat.mod(end, 32n))|||def ih.getbits(entry: List<&2, U32>, +start: Nat, +end: Nat) -> U32:
  H.getbits(ih.word(entry, start), start, end)'
run M24 'def ih.err.reasm(+ctx0: U32, ctx1: U32) -> U32:
  U32.or(U32.and(ctx0, IH_ERR_LO_MASK()), U32.or(
    U32.and(U32.shrn(ctx0, 16n), IH_ERR_MID_MASK()),
    U32.and(U32.shln(ctx1, 16n), IH_ERR_HI_MASK())))|||def ih.err.reasm(+ctx0: U32, ctx1: U32) -> U32:
  U32.or(U32.and(ctx0, IH_ERR_LO_MASK()), U32.or(
    U32.and(U32.shrn(ctx0, 16n), IH_ERR_MID_MASK()),
    U32.and(U32.shrn(ctx1, 16n), IH_ERR_HI_MASK())))'
run M25 'def ih.err_lo(soc21: Bool) -> U32: Bool.pick(U32, soc21, 24, 23)|||def ih.err_lo(soc21: Bool) -> U32: Bool.pick(U32, soc21, 25, 23)'
run M26 'def DOORBELL_RANGE_SIZE() -> U32: 20|||def DOORBELL_RANGE_SIZE() -> U32: 21'
run M27 'def GFX_CMD_ID_AUTOLOAD_RLC() -> U32: 33|||def GFX_CMD_ID_AUTOLOAD_RLC() -> U32: 32'
run M28 'def sdma.setup.fail_at(+sd0_0: U32, +sd0_1: U32, +sd0_2: U32, +idx: U32) -> U32:
  Bool.pick(U32, Bool.and(V.ge(sd0_0, sd0_1, sd0_2, 5, 0, 0), U32.is_gt(idx, 0)), 1, 0)|||def sdma.setup.fail_at(+sd0_0: U32, +sd0_1: U32, +sd0_2: U32, +idx: U32) -> U32:
  Bool.pick(U32, Bool.and(V.ge(sd0_0, sd0_1, sd0_2, 5, 0, 0), U32.is_ge(idx, 0)), 1, 0)'
run M29 'def Tr.emit.go(+refused: Bool, k: U32, arg: U32, +calls: List<&2, Call>,
               +next: U32, nth: U32, at: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, arg}])),|||def Tr.emit.go(+refused: Bool, k: U32, arg: U32, +calls: List<&2, Call>,
               +next: U32, nth: U32, at: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, List.append(&2, Call, calls, [Call{k, arg}]), calls),'
run M30 'def Tr.refuse.go(+refused: Bool, +nth: U32, +at: U32) -> Tr:
  Tr{Nil{}, 0, Bool.or(refused, U32.is_eq(U32.add(nth, 1), at)),|||def Tr.refuse.go(+refused: Bool, +nth: U32, +at: U32) -> Tr:
  Tr{Nil{}, 0, Bool.or(refused, U32.is_eq(U32.add(nth, 1), U32.add(at, 1))),'
run M31 'def PSP_FRAME_DWORDS() -> U32: 16|||def PSP_FRAME_DWORDS() -> U32: 15'
run M32 'def psp.cmd_off(wptr: U32) -> U32: U32.add(wptr, PSP_FRAME_DWORDS())|||def psp.cmd_off(wptr: U32) -> U32: U32.add(wptr, U32.add(PSP_FRAME_DWORDS(), 1))'
run M33 'def SDMA_ENTRY_AID_STRIDE() -> U32: 4|||def SDMA_ENTRY_AID_STRIDE() -> U32: 2'
run M34 'def gfx.q.queue(+kiq_xcc: U32, idx: U32) -> U32:
  Bool.pick(U32, gfx.db.is_kiq(kiq_xcc), MQD_KIQ_QUEUE(), U32.mod(idx, 4))|||def gfx.q.queue(+kiq_xcc: U32, idx: U32) -> U32:
  Bool.pick(U32, gfx.db.is_kiq(kiq_xcc), MQD_KIQ_QUEUE(), U32.div(idx, 4))'
run M35 'def mqd.pq.aql(aql: U32, no_update_rptr: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(aql, 1),
    [PQ_QUEUE_FULL(), PQ_SLOT_BASED_WPTR(), no_update_rptr], [0, 0, 0])|||def mqd.pq.aql(aql: U32, no_update_rptr: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(aql, 1),
    [PQ_QUEUE_FULL(), PQ_SLOT_BASED_WPTR(), 1], [0, 0, 0])'
run M36 'def psp.reg_pref(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> U32:
  Bool.pick(U32, V.ge(mp0_0, mp0_1, mp0_2, 14, 0, 0), PREF_MPASP(), PREF_MP0())|||def psp.reg_pref(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> U32:
  Bool.pick(U32, V.ge(mp0_0, mp0_1, mp0_2, 13, 0, 0), PREF_MPASP(), PREF_MP0())'
run M37 'def pte.gfx9.is_pde(+pte_lv: U32, is_table: U32) -> Bool:
  Bool.and(U32.is_eq(is_table, 0),
    Bool.and(U32.is_ne(pte_lv, VM_PTB()), U32.is_ne(pte_lv, VM_PDB0())))|||def pte.gfx9.is_pde(+pte_lv: U32, is_table: U32) -> Bool:
  Bool.and(U32.is_eq(is_table, 0), U32.is_ne(pte_lv, VM_PTB()))'
run M38 'def pte.gfx9.is_bfs(+pte_lv: U32, is_table: U32) -> Bool:
  Bool.and(U32.is_eq(is_table, 1), U32.is_eq(pte_lv, VM_PDB1()))|||def pte.gfx9.is_bfs(+pte_lv: U32, is_table: U32) -> Bool:
  Bool.and(U32.is_eq(is_table, 1), U32.is_eq(pte_lv, VM_PTB()))'
run M39 'def smu.has_mca(arch: U32) -> Bool: smu.has(arch, SMU_COL_MCA_CNT())|||def smu.has_mca(arch: U32) -> Bool: smu.has(arch, SMU_COL_GFX_RESET())'
run M40 'def PSP_ADDR64() -> H.I64: H.i64_of_hi_lo(287454020, 1432778632)|||def PSP_ADDR64() -> H.I64: H.i64_of_hi_lo(287454020, 287454020)'

# COMPANIONS FOR THE NON-MOVING MUTATIONS. M08, M22 and M39 are EQUIVALENCE
# mutations: they move nothing because they are not a different function, they
# are the same function written another way. Each is therefore paired with a
# mutation on the SAME RULE that IS a different function, which proves the
# rule is genuinely covered by the gate, and the non-mover is reported beside
# it as the blind spot that it is.
#
# M41 pairs M39. After the leaf sweep pruned the 46 unread columns, only four
# `SMU_COL_` survive, and their zero/nonzero patterns over the three smu rows are
# (T,T,T) for DRAM_HI, (F,T,F) for BOTH GFX_RESET and MCA_CNT, and (T,F,F) for
# MODE1. M39 swaps MCA_CNT for GFX_RESET, the surviving lockstep pair, so it moves
# nothing. M41 swaps MCA_CNT for MODE1, which is NOT lockstep, so it moves rows.
run M41 'def smu.has_mca(arch: U32) -> Bool: smu.has(arch, SMU_COL_MCA_CNT())|||def smu.has_mca(arch: U32) -> Bool: smu.has(arch, SMU_COL_MODE1())'
# M42 pairs M22. `V.ge(13,0,6)` already covers 13.0.7 and 13.0.10, so the two
# `V.eq` disjuncts are dead. The 14 arm is NOT redundant, so this moves rows.
run M42 'def smu.arch(+mp1_0: U32, +mp1_1: U32, +mp1_2: U32) -> U32:
  Bool.pick(U32, U32.is_eq(mp1_0, 14), 2,|||def smu.arch(+mp1_0: U32, +mp1_1: U32, +mp1_2: U32) -> U32:
  Bool.pick(U32, U32.is_eq(mp1_0, 13), 2,'
# M43 pairs M08. `U32.or` is commutative, so re-associating the RWE union is
# the same set. DROPPING a term is a different function, and this moves rows.
run M43 'def pte.rwe() -> H.I64:
  i64_lit(0, U32.or(PTE_WRITEABLE(), U32.or(PTE_READABLE(), PTE_EXECUTABLE())))|||def pte.rwe() -> H.I64:
  i64_lit(0, U32.or(PTE_WRITEABLE(), PTE_READABLE()))'

# M44 and M45 lock the two bugs the strengthened oracle found. Both were green
# before, because the oracle row re-transcribed `lo, _ = data64_le(...)` and so
# agreed with a port that had dropped the high word. `M09`-era readings of the
# packet said SIXTEEN words; CPython says SEVENTEEN.
# M44: the high half of the WR_CONFIRM address collapses onto the low half.
run M44 'def kiq.pkt.wr_hi(kiq_va: U32, base: U32) -> U32: H.data64_hi(H.data64(kiq.pkt.addr(kiq_va, base)))|||def kiq.pkt.wr_hi(kiq_va: U32, base: U32) -> U32: H.data64_lo(H.data64(kiq.pkt.addr(kiq_va, base)))'
# M45: the `+ 0x1010` fence offset dropped from the WR_CONFIRM target address.
run M45 'H.i64_of_hi_lo(0, U32.add(U32.add(kiq_va, base), KIQ_FENCE_OFF()))|||H.i64_of_hi_lo(0, U32.add(kiq_va, base))'

echo "=== scratch: $TMP ==="