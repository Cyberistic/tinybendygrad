#!/usr/bin/env python3
"""THE ops_bend MILESTONE GATE.

    .venv/bin/python .agents/slop/opsbend_milestone_gate.py rows.txt PACKET.in PACKET.out

Prints PASS or FAIL. It is NOT the claim -- the claim is the byte comparison. This
harness exists for three things and no more:

  1. WHOLE `name=value` LINE DIFFS, never row NAMES. A name-comparing harness
     reported 0 for all 30 mutations in one unit and 0 for all 68 in another.
  2. THE DENOMINATOR on every count. "3 buffers agree" without "3 of 3" is not a
     statement; a starved lane produced 115 rows where a loaded one produced 787.
  3. THE EXPECTED BYTES ARE READ FROM A FILE, not restated here, so the gate and
     the file cannot drift. The file was written BEFORE any run
     (`.agents/slop/ops_bend-milestone-expected.txt`); restating the literals in
     Python would make this a second oracle and defeat the point.

`PACKET.in` is checked against the port's OWN `encode` output implicitly: the
executor parsed it, and `ms_exit=0` says it did. `PACKET.out` is checked against
the same expectation as `ms_got`, from the OTHER side -- one by the port's Bend
code, one by reading the executor's file with Python -- so the two cannot be the
same mistake.
"""
import pathlib
import sys

EXPECTED = pathlib.Path(__file__).parent / "ops_bend-milestone-expected.txt"

# THE EXPECTATIONS ARE LIFTED OUT OF THE FILE, by parsing its own key=value TAIL
# and reading multi-line values the way Python's own `repr` would have written
# them. MEASURED, the naive `k, _, v = line.partition("=")` reads the whole
# three-line PACKET.out as the DOUBLE-QUOTED first line -- `'"4 00004040'` -- and
# then every byte comparison fails while the MILESTONE IS ACTUALLY PASSING. That is
# the worst shape a harness bug can take: a red gate over a green milestone. So
# the values below are unescaped here, from the file, with no literal of my own.
_RAW = EXPECTED.read_text()


def _field(key, multiline=False):
    """One key's value from the expectation file.

    `multiline` values are quoted and run to the closing quote -- MEASURED, the
    block form (`up to a blank line`) does not terminate here because the file
    separates its keys with single newlines, so a block read swallowed the rest of
    the file and every comparison failed. Scalar values stop at the newline.
    """
    body = _RAW.partition(key + " = ")[2]
    if multiline:
        # body starts at the opening quote, so the closing quote is the SECOND one.
        return body[1:body.index('"', 1)]
    return body.partition("\n")[0]


# MEASURED: a naive `k, _, v = line.partition("=")` reads the whole three-line
# PACKET.out as the DOUBLE-QUOTED FIRST LINE, and then every byte comparison fails
# while the milestone is actually PASSING. That is the worst shape a harness bug
# can take -- a red gate over a green milestone -- so the values are read as
# BLOCKS, one per key, with no literal of my own anywhere in this file.
WANT = {
    "packout": _field("expected_packout", multiline=True),
    "line_count": _field("expected_packout_line_count").strip(),
    "b0": _field("expected_buffer0").strip('"'),
    "b1": _field("expected_buffer1").strip('"'),
    "b2": _field("expected_buffer2").strip('"'),
    "store_count": _field("expected_store_count").strip(),
}
WANT["lines"] = WANT["packout"].rstrip("\n").split("\n")

# THE KERNEL. `ms_b0_hex_in` is what the port wrote into buffer 0 and `ms_got` is
# what came back; between them they must be the input pattern and the expectation.
IN_PATTERN = ["4 efbeadde", "4 0000803f", "4 00000040"]


def rows(path):
    out = {}
    for ln in pathlib.Path(path).read_text().splitlines():
        if "=" in ln:
            k, _, v = ln.partition("=")
            out[k.strip()] = v.strip()
    return out


