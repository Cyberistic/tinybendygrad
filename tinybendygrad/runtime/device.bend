# tinybendygrad/runtime/device.bend -- THE PORT's OWN `Device` LANE.
#
# ---------------------------------------------------------------------------
# WHAT THIS FILE IS, AND WHY IT EXISTS.
#
# The port has EVERY STAGE of the device lane and NOTHING drives them:
#
#   * `schedule/__init__.bend:1139` `schedule(+ar, +sink) -> Lin` IS upstream's
#     `create_schedule` (`tinygrad/schedule/__init__.py:32-80`), and
#     `schedule/__init__.bend:1135` `linear(+x: Lin) -> O.Found` IS upstream's
#     `return UOp(Ops.LINEAR, src=tuple(linearized))`
#     (`tinygrad/schedule/__init__.py:80`).
#   * `renderer/cstyle.bend:2297` `render(+dev, cpu, +kus) -> String` IS upstream's
#     `ClangRenderer.render` (`tinygrad/renderer/cstyle.py:268-278`).
#   * `runtime/ops_cpu.bend:1578` `Cpu.compile(src, argv)` and `:1582`
#     `Cpu.exec(img, bufs, sizes)` ARE upstream's `CPUProgram.__init__` +
#     `__call__` (`tinygrad/runtime/ops_cpu.py:23-62`), in upstream's own order.
#   * `runtime/support/elf.bend:1816` `jit_loader(+e, +base) -> Img` IS
#     upstream's `jit_loader` (`tinygrad/runtime/support/elf.py:52-86`).
#
# AND `grep -rn "Cpu.compile\|Cpu.exec" tinybendygrad/` ANSWERS ONLY THE TWO
# DEFINITIONS: NOTHING IN THE PORT CALLS THEM, AND NOTHING IN THE PORT CALLS
# `schedule()` OUTSIDE ITS OWN GATE ROWS. **THE PORT'S `Device` LANE IS A SET OF
# STAGES WITH NO LANE.**
#
# `.agents/slop/cpuseam/launch.bend:113-131` IS that lane, and it is IN A
# SCRATCH DIRECTORY. This file is the lane, IN THE PORT.
#
# ---------------------------------------------------------------------------
# THE FOUR ENTRIES, AND WHAT EACH ONE IS UPSTREAM'S.
#
#   `program`  THE PROGRAM. Upstream's `Compiled.runtime(obj)` takes a
#              `TinyELF` (`tinygrad/device.py:402`) and the renderer's C is
#              `ctx.render(list(lin.src))` (`tinygrad/codegen/__init__.py:456`).
#              The port's `KU` list IS upstream's `list[UOp]`, so `program` is
#              the port's own spelling of that render step.
#
#   `schedule` THE SCHEDULER. Upstream's `create_schedule(sched_sink)` takes the
#              ASSIGN GRAPH's sink and answers the LINEAR
#              (`tinygrad/schedule/__init__.py:32-80`). The port's `schedule()`
#              is that function; this is the CALLER it did not have.
#
#   `compile`  THE COMPILER. Upstream's `CPUProgram.__init__` step 1 is `cc` on
#              the C source, with upstream's OWN argv
#              (`tinygrad/runtime/support/compiler_cpu.py:21-22`), and the ELF
#              object comes back. The port's `Cpu.compile` is that effect; this
#              is the entry that hands it the argv
#              (`runtime/support/compiler_cpu.bend:268`) and the C.
#
#   `exec`     THE EXECUTION. Upstream's `CPUProgram.__init__` steps 3-7 are
#              `mmap` -> `pthread_jit_write_protect_np` -> write -> `__clear_cache`
#              -> `CFUNCTYPE` -> call (`tinygrad/runtime/ops_cpu.py:29-46`), and
#              `__call__` packs the arguments as 64-bit words
#              (`tinygrad/runtime/ops_cpu.py:51, :61`). The port's `Cpu.exec` is
#              that effect.
#
# `relocate` IS THE MISSING MIDDLE: upstream's step 2 is `jit_loader(lib, base)`
# (`tinygrad/runtime/ops_cpu.py:34`) and it is the port's own
# `runtime/support/elf.bend:1816`.
#
# ---------------------------------------------------------------------------
# WHAT IS STILL MISSING, AND IT IS NAMED HERE RATHER THAN HIDED.
#
# `program` TAKES A `List<KU>` AND THE PORT HAS NO DEF THAT BUILDS ONE FROM THE
# PORT's ARENA. The `KU` record (`renderer/cstyle.bend:126-129`) is a FLATTENED
# uop list -- `srcs` are POSITIONS IN THAT LIST -- and upstream's renderer takes
# `list[UOp]` instead (`tinygrad/renderer/cstyle.py:456`). The port's
# `codegen/late/linearizer.bend:836 linearize(+ar, +lst, vms, +sink) -> List<&2,
# U32>` IS that `list[UOp]`, in arena indices, so the missing link is exactly
# `List<&2, U32> -> List<&2, KU>`.
#
# AND THE LINK IS BLOCKED BY A NAMED WALL, NOT BY A MISSING IDEA:
# `renderer/cstyle.bend:49-54` records that "`Ops.SHRINK` HAS NO DTYPE IN THE
# FOLD" and that "`F.fold.dt` answers `None` for SHRINK, LOAD and every ALU above
# one", and the `KU` record carries a dtype on EVERY node. So the conversion
# needs a dtype the fold cannot answer for three of the ops a real kernel uses.
#
# ⇒ SO `program`'s INPUT IS A `List<KU>`, AND WHOEVER PRODUCES IT IS THE NEXT
# UNIT. THIS FILE IS THE LANE THAT RECEIVES IT.
import Base
import ./../uop/ops.bend as O
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H
import ./../renderer/cstyle.bend as C
import ./../schedule/__init__.bend as SCH
import ./ops_cpu.bend as CPU
import ./support/elf.bend as E

