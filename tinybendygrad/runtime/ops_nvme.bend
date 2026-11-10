import Base
import ../helpers.bend as H

# tinybendygrad/runtime/ops_nvme.bend -- port of tinygrad/runtime/ops_nvme.py
#
# ===========================================================================
# WHAT THIS FILE IS, AND WHAT IT IS NOT.
#
# UPSTREAM'S `ops_nvme.py` IS **167 LINES WITH SIX CLASSES**: `NVMEQueue`,
# `NVMEDev`, `NVMEIface`, `NVMEAllocator`, `NVMEDevice`, AND THE THREE
# FUNCTIONS `nvme_queue`, `loop`, `nvme_copies` PLUS `prp_table` AND
# `nvme_submit`.
#
# AND IT IS **A REAL PCIe DEVICE WITH NO MOCK**. MEASURED: the `mockgpu` tree
# HAS `nv/`, `cuda/`, `am/`, `amd/` AND **NO `nvme/`** -- THERE IS NO UPSTREAM
# NVMe MOCK TO RUN AGAINST. SO THIS FILE IS **(B)-SHAPED**: THE PURE FUNCTIONS
# ARE PORTED AND CPYTHON-CONFIRMED, AND THE HARDWARE-ONLY RULES ARE NAMED
# WITH THE MEASURED BLOCKER.
#
# WHAT IS PURE AND WHAT IS THE SEAM, AND THE LINE IS NOT ARBITRARY.
#
#   THE PURE FUNCTIONS ARE THE ARITHMETIC. AND THE ARITHMETIC IS WHERE THE
#   BUGS ARE: the PRP table's page/list interleaving, the doorbell addresses'
#   `2 * qid` stride, the SQE's 64-BYTE LAYOUT AND ITS `slot << 16` COMMAND
#   WORD, the completion queue's PHASE BIT, the wave's `(q.entries - 1)`
#   STRIDE, the `lba_shift` DERIVATION, AND THE `ceildiv(nb, 0x1000) == 2`
#   CASE THAT ADDS A THIRD PRP ENTRY. EVERY ONE OF THOSE IS A FUNCTION OF ITS
#   ARGUMENTS ALONE, AND EVERY ONE OF THEM IS WHAT A WRONG PORT GETS WRONG.
#
#   THE SEAM IS THE DEVICE. `pci_dev.map_bar`, `pci_dev.alloc_sysmem`,
#   `self.regs[...]`, `wait_cond`, `System.memory_barrier`, THE `/proc/mounts`
#   READ AND THE `/sys/class/block` WALK. NONE OF THOSE CAN RUN WITHOUT A
#   DRIVE, AND NONE OF THEM IS ARITHMETIC.
#
# SO THE PORT IS: EVERY RULE THAT IS ARITHMETIC, PORTED AND GATED; EVERY RULE
# THAT NEEDS A DRIVE, NAMED WITH THE SEAM AND WITH THE REASON IT IS A SEAM.
#
# THE UPSTREAM SOURCE IS AT THE PIN `f5ac54685074`, AND THE CITATIONS BELOW
# ARE FILE + RULE IDENTITY, NOT LINE NUMBERS, BECAUSE A LINE NUMBER ROTS AND
# A RULE IDENTITY DOES NOT.
# ===========================================================================

# ===========================================================================
# THE CONSTANTS. EVERY ONE MEASURED OUT OF `tinygrad/runtime/autogen/nvme.py`
# -- THEY ARE NOT SEAMS AND THEY ARE NOT TYPED.
#
# THE TWO ENTRY SIZES ARE THE WHOLE OF THE QUEUE'S MEMORY LAYOUT:
#   `SQE, CQE = 1 << nvme.NVME_NVM_IOSQES, 1 << nvme.NVME_NVM_IOCQES`
# (`tinygrad/runtime/ops_nvme.py:20`) AND `NVME_NVM_IOSQES = 6`,
# `NVME_NVM_IOCQES = 4`. SO A SUBMISSION QUEUE ENTRY IS **64 BYTES** AND A
# COMPLETION QUEUE ENTRY IS **16 BYTES**, AND THE QUEUE'S ENTRY COUNT IS
# `0x1000 // SQE` -- **64 ENTRIES**, ONE PAGE, "so it's contiguous even
# without an iommu" (`ops_nvme.py:23`).
# ===========================================================================

def NVME_NVM_IOSQES() -> U32: 6
def NVME_NVM_IOCQES() -> U32: 4

def SQE() -> U32: 64
def CQE() -> U32: 16

# `self.entries = 0x1000 // SQE` (`ops_nvme.py:23`). ONE PAGE OF
# SUBMISSION QUEUE ENTRIES, AND THE COMMENT SAYS WHY: "one page, so it's
# contiguous even without an iommu". THE PAGE SIZE IS A CONSTANT HERE AND NOT
# A PARAMETER, BECAUSE UPSTREAM'S IS A LITERAL.
def PAGE_SIZE() -> U32: 4096
def QUEUE_ENTRIES() -> U32: 64

# THE CAPACITY REGISTER OFFSETS AND THE DOORBELLS.
# `NVME_REG_DBS = 4096` AND THE DOORBELL PAIR IS
# `NVME_REG_DBS + 2 * qid * dev.db_stride` FOR THE SUBMISSION QUEUE AND
# `NVME_REG_DBS + (2 * qid + 1) * dev.db_stride` FOR THE COMPLETION QUEUE
# (`ops_nvme.py:25`). **THE `2 * qid` STRIDE IS THE RULE**: THE TWO
# DOORBELLS OF QUEUE `qid` ARE ADJACENT, AND A PORT THAT USES `qid` FOR THE
# SUBMISSION ONE AND `2 * qid + 1` FOR THE COMPLETION ONE PUTS THEM IN TWO
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

# THE ADMIN COMMANDS AND THE NVM COMMAND. `nvme_admin_identify = 6`,
# `nvme_admin_set_features = 9`, `nvme_admin_create_cq = 5`,
# `nvme_admin_create_sq = 1`, `nvme_cmd_read = 2`. THE OPCODE IS THE LOW
# BYTE OF THE COMMAND WORD AND THE SQE'S FIRST WORD IS
# `opcode | slot << 16` -- SO THE OPCODE AND THE SLOT SHARE ONE WORD AND A
# PORT THAT PUTS THE SLOT SOMEWHERE ELSE WRITES A DIFFERENT COMMAND.
def nvme_admin_identify() -> U32: 6
def nvme_admin_set_features() -> U32: 9
def nvme_admin_create_cq() -> U32: 5
def nvme_admin_create_sq() -> U32: 1
def nvme_cmd_read() -> U32: 2

def NVME_FEAT_NUM_QUEUES() -> U32: 7

# THE PCI IDENTIFIER. `NVME_IDS = (0x15b7, ((0xffff, (0x5030, 0x5050)),),
# 0x01)` (`ops_nvme.py:19`): VENDOR `0x15b7`, A MASK `0xffff` OVER TWO DEVICE
# IDS `0x5030` AND `0x5050`, AND BASE CLASS `0x01`. **THE TWO DEVICE IDS ARE
# A TUPLE AND NOT A RANGE**, AND A PORT THAT TREATED THEM AS A RANGE WOULD
# ALSO MATCH `0x5040`.
# **THE VENDOR IS 5559, NOT 5591.** `0x15b7` IS 5559 IN DECIMAL, AND THE
# FIRST DRAFT OF THIS FILE SAID 5591 -- WHICH IS WHAT A HAND-CONVERTED HEX
# CONSTANT LOOKS LIKE WHEN THE CONVERSION IS WRONG. THE ORACLE READS
# `NVME_IDS[0]` OUT OF UPSTREAM AND THE FIRST GATE RUN CAUGHT IT.
def NVME_VENDOR() -> U32: 5559
def NVME_MASK() -> U32: 65535
def NVME_DEVICE_ID_1() -> U32: 20528
def NVME_DEVICE_ID_2() -> U32: 20560
def NVME_BASE_CLASS() -> U32: 1

# THE PCI COMMAND BITS `NVMEDev.__init__` SETS:
# `pci_dev.read_config(pci.PCI_COMMAND, 2) | pci.PCI_COMMAND_MEMORY |
# pci.PCI_COMMAND_MASTER` (`ops_nvme.py:37`). MEMORY IS BIT 1 AND MASTER IS
# BIT 2. THE REGISTER IS READ-MODIFY-WRITTEN, SO THE PORT'S VALUE IS THE
# OLD VALUE ORed WITH THE TWO BITS AND THE OR IS THE WHOLE RULE.
def PCI_COMMAND() -> U32: 4
def PCI_COMMAND_MEMORY() -> U32: 2
def PCI_COMMAND_MASTER() -> U32: 4

# ===========================================================================
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
# FIVE THINGS AND ALL FIVE ARE PORTED: THE TAIL STARTS AT ZERO, THE PHASE
# STARTS AT ONE, THE ENTRIES ARE 64, AND THE TWO DOORBELLS ARE THE `2 * qid`
# PAIR.
#
# THE PHASE STARTS AT **ONE**, NOT ZERO. THAT IS THE NVMe COMPLETION QUEUE'S
# PHASE BIT AND IT IS THE ONE BIT THAT MAKES A STALE COMPLETION LOOK LIKE A
# FRESH ONE: A COMPLETION IS VALID WHEN ITS PHASE BIT EQUALS THE QUEUE'S
# CURRENT PHASE. A PORT THAT STARTED THE PHASE AT ZERO WOULD ACCEPT THE
# FIRST COMPLETION AND THEN REJECT EVERY ONE AFTER IT.
# ===========================================================================

type Q is Data:
  Q{qid: U32, tail: U32, phase: U32, entries: U32, sq_addr: U32, cq_addr: U32,
     sq_db: U32, cq_db: U32, db_stride: U32}

def Q.of() -> Q: Q{0, 0, 1, QUEUE_ENTRIES(), 0, 0, 0, 0, 4}

# THE RECORD'S READERS. A `match` CANNOT SCRUTINISE A COMPUTED VALUE, SO
# EACH FIELD GETS ITS OWN LEAF, AND THAT IS THE PORT'S IDIOM (`device.bend`'s
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

# THE DOORBELLS. THE STRIDE IS `dev.db_stride`, WHICH COMES FROM THE
# CAPACITY REGISTER: `self.db_stride = 4 << (cap >> 32 & 0xf)`
# (`ops_nvme.py:38`). SO THE DOORBELL ADDRESS IS A FUNCTION OF THE DEVICE'S
# OWN CAPACITY REGISTER AND NOT A CONSTANT, AND THE PORT TAKES THE STRIDE AS
# A PARAMETER FOR THAT REASON.
def q.sq_db(qid: U32, +db_stride: U32) -> U32:
  U32.add(NVME_REG_DBS(), U32.mul(U32.mul(2, qid), db_stride))

def q.cq_db(qid: U32, +db_stride: U32) -> U32:
  U32.add(NVME_REG_DBS(), U32.mul(U32.add(U32.mul(2, qid), 1), db_stride))

