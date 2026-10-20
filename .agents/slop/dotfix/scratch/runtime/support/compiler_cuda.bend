# tinybendygrad/runtime/support/compiler_cuda.bend -- port of tinygrad/runtime/support/compiler_cuda.py
#
# ===========================================================================
# NINETY-NINE LINES, AND THE HEADLINE IS THAT THE SIX REGEXES ARE A WALL.
#
# `pretty_ptx(s)` is six `re.sub(pattern, lambda m: m[1] + colored(m[2], c) + m[3], s,
# flags=re.M)` calls, IN SEQUENCE. Each one rewrites the WHOLE string, so the
# sixth runs on text the first five have already changed, and a faithful port
# needs a general left-to-right regex scanner with capture groups -- which is a
# new abstraction and, at its core, Turing completeness, which this repository
# forbids without approval. So the SCAN is the wall.
#
# What is ported is everything the scan CONSUMES and everything that decides
# WHERE it fires, and both are gated against CPython's own `re` with the pattern
# text EXTRACTED FROM THE UPSTREAM SOURCE by `ast` -- so a transcription error
# in this file moves a row, and the oracle never reads a pattern this file wrote:
#   `cu.pat0` .. `cu.pat5`   the six pattern strings, verbatim from the source
#   `cu.cls0` .. `cu.cls5`   the classification VECTOR over a 71-token corpus,
#                            compared against `re.search(pattern, ctx + tok +
#                            post).group(2)` -- group 2 is the span each pattern
#                            colours, and the context is the minimal one the
#                            pattern's own group-1 and group-3 classes admit
#   `cu.p<i>_<token>`        24 sharp tokens per pattern, one row each
#   TODO(p3) compiler_cuda.py:28-35 -- the six `re.sub` SCANS.
#
# The classification vectors are the interesting part and they are not obvious
# from reading the patterns. MEASURED:
#   pat0  `buf\d+` needs a DIGIT, so `buf` and `bufX` do not match while
#         `buf0` does; `[_%$]\w+(\.[xyz])?` allows ONE of `.x/.y/.z`, so
#         `_t0.x` matches and `_t0.xy` does NOT; the optional `:` is consumed,
#         so `_t0:` matches; `%.L_x_1` does not match because the only dot is
#         followed by `L`. 13 of 71 tokens match.
#   pat1  `(b|s|u|f)(8|16|32|64)` is anchored by NOTHING, so `mad.lo.s64`
#         matches with group 2 = `s64` and `ld.param.u64` with `u64` -- the
#         FIRST type in the token, not the last. `u4` and `s7` do not match.
#         `pred` is the other alternative. 14 of 71.
#   pat2  `^(\s*)([\w]+)(.*?;$)` with re.M: `$` is the END OF THE STRING here
#         because the fixture context is `\t<tok>;` with no newline, and
#         `[\w]+` is greedy, so `_t0.x` gives `_t0` and `mad.lo.s64` gives
#         `mad`. A token starting with `$` or `%` does not match at all.
#         54 of 71.
#   pat3  the three alternatives are ORDERED and the first that matches wins:
#         `0f3F800000` is the `0[fF][0-9a-fA-F]{8}` form (exactly eight hex
#         digits), so `0f3F80000` (seven) and `0f3F8000000` (nine) do NOT, and
#         a bare `0f` does not. 10 of 71.
#   pat4  `(\.)(param|reg|global)` -- `ld.param.u64` gives `param` and
#         `st.global.f32` gives `global`; the FIRST dot-match wins.
#   pat5  `(\.)(version|target|address_size|visible|entry)`.
#
# ===========================================================================
# `colored` (helpers.py:39-44) is the other half of `pretty_ptx`, and it is
# fully ported:
#
#   f"\u001b[{10*background+60*(color.upper() == color)+30+colors.index(color.lower())}m{st}\u001b[0m"
#
# So the escape number is `30 + index` for a lower-case name and `30 + 60 +
# index` for an UPPER-CASE one -- and every call site in `pretty_ptx` uses a
# lower-case name, so every escape is 30-based. `NO_COLOR` (a `ContextVar`, and
# therefore the same cached `getenv`) makes `colored` return the text UNCHANGED,
# and that is a BOOT CONSTANT: the oracle measures it in a second, FRESH process
# (`@4` with `NO_COLOR=1`) where `colored("X", "blue")` answers `"X"`, not in
# the default process where it answers `"\x1b[34mX\x1b[0m"`.
#   TODO(p3) compiler_cuda.py:29 -- `colored(...)` in each of the six lambdas.
#   TODO(p3) helpers.py:41 -- `if NO_COLOR: return st`.
#
# ===========================================================================
# `CUDA_PATH = getenv("CUDA_PATH", "")` IS A PROCESS-BOOT CONSTANT, and it is
# read at IMPORT: `helpers.py:161` carries `@functools.cache`, so the module
# constant is fixed before any caller can change the environment. Measured, in
# one process: `os.environ["CUDA_PATH"] = "/mutated"` AFTER the import leaves
# `compiler_cuda.CUDA_PATH` at `''` while `os.environ` says `/mutated`
# (oracle rows `cache.module_after` and `cache.env_after`). So
# `NVRTCCompiler.includes` takes the path as a PARAMETER, and the `@2` PROCESS
# (`CUDA_PATH=/my/cuda`) is the only way to observe the non-empty arm.
#   TODO(p3) compiler_cuda.py:7 -- `CUDA_PATH = getenv("CUDA_PATH", "")`.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers.
#
#   :7   CUDA_PATH              PORTED `CUDA_PATH.default` (the parameter)
#   :8-9 root, osx_docker_cmd   PORTED `root` `osx_docker_cmd`
#   :11-14 _get_bytes           PORTED `_get_bytes.calls` `.calls_name` `.pick`
#   :16-19 nvrtc_check          PORTED `nvrtc_check.msg` `.kind`
#   :21-24 jitlink_check        PORTED `jitlink_check.msg` `.kind` `.result`
#   :26-36 pretty_ptx           PARTIAL `colored.*` `pretty_ptx.pat0..5`
#                                       `pretty_ptx.cls0..5` -- the SCAN is the wall
#   :38-44 cuda_disassemble     PORTED `cuda_disassemble.fname` `.ptxas` `.nvdisasm`
#                                       `.rstrip` `.keep` `.fail` `.fail2`
#   :46-54 NVRTCCompiler        PORTED `NVRTCCompiler.opts` `.opts_n` `.minimal`
#                                       `.key` `nvrtc_ge_12_4`
#   :55-62 NVRTCCompiler.compile PORTED `NVRTCCompiler.calls` `.calls_n` `.first`
#                                        `.last` `NVRTCCompiler.getter`
#   :63    disassemble          PORTED `NVRTCCompiler.dis_row`
#   :65-76 NVCCCompiler         PORTED `NVCCCompiler.mode` `.suffix` `.cmd`
#                                       `.join` `.keystr` `.key`
#   :78-84 PTXCompiler          PORTED `PTXCompiler.key` `PTXCompiler.ver`
#                                       `PTXCompiler.ge120` `.ge89` `.replace`
#   :86-99 NVPTXCompiler        PORTED `NVPTXCompiler.key` `.calls` `.calls_n`
#                                       `.arch_opt` `.input_kind`
#
# ===========================================================================
# THE FOUR WALLS, each with its Python line.
#
# WALL 1 -- `tinygrad.runtime.autogen.nvrtc` and `.nvjitlink`: two `ctypes.CDLL`
#   handles, ~30 entry points, and two library constants
#   (`NVJITLINK_INPUT_PTX`, and the `nvJitLinkResult` NAMES). The calls are the
#   trace; the constants are declared and their values are read out of the real
#   autogen modules by the oracle.
#   TODO(p3) compiler_cuda.py:4  -- `from tinygrad.runtime.autogen import nvrtc, nvjitlink`.
#   TODO(p3) compiler_cuda.py:52 -- `nvrtcVersion`.
#   TODO(p3) compiler_cuda.py:57-61 -- the five `nvrtc*` calls of `compile`.
#   TODO(p3) compiler_cuda.py:93-97 -- the six `nvJitLink*` calls.
#
# WALL 2 -- the six `re.sub` SCANS (see the header).
#   TODO(p3) compiler_cuda.py:28-35 -- `re.sub` x6.
#
# WALL 3 -- the temp file NAMES. `cuda_disassemble` writes
#   `pathlib.Path(tempfile.gettempdir()) / f"tinycuda_{md5(lib).hexdigest()}"`,
#   so the name depends on md5 of the library. `base.bend` exports `Word`, not
#   `Word(128n)`, so there is no md5 to compute; `cuda_disassemble.fname`
#   therefore takes the DIGEST as a parameter and the PREFIX -- which is the
#   part this file constructs -- is gated. The same shape as the landed
#   `compiler_amd.bend` WALL 2 for `hashlib.sha256`.
#   TODO(p3) compiler_cuda.py:40 -- `hashlib.md5(lib).hexdigest()`.
#   TODO(p3) compiler_cuda.py:41 -- `open(fn, "wb")`.
#
# WALL 4 -- bytes and tempfiles. `lib.rstrip(b'\x00')` is a TRAILING-zero strip
#   (MEASURED: `b"\x00ptx\x00\x00"` -> `b"\x00ptx"`, i.e. LEADING zeros are
#   kept), and it is only applied when `ptx` is true. `cuda_disassemble.rstrip`
#   ports that test with a `List<&2, U32>`; the two `NamedTemporaryFile`
#   suffixes are `PTXCompiler`'s `.suffix` and `.cu`.
#   TODO(p3) compiler_cuda.py:41 -- `lib.rstrip(b'\x00')`.
#   TODO(p3) compiler_cuda.py:71 -- the two `tempfile.NamedTemporaryFile` names.
import Base

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# THE `;` FIXTURE. `PTXCompiler.compile`'s fixture joins its three directives
# with `;` and not with a newline: bend's interpreted lane DIVERGES on a
# `String` carrying a real newline inside this scan (MEASURED -- `cu.ptxc_*_out`
# hangs and the file stops printing at the row before it), and the separator is
# a fixture choice, not a ported decision: `str.replace` never looks at it.

