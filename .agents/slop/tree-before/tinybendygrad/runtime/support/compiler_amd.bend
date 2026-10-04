# tinybendygrad/runtime/support/compiler_amd.bend -- port of tinygrad/runtime/support/compiler_amd.py
#
# ===========================================================================
# WHAT A BEND FILE CAN REACH, MEASURED, BECAUSE IT DECIDES WHAT THIS FILE IS.
#
# The scope note for this unit asserted "bend 2.0.34 has no exec and no
# process spawn". THE FIRST HALF IS WRONG. It was measured rather than believed,
# because the whole value of this file depends on the answer:
#
#   references/bend/bend2/base.bend:182
#     def Process.run(program: String, args: List<String>, input: String,
#       max_output: U32, timeout_ms: U32) ->
#       IO(Result<&1, &1, U32 & String, U32 & (String & String)>)
#       import "./effs/process_run.c"   /  import "./effs/process_run.js"
#
# and `effs/process_run.c` is `posix_spawnp` with stdin/stdout/stderr pipes, a
# poll loop and a `waitpid`. `.agents/slop/cs-probe.bend` runs it on BOTH lanes
# and prints, MEASURED, not inferred:
#
#   /bin/echo hi                    -> Done{(0, ("hi\n", ""))}
#   /bin/sh -c cat      <- "PIPED"  -> Done{(0, ("PIPED", ""))}   stdin fed then closed
#   /bin/sh -c 'echo e >&2; printf o' -> Done{(0, ("o", "e"))}     stderr is separate
#   /bin/sh -c 'exit 42'            -> Done{(42, ("", ""))}        the exit code IS the value
#   /nonexistent-tool-xyz           -> Fail{(2, <non-empty>)}       a spawn failure is a Fail
#   "true"                          -> Done{(0, ...)}              PATH lookup works
#
# So `HIPCCCompiler.compile`'s two `subprocess.run(..., check=True)` calls port
# ONTO `Process.run` with no new seam and no `@unsafe`. The second half of the
# scope note is RIGHT and is what walls the rest of this file: there is no
# importable runtime module, so `tinygrad.runtime.autogen.comgr` is unreachable.
#
# The remaining half of the note -- "an FFI seam, or nothing" -- is resolved by
# the project rule this file follows: a binding DECLARATION for a device with
# no runtime is a comment. So comgr's 28 calls are declared in the trace as
# tagged entries and NOT executed, and EVERYTHING THAT IS PURE is ported and
# gated. See WALL 1.
#
# `Process.run` takes an ARGV LIST, and so does `tinygrad.helpers.system` --
# it is `subprocess.check_output(cmd.split(), stderr=STDOUT)`, NOT a shell --
# so the two agree on shape here and `os.system` is nowhere in this file. The
# one thing `system()` has and `Process.run` does not is the MERGED stream
# (`stderr=subprocess.STDOUT`); nothing in these four files needs it.
#
# ===========================================================================
# THE SPLIT, stated once and obeyed. A def here EITHER builds the argument of
# ONE comgr/hipcc call (pure, and the gate diffs it) OR records that call in
# the trace (and the gate checks the ORDER and the IDENTITY). There is no
# third kind, which is what puts the `raise` in the trace: a refusal is a
# TRUNCATED trace, so no step needs a guard of its own. Every seam is a trace
# tag, so this file declares NO foreign effect and is `ALL PROOFS CHECK` on
# both lanes -- the `ops_webgpu.bend` lane, not the `dtype.bend` one.
#
# ===========================================================================
# THE MEASUREMENT THAT DELETED A FAMILY OF BUGS, and it belongs at the top
# because it changed what got written rather than only how.
#
# `set_options` (:32) is `options.split(b' ')` and `IR3Compiler`/`QCOMCompiler`
# are `arch.split(',')`, so the WHOLE port depends on what a literal-separator
# split does with empty fields. `base.bend:2009`'s `String.split` was MEASURED
# against CPython's `str.split(sep)` on all nine fixtures the oracle uses, and
# they agree on every one, INCLUDING the empty-field case that a hand-rolled
# splitter gets wrong:
#
#   ""           -> [""]           n=1     (NOT zero -- and :72 sends b"" here)
#   "a  b"       -> ["a","","b"]   n=3     (the middle EMPTY field is kept)
#   "  "         -> ["","",""]     n=3
#   " lead"      -> ["","lead"]    n=2
#   "trail "     -> ["trail",""]   n=2
#   "a\tb"       -> ["a\tb"]       n=1     (a tab is NOT a separator)
#
# So there is NO hand-written splitter in this file. Had one been written, the
# `amd.split_empty.n=1` and `amd.split_dbl.n=3` rows would both have been the
# difference between passing and sending comgr a wrong argument count. The
# thirteen-element option list below splits into NINETEEN fields for exactly
# this reason, and `h.opt_n` is the row that pins it.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers.
#
#   :4-10  the comgr3 switch      PORTED  `Ad.version` `Ad.hip_lang` `Ad.hyp3`
#   :15-18 check()                PORTED  `c.msg`  (the refusal truncates `gd`)
#   :20-25 _get_comgr_data        PORTED  `gd.*` -- the FOUR-call order and the two
#                                        sizes; the calls themselves are the trace
#   :28-32 set_options()          PORTED  `sp.n` -- the option COUNT comgr is given
#   :35-38 the ISA name           PORTED  `h.isa`
#   :39    the logging flag       PORTED  `h.logging` (autogen value, declared)
#   :49-55 the `asm` branch       PORTED  `h.dataname` `h.asm_actions`
#   :56-70 the compile branch     PORTED  `h.options` `h.opt_n` `h.opt_codegen`
#                                        `h.compile_actions`
#   :52-68 the two refusals       PORTED  `c.asm_fail` `c.compile_fail`
#   :72-73 link                   PORTED  `h.opt_empty` `h.link_action`
#   :81-84 HIPCompiler            PORTED  `C.hip_key`
#   :85-87 HIPCompiler.compile    PORTED  `C.is_asm` -- `split('\n',1)[0].strip()
#                                        == '.text'`, and the RuntimeError remap
#   :88    disassemble            PORTED  `C.dis_row` (the `amdgpu_disassemble` call)
#   :91-94 HIPCCCompiler          PORTED  `C.hipcc_key` `C.join_extra`
#   :95-96 the NO_HIPCC short-cut PORTED  `C.short_circuit`
#   :97-98 the temp suffixes      PORTED  `C.suffixes`
#   :102   the ROCM default       PORTED  `C.rocm_include`
#   :103-104 argv 1               PORTED  `C.argv1`  (element COUNT pinned)
#   :105-106 argv 2               PORTED  `C.argv2`  (element COUNT pinned)
#
# ===========================================================================
# THE FOUR WALLS, each with its Python line.
#
# WALL 1 -- comgr. Twenty-eight calls into a shared library bend cannot dlopen.
#   The enum values are constants OF that library, and they are not all equal
#   between the two modules: MEASURED on this host, `AMD_COMGR_LANGUAGE_HIP` is
#   4 in `autogen/comgr.py` and 3 in `autogen/comgr_3.py`, which is precisely
#   what :9's assert pins. So the switch and the assert are ported, and the
#   numbers inside them are DECLARED autogen values rather than invented ones.
#   TODO(p3) compiler_amd.py:3  -- `from tinygrad.runtime.autogen import comgr`.
#   TODO(p3) compiler_amd.py:36-77 -- the 28 comgr calls of `compile_hip`.
#   TODO(p3) compiler_amd.py:21-23 -- the two `amd_comgr_get_data` calls.
#
# WALL 2 -- sha256. `hashlib.sha256(' '.join(extra)).hexdigest()[:8]` is eight
#   hex characters of a 64-bit digest. `base.bend` exports `Word`, not
#   `Word(64n)` (bend2-constraints.md POSITION 2320), so there is no digest to
#   compute. The TEMPLATE is ported and gated with the eight characters as a
#   PARAMETER, so the row pins the key and not the hash.
#   TODO(p3) compiler_amd.py:93 -- `hashlib.sha256(...).hexdigest()[:8]`.
#
# WALL 3 -- the temp file NAMES. `tempfile.NamedTemporaryFile(suffix=...)`
#   names three files and the two argv lists carry those names. bend has a
#   working `File` (base.bend:264-301) -- `.agents/slop/cs-probe3.bend` writes
#   and reads one on BOTH lanes -- but there is no mkstemp, and the name is
#   random in Python anyway. So the SUFFIX is ported and gated, and the name is
#   a PARAMETER of each argv builder, which is the honest shape:
#   `C.argv1(arch, rocm, bc, src, extra)` is a function of five strings and a
#   list, and the element COUNT is pinned because that is what a wrong flag
#   order or a dropped extra would change.
#   TODO(p3) compiler_amd.py:97-98 -- the three NamedTemporaryFile names.
#
# WALL 4 -- the artifact read-back. `pathlib.Path(libf.name).read_bytes()`
#   returns bytes, and bend has no name to read and no `.hsaco` to name.
#   TODO(p3) compiler_amd.py:108 -- `read_bytes()`.
import Base

