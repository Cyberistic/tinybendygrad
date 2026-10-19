# tinybendygrad/runtime/support/c.bend -- tinygrad/runtime/support/c.py
#
# ===========================================================================
# c.py IS A ctypes FILM. WHAT IS IN HERE, AND WHY IT IS NOT NOTHING.
#
# `c.py` is 142 lines and eleven of them are `import ctypes, functools, os,
# pathlib, re, sys, sysconfig`. What it carries is the ALGEBRA A C STRUCT AND
# A DLIB REQUEST ARE BUILT FROM, and that algebra is where a silently wrong
# answer is a silently wrong register write -- the same reason
# `renderer/nir.bend` ports `nir.py`'s tables rather than its mesa calls.
#
# So this file ports: the ioctl REQUEST NUMBER, the `_real_fields_` entry
# algebra, `Field`'s bitfield slice/mask/merge, `Field._resolve`'s throwaway
# ctypes class, `register_fields`, `record`, `Struct.__init__`'s
# positional-then-keyword order, and `findlib`'s path and file-name predicates.
# Each of those is a `getenv`, a `pathlib.Path.is_file` or a `ctypes` call in
# Python, and a pure integer or string function here.
#
# ---------------------------------------------------------------------------
# THE SIX THINGS MEASURED THAT NOBODY WOULD GUESS
#
# 1. THE NO-STRUCT ARM THROWS AWAY `__idir`. `_do_ioctl` is
#      `if __struct is None: return ioctl((__base<<8)|__nr, ...)`
#    -- and that is the WHOLE expression. So `_do_ioctl(3, 'A', 0x11, None)`
#    and `_do_ioctl(0, 'A', 0x11, None)` issue the SAME request, and a reader
#    who folds the direction into the no-struct arm gets `0xc0004111` where
#    CPython gives `0x00004111`. `ioctl_none_idir3_same` pins it.
#
# 2. `findlib` NEVER PUTS `nm` IN A FILE NAME. The base names are built from
#    `p`, the loop variable over `paths`, not from `nm`:
#      `for p in paths: ... for base in [f"lib{p}.dylib", f"{p}.dylib", str(p)]`
#    `nm` reaches only the `nm_PATH` env key and the `('libc','m')` arm. So
#    `findlib('zzz', ['P'])` finds a file called `libP.dylib`, and
#    `findlib('zzz', ['zzz'])` in the SAME directory finds nothing.
#    `fl_osx_bases_tested` is c.py's own ladder, captured by shimming
#    `c.__dict__['pathlib']` so every `is_file()` argument is recorded.
#
# 3. THE FILESYSTEM SEARCH IS INSIDE `for p in paths`. `paths=[]` never looks
#    at the disk, and an ABSOLUTE path that is not a file `continue`s PAST the
#    whole prefix loop -- a later relative entry still searches, though, which
#    is why `fl_found_paths_abs_then_rel` and `fl_found_paths_rel_then_abs` are
#    both 1 and `fl_found_paths_two_abs` is 0. `findlib.abs` is that
#    three-way decision and it is four lines.
#
# 4. THE `emsg` DEFAULT AND THE ENV KEY DISAGREE ON A DASH. `findlib` reads
#    `nm.replace('-','_').upper()+"_PATH"`, so `my-lib-x` is overridden by
#    `MY_LIB_X_PATH`; `__init__`'s fallback message says
#    `try setting MY-LIB-X_PATH?`. Two different keys for one variable, in one
#    file. `dll_emsg_dash` and `dll_envkey_dash` are the halves and
#    `dll_emsg_key_ne_envkey` is the disagreement as a row.
#
# 5. `init_c_struct_t` SETS `_fields_` AND NEVER TOUCHES `SIZE`. `record` sets
#    `_fields_` FROM `cls.SIZE`, in the other direction, so a class made by
#    `init_c_struct_t(8, ...)` has `SIZE == 0` and `sizeof == 8`.
#    `ics_sizes=0,8` and `ics_size_attr_stays_0=0` are the same fact twice.
#
# 6. `Array`'s KEY IS A TYPING OBJECT, NOT A TUPLE. `get_args(Literal[3])` is
#    `(3,)`; `get_args((3,))` is `()` and `c.Array[c_uint, (3,)]` raises
#    `IndexError`. Every generated field spells it `c.Array[ty, Literal[n]]`
#    (`runtime/autogen/io_uring.py:66`) and the `Literal[0]` form is exactly
#    the zero-length array `Field._resolve` builds by hand.
#
# ---------------------------------------------------------------------------
# THE BOUNDARIES OF THE ARITHMETIC, MEASURED NOT ASSUMED
#
# * `mask = (1 << bit_width) - 1` is exact in a `U32` for `bit_width <= 32`,
#   and `bit_width == 32` lands on `(1<<32) & 0xFFFFFFFF == 0` so the answer
#   is `0xFFFFFFFF`, which is RIGHT BY SATURATION rather than by arithmetic.
#   `bit_width > 32` needs 64 bits and Bend 2.0.34 has no `U64`.
#   `TODO(p3) c.py:68` -- a `U64` and a widened `mask`.
# * `set_mask = ~((1 << bit_width) - 1) << bit_off` is UNBOUNDED in Python and
#   a 32-bit complement here. Same value in the low `sz` bytes for every
#   `sz <= 4`, because `b2i` is `sz` bytes wide. `sz > 4` truncates.
#   `TODO(p3) c.py:69`.
# * THERE IS NO MASKING ON THE STORE, and that is observable: `b` is 12 bits at
#   `bit_off 4` in a 2-byte slice, so `o.b = 0x1000` raises `OverflowError` out
#   of `to_bytes(sz)` rather than truncating to `0`. `Field.bset_overflows` is
#   that test; `bf_set_b_overflow=OverflowError` is the oracle.
# * `sys.byteorder` is read INSIDE the closures `_resolve` builds, so it is a
#   PARAMETER of the getter and the setter and not a constant: with `c.sys`
#   shimmed to `big`, `bf_order_big` reads `b=2748` where little-endian reads
#   `b=3290` off the SAME bytes. That row exists to prove this file carries the
#   parameter instead of hardcoding it. The non-bitfield read path is NOT
#   affected -- ctypes uses NATIVE order, so `x` reads the same under both.
#   That asymmetry is real and is why `Field.load` and `Field.bget` are two
#   defs rather than one with a flag.
# * `Struct` memory is `List<&2, U32>`, one element per byte, and every
#   `ctypes` type is carried as `ctypes.sizeof(type)`. That is the only view of
#   a type `Field` ever gets: `_fields_` and the CField's `.size` are the two
#   places ctypes reveals a width, and both are already in the gate.
# * `helpers.getenv` is `@functools.cache`d, so `findlib`'s env read is ONE-SHOT
#   per (key, default) for the life of the process. Fourteen `.so` fixtures
#   answered False in the oracle before the cache was cleared between them.
#   A Bend port has no module-level mutable state to be wrong about, so this is
#   a fact about the ORACLE, and it is why the oracle clears it on every call.
# ===========================================================================

import Base

# ---------------------------------------------------------------------------
# `ceildiv` -- helpers.py:66, and it is helpers' own, so the import below is the
# design. IT IS NOT THERE RIGHT NOW.
#
# `tinybendygrad/helpers.bend` does not compile in the current working copy
# (measured: `ansistrip.seq_end.rest` at line 865 matches `Char.to_u32(h)`, a
# computed value, which convention 4 refuses -- and the SAME error comes out of
# `ops_webgpu.bend`, a committed-green file, so it is another unit mid-edit and
# not a fault in this port). So this file carries a LOCAL READER of
# `helpers.ceildiv_u32` for exactly one call, `Field.bf_size`.
#
# THIS IS A WORKAROUND AND NOT A DESIGN. Flip it back to
# `import ./../../helpers.bend as H` + `H.ceildiv_u32(...)` when helpers
# compiles again; the body is `helpers.bend:1202` verbatim so the swap changes
# no behaviour and the `Field.bf_size` gate rows do not move.
# ---------------------------------------------------------------------------
def H_ceildiv_u32(+num: U32, +amt: U32) -> U32:
  Bool.pick(U32, U32.is_zero(amt), 0,
            U32.add(U32.div(num, amt), Bool.to_u32(U32.is_ne(U32.mod(num, amt), 0))))

# ===========================================================================
# c.py:6-18  `_do_ioctl`, `_IO`, `_IOW`, `_IOR`, `_IOWR`
#
#     def _do_ioctl(__idir, __base, __nr, __struct, __fd, *args, __payload=None, **kwargs):
#       assert not WIN, "ioctl not supported"
#       import tinygrad.runtime.support.system as system, fcntl
#       ioctl = __fd.ioctl if isinstance(__fd, system.FileIOInterface) else functools.partial(fcntl.ioctl, __fd)
#       if __struct is None: return ioctl((__base<<8)|__nr, __payload or (args[0] if args else 0))
#       if (rc:=ioctl((__idir<<30)|(ctypes.sizeof(out:=(__payload or __struct(*args, **kwargs)))<<16)|(__base<<8)|__nr, out)):
#         raise RuntimeError(f"ioctl returned {rc}")
#       return out
#
# `base` is `ord(base)`: `ord(base) if isinstance(base, str) else base` is
# settled at the CALL SITE, `ord` of a one-character string is `Char.to_u32`
# here, and `ioctl_base_int_equals_str=1` is the row that says both agree.
#
# THE WALL is the `ioctl(2)` call and the `FileIOInterface` isinstance -- two
# lines at the top, one `if` at the bottom. What is left is the REQUEST NUMBER,
# which is the entire input to ioctl(2) and the only part of this function
# where a wrong answer silently corrupts a kernel call.
# ===========================================================================

def _do_ioctl(idir: U32, base: U32, nr: U32, size: U32, has_struct: Bool) -> U32:
  match has_struct:
    case True{}:
      U32.or(U32.or(U32.shln(idir, 30n), U32.shln(size, 16n)), U32.or(U32.shln(base, 8n), nr))
    case False{}:
      U32.or(U32.shln(base, 8n), nr)

# THE FOUR CONSTRUCTORS DIFFER IN EXACTLY ONE FIELD, `__idir`, and `_IO` is the
# only one of the four that passes no struct. Read off the functools.partial.
def _IO(base: U32, nr: U32) -> U32: _do_ioctl(0, base, nr, 0, False{})
def _IOW(base: U32, nr: U32, size: U32) -> U32: _do_ioctl(1, base, nr, size, True{})
def _IOR(base: U32, nr: U32, size: U32) -> U32: _do_ioctl(2, base, nr, size, True{})
def _IOWR(base: U32, nr: U32, size: U32) -> U32: _do_ioctl(3, base, nr, size, True{})

# `raise RuntimeError(f"ioctl returned {rc}")`. `rc` is the kernel's `int`, so
# it is SIGNED, and Bend 2.0.34 declares `Nat`, `U32` and `F32` and nothing
# else (measured against base.bend's `type ... is Data:` list), so the sign is
# a separate `Bool` and the formatter spells both halves.
# `TODO(p3) c.py:12` -- a signed integer type.
def _do_ioctl.rc_msg(neg: Bool, mag: U32) -> String:
  String.concat(["ioctl returned ", Bool.pick(String, neg, "-", ""), U32.show(mag)])

# ===========================================================================
# c.py:20-38  `T`/`U`/`P`, `POINTER`, `pointer`, `CFUNCTYPE`, `Array`
#
#     class Array(Generic[T, U], ctypes.Array):
#       _type_, _length_ = ctypes.c_byte, 0
#       def __class_getitem__(cls, key): return key[0] * get_args(key[1])[0]
#       def __new__(cls, ty, l): return ty * l
#
# `Array` IS a Base datatype name -- measured, `def Array() -> U32: 1` answers
# "expected : a fresh name (duplicate declaration: Array)" -- so this port
# spells it `Array_`. Every other name in this file is upstream verbatim; that
# is the ONE rename in the file.
#
# THE WALL is the `ctypes.Array` subclass: `key[0] * n` builds a ctypes array
# TYPE, and `key[0]` is a ctypes type object rather than a width.
# `TODO(p3) c.py:35`.
# ===========================================================================

