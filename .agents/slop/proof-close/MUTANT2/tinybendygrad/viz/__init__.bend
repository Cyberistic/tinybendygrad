# tinybendygrad/viz/__init__.bend -- port of tinygrad/viz/__init__.py
#
# `tinygrad/viz/__init__.py` is ZERO BYTES. MEASURED: `wc -l
# tinygrad/viz/__init__.py` is 0 and `ls -l` is 0 bytes, so there is no name to
# port and nothing for a reader to map.
#
# WHY THE FILE EXISTS ANYWAY. The owner ruling is one `.bend` per upstream `.py`
# at the SAME PATH, and that ruling is what makes the port navigable -- a reader
# who looks for `tinybendygrad/viz/cli.bend` because they know
# `tinygrad/viz/cli.py` must find it. A missing file reads as "not done", and an
# empty `.py` with no `.bend` reads as "skipped", which is a different and wrong
# claim.
#
# So this file says the one true thing, which is that upstream is empty, and
# stops. `serve.py`'s `from tinygrad.viz import serve as viz` in `cli.py` is a
# SUBMODULE import and resolves in Bend by path (`import ./serve.bend as viz`),
# which is how `cli.bend` reaches it -- so this module needs no re-export and a
# re-export would be the only thing here that is not in the upstream file.