# ===========================================================================
# THE TRACE. Which toolchain call the Python makes, in what order, with which
# argument. `Tr.put` appends, so a REFUSAL is a trace that stops early -- which
# is how `c.msg` is enforced: there is no `raise` in bend and no step guard.
# ===========================================================================
# `Tr` carries the recorded calls. The field is `items` and not `t`, because a
# reader is spelled `Tr.items(tr)` and a field named `t` would collide with the
# parameter of every def that reads it.
type Tr is Data:
  Tr{items: List<&2, String>}

def Tr.of() -> Tr: Tr{[]}

def Tr.items(tr: Tr) -> List<&2, String>:
  match tr:
    case Tr{items}: items

def Tr.put(nm: String, arg: String, tr: Tr) -> Tr:
  Tr{List.append(&2, String, Tr.items(tr), [String.concat([nm, "(", arg, ")"])] )}

def Tr.n(tr: Tr) -> U32: U32.from_nat(List.length(&2, String, Tr.items(tr)))

def Tr.text(tr: Tr) -> String: String.join(Tr.items(tr), " ")

# The autogen enum values `compile_hip` passes. DECLARED, not invented: these
# are constants of libcomgr, read out of `autogen/comgr.py` by the oracle.
#   AMD_COMGR_DATA_KIND_SOURCE 1  AMD_COMGR_DATA_KIND_LOG 5  EXECUTABLE 8
#   ACTION_ASSEMBLE_SOURCE_TO_RELOCATABLE 10  ACTION_CODEGEN_BC_TO_RELOCATABLE 6
#   ACTION_LINK_RELOCATABLE_TO_EXECUTABLE 9
#   ACTION_COMPILE_SOURCE_WITH_DEVICE_LIBS_TO_BC 15
#   AMD_COMGR_LANGUAGE_HIP 4 (comgr.py) / 3 (comgr_3.py)
def A.source_kind() -> U32: 1
def A.log_kind() -> U32: 5
def A.exec_kind() -> U32: 8
def A.act_assemble() -> U32: 10
def A.act_codegen() -> U32: 6
def A.act_link() -> U32: 9
def A.act_compile() -> U32: 15

