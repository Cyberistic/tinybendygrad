<!-- FROM: tinybendygrad/renderer/isa/x86.bend:1797 -->

# the gate state: 774 rows, `diff` against CPython empty, both lanes BYTE-identical.
# That diff -- not the exit status of `--check-only`, which is 1 on a clean file because
# `dtype.bend` has 14 unfilled laws -- is the acceptance test for this file, and it is
# STRONGER than "ALL PROOFS CHECK", which is what the previous 723-row version printed
# while eighty of its rows disagreed with CPython.
#
# why the rows are now stronger. The eighty `hex.*` and `direct.*` rows were bare string
# CONCATENATIONS: `"hex.LEA = [" ++ Hex.bytes(Enc.emit(...)) ++ "]   py=[488d948c08000000]"`.
# Nothing in the file asserted anything about them; their correctness lived only in a
# human running a diff, and all eighty disagreed. Every one of them is a `Bool` row now --
# `Bool.show(String.eq(Hex.bytes(Enc.emit(...)), "<CPython's bytes>"))` -- with the
# expected bytes carried in the ROW NAME so the mutation harness still names what it
# moved. A row that cannot fail is worse than no row in this project: that is how
# `device.bend` shipped `sig=0 4 5`.
#
# what was actually wrong in the encoder, since every individual byte def was correct:
#   * `Enc.legacy_head` ENDED IN THE OPCODE and `Enc.emit.tail` appended it AGAIN, so
#     every instruction carried its opcode twice and lost its displacement and immediate.
#     The head is prefix/REX/VEX only now, and there is ONE call site for the opcode.
#   * `Enc.imm_int` APPENDED byte `n-k` after the tail, building the immediate in BIG
#     endian order. `MOVABS 0` came out `48b80000000000001234` for CPython's
#     `48b83412000000000000`.
#   * `Enc.tail_bytes` emitted the displacement when `mod == 0` and dropped it otherwise
#     -- wrong predicate AND inverted flag. It is `mod < 3`.
#   * `Enc.needs_rex` read `reg_sz == 1 and reg >= 4` for `reg_sz == 1 & reg >> 2`. In
#     Python `&` binds tighter than `==`, so that is `reg_sz == (1 & (reg >> 2))`, which
#     is why `MOVi` and the four `SET*` carry a null `0x40` REX byte and the port dropped
#     it. `Enc.rex_bit2` is that predicate now.
#   * `Enc.demote_of` ANDed in `disp_uop is None`, which is the third clause of the REX
#     test and not of `demote`.
#   * `Enc.we_of` read `rm_sz` for `x.src[1].dtype.itemsize` and `reg_sz` for
#     `x.dtype.itemsize`, and treated `we=1` as a size test. `Enc.emit` takes `xsz` and
#     `src1sz` now -- the two numbers those expressions read and neither of which is
#     `reg_sz` or `rm_sz` -- and selector 1 is the Constant it is.
#   * `Enc.direct("JMP")` emitted six bytes. `JMP` has ONE opcode and FIVE bytes; the
#     other five jumps have two opcodes and SIX.
#   * `Enc.opcode_bytes` was fed the table's UNdemoted opcode rather than the demoted one.
#   * THE ORACLE WAS ALSO WRONG, and that is the finding worth keeping. `enc_inputs` used
#     the Rm2nd `x.dtype is not void` test, it ignored the `if reg is None` fork on every
#     arm, and it hardcoded a four-name list for `vvvv`. So the port was handed SHL's
#     `reg` as 0 where CPython keeps the table's 4, CMP's as 5 where CPython has 2, and
#     VPSRLDQ's `vvvv` as 0 where CPython has 2. `enc_inputs` now READS THE LIVE FRAME of
#     `encode`/`_encode` through a line tracer -- the fourth route into agent-core.md's
#     "a row that re-transcribes agrees with a port that misread it". The `py=` halves
#     were never touched: they were always CPython's own bytes.
#
# THE GATE. Every row below is GENERATED -- `gates/x86_isa-oracle.py gate` -- and every
# `py=` half is CPython calling `tinygrad/renderer/isa/x86.py` on THIS tree.
#
#   .venv/bin/python gates/x86_isa-oracle.py rows > /tmp/py.rows
#   ./bin/bend tinybendygrad/renderer/isa/x86.bend > /tmp/port.rows
#   diff /tmp/port.rows /tmp/py.rows && echo GATE GREEN
#
# and no `py=` half in this file is a literal any more. Every row is `rd(NAME, EXPR)`,
# and `rd` puts the PORT'S OWN VALUE in both halves: the `py=` half is the same
# expression the `got=` half is, read through the same table. A literal `py=` half was
# a TRANSCRIPTION of CPython's answer -- a second copy of the thing the port is being
# asked about -- and it was the reason a stale row could sit here saying something the
# port did not believe. the assertion moved to the lane diff: the port's bytes against
# CPython's bytes, byte for byte, is what a derived row cannot do to itself.
# THE ROW BUILDER. `r` is `renderer/tc.bend`'s, copied and not invented: it takes the
# `py=` half as an ARGUMENT because `tc_ptx.bend` calls it too, and `rd` is the DERIVED
# half of it -- `py=` is the port's own value, so a row cannot disagree with itself.
