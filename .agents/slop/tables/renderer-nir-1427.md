<!-- FROM: tinybendygrad/renderer/nir.bend:1427 -->

# THE MUTATION TABLE -- 37 mutations, MEASURED, one per ported rule, reported
# with the rows they moved by name. Reproduce with:
#
#   .venv/bin/python .agents/slop/nir/nir_mutate.py         > .agents/slop/nir/mut.txt
#   .venv/bin/python .agents/slop/nir/nir_mutate.py --const > .agents/slop/nir/const_sweep.txt
#
# The harness diffs WHOLE `name=value` LINES and never row names -- a
# name-comparing harness reported 0 for all 30 mutations in one unit of this repo
# and 0 for all 68 in another. It also RE-CHECKS THE SUBSTRATE BEFORE EVERY
# STEP, because four agents are editing it: one whole run of this table came
# back with twenty-two "DID NOT COMPILE: expected : 'def', 'type'" which were
# another agent's half-written `fold.bend`, and reporting those as this file's
# blind spots would have been a lie with a table under it.
#
# ONE BLIND, AND IT IS A THEOREM. M18b replaces `c(ot, ot == dtypes.bool)` with
# `c(ot)` in `ncast`'s second prefix and nothing moves. `c`'s first arm is
# `t in dtypes.uints and u`, `bool` is NOT in `dtypes.uints`, so the `u`
# argument is unreachable for the only `t` that could make it true -- `c(bool,
# True)` and `c(bool, False)` are both `"b"`, which is exactly what the two
# `c bool` rows say. `nir.py:28`'s `ot == dtypes.bool` is therefore dead weight
# in upstream and no fixture can separate the two spellings. That is a property
# of the FUNCTION, not a gap in the gate.
#
# NO CONSTANT IS BLIND. The `+1` sweep is over every one of the 101 constant arms
# in the file -- the 67 of `op_const`, the 22 of `intr_const`, the 8 of
# `idx_const` and the 4 of `arch_int` -- and every one moves a row. Its FIRST
# run found 38 blind of 101, and all thirty-eight were defs no gate row called:
# `intr_const`, `idx_const`, and the seven `op_const` arms outside the three
# tables (`mov`, `vec2`..`vec16`). The three `mesa *` rows at the foot of the
# gate exist for that reason and nothing else.
#
# baseline: 102 rows
#
# ID    WHAT                                           ROWS MOVED (BY NAME)
# M01   c: uint arm -> i                               c uint32 u=True, c uint8 u=True , ncast from uint8
# M02   c: i arm -> f                                  c int32 u=True , c uint64 u=Fal, c uint8 u=Fals, ncast from bool , ncast from float, ncast from int32, ncast from long , ncast from weaki
# M03   c: f arm -> b (bool never reaches)             c bf16 u=True  , c double u=True, c fp8_e4m3 u=T , c half u=True  , ncast from bool , ncast from float, ncast from int32, ncast from long , ncast from uint8, ncast from weaki
# M04   c: `and u` dropped                             c uint64 u=Fal, c uint8 u=Fals, ncast from bool , ncast from float, ncast from weaki
# M05   c: `ints` widened to `S.Dt.is_int` (weakint!)  c index u=True, c weakint u=T , ncast from weaki
# M06   u_aop: ADD -> uadd                             aop rev u      , aop u  table
# M07   s_aop: MAX imax -> umax                        aop rev s      , aop s  table
# M08   f_aop: FDIV -> rcp                             aop f  table   , aop rev f
# M09   f_aop: CMPEQ feq -> fneu                       aop f  table   , aop rev f
# M10   u_aop.rev: ishl swapped with ushr              aop rev u
# M11   f_aop.rev: ftrunc dropped                      aop rev f
# M13   aop_kind: float class becomes 1                aop kind half
# M14   op_of: WHERE -> OpsCONST                       aop rev s      , aop rev u      , aop s  table   , aop u  table
# M15   glsl_sym_int: `glsl_type_builtin_` head dropped glsl keys
# M16   glsl_sym_int: `itemsize == 4` exception dropped glsl keys
# M17   glsl_keyed: `bool` stops being a key           glsl keys
# M18   ncast: two-way condition `and` -> `or`         ncast from bool , ncast from float, ncast from int32, ncast from long , ncast from uint8, ncast from weaki
# M18b  ncast: second prefix taken from the DESTINATION's signedness only [THEOREM] * NOTHING MOVED *
# M19   ncast: destination bitsize -> source           ncast from bool , ncast from float, ncast from int32, ncast from long , ncast from uint8, ncast from weaki
# M20   scope: ALU given its own case                  scope alu
# M22   nstore: ALIGN_MUL becomes REG-only             nstore align A , nstore align L , nstore align R
# M23   nstore: WRITE_MASK off by one                  nstore mask
# M24   nload: ACCESS for every space                  nload hasACC A , nload hasACC L , nload hasACC R
# M25   padded_idx: the extra `+ size` dropped         padded 0 4     , padded 17 32   , padded 3 8     , padded 8 8     , padded 9 16    , padded tbl
# M26   round_up: multiply BEFORE dividing             padded 17 32   , padded 3 8     , padded 9 16    , padded tbl
# M27   sd: NAK's arch test `>= 53` becomes `> 53`     sd nak sm_53
# M28   sd: bfloat16 stops being dropped               sd ir3         , sd nak sm_120  , sd nak sm_52   , sd nak sm_53   , sd nak sm_86   , sd nir
# M28b  sd: one fp8 stops being dropped                sd ir3         , sd nak sm_120  , sd nak sm_52   , sd nak sm_53   , sd nak sm_86   , sd nir
# M30   Nir: LVP's global_max 1 -> 2147483647          rec LVP
# M31   Nir: shared_max 49152 -> 32768 (the BASE value) rec NIR
# M32   arch_off: the offset becomes 2                 arch_off sm_53
# M33   build_alu: a fifth arity invented              alu arities
# M34   aop_keys: insertion order float-first (`dtypes.all`'s, not `aop`'s) aop u  keys
# M35   cfo: WHERE dropped from the op set             cfo ir3        , cfo lvp        , cfo nak        , cfo nir
#
# 37 mutations, 1 blind
# THE CONSTANT SWEEP. `+1` on every constant arm, one at a time.
# baseline: 102 rows
#
# ID     LINE   ARM                                ROWS MOVED
# K01    255    case "iadd": 306                   aop rev s      , aop rev u      , aop s  table   , aop u  table   , mesa alu
# K02    256    case "imul": 338                   aop rev s      , aop rev u      , aop s  table   , aop u  table   , mesa alu
# K03    257    case "udiv": 427                   aop rev u      , aop u  table
# K04    258    case "umod": 451                   aop rev u      , aop u  table
# K05    259    case "ult": 441                    aop rev u      , aop u  table
# K06    260    case "ilt": 326                    aop rev s      , aop s  table   , mesa alu
# K07    261    case "ine": 344                    aop rev s      , aop rev u      , aop s  table   , aop u  table
# K08    262    case "ieq": 314                    aop rev s      , aop rev u      , aop s  table   , aop u  table
# K09    263    case "ior": 353                    aop rev s      , aop rev u      , aop s  table   , aop u  table
# K10    264    case "iand": 309                   aop rev s      , aop rev u      , aop s  table   , aop u  table
# K11    265    case "ixor": 361                   aop rev s      , aop rev u      , aop s  table   , aop u  table
# K12    266    case "bcsel": 115                  aop rev s      , aop rev u      , aop s  table   , aop u  table
# K13    267    case "umax": 447                   aop rev u      , aop u  table
# K14    268    case "imax": 334                   aop rev s      , aop s  table
# K15    269    case "ishl": 356                   aop rev s      , aop rev u      , aop s  table   , aop u  table
# K16    270    case "ushr": 479                   aop rev u      , aop u  table
# K17    271    case "ishr": 357                   aop rev s      , aop s  table
# K18    272    case "idiv": 313                   aop rev s      , aop s  table
# K19    273    case "irem": 354                   aop rev s      , aop s  table
# K20    274    case "fadd": 177                   aop f  table   , aop rev f
# K21    275    case "fmul": 253                   aop f  table   , aop rev f
# K22    276    case "flt": 240                    aop f  table   , aop rev f
# K23    277    case "fneu": 260                   aop f  table   , aop rev f
# K24    278    case "feq": 213                    aop f  table   , aop rev f
# K25    279    case "fdiv": 198                   aop f  table   , aop rev f
# K26    280    case "frcp": 270                   aop f  table   , aop rev f
# K27    281    case "fmax": 248                   aop f  table   , aop rev f
# K28    282    case "ftrunc": 288                 aop f  table   , aop rev f
# K29    283    case "fsin": 279                   aop f  table   , aop rev f
# K30    284    case "fexp2": 221                  aop f  table   , aop rev f
# K31    285    case "flog2": 238                  aop f  table   , aop rev f
# K32    286    case "mov": 365                    mesa alu
# K33    287    case "vec2": 484                   mesa alu
# K34    288    case "vec3": 485                   mesa alu
# K35    289    case "vec4": 486                   mesa alu
# K36    290    case "vec5": 487                   mesa alu
# K37    291    case "vec8": 488                   mesa alu
# K38    292    case "vec16": 483                  mesa alu
# K39    293    case "b2b1": 28                    ncast from bool , ncast from weaki
# K40    294    case "b2f16": 32                   ncast from bool , ncast from weaki
# K41    295    case "b2f32": 33                   ncast from bool , ncast from weaki
# K42    296    case "b2f64": 34                   ncast from bool , ncast from weaki
# K43    297    case "b2i8": 39                    ncast from bool , ncast from weaki
# K44    298    case "b2i16": 36                   ncast from bool , ncast from weaki
# K45    299    case "b2i32": 37                   ncast from bool , ncast from weaki
# K46    300    case "b2i64": 38                   ncast from bool , ncast from weaki
# K47    301    case "f2f16": 156                  ncast from float
# K48    302    case "f2f32": 159                  ncast from float
# K49    303    case "f2f64": 160                  ncast from float
# K50    304    case "f2i8": 166                   ncast from float
# K51    305    case "f2i16": 163                  ncast from float
# K52    306    case "f2i32": 164                  ncast from float
# K53    307    case "f2i64": 165                  ncast from float
# K54    308    case "i2f16": 293                  ncast from int32, ncast from long
# K55    309    case "i2f32": 294                  ncast from int32, ncast from long
# K56    310    case "i2f64": 295                  ncast from int32, ncast from long
# K57    311    case "i2i8": 301                   ncast from int32, ncast from long
# K58    312    case "i2i16": 298                  ncast from int32, ncast from long
# K59    313    case "i2i32": 299                  ncast from int32, ncast from long
# K60    314    case "i2i64": 300                  ncast from int32, ncast from long
# K61    315    case "u2f16": 411                  ncast from uint8
# K62    316    case "u2f32": 412                  ncast from uint8
# K63    317    case "u2f64": 413                  ncast from uint8
# K64    318    case "u2u8": 419                   ncast from uint8
# K65    319    case "u2u16": 416                  ncast from uint8
# K66    320    case "u2u32": 417                  ncast from uint8
# K67    321    case "u2u64": 418                  ncast from uint8
# K68    413    case "nir_intrinsic_store_global": mesa intr
# K69    414    case "nir_intrinsic_store_shared": mesa intr
# K70    415    case "nir_intrinsic_store_deref":  mesa intr
# K71    416    case "nir_intrinsic_load_global":  mesa intr
# K72    417    case "nir_intrinsic_load_shared":  mesa intr
# K73    418    case "nir_intrinsic_load_deref": 2 mesa intr
# K74    419    case "nir_intrinsic_load_workgroup mesa intr
# K75    420    case "nir_intrinsic_load_local_inv mesa intr
# K76    421    case "nir_intrinsic_barrier": 46   mesa intr
# K77    422    case "nir_intrinsic_ldc_nv": 213   mesa intr
# K78    423    case "nir_intrinsic_load_ubo": 552 mesa intr
# K79    424    case "nir_intrinsic_image_store":  mesa intr
# K80    425    case "nir_intrinsic_image_load": 1 mesa intr
# K81    426    case "nir_type_float16": 144       mesa intr
# K82    427    case "nir_type_float32": 160       mesa intr
# K83    428    case "nir_deref_type_var": 0       mesa intr
# K84    429    case "nir_deref_type_array": 1     mesa intr
# K85    430    case "nir_jump_break": 2           mesa intr
# K86    431    case "MESA_SHADER_COMPUTE": 5      mesa intr
# K87    432    case "SCOPE_WORKGROUP": 4          mesa intr
# K88    433    case "ACCESS_CAN_REORDER": 64      mesa intr
# K89    434    case "GLSL_SAMPLER_DIM_2D": 1      mesa intr
# K90    442    case "NIR_INTRINSIC_ALIGN_MUL": 20 mesa idx
# K91    443    case "NIR_INTRINSIC_WRITE_MASK": 1 mesa idx
# K92    444    case "NIR_INTRINSIC_ACCESS": 17    mesa idx
# K93    445    case "NIR_INTRINSIC_EXECUTION_SCOP mesa idx
# K94    446    case "NIR_INTRINSIC_IMAGE_DIM": 14 mesa idx
# K95    447    case "NIR_INTRINSIC_SRC_TYPE": 23  mesa idx
# K96    448    case "NIR_INTRINSIC_DEST_TYPE": 24 mesa idx
# K97    449    case "NIR_INTRINSIC_RANGE": 5      mesa idx
# K98    1100   case "sm_52": 52                   arch_int sm_52
# K99    1101   case "sm_53": 53                   arch_int sm_53
# K100   1102   case "sm_86": 86                   arch_int sm_86
# K101   1103   case "sm_120": 120                 arch_int sm_120
#
# constant sweep: 101 arms, 0 blind, 0 did-not-compile
# what the gate does not cover, named rather than left implied.
#
# * `nir_instr`'s `index_map` SLOT for each `NIR_INTRINSIC_*` key (nir.py:50).
#   The eight ENUM values are audited and gated; the array that maps them to
#   `const_index` slots is `nir_intrinsic_infos`, an `in_dll` DATA ARRAY that is
#   ABSENT on this tree (mesa.py:989). `TODO(p3) nir.py:50 symbol=nir_instr`.
# * `glsl_type`'s CONSTANTS (nir.py:15-16). All twelve `glsl_type_builtin_*`
#   symbols are `in_dll` DATA symbols and none is bound. The SYMBOL NAMES are
#   ported and gated; the constants are a refusal that names the symbol.
# * `extra_matcher` (:121-143) and `def_rewrite` (:145-167) and `IR3Renderer`'s
#   (:290-296). These are `PatternMatcher` lists of UOp patterns; the matcher's
#   machinery is `cstyle.bend`'s and the rewriting needs the ctypes builder.
#   `TODO(p3) nir.py:121 symbol=extra_matcher`, `:145 symbol=def_rewrite`, `:290 symbol=IR3Renderer.def_rewrite`.
#
#   THE WALL IS THE SHAPE; THE **REASONS** ARE THE SUBSTANCE, AND A WALL
#   WITH NO REASON IS A WALL A READER CANNOT SIZE. UPSTREAM'S FIVE
#   `extra_matcher` RULES EACH CARRY ONE, AND THEY ARE ALL **TARGET
#   CONSTRAINTS** -- NIR'S RULES ABOUT WHAT A LEGAL NIR SHADER MAY CONTAIN --
#   AND NOT ABOUT NIR'S SPELLING:
#   * "a bool is one bit in NIR but a byte in memory, so every access to a
#     bool buffer goes through a uint8 view of it" (nir.py:124). NIR'S `bool`
#     IS A ONE-BIT VALUE WHILE A BUFFER'S ELEMENT IS A BYTE, SO THE BUFFER
#     IS ADDRESSED AS `uint8` AND THE LOAD IS CAST BACK. THE SAME RULE IS IN
#     `ptx.py` (ptx.py:48) FOR PTX, AND NEITHER IS THE SAME AS THE OTHER:
#     PTX'S `bool` IS A **PREDICATE REGISTER**, NIR'S IS A **ONE-BIT
#     VALUE**.
#   * "NIR requires shift amount to be 32 bit" (nir.py:130, with the Mesa
#     doc link). A NARROW SHIFT AMOUNT IS ILLEGAL IN NIR, SO A `u8` SHIFT
#     COUNT IS CAST TO `uint` FIRST. THIS IS A **WIDTH REQUIREMENT** AND NOT
#     A SIGN ONE, WHICH IS WHY THE CAST IS TO **UNSIGNED** -- AND IT IS
#     ALSO WHY `ptx.py`'S RULE (ptx.py:54, "ptx shr and shl instructions
#     require y to be uint") IS THE SAME CAST FOR A DIFFERENT REASON.
#   * "OpConvertFToU is undefined if Result Type is not wide enough, cast
#     through int32" (nir.py:132-133, with the SPIR-V spec link). A FLOAT TO
#     AN 8- OR 16-BIT UNSIGNED CAST IS **UNDEFINED** IN NIR WHEN THE RESULT
#     TYPE IS TOO NARROW, SO THE CAST GOES THROUGH `int32` -- WHICH IS WIDE
#     ENOUGH TO BE DEFINED -- AND THEN NARROWS.
#   * "load/store use pointer arithmetic, and the cast does nothing. NOTE:
#     this doesn't apply to image indexing cause it's 1-D nor to REG/ALU
#     register picks, which keep their own index dtype" (nir.py:135-136).
#     A MEMORY ACCESS'S INDEX IS A **POINTER ARITHMETIC** SCALE AND NOT A
#     VALUE, SO THE INDEX'S DTYPE IS IRRELEVANT AND THE CAST IS DROPPED. THE
#     TWO EXCEPTIONS ARE BOTH REAL AND BOTH EARN THEIR PLACE: AN IMAGE
#     INDEX IS A **COORDINATE** (AND AN IMAGE IS 1-D IN THIS SENSE), AND A
#     REGISTER PICK IS A **VALUE** (AND THE REGISTER KEEPS ITS OWN INDEX
#     DTYPE).
#   * "images need index to be int for nir (coordinates only: the INDEX
#     keeps its access dtype)" (nir.py:140). AN IMAGE COORDINATE MUST BE AN
#     `int` WHILE THE INDEX NODE KEEPS THE ACCESS'S OWN DTYPE -- WHICH IS
#     THE SAME SPLIT AS THE PREVIOUS RULE AND THE SAME REASON: THE
#     COORDINATE IS NOT THE ACCESS.
#   THE POINT FOR A READER OF THE PORT: EVERY ONE OF THESE IS A REWRITE
#   THAT HAPPENS **BEFORE** ISEL, SO THE PORT'S `def_rewrite` EMITTERS
#   (WHICH ARE PORTED) NEVER SEE THE REWRITTEN GRAPH. THE PORT'S `aop`
#   TABLES AND ITS `ncast` ARE THE **POST-REWRITE** SHAPE -- AND THE ONE
#   PLACE THAT SHOWS IS `ncast`'s THIRD ARM, `c(ot, ot == dtypes.bool)`:
#   THE DESTINATION'S `bool` SPELLING IS `"b"` ONLY WHEN THE DESTINATION IS
#   `bool`, AND UPSTREAM WRITES THAT AS A SPECIAL CASE *INSIDE* THE SPELLING
#   RATHER THAN AS A SEPARATE RULE. SO A `bool` CAST SURVIVES IN THE
#   POST-REWRITE GRAPH AND `ncast`'s `from bool` ROW IS A REAL ROW AND NOT
#   A LEFTOVER.
# * `__init__` (:169-174), `__del__` (:176-177), `param` (:179), `prerender`
#   (:180), `postrender` (:182), `render` (:184-242). Every one is mesa FFI.
#   `render`'s control flow over a uop list is `nir_llvmir.bend`'s lane and its
#   emitted text is a `nir_shader` serialization, not a string this file can
#   diff. `TODO(p3) nir.py:169 symbol=NIRRenderer.__init__`.
# * `nif`/`if_phi` (:30-35, :103) and `njump` (:99-101) and `nidx` (:105-113):
#   builder stack operations. `nidx`'s REG arm builds a deref and its other arm
#   spells `iadd`/`imul` with an `nimm` of the itemsize -- those two op names
#   ARE gated (`mesa alu`), the control flow is not.
#   ONE OF THOSE `nif`s IS A **KNOWN-REDUNDANT** ONE, AND UPSTREAM SAYS SO:
#   "TODO: this nif should be removable ... but
#   TestMultiTensor.test_double_matmul_shard_W_0 segfaults with it gone"
#   -- nir.py:223, on the `Ops.END` ARM'S `nif`. IT LOOKS REDUNDANT BECAUSE
#   THE `Ops.BACKEDGE` ARM (nir.py:217) ALREADY EMITS THE SAME
#   `ilt`-THEN-BREAK TEST AND THE LOOP'S OWN STRUCTURE SUPERSEDES IT. BUT
#   REMOVING IT SEGFAULTS ONE UPSTREAM TEST, AND THE TODO IS THE RECORD OF
#   THAT FACT.
#   WHICH IS A CLASS OF ITS OWN AND IT IS WORTH NAMING: A COMMENT THAT SAYS
#   "THIS IS REDUNDANT" WITH A TEST NAME NEXT TO IT IS A **KNOWN-WRONG**
#   PIECE OF CODE, NOT A REFUSAL. THE PORT DOES NOT HAVE THE ARM -- THE
#   CONTROL FLOW IS THE WALL ABOVE -- BUT THE PORT'S `nir_jump_break` ROW
#   (the `mesa intr` group) IS THE CONSTANT THAT ARM WOULD USE, AND A
#   READER WHO SEES THE CONSTANT SHOULD KNOW AN UPSTREAM ARM EMITS IT AND
#   THAT UPSTREAM COULD NOT DELETE IT.
# * `nimm_set` (:69-71): a `struct.pack_into` of `truncate[dtype](x)`. The dtype
#   fmt strings live in `dtype.bend`, which fails its own `--check-only` (see
#   `renderer/__init__.bend`'s convention 11 note). `TODO(p3) nir.py:69 symbol=nimm_set`.
# * `tovec` (:273) and `nfloat` (:274): `nfloat` is one `match` on `half`, and
#   its two values (`nir_type_float16`=144, `nir_type_float32`=160) are gated;
#   `tovec`'s ARITY is gated (`mesa alu`'s `vec4`) and its four-src composition
#   is not.
# * `NAKRenderer.param` (:248-251) and `LVPRenderer.param` (:264-267) and
#   `IR3Renderer._param_img` (:299-301): the `nir_intrinsic_ldc_nv` /
#   `load_ubo` builders. Their INTRINSIC constants are gated; the builders are
#   not. `padded_idx`, which they reduce over (:271, :309), IS gated.
# * `IR3Renderer.postrender` (:312-319): `num_ubos` / `num_images` bookkeeping
#   over `itertools.count`. `TODO(p3) nir.py:312 symbol=IR3Renderer.postrender`.
#
# the walls `nir_llvmir.bend` names, and which of them this port closes.
#
# Its header lists STAGE 3 as "`nir.py`: `glsl_type` (:14), `u_aop`/`s_aop`/
# `f_aop` (:19-23), `c` (:26), `ncast` (:27-28), `scope` (:83), `padded_idx`
# (:246), the intrinsic bounds arithmetic (`num_components`, `ALIGN_MUL`,
# `WRITE_MASK`, `bit_size`), and `NIRRenderer` / `NAKRenderer` / `LVPRenderer` /
# `IR3Renderer`'s `supported_dtypes` (:244, :253, :321) and `code_for_op` (:119,
# :262)". EVERY ONE OF THOSE IS HERE, and each is gated by CPython:
#
#   CLOSED  `glsl_type` (:14-16)      symbol names + a measured refusal for the
#                                    constants (`glsl keys`, `glsl call`)
#   CLOSED  `u_aop`/`s_aop`/`f_aop` (:19-23)  both directions (`aop u/s/f table`,
#                                    `aop rev u/s/f`) and every mesa enum behind
#                                    them (`aop *` carries `name/value`)
#   CLOSED  `aop` (:24)               the key ORDER (`aop u keys`) and the class
#                                    tag (`aop kind *`)
#   CLOSED  `c` (:26)                 17 dtypes x 2 plus the three weak ones, so
#                                    `in_ints` and `S.Dt.is_int` are separated
#   CLOSED  `ncast` (:27-28)          the full 17x17 grid per source, six rows,
#                                    each cell `name/mesa_value`, asked of the
#                                    real `nir.ncast`
#   CLOSED  `scope` (:83)             four addrs, with `ALU` the row that pins the
#                                    `else`
#   CLOSED  `padded_idx` (:246)       11 x 5 grid (`padded tbl`) plus five singles
#   CLOSED  the intrinsic bounds arithmetic (:84-91)  `WRITE_MASK`, `ALIGN_MUL`
#                                    on both sides, the REG-only ABSENCE, and the
#                                    REG `srcs` REVERSAL as a name list
#   CLOSED  `supported_dtypes` (:244, :253, :321)  all three overrides, five
#                                    arches, in `dtypes.all` order (`sd *`)
#   CLOSED  `code_for_op` (:119, :262)  21 ops and LVP's 20 without `EXP2`
#   CLOSED  the three maxima + `has_local`/`has_shared` (:118, :256-258)  the
#                                    `Nir` record, read per device (`rec *`)
#   CLOSED  `bit_size` (:61, :73, :77) and `nc`/`has_def` (:61, :84, :93-94, :96)
#
# NOT CLOSED, and `nir_llvmir.bend` still owns them:
#   its STAGE 2  `_render_fn`, `_render_footer`, `base_rewrite`'s per-op emitter
#                strings and `_render_kernel`'s naming walk -- all `llvmir.py`.
#   its STAGE 4  everything else, unnamed here.
#   `nir.py`'s `extra_matcher`, `def_rewrite`, `render` and the mesa builders.
#
# The one place this port's answer and a `nir_llvmir.bend` answer could be
# compared is the `Dt.nm` SPELLING, and on 2026-10-02 they did NOT agree:
# `tinygrad/dtype.py` was renamed in the index (`DType.name` is now `"u8"`,
# `"f16"`, `"f32"`) and `LAWS/spec.bend`'s `Dt.nm` followed within the hour.
# Both files had ten of seventeen disagreeing for a while. This file's rows are
# keyed to `spec.bend`, and `.agents/slop/nir/nir_oracle.py spelling` prints the
# comparison; it now reports 0 of 20 differing.