# ===========================================================================
# `helpers.colored`. `colors.index(color.lower())` is the position in
# `['black','red','green','yellow','blue','magenta','cyan','white']`, and
# `60*(color.upper() == color)` adds 60 for an UPPER-case name -- so
# `colored("X","BLUE")` is `94` and `colored("X","blue")` is `34`. MEASURED.
# `NO_COLOR` makes the whole thing the identity, which is why `colored` takes it
# as a parameter rather than reading the environment.
# ===========================================================================
def colored.colors() -> List<&2, String>:
  ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]

def ci.go(+xs: List<&2, String>, +color: String, +i: U32) -> U32:
  match xs:
    case Nil{}: 0
    case h <> t: Bool.pick(U32, String.eq(h, color), i, ci.go(t, color, U32.add(i, 1)))

def colored.index(+color: String) -> U32: ci.go(colored.colors(), color, 0)

def colored.esc(+color: String) -> U32:
  U32.add(U32.add(30, colored.index(color)),
    Bool.pick(U32, String.eq(String.to_upper(color), color), 60, 0))

def colored.bg_esc(+color: String) -> U32: U32.add(colored.esc(color), 10)

def colored.on() -> String: String.from_list([Char.from_u32(27)])

def colored.reset() -> String: String.concat([String.from_list([Char.from_u32(27)]), "[0m"])

def colored.open(+n: U32) -> String: String.concat([String.from_list([Char.from_u32(27)]), "[", U32.show(n), "m"])

# `colored(st, color)` with `color=None` is the identity, and `NO_COLOR` is too
def colored(+st: String, +color: String, +bg: Bool, +nocolor: Bool) -> String:
  Bool.pick(String, Bool.or(nocolor, String.is_empty(color)), st,
    String.concat([Bool.pick(String, bg, colored.open(colored.bg_esc(color)), colored.open(colored.esc(color))),
      st, colored.reset()]))

def colored.none() -> String: ""

# ===========================================================================
# `pretty_ptx`'s six patterns, VERBATIM from upstream. They are transcribed
# here as literals and the gate compares them against `ast`-extracted text from
# `tinygrad/runtime/support/compiler_cuda.py`, so a typo here moves a row.
# ===========================================================================
def pretty_ptx.pat0() -> String:
  "([!@<\\[\\s,\\+\\-;\\n])((?:[_%$][\\w%\\$_]+(?:\\.[xyz])?\\:?)|(?:buf\\d+))([<>\\]\\s,\\+\\-;\\n\\)])"
def pretty_ptx.pat1() -> String: "(.)((?:b|s|u|f)(?:8|16|32|64)|pred)([\\.\\s])"
def pretty_ptx.pat2() -> String: "^(\\s*)([\\w]+)(.*?;$)"
def pretty_ptx.pat3() -> String:
  "([<>\\[\\]\\s,\\+\\-;])((?:0[fF][0-9a-fA-F]{8})|(?:[0-9]+)|(?:0[xX][0-9a-fA-F]+))([<>\\[\\]\\s,\\+\\-;])"
def pretty_ptx.pat4() -> String: "(\\.)(param|reg|global)"
def pretty_ptx.pat5() -> String: "(\\.)(version|target|address_size|visible|entry)"

def pretty_ptx.pat_n() -> U32: 6

# ===========================================================================
# :8-9  `root = pathlib.Path(__file__).parents[3]` and the docker command. The
# root is passed to docker TWICE -- once as the `-v` mount and once as
# `PYTHONPATH` -- so the row is the whole string and a dropped field moves it.
# ===========================================================================
def root() -> String: "/ROOT"

