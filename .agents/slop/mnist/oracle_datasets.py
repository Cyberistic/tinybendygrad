#!/usr/bin/env python3
"""oracle_datasets.py -- THE COMPARER for `tinybendygrad/nn/datasets.bend`'s
`.npy` rows.

    .venv/bin/python .agents/slop/mnist/oracle_datasets.py

WHAT IT COMPARES. The port's `dst_npy_*` rows against the REAL `.npy` files on
disk -- read by numpy, in this repo's `.venv`. The port's numbers are derived
from the `.npy` FORMAT's arithmetic (the header's own length field, the fixed
ten bytes, the shape's product) and the oracle's numbers are read out of the
files. A row that cannot go red is a label, so the rows have to be compared
against something that is not the port.

THE HEADER'S OWN LENGTH IS READ, NOT ASSUMED. `struct.unpack("<H", raw[8:10])`
is the field the format defines, and the file size is checked against
`10 + header_len + payload` -- so a truncated file fails here and not in the
port.

EXIT STATUS: 0 every compared row matched · 1 a row mismatched · 3 a
precondition was absent.
"""
import pathlib
import re
import struct
import subprocess
import sys

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
ROOT = pathlib.Path(__file__).resolve().parents[3]
DATA = HERE / "data"

BEND = ROOT / "bin" / "bend"
PORT = ROOT / "tinybendygrad" / "nn" / "datasets.bend"

ROW = re.compile(r"^(\S+)=(.*)$")

FILES = [
    ("dst_npy_train_images", "mnist_train_images.npy"),
    ("dst_npy_train_labels", "mnist_train_labels.npy"),
    ("dst_npy_t10k_images", "mnist_test_images.npy"),
    ("dst_npy_t10k_labels", "mnist_test_labels.npy"),
]


def port_rows() -> dict[str, str]:
    if not BEND.exists():
        raise FileNotFoundError(f"no {BEND}")
    r = subprocess.run([str(BEND), str(PORT)], capture_output=True, text=True, cwd=str(ROOT))
    if r.returncode != 0:
        raise RuntimeError(f"the port exited {r.returncode}: {r.stderr[-400:]}")
    out = {}
    for line in r.stdout.splitlines():
        m = ROW.match(line.strip())
        if m:
            out[m.group(1)] = m.group(2)
    if not out:
        raise RuntimeError(f"the port printed no rows:\n{r.stdout[-400:]}")
    return out


def npy_facts(path: pathlib.Path) -> dict:
    raw = path.read_bytes()
    magic = raw[:6]
    if magic != b"\x93NUMPY":
        raise RuntimeError(f"{path.name} is not a .npy: magic {magic!r}")
    header_len = struct.unpack("<H", raw[8:10])[0]
    arr = np.load(path, allow_pickle=False)
    return {
        "magic": magic,
        "header_len": header_len,
        "payload": len(raw) - 10 - header_len,
        "file_bytes": len(raw),
        "shape": arr.shape,
        "dtype": arr.dtype,
        "itemsize": arr.dtype.itemsize,
    }


def main() -> int:
    try:
        rows = port_rows()
    except Exception as e:  # noqa: BLE001
        print(f"REFUSED: {type(e).__name__}: {e}", file=sys.stderr)
        return 3

    ok = bad = 0
    for prefix, fname in FILES:
        p = DATA / fname
        if not p.exists():
            print(f"  {prefix}: REFUSED -- no {p}")
            bad += 1
            continue
        f = npy_facts(p)
        checks = [
            ("_file", f["file_bytes"] and fname, rows.get(f"{prefix}_file")),
            ("_shape", ",".join(str(d) for d in f["shape"]), rows.get(f"{prefix}_shape")),
            ("_payload", f["payload"], rows.get(f"{prefix}_payload")),
            ("_file_bytes", f["file_bytes"], rows.get(f"{prefix}_file_bytes")),
        ]
        for suffix, want, got in checks:
            name = f"{prefix}{suffix}"
            if got is None:
                print(f"  {name}: ABSENT FROM THE PORT'S OUTPUT")
                bad += 1
            elif str(want) == str(got):
                print(f"  {name}: MATCH  got={got}")
                ok += 1
            else:
                print(f"  {name}: MISMATCH got={got} file={want}")
                bad += 1

    # THE HEADER'S OWN LENGTH, once, and the row count.
    hl = npy_facts(DATA / "mnist_train_images.npy")["header_len"]
    for name, want, got in (("dst_npy_header_len", hl, rows.get("dst_npy_header_len")),
                            ("dst_npy_fixed", 10, rows.get("dst_npy_fixed")),
                            ("dst_npy_n", 4, rows.get("dst_npy_n"))):
        if got is None:
            print(f"  {name}: ABSENT FROM THE PORT'S OUTPUT")
            bad += 1
        elif str(want) == str(got):
            print(f"  {name}: MATCH  got={got}")
            ok += 1
        else:
            print(f"  {name}: MISMATCH got={got} file={want}")
            bad += 1

    # THE ROW COUNTS, and the LABEL files' asymmetry: the label file's row count
    # is its ELEMENT count and the image file's is its payload over 784.
    for prefix, fname in FILES:
        f = npy_facts(DATA / fname)
        per = int(np.prod(f["shape"][1:])) if len(f["shape"]) > 1 else 1
        want = f["payload"] // per
        got = rows.get(f"{prefix}_rows")
        if got is None:
            print(f"  {prefix}_rows: ABSENT FROM THE PORT'S OUTPUT")
            bad += 1
        elif str(want) == str(got):
            print(f"  {prefix}_rows: MATCH  got={got}")
            ok += 1
        else:
            print(f"  {prefix}_rows: MISMATCH got={got} file={want}")
            bad += 1

    print(f"# {ok} match, {bad} mismatch")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
