# tinybendygrad/llm/__init__.bend -- port of tinygrad/llm/__init__.py
#
# Empty upstream, marker only. Same shape and finding as `engine/__init__.py`,
# `mixin/__init__.py` and `runtime/__init__.py`: `tinygrad/llm/__init__.py` is a
# ZERO-LINE file, so there is nothing to re-export and nothing to port.
#
# The contents of this package are NOT re-exported here in Python either:
#   * `gguf.py`   -> `llm/gguf.bend`
#   * `model.py`  -> `llm/model.bend`      (NOT YET PORTED -- see PARITY.md 7)
#   * `cli.py`    -> `llm/cli.bend`        (NOT YET PORTED)
#   * `serve.py`  -> `llm/serve.bend`      (NOT YET PORTED)
#   * `__main__.py` -> `llm/__main__.bend` (NOT YET PORTED; one line: the main() guard)
#   * `kernels/`  -> `llm/kernels/`        (this directory: an empty `__init__` and a
#                                          declared not-ported `amd` stub)
#
# `ggml.bend` has no upstream counterpart under `llm/`; it is the port's own
# transcription helper for the GGUF/GGML metadata the model loader reads.
