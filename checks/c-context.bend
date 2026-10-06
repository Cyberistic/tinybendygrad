import Base

# THE `cc` INSTRUMENT'S CONTEXT PROBE, AND IT LIVES IN GIT BESIDE THE GATE.
#
# `checks/substrate.py` builds the C context it judges `*.c` fragments against by
# emitting THIS program (`bend checks/c-context.bend -o gen.c`) and cutting the emit
# at the first line of the `.c` imported below. The preamble before that line is
# bend's generated C runtime; the deficit of `#if`/`#endif` in that preamble is
# counted and closed, `#define CID(x) 0` is appended, and the whole thing must
# compile on its own before any fragment is judged.
#
# IT WAS `.agents/slop/guardfix/probe-c.bend`, which matched `.gitignore`'s
# `probe-*.bend`, so it was NEVER tracked and git could not restore it when it
# vanished -- the exact shape `AGENTS.md` warns against. It now imports `sz.c`
# rather than `dtype.c` because the `dtype.bend` seam it used to reach was retired
# (`dtype.bend` no longer imports `runtime/dtype.c`), while `sz.bend` still reaches
# `runtime/sz.c`. The `.c` the probe imports is `C_PROBE_FOREIGN` in substrate.py.

law Sz.read_dir:
  String -> IO(List<String>)

def Sz.read_dir(path):
  import "../tinybendygrad/runtime/sz.c"

law Sz.is_dir:
  String -> IO(U32)

def Sz.is_dir(path):
  import "../tinybendygrad/runtime/sz.c"

def main() -> IO(Unit):
  do IO<Unit>:
    n : U32 <- Sz.is_dir("/")
    IO.print(U32.show(n))
