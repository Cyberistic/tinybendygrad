#!/usr/bin/env python3
"""CPython ORACLE for tinybendygrad/renderer/__init__.bend -- gates tinygrad/renderer/__init__.py.

    .venv/bin/python gates/renderer_init-oracle.py > /tmp/renderer_init.rows

WHY THIS FILE EXISTS AT ALL.  `tinybendygrad/renderer/__init__.bend` prints NINETEEN
`py=` rows, and until this file landed it had NO ORACLE IN GIT: its header said the
`py=` text "is diffed against CPython on this `tinygrad/` tree with `.venv/bin/python
-c "..."`", and **A COMMAND IS NOT AN ORACLE** -- it has no name, no pin, no
provenance, and no way to be run by a gate that did not write it by hand.  A lane
whose witness is a command is a lane whose teeth are a rumour, and the census's own
verdict for a lane that cannot fail is DEAD, not PASS.

THE SUBJECT.  `tinygrad/renderer/__init__.py`, and only three things in it:
`Renderer.supported_dtypes` (:85), `with_storage` (:11) and `Estimates` (:16).  The
port's other six rows -- `emu_long`, `is_named`, `is_alu`, `is_mem` -- are the port's
OWN predicates over upstream's own sets, and each one is answered here by CALLING
upstream's set, never by re-deriving the membership.

THE ROW NAMES ARE THE PORT'S, READ OUT OF THE PORT'S OWN SOURCE.  A row name is a
LABEL and not an answer, so a hand list of them would be a second copy of the port's
shape -- and `gates/ops_dsp_render-oracle.py` already sets the precedent ("row_names()
reads the row order out of the PORT's own source").  So the names come from the
port's source, IN THE PORT'S ORDER, and the oracle REFUSES if the port prints a row
this file does not answer or names one this file does not have: a renamed row is a
REFUSED oracle, not a silently shorter one.

WHAT IS ANSWERED, AND BY WHAT CALL

  sd empty      `Renderer.supported_dtypes` with `EMULATED_DTYPES` at its DEFAULT
  sd emu long   the SAME method with `EMULATED_DTYPES` set to `"long"`
  dtypes.all    `dtypes.all` itself
  emu_long      `dtypes.long in EMULATED_DTYPES.tolist(dtypes)` -- upstream's OWN
                predicate, at the default and at `"long"`
  is_named      `DType.name` against the name the row names
  is_alu        `Ops.X in GroupOp.ALU` -- upstream's own set, which has 28 members
  is_mem        `Ops.X in {Ops.LOAD, Ops.STORE}` -- upstream's own spelling of "a
                memory op", at `tinygrad/renderer/__init__.py:38`
  est           `Estimates.__add__` and `Estimates.simplify`, printed by CPython's
                own dataclass `repr`
  ws            `with_storage`, and the answer's own `arg.dtype.name` / `arg` /
                `src[0].arg.dtype.name`

`supported_dtypes` RETURNS A SET, and a set has no order, so the joined string is
taken in `dtypes.all`'s OWN order -- which is `dtype.py`'s declaration order and the
order the port uses.  That is what makes a DROPPED dtype and a MISORDERED dtype two
different diffs instead of one, and it is why this oracle joins a JOIN rather than
sorting it.

THE PIN, AND WHY THERE IS NONE.  This oracle reads the LIVE `tinygrad/`, and it was
MEASURED against the live tree: every one of the eighteen rows agrees with the port's
own answer, byte for byte.  An upstream that moves this lane's subject moves these
answers and the gate goes RED, which is the point -- and a pin would only hide it.
(`gates/renderkit.py`'s PIN exists because `tinygrad/renderer/llvmir.py` moved by 409
lines after the port was written against it; that did not happen here, and a pin
nobody needs is a second number that can disagree with the first.)

THE ROW SHAPE IS THE PORT'S, AND THE PORT'S IS NOT UNIFORM.  Nine of the port's
rows print `py=[value]` and nine print `py=value` -- a bare `False` beside a
bracketed `[False]` -- because those nine were hand-written before the derived-row
shape was adopted.  So this oracle prints the CANONICAL `name = [value]   py=[value]`
for all eighteen and the COMPARISON IS BY VALUE, NOT BY THE WHOLE ROW'S BYTES: a
reader that diffed the two lanes byte for byte would report a difference in the
SHAPE on nine rows and learn nothing about the ANSWER.  `gates/lanecmp.py` is that
reader, and it is the reader that says which half of a row it compared.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tinygrad.dtype import dtypes
from tinygrad.helpers import EMULATED_DTYPES
from tinygrad.renderer import Estimates, Renderer, with_storage
from tinygrad.uop.ops import GroupOp, Ops, ParamArg, UOp

SUBJECT = "tinybendygrad/renderer/__init__.bend"
PORT = ROOT / SUBJECT

# THE PORT'S OWN ROW NAMES, IN THE PORT'S OWN ORDER.  Two shapes, because the port
# has two: nine rows go through a `*_row` BUILDER whose first argument is the name,
# and nine are printed inline with the name inside the printed string.
BUILDER_ROW = re.compile(r'^\s*_ : Unit <- (?:sd_row|all_row|est_row|ws_row|ws_src_row)\("([^"]*)"')
PRINTED_ROW = re.compile(r'^\s*_ : Unit <- IO\.print\("([^"]*) = \[')


def port_rows() -> list[str]:
    """the row names the port prints, in the order it prints them."""
    names = []
    for line in PORT.read_text().splitlines():
        m = BUILDER_ROW.match(line) or PRINTED_ROW.match(line)
        if m:
            names.append(m.group(1))
    return names


def _supported(emulated: str) -> str:
    """`Renderer.supported_dtypes`, called UNBOUND -- upstream's base method reads no
    `self`, and instantiating a `Renderer` would need a `Compiler` and a device."""
    old = EMULATED_DTYPES.value
    EMULATED_DTYPES.value = emulated
    try:
        supported = Renderer.supported_dtypes(None)
    finally:
        EMULATED_DTYPES.value = old
    return ",".join(d.name for d in dtypes.all if d in supported)


def _emu_long(emulated: str) -> str:
    """`dtypes.long in EMULATED_DTYPES.tolist(dtypes)` -- upstream's own predicate."""
    old = EMULATED_DTYPES.value
    EMULATED_DTYPES.value = emulated
    try:
        return str(dtypes.long in EMULATED_DTYPES.tolist(dtypes))
    finally:
        EMULATED_DTYPES.value = old


