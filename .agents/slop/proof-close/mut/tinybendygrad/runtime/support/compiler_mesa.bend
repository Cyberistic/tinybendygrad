# tinybendygrad/runtime/support/compiler_mesa.bend -- port of tinygrad/runtime/support/compiler_mesa.py
#
# ===========================================================================
# THE SCOPE NOTE FOR THIS UNIT SAID `compiler_mesa.py` "invokes external cc for
# Mesa/software". THAT IS NOT WHAT THE FILE DOES, and the difference matters,
# so it is stated first and MEASURED rather than argued.
#
# Of compiler_mesa.py's 133 lines, ONE shells out: `NAKCompiler.disassemble`'s
# `system(f"nvdisasm -b SM{self.arch[3:]} {fn}")` (:79). Everything else is
# `ctypes` into Mesa's LLVMpipe / NAK / Freedreno libraries -- `rzalloc`,
# `deserialize`, `LVPCompiler`, `NAKCompiler.compile`, `disas_adreno`,
# `IR3Compiler` -- and none of that is reachable from bend for the reason the
# same note gives and that part is CORRECT: there is no importable runtime
# module, so `tinygrad.runtime.autogen.mesa` cannot be opened.
#
# So the shape of this file is the OTHER shape from compiler_amd.bend: there is
# ONE external command and a great deal of pure logic around it, and the pure
# logic is where the gate lives. The ONE command ports onto `base.bend`'s
# `Process.run` (see compiler_amd.bend's header for the nine-row measurement of
# that seam) -- and `helpers.system` is `subprocess.check_output(cmd.split(),
# stderr=STDOUT)`, i.e. an ARGV list and not a shell, so the port is 1:1.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers.
#
#   :9-12  rzalloc                 PARTIAL `ra.*` -- `sizeof` is autogen and the
#                                         kwargs are a ctypes `setattr` by name;
#                                         the ONE thing here that is this file's
#                                         own logic is the size arithmetic
#   :14-17 deserialize             PORTED  `de.*` -- base64 length + the
#                                         blob-reader length, which is what
#                                         `blob_reader_init` is handed
#   :20    LVPCompiler.__init__    PORTED  `lvp.archs` -- `arch.split(",")`
#   :27-28 lp_type's four flags    PORTED  `lpt.*` -- floating/sign/width/length
#   :35    LP_JIT_RES_CONSTANTS    PORTED  `lpt.res` (autogen value, declared)
#   :51    cpu_objdump             PORTED  `dso.cmd` -- the argv `objdump -d <p>`
#   :56    warps_per_sm            PORTED  `w.*` -- THE TABLE. Five arch strings
#                                         answer 48 and EVERY other string
#                                         answers 64, including `sm_86x` and
#                                         `"SM_86"`, which is why the membership
#                                         test cannot be a prefix test
#   :58    int(arch[3:])           PORTED  `a3.*` -- the digits after `sm_`
#   :61    the NAK cache key       PORTED  `nak.key`
#   :75-80 NAKCompiler.disassemble PORTED  `nv.*` -- the temp path and the
#                                         `nvdisasm -b SM<n> <path>` command
#   :82-94 disas_adreno            PORTED  `da.*` -- `data64`, the `%04d [%08x_
#                                         %08x] ` line format, the decode-option
#                                         field ORDER and its four values
#   :98    the a630 assert         PORTED  `ir3.arch_ok`
#   :99    the dev id              PORTED  `ir3.gpu_id` `ir3.chip_id`
#   :101   disable_cache=True      PORTED  `ir3.disable_cache`
#   :104   the IR3 cache key       PORTED  `ir3.key`
#   :119   the uav count           PORTED  `ir3.num_uavs` -- `num_ssbos + num_images`
#   :118   the three-field store   PORTED  `ir3.variant_fields`
#   :123   the four-way concat     PORTED  `ir3.ret_parts` -- four LENGTHS, and
#                                         the fourth is `info.size`
#   :127-131 unpack_lib            PORTED  `ul.*` -- THE HEADLINE. Two successive
#                                         `sizeof` offsets and then a split at
#                                         `count * 4`
#   :133   the disassemble call    PORTED  `ir3.dis_row`
#
# ===========================================================================
# THE FOUR WALLS, each with its Python line.
#
# WALL 1 -- Mesa's ctypes surface. `mesa.*`, `llvm.*` and `libc.*` are a
#   generated binding to a library bend cannot open, and the generated structs
#   are WORSE than opaque: MEASURED on this host, EVERY field of every real
#   `struct_*` in `autogen/mesa.py` is a single `_mem_` blob, so even
#   `info.num_ssbos`, `v.imm_state.count` and `dev_id.gpu_id` -- names the
#   PYTHON itself reads at :119, :131 and :133 -- are not attributes of the
#   autogen type. Those three are therefore autogen walls and are declared as
#   parameters, which is the honest shape.
#   TODO(p3) compiler_mesa.py:1-5  -- the autogen imports.
#   TODO(p3) compiler_mesa.py:10   -- `mesa.rzalloc_size`.
#   TODO(p3) compiler_mesa.py:16-17 -- `blob_reader_init` + `nir_deserialize`.
#   TODO(p3) compiler_mesa.py:23-42 -- the sixteen LVP gallivm calls.
#   TODO(p3) compiler_mesa.py:59-60 -- `nak_compiler_create` / `nak_nir_options`.
#   TODO(p3) compiler_mesa.py:68-72 -- `nak_preprocess_nir` / `nak_compile_shader`.
#   TODO(p3) compiler_mesa.py:86   -- `f"{n:04} [{fst:08x}_{snd:08x}] "` reaches
#                                     libc `fputs` through a ctypes callback.
#   TODO(p3) compiler_mesa.py:91   -- `ir3_isa_disasm` + `struct_isa_decode_options`.
#   TODO(p3) compiler_mesa.py:112-124 -- the twelve IR3 lowering calls.
#   TODO(p3) compiler_mesa.py:119  -- `info.num_ssbos` / `info.num_images`
#                                     (autogen: `_mem_` only, MEASURED).
#   TODO(p3) compiler_mesa.py:131  -- `v.imm_state.count` (same).
#   TODO(p3) compiler_mesa.py:133  -- `self.dev_id.gpu_id` (same).
#
# WALL 2 -- md5. `hashlib.md5(lib).hexdigest()` is a 128-bit digest and bend has
#   no 64-bit product (`base.bend` exports `Word`, not `Word(64n)`;
#   bend2-constraints.md POSITION 2320). The path is ported with the digest as a
#   PARAMETER, so `nv.path` is a row about the path and not about the hash.
#   TODO(p3) compiler_mesa.py:77 -- `hashlib.md5(lib).hexdigest()`.
#
# WALL 3 -- the blob. base64 decode, `struct_blob_reader`, the disassembly
#   buffer and `Path.read_bytes()` all move `bytes`, and `File.read_bytes`
#   exists but has no name to read from here.
#   TODO(p3) compiler_mesa.py:16 -- `base64.b64decode`.
#   TODO(p3) compiler_mesa.py:45 -- `ctypes.string_at(LLVMGetBufferStart(..))`.
#   TODO(p3) compiler_mesa.py:78 -- `f.write(lib[sizeof(struct_nak_shader_info):])`.
#   TODO(p3) compiler_mesa.py:108 -- `pathlib.Path(libf.name).read_bytes()`.
#
# WALL 4 -- objdump / nvdisasm on the PATH. `helpers.system` raises
#   `RuntimeError(f"system: '{cmd}' failed with exit code {e.returncode}\n...")`
#   and `Process.run` has no merged stderr, so the message shape is ported
#   (`sys.msg`) and the merged stream is not.
#   TODO(p3) helpers.py:526 -- `subprocess.check_output(cmd.split(), stderr=STDOUT)`.
import Base

