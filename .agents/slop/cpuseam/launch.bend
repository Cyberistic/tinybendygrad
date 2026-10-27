# launch.bend -- THE PORT's OWN DEVICE LANE, RUNNING A KERNEL IT RENDERED.
#
#   ./bin/bend .agents/slop/cpuseam/launch.bend -o /tmp/launch
#   /tmp/launch r_56_7_2_2 [cc]
#
# IT DOES THE SEVEN THINGS UPSTREAM's `CPUProgram` DOES (ops_cpu.py:23-46), IN
# THE PORT's OWN WORDS:
#   1. RENDER THE C WITH THE PORT's OWN `cstyle.bend` (`C.render`)
#   2. BUILD UPSTREAM's ARGV WITH THE PORT's OWN `compiler_cpu.bend`
#      (`ClangCompiler.compile_argv`)
#   3. `cc` IT (`Cpu.compile`, THE EFFECT) -- THE ELF OBJECT COMES BACK AS HEX
#   4. RELOCATE IT WITH THE PORT's OWN `jit_loader` (`elf.bend:1816`)
#   5. MMAP THE IMAGE AND CALL IT (`Cpu.exec`, THE EFFECT)
#   6. IT READS THE BUFFERS FROM A FILE CPython's OWN DEVICE WROTE
#   7. IT PRINTS THE RESULTING BUFFERS' HEX, AND THE COMPARER READS THEM
#
# THE BUFFERS ARE THE ORACLE's: `.agents/slop/cpuseam/bufs/<name>.rows` IS
# WRITTEN BY `bufs.py`, WHICH HOOKS CPython's OWN `CPUProgram.__call__`.
#
# THE OUTPUT IS TWO LINES: `sizes=<n,n,...>` AND THE HEX OF EVERY BUFFER,
# INPUT AND OUTPUT ALIKE, IN ORDER. THE COMPARER SPLITS THE HEX BY THE SIZES
# AND COMPARES EACH OUTPUT BUFFER AGAINST CPython's OWN `# bufN after` LINE.
import Base
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/runtime/ops_cpu.bend as CPU
import ./../../../tinybendygrad/runtime/support/elf.bend as E
import ./../../../tinybendygrad/runtime/support/compiler_cpu.bend as CC
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/uop/ops.bend as O
import ./gen/r_10_98_4.bend as K0
import ./gen/r_2_14_14_4_4_3_3.bend as K1
import ./gen/r_4_28_7_4_3_3.bend as K2
import ./gen/r_56_14_2_2.bend as K3
import ./gen/r_56_7_2_2.bend as K4

# THE Nth SPACE-SEPARATED FIELD OF A LINE. `List.get` IS THE PORT's OWN, SO
# THERE IS NO HAND-ROLLED PARSER HERE. `&1` AND `&2` ARE DIFFERENT TYPES TO
# BEND, SO THE TWO CALL SITES GET TWO ONE-LINERS OVER `Maybe.default` RATHER
# THAN TWO COPIES OF A MATCH.
def nth(xs: List<&1, String>, k: Nat) -> String:
  Maybe.default(&1, String, List.get(&1, String, xs, k), "")

# THE HEX FIELD OF A `bufN <hex>` LINE: THE FIELD AFTER THE NAME. MEASURED: A
# VERSION THAT JOINED *EVERY* FIELD PUT THE NAME IN THE HEX AND MADE THE HEX
# EIGHT CHARACTERS TOO LONG FOR TWO BUFFERS -- WHICH THE C SIDE CAUGHT AS
# "buffer hex does not match the sizes". THE C SIDE IS THE INSTRUMENT; THIS
# IS THE BUG IT FOUND.
def hex_of(ln: String) -> String:
  Maybe.default(&2, String, List.get(&2, String, String.split(ln, ' '), 1n), "")

# THE `bufN <hex>` LINES, CONCATENATED IN ORDER. THE `# bufN after` LINES START
# WITH `#`, SO THEY ARE NOT INPUTS.
def bufs_of.one(+h: String, +acc: String) -> String:
  Bool.pick(String, String.starts_with(h, "buf"),
    String.concat([acc, hex_of(h)]), acc)

