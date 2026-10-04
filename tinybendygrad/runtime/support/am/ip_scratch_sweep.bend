# tinybendygrad/runtime/support/am/ip.bend -- port of tinygrad/runtime/support/am/ip.py
#
# THE amdgpu BRING-UP VOCABULARY. `support/am/ip.py` is not a device and it never
# opens one: it is the EIGHT CLASSES that take a card from reset to a KIQ ring
# (`AM_SOC`, `AM_GMC`, `AM_SMU`, `AM_GFX`, `AM_IH`, `AM_SDMA`, `AM_PSP`, plus the
# `AM_IP` base), and what survives the crossing to Bend is DATA:
#
#   * the REGISTER FIELD LISTS -- every `.write(...)` / `.update(...)` in the file
#     names its bitfields, and the ORDER of those names is the register write.
#     A wrong order is a silently wrong register, which is why this gate is
#     BY NAME and IN ORDER rather than by count.
#   * the STRUCT FIELD LISTS: `struct_psp_gfx_rb_frame` (:707) and the four
#     `union_psp_gfx_commands` members (:728-751) that `_ring_submit` fills.
#   * the SMU MESSAGE PROTOCOL (:264-273): the three-register C2PMSG triple, its
#     DEBUG arm, and the order the three writes land in.
#   * the KIQ `flush_tlb` PM4 PACKET (:108-110), 17 words, built in order.
#   * the PTE FLAG TABLES (:178-195), four generations, `|` of five constants
#     and a version-selected MTYPE field.
#   * the DOORBELL ARITHMETIC: `KIQ + xcc*0x20` (:354), `sDMA_ENGINE0 +
#     (pipe+queue*4)*0xA` (:592), `(ring_size//4).bit_length()-2` (:367), the
#     `(regf pair)-1) * 0xA) * 2` s2a entry ladder (:570-571).
#   * the VERSION LADDERS -- `ip_ver[am.GC_HWIP] >= (12,0,0)` and its forty-odd
#     siblings, each a three-part compare or a `[:2]` pair compare.
#   * every REFUSAL, as a TRUNCATION of the trace (:588 is the only `raise`).
#
# ---------------------------------------------------------------------------
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of one device call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER and the IDENTITY). There is no third
# kind. Every seam is a trace tag and nothing else, so ORDER and IDENTITY stay
# gateable even though none of them is made here. This is the `ops_webgpu.bend`
# lane and the reason this file is `ALL PROOFS CHECK` with no foreign effect:
# the seam is `Tr.emit`, not a `def ... -> IO(R)` over two `import "./x.c"`.
#
# ---------------------------------------------------------------------------
# EVERY CONSTANT AND EVERY STRUCT FIELD BELOW WAS READ OUT OF CPYTHON, never
# typed. The oracle is `.agents/slop/ip_oracle.py`; it prints the SAME rows by
# importing `tinygrad/runtime/support/am/ip.py` (which imports with NO device
# present), by walking the `am` autogen enums, by PROBING each
# `SOC15_*_FROM_IH_ENTRY` extractor one bit at a time to recover its mask and
# shift, and by reading the `register_fields` lists out of `autogen/am/am.py`.
# A `py=` expectation that is a def of the thing under test is not an
# expectation, so there are none.
#
# ===========================================================================
# STATUS: STAGE 4, FINAL. THE GATE PRINTS 447 ROWS; THE INTERPRETED AND THE
#   NATIVE LANE ARE IDENTICAL, AND THE CPYTHON ORACLE DISAGREES ON 0 OF 444 ROW
#   NAMES. Drivers: `.agents/slop/ip_check.sh` (three lanes),
#   `.agents/slop/ip_mutate.sh` (45 logic mutations),
#   `.agents/slop/ip_sweep.py` (415 leaf permutations).
#
# WHAT IS PORTED, section by section, with the CPython lines it covers:
#   the version substrate `V`: three-part and `[:2]` compares, every ladder
#     ..................................................................... :15-47
#   the KIQ `flush_tlb` PM4 packet, SEVENTEEN words, built in order       :99-113
#   the four-generation PTE flag tables and `is_pte_huge_page`          :177-195
#   the per-arch SMU message table, 3 rows x 20 columns, both ways       :199-215
#   the three-register C2PMSG protocol and its DEBUG arm                :264-273
#   the doorbell arithmetic: KIQ xcc, sDMA engine, ring size, s2a ladder
#     ..................................................................... :354 :366 :373 :570-572 :592
#   the `setup_ring` trace, in order, and its ONE raise                  :584-606
#   the register field lists: 115 rows, by NAME and IN ORDER, keyed on
#     (Python line, name) because sixteen of the names are f-strings that
#     two lines legitimately share                        every `.write`/`.update`
#   the IH entry decode: eleven extractors, bit positions, ACA           :502-513
#   the PSP ring frame and the four union command field lists            :707-751
#
# WHAT IS NOT PORTED -- the six walls, each with its own `TODO(p3)` markers
# in the WALLS section below, and each naming the lines it covers:
#   WALL 1  register ACCESS and `AMDReg.encode`'s bit POSITIONS           :367 :411
#   WALL 2  `hasattr` / `getattr` NAME probing
#     ..................................................................... :17 :21 :22 :25 :56 :58 :103 :260 :359 :389 :477 :506 :646
#   WALL 3  `functools.cache` memoisation                                :177 :230
#   WALL 4  firmware BLOBS, `from_buffer`, `int(round(watts))`           :228 :250
#   WALL 5  thirteen `wait_cond` polls and six `time.sleep`s             :113 :117 :121 :219 :222 :271 :284 :346 :393 :417 :450 :584 :640 :656 :692 :695 :702 :704 :717
#   WALL 6  the memory manager: `mm.palloc`, `mm.map_range`, `paddrs`    :278 :331
#
# THE CROSS-FILE CONTRACT. WALL 1 is the SEAM'S, and `ops_amd.bend`'s WALL 2
# (its lines 173-178) says the same thing about `regCOMPUTE_*`: the port carries
# their USE -- which register, with which field names, in which order -- and not
# their OFFSETS, which belong to `autogen/am/regs/*`, PER ARCH. This file and that
# one AGREE and neither contradicts the other. They share NO register table and NO
# constant: MEASURED, `ops_amd.bend` cites `am/ip` nowhere. Their one overlapping
# FUNCTION is `setup_ring`, which `ops_amd.bend` lists as a wall from
# `ops_amd.py:772`'s point of view (:181) and this file ports as a seven-call
# trace. So the seam is named twice and built once, which is the intent.

import Base
import ../../../helpers.bend as H

# ===========================================================================
# THE TYPES.
# ===========================================================================

# ONE device call and the number that identifies it. `arg` is the ordinal of the
# REGISTER whose bitfield list is being written, or the message id, or the packet
# word -- whatever the trace is about. There is deliberately no field for the
# call's ARGUMENTS: those are what the defs around this record build, and the
# gate reads them from the record a def RETURNS, not from the trace.
type Call is Data:
  Call{k: U32, arg: U32}

# the machine state of the FFI seam. Bend has no pointer, so `next` mints the
# handle ids and what the gate checks is that they are consumed in the right
# ORDER and the right NUMBER of times.
#
# THE RAISE IS HERE. `Tr.emit` records NOTHING once a refusal has fired, and
# `Tr.refuse` is IDEMPOTENT after the first. `nth` counts refusals so far and
# `at` is the refusal ordinal the seam should fail on (0 = never), so one fixture
# numbering reaches EVERY refusal site in turn; the failing refusal is NOT
# recorded, because in Python the `raise` replaces it.
type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, refused: Bool, nth: U32, at: U32}

# ONE register access: the Python LINE it came from, the register's NAME as the
# f-string at that line spells it, and the bitfield NAMES in source order. The
# line is a field so a gate row names its own provenance: a wrong ORDER here is a
# silently wrong register write and the line says which one to check.
type Row is Data:
  Row{ln: U32, reg: String, fs: List<&2, String>}

def Row.ln(r: Row) -> U32:
  match r:
    case Row{ln, reg, fs}: ln

def Row.reg(r: Row) -> String:
  match r:
    case Row{ln, reg, fs}: reg

def Row.fs(r: Row) -> List<&2, String>:
  match r:
    case Row{ln, reg, fs}: fs

def Row.of(ln: U32, reg: String, fs: List<&2, String>) -> Row: Row{ln, reg, fs}

# ===========================================================================
# THE TRACE. `Tr.emit` is the seam: every register write, every ioctl and every
# ring store in this file goes through it, so the trace is the ordered list the
# seam will perform.
# ===========================================================================

def Tr.of() -> Tr: Tr{Nil{}, 0, False{}, 0, 0}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, refused, nth, at}: calls

def Tr.next(t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused, nth, at}: next

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, refused, nth, at}: refused

# the refusal ordinal the seam should fail on, 0 = never. `nth` is NOT reset by
# `Tr.reset`, so one fixture numbering covers a whole device lifetime.
def Tr.fail_at(t: Tr, n: U32) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr{calls, next, refused, nth, n}

# an EMPTY trace that keeps `at` and `nth`, so a gate can read one step without
# the init in front of it and still number its refusals from one.
def Tr.reset(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr{Nil{}, 0, False{}, nth, at}

# the id the NEXT emit mints, i.e. what the seam's call returns. Read BEFORE the
# emit, so ids are monotone in issue order.
def Tr.here(t: Tr) -> U32: Tr.next(t)

# `Bool.pick` evaluates BOTH arms, so the recorded call is a value built here
# and the guard is a parameter. This is the port of every `raise` in the file.
def Tr.emit.go(+refused: Bool, k: U32, arg: U32, +calls: List<&2, Call>,
               +next: U32, nth: U32, at: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, arg}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)), refused, nth, at}

def Tr.emit(k: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}:
      Tr.emit.go(refused, k, arg, calls, next, nth, at)

# THE RAISE. `Tr.refuse` fires at refusal ordinal `at` and is idempotent after
# that, so a fixture numbering reaches each site in turn and no site below needs
# a guard of its own.
def Tr.refuse.go(+refused: Bool, +nth: U32, +at: U32) -> Tr:
  Tr{Nil{}, 0, Bool.or(refused, U32.is_eq(U32.add(nth, 1), at)),
     Bool.pick(U32, refused, nth, U32.add(nth, 1)), at}

def Tr.refuse(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr.refuse.go(refused, nth, at)

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, arg}: k

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, arg}: arg

# ===========================================================================
# READING THE TRACE. `Tr.args` is the args of every entry with tag `k`, in
# order; `Tr.count` is how many there are; `Tr.seen` is how many calls there are
# at all, which is the TRUNCATION length a refusal shows up as.
# ===========================================================================

