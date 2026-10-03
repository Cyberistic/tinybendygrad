#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/runtime/ops_null.bend.

Calls the opcode constants (ops_null.py:22) and raises NullDevice's EMULATE
assert (ops_null.py:65-66) so the message is the exception text.

`nr_nargs_*` / `nr_pads_*` / `nr_words_*` are not printed. Those counts are the
arity of each `cmd(...)` call site, and printing them would restate the call
rather than ask cmd what it laid down for a real exec/copy/wait. The device
rows (`nr_copy_dev`) embed whichever device getenv selected and are host answers.
"""
import os

from tinygrad.helpers import getenv
from tinygrad.runtime.ops_null import EXEC, COPY, WAIT, STORE, TIMESTAMP, NullDevice


def row(name, value):
    print(f"{name}={value}")


def emulate(tag):
    getenv.cache_clear()
    os.environ["EMULATE"] = tag
    try:
        NullDevice("NULL")
    except AssertionError as e:
        return str(e)
    finally:
        os.environ.pop("EMULATE", None)
        getenv.cache_clear()
    return "no-raise"


def main():
    row("nr_exec", EXEC)
    row("nr_copy", COPY)
    row("nr_wait", WAIT)
    row("nr_store", STORE)
    row("nr_timestamp", TIMESTAMP)
    row("nr_emulate_msg_rdna4", emulate("AMD_RDNA4"))
    row("nr_emulate_msg_amd", emulate("AMD"))
    row("nr_emulate_msg_cdna", emulate("AMD_CDNA4"))
    row("nr_emulate_msg_other", emulate("NOPE"))


if __name__ == "__main__":
    main()