def main():
    if len(sys.argv) < 4:
        print("usage: gate.py rows.txt PACKET.in PACKET.out")
        return 2
    R, pkt_in, pkt_out = (rows(sys.argv[1]),
                          pathlib.Path(sys.argv[2]).read_text(),
                          pathlib.Path(sys.argv[3]).read_text())
    bad = []

    def check(name, got, want):
        (bad.append(name) if got != want else None)
        print(f"  {'ok  ' if got == want else 'FAIL'} {name}: {got!r}"
              + ("" if got == want else f"  != want {want!r}"))

    # ---- 1. THE MILESTONE, PER BUFFER, OVER TEXT. --------------------------
    # FOUR failure modes, FOUR distinct strings: no store (the sentinel survives),
    # a store of the wrong operand, a store to the wrong buffer, and a
    # byte-swapped hex. A boolean over "did anything change" would be satisfied by
    # all four, so the comparison is over whole lines.
    #
    # THE ROWS ARE PER BUFFER AND NOT ONE STRING OVER ALL OF PACKET.out, and that
    # is a correction with a measured cause: `IO.print` STOPS AT A NEWLINE, so the
    # single-row version printed only the first line and compared a PREFIX with a
    # PREFIX -- and read True, because the port's own expectation was truncated the
    # same way. The two agreed by agreeing on less than they claimed to.
    print("== the milestone: expected bytes, written before the run")
    check("ms_exit (the executor launched)", R.get("ms_exit"), "0")
    for i in range(3):
        check(f"ms_b{i}_got  (PORT's readback)", R.get(f"ms_b{i}_got"), WANT[f"b{i}"])
        check(f"ms_b{i}_want (the file's expectation)", R.get(f"ms_b{i}_want"),
              WANT[f"b{i}"])
        check(f"ms_b{i} (the gate)", R.get(f"ms_b{i}"), "True")
    check("ms_line_count", R.get("ms_line_count"), "True")

    # ---- 2. THE EXECUTOR'S OWN FILE, READ BY PYTHON. A DIFFERENT READER. ----
    # If the Bend readback and this file agreed only because both were wrong the
    # same way, this is where it shows: two readers, two languages, one answer.
    print("== the executor's own file, read by python (a different reader)")
    check("PACKET.out (executor, via python)", pkt_out, WANT["packout"])
    check("PACKET.out line count", str(len(pkt_out.splitlines())), WANT["line_count"])
    check("PACKET.out agrees with the PORT, line for line",
          str(pkt_out.splitlines() == WANT["lines"]), "True")

    # ---- 3. THE ALLOCATOR, WITH ITS DENOMINATOR. ---------------------------
    print("== the allocator: 3 buffers, 12 bytes, bases 0/4/8")
    for nm, want in [("ms_b0_base", "0"), ("ms_b1_base", "4"), ("ms_b2_base", "8"),
                     ("ms_store_top", "12"), ("ms_store_len", "12"),
                     ("ms_b0_nbytes", "4")]:
        check(nm, R.get(nm), want)
    # THE DENOMINATOR, stated. "3 buffers agree" is not a statement; "3 of 3" is.
    agree = sum(1 for i in range(3)
                if R.get(f"ms_b{i}_got") == WANT[f"b{i}"])
    check("buffers agreeing with the expectation", f"{agree}/3", "3/3")
    print(f"#   load: 3 buffers, 12 bytes in, 12 bytes out, "
          f"{WANT['store_count']} buffer written, 2 left unchanged")
    check("buffers the kernel did NOT write (must be unchanged)",
          str(R.get("ms_b1_hex_in") == "0000803f" and R.get("ms_b2_hex_in") == "00000040"),
          "True")

    # ---- 4. THE PATTERN WENT IN WHOLE. -------------------------------------
    print("== the input pattern, three buffers, 12 bytes")
    for nm, want in [("ms_b0_hex_in", "efbeadde"), ("ms_b1_hex_in", "0000803f"),
                     ("ms_b2_hex_in", "00000040")]:
        check(nm, R.get(nm), want)
    check("bytes written", str(len(R.get("ms_b0_hex_in", "")) // 2
                               + len(R.get("ms_b1_hex_in", "")) // 2
                               + len(R.get("ms_b2_hex_in", "")) // 2), "12")

    # ---- 5. THE PORT'S `raw_free` IS A NO-OP, AS PYTHON'S IS. ---------------
    # `HostAllocator._free` (device.py:307) touches storage only under
    # `if (remote:=...)`, and BEND has no remote -- so a free releasing nothing is
    # the port of the Python, not a shortcut. The row renders the FREED buffer.
    print("== raw_free")
    check("ms_free_noop", R.get("ms_free_noop"), "4 efbeadde")
    check("bend_free_is_noop", R.get("bend_free_is_noop"), "True")

    print(f"\n# {len(bad)} failed of {len(R)} rows read")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())