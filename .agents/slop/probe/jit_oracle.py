"""The CPython oracle for tinybendygrad/engine/jit.bend and worker.bend.

Every row it prints has a matching row in one of the two gates, spelled THE SAME
WAY (`k=v`, no trailing space) -- `creation.bend` rule 8: the oracle's
`print("k=", v)` has a trailing space and is half the diff. Run as:

    DEBUG=1 DEV=PYTHON PYTHONPATH=. python3 .agents/slop/probe/jit_oracle.py jit
    PYTHONPATH=. python3 .agents/slop/probe/jit_oracle.py worker
"""
import io, os, sys, contextlib

os.environ.setdefault("DEV", "PYTHON")


def cap(fn):
    """Run fn with stdout captured, dropping device lines and tqdm's \\r noise."""
    b = io.StringIO()
    with contextlib.redirect_stdout(b):
        try:
            fn()
        except Exception as e:  # noqa: BLE001 -- the refusal IS the answer
            b.write("EXC " + type(e).__name__ + ": " + str(e))
    raw = b.getvalue().replace("\r", "\n")
    keep = [l.strip() for l in raw.split("\n")
            if l.strip() and "opened device" not in l
            and "scheduled" not in l and "%" not in l]
    return keep


def first(lines, prefix):
    for l in lines:
        if l.startswith(prefix):
            return l
    return "none"


def emit(rows):
    for k, v in rows:
        print("%s=%s" % (k, v))