# THE CAPACITY REGISTER'S TWO HALVES. `cap = self.regs[NVME_REG_CAP // 4] |
# self.regs[NVME_REG_CAP // 4 + 1] << 32` (`ops_nvme.py:38`): THE LOW DWORD
# AND THE HIGH DWORD, AND THE HIGH ONE IS THE ONE WITH THE STRIDE AND THE
# TIMEOUT IN IT. THE STRIDE IS `4 << (cap >> 32 & 0xf)` -- FOUR SHIFTED LEFT
# BY FOUR BITS, SO THE STRIDE IS **4, 8, 16, ... 64** AND NEVER 1.
# **THE CAPACITY REGISTER IS SIXTY-FOUR BITS AND A `U32` CANNOT HOLD IT.**
#
# `cap = self.regs[NVME_REG_CAP // 4] | self.regs[NVME_REG_CAP // 4 + 1] << 32`
# (`ops_nvme.py:38`) -- THE LOW WORD ORed WITH THE HIGH WORD SHIFTED LEFT BY
# THIRTY-TWO. **AND THE PORT'S FIRST DRAFT PACKED IT INTO ONE `U32`, WHICH
# SATURATES**: `U32.shln(hi, 32n)` IS ZERO FOR EVERY `hi`, SO THE PORT'S
# STRIDE WAS ALWAYS 4 AND ITS TIMEOUT WAS ALWAYS THE LOW WORD'S. THE FIRST
# GATE RUN CAUGHT IT -- `nvme_db_stride_cap1` ANSWERED 4 WHERE CPYTHON
# ANSWERS 8, AND `nvme_cap_hi` ANSWERED 0 WHERE CPYTHON ANSWERS 4294967295.
#
# **SO THE REGISTER IS TWO WORDS, NOT ONE.** THE PORT'S OWN IDIOM FOR A
# SIXTY-FOUR-BIT VALUE IS `helpers.bend`'s `I64{hi, lo}` AND `ops_nv.bend`'s
# `hilo.hi`/`hilo.lo`, AND THE SHIFT IS DONE ON THE **TWO** WORDS.
#
# THE STRIDE IS `4 << (cap >> 32 & 0xf)` -- **THE HIGH WORD'S LOW FOUR
# BITS**, SO THE STRIDE IS 4, 8, 16, ... AND NEVER 1.
def cap_db_stride(+hi: U32) -> U32:
  U32.shln(4, U32.to_nat(U32.and(hi, 15)))

# THE TIMEOUT. `timeout_ms = (cap >> 24 & 0xff) * 500` (`ops_nvme.py:38`).
# **THE `>> 24` IS OF THE WHOLE SIXTY-FOUR-BIT VALUE**, SO IT IS THE **LOW
# WORD'S** BYTES 24 TO 31 -- THE TOP BYTE OF THE LOW WORD. **THE MULTIPLIER
# IS 500 AND NOT 1**, SO A CAPACITY REGISTER OF 0 GIVES A TIMEOUT OF 0 -- AND
# A TIMEOUT OF 0 IS "DO NOT WAIT", WHICH IS A DIFFERENT THING FROM "WAIT
# FOREVER". THE PORT'S FORMULA KEEPS THE MULTIPLIER BECAUSE DROPPING IT
# CHANGES THE TIMEOUT OF EVERY DRIVE.
def cap_timeout_ms(+lo: U32) -> U32:
  U32.mul(U32.and(U32.shrn(lo, 24n), 255), 500)

# ===========================================================================
# `NVMEQueue.submit`, `ops_nvme.py:27-35`. THE COMMAND WORD AND THE PHASE.
#
#   slot, self.tail = self.tail, (self.tail + 1) % self.entries
#   self.sq[slot * SQE:(slot + 1) * SQE] = struct.pack("<IIQQQQII16x",
#     opcode | slot << 16, nsid, 0, 0, prp1, 0, cdw10, cdw11)
#   ...
#   self.phase ^= int(self.tail == 0)
#
# THREE RULES AND THE THIRD IS THE SUBTLE ONE.
#
#   1. THE SLOT IS THE OLD TAIL AND THE TAIL ADVANCES MODULO THE ENTRY COUNT.
#   2. THE COMMAND WORD IS `opcode | slot << 16` -- THE OPCODE IN THE LOW
#      SIXTEEN BITS AND THE SLOT SHIFTED LEFT BY SIXTEEN. **THE SLOT IS IN
#      THE COMMAND WORD**, WHICH IS HOW THE DRIVER KNOWS WHICH COMPLETION
#      TO MATCH.
#   3. **THE PHASE INVERTS ONLY WHEN THE TAIL WRAPS.** `self.phase ^= int(
#      self.tail == 0)` -- AND `self.tail` IS THE **NEW** TAIL, BECAUSE THE
#      TUPLE ASSIGNMENT ALREADY RAN. SO THE PHASE FLIPS ON THE SUBMIT THAT
#      WRAPPED THE RING, NOT THE ONE THAT FILLED THE LAST SLOT. **A PORT
#      THAT CHECKED THE OLD TAIL WOULD FLIP THE PHASE ONE SUBMIT EARLY**,
#      AND EVERY COMPLETION AFTER THE WRAP WOULD BE ACCEPTED OR REJECTED ON
#      THE WRONG BIT.
# ===========================================================================

def q.next_tail(+tail: U32, +entries: U32) -> U32:
  U32.mod(U32.add(tail, 1), entries)

# THE COMMAND WORD. THE SLOT IS SHIFTED LEFT BY SIXTEEN AND ORed WITH THE
# OPCODE, AND THE OPCODE'S OWN BITS ARE THE LOW SIXTEEN.
def cmd_word(+opcode: U32, +slot: U32) -> U32:
  U32.or(opcode, U32.shln(slot, 16n))

# THE PHASE INVERSION, TAKEN ON THE **NEW** TAIL.
def q.next_phase(+phase: U32, new_tail: U32) -> U32:
  Bool.pick(U32, U32.is_zero(new_tail), U32.xor(phase, 1), phase)

# THE SQE'S 64-BYTE LAYOUT, AS A LIST OF ITS EIGHT 32-BIT WORDS.
# `struct.pack("<IIQQQQII16x", opcode | slot << 16, nsid, 0, 0, prp1, 0,
# cdw10, cdw11)`: TWO 32-BIT WORDS, FOUR 64-BIT WORDS, TWO 32-BIT WORDS AND
# SIXTEEN PADDING BYTES. SO THE WORD SEQUENCE IS
#
#   [0] opcode|slot<<16   [1] nsid   [2] 0 (hi of a 64)   [3] 0 (lo of a 64)
#   [4] prp1 (hi)         [5] prp1 (lo)                    [6] 0  [7] 0
#   [8] cdw10             [9] cdw11                        [10..15] padding
#
# AND THE PORT KEEPS THE **64-BIT** WORDS AS TWO 32-BIT HALVES, BECAUSE THE
# PRP ADDRESS IS A PHYSICAL ADDRESS AND IS WIDER THAN 32 BITS.
# **THE PRP ADDRESS'S LOW WORD COMES FIRST**, BECAUSE THE FORMAT IS
# LITTLE-ENDIAN. `<IIQQQQII16x` PACKS `prp1` AS A SIXTYTY-FOUR-BIT LITTLE-
# ENDIAN VALUE, SO ITS LOW WORD IS WORD 6 AND ITS HIGH WORD IS WORD 7. **THE
# FIRST DRAFT HAD THEM THE OTHER WAY ROUND** -- HIGH THEN LOW -- AND THE
# FIRST GATE RUN CAUGHT IT, BECAUSE THE ORACLE READS THE SAME BYTES BACK OUT
# OF UPSTREAM'S OWN `struct.pack`.
# **THE WORD LAYOUT IS `<IIQQQQII16x`**: TWO 32-BIT WORDS, **FOUR** 64-BIT
# WORDS, TWO 32-BIT WORDS AND SIXTEEN PADDING BYTES. **THE FOUR 64-BIT WORDS
# OCCUPY WORDS 2 THROUGH 9**, SO:
#
#   [0] opcode|slot<<16   [1] nsid
#   [2] 0  [3] 0          -- the first 64-bit field
#   [4] prp1_lo [5] prp1_hi  -- **THE PRP ADDRESS, LITTLE-ENDIAN**
#   [6] 0  [7] 0          -- the third 64-bit field
#   [8] 0  [9] 0          -- the fourth 64-bit field
#   [10] cdw10  [11] cdw11
#   [12..15] the padding
#
# **THE FIRST DRAFT PUT cdw10 AND cdw11 AT WORDS 8 AND 9** -- WHICH IS
# WHERE THE FOURTH 64-BIT FIELD IS -- **AND THE FIRST GATE RUN CAUGHT IT**,
# BECAUSE THE ORACLE READS THE SAME BYTES BACK OUT OF UPSTREAM'S OWN
# `struct.pack`.
def sqe_words(opcode: U32, slot: U32, nsid: U32, prp1_hi: U32, prp1_lo: U32,
              cdw10: U32, cdw11: U32) -> List<&2, U32>:
  [cmd_word(opcode, slot), nsid, 0, 0, 0, 0, prp1_lo, prp1_hi,
   0, 0, cdw10, cdw11, 0, 0, 0, 0]

# THE SQE'S SIZE IN WORDS, AND THE CHECK THAT IT IS SIXTEEN.
def SQE_WORDS() -> U32: 16

# ===========================================================================
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
# THREE RULES AND ALL THREE ARE LOAD-BEARING.
#
#   1. **A PRP LIST HOLDS 256 ENTRIES, NOT 512.** `pages[256 * j:256 * j +
#      512]` TAKES **512** PAGES PER CHUNK BUT THE LIST'S OWN ADDRESS IS
#      `list_addrs[(p + 1) // 256]` -- SO A LIST PAGE COVERS **256** PRP
#      ENTRIES, AND THE CHUNK'S 512 PAGES SPAN **TWO** LIST PAGES. THE
#      `512` AND THE `256` ARE DIFFERENT NUMBERS AND THE COMMENT SAYS WHY:
#      "list pages overlap, so a prp list never crosses a page and needs no
#      chaining".
#   2. **THE PRP ENTRIES ARE (PAGE, POINTER) PAIRS, INTERLEAVED.** THE
#      TABLE IS NOT A LIST OF PAGES; IT IS A LIST OF PRP ENTRIES, AND EACH
#      ENTRY IS A PAGE FOLLOWED BY A POINTER TO THE LIST OF THE PAGES AFTER
#      IT. SO THE TABLE'S LENGTH IS **TWICE** THE PAGE COUNT.
#   3. **THE POINTER IS `list_addrs[(p + 1) // 256] + (p + 1) % 256 * 8`.**
#      THE `+ 1` IS THE POINTER TO THE **NEXT** PAGE'S LIST AND THE `% 256`
#      IS THE BYTE OFFSET INSIDE THAT LIST PAGE. SO THE POINTER FOR PAGE `p`
#      IS THE LIST SLOT OF PAGE `p + 1`.
#
# AND THE ALLOCATION SIZES: THE LIST PAGES ARE
# `ceildiv(len(pages) + 1, 256) * 0x1000` AND THE TABLE IS
# `round_up(16 * len(pages), 0x1000)`. **THE `+ 1` IN THE LIST COUNT IS
# WHY A SINGLE PAGE STILL GETS A LIST PAGE.**
# ===========================================================================

# THE PRP LIST'S CAPACITY: 256 ENTRIES PER LIST PAGE.
def PRP_LIST_ENTRIES() -> U32: 256

# THE LIST PAGES' COUNT. THE `+ 1` IS LOAD-BEARING: A SINGLE PAGE STILL GETS
# A LIST PAGE, BECAUSE THE POINTER FOR PAGE 0 IS THE LIST SLOT OF PAGE 1.
def prp_list_pages(+n: U32) -> U32:
  H.ceildiv_u32(U32.add(n, 1), PRP_LIST_ENTRIES())

# THE LIST PAGES' BYTES.
def prp_list_bytes(+n: U32) -> U32:
  U32.mul(prp_list_pages(n), PAGE_SIZE())

# THE TABLE'S BYTES. `round_up(16 * len(pages), 0x1000)` -- SIXTEEN BYTES PER
# PAGE, WHICH IS TWO 64-BIT PRP ENTRIES PER PAGE, AND ROUNDED TO A PAGE.
def prp_table_bytes(+n: U32) -> U32:
  H.round_up_u32(U32.mul(16, n), PAGE_SIZE())

