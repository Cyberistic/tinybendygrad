#!/usr/bin/env python3
"""pinpy.py -- graphcmp's CPython side, run against a CHOSEN tinygrad TREE.

graphcmp.py imports `tinygrad` from wherever the editable install resolves it, so the
corpus's oracle is pinned to THIS repo's `tinygrad/` and nothing else can be compared
against it. This driver takes a tree directory, puts it FIRST on `sys.path`, and then
calls graphcmp's own `emit_py`/`base` so the rules under test are graphcmp's and only
the tree differs.

It exists because the port cites a pin (`ops.bend:2699` names `axis_id` at
`ops.py:502-508`, and only `ad117c928^` has it there) and the corpus has no way to ask
what that pin's own CPython answers.

USAGE:  pinpy.py <tree-dir> <graph>
"""
import os
import sys

tree, graph = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.abspath(tree))
os.environ["DEV"] = "CPU"
sys.path.insert(0, os.path.abspath(".agents/slop"))

import graphcmp  # noqa: E402

graphcmp.load_tinygrad()
import tinygrad  # noqa: E402

print(f"# tree={tinygrad.__file__} graph={graph}")
for row in graphcmp.emit_py(graph, None):
  print(row)