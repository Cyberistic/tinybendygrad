# tinybendygrad/llm/kernels/__init__.bend -- port of tinygrad/llm/kernels/__init__.py
#
# Empty upstream, marker only. `tinygrad/llm/kernels/__init__.py` is a ZERO-LINE
# file, so there is nothing to re-export and nothing to port. Same shape as
# `engine/__init__.py` and `llm/__init__.py`.
#
# The one module in this package is `amd.py` (811 lines of AMD-specific kernels).
# It is a DECLARED NOT-PORTED STUB rather than a port: `llm/kernels/amd.bend`
# records the disposition and the reason, and `tinygrad`'s own hardware markers --
# not this port -- are what exclude its tests.