def bufs_of.go(ls: List<&2, String>, +acc: String) -> String:
  match ls:
    case Nil{}: acc
    case +h <> t: bufs_of.go(t, bufs_of.one(h, acc))

def bufs_of(ls: List<&2, String>) -> String:
  bufs_of.go(ls, "")

# THE BUFFER SIZES IN BYTES, FROM THE KERNEL's OWN PARAM SHAPES: THE SHAPE's
# ELEMENT COUNT TIMES THE f32 ITEMSIZE. THE FIXTURE's `sizes` LINE SAYS THE SAME
# THING, AND THE COMPARER CHECKS THE TWO AGREE.
def ku_sizes.one(+k: C.KU, +acc: String) -> String:
  Bool.pick(String, O.eq_op(C.KU.op(k), O.OpsPARAM{}),
    String.concat([acc, Bool.pick(String, String.is_empty(acc), "", ","),
      U32.show(U32.mul(C.KU.numel(k), 4))]), acc)

def ku_sizes.go(kus: List<&2, C.KU>, +acc: String) -> String:
  match kus:
    case Nil{}: acc
    case +k <> t: ku_sizes.go(t, ku_sizes.one(k, acc))

def ku_sizes(kus: List<&2, C.KU>) -> String:
  ku_sizes.go(kus, "")

def kus_of(nm: String) -> List<&2, C.KU>:
  match nm:
    case "r_10_98_4": K0.kus()
    case "r_2_14_14_4_4_3_3": K1.kus()
    case "r_4_28_7_4_3_3": K2.kus()
    case "r_56_14_2_2": K3.kus()
    case "r_56_7_2_2": K4.kus()
    case _: Nil{}

# THE `cc` TO USE. IT IS THE SECOND ARGUMENT, BECAUSE UPSTREAM's OWN
# `CPUProgram` COMPILES WITH `getenv("CC", 'clang')` (support/compiler_cpu.py:21)
# AND THE SEAM TAKES THE COMPILER AS AN ARGUMENT RATHER THAN READING THE
# ENVIRONMENT. ⇒ THE PLANT IS A WRAPPER `cc`: THE SEAM's OWN PARAMETER.
def cc_of.go(m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: CC.ClangCompiler.prog_default()

def cc_of(args: List<&1, String>) -> String:
  cc_of.go(List.get(&1, String, args, 2n))

# THE ARCH. UPSTREAM's `CPUDevice` SPELLS IT `platform.machine()` PLUS ",native"
# (ops_cpu.py:76), AND THE PORT's OWN `cpu.arch_of` SPELLS THAT. THE MACHINE
# STRING IS "arm64" HERE, AND IT IS SPELLED BECAUSE BEND HAS NO
# `platform.machine()`.
def arch() -> String: CPU.cpu.arch_of("arm64")

# THE ARGV, AS ONE "\n"-JOINED STRING. THE PORT's OWN SPELLING OF UPSTREAM's
# ARGV (`ops_cpu.bend`'s `cpu.cc_argv_str`), AND THE C SIDE SPLITS IT.
def argv_of(cc: String) -> String:
  CPU.cpu.cc_argv_str(cc, arch())

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +nm : String = nth(args, 1n)
    cargs : List<String> <- IO.args()
    +cc : String = cc_of(cargs)
    ls : List<&2, String> <- H.lines(String.concat([".agents/slop/cpuseam/bufs/", nm, ".rows"]))
    +src : String = C.render(C.dev_clang(), True{}, kus_of(nm))
    +bufs : String = bufs_of(ls)
    +sizes : String = ku_sizes(kus_of(nm))
    # STEP 3: `cc` THE C TO AN ELF OBJECT.
    +elf : String <- IO.try(String, CPU.Cpu.compile(src, argv_of(cc)))
    # STEP 4: RELOCATE IT WITH THE PORT's OWN `jit_loader`.
    ehdr : E.Ehdr = E.Ehdr.at(elf, True{})
    img : E.Img = E.jit_loader(E.elf_loader(elf, ehdr, True{}, 1, Nil{}), 0)
    # STEP 5: MMAP THE IMAGE AND CALL IT.
    out : String <- IO.try(String, CPU.Cpu.exec(E.Img.body(img), bufs, sizes))
    IO.print(String.concat(["sizes=", sizes]))
    IO.print(out)
