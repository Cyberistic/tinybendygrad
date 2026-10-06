#!/usr/bin/env python3
"""reprpin.py -- the tree's OWN `CallInfo.__repr__`, for void and non-void, on a chosen tree.

`graphcmp.py`'s `carg` CALL arm is a hand-written three-slot string, so it answers the
same thing on every tree. The tree's repr is the one that can differ, and at the pin it
is CONDITIONAL (`", dtype=...)" if self.dtype is not dtypes.void else ")"`).

USAGE:  reprpin.py <tree-dir>
"""
import os
import sys

tree = sys.argv[1]
sys.path.insert(0, os.path.abspath(tree))
os.environ["DEV"] = "CPU"

import tinygrad.uop.ops as opm  # noqa: E402
import tinygrad.dtype as dtm  # noqa: E402

import tinygrad  # noqa: E402

print(f"# tree={tinygrad.__file__}")
print(f"# repr(void)   = {opm.CallInfo(None, 'hcq_fence', False, False)!r}")
print(f"# repr(int32)  = {opm.CallInfo(None, 'hcq_fence', False, False, None, dtm.dtypes.int32)!r}"
      if "dtype" in opm.CallInfo.__annotations__
      else "# repr(int32)  = <no dtype field; a 6th positional is a TypeError>")
print(f"# reduce(void) = {opm.CallInfo.__reduce__(opm.CallInfo(None, 'hcq_fence', False, False))[1]!r}")