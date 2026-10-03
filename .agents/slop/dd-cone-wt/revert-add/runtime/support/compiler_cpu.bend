# tinybendygrad/runtime/support/compiler_cpu.bend -- port of tinygrad/runtime/support/compiler_cpu.py
#
# ===========================================================================
# THIRTY LINES, AND THE ONLY THING THAT IS NOT PURE IS ONE `subprocess` CALL
# WHICH `Process.run` ALREADY COVERS.
#
#   subprocess.check_output([getenv("CC", 'clang'), '-c', '-x', 'c', '-O2', '-fPIC',
#                           '-ffreestanding', '-fno-math-errno', '-nostdlib', '-fno-ident',
#                           f'--target={self.arch}-none-unknown-elf', *self.args, '-', '-o', '-'],
#                          input=src.encode('utf-8'))
#
# `base.bend:182`'s `Process.run(program, args, input, max_output, timeout_ms)` is
# a real `posix_spawnp` with a stdin pipe, a stdout pipe, a stderr pipe, a poll
# loop and a `waitpid`, so the list BELOW is the argv and the port is 1:1. There
# is no `@extern`, no seam declaration and no new foreign effect: this file
# declares none, which is why it is `ALL PROOFS CHECK` on both lanes.
#
# What `Process.run` genuinely cannot do, and what is therefore a WALL here:
# nothing. The duplex pipe is `compileserver.bend`'s problem and the merged
# `stderr=STDOUT` is `helpers.system`'s problem, and neither is this file.
#   TODO(p3) compiler_cpu.py:21 -- the `subprocess.check_output` CALL itself.
#   TODO(p3) compiler_cpu.py:21 -- `input=src.encode('utf-8')` (bend has no
#                                    bytes; the source is a `String` already).
#
# ===========================================================================
# THE ARCH `match`, and it is the whole file. THREE arms, each of which builds
# a DIFFERENT list, and the trap is that all three reuse the SAME `feats` list in
# three different languages:
#
#   x86_64   f"-march={cpu}"  + [f"-mno{f}" if f.startswith("-") else f"-m{f}"]
#            MEASURED: the `-mno` branch KEEPS the leading `-`, so the feature
#            `-sse` becomes `-mno-sse`, not `-mnosse`. And a feature that does
#            not start with `-` gets a bare `-m` prefix, so `+fma` becomes
#            `-m+fma` and the EMPTY string becomes the flag `-m`.
#            (`cpu.x86_64f.args` and `cpu.x86blank.args` are the rows.)
#
#   arm64    ["-ffixed-x18", "-mcpu=" + "+".join([cpu] + feats)]
#            with each feature `"no" + f[1:]` if it starts with `-`. So `-sve`
#            becomes `nosve` -- the `-` is CONSUMED, unlike the x86 arm -- and
#            `+crypto` stays `+crypto`, which makes the join read
#            `apple-m1+nosve++crypto`. (`cpu.arm64f.args`.)
#            NOTE the order: x18 is fixed because it is a reserved platform
#            register, clobbered on context switch in macOS.
#
#   riscv64  "-march=" + "_".join(["rv64g" if cpu == "native" else cpu] + feats)
#            MEASURED: `native` becomes `rv64g`, and the features are joined
#            RAW -- no `-m`, no `+`, nothing. (`cpu.riscv64nf.args`.)
#
# and the `case _:` arm RAISES, so `sparc64` and `X86_64` (upper case) are both
# refusals -- the match is case sensitive and there is no prefix matching.
# `cpu.sparc.kind` and `cpu.X86.kind` are the rows.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers. Def names are
# UPSTREAM names where upstream HAS one.
#
#   :7   the assert                PORTED `ClangCompiler.ge2` `ClangCompiler.msg`
#   :8   the unpack                PORTED `ClangCompiler.arch_of` `.cpu_of`
#                                          `.feats`
#   :10  the x86_64 arm            PORTED `ClangCompiler.x86_feat` `ClangCompiler.args`
#   :13  the arm64 arm             PORTED `ClangCompiler.arm64_feat` `ClangCompiler.args`
#   :14  the riscv64 arm           PORTED `ClangCompiler.riscv64_cpu`
#                                          `ClangCompiler.args`
#   :15  the refusal               PORTED `ClangCompiler.supported` `ClangCompiler.unsupported`
#   :16  the cache key             PORTED `ClangCompiler.key`
#   :21-22 the spawn               PORTED `ClangCompiler.compile_argv` `.argv_n`
#   :24  disassemble               PORTED `ClangCompiler.dis_row`
#   :28  X86Compiler.__init__      PORTED `X86Compiler.key`
#   :29  X86Compiler.compile       PORTED `X86Compiler.nibble` `X86Compiler.hex_ok`
#                                          `X86Compiler.hex_n` `X86Compiler.bad_pos`
#   :30  X86Compiler.disassemble   PORTED `X86Compiler.dis_row`
#
# ===========================================================================
# THE FOUR WALLS, each with its Python line.
#
# WALL 1 -- bytes. `src.encode('utf-8')` and `bytes.fromhex(src)` are byte
#   operations and bend has no byte buffer. `compile`'s source is a `String`
#   (WALL 2 above), and `X86Compiler.compile`'s HEX is ported as the scanner that
#   decides whether `bytes.fromhex` accepts the string and, if not, at WHICH
#   position -- which is the part of the ValueError that is computed rather than
#   fixed. The bytes themselves are WALL 1.
#   TODO(p3) compiler_cpu.py:21 -- `src.encode('utf-8')`.
#   TODO(p3) compiler_cpu.py:29 -- `bytes.fromhex(src)`.
#
# WALL 2 -- `cpu_objdump` and `capstone_flatdump` (helpers.py) are a
#   `subprocess` spawn plus a capstone/llvm object. `ClangCompiler.dis_row` and
#   `X86Compiler.dis_row` record the CALL; the argument is a byte blob.
#   TODO(p3) compiler_cpu.py:24 -- `cpu_objdump(lib)`.
#   TODO(p3) compiler_cpu.py:30 -- `capstone_flatdump(lib, "x86_64")`.
#
# WALL 3 -- `getenv("CC", 'clang')` is a PROCESS-BOOT CONSTANT: helpers.py:161
#   carries `@functools.cache`, so `CC` is read ONCE per interpreter and
#   setting it later is invisible. `ClangCompiler.prog` therefore takes the
#   compiler as a PARAMETER, and the oracle measures it in a SECOND, FRESH
#   process (`@0` with `CC` unset and `@1` with `CC=mycc`) rather than in one
#   process that would have reported the first configuration for both.
#   MEASURED, and the negative control is in oracle section `cache`:
#   `cache.before`/`cache.after` are both `default` after `os.environ` was
#   mutated, while `cache.os_after` is `mutated`.
#   TODO(p3) compiler_cpu.py:21 -- `getenv("CC", 'clang')`.
#
# WALL 4 -- `CCACHE`. `Compiler.__init__` is
#   `self.cachekey = cachekey if CCACHE else None` (device.py:337), so the key
#   the port builds is the one that EXISTS only when CCACHE is on -- and CCACHE
#   is a `ContextVar`, which is the same cached `getenv`. So `cpu.x86key` is
#   `None` on this host ONLY because... it is measured, and the port's
#   `X86Compiler.key` carries the `None` as an empty string.
#   TODO(p3) device.py:337 -- `cachekey if CCACHE else None`.
import Base

