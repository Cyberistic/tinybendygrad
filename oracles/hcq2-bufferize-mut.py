#!/usr/bin/env python
"""THE PLANT for `bufferize_buf` -- the ways it could be wrong, and one edit for each.

    .venv/bin/python oracles/hcq2-bufferize-mut.py

A PLANT is a DEFECT INJECTED INTO THE PORT and the ROWS IT MOVES. A mutation
that moves nothing at rc=0 is a COVERAGE GAP -- the row that would have caught
the defect does not exist -- and that is the difference this harness exists to
keep: "0 rows moved" and "the gate is green" are not the same claim.

THE MUTANT IS A COPY OUTSIDE `tinybendygrad/`, because a `.bend` file imports
its neighbours RELATIVE TO ITS OWN PATH (a copy in a tmpdir cannot resolve
them and answers "the substrate did not warm"), and because a mutant must not
enter the substrate digest's population. EVERY RUN HOLDS THE BEND LOCK, so two
compilers never run at once.

THE FIVE WAYS THE BRIEF NAMES, AND THE EDIT THAT INJECTS EACH:

  A BUFFER ADDED TWICE            `link_add` PREPENDS, so the scan finds the
                                  OLDER of two entries. Upstream's
                                  `dict.update` OVERWRITES, so the NEWER one
                                  wins.
  THE WRONG LIST                  the two accumulators are SWAPPED, so the
                                  plain key's hit is read as the device-scoped
                                  one. The device-scoped key is a FOLD of the
                                  device, so the wrong list also makes one
                                  device's entry visible to another.
  A NULL BUFFER                   the base class's `None` answer is treated as
                                  a buffer; and the alloc with NO name is
                                  treated as a miss instead of a FRESH buffer.
  THE DEVICE-SCOPED KEY FORGETS   `to_name(dev, name)` becomes `name`, so the
  THE DEVICE                      device-scoped entry is findable from any
                                  device.
  THE REGISTRY ENTRY SHADOWS      the device's own hook is asked BEFORE the
  THE DEVICE'S OWN HOOK           registry, so the hook wins a case upstream
                                  gives to the registry.

AND THE LOAD-BEARING SIZE: a LINKED buffer RESIZED TO FIT THE ALLOC, which
upstream never does -- the `owned` branch hands the registry's buffer straight
to `UOp.from_buffer`, and there is no `max_numel` on that path.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/bend.lock")
DRIVER = "tinybendygrad/runtime/support/hcq2.bend"
NEEDED = ("tinybendygrad/helpers.bend", "tinybendygrad/device.bend",
          "tinybendygrad/LAWS/spec.bend", DRIVER)

# (name, the file to edit, the text to find, the text to put in its place)
MUTATIONS = [
    ("A BUFFER ADDED TWICE -- the OLDER registration wins",
     "tinybendygrad/device.bend",
     "  List.append(&2, Lk, regs, [Lk{name, kind, buf}])",
     "  List.append(&2, Lk, [Lk{name, kind, buf}], regs)"),
    ("THE WRONG LIST -- the plain and device-scoped hits are swapped",
     "tinybendygrad/device.bend",
     "    case LkTwo{h1, h2}: link_plain(level, h1, h2, hook)",
     "    case LkTwo{h1, h2}: link_plain(level, h2, h1, hook)"),
    ("A NULL BUFFER -- the base class's None answer becomes a buffer",
     "tinybendygrad/device.bend",
     "        case False{}: LkRes{4, 2, 0}",
     "        case False{}: LkRes{3, 2, 0}"),
    ("A NULL BUFFER -- the alloc with NO name is treated as a MISS",
     DRIVER,
     "    case D.BFound{ar, i}: Bz{ar, 0, 2, i, U32.mul(n, S.Dt.itemsize(dt)), dev}",
     "    case D.BFound{ar, i}: Bz{ar, 4, 2, i, U32.mul(n, S.Dt.itemsize(dt)), dev}"),
    ("THE DEVICE-SCOPED KEY FORGETS THE DEVICE",
     "tinybendygrad/device.bend",
     "    case Some{+n}: link_two(1, link_scan(regs, n, to_name([dev, n])), hook)",
     "    case Some{+n}: link_two(1, link_scan(regs, n, n), hook)"),
    ("THE REGISTRY ENTRY SHADOWS THE DEVICE'S OWN HOOK",
     "tinybendygrad/device.bend",
     "def link_plain(level: U32, h1: LkHit, h2: LkHit, hook: Hook) -> LkRes:\n"
     "  match h1:\n"
     "    case LkHit{found, kind, buf}:\n"
     "      match found:\n"
     "        case True{}: LkRes{level, kind, buf}\n"
     "        case False{}: link_dev(level, h2, hook)",
     "def hook_first(hook: Hook, level: U32, kind: U32, buf: U32) -> LkRes:\n"
     "  match hook:\n"
     "    case Hook{has, hbuf}:\n"
     "      match has:\n"
     "        case True{}: LkRes{3, 2, hbuf}\n"
     "        case False{}: LkRes{level, kind, buf}\n"
     "\n"
     "def link_plain(level: U32, h1: LkHit, h2: LkHit, hook: Hook) -> LkRes:\n"
     "  match h1:\n"
     "    case LkHit{found, kind, buf}:\n"
     "      match found:\n"
     "        case True{}: hook_first(hook, level, kind, buf)\n"
     "        case False{}: link_dev(level, h2, hook)"),
    ("A LINKED BUFFER IS RESIZED TO FIT THE ALLOC",
     DRIVER,
     "      bz_pick(level, kind, buf, bz_nb(ar, buf), ar, dev_ix, n, dt)",
     "      bz_pick(level, kind, buf, U32.mul(n, S.Dt.itemsize(dt)), ar, dev_ix, n, dt)"),
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
        p = subprocess.run([str(ROOT / "bin" / "bend"), str(path)],
                           cwd=str(ROOT), capture_output=True, text=True)
    finally:
        unlock()
    return time.time() - t0, p


def rows_of(text):
    out = {}
    for ln in text.splitlines():
        ln = ln.strip()
        if "=" in ln:
            k, v = ln.split("=", 1)
            out[k] = v
    return out


def stage(tmp):
    """The tree the mutant lives in: OUTSIDE `tinybendygrad/`, with the
    relatives the driver imports beside it."""
    for rel in NEEDED:
        dst = tmp / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / rel, dst)
    return tmp / DRIVER


def main():
    base_dir = Path(tempfile.mkdtemp(prefix="bz-mut-", dir="/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"))
    try:
        base_drv = stage(base_dir / "base")
        waited, p = run_bend(base_drv)
        print(f"BASE: bend waited {waited:.0f}s rc={p.returncode}")
        if p.returncode != 0:
            print(p.stdout[-2000:], p.stderr[-2000:])
            return 1
        base = rows_of(p.stdout)
        print(f"BASE: {len(base)} rows\n")
        print("| the failure | the rows that moved | how many |")
        print("| --- | --- | --- |")
        moved_any = 0
        for name, rel, find, repl in MUTATIONS:
            mut_dir = Path(tempfile.mkdtemp(prefix="bz-mut-", dir="/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"))
            try:
                drv = stage(mut_dir)
                src = (ROOT / rel).read_text()
                if src.count(find) != 1:
                    print(f"| {name} | ANCHOR NOT UNIQUE ({src.count(find)}) | 0 |")
                    continue
                (mut_dir / rel).write_text(src.replace(find, repl))
                waited, p = run_bend(drv)
                if p.returncode != 0:
                    print(f"| {name} | DOES NOT COMPILE | 0 |")
                    continue
                mut = rows_of(p.stdout)
                moved = sorted(k for k in base if k in mut and base[k] != mut[k])
                if moved:
                    moved_any += 1
                print(f"| {name} | {', '.join(moved) or 'NOTHING'} | {len(moved)} |")
            finally:
                shutil.rmtree(mut_dir, ignore_errors=True)
        print(f"\n{moved_any} of {len(MUTATIONS)} plants moved a row.")
        return 0
    finally:
        shutil.rmtree(base_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