def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, aa} <> t: Tr.count.go(m, k, t,
          U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

# a LEAF, because `Bool.pick` evaluates both arms and a recursive call inside one
# of them would branch the walk twice over.
def Tr.args.put(+c: Call, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(Call.k(c), k),
    List.append(&2, U32, acc, [Call.arg(c)]), acc)

def Tr.args.go(n: Nat, +k: U32, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: Tr.args.go(m, k, t, Tr.args.put(Call{kk, aa}, k, acc))

def Tr.args(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.args.go(List.length(&2, Call, cs), k, cs, Nil{})

def Tr.seen(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

# does the trace CONTAIN this (tag, arg) sequence, in order? `at` is how much of
# the pattern is matched so far, read out of the pattern BY INDEX rather than
# carried as a second list. THE FUEL IS THE TRACE LENGTH and the answer is
# `at == patlen`: with the fuel set to the PATTERN length, `case 0n:` fires
# after `patlen` trace entries and returns True without ever looking at `at`, so
# a reversed pattern matches. `amp_has_fwd` / `amp_has_rev` are the rows that
# catch it, and they are duplicated from `ops_webgpu.bend` and `ops_amd.bend`
# because this substrate is a copy and a copy needs its own rows.
def Tr.has.step.same2(k1: U32, k2: U32, a1: U32, a2: U32) -> Bool:
  Bool.and(U32.is_eq(k1, k2), U32.is_eq(a1, a2))

def Tr.has.step.hit(same: Bool, at: Nat) -> Nat:
  match same:
    case True{}: Nat.add(at, 1n)
    case False{}: at

def Tr.has.step(m: Maybe<&2, Call>, +c: Call, at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+want}:
      Tr.has.step.hit(Tr.has.step.same2(Call.k(c), Call.k(want), Call.arg(c), Call.arg(want)), at)

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>, +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case Call{kk, aa} <> t:
          Tr.has.go(m, patlen, t, pat, Tr.has.step(List.get(&2, Call, pat, at), Call{kk, aa}, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

def Tr.seq(t: Tr, pat: List<&2, Call>) -> Bool: Tr.has(Tr.calls(t), pat)
# ===========================================================================
# THE CONSTANTS. Every value and its Python line.
# ===========================================================================

# am.py `AMDGPU_PTE_*` / `AMDGPU_PDE_*`, read out of the autogen enums.
def PTE_VALID() -> U32: 1
def PTE_SYSTEM() -> U32: 2
def PTE_SNOOPED() -> U32: 4
def PTE_EXECUTABLE() -> U32: 16
def PTE_READABLE() -> U32: 32
def PTE_WRITEABLE() -> U32: 64
# `am.AMDGPU_PTE_FRAG(x)` is MEASURED to be `(x & 0x1f) << 7`. The MASK is
# load-bearing: `PTE_FRAG(0x20)` is 0 and an unmasked `32 << 7` would not be.
def PTE_FRAG_SHIFT() -> U32: 7
def PTE_FRAG_MASK() -> U32: 31
# `am.AMDGPU_PDE_BFS(a)` is MEASURED to be `a << 59`: `PDE_BFS(1) == 2**59` and
# `PDE_BFS(0x9) == 0x4800000000000000`. There is NO mask.
def PDE_BFS_SHIFT() -> U32: 59
# the three `AMDGPU_VM_PT*` page-table levels, :183/:186/:189-191.
def VM_PDB1() -> U32: 1
def VM_PDB0() -> U32: 2
def VM_PTB() -> U32: 3
# THE THREE MTYPE FIELDS, and THEY ARE AT THREE DIFFERENT BITS. MEASURED out of
# the `AMDGPU_PTE_MTYPE_*_MASK` values: GFX12 0xc0000000000000, NV10
# 0x7000000000000, VG10 0x600000000000000 -- so the mtype value lands at bit 50,
# 48 and 53 respectively, and a port that treats them as ONE shift computes a
# PTE that is wrong in 2 of the 3 generations. THE ORACLE CAUGHT ALL THREE:
# the first version of this file had 50 / 48 / 53, read off the MASK's TOP bit
# instead of its LOWEST, and `amp_pte_mtype_12_uc` printed 786432 where
# CPython's `AMDGPU_PTE_MTYPE_GFX12(0, 3)` is 12582912. `MTYPE_UC` is the value ip.py
# passes when `uncached`, read out of `autogen/am/soc_{9,11,12}.MTYPE_UC`.
def MTYPE_SHIFT_GFX12() -> U32: 54
def MTYPE_SHIFT_NV10() -> U32: 48
def MTYPE_SHIFT_VG10() -> U32: 57
# :156, `self.adev.soc.module.MTYPE_UC` in `MC_VM_MX_L1_TLB_CNTL.mtype`.
# the three 64-bit-only flags. Each is 1<<k, so they are SHIFTS and the port
# keeps the I64 so no constant is silently truncated to 32.
def PDE_PTE_SHIFT() -> U32: 54
def PTE_TF_SHIFT() -> U32: 56

# am.py, :354/:592 and :373/:367.
def DOORBELL_KIQ() -> U32: 0
def DOORBELL_MEC_RING0() -> U32: 3
def DOORBELL_SDMA_ENGINE0() -> U32: 256
# :354, `kiq_xcc*0x20` and :592 `(pipe+queue*4)*0xA`.
def KIQ_XCC_STRIDE() -> U32: 32
def SDMA_ENGINE_STRIDE() -> U32: 10
# :571, `range_offset_entry` is `(base + (entry-1)*0xA) * 2`; :571/601/366/354
# all multiply a doorbell by two.
# :570, `range_size_entry: 20`.
def DOORBELL_RANGE_SIZE() -> U32: 20
# :571, `(base + (entry-1)*0xA) * 2` -- the register holds a DWORD index, so the
# scale is TWO and not one. `amp_db_off_1` is 512, which is `AMDGPU_NAVI10_
# DOORBELL_sDMA_ENGINE0 * 2`, and a port that omits the scale is off by half a
# ring.
def DOORBELL_OFFSET_SCALE() -> U32: 2

# :458, `self.ring_size = 256 << 10`.
def IH_RING_SIZE() -> U32: 262144
# :467, `rb_size=((self.ring_size//4)-1).bit_length()`.
def IH_RB_SIZE() -> U32: 16
# :502-503, an IH entry is EIGHT dwords and the ring is walked `rptr += 8`.
def IH_ENTRY_WORDS() -> U32: 8
# :508/503, the wrap modulus is the ring in dwords.
def IH_WRAP() -> U32: 65536

# :611, `reg_pref` is `regMP0_SMN_C2PMSG` below MP0 14 and `regMPASP_SMN_C2PMSG`
# at or above it.
def PREF_MP0() -> U32: 0
def PREF_MPASP() -> U32: 1
# :624, `self.ring_size = 0x10000`; :715 advances the wptr by
# `ctypes.sizeof(struct_psp_gfx_rb_frame) // 4` and MEASURED `sizeof` is 64.
def PSP_RING_SIZE() -> U32: 65536
def PSP_FRAME_DWORDS() -> U32: 16
# :689/699, the two control words `_ring_create` writes.
def GFX_CTRL_CMD_ID_DESTROY_RINGS() -> U32: 196608
def PSP_RING_TYPE_KM_SHIFTED() -> U32: 131072

# am.py PSP, :632-636 and :643/:652.
def PSP_FW_SOS() -> U32: 1
def PSP_FW_SYS_DRV() -> U32: 2
def PSP_FW_KDB() -> U32: 3
def PSP_FW_SPL() -> U32: 5
def PSP_FW_SOC_DRV() -> U32: 7
def PSP_FW_INTF_DRV() -> U32: 8
def PSP_FW_DBG_DRV() -> U32: 9
def PSP_FW_RAS_DRV() -> U32: 10
def BL_LOAD_SYSDRV() -> U32: 65536
def BL_LOAD_SOSDRV() -> U32: 131072
def BL_LOAD_KEY_DATABASE() -> U32: 524288
def BL_LOAD_SOS_SPL_TABLE() -> U32: 268435456
def BL_LOAD_SOCDRV() -> U32: 720897
def BL_LOAD_DBGDRV() -> U32: 786432
def BL_LOAD_INTFDRV() -> U32: 851968
def BL_LOAD_RASDRV() -> U32: 917504

# :699, `PSP_RING_TYPE__KM << 16` and the ring-create wait masks.
def PSP_SOS_READY_BIT() -> U32: 2147483648
def PSP_RING_CREATED_MASK() -> U32: 2147549183
# :672-673, `msg1_addr >> 20`.
def PSP_MSG1_ADDR_SHIFT() -> U32: 20
# :622, `PSP_FENCE_BUFFER_SIZE`; :738 the TMR pair is written as a data64.

# :45, the two `regS2A` spellings.
# :46-47, the FIVE s2a bitfields, in order.
# :572, `size=4` for the sDMA entry ladder.

# :31, the two `NBIO_HWIP` versions that route through `indirect_wreg_pcie`.
# :183, `1 << vmid` and :109-110 the wait's `1 << vmid`.
# :111, `ring[(ptrs[1] + i) % 0x400]`.
def KIQ_RING_MASK() -> U32: 1023
# :107, the KIQ window is `0x3000*xcc` and the pointer block is at `+0x1000`.
def KIQ_WIN() -> U32: 12288
def KIQ_PTR_OFF() -> U32: 4096
# :108, `doorbell64[am.AMDGPU_DOORBELL_KIQ + xcc*0x20]`.
# :110, `data64_le(gfx.kiq_va + base + 0x1010)`. `0x1010` is `KIQ_PTR_OFF` (0x1000)
# plus the third of the THREE Q-words `ptrs` views at `base + 0x1000`: rptr at +0,
# wptr at +8, fence at +0x10. The packet's WR_CONFIRM writes the FENCE slot.
def KIQ_FENCE_OFF() -> U32: 4112

# :468, `wptr_overflow_clear` / `rb_full_drain_enable`; :484 `enable_intr`.

# :517/:121, the TLB-invalidate wait reads `& 0x1` and `& (1 << vmid)`.
# :101, `clear_protection_fault_status_addr=0`.

# ===========================================================================
# `V` -- THE THREE-PART VERSION, which is `ip_ver[am.<X>_HWIP]` and the
# arithmetic behind all forty-odd comparisons in the file. `V.cmp` is a lexical
# three-part compare and `V.eq2` / `V.ne2` are the `[:2]` pair form at
# :30/:300/:313/:591/:604. ALL THREE ARMS matter and the gate has a row on each
# boundary of each, because a version ladder that is off by one is a register
# write to the wrong IP.
# ===========================================================================

def V.cmp.maj(c: Cmp, am: U32, bm: U32) -> Cmp:
  match c:
    case GT{}: GT{}
    case EQ{}: U32.cmp(am, bm)
    case LT{}: LT{}

def V.cmp.min(c: Cmp, am: U32, an: U32, bm: U32, bn: U32) -> Cmp:
  match c:
    case GT{}: V.cmp.maj(GT{}, am, bm)
    case EQ{}: V.cmp.maj(U32.cmp(an, bn), am, bm)
    case LT{}: LT{}

def V.cmp.pat(c: Cmp, ap: U32, bp: U32) -> Cmp:
  match c:
    case GT{}: GT{}
    case EQ{}: U32.cmp(ap, bp)
    case LT{}: LT{}

# `+` on the four parts: the major compare is passed to `V.cmp.maj` AND the whole
# pair is handed to `V.cmp.min`, so each is read twice. `+` on a `U32` is free.
def V.cmp(+am: U32, +an: U32, ap: U32, +bm: U32, +bn: U32, bp: U32) -> Cmp:
  V.cmp.pat(V.cmp.min(V.cmp.maj(EQ{}, am, bm), am, an, bm, bn), ap, bp)

def V.ge(+am: U32, +an: U32, +ap: U32, +bm: U32, +bn: U32, +bp: U32) -> Bool:
  Cmp.is_ge(V.cmp(am, an, ap, bm, bn, bp))

def V.lt(+am: U32, +an: U32, +ap: U32, +bm: U32, +bn: U32, +bp: U32) -> Bool:
  Cmp.is_lt(V.cmp(am, an, ap, bm, bn, bp))

def V.eq(+am: U32, +an: U32, +ap: U32, +bm: U32, +bn: U32, +bp: U32) -> Bool:
  Cmp.is_eq(V.cmp(am, an, ap, bm, bn, bp))

# :30/:300/:313/:604, `ip_ver[am.<X>_HWIP][:2] == (7,9)` -- the PATCH component
# is not compared at all, so (7,9,0) and (7,9,1) are the SAME version here and a
# port that writes `V.eq` instead gets (7,9,0) != (7,9,1). `amp_v_eq2_*` is the
# row and `amp_v_ne2_*` is its negation, so the two cannot be the same def.
def V.eq2(+am: U32, +an: U32, +bm: U32, +bn: U32) -> Bool:
  Cmp.is_eq(V.cmp.maj(V.cmp.min(EQ{}, am, an, bm, bn), am, bm))

def V.ne2(+am: U32, +an: U32, +bm: U32, +bn: U32) -> Bool:
  Bool.not(V.eq2(am, an, bm, bn))

# ===========================================================================
# THE PER-ARCH SMU MESSAGE TABLE, `import_module("smu", ip_ver[MP1_HWIP])`.
#
# `_ip_module("smu", am.MP1_HWIP)` at :199 does NOT give a fixed set of numbers:
# it picks the newest `autogen/am/smu_<maj>_<min>_<pat>` at or below the version,
# with TWO hard-coded overrides -- (13,0,7) and (13,0,10) map to (13,0,0) -- and
# then reads `PPSMC_MSG_*` and `PPCLK_*` OFF THE MODULE. So every message id in
# `AM_SMU` is a per-arch cell, and `PPSMC_MSG_GfxDriverReset` is not merely
# different per arch, it is ABSENT on `smu_13_0_0` and `smu_14_0_2`, which is why
# :215 is inside a membership test for exactly those versions.
#
# The table is BOTH DIRECTIONS: `smu.names` is the column, `smu.row*` are the
# three rows, `smu.get` is name-index to value and `smu.name_of` is the reverse.
# `0` is the "the module has no such name" sentinel and it is SAFE: MEASURED, no
# `PPSMC_MSG_*` in any of the four modules is 0 (the minimum is 1). `smu.has_mca`
# is the `hasattr` at :260 turned into a named predicate, and it decides whether
# `_aca_read_banks` returns `[]` or a list of banks.
# ===========================================================================

def SMU_COL_DRAM_HI() -> U32: 0
def SMU_COL_GFX_RESET() -> U32: 3
def SMU_COL_MODE1() -> U32: 4
def SMU_COL_MCA_CNT() -> U32: 12

# the COLUMN, in `smu.row*` order. A gate row prints it so a table can never be
# read without knowing which name each cell is.
def smu.names() -> List<&2, String>:
  ["PPSMC_MSG_SetDriverDramAddrHigh", "PPSMC_MSG_SetDriverDramAddrLow",
   "PPSMC_MSG_EnableAllSmuFeatures", "PPSMC_MSG_GfxDriverReset",
   "PPSMC_MSG_Mode1Reset", "PPSMC_MSG_GetSmuVersion", "PPSMC_MSG_GetDpmFreqByIndex",
   "PPSMC_MSG_SetSoftMinByFreq", "PPSMC_MSG_SetSoftMaxByFreq",
   "PPSMC_MSG_SetPptLimit", "PPSMC_MSG_McaBankDumpDW", "PPSMC_MSG_McaBankCeDumpDW",
   "PPSMC_MSG_QueryValidMcaCount", "PPSMC_MSG_QueryValidMcaCeCount",
   "PPSMC_MSG_GetMetricsTable", "PPSMC_MSG_TransferTableSmu2Dram",
   "PPCLK_UCLK", "PPCLK_FCLK", "PPCLK_SOCCLK", "PPCLK_GFXCLK"]

# THE THREE ROWS, in `smu.arch` order. `smu_13_0_6` and `smu_13_0_12` are two
# MODULES with identical values for every column, so they share row 1, and
# `amp_smu_arch_13_0_6` / `amp_smu_arch_13_0_12` are the rows that say so.
def smu.row0() -> List<&2, U32>:
  [14, 15, 6, 0, 47, 2, 31, 25, 26, 50, 0, 0, 0, 0, 0, 18, 2, 3, 1, 0]
def smu.row1() -> List<&2, U32>:
  [13, 14, 5, 3, 0, 2, 23, 19, 20, 24, 55, 59, 54, 58, 9, 0, 3, 4, 2, 0]
def smu.row2() -> List<&2, U32>:
  [14, 15, 6, 0, 0, 2, 31, 25, 26, 50, 0, 0, 0, 0, 0, 18, 2, 3, 1, 0]

def smu.row(+arch: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(arch, 2), smu.row2(),
    Bool.pick(List<&2, U32>, U32.is_eq(arch, 1), smu.row1(), smu.row0()))

# `import_module`'s ladder: the newest module with a matching MAJOR at or below
# the target, with the two (13,0,7)/(13,0,10) overrides folded in. Row 2 is the
# 14-series, row 1 is the 13.0.6/13.0.12 pair and row 0 is everything else.
def smu.arch(+mp1_0: U32, +mp1_1: U32, +mp1_2: U32) -> U32:
  Bool.pick(U32, U32.is_eq(mp1_0, 14), 2,
    Bool.pick(U32, Bool.or(V.ge(mp1_0, mp1_1, mp1_2, 13, 0, 6),
      Bool.or(V.eq(mp1_0, mp1_1, mp1_2, 13, 0, 7), V.eq(mp1_0, mp1_1, mp1_2, 13, 0, 10))), 1, 0))

# `import_module` RAISES `ImportError` for a version with no module at or below
# it -- MEASURED, `import_module("smu", (14,0,0))` raises, because the only 14
# module is `smu_14_0_2`. `smu.arch` has no arm for that and this is the row.
def smu.arch.missing(+mp1_0: U32, +mp1_1: U32, +mp1_2: U32) -> Bool:
  Bool.and(U32.is_eq(mp1_0, 14), V.lt(mp1_0, mp1_1, mp1_2, 14, 0, 2))

def smu.get(+arch: U32, col: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, smu.row(arch), U32.to_nat(col)), 0)

def smu.has(+arch: U32, col: U32) -> Bool:
  Bool.not(U32.is_zero(smu.get(arch, col)))

def smu.has_mca(arch: U32) -> Bool: smu.has(arch, SMU_COL_MCA_CNT())

# column -> name, the other direction of the same table.
def smu.name_of(col: U32) -> String:
  Maybe.default(&2, String, List.get(&2, String, smu.names(), U32.to_nat(col)), "?")

# ===========================================================================
# THE SMU MESSAGE PROTOCOL, :264-273. THE THREE-REGISTER TRIPLE.
#
# `_smu_cmn_send_msg` writes THREE registers in this order and they are three
# different registers depending on ONE flag:
#
#   :265  resp reg  C2PMSG_90 (normal) / C2PMSG_54 (debug)  <- 0
#   :266  param reg C2PMSG_82 (normal) / C2PMSG_53 (debug)  <- param
#   :267  msg reg   C2PMSG_66 (normal) / C2PMSG_75 (debug)  <- msg
#
# so the ARM is the register choice and the ORDER is the protocol. Both are gate
# rows: `amp_smu_order_*` is the trace and `amp_smu_regs_*` is the (resp, param,
# msg) triple read by name. :271's wait reads the SAME resp register and :273
# returns the param register, so the arm at :273 is the param register too.
# ===========================================================================

# the six C2PMSG register names, in protocol order for each arm.
def amp_smu_regs(debug: U32) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_eq(debug, 1),
    ["mmMP1_SMN_C2PMSG_54", "mmMP1_SMN_C2PMSG_53", "mmMP1_SMN_C2PMSG_75"],
    ["mmMP1_SMN_C2PMSG_90", "mmMP1_SMN_C2PMSG_82", "mmMP1_SMN_C2PMSG_66"])

# `k` is the position in `amp_smu_regs`, which is how the trace names the register
# without carrying a String. `Bool.pick` evaluates BOTH arms, so the three
# writes are nested rather than sequenced.
def amp_smu_res(k: U32, arg: U32, t: Tr) -> Tr: Tr.emit(k, arg, t)

# `amp_smu_msgs` is the trace and its LENGTH is pinned, because a dropped write
# shortens the trace and a reordered one changes the values.
def amp_smu_msgs(msg: U32, param: U32, debug: U32, t: Tr) -> Tr:
  amp_smu_res(2, msg, amp_smu_res(1, param, amp_smu_res(0, 0, t)))

# --- the SMU arithmetic, :203-257 and :231-247 ------------------------------
# :203-204, `hi32`/`lo32` of `paddr2mc(driver_table_paddr)` split across two
# messages, HIGH FIRST. The order is the claim.
# `hi32(x)`/`lo32(x)` are 64-bit helpers (helpers.py) and Bend 2.0.34 has no
# `Word(64n)`, so the port keeps the pair as a `U32` and the HIGH half is
# `paddr_mc >> 16`. That is the same thing ONLY for an address below 2**32, which
# is what the fixture is and what `amp_smu_smu_hi` says out loud.
def amp_smu_smu_hi(paddr_mc: U32) -> U32: U32.shrn(paddr_mc, 16n)

def amp_smu_smu(+paddr_mc: U32) -> List<&2, U32>: [amp_smu_smu_hi(paddr_mc), paddr_mc]


# :222, `wait_cond(..., value=0x1002, timeout_ms=2000)` after a mode1 reset.
# :208, `is_smu_alive` uses `timeout=100` and compares the resp register to 0.
# :232-233, `(clck<<16)|i` and the `(clck<<16)|0xff` that asks for the COUNT,
# then `&0x7fffffff` on the answer.
def CLK_SHIFT() -> U32: 16

def amp_smu_dpm(clck: U32, i: U32) -> U32:
  U32.or(U32.shln(clck, U32.to_nat(CLK_SHIFT())), i)

# :246-247, the soft-min and soft-max words. `min` has NO `|0xffff`; max does on
# the >=gfx10 arm at :242. Both forms are rows because the difference is real.
def amp_smu_softmin(clck: U32, v: U32) -> U32:
  U32.or(U32.shln(clck, U32.to_nat(CLK_SHIFT())), v)

def amp_smu_softmax(clck: U32, v: U32) -> U32:
  U32.or(U32.shln(clck, U32.to_nat(CLK_SHIFT())), v)

# :241-242, `level is None` sets the soft MIN to `clck << 16` and the soft MAX to
# `clck << 16 | 0xffff`, so the "unlimited" value is the OR of the two.
def SMU_CLOCK_UNLIMITED() -> U32: 65535

# :254-257, `_aca_read_reg`. The argument is
# `(bank_idx << 16) | (reg_idx*8 + hi*4)`, and it reads the SAME argument twice --
# once with `+4`, once without -- which is why the arm is a `hi: Bool` and not a
# constant.
def amp_smu_aca_arg(bank_idx: U32, reg_idx: U32, hi: U32) -> U32:
  U32.or(U32.shln(bank_idx, U32.to_nat(CLK_SHIFT())),
         U32.add(U32.mul(reg_idx, 8), U32.mul(hi, 4)))

# :262, sixteen registers per bank.

# :249-251, `ppt_limit = max(int(round(watts)), 1)`. `int(round(watts))` is a
# FLOAT round and `base.bend`'s F32 has no round and no to_bits, so the FLOOR is
# WALL 4. What is ported is the `max(..., 1)` clamp, which is a U32 compare.
def PPT_LIMIT_MIN() -> U32: 1

def amp_smu_ppt(watts_i: U32) -> U32:
  U32.max(watts_i, PPT_LIMIT_MIN())

# :236-237, `clks = (PPCLK_UCLK, PPCLK_FCLK, PPCLK_SOCCLK)` and GFXCLK is appended
# only when MP0 is NOT one of (13,0,6) (13,0,12) (13,0,15).
# `amp_smu_13_set` is that membership test, named because :215, :226 and :237
# ALL ask it.
def amp_smu_13_set(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> Bool:
  Bool.or(V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 6), Bool.or(
    V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 12), V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 15)))

# the COUNT is what changes, and it is 4 or 3.
def amp_smu_clks(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> U32:
  U32.sub(4, Bool.to_u32(amp_smu_13_set(mp0_0, mp0_1, mp0_2)))

# :213-216, `mode1_reset`'s message ladder. The first arm is a version SET (four
# members, `>= (14,0,0)` OR three exact versions) and the walrus binds
# `__DEBUGSMC_MSG_Mode1Reset := 2`, so the message is the LITERAL 2 and not the
# module's symbol. The other two are read out of the per-arch table, and both are
# ABSENT (`0`) on every arch that does not reach their arm -- that invariant is a
# row, not an accident.
def DEBUGSMC_MSG_Mode1Reset() -> U32: 2

def amp_smu_mode1.arm14(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> Bool:
  Bool.or(V.ge(mp0_0, mp0_1, mp0_2, 14, 0, 0), Bool.or(
    V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 0), Bool.or(
      V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 7), V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 10))))

def amp_smu_mode1(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> U32:
  Bool.pick(U32, amp_smu_mode1.arm14(mp0_0, mp0_1, mp0_2), DEBUGSMC_MSG_Mode1Reset(),
    Bool.pick(U32, amp_smu_13_set(mp0_0, mp0_1, mp0_2),
      smu.get(smu.arch(mp0_0, mp0_1, mp0_2), SMU_COL_GFX_RESET()),
      smu.get(smu.arch(mp0_0, mp0_1, mp0_2), SMU_COL_MODE1())))

# ===========================================================================
# THE PTE FLAG TABLES, :177-195. FOUR GENERATIONS OF THE SAME FIVE-TERM OR.
#
#   :179  extra |= SYSTEM*system | SNOOPED*snooped | VALID*valid | FRAG(frag)
#   :180  if not is_table: extra |= WRITEABLE | READABLE | EXECUTABLE
#   :181  gfx12+  MTYPE_GFX12(0, MTYPE_UC if uncached else 0)
#   :183  gfx12+  PDE_PTE_GFX12 if not is_table and pte_lv != PTB else
#                PTE_IS_PTE if not is_table else 0
#   :184  gfx10+  MTYPE_NV10(...) then PDE_PTE on the same condition
#   :187  else    MTYPE_VG10(...), then BFS(0x9) for PDB1 tables, TF for PDB0
#                tables, PDE_PTE for non-table PTB/PDB0 pages
#
# The result is 64-BIT: `AMDGPU_PDE_PTE_GFX12` is 2**63 and `AMDGPU_PDE_PTE` is
# 2**54, so a `U32` port silently drops the whole flag. `pte.of` answers an
# `H.I64` and the gate prints hi AND lo on every fixture, which is what stops a
# future edit from deciding one U32 is enough.
# ===========================================================================

# `1 << n` on the high/low halves. `helpers.bend` has `i64_add` and `i64_sub`
# but no shift, and neither CARRIES nor BORROWS (a measured repair, reported in
# the constraints), so the shift is two `U32` halves and needs neither. `n` is
# below 32 at all four call sites, which is why there is no 64-bit shift word.
# `Nat.sub` TRUNCATES and `Nat.sub(32n, 50n)` is 18n, so the shift is a `U32` and
# the halves are taken with `U32.sub`, which saturates. MEASURED the hard way:
# `Nat.sub` in the guard made `pte.mtype(12, 3)` print `3 << 16` instead of
# `3 << 50`, and `amp_pte_mtype_12_uc` is the row that caught it.
def i64_shl32(+hi: U32, +lo: U32, +n: U32) -> H.I64:
  Bool.pick(H.I64, U32.is_lt(n, 32),
    H.i64_of_hi_lo(U32.or(U32.shln(hi, U32.to_nat(n)),
      U32.shrn(lo, U32.to_nat(U32.sub(32, n)))), U32.shln(lo, U32.to_nat(n))),
    H.i64_of_hi_lo(U32.shln(lo, U32.to_nat(U32.sub(n, 32))), 0))

def i64_or(+a: H.I64, +b: H.I64) -> H.I64:
  H.i64_of_hi_lo(U32.or(H.hi32(a), H.hi32(b)), U32.or(H.lo32(a), H.lo32(b)))

def i64_and(+a: H.I64, +b: H.I64) -> H.I64:
  H.i64_of_hi_lo(U32.and(H.hi32(a), H.hi32(b)), U32.and(H.lo32(a), H.lo32(b)))

def i64_lit(hi: U32, lo: U32) -> H.I64: H.i64_of_hi_lo(hi, lo)

# `am.AMDGPU_PTE_FRAG(x)` is MEASURED to be `(x & 0x1f) << 7`. The MASK is
# load-bearing: `PTE_FRAG(0x20)` is 0 and an unmasked `32 << 7` would not be.
def pte.frag(frag: U32) -> H.I64:
  i64_shl32(0, U32.and(frag, PTE_FRAG_MASK()), PTE_FRAG_SHIFT())

# `am.AMDGPU_PDE_BFS(a)` is MEASURED to be `a << 59`: `PDE_BFS(1) == 2**59` and
# `PDE_BFS(0x9) == 0x4800000000000000`. There is NO mask.
def pte.bfs(a: U32) -> H.I64: i64_shl32(0, a, PDE_BFS_SHIFT())

# the MTYPE field is at a DIFFERENT bit in each of the three generations, so it
# is a three-way pick and NOT one constant. `amp_pte_mtype_*` is one row per
# generation and `amp_pte_mtype_same` is the row that says they are NOT the same.
def pte.mtype(+gc0: U32, +mtype: U32) -> H.I64:
  Bool.pick(H.I64, V.ge(gc0, 0, 0, 12, 0, 0),
    i64_shl32(0, mtype, MTYPE_SHIFT_GFX12()),
    Bool.pick(H.I64, V.ge(gc0, 0, 0, 10, 0, 0),
      i64_shl32(0, mtype, MTYPE_SHIFT_NV10()),
      i64_shl32(0, mtype, MTYPE_SHIFT_VG10())))

# :179, the first three terms. `system`/`snooped`/`valid` are MULTIPLIERS and
# FRAG is a shift, so the whole first term is four independent pieces and getting
# the SHIFTS wrong is a silently wrong PTE.
def pte.base.go(frag: U32, system: U32, snooped: U32, valid: U32) -> U32:
  U32.add(U32.mul(PTE_SYSTEM(), system), U32.add(U32.mul(PTE_SNOOPED(), snooped),
    U32.add(U32.mul(PTE_VALID(), valid), H.lo32(pte.frag(frag)))))

def pte.base(frag: U32, system: U32, snooped: U32, valid: U32) -> H.I64:
  i64_lit(0, pte.base.go(frag, system, snooped, valid))

# :180, `WRITEABLE | READABLE | EXECUTABLE`, taken as the OR of the three
# constants rather than as the literal 112 so a renamed constant is caught.
def pte.rwe() -> H.I64:
  i64_lit(0, U32.or(PTE_WRITEABLE(), U32.or(PTE_READABLE(), PTE_EXECUTABLE())))

# :183 and :186, the NON-TABLE page flag and the table-page flag. They are
# DIFFERENT BITS in DIFFERENT GENERATIONS -- 2**63 for gfx12, 2**54 for gfx10+ --
# and the gfx12 pair (`PDE_PTE_GFX12` and `PTE_IS_PTE`) is the SAME bit reached
# by a different test. So the test and the bit are separate defs and the gate has
# a row for each generation.
def pte.pde_gfx12() -> H.I64: i64_shl32(1, 0, 31)
def pte.pde_10() -> H.I64: i64_shl32(0, 1, PDE_PTE_SHIFT())
def pte.tf() -> H.I64: i64_shl32(0, 1, PTE_TF_SHIFT())
def pte.bfs9() -> H.I64: pte.bfs(9)

# `AMDGPU_PTE_TF` is 2**56, which is bit 24 of the LOW half: 2**56 - 2**32 is
# 16777216. `pte.tf()` builds the full 64-bit constant and this builds the low
# mask `not (pte & TF)` needs; the gate says both spellings agree.
def TF_LO_BIT() -> U32: 16777216
def pte.tf_mask() -> U32: TF_LO_BIT()

# :183 is `PDE_PTE_GFX12 if (not is_table and pte_lv != PTB) else (PTE_IS_PTE if
# not is_table else 0)` -- THREE arms on `is_table` FIRST and `pte_lv` SECOND.
# The middle arm, a non-table PTB page, is `PTE_IS_PTE` (2**63) and NOT zero, so
# folding the two tests into one drops it on every PTB page.
def pte.page.is_table(+pte_lv: U32, is_table: U32) -> Bool: U32.is_eq(is_table, 1)
def pte.page.is_not_ptb(+pte_lv: U32) -> Bool: U32.is_ne(pte_lv, VM_PTB())

# AND :186 IS NOT :183. gfx10's arm is ONE condition -- `PDE_PTE if not is_table
# and pte_lv != PTB else 0` -- so a non-table PTB page gets NOTHING there, while
# gfx12's nested conditional gives it `PDE_PTE_GFX12`. The two generations
# disagree on exactly that page and `amp_pte_gfx10_ptb_n_f7_hi` is the row that
# says so; a shared helper for the two is what loses the difference.
def pte.page.gfx12(pte_lv: U32) -> H.I64:
  Bool.pick(H.I64, pte.page.is_not_ptb(pte_lv), pte.pde_gfx12(), pte.pde_gfx12())

def pte.page.gfx10(pte_lv: U32) -> H.I64:
  Bool.pick(H.I64, pte.page.is_not_ptb(pte_lv), pte.pde_10(), i64_lit(0, 0))

def pte.page.go(+gfx12: Bool, +pte_lv: U32, +is_table: U32) -> H.I64:
  Bool.pick(H.I64, pte.page.is_table(pte_lv, is_table), i64_lit(0, 0),
    Bool.pick(H.I64, gfx12, pte.page.gfx12(pte_lv), pte.page.gfx10(pte_lv)))

def pte.page(+gfx12: Bool, +pte_lv: U32, +is_table: U32) -> H.I64:
  pte.page.go(gfx12, pte_lv, is_table)

# :189-191, the gfx9 arm, and the ONLY one with three page-type tests. It is
# reached only when neither gfx10 nor gfx12 holds.
def pte.gfx9.is_bfs(+pte_lv: U32, is_table: U32) -> Bool:
  Bool.and(U32.is_eq(is_table, 1), U32.is_eq(pte_lv, VM_PDB1()))

def pte.gfx9.is_tf(+pte_lv: U32, is_table: U32) -> Bool:
  Bool.and(U32.is_eq(is_table, 1), U32.is_eq(pte_lv, VM_PDB0()))

def pte.gfx9.is_pde(+pte_lv: U32, is_table: U32) -> Bool:
  Bool.and(U32.is_eq(is_table, 0),
    Bool.and(U32.is_ne(pte_lv, VM_PTB()), U32.is_ne(pte_lv, VM_PDB0())))

def pte.gfx9.go(+pte_lv: U32, +is_table: U32) -> H.I64:
  Bool.pick(H.I64, pte.gfx9.is_bfs(pte_lv, is_table), pte.bfs9(),
    Bool.pick(H.I64, pte.gfx9.is_tf(pte_lv, is_table), pte.tf(),
      Bool.pick(H.I64, pte.gfx9.is_pde(pte_lv, is_table), pte.pde_10(), i64_lit(0, 0))))

def pte.gfx9(+pte_lv: U32, +is_table: U32) -> H.I64: pte.gfx9.go(pte_lv, is_table)

def pte.mt.gfx12(+gc0: U32, +gc1: U32, +gc2: U32) -> Bool:
  V.ge(gc0, gc1, gc2, 12, 0, 0)

def pte.mt.gfx10(+gc0: U32, +gc1: U32, +gc2: U32) -> Bool:
  Bool.and(Bool.not(pte.mt.gfx12(gc0, gc1, gc2)), V.ge(gc0, gc1, gc2, 10, 0, 0))

# `MTYPE_UC if uncached else 0` -- :182, :185 and :188 all spell it that way and
# `uncached` is a Bool, so the whole MTYPE term VANISHES when it is false. That is
# why an uncached fixture and a cached fixture differ in exactly six bits.
def pte.of.mt(gc0: U32, uncached: U32, mtype_uc: U32) -> H.I64:
  Bool.pick(H.I64, U32.is_eq(uncached, 1), pte.mtype(gc0, mtype_uc), i64_lit(0, 0))

# :180 AND :183 ARE TWO SEPARATE `if`s. `if not is_table: extra |= WRITEABLE |
# READABLE | EXECUTABLE` is one statement and `:183`'s page flag is a SECOND one
# that runs whatever `is_table` is, subject only to the page-type test. Nesting
# the second under the first loses the `PDE_PTE` / `PDE_PTE_GFX12` bit on every
# NON-table page, which is every page a kernel maps -- and the oracle found it.
def pte.of.body(+pte_lv: U32, +is_table: U32, +gfx12: Bool, +gfx10: Bool, +gc0: U32,
                uncached: U32, mtype_uc: U32) -> H.I64:
  i64_or(Bool.pick(H.I64, U32.is_eq(is_table, 0),
      i64_or(pte.rwe(), pte.of.mt(gc0, uncached, mtype_uc)), i64_lit(0, 0)),
    Bool.pick(H.I64, Bool.or(gfx12, gfx10), pte.page(gfx12, pte_lv, is_table),
      pte.gfx9(pte_lv, is_table)))

# THE WHOLE FUNCTION, :178-192. `functools.cache` on it is WALL 3 (the memo key is
# the 8-tuple) but the VALUE is a pure function of the eight arguments, which is
# why one def serves all four generations.
def pte.of(+pte_lv: U32, +is_table: U32, +frag: U32, +uncached: U32,
           +system: U32, +snooped: U32, +valid: U32, +extra: U32,
           +gc0: U32, +gc1: U32, +gc2: U32, +mtype_uc: U32) -> H.I64:
  i64_or(i64_or(i64_lit(0, extra), pte.base(frag, system, snooped, valid)),
    pte.of.body(pte_lv, is_table, pte.mt.gfx12(gc0, gc1, gc2),
      pte.mt.gfx10(gc0, gc1, gc2), gc0, uncached, mtype_uc))

# :193-195, `is_pte_huge_page`. THE THREE ARMS ANSWER DIFFERENT SHAPES and the
# pre-gfx10 arm MASKS (`pte & ...`) where the other two return the same thing, so
# a port that assumes "the answer is a bit" is wrong for exactly one generation.
#   >= (12,0,0)   pte & AMDGPU_PDE_PTE_GFX12   (2**63)
#   >= (10,0,0)   pte & AMDGPU_PDE_PTE         (2**54)
#   else          pte & AMDGPU_PDE_PTE   if pte_lv != PDB0
#                 not (pte & AMDGPU_PTE_TF)  if pte_lv == PDB0
def pte.huge.not_tf(+pte: H.I64) -> H.I64:
  Bool.pick(H.I64, U32.is_zero(U32.and(H.lo32(pte), pte.tf_mask())), i64_lit(0, 1), i64_lit(0, 0))

def pte.huge.and_pde(+pte: H.I64) -> H.I64: i64_and(pte, pte.pde_10())
def pte.huge.and_gfx12(+pte: H.I64) -> H.I64: i64_and(pte, pte.pde_gfx12())

def pte.huge.pre10(+pte_lv: U32, +pte: H.I64) -> H.I64:
  Bool.pick(H.I64, U32.is_eq(pte_lv, VM_PDB0()), pte.huge.not_tf(pte), pte.huge.and_pde(pte))

def pte.huge.post10(gfx12: Bool, +pte: H.I64) -> H.I64:
  Bool.pick(H.I64, gfx12, pte.huge.and_gfx12(pte), pte.huge.and_pde(pte))

def pte.huge(+pte_lv: U32, +pte: H.I64, +gc0: U32, +gc1: U32, +gc2: U32) -> H.I64:
  Bool.pick(H.I64, V.ge(gc0, gc1, gc2, 10, 0, 0),
    pte.huge.post10(pte.mt.gfx12(gc0, gc1, gc2), pte), pte.huge.pre10(pte_lv, pte))

# :353, the KIQ queue tuple `(2, 1, 0)` against `(1, idx//4, idx%4)`.
def MQD_KIQ_ME() -> U32: 2
def MQD_KIQ_PIPE() -> U32: 1
def MQD_KIQ_QUEUE() -> U32: 0
# :568, the s2a entry ladder: `entry = dev_inst + 1 + 4*aid_id` over FOUR devices.
def SDMA_ENTRY_AID_STRIDE() -> U32: 4
def SDMA_ENTRY_BASE() -> U32: 1


# ===========================================================================
# THE DOORBELL ARITHMETIC, :354 / :366 / :373 / :570-571 / :592 / :601.
#
# There are THREE doorbell numberings in the file and they are not the same:
#
#   :354  KIQ   `AMDGPU_DOORBELL_KIQ + kiq_xcc*0x20`      (0, 32 per xcc)
#   :354  MEC   `AMDGPU_NAVI10_DOORBELL_MEC_RING0`          (3, fixed)
#   :592  SDMA  `AMDGPU_NAVI10_DOORBELL_sDMA_ENGINE0
#                 + (pipe+queue*4)*0xA`                    (256, 10 per channel)
#
# and the doorbell is then written to a register TIMES TWO (:366, :571, :601),
# because the register holds a DWORD index and the doorbell is in 32-byte units.
# `amp_db_*` is one row per stride and `amp_db_off_*` is the row that separates
# the doorbell from its register form.
# ===========================================================================


# :373, `eop_size=(eop_size//4).bit_length()-2` -- the SAME encoding as

# :605, `rb_size=(ring_size//4).bit_length()-1`. ONE MORE than `mqd.size` and NOT
# minus two, because the SDMA ring size field has a different encoding. The pair
# `amp_mqd_qsize` / `amp_mqd_rbsize` on the SAME `ring_size` is the row that says

# :592, `SDMA_ENGINE0 + (pipe+queue*4)*0xA`. The channel index is
# `pipe + queue*4` -- queue is the FAST term -- and :591's register name is
# `regSDMA{pipe}_QUEUE{queue}` with `pipe = idx // 4`. So the name and the
# doorbell channel order the two indices OPPOSITELY, and getting that backwards

# :591, the two register-name spellings. On SDMA (4,4) the name is `regSDMA_GFX`
# and `inst` is the CHANNEL; on everything else it is `regSDMA{pipe}_QUEUE{queue}`


# --- the fixtures the gate sections call -------------------------------------

# ===========================================================================
# `V` -- THE THREE-PART VERSION, which is `ip_ver[am.<X>_HWIP]` and the
# arithmetic behind all forty-odd comparisons in the file. `V.cmp` is a lexical
# three-part compare and `V.eq2` / `V.ne2` are the `[:2]` pair form at
# :30/:300/:313/:591/:604. ALL THREE ARMS matter and the gate has a row on each
# boundary of each, because a version ladder that is off by one is a register
# write to the wrong IP.
# ===========================================================================

# ===========================================================================
# THE PER-ARCH SMU MESSAGE TABLE, `import_module("smu", ip_ver[MP1_HWIP])`.
#
# `_ip_module("smu", am.MP1_HWIP)` at :199 does NOT give a fixed set of numbers:
# it picks the newest `autogen/am/smu_<maj>_<min>_<pat>` at or below the version,
# with TWO hard-coded overrides -- (13,0,7) and (13,0,10) map to (13,0,0) -- and
# then reads `PPSMC_MSG_*` and `PPCLK_*` OFF THE MODULE. So every message id in
# `AM_SMU` is a per-arch cell, and `PPSMC_MSG_GfxDriverReset` is not merely
# different per arch, it is ABSENT on `smu_13_0_0` and `smu_14_0_2`, which is why
# :215 is inside a membership test for exactly those versions.
#
# The table is BOTH DIRECTIONS: `smu.names` is the column, `smu.row*` are the
# three rows, `smu.get` is name-index to value and `smu.name_of` is the reverse.
# `0` is the "the module has no such name" sentinel and it is SAFE: MEASURED, no
# `PPSMC_MSG_*` in any of the four modules is 0 (the minimum is 1). `smu.has_mca`
# is the `hasattr` at :260 turned into a named predicate, and it decides whether
# `_aca_read_banks` returns `[]` or a list of banks.
# ===========================================================================

# ===========================================================================
# THE SMU MESSAGE PROTOCOL, :264-273. THE THREE-REGISTER TRIPLE.
#
# `_smu_cmn_send_msg` writes THREE registers in this order and they are three
# different registers depending on ONE flag:
#
#   :265  resp reg  C2PMSG_90 (normal) / C2PMSG_54 (debug)  <- 0
#   :266  param reg C2PMSG_82 (normal) / C2PMSG_53 (debug)  <- param
#   :267  msg reg   C2PMSG_66 (normal) / C2PMSG_75 (debug)  <- msg
#
# so the ARM is the register choice and the ORDER is the protocol. Both are gate
# rows: `amp_smu_order_*` is the trace and `amp_smu_regs_*` is the (resp, param,
# msg) triple read by name. :271's wait reads the SAME resp register and :273
# returns the param register, so the arm at :273 is the param register too.
# ===========================================================================

# ===========================================================================
# THE PTE FLAG TABLES, :177-195. FOUR GENERATIONS OF THE SAME FIVE-TERM OR.
#
#   :179  extra |= SYSTEM*system | SNOOPED*snooped | VALID*valid | FRAG(frag)
#   :180  if not is_table: extra |= WRITEABLE | READABLE | EXECUTABLE
#   :181  gfx12+  MTYPE_GFX12(0, MTYPE_UC if uncached else 0)
#   :183  gfx12+  PDE_PTE_GFX12 if not is_table and pte_lv != PTB else
#                PTE_IS_PTE if not is_table else 0
#   :184  gfx10+  MTYPE_NV10(...) then PDE_PTE on the same condition
#   :187  else    MTYPE_VG10(...), then BFS(0x9) for PDB1 tables, TF for PDB0
#                tables, PDE_PTE for non-table PTB/PDB0 pages
#
# The result is 64-BIT: `AMDGPU_PDE_PTE_GFX12` is 2**63 and `AMDGPU_PDE_PTE` is
# 2**54, so a `U32` port silently drops the whole flag. `pte.of` answers an
# `H.I64` and the gate prints hi AND lo on every fixture, which is what stops a
# future edit from deciding one U32 is enough.
# ===========================================================================

# ===========================================================================
# THE DOORBELL ARITHMETIC, :354 / :366 / :373 / :570-571 / :592 / :601.
#
# There are THREE doorbell numberings in the file and they are not the same:
#
#   :354  KIQ   `AMDGPU_DOORBELL_KIQ + kiq_xcc*0x20`      (0, 32 per xcc)
#   :354  MEC   `AMDGPU_NAVI10_DOORBELL_MEC_RING0`          (3, fixed)
#   :592  SDMA  `AMDGPU_NAVI10_DOORBELL_sDMA_ENGINE0
#                 + (pipe+queue*4)*0xA`                    (256, 10 per channel)
#
# and the doorbell is then written to a register TIMES TWO (:366, :571, :601),
# because the register holds a DWORD index and the doorbell is in 32-byte units.
# `amp_db_*` is one row per stride and `amp_db_off_*` is the row that separates
# the doorbell from its register form.
# ===========================================================================


# :373, `eop_size=(eop_size//4).bit_length()-2` -- the SAME encoding as

# :605, `rb_size=(ring_size//4).bit_length()-1`. ONE MORE than `mqd.size` and NOT
# minus two, because the SDMA ring size field has a different encoding. The pair
# `amp_mqd_qsize` / `amp_mqd_rbsize` on the SAME `ring_size` is the row that says

# :592, `SDMA_ENGINE0 + (pipe+queue*4)*0xA`. The channel index is
# `pipe + queue*4` -- queue is the FAST term -- and :591's register name is
# `regSDMA{pipe}_QUEUE{queue}` with `pipe = idx // 4`. So the name and the
# doorbell channel order the two indices OPPOSITELY, and getting that backwards

# :591, the two register-name spellings. On SDMA (4,4) the name is `regSDMA_GFX`
# and `inst` is the CHANNEL; on everything else it is `regSDMA{pipe}_QUEUE{queue}`


# :569-571, the s2a entry ladder. `entry = dev_inst + 1 + 4*aid_id` and the
# offset is `(SDMA_ENGINE0 + (entry-1)*0xA) * 2`, so the doorbell channel is
# `entry - 1` and the register holds it TIMES TWO. The scale is load-bearing --


# :569, the four `(port, awid, offset, awaddr)` rows. ORDER matters:
# `enumerate` over it is what makes `dev_inst` and therefore `entry` and

# the four columns, read out of the flat table by `dev_inst` and a COLUMN STRIDE


# ===========================================================================
# THE DOORBELL ARITHMETIC, :354 / :366 / :373 / :570-571 / :592 / :601.
#
# There are THREE doorbell numberings in the file and they are not the same:
#
#   :354  KIQ   `AMDGPU_DOORBELL_KIQ + kiq_xcc*0x20`      (0, 32 per xcc)
#   :354  MEC   `AMDGPU_NAVI10_DOORBELL_MEC_RING0`          (3, fixed)
#   :592  SDMA  `AMDGPU_NAVI10_DOORBELL_sDMA_ENGINE0
#                 + (pipe+queue*4)*0xA`                    (256, 10 per channel)
#
# and the doorbell is then written to a register TIMES TWO (:366, :571, :601),
# because the register holds a DWORD index and the doorbell is in 32-byte units.
# `amp_db_*` is one row per stride and `amp_db_off_*` is the row that separates
# the doorbell from its register form.
# ===========================================================================


# :139/:552, `if inst:` treats zero as ABSENT, so the `xcc != 0` test at :369 and
# the `kiq_xcc` default at :352 need a sentinel. Python's is `-1`; a `U32` needs
# one OUTSIDE the key space, and 255 is outside every `xccs` and every `idx`.
def NO_XCC() -> U32: 255


# :352-382, `setup_ring`'s constants, MEASURED out of the Python's own literals.
def MQD_HEADER() -> U32: 3224438784
def MQD_HQD_STATUS0() -> U32: 536887296
def MQD_QUANTUM() -> U32: 273
# :375, `range(8 if gfx>=10 else 4)` SE fields, each written 0xffffffff.
def MQD_SE_PRE_GFX10() -> U32: 4
def MQD_SE_GFX10() -> U32: 8
def MQD_SE_VALUE() -> U32: 4294967295
# :379-381, `to_mv(...).cast('I')` makes dwords and the walk starts at `0x80`.
def MQD_WALK_DWORD0() -> U32: 128
# :366/:373, the bitfield ENCODE arguments.
def PQ_RPTR_BLOCK_SIZE() -> U32: 5
def PQ_SLOT_BASED_WPTR() -> U32: 2
def PQ_QUEUE_FULL() -> U32: 1
def PQ_UNORD_DISPATCH() -> U32: 0
# :362/:370, the other three encode arguments.
# :333, `scheduler0=(2 << 5) | (1 << 3) | 0x80`.
def SCHEDULER0() -> U32: 200

# :352's default is `kiq_xcc=-1` and the test is `(kiq:=kiq_xcc >= 0)`, so xcc 0
# IS a KIQ xcc and the ONLY non-KIQ value is the sentinel. A port that tests
# `!= 0` gets that exactly backwards -- MEASURED, `amp_db_kiq_0` is
# `AMDGPU_DOORBELL_KIQ` and not `MEC_RING0`.
def gfx.db.is_kiq(+kiq_xcc: U32) -> Bool:
  U32.is_ne(kiq_xcc, NO_XCC())

def gfx.db.kiq(+kiq_xcc: U32) -> U32:
  U32.add(DOORBELL_KIQ(), U32.mul(kiq_xcc, KIQ_XCC_STRIDE()))

def gfx.db.mec() -> U32: DOORBELL_MEC_RING0()

def gfx.db.of(+kiq_xcc: U32) -> U32:
  Bool.pick(U32, gfx.db.is_kiq(kiq_xcc), gfx.db.kiq(kiq_xcc), gfx.db.mec())

# :353, `(2, 1, 0) if kiq else (1, idx // 4, idx % 4)`. The KIQ queue index is
# 0 and the AQL one is `idx % 4`, and :591's SDMA version uses the SAME `// 4`
# and `% 4` on its own `idx`. Three numbers, and they are three rows.
def gfx.q.me(+kiq_xcc: U32, idx: U32) -> U32:
  Bool.pick(U32, gfx.db.is_kiq(kiq_xcc), MQD_KIQ_ME(), 1)

def gfx.q.pipe(+kiq_xcc: U32, idx: U32) -> U32:
  Bool.pick(U32, gfx.db.is_kiq(kiq_xcc), MQD_KIQ_PIPE(), U32.div(idx, 4))

def gfx.q.queue(+kiq_xcc: U32, idx: U32) -> U32:
  Bool.pick(U32, gfx.db.is_kiq(kiq_xcc), MQD_KIQ_QUEUE(), U32.mod(idx, 4))

# :367, `queue_size=(ring_size//4).bit_length()-2` and :373
# `eop_size=(eop_size//4).bit_length()-2`. SAME formula, and `bit_length` of a
# `U32` is `U32.log2` PLUS ONE -- `U32.log2(0)` is the wrong answer for `1`, so
# the `+1` is doing real work and `amp_mqd_qsize` has fixtures at 0 and at 1
# where the two spellings part company.
def mqd.bits(+x: U32) -> U32:
  Bool.pick(U32, U32.is_zero(x), 0, U32.add(U32.from_nat(U32.log2(x)), 1))
def mqd.size(nbytes: U32) -> U32: U32.sub(mqd.bits(U32.div(nbytes, 4)), 2)
def mqd.qsize(ring_size: U32) -> U32: mqd.size(ring_size)
def mqd.esize(eop_size: U32) -> U32: mqd.size(eop_size)

# :605, `rb_size=(ring_size//4).bit_length()-1`. ONE MORE than `mqd.size` and
# NOT minus two, because the SDMA ring size field has a different encoding. The
# pair `amp_mqd_qsize` / `amp_sdma_rbsize` on the SAME `ring_size` is the row
# that says they differ, and :605's arm is `f32_wptr_poll_enable`, so on SDMA
# (4,4) there is no `rb_size` at all.
def sdma.rbsize(ring_size: U32) -> U32: U32.sub(mqd.bits(U32.div(ring_size, 4)), 1)

# :592, `SDMA_ENGINE0 + (pipe+queue*4)*0xA`. The channel index is
# `pipe + queue*4` -- queue is the FAST term -- and :591's register name is
# `regSDMA{pipe}_QUEUE{queue}` with `pipe = idx // 4`. So the name and the
# doorbell channel order the two indices OPPOSITELY, and getting that backwards
# is a doorbell into the wrong queue.
def sdma.pipe(idx: U32) -> U32: U32.div(idx, 4)
def sdma.queue(idx: U32) -> U32: U32.mod(idx, 4)
def sdma.chan(+idx: U32) -> U32: U32.add(sdma.pipe(idx), U32.mul(sdma.queue(idx), 4))
def sdma.db(+idx: U32) -> U32: U32.add(DOORBELL_SDMA_ENGINE0(), U32.mul(sdma.chan(idx), SDMA_ENGINE_STRIDE()))

# :591, the two register-name spellings. On SDMA (4,4) the name is
# `regSDMA_GFX` and `inst` is the CHANNEL; on everything else it is
# `regSDMA{pipe}_QUEUE{queue}` and `inst` is 0.
def sdma.reg_is_gfx(sd0_0: U32, sd0_1: U32) -> Bool: V.eq2(sd0_0, sd0_1, 4, 4)

def sdma.reg.inst(sd0_0: U32, sd0_1: U32, +idx: U32) -> U32:
  Bool.pick(U32, sdma.reg_is_gfx(sd0_0, sd0_1), sdma.chan(idx), 0)


# :373, `eop_size=(eop_size//4).bit_length()-2`, the SAME encoding as
# `queue_size`, and :370's `min_ib_avail_size=0x3` is the one constant beside it.
def mqd.eop_control(eop_size: U32) -> U32: mqd.esize(eop_size)

# :373, `eop_size=(eop_size//4).bit_length()-2` -- the SAME encoding as

# :605, `rb_size=(ring_size//4).bit_length()-1`. ONE MORE than `mqd.size` and NOT
# minus two, because the SDMA ring size field has a different encoding. The pair
# `amp_mqd_qsize` / `amp_mqd_rbsize` on the SAME `ring_size` is the row that says

# :592, `SDMA_ENGINE0 + (pipe+queue*4)*0xA`. The channel index is
# `pipe + queue*4` -- queue is the FAST term -- and :591's register name is
# `regSDMA{pipe}_QUEUE{queue}` with `pipe = idx // 4`. So the name and the
# doorbell channel order the two indices OPPOSITELY, and getting that backwards

# :591, the two register-name spellings. On SDMA (4,4) the name is `regSDMA_GFX`
# and `inst` is the CHANNEL; on everything else it is `regSDMA{pipe}_QUEUE{queue}`


# --- the fixtures the gate sections call -------------------------------------

# ===========================================================================
# `V` -- THE THREE-PART VERSION, which is `ip_ver[am.<X>_HWIP]` and the
# arithmetic behind all forty-odd comparisons in the file. `V.cmp` is a lexical
# three-part compare and `V.eq2` / `V.ne2` are the `[:2]` pair form at
# :30/:300/:313/:591/:604. ALL THREE ARMS matter and the gate has a row on each
# boundary of each, because a version ladder that is off by one is a register
# write to the wrong IP.
# ===========================================================================

# ===========================================================================
# THE PER-ARCH SMU MESSAGE TABLE, `import_module("smu", ip_ver[MP1_HWIP])`.
#
# `_ip_module("smu", am.MP1_HWIP)` at :199 does NOT give a fixed set of numbers:
# it picks the newest `autogen/am/smu_<maj>_<min>_<pat>` at or below the version,
# with TWO hard-coded overrides -- (13,0,7) and (13,0,10) map to (13,0,0) -- and
# then reads `PPSMC_MSG_*` and `PPCLK_*` OFF THE MODULE. So every message id in
# `AM_SMU` is a per-arch cell, and `PPSMC_MSG_GfxDriverReset` is not merely
# different per arch, it is ABSENT on `smu_13_0_0` and `smu_14_0_2`, which is why
# :215 is inside a membership test for exactly those versions.
#
# The table is BOTH DIRECTIONS: `smu.names` is the column, `smu.row*` are the
# three rows, `smu.get` is name-index to value and `smu.name_of` is the reverse.
# `0` is the "the module has no such name" sentinel and it is SAFE: MEASURED, no
# `PPSMC_MSG_*` in any of the four modules is 0 (the minimum is 1). `smu.has_mca`
# is the `hasattr` at :260 turned into a named predicate, and it decides whether
# `_aca_read_banks` returns `[]` or a list of banks.
# ===========================================================================

# ===========================================================================
# THE SMU MESSAGE PROTOCOL, :264-273. THE THREE-REGISTER TRIPLE.
#
# `_smu_cmn_send_msg` writes THREE registers in this order and they are three
# different registers depending on ONE flag:
#
#   :265  resp reg  C2PMSG_90 (normal) / C2PMSG_54 (debug)  <- 0
#   :266  param reg C2PMSG_82 (normal) / C2PMSG_53 (debug)  <- param
#   :267  msg reg   C2PMSG_66 (normal) / C2PMSG_75 (debug)  <- msg
#
# so the ARM is the register choice and the ORDER is the protocol. Both are gate
# rows: `amp_smu_order_*` is the trace and `amp_smu_regs_*` is the (resp, param,
# msg) triple read by name. :271's wait reads the SAME resp register and :273
# returns the param register, so the arm at :273 is the param register too.
# ===========================================================================

# ===========================================================================
# THE PTE FLAG TABLES, :177-195. FOUR GENERATIONS OF THE SAME FIVE-TERM OR.
#
#   :179  extra |= SYSTEM*system | SNOOPED*snooped | VALID*valid | FRAG(frag)
#   :180  if not is_table: extra |= WRITEABLE | READABLE | EXECUTABLE
#   :181  gfx12+  MTYPE_GFX12(0, MTYPE_UC if uncached else 0)
#   :183  gfx12+  PDE_PTE_GFX12 if not is_table and pte_lv != PTB else
#                PTE_IS_PTE if not is_table else 0
#   :184  gfx10+  MTYPE_NV10(...) then PDE_PTE on the same condition
#   :187  else    MTYPE_VG10(...), then BFS(0x9) for PDB1 tables, TF for PDB0
#                tables, PDE_PTE for non-table PTB/PDB0 pages
#
# The result is 64-BIT: `AMDGPU_PDE_PTE_GFX12` is 2**63 and `AMDGPU_PDE_PTE` is
# 2**54, so a `U32` port silently drops the whole flag. `pte.of` answers an
# `H.I64` and the gate prints hi AND lo on every fixture, which is what stops a
# future edit from deciding one U32 is enough.
# ===========================================================================

# ===========================================================================
# THE DOORBELL ARITHMETIC, :354 / :366 / :373 / :570-571 / :592 / :601.
#
# There are THREE doorbell numberings in the file and they are not the same:
#
#   :354  KIQ   `AMDGPU_DOORBELL_KIQ + kiq_xcc*0x20`      (0, 32 per xcc)
#   :354  MEC   `AMDGPU_NAVI10_DOORBELL_MEC_RING0`          (3, fixed)
#   :592  SDMA  `AMDGPU_NAVI10_DOORBELL_sDMA_ENGINE0
#                 + (pipe+queue*4)*0xA`                    (256, 10 per channel)
#
# and the doorbell is then written to a register TIMES TWO (:366, :571, :601),
# because the register holds a DWORD index and the doorbell is in 32-byte units.
# `amp_db_*` is one row per stride and `amp_db_off_*` is the row that separates
# the doorbell from its register form.
# ===========================================================================


# :373, `eop_size=(eop_size//4).bit_length()-2` -- the SAME encoding as

# :605, `rb_size=(ring_size//4).bit_length()-1`. ONE MORE than `mqd.size` and NOT
# minus two, because the SDMA ring size field has a different encoding. The pair
# `amp_mqd_qsize` / `amp_mqd_rbsize` on the SAME `ring_size` is the row that says

# :592, `SDMA_ENGINE0 + (pipe+queue*4)*0xA`. The channel index is
# `pipe + queue*4` -- queue is the FAST term -- and :591's register name is
# `regSDMA{pipe}_QUEUE{queue}` with `pipe = idx // 4`. So the name and the
# doorbell channel order the two indices OPPOSITELY, and getting that backwards

# :591, the two register-name spellings. On SDMA (4,4) the name is `regSDMA_GFX`
# and `inst` is the CHANNEL; on everything else it is `regSDMA{pipe}_QUEUE{queue}`


# :569-571, the s2a entry ladder. `entry = dev_inst + 1 + 4*aid_id` and the
# offset is `(SDMA_ENGINE0 + (entry-1)*0xA) * 2`, so the doorbell channel is
# `entry - 1` and the register holds it TIMES TWO. The scale is load-bearing --


# :569, the four `(port, awid, offset, awaddr)` rows. ORDER matters:
# `enumerate` over it is what makes `dev_inst` and therefore `entry` and

# the four columns, read out of the flat table by `dev_inst` and a COLUMN STRIDE


# :570-571, the s2a entry ladder. `entry = dev_inst + 1 + 4*aid_id` and the
# offset is `(SDMA_ENGINE0 + (entry-1)*0xA) * 2`, so the doorbell channel is
# `entry - 1` and the register holds it TIMES TWO. :569's table gives the four
# (port, awid, offset, awaddr) rows and `entry` runs 1..4 within one aid.
def amp_sdma_entry(aid_id: U32, dev_inst: U32) -> U32:
  U32.add(U32.add(dev_inst, SDMA_ENTRY_BASE()), U32.mul(aid_id, SDMA_ENTRY_AID_STRIDE()))

def amp_sdma_entry_offset(entry: U32) -> U32:
  U32.mul(U32.add(DOORBELL_SDMA_ENGINE0(), U32.mul(U32.sub(entry, SDMA_ENTRY_BASE()),
    SDMA_ENGINE_STRIDE())), DOORBELL_OFFSET_SCALE())

# :569, the four rows `(port, awid, offset, awaddr)`. ORDER matters: `enumerate`
# over it is what makes `dev_inst` and therefore `entry` and therefore the
# doorbell, and the gate prints the whole table.
def amp_sdma_db_tab() -> List<&2, U32>:
  [1, 14, 14, 1, 2, 8, 8, 2, 5, 9, 9, 8, 6, 10, 10, 9]

# the four columns, read out of the flat table by `dev_inst` and a COLUMN STRIDE
# of four. `amp_sdma_db_tab_col` is one row per column and the gate prints the
# four rows joined, so a reordering of `amp_sdma_db_tab` moves all four.
def amp_sdma_db_tab_col(dev_inst: U32, col: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, amp_sdma_db_tab(),
    U32.to_nat(U32.add(U32.mul(dev_inst, 4), col))), 0)

def amp_sdma_db_port(dev_inst: U32) -> U32: amp_sdma_db_tab_col(dev_inst, 0)
def amp_sdma_db_awid(dev_inst: U32) -> U32: amp_sdma_db_tab_col(dev_inst, 1)
def amp_sdma_db_off(dev_inst: U32) -> U32: amp_sdma_db_tab_col(dev_inst, 2)
def amp_sdma_db_awaddr(dev_inst: U32) -> U32: amp_sdma_db_tab_col(dev_inst, 3)

# the same table as ONE ROW of four, which is `enumerate`'s shape at :568. The
# flat sixteen-number row and the four four-number rows are the same data read two
# ways and a gate on each is what says so.
def amp_sdma_db_row(+dev_inst: U32) -> List<&2, U32>:
  [amp_sdma_db_port(dev_inst), amp_sdma_db_awid(dev_inst),
   amp_sdma_db_off(dev_inst), amp_sdma_db_awaddr(dev_inst)]


# --- the constants the DOORBELL section reads --------------------------------
# --- :352-382, `setup_ring`'s constants -------------------------------------


# ===========================================================================

# THE KIQ `flush_tlb` PACKET, :99-112. SEVENTEEN WORDS, BUILT IN ORDER.
#
# :108-110 is one list literal with THREE PM4 packets and the whole thing is
# written into the KIQ ring at `ring[(ptrs[1] + i) % 0x400]` for `i` in
# `enumerate(pkt)`, so the ORDER is the wire format and the wptr advance is
# `len(pkt)`. `kiq.pkt` is that list and `amp_kiq_pkt_*` prints it whole.
#
#   PACKET3(WRITE_DATA,3) 1<<16  req_addr  0  req
#   PACKET3(WAIT_REG_MEM,5) WAIT_REG_MEM_FUNCTION(3) ack_addr 0 (1<<vmid) (1<<vmid) 0x20
#   PACKET3(WRITE_DATA,3) (WR_CONFIRM|WRITE_DATA_DST_SEL(5)) (kiq_va+base+0x1010)le (ptrs[1]+1)
#
# `PACKET3(op, n) == (PACKET_TYPE3 << 30) | ((op & 0xFF) << 8) | ((n & 0x3FFF)
# << 16)` -- MEASURED out of `autogen/am/pm4_soc15.py` -- so BOTH masks matter and
# the count is in the HIGH field, the opposite of the order the two appear in.
# `WR_CONFIRM` is `1 << 20` and `WRITE_DATA_DST_SEL(x)` is `x << 8`; MEASURED, their
# OR at `n = 5` is 0x100500. The port computes it from the two halves so the row
# is a claim and not a restatement of the constant.
# ===========================================================================

def PM4_SEL_MASK() -> U32: 255
def PM4_COUNT_MASK() -> U32: 16383
def PM4_DST_SEL_SHIFT() -> Nat: 8n
def PM4_WR_CONFIRM_SHIFT() -> Nat: 20n
# `autogen/am/pm4_soc15.py`, MEASURED: `PACKET_TYPE3` is 3 and `PACKET3(op, n)`
# puts `op` at bit 8 and `n` at bit 16, both masked. The TYPE is shifted by 30 --
# omitting that is 0xc0033700 becoming 0x00033763, which is a plausible-looking
# wrong packet header, and `amp_pm4_write_data_3` is the row.
def PM4_TYPE3() -> U32: 3
def PM4_TYPE3_SHIFT() -> Nat: 30n
def PM4_SEL_SHIFT() -> Nat: 8n
def PM4_COUNT_SHIFT() -> Nat: 16n
def PM4_PACKET3_WRITE_DATA() -> U32: 55
def PM4_PACKET3_WAIT_REG_MEM() -> U32: 60
# :109, `pm4.WAIT_REG_MEM_FUNCTION(3)` is a `<< 0` generated lambda, so it is the
# identity and the port says so instead of hard-coding 3 twice.
def PM4_WAIT_FN_EQ() -> U32: 3


def pm4.packet3(sel: U32, count: U32) -> U32:
  U32.or(U32.shln(PM4_TYPE3(), PM4_TYPE3_SHIFT()),
    U32.or(U32.shln(U32.and(sel, PM4_SEL_MASK()), PM4_SEL_SHIFT()),
      U32.shln(U32.and(count, PM4_COUNT_MASK()), PM4_COUNT_SHIFT())))

def pm4.write_data(count: U32) -> U32: pm4.packet3(PM4_PACKET3_WRITE_DATA(), count)
def pm4.wait_reg_mem(count: U32) -> U32: pm4.packet3(PM4_PACKET3_WAIT_REG_MEM(), count)

def pm4.wr_confirm() -> U32: U32.shln(1, PM4_WR_CONFIRM_SHIFT())
def pm4.dst_sel(n: U32) -> U32: U32.shln(n, PM4_DST_SEL_SHIFT())
def pm4.write_confirm_sel(n: U32) -> U32: U32.or(pm4.wr_confirm(), pm4.dst_sel(n))

# `data64_le(x)` is `(lo32(x), hi32(x))` -- LITTLE endian, so the LOW word of the
# 64-bit `kiq_va+base+0x1010` goes first. `helpers.bend` has `data64_le` and the
# port uses it rather than hand-rolling the split, because the two orderings are
# indistinguishable on a value whose halves are EQUAL and a fixture with equal
# halves cannot separate them -- `amp_psp_i64le` / `amp_psp_i64be` are the two rows
# and their fixture has DISTINCT halves for exactly that reason.
def kiq.pkt.addr(kiq_va: U32, base: U32) -> H.I64:
  H.i64_of_hi_lo(0, U32.add(U32.add(kiq_va, base), KIQ_FENCE_OFF()))
def kiq.pkt.wr(kiq_va: U32, base: U32) -> U32: H.data64_lo(H.data64(kiq.pkt.addr(kiq_va, base)))
def kiq.pkt.wr_hi(kiq_va: U32, base: U32) -> U32: H.data64_hi(H.data64(kiq.pkt.addr(kiq_va, base)))

# :108's five words. `1 << 16` is the WRITE_DATA header's offset field and `0` is
# the second reserved word.
def kiq.pkt.head(req_addr: U32, req: U32) -> List<&2, U32>:
  [pm4.write_data(3), U32.shln(1, 16n), req_addr, 0, req]

# :109-110's TWELVE words. `1 << vmid` appears TWICE -- the expected and the mask
# -- and `0x20` is the timeout, which are two separate facts a port that folds
# them together gets wrong.
# `*data64_le(...)` is a STAR-UNPACK and so it contributes TWO words: `wr` is the
# LOW half and `wr_hi` the HIGH half. MEASURED out of CPython, the whole packet is
# SEVENTEEN words, and `kiq.pkt.wr_hi` is called from exactly here. A port that
# emitted only `wr` built a sixteen-word packet, and every row still agreed with an
# oracle that had made the same reading error -- which is what happened first, and
# which the mutation `M44` now closes.
# `pm4.WAIT_REG_MEM_FUNCTION(3)` is a `<< 0` generated lambda, so it is the
# identity and the port says so instead of hard-coding 3 twice.
def pm4.wait_fn_eq() -> U32: PM4_WAIT_FN_EQ()

def kiq.pkt.tail(+wait_hdr: U32, +wait_fn: U32, +ack_addr: U32, +z: U32,
                 +vm: U32, +vm2: U32, +tmo: U32, +wd_hdr: U32, +wc_sel: U32,
                 +wr: U32, +wr_hi: U32, +wait: U32) -> List<&2, U32>:
  [wait_hdr, wait_fn, ack_addr, z, vm, vm2, tmo, wd_hdr, wc_sel, wr, wr_hi, wait]

def kiq.pkt(+req_addr: U32, +ack_addr: U32, +vmid: U32, +req: U32,
            +kiq_va: U32, +base: U32, +wptr: U32) -> List<&2, U32>:
  List.append(&2, U32, kiq.pkt.head(req_addr, req), kiq.pkt.tail(pm4.wait_reg_mem(5),
    pm4.wait_fn_eq(), ack_addr, 0, U32.shln(1, U32.to_nat(vmid)),
    U32.shln(1, U32.to_nat(vmid)), 32, pm4.write_data(3), pm4.write_confirm_sel(5),
    kiq.pkt.wr(kiq_va, base), kiq.pkt.wr_hi(kiq_va, base), U32.add(wptr, 1)))

# ===========================================================================
# THE IH ENTRY DECODE, :502-513. ELEVEN EXTRACTORS AND THEIR BIT POSITIONS.
#
# `:502` reads EIGHT dwords out of the ring and `:505-506` calls
# `getattr(am, f'SOC15_{n}_FROM_IH_ENTRY')(entry)` for seven names while `:507`
# does the same for `CONTEXT_ID0..3`. The mask and shift of each are NOT in the
# source -- they live in the autogen lambda -- so they were MEASURED by feeding
# each extractor all 256 single-bit entries and keeping the bits that moved:
#
#   CLIENT_ID 0:7(8)   SOURCE_ID 8:15(8)  RING_ID 16:23(8)  VMID 24:27(4)
#   VMID_TYPE 31:31(1) PASID 96:111(16)   NODEID 112:119(8)
#   CONTEXT_ID0 128:159(32)  CONTEXT_ID1 160:191(32)
#   CONTEXT_ID2 192:223(32) CONTEXT_ID3 224:255(32)
#
# THE FOUR CONTEXT IDs ARE NOT CONTIGUOUS: 28..31 are unused, which is why the
# positions are a table and not `128 + 32*i`. `amp_ih_pos` prints the table.
# ===========================================================================

# MEASURED by probing, and the third element of each triple is the INCLUSIVE HIGH
# BIT -- 7, not 8. An exclusive bound is the natural mistake and it widens every
# field by one, which `amp_ih_client_id_a` is the row that catches.
def ih.field_tab() -> List<&2, U32>:
  [0, 0, 7, 8, 8, 15, 16, 16, 23, 24, 24, 27, 31, 31, 31, 96, 96, 111, 112, 112, 119,
   128, 128, 159, 160, 160, 191, 192, 192, 223, 224, 224, 255]

def ih.col(n: Nat, c: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ih.field_tab(), Nat.add(Nat.mul(n, 3n), c)), 0)

