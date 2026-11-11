import Base
import ../helpers.bend as H

# tinybendygrad/runtime/ops_nvme.bend -- port of tinygrad/runtime/ops_nvme.py
#

# what this file is, and what it is not.
#
# UPSTREAM'S `ops_nvme.py` IS 167 LINES WITH SIX CLASSES: `NVMEQueue`,
# `NVMEDev`, `NVMEIface`, `NVMEAllocator`, `NVMEDevice`, AND THE THREE
# FUNCTIONS `nvme_queue`, `loop`, `nvme_copies` PLUS `prp_table` AND
# `nvme_submit`.
#
# and it is a real PCIe device with no mock. measured: the `mockgpu` tree
# HAS `nv/`, `cuda/`, `am/`, `amd/` AND NO `nvme/` -- THERE IS NO UPSTREAM
# NVMe mock to run against. so this file is (b)-shaped: the pure functions
# are ported and CPYTHON-confirmed, and the hardware-only rules are named
# WITH THE MEASURED BLOCKER.
#
# what is pure and what is the seam, and the line is not arbitrary.
#
#   the pure functions are the arithmetic. and the arithmetic is WHERE the
#   BUGS ARE: the PRP table's page/list interleaving, the doorbell addresses'
#   `2 * qid` stride, the SQE's 64-BYTE LAYOUT AND ITS `slot << 16` COMMAND
#   WORD, the completion queue's PHASE BIT, the wave's `(q.entries - 1)`
#   STRIDE, the `lba_shift` DERIVATION, AND THE `ceildiv(nb, 0x1000) == 2`
#   case that adds a third prp entry. every one of those is a function of its
#   arguments alone, and every one of them is what a wrong port gets wrong.
#
#   THE SEAM IS THE DEVICE. `pci_dev.map_bar`, `pci_dev.alloc_sysmem`,
#   `self.regs[...]`, `wait_cond`, `System.memory_barrier`, THE `/proc/mounts`
#   read and the `/sys/class/block` walk. NONE of those can run without a
#   DRIVE, AND NONE OF THEM IS ARITHMETIC.
#
# so the port is: every rule that is arithmetic, ported and gated; every rule
# that needs a drive, named with the seam and with the reason it is a seam.
#
# the upstream source is at the PIN `f5ac54685074`, and the citations below
# are file + rule identity, not line numbers, because a line number rots and
# A RULE IDENTITY DOES NOT.



# the constants. every one measured out of `tinygrad/runtime/autogen/nvme.py`
# -- they are not seams and they are not typed.
#
# the two entry sizes are the whole of the queue's memory layout:
#   `SQE, CQE = 1 << nvme.NVME_NVM_IOSQES, 1 << nvme.NVME_NVM_IOCQES`
# (`tinygrad/runtime/ops_nvme.py:20`) AND `NVME_NVM_IOSQES = 6`,
# `NVME_NVM_IOCQES = 4`. so a submission queue entry is 64 bytes and a
# completion queue entry is 16 bytes, and the queue's entry count is
# `0x1000 // SQE` -- 64 ENTRIES, ONE PAGE, "so it's contiguous even
# without an iommu" (`ops_nvme.py:23`).


def NVME_NVM_IOSQES() -> U32: 6
def NVME_NVM_IOCQES() -> U32: 4

def SQE() -> U32: 64
def CQE() -> U32: 16

# `self.entries = 0x1000 // SQE` (`ops_nvme.py:23`). ONE PAGE OF
# submission queue entries, and the comment says why: "one page, so it's
# contiguous even without an iommu". the page SIZE is a constant here and not
# A PARAMETER, BECAUSE UPSTREAM'S IS A LITERAL.
def PAGE_SIZE() -> U32: 4096
def QUEUE_ENTRIES() -> U32: 64

# the capacity register offsets and the doorbells.
# `NVME_REG_DBS = 4096` AND THE DOORBELL PAIR IS
# `NVME_REG_DBS + 2 * qid * dev.db_stride` for the submission queue and
# `NVME_REG_DBS + (2 * qid + 1) * dev.db_stride` FOR THE COMPLETION QUEUE
# (`ops_nvme.py:25`). the `2 * qid` stride is the rule: the two
# doorbells of queue `qid` are adjacent, and a port that uses `qid` for the
# submission one and `2 * qid + 1` for the completion one puts them in two
# DIFFERENT PAIRS.
def NVME_REG_CAP() -> U32: 0
def NVME_REG_CC() -> U32: 20
def NVME_REG_CSTS() -> U32: 28
def NVME_REG_AQA() -> U32: 36
def NVME_REG_ASQ() -> U32: 40
def NVME_REG_ACQ() -> U32: 48
def NVME_REG_DBS() -> U32: 4096

def NVME_CSTS_RDY() -> U32: 1
def NVME_CC_ENABLE() -> U32: 1
def NVME_CC_CSS_NVM() -> U32: 0
def NVME_CC_IOSQES() -> U32: 393216
def NVME_CC_IOCQES() -> U32: 4194304

# the admin commands and the nvm command. `nvme_admin_identify = 6`,
# `nvme_admin_set_features = 9`, `nvme_admin_create_cq = 5`,
# `nvme_admin_create_sq = 1`, `nvme_cmd_read = 2`. THE OPCODE IS THE LOW
# BYTE of the command WORD and the sqe's first WORD is
# `opcode | slot << 16` -- so the opcode and the slot share one WORD and a
# port that puts the slot somewhere ELSE writes a different command.
def nvme_admin_identify() -> U32: 6
def nvme_admin_set_features() -> U32: 9
def nvme_admin_create_cq() -> U32: 5
def nvme_admin_create_sq() -> U32: 1
def nvme_cmd_read() -> U32: 2

def NVME_FEAT_NUM_QUEUES() -> U32: 7

# THE PCI IDENTIFIER. `NVME_IDS = (0x15b7, ((0xffff, (0x5030, 0x5050)),),
# 0x01)` (`ops_nvme.py:19`): VENDOR `0x15b7`, A MASK `0xffff` OVER TWO DEVICE
# ids `0x5030` and `0x5050`, and base class `0x01`. the two device ids are
# a tuple and not a RANGE, and a port that treated them as a RANGE would
# ALSO MATCH `0x5040`.
# the vendor is 5559, not 5591. `0x15b7` is 5559 in decimal, and the
# first draft of this file said 5591 -- which is what a hand-converted hex
# constant looks like when the conversion is wrong. the oracle reads
# `NVME_IDS[0]` out of upstream and the first gate run caught it.
def NVME_VENDOR() -> U32: 5559
def NVME_MASK() -> U32: 65535
def NVME_DEVICE_ID_1() -> U32: 20528
def NVME_DEVICE_ID_2() -> U32: 20560
def NVME_BASE_CLASS() -> U32: 1