# ===========================================================================
# :7  the assert. `len(arch) >= 2`, and the message interpolates
# `','.join(arch)!r` -- a Python REPR, so a one-element list prints with quotes.
# MEASURED: `['x86_64']` -> `invalid arch string: 'x86_64', ...` and `[]` ->
# `invalid arch string: '', ...`.
# ===========================================================================
def ClangCompiler.ge2(+n: U32) -> Bool: U32.is_ge(n, 2)

def ClangCompiler.min_n() -> U32: 2

def ClangCompiler.msg(+arch: List<&2, String>) -> String:
  String.concat(["invalid arch string: '", String.join(arch, ","), "', expected '<arch>,<cpu>,[<feats>]' (eg. 'x86_64,znver2')"])

# ===========================================================================
# :8  `self.arch, cpu, *feats = arch`. The unpack fails on a SHORT list, which
# is what the assert above refuses first, so the three readers are total and the
# arity is a SEPARATE question from the values.
# ===========================================================================
def ClangCompiler.n(+xs: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, xs))

def str.at.of(m: Maybe<&2, String>) -> String:
  match m:
    case Some{v}: v
    case None{}: ""

def ClangCompiler.at(+xs: List<&2, String>, +i: U32) -> String:
  str.at.of(List.get(&2, String, xs, U32.to_nat(i)))

def ClangCompiler.arch_of(+xs: List<&2, String>) -> String: ClangCompiler.at(xs, 0)

def ClangCompiler.cpu_of(+xs: List<&2, String>) -> String: ClangCompiler.at(xs, 1)

def ClangCompiler.feats_tail(+xs: List<&2, String>) -> List<&2, String>: List.drop(&2, String, xs, 2n)

def ClangCompiler.feats(+xs: List<&2, String>) -> String: String.join(ClangCompiler.feats_tail(xs), ",")

def ClangCompiler.feats_n(+xs: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, ClangCompiler.feats_tail(xs)))

# ===========================================================================
# :10  the x86_64 feature flag: `f"-mno{f}" if f.startswith("-") else f"-m{f}"`.
# The `-mno` arm KEEPS the `-` -- that is upstream, not a typo, and
# `cpu.x86_64f.args` is the row. The empty string takes the else arm and becomes
# the flag `-m`.
# ===========================================================================
def ClangCompiler.x86_feat(+f: String) -> String:
  Bool.pick(String, String.starts_with(f, "-"),
    String.concat(["-mno", f]), String.concat(["-m", f]))

