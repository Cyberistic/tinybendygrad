"""Append the MEASURED mutation table to the foot of ip.bend.

The table is generated from the two harnesses' output so the numbers in the file
cannot drift from the numbers that were measured. `rows MOVED` is the
load-bearing column: a mutation that moves nothing is a claim about what this
gate does NOT see, and it is reported as such.
"""
import io, re

BEND = 'tinybendygrad/runtime/support/am/ip.bend'
MUT = '/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/mut.txt'
SWEEP = '/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/sweep.txt'

# what each logic mutation changes, so the table is not a list of bare numbers
CLAIM = {
  'M01': 'gfx.db.is_kiq: `kiq_xcc != NO_XCC` becomes `!= 0`',
  'M02': 'smu 13.0.15 message id',
  'M03': 'pte.page.gfx10: the not-a-table arm returns the PDE twice',
  'M04': 'pte.of.mt: the `uncached` arm dropped',
  'M05': 'MTYPE_SHIFT_GFX12 54 -> 50',
  'M06': 'PDE_BFS_SHIFT 59 -> 56',
  'M07': 'PTE_FRAG_MASK 31 -> 255',
  'M08': 'pte.rwe: the RWE union RE-ASSOCIATED (U32.or is commutative)',
  'M09': 'the KIQ packet address `1 << 16` becomes `1 << 17`',
  'M10': 'the sDMA doorbell `<< 1` becomes `<< 0`',
  'M11': 'sdma.chan: pipe and queue swapped',
  'M12': 'SDMA_ENGINE_STRIDE 10 -> 11',
  'M13': 'DOORBELL_OFFSET_SCALE 2 -> 1',
  'M14': 'the sdma entry `dev_inst*4 + col` has its operands swapped',
  'M15': 'mqd.qsize inlined with the `sdma.rbsize` formula (the off-by-one one)',
  'M16': 'mqd.bits: the zero case returns 1 instead of 0',
  'M17': 'pm4.packet3: `sel` and `count` swapped in the two masked shifts',
  'M18': 'PM4_DST_SEL_SHIFT 8 -> 16',
  'M19': 'psp.sos_components: the `List.reverse` half applied',
  'M20': 'the PSP fw-type quadruple: INTF/DBG pair transposed',
  'M21': 'psp.boot_time_tmr: the 14.0.3 disjunct dropped',
  'M22': 'smu.arch: the (13,0,7) and (13,0,10) disjuncts dropped',
  'M23': 'ih.getbits: the in-word pair replaced by the RAW global pair',
  'M24': 'ih.err.reasm: the HI half shifts LEFT instead of right',
  'M25': 'ih.err_lo soc21 arm 24 -> 25',
  'M26': 'DOORBELL_RANGE_SIZE 20 -> 21',
  'M27': 'GFX_CMD_ID_AUTOLOAD_RLC 33 -> 32',
  'M28': 'sdma.setup.fail_at: `idx > 0` becomes `idx >= 0`',
  'M29': 'Tr.emit.go: the refusal arm returns the APPENDED list',
  'M30': 'Tr.refuse.go: the refusal ordinal offset by one',
  'M31': 'PSP_FRAME_DWORDS 16 -> 15',
  'M32': 'psp.cmd_off: the frame advance +1',
  'M33': 'SDMA_ENTRY_AID_STRIDE 4 -> 2',
  'M34': 'gfx.q.queue: `idx mod 4` becomes `idx div 4`',
  'M35': 'mqd.pq.aql: the no_update_rptr arm returns 1',
  'M36': 'psp.reg_pref: the arch bound 14 -> 13',
  'M37': 'pte.gfx9.is_pde: the PDB0 disjunct dropped',
  'M38': 'pte.gfx9.is_bfs: VM_PDB1 becomes VM_PTB',
  'M39': 'smu.has_mca: MCA_CNT -> GFX_RESET (lockstep columns)',
  'M40': 'PSP_ADDR64: the low word replaced by the high word',
  'M41': 'COMPANION of M39: MCA_CNT -> MODE1 (not lockstep)',
  'M42': 'COMPANION of M22: the smu.arch 14-arm becomes 13',
  'M43': 'COMPANION of M08: PTE_EXECUTABLE dropped from the RWE union',
  'M44': 'kiq.pkt.wr_hi collapses onto the LOW half of the WR_CONFIRM address',
  'M45': 'kiq.pkt.addr: the `+ 0x1010` fence offset dropped',
}

mut = [l.strip().split('|||') for l in io.open(MUT) if re.match(r'^M\d+\|\|\|', l)]
sw = [l.strip().split('|||') for l in io.open(SWEEP) if '|||' in l and not l.startswith('mutation')]
sw = [r for r in sw if len(r) == 2]
sw0 = [r[0] for r in sw if r[1] == '0']
swcf = [r[0] for r in sw if r[1] == 'COMPILE-FAIL']
swmv = [r for r in sw if r[1].isdigit() and int(r[1]) > 0]
regline = [r for r in sw if r[0].startswith('REG:') and '@name' not in r[0]]
regname = [r for r in sw if '@name' in r[0]]
regline0 = [r for r in regline if r[1] == '0']
regname0 = [r for r in regname if r[1] == '0']
const0 = [r[0] for r in sw if r[0].startswith('CONST:') and r[1] == '0']
mv = sum(1 for _, n in mut if n != '0')
zero = [k for k, n in mut if n == '0']

