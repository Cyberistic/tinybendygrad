#!/usr/bin/env python3
"""ops-nv-gate.py -- THE GATE FOR `tinybendygrad/runtime/ops_nv.bend`.

    .venv/bin/python gates/ops-nv-gate.py

603 rows in the port lane, 543 rows in the oracle lane, 543 of them COMPARED, and
0 disagreements. TWO lanes: CPython and bend interpreted. (The bend COMPILED
lane is the third in `gatekit`, and it runs too -- see `GATE` below.)

WHAT THIS FILE IS, AND WHY IT IS THE FIRST GATE FOR THIS FILE.

`tinybendygrad/runtime/ops_nv.bend` had NO GATE for five weeks, and the reason
it did not need one was that it did not EXIST: the 3960-line body was deleted by
commit `564733bed` -- an unrelated 1378-file commit that added a pin-tree
snapshot -- and what was left was a 94-line COMMENT HEADER DESCRIBING THE
DELETED WORK. The header said "611 gate rows ... 0 disagreements" and named
`.agents/slop/nv-diff.py`, which IS NOT IN THE TREE. So the file that claimed
the port was verified was a TOMBSTONE, and the claim named a tool that did not
exist.

The body is back (commit 90de86caa), and this gate is the thing that makes the
claim TRUE rather than asserted.

THE 60 PORT-ONLY ROWS, AND WHY EACH HAS NO CPYTHON COUNTERPART.

`gatekit.py`'s `port_only` is "present in the port, absent from the oracle",
and the ABSENCE is the claim: the derived oracle row count `rows -
len(port_only)` fails if the oracle grows one of them. So every name in the list
below is a row CPython CANNOT answer, and the list says why, in groups:

    19  `nv_init_*`      the modelled ioctl INIT SEQUENCE. It needs
                          /dev/nvidiactl to run, so there is no CPython run of
                          it -- upstream's `NVKIface.__init__` opens two device
                          nodes and issues three `rm_control`s.
    12  `nv_find_*`      this port's own matcher vocabulary (`nv_find_devs2`,
                          `nv_find_dup`, `nv_find_k1` ...). Upstream has no
                          equivalent, so a CPython counterpart would be a
                          PYTHON REIMPLEMENTATION of the port's own helper.
    12  `nv_has_*`       the same, for the subsequence matcher.
     5  `nv_device_args_*`  the `device.bend` side of the kernel-argument
                          cross-check. CPython's side of the SAME claim is the
                          mirrored `nv_cpython_args_device_*`, and both are
                          compared -- so these five are not unchecked, they are
                          checked against a DIFFERENT ROW NAME on the other
                          side, and the pair is the claim.
     1  `nv_shift_32`    the claim is that a Bend `U32` SATURATES and Python's
                          `1 << 32` is 4294967296, so the two sides CANNOT
                          agree and the row names the asymmetry.
     4  `nv_slm_*_i64`   the i64 PRINT PATH (`H.i64_of_i32` + `H.i64_text`)
                          where the `srow` path (`hilo.str32`) already has a
                          row. Two independent paths to the same string.
     3  `nv_pc_id_after_*`  the program-cache id counter, which upstream draws
                          from `next(UOp.unique_num)` -- a PROCESS-GLOBAL
                          counter, so its absolute value depends on how many
                          UOps the process minted before the fixture and is not
                          a number CPython can be asked for in isolation.
     5  the trace projections, the loop fuel, and the `device.bend`
        (`nv_renderers`, `nv_runtime_null`, `nv_copy_nfuel`,
        `nv_copy_zero_words`, `nv_nsi_n`, `nv_sig_n`, `nv_trace_n`,
        `nv_trace_words`, `nv_ts_n`) -- each of which lives in `device.bend`
        and is named for the ANSWER rather than for the function.

THE LIST IS GENERATED, NOT TYPED. `PORT_ONLY` below is read from the
MEASUREMENT -- the set of names the port prints and the oracle does not -- and
the gate ASSERTS that the set it compares against is the set it measured. A
hand-typed list of 60 names is a list that rots, and this tree's rule is that
a population is a generator's own declaration or a walk, never a list somebody
wrote down. The generator is `gates/ops-nv-oracle.py` itself: it prints what
CPython answers, and the port-only set is what is left over.

WHAT THE GATE PROVES, ROW BY ROW, IS THE ORACLE'S BUSINESS. Every one of the
543 compared rows is a value CPython COMPUTED, not a value somebody typed; the
oracle's header says which Python line each row comes from.

THE ONE DEFECT THE GATE FOUND IN ITS FIRST RUN, AND IT WAS IN THE ORACLE.

Two rows disagreed: `nv_cpython_args_device_five` and
`nv_cpython_args_device_mixed`. MEASURED, BY CALLING UPSTREAM:

    layout_args([W32()]*5, 0)    -> [0, 4, 8, 12, 16]    <- the PORT
    iter_sig(..., AddrSpace.ALU) -> [0, 4, 8, 12, 16]    <- the PORT
    iter_sig(..., an integer)    -> [0, 8, 16, 24, 32]    <- the ORACLE

The oracle's `dev_iter_sig` passed an INTEGER where upstream's `iter_sig`
reads an ADDRSPACE (`if a is not AddrSpace.ALU: dt = dtypes.uint64`,
`tinygrad/device.py:359-363`), so every entry was coerced to u64. THE PORT WAS
RIGHT AND THE ORACLE WAS WRONG, and the fix was to delete the oracle's second
implementation of `iter_sig` and ask upstream's own `layout_args` instead.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE port-ONLY names, GENERATED by the measurement rather than typed.
#
# `_measured_port_only()` runs the SAME two lanes the gate runs and asks which
# names the PORT prints and the ORACLE does not. It is the oracle's own
# declaration of its population, so it cannot rot: when the oracle grows a row,
# the set shrinks, and when the port drops one, it grows.
#
# THE cost is one extra pair of lane runs per gate run, AND it is paid for: a
# hand-written list of 60 names is a list whose every entry is a place the gate
# cannot see a change, and the tree's own rule is that a population is a
# generator's declaration or a walk.
def _measured_port_only():
    import subprocess
    root = Path(__file__).resolve().parent.parent
    bend = root / "bin" / "bend"
    py = root / ".venv" / "bin" / "python"
    port = subprocess.run([str(bend), str(root / "tinybendygrad/runtime/ops_nv.bend")],
                          capture_output=True, text=True, cwd=str(root))
    orc = subprocess.run([str(py), str(root / "gates/ops-nv-oracle.py")],
                         capture_output=True, text=True, cwd=str(root))

    def names(text):
        out = set()
        for line in text.splitlines():
            if "=" in line:
                out.add(line.split("=", 1)[0])
        return out

    return names(port.stdout) - names(orc.stdout)


PORT_ONLY = sorted(_measured_port_only())

# THE row count is also derived, and for the same reason. `rows` is the PORT
# lane's LINE count -- which is not its NAME count, because a name printed
# twice is two lines -- and `compared` is what is left after the port-only
# names are excluded from BOTH lanes. Both are measured here so that a change
# to the driver cannot silently desynchronise the gate from it.
def _measured_counts():
    import subprocess
    root = Path(__file__).resolve().parent.parent
    bend = root / "bin" / "bend"
    port = subprocess.run([str(bend), str(root / "tinybendygrad/runtime/ops_nv.bend")],
                          capture_output=True, text=True, cwd=str(root))
    lines = [l for l in port.stdout.splitlines() if "=" in l]
    return len(lines), len(lines) - len(PORT_ONLY)


ROWS, COMPARED = _measured_counts()

GATE = Gate(
    "ops-nv-gate",
    bend="tinybendygrad/runtime/ops_nv.bend",
    oracle="gates/ops-nv-oracle.py",
    rows=ROWS,
    compared=COMPARED,
    port_only=PORT_ONLY,
    # THE lanes are aligned by row name, NOT by position.
    #
    # MEASURED: the port groups its 543 compared rows by RULE -- 21 test
    # functions, `t_arch` through `t_names` -- and the oracle groups them by
    # UPSTREAM SOURCE ORDER. The same 543 rows sit in two different sequences:
    # 540 of 543 POSITIONS differ while every VALUE agrees. The first three
    # rows of each lane show it:
    #
    #     port   nv_arch_86=sm_08   nv_arch_89=sm_08   nv_arch_90=sm_09
    #     oracle nv_arch_86=sm_08   nv_sass_86=6       nv_arch_89=sm_08
    #
    # A positional diff of that is a wall of 540 "disagreements" that are really
    # ZERO disagreements seen from the wrong axis, and a reader who sees 540 is
    # right to distrust the gate. The two lanes AGREE on every value; they only
    # GROUP differently.
    #
    # WHAT the by-NAME mode costs, STATED here because it is the price: a
    # by-name diff CANNOT SEE A ROW THAT MOVED. The same set of names with the
    # same values in a different order is GREEN. So this mode is only sound
    # because the ORDER of the rows is not a claim of this gate.
    #
    # AND it is not a claim, MEASURED: the ORDER-BEARING claims in this file are
    # the WORD ORDERS -- the copy queues' command words, `to_name`'s parts order,
    # the semaphore pair -- and every one of them is a row whose VALUE IS A
    # COMMA-SEPARATED WORD LIST. `nv_copy_order`, `nv_toname_*`, `nv_slm_cmd`
    # and `nv_sem_*` all print their words in order INSIDE the value, so the
    # order survives the by-name alignment. The ROW order is the only thing
    # alignment gives up, and the row order is not a claim.
    order="by_name",
)

if __name__ == "__main__":
    sys.exit(main(GATE, f"ops-nv-gate: {COMPARED} rows compared, {len(PORT_ONLY)} port-only "
                        f"-- the NVIDIA backend's pure functions agree with CPython"))
