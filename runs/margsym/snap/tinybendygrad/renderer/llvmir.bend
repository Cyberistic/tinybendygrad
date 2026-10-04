# llvmir.bend -- tinygrad/renderer/llvmir.py (286 lines), STAGE 2 ONLY.
#
# `nir_llvmir.bend` (1142 lines, 205 rows) owns STAGE 1: `ldt`'s type map,
# `lcast`, the three `lop` tables, the renderer record, `supported_dtypes`,
# `llvm_intrinsics`, `code_for_op`, `code_for_workitem`, `barrier`, the two NAMES
# the naming walk assigns (`%data{slot}`, `%{local|reg}_{slot}`), the
# `getelementptr` line and the AMD `f32_to_fp8` prefix. Its own header names
# STAGE 2 as "`_render_fn` (:156-160), `_render_footer` (:210, :265), the per-op
# emitter strings of `base_rewrite` (:77-144) and `_render_kernel`'s naming walk
# (:161-202)". This file is that list MINUS the walk, and the reason is in the
# NOT-PORTED section: the walk needs a UOp model this tree does not have.
#
# ---------------------------------------------------------------------------
# THE GATE. 471 rows + the one framing newline `IO.print` supplies, all diffed
# byte-for-byte against the oracle's own stdout:
#   .venv/bin/python .agents/slop/llvmir-oracle.py rows > .agents/slop/li/py.txt
#   .venv/bin/python .agents/slop/llvmir-oracle.py bend > .agents/slop/li/stage2.bend
#   ./bin/bend tinybendygrad/renderer/llvmir.bend > .agents/slop/li/port.txt
#   diff .agents/slop/li/port.txt .agents/slop/li/py.txt
# ONE `IO.print` for the whole table, so `IO.print`'s own newline is the only
# frame and the oracle's single trailing "\n" is its match. BOTH LANES WERE
# MEASURED BYTE-IDENTICAL TO EACH OTHER AND TO THE ORACLE.
# ⚠ THE ORACLE MOVED. This header used to say `.agents/slop/li/li-oracle.py`, and that
# file does not exist: `rebase-gate.py`'s roster points at `.agents/slop/llvmir-oracle.py`,
# which is where it lives. `.agents/slop/li/` holds CAPTURES, not the oracle.
# ⚠ AND A BYTE DIFF IS NOT A COVERAGE STATEMENT. The two lanes print the SAME BYTES, so a
# value comparison over them agrees by construction no matter what this file computes --
# `disagree` is 0 for free. What the diff cannot see is how many of the 471 printed rows any
# NAME can reach, and for most of this file's life that was 323. See the next section.
#
# ---------------------------------------------------------------------------
# ROW NAMES CARRY NO `=`, AND 157 OF THEM USED TO. 2026-10-04.
#
# `rebase-gate.py:row` splits a row line at its FIRST `=`. This lane's boundary is
# `<name> = [v]   py=[w]`, so a name containing `=` is cut in the wrong place and TWO rows
# that differ only after their `=` become ONE key: the later row silently overwrites the
# earlier and the measurement is unreachable BY ANY NAME, on BOTH sides, under a green
# verdict. MEASURED on this file before the fix, per lane:
#     471 physical rows -> 323 names. 157 names carried an `=`, 148 rows were unaddressable,
#     and TEN keys took more than one row:
#         `rfn abi` 77, `br2 load vol` 48, `br5 stack n` 10, `br4 store vol` 6,
#         `br3 load vol` 6, and `is_volatile {PARAM,CAST,BUFFER,CONST,AFTER} vol` 2 each.
#     `lt 1 ptr f32` was an ELEVENTH key with two rows and NO `=` anywhere -- see below.
# AFTER: 471 rows -> 470 names, 0 names containing `=`, 0 unaddressable by a reshape. The
# only remaining loss is the `lt 1 ptr f32` duplicate, which no separator can fix.
#
# ONLY THE SEPARATOR MOVED, once per key, and `=` was never load-bearing:
#   `abi=`  `abi` IS upstream's own class attribute (llvmir.py:147), read at :160 and
#          assigned `'win64cc'` at :207 and `"amdgpu_kernel"` at :230. `abi=None` is the
#          falsy case of `{' ' + self.abi if self.abi else ''}`. Python keyword-argument
#          spelling in a LABEL; upstream has no `abi=` anywhere.
#   `vol=`  upstream has NO identifier `vol`. `is_volatile` (llvmir.py:10) is the function and
#          the emitters interpolate `{'volatile ' if is_volatile(idx) else ''}` (:90, :95,
#          :98); `vol` is this file's standing abbreviation and the `ivol`/`volsp`
#          parameter's name. One abbreviation, one separator, no upstream text.
#   `n=`    upstream has NO identifier `n`. The STACK rule writes `len(x.src)` (:103) and
#          `enumerate(x.src)`'s `i`; `n` is `br5.name`'s third parameter, standing for that
#          length. Same shape as cstyle.bend's `kern <DEV> lb <N>`.
# NAMES MAY CONTAIN SPACES -- `rows()`'s F3 path only runs on lines with no `=`, and this is
# an F2 lane whose name lives before the boundary. Measured: 471 rows, 470 distinct names
# before and after, so the rename created no collision, and the VALUE MULTISET is unchanged
# (253 distinct values, none added, none removed).
# `.agents/slop/li/li-rename.py`, `.agents/slop/li/li-rename-oracle.py`,
# `.agents/slop/li/rename-audit.txt`, `.agents/slop/llvmir-nameshape-control.md`
#
# `lt 1 ptr f32` IS PRINTED TWICE, ON BOTH SIDES, AND IS NOT FIXED HERE. `r_lts()` below
# and `llvmir-oracle.py:647-648` each list the tuple `(1, dtypes.f32, True)` twice in the
# same `lt` count/ptr table, so the fourth entry is the first again. This is the
# `nv_query_litter` shape agent-core.md records -- wrong in the PORT and in the ORACLE, so
# the differ reports 0 disagreements over a mistake made twice. Deleting the repeat costs no
# coverage (the claim is identical); GUESSING what the fourth entry was meant to be would
# invent a row, so it is REPORTED. `llvmir-gate.py --drop-dup` shows what the lane reads like
# without it: 470 rows, 470 names, AGREE, rc=0.
# ---------------------------------------------------------------------------
# THE `py=` LITERALS ARE GENERATED, NOT TYPED. `llvmir-oracle.py`'s `bend` mode
# prints the row-builder source from the SAME run that prints the gate text, so a
# change to the oracle and a change to the gate cannot disagree.
# `cstyle.bend` arrived with 215 hand-written expectations of which SEVENTEEN were
# wrong (five in the oracle, twelve real port bugs); `ops_nv.bend` arrived with 33
# of 219 constants wrong behind 590 green rows. This file's expectations are
# zero typed and zero of them are wrong.
#
# AND THE ORACLE CALLS THE REAL CODE, which is the other half of the point:
# `base_rewrite.patterns[i][1]` IS CPython's own emitter and `_render_fn` is
# called for real on real `ParamArg`s, so no f-string from llvmir.py is re-typed
# on either side of the diff. `llvmir-oracle.py` calls `L.ldt`, `L.lcast.a`,
# `N.lop.cell`'s CPython original and `L.render_wmma_amd`; this file calls the Bend
# ports of the first three and names the last.
#
# ---------------------------------------------------------------------------
# A READ-ONLY NEIGHBOUR IS RED, AND IT IS NOT THIS FILE
#
# `nir_llvmir.bend:181-191` spells `ldt.fp` as EIGHT `case`s on the dtype NAME
# (`"float"`, `"half"`, `"__bf16"`, `"double"`, `"float8_e4m3"`, ...).
# `LAWS/spec.bend:694-701` now spells those names `"fp8e4m3"`, `"f16"`, `"bf16"`,
# `"f32"`, `"f64"`. So EVERY arm of that ladder stopped matching and fell through
# to `case _: "KeyError"`, and that file's gate is RED on 79 of its 205 rows:
#
#   $ ./bin/bend tinybendygrad/renderer/nir_llvmir.bend -o /tmp/nl_now
#   $ /tmp/nl_now | diff - .agents/slop/nl/py1.txt | grep -c '^< '
#   79
#   $ /tmp/nl_now | grep '^ldt float32\|^lt float\|^lt f32'
#   ldt float = [KeyError]   py=[float]
#
# That is the dtype-rename hazard in its purest form: a pattern that stops
# matching does not FAIL, it falls through, and the answer becomes a DIFFERENT
# answer rather than an error. `ldt(float32)` is `KeyError` where it was `float`.
# `nir_llvmir.bend` is COMMITTED and was out of scope to edit, so the fix is
# REPORTED, not applied, and this file carries its own `lt`.
#
# `lt` IS `ldt` RE-ARMED ON FIELDS THE RENAME DOES NOT TOUCH: `Cls`, `bits` and
# `pri`. Within `CFloat`, `bits == 8` is the fp8 quadruple and every one of them
# spells `i8`, so the four-name collapse is the MAP'S OWN property and not a
# shortcut -- `ldt(fp8e4m3) == ldt(int8) == "i8"` is true in CPython too and
# `lt fp8e4m3` and `lt i8` are both rows of that grid. `pri` is then the ONLY
# load-bearing numeric field, separating half (12) from bfloat16 (13) from float
# (14) from double (15), and `pri` is a SEPARATE ROW GROUP so a renumbering of
# `spec.bend`'s priorities is a moved row rather than a new spelling found later.
# `pri` gets away with not separating `fp8e4m3` from `fp8e4m3fnuz` (both 10)
# precisely because those two answer the SAME string.
#
# ---------------------------------------------------------------------------
# THE TWELVE CONVENTIONS of `renderer/__init__.bend`'s header are obeyed. The five
# that bite here:
#   2. THE GATE IS A STRING DIFF, NEVER A BOOLEAN ABOUT STRINGS. Every row is
#      `<name> = [BEND]   py=[CPYTHON]`, and every MULTI-LINE emitter is gated ONE
#      LINE PER ROW and never as a re-joined blob: `String.concat` drops a literal
#      silently, and a boolean about a joined string can be true while the string
#      is wrong. `br2`'s eight lines are eight rows; `rfn`'s six are six.
#   3. A `|None` field is FLATTENED to a `Bool` plus the value: `_render_fn`'s
#      `abi: str | None` is `""` for absent, and the ROW LABEL keeps the Python
#      spelling (`rfn abi None global [0]`) -- a port that passed the literal
#      `"None"` prints `define None void`, which is what the first draft did.
#   4. A `match` MAY ONLY SCRUTINISE A PARAMETER OR A PATTERN BINDER. Every ladder
#      here destructures its own parameter first; there is no `value.field` sugar
#      and no generated projection.
#   6. A RECORD LITERAL AND A RECORD PATTERN BOTH NAME EVERY FIELD.
#  10. A WALL WITH A NAME INSTEAD OF A PLAUSIBLE WRONG STRING: `KeyError`,
#      `RuntimeError` and `ValueError` are the strings the port answers where
#      CPython raises, and each has a row that says so -- `lt weakfloat`,
#      `br6 bitcast i8x1->f32x1`, `fp8_pos i32`.
#
# ---------------------------------------------------------------------------
# WHAT IS NOT PORTED, WITH PYTHON LINES. Measured, not guessed.
#
#   * `_render_kernel`'s NAMING WALK (llvmir.py:161-202). This is the one
#     STAGE-2 item left out and it is the CENTREPIECE, so the reason is the
#     interesting part rather than an excuse. The walk reads nine things off each
#     UOp -- `op`, `dtype`, `max_numel`, `addrspace`, `arg.slot`, `arg.volatile`,
#     `src[0].dtype`, `src[0].max_numel` and whether `src[0]` is a CONST -- and
#     this tree has no UOp VALUE to hand it: `uop/ops.bend`'s `Arena`/`Node` is an
#     index arena with no `addrspace` or `max_numel` reader, and `arg.volatile`
#     and `src[0].op is Ops.CONST` would each need a new reader there. Writing a
#     SECOND `Nd` record here would be a port of the walk against a MODEL of a
#     UOp rather than against one, and the gate would then be testing the model.
#     `li-oracle.py` KEEPS `walk_rows()` and it RUNS -- it is dead only in the
#     `rows` path -- so the moment `ops.bend` grows the three readers this is a
#     `Nd` record and a fold, not a re-derivation.
#   * `render` (llvmir.py:209 and :251-264). Both are
#     `(k:=_render_kernel(uops))[0] + (k[1], _render_footer(uops))` joined -- they
#     need the walk. `li-oracle.py` keeps `render_rows()` for the same reason, and
#     it already found a real refusal: `amd_fp8s("gfx1100")` is EMPTY, so an fp8
#     uop on gfx1100 raises `IndexError` at llvmir.py:252 and that IS a row when
#     the walk lands.
#   * `render_wmma_amd` (llvmir.py:38-65). Two emitters and four inputs that
#     change between them -- `cdna`, `rdna4`, `arg[1]` and `arg[0]`'s N,M,K -- over
#     a `dt_map` whose `bf16`/`bf16.1k` differ only by a SUFFIX. `tc_ptx.bend`'s
#     unit owns `renderer/tc.py`; the `dt_map` is half `fp8_index`, which IS here
#     (`fp8i`, both directions gated), and half a per-device table that is
#     `tc_ptx.bend`'s. `li-oracle.py` keeps `wmma_rows()` and it runs.
#   * `AMDLLVMRenderer.asm` (llvmir.py:248-250) is `renderer/amd/elf.py`'s
#     `assemble_linear` -- FFI plus a linker. One Python line, no rows.
#   * `__init__` (llvmir.py:211-214, :274-284) binds `CPULLVMCompiler` /
#     `AMDLLVMCompiler` / `tc.get_amd` -- `runtime/support/compiler_llvm.py` and
#     `renderer/tc.py`, both other units' work.
#   * `lconst`'s fp8 and finite-float VALUES (llvmir.py:20, :23) are
#     `float_to_fp8` (dtype.py:244) and `truncate` (dtype.py:295), so they are
#     `dtype.bend`'s. What is HERE is the FOUR-WAY DISPATCH (`lconst branch <d>`,
#     eighteen rows, one per dtype) and the inf/nan hex, which is llvmir.py's own
#     code (:22) and is fully expressed without an `F64`.
#   * `float_to_fp8`'s `_fp8_cfg` (dtype.py:236-241) is dtype.py's.
#   * `float_to_fp16` / `float_to_bf16` are `codegen/decomp/transcendental.bend`'s
#     and reach this file only through `truncate`.
#   * `PatternMatcher` itself is `uop/ops.bend`'s. This file ports the EIGHTEEN
#     RULES' OUTPUTS: `base_rewrite.rules` is the rule COUNT and a row, and `brN`
#     is rule N's emitter.
#   * `range_str` (uop/ops.py:95-97) -- only its LABEL GRAMMAR is here, because
#     that is all `base_rewrite` reads. `axis_id`'s derivation (`self.arg[1:]`,
#     ops.py:502) is `uop/ops.bend`'s, so the ids are parameters and the `m`
#     PREFIX is three rows of its own with ONE caller group.
#   * `SPECIAL`'s `d.vmax` is `uop/ops.bend`'s `nc`/Variable machinery. The AMD
#     footer gate is llvmir's own half -- the `u.arg[0] == "l"` FILTER and `prod`
#     of the survivors, `prod([]) == 1` included -- and the WIDTHS are
#     parameters.
#   * `CTX`'s aliasing (`ctx[x][1:]` on a `PATTERN VARIABLE` whose name is
#     shadowed by the binder) is `uop/ops.bend`'s.


import Base
import ./__init__.bend as R
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../LAWS/spec.bend as S
import ./nir_llvmir.bend as N

# ===========================================================================
# THE GATE PRIMITIVES. A row is a VALUE, so a group of them is a `String` and
# the whole gate is one `IO.print`. The `py=` half is a LITERAL, which is what
# makes the diff a diff -- it cannot be the same expression as the `got=` half.
# ===========================================================================

def r(+nm: String, +got: String, +want: String) -> String:
  String.concat([nm, " = [", got, "]   py=[", want, "]\n"])

def bs(+x: Bool) -> String: Bool.pick(String, x, "True", "False")