def ih.start(n: U32) -> U32: ih.col(U32.to_nat(n), 0n)
def ih.stop(n: U32) -> U32: ih.col(U32.to_nat(n), 2n)

# the eight dwords, and the extractor's `entry` is that list, so a bit index in
# [0,256) selects a word and a bit.
def ih.word(+entry: List<&2, U32>, start: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, entry, Nat.div(start, 32n)), 0)

# `getbits(value, start, end)` is `helpers.bend`'s and the port uses it, so the
# four CONTEXT_IDs come out of it for free -- they are a full 32-bit window at
# four different starts and nothing else.
# `helpers.getbits(value, start, end)` is `(value >> start) & ((1 << (end - start
# + 1)) - 1)` with `start <= end`, so the table's `lo:hi` pair goes in AS IS.
# Deriving a "32 - (hi - lo)" shift from them -- which is what a port that
# mistakes `getbits` for a width does -- reverses the field on every row.
def ih.getbits(entry: List<&2, U32>, +start: Nat, +end: Nat) -> U32:
  H.getbits(ih.word(entry, start), Nat.mod(start, 32n), Nat.mod(end, 32n))

def ih.get(+entry: List<&2, U32>, +n: U32) -> U32:
  ih.getbits(entry, U32.to_nat(ih.start(n)), U32.to_nat(ih.stop(n)))

