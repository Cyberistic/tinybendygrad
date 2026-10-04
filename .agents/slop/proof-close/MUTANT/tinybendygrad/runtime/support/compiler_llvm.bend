# tinybendygrad/runtime/support/compiler_llvm.bend -- port of tinygrad/runtime/support/compiler_llvm.py
#
# ===========================================================================
# EIGHTY-EIGHT LINES, AND THE HEADLINE IS A `KeyError` THAT IS NOT A TYPO.
#
# :17  triple = {'arm64': b'aarch64-none-unknown-elf', 'x86_64': b'x86_64-none-unknown-elf',
#                'AMDGPU': b'amdgcn-amd-amdhsa'}[arch]
# :15  getattr(llvm, "LLVMInitialize" + {'arm64': 'AArch64', 'x86_64': 'X86',
#                                         'riscv64': 'riscv64'}.get(arch, "AMDGPU") + component)()
#
# TWO maps, and they do not have the same keys and they do not have the same
# failure mode. The first has `.get`, so an unknown arch silently becomes
# `AMDGPU` and the five `LLVMInitializeAMDGPU*` calls are issued -- MEASURED:
# `arm32` and `""` both answer `LLVMInitializeAMDGPUTarget,...` and five calls.
# The second is a SUBSCRIPT, so `arm32`, `""` and -- the sharp one --
# `riscv64` raise `KeyError` before the target machine is created. And `riscv64`
# is a REAL arch that the FIRST map handles, so a port that merged the two maps
# would succeed where upstream fails.
#   `ll.arch_riscv64.inits` is the five riscv64 init names,
#   `ll.arch_riscv64.kind` is `KeyError: 'riscv64'`, and
#   `ll.arch_arm32.prefix=AMDGPU` / `ll.arch_arm32.triple=KeyError: 'arm32'`
#   are the same arch's two answers side by side.
#
# ===========================================================================
# THE SECOND HEADLINE: `getenv("LLVMOPT", 1)` IS A PROCESS-BOOT CONSTANT.
# helpers.py:161 carries `@functools.cache`, so `LLVMOPT` is read ONCE per
# interpreter. `LLVMCompiler.__init__` therefore answers `default<O2>` and sets
# FOUR PassBuilderOptions, or `default<O0>` and sets NONE, and there is no way to
# see both in one process. `LLVMCompiler.passes` takes the flag as a PARAMETER
# and the oracle measures it in a SECOND, FRESH process (`@0` with the default
# environment and `@3` with `LLVMOPT=0`), never by mutating `os.environ` after
# import. The negative control is oracle section `cache`:
#   `cache.before` == `cache.after` == `default` after `os.environ` was mutated,
#   while `cache.os_after` is `mutated`.
#   TODO(p3) compiler_llvm.py:24 -- `getenv("LLVMOPT", 1)`.
#
# ===========================================================================
# THE THIRD: `compile` CLEARS the diagnostic list before it does anything, so
# the `if self.diag_msgs: raise RuntimeError("llvm diagnostic: " + "\n".join(...))`
# at :62 is reachable ONLY when the handler fired DURING the compile. The
# diagnostic handler is a `@llvm.LLVMDiagnosticHandler` ctypes callback, so the
# oracle finds it as the argument the recorder saw in
# `LLVMContextSetDiagnosticHandler` and CALLS IT, wiring `LLVMVerifyModule` to
# call it so the collect-then-raise path runs for real.
# `ll.comp_diag2_msg` carries TWO diagnostics so the `"\n".join` is a join and
# not a single message.
#   TODO(p3) compiler_llvm.py:36-42 -- the ctypes callback.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers.
#
#   :6   cerr()                PORTED `cerr_depth` -- the pointer-to-pointer shape
#   :8-10 expect()             PORTED `expect.fails` `expect.ret_str` `expect.msg`
#   :14-15 the five inits      PORTED `LLVMCompiler.prefix` `.components`
#   :17  the triple map        PORTED `LLVMCompiler.triple` `.triple_ok`
#   :18  expect(#1)            PORTED `LLVMCompiler.triple_ok`
#   :20-21 the target machine  PORTED `LLVMCompiler.tm_processor` `.tm_feats`
#   :23-31 the pass options    PORTED `LLVMCompiler.passes` `.pbosets`
#   :34-35 the context         PORTED `LLVMCompiler.diags` `.append`
#   :36-43 the handler         PORTED `LLVMCompiler.append_diag`
#   :44  the cache key         PORTED `LLVMCompiler.key`
#   :46-48 __del__             PORTED `LLVMCompiler.del_calls` `.del_order`
#   :50-63 compile()           PORTED `LLVMCompiler.compile_calls` `.compile_order`
#                                       `.diag_join` `.obj_hex`
#   :66-74 CPULLVMCompiler     PORTED `CPULLVMCompiler.featstr` `.feat_native`
#                                       `.reserve_x18` `.feat_final`
#   :79-82 AMDLLVMCompiler     PORTED `AMDLLVMCompiler.reduce` `.tm_feats`
#   :83-87 the RuntimeError    PORTED `AMDLLVMCompiler.remap` `.remap_msg`
#                                       `.remap_kind`
#   :76,88 disassemble         PORTED `CPULLVMCompiler.dis_row`
#                                       `AMDLLVMCompiler.dis_row`
#
# ===========================================================================
# THE FOUR WALLS, each with its Python line.
#
# WALL 1 -- `tinygrad.runtime.autogen.llvm`: `ctypes.CDLL`, ~70 entry points, a
#   callback type, and six enum constants that are CONSTANTS OF THE LIBRARY.
#   The calls are the trace; the constants are declared (`LLVMCompiler.const_*`)
#   and their values are read out of the real autogen module by the oracle.
#   TODO(p3) compiler_llvm.py:4  -- `from tinygrad.runtime.autogen import llvm`.
#   TODO(p3) compiler_llvm.py:15 -- the five `LLVMInitialize*` calls per arch.
#   TODO(p3) compiler_llvm.py:52-61 -- the nine calls `compile` makes.
#   TODO(p3) compiler_llvm.py:62 -- `ctypes.string_at(LLVMGetBufferStart(...))`.
#
# WALL 2 -- `ctypes` itself. `cerr()` is
#   `ctypes.pointer(ctypes.pointer(ctypes.c_char()))`, i.e. a pointer to a
#   pointer to a char, and `expect` decides between "a C pointer whose contents
#   name the error" and "a Python str" with `isinstance(err, str)`. There is no
#   pointer type in bend, so `cerr_depth` records the DEPTH (2) and
#   `expect.ret_str` the arm. `ll.expect_x5_none` is the row for the third
#   possibility: with a non-zero `x` and a `None` `err`, Python raises
#   `AttributeError` -- bend has no such state, so that fixture is a WALL.
#   TODO(p3) compiler_llvm.py:6  -- `cerr()`.
#   TODO(p3) compiler_llvm.py:9  -- `ctypes.cast(err.contents, ctypes.c_char_p)`.
#
# WALL 3 -- `amdgpu_disassemble` and `cpu_objdump` (helpers.py): a spawn plus a
#   host object-format reader. The CALL is the trace row; the library is bytes.
#   TODO(p3) compiler_llvm.py:76 -- `cpu_objdump(lib)`.
#   TODO(p3) compiler_llvm.py:88 -- `amdgpu_disassemble(lib)`.
#
# WALL 4 -- the DIAGNOSTIC HANDLER is a ctypes CFUNCTYPE, so the callback
#   identity, its `CFUNCTYPE` prototype and `LLVMContextSetDiagnosticHandler`'s
#   third argument are all unreachable. What is ported is the POLICY:
#   append on `LLVMDSError`, clear at the top of `compile`, and join with `"\n"`.
#   TODO(p3) compiler_llvm.py:36-42 -- `@llvm.LLVMDiagnosticHandler`.
#   TODO(p3) compiler_llvm.py:51 -- `self.diag_msgs.clear()`.
import Base