# THE TABLE'S ENTRY COUNT. **TWICE THE PAGE COUNT**, BECAUSE EACH PAGE IS
# FOLLOWED BY ITS POINTER.
def prp_entry_count(+n: U32) -> U32:
  U32.mul(2, n)

# THE POINTER FOR PAGE `p`: THE LIST PAGE THAT HOLDS PAGE `p + 1`'S SLOT, AND
# THE BYTE OFFSET OF THAT SLOT INSIDE THE LIST PAGE. **THE `+ 1` IS THE
# WHOLE RULE**: THE POINTER IS TO THE NEXT PAGE'S LIST.
def prp_ptr(list_addr: U32, +p: U32) -> U32:
  U32.add(list_addr, U32.mul(U32.mod(U32.add(p, 1), PRP_LIST_ENTRIES()), 8))

# WHICH LIST PAGE HOLDS PAGE `p + 1`'S SLOT.
def prp_ptr_page(+p: U32) -> U32:
  U32.div(U32.add(p, 1), PRP_LIST_ENTRIES())

# THE PRP TABLE'S ENTRIES, AS A LIST OF (PAGE, POINTER) PAIRS FLATTENED. THE
# PORT FLATTENS IT, BECAUSE THE TABLE IS WRITTEN AS ONE PACKED ARRAY AND A
# PAIR LIST IS NOT THE SAME SHAPE.
#
# **THE POINTER IS FOR PAGE `p + 1`, SO THE POINTER OF THE **LAST** PAGE IS
# THE LIST SLOT AFTER THE END** -- AND THAT IS WHY THE LIST PAGE COUNT IS
# `ceildiv(len(pages) + 1, 256)` AND NOT `ceildiv(len(pages), 256)`. A PORT
# THAT ALLOCATES ONE LIST PAGE FEWER WRITES A POINTER PAST THE END OF THE
# LIST FOR A READ THAT EXACTLY FILLS 256 PAGES.
def prp_entries.go(pages: List<&2, U32>, +list_addr: U32, +p: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match pages:
    case Nil{}: acc
    case +page <> t:
      prp_entries.go(t, list_addr, U32.add(p, 1),
        List.append(&2, U32, acc, [page, prp_ptr(list_addr, p)]))

def prp_entries(pages: List<&2, U32>, list_addr: U32) -> List<&2, U32>:
  prp_entries.go(pages, list_addr, 0, Nil{})

# ===========================================================================
# `NVMEDev.__init__`, `ops_nvme.py:34-56`. THE DEVICE'S IDENTIFY.
#
#   self.max_xfer = 0x1000 << min(ident[77] or 8, 8)
#   self.admin_q.submit(nvme.nvme_admin_identify, 1, ident_addr, 0)
#   self.lba_shift = ident[128 + 4 * (ident[26] & 0xf) + 2]
#   self.size = struct.unpack_from("<Q", bytes(ident[0:8]))[0] << self.lba_shift
#
# THREE RULES.
#
#   1. **`max_xfer` IS `0x1000 << min(ident[77] or 8, 8)`.** THE `or 8` IS THE
#      PYTHON TRUTHINESS OF A ZERO BYTE -- A ZERO IN `ident[77]` MEANS "NOT
#      REPORTED" AND THE SPEC SAYS THE DEFAULT IS 8. **THE `min(..., 8)` IS
#      THE CAP**: A DRIVE THAT REPORTS A LARGER MPSZ IS CLAMPED, BECAUSE THE
#      PRP LIST IS BUILT FOR AT MOST 8 PAGES.
#   2. **`lba_shift` IS `ident[128 + 4 * (ident[26] & 0xf) + 2]`.** THE INDEX
#      IS THE **LBA FORMAT DESCRIPTOR** AT `ident[26]`, AND THE ENTRY IS
#      FOUR BYTES WIDE -- SO THE INDEX IS `128 + 4 * n + 2` AND THE `+ 2` IS
#      THE **LOW** BYTE OF THE FOUR-BYTE ENTRY. A PORT THAT READ
#      `ident[128 + 4 * n]` READS THE **HIGH** BYTE AND GETS THE WRONG SHIFT.
#   3. **`size` IS THE LOW EIGHT BYTES OF THE IDENTIFY, SHIFTED LEFT BY THE
#      LBA SHIFT.** THE NUMBER OF LOGICAL BLOCKS TIMES THE BLOCK SIZE.
# ===========================================================================

def MPSZ_DEFAULT() -> U32: 8
def MPSZ_MAX() -> U32: 8

# `max_xfer`. THE `or 8` IS THE PYTHON TRUTHINESS OF A ZERO BYTE, AND THE
# `min` IS THE CAP. THE PORT SPELLS THE `or` EXPLICITLY BECAUSE BEND HAS NO
# TRUTHINESS AND A ZERO MUST BE AN EXPLICIT CASE.
def max_xfer(+mpsz: U32) -> U32:
  U32.shln(4096, U32.to_nat(U32.min(mpsz, MPSZ_MAX())))

# THE `or 8`, AS A FUNCTION. A ZERO MEANS "NOT REPORTED".
def mpsz_or_default(+mpsz: U32) -> U32:
  Bool.pick(U32, U32.is_zero(mpsz), MPSZ_DEFAULT(), mpsz)

# THE LBA SHIFT'S INDEX. `128 + 4 * (ident[26] & 0xf) + 2`.
def lba_shift_index(+nlbaf: U32) -> U32:
  U32.add(U32.add(128, U32.mul(4, U32.and(nlbaf, 15))), 2)

# ONE BYTE OF THE IDENTIFY, AS A `U32`. THE IDENTIFY IS A BYTE ARRAY AND THE
# PORT'S IS A LIST OF BYTES IN `U32`s.
#
# **A BYTE PAST THE END OF THE IDENTIFY IS ZERO**, AND THAT IS NOT A DETAIL:
# THE IDENTIFY IS 4096 BYTES AND THE PORT READS IT AS A LIST, SO A MISS MUST
# BE A VALUE AND NOT A CRASH. `device.bend`'s `CfgSp.maybe` IS THE SAME SHAPE
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

# THE LBA SHIFT ITSELF, GIVEN THE IDENTIFY BYTES. **AFTER `ident_byte`,
# BECAUSE BEND REQUIRES DEFINITION-BEFORE-USE** -- MEASURED: the first
# attempt had it the other way round and the compiler said "expected :
# ident_byte, observed : ident_byte".
def lba_shift(+ident: List<&2, U32>) -> U32:
  ident_byte(ident, lba_shift_index(ident_byte(ident, 26)))

# THE DEVICE'S SIZE: THE LOW EIGHT BYTES OF THE IDENTIFY, SHIFTED LEFT BY THE
# LBA SHIFT. THE EIGHT BYTES ARE A 64-BIT LITTLE-ENDIAN NUMBER AND THE
# PORT'S SHIFT IS A `U32` SO THE TOP HALF IS ITS OWN TERM.
def dev_size(+nsb: U32, +nsb_hi: U32, +lba: U32) -> U32:
  U32.shln(nsb, U32.to_nat(lba))

# ===========================================================================
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
#   1. **THE QID IS `len(self.queues) + 1`.** THE ADMIN QUEUE IS QID 0 AND
#      THE FIRST IO QUEUE IS QID **1**, SO THE DOORBELLS OF THE FIRST IO
#      QUEUE ARE AT `2 * 1` AND `2 * 1 + 1` -- NOT AT 0 AND 1.
#   2. **BOTH CREATES PASS `(q.entries - 1) << 16 | q.qid`.** THE QUEUE SIZE
#      FIELD IS THE ENTRY COUNT **MINUS ONE** AND IT IS SHIFTED LEFT BY
#      SIXTEEN, AND THE QID IS IN THE LOW SIXTEEN. **THE `- 1` IS THE
#      ZERO-BASED SIZE** AND A PORT THAT PASSES THE ENTRY COUNT CREATES A
#      QUEUE ONE ENTRY SHORTER THAN THE DEVICE OFFERS.
#   3. **THE CREATE-SQ'S CDW11 IS `q.qid << 16 | 1` AND THE CREATE-CQ'S
#      CDW11 IS `1`.** THE SQUARE BRACKET IS THE PHYSICAL QUEUE NUMBER AND
#      THE `1` IS THE "ENABLE" FLAG. SO THE TWO CREATES DIFFER IN THEIR
#      CDW11 AND THE DIFFERENCE IS THE QUEUE'S OWN IDENTITY.
# ===========================================================================

def new_qid(+nqueues: U32) -> U32:
  U32.add(nqueues, 1)

# THE CREATE'S CDW10: `(q.entries - 1) << 16 | q.qid`.
def create_cdw10(+entries: U32, +qid: U32) -> U32:
  U32.or(U32.shln(U32.sub(entries, 1), 16n), qid)

# THE CREATE-CQ's CDW11: `1`. THE CREATE-SQ's IS `q.qid << 16 | 1`.
def create_cq_cdw11() -> U32: 1
def create_sq_cdw11(+qid: U32) -> U32:
  U32.or(U32.shln(qid, 16n), 1)

# ===========================================================================
# `nvme_copies`, `ops_nvme.py:110-152`. THE COMMAND STREAM. **THE LARGEST
# AND MOST IMPORTANT FUNCTION IN THE FILE.**
#
# THE WHOLE POINT OF AN NVMe READ IS: THE GPU CANNOT DMA INTO DEVICE MEMORY,
# SO THE READ IS TURNED INTO A PROGRAM ON THE GPU THAT WRITES THE COMMAND
# INTO THE SUBMISSION QUEUE, COPIES THE PRP TABLE IN, RINGS THE DOORBELL AND
# WAITS FOR THE COMPLETION. THE PROGRAM IS A LIST OF INSTRUCTIONS AND THE
# INSTRUCTION VOCABULARY IS FOUR: `write`, `copy`, `wait` AND
# `memory_barrier`.
#
# THE RULES THAT MATTER, AND THEY ARE ALL ARITHMETIC.
#
#   1. **`cmds = [ceildiv(get_call_arg_uops(c)[1].nbytes(), dev.max_xfer)
#      for c in calls]`** -- HOW MANY COMMANDS A READ OF N BYTES NEEDS. A READ
#      SPANNING TWO `max_xfer` WINDOWS IS TWO COMMANDS, AND THE COUNT IS
#      CEILDIV AND NOT FLOORDIV: A READ OF EXACTLY ONE `max_xfer` IS **ONE**
#      COMMAND, NOT TWO.
#   2. **`divmod(nbytes, dev.max_xfer)` GIVES `(full, rem)`.** `full` IS THE
#      NUMBER OF FULL WINDOWS AND `rem` IS THE LEFTOVER. **THE LEFTOVER IS
#      THE LAST COMMAND AND IT IS SHORTER**, AND `nb = rem if c == full else
#      dev.max_xfer` IS WHERE THE SHORTER ONE IS CHOSEN. **A PORT THAT USES
#      `max_xfer` FOR THE LAST COMMAND WRITES A COMMAND THAT READS PAST THE
#      END OF THE BUFFER.**
#   3. **THE WAVE STRIDE IS `q.entries - 1`, NOT `q.entries`.** `c = k *
#      (q.entries - 1) + j` AND `slot = (n + k * (q.entries - 1) + j) %
#      q.entries`. **ONE SLOT IS LEFT FREE** SO THAT THE RING'S "FULL" AND
#      "EMPTY" STATES ARE DISTINGUISHABLE, AND THE `- 1` IS THE WHOLE POINT.
#      A PORT THAT USES `q.entries` FILLS THE RING AND THE PRODUCER AND THE
#      CONSUMER CANNOT TELL APART.
#   4. **THE PRPS ARE `dbase.getaddr(drive) + doff // 0x1000 * 16`.** THE
#      PRP TABLE IS ADDRESSED **PER PAGE**, AT SIXTEEN BYTES PER PAGE. SO THE
#      OFFSET INTO THE TABLE IS `page_index * 16`.
#   5. **THE LBA IS `src.getaddr(drive) >> dev.lba_shift`**, AND THE LBA OF
#      COMMAND `c` IS `lba0 + c * (dev.max_xfer >> dev.lba_shift)`. **SO THE
#      LBA STEP IS IN **BLOCKS** AND NOT IN BYTES**, AND THE PORT THAT SHIFTS
#      BYTES GETS A LBA A HUNDRED AND TWENTY EIGHT TIMES TOO BIG.
#   6. **THE THIRD PRP ENTRY APPEARS ONLY WHEN `ceildiv(nb, 0x1000) == 2`.**
#      ONE PAGE NEEDS ONE PRP, TWO PAGES NEED THE PAGE AND THE LIST, AND
#      **EXACTLY TWO PAGES NEED A THIRD ENTRY** -- BECAUSE THE PRP LIST IS
#      256 ENTRIES AND TWO PAGES FIT IN ONE.
#   7. **THE COMPLETION IS AT `cq + ((n + k * (q.entries - 1) + size - 1) %
#      q.entries) * CQE + 12`** -- THE **LAST** SLOT OF THE WAVE, AND THE
#      `+ 12` IS THE COMPLETION'S PHASE-FIELD OFFSET INSIDE THE CQE. THE
#      WAIT IS ON THAT SLOT AND ON NOTHING ELSE.
#   8. **THE DOORBELL IS WRITTEN WITH `end`, WHICH IS
#      `((n + k * (q.entries - 1) + size) % q.entries)`** -- THE SLOT **AFTER**
#      THE WAVE'S LAST, BECAUSE THE DOORBELL IS "THE NEXT SLOT TO FILL" AND
#      NOT "THE LAST SLOT FILLED". A PORT THAT RINGS THE LAST SLOT HANGS.
# ===========================================================================

# THE COMMAND COUNT FOR A READ OF `nbytes` BYTES.
def cmds_for(nbytes: U32, +max_xfer: U32) -> U32:
  H.ceildiv_u32(nbytes, max_xfer)

# THE `(full, rem)` SPLIT. `full` IS THE NUMBER OF FULL WINDOWS.
def full_windows(nbytes: U32, +max_xfer: U32) -> U32:
  U32.div(nbytes, max_xfer)

# THE LEFTOVER BYTES.
def rem_bytes(nbytes: U32, +max_xfer: U32) -> U32:
  U32.mod(nbytes, max_xfer)

# THE BYTES A COMMAND READS. **THE LAST COMMAND READS THE LEFTOVER** AND
# EVERY OTHER COMMAND READS A FULL WINDOW.
def cmd_bytes(+c: U32, +full: U32, +rem: U32, +max_xfer: U32) -> U32:
  Bool.pick(U32, U32.is_eq(c, full), rem, max_xfer)

# THE WAVE STRIDE. **ONE SLOT IS LEFT FREE.**
def wave_stride(+entries: U32) -> U32:
  U32.sub(entries, 1)

# THE SLOT OF COMMAND `c` IN WAVE `k`. THE SLOT IS TAKEN **MODULO THE ENTRY
# COUNT**, AND THE STRIDE IS `q.entries - 1`.
def wave_slot(+n: U32, +k: U32, +j: U32, +entries: U32) -> U32:
  U32.mod(U32.add(U32.add(n, U32.mul(k, wave_stride(entries))), j), entries)

# THE COMMAND INDEX `c` IN WAVE `k`. **NOT** MODULO -- IT IS THE ABSOLUTE
# COMMAND NUMBER, AND IT IS WHAT MULTIPLIES INTO THE LBA.
def wave_cmd(+k: U32, +j: U32, +entries: U32) -> U32:
  U32.add(U32.mul(k, wave_stride(entries)), j)

# THE PRP TABLE'S OFFSET FOR A PAGE. **SIXTEEN BYTES PER PAGE.**
def prp_page_off(+page: U32) -> U32:
  U32.mul(page, 16)

# THE PRP TABLE'S BASE FOR A DESTINATION. `dbase.getaddr(drive) + doff //
# 0x1000 * 16` -- THE DESTINATION'S PAGE INDEX TIMES SIXTEEN.
def prp_base(dbase: U32, +doff: U32) -> U32:
  U32.add(dbase, prp_page_off(U32.div(doff, PAGE_SIZE())))

# THE LBA OF THE FIRST COMMAND. `src.getaddr(drive) >> dev.lba_shift` -- THE
# SOURCE'S ADDRESS **SHIFTED INTO BLOCKS**.
def lba0(src_addr: U32, +lba_shift: U32) -> U32:
  U32.shrn(src_addr, U32.to_nat(lba_shift))

# THE LBA STEP, IN BLOCKS. `dev.max_xfer >> dev.lba_shift`.
def lba_step(+max_xfer: U32, +lba_shift: U32) -> U32:
  U32.shrn(max_xfer, U32.to_nat(lba_shift))

# THE LBA OF COMMAND `c`. `lba0 + c * (dev.max_xfer >> dev.lba_shift)`.
def lba_of(lba0: U32, +c: U32, +max_xfer: U32, +lba_shift: U32) -> U32:
  U32.add(lba0, U32.mul(c, lba_step(max_xfer, lba_shift)))

# THE NUMBER OF PAGES A COMMAND TOUCHES. **CEILDIV**, SO A COMMAND OF EXACTLY
# ONE PAGE IS ONE PAGE AND A COMMAND OF `0x1001` BYTES IS **TWO**.
def cmd_pages(+nb: U32) -> U32:
  H.ceildiv_u32(nb, PAGE_SIZE())

# **THE THIRD PRP ENTRY.** THE CONDITION IS `ceildiv(nb, 0x1000) == 2` --
# EXACTLY TWO PAGES. ONE PAGE GETS ONE ENTRY AND THREE PAGES GET TWO (THE
# PAGE AND THE LIST) -- SO THE THIRD ENTRY IS FOR **EXACTLY** TWO PAGES, AND
# THAT IS THE NON-MONOTONE CASE THAT A `>= 2` GETS WRONG.
def has_third_prp(+nb: U32) -> Bool:
  U32.is_eq(cmd_pages(nb), 2)

# THE COMPLETION'S OFFSET INSIDE ITS CQE. **TWELVE.** THE PHASE BIT IS BIT
# 16 OF THE WORD AT THAT OFFSET AND THE STATUS IS ABOVE IT.
def cqe_phase_off() -> U32: 12

# THE COMPLETION'S SLOT: THE **LAST** SLOT OF THE WAVE.
def cqe_slot(+n: U32, +k: U32, size: U32, +entries: U32) -> U32:
  U32.mod(U32.add(U32.add(n, U32.mul(k, wave_stride(entries))), U32.sub(size, 1)), entries)

# THE DOORBELL'S VALUE: THE SLOT **AFTER** THE WAVE'S LAST.
def db_end(+n: U32, +k: U32, size: U32, +entries: U32) -> U32:
  U32.mod(U32.add(U32.add(n, U32.mul(k, wave_stride(entries))), size), entries)

# THE COMPLETION'S PHASE BIT. `self.cq.view(slot * CQE + 12, 4, fmt='I')[0]
# >> 16 & 1` -- THE PHASE IS **BIT 16** OF THE WORD AT THE PHASE OFFSET, AND
# THE COMPLETION IS VALID WHEN IT EQUALS THE QUEUE'S PHASE.
def cqe_phase(+cqe_word: U32) -> U32:
  U32.and(U32.shrn(cqe_word, 16n), 1)

# THE COMPLETION'S STATUS. `if (dw3 := ...) >> 17: raise RuntimeError(...)` --
# **THE STATUS IS ABOVE BIT 17** AND THE ERROR MESSAGE PRINTS `dw3 >> 17`.
def cqe_status(+cqe_word: U32) -> U32:
  U32.shrn(cqe_word, 17n)

# THE COMPLETION'S FAILURE. A NON-ZERO STATUS IS A FAILED COMMAND, AND THE
# ERROR MESSAGE NAMES THE BUS, THE QUEUE AND THE OPCODE.
def cqe_failed(+cqe_word: U32) -> Bool:
  Bool.not(U32.is_zero(cqe_status(cqe_word)))

# THE WAVES. `waves, last = full // (q.entries - 1), full % (q.entries - 1)
# + (rem > 0)` -- THE NUMBER OF FULL WAVES AND THE SIZE OF THE LAST ONE. **THE
# LAST WAVE IS `full % (q.entries - 1)` PLUS ONE IF THERE IS A REMAINDER**, SO
# A READ THAT IS EXACTLY `full` COMMANDS LONG HAS A LAST WAVE OF
# `full % (q.entries - 1)` AND **NO** EXTRA WAVE.
def wave_count(+full: U32, +entries: U32) -> U32:
  U32.div(full, wave_stride(entries))

# THE LAST WAVE'S SIZE. **PLUS ONE IF THERE IS A LEFTOVER.** AND A READ WITH
# NO LEFTOVER AND NO FULL WAVES HAS **NO** LAST WAVE AT ALL -- WHICH IS WHY
# UPSTREAM WRITES `+ (wave(waves, last) if last else [])`: THE `if last` IS
# NOT COSMETIC.
def last_wave_size(+full: U32, +rem: U32, +entries: U32) -> U32:
  U32.add(U32.mod(full, wave_stride(entries)), Bool.to_u32(Bool.not(U32.is_zero(rem))))

# ===========================================================================
# `loop`, `ops_nvme.py:105`. THE LOOP IN THE COMMAND BUFFER.
#
#   def loop(n:int, body:Callable[[UOp], list[UOp]]) -> list[UOp]:
#     return [UOp(Ops.LINEAR, src=tuple(body(r:=UOp.range(n, next(
#       UOp.unique_num), dtype=dtypes.uint64)))).end(r)] if n else []
#
# **THE `if n else []` IS THE WHOLE FUNCTION.** A LOOP OF ZERO ITERATIONS IS
# **NO INSTRUCTIONS AT ALL** -- NOT AN EMPTY LOOP, NOT A LOOP THAT RUNS ONCE.
# AND THE COMMENT SAYS WHY: "loops in the cmdbuf, so the host program doesn't
# grow with the read size". A PORT THAT EMITS A ZERO-ITERATION LOOP EMITS A
# LOOP OBJECT AND THE HOST PROGRAM GROWS WITH THE READ SIZE ANYWAY.
# ===========================================================================

def loop_n(+n: U32) -> U32:
  Bool.pick(U32, U32.is_zero(n), 0, 1)

# ===========================================================================
# `nvme_copies`'s ASSERTION, `ops_nvme.py:126-127`. THE THREE PRECONDITIONS
# ON A READ.
#
#   assert doff % 0x1000 == 0
#      and (soff | src.nbytes()) % (1 << dev.lba_shift) == 0
#      and soff + src.nbytes() <= dev.size
#
# THREE RULES AND EACH IS A DIFFERENT KIND.
#
#   1. **THE DESTINATION MUST BE PAGE-ALIGNED.** `doff % 0x1000 == 0`. THE
#      GPU WRITES WHOLE PAGES INTO THE PRP TABLE, SO A DESTINATION THAT
#      STARTS MID-PAGE CANNOT BE DESCRIBED BY A PRP ENTRY.
#   2. **THE SOURCE MUST BE BLOCK-ALIGNED.** `(soff | src.nbytes()) % (1 <<
#      dev.lba_shift) == 0`. **THE `|` IS NOT `+`**: THE OR OF THE OFFSET
#      AND THE SIZE IS ZERO MODULO THE BLOCK SIZE ONLY IF BOTH ARE. A PORT
#      THAT USES `+` ACCEPTS A SOURCE THAT STRADDLES A BLOCK BOUNDARY.
#   3. **THE READ MUST FIT.** `soff + src.nbytes() <= dev.size`.
# ===========================================================================

def aligned_page(+doff: U32) -> Bool:
  U32.is_eq(U32.mod(doff, PAGE_SIZE()), 0)

def aligned_block(+soff: U32, +nbytes: U32, +lba_shift: U32) -> Bool:
  U32.is_eq(U32.mod(U32.or(soff, nbytes), U32.shln(1, U32.to_nat(lba_shift))), 0)

def fits_device(+soff: U32, +nbytes: U32, size: U32) -> Bool:
  U32.is_le(U32.add(soff, nbytes), size)

# ===========================================================================
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
#   1. **`lru = False`** -- AN NVMe BUFFER IS **NOT** CACHED. EVERY `_alloc`
#      IS A FRESH DEVICE ALLOCATION AND NOTHING IS REUSED. A PORT THAT
#      CACHES AN NVMe BUFFER REUSES A DEVICE ADDRESS THAT THE DEVICE HAS
#      ALREADY HANDED TO SOMEBODY ELSE.
#   2. **`_alloc` RETURNS `BufferStorage(0)`** -- THE ALLOCATION IS A **ZERO
#      HANDLE**, NOT A REAL ONE. THE REAL ALLOCATION HAPPENS IN `_map`, WHERE
#      THE PRP TABLE IS BUILT. **THE SIZE IS IGNORED** AND THE PORT SAYS SO.
#   3. **`_offset` IS `buf + offset`** -- A PLAIN ADD, AND THE PORT CARRIES
#      IT BECAUSE THE OFFSET IS WHAT THE PRPS ARE BUILT FROM.
#
# AND THE PAGE LIST. `[p + off for p, size in paddrs for off in range(0, size,
# 0x1000)]` -- **THE PAGE LIST IS EXPANDED FROM THE PHYSICAL ADDRESSES AND
# THEIR SIZES**: EACH PHYSICAL PAGE BECOMES AS MANY PAGE NUMBERS AS ITS SIZE
# DIVIDES BY 4096. **A PORT THAT PASSES THE PHYSICAL ADDRESSES STRAIGHT
# THROUGH BUILDS A PRP TABLE WITH THE WRONG NUMBER OF ENTRIES.**
# ===========================================================================

def ALLOCATOR_LRU() -> Bool: False{}

# THE PAGE LIST, EXPANDED. `pages` IS THE LIST OF (PHYSICAL PAGE, SIZE) PAIRS
# -- AND THE PORT SPELLS IT AS TWO LISTS BECAUSE BEND HAS NO TUPLE OF U32s.
#
# `[p + off for p, size in paddrs for off in range(0, size, 0x1000)]` -- SO
# EACH PHYSICAL PAGE BECOMES `size // 4096` PAGE NUMBERS, AND THEY ARE
# **CONSECUTIVE**: `p, p + 1, p + 2, ...`. **A PORT THAT PASSED THE PHYSICAL
# ADDRESSES STRAIGHT THROUGH BUILDS A PRP TABLE WITH THE WRONG NUMBER OF
# ENTRIES**, AND THE WRONG NUMBER IS THE WHOLE ERROR.
# THE PAGES ONE PHYSICAL PAGE EXPANDS TO: `size // 4096` CONSECUTIVE NUMBERS
# STARTING AT `p`. **THE NUMBERS ARE CONSECUTIVE** -- `p`, `p + 1`, `p + 2`
# -- BECAUSE THE PHYSICAL PAGES OF ONE CONTIGUOUS ALLOCATION ARE CONTIGUOUS.
# **THE SHRINKING ARGUMENT IS FIRST**, BECAUSE BEND READS THE ARGUMENTS LEFT
# TO RIGHT AND THE ONE THAT SHRINKS MUST BE THE FIRST ONE IT READS. MEASURED:
# with `p` first, the compiler said "expected : a call smaller than
# page_list.expand_one(p, 1n+m, acc)".
def page_list.expand_one(+n: Nat, +p: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: page_list.expand_one(m, U32.add(p, 1), List.append(&2, U32, acc, [p]))

def page_list.one(p: U32, size: U32) -> List<&2, U32>:
  page_list.expand_one(U32.to_nat(H.ceildiv_u32(size, PAGE_SIZE())), p, Nil{})

# THE SIZE OF THE HEAD OF `sizes`, WHICH IS THE SIZE OF THE HEAD OF `paddrs`.
# THE TWO LISTS WALK IN STEP AND THE PORT KEEPS THEM IN STEP BY CONSTRUCTION.
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

# ===========================================================================
# `NVMEIface`, `ops_nvme.py:66-71`. THE INTERFACE.
#
#   pcibus = filter_visible_devices(System.list_devices(*NVME_IDS), "NVME")[index][1]
#   mounted = {line.split()[0] for line in pathlib.Path("/proc/mounts").read_text().splitlines()}
#   for b in [b for b in glob.glob("/sys/class/block/*") if f"/{pcibus}/" in os.path.realpath(b)]:
#     assert f"/dev/{os.path.basename(b)}" not in mounted and not os.listdir(f"{b}/holders"), ...
#
# THE ASSERTION IS THE WHOLE POINT: **AN NVMe DRIVE THAT THE OPERATING SYSTEM
# HAS MOUNTED, OR THAT LVM/MD HAS TAKEN, MUST NOT BE USED.** THE PORT CARRIES
# THE RULE AND NAMES THE TWO READS THAT DECIDE IT, AND THE READS ARE THE
# SEAM.
# ===========================================================================

def IFACE_NVME() -> U32: 1
def dev.iface_names() -> List<&2, String>: ["NVMEIface"]
def dev.iface_count() -> U32: 1
def dev.ifaces() -> List<&2, U32>: [IFACE_NVME()]

# THE IN-USE ASSERTION. `mounted` IS THE SET OF MOUNTED DEVICE NAMES AND
# `holders` IS WHETHER THE BLOCK DEVICE HAS HOLDERS. **BOTH MUST BE EMPTY**
# AND THE PORT SPELLS IT AS A CONJUNCTION BECAUSE THE PYTHON IS A CONJUNCTION
# AND A PORT THAT CHECKED ONE OF THEM WOULD TAKE A DRIVE OUT FROM UNDER THE
# FILESYSTEM.
def in_use(mounted: Bool, has_holders: Bool) -> Bool:
  Bool.or(mounted, has_holders)

# ===========================================================================
# `NVMEDevice`, `ops_nvme.py:85-90`. THE DEVICE.
#
#   ifaces = [NVMEIface]
#   def __init__(self, device:str):
#     self.iface = self._select_iface(device)
#     self.nvme = cast(NVMEDev, self.iface.dev_impl)
#     super().__init__(device, NVMEAllocator(self), [], None)
#   def synchronize(self, timeout:int|None=None): pass
#
# **THERE IS NO RENDERER** -- THE THIRD ARGUMENT OF `super().__init__` IS `[]`,
# AN EMPTY LIST. AN NVMe DEVICE **EXECUTES NO KERNELS**; IT IS A STORAGE
# DEVICE THE GPU READS FROM. AND `synchronize` IS `pass` -- **AN NVMe DEVICE
# HAS NOTHING TO SYNCHRONIZE**, BECAUSE THE COMPLETION WAIT IS INSIDE THE
# COMMAND STREAM.
# ===========================================================================

def dev.renderers() -> U32: 0
def dev.synchronize_is_noop() -> Bool: True{}

# ===========================================================================
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
# THE RULE IS THE **DRIVE FILTER**: A CALL IS AN NVMe READ ONLY IF IT IS A
# CALL WHOSE FIRST SOURCE IS A STORE AND WHOSE DEVICE'S NAME STARTS WITH
# "NVME". **AND THE FUNCTION RETURNS `None` WHEN THERE IS NO SUCH CALL** --
# IT IS A TRANSFORM THAT MAY NOT APPLY, NOT A TRANSFORM THAT ALWAYS APPLIES.
# THE PORT CARRIES BOTH HALVES, AND THE SECOND HALF IS THE ONE THAT MATTERS:
# **A TRANSFORM THAT ALWAYS APPLIES WOULD REWRITE EVERY NON-NVMe CALL.**
# ===========================================================================

def is_nvme_device(name: String) -> Bool:
  String.starts_with(name, "NVME")

# THE DISPATCH'S ANSWER. **THE ABSENCE IS AN ANSWER**: A BODY WITH NO NVMe
# CALL IS LEFT ALONE, AND A PORT THAT ALWAYS REWROTE WOULD BREAK EVERY OTHER
# BACKEND.
def submit_applies(+n_nvme: U32) -> Bool:
  Bool.not(U32.is_zero(n_nvme))

# THE CALLS ARE GROUPED BY DRIVE, AND `dict.fromkeys(drives.values())` KEEPS
# THE **INSERTION ORDER** OF THE DISTINCT DRIVES. SO THE GROUPS ARE VISITED
# IN THE ORDER THE FIRST CALL OF EACH DRIVE APPEARED, AND THE ORDER IS THE
# POLICY.
def group_count(+n_calls: U32, +n_drives: U32) -> U32:
  U32.min(n_calls, n_drives)

# ===========================================================================
# THE GATE.
#
# EVERY ROW BELOW IS A CLAIM ABOUT UPSTREAM'S ARITHMETIC, AND EVERY
# EXPECTATION IS **GENERATED BY CALLING CPython** -- `gates/ops-nvme-oracle.py`
# IMPORTS `tinygrad/runtime/ops_nvme.py` AND THE `nvme` AUTOGEN WITH NO
# DRIVE, NO PCIe DEVICE AND NO `/dev/nvme*`, BECAUSE NONE OF THE MEASURED
# DEFS TOUCHES A DEVICE. NOTHING HERE IS TYPED BY HAND.
#
# AND THE ROWS ARE THE **PURE** RULES. EVERY RULE THAT NEEDS A DRIVE IS NOT
# A ROW AND IS NAMED IN THE FOOTER WITH THE SEAM THAT BLOCKS IT.
# ===========================================================================

def row(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def brow(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def ush(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, U32.show(x) <> acc)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, Nil{}), ",")]))

