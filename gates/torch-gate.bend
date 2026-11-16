# gates/torch-gate.bend -- the gate driver for `tinybendygrad/nn/torch.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/nn/torch.bend as P

import ./../tinybendygrad/helpers.bend as H
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def seq(t: P.Tr, pat: List<&2, P.Call>) -> Bool: P.Tr.has(P.Tr.calls(t), pat)
def ncalls(t: P.Tr) -> U32: U32.from_nat(List.length(&2, P.Call, P.Tr.calls(t)))
def paths(imp: P.Imp) -> List<&2, String>: P.Imp.path(imp)
def arg0(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, 0n), 0)
def at0(xs: List<&2, String>) -> String: Maybe.default(&2, String, List.get(&2, String, xs, 0n), "?")
def at1(xs: List<&2, String>) -> String: Maybe.default(&2, String, List.get(&2, String, xs, 1n), "?")

# `P.MSG().split("\n")` -- the two lines, IN ORDER. This is the row that makes
# `P.MSG()` itself observable: the head/tail rows read the two CONSTANTS and the
# newline-index row reads `String.length(P.MSG_HEAD())`, so a `P.MSG()` that joined
# them the wrong way round moved NOTHING until these two rows existed. MEASURED by
# the mutation table as M6.
def msg_lines() -> List<&2, String>: String.split(P.MSG(), P.LFU())

def OK() -> P.Imp: P.shim.run("tinygrad/nn/torch.py", True{})
def BAD() -> P.Imp: P.shim.run("tinygrad/nn/torch.py", False{})

# --- 1: `.parent.parent`, :3 ------------------------------------------------
def t_root() -> IO(Unit):
  do IO<Unit>:
    srow("torch_root_rel", P.drop2("tinygrad/nn/torch.py"))
    srow("torch_root_abs", P.drop2("/abs/tinygrad/nn/torch.py"))
    srow("torch_root_deep", P.drop2("a/b/c/d.py"))
    srow("torch_root_one", P.drop2("torch.py"))
    srow("torch_root_two", P.drop2("nn/torch.py"))
    srow("torch_root_rooted", P.drop2("/torch.py"))
    urow("torch_depth", P.PARENT_DEPTH())
    row("torch_root_is_prefix", String.starts_with(P.root_of("/abs/tinygrad/nn/torch.py"), P.ROOT_SLASH()))

# --- 2: `.as_posix()`, :3 ----------------------------------------------------
def t_posix() -> IO(Unit):
  do IO<Unit>:
    srow("torch_posix_posix", P.as_posix("a/b/c.py"))
    srow("torch_posix_win", P.as_posix("a\\b\\c.py"))
    srow("torch_posix_mixed", P.as_posix("C:\\x/y\\z.py"))
    row("torch_posix_idem", String.eq(P.as_posix(P.drop2("tinygrad/nn/torch.py")), "tinygrad"))

# --- 3: the three calls, in order, :3-5 --------------------------------------
def t_order() -> IO(Unit):
  do IO<Unit>:
    +ok : P.Imp <- IO.pure(P.Imp, OK())
    +t : P.Tr <- IO.pure(P.Tr, P.Imp.tr(ok))
    # THE MATCHER PINS ITSELF FIRST, because `torch_order` and `torch_order_rev`
    # are worth nothing if it answers True to everything.
    row("torch_has_rejects_reverse", Bool.not(seq(t, [P.Call{P.CALL_IMPORT, 0}, P.Call{P.CALL_PATH_APPEND, 0}])))
    row("torch_has_rejects_absent", Bool.not(seq(t, [P.Call{P.CALL_RAISE, 1}])))
    row("torch_order", seq(t, [P.Call{P.CALL_PATH_APPEND, 0}, P.Call{P.CALL_IMPORT, 0}]))
    row("torch_order_rev", Bool.not(seq(t, [P.Call{P.CALL_IMPORT, 0}, P.Call{P.CALL_PATH_APPEND, 0}])))
    urow("torch_n_ok", ncalls(t))
    urow("torch_append_n", P.Tr.count(P.CALL_PATH_APPEND(), P.Tr.calls(t)))
    urow("torch_import_n", P.Tr.count(P.CALL_IMPORT(), P.Tr.calls(t)))
    urow("torch_raise_n_ok", P.Tr.count(P.CALL_RAISE(), P.Tr.calls(t)))
    row("torch_refused_ok", Bool.not(P.Tr.refused(t)))
    row("torch_dep_y", U32.is_eq(P.PARENT_DEPTH(), 2))

# --- 4: the refusal, :5 ------------------------------------------------------
def t_refuse() -> IO(Unit):
  do IO<Unit>:
    +b : P.Imp <- IO.pure(P.Imp, BAD())
    +tb : P.Tr <- IO.pure(P.Tr, P.Imp.tr(b))
    urow("torch_n_bad", ncalls(tb))
    urow("torch_raise_n_bad", P.Tr.count(P.CALL_RAISE(), P.Tr.calls(tb)))
    row("torch_refused_bad", P.Tr.refused(tb))
    row("torch_raise_last", seq(tb, [P.Call{P.CALL_IMPORT, 0}, P.Call{P.CALL_RAISE, P.FROM_E()}]))
    urow("torch_raise_arg", arg0(P.Tr.args(P.CALL_RAISE(), P.Tr.calls(tb))))
    # the import is STILL in the trace: the raise reports it, and a trace that
    # dropped the failing call would make the refusal unattributable.
    urow("torch_import_survives", P.Tr.count(P.CALL_IMPORT(), P.Tr.calls(tb)))