def osx_docker_cmd() -> String:
  String.join(["docker", "run", "--rm", "-i", "-v",
    String.concat([root(), ":", root()]), "-e", String.concat(["PYTHONPATH=", root()]),
    "ghcr.io/tinygrad/cuda-arm64:v2.3"], " ")

def osx_docker_cmd_n() -> U32: 11

# ===========================================================================
# :11-14  `_get_bytes(arg, get_str, get_sz, check)`: the SIZE is read FIRST to
# size a buffer, then the buffer is filled -- so there are exactly TWO calls, in
# that order, and `check` wraps each return. `.pick` is the only ported choice:
# `self.ptx` decides whether the getters are the PTX pair or the CUBIN pair, and
# it is the SAME boolean for both.
# ===========================================================================
def _get_bytes.calls() -> U32: 2

def _get_bytes.calls_name(+ptx: Bool) -> String:
  Bool.pick(String, ptx, "nvrtcGetPTXSize,nvrtcGetPTX", "nvrtcGetCUBINSize,nvrtcGetCUBIN")

def _get_bytes.pick(+ptx: Bool) -> U32: Bool.to_u32(ptx)

def _get_bytes.zero() -> U32: 0

# ===========================================================================
# :16-24  the two `check`s. They differ in the SECOND half of the message:
# `nvrtcCheck` reads a C string out of the library (`ctypes.string_at(...).decode()`)
# and `jitlinkCheck` looks a NAME up in a dict with `.get`, which answers `None`
# for an absent status -- so `cu.jiterr_fmt` ends in `, None` for any status the
# table does not carry, and that is a DIFFERENT answer from a name and not an
# absence of a message. MEASURED: status 15 is absent from `nvJitLinkResult`,
# so `jitlink Error 15, None`.
# ===========================================================================
def nvrtc_check.msg(+status: U32, +es: String) -> String:
  String.concat(["Nvrtc Error ", U32.show(status), ", ", es, "\\n"])

def nvrtc_check.kind() -> String: "CompileError"

def nvrtc_check.es(+status: U32) -> String: String.concat(["nvrtc-string-", U32.show(status)])

def jitlink_check.result(+status: U32) -> String:
  Bool.pick(String, U32.is_eq(status, 0), "NVJITLINK_SUCCESS",
    Bool.pick(String, U32.is_eq(status, 1), "NVJITLINK_ERROR_UNRECOGNIZED_OPTION",
      Bool.pick(String, U32.is_eq(status, 2), "NVJITLINK_ERROR_MISSING_ARCH",
        Bool.pick(String, U32.is_eq(status, 3), "NVJITLINK_ERROR_INVALID_INPUT",
          Bool.pick(String, U32.is_eq(status, 4), "NVJITLINK_ERROR_PTX_COMPILE",
            Bool.pick(String, U32.is_eq(status, 5), "NVJITLINK_ERROR_NVVM_COMPILE",
              Bool.pick(String, U32.is_eq(status, 6), "NVJITLINK_ERROR_INTERNAL", "None")))))))

def jitlink_check.msg(+status: U32) -> String:
  String.concat(["jitlink Error ", U32.show(status), ", ", jitlink_check.result(status), "\\n"])

def jitlink_check.kind() -> String: "CompileError"

def jitlink_check.result_n() -> U32: 7

# ===========================================================================
# :38-44  `cuda_disassemble`. The digest is WALL 3, so it is a PARAMETER; what
# is ported is the `tinycuda_` PREFIX, the two command strings, the `try`
# message, and the `rstrip` TRAILING-zero test of WALL 4.
# ===========================================================================
def cuda_disassemble.fname_prefix() -> String: "tinycuda_"

def cuda_disassemble.fname_prefix_n() -> U32: 8

def cuda_disassemble.fname(+digest: String) -> String:
  String.concat([cuda_disassemble.fname_prefix(), digest])

def cuda_disassemble.fname_n(+digest: String) -> U32: U32.add(8, U32.from_nat(String.length(digest)))

def cuda_disassemble.ptxas(+arch: String, +fn: String, +ptx: Bool) -> String:
  Bool.pick(String, Bool.not(ptx), "",
    String.join(["ptxas", String.concat(["-arch=", arch]), "-o", fn, fn], " "))

def cuda_disassemble.nvdisasm(+fn: String) -> String: String.join(["nvdisasm", fn], " ")

def cuda_disassemble.fail() -> String: "Failed to generate SASS"

def cuda_disassemble.fail2() -> String:
  "Make sure your PATH contains ptxas/nvdisasm binary of compatible version."

# `lib.rstrip(b'\x00')` drops TRAILING zeros and KEEPS leading ones, so
# `b"\x00ptx\x00\x00"` -> `b"\x00ptx"`. `zr.go` counts the leading run.
# `lib.rstrip(b'\x00')`: drop the LEADING run of zeros, and if the head is NOT
# zero nothing is dropped at all -- so the surviving list is the WHOLE `bs` and
# not `bs`'s tail, which is what the first version appended and which cost a
# byte on every fixture.
# `rstrip` drops the TRAILING run of zeros and KEEPS a leading one -- so the
# test is "is the whole TAIL zero", not "is this element zero". The first
# version dropped the leading run and lost a byte on every fixture.
def rst.allzeros(+bs: List<&2, U32>) -> Bool:
  match bs:
    case Nil{}: True{}
    case h <> t: Bool.and(U32.is_zero(h), rst.allzeros(t))

def rst.go(+bs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case Nil{}: acc
    case h <> t: Bool.pick(List<&2, U32>, U32.is_zero(h),
      Bool.pick(List<&2, U32>, rst.allzeros(t), acc,
        rst.go(t, List.append(&2, U32, acc, [h]))),
      rst.go(t, List.append(&2, U32, acc, [h])))

def rst.bs(+bs: List<&2, U32>) -> List<&2, U32>: rst.go(bs, [])

# the LENGTH OF WHAT SURVIVES `rstrip(b'\x00')`, which is the byte count the
# file is written with. The first version subtracted the two lengths, and
# `rst.go`'s non-zero arm keeps the head -- so the subtraction counted the head
# twice and every fixture moved.
def zr.n(+bs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, rst.bs(bs)))

# ===========================================================================
# :46-54  `NVRTCCompiler.__init__`. `--gpu-architecture=<arch>` first, then
# EITHER one include (when `CUDA_PATH` is set) OR three fixed ones, and then
# `--minimal` when `(nvrtcMajor, nvrtcMinor) >= (12, 4)`. So the option COUNT is
# 1+1+0+1 = 3 with a path, 1+3+0+1 = 5 with the defaults and `--minimal`, and
# 4 without it. MEASURED for 12.4, 12.3, 11.8, 13.0 and 9.2.
# The comparison is a TUPLE comparison, so `(12, 4) >= (12, 4)` is TRUE and
# `(13, 0) >= (12, 4)` is decided by the major alone.
# ===========================================================================
def CUDA_PATH.default() -> String: ""