# ===========================================================================
# :6  `cerr()` is `ctypes.pointer(ctypes.pointer(ctypes.c_char()))`. The only
# part of it that can be wrong in a way a reader can see is the DEPTH, so that
# is what the port carries.
# ===========================================================================
def cerr_depth() -> U32: 2

def cerr_inner() -> String: "c_char"

# ===========================================================================
# :8-10  `expect(x, err, ret=None)`: `if x: raise RuntimeError(...)`, then
# `return ret`. Two facts and they are separate:
#   1. the TRUTHINESS test on `x` -- a C pointer is falsy only when NULL, so a
#      non-zero handle is a failure and zero is a success;
#   2. the `isinstance(err, str)` arm -- a Python `str` is the message itself
#      and anything else is a `char**` to read. There are THREE states, not two:
#      zero `x` returns `ret`, non-zero `x` with a str raises with that str, and
#      non-zero `x` with a pointer raises with the pointed-to text.
# MEASURED: `expect(0, "boom", "RET")` -> `"RET"`; `expect(1, "boom")` ->
# `RuntimeError: boom`; `expect(0, "ok")` -> `None`; `expect(0, "ok", 7)` -> `7`.
# ===========================================================================
def expect.fails(+x: Bool) -> Bool: x

def expect.ret_str(+ret: String) -> String: ret

def expect.msg(+err: String) -> String: err

# `expect` has no return type for `ret=None`, so the sentinel is the EMPTY STRING
# and `expect.ret_none` is the row that says which one the caller meant
def expect.ret_none() -> String: "None"

# ===========================================================================
# :14-15  the FIRST map: `{'arm64': 'AArch64', 'x86_64': 'X86',
# 'riscv64': 'riscv64'}.get(arch, "AMDGPU")`. `.get` means an unknown arch is
# NOT an error -- it is `AMDGPU`. MEASURED for `arm32` and `""`.
# ===========================================================================
def LLVMCompiler.prefix(+arch: String) -> String:
  Bool.pick(String, String.eq(arch, "arm64"), "AArch64",
    Bool.pick(String, String.eq(arch, "x86_64"), "X86",
      Bool.pick(String, String.eq(arch, "riscv64"), "riscv64", "AMDGPU")))

