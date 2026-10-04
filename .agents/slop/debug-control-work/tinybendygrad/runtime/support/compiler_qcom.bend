# tinybendygrad/runtime/support/compiler_qcom.bend -- port of tinygrad/runtime/support/compiler_qcom.py
#
# ===========================================================================
# THE PURE LOGIC OF THIS FILE IS ONE LINE, and it is the sharpest one in the
# unit:
#
#   def disassemble(self, lib):
#     disas_adreno(lib[(ofs := _read_lib(lib, 0xc0)):ofs + _read_lib(lib, 0x100)], self.chip_id)
#
# The offset is not a constant and not a field: it is read OUT OF THE BUFFER
# being sliced, at a FIXED position, and the slice runs from there for a LENGTH
# that is also read out of the buffer at a different fixed position. So the
# slice is `lib[ofs : ofs + n2]` with BOTH ends data-dependent, and the two
# reads are little-endian 32-bit reads at 0xc0 and 0x100.
#
# `_read_lib` is `struct.unpack("I", lib[off:off+4])[0]` (:8) and the LITTLE
# ENDIAN is the load-bearing fact: the same four bytes read big-endian answer a
# different library slice, and nothing downstream would notice. bend has no
# byte buffer, so `q.read` takes the four bytes as four `U32`s in ADDRESS order
# and the row that pins the order is `q.read_le_*` against CPython's
# `struct.pack("I", ...)`.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers.
#
#   :8   _read_lib               PORTED  `q.read` `q.read_le` `q.read_be`
#   :12  the a630 assert         PORTED  `q.arch_ok`
#   :13  chip_id = 0x6030001     PORTED  `q.chip_id` (0x6030001 = 100859905,
#                                        which fits a `U32` exactly)
#   :16  the cache key           PORTED  `q.key`
#   :17  the rootfs fetch        PARTIAL `q.root` -- the URL and the repo root;
#                                         `fetch(..., extract=True)` is WALL 1
#   :18  the qemu command        PORTED  `q.cmd_qemu`
#   :19-20 the docker command    PORTED  `q.cmd_docker` -- the whole four-line
#                                         f-string, with the `-v` mounts and the
#                                         two `-e` variables
#   :21  the platform gate       PORTED  `q.is_aarch64`
#   :27-32 checked()             PORTED  `q.msg` `q.msg_with` `q.picks_exe` --
#                                         the handle-type test and the two
#                                         arms of the build log
#   :36  the nine-argument call  PORTED  `q.compile_args` -- chip, mode, and the
#                                         source-kind constant, IN ORDER
#   :39  the link call           PORTED  `q.link_args` -- and note the last
#                                         argument is the compile handle, not
#                                         NULL as in :36
#   :46  the disassemble slice   PORTED  `q.slice_off` `q.slice_end` -- THE
#                                         HEADLINE
#
# ===========================================================================
# THE THREE WALLS, each with its Python line.
#
# WALL 1 -- `tinygrad.runtime.autogen.llvm_qcom` and the fetched rootfs.
#   `cl_compiler_*` is a shared library, and `fetch(...)` is a download plus a
#   tarball extract. `IO.get_env` exists (base.bend:172) so the ENVIRONMENT is
#   reachable; the library and the tarball are not.
#   TODO(p3) compiler_qcom.py:6  -- `from tinygrad.runtime.autogen import llvm_qcom`.
#   TODO(p3) compiler_qcom.py:17 -- `fetch('https://git.tinygrad.win/...')`.
#   TODO(p3) compiler_qcom.py:18 -- `shutil.which("qemu-aarch64-static")` when the
#                                    PATH is the system's, not a parameter.
#   TODO(p3) compiler_qcom.py:36-41 -- the five `cl_compiler_*` calls.
#   TODO(p3) compiler_qcom.py:42 -- `ctypes.string_at(ptr, sz.value)`.
#
# WALL 2 -- the two persistent-pipe paths. `self.server(...)` is
#   `subprocess.Popen(argv.split() + [...], stdout=PIPE, stdin=PIPE, bufsize=0)`
#   (device.py:352) and `compile_server` writes a length-prefixed frame and
#   reads one back on the SAME long-lived pipe. `Process.run` spawns and
#   collects; it cannot hold a duplex pipe open. **This is the one seam in the
#   whole unit that `Process.run` does NOT close**, and it is why
#   `compileserver.py` gets its own file.
#   TODO(p3) device.py:352 -- `subprocess.Popen(..., stdout=PIPE, stdin=PIPE)`.
#   TODO(p3) device.py:353-356 -- `compile_server`'s write/read/read.
#   TODO(p3) compiler_qcom.py:35 -- `self.compile_server(src, self.compiler_process)`.
#
# WALL 3 -- bytes. `lib[off:off+4]` is a four-byte slice; bend has no byte
#   buffer, so `q.read` takes the bytes as parameters. That is the only reason
#   this file's one pure function is not a one-liner, and it is the honest
#   shape: the LITTLE-ENDIAN combination is this file's logic and the buffer is
#   the parameter.
#   TODO(p3) compiler_qcom.py:8  -- `lib[off:off+4]`.
#   TODO(p3) compiler_qcom.py:46 -- `lib[ofs:ofs + n2]`.
import Base

