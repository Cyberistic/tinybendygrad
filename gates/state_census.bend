# state_census.bend -- THE GATE DRIVER for `tinybendygrad/nn/state.bend`.
#
#   .venv/bin/python gates/state_census-gate.py
#
# WHY A DRIVER AND NOT THE FILE'S OWN `main`. `nn/state.bend`'s `main` (:838) prints FOURTEEN
# rows and every one of them is a BOOLEAN: `sd_row("sd_nest", String.eq(sd_keys(...),
# "layers.0.weight,..."))`. A Boolean row answers "the port agrees with a string that was
# transcribed into BOTH lanes", so a diff that moved can only ever say "the port computed
# something else", never WHICH, and a transcription error that landed in both lanes is GREEN.
# This driver asks the port for the VALUE and lets CPython supply the expected one, which is
# the only shape in which a byte diff is a claim about the port rather than about a Bool.
#
# IT ALSO RE-DRIVES THE PORT'S OWN FOURTEEN. `St.t_tens()` .. `St.t_param()` are top-level
# `IO(Unit)` defs, so they can be CALLED, and they are called here rather than left to the
# file's `main` (which `bend` runs as the entry point and nothing else can). Nothing is lost:
# the Booleans the file shipped are still in the lane, and now they sit next to the values
# that explain them.
#
# EVERY ROW IS A VALUE. `val_tens` prints `,` -- the empty key's trailing comma -- and
# `val_nest` prints the eleven-key list, and CPython prints the same two strings from
# `get_state_dict`. The fixtures are the file's OWN (`St.sd_t1`, `St.sd_t2`, `St.sd_t3`,
# `St.sd_t9`), so this driver and `nn/state.bend` cannot drift on the fixture either.
#
# NO UOp IS BUILT FOR A ROW'S OWN SAKE, except `val_dup_val`, which reads a CONST's payload
# through `St.sd_cval` so the dict-collapse can be checked on WHICH value survived rather than
# on how many survived.
import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/nn/state.bend as St

