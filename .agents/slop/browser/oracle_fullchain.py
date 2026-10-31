#!/usr/bin/env python3
"""oracle_fullchain.py -- CPython's OWN C FOR THE PORT's OWN SCHEDULED KERNEL.

    .venv/bin/python .agents/slop/browser/oracle_fullchain.py

WHAT IT ANSWERS, AND NOTHING MORE:

  THE SAME FIVE LINKS THE PORT's `fullchain.bend` RUNS, IN CPYTHON:
    1. `prepare_rangeify` -> `get_kernel_graph`   (upstream `__init__.py:132`)
    2. `create_schedule`
    3. `linearize`                                (linearizer.py:7)
    4. `ClangRenderer.render`                     (cstyle.py:268)

  **⇒ AND THE QUESTION IT SETTLES IS WHETHER THE PORT's RENDERED C IS CPYTHON's
  RENDERED C.** The port answered 198 bytes with `Lidx0 < ;` -- an EMPTY TRIP
  COUNT -- so the comparison is the thing that says whether that is a port
  defect or the shape of this program.

**⇒ AND THE KERNEL IS A STORE, NOT A CALL, BECAUSE THE PORT's `split_kernels`
IS A STUB.** `rangeify.bend:811`'s `sk_0` answers `M.Hop{ar, 0}` -- "no
rewrite" -- where upstream's `split_store` (`rangeify.py:326-335`) builds
`ret.sink(arg=KernelInfo()).call(*lctx.map.values())`. So CPython's kernel is a
CALL and the port's is the STORE the END wrapped. **⇒ AND THAT IS A NAMED WALL,
NOT A SILENT ONE**, and it is why the two kernels are compared by their BODIES
rather than by their root ops.
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))

from tinygrad import Tensor, Context  # noqa: E402
from tinygrad.schedule import create_schedule  # noqa: E402
from tinygrad.schedule.rangeify import get_kernel_graph  # noqa: E402
from tinygrad.schedule.prepare import prepare_rangeify  # noqa: E402
from tinygrad.codegen.late.linearizer import linearize  # noqa: E402
from tinygrad.renderer.cstyle import ClangRenderer, CStyleLanguage  # noqa: E402
from tinygrad.renderer import Renderer  # noqa: E402
from tinygrad.helpers import Target  # noqa: E402
from tinygrad.uop.ops import Ops  # noqa: E402


def build():
    """THE PORT's OWN PROGRAM, `realize.bend`'s `rz_program`, transcribed."""
    dst = Tensor.empty(20).realize().reshape(4, 5)
    lhs = Tensor.empty(12).realize().reshape(4, 3)
    rhs = Tensor.empty(15).realize().reshape(3, 5)
    val = (lhs.reshape(4, 1, 3) * rhs.reshape(1, 3, 5).permute(0, 2, 1)).sum(-1)
    dst.assign(val)
    return dst


def main():
    with Context(DEV="CPU"):
        y = build()
    sink = y.uop

    kg = get_kernel_graph(prepare_rangeify(sink))
    lin = create_schedule(kg)
    print(f"py_lin_n={len(lin.src)}")
    if not lin.src:
        print("NO KERNELS -- nothing to render")
        return
    for i, k in enumerate(lin.src):
        print(f"py_kernel[{i}]={k.op}")

    k = lin.src[0]
    # **⇒ AND THE ORACLE USES CPYTHON's OWN `do_to_program`, NOT A HAND-WIRED
    # `linearize` + `render`.** The hand-wired version died with
    # `KeyError: dtypes.weakint` from `ClangRenderer.type_map`, because
    # `linearize` alone does NOT lower `weakint` to `int32` -- `do_to_program`
    # (`codegen/__init__.py:475`) runs `full_rewrite_to_sink` first, which is
    # where the weak dtypes become concrete. **⇒ SO A HAND-WIRED ORACLE WOULD BE
    # A SECOND, WRONG PIPELINE**, and the whole point of an oracle is that it is
    # CPython's own.
    #
    # **⇒ AND `do_to_program` NEEDS `ast.arg` TO BE A `KernelInfo`**
    # (`:488` asserts it), which `split_store` puts there
    # (`rangeify.py:335`: `ret.sink(arg=KernelInfo())`). **⇒ AND THE PORT HAS
    # `KernelInfo` TOO** (`c2fbda4ca` made it upstream's six fields), which is
    # what makes this comparison meaningful rather than one-sided.
    from tinygrad.device import Device
    from tinygrad.codegen import do_to_program
    ast = k.src[0]
    prg = do_to_program(ast, Device["CPU"].renderer)
    # **⇒ AND `PROGRAM`'s SOURCE IS AT `src[2]`, NOT `src[1]`** -- MEASURED:
    # `src[0]=SINK(KernelInfo)`, `src[1]=LINEAR(None)`, `src[2]=SOURCE(str)`,
    # `src[3]=BINARY(bytes)`. A reader that took `src[1]` got `None` and printed
    # `py_c_nbytes=4`, which is the length of the string `"None"` -- a WRONG
    # ANSWER THAT LOOKED LIKE A NUMBER.
    src = prg.src[2].arg
    print(f"py_c_nbytes={len(src)}")
    print("py_c=BEGIN")
    print(src)
    print("py_c=END")


if __name__ == "__main__":
    main()
