#!/usr/bin/env python3
"""Mutation harness for the two .bend files this unit owns.

One edit per run, applied IN PLACE, the interpreted lane is run, and the baseline is
diffed. Two columns matter and they answer different questions:

  MOVED    row NAMES that appeared or disappeared  -- a mutation the gate does not
           notice at all.
  CHANGED  rows present in both whose VALUE differs -- the gate noticed.

`moved == 0 and changed == 0` is the interesting result: it means the mutation is
invisible, and per the recorded lesson that is a MISSING ROW rather than a passing
test. Those are reported as BLIND SPOTS and each one is a claim about what the gate
does not see.

    python3 .agents/slop/dk-mutate.py             # every mutation
    python3 .agents/slop/dk-mutate.py M7 M12      # a subset
    python3 .agents/slop/dk-mutate.py --list      # the table, unrun
    python3 .agents/slop/dk-mutate.py --table     # the table WITH measurements

M0 IS THE CONTROL: a comment-only edit, which by construction must move nothing. A
table with no row that CANNOT move is a table of coincidences.

The edit is applied IN PLACE and then reverted, rather than to a scratch copy,
because `ops_disk.bend` does `import ./../device.bend` and `import ./../helpers.bend`
-- a copy outside the tree cannot resolve them. The revert is in a `finally`, so a
mutation that fails to compile still leaves the file intact.
"""

import os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, "bin", "bend")
FILES = {"ops_disk": "tinybendygrad/runtime/ops_disk.bend",
         "datasets": "tinybendygrad/nn/datasets.bend"}