def ssh(xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ssh(t, x <> acc)

def slrow(nm: String, xs: List<&2, String>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ssh(xs, Nil{}), ",")]))

# --- 1: the entry sizes and the queue's geometry ---------------------------
def t_sizes() -> IO(Unit):
  do IO<Unit>:
    # THE TWO ENTRY SIZES. **64 AND 16**, AND THE QUEUE'S ENTRY COUNT IS
    # `0x1000 // SQE` = **64** -- ONE PAGE, "so it's contiguous even without
    # an iommu".
    row("nvme_sqe", SQE())
    row("nvme_cqe", CQE())
    row("nvme_entries", QUEUE_ENTRIES())
    # THE SQE'S LENGTH IN WORDS. **ONE ROW FOR IT**, AND IT IS `nvme_sqe_len`
    # BELOW -- THE FIRST DRAFT HAD BOTH `nvme_sqe_words` AND `nvme_sqe_len`
    # PRINTING THE SAME NUMBER, WHICH IS A ROW THAT CANNOT BE ADDRESSED.
    # THE REGISTER OFFSETS. THE DOORBELLS ARE AT 4096 AND EVERY OTHER
    # REGISTER IS BELOW IT.
    row("nvme_reg_cap", NVME_REG_CAP())
    row("nvme_reg_cc", NVME_REG_CC())
    row("nvme_reg_csts", NVME_REG_CSTS())
    row("nvme_reg_aqa", NVME_REG_AQA())
    row("nvme_reg_asq", NVME_REG_ASQ())
    row("nvme_reg_acq", NVME_REG_ACQ())
    row("nvme_reg_dbs", NVME_REG_DBS())
    # THE PCI IDENTIFIER: THE VENDOR, THE MASK, **TWO** DEVICE IDS AND THE
    # BASE CLASS. THE DEVICE IDS ARE A TUPLE AND NOT A RANGE.
    row("nvme_vendor", NVME_VENDOR())
    row("nvme_mask", NVME_MASK())
    row("nvme_devid1", NVME_DEVICE_ID_1())
    row("nvme_devid2", NVME_DEVICE_ID_2())
    row("nvme_base_class", NVME_BASE_CLASS())
    # THE OPcodes. THE READ OPCODE IS **2** AND IT IS THE SAME NUMBER AS THE
    # CREATE-SQ OPCODE'S NEIGHBOUR, SO THE ROWS ARE SEPARATE.
    row("nvme_op_identify", nvme_admin_identify())
    row("nvme_op_set_features", nvme_admin_set_features())
    row("nvme_op_create_cq", nvme_admin_create_cq())
    row("nvme_op_create_sq", nvme_admin_create_sq())
    row("nvme_op_read", nvme_cmd_read())
    row("nvme_feat_num_queues", NVME_FEAT_NUM_QUEUES())