# --- 5: `sys.path`, :3 -------------------------------------------------------
def t_path() -> IO(Unit):
  do IO<Unit>:
    +ok : P.Imp <- IO.pure(P.Imp, OK())
    urow("torch_path_n", U32.from_nat(List.length(&2, String, paths(ok))))
    srow("torch_path_0", at0(paths(ok)))
    row("torch_path_is_root", String.eq(at0(paths(ok)), "tinygrad"))
    row("torch_path_not_the_parent", Bool.not(String.eq(at0(paths(ok)), "tinygrad/nn")))
    row("torch_path_is_one_level_up", String.eq(at0(paths(ok)), "tinygrad"))

# --- 6: the message, :5 -----------------------------------------------------
def t_msg() -> IO(Unit):
  do IO<Unit>:
    srow("torch_msg_head", P.MSG_HEAD())
    srow("torch_msg_tail", P.MSG_TAIL())
    urow("torch_msg_lines", P.MSG_LINES_GOT())
    urow("torch_msg_lines_expect", P.MSG_LINES())
    urow("torch_msg_nl", U32.from_nat(String.length(P.MSG_HEAD())))
    urow("torch_msg_nl_expect", P.MSG_NEWLINE_AT())
    row("torch_msg_has_nl", String.contains(P.MSG(), P.NL()))
    srow("torch_msg_line0", at0(msg_lines()))
    srow("torch_msg_line1", at1(msg_lines()))
    row("torch_msg_order", String.eq(at0(msg_lines()), P.MSG_HEAD()))
    srow("torch_module", P.MODULE_NAME())

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_root()
    b : Unit <- t_posix()
    +c : Unit <- t_order()
    d : Unit <- t_refuse()
    e : Unit <- t_path()
    f : Unit <- t_msg()
    IO.print("torch-done=1")

# THE MUTATION TABLE. Every number below is `.agents/slop/mutate.py`'s output,
# not an estimate. The harness applies one edit to a scratch copy, runs the
# INTERPRETED lane, and diffs the row NAMES; the useful column is "rows MOVED",
# because a mutation that moves nothing measures what this gate does NOT see.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | `P.drop2` drops ONE component -- `parent`, not `parent.parent` | 7 | :3's TWO `parent` steps. Four of the seven are the root rows and three are the derived ones (`torch_path_0` and its two readers), which is why the derived rows exist: they are the only thing that sees the answer change where the gate calls it. |
# | M2 | `P.tail2` drops ONE separator from the total | 6 | that the tail is two components AND two separators. M1 and M2 are different bugs with the same symptom, which is why both are here. |
# | M3 | `P.as_posix` maps EVERY character to a slash | 6 | :3's `P.as_posix()`. It moves the POSIX rows too, which is the point: a fold that mapped everything would otherwise pass them. |
# | M4 | `P.drop2` answers `.` for a rooted path as well | 1 | the `"/"` corner, and ONE row is the whole of it -- `Path('/torch.py').parent.parent` is `"/"` and not `"."`. A LOCALISED row, and it is the only one that is. |
# | M5 | `P.drop2` takes a PREFIX (`String.drop`) instead of a SUFFIX (`String.take`) | 7 | the same trap `device.bend`'s `strip0` fell into, and the reason `torch_root_is_prefix` exists: the leading `/` is part of `s` and a prefix must be kept. |
# | M6 | `P.MSG()` joins the two halves the wrong way round | 3 | this was a zero for three runs. `torch_msg_head`/`tail` read the two constants, `torch_msg_nl` reads `String.length(P.MSG_HEAD())`, and `torch_msg_has_nl` is True either way -- so nothing printed `P.MSG()` itself and swapping its halves moved nothing. Fixed by adding `torch_msg_line0`/`line1`/`order`, which are `P.MSG().split("\n")` and are derived from the Python. The honest reading: a gate row that reads a constant is not a row about the thing that uses it. |
# | M7 | the path append happens AFTER the import | 4 | :3 before :4. `torch_has_rejects_reverse` moves too, because the mutation makes the reversed pair actually present -- that row was written to pin `P.Tr.has` and turned out to double as an order row, exactly as in `ops_webgpu.bend`. |
# | M8 | the raise is NOT recorded in the trace | 4 | that `raise` is an EVENT and not merely a flag. `torch_raise_arg` and `torch_raise_n_bad` move because the entry is what they read. |
# | M9 | the raise does NOT set `refused` | 1 | `torch_refused_bad` only. The count and the order rows are unaffected, because a raise with no entry still leaves the trace at two calls -- which is why the flag and the entry are SEPARATE rows. |
# | M11 | a comment-only edit | 0 -- THE CONTROL | a table with no row that CANNOT move is a table of coincidences. |
#
# what this gate still does not see, and it is a short list:
#
#   1. PATHLIB'S NORMALISATION. `'a//b/c.py'`, `'x/y/'` and `'a/./b/c.py'` are
#     three measured cases where a string operation and `Path` disagree, and the
#     port does not reproduce any of them -- they are WALL 1 and the header says
#     so with the counterexamples. Nothing here can see a regression in the WALL.
#   2. THE IMPORT ITSELF (WALL 2). `ok` is a PARAMETER, so a gate can only ever
#     see that the port asks the question. Whether `extra.torch_backend.backend`
#     is importable, and what it raises, is the seam's.
#   3. `sys.path`'s EFFECT on anything. `torch_path_0` is the string the seam
#     would receive; nothing checks that receiving it changes a lookup, because
#     Bend has no import machinery to change.
#   4. THE PREFIX-TEXT WALL is not the same as the SEMANTIC one: the port reads
#     `__file__` as a normalised POSIX path, so a Windows-style `__file__` is
#     handled by `P.as_posix` alone and a drive letter (`C:\...`) is not.
