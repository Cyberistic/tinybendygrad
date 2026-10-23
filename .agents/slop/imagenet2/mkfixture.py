#!/usr/bin/env python3
"""Build the FAKE ImageNet tree the probe and the oracle read.

NO REAL DATA AND NO DOWNLOAD: every file here is a one-line placeholder written
by this script. The tree is built to exercise the four things CPython's
`glob.glob` and the port's expansion must agree on:

  1. a class directory with two files            -> both are in the answer
  2. a HIDDEN class directory (`.hidden`)         -> in NEITHER (glob's `*` does
                                                    not match a leading dot)
  3. a loose FILE at depth one (`loose.txt`)      -> in NEITHER (`train/*` names
                                                    it, but `train/*/*` under it
                                                    is not a directory)
  4. a class directory with no files (`empty`)    -> in NEITHER (it contributes
                                                    nothing, it is not an error)
  5. a DIRECTORY at depth two (`subdir`)          -> in BOTH (glob's `*` matches
                                                    a directory too)

The class index is the REAL file's shape (`{"0": ["tench", 0], ...}`) with three
classes, and the MOCK's shape (`{"0": ["0", "0"], ...}`) is exercised by the
second fixture the probe reads.
"""
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)

# The real shape: the key is the class index, the value's first element is the
# wnid, the value's second element is the index again.
(root / "imagenet_class_index.json").write_text(
    json.dumps({"0": ["tench", 0], "1": ["goldfish", 1], "2": ["great white shark", 2]}) + "\n")

# The mock's own shape (`extra/datasets/fake_imagenet_from_mnist.py:26`).
mock = root / "mock"
mock.mkdir(exist_ok=True)
(mock / "imagenet_class_index.json").write_text(
    json.dumps({str(i): [str(i), str(i)] for i in range(3)}) + "\n")

# A tree with an EMPTY `train/`: the directory is there and holds nothing, which
# is upstream's `FileNotFoundError` and NOT the same as a missing directory.
empty = root / "empty"
(empty / "train").mkdir(parents=True, exist_ok=True)

files = {
    "train/n01440764/n01440764_10026.JPEG": "placeholder\n",
    "train/n01440764/n01440764_10027.JPEG": "placeholder\n",
    "train/n01443537/n01443537_10007.JPEG": "placeholder\n",
    "train/loose.txt": "placeholder\n",
    "train/.hidden/hidden.JPEG": "placeholder\n",
    "train/empty/.keep": "placeholder\n",
    "val/n01440764/n01440764_10026.JPEG": "placeholder\n",
    "val/n01443537/n01443537_10007.JPEG": "placeholder\n",
}
for rel, body in files.items():
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body)

# A directory AT DEPTH TWO: glob's `*` matches it and so must the port.
(root / "train" / "n01440764" / "subdir").mkdir(exist_ok=True)

print(f"fixture at {root}")
for p in sorted(root.rglob("*")):
    print(f"  {p.relative_to(root)}")
