# elf_amd_sort.py -- CPython oracle for the gate rows that
# `tinybendygrad/renderer/amd/elf.bend`'s `insert` / `sort_pairs` / `param_size`
# can move: `kern.sorted` and `kern.unsorted`.
#
# Why a separate file: elf_amd_oracle.py:124-131 folds a list of SIZES that is
# already in order. The Bend rows fold a list of (slot, size) PAIRS and the sort
# runs first, so those two rows are not in elf_amd_oracle.py's output and must be
# derived, not transcribed.
#
# It reproduces elf.py:40 and elf.py:62 verbatim against the real tinygrad
# helpers and the real AddrSpace enum:
#
#   elf.py:40  param_sizes[u.arg.slot] = u.dtype.itemsize if u.addrspace is AddrSpace.ALU else 8
#   elf.py:62  for sz in (param_sizes[i] for i in sorted(param_sizes)):
#                desc.kernarg_size = round_up(desc.kernarg_size, sz) + sz
#
# Every `addrspace` below is the enum MEMBER, not a stand-in: ALU is what makes
# a global's itemsize 8 instead of 4 (the GLOBAL arm of elf.py:40), which is the
# whole reason the fold is not the sum.
#
# THE FIXTURE IS KEYED BY SLOT, never by list position. `param_sizes` is a dict
# (elf.py:38, :40); the fold sorts its KEYS. Building the oracle by zipping
# addrspaces onto the list position is a different fixture and reports a
# different number -- that mistake reported 20 for `kern.unsorted`.
#
#   run: .venv/bin/python .agents/slop/elf_amd_sort.py
# Expect: kern.sorted 16, kern.unsorted 16.

from tinygrad.dtype import AddrSpace
from tinygrad.helpers import round_up

A, G = AddrSpace.ALU, AddrSpace.GLOBAL


def param_size(addrspace, itemsize):
  "elf.py:40, the ternary, with the real enum and the real itemsize."
  return itemsize if addrspace is AddrSpace.ALU else 8


def kernarg(param_sizes):
  "elf.py:62: sorted by SLOT KEY, then the round_up fold over the sizes."
  acc = 0
  for i in sorted(param_sizes):
    acc = round_up(acc, param_sizes[i]) + param_sizes[i]
  return acc


def show(label, by_slot, order):
  """by_slot: slot -> (AddrSpace member, dtype itemsize). order: the Bend
  fixture's list order, so a sort that is dropped is visible."""
  param_sizes = {slot: param_size(a, s) for slot, (a, s) in by_slot.items()}
  sizes = [param_sizes[slot] for slot in order]
  unsorted_acc, acc = 0, 0
  for sz in sizes:
    unsorted_acc = round_up(unsorted_acc, sz) + sz
  print(f"{label}: kernarg={kernarg(param_sizes)}"
        f"  keys={sorted(param_sizes)}  sizes_in_key_order={[param_sizes[i] for i in sorted(param_sizes)]}"
        f"  fixture_list_order={order} sizes_in_list_order={sizes}"
        f"  fold_if_the_sort_is_DROPPED={unsorted_acc}")


# A float32 param is 4 bytes and lands in ALU, so it keeps its itemsize. An i8
# param is 1 byte in ALU. A float32 GLOBAL is 4 bytes and the else arm writes 8.
F32, I64, F64 = 4, 8, 8

# The two Bend rows, read off the fixture list ORDER only -- the sizes come from
# `by_slot`, so nothing about the answer is typed here.
show("kern.sorted",   {0: (A, F32), 1: (A, 1), 2: (G, F32)}, [0, 1, 2])
show("kern.unsorted", {0: (A, F32), 1: (A, 1), 2: (G, F32)}, [2, 0, 1])

# Fixtures that exist only in this oracle, to pin the two claims the rows lean on.
show("kern.keymatters", {0: (A, F64), 1: (A, 1)}, [1, 0])
show("kern.global_only", {0: (G, F32)}, [0])
show("kern.alu_only", {0: (A, F32)}, [0])