#!/usr/bin/env python
"""nvme-mutate.py -- THE THREE NEW MUTATIONS, AND THE ROWS EACH ONE MOVES.

    .venv/bin/python .agents/slop/helpers-device-shrink/nvme-mutate.py

**WHY THIS FILE EXISTS.** `gates/device-gate.bend`'s MUTATION TABLE claims three
new rows:

  | `is_disk_device` drops the `"NVME"` arm of `("DISK", "NVME")` | `disk_nvme`, `disk_nvme_lower`, `disk_nvme_mixed` | 3 |
  | `registry` loses the `nvme` row | `reg_len`, `dcls_nvme`, `dcls_nvme_lower` | 3 |
  | `stems` loses the `NVME` row | `stem_len`, `dcls_nvme`, `dcls_nvme_lower` | 3 |

**AND A TABLE ROW THAT NOBODY MEASURED IS A LABEL.** THE TREE's OWN RULE: "A
mutation that moves nothing is a statement about the GATE and not about the
code, and the only honest response to one is to go and build the fixture or fix
the mutation it is asking for." SO THIS FILE MEASURES THE THREE.

**THE MECHANIC.** THE MUTANT IS COMPILED **IN A SCRATCH DIRECTORY** -- OUTSIDE
`tinybendygrad/` -- SO A MUTATION NEVER MOVES THE SUBSTRATE DIGEST's
POPULATION (`tinybendygrad/**.bend`). THE SCRATCH TREE CARRIES A COPY OF THE
PORT AND OF `LAWS/spec.bend` (WHICH THE PORT IMPORTS), AND THE DRIVER IS
COPIED BESIDE IT WITH ITS IMPORT REBASED ON THE SCRATCH.

**AND IT HOLDS THE BEND LOCK** FOR THE WHOLE RUN, BECAUSE THE MACHINE IS
SHARED AND TWO `bend` PROCESSES AT ONCE IS A MEMORY HAZARD.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PORT = os.path.join(ROOT, "tinybendygrad", "device.bend")
DRIVER = os.path.join(ROOT, "gates", "device-gate.bend")
SPEC = os.path.join(ROOT, "tinybendygrad", "LAWS", "spec.bend")
LOCK = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/bend.lock"
SCRATCH = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"

# (name, the text to find, the text to put in its place)
MUTATIONS = [
    (
        'is_disk_device drops the "NVME" arm of ("DISK", "NVME")',
        '  Bool.or(String.eq(h, "DISK"), String.eq(h, "NVME"))',
        '  String.eq(h, "DISK")',
    ),
    (
        "registry loses the nvme row",
        '   DEnt{15, "rdma", "RDMADevice"}, DEnt{16, "webgpu", "WebGPUDevice"},\n   DEnt{17, "nvme", "NVMEDevice"}]',
        '   DEnt{15, "rdma", "RDMADevice"}, DEnt{16, "webgpu", "WebGPUDevice"}]',
    ),
    (
        "stems loses the NVME row",
        '   AEnt{13, "NVME"}, AEnt{14, "PYTHON"}, AEnt{15, "QCOM"}, AEnt{16, "RDMA"},\n   AEnt{17, "WEBGPU"}]',
        '   AEnt{13, "PYTHON"}, AEnt{14, "QCOM"}, AEnt{15, "RDMA"},\n   AEnt{16, "WEBGPU"}]',
    ),
]


def lock() -> float:
    t0 = time.time()
    while True:
        try:
            os.mkdir(LOCK)
            return t0
        except FileExistsError:
            time.sleep(2)


def unlock() -> None:
    try:
        os.rmdir(LOCK)
    except OSError:
        pass


def rows_of(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for ln in text.splitlines():
        ln = ln.strip()
        if "=" in ln and " " not in ln.split("=", 1)[0]:
            k, v = ln.split("=", 1)
            out[k] = v
    return out


def run_bend(path: str) -> subprocess.CompletedProcess[str]:
    t0 = lock()
    try:
        return subprocess.run(["./bin/bend", path], cwd=ROOT, capture_output=True, text=True)
    finally:
        unlock()


def stage(mut_root: str, port_src: str, driver_src: str) -> str:
    """**THE SCRATCH TREE** -- THE PORT, THE DRIVER, AND `LAWS/spec.bend`."""
    os.makedirs(os.path.join(mut_root, "LAWS"), exist_ok=True)
    shutil.copy(SPEC, os.path.join(mut_root, "LAWS", "spec.bend"))
    port_path = os.path.join(mut_root, "device.bend")
    with open(port_path, "w") as f:
        f.write(port_src)
    # **THE DRIVER's IMPORT OF THE PORT IS REBASED ON THE SCRATCH** -- `./../tinybendygrad/device.bend`
    # IS THE REPO's LAYOUT AND THE SCRATCH HAS NO `tinybendygrad/`.
    driver = re.sub(r"^import \./\.\./tinybendygrad/device\.bend as P$",
                    "import ./device.bend as P", driver_src, flags=re.M)
    driver = re.sub(r"^import \./\.\./tinybendygrad/LAWS/spec\.bend as S$",
                    "import ./LAWS/spec.bend as S", driver, flags=re.M)
    driver_path = os.path.join(mut_root, "device-gate.bend")
    with open(driver_path, "w") as f:
        f.write(driver)
    return driver_path


def main() -> int:
    port_src = open(PORT).read()
    driver_src = open(DRIVER).read()
    mut_root = tempfile.mkdtemp(prefix="nvme-mut-", dir=SCRATCH)
    try:
        driver_path = stage(mut_root, port_src, driver_src)
        p = run_bend(driver_path)
        if p.returncode != 0:
            print("BASELINE FAILED:", p.stdout[-2000:], p.stderr[-2000:])
            return 1
        base = rows_of(p.stdout)
        print(f"baseline: {len(base)} rows")

        print()
        print("| mutation | rows moved | how many |")
        print("| --- | --- | --- |")
        bad = 0
        for name, find, repl in MUTATIONS:
            if port_src.count(find) != 1:
                print(f"| {name} | ANCHOR NOT UNIQUE ({port_src.count(find)}) | 0 |")
                bad += 1
                continue
            driver_path = stage(mut_root, port_src.replace(find, repl), driver_src)
            p = run_bend(driver_path)
            if p.returncode != 0:
                print(f"| {name} | MUTANT DID NOT RUN | 0 |")
                print(p.stdout[-1500:], p.stderr[-1500:])
                bad += 1
                continue
            cur = rows_of(p.stdout)
            moved = sorted(k for k in set(base) | set(cur) if base.get(k) != cur.get(k))
            print(f"| {name} | {', '.join(moved) if moved else 'NOTHING'} | {len(moved)} |")
            if not moved:
                bad += 1
        return 1 if bad else 0
    finally:
        shutil.rmtree(mut_root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