def nl() -> String: String.from_list([Char.from_u32(10)])

def nth(+xs: List<&2, String>, i: Nat) -> String: Maybe.default(&2, String, List.get(&2, String, xs, i), "")

def nlen(+xs: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, xs))

def u32n(+xs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, xs))

def dtn(+d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

# ===========================================================================
# `lt` -- llvmir.py:12-17. THE TYPE MAP, RENAME-PROOF. See the header: this is
# `nir_llvmir.bend`'s `ldt` re-armed on `Cls`/`bits`/`pri` because that file's
# `ldt.fp` ladder arms on dtype NAMES and `spec.bend` has renamed them.
# ===========================================================================

def lt.ints(bits: U32) -> String: String.concat(["i", U32.show(bits)])

# The eight `CFloat` members by WIDTH, then by `pri` for the two 16-bit ones.
# `bits == 8` is the fp8 quadruple and every one of them spells `i8`, so the
# four-name collapse is the MAP'S OWN property and not a shortcut:
# `ldt(fp8e4m3) == ldt(int8) == "i8"` is true in CPython too, and `lt fp8e4m3`
# and `lt i8` are both rows of that grid.
def lt.fp(bits: U32, pri: U32) -> String:
  match bits:
    case 8: "i8"
    case _: match pri:
             case 12: "half"
             case 13: "bfloat"
             case 14: "float"
             case _: "double"

def lt.of(+d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}:
      match cls:
        case S.CVoid{}  : "void"
        case S.CBool{}  : "i1"
        case S.CUint{}  : lt.ints(bits)
        case S.CSint{}  : lt.ints(bits)
        case S.CFloat{} : lt.fp(bits, pri)
        case _: "KeyError"

def lt.v(+d: S.Dt, +count: U32) -> String:
  Bool.pick(String, U32.is_gt(count, 1), String.concat(["<", U32.show(count), " x ", lt.of(d), ">"]), lt.of(d))

# `ldt(dt, count, ptr)` -- NOT a self-call; `ptr` is a parameter so the depth is
# one and the decrease checker is satisfied (nir_llvmir.bend's note above).
def lt.t(+d: S.Dt, +count: U32, ptr: Bool) -> String:
  Bool.pick(String, ptr, String.concat([lt.v(d, count), "*"]), lt.v(d, count))

# `lt.pri` -- the ONE load-bearing numeric field, gated for every dtype below.
def lt.pri(+d: S.Dt) -> U32:
  match d:
    case S.Dt{pri, bits, cls, nm}: pri

# ===========================================================================
# `is_volatile` -- llvmir.py:10.
#
#     def is_volatile(u:UOp) -> bool:
#       return (buf:=u.buf_uop).op is Ops.PARAM and buf.arg.volatile
#
# TWO FACTS AND BOTH ARE ROWS. `buf_uop` walks UP to the PARAM, so a CAST and
# an AFTER above a PARAM answer the PARAM's flag -- and a BUFFER is NOT a PARAM,
# so `is_volatile` on a buffer carrying `volatile=True` is STILL False. That
# second one is the row a reader who tests `u.arg.volatile` gets wrong, and it
# is the row a "volatile set" fixture cannot see.
#
# `is_param` is the port's name for `buf_uop`'s answer, and it is a PARAMETER
# because `buf_uop` is `uop/ops.bend`'s walk. `vol` is `buf.arg.volatile`.
# ===========================================================================

def ivol(is_param: Bool, vol: Bool) -> Bool: Bool.and(is_param, vol)

# `volatile ` with a TRAILING space and nothing when False: llvmir.py:90, :95,
# :98 all spell `{'volatile ' if ... else ''}` inside a longer literal, so the
# space belongs to the FRAGMENT, and the one space before the comma in a load
# line is the fragment's, not the literal's. `br3 load vol True` and
# `br3 load vol False` are the pair that pins it.
def volsp(vol: Bool) -> String: Bool.pick(String, vol, "volatile ", "")

def r_iv(+nm: String, is_param: Bool, vol: Bool, py: String) -> String:
  r(nm, bs(ivol(is_param, vol)), py)

# ===========================================================================
# `lconst` -- llvmir.py:19-24. THE FOUR-WAY DISPATCH plus the inf/nan arm.
#
#     if dtype in dtypes.floats:
#       if dtype in dtypes.fp8s:            return float_to_fp8(x, dtype)
#       if isinf(x) or isnan(x):            return "0x%02X..." % pack("d",x)[::-1]
#       return truncate[dtype](x)
#     return int(x)
#
# THE HEX ARM IS ALL THAT IS PORTABLE, and it is not a table: Bend has no `F64`
# (`uop/fold.bend:2798` says so), so `struct.pack("d", x)` is not expressible --
# but the FOUR answers are constants of the IEEE-754 layout rather than of `x`.
#
# The eight reversed bytes are most-significant FIRST: byte 0 is `0x7F` plus the
# SIGN BIT (so `FF`, NOT `87` -- the sign rides bit 7 of the TOP byte), byte 1 is
# `0xF0` plus `nan`'s quiet bit, byte 2 is the sign again, bytes 3..7 are zero.
# `+nan` and `-nan` are TWO rows and not one for exactly that reason, and the
# `int(x)` rows are gated on the TRUNCATION rather than the float's spelling.
# ===========================================================================

def lconst_neg(pos: Bool) -> Bool: Bool.not(pos)

# THE SIGN RIDES BIT 7 OF THE TOP BYTE AND NOWHERE ELSE, so byte 0 is `0x7F`
# for `+` and `0xFF` for `-` -- NOT `0x87`, which is what `0x7F | 0x08` gives and
# is the reading that costs a hex digit-pair. Byte 1 is `0xF0` plus the nan quiet
# bit and bytes 2..7 are zero, so the WHOLE of the sign-and-nan behaviour is two
# `Bool.pick`s over two one-character tables. `lconst_neg` and `lconst_sign` are separate defs
# because a parameter may be consumed ONCE unless it is marked `+`, and a Bool is
# no exception -- `+pos` is what lets the sign be read twice.

def lconst_b0(+pos: Bool) -> String: Bool.pick(String, pos, "7F", "FF")

def lconst_b1(+is_nan: Bool) -> String: Bool.pick(String, is_nan, "F8", "F0")

def lconst_hex(+pos: Bool, +is_nan: Bool) -> String:
  String.concat(["0x", lconst_b0(pos), lconst_b1(is_nan), "000000000000"])

def lc.arm(flt: Bool, fp8: Bool) -> String:
  Bool.pick(String, flt, Bool.pick(String, fp8, "dtype.float_to_fp8", "dtype.truncate"), "int")

def lc.branch(+d: S.Dt) -> String:
  lc.arm(S.Dt.is_float(d), N.is_fp8(d))

# `int(x)` TRUNCATES TOWARD ZERO, not toward -inf: `int(-1.9) == -1` and
# `int(-256.5) == -256`. `F32.trunc` and `F32.floor` agree on every non-negative
# input and differ on three of the ten `lconst int` rows, which is the whole
# reason those rows carry negatives. `F32.show` of an integral value spells it
# without a decimal point, so it IS CPython's `int(x)` spelling for every
# fixture; there is no I64 here because there is no word to print.
def lc.int(x: F32) -> String: F32.show(F32.trunc(x))

def r_lcs(+nm: String, pos: Bool, is_nan: Bool, py: String) -> String:
  r(nm, lconst_hex(pos, is_nan), py)

def r_lcb(+nm: String, +d: S.Dt, py: String) -> String: r(nm, lc.branch(d), py)

def r_lci(+nm: String, x: F32, py: String) -> String: r(nm, lc.int(x), py)

# ===========================================================================
# `range_str` -- uop/ops.py:95-97. THE LABEL GRAMMAR, which is all three of
# `base_rewrite`'s RANGE rules read:
#
#     '_'.join([str(x) if x >= 0 else "m"+str(-x) for x in u.axis_id])
#
# `axis_id`'s derivation is `uop/ops.bend`'s, so the ids are PARAMETERS here and
# the grammar is the port's. The `m` PREFIX is the load-bearing half: a reader
# that drops it agrees on every non-negative id, which is why `range_str 0,-2`
# and `range_str -3,4` are rows.
# ===========================================================================

# `'_'.join([str(x) if x >= 0 else "m"+str(-x) for x in u.axis_id])`.
#
# `axis_id` is `self.arg[1:]` (uop/ops.py:502) and its members are AXIS IDS, so
# they are `Nat`s and the `m` branch is DEAD for every value the graph can hold.
# That is stated rather than quietly dropped: `rstr.neg` is the `m` spelling with
# its OWN row and ONE caller, so the branch is pinned by the fixture that exists
# only for it and `rstr.go` carries no arithmetic it does not need.
#
# The `m` prefix and the magnitude are SEPARATE defs rather than two arms of one
# `Bool.pick`, because a `U32` parameter may be consumed ONCE (brief: "A record
# binder shadows a same-named parameter", and the same linearity reaches every
# scalar) and both arms would take `lo`. That constraint is the reason the two
# spellings are two defs and not one three-armed pick.
def rstr.id(v: U32) -> String: U32.show(v)

def rstr.neg(v: U32) -> String: String.concat(["m", U32.show(v)])

def rstr.go(+xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}   : acc
    case h <> +t : String.concat([acc, rstr.id(h), Bool.pick(String, List.is_empty(&2, U32, t),
      "", String.concat(["_", rstr.go(t, "")]))])

def rstr(+xs: List<&2, U32>) -> String: rstr.go(xs, "")

def r_rs(+nm: String, xs: List<&2, U32>, py: String) -> String: r(nm, rstr(xs), py)

# The `m` spelling. ONE caller group, three fixtures, and it is the ONLY thing that
# reaches `rstr.neg` -- `axis_id`'s members are `Nat`s, so the branch is dead
# for every value a graph can hold. Kept as a def so the grammar is whole and
# its dead arm is pinned by a row rather than deleted.
def r_rsn(+nm: String, v: U32, py: String) -> String: r(nm, rstr.neg(v), py)

# `lt` and `pri` row builders. `r_lt` is the TYPE MAP over the whole grid plus the
# two weak dtypes whose absence from CPython's map is a `KeyError`, and `r_pri` is
# the ONE load-bearing numeric field `lt.fp` disambiguates half from bfloat16
# with -- a separate group so a renumbering of `spec.bend`'s priorities is a moved
# row and not a new spelling discovered later.
# The indexed-read primitive. `List.get` answers `Maybe` and EVERY caller
# in this file wants a `String` -- a multi-line emitter's `i`-th line, an
# argument's type -- so the default is spelled ONCE here rather than as a
# `Maybe.default` in twenty row builders. `"!OOB"` is the wall for an index
# past the end: CPython would raise `IndexError`, and a row whose index is
# out of range is a row nobody writes.



# `lt` and `pri` row builders. `r_lt` is the TYPE MAP over the whole grid plus the
# two weak dtypes whose absence from CPython's map is a `KeyError`, and `r_pri` is
# the ONE load-bearing numeric field `lt.fp` disambiguates half from bfloat16
# with -- a separate group so a renumbering of `spec.bend`'s priorities is a moved
# row and not a new spelling discovered later.
# The indexed-read primitive. `List.get` answers `Maybe` and EVERY caller
# in this file wants a `String` -- a multi-line emitter's `i`-th line, an
# argument's type -- so the default is spelled ONCE here rather than as a
# `Maybe.default` in twenty row builders. `"!OOB"` is the wall for an index
# past the end: CPython would raise `IndexError`, and a row whose index is
# out of range is a row nobody writes.




# `lt` and `pri` row builders. `r_lt` is the TYPE MAP over the whole grid plus the
# two weak dtypes whose absence from CPython's map is a `KeyError`, and `r_pri` is
# the ONE load-bearing numeric field `lt.fp` disambiguates half from bfloat16
# with -- a separate group so a renumbering of `spec.bend`'s priorities is a moved
# row and not a new spelling discovered later.
# The indexed-read primitive. `List.get` answers `Maybe` and EVERY caller
# in this file wants a `String` -- a multi-line emitter's `i`-th line, an
# argument's type -- so the default is spelled ONCE here rather than as a
# `Maybe.default` in twenty row builders. `"!OOB"` is the wall for an index
# past the end: CPython would raise `IndexError`, and a row whose index is
# out of range is a row nobody writes.




# `lt` and `pri` row builders. `r_lt` is the TYPE MAP over the whole grid plus the
# two weak dtypes whose absence from CPython's map is a `KeyError`, and `r_pri` is
# the ONE load-bearing numeric field `lt.fp` disambiguates half from bfloat16
# with -- a separate group so a renumbering of `spec.bend`'s priorities is a moved
# row and not a new spelling discovered later.
# The indexed-read primitive. `List.get` answers `Maybe` and EVERY caller
# in this file wants a `String` -- a multi-line emitter's `i`-th line, an
# argument's type -- so the default is spelled ONCE here rather than as a
# `Maybe.default` in twenty row builders. `"!OOB"` is the wall for an index
# past the end: CPython would raise `IndexError`, and a row whose index is
# out of range is a row nobody writes.
def nth_s(+xs: List<&2, String>, i: U32) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, U32.to_nat(i)), "!OOB")

def r_lt(+nm: String, +d: S.Dt, py: String) -> String: r(nm, lt.of(d), py)

def r_ltn(+nm: String, +d: S.Dt, cnt: U32, ptr: Bool, py: String) -> String: r(nm, lt.t(d, cnt, ptr), py)

def r_pri(+nm: String, +d: S.Dt, py: String) -> String: r(nm, U32.show(lt.pri(d)), py)

# `lt` and `pri` row builders. `r_lt` is the TYPE MAP over the whole grid plus the
# two weak dtypes whose absence from CPython's map is a `KeyError`, and `r_pri` is
# the ONE load-bearing numeric field `lt.fp` disambiguates half from bfloat16
# with -- a separate group so a renumbering of `spec.bend`'s priorities is a moved
# row and not a new spelling discovered later.
# The indexed-read primitive. `List.get` answers `Maybe` and EVERY caller
# in this file wants a `String` -- a multi-line emitter's `i`-th line, an
# argument's type -- so the default is spelled ONCE here rather than as a
# `Maybe.default` in twenty row builders. `"!OOB"` is the wall for an index
# past the end: CPython would raise `IndexError`, and a row whose index is
# out of range is a row nobody writes.




# ===========================================================================
# `base_rewrite` -- llvmir.py:77-144. THE EIGHTEEN RULES' OUTPUTS.
#
# `brN` IS RULE N. `br_rules` is the COUNT and it is a row rather than a comment
# because the count is the one thing about a `PatternMatcher` that is a property
# of CPython's table and not of anybody's reading of it. `br_rules(2)` is AMD's
# FIVE extra rules AHEAD of these (llvmir.py:232-242, `amd0`..`amd4` below),
# which is why AMD's table is 23 and not 18.
# ===========================================================================

# A `U32` may be consumed ONCE, so the second test cannot live in a nested
# `Bool.pick` arm -- it gets its own def. This is the shape every three-way
# dispatch in this file takes and it is the reason there is no `k of 3` helper.
def br_rules.b(+k: U32) -> U32: Bool.pick(U32, U32.is_eq(k, 1), 23, 5)

def br_rules(+k: U32) -> U32: Bool.pick(U32, U32.is_eq(k, 0), 18, br_rules.b(k))


# `ctx[x][1:]` -- the LABEL SLICE that drops the leading `%`. It appears in NINE
# of the eighteen rules and it is the one transformation in this file that is not
# a concatenation, so it gets its own rows rather than being inlined four times,
# where a dropped `drop` moves one caller and leaves the other three alone.
def lab(+xn: String) -> String: String.drop(xn, 1n)

def r_lab() -> String:
  String.concat([r("lab %v0", lab("%v0"), "v0"), r("lab %data0", lab("%data0"), "data0"),
    r("lab %reg_12", lab("%reg_12"), "reg_12"), r("lab %local_2", lab("%local_2"), "local_2"),
    r("lab %v99", lab("%v99"), "v99")])