# ===========================================================================
# THE PROGRAM. Upstream's `Compiled.runtime(obj)` (`tinygrad/device.py:402`)
# takes the compiled OBJECT; the port's `Program` is the C SOURCE, because the
# port's `compile` is the step that turns the C into the object.
# ===========================================================================
type Prog is Data:
  Prog{name: String, src: String}

def Prog.name(p: Prog) -> String:
  match p:
    case Prog{name, src}: name

def Prog.src(p: Prog) -> String:
  match p:
    case Prog{name, src}: src

# THE RENDER. `C.render(+dev, cpu, +kus)` IS upstream's
# `ClangRenderer.render(self, uops)` (`tinygrad/renderer/cstyle.py:268-278`) and
# `C.dev_clang()` IS THE CLANG RENDERER'S DEVICE TAG.
#
# THE `+kus` IS AFFINE, so the caller hands over the list and does not get it
# back: the port's `List` is a persistent structure and `render` CONSUMES it.
# ⇒ A CALLER THAT NEEDS THE LIST TWICE BUILDS IT TWICE, which is what
# `.agents/slop/cpuseam/launch.bend:120-122` already does.
def program(name: String, kus: List<&2, C.KU>) -> Prog:
  Prog{name, C.render(C.dev_clang(), True{}, kus)}

# ===========================================================================
# THE SCHEDULER. Upstream's `create_schedule(sched_sink)`
# (`tinygrad/schedule/__init__.py:32-80`) IS THE PORT's `schedule()`
# (`schedule/__init__.bend:1139` symbol=schedule), and `linear`
# (`schedule/__init__.bend:1136` symbol=linear) IS upstream's
# `return UOp(Ops.LINEAR, src=tuple(linearized))` (`__init__.py:80`).
#
# ⇒ THIS IS THE CALLER THE PORT's SCHEDULER DID NOT HAVE, AND IT IS WHY THE
# PORT's `Device` LANE "HAS NO SCHEDULER" WAS TRUE IN CODE AND NOT IN PROSE:
# THE FUNCTION WAS THERE AND UNREACHABLE FROM ANY DEVICE.
#
# THE ANSWER IS THE LINEAR NODE AND ITS ARENA: `schedule` CONSUMES the arena and
# `linear` hands back the node in the arena it grew, so the caller keeps the
# arena by taking the `Found`.
def schedule(ar: O.Arena, sink: U32) -> O.Found:
  SCH.linear(SCH.schedule(ar, sink))

# ===========================================================================
# THE COMPILE. Upstream's `CPUProgram.__init__` step 1 (`ops_cpu.py:29-34`) is
# `cc` on the C source with upstream's OWN argv
# (`runtime/support/compiler_cpu.py:21-22`), and the ELF OBJECT comes back.
#
# `cc_argv` IS THE PORT's OWN SPELLING OF THAT ARGV
# (`runtime/support/compiler_cpu.bend:268 symbol=ClangCompiler.compile_argv`), and it is
# JOINED WITH NEWLINES because the C side has no argv of its own -- a second copy
# of upstream's argv is a second thing to rot.
#
# `IO.try` IS BASE's OWN (`references/bend/bend2/base.bend`) and it turns the
# effect's `Fail` into a `Halt` with the message on stderr, which is what
# upstream's `CPUProgram.__init__` raising IS.
def cc_argv(cc: String, arch: String) -> String:
  CPU.cpu.cc_argv_str(cc, arch)

def compile(src: String, argv: String) -> IO(String):
  do IO<String>:
    +elf : String <- IO.try(String, CPU.Cpu.compile(src, argv))
    IO.pure(String, elf)

# ===========================================================================
# THE RELOCATION. Upstream's step 2 (`ops_cpu.py:34`) is
# `jit_loader(lib, base=mv_address(self.mem))` and it is the port's own
# `runtime/support/elf.bend:1816`.
#
# THE BASE IS `0`, AND THAT IS MEASURED, NOT CHOSEN: the port's
# `.agents/slop/cpuseam/REPORT.md:507-523` records that BOTH bases give the same
# five kernels, and the reason is that those five kernels have NO `CALL26`/
# `JUMP26` relocations, so the image-relative arms are the only ones that fire.
def relocate(+elf: String) -> String:
  +ehdr : E.Ehdr = E.Ehdr.at(elf, True{})
  +img : E.Img = E.jit_loader(E.elf_loader(elf, ehdr, True{}, 1, Nil{}), 0)
  E.Img.body(img)

# ===========================================================================
# THE EXECUTION. Upstream's steps 3-7 (`ops_cpu.py:29-46`) and `__call__`
# (`:51, :61`).
#
# ⇒ THE BUFFERS CROSS AS HEX, and that is UPSTREAM's SHAPE AND NOT A
# CONVENIENCE: `Process.run` hands its stdout back as a UTF-8 STRING
# (`references/bend/bend2/effs/process_run.c:277` builds it with `io_str`, and
# `io_str` REPLACES EVERY INVALID SEQUENCE WITH U+FFFD) and AN ELF OBJECT IS NOT
# UTF-8. ⇒ THE HEX IS THE ONLY WAY THE BYTES SURVIVE THE SEAM.
def exec(img: String, bufs: String, sizes: String) -> IO(String):
  do IO<String>:
    +out : String <- IO.try(String, CPU.Cpu.exec(img, bufs, sizes))
    IO.pure(String, out)