type Tr is Data:
  Tr{items: List<&2, String>}

def Tr.of() -> Tr: Tr{[]}

def Tr.items(tr: Tr) -> List<&2, String>:
  match tr:
    case Tr{items}: items

def Tr.put(nm: String, arg: String, tr: Tr) -> Tr:
  Tr{List.append(&2, String, Tr.items(tr), [String.concat([nm, "(", arg, ")"])] )}

def Tr.n(tr: Tr) -> U32: U32.from_nat(List.length(&2, String, Tr.items(tr)))

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# ===========================================================================
# :8  _read_lib. `struct.unpack("I", lib[off:off+4])[0]` is LITTLE ENDIAN:
# byte 0 is the LOW byte. `q.read` takes the four bytes in ADDRESS order, which
# is what makes the endianness a decision rather than a convention.
#
# The boundary matters and is a real error case: `struct.unpack` raises when the
# slice is shorter than four bytes, so `_read_lib(lib, 0x100)` on a 0x100-byte
# library raises rather than returning a truncated read. `q.read_ok` is that
# test, and `q.read` is only reached when it holds.
# ===========================================================================
def q.read_ok(+len: U32, +off: U32) -> Bool: U32.is_ge(U32.sub(len, off), 4)

def q.read(+b0: U32, +b1: U32, +b2: U32, +b3: U32) -> U32:
  U32.or(U32.or(b0, U32.shln(b1, 8n)), U32.or(U32.shln(b2, 16n), U32.shln(b3, 24n)))

def q.read_be(+b0: U32, +b1: U32, +b2: U32, +b3: U32) -> U32:
  U32.or(U32.or(U32.shln(b0, 24n), U32.shln(b1, 16n)), U32.or(U32.shln(b2, 8n), b3))