# (id, file, old, new, what it is testing)
DK = [
  ("M0",  "ops_disk", "# THE CONSTANTS, AND EVERY ONE OF THEM IS A *PLATFORM FACT* WITH TWO CELLS.",
                     "# THE CONSTANTS, AND EVERY ONE OF THEM IS A *PLATFORM FACT* WITH TWO CELLS. (control)",
           "CONTROL: a comment-only edit, which must move nothing"),
  # ---- the naming table, :26 / :28 -------------------------------------------
  ("M1",  "ops_disk", 'def DISK_PREFIX() -> String: "disk:"', 'def DISK_PREFIX() -> String: "disk"',
           ":26 strips len(\"disk:\")"),
  ("M2",  "ops_disk", "String.drop(name, String.length(DISK_PREFIX()))", "name",
           ":26's slice -- the prefix is stripped, not the string dropped"),
  ("M3",  "ops_disk", 'def SHM_PREFIX() -> String: "shm:"', 'def SHM_PREFIX() -> String: "shm"',
           ":29 strips len(\"shm:\")"),
  ("M4",  "ops_disk", 'String.concat(["/", dsk_lstrip(String.drop(fn, String.length(SHM_PREFIX())))])',
                     'String.concat(["", dsk_lstrip(String.drop(fn, String.length(SHM_PREFIX())))])',
           ":29's leading slash is UNCONDITIONAL"),
  ("M5",  "ops_disk", "      +keep: Bool = Bool.or(seen, Bool.not(cut))", "      +keep: Bool = Bool.not(cut)",
           "`:29`'s `lstrip(\"/\")` -- a slash is dropped only BEFORE anything is kept"),
  ("M6",  "ops_disk", "def dev_is_shm(name: String, win: Bool) -> Bool:\n  Bool.and(Bool.not(win), String.starts_with(dsk_filename(name), SHM_PREFIX()))",
                     "def dev_is_shm(name: String, win: Bool) -> Bool:\n  Bool.and(True{}, String.starts_with(dsk_filename(name), SHM_PREFIX()))",
           ":28's `sys.platform != \"win32\"` conjunct"),
  ("M7",  "ops_disk", "def dev_is_shm(name: String, win: Bool) -> Bool:\n  Bool.and(Bool.not(win), String.starts_with(dsk_filename(name), SHM_PREFIX()))",
                     "def dev_is_shm(name: String, win: Bool) -> Bool:\n  Bool.and(Bool.not(win), String.starts_with(name, SHM_PREFIX()))",
           ":28 tests the SLICED filename, not the device string"),
  # ---- the flags, :33 / :34 / :81 / :39 / :103 -------------------------------
  ("M8",  "ops_disk", "def o_creat(osx: Bool) -> U32: Bool.pick(U32, osx, O_CREAT_MACOS(), O_CREAT_LINUX())",
                     "def o_creat(osx: Bool) -> U32: Bool.pick(U32, osx, O_CREAT_MACOS(), O_CREAT_MACOS())",
           "O_CREAT's TWO CELLS"),
  ("M9",  "ops_disk", "def o_direct(osx: Bool) -> U32: Bool.pick(U32, osx, O_DIRECT_MACOS(), O_DIRECT_LINUX())",
                     "def o_direct(osx: Bool) -> U32: Bool.pick(U32, osx, O_DIRECT_LINUX(), O_DIRECT_LINUX())",
           "`getattr(os,\"O_DIRECT\",0)` -- macOS has NO such attribute"),
  ("M10", "ops_disk", "def open_direct(osx: Bool, has: Bool) -> U32: Bool.pick(U32, has, o_direct(osx), 0)",
                     "def open_direct(osx: Bool, has: Bool) -> U32: o_direct(osx)",
           ":33 asks for O_DIRECT -- the `getattr` presence is a SECOND variable"),
  ("M11", "ops_disk", "def open_flags(osx: Bool, direct: U32) -> U32:\n  U32.or(O_RDWR(), U32.or(o_creat(osx), direct))",
                     "def open_flags(osx: Bool, direct: U32) -> U32:\n  U32.or(O_RDWR(), U32.or(o_creat(osx), 0))",
           ":34's RETRY drops O_DIRECT and :33's ASK does not -- and BOTH are recorded"),
  ("M12", "ops_disk", "def map_locked(osx: Bool) -> U32: Bool.pick(U32, osx, 0, MAP_LOCKED_LINUX())",
                     "def map_locked(osx: Bool) -> U32: Bool.pick(U32, osx, MAP_LOCKED_LINUX(), 0)",
           ":81's `0x2000` cell"),
  ("M13", "ops_disk", "def map_populate(osx: Bool) -> U32: Bool.pick(U32, osx, 0, MAP_POPULATE_LINUX())",
                     "def map_populate(osx: Bool) -> U32: Bool.pick(U32, osx, MAP_POPULATE_LINUX(), 0)",
           ":81's `getattr(mmap,\"MAP_POPULATE\", 0x008000)` cell"),
  ("M14", "ops_disk", "            U32.or(MAP_SHARED(), U32.or(MAP_POPULATE_LINUX(), MAP_LOCKED_LINUX())))",
                     "            U32.or(MAP_SHARED(), MAP_POPULATE_LINUX()))",
           ":30 ORs THREE flags"),
  ("M15", "ops_disk", "def madv_hp(osx: Bool) -> U32: Bool.pick(U32, osx, 0, MADV_HUGEPAGE_LINUX())",
                     "def madv_hp(osx: Bool) -> U32: MADV_HUGEPAGE_LINUX()",
           ":39's `getattr` -- macOS has NO MADV_HUGEPAGE, so the value there is 0"),
  ("M16", "ops_disk", "def pagesize(osx: Bool) -> U32:\n  Bool.pick(U32, osx, PAGESIZE_MACOS(), PAGESIZE_LINUX())",
                     "def pagesize(osx: Bool) -> U32: PAGESIZE_LINUX()",
           ":103's `mmap.PAGESIZE` -- 4096 on linux, 16384 on macOS/arm64"),
  # ---- the open, :29-40 ------------------------------------------------------
  ("M17", "ops_disk", "  +e: Dev = dev_put(d, Tr.emit(K_OPEN_DIRECT(), open_flags(osx, dr), Dev.tr(d)))\n  dev_fd(f, dev_put(e, Tr.emit(K_OPEN(), open_flags(osx, 0), Dev.tr(e))))",
                     "  +e: Dev = dev_put(d, Tr.emit(K_OPEN_DIRECT(), open_flags(osx, dr), Dev.tr(d)))\n  dev_fd(f, dev_put(e, Tr.emit(K_OPEN(), open_flags(osx, dr), Dev.tr(e))))",
           ":33 and :34 RECORD BOTH ATTEMPTS -- the try/except is not a branch"),
  ("M18", "ops_disk", "  dev_fd(f, dev_put(e, Tr.emit(K_OPEN(), open_flags(osx, 0), Dev.tr(e))))",
                     "  dev_put(e, Tr.emit(K_OPEN(), open_flags(osx, 0), Dev.tr(e)))",
           ":33's answer is `self.fd`, and it is 4 on the unreset fixture"),
  ("M19", "ops_disk", "def dev_file.trunc.go(trunc: Bool, +size: U32, +d: Dev) -> Dev:\n  match trunc:\n    case True{}:\n      dev_put(d, Tr.emit(K_FTRUNCATE(), size,\n        Tr.emit(K_FSTAT(), Dev.stsize(d), Dev.tr(d))))\n    case False{}:\n      dev_put(d, Tr.emit(K_FSTAT(), Dev.stsize(d), Dev.tr(d)))",
                     "def dev_file.trunc.go(trunc: Bool, +size: U32, +d: Dev) -> Dev:\n  match trunc:\n    case True{}:\n      dev_put(d, Tr.emit(K_FSTAT(), Dev.stsize(d),\n        Tr.emit(K_FTRUNCATE(), size, Dev.tr(d))))\n    case False{}:\n      dev_put(d, Tr.emit(K_FSTAT(), Dev.stsize(d), Dev.tr(d)))",
           ":35's `fstat` runs BEFORE the `ftruncate` it decides"),
  ("M20", "ops_disk", "  match block:\n    case True{}:  d\n    case False{}: dev_file.trunc.go(trunc, size, d)",
                     "  match block:\n    case True{}:  dev_file.trunc.go(trunc, size, d)\n    case False{}: dev_file.trunc.go(trunc, size, d)",
           ":35's `and` SHORT-CIRCUITS -- a block device never stats the file"),
  ("M21", "ops_disk", "def dev_trunc(+size: U32, +d: Dev) -> Bool: U32.is_lt(Dev.stsize(d), size)",
                     "def dev_trunc(+size: U32, +d: Dev) -> Bool: U32.is_gt(Dev.stsize(d), size)",
           ":35's `st_size < size` -- the direction"),
  ("M22", "ops_disk", "def dev_file.mmap.at(+size: U32, +t: Tr, d: Dev) -> Dev:\n  dev_put(d, Tr.emit(K_MMAP(), size, t))",
                     "def dev_file.mmap.at(+size: U32, +t: Tr, d: Dev) -> Dev:\n  dev_put(d, Tr.emit(K_MMAP(), 0, t))",
           ":36 maps with NO flags -- the trace argument is the SIZE, and 0 is the answer a port that recorded flags would give"),
  ("M23", "ops_disk", "def dev_sized(+size: U32, d: Dev) -> Dev:\n  match d:\n    case Dev{name, _, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:\n      Dev{name, size, True{}, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}",
                     "def dev_sized(+size: U32, d: Dev) -> Dev:\n  match d:\n    case Dev{name, size, hs, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}:\n      Dev{name, size, True{}, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}",
           ":37's ASSIGNMENT -- the binder shadowing the parameter makes it a no-op"),
  ("M24", "ops_disk", "def dev_finish.at(madv: Bool, +size: U32, +d: Dev) -> Dev:\n  Bool.pick(Dev, madv, dev_finish.on(size, d), dev_finish.off(size, d))",
                     "def dev_finish.at(madv: Bool, +size: U32, +d: Dev) -> Dev:\n  Bool.pick(Dev, madv, dev_finish.off(size, d), dev_finish.on(size, d))",
           ":38's `hasattr(self.mem,'madvise') and ... is not None`"),
  # ---- the close, :41-49 -----------------------------------------------------
  ("M25", "ops_disk", "  dev_might_close.at(U32.is_zero(Dev.refcount(e)), e)",
                     "  dev_might_close.at(U32.is_zero(Dev.refcount(d)), d)",
           ":42 decrements BEFORE :43 tests -- THE ORDER IS THE FUNCTION"),
  ("M26", "ops_disk", "  Bool.pick(Dev, has_fd, dev_put(d, Tr.emit(K_CLOSE(), Dev.fd(d), Dev.tr(d))), d)",
                     "  Bool.pick(Dev, has_fd, d, dev_put(d, Tr.emit(K_CLOSE(), Dev.fd(d), Dev.tr(d))))",
           ":44's `if self.fd is not None` -- the shm branch has no fd"),
  ("M27", "ops_disk", "  Bool.pick(Dev, has_mem, dev_put(d, Tr.emit(K_MUNMAP(), Dev.size(d), Dev.tr(d))), d)",
                     "  Bool.pick(Dev, has_mem, dev_put(d, Tr.emit(K_MUNMAP(), 0, Dev.tr(d))), d)",
           ":47's `self.mem.close()` and the SIZE it unmaps is `self.size`"),
  ("M28", "ops_disk", "      Dev{name, 0, False{}, fd, hf, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}",
                     "      Dev{name, 0, False{}, 0, False{}, rc, hm, tr, io, osx, win, dr, bd, mv, ss, t}",
           ":49 clears ONLY `size` -- `mem` and `fd` SURVIVE the close"),
  # ---- the buffer, the transfers, :73-99 --------------------------------------
  ("M29", "ops_disk", "def db_window(+b: Db) -> Win: Win{Db.offset(b), Db.size(b)}",
                     "def db_window(+b: Db) -> Win: Win{0, Db.size(b)}",
           ":79's `memoryview(mem)[offset:offset+size]` -- the WINDOW carries the offset"),
  ("M30", "ops_disk", "def alloc_copyout.at(arm: Bool, +chunks: List<&2, U32>, +b: Db, +d: Dev) -> Roff:\n  match arm:\n    case True{}:  alloc_copyout.osx(chunks, Db.offset(b), Dev.fd(d), d)",
                     "def alloc_copyout.at(arm: Bool, +chunks: List<&2, U32>, +b: Db, +d: Dev) -> Roff:\n  match arm:\n    case True{}:  alloc_copyout.osx(chunks, 0, Dev.fd(d), d)",
           ":95's `fo.seek(src.offset)` -- the SEEK lands at the buffer's offset"),
  ("M31", "ops_disk", "  alloc_copyout.at(Bool.and(Dev.osx(d), Dev.has_fd(d)), chunks, b, d)",
                     "  alloc_copyout.at(Bool.and(Dev.osx(d), True{}), chunks, b, d)",
           ":92's SECOND conjunct -- a `disk:shm:` device has `fd is None`"),
  ("M32", "ops_disk", "      dsk_reads.go(t, List.append(&2, U32, offs, [got]), U32.add(got, c),",
                     "      dsk_reads.go(t, List.append(&2, U32, offs, [U32.add(got, c)]), U32.add(got, c),",
           ":97's `bytes_read` is each read's DESTINATION -- the running sum, not the chunk"),
  # ---- the shard, :101-116. THE RESULT ROWS. ---------------------------------
  ("M33", "ops_disk", "def shard_fd_off(+off: U32, osx: Bool) -> U32: U32.sub(off, shard_minor(off, osx))",
                     "def shard_fd_off(+off: U32, osx: Bool) -> U32: off",
           ":103's `fd_offset = src.offset - minor_offset` -- THE PAGE ALIGNMENT"),
  ("M34", "ops_disk", "  H.round_up_u32(U32.add(size, shard_minor(off, osx)), pagesize(osx))",
                     "  H.round_up_u32(size, pagesize(osx))",
           ":104 ADDS the skew to the size before rounding up"),
  ("M35", "ops_disk", "            U32.div(U32.add(total, U32.sub(seg, 1)), seg))",
                     "            U32.div(total, seg))",
           ":108's `range(0, total, seg)` is a CEIL, not a floor"),
  ("M36", "ops_disk", "  U32.min(U32.min(Sh.seg(sh), U32.sub(Sh.total(sh), off)), shard_raw_third(off, sh))",
                     "  U32.min(Sh.seg(sh), shard_raw_third(off, sh))",
           ":110's SECOND term -- `total_copy_size - off`"),
  ("M37", "ops_disk", "def shard_real(+rd: U32, +moff: U32, +sh: Sh, +cin: U32) -> U32:\n  U32.min(U32.sub(rd, moff), U32.sub(Sh.sz(sh), cin))",
                     "def shard_real(+rd: U32, +moff: U32, +sh: Sh, +cin: U32) -> U32:\n  U32.min(rd, U32.sub(Sh.sz(sh), cin))",
           ":113 subtracts the SKEW -- and only the FIRST segment carries one"),
  ("M38", "ops_disk", "      shard.go(m, U32.add(off, Sh.seg(sh)), U32.add(cin, rl), 0, sh,",
                     "      shard.go(m, U32.add(off, Sh.seg(sh)), U32.add(cin, rd), 0, sh,",
           ":115's `copied_in += real_copy_size` -- NOT the bytes read"),
  ("M39", "ops_disk", "      Bool.and(U32.is_eq(Seg.cin(s), run),\n               shard_contig.go(t, U32.add(run, Seg.real(s))))",
                     "      Bool.and(U32.is_zero(run),\n               shard_contig.go(t, U32.add(run, Seg.real(s))))",
           "CONTIGUITY is a RESULT about the data: consecutive `cin`s tile the request"),
  ("M40", "ops_disk", "def dev_ioring.mmaps(+d: Dev) -> Dev:\n  +a: Dev = dev_put(d, Tr.emit(K_MMAP(), 0, Dev.tr(d)))\n  +b: Dev = dev_put(a, Tr.emit(K_MMAP(), IORING_OFF_CQ_RING(), Dev.tr(a)))\n  dev_put(b, Tr.emit(K_MMAP(), IORING_OFF_SQES(), Dev.tr(b)))",
                     "def dev_ioring.mmaps(+d: Dev) -> Dev:\n  +a: Dev = dev_put(d, Tr.emit(K_MMAP(), IORING_OFF_SQES(), Dev.tr(d)))\n  +b: Dev = dev_put(a, Tr.emit(K_MMAP(), IORING_OFF_CQ_RING(), Dev.tr(a)))\n  dev_put(b, Tr.emit(K_MMAP(), 0, Dev.tr(b)))",
           ":57-:60's ORDER -- a nested `emit` appends the INNER call first"),
  ("M41", "ops_disk", "  +a: Dev = dev_put(d, Tr.emit(K_MMAP(), 0, Dev.tr(d)))\n  +b: Dev = dev_put(a, Tr.emit(K_MMAP(), IORING_OFF_CQ_RING(), Dev.tr(a)))",
                     "  +a: Dev = dev_put(d, Tr.emit(K_MMAP(), IORING_OFF_CQ_RING(), Dev.tr(d)))\n  +b: Dev = dev_put(a, Tr.emit(K_MMAP(), 0, Dev.tr(a)))",
           ":57 offset 0 comes BEFORE :58 `IORING_OFF_CQ_RING`"),
  ("M42", "ops_disk", "           dev_put(d, Tr.emit(K_IORING_ENTER(), IORING_ENTER_GETEVENTS(),\n             Tr.emit(K_SQE_STORE(), 0, Dev.tr(d)))))",
                     "           dev_put(d, Tr.emit(K_SQE_STORE(), 0,\n             Tr.emit(K_IORING_ENTER(), IORING_ENTER_GETEVENTS(), Dev.tr(d)))))",
           ":128 stores the sqe and :130 enters -- the nesting must put the STORE first"),
]