# :505's seven names and :507's four, in order.
def ih.names7() -> List<&2, String>:
  ["CLIENT_ID", "SOURCE_ID", "RING_ID", "VMID", "VMID_TYPE", "PASID", "NODEID"]

def ih.names4() -> List<&2, String>: ["CONTEXT_ID0", "CONTEXT_ID1", "CONTEXT_ID2", "CONTEXT_ID3"]

# :509-510, `ih_srcs_names.get(client, {}).get(src, '')` and the refusal of two
# source names. `SKIP_SDMA_TRAP` and `SKIP_CP_EOP_INTR` are the ONLY two strings
# in the whole file that can `continue` the drain loop, and both are compared
# against a NAME that came out of a generated table -- so the COMPARISON is
# WALL 2 and the SKIP PAIR is ported as data.
def ih.skips() -> List<&2, String>: ["SDMA_TRAP", "CP_EOP_INTR"]

# :515-519, the `SQ_INTERRUPT_ID` decode. `enc_type` is `getbits(ctx[1], 6, 7)` on
# soc21 and `getbits(ctx[0], 26, 27)` before it; `err_type` is
# `getbits(ctx[0], 21, 24)` on soc21 and the FOUR-TERM REASSEMBLY below it before
# that. Both the two-arm predicate and the four-name and three-name tables are
# rows, because the pre-soc21 `err_type` does not read either word directly.
def ih.enc.soc21(gc0: U32) -> Bool: V.ge(gc0, 0, 0, 11, 0, 0)
def ih.enc_hi(soc21: Bool) -> U32: Bool.pick(U32, soc21, 6, 26)
def ih.enc_lo(soc21: Bool) -> U32: Bool.pick(U32, soc21, 7, 27)

# :517, `(ctx[0] & 0xfff) | ((ctx[0]>>16) & 0xf000) | ((ctx[1]<<16) & 0xff0000)`.
# THREE terms and TWO OPPOSITE shift directions, and `getbits(..., 20, 23)` then
# reads bits 20..23 of the RESULT. `ctx[1]` is shifted LEFT and masked into the
# byte range, so getting the direction wrong is a plausible-looking wrong answer.
def IH_ERR_LO_MASK() -> U32: 4095
def IH_ERR_MID_MASK() -> U32: 61440
def IH_ERR_HI_MASK() -> U32: 16711680

def ih.err.reasm(+ctx0: U32, ctx1: U32) -> U32:
  U32.or(U32.and(ctx0, IH_ERR_LO_MASK()), U32.or(
    U32.and(U32.shrn(ctx0, 16n), IH_ERR_MID_MASK()),
    U32.and(U32.shln(ctx1, 16n), IH_ERR_HI_MASK())))

def ih.err_hi(soc21: Bool) -> U32: Bool.pick(U32, soc21, 21, 20)
def ih.err_lo(soc21: Bool) -> U32: Bool.pick(U32, soc21, 24, 23)

# :518-519, the two NAME tables. `['auto','wave','error'][enc_type]` and
# `['EDC_FUE','ILLEGAL_INST','MEMVIOL','EDC_FED'][err_type]`, and `enc_type == 2`
# is the test for whether the second table is used at all.
def ih.enc_names() -> List<&2, String>: ["auto", "wave", "error"]
def ih.err_names() -> List<&2, String>: ["EDC_FUE", "ILLEGAL_INST", "MEMVIOL", "EDC_FED"]
def IH_ENC_ERROR() -> U32: 2
def ih.is_err_type(enc_type: U32) -> Bool: U32.is_eq(enc_type, IH_ENC_ERROR())

# :539-541, the ACA classification. `regs[1]` bit 61 AND bit 57 means
# UNCORRECTABLE, and `regs[5]` bits 32..43 and 48..63 are the hwname and the
# mcatype. THE VALUE IS 64-BIT: `_aca_read_reg` at :256-257 is
# `(send_msg(...) << 32) | send_msg(...)`, so bits 61 and 57 are in the HIGH
# word at positions 29 and 25 and a `U32` port cannot even name them.
def ih.aca_bit61() -> U32: 61
def ih.aca_bit57() -> U32: 57
def ih.aca_hwname_lo() -> U32: 32
def ih.aca_mcatype_lo() -> U32: 48

def ih.aca_hi61() -> U32: 29
def ih.aca_hi57() -> U32: 25

def ih.aca_bit(hi: U32, n: U32) -> Bool:
  Bool.not(U32.is_zero(U32.and(U32.shrn(hi, U32.to_nat(n)), 1)))

def ih.aca_uncorrectable(+hi: U32, lo: U32) -> Bool:
  Bool.and(ih.aca_bit(hi, ih.aca_hi61()), ih.aca_bit(hi, ih.aca_hi57()))

# `getbits` takes `Nat`s, and the two windows are 32..43 and 48..63 of the HIGH
# word -- i.e. bits 0..11 and 16..31 OF THAT WORD, which is what makes the port
# read them out of `hi` and not out of the 64-bit value.
def IH_ACA_HWNAME_LO() -> Nat: 0n
def IH_ACA_HWNAME_HI() -> Nat: 11n
def IH_ACA_MCATYPE_LO() -> Nat: 16n
def IH_ACA_MCATYPE_HI() -> Nat: 31n

def ih.aca_hwname(hi: U32) -> U32: H.getbits(hi, IH_ACA_HWNAME_LO(), IH_ACA_HWNAME_HI())
def ih.aca_mcatype(hi: U32) -> U32: H.getbits(hi, IH_ACA_MCATYPE_LO(), IH_ACA_MCATYPE_HI())

# ===========================================================================
# THE REGISTER FIELD LISTS. One `Row` per `.write(...)` / `.update(...)` /
# `.read()` in `ip.py`, with the bitfield NAMES IN SOURCE ORDER.
#
# This is the whole reason the file is worth a gate. `regRLC_SAFE_MODE` is
# written twice -- `message=1, cmd=1` at :392 and `message=0, cmd=1` at :408 --
# so a table keyed by register NAME alone cannot express the file: the pair is
# (line, name) and `Row.ln` is the first field so a row can never claim to be
# the other one. `Row.fs` is a `List<&2, String>` and never a count, because
# `ops_cl`'s unit found `Sig`'s field names INVERTED and a count gate passes
# that: same length, wrong names.
#
# A register written with only `inst=` carries `["inst"]` and NOT `[]`, because
# `inst` selects the INSTANCE and is part of the write. `amp_reg_473` and
# `amp_reg_489` are the two rows that make this distinction load-bearing: the
# same register family, `write(0)` with no keywords and `write(0)` with `inst`.
#


def amp_reg_34() -> Row: Row.of(34, "regXCC_DOORBELL_FENCE", [])
def amp_reg_37() -> Row: Row.of(37, "regBIFC_GFX_INT_MONITOR_MASK", [])
def amp_reg_38() -> Row: Row.of(38, "regBIFC_DOORBELL_ACCESS_EN_PF", [])
def amp_reg_39() -> Row: Row.of(39, "regRCC_DEV0_EPF2_STRAP2", ["strap_no_soft_reset_dev0_f2"])
def amp_reg_40() -> Row: Row.of(40, "regRCC_DEV0_EPF0_RCC_DOORBELL_APER_EN", [])
def amp_reg_42() -> Row:
  Row.of(42, "regHDP_MEM_POWER_CTRL", ["atomic_mem_power_ctrl_en", "atomic_mem_power_ds_en"])
def amp_reg_90() -> Row: Row.of(90, "regBIF_BX_DEV0_EPF0_VF0_HDP_MEM_COHERENCY_FLUSH_CNTL", [])
def amp_reg_119() -> Row: Row.of(119, "reg{ip}VM_INVALIDATE_ENG17_REQ", ["inst"])
def amp_reg_123() -> Row: Row.of(123, "regMMVM_INVALIDATE_ENG17_SEM", ["inst"])
def amp_reg_125() -> Row:
  Row.of(125, "regMMVM_L2_BANK_SELECT_RESERVED_CID2", ["reserved_cache_private_invalidation", "inst"])
def amp_reg_143() -> Row: Row.of(143, "reg{ip}MC_VM_AGP_BASE", ["inst"])
def amp_reg_144() -> Row: Row.of(144, "reg{ip}MC_VM_AGP_BOT", ["inst"])
def amp_reg_145() -> Row: Row.of(145, "reg{ip}MC_VM_AGP_TOP", ["inst"])
def amp_reg_147() -> Row: Row.of(147, "reg{ip}MC_VM_SYSTEM_APERTURE_LOW_ADDR", ["inst"])
def amp_reg_148() -> Row: Row.of(148, "reg{ip}MC_VM_SYSTEM_APERTURE_HIGH_ADDR", ["inst"])
def amp_reg_152() -> Row:
  Row.of(152, "reg{ip}VM_L2_PROTECTION_FAULT_CNTL2", ["active_page_migration_pte_read_retry", "inst"])
def amp_reg_155() -> Row:
  Row.of(155, "reg{ip}MC_VM_MX_L1_TLB_CNTL", ["enable_l1_tlb", "system_access_mode", "enable_advanced_driver_model", "system_aperture_unmapped_access", "mtype", "inst"])
def amp_reg_158() -> Row:
  Row.of(158, "reg{ip}VM_L2_CNTL", ["enable_l2_cache", "enable_default_page_out_to_system_memory", "l2_pde0_cache_tag_generation_mode", "pde_fault_classification", "context1_identity_access_mode", "identity_mode_fragment_size", "enable_l2_fragment_processing", "inst"])
def amp_reg_161() -> Row:
  Row.of(161, "reg{ip}VM_L2_CNTL2", ["invalidate_all_l1_tlbs", "invalidate_l2_cache", "inst"])