# ===========================================================================
# THE TRACE. Which Mesa/LLVM call the Python makes, in what order. Declared,
# not executed: see WALL 1. A refusal truncates it.
# ===========================================================================
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

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# `hashlib.md5(bytes(range(16))).hexdigest()` -- MEASURED by CPython, and the
# digest is WALL 2 so it arrives as this fixture rather than being computed.
def NAKD() -> String: "1ac1ef01e96caf1be0d329331a4fc2a8"

# ===========================================================================
# THE FORMATTERS. `f"{n:04} [{fst:08x}_{snd:08x}] "` (:89) is the only place this
# file builds a human-facing string from numbers, and both halves are load
# bearing: a `fst` that lost its leading zeros runs the instruction columns
# out of alignment and a decimal `n` that lost its width does the same.
#
# Written with `Char.from_u32` rather than an alphabet lookup because a `U32`
# LITERAL ARM LADDER is a PREFIX MATCH (bend2-constraints.md POSITION 1885) and
# sixteen arms of it would be sixteen ways to be silently wrong.
# ===========================================================================
def hx.digit(+d: U32) -> Char:
  # '0' is 48 and 'a' is 97, so the offset for d >= 10 is 97 - 48 - 10 = 39
  Char.from_u32(U32.add(U32.add(48, Bool.pick(U32, U32.is_gt(d, 9), 39, 0)), d))

def hx.pair(+b: U32) -> String:
  String.from_list([hx.digit(U32.shrn(b, 4n)), hx.digit(U32.and(b, 15))])

def hx.u32_8(+v: U32) -> String:
  String.append(String.append(hx.pair(U32.shrn(v, 24n)),
    hx.pair(U32.and(U32.shrn(v, 16n), 255))),
    String.append(hx.pair(U32.and(U32.shrn(v, 8n), 255)), hx.pair(U32.and(v, 255))))

# decimal, zero padded to `w` digits. `f"{n:04}"` is a WIDTH, and losing it
# runs the instruction-number column out of alignment, so `dc.fixed` and
# `U32.show` are separate rows: one is the digits, one is the padding.
#
# The unpadded decimal is base's `U32.show`, not a hand-rolled divide-by-ten
# loop, because a `U32` self-call on `U32.div(n, 10)` is not a decreasing call
# (there is no subterm relation on a number) and a `Nat` fuel for ten digits
# would be a promise instead of a proof.
def dc.zeros(k: Nat) -> String:
  match k:
    case 0n: ""
    case 1n+p: String.append(dc.zeros(p), "0")

def dc.unpadded(n: U32) -> String: U32.show(n)

def dc.d1(n: U32) -> String: U32.show(n)

def dc.fixed.of(+len: Nat, +w: U32, +s: String) -> String:
  Bool.pick(String, Nat.is_lt(len, U32.to_nat(w)),
    String.concat([dc.zeros(Nat.sub(U32.to_nat(w), len)), s]), s)

def dc.fixed(w: U32, +n: U32) -> String: dc.fixed.of(String.length(U32.show(n)), w, U32.show(n))

# ===========================================================================
# :80  helpers.data64 -- `(data >> 32, data & 0xFFFFFFFF)`, helpers.py:80.
#
# 64-bit, so it arrives as the two words `hi`/`lo` it would have produced, and
# that is not a dodge: bend has no 64-bit type (see the header), and the rest
# of this file only ever needs the two halves. MEASURED against the real
# `helpers.data64` on the eight values in the oracle.
# ===========================================================================
def da.data64(hi: U32, lo: U32) -> List<&2, U32>: [hi, lo]

# A two-element pair needs a `List`, because `Pair` is a Base CONSTRUCTOR
# (bend2-constraints.md POSITION 5014). `da.first` / `da.second` take it apart.
def da.first(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}: 0
    case h <> t: h