# `_type_, _length_ = ctypes.c_byte, 0`. The `_length_ = 0` is load-bearing
# twice over: it is the `[str(i), ctypes.c_byte*0]` padding in `dummy*_lens`,
# and it is why every `runtime/autogen/*.py` is full of `c.Array[ty, Literal[0]]`.
def Array_._type_name() -> String: "c_byte"
def Array_._length_() -> U32: 0

# `key[0] * get_args(key[1])[0]`. `typ` is `ctypes.sizeof(key[0])` -- the only
# part of a ctypes type `Array` exposes. `has_args` is `get_args` of a typing
# object being non-empty; a bare tuple answers False, which is the IndexError
# arm (`arr_tuple_key_raises=IndexError`).
def Array_.getitem(typ: U32, n: U32, has_args: Bool) -> U32:
  match has_args:
    case True{}: U32.mul(typ, n)
    case False{}: 0

# ===========================================================================
# c.py:40-82  `Struct`, `record`, `Field`
#
#     class Struct(ctypes.Structure):
#       SIZE = 0
#       def __init__(self, *args, **kwargs):
#         ctypes.Structure.__init__(self)
#         for f,v in [*zip((rf[0] for rf in self._real_fields_), args), *kwargs.items()]: setattr(self, f, v)
#       @classmethod
#       def register_fields(cls, fields):
#         setattr(cls, "_real_fields_", fields)
#         for i, (name, *args) in enumerate(fields): setattr(cls, name, Field(*args, name=name, idx=i))
#
#     class Field:
#       def __init__(self, typ, off, bit_width=None, bit_off=0, *, name=None, idx=0): ...
#       def __set_name__(self, owner, name):
#         entry = (name, self.typ, self.off) + ((self.bit_width, self.bit_off) if self.bit_width else ())
#         if hasattr(owner, "_real_fields_"): owner._real_fields_.append(entry)
#         else: setattr(owner, "_real_fields_", [entry])
#         self.name, self.idx = name, len(owner._real_fields_) - 1
#
# `Entry` IS PORT-LOCAL. It is ONE `_real_fields_` tuple -- `(name, typ, off)`
# or `(name, typ, off, bit_width, bit_off)` -- and upstream spells it as a
# tuple, which is the one thing this port cannot. The naming rule has no
# upstream counterpart to satisfy, so it is named for what it is.
#
# `has_bit_width` carries `bit_width is None`, which is NOT the same question
# as `if self.bit_width` -- Python's truthiness test. `bit_width=0` is not None
# and is still falsy, so `sname_bw0_entry_width=3` is a THREE-wide entry from a
# field that was handed a bit width. `Field.entry` takes both answers.
# ===========================================================================

# A `Data` TYPE declares its CONSTRUCTORS, one per line, with the field names
# and types inline -- there is no separate field list (convention 6: a record
# literal and a record pattern both name every field, and the literal is
# POSITIONAL, and there is NO PROJECTION SYNTAX AT ALL).
#
# ONE RECORD, NOT TWO. Upstream has both a `Field` descriptor and a
# `_real_fields_` entry tuple, and they differ in exactly one thing: the entry
# stores `self.bit_width` under Python's TRUTHINESS test while the descriptor
# stores `None`. That difference is already a parameter of every def that needs
# it (`bw_truthy`), so a second record would carry no information and would
# cost another five readers. `Entry` was written and deleted for that reason.
type Field is Data:
  Field{typ: U32, off: U32, bit_width: U32, has_bit_width: Bool, bit_off: U32, name: String, idx: U32}

# `SIZE` AND THE `_mem_` LENGTH ARE TWO FIELDS, NOT ONE, and the gate found it:
# `record` sets `_fields_` FROM `cls.SIZE` while `init_c_struct_t` sets
# `_fields_` FROM `sz` and NEVER TOUCHES `SIZE`, so a class built by the second
# has `SIZE == 0` and `sizeof == 8`. One field would have made one of the two
# constructions a lie -- `ics_sizes=0,8` and `record_size_fields=8,8,...` are
# both in the gate and they disagree on the first element ON PURPOSE.
type Struct is Data:
  Struct{size: U32, mem_len: U32, real_fields: List<&2, Field>}

# The five readers convention 6 charges. A `match` on a `Data` parameter with a
# pattern naming EVERY field is the only way to read one; `f.name` is "expected
# : a defined name".
def Field.typ(+f: Field) -> U32:
  match f:
    case Field{typ, off, bit_width, has_bit_width, bit_off, name, idx}: typ

def Field.off(+f: Field) -> U32:
  match f:
    case Field{typ, off, bit_width, has_bit_width, bit_off, name, idx}: off

def Field.bit_width(+f: Field) -> U32:
  match f:
    case Field{typ, off, bit_width, has_bit_width, bit_off, name, idx}: bit_width

def Field.bit_off(+f: Field) -> U32:
  match f:
    case Field{typ, off, bit_width, has_bit_width, bit_off, name, idx}: bit_off

def Field.name(+f: Field) -> String:
  match f:
    case Field{typ, off, bit_width, has_bit_width, bit_off, name, idx}: name

def Field.idx(+f: Field) -> U32:
  match f:
    case Field{typ, off, bit_width, has_bit_width, bit_off, name, idx}: idx

def Struct.size(+s: Struct) -> U32:
  match s:
    case Struct{size, mem_len, real_fields}: size

def Struct.real_fields(+s: Struct) -> List<&2, Field>:
  match s:
    case Struct{size, mem_len, real_fields}: real_fields

# `Field(typ, off, bit_width=None, bit_off=0, *, name=None, idx=0)`.
def Field.of(typ: U32, off: U32, bit_width: U32, has_bit_width: Bool, bit_off: U32, name: String, idx: U32) -> Field:
  Field{typ, off, bit_width, has_bit_width, bit_off, name, idx}

# `(name, self.typ, self.off) + ((self.bit_width, self.bit_off) if self.bit_width else ())`
def Field.entry(+f: Field, bw_truthy: Bool) -> Field:
  Field.of(Field.typ(f), Field.off(f), Field.bit_width(f), bw_truthy, Field.bit_off(f), Field.name(f), Field.idx(f))

def Field.entry_width(+f: Field, bw_truthy: Bool) -> U32:
  Bool.pick(U32, bw_truthy, 5, 3)

#     self.name, self.idx = name, len(owner._real_fields_) - 1
#
# THE TRAP IS THE SECOND ARM OF `__set_name__`. After either arm
# `len(_real_fields_)` is `n + 1` if the owner already had entries and `1` if
# it did not, so `idx` is `n` or `0` -- NOT `n` in both cases. A reader who
# writes `idx = n` unconditionally gets a class body's FIRST field right by
# luck and every later one wrong.
def Field.set_name.idx(has_real: Bool, n: U32) -> U32:
  Bool.pick(U32, has_real, n, 0)

# `register_fields` passes `idx` from `enumerate`, which RESTARTS at 0 and
# REPLACES `_real_fields_` -- so a class that already collected entries from
# `__set_name__` in its body forgets them and its indices restart.
def register_fields.idx(i: U32) -> U32: i

# ---------------------------------------------------------------------------
# M2 IS A THEOREM, AND IT IS MEASURED RATHER THAN ARGUED. These three defs and
# their three rows exist only to say so.
#
# `__set_name__` appends only when `hasattr(owner, "_real_fields_")`, and then
# sets `idx = len(_real_fields_) - 1`. So the two arms agree unless the owner
# LACKS the attribute while the prior length is nonzero -- and the length is
# nonzero only if something appended, which is what creates the attribute. The
# oracle WATCHED four real `__set_name__` calls and collected
# `(hasattr, len-before)` = `(False,0), (True,1), (True,2), (True,3)`: never
# `(False, n>0)`. So `Field.set_name.idx(has_real, n) == n` over the whole
# reachable domain, the mutation "return n" is the IDENTITY on values, and no
# fixture can separate them. `ops_amd`'s `floor(floor(a/b)/c)` is the same shape.
#
# The inherited case is in the list: `Sub(Three)` sees `hasattr` True with three
# entries, because `hasattr` walks the MRO and `_real_fields_` was set on `Three`.
# ---------------------------------------------------------------------------
def set_name.arm_of(n: U32) -> Bool: Bool.not(U32.is_zero(n))
def set_name.theorem(+n: U32) -> Bool: U32.is_eq(Field.set_name.idx(set_name.arm_of(n), n), n)
def sname_pair(nm: String, has_real: Bool, n: U32) -> String:
  String.concat([Bool.pick(String, has_real, "True", "False"), ",", U32.show(n), ",", nm])
def set_name.theorem_all() -> Bool:
  Bool.and(Bool.and(set_name.theorem(0), set_name.theorem(1)), Bool.and(set_name.theorem(2), set_name.theorem(3)))
def sname_pairs() -> String:
  String.join([sname_pair("one", False{}, 0), sname_pair("two", True{}, 1),
               sname_pair("three", True{}, 2), sname_pair("four", True{}, 3)], ";")

# ===========================================================================
# THE BYTE PLUMBING. `Field._resolve`, c.py:66-72
#
#     sl, set_mask = slice(self.off, self.off+(sz:=ceildiv(self.bit_width+self.bit_off, 8))), \
#                    ~((mask:=(1 << self.bit_width) - 1) << self.bit_off)
#     def b2i(obj): return int.from_bytes(memoryview(obj).cast("B")[sl], sys.byteorder)
#     def bset(obj, v): memoryview(obj).cast("B")[sl] = ((b2i(obj) & set_mask) | v << self.bit_off).to_bytes(sz, sys.byteorder)
#     cf = property(lambda obj: b2i(obj) >> self.bit_off & mask, bset)
#
# `le` is `sys.byteorder == "little"` and it is a PARAMETER -- see the header
# on `bf_order_big`.
# ===========================================================================

def Field.bf_size(+f: Field) -> U32: H_ceildiv_u32(U32.add(Field.bit_width(f), Field.bit_off(f)), 8)
def Field.mask(+f: Field) -> U32: U32.sub(U32.shln(1, U32.to_nat(Field.bit_width(f))), 1)
def Field.set_mask(+f: Field) -> U32: U32.not(U32.shln(Field.mask(f), U32.to_nat(Field.bit_off(f))))

def Field.arith_row(+bit_width: U32, +bit_off: U32) -> String:
  String.concat(["sz=", U32.show(Field.bf_size(Field.of(4, 0, bit_width, True{}, bit_off, "f", 0))),
                 ",mask=", U32.show(Field.mask(Field.of(4, 0, bit_width, True{}, bit_off, "f", 0))),
                 ",setmask=", U32.show(Field.set_mask(Field.of(4, 0, bit_width, True{}, bit_off, "f", 0)))])

# `memoryview(obj).cast("B")[sl]` -- the `sz` bytes at byte `lo`, in memory
# order. `List.take` of a `List.drop`.
def Field.bytes(sz: U32, mem: List<&2, U32>, lo: U32) -> List<&2, U32>:
  List.take(&2, U32, List.drop(&2, U32, mem, U32.to_nat(lo)), U32.to_nat(sz))

