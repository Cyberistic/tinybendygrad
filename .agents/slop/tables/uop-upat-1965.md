<!-- FROM: tinybendygrad/uop/upat.bend:1950 at ba3f52b0a^; ba3f52b0a REPLACED the block -->

# THE FUZZ DRIVER. `main` with NO argument is the gate and nothing else; with
# ONE argument it reads a case file, builds the case's UPat in the pattern
# arena, runs the SAME `upat_compile` the gate runs, and prints ONE canonical
# line. No new logic: everything below is the case FORMAT's reader, and the
# only call into the port is `upat_compile`.
#
# the case is a string and both sides read it. a case is one line, the `ctx`
# flag, and a `|`-separated list of nodes in POST-ORDER -- a node's `src`
# indices always name nodes already listed. That is what makes the fold below
# a fold instead of a recursive parser, and it is what lets the fuzzer build
# the SAME UPat in tinygrad's `UPat` and here from the same text, which is the
# only way the diff means anything.
#
# Each node is eight `;`-separated fields, and EVERY field is spelled rather
# than derived, so the case can express a shape `__init__` builds and one it
# does not:
#
#   op    `-` (None) or `+`-joined op names -- `ADD`, `MUL`, `SUB`, `MAX`,
#         `INDEX`, `CONST`, `NEG`, `CALL`. TWO or more is the `in {1}` arm.
#   name  `-` or a bind name.
#   arg   `-` (None) | `i<n>` the one-element `ATuple` the port reads as an int
#         | `s` a string arg | `t<n>,<n>` a two-element tuple, i.e. the SAME
#         `LArg` payload on the literal arm. `ATuple{[n]}` IS Python's `n`:
#         that correspondence is the port's, and the fuzzer's cases obey it.
#   dt    `-` or `+`-joined dtypes -- `f32`, `i32`, `h`.
#   src   `-` (no src) | `r<k>` a repeat of child k | `t<k>,<k>,..` a tuple
#         | `l<k>,<k>` a list, which is the `permutations` fork.
#   any   1 for `is_any`, which Python also requires a tuple `src` for.
#   aal   1 for `allow_any_len`.
#
# `strict_length` and `required_len` are NOT fields: `UPat.of` derives them
# from `src` and `aal` exactly as `__init__` does, so the case tests that
# derivation too.