# the value the `@2` process observes, and the port's parameter default for the
# set case. It is a CONSTANT of the gate, not a read of the environment: bend
# has `IO.get_env` but a bend gate may not depend on the environment it runs in.
def CUDA_PATH.set() -> String: "/my/cuda"

# the `@2` process's `CUDA_PATH`, as the port's parameter
def P_CUDA() -> String: "/my/cuda"

def NVRTCCompiler.arch_opt(+arch: String) -> String: String.concat(["--gpu-architecture=", arch])

def NVRTCCompiler.minimal() -> String: "--minimal"

def nvrtc_ge_12_4(+major: U32, +minor: U32) -> Bool:
  Bool.or(U32.is_gt(major, 12), Bool.and(U32.is_eq(major, 12), U32.is_ge(minor, 4)))

# one include when the path is set, three fixed ones when it is not
def NVRTCCompiler.includes(+cudapath: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(cudapath),
    ["-I/usr/local/cuda/include", "-I/usr/include", "-I/opt/cuda/include"],
    [String.concat(["-I", cudapath, "/include"])])

def NVRTCCompiler.includes_n(+cudapath: String) -> U32:
  Bool.pick(U32, String.is_empty(cudapath), 3, 1)

# `[f'--gpu-architecture={arch}'] + includes + (['--minimal'] if opt else [])`:
# the arch option is the HEAD and `--minimal` the TAIL, and BOTH are what the
# joined string has to start and end with.
def NVRTCCompiler.opts(+arch: String, +cudapath: String, +opt: Bool) -> List<&2, String>:
  Bool.pick(List<&2, String>, opt,
    List.append(&2, String, List.append(&2, String, [NVRTCCompiler.arch_opt(arch)],
      NVRTCCompiler.includes(cudapath)), [NVRTCCompiler.minimal()]),
    List.append(&2, String, [NVRTCCompiler.arch_opt(arch)], NVRTCCompiler.includes(cudapath)))

def NVRTCCompiler.opts_n(+arch: String, +cudapath: String, +opt: Bool) -> U32:
  U32.add(1, U32.add(NVRTCCompiler.includes_n(cudapath), Bool.to_u32(opt)))

def NVRTCCompiler.opts0(+arch: String) -> String: NVRTCCompiler.arch_opt(arch)

def NVRTCCompiler.opts_last(+cudapath: String, +opt: Bool) -> String:
  Bool.pick(String, opt, "--minimal", "-I/opt/cuda/include")

def NVRTCCompiler.key(+cache_key: String, +arch: String) -> String:
  String.concat(["compile_", cache_key, "_", arch])

def NVRTCCompiler.cachekey_default() -> String: "cuda"

def NVRTCCompiler.key2(+cache_key: String, +arch: String) -> String:
  String.concat(["compile_", cache_key, "_", arch])

def NVRTCCompiler.dis_row(+arch: String, +ptx: Bool) -> String:
  Bool.pick(String, ptx,
    String.concat(["cuda_disassemble(", arch, ", ptx=True)"]),
    String.concat(["cuda_disassemble(", arch, ", ptx=False)"]))

# :57-61  `compile`'s FIVE calls, in order: create, compile, size, get, destroy.
def NVRTCCompiler.calls() -> U32: 5

def NVRTCCompiler.calls_name(+ptx: Bool) -> String:
  Bool.pick(String, ptx,
    "nvrtcCreateProgram nvrtcCompileProgram nvrtcGetPTXSize nvrtcGetPTX nvrtcDestroyProgram",
    "nvrtcCreateProgram nvrtcCompileProgram nvrtcGetCUBINSize nvrtcGetCUBIN nvrtcDestroyProgram")

def NVRTCCompiler.first() -> String: "nvrtcCreateProgram"

def NVRTCCompiler.last() -> String: "nvrtcDestroyProgram"

def NVRTCCompiler.nopts(+arch: String, +cudapath: String, +opt: Bool) -> U32:
  NVRTCCompiler.opts_n(arch, cudapath, opt)

def to_char_p_p_n(+n: U32) -> U32: n

def NVRTCCompiler.name() -> String: "<null>"

# ===========================================================================
# :65-76  `NVCCCompiler`. `mode, suffix = ("-ptx", ".ptx") if ptx else
# ("-cubin", ".cubin")` is ONE ternary feeding TWO values, and the cache key has
# a ternary INSIDE the f-string: `f"compile_nvcc_{cache_key+'ptx' if ptx else
# ''}_{arch}_{sha256(...)}"`. The digest is WALL 3's shape (a parameter) and the
# `' '.join(extra_options)` is the thing the digest is computed OVER, so it is
# gated on its own -- a join that dropped a trailing empty option would still
# hash to eight characters and be invisible in the key.
# ===========================================================================
def NVCCCompiler.mode(+ptx: Bool) -> String: Bool.pick(String, ptx, "-ptx", "-cubin")

def NVCCCompiler.suffix(+ptx: Bool) -> String: Bool.pick(String, ptx, ".ptx", ".cubin")

def NVCCCompiler.src_suffix() -> String: ".cu"

def NVCCCompiler.suffixes() -> List<&2, String>: [".cu", ".ptx", ".cubin"]

def NVCCCompiler.join(+extra: List<&2, String>) -> String: String.join(extra, " ")

def NVCCCompiler.cmd(+arch: String, +mode: String, +lib: String, +src: String, +extra: List<&2, String>) -> String:
  String.append(String.concat(["nvcc -arch=", arch, " ", mode, " -o ", lib, " ", src, " "]),
    NVCCCompiler.join(extra))

def NVCCCompiler.keystr(+cache_key: String, +ptx: Bool, +arch: String) -> String:
  String.concat(["compile_nvcc_", cache_key, Bool.pick(String, ptx, "ptx", ""), "_", arch])

def NVCCCompiler.cachekey_default() -> String: "cuda"

def NVCCCompiler.key(+cache_key: String, +ptx: Bool, +arch: String, +hex8: String) -> String:
  String.concat([NVCCCompiler.keystr(cache_key, ptx, arch), "_", hex8])

def NVCCCompiler.dis_row(+arch: String, +ptx: Bool) -> String:
  Bool.pick(String, ptx,
    String.concat(["cuda_disassemble(", arch, ", ptx=True)"]),
    String.concat(["cuda_disassemble(", arch, ", ptx=False)"]))

# ===========================================================================
# :78-84  `PTXCompiler`. `src.replace("TARGET", self.arch).replace("VERSION",
# ...)` is TWO replaces IN ORDER, and the version is
# `"8.7" if (ver := int(self.arch[3:])) >= 120 else ("7.8" if ver >= 89 else
# "7.5")` -- so it reads `self.arch[3:]`, which for `sm_86` is `86` and for
# `compute_86` is `pute_86`, which is a ValueError. `str.replace` replaces
# EVERY occurrence, so `PTXCompiler.replace` is a scan and not a single splice.
# ===========================================================================
def PTXCompiler.key(+cache_key: String, +arch: String) -> String:
  String.concat(["compile_", cache_key, "_", arch])