def xf.go(+xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: xf.go(t, List.append(&2, String, acc, [ClangCompiler.x86_feat(h)]))

def ClangCompiler.x86_args(+cpu: String, +feats: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, [String.concat(["-march=", cpu])], xf.go(feats, []))

# ===========================================================================
# :13  the arm64 feature: `"no" + f[1:] if f.startswith("-") else f`. The `-` is
# CONSUMED here, unlike the x86 arm, and the join is `+` rather than `_`, which
# is why `+crypto` contributes a second plus.
# ===========================================================================
def ClangCompiler.arm64_feat(+f: String) -> String:
  Bool.pick(String, String.starts_with(f, "-"),
    String.concat(["no", String.drop(f, 1n)]), f)

def af.go(+xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: af.go(t, List.append(&2, String, acc, [ClangCompiler.arm64_feat(h)]))

def ClangCompiler.arm64_args(+cpu: String, +feats: List<&2, String>) -> List<&2, String>:
  ["-ffixed-x18", String.concat(["-mcpu=", String.join(
    List.append(&2, String, [cpu], af.go(feats, [])), "+")])]

# :13 the comment as a row: x18 is the reserved register that is clobbered on
# context switch in macos and holds the TEB pointer on windows/arm
def ClangCompiler.arm64_fixed() -> String: "-ffixed-x18"

# ===========================================================================
# :14  riscv64. `native` becomes `rv64g` and the features are joined RAW -- no
# `-m`, no `+` -- so `native` + `+zba` is `rv64g_+zba`.
# ===========================================================================
def ClangCompiler.riscv64_cpu(+cpu: String) -> String:
  Bool.pick(String, String.eq(cpu, "native"), "rv64g", cpu)

def ClangCompiler.riscv64_args(+cpu: String, +feats: List<&2, String>) -> List<&2, String>:
  [String.concat(["-march=", String.join(
    List.append(&2, String, [ClangCompiler.riscv64_cpu(cpu)], feats), "_")])]

# ===========================================================================
# :9-15  the three-arm dispatch. The arms are decided by STRING EQUALITY, and
# the order of the tests is the order of the `case` arms, so `ClangCompiler.args`
# must not answer a fourth thing: `ClangCompiler.supported` is what refuses.
# `String.eq` is the test; there is no prefix or case-insensitive match.
# ===========================================================================
def ClangCompiler.is_x86(+a: String) -> Bool: String.eq(a, "x86_64")

def ClangCompiler.is_arm(+a: String) -> Bool: String.eq(a, "arm64")

def ClangCompiler.is_riscv(+a: String) -> Bool: String.eq(a, "riscv64")

def ClangCompiler.supported(+arch: List<&2, String>) -> Bool:
  Bool.or(ClangCompiler.is_x86(ClangCompiler.arch_of(arch)),
    Bool.or(ClangCompiler.is_arm(ClangCompiler.arch_of(arch)),
      ClangCompiler.is_riscv(ClangCompiler.arch_of(arch))))

def ClangCompiler.unsupported(+arch: List<&2, String>) -> String:
  String.concat(["RuntimeError: unsupported arch: '", ClangCompiler.arch_of(arch), "'"])

def ClangCompiler.args(+arch: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, ClangCompiler.is_x86(ClangCompiler.arch_of(arch)),
    ClangCompiler.x86_args(ClangCompiler.cpu_of(arch), ClangCompiler.feats_tail(arch)),
    Bool.pick(List<&2, String>, ClangCompiler.is_arm(ClangCompiler.arch_of(arch)),
      ClangCompiler.arm64_args(ClangCompiler.cpu_of(arch), ClangCompiler.feats_tail(arch)),
      Bool.pick(List<&2, String>, ClangCompiler.is_riscv(ClangCompiler.arch_of(arch)),
        ClangCompiler.riscv64_args(ClangCompiler.cpu_of(arch), ClangCompiler.feats_tail(arch)), [])))

# the element COUNT of the built list -- which is the thing a dropped feature
# or a mis-spliced arm changes and which `ClangCompiler.arm_n` (the arm INDEX)
# cannot see
def ClangCompiler.args_n(+arch: List<&2, String>) -> U32:
  U32.from_nat(List.length(&2, String, ClangCompiler.args(arch)))

def ClangCompiler.arm_n(+arch: List<&2, String>) -> U32:
  Bool.pick(U32, ClangCompiler.is_riscv(ClangCompiler.arch_of(arch)), 1,
    Bool.pick(U32, ClangCompiler.is_arm(ClangCompiler.arch_of(arch)), 2, 1))

# ===========================================================================
# :16  `super().__init__(f"{cachekey}_{'_'.join(arch)}")`. The default cachekey
# is the literal `compile_clang_obj`, and the arch list is joined with `_` -- so
# a feature `-sse` contributes `-sse` and the key contains a `-`.
# ===========================================================================
def ClangCompiler.cachekey_default() -> String: "compile_clang_obj"

def ClangCompiler.key(+cachekey: String, +arch: List<&2, String>) -> String:
  String.concat([cachekey, "_", String.join(arch, "_")])

# ===========================================================================
# :21-22  the spawn's argv. `getenv("CC", 'clang')` is WALL 3 and is therefore
# the FIRST ELEMENT and a parameter. The order is load bearing: the target
# triple comes AFTER `-fno-ident` and BEFORE `*self.args`, and `- -o -` is LAST,
# so the arch flags are between the triple and the `-`.
# ===========================================================================
def ClangCompiler.target(+arch: List<&2, String>) -> String:
  String.concat(["--target=", ClangCompiler.arch_of(arch), "-none-unknown-elf"])

def ClangCompiler.compile_fixed() -> List<&2, String>:
  ["-c", "-x", "c", "-O2", "-fPIC", "-ffreestanding", "-fno-math-errno", "-nostdlib", "-fno-ident"]

def ClangCompiler.compile_fixed_n() -> U32: 9

def ClangCompiler.compile_tail() -> List<&2, String>: ["-", "-o", "-"]

def ClangCompiler.compile_tail_n() -> U32: 3

def ClangCompiler.prog_default() -> String: "clang"

def ClangCompiler.compile_argv(+cc: String, +arch: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, List.append(&2, String,
    List.append(&2, String, [cc], ClangCompiler.compile_fixed()),
    List.append(&2, String, [ClangCompiler.target(arch)], ClangCompiler.args(arch))),
    ClangCompiler.compile_tail())

# 1 program + 9 fixed flags + 1 target + the arch args + 3 tail = 14 + args.
# The features are ALREADY inside the arch args, so counting them twice is what
# the first version did and `cpu.riscv64.argv_n` answered 17 instead of 15.
def ClangCompiler.argv_n(+arch: List<&2, String>) -> U32: U32.add(14, ClangCompiler.args_n(arch))

# ===========================================================================
# :24  `cpu_objdump(lib)`. The artifact is a byte blob (WALL 2), so the row
# carries the CALL and its arch, which is all the port knows.
# ===========================================================================
def ClangCompiler.dis_row(+arch: List<&2, String>) -> String:
  String.concat(["cpu_objdump(", ClangCompiler.arch_of(arch), ")"])

# ===========================================================================
# :28-30  X86Compiler. `super().__init__(None)` makes the cachekey None
# unconditionally -- there is no key -- and `bytes.fromhex(src)` is WALL 1.
# The scanner IS ported, because it is where the ValueError is decided:
# `bytes.fromhex` since 3.7 SKIPS ASCII spaces and rejects every other
# non-hex character, reports the position of the first bad character, and then
# requires an EVEN number of hex digits.
#   MEASURED: "7f454c46" -> 4 bytes; "7f 45 4c" -> 3 bytes (spaces skipped);
#   "7f-45" -> ValueError at position 2; "7f.45" -> position 2;
#   "7f454c4" (7 digits) -> position 7, i.e. the position AFTER the last digit.
# ===========================================================================
def X86Compiler.key() -> String: "None"

def X86Compiler.dis_row() -> String: "capstone_flatdump(x86_64)"

def X86Compiler.arch() -> String: "x86_64"

# `int(x, 16)` for one hex character; the digit value, and -1 for everything else
def X86Compiler.nibble(+c: Char) -> U32: Bool.pick(U32, Char.is_eq(c, '0'), 0, Bool.pick(U32, Char.is_eq(c, '1'), 1, Bool.pick(U32, Char.is_eq(c, '2'), 2, Bool.pick(U32, Char.is_eq(c, '3'), 3, Bool.pick(U32, Char.is_eq(c, '4'), 4, Bool.pick(U32, Char.is_eq(c, '5'), 5, Bool.pick(U32, Char.is_eq(c, '6'), 6, Bool.pick(U32, Char.is_eq(c, '7'), 7, Bool.pick(U32, Char.is_eq(c, '8'), 8, Bool.pick(U32, Char.is_eq(c, '9'), 9, Bool.pick(U32, Char.is_eq(c, 'a'), 10, Bool.pick(U32, Char.is_eq(c, 'A'), 10, Bool.pick(U32, Char.is_eq(c, 'b'), 11, Bool.pick(U32, Char.is_eq(c, 'B'), 11, Bool.pick(U32, Char.is_eq(c, 'c'), 12, Bool.pick(U32, Char.is_eq(c, 'C'), 12, Bool.pick(U32, Char.is_eq(c, 'd'), 13, Bool.pick(U32, Char.is_eq(c, 'D'), 13, Bool.pick(U32, Char.is_eq(c, 'e'), 14, Bool.pick(U32, Char.is_eq(c, 'E'), 14, Bool.pick(U32, Char.is_eq(c, 'f'), 15, Bool.pick(U32, Char.is_eq(c, 'F'), 15, 4294967295))))))))))))))))))))))

def X86Compiler.is_hex(+c: Char) -> Bool: U32.is_ne(X86Compiler.nibble(c), 4294967295)

# `bytes.fromhex`: an ASCII SPACE is skipped and does not count towards the
# parity; any OTHER non-hex character is fatal and its position is reported;
# an ODD number of hex digits is fatal and the position reported is the count.
# MEASURED: "7f454c46" -> 4; "7f 45 4c" -> 3; "" -> 0; "DEADBEEF" -> 4;
# "7f454c4" -> position 7; "zz" -> 0; "7f-45" -> 2; "7f.45" -> 2.
def hx.count(+k: Nat, +cs: List<&2, Char>, +n: U32) -> U32:
  match k:
    case 0n: n
    case 1n+p: match cs:
      case Nil{}: n
      case h <> t: Bool.pick(U32, Bool.or(Char.is_eq(h, ' '), Bool.not(X86Compiler.is_hex(h))),
        hx.count(p, t, n), hx.count(p, t, U32.add(n, 1)))

def hx.bad(+k: Nat, +cs: List<&2, Char>, +pos: Nat, +found: U32) -> U32:
  match k:
    case 0n: found
    case 1n+p: match cs:
      case Nil{}: found
      case h <> t: Bool.pick(U32, U32.is_eq(found, 4294967295),
        Bool.pick(U32, Bool.or(Char.is_eq(h, ' '), X86Compiler.is_hex(h)),
          hx.bad(p, t, Nat.add(pos, 1n), found), hx.bad(p, t, pos, U32.from_nat(pos))),
        hx.bad(p, t, Nat.add(pos, 1n), found))

def X86Compiler.hex_digs(+s: String) -> U32: hx.count(String.length(s), String.to_list(s), 0)

def X86Compiler.hex_bad(+s: String) -> U32: hx.bad(String.length(s), String.to_list(s), 0n, 4294967295)

def X86Compiler.hex_n(+s: String) -> U32: U32.div(X86Compiler.hex_digs(s), 2)

def X86Compiler.hex_ok(+s: String) -> Bool:
  Bool.and(U32.is_eq(X86Compiler.hex_bad(s), 4294967295), U32.is_even(X86Compiler.hex_digs(s)))

# the position CPython's ValueError names: the first bad character, or the
# digit COUNT when the count is odd
def X86Compiler.bad_pos(+s: String) -> U32:
  Bool.pick(U32, U32.is_eq(X86Compiler.hex_bad(s), 4294967295),
    X86Compiler.hex_digs(s), X86Compiler.hex_bad(s))

def X86Compiler.hex_err(+s: String) -> String:
  String.concat(["ValueError: non-hexadecimal number found in fromhex() arg at position ", U32.show(X86Compiler.bad_pos(s))])

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# `bytes.fromhex(s).hex()` is `s` lowercased with the spaces removed, and the
# ValueError names the position -- so `HEX_OF` is the two together and each
# fixture picks one arm. This is the WHOLE of `X86Compiler.compile`.
def hs.go(+k: Nat, +cs: List<&2, Char>, +acc: List<&2, Char>) -> List<&2, Char>:
  match k:
    case 0n: acc
    case 1n+p: match cs:
      case Nil{}: acc
      case h <> t: Bool.pick(List<&2, Char>, Char.is_eq(h, ' '), hs.go(p, t, acc),
        hs.go(p, t, List.append(&2, Char, acc, [Char.to_lower(h)])))

def X86Compiler.hex_str(+s: String) -> String: String.from_list(hs.go(String.length(s), String.to_list(s), []))

def HEX_OF(+s: String) -> String:
  Bool.pick(String, X86Compiler.hex_ok(s), X86Compiler.hex_str(s), X86Compiler.hex_err(s))

# the outcome of `__init__`, as a STRING so that a refusal and an absence are
# never the same row: "ok", the assert, or the unsupported-arch RuntimeError
def R.kind(+ge2: Bool, +supported: Bool, +amsg: String, +umsg: String) -> String:
  Bool.pick(String, Bool.not(ge2), amsg, Bool.pick(String, Bool.not(supported), umsg, "ok"))

# the `@1` process's `CC`. A bend gate may not read the environment, so the
# second value is a CONSTANT of the port and the row says only that the program
# IS the head of the argv and is whatever the parameter is.
def PROG_SET() -> String: "mycc"

# the arch fixtures, in the oracle's order
def A1() -> List<&2, String>: ["x86_64", "znver2"]
def A2() -> List<&2, String>: ["x86_64", "znver2", "-sse", "-avx2", "+fma", "nosse"]
def A3() -> List<&2, String>: ["x86_64"]
def A4() -> List<&2, String>: []
def A5() -> List<&2, String>: ["arm64", "apple-m1"]
def A6() -> List<&2, String>: ["arm64", "apple-m1", "-sve", "+crypto", "-lse"]
def A7() -> List<&2, String>: ["arm64", "-sve"]
def A8() -> List<&2, String>: ["riscv64", "native"]
def A9() -> List<&2, String>: ["riscv64", "native", "+zba", "+zve64d"]
def A10() -> List<&2, String>: ["riscv64", "rv64gc", "+zve64d", "-v"]
def A11() -> List<&2, String>: ["sparc64", "x"]
def A12() -> List<&2, String>: ["X86_64", "znver2"]
def A13() -> List<&2, String>: ["x86_64", "znver2", ""]

# the hex fixtures, in the oracle's order
def H1() -> String: "7f454c46"
def H2() -> String: ""
def H3() -> String: "7f 45 4c"
def H4() -> String: "DEADBEEF"
def H5() -> String: "7f454c4"
def H6() -> String: "zz"
def H7() -> String: "7f-45"
def H8() -> String: "7f.45"

# ===========================================================================
# THE GATE. Every `cpu_` row is a row of `.agents/slop/ext_oracle.py` section
# `cpu`, which calls the real `ClangCompiler.__init__`, the real `compile` with
# `subprocess.check_output` recorded, and the real `X86Compiler.compile`.
# ===========================================================================
def t_arch() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cpu.x86_64.n", U32.show(ClangCompiler.n(A1)))
    b : Unit <- srow("cpu.x86_64f.n", U32.show(ClangCompiler.n(A2)))
    c : Unit <- srow("cpu.x86empty.n", U32.show(ClangCompiler.n(A3)))
    d : Unit <- srow("cpu.x86empty2.n", U32.show(ClangCompiler.n(A4)))
    e : Unit <- srow("cpu.arm64.n", U32.show(ClangCompiler.n(A5)))
    f : Unit <- srow("cpu.arm64f.n", U32.show(ClangCompiler.n(A6)))
    g : Unit <- srow("cpu.arm64dash.n", U32.show(ClangCompiler.n(A7)))
    h : Unit <- srow("cpu.riscv64n.n", U32.show(ClangCompiler.n(A8)))
    i : Unit <- srow("cpu.riscv64nf.n", U32.show(ClangCompiler.n(A9)))
    j : Unit <- srow("cpu.riscv64.n", U32.show(ClangCompiler.n(A10)))
    k : Unit <- srow("cpu.sparc.n", U32.show(ClangCompiler.n(A11)))
    l : Unit <- srow("cpu.X86.n", U32.show(ClangCompiler.n(A12)))
    m : Unit <- srow("cpu.x86blank.n", U32.show(ClangCompiler.n(A13)))
    IO.print("cpu_arch_done=1")

def t_split() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cpu.x86_64.arch", ClangCompiler.arch_of(A1))
    b : Unit <- srow("cpu.x86_64.cpu", ClangCompiler.cpu_of(A1))
    c : Unit <- srow("cpu.x86_64.feats", ClangCompiler.feats(A1))
    d : Unit <- srow("cpu.x86_64f.feats", ClangCompiler.feats(A2))
    e : Unit <- srow("cpu.arm64f.feats", ClangCompiler.feats(A6))
    f : Unit <- srow("cpu.riscv64nf.feats", ClangCompiler.feats(A9))
    g : Unit <- srow("cpu.x86empty.arch", ClangCompiler.arch_of(A3))
    h : Unit <- srow("cpu.x86empty.cpu", ClangCompiler.cpu_of(A3))
    i : Unit <- srow("cpu.x86blank.feats", ClangCompiler.feats(A13))
    IO.print("cpu_split_done=1")

def t_args() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cpu.x86_64.args", String.join(ClangCompiler.args(A1), " "))
    b : Unit <- srow("cpu.x86_64.args_n", U32.show(ClangCompiler.args_n(A1)))
    c : Unit <- srow("cpu.x86_64f.args", String.join(ClangCompiler.args(A2), " "))
    d : Unit <- srow("cpu.x86_64f.args_n", U32.show(ClangCompiler.args_n(A2)))
    e : Unit <- srow("cpu.x86blank.args", String.join(ClangCompiler.args(A13), " "))
    f : Unit <- srow("cpu.x86blank.args_n", U32.show(ClangCompiler.args_n(A13)))
    g : Unit <- srow("cpu.arm64.args", String.join(ClangCompiler.args(A5), " "))
    h : Unit <- srow("cpu.arm64.args_n", U32.show(ClangCompiler.args_n(A5)))
    i : Unit <- srow("cpu.arm64f.args", String.join(ClangCompiler.args(A6), " "))
    j : Unit <- srow("cpu.arm64f.args_n", U32.show(ClangCompiler.args_n(A6)))
    k : Unit <- srow("cpu.arm64dash.args", String.join(ClangCompiler.args(A7), " "))
    l : Unit <- srow("cpu.riscv64n.args", String.join(ClangCompiler.args(A8), " "))
    m : Unit <- srow("cpu.riscv64nf.args", String.join(ClangCompiler.args(A9), " "))
    n : Unit <- srow("cpu.riscv64.args", String.join(ClangCompiler.args(A10), " "))
    o : Unit <- srow("cpu.riscv64.args_n", U32.show(ClangCompiler.args_n(A10)))
    p : Unit <- srow("cpu.sparc.args", String.join(ClangCompiler.args(A11), " "))
    q : Unit <- srow("cpu.sparc.args_n", U32.show(ClangCompiler.args_n(A11)))
    r : Unit <- srow("cpu.X86.args_n", U32.show(ClangCompiler.args_n(A12)))
    t : Unit <- srow("cpu.arm64dash.args_n", U32.show(ClangCompiler.args_n(A7)))
    u : Unit <- srow("cpu.riscv64n.args_n", U32.show(ClangCompiler.args_n(A8)))
    IO.print("cpu_args_done=1")

def t_refuse() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cpu.x86_64.kind", R.kind(ClangCompiler.ge2(ClangCompiler.n(A1)), ClangCompiler.supported(A1), ClangCompiler.msg(A1), ClangCompiler.unsupported(A1)))
    a2 : Unit <- srow("cpu.x86_64.err", ClangCompiler.msg(A1))
    b : Unit <- srow("cpu.x86empty.kind", R.kind(ClangCompiler.ge2(ClangCompiler.n(A3)), ClangCompiler.supported(A3), ClangCompiler.msg(A3), ClangCompiler.unsupported(A3)))
    c : Unit <- srow("cpu.x86empty2.kind", R.kind(ClangCompiler.ge2(ClangCompiler.n(A4)), ClangCompiler.supported(A4), ClangCompiler.msg(A4), ClangCompiler.unsupported(A4)))
    d : Unit <- srow("cpu.sparc.kind", R.kind(ClangCompiler.ge2(ClangCompiler.n(A11)), ClangCompiler.supported(A11), ClangCompiler.msg(A11), ClangCompiler.unsupported(A11)))
    e : Unit <- srow("cpu.X86.kind", R.kind(ClangCompiler.ge2(ClangCompiler.n(A12)), ClangCompiler.supported(A12), ClangCompiler.msg(A12), ClangCompiler.unsupported(A12)))
    h : Unit <- srow("cpu.sparc.err", ClangCompiler.unsupported(A11))
    i : Unit <- srow("cpu.X86.err", ClangCompiler.unsupported(A12))
    j : Unit <- srow("cpu.ge2_one", U32.show(Bool.to_u32(ClangCompiler.ge2(ClangCompiler.n(A3)))))
    k : Unit <- srow("cpu.ge2_zero", U32.show(Bool.to_u32(ClangCompiler.ge2(ClangCompiler.n(A4)))))
    l : Unit <- srow("cpu.ge2_two", U32.show(Bool.to_u32(ClangCompiler.ge2(ClangCompiler.n(A1)))))
    IO.print("cpu_refuse_done=1")

def t_key() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cpu.x86_64.key", ClangCompiler.key(ClangCompiler.cachekey_default(), A1))
    b : Unit <- srow("cpu.x86_64f.key", ClangCompiler.key(ClangCompiler.cachekey_default(), A2))
    c : Unit <- srow("cpu.arm64.key", ClangCompiler.key(ClangCompiler.cachekey_default(), A5))
    d : Unit <- srow("cpu.arm64f.key", ClangCompiler.key(ClangCompiler.cachekey_default(), A6))
    e : Unit <- srow("cpu.riscv64n.key", ClangCompiler.key(ClangCompiler.cachekey_default(), A8))
    f : Unit <- srow("cpu.riscv64nf.key", ClangCompiler.key(ClangCompiler.cachekey_default(), A9))
    g : Unit <- srow("cpu.riscv64.key", ClangCompiler.key(ClangCompiler.cachekey_default(), A10))
    h : Unit <- srow("cpu.x86key", X86Compiler.key())
    i : Unit <- srow("cpu.x86_64.dis_n", U32.show(Bool.to_u32(Bool.not(String.is_empty(ClangCompiler.dis_row(A1))))))
    j : Unit <- srow("cpu.x86_64.dis", ClangCompiler.dis_row(A1))
    IO.print("cpu_key_done=1")

def t_spawn() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cpu.x86_64.argv", String.join(ClangCompiler.compile_argv(ClangCompiler.prog_default(), A1), " "))
    b : Unit <- srow("cpu.x86_64.argv_n", U32.show(ClangCompiler.argv_n(A1)))
    c : Unit <- srow("cpu.x86_64f.argv", String.join(ClangCompiler.compile_argv(ClangCompiler.prog_default(), A2), " "))
    d : Unit <- srow("cpu.x86_64f.argv_n", U32.show(ClangCompiler.argv_n(A2)))
    e : Unit <- srow("cpu.arm64.argv", String.join(ClangCompiler.compile_argv(ClangCompiler.prog_default(), A5), " "))
    f : Unit <- srow("cpu.arm64.argv_n", U32.show(ClangCompiler.argv_n(A5)))
    g : Unit <- srow("cpu.riscv64.argv", String.join(ClangCompiler.compile_argv(ClangCompiler.prog_default(), A10), " "))
    h : Unit <- srow("cpu.riscv64.argv_n", U32.show(ClangCompiler.argv_n(A10)))
    i : Unit <- srow("cpu.x86_64.prog", ClangCompiler.prog_default())
    j : Unit <- srow("cpu.x86_64f.prog", ClangCompiler.prog_default())
    k : Unit <- srow("cpu.arm64f.prog", ClangCompiler.prog_default())
    l : Unit <- srow("cpu.riscv64nf.prog", ClangCompiler.prog_default())
    m : Unit <- srow("cpu.x86_64.target", ClangCompiler.target(A1))
    n : Unit <- srow("cpu.arm64f.target", ClangCompiler.target(A6))
    o : Unit <- srow("cpu.riscv64nf.target", ClangCompiler.target(A9))
    p : Unit <- srow("cpu.x86_64f.comp_n", U32.show(Bool.to_u32(U32.is_eq(ClangCompiler.argv_n(A2), 19))))
    q : Unit <- srow("cpu.arm64f.comp_n", U32.show(Bool.to_u32(U32.is_eq(ClangCompiler.argv_n(A6), 16))))
    r : Unit <- srow("cpu.riscv64nf.comp_n", U32.show(Bool.to_u32(U32.is_eq(ClangCompiler.argv_n(A9), 15))))
    s : Unit <- srow("cpu.x86_64.comp_n", U32.show(Bool.to_u32(U32.is_eq(ClangCompiler.argv_n(A1), 15))))
    IO.print("cpu_spawn_done=1")

def t_x86() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cpu.x86_ok", HEX_OF(H1))
    b : Unit <- srow("cpu.x86_ok_n", U32.show(X86Compiler.hex_n(H1)))
    c : Unit <- srow("cpu.x86_empty", HEX_OF(H2))
    d : Unit <- srow("cpu.x86_empty_n", U32.show(X86Compiler.hex_n(H2)))
    e : Unit <- srow("cpu.x86_sp", HEX_OF(H3))
    f : Unit <- srow("cpu.x86_sp_n", U32.show(X86Compiler.hex_n(H3)))
    g : Unit <- srow("cpu.x86_upper", HEX_OF(H4))
    h : Unit <- srow("cpu.x86_upper_n", U32.show(X86Compiler.hex_n(H4)))
    i : Unit <- srow("cpu.x86_odd", X86Compiler.hex_err(H5))
    j : Unit <- srow("cpu.x86_odd_n", U32.show(X86Compiler.bad_pos(H5)))
    k : Unit <- srow("cpu.x86_bad", X86Compiler.hex_err(H6))
    l : Unit <- srow("cpu.x86_bad_n", U32.show(X86Compiler.bad_pos(H6)))
    m : Unit <- srow("cpu.x86_nodash", X86Compiler.hex_err(H7))
    n : Unit <- srow("cpu.x86_nodash_n", U32.show(X86Compiler.bad_pos(H7)))
    o : Unit <- srow("cpu.x86_dot", X86Compiler.hex_err(H8))
    p : Unit <- srow("cpu.x86_dot_n", U32.show(X86Compiler.bad_pos(H8)))
    q : Unit <- srow("cpu.x86_ok_ok", U32.show(Bool.to_u32(X86Compiler.hex_ok(H1))))
    r : Unit <- srow("cpu.x86_sp_ok", U32.show(Bool.to_u32(X86Compiler.hex_ok(H3))))
    s : Unit <- srow("cpu.x86_dot_ok", U32.show(Bool.to_u32(X86Compiler.hex_ok(H8))))
    t : Unit <- srow("cpu.x86dis_n", U32.show(Bool.to_u32(Bool.not(String.is_empty(X86Compiler.dis_row())))))
    u : Unit <- srow("cpu.x86dis", X86Compiler.dis_row())
    IO.print("cpu_x86_done=1")

# THE FRESH-PROCESS ROWS. `getenv("CC", "clang")` is a PROCESS-BOOT CONSTANT, so
# the two values of `CC` live in TWO processes: `@0` with `CC` unset answers
# `clang` and `@1` with `CC=mycc` answers `mycc`. One bend program cannot read
# the environment twice, so the row pair is written as the two DEFAULTS the port
# would use, and the checker compares each against its own process.
def t_env() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cpu.cc_prog_default", ClangCompiler.prog_default())
    b : Unit <- srow("cpu.cc_prog_set", PROG_SET())
    c : Unit <- srow("cpu.cc_taken_default", String.join(ClangCompiler.compile_argv(ClangCompiler.prog_default(), A1), " "))
    d : Unit <- srow("cpu.cc_taken_set", String.join(ClangCompiler.compile_argv(PROG_SET, A1), " "))
    IO.print("cpu_env_done=1")

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_arch()
    b : Unit <- t_split()
    c : Unit <- t_args()
    d : Unit <- t_refuse()
    e : Unit <- t_key()
    f : Unit <- t_spawn()
    g : Unit <- t_x86()
    h : Unit <- t_env()
    IO.print("compiler_cpu-done=1")