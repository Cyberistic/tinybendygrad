# STUB -- 1:1 PATH MIRROR of extra/datasets/preprocess_imagenet.py (21 LOC upstream). NOT YET PORTED.
#
# WHAT UPSTREAM IS. An `if __name__ == "__main__":` block and NOTHING else -- all 21
# lines are a top-level script that packs 3200 ImageNet rows into two `disk:` buffers.
# There is no def to mirror, so the ported unit is `main`.
#
# UPSTREAM IS BROKEN, MEASURED, AND THAT IS THE FIRST THING TO KNOW. Line 2 is
#     from extra.datasets.imagenet import iterate, get_val_files
# and `extra/datasets/imagenet.py` DEFINES NO `iterate`. Measured at HEAD: the only
# `def iterate` under `extra/datasets/` is `kits19.py:73`, `squad.py:133` and
# `librispeech.py:67`; `grep -n iterate extra/datasets/imagenet.py` is empty. So this
# file raises `ImportError` at import time and has never run. That is why the stop
# point below is line 2 and not line 6, and why `imagenet.bend` in this directory
# ports `get_val_files` but must NOT be given an `iterate` to make this import work:
# inventing the symbol would port a fix upstream does not have and hide the defect.
# TODO(port): STOPPED AT LINE 2 (extra/datasets/preprocess_imagenet.py:2) --
#   `from extra.datasets.imagenet import iterate, get_val_files` cannot resolve.
#   BEFORE anything else, upstream needs `iterate` added to `imagenet.py` or this
#   import narrowed to `get_val_files`; that is a decision for the upstream port, not
#   a stub's to paper over. AFTER that, MISSING: the packing loop itself --
#   `Tensor.empty(sz, *x.shape[1:], device="disk:/tmp/imagenet_x",
#   dtype=dtypes.uint8)` (upstream:14-15), the `X[idx:idx+bs].assign(x)` slice-assign
#   (upstream:18-19) which is the same wall `device.bend:872` records as "disk is a
#   WALL; what is PORTED is the DECISION", and `iterate`/`get_val_files` from
#   `imagenet.bend`, both of which are `Refused` there.
import Base
import ./__init__.bend as D

# upstream: the `if __name__ == "__main__":` block at extra/datasets/preprocess_imagenet.py:4
def main() -> D.Refused:
  D.refuse("extra/datasets/preprocess_imagenet.py:2 import iterate (absent upstream)")