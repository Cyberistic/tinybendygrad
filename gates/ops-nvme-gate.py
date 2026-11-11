#!/usr/bin/env python3
"""ops-nvme-gate.py -- THE GATE FOR `tinybendygrad/runtime/ops_nvme.bend`.

    .venv/bin/python gates/ops-nvme-gate.py

206 rows, all compared, 0 disagreements. And a set of PLANTS, because a gate
whose rows cannot go red is worse than no gate.

WHAT THIS GATE IS, AND WHY IT IS (B)-SHAPED.

UPSTREAM'S `ops_nvme.py` NEEDS A REAL PCIe NVMe DRIVE, AND **THERE IS NO
UPSTREAM NVMe MOCK** -- MEASURED: `test/mockgpu/` HAS `nv/`, `cuda/`, `am/`,
`amd/` AND **NO `nvme/`**. SO THERE IS NO MOCK TO RUN THE BACKEND AGAINST, AND
THIS GATE COVERS **THE PURE FUNCTIONS**, WHICH IS WHERE THE BUGS ARE:

  * THE SQE'S 64-BYTE LAYOUT AND ITS `opcode | slot << 16` COMMAND WORD
  * THE COMPLETION QUEUE'S **PHASE BIT** AND WHEN IT INVERTS
  * THE DOORBELLS' `2 * qid` STRIDE
  * THE PRP TABLE'S PAGE/LIST INTERLEAVING AND ITS `(p + 1)` POINTER
  * THE WAVE STRIDE OF `q.entries - 1` AND THE ONE FREE SLOT
  * THE LBA STEP **IN BLOCKS AND NOT IN BYTES**
  * THE THIRD PRP ENTRY, WHICH APPEARS **ONLY** FOR EXACTLY TWO PAGES
  * THE `max_xfer`'s `or 8` AND ITS `min(..., 8)` CAP
  * THE `lba_shift`'s `+ 2` (THE LOW BYTE OF A FOUR-BYTE ENTRY)
  * THE QUEUE CREATION'S ZERO-BASED SIZE FIELD

EVERY ONE OF THOSE IS A FUNCTION OF ITS ARGUMENTS ALONE, AND EVERY ONE IS
WHAT A WRONG PORT GETS WRONG. THE RULES THAT NEED A DRIVE ARE NAMED IN
`ops_nvme.bend`'s OWN FOOTER WITH THE SEAM THAT BLOCKS THEM, AND NONE OF THEM
IS A ROW HERE.

THE ROWS ARE 206 AND THEY ARE ALL COMPARED, because every row in the file is
a pure-function row and every one of them has a CPython counterpart.

WHAT THE ORACLE IS, AND WHY IT IS NOT A TRANSCRIPTION.

`gates/ops-nvme-oracle.py` CALLS **UPSTREAM'S OWN CODE**:

  * `prp_table` IS **UPSTREAM'S OWN FUNCTION**, RUN AGAINST A SHIM WHOSE
    `pci_dev.alloc_sysmem` RETURNS A `bytearray`. UPSTREAM'S OWN CODE
    PRODUCES THE ENTRIES.
  * `NVMEQueue.submit`'s `struct.pack("<IIQQQQII16x", ...)` IS **UPSTREAM'S
    OWN PACK**, RUN AGAINST A SHIM WHOSE `sq` IS A `bytearray`. THE SLOT,
    THE TAIL, THE PACKED WORD AND THE PHASE ALL COME FROM UPSTREAM.
  * THE CONSTANTS ARE READ OUT OF `tinygrad/runtime/autogen/nvme.py` AND
    `NVME_IDS` OUT OF UPSTREAM.

THE SHIM SUPPLIES NO ARITHMETIC. **A HAND-TYPED EXPECTATION IS A
TRANSCRIPTION, AND A TRANSCRIPTION IS A PLACE TO BE WRONG** -- the
`renderer/cstyle.bend` unit shipped 215 hand-typed expectations of which
SEVENTEEN were wrong, twelve of them real port bugs.

AND THE FIRST GATE RUN FOUND **FIVE REAL DEFECTS**, FOUR IN THE PORT AND ONE
IN THE ORACLE. THE PORT'S WERE:

  1. `NVME_VENDOR` WAS **5591** AND `0x15b7` IS **5559**. A HAND-CONVERTED
     HEX CONSTANT.
  2. **THE CAPACITY REGISTER WAS PACKED INTO ONE `U32`**, AND `U32.shln(hi,
     32n)` SATURATES TO ZERO -- SO THE PORT'S DOORBELL STRIDE WAS ALWAYS 4
     AND ITS TIMEOUT WAS ALWAYS THE LOW WORD'S. THE REGISTER IS SIXTY-FOUR
     BITS AND THE PORT NOW SPELLS IT AS TWO WORDS.
  3. **THE PRP ADDRESS'S LOW WORD CAME SECOND.** THE FORMAT IS LITTLE-ENDIAN.
  4. **cdw10 AND cdw11 SAT AT WORDS 8 AND 9**, WHICH IS WHERE THE FOURTH
     SIXTYTY-FOUR-BIT FIELD IS. THEY GO AT **10 AND 11**.
  5. **THE ROW NAME `nvme_sq_db_q1_s1` PRINTED STRIDE 8**, AND THE ROW NAME
     `nvme_cmd_w_2_0` PRINTED SLOT 1. **A ROW WHOSE NAME AND VALUE DISAGREE
     IS A ROW THAT CANNOT BE ADDRESSED.**

AND THE ORACLE'S WAS THE `dev_iter_sig`-SHAPED ONE: IT READ A BYTE PAST THE
END OF A `bytearray` BY INDEXING, WHICH RAISES, WHERE THE PORT RETURNS
**ZERO**. **A PYTHON `bytearray` AND A PORT LIST ARE NOT THE SAME THING AT
THE END, AND THE CLAIM IS ABOUT THE PORT'S ANSWER.**

THE LANES ARE ALIGNED BY ROW NAME, NOT BY POSITION. MEASURED: the port groups
its rows by RULE (eight test functions) and the oracle groups them by
UPSTREAM SOURCE ORDER, so the same 206 rows sit in two different sequences.
A positional diff of that is a wall of "disagreements" that are ZERO
disagreements seen from the wrong axis. `gatekit.Gate(order="by_name")` IS
THE MODE, AND ITS COST -- THAT A BY-NAME DIFF CANNOT SEE A ROW THAT MOVED --
IS STATED IN `gatekit.py`'s OWN CLASS DOCSTRING. **THE ORDER OF THESE ROWS IS
NOT A CLAIM**: the order-bearing claims in this file are the WORD ORDERS
(the SQE's words, the PRP table's interleaving) and every one of them is a
row whose VALUE is a comma-separated list.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE PORT LANE PRINTS A SENTINEL ROW, `nvme-done=1`, AND THE ORACLE DOES
# NOT. IT IS A PORT-ONLY ROW AND `gatekit`'s `port_only` IS EXACTLY THE
# CATEGORY FOR IT: "present in the port, absent from the oracle", and the
# derived oracle count `rows - len(port_only)` HOLDS THE ABSENCE. SO THE
# PORT LANE HAS 207 ROWS AND THE ORACLE LANE HAS 206.
GATE = Gate(
    "ops-nvme-gate",
    bend="tinybendygrad/runtime/ops_nvme.bend",
    oracle="gates/ops-nvme-oracle.py",
    rows=207,
    compared=206,
    port_only=["nvme-done"],
    order="by_name",
)

if __name__ == "__main__":
    sys.exit(main(GATE, "ops-nvme-gate: 206 rows compared -- the NVMe backend's pure "
                        "functions agree with CPython"))