# ---------------------------------------------------------------------------
# RULE 1, the REGISTER INDEX (llvmir.py:82-83). The ONLY rule that can answer
# `None`, and it does so for every addrspace that is not ALU: the line is
# `... if buf.addrspace == AddrSpace.ALU else None`. Three of these five rows say
# `None`, and that `None` is what makes `_render_kernel`'s `if l is None: raise`
# reachable from a LEGAL graph -- so the refusal below is not the only way to
# reach `RuntimeError`, and a gate that exercised only the refusal would miss it.
#
# `i32 {c.val}` is the CONST's VALUE, not `ctx[c]`, so the index and the name are
# different inputs; `br1 alu` (value 2) and `br1 alu i32` (value 1) keep them
# apart.
# ---------------------------------------------------------------------------
def br1.line(+is_alu: Bool, +xn: String, +bufn: String, +d: S.Dt, +cnt: U32, +idx: U32) -> String:
  Bool.pick(String, is_alu, String.concat(["  ", xn, " = extractelement ", lt.t(d, cnt, False{}),
    " ", bufn, ", i32 ", U32.show(idx)]), "None")

def r_br1(+nm: String, +is_alu: Bool, +bufn: String, +d: S.Dt, cnt: U32, idx: U32, +py: String) -> String:
  r(nm, br1.line(is_alu, "%v0", bufn, d, cnt, idx), py)

# ---------------------------------------------------------------------------
# RULE 2, the PREDICATED LOAD (llvmir.py:86-93). EIGHT lines -- the longest
# emitter in the file -- and every one is a row.
#
#     br label %X_entry / X_entry: / br i1 %mask, label %X_load, label %X_exit
#     X_load: / %X_yes = load [volatile ]TY, TY* %idx
#     br label %X_exit / X_exit: / %X = phi TY [%X_yes, %X_load], [%alt, %X_entry]
#
# FOUR `lt` CALLS and they are not one: the `load` takes the INDEX's dtype at the
# INDEX's own count, the pointer takes that count AND `ptr`, and the `phi` takes
# `x.dtype` at `x.max_numel()`. A reader that spells one `ty` and uses it four
# times agrees with CPython whenever the index and the loaded value share a dtype
# and a width -- which is the only relationship a first fixture can have, because
# both types come from one graph.
#
# `volatile ` IS PART OF THE FRAGMENT (llvmir.py:90 spells
# `{'volatile ' if ... else ''}`), so the volatile line reads `load volatile
# float, float*` -- one space, from the fragment -- and not `load  float`.
# ---------------------------------------------------------------------------
def br2.text(+vol: Bool, +d: S.Dt, +cnt: U32, +xn: String, +idx: String, +alt: String, +mask: String) -> String:
  String.concat([String.concat(["  br label ", xn, "_entry", nl()]),
    String.concat([lab(xn), "_entry:", nl()]),
    String.concat(["  br i1 ", mask, ", label ", xn, "_load, label ", xn, "_exit", nl()]),
    String.concat([lab(xn), "_load:", nl()]),
    String.concat(["  ", xn, "_yes = load ", volsp(vol), lt.t(d, cnt, False{}), ", ", lt.t(d, cnt, True{}), " ", idx, nl()]),
    String.concat(["  br label ", xn, "_exit", nl()]),
    String.concat([lab(xn), "_exit:", nl()]),
    String.concat(["  ", xn, " = phi ", lt.t(d, cnt, False{}), " [", xn, "_yes, ", xn, "_load], [", alt, ", ", xn, "_entry]"])])

def r_br2(+nm: String, +vol: Bool, +d: S.Dt, +xn: String, +idx: String, +alt: String, +mask: String, +i: U32, +py: String) -> String:
  r(nm, nth(String.lines(br2.text(vol, d, 1, xn, idx, alt, mask)), U32.to_nat(i)), py)

# ---------------------------------------------------------------------------
# RULES 3 and 4, the bare `load` and the `store` (llvmir.py:94-99). ONE line
# each, and the `store` puts the VALUE FIRST and the INDEX LAST -- the only place
# in this file that the two operand positions are asymmetric.
#
# BOTH take the INDEX's dtype for BOTH `lt` calls: `ldt(idx.dtype,
# idx.max_numel())` types the store's value too, which is NOT `var.dtype`. A port
# that threads `var.dtype` through agrees with CPython on every fixture whose
# value and index share a dtype -- which is every fixture in the table.
# ---------------------------------------------------------------------------
def br3.line(+vol: Bool, +d: S.Dt, +cnt: U32, +xn: String, +idx: String) -> String:
  String.concat(["  ", xn, " = load ", volsp(vol), lt.t(d, cnt, False{}), ", ", lt.t(d, cnt, True{}), " ", idx])

def br4.line(+vol: Bool, +d: S.Dt, +cnt: U32, +varn: String, +idx: String) -> String:
  String.concat(["  store ", volsp(vol), lt.t(d, cnt, False{}), " ", varn, ", ", lt.t(d, cnt, True{}), " ", idx])

def r_br3(+nm: String, +vol: Bool, +d: S.Dt, +xn: String, +idx: String, +py: String) -> String:
  r(nm, br3.line(vol, d, 1, xn, idx), py)

def r_br4(+nm: String, +vol: Bool, +d: S.Dt, +varn: String, +idx: String, +py: String) -> String:
  r(nm, br4.line(vol, d, 1, varn, idx), py)

# ---------------------------------------------------------------------------
# RULE 5, the STACK `insertelement` CHAIN (llvmir.py:102-105). The only LOOP in
# `base_rewrite`, and the only emitter whose lines depend on each other's
# INDICES:
#
#     "\n".join([(f"{ctx[x]}_{i}" if i+1 != len(x.src) else f"{ctx[x]}") +
#                f" = insertelement {ldt(x.dtype, x.max_numel())} " +
#                (f"{ctx[x]}_{i-1}" if i != 0 else "poison") +
#                f", {ldt(u.dtype)} {ctx[u]}, i32 {i}" for i,u in enumerate(x.src)])
#
# THREE facts in one expression. The LAST line carries the BARE name (`i+1 ==
# len`) and every earlier line the INDEXED one; the predecessor is `poison` at
# `i == 0` and `{ctx[x]}_{i-1}` after that -- so line 0 spells `poison` and line 1
# spells the INDEX OF LINE 0, not of line 1. `n=1` is the row that says a
# one-element STACK has no predecessor AND no indexed name; `n=4` is where both
# kinds of line and both predecessors are present.
#
# `lt.of(u.dtype)` is BARE -- count 1 -- while the element type is COUNTED at
# `x.max_numel()`, so `<16 x i8>` and `i8` in the same line are two different
# calls, and that is the only rule here that threads a LIST of dtypes rather than
# one. THE COUNT IS NOT `len(x.src)`: a one-element STACK of a 4-wide buffer
# answers `<4 x float>`, which is `br5 stack n 1 f32 [0]` and the row that stops a
# reader from using the list length twice -- once for `i+1 == len` and once for
# `max_numel`.
# ---------------------------------------------------------------------------
def br5.name(+xn: String, +i: U32, +n: U32) -> String:
  Bool.pick(String, U32.is_eq(U32.add(i, 1), n), xn, String.concat([xn, "_", U32.show(i)]))

def br5.pred(+xn: String, +i: U32) -> String:
  Bool.pick(String, U32.is_eq(i, 0), "poison", String.concat([xn, "_", U32.show(U32.sub(i, 1))]))

def nth_d(+xs: List<&2, S.Dt>, +i: U32) -> S.Dt: Maybe.default(&2, S.Dt, List.get(&2, S.Dt, xs, U32.to_nat(i)), S.void())

def sdts_len(+xs: List<&2, S.Dt>) -> U32: U32.from_nat(List.length(&2, S.Dt, xs))

def br5.line(+xn: String, +sdts: List<&2, S.Dt>, +snames: List<&2, String>, cnt: U32, +i: U32) -> String:
  String.concat(["  ", br5.name(xn, i, sdts_len(sdts)), " = insertelement ",
    lt.t(nth_d(sdts, 0), cnt, False{}), " ", br5.pred(xn, i), ", ",
    lt.of(nth_d(sdts, i)), " ", nth(snames, U32.to_nat(i)), ", i32 ", U32.show(i)])

def r_br5(+nm: String, +xn: String, +sdts: List<&2, S.Dt>, +snames: List<&2, String>, cnt: U32, +i: U32, +py: String) -> String:
  r(nm, br5.line(xn, sdts, snames, cnt, i), py)

# ---------------------------------------------------------------------------
# RULES 6-10: BITCAST, CAST, TRUNC, the BINARY `lop` and WHERE (llvmir.py:
# 107-115). Five ONE-LINE emitters, three of which end in a TYPE, so they are
# three independent exercises of `lt` and two of `N.lcast.a`.
#
# `lop[x.src[0].dtype][x.op]` is a KEY ERROR when the op is absent from that
# dtype's table -- which is the real `FDIV`-on-an-integer refusal, distinct from
# the `RuntimeError` in the walk. `br9 binary u8 FDIV` is the wall and
# `br9 binary f32 FDIV` is the row that says the wall is the TABLE and not the
# op; `N.lop.has` is the membership test and `N.lop.cell` is the value.
# ---------------------------------------------------------------------------
# THE ITEMSIZE WALL IS NOT THIS EMITTER'S. `UOp(Ops.BITCAST, ...)` asserts
# `in_dtype.itemsize == out_dtype.itemsize` in ops.py BEFORE `base_rewrite` is
# consulted, so `i8 -> float` is refused upstream and rule 6 never runs. Naming
# the wall here is convention 10; the row `br6 bitcast i8x1->f32x1` is what says
# the port does not answer a line where CPython raises.
def br6.same(+d: S.Dt, +od: S.Dt) -> Bool: U32.is_eq(S.Dt.itemsize(d), S.Dt.itemsize(od))

def br6.line(+d: S.Dt, +od: S.Dt, +cnt: U32, +xn: String, +s: String) -> String:
  Bool.pick(String, br6.same(d, od),
    String.concat(["  ", xn, " = bitcast ", lt.t(d, cnt, False{}), " ", s, " to ", lt.t(od, cnt, False{})]),
    "RuntimeError")

def br7.line(+d: S.Dt, +od: S.Dt, +xn: String, +s: String) -> String:
  String.concat(["  ", xn, " = ", N.lcast.a(d, od), " ", lt.of(d), " ", s, " to ", lt.of(od)])

# `ldt(x.dtype)` appears TWICE and `ldt(x.src[0].dtype)` once -- llvmir.py:111 --
# and a TRUNC's dtype is DERIVED from its source (ops.py:122), so all three are
# ONE call and the output dtype `od` is not read at all. That is why
# `br8 trunc f32->i32` prints `float` and not `i32`, and a port that threads the
# OUTPUT dtype through is wrong on every TRUNC row.
def br8.line(+d: S.Dt, +od: S.Dt, +xn: String, +s: String) -> String:
  String.concat(["  ", xn, " = call ", lt.of(d), " @llvm.trunc.", lt.of(d), "(", lt.of(d), " ", s, ")"])

def br9.line(+d: S.Dt, +op: O.Op, +xn: String, +s0: String, +s1: String) -> String:
  Bool.pick(String, N.lop.has(op, d),
    String.concat(["  ", xn, " = ", N.lop.cell(d, op), " ", lt.of(d), " ", s0, ", ", s1]), "KeyError")

def br10.line(+d0: S.Dt, +d1: S.Dt, +d2: S.Dt, +xn: String, +s0: String, +s1: String, +s2: String) -> String:
  String.concat(["  ", xn, " = select ", lt.of(d0), " ", s0, ", ", lt.of(d1), " ", s1, ", ", lt.of(d2), " ", s2])

def r_br6(+nm: String, +fd: S.Dt, +od: S.Dt, +cnt: U32, +xn: String, +sn: String, py: String) -> String:
  r(nm, br6.line(fd, od, cnt, xn, sn), py)

def r_br7(+nm: String, +a: S.Dt, +b: S.Dt, +xn: String, +sn: String, py: String) -> String:
  r(nm, br7.line(a, b, xn, sn), py)

def r_br8(+nm: String, +a: S.Dt, +b: S.Dt, +xn: String, +sn: String, py: String) -> String:
  r(nm, br8.line(a, b, xn, sn), py)

def r_br9(+nm: String, +d: S.Dt, +op: O.Op, +xn: String, +s0: String, +s1: String, py: String) -> String:
  r(nm, br9.line(d, op, xn, s0, s1), py)

def r_br10(+nm: String, +d0: S.Dt, +d1: S.Dt, +d2: S.Dt, +xn: String, +s0: String, +s1: String, +s2: String, py: String) -> String:
  r(nm, br10.line(d0, d1, d2, xn, s0, s1, s2), py)

# ---------------------------------------------------------------------------
# RULES 11-14: the void-RANGE header, the BACKEDGE, the counted RANGE (NINE
# lines) and the END. All four are built on `lab(...)` or on `range_str`, so a `%`
# that never gets dropped is a DIFFERENT LABEL on four of the five.
#
# THE FIVE LABELS ARE `range_str`'s, NOT THE WALK'S. `loop_{r}`, `loop_entry_`,
# `loop_latch_{r}`, `loop_footer_{r}`, `loop_body_{r}`, `loop_exit_{r}` -- and `r`
# here is `range_str(r)`, whose leading digit is the AXIS ID and not `ctx[r][1:]`.
# A port that used `lab(ctx[r])` answers `loop_v3` where CPython answers `loop_0`,
# and all nine lines of the counted RANGE are wrong TOGETHER -- which is why
# `br13 range` (axis 0) and `br13 range neg` (axis 3) are two groups and not one.
#
# The counted RANGE also reads a FIFTH thing nobody else does: `ctx[r.src[0]]`,
# the bound, which is a NAME in the `icmp` and is not the constant 16. Dropping it
# moves ONE row out of nine, and that row is `[6]`.
# ---------------------------------------------------------------------------
def br11.text(+rn: String) -> String:
  String.concat(["  br label %loop_", lab(rn), nl(), "loop_", lab(rn), ":"])

def br12.text(+rn: String, +cn: String) -> String:
  String.concat(["  br i1 ", cn, ", label %loop_", lab(rn), ", label %loop_exit_", lab(rn), nl(),
    "loop_exit_", lab(rn), ":"])

def br13.text(+aid: String, +rn: String, +bn: String, +d: S.Dt) -> String:
  String.concat([String.concat(["  br label %loop_entry_", aid, nl(), "loop_entry_", aid, ":", nl()]),
    String.concat(["  br label %loop_latch_", aid, nl(), "loop_latch_", aid, ":", nl()]),
    String.concat(["  ", rn, " = phi ", lt.of(d), " [ 0, %loop_entry_", aid, " ], [ ", rn, "phi, %loop_footer_", aid, " ]", nl()]),
    String.concat(["  ", rn, "phi = add ", lt.of(d), " ", rn, ", 1", nl()]),
    String.concat(["  ", rn, "cmp = icmp ult ", lt.of(d), " ", rn, ", ", bn, nl()]),
    String.concat(["  br i1 ", rn, "cmp, label %loop_body_", aid, ", label %loop_exit_", aid, nl()]),
    String.concat(["loop_body_", aid, ":"])])

def br14.text(+aid: String) -> String:
  String.concat(["  br label %loop_footer_", aid, nl(), "loop_footer_", aid, ":", nl(),
    "  br label %loop_latch_", aid, nl(), "loop_exit_", aid, ":"])

def r_br11(+nm: String, +rn: String, i: U32, py: String) -> String:
  r(nm, nth_s(String.lines(br11.text(rn)), i), py)

def r_br12(+nm: String, +rn: String, +cn: String, i: U32, py: String) -> String:
  r(nm, nth_s(String.lines(br12.text(rn, cn)), i), py)

def r_br13(+nm: String, +aid: String, +rn: String, +bn: String, +d: S.Dt, i: U32, py: String) -> String:
  r(nm, nth_s(String.lines(br13.text(aid, rn, bn, d)), i), py)

def r_br14(+nm: String, aid: U32, i: U32, py: String) -> String:
  r(nm, nth_s(String.lines(br14.text(U32.show(aid))), i), py)

