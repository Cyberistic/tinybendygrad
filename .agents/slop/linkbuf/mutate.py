#!/usr/bin/env python
"""THE MUTATIONS for the `link_bufs` / `link_buffer` port, and the rows each one
moves.  Measured, not asserted: every mutation is a textual edit of
`tinybendygrad/device.bend`, the mutant is compiled and RUN in a scratch
directory (so the substrate digest does not move), and the rows are diffed
against the baseline.

THE PLANT -- the four ways this could be wrong, and the mutation that is the
plant for each:

  A BUFFER ADDED TWICE            `link_add` PREPENDS instead of appending, so
                                  the scan finds the OLDER of two entries.
                                  Upstream's `dict.update` OVERWRITES, so the
                                  NEWER one wins: `lk_buf_dup` 6 -> 5.

  A BUFFER ADDED TO THE WRONG LIST the two accumulators are SWAPPED, so the
                                  plain key's hit is read as the device-scoped
                                  one and vice versa. The device-scoped key is
                                  a FOLD of the device string, so the wrong
                                  list also makes one device's entry visible to
                                  another: `lk_lvl_plain`, `lk_lvl_dev`,
                                  `lk_lvl_wrongdev`.

  A LIST MUTATED IN PLACE WHEN THE
  CALLER EXPECTED A COPY          the two registry keys are SWAPPED, so the
                                  device-scoped lookup is asked FIRST: the
                                  plain name stops winning: `lk_lvl_both`.

  A NULL BUFFER                   the alloc with NO name is treated as a miss
                                  instead of a FRESH buffer, and the base
                                  class's `None` answer is treated as a
                                  buffer: `lk_lvl_unnamed`, `lk_lvl_none`.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SRC = os.path.join(ROOT, "tinybendygrad", "device.bend")
LOCK = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/bend.lock"
# The scratch tree is OUTSIDE `tinybendygrad/`, so a mutant never enters the
# substrate digest's population (`tinybendygrad/**.bend`) and measuring a
# mutation cannot make the tree look stale.
SCRATCH = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"

# (name, the text to find, the text to put in its place)
MUTATIONS = [
    (
        "link_add PREPENDS (a buffer added twice: the OLDER wins)",
        "List.append(&2, Lk, regs, [Lk{name, kind, buf}])",
        "List.append(&2, Lk, [Lk{name, kind, buf}], regs)",
    ),
    (
        "the two hits are SWAPPED (a buffer added to the wrong list)",
        "    case LkTwo{h1, h2}: link_plain(level, h1, h2, hook)",
        "    case LkTwo{h1, h2}: link_plain(level, h2, h1, hook)",
    ),
    (
        "the two registry keys are SWAPPED (a copy instead of a shared list)",
        "    case Some{+n}: link_two(1, link_scan(regs, n, to_name([dev, n])), hook)",
        "    case Some{+n}: link_two(1, link_scan(regs, to_name([dev, n]), n), hook)",
    ),
    (
        "an unnamed alloc is a MISS (a null buffer)",
        "    case None{}: LkRes{0, 2, 0}",
        "    case None{}: LkRes{4, 2, 0}",
    ),
    (
        "the base class's None answer becomes a buffer (a null buffer)",
        "        case False{}: LkRes{4, 2, 0}",
        "        case False{}: LkRes{3, 2, 0}",
    ),
    (
        "to_name does not lower-case",
        "  String.to_lower(String.from_list(tn.go(List.length(&2, Char, String.to_list(s)), String.to_list(s), Nil{})))",
        "  String.from_list(tn.go(List.length(&2, Char, String.to_list(s)), String.to_list(s), Nil{}))",
    ),
    (
        "to_name does not fold the colon",
        "  List.append(&2, Char, acc, [Bool.pick(Char, Char.is_eq(h, COLON_C()), UNDER_C(), h)])",
        "  List.append(&2, Char, acc, [h])",
    ),
    (
        "the device-scoped key forgets the device",
        "    case Some{+n}: link_two(1, link_scan(regs, n, to_name([dev, n])), hook)",
        "    case Some{+n}: link_two(1, link_scan(regs, n, n), hook)",
    ),
]


def lock():
    t0 = time.time()
    while True:
        try:
            os.mkdir(LOCK)
            return t0
        except FileExistsError:
            time.sleep(2)


def unlock():
    try:
        os.rmdir(LOCK)
    except OSError:
        pass


def run_bend(path):
    t0 = lock()
    try:
        p = subprocess.run(["./bin/bend", path], cwd=ROOT, capture_output=True, text=True)
    finally:
        unlock()
    return t0, p


def rows_of(text):
    out = {}
    for ln in text.splitlines():
        ln = ln.strip()
        if "=" in ln and " " not in ln.split("=", 1)[0]:
            k, v = ln.split("=", 1)
            out[k] = v
    return out


def main():
    src = open(SRC).read()
    mut_root = tempfile.mkdtemp(prefix="linkbuf-mut-", dir=SCRATCH)
    mut = os.path.join(mut_root, "device.bend")
    os.makedirs(os.path.join(mut_root, "LAWS"), exist_ok=True)
    shutil.copy(os.path.join(ROOT, "tinybendygrad", "LAWS", "spec.bend"), os.path.join(mut_root, "LAWS", "spec.bend"))
    try:
        return run_muts(src, mut)
    finally:
        shutil.rmtree(mut_root, ignore_errors=True)


def run_muts(src, mut):
    open(mut, "w").write(src)
    t0, p = run_bend(mut)
    print(f"baseline: bend waited {time.time()-t0:.1f}s rc={p.returncode}")
    if p.returncode != 0:
        print(p.stdout[-2000:], p.stderr[-2000:])
        return 1
    base = rows_of(p.stdout)

    print()
    print("| mutation | rows moved | how many |")
    print("| --- | --- | --- |")
    for name, find, repl in MUTATIONS:
        if src.count(find) != 1:
            print(f"| {name} | ANCHOR NOT UNIQUE ({src.count(find)}) | 0 |")
            continue
        open(mut, "w").write(src.replace(find, repl))
        t0, p = run_bend(mut)
        if p.returncode != 0:
            print(f"| {name} | DOES NOT COMPILE | 0 |")
            print(p.stdout[-1500:], p.stderr[-1500:])
            continue
        mutant = rows_of(p.stdout)
        moved = sorted(k for k in base if k in mutant and base[k] != mutant[k])
        shown = ", ".join(f"`{k}`" for k in moved)
        print(f"| {name} | {shown or 'NOTHING'} | {len(moved)} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