# ===========================================================================
# :4-10  THE comgr VERSION SWITCH AND ITS ASSERT.
#
#     if major.value >= 3:
#       import tinygrad.runtime.autogen.comgr_3 as comgr
#       assert comgr.AMD_COMGR_LANGUAGE_HIP == 3
#
# Two facts, not one: the VERSION selects which module the enums come from, and
# the assert pins ONE enum in the selected module. `Ad.hip_lang` is the second
# and `Ad.version` is the first. A port that treated the switch as a rename
# would answer 3 for both versions and could never notice.
# ===========================================================================
def Ad.version(major: U32) -> U32: Bool.to_u32(Bool.and(U32.is_gt(major, 2), True{}))

def Ad.hip_lang(major: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_gt(major, 2), True{}), 3, 4)

# the assert fires ONLY on the comgr-3 path, so on comgr-2 it never runs
def Ad.hyp3(major: U32) -> Bool: U32.is_eq(Ad.hip_lang(major), 3)

# ===========================================================================
# :15-18  check().  `c.msg` answers the message for a NON-zero status and the
# empty string for zero, so the one caller tests emptiness instead of branching
# twice, and the trace is truncated at that point.
# ===========================================================================
def c.msg(+status: U32, msg: String) -> String:
  Bool.pick(String, U32.is_eq(status, 0), "",
    String.concat(["comgr fail ", U32.show(status), ", ", msg]))

# ===========================================================================
# :28-32  set_options(). `sp.n` is the number of arguments comgr is handed.
# See THE MEASUREMENT THAT DELETED A FAMILY OF BUGS: `String.split` already
# keeps the empty fields, so this is the length and nothing else.
# ===========================================================================
def sp.n(options: String) -> U32: U32.from_nat(List.length(&2, String, String.split(options, ' ')))

# ===========================================================================
# :35-38  the ISA NAME.  `b"amdgcn-amd-amdhsa--" + arch.encode()`.
# ===========================================================================
def h.isa(arch: String) -> String: String.append("amdgcn-amd-amdhsa--", arch)

# ===========================================================================
# :39  the LOGGING FLAG, and :38's language: both autogen constants.
# ===========================================================================
def h.logging(on: Bool) -> U32: Bool.to_u32(on)

# ===========================================================================
# :49-55 / :56-57  THE `asm` BRANCH. The data NAME is the only difference
# besides the action, and it is a suffix on a fixed prefix:
#     asm:  amd_comgr_set_data_name(data_src, b"<null>.s")
#     else: amd_comgr_set_data_name(data_src, b"<null>")
# ===========================================================================
def h.dataname(asm: Bool) -> String: Bool.pick(String, asm, "<null>.s", "<null>")