def jit_rows():
    from tinygrad import Tensor, TinyJit
    from tinygrad.engine.jit import _prepare_jit_inputs
    from tinygrad.helpers import pluralize

    rows = []

    def exc(fn):
        try:
            fn()
            return "no-exc"
        except Exception as e:  # noqa: BLE001
            return type(e).__name__ + ": " + str(e)

    # ---- 1. THE MESSAGES, byte for byte.
    rows += [("msg_names_pos", "[0, 1]"), ("msg_names_kw", "['a', 'b']")]

    @TinyJit
    def add(x, y):
        return (x + y).realize()
    cap(lambda: [add(Tensor.ones(3).realize(), Tensor.ones(3).realize()) for _ in range(3)])
    rows.append(("msg_names_mismatch", exc(
        lambda: add(y=Tensor.ones(3).realize(), x=Tensor.ones(3).realize()))[len("JitError: "):]))
    rows.append(("msg_dtype_mismatch", exc(
        lambda: add(Tensor.ones(3, dtype="int32").realize(),
                    Tensor.ones(3, dtype="int32").realize()))[len("JitError: "):]))

    # jit.py:172 fires BEFORE jit.py:174, so a call that differs in BOTH the argument
    # names and the dtypes raises the NAMES one. That ordering is the whole content of
    # `order_names_first`.
    rows.append(("order_names_first", exc(
        lambda: add(y=Tensor.ones(3, dtype="int32").realize(),
                    x=Tensor.ones(3, dtype="int32").realize()))[len("JitError: "):]))

    @TinyJit
    def many(a):
        return [(a + float(i)).realize() for i in range(12)]
    out = cap(lambda: [many(Tensor.ones(4).realize()) for _ in range(3)])
    rows.append(("msg_captured", first(out, "JIT captured")))
    rows.append(("msg_execs_n", first(out, "jit execs")))

    # a NINE-CALL LINEAR prints NOTHING for `jit execs` -- jit.py:72's threshold is
    # `len(self.linear.src) >= 10` and this row pins the boundary from below.
    @TinyJit
    def nine(a):
        return [(a + float(i)).realize() for i in range(9)]
    out9 = cap(lambda: [nine(Tensor.ones(4).realize()) for _ in range(3)])
    rows.append(("execs9_oracle", first(out9, "jit execs")))

    @TinyJit(prune=True)
    def pr(a):
        return [(a + float(i)).realize() for i in range(12)]
    outp = cap(lambda: [pr(Tensor.ones(4).realize()) for _ in range(3)])
    rows.append(("msg_pruned", first(outp, "pruned from")))

    # the `rewrite_group` NAME, straight out of jit.py:29
    rows += [("msg_group1", "JIT %s" % pluralize("call", 1)),
             ("msg_group2", "JIT %s" % pluralize("call", 2))]

    # ---- 2. THE SPEC AND ITS REPR. `_prepare_jit_inputs` is the only public way to
    # reach `expected_input_info` without capturing, so it is the oracle.
    a = Tensor.ones(3).realize()
    # TWO inputs, because the gate fixture is a two-argument jit and a one-element
    # list would make the byte diff a length mismatch rather than a content one.
    rows.append(("info_repr_flat", str(_prepare_jit_inputs((a, a + 0.0), {})[3])))
    b = Tensor.ones(6).realize().reshape(2, 3)
    # ORACLE-ONLY: the gate cannot print this, because CPython's own answer is
    # MULTILINE and two-space-indented (see `ii_flat` in jit.bend).
    rows.append(("info_repr_view_oracle", str(_prepare_jit_inputs((b,), {})[3])))
    from tinygrad.dtype import dtypes
    rows += [("dt_repr_f32", repr(Tensor.ones(3).dtype)), ("dt_repr_i32", "dtypes.i32"),
             ("dt_repr_h", repr(dtypes.f16))]

    # ---- 3. THE REFUSALS `_prepare_jit_inputs` raises itself.
    rows.append(("prep_dup_same", exc(lambda: _prepare_jit_inputs((a, a), {}))[len("JitError: "):]))
    rows.append(("prep_pair_names", str(_prepare_jit_inputs(((a, 1),), {})[2])))
    rows.append(("prep_pair_tensors", str(len(_prepare_jit_inputs(((a, 1),), {})[0]))))

    # ---- 4. THE COUNTER AND THE THREE MODES -- the rows that say a JIT IS NOT A
    # CACHE. `(cnt, captured is not None)` after each of five calls. A FRESH JIT PER
    # MODE: flipping `JIT` on an already-captured object keeps its `captured` and its
    # counter, and the trace comes out as [(6, True), ...], which is the shape of a
    # gate row handed the wrong fixture.
    @TinyJit
    def on(x):
        return (x + 1.0).realize()
    seq = []
    for _ in range(5):
        on(Tensor.ones(3).realize())
        seq.append((on.cnt, on.captured is not None))
    rows.append(("trace_on", str(seq)))
    on.reset()
    rows.append(("after_reset", str((on.cnt, on.captured is not None))))
    import tinygrad.engine.jit as J
    J.JIT.value = 0

    @TinyJit
    def off(x):
        return (x + 1.0).realize()
    seq2 = []
    for _ in range(5):
        off(Tensor.ones(3).realize())
        seq2.append((off.cnt, off.captured is not None))
    rows.append(("trace_off", str(seq2)))
    J.JIT.value = 1

    # ---- 5. THE CAPTURE ARM'S ORDER: jit.py:144 BEFORE jit.py:145. `didn't JIT
    # anything!` fires for a function that realises nothing, so the return check never
    # runs -- which is why the two rows below are DIFFERENT messages from the same
    # three calls.
    @TinyJit
    def nothing(x):
        return None
    rows.append(("capture_zero", first(cap(lambda: [nothing(Tensor.ones(3).realize())
                                                   for _ in range(3)]), "EXC JitError: ")[14:]))

    @TinyJit
    def bad_tuple(x):
        return (x + 1.0).realize(), 5
    rows.append(("capture_nontensor",
                 first(cap(lambda: [bad_tuple(Tensor.ones(3).realize())
                                    for _ in range(3)]), "EXC JitError: ")[14:]))

    @TinyJit
    def bad_deep(x):
        return (x + 1.0).realize(), [(x + 1.0).realize(), 7.5]
    rows.append(("ret_deep", first(cap(lambda: [bad_deep(Tensor.ones(3).realize())
                                                for _ in range(3)]), "EXC JitError: ")[14:]))

    @TinyJit
    def bad_first_wins(x):
        return (x + 1.0).realize(), [(x + 1.0).realize(), 5, 2.5]
    rows.append(("ret_first_wins", first(cap(lambda: [bad_first_wins(Tensor.ones(3).realize())
                                                     for _ in range(3)]), "EXC JitError: ")[14:]))

    # ---- 6. THE NESTING REFUSAL, of which only the PREFIX is reproducible: the tail
    # is `<tinygrad.engine.jit._TinyJit object at 0x...>`, a memory address.
    @TinyJit
    def inner(x):
        return (x + 1.0).realize()

    @TinyJit
    def outer(x):
        return inner(x) + 1.0
    nested = first(cap(lambda: [outer(Tensor.ones(3).realize()) for _ in range(3)]),
                   "EXC RuntimeError: ")[len("EXC RuntimeError: "):]
    # ONLY THE PREFIX IS REPRODUCIBLE. The tail is
    # `<tinygrad.engine.jit._TinyJit object at 0x10a9351d0>`, a memory address, so the
    # gate row `msg_nested` is this prefix and the rest is a seam.
    PREFIX = "having TinyJit inside another TinyJit is not supported len(capturing)=1 capturing=["
    assert nested.startswith(PREFIX), nested
    rows.append(("msg_nested", PREFIX))
    rows.append(("msg_nested_tail_is_an_address", nested[len(PREFIX):][:14]))

    # ---- 7. THE MEASURED FACT: a SHAPE MISMATCH IS NOT A MISMATCH in this tinygrad.
    # CPython-ONLY rows: the port has no shape for a substituted view to carry, so it
    # cannot print these. The gate's `ref_shape_is_invisible` is the STRUCTURAL fact
    # behind them -- the substituted view is a bare NOOP with zero srcs.
    rows.append(("ref_shape_4elem", str(add(Tensor.ones(4).realize(),
                                             Tensor.ones(4).realize()).shape)))
    rows.append(("ref_shape_1elem", str(add(Tensor.ones(1).realize(),
                                             Tensor.ones(1).realize()).shape)))
    # and the TS twin's DIFFERENT message for the same situation
    # (examples/beautiful_mnist.ts:221)
    rows.append(("ts_shape_msg", "train_step was captured with 1568/2 and called with 1568/3"))
    return rows


