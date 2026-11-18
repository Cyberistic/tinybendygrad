<!-- FROM: tinybendygrad/runtime/support/c.bend:762 -->
# BLOCK:
# the name correspondence, which is a correspondence and not a score.
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
#                         `TODO(p3) c.py:20  symbol=U`.
#     POINTER             `POINTER[T]` is `ctypes.POINTER(T)` and `pointer(x)`
#                         returns a `ctypes._Pointer`. Both are FFI: an ADDRESS.
#                         `TODO(p3) c.py:25  symbol=__class_getitem__`.
#     CFUNCTYPE           `CFUNCTYPE[None, (U32,)]` builds a ctypes function
#                         TYPE. `TODO(p3) c.py:31  symbol=CFUNCTYPE`.
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
# `b2s` is the row formatter and `u32_hex` is the width-8 hex, because
# `ioctl_none_ord_A_11=00004111` is a number in hex and every other `so_*` and
# `bf_set_*` row is a byte string in hex. A count row is never emitted.
# END BLOCK

# the name correspondence, which is a correspondence and not a score.
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
#                         `TODO(p3) c.py:20  symbol=U`.
#     POINTER             `POINTER[T]` is `ctypes.POINTER(T)` and `pointer(x)`
#                         returns a `ctypes._Pointer`. Both are FFI: an ADDRESS.
#                         `TODO(p3) c.py:25  symbol=__class_getitem__`.
#     CFUNCTYPE           `CFUNCTYPE[None, (U32,)]` builds a ctypes function
#                         TYPE. `TODO(p3) c.py:31  symbol=CFUNCTYPE`.
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
# `b2s` is the row formatter and `u32_hex` is the width-8 hex, because
# `ioctl_none_ord_A_11=00004111` is a number in hex and every other `so_*` and
# `bf_set_*` row is a byte string in hex. A count row is never emitted.