DST = [
  ("D0",  "datasets", "# tinybendygrad/nn/datasets.bend", "# tinybendygrad/nn/datasets.bend (control)",
           "CONTROL: a comment-only edit, which must move nothing"),
  ("D1",  "datasets", '    case False{}: "https://storage.googleapis.com/cvdf-datasets/mnist/"',
                     '    case False{}: "http://storage.googleapis.com/cvdf-datasets/mnist/"',
           ":5's base_url, the `fashion=False` cell -- HTTPS"),
  ("D2",  "datasets", '    case True{}:  "http://fashion-mnist.s3-website.eu-central-1.amazonaws.com/"',
                     '    case True{}:  "https://fashion-mnist.s3-website.eu-central-1.amazonaws.com/"',
           ":5's base_url, the `fashion=True` cell -- HTTP"),
  ("D3",  "datasets", 'def IMAGES_TRAIN() -> String: "train-images-idx3-ubyte.gz"',
                     'def IMAGES_TRAIN() -> String: "train-images-idx3.gz"',
           ":7's train-images FILE NAME"),
  ("D3",  "datasets", 'def SKIP_IDX3() -> U32: 16', 'def SKIP_IDX3() -> U32: 8',
           ":7's `[0x10:]` -- the IDX3 header is 16 bytes"),
  ("D4",  "datasets", 'def SKIP_IDX1() -> U32: 8', 'def SKIP_IDX1() -> U32: 16',
           ":7's `[8:]` -- the IDX1 header is 8 bytes"),
  ("D5",  "datasets", 'def MN_IMG() -> Shape: Shape{True{}, [1, 28, 28]}',
                     'def MN_IMG() -> Shape: Shape{True{}, [28, 28]}',
           ":7's `reshape(-1,1,28,28)` -- the channel dimension is EXPLICIT"),
  ("D6",  "datasets", 'def CF_IMG() -> Shape: Shape{True{}, [3, 32, 32]}',
                     'def CF_IMG() -> Shape: Shape{True{}, [32, 32]}',
           ":14's `reshape(-1,3,32,32)`"),
  ("D7",  "datasets", "def CIFAR_ROW() -> U32: 3073", "def CIFAR_ROW() -> U32: 3072",
           ":12's `reshape(-1, 3073)` -- ONE LABEL BYTE plus 3072 image bytes"),
  ("D8",  "datasets", 'def CIFAR_LABEL_OFF() -> U32: 1', 'def CIFAR_LABEL_OFF() -> U32: 0',
           ":14's `train[:, 0]` -- the LABEL is the FIRST column"),
  ("D9",  "datasets", '  String.concat(["cifar-10-batches-bin/data_batch_", U32.show(i), ".bin"])',
                     '  String.concat(["cifar-10-batches-bin/data_batch_", U32.show(i)])',
           ":12's f-string suffix"),
  ("D10", "datasets", "def CIFAR_BATCH_ROWS() -> U32: 10000", "def CIFAR_BATCH_ROWS() -> U32: 10001",
           "each CIFAR-10 batch is 10000 rows -- the published size, not in datasets.py"),
  ("D11", "datasets", "  Ds{\"train_images\", IMAGES_TRAIN(), SKIP_IDX3(), 47040016, 784}",
                     "  Ds{\"train_images\", IMAGES_TRAIN(), SKIP_IDX3(), 7840016, 784}",
           "train-images is the 60000-row file, t10k-images is the 10000-row one"),
  ("D12", "datasets", "  Bool.pick(String, Shape.infer(s), String.concat([\"-1,\", ujoin(Shape.rest(s))]),\n            ujoin(Shape.rest(s)))",
                     "  String.concat([\"-1\", ujoin(Shape.rest(s))])",
           "the shape prints as PYTHON would: `-1,1,28,28`, comma inside the `-1` arm"),
]