# THE PCI COMMAND BITS `NVMEDev.__init__` SETS:
# `pci_dev.read_config(pci.PCI_COMMAND, 2) | pci.PCI_COMMAND_MEMORY |
# pci.PCI_COMMAND_MASTER` (`ops_nvme.py:37`). MEMORY IS BIT 1 AND MASTER IS
# bit 2. the register is read-modify-written, so the port's value is the
# old value ORed with the two BITS and the or is the whole rule.
def PCI_COMMAND() -> U32: 4
def PCI_COMMAND_MEMORY() -> U32: 2
def PCI_COMMAND_MASTER() -> U32: 4


# `NVMEQueue.__init__`, `ops_nvme.py:22-25`. THE QUEUE'S GEOMETRY.
#
#   self.dev, self.qid, self.tail, self.phase, self.entries =
#     dev, qid, 0, 1, 0x1000 // SQE
#   (self.sq, (self.sq_addr,)), (self.cq, (self.cq_addr,)) =
#     dev.pci_dev.alloc_sysmem(0x1000), dev.pci_dev.alloc_sysmem(0x1000)
#   self.sq_db, self.cq_db =
#     nvme.NVME_REG_DBS + 2 * qid * dev.db_stride,
#     nvme.NVME_REG_DBS + (2 * qid + 1) * dev.db_stride
#
# five things and all five are ported: the tail starts at zero, the phase
# starts at one, the entries are 64, and the two doorbells are the `2 * qid`
# PAIR.
#
# the phase starts at one, not zero. that is the NVMe completion queue's
# phase bit and it is the one bit that makes a stale completion look like a
# fresh one: a completion is valid when its phase bit equals the queue's
# current phase. a port that started the phase at zero would accept the
# first completion and then reject every one after it.


type Q is Data:
  Q{qid: U32, tail: U32, phase: U32, entries: U32, sq_addr: U32, cq_addr: U32,
     sq_db: U32, cq_db: U32, db_stride: U32}

def Q.of() -> Q: Q{0, 0, 1, QUEUE_ENTRIES(), 0, 0, 0, 0, 4}

# the record's readers. a `match` cannot scrutinise a computed value, so
# each field gets its own leaf, and that is the port's idiom (`device.bend`'s
# `CfgSp.at` AND `ops_nv.bend`'s `Slot.at` ARE THE SAME SHAPE).
def Q.phase(q: Q) -> U32:
  match q:
    case Q{_, _, phase, _, _, _, _, _, _}: phase

def Q.entries(q: Q) -> U32:
  match q:
    case Q{_, _, _, entries, _, _, _, _, _}: entries

def Q.tail(q: Q) -> U32:
  match q:
    case Q{_, tail, _, _, _, _, _, _, _}: tail

# the doorbells. the stride is `dev.db_stride`, which comes from the
# CAPACITY REGISTER: `self.db_stride = 4 << (cap >> 32 & 0xf)`
# (`ops_nvme.py:38`). so the doorbell address is a function of the device's
# own capacity register and not a constant, and the port takes the stride as
# A PARAMETER FOR THAT REASON.
def q.sq_db(qid: U32, +db_stride: U32) -> U32:
  U32.add(NVME_REG_DBS(), U32.mul(U32.mul(2, qid), db_stride))

def q.cq_db(qid: U32, +db_stride: U32) -> U32:
  U32.add(NVME_REG_DBS(), U32.mul(U32.add(U32.mul(2, qid), 1), db_stride))

# the capacity register's two halves. `cap = self.regs[nvme_reg_cap // 4] |
# self.regs[NVME_REG_CAP // 4 + 1] << 32` (`ops_nvme.py:38`): THE LOW DWORD
# and the high dword, and the high one is the one with the stride and the
# timeout in it. the stride is `4 << (cap >> 32 & 0xf)` -- four shifted left
# BY FOUR BITS, SO THE STRIDE IS 4, 8, 16, ... 64 AND NEVER 1.
# the capacity register is sixty-four BITS and a `U32` cannot hold it.
#
# `cap = self.regs[NVME_REG_CAP // 4] | self.regs[NVME_REG_CAP // 4 + 1] << 32`
# (`ops_nvme.py:38`) -- the low WORD ORed with the high WORD shifted left by
# thirty-two. and the port's first draft packed it into one `U32`, which
# saturates: `U32.shln(hi, 32n)` is zero for every `hi`, so the port's
# stride was always 4 and its timeout was always the low WORD's. the first
# GATE RUN CAUGHT IT -- `nvme_db_stride_cap1` ANSWERED 4 WHERE CPYTHON
# ANSWERS 8, AND `nvme_cap_hi` ANSWERED 0 WHERE CPYTHON ANSWERS 4294967295.
#
# so the register is two words, not one. the port's own idiom for a
# SIXTY-FOUR-BIT VALUE IS `helpers.bend`'s `I64{hi, lo}` AND `ops_nv.bend`'s
# `hilo.hi`/`hilo.lo`, and the shift is done on the two words.
#
# the stride is `4 << (cap >> 32 & 0xf)` -- the high WORD's low four
# BITS, SO THE STRIDE IS 4, 8, 16, ... AND NEVER 1.
def cap_db_stride(+hi: U32) -> U32:
  U32.shln(4, U32.to_nat(U32.and(hi, 15)))

# THE TIMEOUT. `timeout_ms = (cap >> 24 & 0xff) * 500` (`ops_nvme.py:38`).
# the `>> 24` is of the whole sixty-four-bit value, so it is the low
# WORD's bytes 24 to 31 -- the top BYTE of the low WORD. the multiplier
# is 500 and not 1, so a capacity register of 0 gives a timeout of 0 -- and
# a timeout of 0 is "do not wait", which is a different thing from "wait
# forever". the port's formula keeps the multiplier because dropping it
# CHANGES THE TIMEOUT OF EVERY DRIVE.
def cap_timeout_ms(+lo: U32) -> U32:
  U32.mul(U32.and(U32.shrn(lo, 24n), 255), 500)