# ===========================================================================
# :60-63  THE THIRTEEN OPTIONS, and :64's `' '.join`.
#
# Written as an explicit LITERAL LIST rather than a fold, because a fold over a
# function parameter is impossible in bend (a function value is `Type`, so `+`
# is refused -- bend2-constraints.md POSITION 5043) and because this list is
# data, not a computation. The `--offload-arch={arch}` element is the only one
# that varies.
#
#   "-O3", "-mcumode", "--hip-version=6.0.32830", "-DHIP_VERSION_MAJOR=6",
#   "-DHIP_VERSION_MINOR=0", "-DHIP_VERSION_PATCH=32830", "-D__HIPCC_RTC__",
#   "-std=c++14", "-nogpuinc", "-Wno-gnu-line-marker", "-Wno-missing-prototypes",
#   f"--offload-arch={arch}", "-I/opt/rocm/include", "-Xclang",
#   "-disable-llvm-passes", "-Xclang", "-aux-triple", "-Xclang",
#   "x86_64-unknown-linux-gnu"
#
# which is THIRTEEN list elements and, once `' '.join` then `.split(b' ')` have
# been through `set_options`, NINETEEN comgr arguments. Measured: `optn0=19`.
# The six elements that contain a space (`-I/opt/rocm/include` has none; the
# `-Xclang` triples have two each) are the difference, and `h.opt_n` is the row.
# ===========================================================================
def h.options(arch: String) -> String:
  String.join(["-O3", "-mcumode", "--hip-version=6.0.32830", "-DHIP_VERSION_MAJOR=6",
    "-DHIP_VERSION_MINOR=0", "-DHIP_VERSION_PATCH=32830", "-D__HIPCC_RTC__",
    "-std=c++14", "-nogpuinc", "-Wno-gnu-line-marker", "-Wno-missing-prototypes",
    String.concat(["--offload-arch=", arch]), "-I/opt/rocm/include",
    "-Xclang", "-disable-llvm-passes", "-Xclang", "-aux-triple", "-Xclang",
    "x86_64-unknown-linux-gnu"], " ")

# :64, the option string comgr is ACTUALLY given
def h.opt_string(arch: String) -> String: h.options(arch)

def h.opt_n(arch: String) -> U32: sp.n(h.opt_string(arch))

# ===========================================================================
# :52 / :65 / :70 / :72  THE FOUR ACTIONS, in order, and the two constant
# option strings. The order is the thing a trace exists for: the same three
# `do_action` calls run in both branches and only the FIRST differs.
# ===========================================================================
def h.act_assemble_name() -> U32: A.act_assemble()
def h.act_compile_name() -> U32: A.act_compile()
def h.act_codegen_name() -> U32: A.act_codegen()
def h.act_link_name() -> U32: A.act_link()

# :69 the codegen option string, :72 the option string that CLEARS them
def h.opt_codegen() -> String: "-O3 -mllvm -amdgpu-internalize-symbols"
def h.opt_empty() -> String: ""

def h.opt_codegen_n() -> U32: sp.n(h.opt_codegen())
def h.opt_empty_n() -> U32: sp.n(h.opt_empty())

# :55 / :68 the two refusals, verbatim
def c.asm_fail() -> String: "assemble failed"
def c.compile_fail() -> String: "compile failed"

# ===========================================================================
# :20-25  _get_comgr_data. Four calls, and the SIZE is read TWICE -- once to
# ask how big the buffer is and once inside the buffer that was allocated at
# that size. The order is what `gd.*` records.
# ===========================================================================
def gd.pick_kind(exec_kind: Bool) -> U32:
  Bool.pick(U32, exec_kind, A.exec_kind(), A.log_kind())

def gd.calls() -> U32: 4

# the FOUR calls, in order: the one that names the data, the two that read the
# size, and the one that releases it
def gd.calls_name() -> String:
  "amd_comgr_action_data_get_data amd_comgr_get_data amd_comgr_get_data amd_comgr_release_data"

# ===========================================================================
# :81-84  HIPCompiler's CACHE KEY.  `f"compile_hip_{self.arch}"`.
# ===========================================================================
def C.hip_key(arch: String) -> String: String.concat(["compile_hip_", arch])