def amp_reg_162() -> Row:
  Row.of(162, "reg{ip}VM_L2_CNTL3", ["l2_cache_4k_associativity", "l2_cache_bigk_associativity", "bank_select", "l2_cache_bigk_fragment_size", "inst"])
def amp_reg_164() -> Row:
  Row.of(164, "reg{ip}VM_L2_CNTL4", ["l2_cache_4k_partition_count", "inst"])
def amp_reg_165() -> Row:
  Row.of(165, "reg{ip}VM_L2_CNTL5", ["walker_priority_client_id", "inst"])
def amp_reg_292() -> Row: Row.of(292, "regTCP_CNTL", ["inst"])
def amp_reg_294() -> Row: Row.of(294, "regRLC_CNTL", ["inst"])
def amp_reg_296() -> Row:
  Row.of(296, "regRLC_SRM_CNTL", ["srm_enable", "auto_incr_addr", "inst"])
def amp_reg_298() -> Row: Row.of(298, "regRLC_SPM_MC_CNTL", ["inst"])
def amp_reg_306() -> Row: Row.of(306, "regGB_ADDR_CONFIG", ["inst"])
def amp_reg_307() -> Row: Row.of(307, "regTCP_UTCL1_CNTL2", ["spare", "inst"])
def amp_reg_309() -> Row: Row.of(309, "regGRBM_CNTL", ["read_timeout", "inst"])
def amp_reg_312() -> Row:
  Row.of(312, "regSH_MEM_CONFIG", ["initial_inst_prefetch", "f8_mode", "address_mode", "alignment_mode", "inst"])
def amp_reg_319() -> Row:
  Row.of(319, "regSH_MEM_BASES", ["shared_base", "private_base", "inst"])
def amp_reg_323() -> Row: Row.of(323, "regCP_MEC_DOORBELL_RANGE_LOWER", ["inst"])
def amp_reg_324() -> Row: Row.of(324, "regCP_MEC_DOORBELL_RANGE_UPPER", ["inst"])
def amp_reg_333() -> Row: Row.of(333, "regRLC_CP_SCHEDULERS", ["scheduler0", "inst"])
def amp_reg_382() -> Row: Row.of(382, "regCP_HQD_ACTIVE", ["inst"])
def amp_reg_389() -> Row: Row.of(389, "regMM_ATC_L2_MISC_CG", ["enable", "mem_ls_enable"])
def amp_reg_392() -> Row: Row.of(392, "regRLC_SAFE_MODE", ["message", "cmd", "inst"])
def amp_reg_395() -> Row:
  Row.of(395, "regRLC_CGCG_CGLS_CTRL", ["cgcg_gfx_idle_threshold", "cgcg_en", "cgls_rep_compansat_delay", "cgls_en", "inst"])
def amp_reg_397() -> Row:
  Row.of(397, "regCP_RB_WPTR_POLL_CNTL", ["poll_frequency", "idle_poll_count", "inst"])
def amp_reg_398() -> Row:
  Row.of(398, "regCP_INT_CNTL", ["cntx_busy_int_enable", "cntx_empty_int_enable", "cmp_busy_int_enable", "inst"])
def amp_reg_400() -> Row: Row.of(400, "regSDMA0_RLC_CGCG_CTRL", ["cgcg_int_enable", "inst"])
def amp_reg_401() -> Row: Row.of(401, "regSDMA1_RLC_CGCG_CTRL", ["cgcg_int_enable", "inst"])
def amp_reg_405() -> Row:
  Row.of(405, "regRLC_CGTT_MGCG_OVERRIDE", ["gfxip_fgcg_override", "grbm_cgtt_sclk_override", "rlc_cgtt_sclk_override", "gfxip_mgcg_override", "gfxip_cgls_override", "gfxip_cgcg_override", "inst"])
def amp_reg_408() -> Row: Row.of(408, "regRLC_SAFE_MODE", ["message", "cmd", "inst"])
def amp_reg_411() -> Row:
  Row.of(411, "regGRBM_GFX_CNTL", ["meid", "pipeid", "vmid", "queueid", "inst"])
def amp_reg_415() -> Row:
  Row.of(415, "regCP_MEC_RS64_CNTL", ["mec_pipe0_reset", "mec_pipe0_active", "mec_halt", "inst"])
def amp_reg_416() -> Row: Row.of(416, "regCP_MEC_CNTL", ["inst"])
def amp_reg_421() -> Row: Row.of(421, "regCP_MEC_RS64_CNTL", ["mec_halt", "inst"])
def amp_reg_422() -> Row:
  Row.of(422, "regCP_MEC_CNTL", ["mec_me1_halt", "mec_me2_halt", "inst"])
def amp_reg_435() -> Row:
  Row.of(435, "regCP_MEC_CNTL", ["mec_invalidate_icache", "mec_me1_pipe0_reset", "mec_me2_pipe0_reset", "mec_me1_halt", "mec_me2_halt", "inst"])
def amp_reg_430() -> Row:
  Row.of(430, "regCP_{cntl_reg}_CNTL", ["{eng}_pipe{pipe}_reset_pipe{eng}_pipe{pipe}_reset_reset:1", "inst"])
def amp_reg_431() -> Row:
  Row.of(431, "regCP_{cntl_reg}_CNTL", ["{eng}_pipe{pipe}_reset_pipe{eng}_pipe{pipe}_reset_reset:0", "inst"])
def amp_reg_447() -> Row: Row.of(447, "regCP_HQD_DEQUEUE_REQUEST", ["inst"])
def amp_reg_448() -> Row: Row.of(448, "regSPI_COMPUTE_QUEUE_RESET", ["inst"])
def amp_reg_472() -> Row: Row.of(472, "regIH_RB_WPTR{suf}", [])
def amp_reg_473() -> Row: Row.of(473, "regIH_RB_RPTR{suf}", [])
def amp_reg_475() -> Row: Row.of(475, "regIH_DOORBELL_RPTR{suf}", ["enable"])
def amp_reg_478() -> Row:
  Row.of(478, "regIH_STORM_CLIENT_LIST_CNTL", ["client18_is_storm_client"])
def amp_reg_479() -> Row: Row.of(479, "regIH_INT_FLOOD_CNTL", ["flood_cntl_enable"])
def amp_reg_480() -> Row: Row.of(480, "regIH_MSI_STORM_CTRL", ["delay"])
def amp_reg_489() -> Row: Row.of(489, "regIH_RB_RPTR", [])
def amp_reg_492() -> Row: Row.of(492, "regIH_RB_WPTR{suf}", ["rb_overflow"])
def amp_reg_493() -> Row: Row.of(493, "regIH_RB_CNTL{suf}", ["wptr_overflow_clear"])
def amp_reg_494() -> Row: Row.of(494, "regIH_RB_CNTL{suf}", ["wptr_overflow_clear"])
def amp_reg_525() -> Row:
  Row.of(525, "regGCVM_L2_PROTECTION_FAULT_CNTL", ["clear_protection_fault_status_addr"])
def amp_reg_543() -> Row:
  Row.of(543, "regBIF_BX0_BIF_DOORBELL_INT_CNTL", ["ras_cntlr_interrupt_clear", "ras_athub_err_event_interrupt_clear"])
def amp_reg_549() -> Row: Row.of(549, "regSDMA0_{sdma_name}_CNTL", ["halt"])
def amp_reg_555() -> Row:
  Row.of(555, "regSDMA{pipe}_WATCHDOG_CNTL", ["queue_hang_count", "inst"])
def amp_reg_556() -> Row:
  Row.of(556, "regSDMA{pipe}_UTCL1_CNTL", ["resp_mode", "redo_delay", "inst"])
def amp_reg_559() -> Row:
  Row.of(559, "regSDMA{pipe}_UTCL1_PAGE", ["rd_l2_policy", "wr_l2_policy", "llc_noalloc", "inst"])
def amp_reg_561f() -> Row:
  Row.of(561, "regSDMA{pipe}_{sdma_name}_CNTL", ["halt", "{th1_}reset", "inst"])
def amp_reg_563() -> Row:
  Row.of(563, "regSDMA{pipe}_CNTL", ["trap_enable", "utc_l1_enable", "inst"])
def amp_reg_570() -> Row:
  Row.of(570, "regDOORBELL0_CTRL_ENTRY_{entry}", ["bif_doorbell{th1_}_range_size_entry", "bif_doorbell{th1_}_range_offset_entry"])
def amp_reg_577() -> Row: Row.of(577, "{reg}_RB_CNTL", ["rb_enable", "inst"])
def amp_reg_578() -> Row: Row.of(578, "{reg}_IB_CNTL", ["ib_enable", "inst"])
def amp_reg_579() -> Row: Row.of(579, "{reg}_DOORBELL", ["enable", "inst"])
def amp_reg_580() -> Row: Row.of(580, "{reg}_DOORBELL_OFFSET", ["offset", "inst"])
def amp_reg_583() -> Row: Row.of(583, "regGRBM_SOFT_RESET", ["soft_reset_sdma0"])
def amp_reg_585() -> Row: Row.of(585, "regGRBM_SOFT_RESET", [])
def amp_reg_595() -> Row: Row.of(595, "{reg}_MINOR_PTR_UPDATE", ["inst"])
def amp_reg_601() -> Row: Row.of(601, "{reg}_DOORBELL_OFFSET", ["offset", "inst"])
def amp_reg_602() -> Row: Row.of(602, "{reg}_DOORBELL", ["enable", "inst"])
def amp_reg_603() -> Row: Row.of(603, "{reg}_MINOR_PTR_UPDATE", ["inst"])
def amp_reg_606() -> Row: Row.of(606, "{reg}_IB_CNTL", ["ib_enable", "inst"])
def amp_reg_672() -> Row: Row.of(672, "{reg_pref}_36", [])
def amp_reg_673() -> Row: Row.of(673, "{reg_pref}_35", [])
def amp_reg_688() -> Row: Row.of(688, "{reg_pref}_71", [])
def amp_reg_689() -> Row: Row.of(689, "{reg_pref}_64", [])
def amp_reg_695() -> Row: Row.of(695, "{reg_pref}_64", [])
def amp_reg_699() -> Row: Row.of(699, "{reg_pref}_64", [])
def amp_reg_704() -> Row: Row.of(704, "{reg_pref}_64", [])
def amp_reg_715() -> Row: Row.of(715, "{reg_pref}_67", [])
def amp_reg_135() -> Row:
  Row.of(135, "fault_flags", ["pde0_protection_fault_enable_interrupt", "dummy_page_protection_fault_enable_interrupt", "range_protection_fault_enable_interrupt", "valid_protection_fault_enable_interrupt", "read_protection_fault_enable_interrupt", "write_protection_fault_enable_interrupt", "execute_protection_fault_enable_interrupt"])
def amp_reg_136() -> Row:
  Row.of(136, "en_def_flags", ["pde0_protection_fault_enable_default", "dummy_page_protection_fault_enable_default", "range_protection_fault_enable_default", "valid_protection_fault_enable_default", "read_protection_fault_enable_default", "write_protection_fault_enable_default", "execute_protection_fault_enable_default"])
def amp_reg_137() -> Row:
  Row.of(137, "reg{ip}VM_CONTEXT{vmid}_CNTL", ["pde0_protection_fault_enable_interrupt", "dummy_page_protection_fault_enable_interrupt", "range_protection_fault_enable_interrupt", "valid_protection_fault_enable_interrupt", "read_protection_fault_enable_interrupt", "write_protection_fault_enable_interrupt", "execute_protection_fault_enable_interrupt", "pde0_protection_fault_enable_default", "dummy_page_protection_fault_enable_default", "range_protection_fault_enable_default", "valid_protection_fault_enable_default", "read_protection_fault_enable_default", "write_protection_fault_enable_default", "execute_protection_fault_enable_default", "enable_context", "page_table_depth", "page_table_block_size", "inst"])
def amp_reg_170() -> Row:
  Row.of(170, "reg{ip}VM_L2_CONTEXT1_IDENTITY_APERTURE_LOW_ADDR", ["_LO32", "_HI32"])
def amp_reg_171() -> Row:
  Row.of(171, "reg{ip}VM_L2_CONTEXT1_IDENTITY_APERTURE_HIGH_ADDR", ["_LO32", "_HI32"])
def amp_reg_172() -> Row:
  Row.of(172, "reg{ip}VM_L2_CONTEXT_IDENTITY_PHYSICAL_OFFSET", ["_LO32", "_HI32"])
def amp_reg_174() -> Row:
  Row.of(174, "reg{ip}VM_INVALIDATE_ENG{eng_i}_ADDR_RANGE", ["_LO32", "_HI32"])
def amp_reg_465() -> Row: Row.of(465, "regIH_RB_BASE", ["suf", "_HI{suf}"])
def amp_reg_470() -> Row: Row.of(470, "regIH_RB_WPTR_ADDR", ["_LO", "_HI"])
def amp_reg_697() -> Row: Row.of(697, "reg_pref", ["_69", "_70"])
def amp_reg_377() -> Row: Row.of(377, "{struct_t}", [])
def amp_reg_611() -> Row: Row.of(611, "reg_pref", [])
def amp_reg_717() -> Row: Row.of(717, "fence_paddr", [])
def amp_reg_698() -> Row: Row.of(698, "{reg_pref}_71", [])
def amp_reg_561m() -> Row:
  Row.of(561, "regSDMA{pipe}_{sdma_name}_CNTL", ["halt", "reset", "inst"])
def amp_reg_654() -> Row: Row.of(654, "{reg_pref}_81", [])
def amp_reg_656() -> Row: Row.of(656, "{reg_pref}_35", [])
def amp_reg_467() -> Row:
  Row.of(467, "regIH_RB_CNTL{suf}", ["mc_space", "wptr_overflow_clear", "rb_size", "mc_snoop", "mc_ro", "mc_vmid", "wptr_overflow_enable", "rptr_rearm"])
def amp_reg_484() -> Row: Row.of(484, "regIH_RB_CNTL{suf}", ["rb_enable", "enable_intr"])
def amp_reg_604() -> Row:
  Row.of(604, "{reg}_RB_CNTL", ["{th1_}_wptr_poll_enable", "rb_vmid", "rptr_writeback_enable", "rptr_writeback_timer", "rb_enable", "rb_priv", "rb_size", "inst"])
def amp_reg_467b() -> Row:
  Row.of(467, "regIH_RB_CNTL{suf}", ["mc_space", "wptr_overflow_clear", "rb_size", "mc_snoop", "mc_ro", "mc_vmid", "rb_full_drain_enable"])
def amp_reg_484b() -> Row: Row.of(484, "regIH_RB_CNTL{suf}", ["rb_enable"])
def amp_reg_604b() -> Row:
  Row.of(604, "{reg}_RB_CNTL", ["rb_vmid", "rptr_writeback_enable", "rptr_writeback_timer", "rb_enable", "rb_priv", "rb_size", "inst"])

# ===========================================================================
# THE PSP RING FRAME AND THE FOUR COMMANDS, :707-751.
#
# `struct_psp_gfx_rb_frame` is 64 bytes and `struct_psp_gfx_cmd_resp` is 1024,
# and :715 advances the ring wptr by `ctypes.sizeof(rb_frame) // 4` -- MEASURED
# 16 dwords -- which is the ONLY place the frame's size is used. The field lists
# below are read out of `autogen/am/am.py`'s `register_fields`, and they are BY
# NAME IN ORDER because a packed ctypes struct IS its field list: reordering two
# adjacent u32s is a silently wrong ring frame. `ops_cl`'s unit found `Sig`'s
# field names INVERTED and a count gate passed it, which is why every
# `amp_psp_*_fields` row is a name LIST and never a count.
# ===========================================================================

# MEASURED sizes out of `ctypes.sizeof` on the autogen classes.
def PSP_FRAME_BYTES() -> U32: 64
def PSP_RESP_BYTES() -> U32: 1024
def PSP_UNION_ARMS() -> U32: 11
def PSP_LOAD_IP_FW_BYTES() -> U32: 16
def PSP_SETUP_TMR_BYTES() -> U32: 24
def PSP_LOAD_TOC_BYTES() -> U32: 12
def PSP_SPATIAL_PART_BYTES() -> U32: 16

def psp.frame_fields() -> List<&2, String>:
  ["cmd_buf_addr_lo", "cmd_buf_addr_hi", "cmd_buf_size", "fence_addr_lo",
   "fence_addr_hi", "fence_value", "sid_lo", "sid_hi", "vmid", "frame_type",
   "reserved1", "reserved2"]

# `struct_psp_gfx_cmd_resp` (:728/:737/:745/:751/:755). `cmd` is the
# `union_psp_gfx_commands` and `resp` is the response, and the two `reserved_*`
# byte arrays are what make it 1024.
def psp.resp_fields() -> List<&2, String>:
  ["buf_size", "buf_version", "cmd_id", "resp_buf_addr_lo", "resp_buf_addr_hi",
   "resp_offset", "resp_buf_size", "cmd", "reserved_1", "resp", "reserved_2"]

# `union_psp_gfx_commands` (:3280-3289). ELEVEN arms, all at offset 0 because it
# is a union, and `ip.py` touches exactly four of them: `cmd_load_ip_fw`,
# `cmd_setup_tmr`, `cmd_load_toc` and `cmd_spatial_part`.
def psp.union_fields() -> List<&2, String>:
  ["cmd_load_ta", "cmd_unload_ta", "cmd_invoke_cmd", "cmd_setup_tmr",
   "cmd_load_ip_fw", "cmd_save_restore_ip_fw", "cmd_setup_reg_prog",
   "cmd_setup_vmr", "cmd_load_toc", "boot_cfg", "cmd_spatial_part"]

# the four command structs ip.py fills, BY NAME IN ORDER. :729-731 writes
# `fw_phy_addr_hi` BEFORE `fw_phy_addr_lo` even though `lo` is the first field,
# so the WRITE order and the FIELD order are two different claims and the gate
# pins both -- `amp_psp_i64le` / `amp_psp_i64be` are the write-order rows.
def psp.load_ip_fw_fields() -> List<&2, String>:
  ["fw_phy_addr_lo", "fw_phy_addr_hi", "fw_size", "fw_type"]

def psp.setup_tmr_fields() -> List<&2, String>:
  ["buf_phy_addr_lo", "buf_phy_addr_hi", "buf_size", "bitfield", "tmr_flags",
   "system_phy_addr_lo", "system_phy_addr_hi"]

def psp.setup_tmr_bitfields() -> List<&2, String>: ["sriov_enabled", "virt_phy_addr", "reserved"]

def psp.load_toc_fields() -> List<&2, String>:
  ["toc_phy_addr_lo", "toc_phy_addr_hi", "toc_size"]

def psp.spatial_part_fields() -> List<&2, String>:
  ["mode", "override_ips", "override_xcds_avail", "override_this_aid"]

# :707-709, the frame's five NAMED fields. `fence_value=(prev_wptr:=…)+1` is a
# WALRUS -- `prev_wptr` is read again at :712 and :715 -- so the SAME register
# read feeds the frame's fence, the command buffer's offset and the wptr advance.
# :711 and :712 are two SEPARATE `vram.view` writes into two buffers, and the
# second is at `ring_paddr + prev_wptr*4`, so the ORDER is [fence, cmd_off].
def psp.fence_value(wptr: U32) -> U32: U32.add(wptr, 1)
def psp.cmd_off(wptr: U32) -> U32: U32.add(wptr, PSP_FRAME_DWORDS())
def psp.ring_submit(+wptr: U32) -> List<&2, U32>: [psp.fence_value(wptr), psp.cmd_off(wptr)]

# :611, `reg_pref` is one string or the other and EVERY register in `AM_PSP` is
# `{reg_pref}_<n>`, so the ladder is eleven rows' worth of a single predicate.
def psp.reg_pref(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> U32:
  Bool.pick(U32, V.ge(mp0_0, mp0_1, mp0_2, 14, 0, 0), PREF_MPASP(), PREF_MP0())

# :632-636, the EIGHT `(fw_type, compid)` pairs, IN ORDER. The order is load
# bearing: the sOS is brought up by loading the KDB, the SPL table and then the
# drivers, and the LAST is the sOS itself, whose `compid` is the one that skips
# the second `_wait_for_bootloader` at :675.
def psp.sos_components(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> List<&2, U32>:
  [PSP_FW_KDB(), BL_LOAD_KEY_DATABASE(),
   Bool.pick(U32, V.ge(mp0_0, mp0_1, mp0_2, 14, 0, 0), PSP_FW_SPL(), PSP_FW_KDB()),
   BL_LOAD_SOS_SPL_TABLE(),
   PSP_FW_SYS_DRV(), BL_LOAD_SYSDRV(),
   PSP_FW_SOC_DRV(), BL_LOAD_SOCDRV(),
   PSP_FW_INTF_DRV(), BL_LOAD_INTFDRV(),
   PSP_FW_DBG_DRV(), BL_LOAD_DBGDRV(),
   PSP_FW_RAS_DRV(), BL_LOAD_RASDRV(),
   PSP_FW_SOS(), BL_LOAD_SOSDRV()]

# :675, the ONE component whose `compid` skips the post-write wait, and it is the
# LAST of the eight -- `return self._wait_for_bootloader() if compid !=
# am.PSP_BL__LOAD_SOSDRV else 0`. `psp.sos_last` reads it back out of the table,
# so the row and the table cannot drift apart.
def psp.sos_last(mp0_0: U32, mp0_1: U32, mp0_2: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, List.reverse(&2, U32, psp.sos_components(mp0_0, mp0_1, mp0_2)), 0n), 0)

# :628-629, `boot_time_tmr` and `autoload_tmr`. THE TWO SETS OVERLAP ON
# (13,0,14) and differ on (14,0,2) and (14,0,3), so the two predicates are NOT
# complements and `amp_psp_tmr_*` has a row at (13,0,14) for exactly that reason.
def psp.boot_time_tmr(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> Bool:
  Bool.or(V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 6), Bool.or(
    V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 14), Bool.or(
      V.eq(mp0_0, mp0_1, mp0_2, 14, 0, 2), V.eq(mp0_0, mp0_1, mp0_2, 14, 0, 3))))

def psp.autoload_tmr(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> Bool:
  Bool.and(Bool.not(V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 6)), Bool.not(V.eq(mp0_0, mp0_1, mp0_2, 13, 0, 14)))

# :647, `if not self.boot_time_tmr or not self.autoload_tmr: self._tmr_load_cmd()`,
# so the load fires when EITHER is false. `psp.tmr_load` is the disjunction and
# the (13,0,14) row is the one that separates `or` from `and`.
def psp.tmr_load(boot: Bool, autoload: Bool) -> Bool: Bool.or(Bool.not(boot), Bool.not(autoload))

# :735/:738/:741, `tmr_paddr if self.tmr_paddr else 0` -- THREE SEPARATE zero
# tests on the same paddr, and they are what make a partial boot not write the
# TMR address at all. `psp.phys_or_zero` and `psp.size_or_zero` are two of the
# three and the third is `psp.phys_or_zero` again with a different argument.
def psp.phys_or_zero(paddr: U32, paddr_xgmi: U32) -> U32:
  Bool.pick(U32, U32.is_zero(paddr), 0, paddr_xgmi)

def psp.size_or_zero(tmr_size: U32, tmr_paddr: U32) -> U32:
  Bool.pick(U32, U32.is_zero(tmr_paddr), 0, tmr_size)

# :643 and :652, `PSP_FW_TYPE_PSP_TOC in sos_fw` decides `_tmr_init` and
# `PSP_FW_TYPE_PSP_RL` is the non-gfx11 RLC list. Both are `in` tests on a
# firmware dict, which is WALL 4; the two KEYS are ported as constants.
def PSP_FW_RL_KEY() -> U32: 6
def PSP_FW_TOC_KEY() -> U32: 4

# :651, `_rlc_autoload_cmd` is `GFX_CMD_ID_AUTOLOAD_RLC` for gfx11+ and the
# `GFX_FW_TYPE_REG_LIST` pair otherwise. Two arms, one id each, and the two ids
# come from DIFFERENT enums (a command id and a firmware type) -- 33 and 67.
def GFX_CMD_ID_LOAD_IP_FW() -> U32: 6
def GFX_CMD_ID_SETUP_TMR() -> U32: 5
def GFX_CMD_ID_LOAD_TOC() -> U32: 32
def GFX_CMD_ID_SRIOV_SPATIAL_PART() -> U32: 39
def GFX_CMD_ID_AUTOLOAD_RLC() -> U32: 33
def GFX_FW_TYPE_REG_LIST() -> U32: 67

