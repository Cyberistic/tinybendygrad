# tinybendygrad/llm/kernels/amd.bend -- port of tinygrad/llm/kernels/amd.py
#
# declared not-ported stub, and the declaration is the point.
#
# `tinygrad/llm/kernels/amd.py` is 811 lines: WMMA-tiled GEMM kernels written
# against `HIPRenderer` for a specific AMD device (`BLOCK_M/N = 32`, `WMMA 16x16x16`,
# `HIPRenderer`'s loaded-buffer protocol). It imports `tinygrad.renderer.cstyle.
# HIPRenderer` and `tinygrad.llm.gguf.ggml_data_to_tensor`, and every entry point
# ends in a HIP kernel launch with a hand-tuned tile schedule.
#
# WHY IT IS NOT PORTED, in the words of the scope decision this file obeys --
# `.agents/TODO.md`, "Out of scope -- needs hardware we do not have":
#
#   "Per the brief, everything that needs an AMD/NV/CUDA/Metal/QCOM/DSP device, plus
#    all of `runtime/autogen/`, `renderer/amd/`, `runtime/support/{am,nv,rdma}/` and
#    `llm/kernels/amd.py`. These get a documented not-ported stub; their tests are
#    excluded by tinygrad's own hardware markers, not by us."
#
# SO: there is no arithmetic here to transcribe and no gate to move. A port would be
# a transcription of HIP launch geometry that nothing in this tree can execute, and
# writing one would claim a surface that cannot be checked -- which is exactly the
# failure mode `.agents/slop/PARITY.md` records elsewhere ("a row that cannot go red").
#
# - and this is why it is a file and not a silence. a missing file is
# indistinguishable from an oversight: `checks/port-compile-gate.py` counts it,
# `PARITY.md` 7 lists it, and `checks/no-strays.py` has nothing to say about a path
# that does not exist. Naming the disposition here makes the gap a DECISION that a
# reader can disagree with, rather than a hole they have to discover.
#
# - IF THIS EVER BECOMES PORTABLE, the honest first step is NOT this file: it is a
# `renderer/hip.bend` and a HIP `Program`, because the kernels are the small part.