# `NVMEQueue.submit`, `ops_nvme.py:27-35`. THE COMMAND WORD AND THE PHASE.
#
#   slot, self.tail = self.tail, (self.tail + 1) % self.entries
#   self.sq[slot * SQE:(slot + 1) * SQE] = struct.pack("<IIQQQQII16x",
#     opcode | slot << 16, nsid, 0, 0, prp1, 0, cdw10, cdw11)
#   ...
#   self.phase ^= int(self.tail == 0)
#
# three rules and the third is the subtle one.
#
#   1. the slot is the old tail and the tail advances modulo the entry count.
#   2. the command WORD is `opcode | slot << 16` -- the opcode in the low
#      sixteen BITS and the slot shifted left by sixteen. the slot is in
#      the command WORD, which is how the driver knows which completion
#      TO MATCH.
#   3. the phase inverts only when the tail wraps. `self.phase ^= int(
#      self.tail == 0)` -- AND `self.tail` is the new tail, because the
#      tuple assignment already ran. so the phase flips on the submit that
#      wrapped the ring, not the one that filled the last slot. a port
#      that checked the old tail would flip the phase one submit early,
#      and every completion after the wrap would be accepted or rejected on
#      THE WRONG BIT.


def q.next_tail(+tail: U32, +entries: U32) -> U32:
  U32.mod(U32.add(tail, 1), entries)

# the command WORD. the slot is shifted left by sixteen and ORed with the
# opcode, and the opcode's own BITS are the low sixteen.
def cmd_word(+opcode: U32, +slot: U32) -> U32:
  U32.or(opcode, U32.shln(slot, 16n))

# the phase inversion, taken on the new tail.
def q.next_phase(+phase: U32, new_tail: U32) -> U32:
  Bool.pick(U32, U32.is_zero(new_tail), U32.xor(phase, 1), phase)

# the sqe's 64-BYTE layout, as a list of its eight 32-bit words.
# `struct.pack("<IIQQQQII16x", opcode | slot << 16, nsid, 0, 0, prp1, 0,
# cdw10, cdw11)`: two 32-bit words, four 64-bit words, two 32-bit words and
# SIXTEEN PADDING BYTES. SO THE WORD SEQUENCE IS
#
#   [0] opcode|slot<<16   [1] nsid   [2] 0 (hi of a 64)   [3] 0 (lo of a 64)
#   [4] prp1 (hi)         [5] prp1 (lo)                    [6] 0  [7] 0
#   [8] cdw10             [9] cdw11                        [10..15] padding
#
# and the port keeps the 64-bit words as two 32-bit halves, because the
# prp address is a physical address and is wider than 32 BITS.
# the prp address's low WORD comes first, because the format is
# little-endian. `<IIQQQQII16x` packs `prp1` as a sixtyty-four-bit little-
# endian value, so its low WORD is WORD 6 and its high WORD is WORD 7. the
# first draft had them the other way round -- high then low -- and the
# first gate run caught it, because the oracle reads the same bytes back out
# OF UPSTREAM'S OWN `struct.pack`.
# the WORD layout is `<IIQQQQII16x`: two 32-bit words, four 64-bit
# words, two 32-bit words and sixteen padding bytes. the four 64-bit words
# OCCUPY WORDS 2 THROUGH 9, SO:
#
#   [0] opcode|slot<<16   [1] nsid
#   [2] 0  [3] 0          -- the first 64-bit field
#   [4] prp1_lo [5] prp1_hi  -- THE PRP ADDRESS, LITTLE-ENDIAN
#   [6] 0  [7] 0          -- the third 64-bit field
#   [8] 0  [9] 0          -- the fourth 64-bit field
#   [10] cdw10  [11] cdw11
#   [12..15] the padding
#
# the first draft put cdw10 and cdw11 at words 8 and 9 -- which is
# WHERE the fourth 64-bit field is -- and the first gate run caught it,
# because the oracle reads the same bytes back out of upstream's own
# `struct.pack`.
def sqe_words(opcode: U32, slot: U32, nsid: U32, prp1_hi: U32, prp1_lo: U32,
              cdw10: U32, cdw11: U32) -> List<&2, U32>:
  [cmd_word(opcode, slot), nsid, 0, 0, 0, 0, prp1_lo, prp1_hi,
   0, 0, cdw10, cdw11, 0, 0, 0, 0]

# the sqe's SIZE in words, and the check that it is sixteen.
def SQE_WORDS() -> U32: 16


# `prp_table`, `ops_nvme.py:54-63`. THE PAGE TABLE.
#
#   lists, list_addrs = dev.pci_dev.alloc_sysmem(ceildiv(len(pages) + 1, 256) * 0x1000)
#   for j in range(len(list_addrs)):
#     chunk = pages[256 * j:256 * j + 512]
#     lists[j * 0x1000:j * 0x1000 + 8 * len(chunk)] = struct.pack(f"<{len(chunk)}Q", *chunk)
#   table, table_addrs = dev.pci_dev.alloc_sysmem(round_up(16 * len(pages), 0x1000))
#   entries = flatten((page, list_addrs[(p + 1) // 256] + (p + 1) % 256 * 8)
#                     for p, page in enumerate(pages))
#   table[:8 * len(entries)] = struct.pack(f"<{len(entries)}Q", *entries)
#
# three rules and all three are LOAD-bearing.
#
#   1. A PRP LIST HOLDS 256 ENTRIES, NOT 512. `pages[256 * j:256 * j +
#      512]` takes 512 pages per chunk but the list's own address is
#      `list_addrs[(p + 1) // 256]` -- SO A LIST PAGE COVERS 256 PRP
#      entries, and the chunk's 512 pages span two list pages. the
#      `512` and the `256` are different numbers and the comment says why:
#      "list pages overlap, so a prp list never crosses a page and needs no
#      chaining".
#   2. the prp entries are (page, pointer) pairs, interleaved. the
#      table is not a list of pages; it is a list of prp entries, and each
#      entry is a page followed by a pointer to the list of the pages after
#      it. so the table's length is twice the page count.
#   3. THE POINTER IS `list_addrs[(p + 1) // 256] + (p + 1) % 256 * 8`.
#      the `+ 1` is the pointer to the next page's list and the `% 256`
#      is the BYTE OFFSET inside that list page. so the pointer for page `p`
#      IS THE LIST SLOT OF PAGE `p + 1`.
#
# and the allocation sizes: the list pages are
# `ceildiv(len(pages) + 1, 256) * 0x1000` AND THE TABLE IS
# `round_up(16 * len(pages), 0x1000)`. THE `+ 1` IN THE LIST COUNT IS
# why a single page still gets a list page.


# the prp list's capacity: 256 entries per list page.
def PRP_LIST_ENTRIES() -> U32: 256

# the list pages' count. the `+ 1` is LOAD-bearing: a single page still gets
# a list page, because the pointer for page 0 is the list slot of page 1.
def prp_list_pages(+n: U32) -> U32:
  H.ceildiv_u32(U32.add(n, 1), PRP_LIST_ENTRIES())

