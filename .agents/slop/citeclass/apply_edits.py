#!/usr/bin/env python3
"""apply_edits.py -- RE-POINT THE STALE UPSTREAM CITATIONS IN `tinybendygrad/uop/ops.bend`.

EVERY REPLACEMENT IS COMMENT-ONLY AND LINE-COUNT-PRESERVING, and the script REFUSES to
write unless both hold. THE LINE COUNT IS NOT AESTHETIC: **156** citations in OTHER
files name a line of `ops.bend` (`tinybendygrad/schedule/__init__.bend:1612` says
`uop/ops.bend:4044`), so inserting or deleting one line of THIS file breaks 156
citations that are measured by nobody. THE FILE'S LINE NUMBERS ARE AN INTERFACE.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TARGET = ROOT / "tinybendygrad" / "uop" / "ops.bend"

EDITS: list[tuple[str, str, str]] = [
  # ---- 805: `sint = int|UOp` is at 1923, not 1925 (1925 is blank). ----
  ("805 sint", """# `Sint` is ops.py:1925's `sint = int|UOp`, spelled out. It is the element type""",
   """# `Sint` is ops.py:1923 symbol=sint -- `sint = int|UOp`, spelled out. It is the element type"""),

  # ---- 2341: `UOpMetaClass.__call__` is at 193, not 196-212. ----
  ("2341 UOpMetaClass.__call__", """# UOpMetaClass.__call__ -- ops.py:196-212. THE CONSTRUCTOR.""",
   """# UOpMetaClass.__call__ -- ops.py:193 symbol=UOpMetaClass.__call__. THE CONSTRUCTOR."""),

  # ---- 4245-4274: the four rule tables, the PMEntry construction, and the
  #      reject sets. `remove_all_tags` IS NOT IN upstream's `ops.py` AT ALL. ----
  ("4245 rule tables", """# THE OPS.PY RULE TABLES -- ops.py:1896, 1897, 1904, 1907. These four are the
# WHOLE of `PatternMatcher` surface in ops.py, and until now `pm_dispatch_m`
# could reach none of them: it answered three placeholder bodies (SINK, NOOP,
# CAST) and codegen's two. `engine/realize.bend:1072-1080` records the wall this
# creates -- "a `PMEntrys` built in THIS file can only ever reach those three
# bodies" -- and the cost is that eleven files in this tree each grew their own
# scan. What follows puts the four in the table that already exists.
#
# `ops.py:1602-1606` is where a `PMEntry` comes from, and it is three lines:
#
#     entry: list = [p, None, p.early_reject]
#     entry[1] = upat_deferred_compile(p, fxn, entry) if compiled else upat_interpret(p, fxn)
#     for uop in p.op: self.pdict.setdefault(uop, []).append(entry)
#
# `p.early_reject` is field three and `entry[1]` -- the compiled function -- is
# the TAG. `for uop in p.op` is the fan-out that makes `PMEntry.ops` a CLAIMED
# SET, and it is `ops.py:1614`'s `self.pdict.get(uop.op, [])`, which `pm_claimed`
# already reads.
#
# ALL FOUR REJECT SETS ARE EMPTY, and that is ops.py's arithmetic rather than a
# shortcut. `ops.py:1480-1483` is
#
#     upat_match = [src] if isinstance(src, UPat) else ([] if src is None else self.src[0])
#     self.early_reject = {pp.op[0] for pp in upat_match if pp.op is not None and len(pp.op) == 1}
#
# and all four patterns are built with `src=` OMITTED, so `src is None`, so
# `upat_match == []`, so `early_reject == set()`. `ops.py:1617`'s
# `if not early_reject.issubset(ler): continue` therefore never skips any of
# them, and `PMEntry.rej` is `Nil{}` four times. A non-empty reject set here
# would be an invention.""",
   """# THE OPS.PY RULE TABLES -- ops.py:1898 symbol=_substitute,
# ops.py:1899 symbol=_pm_resolve_params, ops.py:1908 symbol=pm_drop_after, and
# tinygrad/uop/spec.py:207 symbol=spec_program. The FOURTH is NOT IN upstream's
# `ops.py` AT ALL -- upstream has NO `remove_all_tags`, which is THIS port's own
# table -- and the surviving construct is `spec.py`'s `UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks)`.
# These four are the WHOLE of `PatternMatcher` surface in ops.py, and until now
# `pm_dispatch_m` could reach none of them: it answered three placeholder bodies
# (SINK, NOOP, CAST) and codegen's two. `engine/realize.bend:1072-1080` records the wall this
# creates -- "a `PMEntrys` built in THIS file can only ever reach those three
# bodies" -- and the cost is that eleven files in this tree each grew their own
# scan. What follows puts the four in the table that already exists.
#
# `ops.py:1591-1593` symbol=PatternMatcher.__init__ is where a `PMEntry` comes from, and it is three lines:
#
#     entry: list = [p, None, p.early_reject]
#     entry[1] = upat_deferred_compile(p, fxn, entry) if compiled else upat_interpret(p, fxn)
#     for uop in p.op: self.pdict.setdefault(uop, []).append(entry)
#
# `p.early_reject` is field three and `entry[1]` -- the compiled function -- is
# the TAG. `for uop in p.op` is the fan-out that makes `PMEntry.ops` a CLAIMED
# SET, and it is `ops.py:1601` symbol=PatternMatcher.rewrite's
# `self.pdict.get(uop.op, [])`, which `pm_claimed` already reads.
#
# ALL FOUR REJECT SETS ARE EMPTY, and that is ops.py's arithmetic rather than a
# shortcut. `ops.py:1469-1470` symbol=UPat.__init__ computes `upat_match` and
# `self.early_reject`, and all four patterns are built with `src=` OMITTED, so
# `src is None`, so `upat_match == []`, so `early_reject == set()`.
# `ops.py:1604` symbol=PatternMatcher.rewrite's `if not early_reject.issubset(ler): continue`
# therefore never skips any of them, and `PMEntry.rej` is `Nil{}` four times. A
# non-empty reject set here would be an invention."""),

  # ---- 4277-4281: `UPat(tuple(Ops))` is at 1898; `UPat(GroupOp.All` is NOT in
  #      `ops.py` -- it is `spec.py`'s `UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks)`. ----
  ("4277 tuple(Ops)", """# `tuple(Ops)` -- the claim of ops.py:1896's `UPat(tuple(Ops), name="x")` and of
# ops.py:1904's `UPat(GroupOp.All, name="x")`. `GroupOp.All` IS `set(Ops)`
# (tinygrad/uop/__init__.py:135), measured by CPython: `len(tuple(Ops))` is 77
# and `GroupOp.All == set(Ops)` is `True`. So one list serves both rules, and it
# is the same 77 for both.""",
   """# `tuple(Ops)` -- the claim of ops.py:1898 symbol=_substitute's
# `UPat(tuple(Ops), name="x")` and of tinygrad/uop/spec.py:207 symbol=spec_program's
# `UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks)`. `GroupOp.All` IS `set(Ops)`
# (tinygrad/uop/__init__.py:135 symbol=GroupOp.All), measured by CPython:
# `len(tuple(Ops))` is 77 and `GroupOp.All == set(Ops)` is `True`. One list serves both rules -- 77 for both."""),

  # ---- 4296-4302: the guard is the PORT's own; `remove_all_tags` is NOT upstream. ----
  ("4296 tag_is_none", """# `x.tag is not None` -- the guard of ops.py:1904's
# `lambda x: x.replace(tag=None) if x.tag is not None else None`. `Tag`'s bottom
# is `TNone{}` (this file's `type Tag is Data`, whose five constructors are
# TNone/TBool/TStr/TInt/TTuple), so Python's `None` IS `TNone{}` and the guard is
# the other four. The same shape as `eq_tag.TNone` above, which is why it is a
# separate def and not a fold: a fold over the constructors is the mutual
# recursion the `Tag` header says it would force on `eq_tag`.""",
   """# `x.tag is not None` -- the guard of the port's OWN `remove_all_tags` lambda,
# which is NOT IN upstream's `ops.py` at this pin (upstream has NO `remove_all_tags`); the surviving upstream construct is tinygrad/uop/spec.py:207 symbol=spec_program's `UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks)`. `Tag`'s bottom
# is `TNone{}` (this file's `type Tag is Data`, whose five constructors are
# TNone/TBool/TStr/TInt/TTuple), so Python's `None` IS `TNone{}` and the guard is
# the other four. The same shape as `eq_tag.TNone` above, which is why it is a
# separate def and not a fold: a fold over the constructors is the mutual
# recursion the `Tag` header says it would force on `eq_tag`."""),

  # ---- 4308-4309: `pm_drop_after` is at 1908, not 1907. ----
  ("4308 pm_drop_after", """# TAG 40 -- ops.py:1907. `pm_drop_after`:""",
   """# TAG 40 -- ops.py:1908 symbol=pm_drop_after. `pm_drop_after`:"""),

  # ---- 4319-4320: `_pm_resolve_params` is at 1899, not 1897. ----
  ("4319 _pm_resolve_params", """# TAG 42 -- ops.py:1897. `_pm_resolve_params`:""",
   """# TAG 42 -- ops.py:1899 symbol=_pm_resolve_params. `_pm_resolve_params`:"""),

  # ---- 4394-4397: `ctx=None` is `rewrite`'s signature at 1600 and 1698, not 1888. ----
  ("4395 ctx=None", """# ONE TABLE CANNOT HOLD ALL FOUR of ops.py's rules, and the blocker is not
# linearity. `ops.py:1888` types the pass's `ctx` as `ctx=None` and each lambda
# reads whatever shape it likes off it, so Python has no reason for the four to
# agree. A Bend parameter has a type, so:""",
   """# ONE TABLE CANNOT HOLD ALL FOUR of ops.py's rules, and the blocker is not
# linearity. `ops.py:1600` symbol=PatternMatcher.rewrite and `ops.py:1698` symbol=TrackedPatternMatcher.rewrite type the pass's `ctx` as `ctx=None`, and each lambda
# reads whatever shape it likes off it, so Python has no reason for the four to
# agree. A Bend parameter has a type, so:"""),

  # ---- 4405: `replace` is at 245, not 253-257. ----
  ("4405 replace mints", """# already paid for: `remove_all_tags` MINTS. `ops.py:253-257`'s `replace` returns""",
   """# already paid for: `remove_all_tags` MINTS. `ops.py:245-249` symbol=UOp.replace returns"""),

  # ---- 4418-4426: `remove_all_tags` is NOT IN upstream; `replace` is at 245. ----
  ("4418 remove_all_tags", """# TAG 41 -- ops.py:1904. `remove_all_tags`:
#     remove_all_tags = PatternMatcher([(UPat(GroupOp.All, name="x"), lambda x: x.replace(tag=None) if x.tag is not None else None)])
#
# `ops.py:253-257` is what `replace(tag=None)` is:
#     new_args = (kwargs.pop("op", self.op), kwargs.pop("src", self.src), kwargs.pop("arg", self.arg), kwargs.pop("tag", self.tag))
#     if (self.op, self.src, self.arg, self.tag) == new_args: return self
#     return UOp(*new_args)
# so the port is the node rebuilt with all four of ITS OWN fields and `TNone{}` in
# the tag slot -- which is `ops.bend:6649`'s inline `replace`, already written.""",
   """# TAG 41 -- tinygrad/uop/spec.py:207 symbol=spec_program. `remove_all_tags`:
#     remove_all_tags = PatternMatcher([(UPat(GroupOp.All, name="x"), lambda x: x.replace(tag=None) if x.tag is not None else None)])
#
# `remove_all_tags` is NOT IN upstream's `ops.py` AT THIS PIN; the surviving upstream construct that matches "every op" is `spec.py`'s `UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks)`.
# `ops.py:245-249` symbol=UOp.replace is what `replace(tag=None)` is:
#     new_args = (kwargs.pop("op", self.op), kwargs.pop("src", self.src), kwargs.pop("arg", self.arg), kwargs.pop("tag", self.tag))
#     if (self.op, self.src, self.arg, self.tag) == new_args: return self
#     return UOp(*new_args)
# so the port is the node rebuilt with all four of ITS OWN fields and `TNone{}` in the tag slot -- which is `ops.bend:6649`'s inline `replace`, already written."""),

  # ---- 4435-4443: the guard is the port's own; the upstream pointer is spec.py. ----
  ("4438 guard", """# THE PARAMETER IS NAMED `untagged`, NOT `tagged`, and the first draft called it
# `tagged` while passing it `tag_is_none(...)`. That compiled, typechecked, answered
# CORRECTLY for every input, and the probe's `pick_t_rule`/`pick_f_rule` pair is what
# found it: those two rows are written from ops.py:1904's guard -- "True means the
# node HAS a tag, so it gets a replacement" -- and the implementation answered the
# other way round, so the row and the code disagreed and the ROW was right about
# what the name claims. A name that is the negation of the value it holds is the
# same defect as a shadowed binder with better manners: both compile, both report
# their flag correctly, and both mislead whoever writes the next mutation.""",
   """# THE PARAMETER IS NAMED `untagged`, NOT `tagged`, and the first draft called it
# `tagged` while passing it `tag_is_none(...)`. That compiled, typechecked, answered
# CORRECTLY for every input, and the probe's `pick_t_rule`/`pick_f_rule` pair is what
# found it: those two rows are written from the port's OWN `remove_all_tags` guard,
# which is NOT IN upstream's `ops.py`; the surviving upstream construct that matches
# "every op" is tinygrad/uop/spec.py:207 symbol=spec_program. And the implementation
# answered the other way round, so the row and the code disagreed and the ROW was
# right about what the name claims. A name that is the negation of the value it holds
# is the same defect as a shadowed binder with better manners: both compile, both report their flag correctly, and both mislead whoever writes the next mutation."""),

  # ---- 4451-4454: `_substitute` is at 1898; `dvars` is at 514. ----
  ("4451 _substitute", """# TAG 43 -- ops.py:1896. `_substitute`:
#     _substitute = PatternMatcher([(UPat(tuple(Ops), name="x"), lambda ctx,x: ctx.get(x,None))])
#
# The ctx is `dvars: dict[UOp, UOp]` (`ops.py:530`), so it is keyed by the NODE""",
   """# TAG 43 -- ops.py:1898 symbol=_substitute. `_substitute`:
#     _substitute = PatternMatcher([(UPat(tuple(Ops), name="x"), lambda ctx,x: ctx.get(x,None))])
#
# The ctx is `dvars: dict[UOp, UOp]` (`ops.py:514` symbol=UOp.substitute), so it is keyed by the NODE"""),

  # ---- 4944: `sint_to_uop` is at 1895, not 1893. ----
  ("4944 sint_to_uop", """# `sint_to_uop` -- ops.py:1893. `UOp.const(x, dtype=dtypes.weakint)`, and the""",
   """# `sint_to_uop` -- ops.py:1895 symbol=sint_to_uop. `UOp.const(x, dtype=dtypes.weakint)`, and the"""),

  # ---- 4955: `gate_kernel_sink` is at 1915, not 1901. ----
  ("4955 gate_kernel_sink", """# `gate_kernel_sink` -- ops.py:1901. Three arms, two of them NEGATIVE tests, and""",
   """# `gate_kernel_sink` -- ops.py:1915 symbol=gate_kernel_sink. Three arms, two of them NEGATIVE tests, and"""),

  # ---- 5436: `substitute` is at 514, not 530. ----
  ("5436 substitute", """#     `bsl.go`'s shape and readable; `substitute` (ops.py:530) is not ported, and""",
   """#     `bsl.go`'s shape and readable; `substitute` (ops.py:514 symbol=UOp.substitute) is not ported, and"""),

  # ---- 8187: `resolve_returned_after` is at 1901, not 1899. ----
  ("8187 resolve_returned_after", """# ==== ops.py:1899  `resolve_returned_after` ===============================""",
   """# ==== ops.py:1901 symbol=resolve_returned_after  ==============================="""),

  # ---- 8561: `unified_rewrite` is at 1814 and its fixpoint is 1826-1837. ----
  ("8561 unified_rewrite", """# `unified_rewrite`'s fixpoint (ops.py:1828-1835), where `test_n: UOp|None` is""",
   """# `unified_rewrite`'s fixpoint (ops.py:1826-1837 symbol=RewriteContext.unified_rewrite), where `test_n: UOp|None` is"""),
]