def q.byte_at(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case None{}: 0

def q.byte(+bs: List<&2, U32>, +i: U32) -> U32: q.byte_at(List.get(&2, U32, bs, U32.to_nat(i)))

def q.read_at(+bs: List<&2, U32>, +off: U32) -> U32:
  q.read(q.byte(bs, off), q.byte(bs, U32.add(off, 1)),
    q.byte(bs, U32.add(off, 2)), q.byte(bs, U32.add(off, 3)))

# the two positions `disassemble` reads
def q.off_pos() -> U32: 192         # 0xc0
def q.len_pos() -> U32: 256         # 0x100

# ===========================================================================
# :46  THE SLICE. `lib[ofs : ofs + _read_lib(lib, 0x100)]`, where `ofs` is read
# at 0xc0. Both ends are data, and the two reads are at DIFFERENT positions, so
# a port that used 0xc0 for both would produce a slice of the right length in
# the wrong place whenever the library disagrees with itself.
# ===========================================================================
def q.slice_off(+n: U32, +bs: List<&2, U32>) -> U32: q.read_at(bs, q.off_pos())

def q.slice_end(+n: U32, +bs: List<&2, U32>) -> U32:
  U32.add(q.read_at(bs, q.off_pos()), q.read_at(bs, q.len_pos()))

def q.slice_len(+n: U32, +bs: List<&2, U32>) -> U32: q.read_at(bs, q.len_pos())

def q.slice_str(+n: U32, +bs: List<&2, U32>) -> String:
  String.concat([U32.show(q.read_at(bs, q.off_pos())), ":", U32.show(q.slice_end(n, bs))])

# ===========================================================================
# :12  the arch assert and :13/:16 the chip id and the cache key.
# ===========================================================================
def q.head.of(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case h <> t: h

def q.arch_ok(+arch: String) -> Bool: String.eq(q.head.of(String.split(arch, ',')), "a630")

def q.chip_id() -> U32: 100859905        # 0x6030001

def q.mode() -> U32: 64                  # CL_MODE_64BIT

def q.src_str() -> U32: 1                # CL_SRC_STR

# the argument lists as a string, so a reordered argument is a DIFF and not a
# count. There is no `U32.show` over a list in base.bend (MEASURED), so this is
# the list walk, and it walks the TAIL so the decrease check is satisfied.
def q.join_u.of(rest: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rest:
    case Nil{}: acc
    case h <> t: q.join_u.of(t, List.append(&2, String, acc, [U32.show(h)]))

def q.join_u(+xs: List<&2, U32>) -> String: String.join(q.join_u.of(xs, []), ",")

def q.key(+arch: String) -> String: String.concat(["compile_qcomcl_", arch])

def q.is_aarch64(+machine: String) -> Bool: String.eq(machine, "aarch64")

# ===========================================================================
# :17  the rootfs and the repo root. `rootlib.Path(__file__).parents[3]` is the
# repository root, which is where `compileserver.py` and `tinygrad` live, and it
# is passed to docker twice: once as a `-v` mount and once as `PYTHONPATH`.
# ===========================================================================
def q.root() -> String: "/ROOT"

def q.fs_url() -> String: "https://git.tinygrad.win/tinygrad/images/releases/download/v2/qcomcl.tar.gz"

# ===========================================================================
# :18  THE QEMU COMMAND, and it is one string that a shell will word-split, so
# the SPACES are load bearing:
#
#   f"{qemu} -cpu max,pauth=off -L {fs} {fs}/usr/bin/python3"
#
# `qemu` is `shutil.which("qemu-aarch64-static")` or None, and the whole branch
# is chosen by its presence -- not by the platform. So there are THREE states,
# not two: aarch64 (no process at all), qemu (a local emulator) and docker.
# ===========================================================================
def q.cmd_qemu(+qemu: String, +fs: String) -> String:
  String.join([qemu, "-cpu", "max,pauth=off", "-L", fs, String.concat([fs, "/usr/bin/python3"])], " ")

def q.qemu_n(+qemu: String, +fs: String) -> U32: 6

# ===========================================================================
# :19-20  THE DOCKER COMMAND. Four pieces of information, and all four are
# observable: the `--platform`, BOTH `-v` mounts, `PYTHONPATH` and `QEMU_CPU`.
# Dropping the second mount mounts nothing and `-e PYTHONPATH` then names a
# directory that is not in the image.
# ===========================================================================
def q.cmd_docker(+fs: String, +root: String) -> String:
  String.join(["docker", "run", "--rm", "-i", "--platform", "linux/aarch64",
    "-v", String.concat([fs, "/usr:/usr"]),
    "-v", String.concat([root, ":", root]),
    "-e", String.concat(["PYTHONPATH=", root]),
    "-e", "QEMU_CPU=max,pauth=off", "gcr.io/distroless/static", "python3"], " ")

def q.docker_n() -> U32: 16

def q.docker_flags(+fs: String, +root: String) -> List<&2, String>:
  ["docker", "run", "--rm", "-i", "--platform", "linux/aarch64",
   "-v", String.concat([fs, "/usr:/usr"]),
   "-v", String.concat([root, ":", root]),
   "-e", String.concat(["PYTHONPATH=", root]),
   "-e", "QEMU_CPU=max,pauth=off", "gcr.io/distroless/static", "python3"]

# ===========================================================================
# :27-32  checked(). Two facts, and the second is not a reformat of the first:
#
#   if not handle or (data := (hc.executable if hc.type == CL_HANDLE_LINKED
#                              else hc.compiled).contents).error_code != 0:
#     <destroy and recreate the llvm instance>
#     raise RuntimeError("QCOM Compilation Error" +
#                        ("" if not handle else f": {data.build_log}"))
#
# So a NULL handle gets the bare message and a handle with a non-zero error code
# gets the message AND the build log, and in BOTH cases the instance is
# recreated first. `q.picks_exe` is the handle-TYPE test and it is a different
# question from the error code.
# ===========================================================================
def q.handle_linked() -> U32: 2          # CL_HANDLE_LINKED

def q.picks_exe(+htype: U32) -> Bool: U32.is_eq(htype, q.handle_linked())

def q.fails(+handle: Bool, +error_code: U32) -> Bool:
  Bool.or(Bool.not(handle), U32.is_ne(error_code, 0))

def q.msg(+handle: Bool, +build_log: String) -> String:
  Bool.pick(String, Bool.not(handle), "QCOM Compilation Error",
    String.concat(["QCOM Compilation Error: ", build_log]))

def q.resets(+fails: Bool) -> U32: Bool.to_u32(fails)

def q.is_compile(handle: Bool, log: String) -> String: q.msg(handle, log)

# ===========================================================================
# :36  `cl_compiler_compile_source(inst, chip_id, CL_MODE_64BIT, b"", 0, 0, 0,
#      src.encode(), 0, CL_SRC_STR, None)` -- ELEVEN arguments, and the two
# consecutive ZEROS at positions 5 and 6 are separate arguments, not one.
# ===========================================================================
def q.compile_args(+chip_id: U32, +src: String) -> List<&2, U32>:
  [chip_id, 64, 0, 0, 0, 0, q.src_str(), 0]

def q.compile_arg_n() -> U32: 11

# :39 `cl_compiler_link_program(inst, chip_id, CL_MODE_64BIT, None, 1, ch)`
# FIVE arguments plus the handle, and the handle is the LAST one -- not NULL as
# in the compile call. Six arguments total.
def q.link_args(+chip_id: U32) -> List<&2, U32>: [chip_id, 64, 1]

def q.link_arg_n() -> U32: 6

# :40 `cl_compiler_handle_create_binary(lh, byref(ptr), byref(sz))`
def q.binary_args() -> U32: 3

# ===========================================================================
# THE GATE.
# ===========================================================================
# a 0x110-byte library with a chosen u32 at 0xc0 and another at 0x100, built as
# a LIST of byte values in ADDRESS order -- which is what makes `q.read`'s
# endianness a decision the gate can see.
# a run of `n` bytes starting at `v`, so a fixture library is a byte ADDRESS
# list and the endianness of `q.read` is a decision the gate can see
def BS.go(k: Nat, +b: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n: acc
    case 1n+p: BS.go(p, U32.add(b, 1), List.append(&2, U32, acc, [b]))

def BS.of(v: U32, k: Nat) -> List<&2, U32>: BS.go(k, v, [])

def b4(+v: U32) -> List<&2, U32>:
  [U32.and(v, 255), U32.and(U32.shrn(v, 8n), 255),
   U32.and(U32.shrn(v, 16n), 255), U32.shrn(v, 24n)]

def t_read() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("q.read_le_1", U32.show(q.read(1, 0, 0, 0)))
    b : Unit <- srow("q.read_be_1", U32.show(q.read_be(1, 0, 0, 0)))
    c : Unit <- srow("q.read_le_ff", U32.show(q.read(255, 255, 255, 255)))
    d : Unit <- srow("q.read_le_0100", U32.show(q.read(0, 1, 0, 0)))
    e : Unit <- srow("q.read_le_0001", U32.show(q.read(0, 0, 1, 0)))
    f : Unit <- srow("q.read_le_0010", U32.show(q.read(0, 0, 16, 0)))
    g : Unit <- srow("q.read_le_1234", U32.show(q.read(120, 86, 52, 18)))
    h : Unit <- srow("q.read_be_1234", U32.show(q.read_be(120, 86, 52, 18)))
    v : Unit <- srow("q.read_le_chip", U32.show(q.read(1, 0, 48, 96)))
    w : Unit <- srow("q.read_ok_0_0", U32.show(Bool.to_u32(q.read_ok(0, 0))))
    x : Unit <- srow("q.read_ok_3_0", U32.show(Bool.to_u32(q.read_ok(3, 0))))
    y : Unit <- srow("q.read_ok_4_0", U32.show(Bool.to_u32(q.read_ok(4, 0))))
    z : Unit <- srow("q.read_ok_256_256", U32.show(Bool.to_u32(q.read_ok(256, 256))))
    IO.print("qcom_read_done=1")

# the four libraries: (offset at 0xc0, length at 0x100)
# a library big enough to be read at 0xc0 and at 0x100: 192 bytes, the offset
# word, 60 bytes, the length word. The two words are 192 and 256 apart and the
# padding is what makes them so -- which is the whole point of the fixture,
# because a port that read BOTH at 0xc0 would still get four bytes.
def lib(+ofs: U32, +n2: U32) -> List<&2, U32>:
  List.append(&2, U32, BS.of(0, U32.to_nat(q.off_pos())), List.append(&2, U32, List.append(&2, U32, b4(ofs), BS.of(0, 60n)), b4(n2)))

def SL0() -> List<&2, U32>: lib(0, 0)
def SL1() -> List<&2, U32>: lib(4, 7)
def SL2() -> List<&2, U32>: lib(4, 0)
def SL3() -> List<&2, U32>: lib(8, 32)

def t_slice() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("q.pos_off", U32.show(q.off_pos()))
    b : Unit <- srow("q.pos_len", U32.show(q.len_pos()))
    c : Unit <- srow("q.slice_str_0_0", q.slice_str(0, SL0()))
    d : Unit <- srow("q.slice_str_4_7", q.slice_str(0, SL1()))
    e : Unit <- srow("q.slice_str_4_0", q.slice_str(0, SL2()))
    f : Unit <- srow("q.slice_str_8_32", q.slice_str(0, SL3()))
    g : Unit <- srow("q.slice_len_4_7", U32.show(q.slice_len(0, SL1())))
    h : Unit <- srow("q.slice_end_4_7", U32.show(q.slice_end(0, SL1())))
    i : Unit <- srow("q.slice_len_0_0", U32.show(q.slice_len(0, SL0())))
    j : Unit <- srow("q.slice_end_0_0", U32.show(q.slice_end(0, SL0())))
    IO.print("qcom_slice_done=1")

def t_init() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("q.arch_ok_a630", U32.show(Bool.to_u32(q.arch_ok("a630"))))
    b : Unit <- srow("q.arch_ok_a630_x", U32.show(Bool.to_u32(q.arch_ok("a630,x"))))
    c : Unit <- srow("q.arch_ok_a630_c", U32.show(Bool.to_u32(q.arch_ok("a630,"))))
    d : Unit <- srow("q.arch_ok_a640", U32.show(Bool.to_u32(q.arch_ok("a640"))))
    e : Unit <- srow("q.arch_ok_EMPTY", U32.show(Bool.to_u32(q.arch_ok(""))))
    f : Unit <- srow("q.arch_ok_A630", U32.show(Bool.to_u32(q.arch_ok("A630"))))
    g : Unit <- srow("q.arch_ok_a63", U32.show(Bool.to_u32(q.arch_ok("a63"))))
    h : Unit <- srow("q.key_a630", q.key("a630"))
    i : Unit <- srow("q.key_a630_x", q.key("a630,x"))
    j : Unit <- srow("q.chip_id", U32.show(q.chip_id()))
    k : Unit <- srow("q.mode", U32.show(q.mode()))
    l : Unit <- srow("q.src_str", U32.show(q.src_str()))
    m : Unit <- srow("q.is_aarch64_1", U32.show(Bool.to_u32(q.is_aarch64("aarch64"))))
    n : Unit <- srow("q.is_aarch64_0", U32.show(Bool.to_u32(q.is_aarch64("x86_64"))))
    o : Unit <- srow("q.root", q.root())
    IO.print("qcom_init_done=1")

def t_cmd() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("q.cmd_qemu", q.cmd_qemu("/usr/bin/qemu-aarch64-static", "/F"))
    b : Unit <- srow("q.qemu_n", U32.show(q.qemu_n("/usr/bin/qemu-aarch64-static", "/F")))
    c : Unit <- srow("q.cmd_docker", q.cmd_docker("/F", "/R"))
    d : Unit <- srow("q.docker_n", U32.show(q.docker_n()))
    e : Unit <- srow("q.cmd_qemu_2", q.cmd_qemu("/q/qemu-aarch64-static", "/rootfs"))
    f : Unit <- srow("q.cmd_docker_2", q.cmd_docker("/rootfs", "/work"))
    g : Unit <- srow("q.docker_flags_n", Nat.show(List.length(&2, String, q.docker_flags("/F", "/R"))))
    h : Unit <- srow("q.fs_url", q.fs_url())
    IO.print("qcom_cmd_done=1")

def t_checked() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("q.fails_null", U32.show(Bool.to_u32(q.fails(False{}, 0))))
    b : Unit <- srow("q.fails_zero", U32.show(Bool.to_u32(q.fails(True{}, 0))))
    c : Unit <- srow("q.fails_err", U32.show(Bool.to_u32(q.fails(True{}, 1))))
    d : Unit <- srow("q.fails_null_err", U32.show(Bool.to_u32(q.fails(False{}, 7))))
    e : Unit <- srow("q.msg_null", q.msg(False{}, "LOG"))
    f : Unit <- srow("q.msg_nolog", q.msg(True{}, ""))
    g : Unit <- srow("q.msg_err", q.msg(True{}, "log-line"))
    h : Unit <- srow("q.resets_null", U32.show(q.resets(q.fails(False{}, 0))))
    i : Unit <- srow("q.resets_ok", U32.show(q.resets(q.fails(True{}, 0))))
    j : Unit <- srow("q.picks_exe_2", U32.show(Bool.to_u32(q.picks_exe(2))))
    k : Unit <- srow("q.picks_exe_1", U32.show(Bool.to_u32(q.picks_exe(1))))
    l : Unit <- srow("q.handle_linked", U32.show(q.handle_linked()))
    IO.print("qcom_checked_done=1")

def t_args() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("q.compile_arg_n", U32.show(q.compile_arg_n()))
    b : Unit <- srow("q.link_arg_n", U32.show(q.link_arg_n()))
    c : Unit <- srow("q.binary_args", U32.show(q.binary_args()))
    d : Unit <- srow("q.compile_args_str", q.join_u(q.compile_args(q.chip_id(), "SRC")))
    e : Unit <- srow("q.link_args_str", q.join_u(q.link_args(q.chip_id())))
    f : Unit <- srow("q.compile_args_n", Nat.show(List.length(&2, U32, q.compile_args(q.chip_id(), "SRC"))))
    g : Unit <- srow("q.link_args_n", Nat.show(List.length(&2, U32, q.link_args(q.chip_id()))))
    IO.print("qcom_args_done=1")

# the trace: the ORDER of the calls, with the platform branch
def Tr.first_of(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case h <> t: h

def Tr.last_of(m: Maybe<&2, String>) -> String:
  match m:
    case Some{v}: v
    case None{}: ""

def Tr.last_name(tr: Tr) -> String: Tr.last_of(List.last(&2, String, Tr.items(tr)))

def ia(t: Tr) -> Tr:
  s0 = Tr.put("cl_compiler_create_llvm_instance", "", t)
  s1 = Tr.put("cl_compiler_compile_source", "chip,CL_MODE_64BIT,src,CL_SRC_STR", s0)
  s2 = Tr.put("cl_compiler_link_program", "chip,CL_MODE_64BIT,1,ch", s1)
  s3 = Tr.put("cl_compiler_handle_create_binary", "lh,ptr,sz", s2)
  s4 = Tr.put("cl_compiler_free_handle", "ch", s3)
  s5 = Tr.put("cl_compiler_free_handle", "lh", s4)
  s6 = Tr.put("cl_compiler_free_assembly", "ptr", s5)
  Tr.put("cl_compiler_destroy_llvm_instance", "inst", s6)

def sr(t: Tr) -> Tr:
  s0 = Tr.put("stdin.write", "pack(I,len(src))+src", t)
  s1 = Tr.put("stdout.read", "4", s0)
  s2 = Tr.put("stdout.read", "unpack(I,n)", s1)
  Tr.put("compile", "src", s2)

def t_trace() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("tr.aarch64.n", U32.show(Tr.n(ia(Tr.of()))))
    b : Unit <- srow("tr.server.n", U32.show(Tr.n(sr(Tr.of()))))
    c : Unit <- srow("tr.aarch64.first", Tr.first_of(Tr.items(ia(Tr.of()))))
    d : Unit <- srow("tr.aarch64.last", Tr.last_name(ia(Tr.of())))
    e : Unit <- srow("tr.server.first", Tr.first_of(Tr.items(sr(Tr.of()))))
    f : Unit <- srow("tr.server.last", Tr.last_name(sr(Tr.of())))
    IO.print("qcom_trace_done=1")

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_read()
    b : Unit <- t_slice()
    c : Unit <- t_init()
    d : Unit <- t_cmd()
    e : Unit <- t_checked()
    f : Unit <- t_args()
    g : Unit <- t_trace()
    IO.print("compiler_qcom-done=1")
