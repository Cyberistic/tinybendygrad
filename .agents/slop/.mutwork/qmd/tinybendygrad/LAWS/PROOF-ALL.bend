# PROOF-ALL.bend -- the aggregate gate: every law in ../LAWS.bend discharged.
#
# P1 is the shape half (../PROOF.bend); P2 is the ALU/dtype half
# (../PROOF2.bend). Neither half is a complete proof on its own -- each leaves
# the other's laws open -- so this file is the one command that must pass:
#
#     ./bin/bend bendgrad/LAWS/PROOF-ALL.bend      # ALL PROOFS CHECK
#
# The import aliases are names, not wiring: bend discharges a law by a def of
# the same name anywhere in the book, so the two halves simply have to meet in
# one book.

import Base
import ../PROOF.bend as P1
import ../PROOF2.bend as P2