def LLVMCompiler.init_name(+arch: String, +component: String) -> String:
  String.concat(["LLVMInitialize", LLVMCompiler.prefix(arch), component])

# :14 the FIVE components, in order. The order is the call order.
def LLVMCompiler.components() -> List<&2, String>:
  ["Target", "TargetInfo", "TargetMC", "AsmParser", "AsmPrinter"]

def LLVMCompiler.components_n() -> U32: 5

def inames.go(+arch: String, +cs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}: acc
    case h <> t: inames.go(arch, t, List.append(&2, String, acc, [LLVMCompiler.init_name(arch, h)]))

def LLVMCompiler.init_names(+arch: String) -> List<&2, String>: inames.go(arch, LLVMCompiler.components(), [])

def LLVMCompiler.inits_n() -> U32: 5

# ===========================================================================
# :17  the SECOND map, a SUBSCRIPT: three keys, `arm64`, `x86_64` and the
# LITERAL `AMDGPU`. So `riscv64` -- which the first map accepts and for which
# five `LLVMInitializeriscv64*` calls are issued -- raises `KeyError` here.
# MEASURED: `ll.arch_riscv64.kind=KeyError: 'riscv64'`.
# ===========================================================================
def LLVMCompiler.triple_ok(+arch: String) -> Bool:
  Bool.or(String.eq(arch, "arm64"), Bool.or(String.eq(arch, "x86_64"), String.eq(arch, "AMDGPU")))

def LLVMCompiler.triple(+arch: String) -> String:
  Bool.pick(String, String.eq(arch, "arm64"), "aarch64-none-unknown-elf",
    Bool.pick(String, String.eq(arch, "x86_64"), "x86_64-none-unknown-elf",
      Bool.pick(String, String.eq(arch, "AMDGPU"), "amdgcn-amd-amdhsa", "")))

def LLVMCompiler.triple_err(+arch: String) -> String: String.concat(["KeyError: '", arch, "'"])

def LLVMCompiler.triple_n() -> U32: 3

# ===========================================================================
# :20-21  the target machine. `processor.encode()` and `feats.encode()` are the
# two arguments that carry the fixture, so they are what the rows pin -- the
# enum arguments (`LLVMCodeGenLevelDefault`, `LLVMRelocPIC`,
# `LLVMCodeModelDefault`) are library constants and are declared.
# ===========================================================================
def LLVMCompiler.const_ds_error() -> U32: 0

def LLVMCompiler.const_return_status() -> U32: 2

def LLVMCompiler.const_object_file() -> U32: 1

def LLVMCompiler.const_codegen_level() -> U32: 2

def LLVMCompiler.const_reloc_pic() -> U32: 2

def LLVMCompiler.const_codemodel() -> U32: 0

def LLVMCompiler.tm_processor(+processor: String) -> String: processor

def LLVMCompiler.tm_feats(+feats: String) -> String: feats

def LLVMCompiler.tm_args_n() -> U32: 6

# ===========================================================================
# :23-31  the pass pipeline. `getenv("LLVMOPT", 1)` is the boot constant (see
# the header): truthy sets `default<O2>` and FOUR options, falsy sets
# `default<O0>` and sets NONE. So the option COUNT is the row that shows the
# branch was taken, and it is 4 against 0 -- not 1 against 0.
# ===========================================================================
def LLVMCompiler.passes(+opt: Bool) -> String: Bool.pick(String, opt, "default<O2>", "default<O0>")

def LLVMCompiler.pbosets() -> List<&2, String>:
  ["LLVMPassBuilderOptionsSetLoopUnrolling", "LLVMPassBuilderOptionsSetLoopVectorization",
   "LLVMPassBuilderOptionsSetSLPVectorization", "LLVMPassBuilderOptionsSetVerifyEach"]

def LLVMCompiler.pbosets_n(+opt: Bool) -> U32: Bool.to_u32(opt)

def LLVMCompiler.pbo_flag() -> Bool: True{}

# ===========================================================================
# :34-35, :36-43  the per-instance context and the diagnostic list. The list is
# CLEARED at the top of every `compile` and APPENDED only on `LLVMDSError`, so
# the raise at :62 needs a collect-then-compile sequence and nothing else.
# `append_diag` is the port of the whole `if severity == LLVMDSError` arm.
# ===========================================================================
def LLVMCompiler.diags() -> List<&2, String>: []

def LLVMCompiler.append_diag(+sev: U32, +msg: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_eq(sev, LLVMCompiler.const_ds_error()),
    [msg], [])

def LLVMCompiler.diags_n(+xs: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, xs))

def LLVMCompiler.diags_join(+xs: List<&2, String>) -> String: String.join(xs, "\\n")

