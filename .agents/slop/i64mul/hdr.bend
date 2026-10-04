import Base
# THE LANDED GATE. Every def under test is reached THROUGH H, i.e. through the real
# tinybendygrad/helpers.bend. This file defines NO i64 arithmetic of its own, so a
# mutation of helpers.bend moves these rows. `mrow`/`srow`/`main` are emitted by
# gen_gate.py, which calls H.u64_mul / H.i64_mul by name.
import ./../../../tinybendygrad/helpers.bend as H