def main() -> int:
  text = TARGET.read_text(encoding="utf-8")
  lines = text.split("\n")
  before = len(lines)
  for name, old, new in EDITS:
    n_old, n_new = old.count("\n") + 1, new.count("\n") + 1
    if n_old != n_new:
      print(f"REFUSED {name}: {n_old} lines -> {n_new} lines", file=sys.stderr)
      return 1
    hits = text.count(old)
    if hits != 1:
      print(f"REFUSED {name}: the old text occurs {hits} times, not 1", file=sys.stderr)
      return 1
    # EVERY EDITED LINE MUST BE A COMMENT LINE. A citation lives in a comment, and an
    # edit that touched code would not be a comment-only change.
    for ln in old.split("\n"):
      if ln.strip() and not ln.lstrip().startswith("#"):
        print(f"REFUSED {name}: the old text touches a NON-COMMENT line: {ln!r}",
              file=sys.stderr)
        return 1
    for ln in new.split("\n"):
      if ln.strip() and not ln.lstrip().startswith("#"):
        print(f"REFUSED {name}: the new text touches a NON-COMMENT line: {ln!r}",
              file=sys.stderr)
        return 1
    text = text.replace(old, new)
  after = text.split("\n")
  if len(after) != before:
    print(f"REFUSED: the file went from {before} lines to {len(after)}", file=sys.stderr)
    return 1
  TARGET.write_text(text, encoding="utf-8")
  print(f"OK: {len(EDITS)} comment-only edits, line count {before} -> {len(after)}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