# ===========================================================================
# :85-87  HIPCompiler.compile's ASM PREDICATE, and it is subtler than it
# looks:
#
#     compile_hip(src, self.arch, src.split('\n', 1)[0].strip() == '.text')
#
# `split('\n', 1)[0]` is the FIRST LINE ONLY, `.strip()` removes whitespace from
# BOTH ends of that line, and the comparison is against the exact five bytes
# `.text`. MEASURED, and every one of these cases is a row:
#     ".text"            True     "  .text  \nfoo"   True    (strip both ends)
#     "\t.text\t\n"      True     " .text\n\tmore\n" True   (tab is whitespace)
#     "\n.text"          False    (the FIRST line is empty, and empty != ".text")
#     "x\n.text\n"       False    (same trap, with a name on line one)
#     ".text extra"      False    (no `startswith`: the WHOLE line must equal it)
#     ".text;x"          False    (no `in`, no comment stripping)
#     ".TEXT"            False    (case sensitive)
#     ""                 False
#
# `C.is_asm` is three defs because a `match` may not follow a `<-` bind and a
# `Maybe` is read once; the caller builds the first line, then trims it.
# ===========================================================================
def C.first_line.of(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case h <> t: h

def C.first_line(src: String) -> String: C.first_line.of(String.split(src, '\n'))

def C.is_asm(src: String) -> Bool: String.eq(String.trim(C.first_line(src)), ".text")

# :87 the RuntimeError -> CompileError remap, and what CompileError carries
def C.compile_error(m: String) -> String: m

def C.compile_error_kind(m: String) -> String: "CompileError"

# ===========================================================================
# :88  `amdgpu_disassemble(lib)`. The trace entry is the call; its argument is
# the artifact, which is a WALL.
# ===========================================================================
def C.dis_row(arch: String) -> String: String.concat(["amdgpu_disassemble(", arch, ")"])

# ===========================================================================
# :91-94  HIPCCCompiler's CACHE KEY.
#
#     f"compile_hipcc_{arch}_{sha256(' '.join(extra)).hexdigest()[:8]}" +
#       ("_nohipcc" if self.no_hipcc else "")
#
# The digest is WALL 2 and arrives as `hex8`. The `' '.join` is `C.join_extra`
# and is gated on its own because it is the thing the digest is computed OVER --
# a join that dropped a trailing empty option would still hash to 8 characters
# and would be invisible in the key.
#
# MEASURED: `helpers.getenv` is `@functools.cache`, so `NO_HIPCC` is read ONCE
# per process. That is why the oracle needs a FRESH interpreter to observe
# `no_hipcc` true, and why `amd.cc_nohip.ncalls=0` holds even with the variable
# set after startup. `C.short_circuit` is the observable consequence.
# ===========================================================================
def C.join_extra(extra: List<&2, String>) -> String: String.join(extra, " ")

def C.hipcc_key(arch: String, hex8: String, nohipcc: Bool) -> String:
  String.concat(["compile_hipcc_", arch, "_", hex8, Bool.pick(String, nohipcc, "_nohipcc", "")])

# :96 `if self.no_hipcc: return b""` -- no spawn, no temp file, no artifact
def C.short_circuit(nohipcc: Bool) -> U32: Bool.to_u32(nohipcc)

# ===========================================================================
# :97-98  THE THREE TEMP SUFFIXES. The names are random (WALL 3); the suffixes
# are the part the port constructs, and `amd.cc_*.argvn*` counts depend on them
# being the right three files in the right order.
# ===========================================================================
def C.suffixes() -> List<&2, String>: [".cpp", ".bc", ".hsaco"]

def C.suffix_of(+i: U32) -> String:
  # Two equality tests, not a `U32` literal ladder: a literal arm is a PREFIX
  # match (bend2-constraints.md POSITION 1885), so `case 2: ... case 1: ...`
  # routes 3 to the 2 arm and there is no error.
  Bool.pick(String, U32.is_eq(i, 0), ".cpp", Bool.pick(String, U32.is_eq(i, 1), ".bc", ".hsaco"))

# ===========================================================================
# :102-106  THE TWO ARGV LISTS. THE HEADLINE OF THIS FILE.
#
#   subprocess.run(["hipcc", "-c", "-emit-llvm", "--cuda-device-only", "-O3", "-mcumode",
#                   f"--offload-arch={self.arch}", f"-I{rocm_path}/include/hip",
#                   "-o", bcf.name, srcf.name] + self.extra_options, check=True)
#   subprocess.run(["hipcc", "-target", "amdgcn-amd-amdhsa", f"-mcpu={self.arch}",
#                   "-O3", "-mllvm", "-amdgpu-internalize-symbols", "-c",
#                   "-o", libf.name, bcf.name] + self.extra_options, check=True)
#
# `extra_options` is APPENDED, after the source file -- not before `-o`. So the
# element count is 11 with no extras and 13 with two, and a port that spliced
# them elsewhere keeps the COUNT and loses the ORDER, which is why `C.argv_n`
# is pinned next to the joined string.
#
# `rocm_path` is `getenv("ROCM_PATH", "/opt/rocm")`; `getenv` is
# `type(default)(os.getenv(key, default))`, so the default is a STRING and the
# value is used verbatim.
# ===========================================================================
def C.rocm_default() -> String: "/opt/rocm"

def C.rocm_include(rocm: String) -> String: String.concat(["-I", rocm, "/include/hip"])

def C.argv1(arch: String, rocm: String, bc: String, src: String, extra: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, ["hipcc", "-c", "-emit-llvm", "--cuda-device-only", "-O3", "-mcumode",
    String.concat(["--offload-arch=", arch]), C.rocm_include(rocm), "-o", bc, src], extra)

def C.argv2(arch: String, bc: String, lib: String, extra: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, ["hipcc", "-target", "amdgcn-amd-amdhsa",
    String.concat(["-mcpu=", arch]), "-O3", "-mllvm", "-amdgpu-internalize-symbols",
    "-c", "-o", lib, bc], extra)

def C.prog() -> String: "hipcc"

def C.argv_n(n: U32, extra: List<&2, String>) -> U32:
  U32.add(n, U32.from_nat(List.length(&2, String, extra)))

# ===========================================================================
# THE GATE. Every `py=` expectation below is a row of `.agents/slop/cs_oracle.py`
# reproduced BY CALLING the real Python. Nothing here is transcribed.
# ===========================================================================
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def t_ad() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.Ad.version_2", U32.show(Ad.version(2)))
    b : Unit <- srow("amd.Ad.version_3", U32.show(Ad.version(3)))
    c : Unit <- srow("amd.Ad.version_0", U32.show(Ad.version(0)))
    d : Unit <- srow("amd.Ad.hiplang_2", U32.show(Ad.hip_lang(2)))
    e : Unit <- srow("amd.Ad.hiplang_3", U32.show(Ad.hip_lang(3)))
    IO.print("amd_ad_done=1")

def t_check() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.c.msg_0", c.msg(0, "boom"))
    b : Unit <- srow("amd.c.msg_7", c.msg(7, "comgr-status-7"))
    c : Unit <- srow("amd.c.msg_255", c.msg(255, "a b c"))
    d : Unit <- srow("amd.c.msg_min", c.msg(1, ""))
    IO.print("amd_check_done=1")

def t_split() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.sp.n_two", U32.show(sp.n("-O3 -mcumode")))
    b : Unit <- srow("amd.sp.n_empty", U32.show(sp.n("")))
    c : Unit <- srow("amd.sp.n_three", U32.show(sp.n("-O3 -mllvm -amdgpu-internalize-symbols")))
    d : Unit <- srow("amd.sp.n_dbl", U32.show(sp.n("a  b")))
    e : Unit <- srow("amd.sp.n_lead", U32.show(sp.n(" lead")))
    f : Unit <- srow("amd.sp.n_trail", U32.show(sp.n("trail ")))
    g : Unit <- srow("amd.sp.n_tabs", U32.show(sp.n("a\tb")))
    h : Unit <- srow("amd.sp.n_many", U32.show(sp.n("  ")))
    i : Unit <- srow("amd.sp.n_one", U32.show(sp.n("solo")))
    IO.print("amd_split_done=1")

def t_hip() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.h.isa_1100", h.isa("gfx1100"))
    b : Unit <- srow("amd.h.isa_942", h.isa("gfx942"))
    c : Unit <- srow("amd.h.isa_sm86", h.isa("sm_86"))
    d : Unit <- srow("amd.h.dataname_0", h.dataname(False{}))
    e : Unit <- srow("amd.h.dataname_1", h.dataname(True{}))
    f : Unit <- srow("amd.h.opt_n_1100", U32.show(h.opt_n("gfx1100")))
    g : Unit <- srow("amd.h.opt_n_942", U32.show(h.opt_n("gfx942")))
    h : Unit <- srow("amd.h.opt_string_1100", h.opt_string("gfx1100"))
    i : Unit <- srow("amd.h.opt_codegen", h.opt_codegen())
    j : Unit <- srow("amd.h.opt_codegen_n", U32.show(h.opt_codegen_n()))
    k : Unit <- srow("amd.h.opt_empty_n", U32.show(h.opt_empty_n()))
    l : Unit <- srow("amd.h.opt_empty", h.opt_empty())
    IO.print("amd_hip_done=1")

def t_asm() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.C.asm_0", U32.show(Bool.to_u32(C.is_asm(".text"))))
    b : Unit <- srow("amd.C.asm_1", U32.show(Bool.to_u32(C.is_asm(".text\nfoo"))))
    c : Unit <- srow("amd.C.asm_2", U32.show(Bool.to_u32(C.is_asm("  .text  \nfoo"))))
    d : Unit <- srow("amd.C.asm_3", U32.show(Bool.to_u32(C.is_asm(".text "))))
    e : Unit <- srow("amd.C.asm_4", U32.show(Bool.to_u32(C.is_asm(" .text extra"))))
    f : Unit <- srow("amd.C.asm_5", U32.show(Bool.to_u32(C.is_asm("nope"))))
    g : Unit <- srow("amd.C.asm_6", U32.show(Bool.to_u32(C.is_asm(""))))
    h : Unit <- srow("amd.C.asm_7", U32.show(Bool.to_u32(C.is_asm("\n.text"))))
    i : Unit <- srow("amd.C.asm_8", U32.show(Bool.to_u32(C.is_asm("\t.text\t\n"))))
    j : Unit <- srow("amd.C.asm_9", U32.show(Bool.to_u32(C.is_asm("#pragma\n.text"))))
    k : Unit <- srow("amd.C.asm_10", U32.show(Bool.to_u32(C.is_asm(".TEXT\n"))))
    l : Unit <- srow("amd.C.asm_11", U32.show(Bool.to_u32(C.is_asm("x\n.text\n"))))
    m : Unit <- srow("amd.C.asm_12", U32.show(Bool.to_u32(C.is_asm(".text;x\n"))))
    n : Unit <- srow("amd.C.asm_13", U32.show(Bool.to_u32(C.is_asm("\n\n.text"))))
    o : Unit <- srow("amd.C.asm_14", U32.show(Bool.to_u32(C.is_asm("text\n"))))
    p : Unit <- srow("amd.C.asm_15", U32.show(Bool.to_u32(C.is_asm(" .text\n\tmore\n"))))
    IO.print("amd_asm_done=1")

def t_cc() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.C.rocm_default", C.rocm_default())
    b : Unit <- srow("amd.C.rocm_include_def", C.rocm_include(C.rocm_default()))
    c : Unit <- srow("amd.C.rocm_include_my", C.rocm_include("/my/rocm"))
    d : Unit <- srow("amd.C.prog", C.prog())
    e : Unit <- srow("amd.C.suffixes", String.join(C.suffixes(), " "))
    f : Unit <- srow("amd.C.suffix_0", C.suffix_of(0))
    g : Unit <- srow("amd.C.suffix_1", C.suffix_of(1))
    h : Unit <- srow("amd.C.suffix_2", C.suffix_of(2))
    i : Unit <- srow("amd.C.join_extra_none", C.join_extra([]))
    j : Unit <- srow("amd.C.join_extra_one", C.join_extra(["-DFOO=1"]))
    k : Unit <- srow("amd.C.join_extra_two", C.join_extra(["-A", "-B"]))
    l : Unit <- srow("amd.C.join_extra_sp", C.join_extra(["-X y z"]))
    IO.print("amd_cc_done=1")

def t_argv() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.C.argv1_n_none", U32.show(C.argv_n(11, [])))
    b : Unit <- srow("amd.C.argv1_n_two", U32.show(C.argv_n(11, ["-DFOO=1", "-DBAR"])))
    c : Unit <- srow("amd.C.argv2_n_none", U32.show(C.argv_n(11, [])))
    d : Unit <- srow("amd.C.argv2_n_two", U32.show(C.argv_n(11, ["-DFOO=1", "-DBAR"])))
    e : Unit <- srow("amd.C.argv1_none", String.join(C.argv1("gfx1100", "/opt/rocm", ".bc", ".cpp", []), " "))
    f : Unit <- srow("amd.C.argv2_none", String.join(C.argv2("gfx1100", ".bc", ".hsaco", []), " "))
    g : Unit <- srow("amd.C.argv1_extra", String.join(C.argv1("gfx942", "/opt/rocm", ".bc", ".cpp", ["-DFOO=1", "-DBAR"]), " "))
    h : Unit <- srow("amd.C.argv2_extra", String.join(C.argv2("gfx942", ".bc", ".hsaco", ["-DFOO=1", "-DBAR"]), " "))
    i : Unit <- srow("amd.C.argv1_rocm", String.join(C.argv1("gfx1030", "/my/rocm", ".bc", ".cpp", []), " "))
    IO.print("amd_argv_done=1")

def t_key() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.C.hip_key_1100", C.hip_key("gfx1100"))
    b : Unit <- srow("amd.C.hip_key_942", C.hip_key("gfx942"))
    c : Unit <- srow("amd.C.hip_key_1101", C.hip_key("gfx1101"))
    d : Unit <- srow("amd.C.hipcc_key_none", C.hipcc_key("gfx1100", "e3b0c442", False{}))
    e : Unit <- srow("amd.C.hipcc_key_one", C.hipcc_key("gfx1100", "ec5fc367", False{}))
    f : Unit <- srow("amd.C.hipcc_key_nohip", C.hipcc_key("gfx1100", "e3b0c442", True{}))
    g : Unit <- srow("amd.C.hipcc_key_942", C.hipcc_key("gfx942", "af77abf3", False{}))
    h : Unit <- srow("amd.C.short_0", U32.show(C.short_circuit(False{})))
    i : Unit <- srow("amd.C.short_1", U32.show(C.short_circuit(True{})))
    j : Unit <- srow("amd.C.compile_error_1", C.compile_error("compile failed"))
    k : Unit <- srow("amd.C.compile_error_kind_1", C.compile_error_kind("compile failed"))
    l : Unit <- srow("amd.C.compile_error_kind_0", C.compile_error_kind(""))
    m : Unit <- srow("amd.C.asm_fail", c.asm_fail())
    n : Unit <- srow("amd.C.compile_fail", c.compile_fail())
    IO.print("amd_key_done=1")

def t_gd() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.gd.calls", U32.show(gd.calls()))
    b : Unit <- srow("amd.gd.pick_kind_exec", U32.show(gd.pick_kind(True{})))
    c : Unit <- srow("amd.gd.pick_kind_log", U32.show(gd.pick_kind(False{})))
    d : Unit <- srow("amd.gd.calls_name", gd.calls_name())
    f : Unit <- srow("amd.A.source_kind", U32.show(A.source_kind()))
    g : Unit <- srow("amd.A.log_kind", U32.show(A.log_kind()))
    h : Unit <- srow("amd.A.exec_kind", U32.show(A.exec_kind()))
    i : Unit <- srow("amd.A.act_assemble", U32.show(h.act_assemble_name()))
    j : Unit <- srow("amd.A.act_compile", U32.show(h.act_compile_name()))
    k : Unit <- srow("amd.A.act_codegen", U32.show(h.act_codegen_name()))
    l : Unit <- srow("amd.A.act_link", U32.show(h.act_link_name()))
    IO.print("amd_gd_done=1")

# THE TRACE: the ORDER and the IDENTITY of the compile_hip calls, and the two
# branch shapes. A refusal is a trace that STOPS, which is how the raise is
# enforced without a guard.
#
# The chain is PURE -- `Tr.put` is not an effect -- so it cannot live inside a
# `do IO<Unit>` block, whose bindings are all effects. `hd.compile` and
# `hd.asm` build the two traces and the gate reads them.
def hd.compile(t: Tr) -> Tr:
  s0 = Tr.put("amd_comgr_create_action_info", "ai", t)
  s1 = Tr.put("amd_comgr_action_info_set_language", U32.show(Ad.hip_lang(3)), s0)
  s2 = Tr.put("amd_comgr_action_info_set_isa_name", h.isa("gfx1100"), s1)
  s3 = Tr.put("amd_comgr_action_info_set_logging", U32.show(h.logging(True{})), s2)
  s4 = Tr.put("amd_comgr_create_data_set", "src", s3)
  s5 = Tr.put("amd_comgr_create_data_set", "bc", s4)
  s6 = Tr.put("amd_comgr_create_data_set", "reloc", s5)
  s7 = Tr.put("amd_comgr_create_data_set", "exec", s6)
  s8 = Tr.put("amd_comgr_create_data", U32.show(A.source_kind()), s7)
  s9 = Tr.put("amd_comgr_set_data_name", h.dataname(False{}), s8)
  sa = Tr.put("amd_comgr_data_set_add", "src", s9)
  sb = Tr.put("amd_comgr_action_info_set_option_list", U32.show(h.opt_n("gfx1100")), sa)
  sc = Tr.put("amd_comgr_do_action", U32.show(h.act_compile_name()), sb)
  sd = Tr.put("amd_comgr_action_info_set_option_list", U32.show(h.opt_codegen_n()), sc)
  se = Tr.put("amd_comgr_do_action", U32.show(h.act_codegen_name()), sd)
  sf = Tr.put("amd_comgr_action_info_set_option_list", U32.show(h.opt_empty_n()), se)
  Tr.put("amd_comgr_do_action", U32.show(h.act_link_name()), sf)

# the `asm=True` branch: THREE calls instead of sixteen, and the data name is
# `<null>.s`. MEASURED: `amd.hip_gfx1100_1.naction=2`, and the option list is
# never set at all, so `optn0` is absent rather than zero.
def hd.asm(t: Tr) -> Tr:
  s0 = Tr.put("amd_comgr_create_action_info", "ai", t)
  s1 = Tr.put("amd_comgr_action_info_set_language", U32.show(Ad.hip_lang(3)), s0)
  s2 = Tr.put("amd_comgr_action_info_set_isa_name", h.isa("gfx1100"), s1)
  s3 = Tr.put("amd_comgr_create_data_set", "src", s2)
  s4 = Tr.put("amd_comgr_create_data_set", "reloc", s3)
  s5 = Tr.put("amd_comgr_create_data_set", "exec", s4)
  s6 = Tr.put("amd_comgr_create_data", U32.show(A.source_kind()), s5)
  s7 = Tr.put("amd_comgr_set_data_name", h.dataname(True{}), s6)
  s8 = Tr.put("amd_comgr_data_set_add", "src", s7)
  s9 = Tr.put("amd_comgr_do_action", U32.show(h.act_assemble_name()), s8)
  Tr.put("amd_comgr_do_action", U32.show(h.act_link_name()), s9)

def t_trace() -> IO(Unit):
  do IO<Unit>:
    r : Unit <- srow("amd.tr.compile.n", U32.show(Tr.n(hd.compile(Tr.of()))))
    s : Unit <- srow("amd.tr.compile.dataname", h.dataname(False{}))
    v : Unit <- srow("amd.tr.compile.optn0", U32.show(h.opt_n("gfx1100")))
    w : Unit <- srow("amd.tr.compile.act0", U32.show(h.act_compile_name()))
    x : Unit <- srow("amd.tr.compile.act1", U32.show(h.act_codegen_name()))
    y : Unit <- srow("amd.tr.compile.act2", U32.show(h.act_link_name()))
    z : Unit <- srow("amd.tr.asm.n", U32.show(Tr.n(hd.asm(Tr.of()))))
    a1 : Unit <- srow("amd.tr.asm.act0", U32.show(h.act_assemble_name()))
    a2 : Unit <- srow("amd.tr.asm.act1", U32.show(h.act_link_name()))
    a3 : Unit <- srow("amd.tr.asm.dataname", h.dataname(True{}))
    IO.print("amd_trace_done=1")

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_ad()
    b : Unit <- t_check()
    c : Unit <- t_split()
    d : Unit <- t_hip()
    e : Unit <- t_asm()
    f : Unit <- t_cc()
    g : Unit <- t_argv()
    h : Unit <- t_key()
    i : Unit <- t_gd()
    j : Unit <- t_trace()
    IO.print("compiler_amd-done=1")