# `data64` returns a TWO-TUPLE (helpers.py:80), so first and last ARE the two
# halves. A recursive "second element" walk was written first and needs a `.pick`
# pair to keep the head alive across the recursive arm, and a `.pick` pair of
# one self-recursive walk is MUTUAL recursion -- so `List.last` is the whole of
# it, and there is no condition to get wrong.
def da.last.of(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case None{}: 0

def da.last(xs: List<&2, U32>) -> U32: da.last.of(List.last(&2, U32, xs))

# `da.data64_str` exists so `da.data64` has a CALLER. The mutation that swapped
# its two fields moved ZERO rows until this row existed -- a def nothing calls is
# invisible to every other check, and only the mutation table said so.
def da.data64_str(+hi: U32, +lo: U32) -> String:
  String.concat([hx.u32_8(da.first(da.data64(hi, lo))), "_", hx.u32_8(da.last(da.data64(hi, lo)))])

def da.line(+n: U32, instr_hi: U32, instr_lo: U32) -> String:
  String.concat([dc.fixed(4, n), " [", hx.u32_8(instr_hi), "_", hx.u32_8(instr_lo), "] "])

# ===========================================================================
# :86-91  disas_adreno's decode options, and the ORDER of its five fields.
#
#   mesa.ir3_isa_disasm(lib, len(lib), mesa_fp,
#     mesa.struct_isa_decode_options(gpu_id, True, 0, True, pre_instr_cb=hd))
#
# The field order is the write and the values are not symmetric: `True, 0, True`.
# `da.opts` keeps the five in the order the Python passes them, so a reordering
# is a diff of the joined string rather than a count that stays the same.
# ===========================================================================
def da.opts(gpu_id: U32) -> List<&2, U32>: [gpu_id, 1, 0, 1]

def da.opt_count() -> U32: 4

def da.opts_str2(rest: List<&2, U32>, +hd: String) -> List<&2, String>:
  match rest:
    case Nil{}: [hd]
    case h <> t: List.append(&2, String, [hd], da.opts_str2(t, dc.unpadded(h)))

def da.opts_sp(+gpu_id: U32) -> List<&2, String>: da.opts_str2(da.opts(gpu_id), dc.unpadded(gpu_id))

def da.opts_str(gpu_id: U32) -> String: String.join(da.opts_sp(gpu_id), ",")

# ===========================================================================
# :56  warps_per_sm. THE TABLE, and the shape of the test is the content.
#
#   return 48 if arch in ("sm_86", "sm_87", "sm_89", "sm_120") else 64
#
# A membership test against FOUR EXACT strings, so every other string is 64.
# MEASURED, and the negative rows are the whole point:
#   "sm_86" "sm_87" "sm_89" "sm_120"  -> 48
#   "sm_86x"                          -> 64   a PREFIX test would say 48
#   "SM_86"                           -> 64   case sensitive
#   "sm_86 "                          -> 64   the trailing space is part of it
#   "sm_8" "" "sm"                    -> 64
#
# `w.warps` is written as four equality tests rather than a range or a prefix,
# and `w.is48` is the set itself so the two cannot drift apart.
# ===========================================================================
def w.is48(+arch: String) -> Bool:
  Bool.or(Bool.or(String.eq(arch, "sm_86"), String.eq(arch, "sm_87")),
    Bool.or(String.eq(arch, "sm_89"), String.eq(arch, "sm_120")))

def w.warps(+arch: String) -> U32: Bool.to_u32(w.is48(arch))

def w.n48() -> U32: 4

def w.warps_raw(+arch: String) -> U32: Bool.pick(U32, w.is48(arch), 48, 64)

def w.set() -> List<&2, String>: ["sm_86", "sm_87", "sm_89", "sm_120"]

# ===========================================================================
# :58  `int(arch[3:])`. The arch is `sm_` followed by DECIMAL DIGITS, and
# `arch[3:]` is taken on faith by Python -- `int("")` would raise, and
# `int("sm")` never happens because the slice is empty. So the digits are the
# part, and `a3.n` is the decimal parse of them.
# ===========================================================================
def a3.drop3(+arch: String) -> String:
  # `arch[3:]` -- drop exactly three characters, no more and no fewer. Python's
  # slice is well defined on a short string (it is the empty string) and so is
  # `String.drop`, which is why there is no guard.
  String.drop(arch, 3n)

# :16 `blob_reader_init(blobreader, src:=base64.b64decode(enc_src), len(src))`
# the two lengths a blob reader is handed: the DECODED length, and base64's
# three-for-four expansion is what makes the encoded length a different number.
def de.b64_chars(+encoded: String) -> U32: U32.from_nat(String.length(encoded))

# The padding is the number of TRAILING '=' characters -- one or two, and
# measured against the STRING and not against `len % 4`. The negative row is the
# eight-character UNPADDED encoding, which has zero of them. `de.b64_tail` walks
# backwards from the last character and stops at the first non-'='; it needs a
# `Nat` because a `String` has no structural subterm to recurse on.
# The padding is the number of TRAILING '=' characters -- one or two, and read
# off the STRING rather than off `len % 4`. The negative row is the
# eight-character UNPADDED encoding, which has zero of them.
#
# TWO equality tests, not a walk: `String.take(s, len(s) - k)` is the k-th
# character from the end, and a padded and an unpadded encoding of the SAME
# length are distinguished by exactly these two. (A recursive backwards walk was
# written first and needed a `Nat` fuel with the fuel as the FIRST parameter,
# because a `String` has no structural subterm -- bend2-constraints.md POSITION
# 3191 -- and two reads of the fuel then forced a `.of` split, which is mutual
# recursion. The two tests are four lines and none of that.)
# MEASURED, and it cost a row: `String.take` in base.bend:1932 takes a PREFIX,
# not a suffix. The last character is `String.take(String.drop(s, len-1), 1)`.
def de.at(+encoded: String, +from_end: U32) -> String:
  String.take(String.drop(encoded, U32.to_nat(U32.sub(de.b64_chars(encoded), from_end))), 1n)

def de.b64_pad1(encoded: String) -> Bool: String.eq(de.at(encoded, 1), "=")

def de.b64_pad2(encoded: String) -> Bool: String.eq(de.at(encoded, 2), "=")

def de.b64_pad(+encoded: String) -> U32:
  Bool.pick(U32, de.b64_pad2(encoded), 2, Bool.pick(U32, de.b64_pad1(encoded), 1, 0))

# `base64.b64decode` is floor(len/4)*3 minus one per padding character, so the
# three fixtures give 6, 5 and 6 bytes for a length of 8, 8 and 8.
def de.b64_bytes.of(+n: U32, +pad: U32) -> U32: U32.sub(U32.mul(U32.div(n, 4), 3), pad)

def de.b64_bytes(+encoded: String) -> U32: de.b64_bytes.of(de.b64_chars(encoded), de.b64_pad(encoded))

def de.n(+o: U32) -> U32: o

def ra.size(+o: U32) -> U32: de.n(o)
# `int(digits)`, base ten. There is no `Nat.parse` in base.bend (MEASURED:
# `grep '^def Nat\.' base.bend` finds add/sub/mul/div/mod/pow/cmp/show and no
# parser), so this is the parse. It walks a `Char` LIST rather than a `String`
# because a `List` tail is a structural subterm and a `String` is not -- the
# self-call has to shrink, and `String.from_list(t2)` does not.
def a3.read.go(cs: List<&2, Char>, acc: Nat) -> Nat:
  match cs:
    case Nil{}: acc
    case h <> t: a3.read.go(t, Nat.add(Nat.mul(acc, 10n), U32.to_nat(U32.sub(Char.to_u32(h), 48))))

def a3.read.of(cs: List<&2, Char>) -> Nat: a3.read.go(cs, 0n)

def a3.read(s: String) -> Nat: a3.read.of(String.to_list(s))

def a3.n(+arch: String) -> U32: U32.from_nat(a3.read(a3.drop3(arch)))

# ===========================================================================
# :59  `struct_nv_device_info(sm=int(arch[3:]), max_warps_per_mp=warps_per_sm(arch))`
# ===========================================================================
# `struct_nv_device_info(sm=..., max_warps_per_mp=...)` -- two named fields, so
# two defs. There is no `U32.get` in base.bend (MEASURED), so a two-element
# `U32` list could not be taken apart again and the fields are separate.
def nak.sm(+arch: String) -> U32: a3.n(arch)
def nak.warps(+arch: String) -> U32: Bool.pick(U32, w.is48(arch), 48, 64)

def nak.key(+arch: String) -> String: String.concat(["compile_nak_", arch])

def nak.dev_str(+arch: String) -> String:
  String.concat([dc.unpadded(nak.sm(arch)), ",", dc.unpadded(nak.warps(arch))])

# ===========================================================================
# :75-80  NAKCompiler.disassemble's ONE external command.
#
#   fn = (Path(tempfile.gettempdir()) / f"tinynak_{md5(lib).hexdigest()}").as_posix()
#   print(system(f"nvdisasm -b SM{self.arch[3:]} {fn}"))
#
# The digest is WALL 2 and arrives as `digest`; what is left is the PATH and
# the COMMAND, and both are rows. `as_posix()` is a no-op on macOS and Linux
# and is not ported, because on both it cannot change the string.
# ===========================================================================
def nv.dir(tmp: String) -> String: tmp

def nv.path(tmp: String, +digest: String) -> String:
  String.concat([tmp, "/tinynak_", digest])

def nv.cmd(tmp: String, digest: String, +arch: String) -> List<&2, String>:
  ["nvdisasm", "-b", String.concat(["SM", a3.drop3(arch)]), nv.path(tmp, digest)]

def nv.cmd_str(tmp: String, digest: String, +arch: String) -> String:
  String.join(nv.cmd(tmp, digest, arch), " ")

# :80 the failure message, verbatim
def nv.fail(+e: String) -> String:
  String.concat(["Failed to generate SASS ", e, " Make sure your PATH contains nvdisasm binary of compatible version."])

# ===========================================================================
# :51  cpu_objdump's command. helpers.py:530 writes `kernel.o` into a
# `TemporaryDirectory` and runs `objdump -d <path>`.
# ===========================================================================
def dso.tool() -> String: "objdump"

def dso.file() -> String: "kernel.o"

def dso.cmd(+tmp: String) -> List<&2, String>: [dso.tool(), "-d", String.concat([tmp, "/", dso.file()])]

def dso.cmd_str(+tmp: String) -> String: String.join(dso.cmd(tmp), " ")

# ===========================================================================
# :98-104  IR3Compiler. The assert, the device id, the option flag and the key.
# `0x6030001` is 100859905 and it fits a `U32` exactly; the hex is in the comment
# because bend has no hex literal literals.
# ===========================================================================
def ir3.head.of(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case h <> t: h

def ir3.arch_ok(+arch: String) -> Bool: String.eq(ir3.head.of(String.split(arch, ',')), "a630")

def ir3.gpu_id() -> U32: 630
def ir3.chip_id() -> U32: 100859905     # 0x6030001

def ir3.disable_cache(on: Bool) -> U32: Bool.to_u32(on)

def ir3.key(+arch: String) -> String: String.concat(["compile_ir3_", arch])

# :118 `v.const_state, shader.variants, shader.variant_count = ..., ..., 1`
# THREE fields assigned in ONE statement, and the third is a literal 1.
def ir3.variant_count() -> U32: 1

def ir3.variant_field_count() -> U32: 3

# :119 `v.num_uavs = info.num_ssbos + info.num_images`. Both fields are WALL 1,
# so they are parameters; the SUM is this file's own logic and is gated.
def ir3.num_uavs(ssbos: U32, images: U32) -> U32: U32.add(ssbos, images)

# :123 the four-way concatenation, by LENGTH:
#   bytes(v) + bytes(v.const_state.contents) + values(count*4) + string_at(lib, info.size)
def ir3.ret_parts(+variant: U32, +const_state: U32, +count: U32, +info_size: U32) -> List<&2, U32>:
  [variant, const_state, U32.mul(count, 4), info_size]

def ir3.ret_len(variant: U32, const_state: U32, count: U32, info_size: U32) -> U32:
  U32.from_nat(List.length(&2, U32, ir3.ret_parts(variant, const_state, count, info_size)))

def ir3.ret_total(+variant: U32, +const_state: U32, +count: U32, +info_size: U32) -> U32:
  U32.add(U32.add(U32.add(variant, const_state), U32.mul(count, 4)), info_size)

# `ir3.ret_parts_str` DERIVES from `ir3.ret_parts`. The first version spelled the
# four lengths a SECOND time, and mutation M29 -- which changed `ret_parts` to
# `count * 8` -- moved NOTHING: two transcriptions of one list, so neither was
# localised. This is the "a count row and the table it counts are two
# independent transcriptions" note (bend2-constraints.md POSITION 5128) inside
# one file.
def ir3.ret_parts_str.of(xs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: ir3.ret_parts_str.of(t, List.append(&2, String, acc, [dc.unpadded(h)]))

def ir3.ret_parts_str(+variant: U32, +const_state: U32, +count: U32, +info_size: U32) -> String:
  String.join(ir3.ret_parts_str.of(ir3.ret_parts(variant, const_state, count, info_size), []), ",")

# ===========================================================================
# :127-131  unpack_lib. THE HEADLINE PURE LOGIC OF THIS FILE.
#
#     shifted = lib[ctypes.sizeof(v:=struct_ir3_shader_variant.from_buffer_copy(lib)):]
#     shifted = shifted[ctypes.sizeof(cs:=struct_ir3_const_state.from_buffer_copy(shifted)):]
#     return v, cs, shifted[:v.imm_state.count*4], shifted[v.imm_state.count*4:]
#
# TWO successive offsets -- drop `variant` bytes, then drop `const_state` bytes
# from what is left -- and THEN one split at `count * 4`. The order is the
# content: a port that split first would answer `count*4` bytes off the front
# of the ORIGINAL buffer, and the two agree exactly when
# `sizeof(const_state) == 0`, which is never.
#
# `ul.head` and `ul.imm` take the LENGTHS (the sizes and the count are WALL 1
# and WALL 1 respectively), and `ul.tail` the total, so the two-stage slicing is
# a subtraction chain rather than a re-derivation of an index.
# ===========================================================================
def ul.head(variant: U32, const_state: U32) -> U32: U32.add(variant, const_state)

def ul.imm(variant: U32, const_state: U32, +count: U32) -> U32: U32.mul(count, 4)

def ul.total(+variant: U32, +const_state: U32, +count: U32, +info_size: U32) -> U32:
  U32.add(ul.head(variant, const_state), U32.add(U32.mul(count, 4), info_size))

def ul.asm_len(+variant: U32, +const_state: U32, +count: U32, +info_size: U32) -> U32:
  U32.sub(ul.total(variant, const_state, count, info_size), ul.head(variant, const_state))

def ul.split_point(+variant: U32, +const_state: U32, +count: U32) -> U32:
  U32.add(ul.head(variant, const_state), U32.mul(count, 4))

# ===========================================================================
# :20  LVPCompiler.__init__'s `arch.split(",")`. base's `String.split` KEEPS the
# empty fields (MEASURED, and that is the same measurement compiler_amd.bend
# records), so `""` answers ONE empty arch and not zero.
# ===========================================================================
def lvp.archs(+arch: String) -> List<&2, String>: String.split(arch, ',')

def lvp.arch_n(+arch: String) -> U32: U32.from_nat(List.length(&2, String, lvp.archs(arch)))

def lvp.cache_key() -> String: "compile_lvp"

# :27-28 `struct_lp_type(floating=True, sign=True, width=32, length=4)`
def lpt.floating(on: Bool) -> U32: Bool.to_u32(on)
def lpt.sign(on: Bool) -> U32: Bool.to_u32(on)
def lpt.width() -> U32: 32
def lpt.length() -> U32: 4
def lpt.res() -> U32: 0               # LP_JIT_RES_CONSTANTS
def lpt.str() -> String: "1,1,32,4"



# ===========================================================================
# THE GATE. Every expectation is a row of `.agents/slop/cs_oracle.py`, produced
# by calling the REAL Python with only the FFI replaced.
# ===========================================================================
def t_fmt() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("hx.pair_0", hx.pair(0))
    b : Unit <- srow("hx.pair_10", hx.pair(10))
    c : Unit <- srow("hx.pair_15", hx.pair(15))
    d : Unit <- srow("hx.pair_255", hx.pair(255))
    e : Unit <- srow("hx.u32_8_0", hx.u32_8(0))
    f : Unit <- srow("hx.u32_8_1", hx.u32_8(1))
    g : Unit <- srow("hx.u32_8_255", hx.u32_8(255))
    h : Unit <- srow("hx.u32_8_4096", hx.u32_8(4096))
    i : Unit <- srow("hx.u32_8_4294967295", hx.u32_8(4294967295))
    j : Unit <- srow("hx.u32_8_3735928559", hx.u32_8(3735928559))
    k : Unit <- srow("dc.d1_0", dc.d1(0))
    l : Unit <- srow("dc.d1_7", dc.d1(7))
    m : Unit <- srow("dc.fixed4_0", dc.fixed(4, 0))
    n : Unit <- srow("dc.fixed4_15", dc.fixed(4, 15))
    o : Unit <- srow("dc.fixed4_255", dc.fixed(4, 255))
    p : Unit <- srow("dc.fixed4_4096", dc.fixed(4, 4096))
    q : Unit <- srow("dc.fixed4_65535", dc.fixed(4, 65535))
    r : Unit <- srow("dc.unpadded_0", dc.unpadded(0))
    s : Unit <- srow("dc.unpadded_12345", dc.unpadded(12345))
    t : Unit <- srow("dc.fixed4_65536", dc.fixed(4, 65536))
    u : Unit <- srow("dc.fixed4_999", dc.fixed(4, 999))
    # THE BOUNDARY FIXTURES, and mutation M09 found they were missing: widening
    # the WIDTH in `dc.fixed`'s condition moved NOTHING until a fixture with
    # `len(n) == w` existed, because every value above has fewer than four
    # digits and so answers the padded arm under both widths. `1000` is the
    # smallest four-digit value and `9999` the largest.
    v : Unit <- srow("dc.fixed4_1000", dc.fixed(4, 1000))
    w : Unit <- srow("dc.fixed4_9999", dc.fixed(4, 9999))
    x : Unit <- srow("dc.fixed4_100", dc.fixed(4, 100))
    y : Unit <- srow("dc.fixed3_1000", dc.fixed(3, 1000))
    z : Unit <- srow("dc.fixed1_0", dc.fixed(1, 0))
    IO.print("mesa_fmt_done=1")

def t_line() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("da.line_0_0_0", da.line(0, 0, 0))
    b : Unit <- srow("da.line_1_0_1", da.line(1, 0, 1))
    c : Unit <- srow("da.line_15_0_15", da.line(15, 0, 15))
    d : Unit <- srow("da.line_255_0_255", da.line(255, 0, 255))
    e : Unit <- srow("da.line_4096_dead_beef", da.line(4096, 3735928559, 3405691582))
    f : Unit <- srow("da.line_65535_max_max", da.line(65535, 4294967295, 4294967295))
    g : Unit <- srow("da.line_1_1_2", da.line(1, 1, 2))
    h : Unit <- srow("da.line_2_abcdef_2", da.line(2, 2882400001, 591751049))
    i : Unit <- srow("da.line_65536_0_16", da.line(65536, 0, 16))
    j : Unit <- srow("da.line_12345_0_0", da.line(12345, 0, 0))
    k : Unit <- srow("da.line_999_0_low", da.line(999, 0, 4294967295))
    l : Unit <- srow("da.data64_str_dead_beef", da.data64_str(3735928559, 3405691582))
    m : Unit <- srow("da.data64_str_zero", da.data64_str(0, 0))
    n : Unit <- srow("da.data64_str_1", da.data64_str(1, 0))
    IO.print("mesa_line_done=1")

def t_warps() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("w.warps_sm_86", U32.show(w.warps_raw("sm_86")))
    b : Unit <- srow("w.warps_sm_87", U32.show(w.warps_raw("sm_87")))
    c : Unit <- srow("w.warps_sm_89", U32.show(w.warps_raw("sm_89")))
    d : Unit <- srow("w.warps_sm_120", U32.show(w.warps_raw("sm_120")))
    e : Unit <- srow("w.warps_sm_75", U32.show(w.warps_raw("sm_75")))
    f : Unit <- srow("w.warps_sm_80", U32.show(w.warps_raw("sm_80")))
    g : Unit <- srow("w.warps_sm_90", U32.show(w.warps_raw("sm_90")))
    h : Unit <- srow("w.warps_sm_100", U32.show(w.warps_raw("sm_100")))
    i : Unit <- srow("w.warps_sm_86x", U32.show(w.warps_raw("sm_86x")))
    j : Unit <- srow("w.warps_SM_86", U32.show(w.warps_raw("SM_86")))
    k : Unit <- srow("w.warps_sm_86_SP", U32.show(w.warps_raw("sm_86 ")))
    l : Unit <- srow("w.warps_sm_8", U32.show(w.warps_raw("sm_8")))
    m : Unit <- srow("w.warps_EMPTY", U32.show(w.warps_raw("")))
    n : Unit <- srow("w.warps_sm", U32.show(w.warps_raw("sm")))
    o : Unit <- srow("w.set", String.join(w.set(), " "))
    p : Unit <- srow("w.n48", U32.show(w.n48()))
    IO.print("mesa_warps_done=1")

def t_a3() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("a3.n_sm_86", U32.show(a3.n("sm_86")))
    b : Unit <- srow("a3.n_sm_89", U32.show(a3.n("sm_89")))
    c : Unit <- srow("a3.n_sm_120", U32.show(a3.n("sm_120")))
    d : Unit <- srow("a3.n_sm_75", U32.show(a3.n("sm_75")))
    e : Unit <- srow("a3.drop3_sm_86", a3.drop3("sm_86"))
    f : Unit <- srow("a3.drop3_sm_120", a3.drop3("sm_120"))
    g : Unit <- srow("a3.drop3_sm", a3.drop3("sm"))
    h : Unit <- srow("a3.drop3_EMPTY", a3.drop3(""))
    i : Unit <- srow("a3.drop3_s", a3.drop3("s"))
    IO.print("mesa_a3_done=1")

def t_nak() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("nak.key_sm_86", nak.key("sm_86"))
    b : Unit <- srow("nak.key_sm_120", nak.key("sm_120"))
    c : Unit <- srow("nak.dev_sm_86", nak.dev_str("sm_86"))
    d : Unit <- srow("nak.dev_sm_75", nak.dev_str("sm_75"))
    s : Unit <- srow("nak.dev_sm_89", nak.dev_str("sm_89"))
    u : Unit <- srow("nak.dev_sm_120", nak.dev_str("sm_120"))
    e : Unit <- srow("nv.cmd_str", nv.cmd_str("/T", NAKD(), "sm_86"))
    f : Unit <- srow("nv.cmd_str120", nv.cmd_str("/T", NAKD(), "sm_120"))
    g : Unit <- srow("nv.path", nv.path("/T", NAKD()))
    h : Unit <- srow("nv.dir", nv.dir("/T"))
    i : Unit <- srow("dso.cmd_str", dso.cmd_str("/T"))
    j : Unit <- srow("dso.file", dso.file())
    IO.print("mesa_nak_done=1")

def t_ir3() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ir3.arch_ok_a630", U32.show(Bool.to_u32(ir3.arch_ok("a630"))))
    b : Unit <- srow("ir3.arch_ok_a630_x", U32.show(Bool.to_u32(ir3.arch_ok("a630,x"))))
    c : Unit <- srow("ir3.arch_ok_a630_comma", U32.show(Bool.to_u32(ir3.arch_ok("a630,"))))
    d : Unit <- srow("ir3.arch_ok_a640", U32.show(Bool.to_u32(ir3.arch_ok("a640"))))
    e : Unit <- srow("ir3.arch_ok_EMPTY", U32.show(Bool.to_u32(ir3.arch_ok(""))))
    f : Unit <- srow("ir3.arch_ok_A630", U32.show(Bool.to_u32(ir3.arch_ok("A630"))))
    g : Unit <- srow("ir3.arch_ok_a63", U32.show(Bool.to_u32(ir3.arch_ok("a63"))))
    h : Unit <- srow("ir3.gpu_id", U32.show(ir3.gpu_id()))
    i : Unit <- srow("ir3.chip_id", U32.show(ir3.chip_id()))
    j : Unit <- srow("ir3.disable_cache_1", U32.show(ir3.disable_cache(True{})))
    k : Unit <- srow("ir3.disable_cache_0", U32.show(ir3.disable_cache(False{})))
    l : Unit <- srow("ir3.key_a630", ir3.key("a630"))
    m : Unit <- srow("ir3.key_a630_x", ir3.key("a630,x"))
    n : Unit <- srow("ir3.variant_field_count", U32.show(ir3.variant_field_count()))
    o : Unit <- srow("ir3.variant_fields", dc.unpadded(ir3.variant_count()))
    p : Unit <- srow("ir3.num_uavs_0_0", U32.show(ir3.num_uavs(0, 0)))
    q : Unit <- srow("ir3.num_uavs_2_3", U32.show(ir3.num_uavs(2, 3)))
    r : Unit <- srow("ir3.num_uavs_4294967295_1", U32.show(ir3.num_uavs(4294967295, 1)))
    s : Unit <- srow("ir3.num_uavs_65535_65535", U32.show(ir3.num_uavs(65535, 65535)))
    t : Unit <- srow("ir3.ret_parts_str", ir3.ret_parts_str(2040, 1424, 3, 512))
    v : Unit <- srow("ir3.ret_total", U32.show(ir3.ret_total(2040, 1424, 3, 512)))
    w : Unit <- srow("ir3.ret_len", U32.show(ir3.ret_len(2040, 1424, 3, 512)))
    x : Unit <- srow("ir3.ret_len_0", U32.show(ir3.ret_len(0, 0, 0, 0)))
    IO.print("mesa_ir3_done=1")

def t_ul() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("ul.head", U32.show(ul.head(2040, 1424)))
    b : Unit <- srow("ul.head_0", U32.show(ul.head(0, 0)))
    c : Unit <- srow("ul.imm_0", U32.show(ul.imm(2040, 1424, 0)))
    d : Unit <- srow("ul.imm_1", U32.show(ul.imm(2040, 1424, 1)))
    e : Unit <- srow("ul.imm_3", U32.show(ul.imm(2040, 1424, 3)))
    f : Unit <- srow("ul.imm_9", U32.show(ul.imm(2040, 1424, 9)))
    g : Unit <- srow("ul.total_0", U32.show(ul.total(2040, 1424, 0, 6)))
    h : Unit <- srow("ul.total_1", U32.show(ul.total(2040, 1424, 1, 6)))
    i : Unit <- srow("ul.total_3", U32.show(ul.total(2040, 1424, 3, 6)))
    j : Unit <- srow("ul.total_9", U32.show(ul.total(2040, 1424, 9, 6)))
    k : Unit <- srow("ul.asm_len_0", U32.show(ul.asm_len(2040, 1424, 0, 6)))
    l : Unit <- srow("ul.asm_len_3", U32.show(ul.asm_len(2040, 1424, 3, 6)))
    m : Unit <- srow("ul.asm_len_9", U32.show(ul.asm_len(2040, 1424, 9, 6)))
    n : Unit <- srow("ul.split_point_0", U32.show(ul.split_point(2040, 1424, 0)))
    o : Unit <- srow("ul.split_point_3", U32.show(ul.split_point(2040, 1424, 3)))
    p : Unit <- srow("ul.split_point_9", U32.show(ul.split_point(2040, 1424, 9)))
    IO.print("mesa_ul_done=1")

def t_lvp() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("lvp.arch_n_a630", U32.show(lvp.arch_n("a630")))
    b : Unit <- srow("lvp.arch_n_a630_x", U32.show(lvp.arch_n("a630,x")))
    c : Unit <- srow("lvp.arch_n_EMPTY", U32.show(lvp.arch_n("")))
    d : Unit <- srow("lvp.arch_n_trailing", U32.show(lvp.arch_n("a630,")))
    e : Unit <- srow("lvp.archs_a630_x", String.join(lvp.archs("a630,x"), "|"))
    f : Unit <- srow("lvp.archs_EMPTY", String.join(lvp.archs(""), "|"))
    g : Unit <- srow("lvp.cache_key", lvp.cache_key())
    h : Unit <- srow("lpt.str", lpt.str())
    i : Unit <- srow("lpt.width", U32.show(lpt.width()))
    j : Unit <- srow("lpt.length", U32.show(lpt.length()))
    k : Unit <- srow("lpt.res", U32.show(lpt.res()))
    l : Unit <- srow("lpt.floating_1", U32.show(lpt.floating(True{})))
    m : Unit <- srow("lpt.sign_1", U32.show(lpt.sign(True{})))
    IO.print("mesa_lvp_done=1")

# base64 fixtures: 8 characters, padded with TWO '=', with ONE, and none.
def PAD2() -> String: "QUFBQQ=="
def PAD1() -> String: "QUFBQQE="
def PAD0() -> String: "QUFBQUFB"

def t_de() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("de.n_0", U32.show(de.n(0)))
    b : Unit <- srow("de.n_1", U32.show(de.n(1)))
    c : Unit <- srow("de.n_2", U32.show(de.n(2)))
    d : Unit <- srow("de.n_7", U32.show(de.n(7)))
    e : Unit <- srow("de.n_12", U32.show(de.n(12)))
    f : Unit <- srow("de.n_24", U32.show(de.n(24)))
    g : Unit <- srow("ra.size_16", U32.show(ra.size(16)))
    h : Unit <- srow("ra.size_8", U32.show(ra.size(8)))
    i : Unit <- srow("de.b64_chars_8", U32.show(de.b64_chars(PAD2)))
    j : Unit <- srow("de.b64_pad_8", U32.show(de.b64_pad(PAD2)))
    k : Unit <- srow("de.b64_pad_8b", U32.show(de.b64_pad(PAD1)))
    l : Unit <- srow("de.b64_bytes_8", U32.show(de.b64_bytes(PAD2)))
    m : Unit <- srow("de.b64_bytes_8b", U32.show(de.b64_bytes(PAD1)))
    n : Unit <- srow("de.b64_bytes_0", U32.show(de.b64_bytes(PAD0)))
    IO.print("mesa_de_done=1")

# the trace: the ORDER of the compile_hip-equivalent calls for each class
def lc(t: Tr) -> Tr:
  s0 = Tr.put("nir_deserialize", "opts", t)
  s1 = Tr.put("gallivm_create", "lp_context_ref", s0)
  s2 = Tr.put("lp_build_tgsi_params", "float,sign,32,4", s1)
  s3 = Tr.put("LLVMAddFunction", "entry", s2)
  s4 = Tr.put("lp_build_mask_begin", "one", s3)
  s5 = Tr.put("lp_build_mask_end", "", s4)
  s6 = Tr.put("lp_build_nir_soa", "shader", s5)
  s7 = Tr.put("LLVMBuildRetVoid", "", s6)
  s8 = Tr.put("gallivm_verify_function", "fn", s7)
  s9 = Tr.put("lp_passmgr_run", "module", s8)
  Tr.put("LLVMTargetMachineEmitToMemoryBuffer", "obj", s9)

def nc(t: Tr) -> Tr:
  s0 = Tr.put("nir_deserialize", "nir_options", t)
  s1 = Tr.put("nak_preprocess_nir", "cc", s0)
  s2 = Tr.put("nak_compile_shader", "False,cc,0,None", s1)
  s3 = Tr.put("nak_shader_bin_destroy", "out", s2)
  Tr.put("ralloc_free", "shader", s3)

def rc(t: Tr) -> Tr:
  s0 = Tr.put("nir_deserialize", "nir_options", t)
  s1 = Tr.put("ir3_nir_lower_io_vars_to_temporaries", "shader", s0)
  s2 = Tr.put("ir3_finalize_nir", "cc,opts", s1)
  s3 = Tr.put("ir3_nir_post_finalize", "shader", s2)
  s4 = Tr.put("ir3_compile_shader_nir", "cc,shader,v", s3)
  s5 = Tr.put("ir3_shader_assemble", "v", s4)
  Tr.put("ralloc_free", "pointer(v)", s5)

def Tr.first_of(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case h <> t: h

def Tr.last_of(m: Maybe<&2, String>) -> String:
  match m:
    case Some{v}: v
    case None{}: ""

def Tr.tail_name(tr: Tr) -> String: Tr.last_of(List.last(&2, String, Tr.items(tr)))

def Tr.head(tr: Tr) -> String: Tr.first_of(Tr.items(tr))

def t_trace() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("tr.lvp.n", U32.show(Tr.n(lc(Tr.of()))))
    b : Unit <- srow("tr.nak.n", U32.show(Tr.n(nc(Tr.of()))))
    c : Unit <- srow("tr.ir3.n", U32.show(Tr.n(rc(Tr.of()))))
    d : Unit <- srow("tr.lvp.first", Tr.head(lc(Tr.of())))
    e : Unit <- srow("tr.lvp.last", Tr.tail_name(lc(Tr.of())))
    f : Unit <- srow("tr.nak.first", Tr.head(nc(Tr.of())))
    g : Unit <- srow("tr.nak.last", Tr.tail_name(nc(Tr.of())))
    v : Unit <- srow("tr.ir3.first", Tr.head(rc(Tr.of())))
    w : Unit <- srow("tr.ir3.last", Tr.tail_name(rc(Tr.of())))
    IO.print("mesa_trace_done=1")

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_fmt()
    b : Unit <- t_line()
    c : Unit <- t_warps()
    d : Unit <- t_a3()
    e : Unit <- t_nak()
    f : Unit <- t_ir3()
    g : Unit <- t_ul()
    i : Unit <- t_lvp()
    j : Unit <- t_de()
    k : Unit <- t_trace()
    IO.print("compiler_mesa-done=1")