def psp.rlc_cmd(+gc0: U32, +gc1: U32, +gc2: U32) -> U32:
  Bool.pick(U32, V.ge(gc0, gc1, gc2, 11, 0, 0), GFX_CMD_ID_AUTOLOAD_RLC(), GFX_FW_TYPE_REG_LIST())

# ===========================================================================
# THE WALLS. Nothing below is in the port; each is a `raise`, an `ioctl`, a
# register ACCESS, or a Python reflection that Bend has no spelling for.
#
# 1. REGISTER ACCESS. Every `.write(...)` / `.update(...)` / `.read_bitfields()`
#    lands in the register file, and `AMDReg.encode`'s bit POSITIONS are in
#    `autogen/am/regs.py`, PER ARCH. `ops_amd.bend`'s WALL 2 says the same about
#    `regCOMPUTE_*` and `regSQ_THREAD_TRACE_*`, so this file and that one agree on
#    the split: the port carries WHICH register, WHICH field NAMES and in WHICH
#    order, and the offsets are the seam's. `amp_mqd_pqbits_*` is the row that
#    shows the split is real by printing the ENCODED word CPython produces.
#    TODO(p3) runtime/support/am/ip.py:411  AMDReg.encode -> regGRBM_GFX_CNTL.
#    TODO(p3) runtime/support/am/ip.py:367  regCP_HQD_PQ_CONTROL bit positions.
#
# 2. `hasattr` / `getattr`. :17/:21/:22/:25/:56/:58/:103/:260/:359/:389/:477/:646
#    all probe the `adev` or the module for a NAME, and :506-507 does
#    `getattr(am, f'SOC15_{n}_FROM_IH_ENTRY')`. A Python attribute table is a
#    `dict`; what survives is the ANSWER and not the lookup.
#    TODO(p3) runtime/support/am/ip.py:260  hasattr(smu_mod, 'PPSMC_MSG_QueryValidMcaCount').
#    TODO(p3) runtime/support/am/ip.py:389  hasattr(adev, 'regMM_ATC_L2_MISC_CG').
#    TODO(p3) runtime/support/am/ip.py:646  hasattr(adev.fw, 'smu_psp_desc').
#
# 3. `functools.cache`. `get_pte_flags` (:177) and `read_clocks` (:230) are
#    memoised on their argument tuples. Bend has no memo table and the VALUE is a
#    pure function of the arguments, so nothing is lost but the cache.
#    TODO(p3) runtime/support/am/ip.py:177  functools.cache on get_pte_flags.
#    TODO(p3) runtime/support/am/ip.py:230  functools.cache on read_clocks.
#
# 4. THE FIRMWARE BLOBS and the FLOAT ROUND. `self.adev.fw.sos_fw[fw]` is a
#    `memoryview` of a signed PSP image, `read_table` (:228) is
#    `table_t.from_buffer(bytearray(vram.view(...)))`, and :250's
#    `int(round(watts))` is a float round. The KEYS and the clamp are ported; the
#    bytes and the round are not.
#    TODO(p3) runtime/support/am/ip.py:250  int(round(watts)).
#    TODO(p3) runtime/support/am/ip.py:228  table_t.from_buffer(...).
#
# 5. `wait_cond` and `time.sleep`. Thirteen `wait_cond`s (:113, :117, :121, :222,
#    :271, :284, :393, :450, :640, :656, :695, :704, :717) and six `time.sleep`s
#    (:219, :346, :417, :584, :692, :702). Each wait is a POLL with a timeout and
#    a message; the port carries the POLLED VALUE and the EXPECTED VALUE and not
#    the spin.
#    TODO(p3) runtime/support/am/ip.py:113  wait_cond on the KIQ fence.
#    TODO(p3) runtime/support/am/ip.py:219  time.sleep(0.5) after mode1 reset.
#
# 6. THE MPS AND PAGE TABLES. `mm.palloc`, `mm.map_range`, `mm.alloc_vaddr`,
#    `pci_dev.alloc_sysmem`, `paddrs` and `mm.root_page_table` are the memory
#    manager, which is `support/memory.py` and not this file. What survives is
#    the SIZE and the ALIGNMENT each asks for.
#    TODO(p3) runtime/support/am/ip.py:278  mm.palloc(0x1000 * xccs, 2 + is_vf).
#    TODO(p3) runtime/support/am/ip.py:331  mm.map_range(..., AddrSpace.SYS, snooped, uncached).
#
# ===========================================================================
# ===========================================================================
# THE GATE. One row per claim; the ORACLE is `.agents/slop/ip_oracle.py` and
# every `py=` expectation in it was produced by CALLING CPython, never typed.
# ===========================================================================

def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def brow(nm: String, v: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(v)]))

def srow2(nm: String, v: List<&2, String>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(v, " ")]))

# `List.append(a, A, xs, ys)` is `ys ++ xs` -- a PREPEND -- which is the measured
# spelling and the reason there is no `List.reverse` here. `ops_amd.bend`'s `ush`
# is the same shape and a version of this with the reverse in it prints every
# list backwards.
def ush(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: ush(t, List.append(&2, String, acc, [U32.show(h)]))

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, Nil{}), " ")]))

def i64row(nm: String, x: H.I64) -> IO(Unit): srow(nm, H.i64_text(x))
def i64hirow(nm: String, x: H.I64) -> IO(Unit): urow(nm, H.hi32(x))
def i64lorow(nm: String, x: H.I64) -> IO(Unit): urow(nm, H.lo32(x))

# ONE ROW PER REGISTER ROW, printed as `line <L> | <register> | <fields...>`. The
# LINE is in the row so a reader can find the Python, and the FIELDS are in the
# row so a wrong ORDER is visible. `amp_reg_*` is this row family and there are
# 96 of them.
def frow(nm: String, +r: Row) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(Row.ln(r)), " | ", Row.reg(r), " | ",
    String.join(Row.fs(r), " ")]))

# the `data64_le` pair :110 writes, with DISTINCT halves so the little-endian
# ordering and the high-first ordering cannot agree by accident. PSP_ADDR64 is
# 0x1122334455667788 and the two orders are its halves swapped.
def PSP_ADDR64() -> H.I64: H.i64_of_hi_lo(287454020, 1432778632)
def PSP_I64_LE() -> List<&2, U32>: [H.lo32(PSP_ADDR64()), H.hi32(PSP_ADDR64())]
def PSP_I64_BE() -> List<&2, U32>: [H.hi32(PSP_ADDR64()), H.lo32(PSP_ADDR64())]

# :110's `data64_le(kiq_va+base+0x1010)` for a fixed `(kiq_va, base)`.
def KIQ_VA() -> U32: 2882400000

def amp_smu_dpm_l(clck: U32, i: U32) -> List<&2, U32>: [amp_smu_dpm(clck, i)]

def amp_smu_aca_l(+bank_idx: U32, +reg_idx: U32) -> List<&2, U32>:
  [amp_smu_aca_arg(bank_idx, reg_idx, 0), amp_smu_aca_arg(bank_idx, reg_idx, 1)]

# the THREE REGISTER ROLES in protocol order, as NAMES, so `amp_smu_order_*`
# says which write lands on which register and the ORDER is a claim of its own.
def amp_smu_roles() -> List<&2, String>: ["resp", "param", "msg"]

def amp_smu_order(debug: U32) -> List<&2, String>: amp_smu_roles()

# ===========================================================================
# THE GATE FIXTURES. Every number here is MEASURED out of CPython or derived from
# a measured constant, and each one exists because it can separate two readings
# that a weaker fixture would let agree.
# ===========================================================================

# `pm4.PACKET3(op, n)` over a fixture grid that crosses the `0xff` op mask and the
# `0x3fff` count mask, so a mask or a swap of the two fields moves a row.
def PM4_PKT3_L() -> List<&2, U32>:
  [pm4.packet3(0, 0), pm4.packet3(1, 0), pm4.packet3(0, 1), pm4.packet3(3, 3),
   pm4.packet3(60, 5), pm4.packet3(255, 255), pm4.packet3(256, 1), pm4.packet3(1, 16384)]

# `WR_CONFIRM` and `WRITE_DATA_DST_SEL(n)` over a grid that puts `n` above 8 bits,
# which is where `<< 8` and `<< 16` disagree.
def PM4_WR_L() -> List<&2, U32>: [pm4.wr_confirm(), pm4.write_confirm_sel(1)]
def PM4_DST_L() -> List<&2, U32>: [pm4.dst_sel(0), pm4.dst_sel(1), pm4.dst_sel(5), pm4.dst_sel(256)]

# the eleven IH field POSITIONS, as `name:start:stop` triples flattened.
def IH_POS() -> List<&2, U32>:
  [0, 7, 8, 15, 16, 23, 24, 27, 31, 31, 96, 111, 112, 119,
   128, 159, 160, 191, 192, 223, 224, 255]

# THREE ENTRIES chosen so every field is EXERCISED: `IH_E_A` has one bit set in
# each of the eight words, `IH_E_B` is all ones, and `IH_E_C` sets the two bits
# the `err_type` reassembly and the ACA classification read. A single-entry
# fixture cannot separate `getbits(v, 6, 7)` from `getbits(v, 7, 6)`, which is
# why `amp_ih_err_bits` and `IH_ERR_REASM` are separate rows.
def IH_E_A() -> List<&2, U32>:
  [16909060, 8421504, 22369621, 1048577, 4194305, 234881024, 226492416, 267386880]

def IH_E_B() -> List<&2, U32>:
  [4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295]

def IH_E_C() -> List<&2, U32>:
  [3667189759, 268369897, 3165162705, 3565157206, 305441741, 4261412864, 150994944, 3115665135]

# :516-517's two arms and :518's reassembly, over values where the four terms of
# the reassembly are all non-zero.
def IH_ENC_BITS() -> List<&2, U32>:
  [ih.enc_hi(False{}), ih.enc_lo(False{}), ih.enc_hi(True{}), ih.enc_lo(True{})]

def IH_ERR_BITS() -> List<&2, U32>:
  [ih.err_hi(False{}), ih.err_lo(False{}), ih.err_hi(True{}), ih.err_lo(True{})]

def IH_ERR_REASM() -> List<&2, U32>:
  [ih.err.reasm(0, 0), ih.err.reasm(4294967295, 4294967295),
   ih.err.reasm(3650725889, 0), ih.err.reasm(0, 15790321)]

# :539-541's `regs[1] >> 61 & 1 and regs[1] >> 57 & 1`, over the four quadrants.
def IH_ACA_UNC() -> List<&2, U32>:
  [Bool.to_u32(ih.aca_uncorrectable(0, 0)), Bool.to_u32(ih.aca_uncorrectable(536870912, 0)),
   Bool.to_u32(ih.aca_uncorrectable(33554432, 0)), Bool.to_u32(ih.aca_uncorrectable(4294967295, 0))]

def IH_ACA_FIELDS() -> List<&2, U32>:
  [ih.aca_hwname(0), ih.aca_hwname(4294967295), ih.aca_mcatype(0), ih.aca_mcatype(4294967295)]

# :489's `wptr['offset'] % (ring_size // 4)` and :503's `(rptr + 8) % (ring_size//4)`.
# THE TWO SHARE THE MODULUS, so `amp_ih_drain` is one row with four values and a
# fixture on the wrap boundary (`262145 mod 65536` and `65536+8 mod 65536`).
def IH_DRAIN_OFF() -> U32: U32.mod(262144, IH_WRAP())
def IH_DRAIN_OFF2() -> U32: U32.mod(262145, IH_WRAP())
def IH_DRAIN_RPTR() -> U32: U32.mod(U32.add(65530, 8), IH_WRAP())
def IH_DRAIN_RPTR2() -> U32: U32.mod(U32.add(65536, 8), IH_WRAP())

def IH_DRAIN() -> List<&2, U32>: [IH_DRAIN_OFF(), IH_DRAIN_OFF2(), IH_DRAIN_RPTR(), IH_DRAIN_RPTR2()]

# the KIQ ring wrap, :111.

def KIQ_WRAP_AT(wptr: U32, i: U32) -> U32: U32.and(U32.add(wptr, i), KIQ_RING_MASK())

def KIQ_WRAP_L() -> List<&2, U32>:
  [KIQ_WRAP_AT(0, 0), KIQ_WRAP_AT(1023, 0), KIQ_WRAP_AT(1024, 0),
   KIQ_WRAP_AT(1023, 1), KIQ_WRAP_AT(1024, 1), KIQ_WRAP_AT(4095, 5)]

# :628-629's two predicates and :647's disjunction, as three Bools per version.
def PSP_TMR(+mp0_0: U32, +mp0_1: U32, +mp0_2: U32) -> List<&2, U32>:
  [Bool.to_u32(psp.boot_time_tmr(mp0_0, mp0_1, mp0_2)),
   Bool.to_u32(psp.autoload_tmr(mp0_0, mp0_1, mp0_2)),
   Bool.to_u32(psp.tmr_load(psp.boot_time_tmr(mp0_0, mp0_1, mp0_2),
     psp.autoload_tmr(mp0_0, mp0_1, mp0_2)))]

# ===========================================================================
# GATE 1: THE REGISTER FIELD LISTS, BY NAME AND IN ORDER.
# ===========================================================================
def t_regs() -> IO(Unit):
  do IO<Unit>:
    frow("amp_reg_34", amp_reg_34())
    frow("amp_reg_37", amp_reg_37())
    frow("amp_reg_38", amp_reg_38())
    frow("amp_reg_39", amp_reg_39())
    frow("amp_reg_40", amp_reg_40())
    frow("amp_reg_42", amp_reg_42())
    frow("amp_reg_90", amp_reg_90())
    frow("amp_reg_119", amp_reg_119())
    frow("amp_reg_123", amp_reg_123())
    frow("amp_reg_125", amp_reg_125())
    frow("amp_reg_135", amp_reg_135())
    frow("amp_reg_136", amp_reg_136())
    frow("amp_reg_697", amp_reg_697())
    frow("amp_reg_137", amp_reg_137())
    frow("amp_reg_143", amp_reg_143())
    frow("amp_reg_144", amp_reg_144())
    frow("amp_reg_145", amp_reg_145())
    frow("amp_reg_147", amp_reg_147())
    frow("amp_reg_148", amp_reg_148())
    frow("amp_reg_152", amp_reg_152())
    frow("amp_reg_155", amp_reg_155())
    frow("amp_reg_158", amp_reg_158())
    frow("amp_reg_161", amp_reg_161())
    frow("amp_reg_162", amp_reg_162())
    frow("amp_reg_164", amp_reg_164())
    frow("amp_reg_165", amp_reg_165())
    frow("amp_reg_170", amp_reg_170())
    frow("amp_reg_171", amp_reg_171())
    frow("amp_reg_172", amp_reg_172())
    frow("amp_reg_174", amp_reg_174())
    frow("amp_reg_292", amp_reg_292())
    frow("amp_reg_294", amp_reg_294())
    frow("amp_reg_296", amp_reg_296())
    frow("amp_reg_298", amp_reg_298())
    frow("amp_reg_306", amp_reg_306())
    frow("amp_reg_307", amp_reg_307())
    frow("amp_reg_309", amp_reg_309())
    frow("amp_reg_312", amp_reg_312())
    frow("amp_reg_319", amp_reg_319())
    frow("amp_reg_323", amp_reg_323())
    frow("amp_reg_324", amp_reg_324())
    frow("amp_reg_333", amp_reg_333())
    frow("amp_reg_377", amp_reg_377())
    frow("amp_reg_382", amp_reg_382())
    frow("amp_reg_389", amp_reg_389())
    frow("amp_reg_392", amp_reg_392())
    frow("amp_reg_395", amp_reg_395())
    frow("amp_reg_397", amp_reg_397())
    frow("amp_reg_398", amp_reg_398())
    frow("amp_reg_400", amp_reg_400())
    frow("amp_reg_401", amp_reg_401())
    frow("amp_reg_405", amp_reg_405())
    frow("amp_reg_408", amp_reg_408())
    frow("amp_reg_411", amp_reg_411())
    frow("amp_reg_415", amp_reg_415())
    frow("amp_reg_416", amp_reg_416())
    frow("amp_reg_421", amp_reg_421())
    frow("amp_reg_422", amp_reg_422())
    frow("amp_reg_435", amp_reg_435())
    frow("amp_reg_447", amp_reg_447())
    frow("amp_reg_448", amp_reg_448())
    frow("amp_reg_478", amp_reg_478())
    frow("amp_reg_479", amp_reg_479())
    frow("amp_reg_480", amp_reg_480())
    frow("amp_reg_525", amp_reg_525())
    frow("amp_reg_543", amp_reg_543())
    frow("amp_reg_549", amp_reg_549())
    frow("amp_reg_555", amp_reg_555())
    frow("amp_reg_556", amp_reg_556())
    frow("amp_reg_559", amp_reg_559())
    frow("amp_reg_561f", amp_reg_561f())
    frow("amp_reg_561m", amp_reg_561m())
    frow("amp_reg_563", amp_reg_563())
    frow("amp_reg_570", amp_reg_570())
    frow("amp_reg_577", amp_reg_577())
    frow("amp_reg_578", amp_reg_578())
    frow("amp_reg_579", amp_reg_579())
    frow("amp_reg_580", amp_reg_580())
    frow("amp_reg_583", amp_reg_583())
    frow("amp_reg_585", amp_reg_585())
    frow("amp_reg_595", amp_reg_595())
    frow("amp_reg_601", amp_reg_601())
    frow("amp_reg_602", amp_reg_602())
    frow("amp_reg_603", amp_reg_603())
    frow("amp_reg_604", amp_reg_604())
    frow("amp_reg_604b", amp_reg_604b())
    frow("amp_reg_606", amp_reg_606())
    frow("amp_reg_611", amp_reg_611())
    frow("amp_reg_654", amp_reg_654())
    frow("amp_reg_656", amp_reg_656())
    frow("amp_reg_672", amp_reg_672())
    frow("amp_reg_673", amp_reg_673())
    frow("amp_reg_688", amp_reg_688())
    frow("amp_reg_689", amp_reg_689())
    frow("amp_reg_695", amp_reg_695())
    frow("amp_reg_698", amp_reg_698())
    frow("amp_reg_699", amp_reg_699())
    frow("amp_reg_704", amp_reg_704())
    frow("amp_reg_715", amp_reg_715())
    frow("amp_reg_717", amp_reg_717())
    frow("amp_reg_465", amp_reg_465())
    frow("amp_reg_467", amp_reg_467())
    frow("amp_reg_467b", amp_reg_467b())
    frow("amp_reg_470", amp_reg_470())
    frow("amp_reg_472", amp_reg_472())
    frow("amp_reg_473", amp_reg_473())
    frow("amp_reg_475", amp_reg_475())
    frow("amp_reg_484", amp_reg_484())
    frow("amp_reg_484b", amp_reg_484b())
    frow("amp_reg_489", amp_reg_489())
    frow("amp_reg_492", amp_reg_492())
    frow("amp_reg_493", amp_reg_493())
    frow("amp_reg_494", amp_reg_494())
    frow("amp_reg_430", amp_reg_430())
    frow("amp_reg_431", amp_reg_431())

# THE BIT POSITIONS, MEASURED by probing `AMDReg.encode` on the (12,0,0)
# `regCP_HQD_PQ_CONTROL` field table with ONE field set to 1 at a time. They are
# the seam's offsets kept in one place so WALL 1 is a list and not a smell, and
# `amp_mqd_pqbits_*` shows the encoded words the same CPython call produces.
def PQ_QUEUE_SIZE_BIT() -> U32: 1
def PQ_RPTR_BLOCK_BIT() -> U32: 256
def PQ_QUEUE_FULL_BIT() -> U32: 16384
def PQ_SLOT_WPTR_BIT() -> U32: 262144
def PQ_NO_UPDATE_RPTR_BIT() -> U32: 134217728
def PQ_UNORD_DISPATCH_BIT() -> U32: 268435456
def PQ_KMI_PRIV_BIT() -> U32: 1073741824
def PQ_KMD_QUEUE_BIT() -> U32: 2147483648

# :367-369, `cp_hqd_pq_control=encode(rptr_block_size=5, unord_dispatch=0,
# queue_size=..., **({'priv_state':1,'kmd_queue':1} if kiq else {}),
# **({'queue_full_en':1,'slot_based_wptr':2,'no_update_rptr':...} if aql else {}))`.
#
# WHAT IS PORTED IS THE FIELD VALUES IN SOURCE ORDER and not the encoded word:
# `AMDReg.encode` is `reduce(or, (value << fields[name][0] ...))` and those bit
# POSITIONS are per-ARCH tables in `autogen/am/regs.py`, which is WALL 1 and the
# same split `ops_amd.bend`'s WALL 2 records for `regCOMPUTE_*`.
# `amp_mqd_pqbits_*` is the row that shows the split is real: it prints the
# ENCODED word CPython's own `encode` produces for the fixture.
def mqd.pq.kiq(kiq: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(kiq, 1), [1, 1], [0, 0])

def mqd.pq.aql(aql: U32, no_update_rptr: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(aql, 1),
    [PQ_QUEUE_FULL(), PQ_SLOT_BASED_WPTR(), no_update_rptr], [0, 0, 0])

def mqd.pq_vals(kiq: U32, aql: U32, no_update_rptr: U32) -> List<&2, U32>:
  List.append(&2, U32, mqd.pq.kiq(kiq), mqd.pq.aql(aql, no_update_rptr))

def mqd.pq_head(queue_size: U32) -> List<&2, U32>:
  [PQ_RPTR_BLOCK_SIZE(), PQ_UNORD_DISPATCH(), queue_size]

def mqd.pq_control(+kiq: U32, +aql: U32, queue_size: U32, no_update_rptr: U32) -> List<&2, U32>:
  List.append(&2, U32, mqd.pq_head(queue_size), mqd.pq_vals(kiq, aql, no_update_rptr))

# `AMDReg.encode` is `reduce(or, (value << fields[name][0] ...))`, so the two
# ENCODED WORDS are the OR of the values and the positions. `mqd.pq.bits` is
# that OR and the two constants are what CPython's `encode` produced for the
# fixture, which is what makes them a row and not a restatement.
# `bit_list` holds MASKS (`1 << bit`) and `U32.shln` wants the INDEX, so the
# mask is LOGGED here. Passing the mask straight to `shln` saturates to zero for
# every bit above 31 and the whole encoded word collapses -- which is what
# `amp_mqd_pqbits_kiq` is the row for.
def mqd.pq.bit_at(+bits: List<&2, U32>, k: Nat) -> Nat:
  U32.log2(Maybe.default(&2, U32, List.get(&2, U32, bits, k), 1))