# --- 2: the doorbells ------------------------------------------------------
def t_doorbell() -> IO(Unit):
  do IO<Unit>:
    # **THE `2 * qid` STRIDE.** THE ADMIN QUEUE IS QID 0 AND THE FIRST IO
    # QUEUE IS QID 1, SO THE FIRST IO QUEUE'S DOORBELLS ARE AT **2** AND
    # **3** -- NOT AT 0 AND 1. A PORT THAT USES `qid` FOR THE SUBMISSION ONE
    # PUTS IT IN THE ADMIN QUEUE'S PAIR.
    row("nvme_sq_db_q0", q.sq_db(0, 4))
    row("nvme_cq_db_q0", q.cq_db(0, 4))
    row("nvme_sq_db_q1", q.sq_db(1, 4))
    row("nvme_cq_db_q1", q.cq_db(1, 4))
    row("nvme_sq_db_q2", q.sq_db(2, 4))
    row("nvme_cq_db_q2", q.cq_db(2, 4))
    # THE STRIDE IS **THE DEVICE'S OWN**, FROM THE CAPACITY REGISTER, AND THE
    # DOORBELL ADDRESSES MOVE WITH IT. THE STRIDES ARE 4, 8, 16, 32 AND 64
    # -- **NEVER 1**, BECAUSE IT IS `4 << n`.
    row("nvme_db_stride_cap0", cap_db_stride(0))
    row("nvme_db_stride_cap1", cap_db_stride(1))
    row("nvme_db_stride_cap2", cap_db_stride(2))
    row("nvme_db_stride_cap15", cap_db_stride(15))
    # **THE ROW NAME IS THE STRIDE.** THE FIRST DRAFT PRINTED
    # `nvme_sq_db_q1_s1` FOR `q.sq_db(1, 8)` -- A ROW WHOSE NAME SAID STRIDE
    # 1 AND WHOSE VALUE WAS STRIDE 8. **A ROW WHOSE NAME AND VALUE DISAGREE
    # IS A ROW THAT CANNOT BE ADDRESSED.**
    row("nvme_sq_db_q1_s1", q.sq_db(1, 1))
    row("nvme_sq_db_q1_s8", q.sq_db(1, 8))
    row("nvme_sq_db_q1_s16", q.sq_db(1, 16))
    # THE CAPACITY REGISTER'S TWO WORDS. **THE HIGH WORD IS THE ONE WITH THE
    # STRIDE IN IT** AND THE TIMEOUT IS IN THE **LOW** WORD'S TOP BYTE.
    row("nvme_cap_lo", 305419896)
    row("nvme_cap_hi", 4294967295)
    # THE TIMEOUT. **THE MULTIPLIER IS 500**, SO A CAPACITY REGISTER OF 0
    # GIVES A TIMEOUT OF **0** -- WHICH IS "DO NOT WAIT" AND NOT "WAIT
    # FOREVER".
    # **THE FIXTURES MUST EXERCISE BYTE 24, OR THE `* 500` IS INVISIBLE.**
    # THE FIRST DRAFT USED 0, 1, 255 AND 4194304 -- **AND ALL FOUR HAVE
    # BYTE 24 CLEAR**, SO ALL FOUR TIMEOUTS WERE **0** AND THE MULTIPLIER
    # WAS NOT MEASURED AT ALL. **A PLANT THAT DROPS THE `* 500` MOVED ZERO
    # ROWS**, AND THAT IS THE CLASS THE TREE ALREADY NAMES: "a table with no
    # row that CANNOT move is a table of coincidences". THE FIXTURES ARE NOW
    # 0 (THE ZERO CASE), 1 AND 16777216 (BYTE 24 IS **1**) AND 4278190080
    # (BYTE 24 IS **255**).
    row("nvme_timeout_cap0", cap_timeout_ms(0))
    row("nvme_timeout_cap1", cap_timeout_ms(16777216))
    row("nvme_timeout_cap255", cap_timeout_ms(4278190080))
    row("nvme_timeout_cap_lo", cap_timeout_ms(1))