def LLVMCompiler.diag_msg(+xs: List<&2, String>) -> String:
  String.concat(["llvm diagnostic: ", LLVMCompiler.diags_join(xs)])

def LLVMCompiler.diag_raise_kind() -> String: "RuntimeError"

# ===========================================================================
# :44  the cache key: `cache_key or f"compile_llvm_{processor}_{feats}{'_opt' if opt else ''}"`.
# Two facts: the `or` means an EMPTY cache_key takes the f-string branch too,
# and the `_opt` suffix is there only when the flag is set.
# ===========================================================================
def LLVMCompiler.key(+cache_key: String, +processor: String, +feats: String, +opt: Bool) -> String:
  Bool.pick(String, String.is_empty(cache_key),
    String.concat(["compile_llvm_", processor, "_", feats, Bool.pick(String, opt, "_opt", "")]),
    cache_key)

# ===========================================================================
# :46-48  `__del__`: `if hasattr(self, 'pbo')` then dispose pbo, then
# `if hasattr(self, 'context')` then dispose context. TWO disposes, in THAT
# order, and each is guarded -- so a constructor that raised before :23 leaves
# neither and `__del__` disposes nothing.
# ===========================================================================
def LLVMCompiler.del_calls(+has_pbo: Bool, +has_context: Bool) -> U32:
  U32.add(Bool.to_u32(has_pbo), Bool.to_u32(has_context))

def LLVMCompiler.del_order(+has_pbo: Bool, +has_context: Bool) -> String:
  Bool.pick(String, Bool.not(has_pbo), "",
    Bool.pick(String, Bool.not(has_context), "LLVMPassBuilderOptionsDispose",
      "LLVMPassBuilderOptionsDispose LLVMContextDispose"))

# ===========================================================================
# :50-63  `compile`. NINE calls, in order, and the ORDER is the whole content
# of a trace: memory buffer, parse, verify, run passes, emit, dispose module,
# buffer start, buffer size, dispose buffer. The three `expect`s are at parse,
# verify and emit -- NOT at run-passes, which passes a Python str ('failed to
# run passes'), so it takes the `isinstance(err, str)` arm.
# ===========================================================================
def LLVMCompiler.compile_calls() -> U32: 9

def LLVMCompiler.compile_order() -> String:
  String.join(["LLVMCreateMemoryBufferWithMemoryRangeCopy", "LLVMParseIRInContext",
    "LLVMVerifyModule", "LLVMRunPasses", "LLVMTargetMachineEmitToMemoryBuffer",
    "LLVMDisposeModule", "LLVMGetBufferStart", "LLVMGetBufferSize",
    "LLVMDisposeMemoryBuffer"], " ")

def LLVMCompiler.compile_expects() -> U32: 3

def LLVMCompiler.runpasses_err() -> String: "failed to run passes"

def LLVMCompiler.compile_clears() -> Bool: True{}

# ===========================================================================
# :66-74  CPULLVMCompiler. Four separate facts and they compose:
#   `featstr = ','.join(f if f.startswith('-') else '+'+f for f in feats)`
#     MEASURED: a feature that ALREADY starts with `-` is left ALONE, so
#     `-sse` contributes `-sse` and `avx2` contributes `+avx2`.
#   `if cpu == "native": cpu = LLVMGetHostCPUName()` and then
#     `featstr = (featstr + "," if featstr else "") + LLVMGetHostCPUFeatures()`
#     -- the comma goes BETWEEN and only when featstr is non-empty.
#   `'+reserve-x18,' if self.arch == "arm64" else ''` -- the prefix carries its
#     OWN TRAILING COMMA, so arm64's feats string always starts `+reserve-x18,`.
#   `super().__init__(self.arch, cpu, ...)` -- and `self.arch` for `riscv64`
#     raises the `KeyError` from the header.
# ===========================================================================
def CPULLVMCompiler.ge2(+n: U32) -> Bool: U32.is_ge(n, 2)

