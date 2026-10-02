# helpers_local.bend -- WORKAROUND READER, NOT A DESIGN.
#
# tinybendygrad/helpers.bend is READ-ONLY to this unit and is CURRENTLY
# uncompilable: `ansistrip.seq_end.at` (line 865) calls `ansistrip.seq_end.go`
# (line 875) and `ansistrip.seq_end.go` calls `ansistrip.seq_end.at`, which is
# MUTUAL RECURSION and bend 2.0.34 refuses:
#
#   SOME PROOFS FAIL
#   Error:
#   - expected : a filled definition (an unfilled law is a dead claim: live code
#     cannot use it)
#   - observed : ansistrip.seq_end.at
#   Location: ansistrip.seq_end.go  (helpers.bend:869)
#
# Reproduced three times in a row, so it is not a transient.
#
# Nothing here is used by the PORT. The port imports `helpers.bend` and only
# reads `H.getbits`, `H.i2u`, `H.ceildiv_u32` and `H.round_up_u32` from it.
# This file is a byte-for-byte copy of those four (plus their two
# dependencies) so the port can be COMPILED and GATED while that is true.
#
# DELETE THIS FILE AND FLIP elf.bend's import BACK the moment helpers.bend
# compiles. The import line in elf.bend is the only place to change, and
# .agents/slop/elf/REPORT.md records this as a workaround, not a decision.

def div0(zero: Bool, v: U32) -> U32:
  match zero:
    case True{}: 0
    case False{}: v

def ceildiv_u32(+num: U32, +amt: U32) -> U32:
  div0(U32.is_zero(amt), U32.add(U32.div(num, amt), Bool.to_u32(U32.is_ne(U32.mod(num, amt), 0))))

def round_up_u32(num: U32, +amt: U32) -> U32:
  U32.mul(ceildiv_u32(num, amt), amt)

def bit_mask(w: Nat) -> U32:
  U32.sub(U32.shln(1, w), 1)

def getbits(value: U32, +start: Nat, end: Nat) -> U32:
  U32.and(U32.shrn(value, start), bit_mask(Nat.add(Nat.sub(end, start), 1n)))

def i2u(neg: Bool, bits: Nat, value: U32) -> U32:
  match neg:
    case True{}: U32.add(U32.shln(1, bits), value)
    case False{}: value