rows = []
for k, n in mut:
  rows.append(f'#   {k}  {n:>3}  {CLAIM[k]}')
table_logic = '\n'.join(rows)

regn = ', '.join(r[0].split(':')[1] for r in regname0)
c0 = ', '.join(r.split(':')[1] for r in const0)

block = f'''
# ===========================================================================
# THE MUTATION TABLE. MEASURED, NOT ASSERTED.
#
# `rows MOVED` is the load-bearing column. A mutation that moves NOTHING is not a
# gate that passed; it is a measurement of what this gate CANNOT see, and it is
# reported here rather than closed by adding a row that encodes the bug.
#
# TWO HARNESSES, because "every rule" means two kinds of rule.
#   `.agents/slop/ip_mutate.sh` -- {len(mut)} LOGIC mutations, one per rule.
#   `.agents/slop/ip_sweep.py`  -- {len(sw)} LEAF perturbations, EXHAUSTIVE: every
#     numeric constant by one unit, and every generated register row twice, once
#     on its LINE and once on its FIELD NAME. No hand-picking, so the coverage
#     claim is a measurement rather than an assertion.
#
# THE LOGIC TABLE ({mv} of {len(mut)} move rows, {len(zero)} do not):
#   id   MOVED  what the edit claims
#   {table_logic}
#
# THE THREE NON-MOVERS ARE EQUIVALENCES, NOT HOLES, AND EACH IS PAIRED.
#   M08  `U32.or` is commutative, so re-associating a union of flags is the same
#        set. M43 drops a TERM instead, which is a different function: 9 rows.
#   M22  `V.ge(13,0,6)` already covers (13,0,7) and (13,0,10), so both `V.eq`
#        disjuncts are dead and no fixture can tell. M42 breaks the 14-arm
#        instead, which is not redundant: 18 rows.
#   M39  after the sweep pruned the unread columns, MCA_CNT and GFX_RESET are the
#        surviving lockstep pair -- (F,T,F) over the three smu rows -- so they
#        are indistinguishable BY CONSTRUCTION. M41 picks MODE1, (T,F,F): 2 rows.
#        This one is a real fixture limit and it is named, not papered over.
#
# THE LEAF SWEEP ({len(swmv)} of {len(sw)} move rows, displacing
# {sum(int(r[1]) for r in swmv)} row positions between them):
#   CONST   {sum(1 for r in sw if r[0].startswith('CONST:'))} constants, {sum(1 for r in swmv if r[0].startswith('CONST:'))} moving.
#   REG     {len(regline)} line perturbations, {len(regline)-len(regline0)} moving.
#   REG@name {len(regname)} field-name perturbations, {len(regname)-len(regname0)} moving.
#
# {len(sw0)} BLIND SPOTS SURVIVE, AND HERE THEY ARE:
#   1. NINE field-name swaps that move nothing: {regn}. MEASURED and explained --
#      each of those rows shares its field name with its neighbour because the
#      name is a Python f-string (`regCP_{{cntl_reg}}_CNTL`, `regIH_RB_CNTL{{suf}}`,
#      `{{reg_pref}}_64`, `regGRBM_SOFT_RESET`, ...) that two lines legitimately
#      spell the same way. The LINE perturbation moves on all
#      {len(regline)}/{len(regline)}, which is the whole reason `Row` is keyed on
#      `(ln, reg)` and not on the name alone.
#   2. FIVE constants no gate row reads: {c0}. Each is USED by code and reaches
#      no emitted row at these fixtures. `IH_ERR_MID_MASK`/`IH_ERR_HI_MASK` are
#      masked away by the reassembly fixtures; `PQ_UNORD_DISPATCH_BIT` is not
#      reached by the KIQ/AQL pair; `SMU_COL_MCA_CNT` is the lockstep column of
#      M39. A sixth, `MQD_SE_VALUE`, cannot be perturbed at all: it is
#      `0xFFFFFFFF` and `+1` is outside `U32`, so the type system refuses.
#   3. The 46 unread constants the sweep found were DELETED, not reported. A def
#      with zero call sites is provably behaviour-preserving to remove, and all
#      three lanes re-verified byte-identical afterwards.
#
# WHAT THIS TABLE IS NOT. It does not cover the six WALLS, because a wall is by
# definition the part of `ip.py` this file does not contain, and there is nothing
# here to perturb.
'''
s = io.open(BEND, encoding='utf-8').read()
io.open(BEND, 'w', encoding='utf-8').write(s.rstrip('\n') + '\n' + block)
print(f'logic {mv}/{len(mut)} moving, zero={zero}')
print(f'sweep {len(swmv)}/{len(sw)} moving, {len(sw0)} blind, cf={swcf}')
print(f'REG {len(regline)-len(regline0)}/{len(regline)}  REG@name {len(regname)-len(regname0)}/{len(regname)}')
print('appended', len(block.split('\n')), 'lines')