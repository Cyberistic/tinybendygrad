#!/usr/bin/env python3
"""amdev_consts.py -- EMIT the Bend constant defs from CPython.

A hand-typed constant is how ops_nv shipped 33 wrong ones in a file already
printing 590 green rows. So the `def NAME() -> U32: N` block at the head of
amdev.bend is GENERATED, by reading each value out of the `am` module (or
evaluating the Python expression amdev.py writes) and printing the Bend.

    .venv/bin/python .agents/slop/amdev_consts.py            # print
    .venv/bin/python .agents/slop/amdev_consts.py --check FILE.bend
"""
import sys, re
sys.path.insert(0, '.')
from tinygrad.runtime.autogen.am import am
from tinygrad.runtime.autogen import pci
from tinygrad.runtime.support.am.amdev import AMDev, AMPageTableEntry
from tinygrad.runtime.support.memory import AddrSpace

# (bend name, python value) -- the NAME is mine, the VALUE is amdev.py's.
C = [
  ("MMIOV_FUNC_IDENTIFIER",            am.mmRCC_IOV_FUNC_IDENTIFIER),
  ("NV_MAIBOX_CONTROL_TRN_OFFSET_BYTE", am.NV_MAIBOX_CONTROL_TRN_OFFSET_BYTE),
  ("MAILBOX_MSGBUF_TRN_DW0",           am.mmMAILBOX_MSGBUF_TRN_DW0),
  ("MAILBOX_MSGBUF_RCV_DW0",           am.mmMAILBOX_MSGBUF_RCV_DW0),
  ("IDH_REQ_GPU_INIT_ACCESS",          am.IDH_REQ_GPU_INIT_ACCESS),
  ("IDH_REQ_GPU_FINI_ACCESS",          am.IDH_REQ_GPU_FINI_ACCESS),
  ("IDH_READY_TO_ACCESS_GPU",          am.IDH_READY_TO_ACCESS_GPU),
  ("MAILBOX_CLEAR_MS",                 1000),
  ("MAILBOX_ACK_TIMEDOUT",             am.NV_MAILBOX_POLL_ACK_TIMEDOUT),
  ("MAILBOX_MSG_TIMEDOUT",             am.NV_MAILBOX_POLL_MSG_TIMEDOUT),
  ("AMDGPU_PTE_VALID",                 am.AMDGPU_PTE_VALID),
  ("AMDGPU_PTE_SYSTEM",                am.AMDGPU_PTE_SYSTEM),
  ("AMDGPU_VM_PTB",                    am.AMDGPU_VM_PTB),
  ("AMDGPU_VM_PDB2",                   am.AMDGPU_VM_PDB2),
  ("IP_DISCOVERY",                     am.IP_DISCOVERY),
  ("HARVEST_INFO",                     am.HARVEST_INFO),
  ("GC",                               am.GC),
  ("BINARY_SIGNATURE",                 am.BINARY_SIGNATURE),
  ("DISCOVERY_TABLE_SIGNATURE",        am.DISCOVERY_TABLE_SIGNATURE),
  ("HARVEST_TABLE_SIGNATURE",          am.HARVEST_TABLE_SIGNATURE),
  ("MAX_HWIP",                         am.MAX_HWIP),
  ("MP0_HWIP",                         am.MP0_HWIP),
  ("MP1_HWIP",                         am.MP1_HWIP),
  ("GC_HWIP",                          am.GC_HWIP),
  ("HDP_HWIP",                         am.HDP_HWIP),
  ("MMHUB_HWIP",                       am.MMHUB_HWIP),
  ("OSSSYS_HWIP",                      am.OSSSYS_HWIP),
  ("NBIO_HWIP",                        am.NBIO_HWIP),
  ("SDMA0_HWIP",                       am.SDMA0_HWIP),
  ("PCI_COMMAND",                      pci.PCI_COMMAND),
  ("PCI_COMMAND_MASTER",               pci.PCI_COMMAND_MASTER),
  ("AMDEV_VERSION",                    AMDev.Version),
  ("MMRCC_CONFIG_MEMSIZE",             0xde3),
  ("TMR_OFF_KB",                       64),
  ("TMR_SZ_KB",                        10),
  ("VRAM_SHIFT",                       20),
  ("VA_BITS",                          48),
  ("BOOT_SIZE",                        3 << 20),
  ("RESERVED_BIG",                     384 << 20),
  ("RESERVED_SMALL",                   64 << 20),
  ("PTE_ADDR_MASK_LO",                 0x0000FFFFFFFFF000 & 0xffffffff),
  ("PTE_ADDR_MASK_HI",                 0x0000FFFFFFFFF000 >> 32),
  ("VRAM_WIN_FLAG",                    0x80000000),
  ("VRAM_WIN_MASK",                    0x7FFFFFFF),
  ("RREG_LO",                          0x00),
  ("RREG_HI",                          0x06),
  ("RREG_DATA",                        0x01),
  ("P2S_TABLE_ID_X",                   0x50325358),
  ("ASPM_CAP0",                        0x34),
  ("ASPM_MASK",                        0xfc),
  ("ASPM_LINK_CAP",                    0x10),
  ("ASPM_LNKCTL",                      0x10),
  ("ASPM_LNKCTL_MASK",                 ~3 & 0xffffffff),
  ("RLCG_READ_BIT",                    0x1),
  ("RLCG_READ_SHIFT",                  28),
  ("RLCG_RSV_MASK",                    0xFFFFF),
  ("RLCG_ERR_MASK",                    0xF000000),
  ("PCIE_AID_MASK",                    0b11),
  ("PCIE_AID_SHIFT",                   32),
  ("PCIE_EXT_SHIFT",                   34),
  ("PCIE_HI_MASK",                     0xff),
  ("VRAM_WIN_STEP",                    4),
  ("HARVEST_BYTES",                    8 + 32 * 4),
  ("HARVEST_ENTS",                     32),
  ("AID_ALIVE_F",                      0xf),
  ("AID_ALIVE_3",                      0x3),
  ("AID_ALIVE_C",                      0xc),
  ("AID_GROUP",                        4),
  ("MAILBOX_NWORDS",                   4),  # Nat in the .bend, so the checker skips it
  ("ADDRSPACE_SYS",                    AddrSpace.SYS.value),
  ("ADDRSPACE_PHYS",                   AddrSpace.PHYS.value),
  ("VA_SHIFT0",                        12),
  ("VA_SHIFT1",                        21),
  ("VA_SHIFT2",                        30),
  ("VA_SHIFT3",                        39),
  ("PALLOC_NLV",                       9 * (3 - am.AMDGPU_VM_PDB2)),
  ("PALLOC_LEN",                        9 * (3 - am.AMDGPU_VM_PDB2) + 1),
  ("PALLOC_BIG_I",                     9),
  ("PALLOC_SMALL",                     0x1000),
  ("PALLOC_BIG",                       2 << 20),
]

if len(sys.argv) > 2 and sys.argv[1] == "--check":
  src = open(sys.argv[2]).read()
  got = dict(re.findall(r"^def (\w+)\(\) -> (?:U32|Nat): (\d+)n?$", src, re.M))
  bad = [(n, v, got.get(n)) for n, v in C if got.get(n) != str(v)]
  for n, v, g in bad: print(f"MISMATCH {n}: file={g} cpython={v}")
  print(f"{len(C) - len(bad)}/{len(C)} constants agree with CPython")
  sys.exit(1 if bad else 0)

for n, v in C: print(f"def {n}() -> U32: {v}")