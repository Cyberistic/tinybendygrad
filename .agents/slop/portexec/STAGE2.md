# STAGE 2 — CALLING THE PORT'S KERNEL **FROM BEND**

**REACHED: yes. `zsh .agents/slop/portexec/run-kernel.sh` → PASS, 3/3 negative
controls red, and one real bug in my own harness found by a control.**

## THE CHAIN, AND WHICH STEP IS WHICH

```
bend -o   run-kernel.bend -o run.c     122,657 bytes; shim INLINED at line 4688
cc        -Wall -Werror -c kernel.c     680-byte object, ZERO warnings   <- the PORT's C
cc        -c run.c                      83,224 bytes (bend's own runtime warns; -Wall only)
LINK      run.o kernel.o -o run.bin     ok
RUN       ./run.bin                     4 WORD lines
COMPARE   vs CPython                    diff bytes: 0,  4/4 words
```

`bend -o` **inlines** `shim.c` (confirmed by grepping `klaunch_run` at line 4688
of `run.c`), so the shim is never concatenated by hand.

## WHAT THE PORT CONTROLS

| part | who |
|---|---|
| `void E_4(float* restrict data0_4, float* restrict data1_4)` | **PORT** — `cstyle.bend:1643` `render_kernel`, read out of the port's own 227-row stdout |
| the two kernel body lines | **NEITHER** — the gate's literal `g_kernel()` at `cstyle.bend:1879`, handed to `render_kernel` as an input; upstream is handed the same two lines (`renderer_oracle.py:508`) |
| the `extern` prototype in the shim | **PORT** — parsed out of the port's own emitted text by `exec_harness.signature`, never typed |
| everything else in the shim, and all of `main` | **HARNESS** |

## THE `Nat` POINTER — the thing that could not work

`Nat` works to 2^51−1 and aborts at 2^52−1, so the question was whether a real
address fits. **Measured, three runs, before relying on it** (`addrprobe.c`):

```
heap   0x10080a480 .. 0x104772480   = 4,303,398,016 .. 4,369,884,288
stack  0x16bd36284                   = 6,103,982,724
                                  both < 2^48 = 281,474,976,710,656
```

And at run time Bend printed its own addresses, all three under 2^51:

```
KERNEL_NAT 4378857668     <- &E_4, the PORT's own emitted symbol
DST_NAT    4387250240
SRC_NAT    4387250256
```

Two runs printed **different** addresses (`4344107204 / 4354187328 / 4354187344`).
That is ASLR, it is why no address is ever compared to a constant
(`ffi-experiment/EXPECTED.md`, E8), and it is why the determinism check compares
the `WORD` lines only — comparing whole stdout called a correct lane
non-deterministic on the first attempt.

## THE BUG A NEGATIVE CONTROL FOUND

The lane was **green with both buffer pointers equal**. `khi()`/`klo()` read a C
static that `kmalloc` overwrites, and my generated program read `dst_hi`/`dst_lo`
*after* the second allocation — so the kernel was called with the same buffer
twice. A self-aliased call of this kernel returns the **correct** answer by
construction, because the kernel's answer is a function of one buffer only.

Nothing in the PASS path could see it. The `"fill the wrong buffer"` control was
written to turn the lane red, did not, and that is the only reason it was found.
The fix is in `gen_ffi.py`'s `tail` (take the `(hi, lo)` pair immediately), and
`run-kernel.sh` STEP 5 now **asserts the buffer Nats are DISTINCT** so the lane can
never be green through an aliased call again.

## NEGATIVE CONTROLS

| plant | result |
|---|---|
| the PORT's own body text, `+1.0f` → `+2.0f` | **RED** |
| shim: never call the kernel | **RED** |
| bend program: fill the output buffer, not the input | **RED** |

**TWO PLANTS THAT ARE THEOREMS, REPORTED AS THEOREMS.** Making the two buffer slots
equal — in *either* direction — leaves the lane green. `kern2 CLANG` reads only
`data1_4`, writes only `data0_4`, and its answer is a function of one buffer, so
aliasing is invisible to it. Both aliased runs printed exactly the correct four
words. Dropping the last three input words is the same theorem: the kernel reads
lane 0 only. These are not counted towards the three.

## WHAT THIS DOES AND DOES NOT CLAIM

The port's emitted C was **compiled by `cc -Wall -Werror` with zero warnings,
linked, and executed**, and Bend — not C — allocated the buffers, filled them word
by word, called the kernel through a `Nat` pointer it obtained from C, read the
output back word by word and printed it. That is the first time in this project
that the port's output has been executed rather than compared as text.

It does **not** claim the port generated the arithmetic: the two body lines are a
fixture, and `cstyle.bend` has no `_render` at all.
