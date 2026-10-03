# elf_amd_mut.py -- mutation harness for the sort in
# tinybendygrad/renderer/amd/elf.bend. One entry per rule `insert` /
# `sort_pairs` / `param_size` implements, each reported WITH the rows it moved
# BY NAME.
#
# It works on a COPY of the subtree under $SCRATCH (helpers.bend, dsl.bend,
# elf.bend), never the live tree, and it diffs whole `name=value` lines, not row
# names -- a name-comparing harness reported 0 for all 68 mutations in another
# unit. The copy must reproduce the live md5 before any mutation is believed.
#
#   run: .venv/bin/python .agents/slop/elf_amd_mut.py
#
# M1 is the reason `kern.keyorder` exists: M2 through M4 all fold to 16 on
# `kern.sorted` and `kern.unsorted` too, so those two rows are blind to the
# comparison and only `kern.keyorder` sees it.

import hashlib
import os
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(REPO, "bin", "bend")
SCRATCH = os.environ.get("SCRATCH", "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/elfmut")
REL = "renderer/amd/elf.bend"

# (name, old, new) -- each `old` must occur EXACTLY ONCE or the run aborts.
MUTS = [
  ("M1_insert_comparison_flipped",
   "Bool.pick(List<&2, Slot>, U32.is_lt(Slot.slot(p), Slot.slot(h)),",
   "Bool.pick(List<&2, Slot>, Bool.not(U32.is_lt(Slot.slot(p), Slot.slot(h))),"),
  ("M2_sort_dropped",
   "def sort_pairs(xs: List<&2, Slot>) -> List<&2, Slot>: sort_go(xs, Nil{})",
   "def sort_pairs(xs: List<&2, Slot>) -> List<&2, Slot>: xs"),
  ("M3_sorted_by_size_not_slot",
   "Bool.pick(List<&2, Slot>, U32.is_lt(Slot.slot(p), Slot.slot(h)),",
   "Bool.pick(List<&2, Slot>, U32.is_lt(Slot.sz(p), Slot.sz(h)),"),
  ("M4_insert_arms_swapped",
   "List.append(&2, Slot, [p], List.append(&2, Slot, [h], t)),\n        List.append(&2, Slot, [h], insert(p, t)))",
   "List.append(&2, Slot, [h], insert(p, t)),\n        List.append(&2, Slot, [p], List.append(&2, Slot, [h], t)))"),
  ("M5_param_size_arms_swapped",
   "def param_size(alu: Bool, item: U32) -> U32: Bool.pick(U32, alu, item, 8)",
   "def param_size(alu: Bool, item: U32) -> U32: Bool.pick(U32, alu, 8, item)"),
]


def stage():
  shutil.rmtree(SCRATCH, ignore_errors=True)
  os.makedirs(os.path.join(SCRATCH, "renderer/amd"), exist_ok=True)
  for src, dst in (("tinybendygrad/helpers.bend", "helpers.bend"),
                   ("tinybendygrad/renderer/amd/dsl.bend", "renderer/amd/dsl.bend"),
                   ("tinybendygrad/renderer/amd/elf.bend", REL)):
    shutil.copy(os.path.join(REPO, src), os.path.join(SCRATCH, dst))


def run(path):
  out = subprocess.run([BEND, path], cwd=SCRATCH, capture_output=True, text=True).stdout
  rows = {}
  for line in out.splitlines():
    if "=" in line and not line.startswith("elf-done"):
      k, _, v = line.partition("=")
      rows[k] = v
  return rows, hashlib.md5(out.encode()).hexdigest()


def live():
  out = subprocess.run([BEND, os.path.join(REPO, "tinybendygrad/renderer/amd/elf.bend")],
                       capture_output=True, text=True).stdout
  rows = {}
  for line in out.splitlines():
    if "=" in line and not line.startswith("elf-done"):
      k, _, v = line.partition("=")
      rows[k] = v
  return rows, hashlib.md5(out.encode()).hexdigest()


stage()
base_rows, base_md5 = run(REL)
live_rows, live_md5 = live()
print(f"live md5 {live_md5}\ncopy md5 {base_md5}  rows={len(base_rows)} false={sum(1 for v in base_rows.values() if v == 'False')}")
if base_md5 != live_md5:
  print("COPY DOES NOT REPRODUCE THE LIVE BASELINE -- every result below is void")
  sys.exit(1)

src = open(os.path.join(SCRATCH, REL)).read()
for name, old, new in MUTS:
  if src.count(old) != 1:
    print(f"{name}: ABORT, anchor occurs {src.count(old)} times, not 1")
    sys.exit(1)

for name, old, new in MUTS:
  open(os.path.join(SCRATCH, REL), "w").write(src.replace(old, new, 1))
  rows, md5 = run(REL)
  if md5 == base_md5:
    print(f"{name}: moved NOTHING (blind spot)")
  else:
    moved = sorted(k for k in set(base_rows) | set(rows) if base_rows.get(k) != rows.get(k))
    print(f"{name}: moved {len(moved)} row(s): {', '.join(moved)}")
    print(f"    values: {', '.join(f'{k}={rows.get(k, '<absent>')}' for k in moved[:8])}")

open(os.path.join(SCRATCH, REL), "w").write(src)
_, md5 = run(REL)
print(f"restored: md5 {md5} {'==' if md5 == base_md5 else '!='} baseline {base_md5}")