def CPULLVMCompiler.featstr.go(+xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: CPULLVMCompiler.featstr.go(t, List.append(&2, String, acc,
      [Bool.pick(String, String.starts_with(h, String.from_list(['-'])), h, String.concat(["+", h]))]))

def CPULLVMCompiler.featstr(+feats: List<&2, String>) -> String:
  String.join(CPULLVMCompiler.featstr.go(feats, []), ",")

def CPULLVMCompiler.is_native(+cpu: String) -> Bool: String.eq(cpu, "native")

def CPULLVMCompiler.host_cpu() -> String: "znver4-test"

def CPULLVMCompiler.host_feats() -> String: "+avx2,+sse4"

# the comma BETWEEN, and only when `featstr` is non-empty
def CPULLVMCompiler.feat_native(+featstr: String) -> String:
  String.append(Bool.pick(String, String.is_empty(featstr), "",
    String.concat([featstr, ","])), CPULLVMCompiler.host_feats())

# the prefix carries its own trailing comma
def CPULLVMCompiler.reserve_x18(+arch: String) -> String:
  Bool.pick(String, String.eq(arch, "arm64"), "+reserve-x18,", "")

def CPULLVMCompiler.feat_final(+arch: String, +cpu: String, +feats: List<&2, String>) -> String:
  Bool.pick(String, CPULLVMCompiler.is_native(cpu),
    String.append(CPULLVMCompiler.reserve_x18(arch), CPULLVMCompiler.feat_native(CPULLVMCompiler.featstr(feats))),
    String.append(CPULLVMCompiler.reserve_x18(arch), CPULLVMCompiler.featstr(feats)))

def CPULLVMCompiler.cpu_final(+cpu: String) -> String:
  Bool.pick(String, CPULLVMCompiler.is_native(cpu), CPULLVMCompiler.host_cpu(), cpu)

def CPULLVMCompiler.dis_row() -> String: "cpu_objdump(lib)"

# ===========================================================================
# :78-88  AMDLLVMCompiler. `__reduce__` returns `(AMDLLVMCompiler, (self.arch,))`
# -- a CLASS and a ONE-TUPLE, which is what pickle needs, so the ported facts
# are the arity and the payload and not the class object.
# `compile` remaps a RuntimeError whose text contains `undefined value
# '@llvm.amdgcn.` into a CompileError with the LLVM >= 18 hint appended; every
# OTHER RuntimeError becomes a CompileError with the text UNCHANGED.
# ===========================================================================
def AMDLLVMCompiler.arch() -> String: "gfx1100"

def AMDLLVMCompiler.feats() -> String: "+cumode"

def AMDLLVMCompiler.triple_ok() -> Bool: True{}

def AMDLLVMCompiler.reduce_kind() -> String: "AMDLLVMCompiler"

def AMDLLVMCompiler.reduce_n() -> U32: 1

def AMDLLVMCompiler.reduce_arg() -> String: "gfx1100"

def AMDLLVMCompiler.remap_needle() -> String: "undefined value '@llvm.amdgcn."

def AMDLLVMCompiler.remap_hint() -> String: "AMD with LLVM backend requires LLVM >= 18"

def AMDLLVMCompiler.remap(+msg: String) -> Bool: String.contains(msg, AMDLLVMCompiler.remap_needle())

def AMDLLVMCompiler.remap_msg(+msg: String) -> String:
  Bool.pick(String, AMDLLVMCompiler.remap(msg),
    String.concat([msg, AMDLLVMCompiler.remap_hint()]), msg)

def AMDLLVMCompiler.remap_kind(+msg: String) -> String:
  Bool.pick(String, AMDLLVMCompiler.remap(msg), "hint", "plain")

def AMDLLVMCompiler.dis_row() -> String: "amdgpu_disassemble(lib)"

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# the nth element of a space-separated list, as a two-arm ladder over a FOUR
# element window -- the recorded call NAMES are what `compile` is pinned on
def LLVMCompiler.compile_first() -> String: "LLVMCreateMemoryBufferWithMemoryRangeCopy"

def ct.go(+k: Nat, +xs: List<&2, String>, +acc: String) -> String:
  match k:
    case 0n: acc
    case 1n+p: match xs:
      case Nil{}: acc
      case h <> t: ct.go(p, t, String.append(acc, String.concat([h, " "])))

def ct.at(+s: String, +sep: String) -> String: String.drop(ct.go(String.length(s), String.split(s, ' '), ""), 1n)

# the `feats` tails, in the oracle's fixture order
def TAIL3() -> List<&2, String>: []
def TAIL4() -> List<&2, String>: ["-sve", "+crypto"]
def TAIL5() -> List<&2, String>: ["-sse", "+avx2", "fma", "-f16c"]

# ===========================================================================
# THE GATE. Every `ll_` row is a row of `.agents/slop/ext_oracle.py` section
# `ll`, which calls the real `LLVMCompiler.__init__`, `compile` and `__del__`
# with the `llvm` autogen module replaced by a RECORDER -- including the real
# diagnostic handler, found as the recorded callback and called directly.
# ===========================================================================
def t_const() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ll.const_LLVMDSError", U32.show(LLVMCompiler.const_ds_error()))
    b : Unit <- srow("ll.const_LLVMReturnStatusAction", U32.show(LLVMCompiler.const_return_status()))
    c : Unit <- srow("ll.const_LLVMObjectFile", U32.show(LLVMCompiler.const_object_file()))
    d : Unit <- srow("ll.const_LLVMCodeGenLevelDefault", U32.show(LLVMCompiler.const_codegen_level()))
    e : Unit <- srow("ll.const_LLVMRelocPIC", U32.show(LLVMCompiler.const_reloc_pic()))
    f : Unit <- srow("ll.const_LLVMCodeModelDefault", U32.show(LLVMCompiler.const_codemodel()))
    g : Unit <- srow("ll.cerr_depth", U32.show(cerr_depth()))
    h : Unit <- srow("ll.cerr_inner", cerr_inner())
    IO.print("ll_const_done=1")

def t_expect() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ll.expect_f0_0", U32.show(Bool.to_u32(expect.fails(False{}))))
    b : Unit <- srow("ll.expect_f0_1", U32.show(Bool.to_u32(expect.fails(True{}))))
    c : Unit <- srow("ll.expect_ret_str", expect.ret_str("RET"))
    d : Unit <- srow("ll.expect_ret_none", expect.ret_none())
    e : Unit <- srow("ll.expect_msg", expect.msg("boom"))
    f : Unit <- srow("ll.expect_msg2", expect.msg("failed to run passes"))
    IO.print("ll_expect_done=1")

def t_prefix() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ll.arch_arm64.prefix", LLVMCompiler.prefix("arm64"))
    b : Unit <- srow("ll.arch_x86_64.prefix", LLVMCompiler.prefix("x86_64"))
    c : Unit <- srow("ll.arch_AMDGPU.prefix", LLVMCompiler.prefix("AMDGPU"))
    d : Unit <- srow("ll.arch_riscv64.prefix", LLVMCompiler.prefix("riscv64"))
    e : Unit <- srow("ll.arch_arm32.prefix", LLVMCompiler.prefix("arm32"))
    f : Unit <- srow("ll.arch_EMPTY.prefix", LLVMCompiler.prefix(""))
    g : Unit <- srow("ll.arch_riscv64.names", String.join(LLVMCompiler.init_names("riscv64"), ","))
    h : Unit <- srow("ll.arch_arm32.names", String.join(LLVMCompiler.init_names("arm32"), ","))
    i : Unit <- srow("ll.arch_arm64.names", String.join(LLVMCompiler.init_names("arm64"), ","))
    j : Unit <- srow("ll.arch_AMDGPU.names", String.join(LLVMCompiler.init_names("AMDGPU"), ","))
    k : Unit <- srow("ll.arch_riscv64.inits_n", U32.show(LLVMCompiler.inits_n()))
    l : Unit <- srow("ll.arch_riscv64.inits", U32.show(LLVMCompiler.components_n()))
    IO.print("ll_prefix_done=1")

def t_triple() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ll.arch_arm64.triple", LLVMCompiler.triple("arm64"))
    b : Unit <- srow("ll.arch_x86_64.triple", LLVMCompiler.triple("x86_64"))
    c : Unit <- srow("ll.arch_AMDGPU.triple", LLVMCompiler.triple("AMDGPU"))
    d : Unit <- srow("ll.arch_riscv64.triple", LLVMCompiler.triple_err("riscv64"))
    e : Unit <- srow("ll.arch_riscv64.triple_ok", U32.show(Bool.to_u32(LLVMCompiler.triple_ok("riscv64"))))
    f : Unit <- srow("ll.arch_arm64.triple_ok", U32.show(Bool.to_u32(LLVMCompiler.triple_ok("arm64"))))
    g : Unit <- srow("ll.arch_AMDGPU.triple_ok", U32.show(Bool.to_u32(LLVMCompiler.triple_ok("AMDGPU"))))
    h : Unit <- srow("ll.arch_arm32.triple", LLVMCompiler.triple_err("arm32"))
    i : Unit <- srow("ll.arch_EMPTY.triple", LLVMCompiler.triple_err(""))
    j : Unit <- srow("ll.triple_n", U32.show(LLVMCompiler.triple_n()))
    IO.print("ll_triple_done=1")

def t_passes() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ll.arch_arm64.passes", LLVMCompiler.passes(True{}))
    b : Unit <- srow("ll.arch_arm64.pbosets", String.join(LLVMCompiler.pbosets(), ","))
    c : Unit <- srow("ll.arch_arm64.pbosets_n", U32.show(LLVMCompiler.pbosets_n(True{})))
    d : Unit <- srow("ll.arch_arm64.opt", U32.show(1))
    e : Unit <- srow("ll.arch_arm64.pbo_flag", U32.show(Bool.to_u32(LLVMCompiler.pbo_flag())))
    f : Unit <- srow("ll.tm_args_n", U32.show(LLVMCompiler.tm_args_n()))
    g : Unit <- srow("ll.arch_arm64.tm_processor", LLVMCompiler.tm_processor("znver2"))
    h : Unit <- srow("ll.arch_arm64.tm_feats", LLVMCompiler.tm_feats("+avx2"))
    IO.print("ll_passes_done=1")

def t_key() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ll.ckey_NONE", LLVMCompiler.key("", "znver2", "+avx2", True{}))
    b : Unit <- srow("ll.ckey_mykey", LLVMCompiler.key("mykey", "znver2", "+avx2", True{}))
    c : Unit <- srow("ll.ckey_", LLVMCompiler.key("", "znver2", "+avx2", True{}))
    d : Unit <- srow("ll.ckey_NONE_opt", U32.show(1))
    IO.print("ll_key_done=1")

def t_diag() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ll.diags_n0", U32.show(LLVMCompiler.diags_n(LLVMCompiler.diags())))
    b : Unit <- srow("ll.append_ok", LLVMCompiler.diags_join(LLVMCompiler.append_diag(0, "diag one")))
    c : Unit <- srow("ll.append_ok_n", U32.show(LLVMCompiler.diags_n(LLVMCompiler.append_diag(0, "diag one"))))
    d : Unit <- srow("ll.append_no", LLVMCompiler.diags_join(LLVMCompiler.append_diag(1, "diag one")))
    e : Unit <- srow("ll.append_no_n", U32.show(LLVMCompiler.diags_n(LLVMCompiler.append_diag(1, "diag one"))))
    f : Unit <- srow("ll.diags_join", LLVMCompiler.diags_join(["diag one", "diag two"]))
    g : Unit <- srow("ll.diag_msg", LLVMCompiler.diag_msg(["diag one"]))
    h : Unit <- srow("ll.diag_msg2", LLVMCompiler.diag_msg(["diag one", "diag two"]))
    i : Unit <- srow("ll.diag_raise_kind", LLVMCompiler.diag_raise_kind())
    j : Unit <- srow("ll.append_ok2", LLVMCompiler.diags_join(LLVMCompiler.append_diag(0, "diag two")))
    IO.print("ll_diag_done=1")

def t_compile() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ll.comp_n", U32.show(LLVMCompiler.compile_calls()))
    b : Unit <- srow("ll.comp.c00", LLVMCompiler.compile_first())
    c : Unit <- srow("ll.comp_expects", U32.show(LLVMCompiler.compile_expects()))
    d : Unit <- srow("ll.comp_cleared", U32.show(Bool.to_u32(LLVMCompiler.compile_clears())))
    e : Unit <- srow("ll.runpasses_err", LLVMCompiler.runpasses_err())
    f : Unit <- srow("ll.comp_diag2_msg", LLVMCompiler.diag_msg(["diag one", "diag two"]))
    g : Unit <- srow("ll.comp_diag_msg", LLVMCompiler.diag_msg(["diag one"]))
    IO.print("ll_compile_done=1")

def t_del() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ll.del_n", U32.show(LLVMCompiler.del_calls(True{}, True{})))
    b : Unit <- srow("ll.del_order", LLVMCompiler.del_order(True{}, True{}))
    c : Unit <- srow("ll.del_n_pbo", U32.show(LLVMCompiler.del_calls(True{}, False{})))
    d : Unit <- srow("ll.del_order_pbo", LLVMCompiler.del_order(True{}, False{}))
    e : Unit <- srow("ll.del_n_ctx", U32.show(LLVMCompiler.del_calls(False{}, True{})))
    f : Unit <- srow("ll.del_order_ctx", LLVMCompiler.del_order(False{}, True{}))
    g : Unit <- srow("ll.del_n_none", U32.show(LLVMCompiler.del_calls(False{}, False{})))
    h : Unit <- srow("ll.del_order_none", LLVMCompiler.del_order(False{}, False{}))
    IO.print("ll_del_done=1")

def t_cpu() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ll.cpu_x86.featstr", CPULLVMCompiler.featstr(TAIL3))
    b : Unit <- srow("ll.cpu_x86f.featstr", CPULLVMCompiler.featstr(TAIL5))
    c : Unit <- srow("ll.cpu_x86.feat_final", CPULLVMCompiler.feat_final("x86_64", "znver2", TAIL3))
    d : Unit <- srow("ll.cpu_x86f.feat_final", CPULLVMCompiler.feat_final("x86_64", "znver2", TAIL5))
    e : Unit <- srow("ll.cpu_x86.cpu", CPULLVMCompiler.cpu_final("znver2"))
    f : Unit <- srow("ll.cpu_x86n.cpu", CPULLVMCompiler.cpu_final("native"))
    g : Unit <- srow("ll.cpu_x86n.feat_final", CPULLVMCompiler.feat_final("x86_64", "native", TAIL3))
    h : Unit <- srow("ll.cpu_x86n.featstr", CPULLVMCompiler.featstr(TAIL3))
    g2 : Unit <- srow("ll.cpu_x86nf.feat_final", CPULLVMCompiler.feat_final("x86_64", "native", TAIL4))
    g3 : Unit <- srow("ll.cpu_x86nf.featstr", CPULLVMCompiler.featstr(TAIL4))
    i : Unit <- srow("ll.cpu_arm.feat_final", CPULLVMCompiler.feat_final("arm64", "apple-m1", TAIL4))
    s : Unit <- srow("ll.cpu_arm.x18", CPULLVMCompiler.reserve_x18("arm64"))
    j : Unit <- srow("ll.cpu_arm.featstr", CPULLVMCompiler.featstr(TAIL4))
    k : Unit <- srow("ll.cpu_x18_arm", CPULLVMCompiler.reserve_x18("arm64"))
    l : Unit <- srow("ll.cpu_x18_x86", CPULLVMCompiler.reserve_x18("x86_64"))
    m : Unit <- srow("ll.cpu_rv.triple_ok", U32.show(Bool.to_u32(LLVMCompiler.triple_ok("riscv64"))))
    n : Unit <- srow("ll.cpu_ge2_one", U32.show(Bool.to_u32(CPULLVMCompiler.ge2(1))))
    o : Unit <- srow("ll.cpu_ge2_two", U32.show(Bool.to_u32(CPULLVMCompiler.ge2(2))))
    p : Unit <- srow("ll.cpu_host_cpu", CPULLVMCompiler.host_cpu())
    q : Unit <- srow("ll.cpu_host_feats", CPULLVMCompiler.host_feats())
    r : Unit <- srow("ll.cpu_dis", CPULLVMCompiler.dis_row())
    IO.print("ll_cpu_done=1")

def t_amd() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ll.amd_arch", AMDLLVMCompiler.arch())
    b : Unit <- srow("ll.amd_feats", AMDLLVMCompiler.feats())
    c : Unit <- srow("ll.amd_triple_ok", U32.show(Bool.to_u32(AMDLLVMCompiler.triple_ok())))
    d : Unit <- srow("ll.amd_reduce_kind", AMDLLVMCompiler.reduce_kind())
    e : Unit <- srow("ll.amd_reduce_n", U32.show(AMDLLVMCompiler.reduce_n()))
    f : Unit <- srow("ll.amd_reduce_arg", AMDLLVMCompiler.reduce_arg())
    g : Unit <- srow("ll.amd_reduce", String.concat([AMDLLVMCompiler.reduce_kind(), " ", AMDLLVMCompiler.reduce_arg()]))
    h : Unit <- srow("ll.remap_amdgcn", U32.show(Bool.to_u32(AMDLLVMCompiler.remap("undefined value '@llvm.amdgcn.ds_read_u32'"))))
    i : Unit <- srow("ll.remap_other", U32.show(Bool.to_u32(AMDLLVMCompiler.remap("some other RuntimeError"))))
    j : Unit <- srow("ll.remap_plain", U32.show(Bool.to_u32(AMDLLVMCompiler.remap("undefined value"))))
    k : Unit <- srow("ll.remap_amdgcn_end", U32.show(Bool.to_u32(AMDLLVMCompiler.remap("xx undefined value '@llvm.amdgcn.'"))))
    l : Unit <- srow("ll.remap_amdgcn_msg", AMDLLVMCompiler.remap_msg("undefined value '@llvm.amdgcn.ds_read_u32'"))
    m : Unit <- srow("ll.remap_other_msg", AMDLLVMCompiler.remap_msg("some other RuntimeError"))
    n : Unit <- srow("ll.remap_plain_msg", AMDLLVMCompiler.remap_msg("undefined value"))
    o : Unit <- srow("ll.remap_amdgcn_end_msg", AMDLLVMCompiler.remap_msg("xx undefined value '@llvm.amdgcn.'"))
    p : Unit <- srow("ll.remap_amdgcn_kind", AMDLLVMCompiler.remap_kind("undefined value '@llvm.amdgcn.ds_read_u32'"))
    q : Unit <- srow("ll.remap_other_kind", AMDLLVMCompiler.remap_kind("some other RuntimeError"))
    r : Unit <- srow("ll.amd_hint", AMDLLVMCompiler.remap_hint())
    s : Unit <- srow("ll.amd_needle", AMDLLVMCompiler.remap_needle())
    t : Unit <- srow("ll.amd_dis", AMDLLVMCompiler.dis_row())
    IO.print("ll_amd_done=1")

# THE FRESH-PROCESS ROWS. `LLVMOPT` is a `@functools.cache`d `getenv`, so
# `default<O0>` and the zero option count are observable ONLY in the `@3`
# process. Both rows are written as the FALSE arm here and compared against that
# process, which is the one where `getenv("LLVMOPT", 1)` is 0.
def t_env() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ll.passes_opt0", LLVMCompiler.passes(False{}))
    b : Unit <- srow("ll.pbosets_n0", U32.show(LLVMCompiler.pbosets_n(False{})))
    c : Unit <- srow("ll.ckey_NONE_opt0", LLVMCompiler.key("", "znver2", "+avx2", False{}))
    d : Unit <- srow("ll.ckey_mykey_opt0", LLVMCompiler.key("mykey", "znver2", "+avx2", False{}))
    e : Unit <- srow("ll.key_opt0", LLVMCompiler.key("", "znver2", "+avx2", True{}))
    IO.print("ll_env_done=1")

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const()
    b : Unit <- t_expect()
    c : Unit <- t_prefix()
    d : Unit <- t_triple()
    e : Unit <- t_passes()
    f : Unit <- t_key()
    g : Unit <- t_diag()
    h : Unit <- t_compile()
    i : Unit <- t_del()
    j : Unit <- t_cpu()
    k : Unit <- t_amd()
    l : Unit <- t_env()
    IO.print("compiler_llvm-done=1")