def run(path):
  r = subprocess.run([BEND, path], capture_output=True, text=True)
  return r.returncode, r.stdout, r.stderr

def parse(text):
  out = {}
  for line in text.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k] = v
  return out

def mutate(entry, base):
  mid, which, old, new, what = entry
  path = os.path.join(ROOT, FILES[which])
  src = open(path).read()
  n = src.count(old)
  if n != 1:
    return None, f"EDIT MATCHES {n} TIMES (need exactly 1)"
  code, out, err = None, None, None
  try:
    open(path, "w").write(src.replace(old, new, 1))
    code, out, err = run(FILES[which])
  finally:
    open(path, "w").write(src)
  if code != 0:
    head = (err or out).strip().splitlines()
    msg = next((l for l in head if l.startswith("Error")), head[0] if head else "?")
    return ("DID NOT COMPILE", msg[:70]), None
  got = parse(out)
  ref = parse(base)
  moved = sorted(set(got) ^ set(ref))
  changed = sorted(k for k in set(got) & set(ref) if got[k] != ref[k])
  return (len(moved), len(changed), moved, changed), None

def main():
  args = [a for a in sys.argv[1:]]
  if "--list" in args:
    for e in DK: print(f"{e[0]:5} {e[1]:9} {e[4]}")
    for e in DST: print(f"{e[0]:5} {e[1]:9} {e[4]}")
    return
  only = [a for a in args if not a.startswith("--")]
  T = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/bt"
  base = {}
  for which, stem in (("ops_disk", "ops_disk"), ("datasets", "datasets")):
    code, out, _ = run(FILES[which])
    if code != 0: print(f"BASELINE FAILS for {which}"); sys.exit(1)
    base[which] = out
  table, blind = [], []
  for e in DK + DST:
    if only and e[0] not in only: continue
    r, err = mutate(e, base[e[1]])
    if err: table.append((e[0], e[4], "ERR", err, "")); continue
    if isinstance(r, tuple) and r[0] == "DID NOT COMPILE":
        table.append((e[0], e[4], "NOBUILD", r[1], "")); continue
    nmv, nch, moved, changed = r
    table.append((e[0], e[4], f"{nmv}/{nch}", ", ".join(moved + changed)[:150], ""))
    if nmv == 0 and nch == 0 and e[0] not in ("M0", "D0"):
      blind.append((e[0], e[4]))
  print(f"{'ID':5} {'MOVED/CHANGED':14} WHAT")
  for mid, what, res, detail, _ in table:
    print(f"{mid:5} {res:14} {what}")
    if detail: print(f"{'':5} {'':14}   -> {detail}")
  print()
  if blind:
    print("BLIND SPOTS -- moved nothing and changed nothing:")
    for mid, what in blind: print(f"  {mid}: {what}")
  else:
    print("BLIND SPOTS: none.")

main()