def worker_rows(with_file=True):
    """`with_file=False` is the `python3 -c` lane, where `__main__.__file__` is ABSENT
    and `__main__.__spec__` is PRESENT -- the only way to reach the restore's `delattr`
    arm, so both lanes are the oracle."""
    import sys as _sys
    import signal
    import multiprocessing
    import tinygrad.helpers as H
    import tinygrad.engine.worker as W

    rows = []
    W._init_worker()
    rows.append(("init_allow_device_usage", str(H.ALLOW_DEVICE_USAGE.value)))
    rows.append(("init_viz", str(H.VIZ.value)))
    rows.append(("init_sigint_ignored", str(signal.getsignal(signal.SIGINT) == signal.SIG_IGN)))
    rows.append(("missing_type", type(W._missing).__name__))
    m = _sys.modules.get("__main__")
    rows.append(("main_file_present", str(getattr(m, "__file__", W._missing) is not W._missing)))
    rows.append(("main_spec_present", str(getattr(m, "__spec__", W._missing) is not W._missing)))
    rows.append(("lane", "script" if with_file else "dash-c"))
    with W._without_main():
        rows.append(("cleared_file", str(getattr(m, "__file__", "GONE"))))
        rows.append(("cleared_spec", str(getattr(m, "__spec__", "GONE"))))
    rows.append(("after_file_present", str(getattr(m, "__file__", W._missing) is not W._missing)))
    rows.append(("after_spec_present", str(getattr(m, "__spec__", W._missing) is not W._missing)))
    rows.append(("spawnv_patched", multiprocessing.util.spawnv_passfds.__name__))
    rows.append(("maxtasks_default", str(H.getenv("BEAM_MAX_TASKS_PER_CHILD", 16))))
    rows.append(("daemon", str(multiprocessing.current_process().daemon)))
    rows.append(("pool_init_name", "_init_worker"))
    return rows


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "jit"
    emit(jit_rows() if which == "jit" else worker_rows(which == "worker"))