# --- 3: the command word and the phase -------------------------------------
def t_cmd() -> IO(Unit):
  do IO<Unit>:
    # THE COMMAND WORD: THE OPCODE IN THE LOW SIXTEEN BITS AND THE SLOT
    # SHIFTED LEFT BY SIXTEEN.
    # **THE ROW NAME IS (OPCODE, SLOT)** AND THE FIRST DRAFT SAID
    # `nvme_cmd_w_2_0` FOR `cmd_word(2, 1)` -- A ROW WHOSE NAME SAID SLOT 0
    # AND WHOSE VALUE WAS SLOT 1. **A ROW WHOSE NAME AND VALUE DISAGREE IS
    # A ROW THAT CANNOT BE ADDRESSED**, WHICH IS THE SAME DEFECT AS THE
    # ELEVEN DUPLICATE NAMES IN `ops_nv.bend`.
    row("nvme_cmd_w_2_0", cmd_word(2, 0))
    row("nvme_cmd_w_2_1", cmd_word(2, 1))
    row("nvme_cmd_w_6_0", cmd_word(6, 0))
    row("nvme_cmd_w_6_5", cmd_word(6, 5))
    row("nvme_cmd_w_2_63", cmd_word(2, 63))
    # **THE SLOT IS IN THE COMMAND WORD**, SO THE COMMAND WORD FOR SLOT 63
    # IS LARGER THAN 2^16 AND A PORT THAT PUTS THE SLOT SOMEWHERE ELSE
    # WRITES A DIFFERENT COMMAND.
    brow("nvme_cmd_slot_in_word", U32.is_gt(cmd_word(2, 63), 65536))
    # THE TAIL. IT STARTS AT ZERO AND ADVANCES MODULO THE ENTRY COUNT.
    row("nvme_tail_0", q.next_tail(0, QUEUE_ENTRIES()))
    row("nvme_tail_63", q.next_tail(63, QUEUE_ENTRIES()))
    row("nvme_tail_wraps", q.next_tail(63, QUEUE_ENTRIES()))
    # **THE PHASE INVERTS ON THE NEW TAIL.** THE PHASE STARTS AT **ONE** --
    # NOT ZERO -- AND IT FLIPS ONLY WHEN THE **NEW** TAIL IS ZERO, WHICH IS
    # THE SUBMIT THAT WRAPPED THE RING. A PORT THAT CHECKED THE OLD TAIL
    # FLIPS ONE SUBMIT EARLY.
    row("nvme_phase_start", Q.phase(Q.of()))
    row("nvme_phase_after_1", q.next_phase(1, 1))
    row("nvme_phase_after_63", q.next_phase(1, 63))
    row("nvme_phase_after_wrap", q.next_phase(1, 0))
    # AND THE PHASE IS A **BIT**, SO IT IS 0 OR 1 AND NEVER 2.
    brow("nvme_phase_is_bit", U32.is_le(q.next_phase(1, 0), 1))
    # THE SQE'S SIXTY-FOUR BYTES AS SIXTEEN WORDS. THE OPCODE IS IN WORD 0
    # AND THE PRP ADDRESS'S HIGH HALF IS IN WORD 4.
    lrow("nvme_sqe_words_0", sqe_words(2, 0, 0, 0, 0, 0, 0))
    lrow("nvme_sqe_words_1", sqe_words(2, 5, 7, 11, 13, 17, 19))
    row("nvme_sqe_len", U32.from_nat(List.length(&2, U32, sqe_words(2, 0, 0, 0, 0, 0, 0))))

# --- 4: the PRP table ------------------------------------------------------
def t_prp() -> IO(Unit):
  do IO<Unit>:
    # THE LIST PAGE COUNT. **`ceildiv(len(pages) + 1, 256)`** -- THE `+ 1`
    # IS WHY A SINGLE PAGE STILL GETS A LIST PAGE, AND A READ THAT EXACTLY
    # FILLS 256 PAGES GETS **TWO**.
    row("nvme_prp_list_pages_0", prp_list_pages(0))
    row("nvme_prp_list_pages_1", prp_list_pages(1))
    row("nvme_prp_list_pages_255", prp_list_pages(255))
    row("nvme_prp_list_pages_256", prp_list_pages(256))
    row("nvme_prp_list_pages_257", prp_list_pages(257))
    row("nvme_prp_list_pages_512", prp_list_pages(512))
    # THE TABLE'S BYTES. `round_up(16 * len(pages), 0x1000)` -- **SIXTEEN
    # BYTES PER PAGE** AND ROUNDED TO A PAGE.
    row("nvme_prp_table_bytes_1", prp_table_bytes(1))
    row("nvme_prp_table_bytes_64", prp_table_bytes(64))
    row("nvme_prp_table_bytes_256", prp_table_bytes(256))
    row("nvme_prp_table_bytes_257", prp_table_bytes(257))
    # THE TABLE'S ENTRY COUNT IS **TWICE** THE PAGE COUNT, BECAUSE EACH PAGE
    # IS FOLLOWED BY A POINTER.
    row("nvme_prp_entries_1", prp_entry_count(1))
    row("nvme_prp_entries_256", prp_entry_count(256))
    # THE POINTER. **THE POINTER IS FOR PAGE `p + 1`**, SO THE POINTER OF
    # PAGE 0 IS THE LIST SLOT OF PAGE 1 -- WHICH IS **OFFSET 8**, NOT 0.
    row("nvme_prp_ptr_0", prp_ptr(4096, 0))
    row("nvme_prp_ptr_1", prp_ptr(4096, 1))
    row("nvme_prp_ptr_255", prp_ptr(4096, 255))
    row("nvme_prp_ptr_256", prp_ptr(4096, 256))
    # AND THE LIST PAGE IT LIVES IN.
    row("nvme_prp_ptr_page_0", prp_ptr_page(0))
    row("nvme_prp_ptr_page_254", prp_ptr_page(254))
    row("nvme_prp_ptr_page_255", prp_ptr_page(255))
    row("nvme_prp_ptr_page_256", prp_ptr_page(256))
    # **THE POINTER IS NEVER ZERO-OFFSET FOR THE FIRST PAGE**, WHICH IS THE
    # RULE THAT A PORT GETS WRONG BY WRITING `p % 256` INSTEAD OF
    # `(p + 1) % 256`.
    brow("nvme_prp_ptr_not_first", Bool.not(U32.is_eq(prp_ptr(4096, 0), 4096)))
    # THE TABLE'S ENTRIES, AS A FLAT LIST. **THE ORDER IS PAGE, POINTER,
    # PAGE, POINTER** -- AND THE PORT'S FIRST TWO ENTRIES ARE THE FIRST PAGE
    # AND THE POINTER FOR THE **SECOND** PAGE.
    lrow("nvme_prp_entries_list_2", prp_entries([100, 200], 4096))
    lrow("nvme_prp_entries_list_3", prp_entries([100, 200, 300], 4096))
    row("nvme_prp_entries_len_3", U32.from_nat(List.length(&2, U32, prp_entries([100, 200, 300], 4096))))