# `case 1n+m` DESTROYS the scrutinee, so the index cannot be recovered from `n`
# inside the arm. It is therefore a SECOND Nat, and the SHRINKING one is first.
def mqd.pq.bits.go(n: Nat, +i: Nat, vals: List<&2, U32>, +bits: List<&2, U32>, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+m:
      match vals:
        case Nil{}: acc
        case v <> t: mqd.pq.bits.go(m, Nat.add(i, 1n), t, bits,
          U32.or(acc, U32.shln(v, mqd.pq.bit_at(bits, i))))

def mqd.pq.bits(+vals: List<&2, U32>, bits: List<&2, U32>) -> U32:
  mqd.pq.bits.go(List.length(&2, U32, vals), 0n, vals, bits, 0)


def mqd.pq.bit_list() -> List<&2, U32>:
  [PQ_RPTR_BLOCK_BIT(), PQ_UNORD_DISPATCH_BIT(), PQ_QUEUE_SIZE_BIT(),
   PQ_KMI_PRIV_BIT(), PQ_KMD_QUEUE_BIT(),
   PQ_QUEUE_FULL_BIT(), PQ_SLOT_WPTR_BIT(), PQ_NO_UPDATE_RPTR_BIT()]

def MQD_PQ_BITS_KIQ() -> U32:
  mqd.pq.bits(mqd.pq_control(1, 0, 10, 0), mqd.pq.bit_list())

def MQD_PQ_BITS_AQL() -> U32:
  mqd.pq.bits(mqd.pq_control(0, 1, 10, 1), mqd.pq.bit_list())

def MQD_PQ_BIT_POS() -> List<&2, U32>:
  [PQ_RPTR_BLOCK_BIT(), PQ_QUEUE_FULL_BIT(), PQ_SLOT_WPTR_BIT(),
   PQ_NO_UPDATE_RPTR_BIT(), PQ_KMI_PRIV_BIT(), PQ_KMD_QUEUE_BIT()]

def MQD_QSIZE() -> List<&2, U32>:
  [mqd.qsize(0), mqd.qsize(1), mqd.qsize(4), mqd.qsize(256), mqd.qsize(1024), mqd.qsize(65536)]

def MQD_ESIZE() -> List<&2, U32>: [mqd.esize(4096), mqd.esize(8192)]

def MQD_RBSIZE() -> List<&2, U32>:
  [sdma.rbsize(256), sdma.rbsize(1024), sdma.rbsize(65536)]

# ===========================================================================
# GATE 2: THE PSP STRUCT FIELD LISTS, BY NAME AND IN ORDER.
# ===========================================================================
def t_structs() -> IO(Unit):
  do IO<Unit>:
    srow2("amp_psp_frame_fields", psp.frame_fields())
    urow("amp_psp_frame_bytes", PSP_FRAME_BYTES())
    urow("amp_psp_frame_dwords", PSP_FRAME_DWORDS())
    urow("amp_psp_resp_bytes", PSP_RESP_BYTES())
    srow2("amp_psp_resp_fields", psp.resp_fields())
    srow2("amp_psp_union_fields", psp.union_fields())
    urow("amp_psp_union_arms", PSP_UNION_ARMS())
    srow2("amp_psp_load_ip_fw_fields", psp.load_ip_fw_fields())
    srow2("amp_psp_setup_tmr_fields", psp.setup_tmr_fields())
    srow2("amp_psp_setup_tmr_bf", psp.setup_tmr_bitfields())
    srow2("amp_psp_load_toc_fields", psp.load_toc_fields())
    srow2("amp_psp_spatial_part_fields", psp.spatial_part_fields())
    urow("amp_psp_load_ip_fw_bytes", PSP_LOAD_IP_FW_BYTES())
    urow("amp_psp_setup_tmr_bytes", PSP_SETUP_TMR_BYTES())
    urow("amp_psp_load_toc_bytes", PSP_LOAD_TOC_BYTES())
    urow("amp_psp_spatial_part_bytes", PSP_SPATIAL_PART_BYTES())
    # :729-731 writes `hi` BEFORE `lo` while `lo` is the FIRST field, so the two
    # orders are separate claims. `amp_psp_i64le` prints both halves LITTLE endian
    # and `amp_psp_i64be` prints them HIGH FIRST, and the two rows agree only
    # where the halves are equal -- which is why the fixture has distinct halves.
    lrow("amp_psp_i64le", PSP_I64_LE())
    lrow("amp_psp_i64be", PSP_I64_BE())

# ===========================================================================
# GATE 3: THE SMU MESSAGE PROTOCOL, :264-273 and the per-arch table.
# ===========================================================================
def t_smu() -> IO(Unit):
  do IO<Unit>:
    srow2("amp_smu_regs_norm", amp_smu_regs(0))
    srow2("amp_smu_regs_dbg", amp_smu_regs(1))
    srow2("amp_smu_order_norm", amp_smu_order(0))
    srow2("amp_smu_order_dbg", amp_smu_order(1))
    urow("amp_smu_seen_norm", Tr.seen(amp_smu_msgs(4660, 3735928559, 0, Tr.of())))
    urow("amp_smu_seen_dbg", Tr.seen(amp_smu_msgs(4660, 3735928559, 1, Tr.of())))
    lrow("amp_smu_resp_norm", Tr.args(0, Tr.calls(amp_smu_msgs(4660, 3735928559, 0, Tr.of()))))
    lrow("amp_smu_resp_dbg", Tr.args(0, Tr.calls(amp_smu_msgs(4660, 3735928559, 1, Tr.of()))))
    lrow("amp_smu_param_norm", Tr.args(1, Tr.calls(amp_smu_msgs(4660, 3735928559, 0, Tr.of()))))
    lrow("amp_smu_param_dbg", Tr.args(1, Tr.calls(amp_smu_msgs(4660, 3735928559, 1, Tr.of()))))
    lrow("amp_smu_msg_norm", Tr.args(2, Tr.calls(amp_smu_msgs(4660, 3735928559, 0, Tr.of()))))
    lrow("amp_smu_msg_dbg", Tr.args(2, Tr.calls(amp_smu_msgs(4660, 3735928559, 1, Tr.of()))))
    lrow("amp_smu_smu_init", amp_smu_smu(305441741))
    lrow("amp_smu_smu_init2", amp_smu_smu(43981))
    # the per-arch table, both directions
    srow2("amp_smu_cols", smu.names())
    lrow("amp_smu_row_13_0_0", smu.row(0))
    lrow("amp_smu_row_13_0_6", smu.row(1))
    lrow("amp_smu_row_14_0_2", smu.row(2))
    urow("amp_smu_arch_13_0_0", smu.arch(13, 0, 0))
    urow("amp_smu_arch_13_0_6", smu.arch(13, 0, 6))
    urow("amp_smu_arch_13_0_7", smu.arch(13, 0, 7))
    urow("amp_smu_arch_13_0_10", smu.arch(13, 0, 10))
    urow("amp_smu_arch_13_0_12", smu.arch(13, 0, 12))
    urow("amp_smu_arch_13_0_15", smu.arch(13, 0, 15))
    urow("amp_smu_arch_14_0_2", smu.arch(14, 0, 2))
    urow("amp_smu_arch_14_0_3", smu.arch(14, 0, 3))
    urow("amp_smu_arch_14_1_0", smu.arch(14, 1, 0))
    urow("amp_smu_arch_12_0_0", smu.arch(12, 0, 0))
    brow("amp_smu_miss_14_0_0", smu.arch.missing(14, 0, 0))
    brow("amp_smu_miss_14_0_2", smu.arch.missing(14, 0, 2))
    brow("amp_smu_miss_13_0_0", smu.arch.missing(13, 0, 0))
    urow("amp_smu_dram_hi_13_0_0", smu.get(smu.arch(13, 0, 0), SMU_COL_DRAM_HI()))
    urow("amp_smu_dram_hi_13_0_6", smu.get(smu.arch(13, 0, 6), SMU_COL_DRAM_HI()))
    urow("amp_smu_dram_hi_14_0_2", smu.get(smu.arch(14, 0, 2), SMU_COL_DRAM_HI()))
    urow("amp_smu_gfxrst_13_0_0", smu.get(smu.arch(13, 0, 0), SMU_COL_GFX_RESET()))
    urow("amp_smu_gfxrst_13_0_6", smu.get(smu.arch(13, 0, 6), SMU_COL_GFX_RESET()))
    urow("amp_smu_mode1_13_0_0", smu.get(smu.arch(13, 0, 0), SMU_COL_MODE1()))
    urow("amp_smu_mode1_14_0_2", smu.get(smu.arch(14, 0, 2), SMU_COL_MODE1()))
    brow("amp_smu_has_mca_13_0_0", smu.has_mca(smu.arch(13, 0, 0)))
    brow("amp_smu_has_mca_13_0_6", smu.has_mca(smu.arch(13, 0, 6)))
    brow("amp_smu_has_mca_14_0_2", smu.has_mca(smu.arch(14, 0, 2)))
    urow("amp_smu_ppt_0", amp_smu_ppt(0))
    urow("amp_smu_ppt_1", amp_smu_ppt(1))
    urow("amp_smu_ppt_250", amp_smu_ppt(250))
    lrow("amp_smu_dpm_2_0", amp_smu_dpm_l(2, 0))
    lrow("amp_smu_dpm_2_255", amp_smu_dpm_l(2, 255))
    lrow("amp_smu_dpm_3_5", amp_smu_dpm_l(3, 5))
    lrow("amp_smu_aca_0_0", amp_smu_aca_l(0, 0))
    lrow("amp_smu_aca_5_15", amp_smu_aca_l(5, 15))
    urow("amp_smu_clks_13_0_0", amp_smu_clks(13, 0, 0))
    urow("amp_smu_clks_13_0_6", amp_smu_clks(13, 0, 6))
    urow("amp_smu_clks_13_0_12", amp_smu_clks(13, 0, 12))
    urow("amp_smu_clks_13_0_15", amp_smu_clks(13, 0, 15))
    urow("amp_smu_clks_14_0_2", amp_smu_clks(14, 0, 2))
    urow("amp_smu_mode1_13_0_0", amp_smu_mode1(13, 0, 0))
    urow("amp_smu_mode1_13_0_6", amp_smu_mode1(13, 0, 6))
    urow("amp_smu_mode1_13_0_7", amp_smu_mode1(13, 0, 7))
    urow("amp_smu_mode1_13_0_10", amp_smu_mode1(13, 0, 10))
    urow("amp_smu_mode1_13_0_12", amp_smu_mode1(13, 0, 12))
    urow("amp_smu_mode1_13_0_15", amp_smu_mode1(13, 0, 15))
    urow("amp_smu_mode1_14_0_0", amp_smu_mode1(14, 0, 0))
    urow("amp_smu_mode1_14_0_2", amp_smu_mode1(14, 0, 2))
    urow("amp_smu_clocks_unlimited", SMU_CLOCK_UNLIMITED())

# ===========================================================================
# GATE 4: THE PTE FLAG TABLES, :177-195. FOUR GENERATIONS, BOTH HALVES.
#
# Every row prints hi AND lo, because the whole point of the section is that the
# flags do not fit in 32 bits: `amp_pte_pde_hi` is 2147483648 for gfx12 and 0
# for gfx10, and a port that truncated would print the gfx10 answer twice.
# ===========================================================================
def t_pte() -> IO(Unit):
  do IO<Unit>:
    urow("amp_pte_frag_0", H.lo32(pte.frag(0)))
    urow("amp_pte_frag_1", H.lo32(pte.frag(1)))
    urow("amp_pte_frag_7", H.lo32(pte.frag(7)))
    urow("amp_pte_frag_31", H.lo32(pte.frag(31)))
    urow("amp_pte_frag_32", H.lo32(pte.frag(32)))
    urow("amp_pte_frag_33", H.lo32(pte.frag(33)))
    urow("amp_pte_bfs_9", H.lo32(pte.bfs(9)))
    i64row("amp_pte_bfs_9_i64", pte.bfs(9))
    urow("amp_pte_pde_gfx12_hi", H.hi32(pte.pde_gfx12()))
    urow("amp_pte_pde_gfx12_lo", H.lo32(pte.pde_gfx12()))
    urow("amp_pte_pde_10_hi", H.hi32(pte.pde_10()))
    urow("amp_pte_pde_10_lo", H.lo32(pte.pde_10()))
    urow("amp_pte_tf_hi", H.hi32(pte.tf()))
    urow("amp_pte_tf_lo", H.lo32(pte.tf()))
    urow("amp_pte_tf_mask", pte.tf_mask())
    urow("amp_pte_rwe_lo", H.lo32(pte.rwe()))
    i64row("amp_pte_mtype_12_uc", pte.mtype(12, 3))
    i64row("amp_pte_mtype_10_uc", pte.mtype(10, 3))
    i64row("amp_pte_mtype_9_uc", pte.mtype(9, 3))
    i64row("amp_pte_mtype_12_7", pte.mtype(12, 7))
    i64row("amp_pte_mtype_10_7", pte.mtype(10, 7))
    i64row("amp_pte_mtype_9_7", pte.mtype(9, 7))
    brow("amp_pte_mtype_same", H.i64_le(pte.mtype(12, 3), pte.mtype(9, 3)))
    urow("amp_pte_mtype_gfx12_n", MTYPE_SHIFT_GFX12())
    urow("amp_pte_mtype_nv10_n", MTYPE_SHIFT_NV10())
    urow("amp_pte_mtype_vg10_n", MTYPE_SHIFT_VG10())
    # the whole function, over a fixed fixture grid, per generation
    i64hirow("amp_pte_gfx12_pdb1_t_f0_hi", pte.of(1, 1, 0, 0, 0, 0, 0, 0, 12, 0, 0, 3))
    i64lorow("amp_pte_gfx12_pdb1_t_f0_lo", pte.of(1, 1, 0, 0, 0, 0, 0, 0, 12, 0, 0, 3))
    i64hirow("amp_pte_gfx12_ptb_n_f3_hi", pte.of(3, 0, 3, 1, 1, 1, 1, 0, 12, 0, 0, 3))
    i64lorow("amp_pte_gfx12_ptb_n_f3_lo", pte.of(3, 0, 3, 1, 1, 1, 1, 0, 12, 0, 0, 3))
    i64hirow("amp_pte_gfx12_pdb0_n_f0_hi", pte.of(2, 0, 0, 0, 0, 0, 1, 0, 12, 0, 0, 3))
    i64lorow("amp_pte_gfx12_pdb0_n_f0_lo", pte.of(2, 0, 0, 0, 0, 0, 1, 0, 12, 0, 0, 3))
    i64hirow("amp_pte_gfx12_pdb1_n_c_hi", pte.of(1, 0, 1, 0, 0, 0, 1, 0, 12, 0, 0, 3))
    i64lorow("amp_pte_gfx12_pdb1_n_c_lo", pte.of(1, 0, 1, 0, 0, 0, 1, 0, 12, 0, 0, 3))
    i64hirow("amp_pte_gfx10_ptb_n_f7_hi", pte.of(3, 0, 7, 1, 1, 0, 1, 0, 10, 3, 0, 3))
    i64lorow("amp_pte_gfx10_ptb_n_f7_lo", pte.of(3, 0, 7, 1, 1, 0, 1, 0, 10, 3, 0, 3))
    i64hirow("amp_pte_gfx10_pdb1_n_c_hi", pte.of(1, 0, 2, 1, 0, 1, 1, 0, 10, 3, 0, 3))
    i64lorow("amp_pte_gfx10_pdb1_n_c_lo", pte.of(1, 0, 2, 1, 0, 1, 1, 0, 10, 3, 0, 3))
    i64hirow("amp_pte_gfx9_pdb1_t_f2_hi", pte.of(1, 1, 2, 0, 0, 0, 1, 0, 9, 4, 3, 3))
    i64lorow("amp_pte_gfx9_pdb1_t_f2_lo", pte.of(1, 1, 2, 0, 0, 0, 1, 0, 9, 4, 3, 3))
    i64hirow("amp_pte_gfx9_pdb0_t_f2_hi", pte.of(2, 1, 2, 0, 0, 0, 1, 0, 9, 4, 3, 3))
    i64lorow("amp_pte_gfx9_pdb0_t_f2_lo", pte.of(2, 1, 2, 0, 0, 0, 1, 0, 9, 4, 3, 3))
    i64hirow("amp_pte_gfx9_ptb_t_f2_hi", pte.of(3, 1, 2, 0, 0, 0, 1, 0, 9, 4, 3, 3))
    i64lorow("amp_pte_gfx9_ptb_t_f2_lo", pte.of(3, 1, 2, 0, 0, 0, 1, 0, 9, 4, 3, 3))
    i64hirow("amp_pte_gfx9_pdb0_n_f2_hi", pte.of(2, 0, 2, 0, 0, 0, 1, 0, 9, 4, 3, 3))
    i64lorow("amp_pte_gfx9_pdb0_n_f2_lo", pte.of(2, 0, 2, 0, 0, 0, 1, 0, 9, 4, 3, 3))
    i64hirow("amp_pte_gfx9_pdb1_n_f2_hi", pte.of(1, 0, 2, 0, 0, 0, 1, 0, 9, 4, 3, 3))
    i64lorow("amp_pte_gfx9_pdb1_n_f2_lo", pte.of(1, 0, 2, 0, 0, 0, 1, 0, 9, 4, 3, 3))
    i64hirow("amp_pte_gfx9_pdb1_n_u_hi", pte.of(1, 0, 2, 1, 0, 0, 1, 0, 9, 4, 3, 3))
    i64lorow("amp_pte_gfx9_pdb1_n_u_lo", pte.of(1, 0, 2, 1, 0, 0, 1, 0, 9, 4, 3, 3))
    i64hirow("amp_pte_extra_9_0_0_7_hi", pte.of(3, 1, 0, 0, 0, 0, 1, 7, 9, 4, 3, 3))
    i64lorow("amp_pte_extra_9_0_0_7_lo", pte.of(3, 1, 0, 0, 0, 0, 1, 7, 9, 4, 3, 3))
    # `is_pte_huge_page`, :193-195. THE THREE ARMS ANSWER DIFFERENT SHAPES.
    i64row("amp_pte_huge_9_pdb0_p", pte.huge(2, i64_lit(0, 1), 9, 4, 3))
    i64row("amp_pte_huge_9_pdb0_q", pte.huge(2, i64_lit(1, 1), 9, 4, 3))
    i64row("amp_pte_huge_9_ptb_p", pte.huge(3, i64_lit(0, 1), 9, 4, 3))
    i64row("amp_pte_huge_10_ptb_p", pte.huge(3, i64_lit(0, 1), 10, 3, 0))
    i64row("amp_pte_huge_12_ptb_p", pte.huge(3, i64_lit(0, 1), 12, 0, 0))
    i64row("amp_pte_huge_12_ptb_q", pte.huge(3, i64_lit(1, 1), 12, 0, 0))
    i64row("amp_pte_huge_10_ptb_q", pte.huge(3, i64_lit(1, 1), 10, 3, 0))

# ===========================================================================
# GATE 5: THE DOORBELL ARITHMETIC AND THE MQD SIZE ENCODINGS.
# ===========================================================================
def t_db() -> IO(Unit):
  do IO<Unit>:
    urow("amp_db_kiq_0", gfx.db.of(0))
    urow("amp_db_kiq_1", gfx.db.of(1))
    urow("amp_db_kiq_3", gfx.db.of(3))
    urow("amp_db_none_255", gfx.db.of(255))
    urow("amp_db_mec_255", gfx.db.of(255))
    urow("amp_db_kq_kiq_me", gfx.q.me(0, 0))
    urow("amp_db_kq_kiq_pipe", gfx.q.pipe(0, 0))
    urow("amp_db_kq_kiq_queue", gfx.q.queue(0, 0))
    urow("amp_db_kq_aql_me", gfx.q.me(255, 0))
    urow("amp_db_kq_aql_pipe0", gfx.q.pipe(255, 0))
    urow("amp_db_kq_aql_q0", gfx.q.queue(255, 0))
    urow("amp_db_kq_aql_pipe1", gfx.q.pipe(255, 4))
    urow("amp_db_kq_aql_q1", gfx.q.queue(255, 4))
    urow("amp_db_kq_aql_pipe2", gfx.q.pipe(255, 7))
    urow("amp_db_kq_aql_q2", gfx.q.queue(255, 7))
    urow("amp_db_sdma_0", sdma.db(0))
    urow("amp_db_sdma_1", sdma.db(1))
    urow("amp_db_sdma_4", sdma.db(4))
    urow("amp_db_sdma_5", sdma.db(5))
    urow("amp_db_sdma_7", sdma.db(7))
    urow("amp_db_sdma_pipe5", sdma.pipe(5))
    urow("amp_db_sdma_queue5", sdma.queue(5))
    urow("amp_db_sdma_chan5", sdma.chan(5))
    urow("amp_db_sdma_inst_44_2_5", sdma.reg.inst(4, 4, 5))
    urow("amp_db_sdma_inst_6_0_5", sdma.reg.inst(6, 0, 5))
    urow("amp_db_sdma_inst_6_0_0", sdma.reg.inst(6, 0, 0))
    lrow("amp_db_tab", amp_sdma_db_tab())
    lrow("amp_db_tab_row0", amp_sdma_db_row(0))
    lrow("amp_db_tab_row1", amp_sdma_db_row(1))
    lrow("amp_db_tab_row2", amp_sdma_db_row(2))
    lrow("amp_db_tab_row3", amp_sdma_db_row(3))
    lrow("amp_db_tab_row9", amp_sdma_db_row(9))
    urow("amp_db_entry_0_0", amp_sdma_entry(0, 0))
    urow("amp_db_entry_0_3", amp_sdma_entry(0, 3))
    urow("amp_db_entry_1_0", amp_sdma_entry(1, 0))
    urow("amp_db_entry_2_3", amp_sdma_entry(2, 3))
    urow("amp_db_off_1", amp_sdma_entry_offset(1))
    urow("amp_db_off_4", amp_sdma_entry_offset(4))
    urow("amp_db_off_5", amp_sdma_entry_offset(5))
    urow("amp_db_size", DOORBELL_RANGE_SIZE())
    # the MQD size encodings: :367/:373 minus TWO and :605 minus ONE, on the SAME
    # ring sizes, and a `ring_size` of 0 and 1 where the `-2` underflows.
    lrow("amp_mqd_qsize", MQD_QSIZE())
    lrow("amp_mqd_esize", MQD_ESIZE())
    lrow("amp_mqd_rbsize", MQD_RBSIZE())
    urow("amp_mqd_se_pre10", MQD_SE_PRE_GFX10())
    urow("amp_mqd_se_gfx10", MQD_SE_GFX10())
    urow("amp_mqd_walk_d0", MQD_WALK_DWORD0())
    urow("amp_mqd_header", MQD_HEADER())
    urow("amp_mqd_hq_status0", MQD_HQD_STATUS0())
    urow("amp_mqd_quantum", MQD_QUANTUM())
    urow("amp_mqd_scheduler0", SCHEDULER0())
    lrow("amp_mqd_pq_vals_none", mqd.pq_control(0, 0, 10, 0))
    lrow("amp_mqd_pq_vals_kiq", mqd.pq_control(1, 0, 10, 0))
    lrow("amp_mqd_pq_vals_aql", mqd.pq_control(0, 1, 10, 1))
    lrow("amp_mqd_pq_vals_both", mqd.pq_control(1, 1, 10, 1))
    lrow("amp_mqd_pq_vals_aql_noup0", mqd.pq_control(0, 1, 10, 0))
    urow("amp_mqd_pqbits_kiq", MQD_PQ_BITS_KIQ())
    urow("amp_mqd_pqbits_aql", MQD_PQ_BITS_AQL())
    lrow("amp_mqd_pq_bits", MQD_PQ_BIT_POS())
    urow("amp_mqd_eop_control_0", mqd.eop_control(0))
    urow("amp_mqd_eop_control_1", mqd.eop_control(1))


# ===========================================================================
# GATE 6: THE KIQ PM4 PACKET, :108-112. EIGHTEEN WORDS, IN ORDER.
# ===========================================================================
def t_kiq() -> IO(Unit):
  do IO<Unit>:
    urow("amp_pm4_type3", PM4_TYPE3())
    urow("amp_pm4_sel", PM4_PACKET3_WRITE_DATA())
    urow("amp_pm4_wait", PM4_PACKET3_WAIT_REG_MEM())
    lrow("amp_pm4_pkt3", PM4_PKT3_L())
    lrow("amp_pm4_wr", PM4_WR_L())
    lrow("amp_pm4_wr_dstsel", PM4_DST_L())
    urow("amp_pm4_write_data_3", pm4.write_data(3))
    urow("amp_pm4_write_data_0", pm4.write_data(0))
    urow("amp_pm4_write_data_300", pm4.write_data(300))
    urow("amp_pm4_wait_reg_mem_5", pm4.wait_reg_mem(5))
    urow("amp_pm4_wait_fn_eq", pm4.wait_fn_eq())
    lrow("amp_kiq_pkt_a", kiq.pkt(4100, 4104, 3, 305419896, KIQ_VA(), 0, 0))
    lrow("amp_kiq_pkt_b", kiq.pkt(4100, 4104, 0, 2271560481, KIQ_VA(), 12288, 1023))
    lrow("amp_kiq_pkt_c", kiq.pkt(0, 0, 7, 0, KIQ_VA(), 24576, 4095))
    urow("amp_kiq_pkt_n_a", U32.from_nat(List.length(&2, U32, kiq.pkt(4100, 4104, 3, 0, KIQ_VA(), 0, 0))))
    urow("amp_kiq_pkt_n_b", U32.from_nat(List.length(&2, U32, kiq.pkt(0, 0, 0, 0, KIQ_VA(), 0, 0))))
    urow("amp_kiq_pkt_n_c", U32.from_nat(List.length(&2, U32, kiq.pkt(0, 0, 0, 0, KIQ_VA(), 0, 0))))
    lrow("amp_kiq_wrap", KIQ_WRAP_L())
    urow("amp_kiq_win", KIQ_WIN())
    urow("amp_kiq_ptr_off", KIQ_PTR_OFF())
    urow("amp_kiq_fence_off", KIQ_FENCE_OFF())

# ===========================================================================
# GATE 7: THE IH ENTRY DECODE, :502-513 and :515-527.
# ===========================================================================
def t_ih() -> IO(Unit):
  do IO<Unit>:
    urow("amp_ih_ring_size", IH_RING_SIZE())
    urow("amp_ih_wrap", IH_WRAP())
    urow("amp_ih_rb_size", IH_RB_SIZE())
    urow("amp_ih_entry_words", IH_ENTRY_WORDS())
    srow2("amp_ih_names7", ih.names7())
    srow2("amp_ih_names4", ih.names4())
    lrow("amp_ih_fields", ih.field_tab())
    lrow("amp_ih_pos", IH_POS())
    urow("amp_ih_client_id_a", ih.get(IH_E_A(), 0))
    urow("amp_ih_source_id_a", ih.get(IH_E_A(), 1))
    urow("amp_ih_ring_id_a", ih.get(IH_E_A(), 2))
    urow("amp_ih_vmid_a", ih.get(IH_E_A(), 3))
    urow("amp_ih_vmid_type_a", ih.get(IH_E_A(), 4))
    urow("amp_ih_pasid_a", ih.get(IH_E_A(), 5))
    urow("amp_ih_nodeid_a", ih.get(IH_E_A(), 6))
    urow("amp_ih_ctx0_a", ih.get(IH_E_A(), 7))
    urow("amp_ih_ctx1_a", ih.get(IH_E_A(), 8))
    urow("amp_ih_ctx2_a", ih.get(IH_E_A(), 9))
    urow("amp_ih_ctx3_a", ih.get(IH_E_A(), 10))
    urow("amp_ih_client_id_b", ih.get(IH_E_B(), 0))
    urow("amp_ih_client_id_b2", ih.get(IH_E_B(), 0))
    urow("amp_ih_ctx0_b", ih.get(IH_E_B(), 7))
    urow("amp_ih_nodeid_b", ih.get(IH_E_B(), 6))
    urow("amp_ih_vmid_type_c", ih.get(IH_E_C(), 4))
    urow("amp_ih_pasid_c", ih.get(IH_E_C(), 5))
    urow("amp_ih_ctx0_c", ih.get(IH_E_C(), 7))
    srow2("amp_ih_skips", ih.skips())
    srow2("amp_ih_enc_names", ih.enc_names())
    srow2("amp_ih_err_names", ih.err_names())
    brow("amp_ih_enc_soc21_11", ih.enc.soc21(11))
    brow("amp_ih_enc_soc21_10", ih.enc.soc21(10))
    lrow("amp_ih_enc_bits", IH_ENC_BITS())
    lrow("amp_ih_err_bits", IH_ERR_BITS())
    lrow("amp_ih_err_reasm", IH_ERR_REASM())
    brow("amp_ih_is_err_2", ih.is_err_type(2))
    brow("amp_ih_is_err_1", ih.is_err_type(1))
    urow("amp_ih_aca_b61", ih.aca_bit61())
    urow("amp_ih_aca_b57", ih.aca_bit57())
    urow("amp_ih_aca_hwname", ih.aca_hwname_lo())
    urow("amp_ih_aca_mcatype", ih.aca_mcatype_lo())
    lrow("amp_ih_aca_unc", IH_ACA_UNC())
    lrow("amp_ih_aca_fields", IH_ACA_FIELDS())
    urow("amp_ih_aca_hi61", ih.aca_hi61())
    urow("amp_ih_aca_hi57", ih.aca_hi57())
    # :489/:503, the drain's two wrap arithmetic claims: the offset is
    # `wptr['offset'] % (ring_size // 4)` and the entry walk is `rptr + 8` mod the
#     same. They share the modulus and the two rows say so.
    lrow("amp_ih_drain", IH_DRAIN())

# ===========================================================================
# GATE 8: THE PSP PREDICATES AND THE COMMAND IDS, :611-755.
# ===========================================================================
def t_psp() -> IO(Unit):
  do IO<Unit>:
    urow("amp_psp_ring_size", PSP_RING_SIZE())
    urow("amp_psp_frame_dwords", PSP_FRAME_DWORDS())
    lrow("amp_psp_submit", psp.ring_submit(0))
    lrow("amp_psp_submit_16", psp.ring_submit(16))
    lrow("amp_psp_submit_48", psp.ring_submit(48))
    urow("amp_psp_pref_13_0_6", psp.reg_pref(13, 0, 6))
    urow("amp_psp_pref_14_0_0", psp.reg_pref(14, 0, 0))
    urow("amp_psp_pref_14_0_2", psp.reg_pref(14, 0, 2))
    lrow("amp_psp_sos_13_0_6", psp.sos_components(13, 0, 6))
    lrow("amp_psp_sos_14_0_2", psp.sos_components(14, 0, 2))
    urow("amp_psp_sos_last_13_0_6", psp.sos_last(13, 0, 6))
    urow("amp_psp_sos_last_14_0_2", psp.sos_last(14, 0, 2))
    lrow("amp_psp_tmr_13_0_6", PSP_TMR(13, 0, 6))
    lrow("amp_psp_tmr_13_0_10", PSP_TMR(13, 0, 10))
    lrow("amp_psp_tmr_13_0_14", PSP_TMR(13, 0, 14))
    lrow("amp_psp_tmr_14_0_2", PSP_TMR(14, 0, 2))
    lrow("amp_psp_tmr_14_0_3", PSP_TMR(14, 0, 3))
    lrow("amp_psp_tmr_13_0_12", PSP_TMR(13, 0, 12))
    urow("amp_psp_phys_0_0", psp.phys_or_zero(0, 4660))
    urow("amp_psp_phys_1_2", psp.phys_or_zero(1, 4660))
    urow("amp_psp_size_0_0", psp.size_or_zero(1024, 0))
    urow("amp_psp_size_1024_1", psp.size_or_zero(1024, 1))
    urow("amp_psp_rlc_9_4_3", psp.rlc_cmd(9, 4, 3))
    urow("amp_psp_rlc_11_0_0", psp.rlc_cmd(11, 0, 0))
    urow("amp_psp_rlc_12_0_0", psp.rlc_cmd(12, 0, 0))
    urow("amp_psp_cmd_loadipfw", GFX_CMD_ID_LOAD_IP_FW())
    urow("amp_psp_cmd_setuptmr", GFX_CMD_ID_SETUP_TMR())
    urow("amp_psp_cmd_loadtoc", GFX_CMD_ID_LOAD_TOC())
    urow("amp_psp_cmd_spatial", GFX_CMD_ID_SRIOV_SPATIAL_PART())
    urow("amp_psp_cmd_autoldrlc", GFX_CMD_ID_AUTOLOAD_RLC())
    urow("amp_psp_fw_reglist", GFX_FW_TYPE_REG_LIST())
    urow("amp_psp_toc_key", PSP_FW_TOC_KEY())
    urow("amp_psp_rl_key", PSP_FW_RL_KEY())
    urow("amp_psp_km_shift", PSP_RING_TYPE_KM_SHIFTED())
    urow("amp_psp_destroy_rings", GFX_CTRL_CMD_ID_DESTROY_RINGS())
    urow("amp_psp_sos_ready", PSP_SOS_READY_BIT())
    urow("amp_psp_ring_mask", PSP_RING_CREATED_MASK())
    urow("amp_psp_msg1_shift", PSP_MSG1_ADDR_SHIFT())

# ===========================================================================
# GATE 9: THE ONE REFUSAL, :588, AND `Tr`'s OWN INVARIANTS.
#
# `if self.adev.ip_ver[am.SDMA0_HWIP] >= (5,0,0) and idx > 0: raise RuntimeError(f"am
# {self.adev.devfmt}: sdma queue {idx} is not available")` is the ONLY `raise` in
# the file and it is TWO conjuncts, so the refusal is reachable on four fixtures
# and the two conjuncts are separate claims.
# ===========================================================================
# `sdma.setup.fail_at` IS :588: the refusal fires at ordinal 1 on both conjuncts and
# at ordinal 0 otherwise. It is the ONE `raise` in the file, and the two conjuncts
# are separate claims: `amp_refuse_fail_44_0_1` is 0 (below SDMA 5) and
# `amp_refuse_fail_50_0_0` is 0 (`idx == 0`).
def sdma.setup.fail_at(+sd0_0: U32, +sd0_1: U32, +sd0_2: U32, +idx: U32) -> U32:
  Bool.pick(U32, Bool.and(V.ge(sd0_0, sd0_1, sd0_2, 5, 0, 0), U32.is_gt(idx, 0)), 1, 0)

def sdma.setup(+sd0_0: U32, +sd0_1: U32, +sd0_2: U32, +idx: U32) -> Tr:
  Tr.fail_at(Tr.of(), sdma.setup.fail_at(sd0_0, sd0_1, sd0_2, idx))

# THE TRACE a `setup_ring` makes, in the order :595-606 write it: the
# `_MINOR_PTR_UPDATE` 1, the doorbell offset, the doorbell, `_MINOR_PTR_UPDATE` 0,
# `_RB_CNTL`, `_IB_CNTL`. `sdma.setup.tr` is that list and the REFUSAL truncates
# it, which is why the trace LENGTH is the row that sees :588.
def CALL_DBOFF() -> U32: 1
def CALL_ENABLE() -> U32: 2
def CALL_MINOR() -> U32: 3
def CALL_MINOR1() -> U32: 5
def CALL_IB() -> U32: 4

def DB_OFF_SHIFT() -> Nat: 1n

def sdma.setup.dboff(idx: U32, t: Tr) -> Tr:
  Tr.emit(CALL_DBOFF(), U32.shln(sdma.db(idx), DB_OFF_SHIFT()), t)

# :588 is the FIRST STATEMENT of `setup_ring`, so a refusing setup records
# NOTHING at all and `Tr.emit` is a no-op for every step below it. That is what
# makes `amp_refuse_n_*` the row that sees the raise: 6 when it does not fire and
# 0 when it does, and NOT 3 or 4.
def sdma.setup.step1(+sd0_0: U32, +sd0_1: U32, +sd0_2: U32, +idx: U32) -> Tr:
  Tr.emit(CALL_MINOR(), 0, Tr.refuse(Tr.fail_at(Tr.of(), sdma.setup.fail_at(sd0_0, sd0_1, sd0_2, idx))))

def sdma.setup.step2(idx: U32, t: Tr) -> Tr: sdma.setup.dboff(idx, t)
def sdma.setup.step3(idx: U32, t: Tr) -> Tr: Tr.emit(CALL_ENABLE(), sdma.db(idx), t)
def sdma.setup.step4(idx: U32, t: Tr) -> Tr: sdma.setup.dboff(idx, t)

def sdma.setup.step5(idx: U32, t: Tr) -> Tr: Tr.emit(CALL_MINOR1(), 0, t)

def sdma.setup.step6(idx: U32, t: Tr) -> Tr: Tr.emit(CALL_IB(), 0, t)

def sdma.setup.tr(+sd0_0: U32, +sd0_1: U32, +sd0_2: U32, +idx: U32) -> Tr:
  sdma.setup.step6(idx, sdma.setup.step5(idx,
    sdma.setup.step4(idx, sdma.setup.step3(idx,
      sdma.setup.step2(idx, sdma.setup.step1(sd0_0, sd0_1, sd0_2, idx))))))

def sdma.setup.keys.go(n: Nat, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: sdma.setup.keys.go(m, t, List.append(&2, U32, acc, [kk]))

def sdma.setup.keys(+cs: List<&2, Call>) -> List<&2, U32>:
  sdma.setup.keys.go(List.length(&2, Call, cs), cs, Nil{})

def sdma.setup.args.go(n: Nat, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa} <> t: sdma.setup.args.go(m, t,
          List.append(&2, U32, acc, [U32.add(U32.mul(kk, 1000), aa)]))

def sdma.setup.args(+cs: List<&2, Call>) -> List<&2, U32>:
  sdma.setup.args.go(List.length(&2, Call, cs), cs, Nil{})

def TR_AT(t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused, nth, at}: at

def t_refuse() -> IO(Unit):
  do IO<Unit>:
    urow("amp_refuse_fail_44_0_0", sdma.setup.fail_at(4, 4, 0, 0))
    urow("amp_refuse_fail_44_0_1", sdma.setup.fail_at(4, 4, 0, 1))
    urow("amp_refuse_fail_50_0_0", sdma.setup.fail_at(5, 0, 0, 0))
    urow("amp_refuse_fail_50_0_1", sdma.setup.fail_at(5, 0, 0, 1))
    urow("amp_refuse_fail_50_0_4", sdma.setup.fail_at(5, 0, 0, 4))
    urow("amp_refuse_fail_60_0_0", sdma.setup.fail_at(6, 0, 0, 0))
    urow("amp_refuse_fail_60_0_7", sdma.setup.fail_at(6, 0, 0, 7))
    urow("amp_refuse_n_44_0_1", Tr.seen(sdma.setup.tr(4, 4, 0, 1)))
    urow("amp_refuse_n_50_0_1", Tr.seen(sdma.setup.tr(5, 0, 0, 1)))
    urow("amp_refuse_n_50_0_0", Tr.seen(sdma.setup.tr(5, 0, 0, 0)))
    urow("amp_refuse_n_50_0_7", Tr.seen(sdma.setup.tr(5, 0, 0, 7)))
    urow("amp_refuse_n_44_0_0", Tr.seen(sdma.setup.tr(4, 4, 0, 0)))
    brow("amp_refuse_seen_50_0_1", Tr.refused(sdma.setup.tr(5, 0, 0, 1)))
    brow("amp_refuse_seen_44_0_1", Tr.refused(sdma.setup.tr(4, 4, 0, 1)))
    lrow("amp_refuse_args_50_0_1", Tr.args(CALL_ENABLE(), Tr.calls(sdma.setup.tr(5, 0, 0, 1))))
    lrow("amp_refuse_args_50_0_0", Tr.args(CALL_ENABLE(), Tr.calls(sdma.setup.tr(5, 0, 0, 0))))
    lrow("amp_refuse_order_50_0_0", sdma.setup.keys(Tr.calls(sdma.setup.tr(5, 0, 0, 0))))
    lrow("amp_refuse_pairs_50_0_0", sdma.setup.args(Tr.calls(sdma.setup.tr(5, 0, 0, 0))))
    urow("amp_refuse_ncalls_50_0_0", Tr.seen(sdma.setup.tr(5, 0, 0, 0)))
    urow("amp_refuse_at_50_0_0", TR_AT(sdma.setup.tr(5, 0, 0, 0)))
    # `Tr.has` needs a NON-REFUSING trace, so these four use `idx = 0`
    # (amp_refuse_n_50_0_0 is 6 and amp_refuse_n_50_0_1 is 0, which is the pair
    # that says idx=1 truncates). `amp_has_fwd` / `amp_has_rev` are the
    # ORDER rows and `amp_has_len0` / `amp_has_len6` pin the LENGTH, which is the
    # other thing `Tr.has` could be broken in.
    brow("amp_has_fwd", Tr.has(Tr.calls(sdma.setup.tr(5, 0, 0, 0)),
      [Call{CALL_MINOR(), 0}, Call{CALL_DBOFF(), 512}, Call{CALL_ENABLE(), 256}]))
    brow("amp_has_rev", Tr.has(Tr.calls(sdma.setup.tr(5, 0, 0, 0)),
      [Call{CALL_ENABLE(), 256}, Call{CALL_DBOFF(), 512}, Call{CALL_MINOR(), 0}]))
    brow("amp_has_len0", Tr.has(Tr.calls(sdma.setup.tr(5, 0, 0, 0)), Nil{}))
    brow("amp_has_len6", Tr.has(Tr.calls(sdma.setup.tr(5, 0, 0, 0)),
      [Call{CALL_MINOR(), 0}, Call{CALL_DBOFF(), 512}, Call{CALL_ENABLE(), 256},
       Call{CALL_DBOFF(), 512}, Call{CALL_MINOR1(), 0}, Call{CALL_IB(), 0}]))
    brow("amp_has_len6b", Tr.has(Tr.calls(sdma.setup.tr(5, 0, 0, 0)),
      [Call{CALL_MINOR(), 0}, Call{CALL_DBOFF(), 512}, Call{CALL_ENABLE(), 257},
       Call{CALL_DBOFF(), 512}, Call{CALL_MINOR1(), 0}, Call{CALL_IB(), 0}]))
    brow("amp_has_short", Tr.has(Tr.calls(sdma.setup.tr(5, 0, 0, 0)),
      [Call{CALL_MINOR(), 0}, Call{CALL_DBOFF(), 512}]))
    brow("amp_has_wrongarg", Tr.has(Tr.calls(sdma.setup.tr(5, 0, 0, 0)),
      [Call{CALL_MINOR(), 1}, Call{CALL_DBOFF(), 512}, Call{CALL_ENABLE(), 256}]))

# ===========================================================================
# `main` -- the gate, in the order the sections are written.
# ===========================================================================
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_regs()
    b : Unit <- t_structs()
    c : Unit <- t_smu()
    d : Unit <- t_pte()
    e : Unit <- t_db()
    f : Unit <- t_kiq()
    g : Unit <- t_ih()
    h : Unit <- t_psp()
    i : Unit <- t_refuse()
    IO.print("ip-done=1")

# ===========================================================================
# THE MUTATION TABLE. MEASURED, NOT ASSERTED.
#
# `rows MOVED` is the load-bearing column. A mutation that moves NOTHING is not a
# gate that passed; it is a measurement of what this gate CANNOT see, and it is
# reported here rather than closed by adding a row that encodes the bug.
#
# TWO HARNESSES, because "every rule" means two kinds of rule.
#   `.agents/slop/ip_mutate.sh` -- 45 LOGIC mutations, one per rule.
#   `.agents/slop/ip_sweep.py`  -- 369 LEAF perturbations, EXHAUSTIVE: every
#     numeric constant by one unit, and every generated register row twice, once
#     on its LINE and once on its FIELD NAME. No hand-picking, so the coverage
#     claim is a measurement rather than an assertion.
#
# THE LOGIC TABLE (42 of 45 move rows, 3 do not):
#   id   MOVED  what the edit claims
#   #   M01    8  gfx.db.is_kiq: `kiq_xcc != NO_XCC` becomes `!= 0`
#   M02   2  smu 13.0.15 message id
#   M03   1  pte.page.gfx10: the not-a-table arm returns the PDE twice
#   M04   4  pte.of.mt: the `uncached` arm dropped
#   M05   4  MTYPE_SHIFT_GFX12 54 -> 50
#   M06   2  PDE_BFS_SHIFT 59 -> 56
#   M07   2  PTE_FRAG_MASK 31 -> 255
#   M08   0  pte.rwe: the RWE union RE-ASSOCIATED (U32.or is commutative)
#   M09   3  the KIQ packet address `1 << 16` becomes `1 << 17`
#   M10   3  the sDMA doorbell `<< 1` becomes `<< 0`
#   M11   3  sdma.chan: pipe and queue swapped
#   M12   4  SDMA_ENGINE_STRIDE 10 -> 11
#   M13   3  DOORBELL_OFFSET_SCALE 2 -> 1
#   M14   5  the sdma entry `dev_inst*4 + col` has its operands swapped
#   M15   1  mqd.qsize inlined with the `sdma.rbsize` formula (the off-by-one one)
#   M16   3  mqd.bits: the zero case returns 1 instead of 0
#   M17   8  pm4.packet3: `sel` and `count` swapped in the two masked shifts
#   M18   5  PM4_DST_SEL_SHIFT 8 -> 16
#   M19   2  psp.sos_components: the `List.reverse` half applied
#   M20   2  the PSP fw-type quadruple: INTF/DBG pair transposed
#   M21   1  psp.boot_time_tmr: the 14.0.3 disjunct dropped
#   M22   0  smu.arch: the (13,0,7) and (13,0,10) disjuncts dropped
#   M23  10  ih.getbits: the in-word pair replaced by the RAW global pair
#   M24   1  ih.err.reasm: the HI half shifts LEFT instead of right
#   M25   1  ih.err_lo soc21 arm 24 -> 25
#   M26   1  DOORBELL_RANGE_SIZE 20 -> 21
#   M27   3  GFX_CMD_ID_AUTOLOAD_RLC 33 -> 32
#   M28  11  sdma.setup.fail_at: `idx > 0` becomes `idx >= 0`
#   M29  21  Tr.emit.go: the refusal arm returns the APPENDED list
#   M30  15  Tr.refuse.go: the refusal ordinal offset by one
#   M31   5  PSP_FRAME_DWORDS 16 -> 15
#   M32   3  psp.cmd_off: the frame advance +1
#   M33   2  SDMA_ENTRY_AID_STRIDE 4 -> 2
#   M34   2  gfx.q.queue: `idx mod 4` becomes `idx div 4`
#   M35   1  mqd.pq.aql: the no_update_rptr arm returns 1
#   M36   1  psp.reg_pref: the arch bound 14 -> 13
#   M37   1  pte.gfx9.is_pde: the PDB0 disjunct dropped
#   M38   3  pte.gfx9.is_bfs: VM_PDB1 becomes VM_PTB
#   M39   0  smu.has_mca: MCA_CNT -> GFX_RESET (lockstep columns)
#   M40   2  PSP_ADDR64: the low word replaced by the high word
#   M41   2  COMPANION of M39: MCA_CNT -> MODE1 (not lockstep)
#   M42  18  COMPANION of M22: the smu.arch 14-arm becomes 13
#   M43   9  COMPANION of M08: PTE_EXECUTABLE dropped from the RWE union
#   M44   3  kiq.pkt.wr_hi collapses onto the LOW half of the WR_CONFIRM address
#   M45   3  kiq.pkt.addr: the `+ 0x1010` fence offset dropped
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
# THE LEAF SWEEP (354 of 369 move rows, displacing 588 row positions):
#   CONST     139 constants perturbed,        133 move rows.
#   REG       115 register LINE perturbations, 115 move rows.
#   REG@name  115 register NAME perturbations, 106 move rows.
#
# 14 BLIND SPOTS SURVIVE, AND HERE THEY ARE:
#   1. NINE field-name swaps that move nothing, in `amp_reg_` order: 422, 430,
#      467, 467b, 493, 583, 689, 695, 699. MEASURED and EXPLAINED: each of those
#      rows shares its field name with its neighbour because the name is a Python
#      f-string -- `regCP_{cntl_reg}_CNTL`, `regIH_RB_CNTL{suf}`,
#      `{reg_pref}_64`, `regGRBM_SOFT_RESET` -- that two lines legitimately spell
#      the same way. The LINE perturbation moves on all 115 of 115, which is the
#      whole reason `Row` is keyed on `(ln, reg)` and not on the name alone.
#   2. FIVE constants that are used by code and reach no emitted row:
#      `IH_ERR_MID_MASK` and `IH_ERR_HI_MASK` are masked away by the reassembly
#      fixtures, `IH_ACA_MCATYPE_HI` by the ACA fixtures, `PQ_UNORD_DISPATCH_BIT`
#      by the KIQ/AQL pair, and `SMU_COL_MCA_CNT` is the lockstep column of M39.
#      A sixth, `MQD_SE_VALUE`, CANNOT be perturbed: it is `0xFFFFFFFF` and `+1`
#      is outside `U32`, so the type system refuses it.
#   3. The 46 unread constants the sweep found were DELETED, not reported. A def
#      with zero call sites is provably behaviour-preserving to remove, and all
#      three lanes re-verified byte-identical afterwards.
#
# WHAT THIS TABLE IS NOT. It does not cover the six WALLS, because a wall is by
# definition the part of `ip.py` this file does not contain, and there is nothing
# here to perturb.