# ---------------------------------------------------------------------------
# RULES 15-17 AND THE AMD BARRIER (llvmir.py:140-143, :236). The IF header and the
# ENDIF both label from the IF's name, not from their own -- `br16 endif bool`
# takes the ENDIF's `%v8` and answers `ifskip_v7`, which is the one place in this
# file where a rule's subject is not the name it prints. That is the row pair
# `br15 if bool [1]` and `br16 endif bool [1]`.
#
# `br17 barrier` is `  fence seq_cst` -- TWO leading spaces and NO syncscope --
# and `amd2 barrier` is `L.barrier`, the THREE-LINE constant `nir_llvmir.bend`
# already owns, with an EMPTY FOURTH line from its trailing newline. They are
# different strings, so they are different rows; a reader who gave AMD the CPU
# rule's answer moves three and a reader who drops AMD's empty tail moves one.
# ---------------------------------------------------------------------------
def br15.text(+xn: String, +cn: String) -> String:
  String.concat(["  br i1 ", cn, ", label %ifbody_", lab(xn), ", label %ifskip_", lab(xn), nl(),
    "ifbody_", lab(xn), ":"])

def br16.text(+ifn: String) -> String:
  String.concat(["  br label %ifskip_", lab(ifn), nl(), "ifskip_", lab(ifn), ":"])

def br17.text() -> String: "  fence seq_cst"

def r_br15(+nm: String, +xn: String, +cn: String, i: U32, py: String) -> String:
  r(nm, nth_s(String.lines(br15.text(xn, cn)), i), py)

def r_br16(+nm: String, +ifn: String, i: U32, py: String) -> String:
  r(nm, nth_s(String.lines(br16.text(ifn)), i), py)

def r_br17(+nm: String, py: String) -> String: r(nm, br17.text(), py)

def r_amd2(+nm: String, i: U32, py: String) -> String:
  r(nm, nth_s(String.lines(String.join(N.barrier(), nl())), i), py)

# ---------------------------------------------------------------------------
# AMD'S FIVE RULES AHEAD OF `base_rewrite` (llvmir.py:232-242). Rule 3's TWO
# SPACES after the argument type and rule 4's synthesized `%v0_i32` are the two
# things here that a re-implementation gets wrong by being tidy.
#
# `fp8_index` IS `renderer/cstyle.bend`'s TOO and it is NOT THERE either -- that
# file DOCUMENTS `fp8s.index(d) % 2` at :612 and has no def -- so it is here, and
# the position is the load-bearing half:
#
#     fp8_index = dtypes.fp8s.index(dtype) % 2     (cstyle.py:494)
#
# `fp8e5m2` is at 1 and `fp8e5m2fnuz` at 3; BOTH are odd, so both answer 1, while
# `fp8e4m3` is at 0 and `fp8e4m3fnuz` at 2 and both answer 0. A reader that tested
# `is_fnuz` instead would answer the OPPOSITE on all four -- and `amd3`'s `i1`
# argument and `amd4`'s `bf8`/`fp8` spelling are both driven by it, so eight rows
# move. `fp8s.order` is the row that says the ORDER is the table.
def f8pos.go(+ds: List<&2, S.Dt>, +d: S.Dt, +i: U32) -> U32:
  match ds:
    case Nil{}      : 4294967295
    case h <> +t    : Bool.pick(U32, O.eq_dt(h, d), i, f8pos.go(t, d, U32.add(i, 1)))

# `f8pos.go`'s miss is CPython's `list.index()` raising `ValueError`, so 4294967295
# is a SENTINEL and not an index: `fp8_pos i32` is the row that makes it reachable,
# and a reader who answers 0 for a miss would agree with CPython on the FOUR fp8
# rows and be wrong everywhere else.
def f8pos.miss(+m: U32) -> String: Bool.pick(String, U32.is_eq(m, 4294967295), "ValueError", U32.show(m))

def f8pos(+d: S.Dt) -> U32: f8pos.go(N.fp8s(), d, 0)

def fp8i(+d: S.Dt) -> U32: U32.mod(f8pos(d), 2)

def f8names.go(+ds: List<&2, S.Dt>, +acc: String) -> String:
  match ds:
    case Nil{}      : acc
    case h <> +t    : String.concat([acc, dtn(h), Bool.pick(String, List.is_empty(&2, S.Dt, t), "",
      String.concat([",", f8names.go(t, "")]))])

def f8names() -> String: f8names.go(N.fp8s(), "")

def r_f8o(+nm: String) -> String: r("fp8s.order", f8names(), nm)

def r_f8i(+nm: String, +d: S.Dt, +py: String) -> String:
  r(String.concat(["fp8_index ", nm]), U32.show(fp8i(d)), py)

def r_f8p(+nm: String, +d: S.Dt, +py: String) -> String:
  r(String.concat(["fp8_pos ", nm]), f8pos.miss(f8pos(d)), py)

# THE SAME WALL THROUGH THE OTHER DIRECTION, as its own pair of defs: `fp8_pos i32`
# and `fp8_index i32` are two rows of the SAME miss and they are what make the
# sentinel reachable. One def for both would give one of them the other's NAME.
def r_f8mp(+nm: String, +d: S.Dt, +py: String) -> String: r(String.concat(["fp8_pos ", nm]), f8pos.miss(f8pos(d)), py)

def r_f8mi(+nm: String, +d: S.Dt, +py: String) -> String: r(String.concat(["fp8_index ", nm]), f8pos.miss(f8pos(d)), py)
# ---------------------------------------------------------------------------
def amd0.text(+is_l: Bool, +x: U32, +xn: String) -> String:
  String.concat(["  ", xn, " = ", N.wi(is_l, x), "; "])

def amd1.line(+op: O.Op, +d: S.Dt, +od: S.Dt, +xn: String, +s: String) -> String:
  String.concat(["  ", xn, " = call ", lt.of(od), " @llvm.", N.intr_of(op), ".", lt.of(od), "(", lt.of(d), " ", s, ")"])

def amd3.line(+xn: String, +s: String, +bf8: U32) -> String:
  String.concat(["  ", xn, " = call i8 @f32_to_fp8(float  ", s, ", i1 ", U32.show(bf8), ")"])

def amd4.text(+bf8: U32, +xn: String, +s: String) -> String:
  String.concat([String.concat(["  ", xn, "_i32 = zext i8 ", s, " to i32"]), nl(),
    String.concat(["  ", xn, " = call float @llvm.amdgcn.cvt.f32.", Bool.pick(String, U32.is_eq(bf8, 1), "bf8", "fp8"),
      "(i32 ", xn, "_i32, i32 0)"])])

def r_amd0(+nm: String, +is_l: Bool, x: U32, +xn: String, py: String) -> String:
  r(nm, amd0.text(is_l, x, xn), py)

def r_amd1(+nm: String, +op: O.Op, +a: S.Dt, +b: S.Dt, +xn: String, +sn: String, py: String) -> String:
  r(nm, amd1.line(op, a, b, xn, sn), py)

def r_amd3(+nm: String, +fp8: S.Dt, +xn: String, +sn: String, +py: String) -> String:
  r(nm, amd3.line(xn, sn, fp8i(fp8)), py)

def r_amd4(+nm: String, +fp8: S.Dt, +xn: String, +sn: String, i: U32, +py: String) -> String:
  r(nm, nth_s(String.lines(amd4.text(fp8i(fp8), xn, sn)), i), py)

# ---------------------------------------------------------------------------
# `_render_fn` -- llvmir.py:156-160, the AMD barrier rule, and `_render_footer`.
# ===========================================================================

# `sargs`, ONE argument (llvmir.py:158-159):
#
#     f"{ldt(u.dtype, ptr=u.addrspace == AddrSpace.GLOBAL)}{' noalias' if u.addrspace == GLOBAL else ''} " + name
#
# `ptr` and `noalias` are BOTH keyed on GLOBAL, so a GLOBAL argument reads
# `float* noalias %data0` -- two clauses, ONE condition -- and the other three
# read `float %data0`. `rfn sargs global` and `rfn sargs reg` are the pair: one
# of them alone is a fixture that cannot see the other, because the TYPE half is
# identical and only the SUFFIX differs. The join is `", "` and its empty answer
# is `""` -- `rfn sargs empty` is the row that says a zero-argument kernel reads
# `define void @f()` with NO space before the paren.
def sargs.one(+is_glob: Bool, +d: S.Dt, +nm: String) -> String:
  String.concat([lt.t(d, 1, is_glob), Bool.pick(String, is_glob, " noalias", ""), " ", nm])

def sargs.many(+xs: List<&2, String>) -> String: String.join(xs, ", ")

# `"\n".join((prefix or []) + [f"define{' '+abi if abi else ''} void @{name}({sargs}) #0", "{"] + kernel + ["  ret void\n}"])`
#
# The ABI SLOT carries its OWN leading space (`' ' + self.abi`), so `define
# amdgpu_kernel void` and `define void` differ by a space INSIDE the slot and not
# before `void`. The LAST element is `"  ret void\n}"` -- ONE string with a
# newline in it -- so the join yields `  ret void` and `}` as two LINES, and that
# is why every `rfn` group has `}` as its final row.
#
# `prefix or []` puts AMD's `f32_to_fp8` prologue ahead of the `define`, and
# `rfn prefix [0..1]` are its two lines. A dropped prefix shows as a MISSING
# line, which no boolean about the joined string would notice -- the line indices
# are what see it.
# THE ABI SLOT IS `' ' + self.abi` INSIDE the conditional, so the SPACE rides the
# abi and ` void @` is OUTSIDE it: `define void @f` and `define amdgpu_kernel void
# @f` differ by the abi AND its leading space and by nothing else. Putting the
# ` void @` inside the conditional is the reading that answers a bare `define`,
# which is what the first draft did and what `rfn abi None global [0]` saw.
def rfn.slot(+abi: String) -> String: Bool.pick(String, String.eq(abi, ""), "", String.concat([" ", abi]))

def rfn.define(+abi: String, +nm: String, +sa: String) -> String:
  String.concat(["define", rfn.slot(abi), " void @", nm, "(", sa, ") #0"])

# `List.append` NESTING IS ONE DEEP in this toolchain -- three chained appends in
# one expression typechecks as a call with a length where a list belongs, and the
# error names `Quant` rather than `List`. `rfn.cat` is the one level of nesting
# that works, and it is a named def so the constraint is written down once.
def rfn.cat(+a: List<&2, String>, +b: List<&2, String>) -> List<&2, String>: List.append(&2, String, a, b)

def rfn.all(+abi: String, +nm: String, +sa: String, +kern: List<&2, String>, +pfx: List<&2, String>) -> String:
  String.join(rfn.cat(rfn.cat(pfx, rfn.cat([rfn.define(abi, nm, sa), "{"], kern)), ["  ret void", "}"]), nl())


def r_rfn(+nm: String, +abi: String, +kname: String, +sa: String, +kern: List<&2, String>, +pfx: List<&2, String>, +i: U32, +py: String) -> String:
  r(nm, nth_s(String.lines(rfn.all(abi, kname, sa, kern, pfx)), i), py)

def r_rsargs(+nm: String, +is_glob: Bool, +d: S.Dt, +argn: String, +py: String) -> String:
  r(nm, sargs.one(is_glob, d, argn), py)

def r_rsargs2e(+nm: String, +py: String) -> String: r(nm, sargs.many(Nil{}), py)

def r_rsargs2(+nm: String, +is_glob: Bool, +a: S.Dt, +b: S.Dt, +py: String) -> String:
  r(nm, sargs.many([sargs.one(is_glob, a, "%data0"), sargs.one(is_glob, b, "%data1")]), py)

# `CPU._render_footer` -- llvmir.py:210. A CONSTANT STRING with five attributes in
# a fixed order, so it is one row plus the nine space-separated PARTS: a reader who
# reorders them moves the joined row and every part row at once, and a reader who
# drops one quote moves `ftr cpu part 6` alone.
def ftr.cpu() -> String:
  String.concat(["attributes #0 = { alwaysinline nounwind \"no-builtins\" \"no-trapping-math\"=\"true\" }"])

def ftr.cpu_part(+i: U32) -> String:
  nth_s(String.split(ftr.cpu(), Char.from_u32(32)), i)

# `AMD._render_footer` -- llvmir.py:265-271. Its ONE input is
# `prod([d.vmax for d in uops if u.op is SPECIAL and u.arg[0] == "l"])` and the
# filter is as load-bearing as the product: `ftr amd prod wglobal` and
# `ftr amd prod wgl` are the two rows where a `g` contributes nothing and a `l`
# contributes 16. `prod([])` is 1 and `ftr amd prod none` is that row -- a reader
# who wrote `max(1, ...)` answers the same thing and is therefore untestable here,
# so the claim is stated rather than claimed to be covered.
#
# `d.vmax` is `uop/ops.bend`'s `nc`/Variable machinery, so the WIDTHS are
# parameters here and the filter plus the product are this file's.
def prod.go(+ws: List<&2, U32>, +acc: U32) -> U32:
  match ws:
    case Nil{}   : acc
    case w <> +t : prod.go(t, U32.mul(acc, w))

def prod(+ws: List<&2, U32>) -> U32: prod.go(ws, 1)

# `ftr amd prod <lab>` is the DERIVED work-group size on its own -- the arithmetic,
# nine rows -- and `ftr amd <lab>` is the JOINED ATTRIBUTE STRING it is
# interpolated into. Both exist because a reader can get the NUMBER right while
# dropping one of the five attributes, and that reader moves the second and NONE
# of the nine. M69 in the mutation table is the shape of that bug: dropping the
# leading `1,` moves the joined rows alone.
def ftr.amd(+wg: U32) -> String:
  String.concat(["attributes #0 = { alwaysinline nounwind \"no-builtins\" \"amdgpu-flat-work-group-size\"=\"1,",
    U32.show(wg), "\" \"no-trapping-math\"=\"true\" }"])

def r_ftra(+nm: String, +ws: List<&2, U32>, +py: String) -> String: r(nm, ftr.amd(prod(ws)), py)

# `r_ftrc` is the CPU footer's CONSTANT string and `r_ftr` the AMD one, which
# DERIVES its work-group size from `prod([d.vmax for d in uops if ... arg[0] ==
# "l"])`. The filter is as load-bearing as the product -- `amd prod wglobal` and
# `amd prod wgl` are the rows where a `g` contributes nothing and a `l`
# contributes 16 -- and `prod([])` is 1, which is `amd prod none`. A reader who
# wrote `max(1, ...)` answers the same thing and is therefore UNTESTABLE here, so
# the claim is stated rather than claimed to be covered.
#
# `d.vmax` is `uop/ops.bend`'s `nc`/Variable machinery, so the WIDTHS are
# parameters here and the filter plus the product are this file's.
def r_ftr(+nm: String, +ws: List<&2, U32>, +py: String) -> String: r(nm, U32.show(prod(ws)), py)

def r_ftrc(+nm: String, +py: String) -> String: r(nm, ftr.cpu(), py)

def r_ftrp(+i: U32, +py: String) -> String:
  r(String.concat(["ftr cpu part ", U32.show(i)]), ftr.cpu_part(i), py)

# `AMDLLVMRenderer.is_rdna4` -- llvmir.py:273: `arch.split(':')[0] in {'gfx1200',
# 'gfx1201'}`. The `:` matters and so does the `split`: `gfx1200:xnack-` is True
# and `gfx1200x` is False, and a `starts_with("gfx1200")` reader gets the second
# right and the third WRONG -- which is why `is_rdna4 gfx12001` and
# `is_rdna4 gfx1200x` are rows and not one.
def rd4.split(+arch: String) -> String: nth_s(String.split(arch, Char.from_u32(58)), 0)

def rd4.is_g1(+a: String) -> Bool: String.eq(a, "gfx1200")

def rd4.is(+arch: String) -> Bool:
  Bool.or(rd4.is_g1(rd4.split(arch)), String.eq(rd4.split(arch), "gfx1201"))

def r_rdna(+arch: String, +py: String) -> String: r(String.concat(["is_rdna4 ", arch]), bs(rd4.is(arch)), py)