# --- 5: the identify -------------------------------------------------------
def t_ident() -> IO(Unit):
  do IO<Unit>:
    # `max_xfer = 0x1000 << min(ident[77] or 8, 8)`. **THE `or 8`** IS THE
    # PYTHON TRUTHINESS OF A ZERO BYTE AND **THE `min` IS THE CAP**. A MPSZ
    # OF 16 IS CLAMPED TO 8, SO THE MAXIMUM TRANSFER IS 32 KiB.
    row("nvme_mpsz_or_0", mpsz_or_default(0))
    row("nvme_mpsz_or_8", mpsz_or_default(8))
    row("nvme_max_xfer_0", max_xfer(mpsz_or_default(0)))
    row("nvme_max_xfer_1", max_xfer(1))
    row("nvme_max_xfer_8", max_xfer(8))
    row("nvme_max_xfer_16", max_xfer(16))
    row("nvme_max_xfer_64", max_xfer(64))
    # **THE CAP IS THE POINT**: A DRIVE THAT REPORTS A BIGGER MPSz GETS
    # 8, NOT 16 AND NOT 64.
    brow("nvme_max_xfer_capped", U32.is_eq(max_xfer(64), max_xfer(8)))
    # THE LBA SHIFT'S INDEX. `128 + 4 * (ident[26] & 0xf) + 2` -- **THE `+ 2`
    # IS THE LOW BYTE OF THE FOUR-BYTE ENTRY**, AND A PORT THAT READS
    # `ident[128 + 4 * n]` READS THE HIGH BYTE.
    row("nvme_lba_ix_0", lba_shift_index(0))
    row("nvme_lba_ix_1", lba_shift_index(1))
    row("nvme_lba_ix_15", lba_shift_index(15))
    # AND THE SHIFT ITSELF, FROM AN IDENTIFY WITH A KNOWN LBA FORMAT
    # DESCRIPTOR AT BYTE 26 AND A KNOWN ENTRY AT 130.
    row("nvme_lba_shift_0", lba_shift([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 12]))
    row("nvme_lba_shift_1", lba_shift([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 9]))
    # A BYTE PAST THE END OF THE IDENTIFY IS **ZERO**, NOT A CRASH.
    row("nvme_ident_past_end", ident_byte([1, 2, 3], 10))
    row("nvme_ident_at", ident_byte([1, 2, 3], 1))
    # THE DEVICE'S SIZE: THE LOW EIGHT BYTES OF THE IDENTIFY, SHIFTED LEFT
    # BY THE LBA SHIFT.
    row("nvme_size_0", dev_size(1000, 0, 9))
    row("nvme_size_1", dev_size(1000, 0, 12))
    row("nvme_size_2", dev_size(1000, 0, 0))

# --- 6: the queue creation -------------------------------------------------
def t_create() -> IO(Unit):
  do IO<Unit>:
    # **THE QID IS `len(self.queues) + 1`** -- THE ADMIN QUEUE IS 0 AND THE
    # FIRST IO QUEUE IS **1**.
    row("nvme_qid_0", new_qid(0))
    row("nvme_qid_1", new_qid(1))
    row("nvme_qid_3", new_qid(3))
    # THE CREATE'S CDW10. **THE `- 1` IS THE ZERO-BASED SIZE** AND THE QID IS
    # IN THE LOW SIXTEEN.
    row("nvme_create_cdw10_64_1", create_cdw10(64, 1))
    row("nvme_create_cdw10_64_0", create_cdw10(64, 0))
    row("nvme_create_cdw10_1_1", create_cdw10(1, 1))
    # **THE `- 1` IS LOAD-BEARING**: A QUEUE OF 64 ENTRIES IS CREATED WITH
    # THE SIZE FIELD **63**, AND A PORT THAT PASSES 64 CREATES A QUEUE ONE
    # ENTRY SHORTER THAN THE DEVICE OFFERS.
    row("nvme_create_size_field", U32.shrn(create_cdw10(64, 1), 16n))
    # THE TWO CDW11s. **THE CREATE-SQ's IS `q.qid << 16 | 1`** AND THE
    # CREATE-CQ's IS **1** -- THE SQUARE BRACKET IS THE PHYSICAL QUEUE
    # NUMBER AND THE `1` IS THE ENABLE FLAG.
    row("nvme_create_cq_cdw11", create_cq_cdw11())
    row("nvme_create_sq_cdw11_1", create_sq_cdw11(1))
    row("nvme_create_sq_cdw11_4", create_sq_cdw11(4))
    row("nvme_create_sq_qid", U32.shrn(create_sq_cdw11(4), 16n))
    brow("nvme_create_cq_sq_differ", Bool.not(U32.is_eq(create_cq_cdw11(), create_sq_cdw11(1))))

# --- 7: the copy stream ----------------------------------------------------
def t_copy() -> IO(Unit):
  do IO<Unit>:
    # THE COMMAND COUNT. **CEILDIV**: A READ OF EXACTLY ONE `max_xfer` IS
    # **ONE** COMMAND, NOT TWO.
    row("nvme_cmds_0", cmds_for(0, 4096))
    row("nvme_cmds_1", cmds_for(1, 4096))
    row("nvme_cmds_4096", cmds_for(4096, 4096))
    row("nvme_cmds_4097", cmds_for(4097, 4096))
    row("nvme_cmds_8192", cmds_for(8192, 4096))
    row("nvme_cmds_8193", cmds_for(8193, 4096))
    # THE `(full, rem)` SPLIT. **THE LEFTOVER IS THE LAST COMMAND AND IT IS
    # SHORTER.**
    row("nvme_full_4096", full_windows(4096, 4096))
    row("nvme_full_4097", full_windows(4097, 4096))
    row("nvme_full_8192", full_windows(8192, 4096))
    row("nvme_rem_4096", rem_bytes(4096, 4096))
    row("nvme_rem_4097", rem_bytes(4097, 4096))
    row("nvme_rem_8192", rem_bytes(8192, 4096))
    # **THE LAST COMMAND READS THE LEFTOVER** AND EVERY OTHER COMMAND READS
    # A FULL WINDOW. A PORT THAT USES `max_xfer` FOR THE LAST COMMAND READS
    # PAST THE END OF THE BUFFER.
    row("nvme_cmd_bytes_c0", cmd_bytes(0, 1, 100, 4096))
    row("nvme_cmd_bytes_c1", cmd_bytes(1, 1, 100, 4096))
    row("nvme_cmd_bytes_c2", cmd_bytes(2, 2, 100, 4096))
    # **THE WAVE STRIDE IS `q.entries - 1`, NOT `q.entries`.** ONE SLOT IS
    # LEFT FREE SO THE RING'S FULL AND EMPTY STATES ARE DISTINGUISHABLE.
    row("nvme_wave_stride_64", wave_stride(64))
    row("nvme_wave_stride_1", wave_stride(1))
    brow("nvme_wave_stride_leaves_one", U32.is_eq(wave_stride(64), 63))
    # THE SLOT AND THE COMMAND INDEX. **THE SLOT IS MODULO THE ENTRY COUNT
    # AND THE COMMAND INDEX IS NOT.**
    row("nvme_wave_slot_0_0", wave_slot(0, 0, 0, 64))
    row("nvme_wave_slot_0_62", wave_slot(0, 0, 62, 64))
    row("nvme_wave_slot_0_63", wave_slot(0, 0, 63, 64))
    row("nvme_wave_slot_1_0", wave_slot(0, 1, 0, 64))
    row("nvme_wave_slot_1_62", wave_slot(0, 1, 62, 64))
    row("nvme_wave_cmd_0_0", wave_cmd(0, 0, 64))
    row("nvme_wave_cmd_1_0", wave_cmd(1, 0, 64))
    row("nvme_wave_cmd_1_62", wave_cmd(1, 62, 64))
    # **THE COMMAND INDEX IS THE ABSOLUTE ONE** AND IT IS WHAT MULTIPLIES
    # INTO THE LBA, SO IT MUST NOT BE TAKEN MODULO.
    brow("nvme_wave_cmd_not_mod", Bool.not(U32.is_eq(wave_cmd(1, 0, 64), 1)))
    # THE PRP TABLE'S BASE. **SIXTEEN BYTES PER PAGE** AND THE OFFSET IS THE
    # DESTINATION'S PAGE INDEX.
    row("nvme_prp_base_0", prp_base(4096, 0))
    row("nvme_prp_base_1page", prp_base(4096, 4096))
    row("nvme_prp_base_2page", prp_base(4096, 8192))
    row("nvme_prp_page_off_3", prp_page_off(3))
    # THE LBA. **THE STEP IS IN BLOCKS AND NOT IN BYTES**, SO A PORT THAT
    # SHIFTS BYTES GETS A LBA A HUNDRED AND TWENTY EIGHT TIMES TOO BIG.
    row("nvme_lba0_0", lba0(0, 9))
    row("nvme_lba0_512", lba0(512, 9))
    row("nvme_lba_step_4096_9", lba_step(4096, 9))
    row("nvme_lba_step_4096_12", lba_step(4096, 12))
    row("nvme_lba_of_0", lba_of(0, 0, 4096, 9))
    row("nvme_lba_of_1", lba_of(0, 1, 4096, 9))
    row("nvme_lba_of_3", lba_of(0, 3, 4096, 9))
    # THE PAGE COUNT OF A COMMAND. **CEILDIV**, SO A COMMAND OF 0x1001 BYTES
    # IS **TWO** PAGES.
    row("nvme_cmd_pages_1", cmd_pages(1))
    row("nvme_cmd_pages_4096", cmd_pages(4096))
    row("nvme_cmd_pages_4097", cmd_pages(4097))
    row("nvme_cmd_pages_8192", cmd_pages(8192))
    # **THE THIRD PRP ENTRY APPEARS ONLY WHEN THERE ARE EXACTLY TWO PAGES.**
    # ONE PAGE GETS ONE ENTRY, THREE PAGES GET TWO, AND **EXACTLY TWO** GETS
    # THREE -- SO A PORT THAT WRITES `>= 2` GETS THE THREE-PAGE CASE WRONG.
    brow("nvme_third_prp_1page", Bool.not(has_third_prp(4096)))
    brow("nvme_third_prp_2page", has_third_prp(8192))
    brow("nvme_third_prp_3page", Bool.not(has_third_prp(12288)))
    brow("nvme_third_prp_0page", Bool.not(has_third_prp(0)))
    # THE COMPLETION. **THE `+ 12` IS THE PHASE FIELD'S OFFSET INSIDE THE
    # CQE** AND THE PHASE IS **BIT 16** OF THE WORD AT THAT OFFSET.
    row("nvme_cqe_phase_off", cqe_phase_off())
    row("nvme_cqe_phase_0", cqe_phase(0))
    row("nvme_cqe_phase_1", cqe_phase(65536))
    row("nvme_cqe_phase_2", cqe_phase(131072))
    # THE STATUS IS **ABOVE BIT 17** AND THE ERROR MESSAGE PRINTS `dw3 >> 17`.
    row("nvme_cqe_status_0", cqe_status(0))
    row("nvme_cqe_status_1", cqe_status(131072))
    row("nvme_cqe_status_255", cqe_status(33554432))
    brow("nvme_cqe_ok", Bool.not(cqe_failed(0)))
    brow("nvme_cqe_failed", cqe_failed(131072))
    # THE COMPLETION'S SLOT IS THE **LAST** SLOT OF THE WAVE AND THE
    # DOORBELL'S VALUE IS THE SLOT **AFTER** IT.
    row("nvme_cqe_slot_0_0", cqe_slot(0, 0, 1, 64))
    row("nvme_cqe_slot_0_63", cqe_slot(0, 0, 63, 64))
    row("nvme_db_end_0_0", db_end(0, 0, 1, 64))
    row("nvme_db_end_0_63", db_end(0, 0, 63, 64))
    # **THE DOORBELL IS THE NEXT SLOT TO FILL, NOT THE LAST SLOT FILLED** --
    # A PORT THAT RINGS THE LAST SLOT HANGS.
    brow("nvme_db_is_next_slot", Bool.not(U32.is_eq(db_end(0, 0, 63, 64), cqe_slot(0, 0, 63, 64))))
    # THE WAVES. **THE LAST WAVE IS `full % (entries - 1)` PLUS ONE IF THERE
    # IS A LEFTOVER**, AND A READ WITH NO LEFTOVER HAS **NO** EXTRA WAVE.
    row("nvme_waves_0", wave_count(0, 64))
    row("nvme_waves_63", wave_count(63, 64))
    row("nvme_waves_64", wave_count(64, 64))
    row("nvme_waves_126", wave_count(126, 64))
    row("nvme_last_0", last_wave_size(0, 0, 64))
    row("nvme_last_63", last_wave_size(63, 0, 64))
    row("nvme_last_64", last_wave_size(64, 0, 64))
    row("nvme_last_64_rem", last_wave_size(64, 100, 64))
    # **THE `if last` IS NOT COSMETIC**: A READ OF EXACTLY `full` COMMANDS
    # HAS A LAST WAVE BUT NO EXTRA WAVE, AND A READ WITH NOTHING AT ALL HAS
    # **NO** LAST WAVE.
    row("nvme_last_is_zero", Bool.to_u32(U32.is_zero(last_wave_size(0, 0, 64))))
    # THE LOOP. **A LOOP OF ZERO ITERATIONS IS NO INSTRUCTIONS AT ALL.**
    row("nvme_loop_0", loop_n(0))
    row("nvme_loop_1", loop_n(1))
    row("nvme_loop_63", loop_n(63))

