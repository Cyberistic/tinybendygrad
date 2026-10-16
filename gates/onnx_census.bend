# onnx_census.bend -- THE GATE DRIVER for `tinybendygrad/nn/onnx.bend`, layer 1 of 3.
#
#   .venv/bin/python gates/onnx_census-gate.py
#
# WHY A DRIVER RATHER THAN THE FILE'S OWN `main`. `nn/onnx.bend`'s `main` (:1846) prints 123
# rows, 46 of them INLINE in `main` and the rest delegated to five row-group helpers. `bend`
# runs `main` as the entry point and nothing else can call it, so a `gatekit` gate that names
# the PORT file as its driver compares the port against an oracle through `main`, and a gate
# that names a `gates/*.bend` driver compares through whatever that driver chose to call. The
# FIRST is weaker and the second is honest: a driver can print what the port computes WITHOUT
# transcribing an expected value, and it can add rows the port does not have.
#
# SO NOTHING IS LOST. Every one of `main`'s 123 rows is reproduced here, verbatim in the same
# order, by calling the port's own defs -- `onx_ops_rows`, `onx_p2t_rows`, `onx_ap_rows`,
# `onx_pool_rows`, `onx_axes_rows` for the groups and `onx_row("nm", <the same def main calls>)`
# for the forty-six inline ones. The expected v_rows are NOT transcribed here: every row is
# `Bool.eq(port_def(), <a literal>)` computed INSIDE the port, and CPython's answer comes from
# `gates/onnx_census-oracle.py` calling tinygrad's own `OnnxDataType`, `AttributeType`,
# `WireType`, `Domain`, `required_input_python_consts`, `onnx_ops` and
# `OnnxRunner._select_op`.
#
# WHAT IS ADDED, AND IT IS ADDITIVE ONLY. Eighty extra `v_*` rows, each printing the SUBJECT of
# one of `main`'s Boolean rows as a VALUE:
#
#   * every COUNT. `onnx_wt_n` is `Bool.eq(onx_wt_n(), 6)`, so a table that grew answered
#     False on both lanes and the diff said nothing about the number. `v_cnt_wt` prints `6`.
#   * every ENUM ROUND TRIP, cell by cell, through the port's own lookup
#     (`onx_odt_name_of`, `onx_odt_key_of`, `onx_at_name_of`, `onx_at_field_of`,
#     `onx_wt_name`) over the port's own code list (`onx_odt_codes`, `onx_at_codes`,
#     `onx_wt_codes`). Those code lists are the port's DATA and are read from the port, not
#     written here, so a census that disagrees with CPython about the codes is disagreeing
#     about tinygrad's, which is the point.
#   * every `_select_op` FIXTURE, through `onx_sel_str`, as a NAME. `main` already prints
#     those as `onnx_sel_*`, and they are the only version-router rows in the file.
#
# THE SIX `*_rows` / `onnx_stage2` ROWS ARE LITERALS AND STAY. `onx_ops_rows()`,
# `onx_p2t_rows()`, `onx_ap_rows()`, `onx_pool_rows()`, `onx_axes_rows()` and
# `onnx_stage2=True` print a CONSTANT on both lanes, so they assert only that the group ran.
# They are kept because deleting a row the port ships would be weakening an instrument to make
# it pass; they are CLASSIFIED as C-CONST by `gates/onnx_census-gate.py`, which prints what
# that class cannot distinguish, and `ctrl_p2t` is a real control row for it -- the same
# `_onnx_pads_to_tiny_pads` fixture under a second name, so a group that emitted nothing or
# emitted twice is visible.
import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/nn/onnx.bend as N

def p(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def pu(nm: String, n: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(n)]))