def r_lts() -> String:
  String.concat([r_lt("lt void", S.void(), "void"), r_lt("lt weakfloat", S.weakfloat(), "KeyError"), r_lt("lt weakint", S.weakint(), "KeyError"), r_lt("lt fp8e4m3", S.fp8e4m3(), "i8"), r_lt("lt fp8e5m2", S.fp8e5m2(), "i8"), r_lt("lt fp8e4m3fnuz", S.fp8e4m3fnuz(), "i8"), r_lt("lt fp8e5m2fnuz", S.fp8e5m2fnuz(), "i8"), r_lt("lt f16", S.half(), "half"), r_lt("lt bf16", S.bfloat16(), "bfloat"), r_lt("lt f32", S.single(), "float"), r_lt("lt f64", S.double(), "double"), r_lt("lt u8", S.uint8(), "i8"), r_lt("lt u16", S.uint16(), "i16"), r_lt("lt u32", S.uint32(), "i32"), r_lt("lt u64", S.uint64(), "i64"), r_lt("lt i8", S.int8(), "i8"), r_lt("lt i16", S.int16(), "i16"), r_lt("lt i32", S.int32(), "i32"), r_lt("lt i64", S.int64(), "i64"), r_lt("lt bool", S.boolean(), "i1"), r_ltn("lt 1 ptr f32", S.single(), 1, True{}, "float*"), r_ltn("lt 4     f32", S.single(), 4, False{}, "<4 x float>"), r_ltn("lt 4 ptr f32", S.single(), 4, True{}, "<4 x float>*"), r_ltn("lt 1 ptr f32", S.single(), 1, True{}, "float*"), r_ltn("lt 8     f64", S.double(), 8, False{}, "<8 x double>"), r_ltn("lt 2 ptr bf16", S.bfloat16(), 2, True{}, "<2 x bfloat>*")])

def r_pris() -> String:
  String.concat([r_pri("pri fp8e4m3", S.fp8e4m3(), "10"), r_pri("pri fp8e5m2", S.fp8e5m2(), "11"), r_pri("pri fp8e4m3fnuz", S.fp8e4m3fnuz(), "10"), r_pri("pri fp8e5m2fnuz", S.fp8e5m2fnuz(), "11"), r_pri("pri f16", S.half(), "12"), r_pri("pri bf16", S.bfloat16(), "13"), r_pri("pri f32", S.single(), "14"), r_pri("pri f64", S.double(), "15"), r_pri("pri u8", S.uint8(), "2"), r_pri("pri u16", S.uint16(), "4"), r_pri("pri u32", S.uint32(), "6"), r_pri("pri u64", S.uint64(), "8"), r_pri("pri i8", S.int8(), "1"), r_pri("pri i16", S.int16(), "3"), r_pri("pri i32", S.int32(), "5"), r_pri("pri i64", S.int64(), "7"), r_pri("pri bool", S.boolean(), "0")])

def r_ivs() -> String:
  String.concat([r_iv("is_volatile PARAM vol False", True{}, False{}, "False"), r_iv("is_volatile PARAM vol True", True{}, True{}, "True"), r_iv("is_volatile CAST vol False", True{}, False{}, "False"), r_iv("is_volatile CAST vol True", True{}, True{}, "True"), r_iv("is_volatile BUFFER vol False", False{}, False{}, "False"), r_iv("is_volatile BUFFER vol True", False{}, True{}, "False"), r_iv("is_volatile CONST vol False", False{}, False{}, "False"), r_iv("is_volatile CONST vol True", False{}, True{}, "False"), r_iv("is_volatile AFTER vol False", True{}, False{}, "False"), r_iv("is_volatile AFTER vol True", True{}, True{}, "True")])

def r_lc1s() -> String:
  String.concat([r_lcs("lconst special +inf", True{}, False{}, "0x7FF0000000000000"), r_lcs("lconst special -inf", False{}, False{}, "0xFFF0000000000000"), r_lcs("lconst special +nan", True{}, True{}, "0x7FF8000000000000"), r_lcs("lconst special -nan", False{}, True{}, "0xFFF8000000000000"), r_lcb("lconst branch void", S.void(), "int"), r_lcb("lconst branch bool", S.boolean(), "int"), r_lcb("lconst branch i8", S.int8(), "int"), r_lcb("lconst branch i16", S.int16(), "int"), r_lcb("lconst branch i32", S.int32(), "int"), r_lcb("lconst branch i64", S.int64(), "int"), r_lcb("lconst branch u8", S.uint8(), "int"), r_lcb("lconst branch u16", S.uint16(), "int"), r_lcb("lconst branch u32", S.uint32(), "int"), r_lcb("lconst branch u64", S.uint64(), "int"), r_lcb("lconst branch fp8e4m3", S.fp8e4m3(), "dtype.float_to_fp8"), r_lcb("lconst branch fp8e5m2", S.fp8e5m2(), "dtype.float_to_fp8"), r_lcb("lconst branch fp8e4m3fnuz", S.fp8e4m3fnuz(), "dtype.float_to_fp8"), r_lcb("lconst branch fp8e5m2fnuz", S.fp8e5m2fnuz(), "dtype.float_to_fp8"), r_lcb("lconst branch f16", S.half(), "dtype.truncate"), r_lcb("lconst branch bf16", S.bfloat16(), "dtype.truncate"), r_lcb("lconst branch f32", S.single(), "dtype.truncate"), r_lcb("lconst branch f64", S.double(), "dtype.truncate"), r_lci("lconst int 1.9", 1.9, "1"), r_lci("lconst int -1.9", F32.neg(1.9), "-1"), r_lci("lconst int 0.0", 0.0, "0"), r_lci("lconst int 255.5", 255.5, "255"), r_lci("lconst int -256.5", F32.neg(256.5), "-256"), r_lci("lconst int 2.5", 2.5, "2"), r_lci("lconst int -2.5", F32.neg(2.5), "-2"), r_lci("lconst uint 2.5", 2.5, "2"), r_lci("lconst uint -2.5", F32.neg(2.5), "-2"), r_lci("lconst uint 1.5", 1.5, "1")])

def r_rss() -> String:
  String.concat([r_rsn("range_str neg 3", 3, "m3"), r_rsn("range_str neg 0", 0, "m0"), r_rsn("range_str neg 12", 12, "m12"), r_rs("range_str 0", [0], "0"), r_rs("range_str 3", [3], "3"), r_rs("range_str 0,1", [0, 1], "0_1"), r_rs("range_str 2,0,1", [2, 0, 1], "2_0_1"), r_rs("range_str 7,8,9", [7, 8, 9], "7_8_9")])

def r_cnts() -> String:
  String.concat([r("base_rewrite.rules", U32.show(br_rules(0)), "18"), r("amd.string_rewrite.rules", U32.show(br_rules(1)), "23"), r("base_rewrite.after_amd", U32.show(br_rules(2)), "5")])

def r_br1s() -> String:
  String.concat([r_br1("br1 extractelement alu", True{}, "%reg_1", S.single(), 4, 2, "  %v0 = extractelement <4 x float> %reg_1, i32 2"), r_br1("br1 extractelement reg", False{}, "%reg_1", S.single(), 4, 2, "None"), r_br1("br1 extractelement global", False{}, "%reg_1", S.single(), 4, 2, "None"), r_br1("br1 extractelement local", False{}, "%reg_1", S.single(), 4, 2, "None"), r_br1("br1 extractelement alu i32", True{}, "%reg_1", S.int32(), 4, 1, "  %v0 = extractelement <4 x i32> %reg_1, i32 1")])

def r_br2s() -> String:
  String.concat([r_br2("br2 load vol False f32 [0]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 0, "  br label %v0_entry"), r_br2("br2 load vol False f32 [1]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 1, "v0_entry:"), r_br2("br2 load vol False f32 [2]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 2, "  br i1 %v2, label %v0_load, label %v0_exit"), r_br2("br2 load vol False f32 [3]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 3, "v0_load:"), r_br2("br2 load vol False f32 [4]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 4, "  %v0_yes = load float, float* %v1"), r_br2("br2 load vol False f32 [5]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 5, "  br label %v0_exit"), r_br2("br2 load vol False f32 [6]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 6, "v0_exit:"), r_br2("br2 load vol False f32 [7]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 7, "  %v0 = phi float [%v0_yes, %v0_load], [%reg_0, %v0_entry]"), r_br2("br2 load vol False i32 [0]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 0, "  br label %v0_entry"), r_br2("br2 load vol False i32 [1]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 1, "v0_entry:"), r_br2("br2 load vol False i32 [2]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 2, "  br i1 %v2, label %v0_load, label %v0_exit"), r_br2("br2 load vol False i32 [3]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 3, "v0_load:"), r_br2("br2 load vol False i32 [4]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 4, "  %v0_yes = load i32, i32* %v1"), r_br2("br2 load vol False i32 [5]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 5, "  br label %v0_exit"), r_br2("br2 load vol False i32 [6]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 6, "v0_exit:"), r_br2("br2 load vol False i32 [7]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 7, "  %v0 = phi i32 [%v0_yes, %v0_load], [%reg_0, %v0_entry]"), r_br2("br2 load vol False u8 [0]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 0, "  br label %v0_entry"), r_br2("br2 load vol False u8 [1]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 1, "v0_entry:"), r_br2("br2 load vol False u8 [2]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 2, "  br i1 %v2, label %v0_load, label %v0_exit"), r_br2("br2 load vol False u8 [3]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 3, "v0_load:"), r_br2("br2 load vol False u8 [4]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 4, "  %v0_yes = load i8, i8* %v1"), r_br2("br2 load vol False u8 [5]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 5, "  br label %v0_exit"), r_br2("br2 load vol False u8 [6]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 6, "v0_exit:"), r_br2("br2 load vol False u8 [7]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 7, "  %v0 = phi i8 [%v0_yes, %v0_load], [%reg_0, %v0_entry]"), r_br2("br2 load vol True f32 [0]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 0, "  br label %v0_entry"), r_br2("br2 load vol True f32 [1]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 1, "v0_entry:"), r_br2("br2 load vol True f32 [2]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 2, "  br i1 %v2, label %v0_load, label %v0_exit"), r_br2("br2 load vol True f32 [3]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 3, "v0_load:"), r_br2("br2 load vol True f32 [4]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 4, "  %v0_yes = load volatile float, float* %v1"), r_br2("br2 load vol True f32 [5]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 5, "  br label %v0_exit"), r_br2("br2 load vol True f32 [6]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 6, "v0_exit:"), r_br2("br2 load vol True f32 [7]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 7, "  %v0 = phi float [%v0_yes, %v0_load], [%reg_0, %v0_entry]"), r_br2("br2 load vol True i32 [0]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 0, "  br label %v0_entry"), r_br2("br2 load vol True i32 [1]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 1, "v0_entry:"), r_br2("br2 load vol True i32 [2]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 2, "  br i1 %v2, label %v0_load, label %v0_exit"), r_br2("br2 load vol True i32 [3]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 3, "v0_load:"), r_br2("br2 load vol True i32 [4]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 4, "  %v0_yes = load volatile i32, i32* %v1"), r_br2("br2 load vol True i32 [5]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 5, "  br label %v0_exit"), r_br2("br2 load vol True i32 [6]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 6, "v0_exit:"), r_br2("br2 load vol True i32 [7]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 7, "  %v0 = phi i32 [%v0_yes, %v0_load], [%reg_0, %v0_entry]"), r_br2("br2 load vol True u8 [0]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 0, "  br label %v0_entry"), r_br2("br2 load vol True u8 [1]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 1, "v0_entry:"), r_br2("br2 load vol True u8 [2]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 2, "  br i1 %v2, label %v0_load, label %v0_exit"), r_br2("br2 load vol True u8 [3]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 3, "v0_load:"), r_br2("br2 load vol True u8 [4]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 4, "  %v0_yes = load volatile i8, i8* %v1"), r_br2("br2 load vol True u8 [5]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 5, "  br label %v0_exit"), r_br2("br2 load vol True u8 [6]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 6, "v0_exit:"), r_br2("br2 load vol True u8 [7]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 7, "  %v0 = phi i8 [%v0_yes, %v0_load], [%reg_0, %v0_entry]")])

def r_br34s() -> String:
  String.concat([r_br3("br3 load vol False f32", False{}, S.single(), "%v0", "%v1", "  %v0 = load float, float* %v1"), r_br4("br4 store vol False f32", False{}, S.single(), "%v2", "%v1", "  store float %v2, float* %v1"), r_br3("br3 load vol False i8", False{}, S.int8(), "%v0", "%v1", "  %v0 = load i8, i8* %v1"), r_br4("br4 store vol False i8", False{}, S.int8(), "%v2", "%v1", "  store i8 %v2, i8* %v1"), r_br3("br3 load vol False u64", False{}, S.uint64(), "%v0", "%v1", "  %v0 = load i64, i64* %v1"), r_br4("br4 store vol False u64", False{}, S.uint64(), "%v2", "%v1", "  store i64 %v2, i64* %v1"), r_br3("br3 load vol True f32", True{}, S.single(), "%v0", "%v1", "  %v0 = load volatile float, float* %v1"), r_br4("br4 store vol True f32", True{}, S.single(), "%v2", "%v1", "  store volatile float %v2, float* %v1"), r_br3("br3 load vol True i8", True{}, S.int8(), "%v0", "%v1", "  %v0 = load volatile i8, i8* %v1"), r_br4("br4 store vol True i8", True{}, S.int8(), "%v2", "%v1", "  store volatile i8 %v2, i8* %v1"), r_br3("br3 load vol True u64", True{}, S.uint64(), "%v0", "%v1", "  %v0 = load volatile i64, i64* %v1"), r_br4("br4 store vol True u64", True{}, S.uint64(), "%v2", "%v1", "  store volatile i64 %v2, i64* %v1")])

def r_br5s() -> String:
  String.concat([r_br5("br5 stack n 1 f32 [0]", "%v0", [S.single()], ["%v1"], 4, 0, "  %v0 = insertelement <4 x float> poison, float %v1, i32 0"), r_br5("br5 stack n 2 f32 [0]", "%v0", [S.single(), S.single()], ["%v1", "%v2"], 8, 0, "  %v0_0 = insertelement <8 x float> poison, float %v1, i32 0"), r_br5("br5 stack n 2 f32 [1]", "%v0", [S.single(), S.single()], ["%v1", "%v2"], 8, 1, "  %v0 = insertelement <8 x float> %v0_0, float %v2, i32 1"), r_br5("br5 stack n 4 u8 [0]", "%v0", [S.uint8(), S.uint8(), S.uint8(), S.uint8()], ["%v1", "%v2", "%v3", "%v4"], 16, 0, "  %v0_0 = insertelement <16 x i8> poison, i8 %v1, i32 0"), r_br5("br5 stack n 4 u8 [1]", "%v0", [S.uint8(), S.uint8(), S.uint8(), S.uint8()], ["%v1", "%v2", "%v3", "%v4"], 16, 1, "  %v0_1 = insertelement <16 x i8> %v0_0, i8 %v2, i32 1"), r_br5("br5 stack n 4 u8 [2]", "%v0", [S.uint8(), S.uint8(), S.uint8(), S.uint8()], ["%v1", "%v2", "%v3", "%v4"], 16, 2, "  %v0_2 = insertelement <16 x i8> %v0_1, i8 %v3, i32 2"), r_br5("br5 stack n 4 u8 [3]", "%v0", [S.uint8(), S.uint8(), S.uint8(), S.uint8()], ["%v1", "%v2", "%v3", "%v4"], 16, 3, "  %v0 = insertelement <16 x i8> %v0_2, i8 %v4, i32 3"), r_br5("br5 stack n 3 bf16 [0]", "%v0", [S.bfloat16(), S.bfloat16(), S.bfloat16()], ["%v1", "%v2", "%v3"], 12, 0, "  %v0_0 = insertelement <12 x bfloat> poison, bfloat %v1, i32 0"), r_br5("br5 stack n 3 bf16 [1]", "%v0", [S.bfloat16(), S.bfloat16(), S.bfloat16()], ["%v1", "%v2", "%v3"], 12, 1, "  %v0_1 = insertelement <12 x bfloat> %v0_0, bfloat %v2, i32 1"), r_br5("br5 stack n 3 bf16 [2]", "%v0", [S.bfloat16(), S.bfloat16(), S.bfloat16()], ["%v1", "%v2", "%v3"], 12, 2, "  %v0 = insertelement <12 x bfloat> %v0_1, bfloat %v3, i32 2")])

