#!/usr/bin/env python3
"""sum.py -- THE VERDICT COUNTS, AND THE SLICE'S PROGRESS.

Usage: sum.py <rows-file> [<rows-file> ...]
"""
from __future__ import annotations
import csv, collections, os, sys

MY = set("""tinybendygrad/examples/test_pkl_imagenet.bend
tinybendygrad/extra/datasets/imagenet_download.bend
tinybendygrad/extra/models/clip.bend
tinybendygrad/extra/models/convnext.bend
tinybendygrad/extra/models/mask_rcnn.bend
tinybendygrad/extra/models/transformer.bend
tinybendygrad/extra/models/unet.bend
tinybendygrad/nn/item.bend
tinybendygrad/nn/pool.bend
tinybendygrad/schedule/rangeify.bend
tinybendygrad/uop/weak.bend""".split())
SLICE = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/bare.rows"


def key(r):
    return (r["rel"], r["at"], r["subject"], r["lo"], r["hi"])


def main():
    slice_keys = {key(r) for r in csv.DictReader(open(SLICE), delimiter="\t")}
    for path in sys.argv[1:]:
        rows = list(csv.DictReader(open(path), delimiter="\t"))
        c = collections.Counter(r["verdict"] for r in rows)
        print(f"== {os.path.basename(path)}  total={len(rows)}")
        for k in sorted(c):
            print(f"   {k:24s} {c[k]}")
        mine = [r for r in rows if r["rel"] in MY]
        cm = collections.Counter(r["verdict"] for r in mine)
        print(f"   -- MY 11 FILES: total={len(mine)}")
        for k in sorted(cm):
            print(f"      {k:22s} {cm[k]}")
        # THE SLICE ROWS
        sl = [r for r in rows if key(r) in slice_keys]
        cs = collections.Counter(r["verdict"] for r in sl)
        print(f"   -- THE 79 SLICE ROWS: {len(sl)} matched; " +
              ", ".join(f"{k}={v}" for k, v in sorted(cs.items())))
        still = [r for r in sl if r["verdict"] == "UNCLAIMED"]
        for r in still:
            print(f"      STILL UNCLAIMED {r['rel']}:{r['at']} -> {r['subject']}:{r['lo']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
