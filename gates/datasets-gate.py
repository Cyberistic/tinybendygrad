#!/usr/bin/env python3
"""datasets-gate.py -- the gate for `tinybendygrad/nn/datasets.bend`.

    .venv/bin/python gates/datasets-gate.py

77 rows, all compared, 0 disagreements.

WHAT THE ROWS CLAIM. `nn/datasets.py` at the pin is eleven lines: the MNIST and
Fashion URLs, the two hard-coded header skips, the two reshapes, and CIFAR's
`reshape(-1, 3073)` with `train[:, 1:]` / `train[:, 0]`. Every one of those is a
NUMBER, and a number can be wrong without failing to compile -- so the rows are
the arithmetic and the oracle is the same arithmetic reached from the other
side.

THE ORACLE IMPORTS NOTHING FROM `tinygrad`, ON PURPOSE. `mnist()` never reads
the IDX header, so every claim is either a literal from `nn/datasets.py`'s text
or arithmetic over the PUBLISHED file sizes. A shared helper would only let a
mis-transcription travel, and this tree has measured that cost: the
`renderer/cstyle.bend` unit shipped 215 hand-typed expectations and SEVENTEEN
were wrong.

THE LANES ARE ALIGNED BY ROW NAME. The port groups its rows by RULE (four `t_*`
walks) and the oracle by SOURCE ORDER, so the same 77 rows sit in two different
sequences -- and a positional diff of that is a wall of disagreements that are
zero disagreements seen from the wrong axis. What `by_name` costs is stated in
`gatekit.py`: a by-name diff cannot see a row that MOVED, and the order of these
rows is not a claim. Every order-bearing claim here is a row whose VALUE is a
comma-separated list.

WHAT THE ORACLE HAD TO BE REPAIRED FOR, AND IT IS THREE DEFECTS, NOT ONE.
MEASURED 2026-11-11, and every one of them was a row that could not go red:

  1. `CIFAR_LABEL_OFF` read 1. Upstream's `train[:, 0]` is the LABEL and
     `train[:, 1:]` is the IMAGE, so the label's offset is ZERO. The oracle's 1
     was the IMAGE's offset under the label's name, and the row
     `dst_cifar_label_off` said so -- against the port, which said 0.
  2. `dst_cifar_split` and `dst_cifar_image_named` subtracted the label's
     offset where the arithmetic subtracts the ONE label BYTE. 3073 - 1 == 3072
     is the image width; 3073 - 0 == 3073 is not.
  3. The oracle had NO `.npy` LANE AT ALL: it printed 45 rows and the port
     printed 76, so the 31 missing rows read as disagreements about the rows
     they shared. And its `file_bytes` was `header + payload` -- 10 bytes
     short, because the `.npy` magic was missing.

AND THE PORT WAS WRONG ON ONE ROW, TOO: `dst_cifar_split` subtracted the
label's offset. It now subtracts the one label byte, and the two lanes agree on
all 77.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

GATE = Gate(
    "datasets-gate",
    bend="gates/datasets-gate.bend",
    oracle="gates/datasets-oracle.py",
    rows=77,
    compared=77,
    order="by_name",
)

if __name__ == "__main__":
    sys.exit(main(GATE, "datasets-gate: 77 rows compared -- the dataset URLs, "
                        "header skips, reshapes and .npy headers agree"))
