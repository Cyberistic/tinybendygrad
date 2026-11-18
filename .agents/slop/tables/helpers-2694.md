<!-- FROM: tinybendygrad/helpers.bend:2694 -->
# BLOCK:
# THE TWENTY MEASURED ROWS, THE PLANT LIST AND THE LIST-LEVEL ROWS.
# (The prose of this block was cut in the source; the DATA is here.)
#
# `Target.parse` -- tinygrad/helpers.py:206-214. THE DEV STRING PARSER.
#
# `Target` is upstream's record (helpers.py:198-203) and this is the one
# function that FILLS it from a string, so it is the only thing in the port that
# turns the `DEV=` environment variable into anything. Upstream, verbatim:
#
#     @staticmethod
#     def parse(s:str) -> Target:
#
# SIX FACTS, and a port that misses any one of them is wrong in a way a
# "looks about right" reading will not catch.
#
# 1. the `+` cut is not the middle of the string. `s.split('+')` gives the
#    interface half first and the device half second, so `DEV=USB+AMD` is the
#    interface "USB" and the device "AMD" -- the OPPOSITE of the order the two
#    are written in. A string with NO '+' is all device and the interface is
#    empty; a string with a '+' is the interface half and the device half.
# 2. the interface half may carry its own ':'. `split[0].rsplit(":", 1)` cuts
#    that half at its LAST ':' -- before the cut is the interface, after it is
#    the indices -- and `rsplit` with a maxsplit of ONE means "A:B:C" is the
#    interface "A:B" and the indices "C", NOT the interface "A" and the
#    indices "B:C".
# 3. the device half is split on ':' and its first two fields are uppercased.
#    The arch is NOT: `DEV=AMD:LLVM:gfx1100` keeps "gfx1100" as it is written,
#    and `render.of` (runtime/ops_python.bend) matches the arch with
#    `String.starts_with(arch, "gfx")`, so an uppercased arch would stop being
#    an AMD arch at all. The interface and the indices are not uppercased either.
# 4. two refusals, and they are not the same refusal. a third '+' is "too
#    many '+'"; a fourth ':' IN THE DEVICE HALF is "too many ':'". Upstream
#    raises `RuntimeError`; the port's `None` IS that RuntimeError
#    (helpers.bend:3002 symbol=Target.parse), so `Target.parse` answers a `Maybe`. The port cannot
#    carry upstream's MESSAGE -- `None` is a value with no room for one -- but
#    the BOUNDARY, which strings are refused and which are not, is the fact
#    that matters and it is carried exactly.
# 5. the colons of the interface half are not the device half's budget. The
#    ':' count that refuses is the count of the DEVICE half ALONE, so
#    "A:B:C+D" parses (the device half "D" has one field) and "A+B:C:D" parses
#    too (the device half "B:C:D" has three, which is the most there is).
#    Upstream's own error message is narrower still: it rebinds `s` to
#    `split[1]` BEFORE the ':' split, so the "too many ':'" message names the
#    DEVICE half and not the whole string.
# 6. the empty string is not a malformed string. `Target.parse("")` is
#    `Target("", "", "", "", "")`: the device half is "" and the interface is
#    "". A port that treats "" as malformed refuses a string upstream accepts.
#
# the port's own name for the fields. Upstream's record is
# `Target{device, renderer, arch, interface, indices}` and the port's is
# `Target{device, renderer, arch, iface, indices}` -- ONE name differs and it
# is the port's SHORT one: `interface` is `iface` here and NOTHING ELSE. Every
# field upstream's `parse` fills is a field the port has, so the port's
# `Target` is NOT missing one; `iface` IS upstream's `interface`, filled from
# the same place in the same order, and `render.of` (runtime/ops_python.bend)
# reads the arch and the device only, so no field of the record is unread.
#
# MEASURED, 2026-10-22, AGAINST CPython'S OWN `Target.parse` AND `ProgramInfo`.
# The oracle is the vendored `tinygrad/helpers.py` and `tinygrad/uop/ops.py` at the pin,
# CALLED, never re-implemented, and the port's answer is read out of the port by the
# round trip's two lanes (`gates/target-roundtrip.bend` and `gates/target-oracle.py`).
# THE DIFF IS EMPTY on all TWENTY rows: the five fields, in upstream's order, come back
# out of the `ProgramInfo` EXACTLY as they went in, and `eq_target` says so too.
#
#   ""                    => ||||
#   CPU                   => CPU||||
#   CPU:CLANG             => CPU|CLANG|||
#   AMD:LLVM:gfx1100      => AMD|LLVM|gfx1100||
#   AMD:LLVM:GFX1100      => AMD|LLVM|GFX1100||
#   cpu:clang             => CPU|CLANG|||
#   USB+AMD               => AMD|||USB|
#   USB:1+AMD             => AMD|||USB|1
#   AMD+CPU:CLANG         => CPU|CLANG||AMD|
#   A:B:C+AMD             => AMD|||A:B|C
#   usb:1+amd:llvm:gfx1100 => AMD|LLVM|gfx1100|usb|1
#   A:B:C:D               => REFUSED      (upstream: too many ':' in target string: 'A:B:C:D')
#   A+B+C                 => REFUSED      (upstream: too many '+' in target string: 'A+B+C')
#   A:B:C+D               => D|||A:B|C
#   A+B:C:D               => B|C|D|A|
#   A+B:C:D:E             => REFUSED      (upstream: too many ':' in target string: 'B:C:D:E')
#   ":"                   => ||||
#   "A:"                  => A||||
#   "::"                  => ||||
#   "A::B"                => A||B||
#
# The five fields are printed as `device|renderer|arch|interface|indices`, in
# upstream's order, with upstream's `interface` spelled `iface`. THE REFUSALS
# agree on the boundary and not on the message: upstream raises
# `RuntimeError("too many ':' in target string: 'B:C:D:E'")` and the port
# answers `None`, which IS that RuntimeError in this tree's vocabulary
# (helpers.bend:2329) and cannot carry its text, because `None` is a value
# with no room for one.
#
# the plant, and WHERE each planted case lands. The ways this could be wrong,
# and the row that catches each:
#
#   * A COMPONENT IN THE WRONG ORDER -- the `+` cut puts the interface half
#     FIRST. Caught by "USB+AMD" (device AMD, interface USB) and by
#     "AMD+CPU:CLANG" (device CPU, renderer CLANG, interface AMD).
#   * A DEFAULT OVERRIDING A GIVEN VALUE -- the unset fields must be "" and
#     the given ones must survive. Caught by "CPU:CLANG" (renderer CLANG,
#     arch ""), by "AMD:LLVM:gfx1100" (the arch is NOT uppercased) and by
#     "A::B" (an EMPTY middle field is not shifted: arch B, renderer "").
#   * A MALFORMED STRING SILENTLY ACCEPTED -- caught by "A+B+C" (too many
#     '+') and by "A:B:C:D" and "A+B:C:D:E" (too many ':'), and NOT by
#     "A:B:C+D" and "A+B:C:D", which upstream ACCEPTS and so must the port.
#   * A DEVICE NAME THAT IS A PREFIX OF ANOTHER -- `Target.parse` matches no
#     names at all, so the plant is at the LIST level, and it is planted there:
#     ";CPU" parses to a target with an EMPTY device and one with "CPU", and
#     the EMPTY one wins for EVERY device, which is upstream's rule
#     (`not t.device or t.device == dev`) and not a prefix match.
#   * THE EMPTY STRING IS NOT MALFORMED -- caught by the "" row.
#
# THE LIST LEVEL, the same comparison, five more rows plus five selections
# plus two `replacedefault` rows, all identical:
#
#   CPU:CLANG;CPU:LLVM => LIST [CPU|CLANG|||] [CPU|LLVM|||]
#   ;CPU               => LIST [||||] [CPU||||]
#   A;B+C              => LIST [A||||] [C|||B|]
#   CPU:CLANG;CPU:LLVM + CPU => CPU|CLANG|||     (the FIRST wins)
#   CPU:CLANG;CPU:LLVM + GPU => GPU||||           (no match: a blank target)
#   CPU:CLANG;AMD:LLVM + AMD => AMD|LLVM|||       (the second, matched)
#   ;CPU + CPU => CPU||||                         (the EMPTY device wins)
#   ;CPU + GPU => GPU||||
#
# THE PRECEDENCE IS UPSTREAM'S `_DEV.target(dev)` (helpers.py:216-218) AND NOT
# `Target.parse`: the parse is per string, and the choice among the parsed
# targets is the LIST's. Upstream's rule is `next((t for t in self._value if
# not t.device or t.device == dev), Target(device=dev))` -- the FIRST target
# whose device is empty or is `dev`, and the answer's device is `dev` whatever
# the winner said -- and the port's `Target.select` is that, and the oracle
# called upstream's own `DEV.target(dev)` on upstream's own parsed list, so
# neither side is a re-implementation.
#
# WHAT CALLS IT IN THE PORT: `ProgramInfo.target` (`uop/ops.bend`), and that is
# the WHOLE POINT of the record being here. The port has no DEV plumbing --
# `helpers.bend` holds 4 of the 61 ContextVars and DEV is not one of them --
# so there is no `DEV` string for anything to parse; but `ProgramInfo` carries
# a `Target` and the two were DIFFERENT TYPES, so a parsed target could not go
# into one. `device.bend`'s `canon` (device.py:26's `_canonicalize`)
# is NOT this parser and must not become it: it splits on the FIRST ':' only,
# uppercases the head, and strips a trailing ":0", so `canon("CPU:0")` is
# "CPU" while `Target.parse("CPU:0")` is the device "CPU" and the RENDERER
# "0". One keeps a device name a STRING and the other splits a device name
# into FIELDS.
# The three characters the parser cuts on. `'+'` is 43, `':'` is 58, `';'` is 59.
