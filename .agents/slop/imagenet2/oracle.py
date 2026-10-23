#!/usr/bin/env python3
"""THE ORACLE: CPython's own answer for the same tree.

This is upstream's `extra/datasets/imagenet.py` logic, verbatim, with the
module-level `BASEDIR` replaced by the root the caller names:

  get_imagenet_categories: json.load(open(BASEDIR / "imagenet_class_index.json"))
                            read as {v[0]: int(k) for k, v in ci.items()}
  get_train_files:         glob.glob(p := str(BASEDIR / "train/*/*")), and
                           FileNotFoundError(f"No training files in {p}") when
                           the glob matched nothing
  get_val_files:           the same over "val/*/*"

Each of the three is caught on its own, so a tree with no `train/` still has an
answer for the class map -- and the refusal it prints is UPSTREAM'S, which is
NOT the port's: upstream has one refusal ("the glob matched nothing") where the
port has two ("no `train/` directory" and "`train/` holds nothing").  The port's
refusal is the more specific one and the difference is named in REPORT.md.

The file list is SORTED, because `glob.glob` answers in `os.scandir` order and
the ORDER IS NOT THE CLAIM: the claim is the set of paths.

The printed shape is the one the bend probe prints, so the two are comparable
byte for byte.
"""
import glob
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])


def get_imagenet_categories(basedir):
    ci = json.load(open(basedir / "imagenet_class_index.json"))
    return {v[0]: int(k) for k, v in ci.items()}


def get_files(basedir, split, what):
    files = glob.glob(p := str(basedir / f"{split}/*/*"))
    if not files:
        raise FileNotFoundError(f"No {what} files in {p}")
    return sorted(files)


def rel(root, paths):
    return [str(pathlib.Path(p).relative_to(root)) for p in paths]


def line(tag, fn):
    try:
        return f"{tag}=" + "|".join(fn())
    except (FileNotFoundError, OSError) as e:
        return f"{tag}=REFUSED: {e}"


def cats_line():
    cats = get_imagenet_categories(root)
    return [f"{k}={v}" for k, v in sorted(cats.items())]


print(line("train", lambda: rel(root, get_files(root, "train", "training"))))
print(line("val", lambda: rel(root, get_files(root, "val", "validation"))))
print(line("cat", cats_line))
