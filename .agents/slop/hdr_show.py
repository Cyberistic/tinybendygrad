#!/usr/bin/env python3
"""Show a Python line (or range) by number, so a header's `:39` claim can be read.

A wall that cites `ip.py:39` is a claim that line 39 is where the FFI is. If the
line has moved, or now says something else, the wall is false -- and nothing in
the repo reads prose, so nothing else would notice.

    python3 .agents/slop/hdr_show.py tinygrad/runtime/ops_nv.py 353-384
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def show(path, spec):
    src = (ROOT / path).read_text().splitlines()
    a, _, b = spec.partition('-')
    a = int(a)
    b = int(b) if b else a
    for n in range(a, b + 1):
        if 1 <= n <= len(src):
            print('%5d %s' % (n, src[n - 1]))
        else:
            print('%5d <PAST EOF, file has %d lines>' % (n, len(src)))


if __name__ == '__main__':
    show(sys.argv[1], sys.argv[2])