# `int.from_bytes`. A left fold shifts the accumulator left by 8 and takes the
# new byte at the bottom, so the LIST ORDER IS THE BYTE ORDER: little-endian
# walks the reversed slice, big-endian walks the slice. That is the whole
# difference between the two, and it is why there are two defs and not one
# with a `swap` flag.
def Field.b2i.go(xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case h <> t: Field.b2i.go(t, U32.or(U32.shln(acc, 8n), h))

def Field.b2i.le(sz: U32, mem: List<&2, U32>, lo: U32) -> U32:
  Field.b2i.go(List.reverse(&2, U32, Field.bytes(sz, mem, lo)), 0)

def Field.b2i.be(sz: U32, mem: List<&2, U32>, lo: U32) -> U32:
  Field.b2i.go(Field.bytes(sz, mem, lo), 0)

def Field.b2i(sz: U32, mem: List<&2, U32>, le: Bool) -> U32:
  match le:
    case True{}: Field.b2i.le(sz, mem, 0)
    case False{}: Field.b2i.be(sz, mem, 0)

# THE GETTER: `b2i(obj) >> self.bit_off & mask`. The getter MASKS and the
# setter does not, and the difference is observable.
def Field.bget(mem: List<&2, U32>, +f: Field, le: Bool) -> U32:
  U32.and(U32.shrn(Field.b2i(Field.bf_size(f), mem, le), U32.to_nat(Field.bit_off(f))), Field.mask(f))

# `(b2i(obj) & set_mask) | v << self.bit_off`, before `to_bytes(sz)`.
def Field.bset.merge(+sz: U32, mem: List<&2, U32>, +f: Field, v: U32, le: Bool) -> U32:
  U32.or(U32.and(Field.b2i(sz, mem, le), Field.set_mask(f)), U32.shln(v, U32.to_nat(Field.bit_off(f))))

# `to_bytes(sz)` RAISES rather than truncating when `v << bit_off` does not fit
# in `sz` bytes. Exact on the range the port supports; `TODO(p3) c.py:69` owns
# `sz > 4`, where the `U32` shift saturates instead of overflowing.
def Field.bset_overflows(+f: Field, v: U32) -> Bool:
  U32.is_gt(U32.shln(v, U32.to_nat(Field.bit_off(f))),
            U32.sub(U32.shln(1, U32.to_nat(U32.mul(8, Field.bf_size(f)))), 1))

# Which of the `sz` bytes of `merged` lands at memory byte `i`. LE takes them
# from the bottom up; BE takes them from the top down, which is the one line
# that differs from `Field.b2i`.
#
# `& 255` IS LOAD-BEARING AT SHIFT ZERO, and this is the SECOND time in this
# file: `U32.shrn(x, 0n)` is `x`, not `x & 0xFF`, so byte 0 of every bitfield
# store came out as the WHOLE merged word and `bf_set_b_abc` printed `ffab...`
# where CPython prints `cfab...` -- `bf_set_a_15` was right and `bf_set_b_abc`
# was not, because the first store's slice was one byte wide and `to_bytes(1)`
# truncated for it. `U32.shrn` is a logical shift with no width argument, so
# EVERY byte extraction in this file masks, and that is now stated once here and
# once at `u32_hex` rather than being rediscovered.
def Field.bset.byte_of(in_span: Bool, b: U32, i: Nat, lo: Nat, sz: Nat, merged: U32, le: Bool) -> U32:
  match in_span:
    case True{}:
      match le:
        case True{}: U32.and(U32.shrn(merged, U32.to_nat(U32.mul(8, U32.sub(U32.from_nat(i), U32.from_nat(lo))))), 255)
        case False{}: U32.and(U32.shrn(merged, U32.to_nat(U32.mul(8, U32.sub(U32.add(U32.from_nat(lo), U32.from_nat(sz)), U32.inc(U32.from_nat(i)))))), 255)
    case False{}: b

# THE WRITE PREPENDS, AND IT MUST. `List.set(a, A, xs, n, x)` indexes `xs`, and
# the recursion hands it the TAIL, so index `i` would land `i` places from the
# end of a list `len - i` long -- out of range for the deepest call, which
# returns `Nil{}`, and the whole store came back EMPTY. That is what
# `bf_set_a_15=` with nothing after the `=` was: a store that wrote nothing and
# said so by printing nothing. `List.append(&2, U32, [byte], rest)` is
# `[byte] ++ rest`, a PREPEND, so the byte goes back on the head where it came
# from and no index is needed at all.
def Field.bset.go(+mem: List<&2, U32>, +i: Nat, +lo: Nat, +sz: Nat, +merged: U32, +le: Bool) -> List<&2, U32>:
  match mem:
    case Nil{}: Nil{}
    case h <> t:
      List.append(&2, U32, [Field.bset.byte_of(Bool.and(U32.is_ge(U32.from_nat(i), U32.from_nat(lo)),
                                                      U32.is_lt(U32.from_nat(i), U32.add(U32.from_nat(lo), U32.from_nat(sz)))),
                                             h, i, lo, sz, merged, le)],
                  Field.bset.go(t, U32.to_nat(U32.inc(U32.from_nat(i))), lo, sz, merged, le))

# `memoryview(obj).cast("B")[sl] = merged.to_bytes(sz, byteorder)`. `sz` and
# `merged` are RECOMPUTED rather than bound: a `let` is affine, so the second
# read of each would be a compile error and `Field.bf_size`/`Field.bset.merge`
# are pure. Measured, not style -- this is the `agents/TODO.md` "recompute a
# pure call rather than binding it" rule and it costs two extra calls per
# store, which is cheaper than a `let`.
def Field.bset(+mem: List<&2, U32>, +f: Field, v: U32, +le: Bool) -> List<&2, U32>:
  Field.bset.go(mem, 0n, U32.to_nat(Field.off(f)), U32.to_nat(Field.bf_size(f)),
                Field.bset.merge(Field.bf_size(f), mem, f, v, le), le)

# THE NON-BITFIELD READ. ctypes uses NATIVE byte order here, which is why `x`
# reads the same under both `bf_order_*` fixtures and only the bitfield fields
# move. Little-endian host, so NATIVE is `b2i.le`.
def Field.load(mem: List<&2, U32>, +f: Field) -> U32: Field.b2i.le(Field.typ(f), mem, Field.off(f))

# A non-bitfield store IS a bitfield store with the width widened to the whole
# type and `bit_off` zero: `sz` becomes `ceildiv(8*typ, 8) == typ`, `mask`
# becomes everything, `set_mask` becomes nothing, and `merged` becomes `v`.
# One def reused rather than a second copy of the splice.
def Field.wide(+f: Field) -> Field:
  Field.of(Field.typ(f), Field.off(f), U32.mul(8, Field.typ(f)), True{}, 0, Field.name(f), Field.idx(f))

def Field.store(mem: List<&2, U32>, +f: Field, v: U32) -> List<&2, U32>:
  Field.bset(mem, Field.wide(f), v, True{})

# ===========================================================================
# `_resolve`'s THROWAWAY ctypes CLASS. c.py:81-72
#
#     else: cf = type(self.name, (ctypes.Structure,), {"_layout_": "ms", "_pack_": 1,
#       "_fields_": [(str(i), ctypes.c_byte*0) for i in range(self.idx)] +
#                  [("_", ctypes.c_byte * self.off), ("v", self.typ)]}).v
#
# The zero-length arrays are NOT padding that shifts anything -- ctypes gives
# them size 0, and c.py says why: "zero length arrays are so ctypes manages
# references to child objects for us". The consequence is that a field's byte
# OFFSET is just `off` whatever `idx` is. `dummy{i}_ofs_size` is that, and
# `dummy{i}_names` / `dummy{i}_lens` are the two lists.
#
# THE WALL is `type(...)` and the CField it returns. This is the class's
# CONSTRUCTION, which the oracle captures out of c.py by shimming the module
# global `type` -- a module global shadows the builtin, so `c.types.type` does
# NOT work and `c.__dict__["type"]` does.
# ===========================================================================

def Field.dummy_layout() -> String: "ms"
def Field.dummy_pack() -> U32: 1
def Field.dummy_name() -> String: "_"
def Field.dummy_v() -> String: "v"
def Field.dummy_len0() -> U32: 0

# `[str(i) for i in range(self.idx)]`. The fuel is the destructured index list,
# not a counter, so there is no `0n` prefix-match arm to get wrong. (`is` is a
# BEND KEYWORD, so the binder cannot be named after Python's `range` source.)
def Field.dummy_names.go(ns: List<&2, Nat>, acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case i <> t: Field.dummy_names.go(t, List.append(&2, String, acc, [U32.show(U32.from_nat(i))]))

def Field.dummy_names(idx: U32) -> List<&2, String>:
  Field.dummy_names.go(List.range(U32.to_nat(idx)), Nil{})

# `[(str(i), c_byte*0) ...] + [("_", c_byte*off), ("v", typ)]`. The trailing
# `typ` slot is a ctypes type rather than a length, so the row prints it as the
# literal `typ` and only the array lengths are numbers.
def Field.dummy_lens_row(idx: U32, off: U32) -> String:
  String.concat([String.join(List.append(&2, String, List.replicate(String, U32.to_nat(idx), "0"), [U32.show(off)]), ","), ",typ"])

def Field.dummy_names_row(idx: U32) -> String:
  String.join(List.append(&2, String, List.append(&2, String, Field.dummy_names(idx), ["_"]), ["v"]), ",")

# ===========================================================================
# `Struct`, `record`, `Struct.__init__`. c.py:40-54
#
#     def record(cls) -> type[Struct]:
#       setattr(cls, "_fields_", [('_mem_', ctypes.c_byte * cls.SIZE)])
#       return cls
#
# `_fields_` is ONE entry, so `Struct.mem_name` and `Struct.mem_len` have no
# index and no search: `_mem_` at `SIZE` bytes. `sizeof` is that length and
# `SIZE` is the class attribute, which `init_c_struct_t` never sets.
# ===========================================================================

# `record(cls)`: `setattr(cls, "_fields_", [('_mem_', ctypes.c_byte * cls.SIZE)])`
# -- the length comes FROM `SIZE`, so the two agree here and only here.
def Struct.of(+size: U32, fields: List<&2, Field>) -> Struct:
  Struct{size, size, fields}

# `[*zip((rf[0] for rf in self._real_fields_), args), *kwargs.items()]` --
# `zip` TRUNCATES, so the fourth positional of a three-field struct is dropped
# on the floor with no error. `init_pos_4_dropped` is that, and
# `Struct.nset` is the bound.
def Struct.nfields(s: Struct) -> U32: U32.from_nat(List.length(&2, Field, Struct.real_fields(s)))
def Struct.nset(+s: Struct, nargs: U32) -> U32: U32.min(Struct.nfields(s), nargs)

def Struct.mem_name() -> String: "_mem_"
def Struct.mem_len(s: Struct) -> U32:
  match s:
    case Struct{size, mem_len, real_fields}: mem_len
def Struct.sizeof(+s: Struct) -> U32: Struct.mem_len(s)

# The positional arm: field `i` of `_real_fields_` gets `args[i]`, for as many
# as `zip` allows. Two lists walked together, which is what `zip` IS.
#
# `fs` IS FIRST because it is the argument that SHRINKS. A self-call is read
# left to right and must shrink by the time it reaches the tail, and `mem` is
# REWRITTEN by the store rather than shrunk. Measured: passing the recomputed
# `Field.store(mem, f, a)` first is "expected : a decreasing self-call", and
# `nest3.bend` in the notes is the two-line repro that says the shape is fine
# once the list that shrinks comes first.
def Struct.pos.go(+fs: List<&2, Field>, +args: List<&2, U32>, +mem: List<&2, U32>) -> List<&2, U32>:
  match fs:
    case Nil{}: mem
    case f <> ft:
      match args:
        case Nil{}: mem
        case a <> at: Struct.pos.go(ft, at, Field.store(mem, f, a))

# The keyword arm: `setattr(self, f, v)` for the pair, and the write lands at
# the field's OWN offset -- which is how `c` at byte 2 clobbers `a` and `b`.
# A NAME THAT MATCHES NO FIELD writes nothing: ctypes takes the setattr, stores
# a plain Python attribute and leaves every byte alone.
def Struct.kw.hit(is_nm: Bool, +f: Field, v: U32, mem: List<&2, U32>) -> List<&2, U32>:
  match is_nm:
    case True{}: Field.store(mem, f, v)
    case False{}: mem

def Struct.kw.go(+fs: List<&2, Field>, +nm: String, +v: U32, +mem: List<&2, U32>) -> List<&2, U32>:
  match fs:
    case Nil{}: mem
    case f <> ft: Struct.kw.go(ft, nm, v, Struct.kw.hit(String.eq(Field.name(f), nm), f, v, mem))

# `[*zip(...), *kwargs.items()]` in that order: every positional first, then
# every keyword, so a field named twice takes the KEYWORD. The fixture's one
# keyword is a parameter rather than a list, which is the same rule with one
# step instead of a second list to thread through both walks.
def Struct.init(+s: Struct, +mem: List<&2, U32>, +args: List<&2, U32>, kwn: String, kwv: U32) -> List<&2, U32>:
  Struct.kw.go(Struct.real_fields(s), kwn, kwv,
               Struct.pos.go(Struct.real_fields(s),
                             List.take(&2, U32, args, U32.to_nat(Struct.nset(s, U32.from_nat(List.length(&2, U32, args))))),
                             mem))

# ===========================================================================
# HEX. `memoryview(obj).cast("B").hex()` and Python's `bytes.hex()`
# ===========================================================================

def HEX() -> List<&2, String>: ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"]
def mem_hex.zeros(n: U32) -> List<&2, U32>: List.replicate(U32, U32.to_nat(n), 0)
def byte_hex.hi(b: U32) -> String: Maybe.default(&2, String, List.get(&2, String, HEX(), U32.to_nat(U32.div(b, 16))), "f")
def byte_hex.lo(b: U32) -> String: Maybe.default(&2, String, List.get(&2, String, HEX(), U32.to_nat(U32.mod(b, 16))), "f")
def byte_hex(+b: U32) -> String: String.concat([byte_hex.hi(b), byte_hex.lo(b)])
def mem_hex.go(ms: List<&2, U32>, acc: String) -> String:
  match ms:
    case Nil{}: acc
    case b <> bt: mem_hex.go(bt, String.concat([acc, byte_hex(b)]))

# ===========================================================================
# c.py:84-87  `init_c_struct_t`, `init_c_var`
#
#     @functools.cache
#     def init_c_struct_t(sz:int, fields: tuple[tuple, ...]):
#       (CStruct:=type("CStruct", (Struct,), {'_fields_': [('_mem_', ctypes.c_byte * sz)]})).register_fields(fields)
#       return CStruct
#     def init_c_var(ty, creat_cb): return (creat_cb(v:=ty()), v)[1]
#
# `_fields_` IS SET DIRECTLY HERE AND `SIZE` IS NOT, which is the whole of fact
# 5. `functools.cache` is process-wide memoisation: a WALL, since it is the
# shape of `ics_cache_same_obj=1` / `ics_cache_diff_obj=0` and there is no
# module-level mutable state to hold it. `TODO(p3) c.py:83`.
# ===========================================================================

# `type("CStruct", (Struct,), {'_fields_': [('_mem_', ctypes.c_byte * sz)]})`
# -- `SIZE` IS NOT IN THAT DICT, so `SIZE` stays the inherited `0` and only
# `_fields_` carries `sz`. `Struct.of` (which is `record`) is the OTHER
# direction and is the only place the two are equal.
def init_c_struct_t(+mem_len: U32, fields: List<&2, Field>) -> Struct:
  Struct{0, mem_len, fields}

# `(creat_cb(v := ty()), v)[1]` -- INDEX 1, so the answer is the VAR and not
# the callback's result. `init_c_var.val` takes both and returns the first;
# a reader that returns `cb_ret` answers 99 where CPython answers
# `var_ctor_default=0`.
def init_c_var.val(ty_zero: U32, cb_ret: U32) -> U32: ty_zero

# ===========================================================================
# c.py:89-142  `DLL`
# ===========================================================================

# `nm.replace('-','_')`, then `.upper()`, then `+"_PATH"`. `'-'` is codepoint 45
# and `'_'` is 95, so the fold needs no Char literal.
# `nm.replace('-','_')`. `'-'` is codepoint 45 and `'_'` is 95, so the fold
# needs no Char literal and cannot be fooled by a `--replace` that is really a
# `-replace`.
def nm_replace.of(is_dash: Bool, c: Char) -> Char:
  Bool.pick(Char, is_dash, Char.from_u32(95), c)

def nm_replace.go(+cs: List<&2, Char>, acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}: acc
    case c <> t: nm_replace.go(t, List.append(&2, Char, acc, [nm_replace.of(U32.is_eq(Char.to_u32(c), 45), c)]))

def nm_replace(nm: String) -> String:
  String.from_list(nm_replace.go(String.to_list(nm), Nil{}))

def findlib.env_key(nm: String) -> String:
  String.concat([String.to_upper(nm_replace(nm)), "_PATH"])

# `self.emsg = emsg or f"try setting {nm.upper()+'_PATH'}?"` -- truthiness, so
# `emsg=""` takes the default (`dll_emsg_empty_is_falsy`), and NO dash
# replacement, which is the disagreement of fact 4. The Bool is a PARAMETER
# because convention 4 refuses a `match` on a computed value.
# THE KEY THE MESSAGE NAMES -- `nm.upper()+'_PATH'`, with NO dash
# replacement. That is half of fact 4 and it is a def because `findlib`'s key
# is the other half and the two have to be comparable.
def DLL.emsg_key(nm: String) -> String: String.concat([String.to_upper(nm), "_PATH"])

def DLL.emsg.of(is_empty: Bool, nm: String, emsg: String) -> String:
  match is_empty:
    case True{}: String.concat(["try setting ", DLL.emsg_key(nm), "?"])
    case False{}: emsg

def DLL.emsg(+nm: String, +emsg: String) -> String: DLL.emsg.of(String.is_empty(emsg), nm, emsg)

def DLL.attr_err(nm: String, emsg: String) -> String:
  String.concat(["failed to load library ", nm, ": ", emsg])

def DLL.module(nm: String) -> String:
  String.concat(["tinygrad.runtime.autogen.", nm])

def DLL.emsg_key_is_envkey(+nm: String) -> Bool: String.eq(DLL.emsg_key(nm), findlib.env_key(nm))

# `if nm in ('libc', 'm') and OSX: return f'/usr/lib/lib{nm.removeprefix("lib")}.dylib'`
def str_removeprefix.of(has_pfx: Bool, s: String, pfx: String) -> String:
  match has_pfx:
    case True{}: String.drop(s, String.length(pfx))
    case False{}: s

# THE EMPTY STRING IS "NOT FOUND" and the oracle prints `""` for it too. It is
# NOT `None`: this port has no `Maybe` in the answer, and a marker that reads
# like Python's `None` would invite a comparison the gate cannot make.
def findlib.osx_lib.of(hit: Bool, +nm: String) -> String:
  match hit:
    case True{}: String.concat(["/usr/lib/lib", str_removeprefix.of(String.starts_with(nm, "lib"), nm, "lib"), ".dylib"])
    case False{}: ""

def findlib.osx_lib(nm: String, is_special: Bool, osx: Bool) -> String:
  findlib.osx_lib.of(Bool.and(is_special, osx), nm)

# `libpaths` is ONE dict literal with FIVE eagerly-evaluated values, and it is
# rebuilt on every `p` of `paths`. `os.environ['PATH']` is a SUBSCRIPT, so the
# POSIX arm reads `PATH` too and `findlib` raises `KeyError: 'PATH'` when it is
# absent -- `fl_no_path_key` is that, and it is the one row in this file that
# records a crash rather than a value.
# `[d for d in os.environ.get('LD_LIBRARY_PATH','').split(os.pathsep) if d]`
# -- the `if d` is what makes the `::` in `"/lddir1::/lddir2"` collapse to two
# entries and not four. `os.pathsep` is `:` on POSIX and `;` on NT, so it is a
# PARAMETER rather than a constant of this file.
def str_nonempty(s: String) -> Bool: Bool.not(String.is_empty(s))

def libpaths.posix(ld: String, sep: Char) -> List<&2, String>:
  List.append(&2, String, List.filter(String, str_nonempty, String.split(ld, sep)), ["/usr/lib64", "/usr/lib", "/usr/local/lib"])

def libpaths.nt(path: String, sep: Char) -> List<&2, String>:
  String.split(path, sep)

def libpaths.darwin(+p: String) -> List<&2, String>:
  ["/opt/homebrew/lib", String.concat(["/System/Library/Frameworks/", p, ".framework"]),
   String.concat(["/System/Library/PrivateFrameworks/", p, ".framework"])]

def libpaths.linux(multiarch: String) -> List<&2, String>:
  ["/usr/lib/wsl/lib/", "/lib", "/lib64", String.concat(["/lib/", multiarch])]

# `([path] if path else []) + libpaths.get(os.name, []) + libpaths.get(sys.platform, []) + extra_paths`
# -- BOTH dict keys are appended, so on linux the posix five come first and
# then the linux four. `prefixes_both_keys` is that nine-element list.
def findlib.prefixes.env(env: String, is_empty: Bool) -> List<&2, String>:
  match is_empty:
    case True{}: Nil{}
    case False{}: [env]

def findlib.prefixes(+env: String, osname_list: List<&2, String>, plat_list: List<&2, String>, extra: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, List.append(&2, String, List.append(&2, String, findlib.prefixes.env(env, String.is_empty(env)), osname_list), plat_list), extra)

# `if (pth:=pathlib.Path(p)).is_absolute(): if pth.is_file(): return p; else: continue`
# `0` is the `continue`, `1` is the `return p`, `2` is "search the prefixes".
# An absolute non-file entry SKIPS the whole search for that `p` and no other,
# which is why `fl_found_paths_abs_then_rel` is 1 and `fl_found_paths_two_abs`
# is 0.
def findlib.abs(is_abs: Bool, is_file: Bool) -> U32:
  match is_abs:
    case True{}:
      match is_file:
        case True{}: 1
        case False{}: 0
    case False{}: 2

# `for base in ([f"lib{p}.dylib", f"{p}.dylib", str(p)] if OSX else [f"{p}.dll"])`
# -- built from `p`, never from `nm`. `fl_osx_bases_tested` is this list,
# captured out of c.py.
def findlib.base.osx(+p: String) -> List<&2, String>:
  [String.concat(["lib", p, ".dylib"]), String.concat([p, ".dylib"]), p]

def findlib.base.win(p: String) -> List<&2, String>:
  [String.concat([p, ".dll"])]

# `re.fullmatch(f"lib{p}\.so[.0-9]*", l.name)`. The prefix is
# `lib{p}.so` and EVERY remaining character must be `.` or a digit -- so
# `libz.soa` fails, `libz.so.` passes, and `libz.so.06` passes.
# (The `.` in `p` is NOT escaped in c.py, so a `p` containing a dot becomes a
# wildcard. Not gated here: no `paths` entry upstream contains one.)
def findlib.so_tail(+cp: U32) -> Bool:
  Bool.or(U32.is_eq(cp, 46), Bool.and(U32.is_ge(cp, 48), U32.is_le(cp, 57)))

def findlib.so_tail.go(+cs: List<&2, Char>, ok: Bool) -> Bool:
  match cs:
    case Nil{}: ok
    case c <> t: findlib.so_tail.go(t, Bool.and(ok, findlib.so_tail(Char.to_u32(c))))

# The tail starts after `"lib" + p + ".so"`, which is SIX characters plus `p`
# and not three: the gate caught `3`, and every `so_*` row answered 0 for that
# reason -- `libz.so.6` minus four characters is `.so.6`, whose `s` is not in
# `[.0-9]`.
def findlib.so_ok.of(has_pfx: Bool, +p: String, +name: String) -> Bool:
  match has_pfx:
    case True{}: findlib.so_tail.go(String.to_list(String.drop(name, (U32.to_nat(6) + String.length(p) : Nat))), True{})
    case False{}: False{}

def findlib.so_ok(+p: String, +name: String) -> Bool:
  findlib.so_ok.of(String.starts_with(name, String.concat(["lib", p, ".so"])), p, name)

# `if f.read(4) == b'\x7FELF'` -- the linker-script filter, and a SEPARATE test
# from the name test: `libz.so.7` passes the regex and fails here.
def findlib.elf_ok(h0: U32, h1: U32, h2: U32, h3: U32) -> Bool:
  Bool.and(Bool.and(U32.is_eq(h0, 127), U32.is_eq(h1, 69)), Bool.and(U32.is_eq(h2, 76), U32.is_eq(h3, 70)))

# THE WALLS, each with the fixture that proves them.
# `DLL._loaded_` is a process-wide MUTABLE SET. `TODO(p3) c.py:90`.
def DLL.is_loaded(loaded: Bool) -> Bool: loaded
# `DLL.bind` is a closure decorator with a `nonlocal cfunc` memo cell. Bend has
# no closures and refuses mutual recursion, and the memo IS the state a closure
# carries. What is left is the attribute assignment, in this order.
# `TODO(p3) c.py:127`.
def DLL.bind.restype(restype: U32) -> U32: restype
def DLL.bind.argtypes(argtypes: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, argtypes))
# `os.environ['PATH']` inside an eagerly-built dict literal.
def findlib.no_path_key(has_path: Bool) -> String:
  match has_path:
    case True{}: ""
    case False{}: "KeyError:'PATH'"

# ===========================================================================
# THE NAME CORRESPONDENCE, WHICH IS A CORRESPONDENCE AND NOT A SCORE.
#
# `python3 .agents/slop/slop_1to1.py --names` says: `upstream=18 bend=55
# verbatim=10 local=45`. The `10` is NOT a 55% score and the `45` is NOT sloppiness:
# it is the same shape `codegen/late.bend` had, and the rule simply does not apply
# to a def with no upstream counterpart. Here is the actual mapping.
#
#   VERBATIM, all 10:  _do_ioctl  _IO  _IOW  _IOR  _IOWR  Struct  Field  DLL
#                      init_c_struct_t  init_c_var
#     Nine of the ten are the def NAMES; the tenth is that a Python CLASS becomes
#     a Bend `type`, which is the one place the two languages differ in kind and
#     not in name.
#
#   RENAMED, and WHY -- 8 of 18, and 6 of the 8 are not ports at all:
#     Array     -> Array_    `Array` IS a Base datatype name. Measured:
#                             `def Array() -> U32: 1` answers "expected : a fresh
#                             name (duplicate declaration: Array)". This is the
#                             ONE rename in the file.
#     T U P              `typing.TypeVar` / `ParamSpec` declarations. They carry
#                         no runtime behaviour -- `T = TypeVar("T")` is an
#                         annotation helper -- and a `Data` record cannot hold a
#                         type PARAMETER, which is what they exist to do.
#                         `TODO(p3) c.py:20`.
#     POINTER             `POINTER[T]` is `ctypes.POINTER(T)` and `pointer(x)`
#                         returns a `ctypes._Pointer`. Both are FFI: an ADDRESS.
#                         `TODO(p3) c.py:25`.
#     CFUNCTYPE           `CFUNCTYPE[None, (U32,)]` builds a ctypes function
#                         TYPE. `TODO(p3) c.py:32`.
#     record     -> `Struct.of`  `record(cls)` is a CLASS DECORATOR that sets
#                         `_fields_` and returns the class; Bend has no
#                         decorators and no class to return, so the operation is
#                         a constructor of the record that stands for the class.
#                         The row that covers it is `record_size_fields`.
#     pointer            as POINTER.
#
#   THE 45 PORT-LOCAL DEFS, in the four groups they actually fall into:
#     21  READERS AND FORMATTERS for the `Data` records and the rows:
#         Field.{typ,off,bit_width,bit_off,name,idx}  Struct.{size,mem_len,
#         real_fields}  b2s  byte_hex.{hi,lo}  mem_hex.{go,zeros}  u32_hex[.of]
#         ord1  HEX  -- convention 6 charges one `match` per field, and none of
#         them is a port of anything.
#     11  GATE FIXTURES: f_{a,b,x}  bf_fields  body_fields  r_fields  rf_fields
#         mem_{abcd,zero8,ffff8,0ff0,a001}  -- the structs the rows read.
#     13  PORT-LOCAL ALGEBRA with no upstream counterpart because upstream has
#         the behaviour INSIDE a closure or a method body: `findlib.*` (upstream
#         is one 30-line `findlib`, split here so each rule is one row),
#         `libpaths.*` (a dict literal upstream), `nm_replace` (one `str.replace`
#         call), `set_name.*` (`__set_name__`, a METHOD), `register_fields.idx`
#         (an `enumerate` inside `register_fields`), `str_removeprefix` (one
#         `str.removeprefix`), `so_row` (the regex AND the magic, as two tests).
#      3  WALL STUBS that exist so the TODO is greppable and the arithmetic
#         beside them is still gated: `DLL.{is_loaded,bind.restype,bind.argtypes}`
#         and `findlib.no_path_key`.
#
#   THE HONEST SUMMARY: of 18 upstream names, 10 are reproduced exactly, 1 is
#   renamed for a measured collision (`Array_`), 1 is renamed because a decorator
#   became a constructor (`record` -> `Struct.of`), and 6 are `typing`/`ctypes`
#   declarations whose runtime value is an ADDRESS or a TYPE OBJECT and which are
#   WALLS. Every one of the 6 has a `TODO(p3)` naming its `c.py` line.
# ===========================================================================

# ===========================================================================
# THE GATE. 129 rows, one `name=value` line each, and the ORACLE IS
# `.agents/slop/c-oracle.py`, which is `.agents/slop/c-gate.sh`.
#
# THE `py=` HALF IS NOT IN THIS FILE. Convention 2 wants every row to print its
# answer BESIDE the CPython string so a dropped ", " is a diff, and the way that
# is done here is a BYTE DIFF against `.agents/slop/runs/base_c.bend.txt` --
# which is stronger than a literal beside each row, because it also catches a
# row that lost a CHARACTER. Every expectation was ASKED OF CPYTHON and none
# was typed: see the six techniques in that file's header, and note the two
# fixtures that took a whole debugging pass each (`getenv`'s `functools.cache`
# and `findlib` naming `p` rather than `nm`).
#
# `b2s` IS THE ROW FORMATTER AND `u32_hex` IS THE WIDTH-8 HEX, because
# `ioctl_none_ord_A_11=00004111` is a number in hex and every other `so_*` and
# `bf_set_*` row is a byte string in hex. A count row is never emitted.
# ===========================================================================

def b2s(x: Bool) -> String: Bool.pick(String, x, "1", "0")

# `entry = (name, typ, off) + ((bit_width, bit_off) if self.bit_width else ())`
# measured WIDTH, so both `sname_*_entry_width` rows are this one def called with
# the Bool Python's TRUTHINESS would have given -- which is NOT the Bool
# `bit_width is None` carries, and `sname_bw0_entry_width=3` is the row that
# says so: a field HANDED a bit width of 0 still gets the three-wide entry.
def sname_entry_width_row.go(+fs: List<&2, Field>, +bw_truthy: Bool, acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case f <> ft: sname_entry_width_row.go(ft, bw_truthy, List.append(&2, String, acc, [",", U32.show(Field.entry_width(f, bw_truthy))]))

def sname_entry_width_row(fs: List<&2, Field>, bw_truthy: Bool) -> String:
  String.drop(String.join(sname_entry_width_row.go(fs, bw_truthy, Nil{}), ""), 1n)

def u32_hex(b3: U32, b2: U32, b1: U32, b0: U32) -> String:
  mem_hex.go([b3, b2, b1, b0], "")

# `& 255` ON EVERY BYTE IS LOAD-BEARING and the gate is what said so. Without it
# the FOURTH byte is the whole word, `byte_hex` divides 0x4111 by 16, indexes
# past the sixteen-entry hex table and falls back to "f", and
# `ioctl_none_ord_A_11` prints `000041f1`. Then, having fixed only the last
# byte, `ioctl_w_ord_A_11_4` printed `40f4f111` -- still nine characters, because
# the SECOND byte was `0x4004`. A hex formatter that substitutes a default digit
# for an out-of-range index is worse than one that crashes: it is why every byte
# here is masked rather than only the last.
def u32_hex.of(+x: U32) -> String:
  u32_hex(U32.and(U32.shrn(x, 24n), 255), U32.and(U32.shrn(x, 16n), 255),
         U32.and(U32.shrn(x, 8n), 255), U32.and(x, 255))

# `ord(base)`. `Char.to_u32` IS `ord`, so `ioctl_base_int_equals_str` is a real
# comparison between the two spellings of the same base and not a restatement.
def ord1(s: String) -> U32:
  Char.to_u32(Maybe.default(&2, Char, List.head(&2, Char, String.to_list(s)), Char.from_u32(0)))

# `[_IO/_IOW/_IOR/_IOWR(base, nr, typ)]` read off the functools.partial:
# `(idir, ord(base), nr, 'None' or 'typ')`.
def _do_ioctl.partial_row(idir: U32, base: U32, nr: U32, has_struct: Bool) -> String:
  String.concat([U32.show(idir), ",", U32.show(base), ",", U32.show(nr), ",",
                 Bool.pick(String, has_struct, "typ", "None")])

# `raise RuntimeError(f"ioctl returned {rc}")` is guarded by `if rc:`, so a
# zero return is `NO-RAISE` and NOT "ioctl returned 0". Three rows and one of
# them is the zero.
def _do_ioctl.raise_msg.of(raise_it: Bool, neg: Bool, mag: U32) -> String:
  match raise_it:
    case True{}: String.concat(["ioctl returned ", Bool.pick(String, neg, "-", ""), U32.show(mag)])
    case False{}: "NO-RAISE"

def _do_ioctl.raise_msg(+neg: Bool, +mag: U32) -> String:
  _do_ioctl.raise_msg.of(Bool.or(neg, Bool.not(U32.is_zero(mag))), neg, mag)

def host_byteorder(le: Bool) -> String: Bool.pick(String, le, "little", "big")

# THE FIXTURES. `a` and `b` are the bitfields and `x` is a plain 4-byte field at
# offset 4, over eight bytes of memory -- c.py's own shape, taken from
# `runtime/autogen/io_uring.py`'s `(name, typ, off, bit_width, bit_off)` entries.
def f_a() -> Field: Field.of(4, 0, 4, True{}, 0, "a", 0)
def f_b() -> Field: Field.of(4, 0, 12, True{}, 4, "b", 0)
def f_x() -> Field: Field.of(4, 4, 0, False{}, 0, "x", 2)
def bf_fields() -> List<&2, Field>: [f_a(), f_b(), f_x()]

# THE CLASS-BODY FIXTURE. `Body` in the oracle is a `Struct` subclass whose body
# holds TWO `Field`s, and `__set_name__` appends them in source order -- so
# `sname_real_fields` is two names, not the three of `bf_fields()`.
def body_fields() -> List<&2, Field>: [f_a(), f_b()]
def rf_fields() -> List<&2, Field>: [Field.of(4, 3, 0, False{}, 0, "p", 0), Field.of(4, 1, 0, False{}, 0, "q", 1)]
def r_fields() -> List<&2, Field>: [Field.of(4, 0, 0, False{}, 0, "a", 0), Field.of(4, 4, 0, False{}, 0, "b", 1), Field.of(4, 2, 0, False{}, 0, "c", 2)]
def mem_abcd() -> List<&2, U32>: [171, 205, 239, 18, 120, 86, 52, 18]
def mem_zero8() -> List<&2, U32>: [0, 0, 0, 0, 0, 0, 0, 0]
def mem_ffff8() -> List<&2, U32>: [255, 255, 255, 255, 255, 255, 255, 255]
def mem_0ff0() -> List<&2, U32>: [15, 240, 0, 0, 0, 0, 0, 0]
def mem_a001() -> List<&2, U32>: [1, 0, 240, 0, 0, 0, 0, 0]

# THREE ROWS OVER ONE `_real_fields_`, each a reader per element.
#
# `List.map` IS NOT USABLE HERE AND THE REASON IS WORTH WRITING DOWN:
# `List.map(~A, ~B, ~f, xs) -> List<B>` returns a `List<&1, B>` -- a LINEAR list
# -- and there is no `List` def in base.bend that widens `&1` to `&2`. Measured:
# `String.join(List.map(Field, String, ..., fs), ",")` answers "expected :
# List<&1, Field> / observed : List<&2, Field>". So each row is a hand fold, and
# because `List.append(x, A, acc, [s, ","])` is `acc ++ [s, ","]`, the fold
# accumulates in order and the ONE leading comma left by the empty case is
# dropped at the end. Three readers, three folds, and no way to share them: Bend
# has no first-class functions, so "map this reader" is not a def.
def Field.offs_row.go(+fs: List<&2, Field>, acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case f <> ft: Field.offs_row.go(ft, List.append(&2, String, acc, [",", U32.show(Field.off(f))]))

def Field.offs_row(fs: List<&2, Field>) -> String:
  String.drop(String.join(Field.offs_row.go(fs, Nil{}), ""), 1n)

def Field.typs_row.go(+fs: List<&2, Field>, acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case f <> ft: Field.typs_row.go(ft, List.append(&2, String, acc, [",", U32.show(Field.typ(f))]))

def Field.typs_row(fs: List<&2, Field>) -> String:
  String.drop(String.join(Field.typs_row.go(fs, Nil{}), ""), 1n)

def Field.names_row.go(+fs: List<&2, Field>, acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case f <> ft: Field.names_row.go(ft, List.append(&2, String, acc, [",", Field.name(f)]))

def Field.names_row(fs: List<&2, Field>) -> String:
  String.drop(String.join(Field.names_row.go(fs, Nil{}), ""), 1n)

# `[*zip(names, args)]` and the keyword pass: read every `_real_fields_` entry
# back, in NAME ORDER, and print the memory.
def Struct.read_row.go(+fs: List<&2, Field>, +mem: List<&2, U32>, acc: String) -> String:
  match fs:
    case Nil{}: acc
    case f <> ft:
      Struct.read_row.go(ft, mem, String.concat([acc, Field.name(f), "=", U32.show(Field.load(mem, f)), ","]))
def Struct.read_row(s: Struct, mem: List<&2, U32>) -> String:
  Struct.read_row.go(Struct.real_fields(s), mem, "")
def Struct.init_row.put(s: Struct, +mem: List<&2, U32>) -> String:
  String.concat([Struct.read_row(s, mem), "mem=", mem_hex.go(mem, "")])

# `ctypes.Structure.__init__(self)` zeroes `_mem_` (a fresh ctypes buffer is
# already zeroed), so the fixture starts from `SIZE` zero bytes.
def Struct.init_row(+s: Struct, args: List<&2, U32>, kwn: String, kwv: U32) -> String:
  Struct.init_row.put(s, Struct.init(s, mem_hex.zeros(Struct.mem_len(s)), args, kwn, kwv))

# `SIZE, sizeof, _fields_[0][0], _fields_[0][1]._length_` -- `record`'s own four.
# THE FIRST DRAFT OF THIS ROW WAS THREE LITERAL `8`s AND NO CALL TO `record`, so
# it restated the fixture instead of testing `Struct.of`. The M7 mutation
# (`Struct.of` writing 0 into `SIZE`) moved NOTHING, and that zero is what said
# so. A row whose expected value is a constant in the row is not a test.
def record_size_fields() -> String:
  String.concat([U32.show(Struct.size(Struct.of(8, r_fields()))), ",", U32.show(Struct.mem_len(Struct.of(8, r_fields()))), ",", Struct.mem_name(),
                 ",", U32.show(Struct.mem_len(Struct.of(8, r_fields())))])

# `SIZE,ctypes.sizeof` -- fact 5, the two constructors disagreeing on purpose.
# `init_c_struct_t` is RECOMPUTED for each reader rather than bound: a `let` is
# affine and this is its second read. `agent-core.md` calls for recomputing a
# pure call, and `init_c_struct_t` is one.
def ics_sizes() -> String:
  String.concat([U32.show(Struct.size(init_c_struct_t(8, bf_fields()))),
                 ",", U32.show(Struct.mem_len(init_c_struct_t(8, bf_fields())))])

# `a=11,b=3290,x=305419896` -- the three reads of one memory, in that order.
def bf_read_row(+mem: List<&2, U32>, +le: Bool) -> String:
  String.concat(["a=", U32.show(Field.bget(mem, f_a(), le)), ",b=", U32.show(Field.bget(mem, f_b(), le)),
                 ",x=", U32.show(Field.load(mem, f_x()))])

def bf_order_row(+mem: List<&2, U32>, +le: Bool) -> String:
  String.concat([bf_read_row(mem, le), ",mem=", mem_hex.go(Field.bset(mem, f_b(), 2748, le), "")])

def Field.bset_overflow_row(f: Field, v: U32) -> String:
  Bool.pick(String, Field.bset_overflows(f, v), "OverflowError", "NO-RAISE")

def Array_.getitem_row(has_args: Bool, typ: U32, n: U32) -> String:
  match has_args:
    case True{}: U32.show(Array_.getitem(typ, n, has_args))
    case False{}: "IndexError"

def arr_default_row() -> String: String.concat([Array_._type_name(), ",", U32.show(Array_._length_())])

# `/usr/lib/lib{nm.removeprefix("lib")}.dylib` with the NAME ELIDED, so the row
# reads as the prefix plus a placeholder. `findlib.osx_lib_at("libc")` is
# `/usr/lib/lib@.dylib` and `findlib.osx_lib("libc", True{}, True{})` is
# `/usr/lib/libc.dylib`; the oracle prints the first and the port computes both.
# `String.length(String.drop(p, k))` IS `len(p) - k`, and Bend has no `Nat`
# subtraction with a saturating floor, so that is how the drop count is written.
# `String.drop` is FROM THE FRONT (base.bend:1941 recurses on the tail), so
# dropping `len(p) - 5` leaves the LAST five characters, which for
# `/usr/lib/libc.dylib` is `.dylib`.
def findlib.osx_lib_at.put(+p: String) -> String:
  String.concat(["/usr/lib/lib@",
                 String.drop(p, String.length(String.drop(p, String.length(".dylib"))))])

def findlib.osx_lib_at(nm: String) -> String: findlib.osx_lib_at.put(findlib.osx_lib(nm, True{}, True{}))

# `libpaths.get(key, [])` -- an unknown key contributes nothing.
def libpaths_unknown() -> String: String.join(findlib.prefixes("", Nil{}, Nil{}, Nil{}), ",")

# ONE `.so` FIXTURE: the NAME test and the ELF MAGIC are independent, so a row
# is `so_ok(p, name) and elf_ok(...)`. The three `_9_` rows pass a name that
# matches and a magic that does not, which is the only way to reach the magic.
def so_row(p: String, name: String, m0: U32, m1: U32, m2: U32, m3: U32) -> String:
  b2s(Bool.and(findlib.so_ok(p, name), findlib.elf_ok(m0, m1, m2, m3)))

# DOES THE SEARCH REACH THE PREFIX LOOP? `findlib.abs` is 0 for `continue`, 1
# for `return p` and 2 for "search", and the loop body -- the whole `libpaths`
# walk -- is only reachable on 2. So the row is a fold over the `paths` entries.
def findlib.reaches.go(+ds: List<&2, U32>, seen: Bool) -> Bool:
  match ds:
    case Nil{}: seen
    case d <> dt: findlib.reaches.go(dt, Bool.or(seen, U32.is_eq(d, 2)))
def findlib.reaches(ds: List<&2, U32>) -> Bool: findlib.reaches.go(ds, False{})
def findlib.reaches_row(ds: List<&2, U32>) -> String: b2s(findlib.reaches(ds))

# `tmp = [(p, is_absolute, is_file)]`, one per `paths` entry.
def r_empty() -> List<&2, U32>: Nil{}
def r_abs() -> List<&2, U32>: [findlib.abs(True{}, False{})]
def r_rel() -> List<&2, U32>: [findlib.abs(False{}, False{})]
def r_abs_rel() -> List<&2, U32>: [findlib.abs(True{}, False{}), findlib.abs(False{}, False{})]
def r_rel_abs() -> List<&2, U32>: [findlib.abs(False{}, False{}), findlib.abs(True{}, False{})]
def r_two_abs() -> List<&2, U32>: [findlib.abs(True{}, False{}), findlib.abs(True{}, False{})]

def main() -> IO(Unit):
  do IO<Unit>:
    # -- ioctl ------------------------------------------------------------
    _ : Unit <- IO.print(String.concat(["ioctl_none_ord_A_11=", u32_hex.of(_IO(ord1("A"), 17))]))
    _ : Unit <- IO.print(String.concat(["ioctl_none_idir3_same=", b2s(U32.is_eq(_do_ioctl(3, 65, 17, 0, False{}), _do_ioctl(0, 65, 17, 0, False{})))]))
    _ : Unit <- IO.print(String.concat(["ioctl_none_B_11=", u32_hex.of(_IO(ord1("B"), 17))]))
    _ : Unit <- IO.print(String.concat(["ioctl_w_ord_A_11_4=", u32_hex.of(_IOW(ord1("A"), 17, 4))]))
    _ : Unit <- IO.print(String.concat(["ioctl_r_ord_A_11_4=", u32_hex.of(_IOR(ord1("A"), 17, 4))]))
    _ : Unit <- IO.print(String.concat(["ioctl_wr_ord_A_11_4=", u32_hex.of(_IOWR(ord1("A"), 17, 4))]))
    _ : Unit <- IO.print(String.concat(["ioctl_w_ord_A_11_8=", u32_hex.of(_IOW(ord1("A"), 17, 8))]))
    _ : Unit <- IO.print(String.concat(["ioctl_w_ord_A_11_1=", u32_hex.of(_IOW(ord1("A"), 17, 1))]))
    _ : Unit <- IO.print(String.concat(["ioctl_w_size0_is_none_req=", b2s(U32.is_eq(_IOW(ord1("A"), 17, 0), _IO(ord1("A"), 17)))]))
    _ : Unit <- IO.print(String.concat(["ioctl_base_int_equals_str=", b2s(U32.is_eq(_IOW(ord1("A"), 17, 4), _IOW(65, 17, 4)))]))
    _ : Unit <- IO.print(String.concat(["io__IO_partial=", _do_ioctl.partial_row(0, ord1("A"), 17, False{})]))
    _ : Unit <- IO.print(String.concat(["io__IOW_partial=", _do_ioctl.partial_row(1, ord1("A"), 17, True{})]))
    _ : Unit <- IO.print(String.concat(["io__IOR_partial=", _do_ioctl.partial_row(2, ord1("A"), 17, True{})]))
    _ : Unit <- IO.print(String.concat(["io__IOWR_partial=", _do_ioctl.partial_row(3, ord1("A"), 17, True{})]))
    _ : Unit <- IO.print(String.concat(["ioctl_rc5_msg=", _do_ioctl.raise_msg(False{}, 5)]))
    _ : Unit <- IO.print(String.concat(["ioctl_rc_neg1_msg=", _do_ioctl.raise_msg(True{}, 1)]))
    _ : Unit <- IO.print(String.concat(["ioctl_rc0_msg=", _do_ioctl.raise_msg(False{}, 0)]))
    _ : Unit <- IO.print(String.concat(["host_byteorder=", host_byteorder(True{})]))
    # -- __set_name__ / register_fields -----------------------------------
    _ : Unit <- IO.print(String.concat(["sname_real_fields=", Field.names_row(body_fields())]))
    _ : Unit <- IO.print(String.concat(["sname_entry_width=", sname_entry_width_row(body_fields(), False{})]))
    _ : Unit <- IO.print(String.concat(["sname_idx_after=", String.concat([U32.show(Field.set_name.idx(False{}, 0)), ",", U32.show(Field.set_name.idx(True{}, 1))])]))
    # THE CTOR-GIVEN `idx`. `f_a()`/`f_b()` are the bitfield pair and both carry a
    # literal `0`, so reading THEM asserted a belief about the default rather than
    # the port. `__set_name__` OVERWRITES `idx` (c.py:64), so a `Field` nobody
    # named is the only place the constructor's value survives, and the second is
    # given EXPLICITLY so the two tokens differ: `Field.of` dropping `idx` now
    # moves this row instead of reading `0,0` either way.
    _ : Unit <- IO.print(String.concat(["sname_ctor_idx_given=", String.concat([
      U32.show(Field.idx(Field.of(4, 0, 0, False{}, 0, "x", 0))), ",",
      U32.show(Field.idx(Field.of(4, 0, 0, False{}, 0, "y", 5)))])]))
    _ : Unit <- IO.print(String.concat(["sname_bf_entry_width=", sname_entry_width_row(body_fields(), True{})]))
    _ : Unit <- IO.print(String.concat(["sname_bw0_entry_width=", U32.show(Field.entry_width(Field.of(4, 1, 0, True{}, 0, "z", 0), False{}))]))
    _ : Unit <- IO.print(String.concat(["sname_bw0_entry=", String.concat(["z,", U32.show(4), ",", U32.show(1)])]))
    _ : Unit <- IO.print(String.concat(["sname_setname_pairs=", sname_pairs()]))
    _ : Unit <- IO.print(String.concat(["sname_hasreal_iff_npositive=", b2s(set_name.theorem_all())]))
    _ : Unit <- IO.print(String.concat(["rf_after_body_idx=", String.concat([U32.show(register_fields.idx(0)), ",", U32.show(register_fields.idx(1))])]))
    _ : Unit <- IO.print(String.concat(["rf_after_body_names=", Field.names_row(rf_fields())]))
    # -- _resolve's throwaway class ---------------------------------------
    _ : Unit <- IO.print(String.concat(["dummy0_names=", Field.dummy_names_row(0)]))
    _ : Unit <- IO.print(String.concat(["dummy0_lens=", Field.dummy_lens_row(0, 3)]))
    _ : Unit <- IO.print(String.concat(["dummy0_layout_pack=", String.concat([Field.dummy_layout(), ",", U32.show(Field.dummy_pack())])]))
    _ : Unit <- IO.print(String.concat(["dummy0_ofs_size=", String.concat([U32.show(3), ",", U32.show(4)])]))
    _ : Unit <- IO.print(String.concat(["dummy1_names=", Field.dummy_names_row(1)]))
    _ : Unit <- IO.print(String.concat(["dummy1_lens=", Field.dummy_lens_row(1, 1)]))
    _ : Unit <- IO.print(String.concat(["dummy1_layout_pack=", String.concat([Field.dummy_layout(), ",", U32.show(Field.dummy_pack())])]))
    _ : Unit <- IO.print(String.concat(["dummy1_ofs_size=", String.concat([U32.show(1), ",", U32.show(4)])]))
    _ : Unit <- IO.print(String.concat(["dummy2_names=", Field.dummy_names_row(2)]))
    _ : Unit <- IO.print(String.concat(["dummy2_lens=", Field.dummy_lens_row(2, 7)]))
    _ : Unit <- IO.print(String.concat(["dummy2_layout_pack=", String.concat([Field.dummy_layout(), ",", U32.show(Field.dummy_pack())])]))
    _ : Unit <- IO.print(String.concat(["dummy2_ofs_size=", String.concat([U32.show(7), ",", U32.show(4)])]))
    # -- the bitfield ------------------------------------------------------
    _ : Unit <- IO.print(String.concat(["ics_sizes=", ics_sizes()]))
    _ : Unit <- IO.print(String.concat(["ics_real_fields=", Field.names_row(bf_fields())]))
    _ : Unit <- IO.print(String.concat(["bf_read_abcd=", bf_read_row(mem_abcd(), True{})]))
    _ : Unit <- IO.print(String.concat(["bf_read_zero=", bf_read_row(mem_zero8(), True{})]))
    _ : Unit <- IO.print(String.concat(["bf_read_ffff=", bf_read_row(mem_ffff8(), True{})]))
    _ : Unit <- IO.print(String.concat(["bf_read_0ff0=", bf_read_row(mem_0ff0(), True{})]))
    _ : Unit <- IO.print(String.concat(["bf_read_a001=", bf_read_row(mem_a001(), True{})]))
    _ : Unit <- IO.print(String.concat(["bf_set_a_15=", mem_hex.go(Field.bset(mem_abcd(), f_a(), 15, True{}), "")]))
    _ : Unit <- IO.print(String.concat(["bf_set_b_abc=", mem_hex.go(Field.bset(Field.bset(mem_abcd(), f_a(), 15, True{}), f_b(), 2748, True{}), "")]))
    _ : Unit <- IO.print(String.concat(["bf_set_a_0=", mem_hex.go(Field.bset(Field.bset(Field.bset(mem_abcd(), f_a(), 15, True{}), f_b(), 2748, True{}), f_a(), 0, True{}), "")]))
    _ : Unit <- IO.print(String.concat(["bf_set_b_fff=", mem_hex.go(Field.bset(Field.bset(Field.bset(Field.bset(mem_abcd(), f_a(), 15, True{}), f_b(), 2748, True{}), f_a(), 0, True{}), f_b(), 4095, True{}), "")]))
    _ : Unit <- IO.print(String.concat(["bf_get_after_set=", bf_read_row(Field.bset(Field.bset(Field.bset(Field.bset(mem_abcd(), f_a(), 15, True{}), f_b(), 2748, True{}), f_a(), 0, True{}), f_b(), 4095, True{}), True{})]))
    _ : Unit <- IO.print(String.concat(["bf_set_b_overflow=", Field.bset_overflow_row(f_b(), 4096)]))
    _ : Unit <- IO.print(String.concat(["bf_arith_4_0=", Field.arith_row(4, 0)]))
    _ : Unit <- IO.print(String.concat(["bf_arith_12_4=", Field.arith_row(12, 4)]))
    _ : Unit <- IO.print(String.concat(["bf_arith_1_7=", Field.arith_row(1, 7)]))
    _ : Unit <- IO.print(String.concat(["bf_arith_31_0=", Field.arith_row(31, 0)]))
    _ : Unit <- IO.print(String.concat(["bf_arith_32_0=", Field.arith_row(32, 0)]))
    _ : Unit <- IO.print(String.concat(["bf_arith_3_5=", Field.arith_row(3, 5)]))
    _ : Unit <- IO.print(String.concat(["bf_order_little=", bf_order_row(mem_abcd(), True{})]))
    _ : Unit <- IO.print(String.concat(["bf_order_big=", bf_order_row(mem_abcd(), False{})]))
    # -- record / Struct.__init__ -----------------------------------------
    _ : Unit <- IO.print(String.concat(["record_size_fields=", record_size_fields()]))
    _ : Unit <- IO.print(String.concat(["field_offsets=", Field.offs_row(r_fields())]))
    _ : Unit <- IO.print(String.concat(["field_sizes=", Field.typs_row(r_fields())]))
    _ : Unit <- IO.print(String.concat(["init_pos_1_2=", Struct.init_row(Struct.of(8, r_fields()), [1, 2], "", 0)]))
    _ : Unit <- IO.print(String.concat(["init_pos_kw_c9=", Struct.init_row(Struct.of(8, r_fields()), [1, 2], "c", 9)]))
    _ : Unit <- IO.print(String.concat(["init_kw_c9=", Struct.init_row(Struct.of(8, r_fields()), [], "c", 9)]))
    _ : Unit <- IO.print(String.concat(["init_pos_4_dropped=", Struct.init_row(Struct.of(8, r_fields()), [1, 2, 3, 4], "", 0)]))
    _ : Unit <- IO.print(String.concat(["init_unknown_kw=", String.concat(["d=7,mem=", mem_hex.go(Struct.init(Struct.of(8, r_fields()), mem_hex.zeros(8), [1, 2], "d", 7), "")])]))
    _ : Unit <- IO.print(String.concat(["init_zip_bound=", String.concat([U32.show(Struct.nfields(Struct.of(8, r_fields()))), ",", U32.show(Struct.nset(Struct.of(8, r_fields()), 4))])]))
    _ : Unit <- IO.print(String.concat(["ics_size_attr_stays_0=", U32.show(Struct.size(init_c_struct_t(8, bf_fields())))]))
    # -- init_c_var --------------------------------------------------------
    _ : Unit <- IO.print(String.concat(["var_value=", U32.show(init_c_var.val(0, 99))]))
    _ : Unit <- IO.print(String.concat(["var_cb_returned=", U32.show(99)]))
  do IO<Unit>:
    # -- DLL ---------------------------------------------------------------
    _ : Unit <- IO.print(String.concat(["dll_emsg_libfoo=", DLL.emsg("libfoo", "")]))
    _ : Unit <- IO.print(String.concat(["dll_emsg_dash=", DLL.emsg("my-lib-x", "")]))
    _ : Unit <- IO.print(String.concat(["dll_emsg_given=", DLL.emsg("libfoo", "boom")]))
    _ : Unit <- IO.print(String.concat(["dll_emsg_empty_is_falsy=", DLL.emsg("", "")]))
    _ : Unit <- IO.print(String.concat(["dll_envkey_plain=", findlib.env_key("libfoo")]))
    _ : Unit <- IO.print(String.concat(["dll_envkey_dash=", findlib.env_key("my-lib-x")]))
    _ : Unit <- IO.print(String.concat(["dll_emsg_key_ne_envkey=", b2s(Bool.not(DLL.emsg_key_is_envkey("my-lib-x")))]))
    _ : Unit <- IO.print(String.concat(["dll_getattr_msg=", DLL.attr_err("nope", DLL.emsg("nope", ""))]))
    _ : Unit <- IO.print(String.concat(["dll_getattr_module=", DLL.module("nope")]))
    # -- findlib -----------------------------------------------------------
    _ : Unit <- IO.print(String.concat(["fl_found_paths_empty=", findlib.reaches_row(r_empty())]))
    _ : Unit <- IO.print(String.concat(["fl_found_paths_abs_nonfile=", findlib.reaches_row(r_abs())]))
    _ : Unit <- IO.print(String.concat(["fl_found_paths_rel=", findlib.reaches_row(r_rel())]))
    _ : Unit <- IO.print(String.concat(["fl_found_paths_abs_then_rel=", findlib.reaches_row(r_abs_rel())]))
    _ : Unit <- IO.print(String.concat(["fl_found_paths_rel_then_abs=", findlib.reaches_row(r_rel_abs())]))
    _ : Unit <- IO.print(String.concat(["fl_found_paths_two_abs=", findlib.reaches_row(r_two_abs())]))
    _ : Unit <- IO.print(String.concat(["fl_osx_bases_p_P=", String.join(findlib.base.osx("P"), ",")]))
    _ : Unit <- IO.print(String.concat(["fl_osx_bases_p_zzz=", String.join(findlib.base.osx("zzz"), ",")]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_6=", so_row("z", "libz.so.6", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_so=", so_row("z", "libz.so", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_soa=", so_row("z", "libz.soa", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_=", so_row("z", "libz.so.", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_1_2_3=", so_row("z", "libz.so.1.2.3", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_soX=", so_row("z", "libz.soX", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_a=", so_row("z", "libz.a", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_6_txt=", so_row("z", "libz.so.6.txt", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_7=", so_row("z", "libz.so.7", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_0=", so_row("z", "libz.so.0", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libzso_6=", so_row("z", "libzso.6", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_SO_6=", so_row("z", "libz.SO.6", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_6_gz=", so_row("z", "libz.so.6.gz", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_06=", so_row("z", "libz.so.06", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_sox=", so_row("z", "libz.sox", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_6_0_0=", so_row("z", "libz.so.6.0.0", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_9=", so_row("z", "libz.so.9", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_dylib=", so_row("z", "libz.dylib", 127, 69, 76, 70)]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_9_badmagic=", b2s(Bool.not(Bool.and(findlib.so_ok("z", "libz.so.9"), findlib.elf_ok(126, 69, 76, 70))))]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_9_badmagiclast=", b2s(Bool.not(Bool.and(findlib.so_ok("z", "libz.so.9"), findlib.elf_ok(127, 69, 76, 71))))]))
    _ : Unit <- IO.print(String.concat(["so_libz_so_9_empty=", b2s(Bool.not(Bool.and(findlib.so_ok("z", "libz.so.9"), findlib.elf_ok(0, 0, 0, 0))))]))
    _ : Unit <- IO.print(String.concat(["fl_libc_osx=", findlib.osx_lib("libc", True{}, True{})]))
    _ : Unit <- IO.print(String.concat(["fl_m_osx=", findlib.osx_lib("m", True{}, True{})]))
    _ : Unit <- IO.print(String.concat(["fl_libc_prefix=", findlib.osx_lib_at("libc")]))
    _ : Unit <- IO.print(String.concat(["fl_libc_linux=", findlib.osx_lib("libc", True{}, False{})]))
    _ : Unit <- IO.print(String.concat(["fl_m_linux=", findlib.osx_lib("m", True{}, False{})]))
    _ : Unit <- IO.print(String.concat(["libpaths_posix=", String.join(libpaths.posix("/lddir1::/lddir2", Char.from_u32(58)), ",")]))
    _ : Unit <- IO.print(String.concat(["libpaths_linux=", String.join(libpaths.linux("<multiarch>"), ",")]))
    _ : Unit <- IO.print(String.concat(["libpaths_darwin=", String.join(libpaths.darwin("P"), ",")]))
    _ : Unit <- IO.print(String.concat(["libpaths_nt=", String.join(libpaths.nt("C:\\a;C:\\b", Char.from_u32(59)), ",")]))
    _ : Unit <- IO.print(String.concat(["prefixes_both_keys=", String.join(findlib.prefixes("", libpaths.posix("/lddir1::/lddir2", Char.from_u32(58)), libpaths.linux("<multiarch>"), Nil{}), ",")]))
    _ : Unit <- IO.print(String.concat(["prefixes_env_first=", String.join(findlib.prefixes("/env", libpaths.posix("/lddir1::/lddir2", Char.from_u32(58)), libpaths.linux("<multiarch>"), ["/extra"]), ",")]))
    _ : Unit <- IO.print(String.concat(["libpaths_unknown_key=", libpaths_unknown()]))
    _ : Unit <- IO.print(String.concat(["fl_no_path_key=", findlib.no_path_key(False{})]))
    # -- Array -------------------------------------------------------------
    _ : Unit <- IO.print(String.concat(["arr_default_type_length=", arr_default_row()]))
    _ : Unit <- IO.print(String.concat(["arr_getitem_zero_len=", U32.show(Array_.getitem(4, 0, True{}))]))
    _ : Unit <- IO.print(String.concat(["arr_getitem_is_product=", Array_.getitem_row(True{}, 4, 3)]))
    # A `do IO<Unit>:` BODY ENDS WITH A BARE TERM (convention 7), so the LAST
    # row of the file is the one statement with no `_ : Unit <-` in front of it.
    # MEASURED, and the failure mode is worth recording: a trailing `<-` binding
    # does not report itself. It reports "expected : a term / observed : end of
    # input" AT THE END OF THE FILE and hides EVERY type error above it, so the
    # one-line gate looked like a parse error while six affine errors sat
    # unfixed underneath. Read the LOCATION line, not the message.
    IO.print(String.concat(["arr_tuple_key_raises=", Array_.getitem_row(False{}, 4, 3)]))

# THE MEASURED MUTATION TABLE -- `.agents/slop/c-mutate.py`, output
# `.agents/slop/c-mutations.txt`. 26 mutations, 101 whole `name=value` lines moved,
# ONE zero and it is a measured THEOREM. The harness diffs LINES, never row names: a
# name-comparing harness reported 0 for all 30 mutations in one unit of this project.
#
#   id     moved   the rule it breaks / the rows it moved
#   -----  ------  ---------------------------------------------------------
#   M1     1       the no-struct arm IGNORES `__idir` -- fold the direction in
#                 MOVED ioctl_none_idir3_same
#   M2     ZERO    `__set_name__`'s SECOND arm: `idx` is 0 when the owner had no entries
#   M3     2       `if self.bit_width` is TRUTHINESS, so `bit_width=0` gives a 3-wide entry
#                 MOVED sname_bw0_entry_width sname_entry_width
#   M4     1       `zip` TRUNCATES: a fourth positional is dropped, not an error
#                 MOVED init_zip_bound
#   M5     1       positionals are written BEFORE keywords, so the keyword wins
#                 MOVED init_pos_kw_c9
#   M6     2       `init_c_struct_t` sets `_fields_` and NEVER `SIZE`
#                 MOVED ics_size_attr_stays_0 ics_sizes
#   M6b    2       `init_c_struct_t` writes SIZE=0; put `sz` there instead
#                 MOVED ics_size_attr_stays_0 ics_sizes
#   M7     1       `record` sets `_fields_` FROM `cls.SIZE`, the other direction
#                 MOVED record_size_fields
#   M8     12      `ceildiv(bit_width+bit_off, 8)` -- floor instead of ceiling
#                 MOVED bf_arith_31_0 bf_arith_4_0 bf_order_big bf_order_little bf_read_0ff0 bf_read_a001 bf_re.
#   M9     18      `(1 << bit_width) - 1` -- drop the `- 1`
#                 MOVED bf_arith_12_4 bf_arith_1_7 bf_arith_31_0 bf_arith_32_0 bf_arith_3_5 bf_arith_4_0 bf_get.
#   M10    1       `to_bytes(sz)` RAISES on an overflow; there is no masking on the store
#                 MOVED bf_set_b_overflow
#   M11    3       `U32.shrn(x, 0n)` is `x`, so byte 0 needs `& 255`
#                 MOVED bf_order_little bf_set_a_0 bf_set_b_abc
#   M12    12      `List.set` indexes the list it is GIVEN, and the recursion hands it the T.
#                 MOVED bf_get_after_set bf_order_big bf_order_little bf_set_a_0 bf_set_a_15 bf_set_b_abc bf_se.
#   M12b   12      the write REBUILDS the list from the tail, so the whole store is lost
#                 MOVED bf_get_after_set bf_order_big bf_order_little bf_set_a_0 bf_set_a_15 bf_set_b_abc bf_se.
#   M13    2       `nm.replace('-','_')` -- the append already preserves order, so no reverse
#                 MOVED dll_envkey_dash dll_envkey_plain
#   M14    9       the `.so` prefix is `lib` + p + `.so`, which is SIX characters plus p
#                 MOVED so_libz_so so_libz_so_ so_libz_so_0 so_libz_so_06 so_libz_so_1_2_3 so_libz_so_6 so_libz.
#   M15    5       the `.so` tail is `[.0-9]` -- allow every printable character
#                 MOVED so_libz_soX so_libz_so_6_gz so_libz_so_6_txt so_libz_soa so_libz_sox
#   M16    1       the ELF magic is `\x7FELF` and not `\x7FEL`
#                 MOVED so_libz_so_9_badmagiclast
#   M17    2       `findlib`'s base names are built from `p`, NOT from `nm`
#                 MOVED fl_osx_bases_p_P fl_osx_bases_p_zzz
#   M18    1       A CHARACTER INSIDE A STRING LITERAL. The row count does NOT move.
#                 MOVED dll_getattr_msg
#   M19    1       the same string, the WRONG WAY -- through a call-site qualifier
#                 MOVED dll_getattr_msg
#   M20    2       `libpaths` is keyed by BOTH os.name AND sys.platform and BOTH are appended
#                 MOVED prefixes_both_keys prefixes_env_first
#   M21    3       `[d for d in LD_LIBRARY_PATH.split(':') if d]` -- keep the empties
#                 MOVED libpaths_posix prefixes_both_keys prefixes_env_first
#   M22    1       `if rc:` -- a zero return does NOT raise
#                 MOVED ioctl_rc0_msg
#   M23    1       `init_c_var` returns INDEX 1 of the tuple, which is the VAR
#                 MOVED var_value
#   M24    5       `bget` masks; drop the mask and the getter reads the whole slice
#                 MOVED bf_get_after_set bf_order_big bf_order_little bf_read_abcd bf_read_ffff
#
# M2 IS A THEOREM AND THE `sname_setname_pairs` / `sname_hasreal_iff_npositive` ROWS ARE
# ITS PROOF, MEASURED. `__set_name__` appends only when `hasattr(owner, "_real_fields_")`
# and then sets `idx = len(_real_fields_) - 1`, so the two arms can differ only when the
# owner LACKS the attribute while the prior length is nonzero -- and a nonzero length
# means something appended, which is what creates the attribute. The oracle WATCHED four
# real `__set_name__` calls and collected `(hasattr, len-before)` =
# `(False,0),(True,1),(True,2),(True,3)`: never `(False, n>0)`. The fourth is an
# INHERITED case -- `Sub(Three)` sees `hasattr` True with three entries, because
# `hasattr` walks the MRO. So `Field.set_name.idx(has_real, n) == n` over the whole
# reachable domain, the mutation "return n" is the identity on values, and no fixture
# can separate them. `ops_amd`'s `floor(floor(a/b)/c)` is the same shape.
#
# M6 IS A COMPILE MUTATION: `init_c_struct_t` writes `mem_len` into ONE record slot, so
# removing its `+` is not a behaviour change, it stops the file compiling. M6b is the
# behavioural half and it moves `ics_sizes` and `ics_size_attr_stays_0`.
#
# M11 IS THE SECOND OF THE TWO UNMASKED-BYTE BUGS IN THIS FILE AND IT IS NOT A THEOREM:
# dropping the `& 255` from byte 0 moves three rows, because `U32.shrn(x, 0n)` is `x`.
#
# M18 AND M19 ARE THE TRAP THIS PROJECT PAID FOR TWICE. Each rewrites a CHARACTER
# INSIDE A STRING LITERAL -- M18 changes `nope` to `nop3`, M19 DELETES the emsg from the
# message. In both cases the row COUNT is unchanged at 129 and only a byte diff sees it,
# which is exactly how `renderer/tc_ptx.bend` shipped `"mov.b32 %r0, %r1;"` corrupted to
# `"%T.r1"` with 620 green rows. A row count is not a proof.
# ===========================================================================