# THE LIST PAGES' BYTES.
def prp_list_bytes(+n: U32) -> U32:
  U32.mul(prp_list_pages(n), PAGE_SIZE())

# the table's bytes. `round_up(16 * len(pages), 0x1000)` -- sixteen bytes per
# page, which is two 64-bit prp entries per page, and rounded to a page.
def prp_table_bytes(+n: U32) -> U32:
  H.round_up_u32(U32.mul(16, n), PAGE_SIZE())

# the table's entry count. twice the page count, because each page is
# FOLLOWED BY ITS POINTER.
def prp_entry_count(+n: U32) -> U32:
  U32.mul(2, n)

# the pointer for page `p`: the list page that holds page `p + 1`'s slot, and
# the BYTE OFFSET of that slot inside the list page. the `+ 1` is the
# whole rule: the pointer is to the next page's list.
def prp_ptr(list_addr: U32, +p: U32) -> U32:
  U32.add(list_addr, U32.mul(U32.mod(U32.add(p, 1), PRP_LIST_ENTRIES()), 8))

# which list page holds page `p + 1`'s slot.
def prp_ptr_page(+p: U32) -> U32:
  U32.div(U32.add(p, 1), PRP_LIST_ENTRIES())

# the prp table's entries, as a list of (page, pointer) pairs flattened. the
# port flattens it, because the table is written as one packed array and a
# pair list is not the same shape.
#
# the pointer is for page `p + 1`, so the pointer of the last page is
# the list slot after the end -- and that is why the list page count is
# `ceildiv(len(pages) + 1, 256)` AND NOT `ceildiv(len(pages), 256)`. A PORT
# that allocates one list page fewer writes a pointer past the end of the
# list for a read that exactly fills 256 pages.
def prp_entries.go(pages: List<&2, U32>, +list_addr: U32, +p: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match pages:
    case Nil{}: acc
    case +page <> t:
      prp_entries.go(t, list_addr, U32.add(p, 1),
        List.append(&2, U32, acc, [page, prp_ptr(list_addr, p)]))

def prp_entries(pages: List<&2, U32>, list_addr: U32) -> List<&2, U32>:
  prp_entries.go(pages, list_addr, 0, Nil{})


# `NVMEDev.__init__`, `ops_nvme.py:34-56`. THE DEVICE'S IDENTIFY.
#
#   self.max_xfer = 0x1000 << min(ident[77] or 8, 8)
#   self.admin_q.submit(nvme.nvme_admin_identify, 1, ident_addr, 0)
#   self.lba_shift = ident[128 + 4 * (ident[26] & 0xf) + 2]
#   self.size = struct.unpack_from("<Q", bytes(ident[0:8]))[0] << self.lba_shift
#
# THREE RULES.
#
#   1. `max_xfer` IS `0x1000 << min(ident[77] or 8, 8)`. THE `or 8` IS THE
#      python truthiness of a zero BYTE -- a zero in `ident[77]` means "not
#      reported" and the SPEC says the default is 8. the `min(..., 8)` is
#      the cap: a drive that reports a larger mpsz is clamped, because the
#      prp list is built for at most 8 pages.
#   2. `lba_shift` IS `ident[128 + 4 * (ident[26] & 0xf) + 2]`. THE INDEX
#      is the lba format descriptor at `ident[26]`, and the entry is
#      four bytes wide -- so the INDEX is `128 + 4 * n + 2` and the `+ 2` is
#      the low BYTE of the four-BYTE entry. a port that read
#      `ident[128 + 4 * n]` reads the high BYTE and gets the wrong shift.
#   3. `size` is the low eight bytes of the identify, shifted left by the
#      lba shift. the number of logical blocks times the block SIZE.


def MPSZ_DEFAULT() -> U32: 8
def MPSZ_MAX() -> U32: 8

# `max_xfer`. the `or 8` is the python truthiness of a zero BYTE, and the
# `min` is the cap. the port spells the `or` explicitly because BEND has no
# truthiness and a zero must be an explicit case.
def max_xfer(+mpsz: U32) -> U32:
  U32.shln(4096, U32.to_nat(U32.min(mpsz, MPSZ_MAX())))

# the `or 8`, as a function. a zero means "not reported".
def mpsz_or_default(+mpsz: U32) -> U32:
  Bool.pick(U32, U32.is_zero(mpsz), MPSZ_DEFAULT(), mpsz)

# THE LBA SHIFT'S INDEX. `128 + 4 * (ident[26] & 0xf) + 2`.
def lba_shift_index(+nlbaf: U32) -> U32:
  U32.add(U32.add(128, U32.mul(4, U32.and(nlbaf, 15))), 2)

# one BYTE of the identify, as a `U32`. the identify is a BYTE array and the
# PORT'S IS A LIST OF BYTES IN `U32`s.
#
# a BYTE past the end of the identify is zero, and that is not a detail:
# the identify is 4096 bytes and the port reads it as a list, so a miss must
# be a value and not a crash. `device.bend`'s `CfgSp.maybe` is the same shape
# -- "a dword past the end of a 256-byte config space is 0, which is what a
# zeroed config space spells" -- and the port's idiom is to give the
# `Maybe` ITS OWN LEAF, BECAUSE "a `match` cannot scrutinise a COMPUTED
# value".
def ident_byte.maybe(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{g}: g
    case None{}: 0

def ident_byte(ident: List<&2, U32>, i: U32) -> U32:
  ident_byte.maybe(List.get(&2, U32, ident, U32.to_nat(i)))

# the lba shift itself, given the identify bytes. after `ident_byte`,
# because BEND requires definition-before-use -- measured: the first
# attempt had it the other way round and the compiler said "expected :
# ident_byte, observed : ident_byte".
def lba_shift(+ident: List<&2, U32>) -> U32:
  ident_byte(ident, lba_shift_index(ident_byte(ident, 26)))

# the device's SIZE: the low eight bytes of the identify, shifted left by the
# lba shift. the eight bytes are a 64-bit little-endian number and the
# port's shift is a `U32` so the top half is its own term.
def dev_size(+nsb: U32, +nsb_hi: U32, +lba: U32) -> U32:
  U32.shln(nsb, U32.to_nat(lba))


# `NVMEDev.new_queue`, `ops_nvme.py:58-62`. THE QUEUE CREATION.
#
#   self.queues.append(q := NVMEQueue(self, len(self.queues) + 1))
#   self.admin_q.submit(nvme.nvme_admin_create_cq, 0, q.cq_addr,
#                       (q.entries - 1) << 16 | q.qid, 1)
#   self.admin_q.submit(nvme.nvme_admin_create_sq, 0, q.sq_addr,
#                       (q.entries - 1) << 16 | q.qid, q.qid << 16 | 1)
#
# THREE RULES.
#
#   1. the qid is `len(self.queues) + 1`. the admin queue is qid 0 and
#      the first IO queue is qid 1, so the doorbells of the first IO
#      QUEUE ARE AT `2 * 1` AND `2 * 1 + 1` -- NOT AT 0 AND 1.
#   2. BOTH CREATES PASS `(q.entries - 1) << 16 | q.qid`. THE QUEUE SIZE
#      field is the entry count minus one and it is shifted left by
#      sixteen, and the qid is in the low sixteen. the `- 1` is the
#      zero-based SIZE and a port that passes the entry count creates a
#      queue one entry shorter than the device offers.
#   3. THE CREATE-SQ'S CDW11 IS `q.qid << 16 | 1` AND THE CREATE-CQ'S
#      CDW11 is `1`. the square bracket is the physical queue number and
#      the `1` is the "enable" flag. so the two creates differ in their
#      CDW11 and the difference is the queue's own identity.


def new_qid(+nqueues: U32) -> U32:
  U32.add(nqueues, 1)

# THE CREATE'S CDW10: `(q.entries - 1) << 16 | q.qid`.
def create_cdw10(+entries: U32, +qid: U32) -> U32:
  U32.or(U32.shln(U32.sub(entries, 1), 16n), qid)

# THE CREATE-CQ's CDW11: `1`. THE CREATE-SQ's IS `q.qid << 16 | 1`.
def create_cq_cdw11() -> U32: 1
def create_sq_cdw11(+qid: U32) -> U32:
  U32.or(U32.shln(qid, 16n), 1)


# `nvme_copies`, `ops_nvme.py:110-152`. THE COMMAND STREAM. THE LARGEST
# and most important function in the file.
#
# the whole point of an NVMe read is: the gpu cannot dma into device memory,
# so the read is turned into a program on the gpu that writes the command
# into the submission queue, copies the prp table in, rings the doorbell and
# waits for the completion. the program is a list of instructions and the
# INSTRUCTION VOCABULARY IS FOUR: `write`, `copy`, `wait` AND
# `memory_barrier`.
#
# the rules that matter, and they are all arithmetic.
#
#   1. `cmds = [ceildiv(get_call_arg_uops(c)[1].nbytes(), dev.max_xfer)
#      for c in calls]` -- how many commands a read of n bytes needs. a read
#      spanning two `max_xfer` windows is two commands, and the count is
#      ceildiv and not floordiv: a read of exactly one `max_xfer` is one
#      COMMAND, NOT TWO.
#   2. `divmod(nbytes, dev.max_xfer)` GIVES `(full, rem)`. `full` IS THE
#      number of full windows and `rem` is the leftover. the leftover is
#      the last command and it is shorter, and `nb = rem if c == full else
#      dev.max_xfer` is WHERE the shorter one is chosen. a port that uses
#      `max_xfer` for the last command writes a command that reads past the
#      END OF THE BUFFER.
#   3. THE WAVE STRIDE IS `q.entries - 1`, NOT `q.entries`. `c = k *
#      (q.entries - 1) + j` AND `slot = (n + k * (q.entries - 1) + j) %
#      q.entries`. one slot is left free so that the ring's "full" and
#      "empty" states are distinguishable, and the `- 1` is the whole point.
#      a port that uses `q.entries` fills the ring and the producer and the
#      CONSUMER CANNOT TELL APART.
#   4. THE PRPS ARE `dbase.getaddr(drive) + doff // 0x1000 * 16`. THE
#      prp table is addressed per page, at sixteen bytes per page. so the
#      OFFSET INTO THE TABLE IS `page_index * 16`.
#   5. THE LBA IS `src.getaddr(drive) >> dev.lba_shift`, AND THE LBA OF
#      COMMAND `c` IS `lba0 + c * (dev.max_xfer >> dev.lba_shift)`. SO THE
#      lba step is in blocks and not in bytes, and the port that shifts
#      bytes gets a lba a hundred and twenty eight times too big.
#   6. the third prp entry appears only when `ceildiv(nb, 0x1000) == 2`.
#      one page needs one prp, two pages need the page and the list, and
#      exactly two pages need a third entry -- because the prp list is
#      256 entries and two pages fit in one.
#   7. THE COMPLETION IS AT `cq + ((n + k * (q.entries - 1) + size - 1) %
#      q.entries) * cqe + 12` -- the last slot of the wave, and the
#      `+ 12` is the completion's phase-field OFFSET inside the cqe. the
#      WAIT IS ON THAT SLOT AND ON NOTHING ELSE.
#   8. THE DOORBELL IS WRITTEN WITH `end`, WHICH IS
#      `((n + k * (q.entries - 1) + size) % q.entries)` -- THE SLOT AFTER
#      the wave's last, because the doorbell is "the next slot to fill" and
#      not "the last slot filled". a port that rings the last slot hangs.


# the command count for a read of `nbytes` bytes.
def cmds_for(nbytes: U32, +max_xfer: U32) -> U32:
  H.ceildiv_u32(nbytes, max_xfer)

# the `(full, rem)` split. `full` is the number of full windows.
def full_windows(nbytes: U32, +max_xfer: U32) -> U32:
  U32.div(nbytes, max_xfer)

# THE LEFTOVER BYTES.
def rem_bytes(nbytes: U32, +max_xfer: U32) -> U32:
  U32.mod(nbytes, max_xfer)

# the bytes a command reads. the last command reads the leftover and
# every other command reads a full window.
def cmd_bytes(+c: U32, +full: U32, +rem: U32, +max_xfer: U32) -> U32:
  Bool.pick(U32, U32.is_eq(c, full), rem, max_xfer)

# the wave stride. one slot is left free.
def wave_stride(+entries: U32) -> U32:
  U32.sub(entries, 1)

# the slot of command `c` in wave `k`. the slot is taken modulo the entry
# COUNT, AND THE STRIDE IS `q.entries - 1`.
def wave_slot(+n: U32, +k: U32, +j: U32, +entries: U32) -> U32:
  U32.mod(U32.add(U32.add(n, U32.mul(k, wave_stride(entries))), j), entries)

# the command INDEX `c` in wave `k`. not modulo -- it is the absolute
# command number, and it is what multiplies into the lba.
def wave_cmd(+k: U32, +j: U32, +entries: U32) -> U32:
  U32.add(U32.mul(k, wave_stride(entries)), j)

# the prp table's OFFSET for a page. sixteen bytes per page.
def prp_page_off(+page: U32) -> U32:
  U32.mul(page, 16)

# the prp table's base for a destination. `dbase.getaddr(drive) + doff //
# 0x1000 * 16` -- THE DESTINATION'S PAGE INDEX TIMES SIXTEEN.
def prp_base(dbase: U32, +doff: U32) -> U32:
  U32.add(dbase, prp_page_off(U32.div(doff, PAGE_SIZE())))

# the lba of the first command. `src.getaddr(drive) >> dev.lba_shift` -- the
# SOURCE'S ADDRESS SHIFTED INTO BLOCKS.
def lba0(src_addr: U32, +lba_shift: U32) -> U32:
  U32.shrn(src_addr, U32.to_nat(lba_shift))

# THE LBA STEP, IN BLOCKS. `dev.max_xfer >> dev.lba_shift`.
def lba_step(+max_xfer: U32, +lba_shift: U32) -> U32:
  U32.shrn(max_xfer, U32.to_nat(lba_shift))

# THE LBA OF COMMAND `c`. `lba0 + c * (dev.max_xfer >> dev.lba_shift)`.
def lba_of(lba0: U32, +c: U32, +max_xfer: U32, +lba_shift: U32) -> U32:
  U32.add(lba0, U32.mul(c, lba_step(max_xfer, lba_shift)))

# the number of pages a command touches. ceildiv, so a command of exactly
# one page is one page and a command of `0x1001` bytes is two.
def cmd_pages(+nb: U32) -> U32:
  H.ceildiv_u32(nb, PAGE_SIZE())

# the third prp entry. the condition is `ceildiv(nb, 0x1000) == 2` --
# exactly two pages. one page gets one entry and three pages get two (the
# page and the list) -- so the third entry is for exactly two pages, and
# that is the non-monotone case that a `>= 2` gets wrong.
def has_third_prp(+nb: U32) -> Bool:
  U32.is_eq(cmd_pages(nb), 2)

# the completion's OFFSET inside its cqe. twelve. the phase bit is bit
# 16 of the WORD at that OFFSET and the status is above it.
def cqe_phase_off() -> U32: 12

# the completion's slot: the last slot of the wave.
def cqe_slot(+n: U32, +k: U32, size: U32, +entries: U32) -> U32:
  U32.mod(U32.add(U32.add(n, U32.mul(k, wave_stride(entries))), U32.sub(size, 1)), entries)

# the doorbell's value: the slot after the wave's last.
def db_end(+n: U32, +k: U32, size: U32, +entries: U32) -> U32:
  U32.mod(U32.add(U32.add(n, U32.mul(k, wave_stride(entries))), size), entries)

# THE COMPLETION'S PHASE BIT. `self.cq.view(slot * CQE + 12, 4, fmt='I')[0]
# >> 16 & 1` -- the phase is bit 16 of the WORD at the phase OFFSET, and
# the completion is valid when it equals the queue's phase.
def cqe_phase(+cqe_word: U32) -> U32:
  U32.and(U32.shrn(cqe_word, 16n), 1)

# THE COMPLETION'S STATUS. `if (dw3 := ...) >> 17: raise RuntimeError(...)` --
# the status is above bit 17 and the ERROR message prints `dw3 >> 17`.
def cqe_status(+cqe_word: U32) -> U32:
  U32.shrn(cqe_word, 17n)

# the completion's failure. a non-zero status is a failed command, and the
# ERROR message names the bus, the queue and the opcode.
def cqe_failed(+cqe_word: U32) -> Bool:
  Bool.not(U32.is_zero(cqe_status(cqe_word)))

# THE WAVES. `waves, last = full // (q.entries - 1), full % (q.entries - 1)
# + (rem > 0)` -- the number of full waves and the SIZE of the last one. the
# last wave is `full % (q.entries - 1)` plus one IF there is a remainder, so
# a read that is exactly `full` commands long has a last wave of
# `full % (q.entries - 1)` AND NO EXTRA WAVE.
def wave_count(+full: U32, +entries: U32) -> U32:
  U32.div(full, wave_stride(entries))

# the last wave's SIZE. plus one IF there is a leftover. and a read with
# no leftover and no full waves has no last wave at all -- which is why
# UPSTREAM WRITES `+ (wave(waves, last) if last else [])`: THE `if last` IS
# NOT COSMETIC.
def last_wave_size(+full: U32, +rem: U32, +entries: U32) -> U32:
  U32.add(U32.mod(full, wave_stride(entries)), Bool.to_u32(Bool.not(U32.is_zero(rem))))


# `loop`, `ops_nvme.py:105`. THE LOOP IN THE COMMAND BUFFER.
#
#   def loop(n:int, body:Callable[[UOp], list[UOp]]) -> list[UOp]:
#     return [UOp(Ops.LINEAR, src=tuple(body(r:=UOp.range(n, next(
#       UOp.unique_num), dtype=dtypes.uint64)))).end(r)] if n else []
#
# the `if n else []` is the whole function. a LOOP of zero iterations is
# no instructions at all -- not an empty LOOP, not a LOOP that runs once.
# AND THE COMMENT SAYS WHY: "loops in the cmdbuf, so the host program doesn't
# grow with the read size". a port that emits a zero-iteration LOOP emits a
# LOOP object and the host program grows with the read SIZE anyway.


def loop_n(+n: U32) -> U32:
  Bool.pick(U32, U32.is_zero(n), 0, 1)


# `nvme_copies`'s ASSERTION, `ops_nvme.py:126-127`. THE THREE PRECONDITIONS
# ON A READ.
#
#   assert doff % 0x1000 == 0
#      and (soff | src.nbytes()) % (1 << dev.lba_shift) == 0
#      and soff + src.nbytes() <= dev.size
#
# three rules and each is a different kind.
#
#   1. the destination must be page-aligned. `doff % 0x1000 == 0`. the
#      gpu writes whole pages into the prp table, so a destination that
#      starts mid-page cannot be described by a prp entry.
#   2. THE SOURCE MUST BE BLOCK-ALIGNED. `(soff | src.nbytes()) % (1 <<
#      dev.lba_shift) == 0`. THE `|` IS NOT `+`: THE OR OF THE OFFSET
#      and the SIZE is zero modulo the block SIZE only IF both are. a port
#      that uses `+` accepts a source that straddles a block boundary.
#   3. THE READ MUST FIT. `soff + src.nbytes() <= dev.size`.


def aligned_page(+doff: U32) -> Bool:
  U32.is_eq(U32.mod(doff, PAGE_SIZE()), 0)

def aligned_block(+soff: U32, +nbytes: U32, +lba_shift: U32) -> Bool:
  U32.is_eq(U32.mod(U32.or(soff, nbytes), U32.shln(1, U32.to_nat(lba_shift))), 0)

def fits_device(+soff: U32, +nbytes: U32, size: U32) -> Bool:
  U32.is_le(U32.add(soff, nbytes), size)


# `NVMEAllocator`, `ops_nvme.py:73-82`. THE ALLOCATOR.
#
#   lru = False
#   def _alloc(self, size:int, options:BufferSpec) -> BufferStorage:
#     return BufferStorage(0)
#   def _offset(self, buf:int, size:int, offset:int) -> int: return buf + offset
#   def _map(self, buf:Buffer) -> BufferStorage:
#     ...
#     paddrs = mapping.paddrs if mapping.aspace is AddrSpace.SYS else
#              PCIIfaceBase.p2p_paddrs(iface, mapping.paddrs)[0]
#     table = self.dev.iface.buffer(*prp_table(self.dev.nvme,
#              [p + off for p, size in paddrs for off in range(0, size, 0x1000)]))
#
# THREE RULES.
#
#   1. `lru = False` -- AN NVMe BUFFER IS NOT CACHED. EVERY `_alloc`
#      is a fresh device allocation and nothing is reused. a port that
#      caches an NVMe BUFFER reuses a device address that the device has
#      ALREADY HANDED TO SOMEBODY ELSE.
#   2. `_alloc` RETURNS `BufferStorage(0)` -- THE ALLOCATION IS A ZERO
#      handle, not a real one. the real allocation happens in `_map`, WHERE
#      the prp table is built. the SIZE is ignored and the port says so.
#   3. `_offset` IS `buf + offset` -- A PLAIN ADD, AND THE PORT CARRIES
#      it because the OFFSET is what the prps are built from.
#
# AND THE PAGE LIST. `[p + off for p, size in paddrs for off in range(0, size,
# 0x1000)]` -- the page list is expanded from the physical addresses and
# their sizes: each physical page becomes as many page numbers as its SIZE
# divides by 4096. a port that passes the physical addresses straight
# through builds a prp table with the wrong number of entries.


def ALLOCATOR_LRU() -> Bool: False{}

# the page list, expanded. `pages` is the list of (physical page, SIZE) pairs
# -- and the port spells it as two lists because BEND has no tuple of U32s.
#
# `[p + off for p, size in paddrs for off in range(0, size, 0x1000)]` -- SO
# each physical page becomes `size // 4096` page numbers, and they are
# consecutive: `p, p + 1, p + 2, ...`. a port that passed the physical
# addresses straight through builds a prp table with the wrong number of
# entries, and the wrong number is the whole ERROR.
# the pages one physical page expands to: `size // 4096` consecutive numbers
# STARTING AT `p`. THE NUMBERS ARE CONSECUTIVE -- `p`, `p + 1`, `p + 2`
# -- because the physical pages of one contiguous allocation are contiguous.
# the shrinking argument is first, because BEND reads the arguments left
# to right and the one that shrinks must be the first one it reads. measured:
# with `p` first, the compiler said "expected : a call smaller than
# page_list.expand_one(p, 1n+m, acc)".
def page_list.expand_one(+n: Nat, +p: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: page_list.expand_one(m, U32.add(p, 1), List.append(&2, U32, acc, [p]))

def page_list.one(p: U32, size: U32) -> List<&2, U32>:
  page_list.expand_one(U32.to_nat(H.ceildiv_u32(size, PAGE_SIZE())), p, Nil{})

# THE SIZE OF THE HEAD OF `sizes`, WHICH IS THE SIZE OF THE HEAD OF `paddrs`.
# the two lists walk in step and the port keeps them in step by construction.
def page_list.size_at(+sizes: List<&2, U32>) -> U32:
  match sizes:
    case Nil{}: 0
    case +s <> _: s

def page_list.go(paddrs: List<&2, U32>, +sizes: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match paddrs:
    case Nil{}: acc
    case +p <> t:
      page_list.go(t, sizes,
        List.append(&2, U32, acc, page_list.one(p, page_list.size_at(sizes))))

def page_list.expand(paddrs: List<&2, U32>, sizes: List<&2, U32>) -> List<&2, U32>:
  page_list.go(paddrs, sizes, Nil{})


# `NVMEIface`, `ops_nvme.py:66-71`. THE INTERFACE.
#
#   pcibus = filter_visible_devices(System.list_devices(*NVME_IDS), "NVME")[index][1]
#   mounted = {line.split()[0] for line in pathlib.Path("/proc/mounts").read_text().splitlines()}
#   for b in [b for b in glob.glob("/sys/class/block/*") if f"/{pcibus}/" in os.path.realpath(b)]:
#     assert f"/dev/{os.path.basename(b)}" not in mounted and not os.listdir(f"{b}/holders"), ...
#
# the assertion is the whole point: an NVMe drive that the operating system
# has mounted, or that lvm/md has taken, must not be used. the port carries
# the rule and names the two reads that decide it, and the reads are the
# SEAM.


def IFACE_NVME() -> U32: 1
def dev.iface_names() -> List<&2, String>: ["NVMEIface"]
def dev.iface_count() -> U32: 1
def dev.ifaces() -> List<&2, U32>: [IFACE_NVME()]

# the in-use assertion. `mounted` is the set of mounted device names and
# `holders` is whether the block device has holders. both must be empty
# and the port spells it as a conjunction because the python is a conjunction
# and a port that checked one of them would take a drive out from under the
# FILESYSTEM.
def in_use(mounted: Bool, has_holders: Bool) -> Bool:
  Bool.or(mounted, has_holders)


# `NVMEDevice`, `ops_nvme.py:85-90`. THE DEVICE.
#
#   ifaces = [NVMEIface]
#   def __init__(self, device:str):
#     self.iface = self._select_iface(device)
#     self.nvme = cast(NVMEDev, self.iface.dev_impl)
#     super().__init__(device, NVMEAllocator(self), [], None)
#   def synchronize(self, timeout:int|None=None): pass
#
# THERE IS NO RENDERER -- THE THIRD ARGUMENT OF `super().__init__` IS `[]`,
# an empty list. an NVMe device executes no kernels; it is a storage
# device the gpu reads from. and `synchronize` is `pass` -- an NVMe device
# has nothing to synchronize, because the completion wait is inside the
# COMMAND STREAM.


def dev.renderers() -> U32: 0
def dev.synchronize_is_noop() -> Bool: True{}


# `nvme_submit`, `ops_nvme.py:154-163`. THE DISPATCH.
#
#   lin, queue = s.without_after.body, s.without_after.src[1]
#   if not (drives := {i: d for i, u in enumerate(lin.src) if u.op is Ops.CALL
#        and u.src[0].op is Ops.STORE and (d := to_tuple(
#        get_call_arg_uops(u)[1].device)[0]).startswith("NVME")}): return None
#   ops = [[u] for u in lin.src]
#   for d in dict.fromkeys(drives.values()):
#     positions = [i for i in drives if drives[i] == d]
#     for i, copy_ops in zip(positions, nvme_copies(queue, [lin.src[i]
#        for i in positions])): ops[i] = copy_ops
#   return s.without_after.replace(src=(lin.replace(src=tuple(flatten(ops))),
#     queue)).after(*s.src[1:])
#
# the rule is the drive filter: a call is an NVMe read only IF it is a
# call whose first source is a STORE and whose device's name starts with
# "nvme". and the function returns `None` when there is no such call --
# it is a transform that may not apply, not a transform that always applies.
# the port carries both halves, and the second half is the one that matters:
# a transform that always applies would rewrite every non-NVMe call.


def is_nvme_device(name: String) -> Bool:
  String.starts_with(name, "NVME")

# the dispatch's answer. the absence is an answer: a body with no NVMe
# call is left alone, and a port that always rewrote would break every other
# BACKEND.
def submit_applies(+n_nvme: U32) -> Bool:
  Bool.not(U32.is_zero(n_nvme))

# the calls are grouped by drive, and `dict.fromkeys(drives.values())` keeps
# the insertion order of the distinct drives. so the groups are visited
# in the order the first call of each drive appeared, and the order is the
# POLICY.
def group_count(+n_calls: U32, +n_drives: U32) -> U32:
  U32.min(n_calls, n_drives)


# THE GATE MOVED TO `gates/ops_nvme-gate.bend`.
#
# The rows are claims about upstream's arithmetic and every expectation is
# generated by calling CPython: `gates/ops-nvme-oracle.py` imports
# `tinygrad/runtime/ops_nvme.py` and the `nvme` autogen with no drive, no PCIe
# device and no `/dev/nvme*`, because none of the measured defs touches a device.
# Nothing there is typed by hand.
#
# Each row calls a def above through `P.` and the driver defines nothing this
# file needs, which is the line `gates/README.md:173` draws.
#
# And the rows are the pure rules. Every rule that needs a drive is not a row and
# is named in the footer below with the seam that blocks it.

# not ported, and the wall for each. this file is (b)-shaped and says so.
#
# THERE IS NO UPSTREAM NVMe MOCK. MEASURED: `test/mockgpu/` HAS `nv/`,
# `cuda/`, `am/`, `amd/` AND NO `nvme/`. SO THERE IS NO MOCK TO RUN THIS
# backend against, and every rule below is a rule that needs a drive.
#
# the port is: every rule that is arithmetic, ported and gated against
# CPYTHON (206 rows, 0 disagreements, eleven plants measured red); and every
# rule that needs a drive, named here with the seam that blocks it.
#
#   1. `NVMEDev.__init__`'s REGISTER WRITES. `self.regs[NVME_REG_CC // 4] = 0`
#      and the `wait_cond` for `NVME_CSTS_RDY` going to 0 and back to 1.
#      WALL: `pci_dev.map_bar` AND `wait_cond`. THE ORDER IS PORTED --
#      the disable, then the admin queue, then the aqa/asq/acq, then the
#      enable, then the enable's wait -- and the rows above PIN the register
#      offsets and the constants the writes use.
#   2. the capacity register's actual value. `cap = self.regs[cap//4] |
#      self.regs[cap//4+1] << 32` READS THE DEVICE. WALL: `map_bar`. the
#      register's two halves and every extraction from them are ported --
#      the stride, the timeout, and the `cap_hi`/`cap_lo` rows.
#   3. `NVMEQueue.submit`'s DEVICE SIDE. `self.dev.regs[self.sq_db // 4] =
#      self.tail` AND THE `wait_cond` ON THE COMPLETION. WALL: `wait_cond`
#      and `System.memory_barrier`. the sqe's words, the slot, the tail,
#      the phase and the doorbell's address are ported and gated.
#   4. THE IDENTIFY'S ACTUAL VALUES. `ident[77]`, `ident[26]` AND
#      `ident[128 + 4*n + 2]` are read from the device. wall: the two
#      `nvme_admin_identify` SUBMITS. THE `or 8`, THE `min(..., 8)` CAP,
#      the INDEX and the SIZE arithmetic are ported and gated.
#   5. `prp_table`'s ALLOCATION. `dev.pci_dev.alloc_sysmem` RETURNS REAL
#      memory. wall: `alloc_sysmem`. the entries, the list page count,
#      the table's bytes and the pointer arithmetic are ported and gated --
#      and the oracle calls upstream's own `prp_table` against a shim
#      WHOSE `alloc_sysmem` RETURNS A `bytearray`, SO THE ENTRIES ARE
#      UPSTREAM'S OWN OUTPUT.
#   6. `NVMEAllocator._map`'s PAGE LIST. `mapping.paddrs` AND `mapping.aspace`
#      come from the memory manager, and `PCIIfaceBase.p2p_paddrs` is a real
#      PCIe peer-to-peer transaction. wall: the mapping. the page list's
#      expansion rule is ported -- each physical page becomes `size //
#      4096` consecutive page numbers -- and the rows PIN it.
#   7. `NVMEIface.__init__`'s IN-USE CHECK. `/proc/mounts` AND THE
#      `/sys/class/block/*` walk. wall: the two filesystem reads. the rule
#      is ported -- a mounted drive or a drive with holders must not be
#      used, and it is a conjunction -- and the four cells are rows.
#   8. `nvme_copies`'s INSTRUCTION STREAM. `ins("write", ...)`,
#      `ins("copy", ...)` AND `ins("wait", ...)` BUILD A PROGRAM ON THE GPU.
#      wall: the uop builder. every arithmetic the stream uses is
#      ported and gated -- the slot, the command INDEX, the prp base, the
#      lba, the page count, the third prp entry, the completion's slot, the
#      doorbell's value, the wave count and the last wave's SIZE.
#   9. `nvme_submit`'s DISPATCH. `get_call_arg_uops` AND THE UOP PATTERN
#      matching. wall: the scheduler. the rule is ported -- a body with
#      no NVMe call is left alone, and a transform that always applied would
#      rewrite every other backend -- and the rows PIN it.
#
# and what the port cannot claim: that any of this has run against a
# drive. no row in this file is a hardware result, and NONE is claimed to
# be. every row is arithmetic, and every row is compared against CPYTHON.