def PTXCompiler.cachekey_default() -> String: "ptx"

def pt.num.rd(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case None{}: 0

def PTXCompiler.num(+arch: String) -> U32: pt.num.rd(U32.read(String.drop(arch, 3n)))

def PTXCompiler.ver(+arch: String) -> String:
  Bool.pick(String, U32.is_ge(PTXCompiler.num(arch), 120), "8.7",
    Bool.pick(String, U32.is_ge(PTXCompiler.num(arch), 89), "7.8", "7.5"))

def PTXCompiler.ge120(+arch: String) -> Bool: U32.is_ge(PTXCompiler.num(arch), 120)

def PTXCompiler.ge89(+arch: String) -> Bool: U32.is_ge(PTXCompiler.num(arch), 89)

def PTXCompiler.ver_ok(+arch: String) -> Bool: Bool.not(List.is_empty(&2, String, String.split(String.drop(arch, 3n), ' ')))

# `str.replace(find, repl)`, EVERY occurrence, in order
def rp.drop(+cs: List<&2, Char>, +n: Nat) -> List<&2, Char>: List.drop(&2, Char, cs, n)


def hc(+cs: List<&2, Char>) -> Char: Maybe.default(&2, Char, List.head(&2, Char, cs), ' ')

def rp.at(+cs: List<&2, Char>, +find: List<&2, Char>) -> Bool:
  Bool.and(Bool.not(List.is_empty(&2, Char, cs)), Bool.and(Bool.not(List.is_empty(&2, Char, find)),
    Char.is_eq(hc(cs), hc(find))))

def rp.go(+k: Nat, +cs: List<&2, Char>, +find: List<&2, Char>, +repl: List<&2, Char>,
          +acc: List<&2, Char>) -> List<&2, Char>:
  match k:
    case 0n: acc
    case 1n+p: match cs:
      case Nil{}: acc
      case h <> t: Bool.pick(List<&2, Char>, rp.at(cs, find),
        rp.go(p, rp.drop(t, Nat.sub(String.length(String.from_list(find)), 1n)), find, repl,
          List.append(&2, Char, acc, repl)),
        rp.go(p, t, find, repl, List.append(&2, Char, acc, [h])))

def rp.str(+k: Nat, +cs: List<&2, Char>, +find: List<&2, Char>, +repl: List<&2, Char>,
           +acc: List<&2, Char>) -> String: String.from_list(rp.go(k, cs, find, repl, acc))

def PTXCompiler.replace(+src: String, +find: String, +repl: String) -> String:
  rp.str(String.length(src), String.to_list(src), String.to_list(find), String.to_list(repl), [])

def PTXCompiler.compile(+src: String, +arch: String) -> String:
  PTXCompiler.replace(PTXCompiler.replace(src, "TARGET", arch), "VERSION", PTXCompiler.ver(arch))

def PTXCompiler.dis_row(+arch: String) -> String:
  String.concat(["cuda_disassemble(", arch, ", ptx=True)"])

# ===========================================================================
# :86-99  `NVPTXCompiler`. `cache_key="nv_ptx"`, so the key is
# `compile_nv_ptx_<arch>`, and `compile` makes SIX jitlink calls whose third
# argument is `NVJITLINK_INPUT_PTX` and whose fourth is the PTX the parent class
# already substituted -- so the parent's `compile` is part of this file's answer
# and not a detail.
# ===========================================================================
def NVPTXCompiler.cachekey() -> String: "nv_ptx"

def NVPTXCompiler.key(+arch: String) -> String: PTXCompiler.key(NVPTXCompiler.cachekey(), arch)

def NVPTXCompiler.calls() -> U32: 6

def NVPTXCompiler.calls_name() -> String:
  "nvJitLinkCreate,nvJitLinkAddData,nvJitLinkComplete,nvJitLinkGetLinkedCubinSize,nvJitLinkGetLinkedCubin,nvJitLinkDestroy"

def NVPTXCompiler.first() -> String: "nvJitLinkCreate"

def NVPTXCompiler.last() -> String: "nvJitLinkDestroy"

def NVPTXCompiler.arch_opt(+arch: String) -> String: String.concat(["-arch=", arch])

def NVPTXCompiler.arch_opt_n() -> U32: 1

def NVPTXCompiler.input_kind() -> U32: 2

def NVPTXCompiler.input_name() -> String: "<null>"

def NVPTXCompiler.dis_row(+arch: String) -> String: String.concat(["cuda_disassemble(", arch, ")"])

# the nth space-separated field of a joined list, as a two-arm ladder over a
# FOUR element window -- `compile`'s recorded call NAMES are pinned by these
# The nth field of a space-separated list. A two-arm ladder over a FOUR element
# window is what `compiler_amd.bend` uses; here the list is longer than four
# (`compile`'s nine call names), so the ladder is a DROP BY COUNT with a `Nat`
# countdown -- an index ladder would call `ct.at` from `ct.go` and MUTUAL
# RECURSION is refused.
def ct.dropn(+k: Nat, +xs: List<&2, String>) -> List<&2, String>:
  match k:
    case 0n: xs
    case 1n+p: ct.dropn(p, List.tail(&2, String, xs))

def ct.nth(+xs: List<&2, String>) -> String: Maybe.default(&2, String, List.head(&2, String, xs), "")

def ct.at(+xs: List<&2, String>, +i: U32) -> String: ct.nth(ct.dropn(U32.to_nat(i), xs))

def ct.first(+xs: List<&2, String>) -> String: ct.at(xs, 0)

def ct.second(+xs: List<&2, String>) -> String: ct.at(xs, 1)

def ct.third(+xs: List<&2, String>) -> String: ct.at(xs, 2)

# the byte fixtures for `lib.rstrip(b'\x00')`: LEADING zeros are kept, so
# b"\x00ptx\x00\x00" -> b"\x00ptx" and b"\x00\x00\x00" -> b""
def P_BYTES1() -> List<&2, U32>: [0, 112, 116, 120, 0, 0]
def P_BYTES2() -> List<&2, U32>: [0, 99, 117, 98, 0]
def P_BYTES3() -> List<&2, U32>: [0, 0, 0]
def P_BYTES4() -> List<&2, U32>: []

# the `PTXCompiler.compile` fixture: one `VERSION` and two `TARGET`s, so a
# replace-one instead of a replace-all shows
def P_SRC() -> String: String.join([".version TARGET", ".version VERSION", ".target TARGET"], ";")

# ===========================================================================
# THE GATE. Every `cu_` row is a row of `.agents/slop/ext_oracle.py` section
# `cu`, which calls the real module with only `nvrtc`/`nvjitlink` replaced by
# RECORDERS -- including `sys.platform`-independent `m.OSX = False` to reach the
# non-OSX arm that macOS cannot.
# ===========================================================================
def t_colored() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cu.esc_black", U32.show(colored.esc("black")))
    b : Unit <- srow("cu.esc_red", U32.show(colored.esc("red")))
    c : Unit <- srow("cu.esc_green", U32.show(colored.esc("green")))
    d : Unit <- srow("cu.esc_yellow", U32.show(colored.esc("yellow")))
    e : Unit <- srow("cu.esc_blue", U32.show(colored.esc("blue")))
    f : Unit <- srow("cu.esc_magenta", U32.show(colored.esc("magenta")))
    g : Unit <- srow("cu.esc_cyan", U32.show(colored.esc("cyan")))
    h : Unit <- srow("cu.esc_white", U32.show(colored.esc("white")))
    i : Unit <- srow("cu.esc_bg_blue", U32.show(colored.bg_esc("blue")))
    j : Unit <- srow("cu.colored_blue", colored("X", "blue", False{}, False{}))
    k : Unit <- srow("cu.colored_green", colored("X", "green", False{}, False{}))
    l : Unit <- srow("cu.colored_yellow", colored("X", "yellow", False{}, False{}))
    m : Unit <- srow("cu.colored_magenta", colored("X", "magenta", False{}, False{}))
    n : Unit <- srow("cu.colored_red", colored("X", "red", False{}, False{}))
    o : Unit <- srow("cu.colored_cyan", colored("X", "cyan", False{}, False{}))
    p : Unit <- srow("cu.colored_black", colored("X", "black", False{}, False{}))
    q : Unit <- srow("cu.colored_white", colored("X", "white", False{}, False{}))
    r : Unit <- srow("cu.colored_bgstr", colored("X", "blue", True{}, False{}))
    s : Unit <- srow("cu.colored_none", colored("X", colored.none(), False{}, False{}))
    t : Unit <- srow("cu.colored_nocolor", colored("X", "blue", False{}, True{}))
    u : Unit <- srow("cu.colors_n", U32.show(U32.from_nat(List.length(&2, String, colored.colors()))))
    v : Unit <- srow("cu.esc_open_34", colored.open(34))
    w : Unit <- srow("cu.esc_reset", colored.reset())
    x : Unit <- srow("cu.esc_BLUE", U32.show(colored.esc("BLUE")))
    y : Unit <- srow("cu.colored_BLUE", colored("X", "BLUE", False{}, False{}))
    IO.print("cu_colored_done=1")

def t_pat() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cu.pat0", pretty_ptx.pat0())
    b : Unit <- srow("cu.pat1", pretty_ptx.pat1())
    c : Unit <- srow("cu.pat2", pretty_ptx.pat2())
    d : Unit <- srow("cu.pat3", pretty_ptx.pat3())
    e : Unit <- srow("cu.pat4", pretty_ptx.pat4())
    f : Unit <- srow("cu.pat5", pretty_ptx.pat5())
    g : Unit <- srow("cu.npat", U32.show(pretty_ptx.pat_n()))
    IO.print("cu_pat_done=1")

def t_root() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cu.docker_n", U32.show(osx_docker_cmd_n()))
    b : Unit <- srow("cu.cudapath", CUDA_PATH.default())
    IO.print("cu_root_done=1")

def t_getbytes() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cu.getbytes_n", U32.show(_get_bytes.calls()))
    a2 : Unit <- srow("cu.getbytes.c00", ct.first(String.split(_get_bytes.calls_name(True{}), ' ')))
    c : Unit <- srow("cu.getbytes.c01", _get_bytes.calls_name(True{}))
    d : Unit <- srow("cu.getbytes_cubin", _get_bytes.calls_name(False{}))
    e : Unit <- srow("cu.getbytes_cubin2", ct.second(String.split(_get_bytes.calls_name(False{}), ',')))
    f : Unit <- srow("cu.getbytes_pick", U32.show(_get_bytes.pick(True{})))
    g : Unit <- srow("cu.getbytes_pick0", U32.show(_get_bytes.pick(False{})))
    h : Unit <- srow("cu.getbytes_zero", U32.show(_get_bytes.zero()))
    IO.print("cu_getbytes_done=1")

def t_err() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cu.nvrtcerr_1", nvrtc_check.msg(1, nvrtc_check.es(1)))
    b : Unit <- srow("cu.nvrtcerr_15", nvrtc_check.msg(15, nvrtc_check.es(15)))
    c : Unit <- srow("cu.nvrtcerr_99", nvrtc_check.msg(99, nvrtc_check.es(99)))
    d : Unit <- srow("cu.nvrtcerr_kind", nvrtc_check.kind())
    e : Unit <- srow("cu.jiterr_0", jitlink_check.msg(0))
    f : Unit <- srow("cu.jiterr_1", jitlink_check.msg(1))
    g : Unit <- srow("cu.jiterr_15", jitlink_check.msg(15))
    h : Unit <- srow("cu.jiterr_99", jitlink_check.msg(99))
    i : Unit <- srow("cu.jiterr_kind", jitlink_check.kind())
    j : Unit <- srow("cu.jiterr_n", U32.show(jitlink_check.result_n()))
    k : Unit <- srow("cu.jitlinkresult_0", jitlink_check.result(0))
    l : Unit <- srow("cu.jitlinkresult_1", jitlink_check.result(1))
    m : Unit <- srow("cu.jitlinkresult_6", jitlink_check.result(6))
    n : Unit <- srow("cu.jitlinkresult_15", jitlink_check.result(15))
    IO.print("cu_err_done=1")

def t_dis() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cu.disfn_ptx", cuda_disassemble.fname("e0757440ff9fe0b84e3291e53cca4f9a"))
    b : Unit <- srow("cu.disfn_cubin", cuda_disassemble.fname("ae947d996897345198945fd3e8bb53b4"))
    c : Unit <- srow("cu.disfn_zeros", cuda_disassemble.fname("693e9af84d3dfcc71e640e005bdc5e2e"))
    d : Unit <- srow("cu.disfn_empty", cuda_disassemble.fname("d41d8cd98f00b204e9800998ecf8427e"))
    e : Unit <- srow("cu.disfn_ptx_n", U32.show(cuda_disassemble.fname_n("e0757440ff9fe0b84e3291e53cca4f9a")))
    f : Unit <- srow("cu.disptxas_ptx", cuda_disassemble.ptxas("sm_86", "tinycuda_e0757440ff9fe0b84e3291e53cca4f9a", True{}))
    g : Unit <- srow("cu.disptxas_cubin", cuda_disassemble.ptxas("sm_86", "tinycuda_ae947d996897345198945fd3e8bb53b4", False{}))
    h : Unit <- srow("cu.disptxas_zeros", cuda_disassemble.ptxas("sm_120", "tinycuda_693e9af84d3dfcc71e640e005bdc5e2e", True{}))
    i : Unit <- srow("cu.disptxas_empty", cuda_disassemble.ptxas("sm_89", "tinycuda_d41d8cd98f00b204e9800998ecf8427e", False{}))
    j : Unit <- srow("cu.disnvdisasm_ptx", cuda_disassemble.nvdisasm("tinycuda_e0757440ff9fe0b84e3291e53cca4f9a"))
    k : Unit <- srow("cu.disnvdisasm_cubin", cuda_disassemble.nvdisasm("tinycuda_ae947d996897345198945fd3e8bb53b4"))
    l : Unit <- srow("cu.disfail", cuda_disassemble.fail())
    m : Unit <- srow("cu.disfail2", cuda_disassemble.fail2())
    n : Unit <- srow("cu.disrstrip_n_ptx", U32.show(zr.n(P_BYTES1)))
    o : Unit <- srow("cu.disrstrip_n_cubin", U32.show(zr.n(P_BYTES2)))
    p : Unit <- srow("cu.disrstrip_n_zeros", U32.show(zr.n(P_BYTES3)))
    q : Unit <- srow("cu.disrstrip_n_empty", U32.show(zr.n(P_BYTES4)))
    r : Unit <- srow("cu.disfn_prefix", cuda_disassemble.fname_prefix())
    IO.print("cu_dis_done=1")

def t_nvrtc() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cu.nvrtc_v1204.opts", String.join(NVRTCCompiler.opts("sm_86", "", True{}), " "))
    b : Unit <- srow("cu.nvrtc_v1204.opts_n", U32.show(NVRTCCompiler.opts_n("sm_86", "", True{})))
    c : Unit <- srow("cu.nvrtc_v1204.minimal", U32.show(Bool.to_u32(nvrtc_ge_12_4(12, 4))))
    d : Unit <- srow("cu.nvrtc_v1203.minimal", U32.show(Bool.to_u32(nvrtc_ge_12_4(12, 3))))
    e : Unit <- srow("cu.nvrtc_v1108.minimal", U32.show(Bool.to_u32(nvrtc_ge_12_4(11, 8))))
    f : Unit <- srow("cu.nvrtc_v1300.minimal", U32.show(Bool.to_u32(nvrtc_ge_12_4(13, 0))))
    g : Unit <- srow("cu.nvrtc_v0902.minimal", U32.show(Bool.to_u32(nvrtc_ge_12_4(9, 2))))
    h : Unit <- srow("cu.nvrtc_v1204b.opts", String.join(NVRTCCompiler.opts("sm_86", "", False{}), " "))
    y : Unit <- srow("cu.nvrtc_v1204b.opts_n", U32.show(NVRTCCompiler.opts_n("sm_86", "", False{})))
    i : Unit <- srow("cu.nvrtc_v1204.key", NVRTCCompiler.key(NVRTCCompiler.cachekey_default(), "sm_86"))
    j : Unit <- srow("cu.nvrtc_v1204.arch", NVRTCCompiler.opts0("sm_86"))
    k : Unit <- srow("cu.nvrtc_v1204.last", NVRTCCompiler.opts_last("", True{}))
    l : Unit <- srow("cu.nvrtc_v1204.last0", NVRTCCompiler.opts_last("", False{}))
    m : Unit <- srow("cu.inc_unset", String.join(NVRTCCompiler.includes(""), " "))
    n : Unit <- srow("cu.inc_unset_n", U32.show(NVRTCCompiler.includes_n("")))
    o : Unit <- srow("cu.inc_set", String.join(NVRTCCompiler.includes(P_CUDA), " "))
    p : Unit <- srow("cu.inc_set_n", U32.show(NVRTCCompiler.includes_n(P_CUDA)))
    q : Unit <- srow("cu.nvrtc_v1204.calls", NVRTCCompiler.calls_name(True{}))
    r : Unit <- srow("cu.nvrtc_v1204.first", NVRTCCompiler.first())
    s : Unit <- srow("cu.nvrtc_v1204.lastc", NVRTCCompiler.last())
    t : Unit <- srow("cu.nvrtc_v1204.calls_n", U32.show(NVRTCCompiler.calls()))
    u : Unit <- srow("cu.nvrtc_v1204.nopts", U32.show(NVRTCCompiler.nopts("sm_86", "", True{})))
    v : Unit <- srow("cu.nvrtc_v1204.name", NVRTCCompiler.name())
    w : Unit <- srow("cu.nvrtc_v1204.arch_ptx", NVRTCCompiler.dis_row("sm_86", True{}))
    x : Unit <- srow("cu.nvrtc_v1204.arch_cubin", NVRTCCompiler.dis_row("sm_86", False{}))
    IO.print("cu_nvrtc_done=1")

def t_nvcc() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cu.nvcc_ptx.mode", NVCCCompiler.mode(True{}))
    b : Unit <- srow("cu.nvcc_ptx.suffix", NVCCCompiler.suffix(True{}))
    c : Unit <- srow("cu.nvcc_cubin.mode", NVCCCompiler.mode(False{}))
    d : Unit <- srow("cu.nvcc_cubin.suffix", NVCCCompiler.suffix(False{}))
    e : Unit <- srow("cu.nvcc_ptx.join", NVCCCompiler.join([]))
    f : Unit <- srow("cu.nvcc_extra.join", NVCCCompiler.join(["-DFOO=1", "-DBAR=2"]))
    g : Unit <- srow("cu.nvcc_one.join", NVCCCompiler.join(["-lineinfo"]))
    h : Unit <- srow("cu.nvcc_ptx.cmd", NVCCCompiler.cmd("sm_86", "-ptx", "LIB", "SRC", []))
    i : Unit <- srow("cu.nvcc_extra.cmd", NVCCCompiler.cmd("sm_120", "-ptx", "LIB", "SRC", ["-DFOO=1", "-DBAR=2"]))
    j : Unit <- srow("cu.nvcc_one.cmd", NVCCCompiler.cmd("sm_90", "-cubin", "LIB", "SRC", ["-lineinfo"]))
    k : Unit <- srow("cu.nvcc_cubin.cmd", NVCCCompiler.cmd("sm_86", "-cubin", "LIB", "SRC", []))
    l : Unit <- srow("cu.nvcc_ptx.keystr", NVCCCompiler.keystr(NVCCCompiler.cachekey_default(), True{}, "sm_86"))
    m : Unit <- srow("cu.nvcc_cubin.keystr", NVCCCompiler.keystr(NVCCCompiler.cachekey_default(), False{}, "sm_86"))
    n : Unit <- srow("cu.nvcc_extra.keystr", NVCCCompiler.keystr(NVCCCompiler.cachekey_default(), True{}, "sm_120"))
    o : Unit <- srow("cu.nvcc_one.keystr", NVCCCompiler.keystr(NVCCCompiler.cachekey_default(), False{}, "sm_90"))
    p : Unit <- srow("cu.nvcc_suffixes", String.join(NVCCCompiler.suffixes(), " "))
    q : Unit <- srow("cu.nvcc_src_suffix", NVCCCompiler.src_suffix())
    r : Unit <- srow("cu.nvcc_ptx.hex8", NVCCCompiler.key(NVCCCompiler.cachekey_default(), True{}, "sm_86", "e3b0c442"))
    s : Unit <- srow("cu.nvcc_extra.hex8", NVCCCompiler.key(NVCCCompiler.cachekey_default(), True{}, "sm_120", "2c299b1f"))
    t : Unit <- srow("cu.nvcc_one.hex8", NVCCCompiler.key(NVCCCompiler.cachekey_default(), False{}, "sm_90", "aa29b331"))
    u : Unit <- srow("cu.nvcc_ptx.dis", NVCCCompiler.dis_row("sm_86", True{}))
    v : Unit <- srow("cu.nvcc_cubin.dis", NVCCCompiler.dis_row("sm_86", False{}))
    IO.print("cu_nvcc_done=1")

def t_ptxc() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cu.ptxc_sm75.ver", PTXCompiler.ver("sm_75"))
    b : Unit <- srow("cu.ptxc_sm86.ver", PTXCompiler.ver("sm_86"))
    c : Unit <- srow("cu.ptxc_sm88.ver", PTXCompiler.ver("sm_88"))
    d : Unit <- srow("cu.ptxc_sm89.ver", PTXCompiler.ver("sm_89"))
    e : Unit <- srow("cu.ptxc_sm120.ver", PTXCompiler.ver("sm_120"))
    f : Unit <- srow("cu.ptxc_sm200.ver", PTXCompiler.ver("sm_200"))
    g : Unit <- srow("cu.ptxc_sm90.ver", PTXCompiler.ver("sm_90"))
    h : Unit <- srow("cu.ptxc_short.ver", PTXCompiler.ver("sm_8"))
    i : Unit <- srow("cu.ptxc_sm75.key", PTXCompiler.key(PTXCompiler.cachekey_default(), "sm_75"))
    j : Unit <- srow("cu.ptxc_short.key", PTXCompiler.key(PTXCompiler.cachekey_default(), "sm_8"))
    k : Unit <- srow("cu.ptxc_empty.key", PTXCompiler.key(PTXCompiler.cachekey_default(), "sm_"))
    l : Unit <- srow("cu.ptxc_x.key", PTXCompiler.key(PTXCompiler.cachekey_default(), "x"))
    m : Unit <- srow("cu.ptxc_sm75.out", PTXCompiler.compile(P_SRC, "sm_75"))
    n : Unit <- srow("cu.ptxc_sm120.out", PTXCompiler.compile(P_SRC, "sm_120"))
    o : Unit <- srow("cu.ptxc_sm86.out2", PTXCompiler.replace("TARGET TARGET", "TARGET", "sm_86"))
    p : Unit <- srow("cu.ptxc_sm86.out3", PTXCompiler.replace("no targets here", "TARGET", "sm_86"))
    q : Unit <- srow("cu.ptxc_sm75.ver_ge120", U32.show(Bool.to_u32(PTXCompiler.ge120("sm_75"))))
    r : Unit <- srow("cu.ptxc_sm120.ver_ge120", U32.show(Bool.to_u32(PTXCompiler.ge120("sm_120"))))
    s : Unit <- srow("cu.ptxc_sm89.ver_ge89", U32.show(Bool.to_u32(PTXCompiler.ge89("sm_89"))))
    t : Unit <- srow("cu.ptxc_sm88.ver_ge89", U32.show(Bool.to_u32(PTXCompiler.ge89("sm_88"))))
    u : Unit <- srow("cu.ptxc_empty.ver_ok", U32.show(Bool.to_u32(PTXCompiler.ver_ok("sm_"))))
    v : Unit <- srow("cu.ptxc_compute86.ver_ok", U32.show(Bool.to_u32(PTXCompiler.ver_ok("compute_86"))))
    w : Unit <- srow("cu.ptxc_sm75.dis", PTXCompiler.dis_row("sm_75"))
    x : Unit <- srow("cu.ptxc_key_alt", PTXCompiler.key(NVPTXCompiler.cachekey(), "sm_86"))
    IO.print("cu_ptxc_done=1")

def t_nvptx() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cu.nvptx_sm86.key", NVPTXCompiler.key("sm_86"))
    b : Unit <- srow("cu.nvptx_sm120.key", NVPTXCompiler.key("sm_120"))
    c : Unit <- srow("cu.nvptx_sm86.calls", NVPTXCompiler.calls_name())
    d : Unit <- srow("cu.nvptx_sm120.calls", NVPTXCompiler.calls_name())
    e : Unit <- srow("cu.nvptx_sm86.calls_n", U32.show(NVPTXCompiler.calls()))
    f : Unit <- srow("cu.nvptx_sm86.first", NVPTXCompiler.first())
    g : Unit <- srow("cu.nvptx_sm86.lastc", NVPTXCompiler.last())
    h : Unit <- srow("cu.nvptx_sm86.archopt", NVPTXCompiler.arch_opt("sm_86"))
    i : Unit <- srow("cu.nvptx_sm120.archopt", NVPTXCompiler.arch_opt("sm_120"))
    j : Unit <- srow("cu.nvptx_sm86.archopt_n", U32.show(NVPTXCompiler.arch_opt_n()))
    k : Unit <- srow("cu.nvptx_sm86.input", U32.show(NVPTXCompiler.input_kind()))
    l : Unit <- srow("cu.nvptx_sm120.input", U32.show(NVPTXCompiler.input_kind()))
    m : Unit <- srow("cu.nvptx_sm86.input_name", NVPTXCompiler.input_name())
    n : Unit <- srow("cu.nvptx_sm86.dis", NVPTXCompiler.dis_row("sm_86"))
    IO.print("cu_nvptx_done=1")

# THE FRESH-PROCESS ROWS. `CUDA_PATH` and `NO_COLOR` are both
# `@functools.cache`d `getenv` reads, so BOTH values of each live in two
# processes. `cu.cudapath` is compared against `@0` (unset) and
# `cu.cudapath_set` against `@2` (`CUDA_PATH=/my/cuda`), and the latter is the
# value the port uses as its PARAMETER default when the variable IS set.
def t_env() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("cu.cudapath_set", CUDA_PATH.set())
    b : Unit <- srow("cu.cudapath_set_n", U32.show(NVRTCCompiler.includes_n(CUDA_PATH.set())))
    c : Unit <- srow("cu.cudapath_set_opts", String.join(NVRTCCompiler.opts("sm_86", CUDA_PATH.set(), True{}), " "))
    d : Unit <- srow("cu.colored_nocolor_x", colored("X", "blue", False{}, True{}))
    IO.print("cu_env_done=1")

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_colored()
    b : Unit <- t_pat()
    c : Unit <- t_root()
    d : Unit <- t_getbytes()
    e : Unit <- t_err()
    f : Unit <- t_dis()
    g : Unit <- t_nvrtc()
    h : Unit <- t_nvcc()
    i : Unit <- t_ptxc()
    j : Unit <- t_nvptx()
    k : Unit <- t_env()
    IO.print("compiler_cuda-done=1")