def r_br678s() -> String:
  String.concat([r_br6("br6 bitcast f32x4->i32x4", S.single(), S.int32(), 4, "%v0", "%v1", "  %v0 = bitcast <4 x float> %v1 to <4 x i32>"), r_br6("br6 bitcast i8x1->f32x1", S.int8(), S.single(), 1, "%v0", "%v1", "RuntimeError"), r_br6("br6 bitcast f16x8->bf16x8", S.half(), S.bfloat16(), 8, "%v0", "%v1", "  %v0 = bitcast <8 x half> %v1 to <8 x bfloat>"), r_br6("br6 bitcast u8x16->i8x16", S.uint8(), S.int8(), 16, "%v0", "%v1", "  %v0 = bitcast <16 x i8> %v1 to <16 x i8>"), r_br7("br7 cast f32->i32", S.single(), S.int32(), "%v0", "%v1", "  %v0 = fptosi float %v1 to i32"), r_br7("br7 cast u32->f32", S.uint32(), S.single(), "%v0", "%v1", "  %v0 = uitofp i32 %v1 to float"), r_br7("br7 cast i8->i16", S.int8(), S.int16(), "%v0", "%v1", "  %v0 = sext i8 %v1 to i16"), r_br7("br7 cast i16->i8", S.int16(), S.int8(), "%v0", "%v1", "  %v0 = trunc i16 %v1 to i8"), r_br7("br7 cast bf16->f32", S.bfloat16(), S.single(), "%v0", "%v1", "  %v0 = fpext bfloat %v1 to float"), r_br7("br7 cast f32->u8", S.single(), S.uint8(), "%v0", "%v1", "  %v0 = fptoui float %v1 to i8"), r_br7("br7 cast f64->f32", S.double(), S.single(), "%v0", "%v1", "  %v0 = fptrunc double %v1 to float"), r_br7("br7 cast f32->f64", S.single(), S.double(), "%v0", "%v1", "  %v0 = fpext float %v1 to double"), r_br7("br7 cast i64->i32", S.int64(), S.int32(), "%v0", "%v1", "  %v0 = trunc i64 %v1 to i32"), r_br8("br8 trunc f32->i32", S.single(), S.int32(), "%v0", "%v1", "  %v0 = call float @llvm.trunc.float(float %v1)"), r_br8("br8 trunc i32->i8", S.int32(), S.int8(), "%v0", "%v1", "  %v0 = call i32 @llvm.trunc.i32(i32 %v1)"), r_br8("br8 trunc f64->f32", S.double(), S.single(), "%v0", "%v1", "  %v0 = call double @llvm.trunc.double(double %v1)"), r_br9("br9 binary bool ADD", S.boolean(), O.OpsADD{}, "%v0", "%v1", "%v2", "  %v0 = add i1 %v1, %v2"), r_br9("br9 binary bool MUL", S.boolean(), O.OpsMUL{}, "%v0", "%v1", "%v2", "  %v0 = mul i1 %v1, %v2"), r_br9("br9 binary bool CDIV", S.boolean(), O.OpsCDIV{}, "%v0", "%v1", "%v2", "  %v0 = udiv i1 %v1, %v2"), r_br9("br9 binary bool CMOD", S.boolean(), O.OpsCMOD{}, "%v0", "%v1", "%v2", "  %v0 = urem i1 %v1, %v2"), r_br9("br9 binary bool CMPLT", S.boolean(), O.OpsCMPLT{}, "%v0", "%v1", "%v2", "  %v0 = icmp ult i1 %v1, %v2"), r_br9("br9 binary bool SHR", S.boolean(), O.OpsSHR{}, "%v0", "%v1", "%v2", "  %v0 = lshr i1 %v1, %v2"), r_br9("br9 binary bool SHL", S.boolean(), O.OpsSHL{}, "%v0", "%v1", "%v2", "  %v0 = shl i1 %v1, %v2"), r_br9("br9 binary bool FDIV", S.boolean(), O.OpsFDIV{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary u8 ADD", S.uint8(), O.OpsADD{}, "%v0", "%v1", "%v2", "  %v0 = add i8 %v1, %v2"), r_br9("br9 binary u8 MUL", S.uint8(), O.OpsMUL{}, "%v0", "%v1", "%v2", "  %v0 = mul i8 %v1, %v2"), r_br9("br9 binary u8 CDIV", S.uint8(), O.OpsCDIV{}, "%v0", "%v1", "%v2", "  %v0 = udiv i8 %v1, %v2"), r_br9("br9 binary u8 CMOD", S.uint8(), O.OpsCMOD{}, "%v0", "%v1", "%v2", "  %v0 = urem i8 %v1, %v2"), r_br9("br9 binary u8 CMPLT", S.uint8(), O.OpsCMPLT{}, "%v0", "%v1", "%v2", "  %v0 = icmp ult i8 %v1, %v2"), r_br9("br9 binary u8 SHR", S.uint8(), O.OpsSHR{}, "%v0", "%v1", "%v2", "  %v0 = lshr i8 %v1, %v2"), r_br9("br9 binary u8 SHL", S.uint8(), O.OpsSHL{}, "%v0", "%v1", "%v2", "  %v0 = shl i8 %v1, %v2"), r_br9("br9 binary u8 FDIV", S.uint8(), O.OpsFDIV{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary i32 ADD", S.int32(), O.OpsADD{}, "%v0", "%v1", "%v2", "  %v0 = add nsw i32 %v1, %v2"), r_br9("br9 binary i32 MUL", S.int32(), O.OpsMUL{}, "%v0", "%v1", "%v2", "  %v0 = mul i32 %v1, %v2"), r_br9("br9 binary i32 CDIV", S.int32(), O.OpsCDIV{}, "%v0", "%v1", "%v2", "  %v0 = sdiv i32 %v1, %v2"), r_br9("br9 binary i32 CMOD", S.int32(), O.OpsCMOD{}, "%v0", "%v1", "%v2", "  %v0 = srem i32 %v1, %v2"), r_br9("br9 binary i32 CMPLT", S.int32(), O.OpsCMPLT{}, "%v0", "%v1", "%v2", "  %v0 = icmp slt i32 %v1, %v2"), r_br9("br9 binary i32 SHR", S.int32(), O.OpsSHR{}, "%v0", "%v1", "%v2", "  %v0 = ashr i32 %v1, %v2"), r_br9("br9 binary i32 SHL", S.int32(), O.OpsSHL{}, "%v0", "%v1", "%v2", "  %v0 = shl i32 %v1, %v2"), r_br9("br9 binary i32 FDIV", S.int32(), O.OpsFDIV{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary i8 ADD", S.int8(), O.OpsADD{}, "%v0", "%v1", "%v2", "  %v0 = add nsw i8 %v1, %v2"), r_br9("br9 binary i8 MUL", S.int8(), O.OpsMUL{}, "%v0", "%v1", "%v2", "  %v0 = mul i8 %v1, %v2"), r_br9("br9 binary i8 CDIV", S.int8(), O.OpsCDIV{}, "%v0", "%v1", "%v2", "  %v0 = sdiv i8 %v1, %v2"), r_br9("br9 binary i8 CMOD", S.int8(), O.OpsCMOD{}, "%v0", "%v1", "%v2", "  %v0 = srem i8 %v1, %v2"), r_br9("br9 binary i8 CMPLT", S.int8(), O.OpsCMPLT{}, "%v0", "%v1", "%v2", "  %v0 = icmp slt i8 %v1, %v2"), r_br9("br9 binary i8 SHR", S.int8(), O.OpsSHR{}, "%v0", "%v1", "%v2", "  %v0 = ashr i8 %v1, %v2"), r_br9("br9 binary i8 SHL", S.int8(), O.OpsSHL{}, "%v0", "%v1", "%v2", "  %v0 = shl i8 %v1, %v2"), r_br9("br9 binary i8 FDIV", S.int8(), O.OpsFDIV{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f32 ADD", S.single(), O.OpsADD{}, "%v0", "%v1", "%v2", "  %v0 = fadd nsz arcp contract afn float %v1, %v2"), r_br9("br9 binary f32 MUL", S.single(), O.OpsMUL{}, "%v0", "%v1", "%v2", "  %v0 = fmul nsz arcp contract afn float %v1, %v2"), r_br9("br9 binary f32 CDIV", S.single(), O.OpsCDIV{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f32 CMOD", S.single(), O.OpsCMOD{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f32 CMPLT", S.single(), O.OpsCMPLT{}, "%v0", "%v1", "%v2", "  %v0 = fcmp nsz arcp contract afn olt float %v1, %v2"), r_br9("br9 binary f32 SHR", S.single(), O.OpsSHR{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f32 SHL", S.single(), O.OpsSHL{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f32 FDIV", S.single(), O.OpsFDIV{}, "%v0", "%v1", "%v2", "  %v0 = fdiv nsz arcp contract afn float %v1, %v2"), r_br9("br9 binary f16 ADD", S.half(), O.OpsADD{}, "%v0", "%v1", "%v2", "  %v0 = fadd nsz arcp contract afn half %v1, %v2"), r_br9("br9 binary f16 MUL", S.half(), O.OpsMUL{}, "%v0", "%v1", "%v2", "  %v0 = fmul nsz arcp contract afn half %v1, %v2"), r_br9("br9 binary f16 CDIV", S.half(), O.OpsCDIV{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f16 CMOD", S.half(), O.OpsCMOD{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f16 CMPLT", S.half(), O.OpsCMPLT{}, "%v0", "%v1", "%v2", "  %v0 = fcmp nsz arcp contract afn olt half %v1, %v2"), r_br9("br9 binary f16 SHR", S.half(), O.OpsSHR{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f16 SHL", S.half(), O.OpsSHL{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f16 FDIV", S.half(), O.OpsFDIV{}, "%v0", "%v1", "%v2", "  %v0 = fdiv nsz arcp contract afn half %v1, %v2"), r_br9("br9 binary bf16 ADD", S.bfloat16(), O.OpsADD{}, "%v0", "%v1", "%v2", "  %v0 = fadd nsz arcp contract afn bfloat %v1, %v2"), r_br9("br9 binary bf16 MUL", S.bfloat16(), O.OpsMUL{}, "%v0", "%v1", "%v2", "  %v0 = fmul nsz arcp contract afn bfloat %v1, %v2"), r_br9("br9 binary bf16 CDIV", S.bfloat16(), O.OpsCDIV{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary bf16 CMOD", S.bfloat16(), O.OpsCMOD{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary bf16 CMPLT", S.bfloat16(), O.OpsCMPLT{}, "%v0", "%v1", "%v2", "  %v0 = fcmp nsz arcp contract afn olt bfloat %v1, %v2"), r_br9("br9 binary bf16 SHR", S.bfloat16(), O.OpsSHR{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary bf16 SHL", S.bfloat16(), O.OpsSHL{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary bf16 FDIV", S.bfloat16(), O.OpsFDIV{}, "%v0", "%v1", "%v2", "  %v0 = fdiv nsz arcp contract afn bfloat %v1, %v2"), r_br9("br9 binary f64 ADD", S.double(), O.OpsADD{}, "%v0", "%v1", "%v2", "  %v0 = fadd nsz arcp contract afn double %v1, %v2"), r_br9("br9 binary f64 MUL", S.double(), O.OpsMUL{}, "%v0", "%v1", "%v2", "  %v0 = fmul nsz arcp contract afn double %v1, %v2"), r_br9("br9 binary f64 CDIV", S.double(), O.OpsCDIV{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f64 CMOD", S.double(), O.OpsCMOD{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f64 CMPLT", S.double(), O.OpsCMPLT{}, "%v0", "%v1", "%v2", "  %v0 = fcmp nsz arcp contract afn olt double %v1, %v2"), r_br9("br9 binary f64 SHR", S.double(), O.OpsSHR{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f64 SHL", S.double(), O.OpsSHL{}, "%v0", "%v1", "%v2", "KeyError"), r_br9("br9 binary f64 FDIV", S.double(), O.OpsFDIV{}, "%v0", "%v1", "%v2", "  %v0 = fdiv nsz arcp contract afn double %v1, %v2"), r_br10("br10 where mixed", S.boolean(), S.single(), S.int32(), "%v0", "%v1", "%v2", "%v3", "  %v0 = select i1 %v1, float %v2, i32 %v3")])

def r_brRBs() -> String:
  String.concat([r_br11("br11 rangevoid [0]", "%v3", 0, "  br label %loop_v3"), r_br11("br11 rangevoid [1]", "%v3", 1, "loop_v3:"), r_br13("br13 range [0]", "0", "%v3", "%v2", S.int32(), 0, "  br label %loop_entry_0"), r_br13("br13 range [1]", "0", "%v3", "%v2", S.int32(), 1, "loop_entry_0:"), r_br13("br13 range [2]", "0", "%v3", "%v2", S.int32(), 2, "  br label %loop_latch_0"), r_br13("br13 range [3]", "0", "%v3", "%v2", S.int32(), 3, "loop_latch_0:"), r_br13("br13 range [4]", "0", "%v3", "%v2", S.int32(), 4, "  %v3 = phi i32 [ 0, %loop_entry_0 ], [ %v3phi, %loop_footer_0 ]"), r_br13("br13 range [5]", "0", "%v3", "%v2", S.int32(), 5, "  %v3phi = add i32 %v3, 1"), r_br13("br13 range [6]", "0", "%v3", "%v2", S.int32(), 6, "  %v3cmp = icmp ult i32 %v3, %v2"), r_br13("br13 range [7]", "0", "%v3", "%v2", S.int32(), 7, "  br i1 %v3cmp, label %loop_body_0, label %loop_exit_0"), r_br13("br13 range [8]", "0", "%v3", "%v2", S.int32(), 8, "loop_body_0:"), r_br13("br13 range neg [0]", "3", "%v3", "%v2", S.int32(), 0, "  br label %loop_entry_3"), r_br13("br13 range neg [1]", "3", "%v3", "%v2", S.int32(), 1, "loop_entry_3:"), r_br13("br13 range neg [2]", "3", "%v3", "%v2", S.int32(), 2, "  br label %loop_latch_3"), r_br13("br13 range neg [3]", "3", "%v3", "%v2", S.int32(), 3, "loop_latch_3:"), r_br13("br13 range neg [4]", "3", "%v3", "%v2", S.int32(), 4, "  %v3 = phi i32 [ 0, %loop_entry_3 ], [ %v3phi, %loop_footer_3 ]"), r_br13("br13 range neg [5]", "3", "%v3", "%v2", S.int32(), 5, "  %v3phi = add i32 %v3, 1"), r_br13("br13 range neg [6]", "3", "%v3", "%v2", S.int32(), 6, "  %v3cmp = icmp ult i32 %v3, %v2"), r_br13("br13 range neg [7]", "3", "%v3", "%v2", S.int32(), 7, "  br i1 %v3cmp, label %loop_body_3, label %loop_exit_3"), r_br13("br13 range neg [8]", "3", "%v3", "%v2", S.int32(), 8, "loop_body_3:"), r_br12("br12 backedge [0]", "%v3", "%v4", 0, "  br i1 %v4, label %loop_v3, label %loop_exit_v3"), r_br12("br12 backedge [1]", "%v3", "%v4", 1, "loop_exit_v3:"), r_br14("br14 end pos [0]", 7, 0, "  br label %loop_footer_7"), r_br14("br14 end pos [1]", 7, 1, "loop_footer_7:"), r_br14("br14 end pos [2]", 7, 2, "  br label %loop_latch_7"), r_br14("br14 end pos [3]", 7, 3, "loop_exit_7:"), r_br14("br14 end neg [0]", 3, 0, "  br label %loop_footer_3"), r_br14("br14 end neg [1]", 3, 1, "loop_footer_3:"), r_br14("br14 end neg [2]", 3, 2, "  br label %loop_latch_3"), r_br14("br14 end neg [3]", 3, 3, "loop_exit_3:")])

def r_brIBs() -> String:
  String.concat([r_br15("br15 if bool [0]", "%v7", "%v6", 0, "  br i1 %v6, label %ifbody_v7, label %ifskip_v7"), r_br15("br15 if bool [1]", "%v7", "%v6", 1, "ifbody_v7:"), r_br16("br16 endif bool [0]", "%v7", 0, "  br label %ifskip_v7"), r_br16("br16 endif bool [1]", "%v7", 1, "ifskip_v7:"), r_br15("br15 if i32 [0]", "%v7", "%v6", 0, "  br i1 %v6, label %ifbody_v7, label %ifskip_v7"), r_br15("br15 if i32 [1]", "%v7", "%v6", 1, "ifbody_v7:"), r_br16("br16 endif i32 [0]", "%v7", 0, "  br label %ifskip_v7"), r_br16("br16 endif i32 [1]", "%v7", 1, "ifskip_v7:"), r_br17("br17 barrier", "  fence seq_cst"), r_amd2("amd2 barrier [0]", 0, "fence syncscope(\"workgroup\") release"), r_amd2("amd2 barrier [1]", 1, "tail call void @llvm.amdgcn.s.barrier()"), r_amd2("amd2 barrier [2]", 2, "fence syncscope(\"workgroup\") acquire"), r_amd2("amd2 barrier [3]", 3, "")])

def r_amds() -> String:
  String.concat([r_f8o("fp8e4m3,fp8e5m2,fp8e4m3fnuz,fp8e5m2fnuz"), r_f8p("fp8e4m3", S.fp8e4m3(), "0"), r_f8p("fp8e5m2", S.fp8e5m2(), "1"), r_f8p("fp8e4m3fnuz", S.fp8e4m3fnuz(), "2"), r_f8p("fp8e5m2fnuz", S.fp8e5m2fnuz(), "3"), r_f8mp("i32", S.int32(), "ValueError"), r_f8mp("f16", S.half(), "ValueError"), r_f8i("fp8e4m3", S.fp8e4m3(), "0"), r_f8i("fp8e5m2", S.fp8e5m2(), "1"), r_f8i("fp8e4m3fnuz", S.fp8e4m3fnuz(), "0"), r_f8i("fp8e5m2fnuz", S.fp8e5m2fnuz(), "1"), r_f8mi("i32", S.int32(), "ValueError"), r_f8mi("f16", S.half(), "ValueError"), r_amd0("amd0 special g0", False{}, 0, "%v3", "  %v3 = tail call i32 @llvm.amdgcn.workgroup.id.x(); "), r_amd0("amd0 special g2", False{}, 2, "%v3", "  %v3 = tail call i32 @llvm.amdgcn.workgroup.id.z(); "), r_amd0("amd0 special l0", True{}, 0, "%v3", "  %v3 = tail call i32 @llvm.amdgcn.workitem.id.x(); "), r_amd0("amd0 special l1", True{}, 1, "%v3", "  %v3 = tail call i32 @llvm.amdgcn.workitem.id.y(); "), r_amd0("amd0 special l2", True{}, 2, "%v3", "  %v3 = tail call i32 @llvm.amdgcn.workitem.id.z(); "), r_amd1("amd1 sqrt f32->f32", O.OpsSQRT{}, S.single(), S.single(), "%v0", "%v1", "  %v0 = call float @llvm.sqrt.float(float %v1)"), r_amd1("amd1 sqrt f16->f16", O.OpsSQRT{}, S.half(), S.half(), "%v0", "%v1", "  %v0 = call half @llvm.sqrt.half(half %v1)"), r_amd1("amd1 sqrt f64->f64", O.OpsSQRT{}, S.double(), S.double(), "%v0", "%v1", "  %v0 = call double @llvm.sqrt.double(double %v1)"), r_amd1("amd1 log2 f32->f32", O.OpsLOG2{}, S.single(), S.single(), "%v0", "%v1", "  %v0 = call float @llvm.log2.float(float %v1)"), r_amd1("amd1 log2 f16->f16", O.OpsLOG2{}, S.half(), S.half(), "%v0", "%v1", "  %v0 = call half @llvm.log2.half(half %v1)"), r_amd1("amd1 log2 f64->f64", O.OpsLOG2{}, S.double(), S.double(), "%v0", "%v1", "  %v0 = call double @llvm.log2.double(double %v1)"), r_amd1("amd1 exp2 f32->f32", O.OpsEXP2{}, S.single(), S.single(), "%v0", "%v1", "  %v0 = call float @llvm.exp2.float(float %v1)"), r_amd1("amd1 exp2 f16->f16", O.OpsEXP2{}, S.half(), S.half(), "%v0", "%v1", "  %v0 = call half @llvm.exp2.half(half %v1)"), r_amd1("amd1 exp2 f64->f64", O.OpsEXP2{}, S.double(), S.double(), "%v0", "%v1", "  %v0 = call double @llvm.exp2.double(double %v1)"), r_amd3("amd3 cast f32->fp8e4m3", S.fp8e4m3(), "%v0", "%v1", "  %v0 = call i8 @f32_to_fp8(float  %v1, i1 0)"), r_amd3("amd3 cast f32->fp8e5m2", S.fp8e5m2(), "%v0", "%v1", "  %v0 = call i8 @f32_to_fp8(float  %v1, i1 1)"), r_amd3("amd3 cast f32->fp8e4m3fnuz", S.fp8e4m3fnuz(), "%v0", "%v1", "  %v0 = call i8 @f32_to_fp8(float  %v1, i1 0)"), r_amd3("amd3 cast f32->fp8e5m2fnuz", S.fp8e5m2fnuz(), "%v0", "%v1", "  %v0 = call i8 @f32_to_fp8(float  %v1, i1 1)"), r_amd4("amd4 cast fp8e4m3->f32 [0]", S.fp8e4m3(), "%v0", "%v1", 0, "  %v0_i32 = zext i8 %v1 to i32"), r_amd4("amd4 cast fp8e4m3->f32 [1]", S.fp8e4m3(), "%v0", "%v1", 1, "  %v0 = call float @llvm.amdgcn.cvt.f32.fp8(i32 %v0_i32, i32 0)"), r_amd4("amd4 cast fp8e5m2->f32 [0]", S.fp8e5m2(), "%v0", "%v1", 0, "  %v0_i32 = zext i8 %v1 to i32"), r_amd4("amd4 cast fp8e5m2->f32 [1]", S.fp8e5m2(), "%v0", "%v1", 1, "  %v0 = call float @llvm.amdgcn.cvt.f32.bf8(i32 %v0_i32, i32 0)"), r_amd4("amd4 cast fp8e4m3fnuz->f32 [0]", S.fp8e4m3fnuz(), "%v0", "%v1", 0, "  %v0_i32 = zext i8 %v1 to i32"), r_amd4("amd4 cast fp8e4m3fnuz->f32 [1]", S.fp8e4m3fnuz(), "%v0", "%v1", 1, "  %v0 = call float @llvm.amdgcn.cvt.f32.fp8(i32 %v0_i32, i32 0)"), r_amd4("amd4 cast fp8e5m2fnuz->f32 [0]", S.fp8e5m2fnuz(), "%v0", "%v1", 0, "  %v0_i32 = zext i8 %v1 to i32"), r_amd4("amd4 cast fp8e5m2fnuz->f32 [1]", S.fp8e5m2fnuz(), "%v0", "%v1", 1, "  %v0 = call float @llvm.amdgcn.cvt.f32.bf8(i32 %v0_i32, i32 0)")])

def r_rfns() -> String:
  String.concat([r_rsargs("rfn sargs global", True{}, S.single(), "%data0", "float* noalias %data0"), r_rsargs2("rfn sargs2 global", True{}, S.single(), S.uint32(), "float* noalias %data0, i32* noalias %data1"), r_rsargs("rfn sargs reg", False{}, S.single(), "%data0", "float %data0"), r_rsargs2("rfn sargs2 reg", False{}, S.single(), S.uint32(), "float %data0, i32 %data1"), r_rsargs("rfn sargs local", False{}, S.single(), "%data0", "float %data0"), r_rsargs2("rfn sargs2 local", False{}, S.single(), S.uint32(), "float %data0, i32 %data1"), r_rsargs("rfn sargs alu", False{}, S.single(), "%data0", "float %data0"), r_rsargs2("rfn sargs2 alu", False{}, S.single(), S.uint32(), "float %data0, i32 %data1"), r_rsargs2e("rfn sargs2 empty", ""), r_rfn("rfn abi None global [0]", "", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0, "define void @mykernel(float* noalias %data0, i32* noalias %data1) #0"), r_rfn("rfn abi None global [1]", "", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1, "{"), r_rfn("rfn abi None global [2]", "", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi None global [3]", "", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3, "  %v1 = fmul"), r_rfn("rfn abi None global [4]", "", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4, "  ret void"), r_rfn("rfn abi None global [5]", "", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5, "}"), r_rfn("rfn abi None reg [0]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0, "define void @mykernel(float %data0, i32 %data1) #0"), r_rfn("rfn abi None reg [1]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1, "{"), r_rfn("rfn abi None reg [2]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi None reg [3]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3, "  %v1 = fmul"), r_rfn("rfn abi None reg [4]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4, "  ret void"), r_rfn("rfn abi None reg [5]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5, "}"), r_rfn("rfn abi None local [0]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0, "define void @mykernel(float %data0, i32 %data1) #0"), r_rfn("rfn abi None local [1]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1, "{"), r_rfn("rfn abi None local [2]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi None local [3]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3, "  %v1 = fmul"), r_rfn("rfn abi None local [4]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4, "  ret void"), r_rfn("rfn abi None local [5]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5, "}"), r_rfn("rfn abi None alu [0]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0, "define void @mykernel(float %data0, i32 %data1) #0"), r_rfn("rfn abi None alu [1]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1, "{"), r_rfn("rfn abi None alu [2]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi None alu [3]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3, "  %v1 = fmul"), r_rfn("rfn abi None alu [4]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4, "  ret void"), r_rfn("rfn abi None alu [5]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5, "}"), r_rfn("rfn abi amdgpu_kernel global [0]", "amdgpu_kernel", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0, "define amdgpu_kernel void @mykernel(float* noalias %data0, i32* noalias %data1) #0"), r_rfn("rfn abi amdgpu_kernel global [1]", "amdgpu_kernel", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1, "{"), r_rfn("rfn abi amdgpu_kernel global [2]", "amdgpu_kernel", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi amdgpu_kernel global [3]", "amdgpu_kernel", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3, "  %v1 = fmul"), r_rfn("rfn abi amdgpu_kernel global [4]", "amdgpu_kernel", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4, "  ret void"), r_rfn("rfn abi amdgpu_kernel global [5]", "amdgpu_kernel", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5, "}"), r_rfn("rfn abi amdgpu_kernel reg [0]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0, "define amdgpu_kernel void @mykernel(float %data0, i32 %data1) #0"), r_rfn("rfn abi amdgpu_kernel reg [1]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1, "{"), r_rfn("rfn abi amdgpu_kernel reg [2]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi amdgpu_kernel reg [3]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3, "  %v1 = fmul"), r_rfn("rfn abi amdgpu_kernel reg [4]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4, "  ret void"), r_rfn("rfn abi amdgpu_kernel reg [5]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5, "}"), r_rfn("rfn abi amdgpu_kernel local [0]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0, "define amdgpu_kernel void @mykernel(float %data0, i32 %data1) #0"), r_rfn("rfn abi amdgpu_kernel local [1]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1, "{"), r_rfn("rfn abi amdgpu_kernel local [2]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi amdgpu_kernel local [3]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3, "  %v1 = fmul"), r_rfn("rfn abi amdgpu_kernel local [4]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4, "  ret void"), r_rfn("rfn abi amdgpu_kernel local [5]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5, "}"), r_rfn("rfn abi amdgpu_kernel alu [0]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0, "define amdgpu_kernel void @mykernel(float %data0, i32 %data1) #0"), r_rfn("rfn abi amdgpu_kernel alu [1]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1, "{"), r_rfn("rfn abi amdgpu_kernel alu [2]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi amdgpu_kernel alu [3]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3, "  %v1 = fmul"), r_rfn("rfn abi amdgpu_kernel alu [4]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4, "  ret void"), r_rfn("rfn abi amdgpu_kernel alu [5]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5, "}"), r_rfn("rfn abi win64cc global [0]", "win64cc", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0, "define win64cc void @mykernel(float* noalias %data0, i32* noalias %data1) #0"), r_rfn("rfn abi win64cc global [1]", "win64cc", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1, "{"), r_rfn("rfn abi win64cc global [2]", "win64cc", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi win64cc global [3]", "win64cc", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3, "  %v1 = fmul"), r_rfn("rfn abi win64cc global [4]", "win64cc", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4, "  ret void"), r_rfn("rfn abi win64cc global [5]", "win64cc", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5, "}"), r_rfn("rfn abi win64cc reg [0]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0, "define win64cc void @mykernel(float %data0, i32 %data1) #0"), r_rfn("rfn abi win64cc reg [1]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1, "{"), r_rfn("rfn abi win64cc reg [2]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi win64cc reg [3]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3, "  %v1 = fmul"), r_rfn("rfn abi win64cc reg [4]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4, "  ret void"), r_rfn("rfn abi win64cc reg [5]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5, "}"), r_rfn("rfn abi win64cc local [0]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0, "define win64cc void @mykernel(float %data0, i32 %data1) #0"), r_rfn("rfn abi win64cc local [1]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1, "{"), r_rfn("rfn abi win64cc local [2]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi win64cc local [3]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3, "  %v1 = fmul"), r_rfn("rfn abi win64cc local [4]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4, "  ret void"), r_rfn("rfn abi win64cc local [5]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5, "}"), r_rfn("rfn abi win64cc alu [0]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0, "define win64cc void @mykernel(float %data0, i32 %data1) #0"), r_rfn("rfn abi win64cc alu [1]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1, "{"), r_rfn("rfn abi win64cc alu [2]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi win64cc alu [3]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3, "  %v1 = fmul"), r_rfn("rfn abi win64cc alu [4]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4, "  ret void"), r_rfn("rfn abi win64cc alu [5]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5, "}"), r_rfn("rfn abi None empty [0]", "", "empty", "", ["  %v0 = fadd"], [], 0, "define void @empty() #0"), r_rfn("rfn abi None empty [1]", "", "empty", "", ["  %v0 = fadd"], [], 1, "{"), r_rfn("rfn abi None empty [2]", "", "empty", "", ["  %v0 = fadd"], [], 2, "  %v0 = fadd"), r_rfn("rfn abi None empty [3]", "", "empty", "", ["  %v0 = fadd"], [], 3, "  ret void"), r_rfn("rfn abi None empty [4]", "", "empty", "", ["  %v0 = fadd"], [], 4, "}"), r_rfn("rfn prefix [0]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 0, "PREFIX1"), r_rfn("rfn prefix [1]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 1, "PREFIX2"), r_rfn("rfn prefix [2]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 2, "define amdgpu_kernel void @withprefix(float* noalias %data0) #0"), r_rfn("rfn prefix [3]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 3, "{"), r_rfn("rfn prefix [4]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 4, "  %v0 = fadd"), r_rfn("rfn prefix [5]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 5, "  ret void"), r_rfn("rfn prefix [6]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 6, "}")])

def r_ftrs() -> String:
  String.concat([r_ftrc("ftr cpu", "attributes #0 = { alwaysinline nounwind \"no-builtins\" \"no-trapping-math\"=\"true\" }"), r_ftrp(0, "attributes"), r_ftrp(1, "#0"), r_ftrp(2, "="), r_ftrp(3, "{"), r_ftrp(4, "alwaysinline"), r_ftrp(5, "nounwind"), r_ftrp(6, "\"no-builtins\""), r_ftrp(7, "\"no-trapping-math\"=\"true\""), r_ftrp(8, "}"), r_ftr("ftr amd prod none", [], "1"), r_ftra("ftr amd none", [], "attributes #0 = { alwaysinline nounwind \"no-builtins\" \"amdgpu-flat-work-group-size\"=\"1,1\" \"no-trapping-math\"=\"true\" }"), r_ftr("ftr amd prod w64", [64], "64"), r_ftra("ftr amd w64", [64], "attributes #0 = { alwaysinline nounwind \"no-builtins\" \"amdgpu-flat-work-group-size\"=\"1,64\" \"no-trapping-math\"=\"true\" }"), r_ftr("ftr amd prod wx64h8", [64, 8], "512"), r_ftra("ftr amd wx64h8", [64, 8], "attributes #0 = { alwaysinline nounwind \"no-builtins\" \"amdgpu-flat-work-group-size\"=\"1,512\" \"no-trapping-math\"=\"true\" }"), r_ftr("ftr amd prod wgx1024", [1024], "1024"), r_ftra("ftr amd wgx1024", [1024], "attributes #0 = { alwaysinline nounwind \"no-builtins\" \"amdgpu-flat-work-group-size\"=\"1,1024\" \"no-trapping-math\"=\"true\" }"), r_ftr("ftr amd prod wx1", [1], "1"), r_ftra("ftr amd wx1", [1], "attributes #0 = { alwaysinline nounwind \"no-builtins\" \"amdgpu-flat-work-group-size\"=\"1,1\" \"no-trapping-math\"=\"true\" }"), r_ftr("ftr amd prod wglobal", [], "1"), r_ftra("ftr amd wglobal", [], "attributes #0 = { alwaysinline nounwind \"no-builtins\" \"amdgpu-flat-work-group-size\"=\"1,1\" \"no-trapping-math\"=\"true\" }"), r_ftr("ftr amd prod wgl", [16], "16"), r_ftra("ftr amd wgl", [16], "attributes #0 = { alwaysinline nounwind \"no-builtins\" \"amdgpu-flat-work-group-size\"=\"1,16\" \"no-trapping-math\"=\"true\" }"), r_ftr("ftr amd prod w3", [32, 32, 32], "32768"), r_ftra("ftr amd w3", [32, 32, 32], "attributes #0 = { alwaysinline nounwind \"no-builtins\" \"amdgpu-flat-work-group-size\"=\"1,32768\" \"no-trapping-math\"=\"true\" }"), r_ftr("ftr amd prod wbig", [65535, 65535], "4294836225"), r_ftra("ftr amd wbig", [65535, 65535], "attributes #0 = { alwaysinline nounwind \"no-builtins\" \"amdgpu-flat-work-group-size\"=\"1,4294836225\" \"no-trapping-math\"=\"true\" }")])

def r_rdnas() -> String:
  String.concat([r_rdna("gfx1200", "True"), r_rdna("gfx1201", "True"), r_rdna("gfx12001", "False"), r_rdna("gfx1100", "False"), r_rdna("gfx1200:xnack-", "True"), r_rdna("gfx942", "False"), r_rdna("AMD_GCN3_", "False"), r_rdna("gfx1200x", "False"), r_rdna("gfx120", "False"), r_rdna("gfx12012", "False"), r_rdna("gfx1201:xnack-", "True")])
# ONE print for the WHOLE table, so `IO.print`'s own newline is the only frame and
# the oracle's single trailing "\n" is its match.
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([r_lab(), r_lts(), r_pris(), r_ivs(), r_lc1s(), r_rss(), r_cnts(),
      r_br1s(), r_br2s(), r_br34s(), r_br5s(), r_br678s(), r_brRBs(), r_brIBs(),
      r_amds(), r_rfns(), r_ftrs(), r_rdnas()]))


# ===========================================================================
# THE MUTATION TABLE. Measured with `.agents/slop/li/li-mutate.py rules`: ONE
# TEXTUAL EDIT AT A TIME, and the harness diffs WHOLE `name=value` LINES and
# prints WHICH rows moved. A name-comparing harness reported 0 for all 30
# mutations in one unit and 0 for all 68 in another, so this one compares text.
#
# 79 mutations, 76 moved something, 3 blind -- and the 3 are the COMMENT-ONLY
# CONTROLS, which is the only outcome they are allowed to have.
#
#   M1 lt.fp's 16-bit arm is half 9 amd1 exp2 f16->f16, amd1 log2 f16->f16, amd1 s
#   M2 lt.fp answers double at pri 13 11 br5 stack n 3 bf16 [0], br5 stack n 3 bf1
#   M3 lt.ints is bits // 8 70 br1 extractelement alu i32, br10 where mixed, br13 
#   M4 CONTROL a comment-only edit 0
#   M5 lt.v's count arm is >= 1 33 br2 load vol False f32 [4], br2 load vol False 
#   M6 lt.v's count arm is dropped 19 br1 extractelement alu, br1 extractelement a
#   M7 lt.fp's 8-bit arm is 9 4 lt fp8e4m3, lt fp8e4m3fnuz, lt fp8e5m2 ...
#   M8 lt.fp's catch-all is float 12 amd1 exp2 f64->f64, amd1 log2 f64->f64, amd1 
#   M9 lt.of weak-class catch-all is void 2 lt weakfloat, lt weakint
#   M10 ivol ORs instead of ANDs 5 is_volatile AFTER vol False, is_volatile BUFFER
#   M11 ivol ignores is_param 2 is_volatile BUFFER vol True, is_volatile CONST vol
#   M12 ivol ignores vol 3 is_volatile AFTER vol False, is_volatile CAST vol False
#   M13 volsp's volatile arm has no space 9 br2 load vol True f32 [4], br2 load vo
#   M14 lconst_b0 is 7F/87 (the OR reading) 2 lconst special -inf, lconst special 
#   M15 lconst_b0 swaps its arms 4 lconst special +inf, lconst special +nan, lcons
#   M16 lconst_b1 drops the nan quiet bit 2 lconst special +nan, lconst special -n
#   M17 lconst_hex tail is 10 zeros 4 lconst special +inf, lconst special +nan, lc
#   M18 lconst_hex drops the 0x 4 lconst special +inf, lconst special +nan, lconst
#   M19 lc.arm's fp8 arm is truncate 4 lconst branch fp8e4m3, lconst branch fp8e4m
#   M20 lc.int FLOORS instead of truncating 4 lconst int -1.9, lconst int -2.5, lc
#   M21 lc.int prints the untruncated value 9 lconst int -1.9, lconst int -2.5, lc
#   M22 lc.arm floats answer int 8 lconst branch bf16, lconst branch f16, lconst b
#   M23 lab keeps the % 35 br11 rangevoid [0], br11 rangevoid [1], br12 backedge [
#   M24 rstr.id drops the leading digit 4 range_str 0,1, range_str 2,0,1, range_st
#   M25 rstr.neg drops the m 3 range_str neg 0, range_str neg 12, range_str neg 3
#   M26 rstr.go's separator is a dot 3 range_str 0,1, range_str 2,0,1, range_str 7
#   M27 br_rules's first arm is 19 1 base_rewrite.rules
#   M28 br_rules.b's 23 becomes 22 1 amd.string_rewrite.rules
#   M29 br_rules.b's third arm is 6 1 base_rewrite.after_amd
#   M30 br1 answers None for ALU 2 br1 extractelement alu, br1 extractelement alu 
#   M31 br1 answers a line for every addrspace 3 br1 extractelement global, br1 ex
#   M32 br1's index type is i64 2 br1 extractelement alu, br1 extractelement alu i
#   M33 br1 drops the extractelement 2 br1 extractelement alu, br1 extractelement 
#   M34 br2 drops volatile 3 br2 load vol True f32 [4], br2 load vol True i32 [4],
#   M35 br2 phi drops the alt 6 br2 load vol False f32 [7], br2 load vol False i32
#   M36 br2's phi is a bare name 6 br2 load vol False f32 [7], br2 load vol False 
#   M37 br2 swaps _load and _exit 6 br2 load vol False f32 [2], br2 load vol False
#   M38 br2's entry label keeps the % 6 br2 load vol False f32 [1], br2 load vol F
#   M39 br2 branches on the node not the mask 6 br2 load vol False f32 [2], br2 lo
#   M40 br4 swaps value and index 6 br4 store vol False f32, br4 store vol False i
#   M41 br3 drops the volatile fragment 3 br3 load vol True f32, br3 load vol True
#   M42 br5.name indexes every line 4 br5 stack n 1 f32 [0], br5 stack n 2 f32 [1]
#   M43 br5.pred is poison at every i 4 br5 stack n 1 f32 [0], br5 stack n 2 f32 [
#   M44 br5.pred indexes the CURRENT line 6 br5 stack n 2 f32 [1], br5 stack n 3 b
#   M45 br5's element count is len(srcs) 10 br5 stack n 1 f32 [0], br5 stack n 2 f
#   M46 br6.same is always True 1 br6 bitcast i8x1->f32x1
#   M47 br8 types the RESULT od 3 br8 trunc f32->i32, br8 trunc f64->f32, br8 trun
#   M48 br9 never walls 20 br9 binary bf16 CDIV, br9 binary bf16 CMOD, br9 binary 
#   M49 br10 reuses d0 three times 1 br10 where mixed
#   M50 br11's loop label is bare 1 br11 rangevoid [0]
#   M51 br13 labels from the NAME not the axis id 2 br13 range [5], br13 range neg
#   M52 br13's icmp bound is a literal 2 br13 range [6], br13 range neg [6]
#   M53 br14 drops the latch label 4 br14 end neg [2], br14 end neg [3], br14 end 
#   M54 br16 labels from the ENDIF own name 4 br16 endif bool [0], br16 endif bool
#   M55 br17 drops the leading two spaces 1 br17 barrier
#   M56 amd2 drops the barrier's quotes 4 amd2 barrier [0], amd2 barrier [1], amd2
#   M57 amd0 drops the trailing space 5 amd0 special g0, amd0 special g2, amd0 spe
#   M58 amd3 drops the DOUBLE space 4 amd3 cast f32->fp8e4m3, amd3 cast f32->fp8e4
#   M59 amd3 spells the i1 as 0 for bf8 4 amd3 cast f32->fp8e4m3, amd3 cast f32->f
#   M60 amd4 swaps bf8 and fp8 4 amd4 cast fp8e4m3->f32 [1], amd4 cast fp8e4m3fnuz
#   M61 amd4 drops the synthesized _i32 4 amd4 cast fp8e4m3->f32 [0], amd4 cast fp
#   M62 fp8i is f8pos without the mod 5 amd3 cast f32->fp8e4m3fnuz, amd3 cast f32-
#   M63 fp8i tests is_fnuz instead of the position 6 amd3 cast f32->fp8e4m3fnuz, a
#   M64 f8pos.go starts at 1 16 amd3 cast f32->fp8e4m3, amd3 cast f32->fp8e4m3fnuz
#   M65 f8pos.go's miss is 0 not the sentinel 4 fp8_index f16, fp8_index i32, fp8_
#   M66 f8pos.miss's sentinel is 0 5 fp8_index f16, fp8_index i32, fp8_pos f16 ...
#   M67 f8names emits no commas 1 fp8s.order
#   M68 rfn.slot's space is outside the conditional 5 rfn abi None alu [0], rfn ab
#   M69 rfn.define drops the #0 14 rfn abi None alu [0], rfn abi None empty [0], r
#   M70 sargs one's noalias keys on REG 8 rfn sargs alu, rfn sargs global, rfn sar
#   M71 sargs drops the ptr star 2 rfn sargs global, rfn sargs2 global
#   M72 rfn.all's tail is one string 28 rfn abi None alu [4], rfn abi None alu [5]
#   M73 rfn.cat is a prefix not an append 84 rfn abi None alu [0], rfn abi None al
#   M74 ftr.amd prefixes the group size with a 0 9 ftr amd none, ftr amd w3, ftr a
#   M75 ftr.amd halves the size 9 ftr amd none, ftr amd w3, ftr amd w64 ...
#   M76 prod seeds with 0 not 1 18 ftr amd none, ftr amd prod none, ftr amd prod w
#   M77 ftr.cpu_part splits on nothing 9 ftr cpu part 0, ftr cpu part 1, ftr cpu p
#   M78 CONTROL a comment-only edit 0
#   M79 CONTROL a comment-only edit 0

# ---------------------------------------------------------------------------
# WHAT THE TABLE SAYS.
#
# M3 IS THE LARGEST SINGLE MOVEMENT (70 rows) and it is `lt.ints` answering
# `bits // 8`. That is the same bug `nir_llvmir.bend`'s own header records as
# having been FOUND there -- `i1`, `i2`, `i4`, `i8` for the eight- and sixteen-
# bit types -- and the reason this file re-arms `lt` rather than fixing a copy of
# it is that a fix which is a NAME is a fix which is one rename away from broken
# again.
#
# M73 IS THE SECOND LARGEST (84 rows) and it is the OPPOSITE KIND of finding:
# `rfn.cat` turned into a prefix instead of an append makes the whole `_render_fn`
# table lose its `define` line and every kernel line after it. That is why the
# gate is a POSITIONAL diff and not a per-row boolean -- a per-cell comparison
# would have called 84 changed rows "84 rows, same count".
#
# FOUR MUTATIONS MOVE EXACTLY ONE ROW AND THAT IS THE POINT OF THEM, not a
# thinness: M27/M28/M29 are the three rule COUNTS and each count has one row;
# M31 is `br1`'s `None` arm and it is the only `None`-producing rule in the file;
# M46 is the BITCAST itemsize wall and `br6 bitcast i8x1->f32x1` is its only
# fixture; M49 is `br10`'s three `lt` calls and `br10 where mixed` is the only row
# whose three src dtypes DIFFER.
#
# ONE COLUMN IS DELIBERATELY CONSTANT. `rfn sargs reg`, `rfn sargs local` and
# `rfn sargs alu` all read `float %data0` -- ONLY GLOBAL is spelled -- so M70
# (keying `noalias` on REG) moves all four rather than one. That is the "a gate
# COLUMN that is constant over the whole suite is a column no mutation can move"
# note in its sharpest form, and moving four is better than moving one for the
# same reason: the test has to be one test and the column has to exist.
#
# M22 IS A GENUINE THINNESS AND IT IS STATED, NOT PATCHED. `lc.arm(flt, fp8)`
# answers `dtype.truncate` for a float and `int` for an integer, and swapping the
# fp8 arm (M19, 4 rows) moves while swapping the OUTER arms (M22) moves 0. The
# reason is that `lconst branch <d>` is the only group reading `lc.arm`, and every
# dtype in the grid is either a float or not, so the OUTER test is settled by
# `is_float` and never re-evaluated. `lconst branch i32` and `lconst branch f32`
# ARE the two arms and both are rows; what cannot happen is a float REACHING the
# `int` arm, which needs a dtype that is both, and none exists. That is a THEOREM
# over the dtype grid, not a missing fixture.
#
# ---------------------------------------------------------------------------
# THE CONSTANT SWEEP. `.agents/slop/li/li-mutate.py consts` does `+1` on every
# 3-or-more-digit literal in the file. 58 swept, 6 moved a row, 52 blind -- and
# THE MEASUREMENT IS THE ONE `x86` PRODUCED: a constants sweep finds none of the
# LOGIC defects and a rules sweep finds all of them. Here the ratio is 6 against
# 76.
#
# ALL SIX MOVES ARE FIXTURE LITERALS INSIDE THE GENERATED ROW BUILDERS -- the
# `py=` halves of `ftr amd prod wx64h8`, `ftr amd prod wgx1024`, `ftr amd w3`,
# `ftr amd prod wbig` and `ftr amd wbig` -- and NOT ONE IS PORT LOGIC. They are
# the width constants of the AMD footer FIXTURES, and they move because the
# oracle's own answer moves with them. That is the honest reading: the sweep found
# five places where this file's expectation and its input are the SAME NUMBER,
# and knowing about those five is worth the run.
#
# THE FIFTY-TWO BLIND SPOTS ARE ALMOST ALL PYTHON LINE NUMBERS IN COMMENTS.
# `llvmir.py:225`, `nir_llvmir.bend:181-191`, `spec.bend:694-701` and so on: the
# sweep cannot tell a citation from a constant, so fifty of its fifty-eight
# mutations edit a comment. The two that are neither comments nor fixture widths
# are C50 (`f8pos.go`'s 4294967295 MISS sentinel, which BROKE because 4294967296
# is not a `U32`) and C1/C2/C3/C4, which are all citations. THAT IS THE HARNESS'S
# OWN BLIND LIST AND IT IS THE DELIVERABLE: a sweep over a file that cites its
# sources by line number is mostly a sweep over prose, and a reader who wanted a
# guarantee from it would be reading the wrong table.
# ===========================================================================