def p(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def pu(nm: String, n: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(n)]))
def pb(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

# `Maybe<Dt>` AS A STRING, and `-` for `None`, which is CPython's `safe_dtypes[nm]` raising
# a `KeyError`. The lookup itself is the port's `St.sd_get`, so this row is the real search
# and not a restatement of the table.
def dt_of(m: Maybe<&1, S.Dt>) -> String:
  match m:
    case Some{d}: T.dt_name(d)
    case None{}: "-"

# `Maybe<String>` the same way, for `inverse_safe_dtypes`.
def str_of(m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "-"

# `St.sd_spellings` joins `List<Sd>`; the whitelist is `List<String>`, and one fold does it.
def wjoin(es: List<&2, String>) -> String:
  List.foldl(~&2, ~String, ~String, (acc: String) => (e: String) => String.concat([acc, e, ","]), es, "")

# ===========================================================================
# A. THE PORT'S OWN FOURTEEN BOOLEAN ROWS, called through the port's defs.
# ===========================================================================
def port_rows() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- St.t_tens()
    b : Unit <- St.t_map()
    c : Unit <- St.t_seq()
    d : Unit <- St.t_nest()
    e : Unit <- St.t_strip()
    f : Unit <- St.t_attr()
    g : Unit <- St.t_ord()
    h : Unit <- St.t_dup()
    i : Unit <- St.t_safe()
    j : Unit <- St.t_safedt()
    k : Unit <- St.t_invn()
    l : Unit <- St.t_inv()
    m : Unit <- St.t_seek()
    St.t_param()

# ===========================================================================
# B. THE VALUE ROWS. Six classes, one value row each plus a COUNT row and a
#    CONTROL row, and the control is the SAME computation under a second name --
#    a diff between two identical rows is a diff only if the lane is stable.
# ===========================================================================

# --- C1 KEYS: `get_state_dict`'s answer as a LIST OF NAMES -------------
def nest_obj() -> St.Obj:
  bn : St.Obj = St.OMap{[St.Kv{"weight", St.OTens{St.sd_t1()}}, St.Kv{"bias", St.OTens{St.sd_t2()}},
    St.Kv{"num_batches_tracked", St.OTens{St.sd_t3()}}, St.Kv{"running_mean", St.OTens{St.sd_t1()}},
    St.Kv{"running_var", St.OTens{St.sd_t2()}}]}
  tail : St.Obj = St.OMap{[St.Kv{"weight", St.OTens{St.sd_t3()}}]}
  layers : St.Obj = St.OSeq{[bn, St.OOther{St.sd_t2()}, tail]}
  St.OMap{[St.Kv{"layers", layers}]}

def c_keys() -> IO(Unit):
  do IO<Unit>:
    p("val_tens", St.sd_keys(St.sd_collapsed(St.OTens{St.sd_t1()})))
    p("val_map", St.sd_keys(St.sd_collapsed(St.OMap{[St.Kv{"w", St.OTens{St.sd_t1()}}]})))
    p("val_seq", St.sd_keys(St.sd_collapsed(St.OSeq{[St.OTens{St.sd_t1()}, St.OTens{St.sd_t2()}]})))
    p("val_nest", St.sd_keys(St.sd_collapsed(nest_obj())))
    p("val_attr1", St.sd_keys(St.sd_collapsed(St.OMap{[St.Kv{"a", St.OTens{St.sd_t1()}},
      St.Kv{"b", St.OTens{St.sd_t2()}}]})))
    p("val_attr2", St.sd_keys(St.sd_collapsed(St.OMap{[St.Kv{"q", St.OTens{St.sd_t1()}}]})))
    p("val_ord", St.sd_keys(St.sd_collapsed(St.OMap{[St.Kv{"z", St.OTens{St.sd_t1()}},
      St.Kv{"a", St.OTens{St.sd_t2()}}]})))
    # THE CONTROL: `val_ord`'s fixture under a second name. If these two ever differ the
    # lane is not stable and every other row on it is worthless.
    p("ctrl_ord", St.sd_keys(St.sd_collapsed(St.OMap{[St.Kv{"z", St.OTens{St.sd_t1()}},
      St.Kv{"a", St.OTens{St.sd_t2()}}]})))
    # THE BOOLEAN CLASS'S CONTROL, and it was MISSING until the class census said so. The
    # twenty `True`/`False` rows in this lane each compare against a literal that lives in
    # the LANE, so there is no third place to perturb them -- which is exactly what the
    # class census calls C-BOOL's "cannot distinguish". This row is the closest thing that
    # CAN be said about a Boolean row: the same comparison asked twice gives the same
    # answer. It does not close the hole; it is here so the hole is named by a row.
    pb("ctrl_bool", St.sd_is_weak(S.single()))
    pu("val_keys_n", U32.from_nat(List.length(&2, St.Ent, St.sd_collapsed(nest_obj()))))

# --- C2 COLLAPSE: which value survived, not how many survived -----------
# `{'a.b': t1, 'a': {'b': t9}}` -- CPython collapses to ONE entry holding the LAST value,
# at the FIRST position. `val_dup_val` reads that value's CONST payload, so a `sd_put` that
# APPENDED would fail `val_dup_n` and a `sd_put` that FILTERED would pass it and fail this.
def dup_obj() -> St.Obj:
  St.OMap{[St.Kv{"a.b", St.OTens{St.sd_t1()}},
           St.Kv{"a", St.OMap{[St.Kv{"b", St.OTens{St.sd_t9()}}]}}]}

def c_collapse() -> IO(Unit):
  +cs : List<&2, St.Ent> = St.sd_collapsed(dup_obj())
  do IO<Unit>:
    p("val_dup_keys", St.sd_keys(cs))
    pu("val_dup_val", St.sd_first_val(cs))
    pu("val_dup_n", U32.from_nat(List.length(&2, St.Ent, cs)))

# --- C3 STRIP: `prefix.strip('.')`, one row per prefix ------------------
def c_strip() -> IO(Unit):
  do IO<Unit>:
    p("val_strip_0", St.sd_strip(""))
    p("val_strip_1", St.sd_strip("."))
    p("val_strip_2", St.sd_strip(".."))
    p("val_strip_3", St.sd_strip(".a."))
    p("val_strip_4", St.sd_strip("a..b.."))
    p("val_strip_5", St.sd_strip("a"))
    # THE CONTROL, and the row that exists because of the file's OWN bug: an earlier
    # `sd_drop.head` dropped EVERY dot and `a..b..` came back `ab`. This row is the one
    # that says the interior run SURVIVES, as a value and not as a Bool.
    p("ctrl_strip", St.sd_strip("....a....b...."))

# --- C4 THE DTYPE TABLE: spellings, count, lookup both ways -------------
# The spellings are a joined value AND a count, because a table that lost its last entry
# still satisfies the joined prefix a diff would show as a shortened string.
def c_safe() -> IO(Unit):
  do IO<Unit>:
    p("val_safe", St.sd_spellings(St.safe_dtypes()))
    pu("val_safe_n", U32.from_nat(List.length(&2, St.Sd, St.safe_dtypes())))
    p("val_get_BOOL", dt_of(St.sd_get("BOOL")))
    p("val_get_I8", dt_of(St.sd_get("I8")))
    p("val_get_U8", dt_of(St.sd_get("U8")))
    p("val_get_I16", dt_of(St.sd_get("I16")))
    p("val_get_U16", dt_of(St.sd_get("U16")))
    p("val_get_I32", dt_of(St.sd_get("I32")))
    p("val_get_U32", dt_of(St.sd_get("U32")))
    p("val_get_I64", dt_of(St.sd_get("I64")))
    p("val_get_U64", dt_of(St.sd_get("U64")))
    p("val_get_F8_E4M3", dt_of(St.sd_get("F8_E4M3")))
    p("val_get_F8_E5M2", dt_of(St.sd_get("F8_E5M2")))
    p("val_get_F16", dt_of(St.sd_get("F16")))
    p("val_get_BF16", dt_of(St.sd_get("BF16")))
    p("val_get_F32", dt_of(St.sd_get("F32")))
    p("val_get_F64", dt_of(St.sd_get("F64")))
    # THE NEGATIVE FIXTURE. A lookup whose every fixture is POSITIVE cannot see a lookup
    # that answers `Some` for a spelling the table does not have, so one is asked for.
    p("val_get_none", dt_of(St.sd_get("NOSUCH")))
    # THE LOOKUP CLASS'S CONTROL: the same lookup asked twice, so a lane that answered a
    # lookup differently on two identical calls is caught here rather than by one of the
    # fifteen `val_get_*` rows being quietly the wrong dtype.
    p("ctrl_get", dt_of(St.sd_get("BF16")))
    # and the reverse, `inverse_safe_dtypes`, one row per dtype -- `safe_save` takes this
    # direction, and a table that is not a bijection corrupts it silently.
    p("val_name_bool", str_of(St.sd_name(S.boolean())))
    p("val_name_f32", str_of(St.sd_name(S.single())))
    p("val_name_f64", str_of(St.sd_name(S.double())))
    p("val_name_bf16", str_of(St.sd_name(S.bfloat16())))
    p("val_name_fp8e4m3", str_of(St.sd_name(S.fp8e4m3())))
    p("val_name_fp8e5m2", str_of(St.sd_name(S.fp8e5m2())))
    p("val_name_weak", str_of(St.sd_name(S.weakint())))
    p("val_name_none", str_of(St.sd_name(S.void())))
    # `safe_save`'s refusal at state.py:73 is `v.dtype in dtypes.weaks`, and `safe_dtypes`
    # does NOT contain either weak -- so this is a TABLE-MEMBERSHIP claim, and it is the
    # one row in C4 whose answer is False on both sides BY DESIGN.
    pb("val_weak_in", St.sd_is_weak(S.weakint()))
    pb("val_weak_out", St.sd_is_weak(S.single()))

# --- C5 SEEK: `TensorIO.seek`, one row per call -------------------------
# Seven rows, each a `hi:lo` pair from `H.i64_text`. The two NEGATIVE offsets are passed as
# their two's complement `U32` images because `St.sd_seek`'s parameter is a `U32`; a `U32`
# clamp answers `4294967295:4294967295` where CPython answers `0:0`.
def c_seek() -> IO(Unit):
  do IO<Unit>:
    p("val_seek_0_0_0", St.sd_seek_v(1, 0, 0, 0))
    p("val_seek_0_1_0", St.sd_seek_v(1, 0, 1, 0))
    p("val_seek_0_neg1_0", St.sd_seek_v(1, 0, 4294967295, 0))
    p("val_seek_0_1_1", St.sd_seek_v(1, 0, 1, 1))
    p("val_seek_0_0_2", St.sd_seek_v(1, 0, 0, 2))
    p("val_seek_0_9_0", St.sd_seek_v(1, 0, 9, 0))
    p("val_seek_0_neg5_0", St.sd_seek_v(1, 0, 4294967291, 0))
    # THE SEEK CLASS'S CONTROL: `seek(0,0)` on a four-element tensor is the one call whose
    # answer is the SAME whatever the length, so it pins the fixture without pinning the
    # clamp.
    p("ctrl_seek", St.sd_seek_v(4, 3, 0, 0))

# --- C6 THE WHITELIST: `TorchPickle.find_class`'s predicate -------------
# `module.split(".")[0]` against `{"torch","collections","numpy","_codecs"}`. The file
# records that its own first version returned the EMPTY root for a module with no dot,
# which INVERTED the test on every such module -- so these are four rows, not one Bool, and
# the module with no dot is here on purpose.
def c_fc() -> IO(Unit):
  do IO<Unit>:
    p("val_fc_root_os", St.sd_fc_root("os.path"))
    p("val_fc_root_col", St.sd_fc_root("collections"))
    p("val_fc_root_np", St.sd_fc_root("numpy"))
    p("val_fc_root_torch", St.sd_fc_root("torch.storage"))
    p("val_fc_root_empty", St.sd_fc_root(""))
    p("val_fc_whitelist", wjoin(St.sd_fc_whitelist()))
    pb("val_fc_ok_os", St.sd_fc_allowed("os.path"))
    pb("val_fc_dummy_os", St.sd_fc_dummy("os.path"))
    pb("val_fc_dummy_col", St.sd_fc_dummy("collections"))
    pb("val_fc_dummy_np", St.sd_fc_dummy("numpy"))
    # THE PRINTED STRING, at both DEBUG levels, so `sd_dbg`'s two-input form is gated on
    # the TEXT and not only on the Bool: the file records that `{module}` in the f-string
    # is `posixpath` even when the caller wrote `os.path`.
    p("val_dbg_2_os", St.sd_dbg(2, "posixpath", "join"))
    p("val_dbg_3_os", St.sd_dbg(3, "posixpath", "join"))
    p("val_dbg_1_os", St.sd_dbg(1, "posixpath", "join"))
    p("val_dbg_2_col", St.sd_dbg(2, "collections", "OrderedDict"))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- port_rows()
    b : Unit <- c_keys()
    c : Unit <- c_collapse()
    d : Unit <- c_strip()
    e : Unit <- c_safe()
    f : Unit <- c_seek()
    c_fc()
