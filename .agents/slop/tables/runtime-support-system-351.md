<!-- FROM: tinybendygrad/runtime/support/system.bend:351 -->
# BLOCK:
# THE TRACE. `Tr.emit` is the seam: every OS call goes through it, so the trace is
# the ordered list of syscalls the C runtime will make.
#
# THE RAISE. `Tr.emit` and `Tr.emit.stop` record NOTHING once `refused` is set.
#
# MEASURED BLIND SPOT. Dropping the `refused` guard from `Tr.emit.go` (M42) moves NO
# ROW, and the reason is structural rather than a coverage gap: no def in this file
# emits after a refusal, because every truncation is produced by the CALLER's
# `Bool.pick` -- `sysfs.raise` calls `Tr.fail` on a trace whose last call it just
# emitted, and `Tr.emit.stop` fails on the call it emits. So the guard is
# defence-in-depth that Python's control flow never reaches. It is kept because a
# future def that emits after a refusal needs it, and it is REPORTED rather than
# closed with a row that asserts the guard's own behaviour.
# That is the port of every `raise` and every `assert` in the file -- :15's
# visibility assert, :37's mmap failure, :59's re-read failure, :92's mlock, :99's
# contiguous cap, :120's "no pcie", :135's IndexError, :198's flock, :212's
# PermissionError, :216's bound driver, :268's resize -- and it is why no step
# below needs a guard of its own. A refusal shows up as a TRUNCATION.
# END BLOCK

# THE TRACE. `Tr.emit` is the seam: every OS call goes through it, so the trace is
# the ordered list of syscalls the C runtime will make.
#
# THE RAISE. `Tr.emit` and `Tr.emit.stop` record NOTHING once `refused` is set.
#
# MEASURED BLIND SPOT. Dropping the `refused` guard from `Tr.emit.go` (M42) moves NO
# ROW, and the reason is structural rather than a coverage gap: no def in this file
# emits after a refusal, because every truncation is produced by the CALLER's
# `Bool.pick` -- `sysfs.raise` calls `Tr.fail` on a trace whose last call it just
# emitted, and `Tr.emit.stop` fails on the call it emits. So the guard is
# defence-in-depth that Python's control flow never reaches. It is kept because a
# future def that emits after a refusal needs it, and it is REPORTED rather than
# closed with a row that asserts the guard's own behaviour.
# That is the port of every `raise` and every `assert` in the file -- :15's
# visibility assert, :37's mmap failure, :59's re-read failure, :92's mlock, :99's
# contiguous cap, :120's "no pcie", :135's IndexError, :198's flock, :212's
# PermissionError, :216's bound driver, :268's resize -- and it is why no step
# below needs a guard of its own. A refusal shows up as a TRUNCATION.
