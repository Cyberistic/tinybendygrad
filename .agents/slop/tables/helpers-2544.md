<!-- FROM: tinybendygrad/helpers.bend:2544 -->
# BLOCK:
# GlobalCounters -- `class GlobalCounters`, helpers.py:302
#
# SIX ClassVars (helpers.py:303-308) and one `@staticmethod reset` (:309-310). The
# class has no methods beyond `reset` and no instances anywhere: every write is
# `GlobalCounters.<name> = ...` or `GlobalCounters.<name> += ...` on the CLASS.
#
# THE MUTABLE-STATE ANSWER, since it is the question this block exists to settle.
# Upstream's state lives in the class object and every reader sees the last write.
# Bend has no mutable globals, no `Ref`, no store and no closures, so the state is a
# `Data` VALUE that is threaded: `Counters` in, `Counters` out, and each `bump_*` is
# the one-line rebuild that upstream's `+=` is. That is not a weaker counter, it is
# the same counter:
#   - it COUNTS. `bump_ops` adds `d` to the value that came IN, so a sequence of five
#     bumps accumulates, and the gate runs exactly that sequence and prints the total
#     after each step (`gc_init_ops`, `gc_bumped_ops`) against live CPython.
#   - it CANNOT GO STALE, which is the property a mutable global does not have. There
#     is no second copy to read, so a reader that forgets to thread the newest record
#     gets the OLD value -- a wrong answer the gate can see, not a silently shared
#     cell that is right until someone forgets to update it.
# What threading costs is the caller: `GlobalCounters.reset()` upstream is a statement
# and `GlobalCounters.reset(GlobalCounters.reset())` here is a value the caller must
# use. That is the whole price and it is paid at the one place that owns the record.
#
# `mem_used` and `mem_used_per_device` are the interesting half and `reset` is why:
# the tuple at :310 names FOUR fields, and the source says on :324-325 that the other
# two are "NOT reset". A `reset` that zeroed all six would be a plausible-looking bug
# that no test of the four would catch, so the gate reads `mem_used` and the per-device
# counts AFTER a reset (`gc_after_used`, `gc_after_dev0`, `gc_after_dev3`).
#
# `time_sum_s` is a CPython `float`, i.e. an F64, and it is the one field that cannot
# be incremented here: `base.bend` has no F32 addition. `F32.add` is a `law`
# (references/bend/bend2/base.bend:1681 symbol=F32.add) -- an axiom with no body -- and live code may not call a law, so a
# float accumulator has no expression. The field is carried, typed `F32`, and is
# never written here; `.agents/slop/helpers-oracle.py` measures what CPython does with
# it and prints those rows to STDERR so they are recorded without being diffed.
# TODO(p4) helpers.py:306  `time_sum_s` needs the engine's clock, which is a C effect.
# END BLOCK

# GlobalCounters -- `class GlobalCounters`, helpers.py:302
#
# SIX ClassVars (helpers.py:303-308) and one `@staticmethod reset` (:309-310). The
# class has no methods beyond `reset` and no instances anywhere: every write is
# `GlobalCounters.<name> = ...` or `GlobalCounters.<name> += ...` on the CLASS.
#
# THE MUTABLE-STATE ANSWER, since it is the question this block exists to settle.
# Upstream's state lives in the class object and every reader sees the last write.
# Bend has no mutable globals, no `Ref`, no store and no closures, so the state is a
# `Data` VALUE that is threaded: `Counters` in, `Counters` out, and each `bump_*` is
# the one-line rebuild that upstream's `+=` is. That is not a weaker counter, it is
# the same counter:
#   - it COUNTS. `bump_ops` adds `d` to the value that came IN, so a sequence of five
#     bumps accumulates, and the gate runs exactly that sequence and prints the total
#     after each step (`gc_init_ops`, `gc_bumped_ops`) against live CPython.
#   - it CANNOT GO STALE, which is the property a mutable global does not have. There
#     is no second copy to read, so a reader that forgets to thread the newest record
#     gets the OLD value -- a wrong answer the gate can see, not a silently shared
#     cell that is right until someone forgets to update it.
# What threading costs is the caller: `GlobalCounters.reset()` upstream is a statement
# and `GlobalCounters.reset(GlobalCounters.reset())` here is a value the caller must
# use. That is the whole price and it is paid at the one place that owns the record.
#
# `mem_used` and `mem_used_per_device` are the interesting half and `reset` is why:
# the tuple at :310 names FOUR fields, and the source says on :324-325 that the other
# two are "NOT reset". A `reset` that zeroed all six would be a plausible-looking bug
# that no test of the four would catch, so the gate reads `mem_used` and the per-device
# counts AFTER a reset (`gc_after_used`, `gc_after_dev0`, `gc_after_dev3`).
#
# `time_sum_s` is a CPython `float`, i.e. an F64, and it is the one field that cannot
# be incremented here: `base.bend` has no F32 addition. `F32.add` is a `law`
# (references/bend/bend2/base.bend:1681 symbol=F32.add) -- an axiom with no body -- and live code may not call a law, so a
# float accumulator has no expression. The field is carried, typed `F32`, and is
# never written here; `.agents/slop/helpers-oracle.py` measures what CPython does with
# it and prints those rows to STDERR so they are recorded without being diffed.
# TODO(p4) helpers.py:306  `time_sum_s` needs the engine's clock, which is a C effect.
