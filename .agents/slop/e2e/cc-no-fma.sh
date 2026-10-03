#!/bin/sh
# e2e/cc-no-fma.sh -- clang with FMA CONTRACTION OFF, for the CPU reference.
#
# WHY. `tinygrad/runtime/support/compiler_cpu.py:21` compiles the generated C with
# `-O2` and NO `-ffp-contract=off`, so clang may fuse a `a*b + c` into one FMA with
# a single rounding, while WGSL's `a*b + c` is two roundings. That is the whole of
# the difference the first GPU run showed (1-3 ulp on every element) and
# `examples/webgpu/mnist/README.md` reports the same effect for its convolutions.
#
# THE POINT OF THE WRAPPER is to make that attribution MEASURED rather than
# asserted: with contraction off on the CPU, the GPU's words and the CPU's words are
# compared for EQUALITY, and with contraction on they are compared for DISTANCE.
# One claim, two numbers, and the cause is named instead of absorbed into a
# tolerance nobody can audit.
#
# IT IS AN ENV VAR, NOT AN EDIT. `compiler_cpu.py` reads `getenv("CC", 'clang')`, so
# `CC=<this script>` changes the compiler without touching a read-only file. The
# wrapper only APPENDS a flag; everything else, including the `--target=` triple, is
# passed through untouched.
# THE FLAG GOES FIRST. MEASURED: appended after `tinygrad`'s argument list --
# which ends in `- -o -`, the stdin marker -- it does not reach clang's option
# parser and the CPU answer came back FMA-contracted anyway.
exec clang -ffp-contract=off "$@"