def _param() -> UOp:
    return UOp(Ops.PARAM, src=(), arg=ParamArg(0, dtypes.int32, 4, device="CPU"))


def _alloc() -> UOp:
    return UOp(Ops.ALLOC, src=(UOp.range(4, 0),), arg=ParamArg(0, dtypes.int32, 4, device="CPU"))


def _index() -> UOp:
    return UOp(Ops.INDEX, src=(_param(),))


def _ws_buffer() -> str:
    return with_storage(_param(), dtypes.float32).arg.dtype.name


def _ws_index() -> str:
    arg = with_storage(_index(), dtypes.float32).arg
    return "None" if arg is None else arg.dtype.name


def _ws_idx_src0() -> str:
    return with_storage(_index(), dtypes.float32).src[0].arg.dtype.name


def _ws_alloc() -> str:
    return with_storage(_alloc(), dtypes.float32).arg.dtype.name


# THE ANSWERS, KEYED BY THE PORT'S ROW NAME.  The KEY is a label; the VALUE is a CALL
# into upstream, and no answer is written down here.  A row the port renames is a row
# this table cannot answer, and the refusal below is what turns that into a verdict
# instead of a shorter lane.
#
# THE KEYS ARE STRIPPED OF THE PORT'S ALIGNMENT PADDING.  Nine of these names are
# padded so the answers line up under a 200-character dtype list, and the padding is
# the PORT's cosmetics, not part of the question -- so a re-padded row is still
# answered, and a row whose NAME (not its padding) moved is a refusal.  Two port rows
# that strip to the same key are a refusal too, because then the key would not name a
# row any more.
ANSWERS = {
    "sd empty": lambda: _supported(""),
    "sd emu long": lambda: _supported("long"),
    "dtypes.all": lambda: ",".join(d.name for d in dtypes.all),
    "emu_long []": lambda: _emu_long(""),
    "emu_long [long]": lambda: _emu_long("long"),
    "is_named double": lambda: str(dtypes.double.name == "f64"),
    "is_named long!=": lambda: str(dtypes.long.name == "f64"),
    "is_alu ADD": lambda: str(Ops.ADD in GroupOp.ALU),
    "is_alu SINK": lambda: str(Ops.SINK in GroupOp.ALU),
    "is_mem LOAD": lambda: str(Ops.LOAD in (Ops.LOAD, Ops.STORE)),
    "is_mem STORE": lambda: str(Ops.STORE in (Ops.LOAD, Ops.STORE)),
    "is_mem ADD": lambda: str(Ops.ADD in (Ops.LOAD, Ops.STORE)),
    "est add": lambda: repr(Estimates(1, 2, 3) + Estimates(4, 5, 6)),
    "est simplfy": lambda: repr(Estimates(3, 4, 5).simplify()),
    "ws buffer": _ws_buffer,
    "ws index": _ws_index,
    "ws idx.src0": _ws_idx_src0,
    "ws alloc": _ws_alloc,
}


def refuse(why: str) -> None:
    print(f"== REFUSED, NOT A VERDICT: {SUBJECT}: {why}", file=sys.stderr)
    raise SystemExit(3)


def main() -> int:
    names = port_rows()
    if not names:
        refuse("the port's source carries no row this oracle can name")
    keys = [n.rstrip() for n in names]
    if len(set(keys)) != len(keys):
        refuse(f"the port's row names are not unique once the alignment padding is "
               f"stripped, so a name would not identify a row: {names}")
    unanswered = [n for n, k in zip(names, keys) if k not in ANSWERS]
    if unanswered:
        refuse(f"the port prints {len(unanswered)} row(s) this oracle does not answer: "
               f"{unanswered}")
    extra = [k for k in ANSWERS if k not in keys]
    if extra:
        refuse(f"this oracle answers {len(extra)} row(s) the port does not print: {extra}")
    for n, k in zip(names, keys):
        value = ANSWERS[k]()
        print(f"{n} = [{value}]   py=[{value}]")
    print(f"# ORACLE ROW COUNT = {len(names)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