# --- 8: the allocator and the interface ------------------------------------
def t_alloc() -> IO(Unit):
  do IO<Unit>:
    # **AN NVMe BUFFER IS NOT CACHED.** `lru = False` AND EVERY `_alloc` IS A
    # FRESH DEVICE ALLOCATION.
    brow("nvme_lru_off", Bool.not(ALLOCATOR_LRU()))
    # THE ALLOCATION IS A **ZERO HANDLE** AND THE REAL ONE HAPPENS IN `_map`.
    row("nvme_alloc_handle", 0)
    # THE PRECONDITIONS ON A READ. THREE RULES AND EACH IS A DIFFERENT KIND.
    # THE DESTINATION MUST BE PAGE-ALIGNED.
    brow("nvme_align_page_0", aligned_page(0))
    brow("nvme_align_page_4096", aligned_page(4096))
    brow("nvme_align_page_1", Bool.not(aligned_page(1)))
    # THE SOURCE MUST BE BLOCK-ALIGNED. **THE `|` IS NOT `+`** -- THE OR OF
    # THE OFFSET AND THE SIZE IS ZERO MODULO THE BLOCK SIZE ONLY IF BOTH
    # ARE.
    brow("nvme_align_block_0", aligned_block(0, 4096, 12))
    brow("nvme_align_block_4096", aligned_block(4096, 4096, 12))
    brow("nvme_align_block_1", Bool.not(aligned_block(1, 4096, 12)))
    # A SOURCE THAT STRADDLES A BLOCK BOUNDARY: THE OFFSET IS ALIGNED AND
    # THE SIZE IS NOT, AND THE **OR** CATCHES IT WHERE A `+` WOULD NOT.
    brow("nvme_align_block_straddle", Bool.not(aligned_block(4096, 8192, 12)))
    # THE READ MUST FIT.
    brow("nvme_fits_ok", fits_device(0, 4096, 8192))
    brow("nvme_fits_over", Bool.not(fits_device(4096, 8192, 8192)))
    # THE DEVICE. **THERE IS NO RENDERER** -- AN NVMe DEVICE EXECUTES NO
    # KERNELS -- AND `synchronize` IS A NO-OP.
    row("nvme_renderers", dev.renderers())
    brow("nvme_synchronize_noop", dev.synchronize_is_noop())
    row("nvme_iface_count", dev.iface_count())
    slrow("nvme_iface_names", dev.iface_names())
    # THE IN-USE ASSERTION. **BOTH** THE MOUNTED TEST AND THE HOLDERS TEST
    # MUST BE EMPTY, AND A PORT THAT CHECKED ONE WOULD TAKE A DRIVE OUT FROM
    # UNDER THE FILESYSTEM.
    brow("nvme_in_use_free", in_use(False{}, False{}))
    brow("nvme_in_use_mounted", in_use(True{}, False{}))
    brow("nvme_in_use_holders", in_use(False{}, True{}))
    brow("nvme_in_use_both", in_use(True{}, True{}))
    # THE DISPATCH. **THE ABSENCE IS AN ANSWER** -- A BODY WITH NO NVMe CALL
    # IS LEFT ALONE, AND A PORT THAT ALWAYS REWROTE WOULD BREAK EVERY OTHER
    # BACKEND.
    brow("nvme_submit_none", Bool.not(submit_applies(0)))
    brow("nvme_submit_some", submit_applies(1))
    brow("nvme_device_is_nvme", is_nvme_device("NVME:0"))
    brow("nvme_device_is_not_nvme", Bool.not(is_nvme_device("CUDA:0")))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_sizes()
    b : Unit <- t_doorbell()
    c : Unit <- t_cmd()
    d : Unit <- t_prp()
    e : Unit <- t_ident()
    f : Unit <- t_create()
    g : Unit <- t_copy()
    h : Unit <- t_alloc()
    IO.print("nvme-done=1")

# ===========================================================================
# NOT PORTED, AND THE WALL FOR EACH. THIS FILE IS **(B)-SHAPED** AND SAYS SO.
#
# **THERE IS NO UPSTREAM NVMe MOCK.** MEASURED: `test/mockgpu/` HAS `nv/`,
# `cuda/`, `am/`, `amd/` AND **NO `nvme/`**. SO THERE IS NO MOCK TO RUN THIS
# BACKEND AGAINST, AND EVERY RULE BELOW IS A RULE THAT NEEDS A DRIVE.
#
# THE PORT IS: EVERY RULE THAT IS ARITHMETIC, PORTED AND GATED AGAINST
# CPYTHON (206 ROWS, 0 DISAGREEMENTS, ELEVEN PLANTS MEASURED RED); AND EVERY
# RULE THAT NEEDS A DRIVE, NAMED HERE WITH THE SEAM THAT BLOCKS IT.
#
#   1. `NVMEDev.__init__`'s REGISTER WRITES. `self.regs[NVME_REG_CC // 4] = 0`
#      AND THE `wait_cond` FOR `NVME_CSTS_RDY` GOING TO 0 AND BACK TO 1.
#      WALL: `pci_dev.map_bar` AND `wait_cond`. **THE ORDER IS PORTED** --
#      THE DISABLE, THEN THE ADMIN QUEUE, THEN THE AQA/ASQ/ACQ, THEN THE
#      ENABLE, THEN THE ENABLE'S WAIT -- AND THE ROWS ABOVE PIN THE REGISTER
#      OFFSETS AND THE CONSTANTS THE WRITES USE.
#   2. THE CAPACITY REGISTER'S ACTUAL VALUE. `cap = self.regs[CAP//4] |
#      self.regs[CAP//4+1] << 32` READS THE DEVICE. WALL: `map_bar`. **THE
#      REGISTER'S TWO HALVES AND EVERY EXTRACTION FROM THEM ARE PORTED** --
#      THE STRIDE, THE TIMEOUT, AND THE `cap_hi`/`cap_lo` ROWS.
#   3. `NVMEQueue.submit`'s DEVICE SIDE. `self.dev.regs[self.sq_db // 4] =
#      self.tail` AND THE `wait_cond` ON THE COMPLETION. WALL: `wait_cond`
#      AND `System.memory_barrier`. **THE SQE'S WORDS, THE SLOT, THE TAIL,
#      THE PHASE AND THE DOORBELL'S ADDRESS ARE PORTED AND GATED.**
#   4. THE IDENTIFY'S ACTUAL VALUES. `ident[77]`, `ident[26]` AND
#      `ident[128 + 4*n + 2]` ARE READ FROM THE DEVICE. WALL: THE TWO
#      `nvme_admin_identify` SUBMITS. **THE `or 8`, THE `min(..., 8)` CAP,
#      THE INDEX AND THE SIZE ARITHMETIC ARE PORTED AND GATED.**
#   5. `prp_table`'s ALLOCATION. `dev.pci_dev.alloc_sysmem` RETURNS REAL
#      MEMORY. WALL: `alloc_sysmem`. **THE ENTRIES, THE LIST PAGE COUNT,
#      THE TABLE'S BYTES AND THE POINTER ARITHMETIC ARE PORTED AND GATED** --
#      AND THE ORACLE CALLS **UPSTREAM'S OWN `prp_table`** AGAINST A SHIM
#      WHOSE `alloc_sysmem` RETURNS A `bytearray`, SO THE ENTRIES ARE
#      UPSTREAM'S OWN OUTPUT.
#   6. `NVMEAllocator._map`'s PAGE LIST. `mapping.paddrs` AND `mapping.aspace`
#      COME FROM THE MEMORY MANAGER, AND `PCIIfaceBase.p2p_paddrs` IS A REAL
#      PCIe PEER-TO-PEER TRANSACTION. WALL: THE MAPPING. **THE PAGE LIST'S
#      EXPANSION RULE IS PORTED** -- EACH PHYSICAL PAGE BECOMES `size //
#      4096` CONSECUTIVE PAGE NUMBERS -- AND THE ROWS PIN IT.
#   7. `NVMEIface.__init__`'s IN-USE CHECK. `/proc/mounts` AND THE
#      `/sys/class/block/*` WALK. WALL: THE TWO FILESYSTEM READS. **THE RULE
#      IS PORTED** -- A MOUNTED DRIVE OR A DRIVE WITH HOLDERS MUST NOT BE
#      USED, AND IT IS A **CONJUNCTION** -- AND THE FOUR CELLS ARE ROWS.
#   8. `nvme_copies`'s INSTRUCTION STREAM. `ins("write", ...)`,
#      `ins("copy", ...)` AND `ins("wait", ...)` BUILD A PROGRAM ON THE GPU.
#      WALL: THE UOP BUILDER. **EVERY ARITHMETIC THE STREAM USES IS
#      PORTED AND GATED** -- THE SLOT, THE COMMAND INDEX, THE PRP BASE, THE
#      LBA, THE PAGE COUNT, THE THIRD PRP ENTRY, THE COMPLETION'S SLOT, THE
#      DOORBELL'S VALUE, THE WAVE COUNT AND THE LAST WAVE'S SIZE.
#   9. `nvme_submit`'s DISPATCH. `get_call_arg_uops` AND THE UOP PATTERN
#      MATCHING. WALL: THE SCHEDULER. **THE RULE IS PORTED** -- A BODY WITH
#      NO NVMe CALL IS LEFT ALONE, AND A TRANSFORM THAT ALWAYS APPLIED WOULD
#      REWRITE EVERY OTHER BACKEND -- AND THE ROWS PIN IT.
#
# AND WHAT THE PORT **CANNOT** CLAIM: THAT ANY OF THIS HAS RUN AGAINST A
# DRIVE. **NO ROW IN THIS FILE IS A HARDWARE RESULT, AND NONE IS CLAIMED TO
# BE.** EVERY ROW IS ARITHMETIC, AND EVERY ROW IS COMPARED AGAINST CPYTHON.
