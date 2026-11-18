import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/helpers.bend"

# **THE **SIX **FACTS **STAY** (⇒⇒† AND **THEY **ARE **THE **DIFFERENCES**), **⇒⇒† AND **THE
# **TWENTY **MEASURED **ROWS **AND **THE **PLANT **LIST **GO **TO **THE **TABLE **FILE** (⇒⇒† AND
# **THEY **ARE **DATA**).
EDITS = [
  (2694, 2836, """# `Target.parse` -- tinygrad/helpers.py:206-214. THE DEV STRING PARSER.
#
# `Target` is upstream's record (helpers.py:198-203) and this is the one function that FILLS it
# from a string, so it is the only thing in the port that turns the `DEV=` environment variable
# into anything. Upstream, verbatim:
#
#     @staticmethod
#     def parse(s:str) -> Target:
#
# SIX FACTS, and a port that misses any one of them is wrong in a way a "looks about right"
# reading will not catch.
#
# 1. the `+` cut is not the middle of the string. `s.split('+')` gives the interface half first
#    and the device half second, so `DEV=USB+AMD` is the interface "USB" and the device "AMD" --
#    the OPPOSITE of the order the two are written in. A string with NO '+' is all device and
#    the interface is empty; a string with a '+' is the interface half and the device half.
# 2. the interface half may carry its own ':'. `split[0].rsplit(":", 1)` cuts that half at its
#    LAST ':' -- before the cut is the interface, after it is the indices -- and `rsplit` with a
#    maxsplit of ONE means "A:B:C" is the interface "A:B" and the indices "C", NOT the interface
#    "A" and the indices "B:C".
# 3. the device half is split on ':' and its first two fields are uppercased. The arch is NOT:
#    `DEV=AMD:LLVM:gfx1100` keeps "gfx1100" as it is written, and `render.of`
#    (runtime/ops_python.bend) matches the arch with `String.starts_with(arch, "gfx")`, so an
#    uppercased arch would stop being an AMD arch at all. The interface and the indices are not
#    uppercased either.
# 4. two refusals, and they are not the same refusal. a third '+' is "too many '+'"; a fourth
#    ':' IN THE DEVICE HALF is "too many ':'". Upstream raises `RuntimeError`; the port's `None`
#    IS that RuntimeError (helpers.bend:3002 symbol=Target.parse), so `Target.parse` answers a
#    `Maybe`. The port cannot carry upstream's MESSAGE -- `None` is a value with no room for one
#    -- but the BOUNDARY, which strings are refused and which are not, is the fact that matters
#    and it is carried exactly.
# 5. the colons of the interface half are not the device half's budget. The ':' count that
#    refuses is the count of the DEVICE half ALONE, so "A:B:C+D" parses (the device half "D" has
#    one field) and "A+B:C:D" parses too (the device half "B:C:D" has three, which is the most
#    there is). Upstream's own error message is narrower still: it rebinds `s` to `split[1]`
#    BEFORE the ':' split, so the "too many ':'" message names the DEVICE half and not the whole
#    string.
# 6. the empty string is not a malformed string. `Target.parse("")` is `Target("", "", "", "",
#    "")`: the device half is "" and the interface is "". A port that treats "" as malformed
#    refuses a string upstream accepts.
#
# the port's own name for the fields. Upstream's record is `Target{device, renderer, arch,
# interface, indices}` and the port's is `Target{device, renderer, arch, iface, indices}` -- ONE
# name differs and it is the port's SHORT one: `interface` is `iface` here and NOTHING ELSE.
# Every field upstream's `parse` fills is a field the port has, so the port's `Target` is NOT
# missing one; `iface` IS upstream's `interface`, filled from the same place in the same order,
# and `render.of` (runtime/ops_python.bend) reads the arch and the device only, so no field of
# the record is unread.
#
# MEASURED, 2026-10-22, AGAINST CPython'S OWN `Target.parse` AND `ProgramInfo`. The oracle is
# the vendored `tinygrad/helpers.py` and `tinygrad/uop/ops.py` at the pin, CALLED, never
# re-implemented, and the port's answer is read out of the port by the round trip's two lanes
# (`gates/target-roundtrip.bend` and `gates/target-oracle.py`). THE DIFF IS EMPTY on all TWENTY
# rows: the five fields, in upstream's order, come back out of the `ProgramInfo` EXACTLY as they
# went in, and `eq_target` says so too. THE TWENTY ROWS, THE PLANT LIST AND THE LIST-LEVEL
# ROWS ARE IN `.agents/slop/tables/helpers-2694.md`.
#
# The five fields are printed as `device|renderer|arch|interface|indices`, in upstream's order,
# with upstream's `interface` spelled `iface`. THE REFUSALS agree on the boundary and not on the
# message: upstream raises `RuntimeError("too many ':' in target string: 'B:C:D:E'")` and the port
# answers `None`, which IS that RuntimeError in this tree's vocabulary (helpers.bend:2329) and
# cannot carry its text, because `None` is a value with no room for one.
#
# THE PRECEDENCE IS UPSTREAM'S `_DEV.target(dev)` (helpers.py:216-218) AND NOT `Target.parse`: the
# parse is per string, and the choice among the parsed targets is the LIST's. Upstream's rule is
# `next((t for t in self._value if not t.device or t.device == dev), Target(device=dev))` -- the
# FIRST target whose device is empty or is `dev`, and the answer's device is `dev` whatever the
# winner said -- and the port's `Target.select` is that, and the oracle called upstream's own
# `DEV.target(dev)` on upstream's own parsed list, so neither side is a re-implementation.
#
# WHAT CALLS IT IN THE PORT: `ProgramInfo.target` (`uop/ops.bend`), and that is the WHOLE POINT
# of the record being here. The port has no DEV plumbing -- `helpers.bend` holds 4 of the 61
# ContextVars and DEV is not one of them -- so there is no `DEV` string for anything to parse;
# but `ProgramInfo` carries a `Target` and the two were DIFFERENT TYPES, so a parsed target
# could not go into one. `device.bend`'s `canon` (device.py:26's `_canonicalize`) is NOT this
# parser and must not become it: it splits on the FIRST ':' only, uppercases the head, and
# strips a trailing ":0", so `canon("CPU:0")` is "CPU" while `Target.parse("CPU:0")` is the
# device "CPU" and the RENDERER "0". One keeps a device name a STRING and the other splits a
# device name into FIELDS."""),
]

apply(F, EDITS)