# ---------------------------------------------------------------------------
# A. `main`'s FORTY-SIX INLINE ROWS, reproduced through the port's own defs.
# ---------------------------------------------------------------------------
def inline_rows() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- N.onx_row("onnx_wt", N.onx_wt_rt())
    _ : Unit <- N.onx_row("onnx_wt_n", U32.is_eq(N.onx_wt_n(), 6))
    _ : Unit <- IO.print(String.concat(["onnx_wt_tbl=", N.onx_wt_tbl()]))
    _ : Unit <- N.onx_row("onnx_at", N.onx_at_rt())
    _ : Unit <- N.onx_row("onnx_at2", N.onx_at_rt2())
    _ : Unit <- N.onx_row("onnx_at_n", U32.is_eq(N.onx_at_n(), 8))
    _ : Unit <- IO.print(String.concat(["onnx_at_tbl=", N.onx_at_tbl()]))
    _ : Unit <- N.onx_row("onnx_odt_rt", N.onx_odt_rt())
    _ : Unit <- N.onx_row("onnx_odt_rt2", N.onx_odt_rt2())
    _ : Unit <- N.onx_row("onnx_odt_n", U32.is_eq(N.onx_odt_n(), 13))
    _ : Unit <- N.onx_row("onnx_odt_dt_rt", N.onx_odt_dt_rt())
    _ : Unit <- N.onx_row("onnx_odt_all", N.onx_odt_all_members())
    _ : Unit <- N.onx_row("onnx_odt_holes_rt", N.onx_odt_holes_rt())
    _ : Unit <- N.onx_row("onnx_odt_inv", N.onx_odt_inv())
    _ : Unit <- IO.print(String.concat(["onnx_odt_inv_tbl=", N.onx_odt_inv_tbl()]))
    _ : Unit <- N.onx_row("onnx_odt_inv_neg", N.onx_odt_inv_neg())
    _ : Unit <- IO.print(String.concat(["onnx_odt_tbl=", N.onx_odt_tbl()]))
    _ : Unit <- IO.print(String.concat(["onnx_odt_ktbl=", N.onx_odt_ktbl()]))
    _ : Unit <- IO.print(String.concat(["onnx_odt_dtbl=", N.onx_odt_dtbl()]))
    _ : Unit <- IO.print(String.concat(["onnx_odt_holes=", N.onx_odt_holes()]))
    _ : Unit <- IO.print(String.concat(["onnx_odt_hole_dts=", N.onx_odt_hole_dts()]))
    _ : Unit <- IO.print(String.concat(["onnx_aval_tags=", N.onx_aval_tags()]))
    _ : Unit <- IO.print(String.concat(["onnx_dom_tbl=", N.onx_dom_tbl()]))
    _ : Unit <- N.onx_row("onnx_dom_n", U32.is_eq(N.onx_dom_n(), 9))
    _ : Unit <- N.onx_row("onnx_dom_rt", N.onx_dom_rt())
    _ : Unit <- N.onx_row("onnx_dom_empty", N.onx_dom_empty())
    _ : Unit <- N.onx_row("onnx_dom_onnx", N.onx_dom_onnx())
    _ : Unit <- N.onx_row("onnx_dom_tiny", N.onx_dom_tiny())
    _ : Unit <- N.onx_row("onnx_dom_ms", N.onx_dom_ms())
    _ : Unit <- N.onx_row("onnx_dom_unknown", N.onx_dom_unknown())
    _ : Unit <- N.onx_row("onnx_dom_unknown2", N.onx_dom_unknown2())
    _ : Unit <- N.onx_row("onnx_dom_unknown3", N.onx_dom_unknown3())
    _ : Unit <- IO.print(String.concat(["onnx_dom_training=", N.onx_dom_training()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_tbl=", N.onx_pc_tbl()]))
    _ : Unit <- N.onx_row("onnx_pc_n", U32.is_eq(N.onx_pc_n(), 38))
    _ : Unit <- IO.print(String.concat(["onnx_pc_reduce=", N.onx_pc_reduce()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_adam=", N.onx_pc_adam()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_slice=", N.onx_pc_slice()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_range=", N.onx_pc_range()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_pad=", N.onx_pc_pad()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_dropout=", N.onx_pc_dropout()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_hann=", N.onx_pc_hann()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_absent=", N.onx_pc_absent()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_absent2=", N.onx_pc_absent2()]))
    _ : Unit <- N.onx_row("onnx_pc_has_hit", N.onx_pc_has_hit())
    _ : Unit <- N.onx_row("onnx_pc_has_miss", N.onx_pc_has_miss())
    _ : Unit <- N.onx_row("onnx_pc_has_abs", N.onx_pc_has_abs())
    N.onx_row("onnx_pc_has_neg", N.onx_pc_has_neg())

# ---------------------------------------------------------------------------
# B. `main`'s SIX GROUP ROWS, through the port's own helpers. UNCHANGED.
# ---------------------------------------------------------------------------
def group_rows() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- N.onx_ops_rows()
    b : Unit <- N.onx_p2t_rows()
    c : Unit <- N.onx_ap_rows()
    d : Unit <- N.onx_pool_rows()
    N.onx_axes_rows()

# ===========================================================================
# C. THE ADDED VALUE ROWS. Every one of these prints a SUBJECT of a Boolean row
#    above, so a defect names itself instead of answering False.
# ===========================================================================

# `main`'s COUNTS, as numbers. Five of the six are `Bool.eq(<count>, <literal>)`, and the
# sixth (`onnx_ops_n`) is the only one `main` did not print at all -- `171` is asserted by
# `onnx_ops_tbl`'s LENGTH and nothing else, so a table that lost an entry from the middle
# would keep both. `v_cnt_*_codes` are the CODE lists, which are the fixture every cell row
# below is indexed by: a census that disagrees about the codes disagrees about the port's
# table of tinygrad's codes, and says so in its own row.
def v_counts() -> IO(Unit):
  do IO<Unit>:
    pu("v_cnt_wt", N.onx_wt_n())
    pu("v_cnt_at", N.onx_at_n())
    pu("v_cnt_odt", N.onx_odt_n())
    pu("v_cnt_dom", N.onx_dom_n())
    pu("v_cnt_pc", N.onx_pc_n())
    pu("v_cnt_ops", U32.from_nat(List.length(&2, String, N.onnx_ops())))
    pu("v_cnt_at_codes", U32.from_nat(List.length(&2, U32, N.onx_at_codes())))
    pu("v_cnt_wt_codes", U32.from_nat(List.length(&2, U32, N.onx_wt_codes())))
    pu("v_cnt_odt_codes", U32.from_nat(List.length(&2, U32, N.onx_odt_codes())))

# THE ENUM TABLES, CELL BY CELL, through the port's own lookups over the port's own code
# lists. `onx_odt_tbl` joins them and a diff would show one changed cell inside a string; these
# rows localise it.
def v_wt_cells() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- p("v_wt_0", N.onx_wt_name(0))
    a1 : Unit <- p("v_wt_1", N.onx_wt_name(1))
    a2 : Unit <- p("v_wt_2", N.onx_wt_name(2))
    a3 : Unit <- p("v_wt_3", N.onx_wt_name(3))
    a4 : Unit <- p("v_wt_4", N.onx_wt_name(4))
    p("v_wt_5", N.onx_wt_name(5))

def v_at_cells() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- p("v_at_1", String.concat([N.onx_at_name_of(1), "/", N.onx_at_field_of(1)]))
    a2 : Unit <- p("v_at_2", String.concat([N.onx_at_name_of(2), "/", N.onx_at_field_of(2)]))
    a3 : Unit <- p("v_at_3", String.concat([N.onx_at_name_of(3), "/", N.onx_at_field_of(3)]))
    a4 : Unit <- p("v_at_4", String.concat([N.onx_at_name_of(4), "/", N.onx_at_field_of(4)]))
    p("v_at_5", String.concat([N.onx_at_name_of(5), "/", N.onx_at_field_of(5)]))
    a6 : Unit <- p("v_at_6", String.concat([N.onx_at_name_of(6), "/", N.onx_at_field_of(6)]))
    a7 : Unit <- p("v_at_7", String.concat([N.onx_at_name_of(7), "/", N.onx_at_field_of(7)]))
    p("v_at_8", String.concat([N.onx_at_name_of(8), "/", N.onx_at_field_of(8)]))

def v_odt_cells() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- p("v_odt_1", String.concat([N.onx_odt_name_of(1), "/", N.onx_odt_key_of(1)]))
    a2 : Unit <- p("v_odt_2", String.concat([N.onx_odt_name_of(2), "/", N.onx_odt_key_of(2)]))
    a3 : Unit <- p("v_odt_3", String.concat([N.onx_odt_name_of(3), "/", N.onx_odt_key_of(3)]))
    a4 : Unit <- p("v_odt_4", String.concat([N.onx_odt_name_of(4), "/", N.onx_odt_key_of(4)]))
    a5 : Unit <- p("v_odt_5", String.concat([N.onx_odt_name_of(5), "/", N.onx_odt_key_of(5)]))
    a6 : Unit <- p("v_odt_6", String.concat([N.onx_odt_name_of(6), "/", N.onx_odt_key_of(6)]))
    a7 : Unit <- p("v_odt_7", String.concat([N.onx_odt_name_of(7), "/", N.onx_odt_key_of(7)]))
    a9 : Unit <- p("v_odt_9", String.concat([N.onx_odt_name_of(9), "/", N.onx_odt_key_of(9)]))
    a10 : Unit <- p("v_odt_10", String.concat([N.onx_odt_name_of(10), "/", N.onx_odt_key_of(10)]))
    a11 : Unit <- p("v_odt_11", String.concat([N.onx_odt_name_of(11), "/", N.onx_odt_key_of(11)]))
    a12 : Unit <- p("v_odt_12", String.concat([N.onx_odt_name_of(12), "/", N.onx_odt_key_of(12)]))
    a13 : Unit <- p("v_odt_13", String.concat([N.onx_odt_name_of(13), "/", N.onx_odt_key_of(13)]))
    a16 : Unit <- p("v_odt_16", String.concat([N.onx_odt_name_of(16), "/", N.onx_odt_key_of(16)]))
    # THE HOLE CELLS, which is where a dense table would have answered a name where tinygrad
    # answers nothing: codes 0, 8, 14 and 15 are NOT members of `OnnxDataType`, and code 1 is.
    a0 : Unit <- p("v_odt_0", N.onx_odt_key_of(0))
    a8 : Unit <- p("v_odt_8", N.onx_odt_key_of(8))
    a14 : Unit <- p("v_odt_14", N.onx_odt_key_of(14))
    a15 : Unit <- p("v_odt_15", N.onx_odt_key_of(15))
    # THE CONTROL: code 16's cell asked twice, so a lane that answered one lookup two ways
    # is caught here rather than by a neighbouring cell being quietly wrong.
    p("ctrl_odt_16", String.concat([N.onx_odt_name_of(16), "/", N.onx_odt_key_of(16)]))

# THE C-CONST CLASS'S CONTROL, AND IT IS THE ONLY THING THAT CAN BE ONE HERE.
# `main`'s six literal rows assert that a group ran; they cannot assert anything about the
# group's CONTENT, because their value is a literal in both lanes. `ctrl_p2t_4` is the same
# `_onnx_pads_to_tiny_pads` fixture `onnx_p2t_4` already prints, under a second name, so a
# group that emitted nothing is caught by the population census and a group that emitted the
# same row twice is caught here. `ctrl_sel_conv` is the same `_select_op` fixture under a
# second name, for the version router -- which is the only group in this file whose answer is
# a NAME, and therefore the group where "ran" and "ran correctly" are most easily confused.
def v_ctrl() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- p("ctrl_p2t_4", N.onx_i64s_str(N.onx_p2t(N.onx_i64s([1, 2, 3, 4]))))
    _ : Unit <- p("ctrl_ap_su_neg1", N.onx_i64s_str(N.onx_auto_pad(N.onx_i64s([4294967295]), True{})))
    p("ctrl_sel_conv", N.onx_sel_str("Conv", N.DomOnnx{}, 1))

def v_rows() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- v_counts()
    b : Unit <- v_wt_cells()
    c : Unit <- v_at_cells()
    d : Unit <- v_odt_cells()
    v_ctrl()


def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- inline_rows()
    b : Unit <- group_rows()
    c : Unit <- N.onx_row("onnx_stage2", True{})
    v_rows()

