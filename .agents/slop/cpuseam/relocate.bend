# relocate.bend -- THE PORT's OWN `jit_loader`, ON A REAL ELF OBJECT.
#
#   ./bin/bend .agents/slop/cpuseam/relocate.bend -o /tmp/relocate.js
#   bun /tmp/relocate.js r_10_98_4
#
# IT READS THE ELF OBJECT `cc` PRODUCED WITH UPSTREAM's OWN ARGV AND RELOCATES
# IT WITH THE PORT's OWN `runtime/support/elf.bend`:
#   `E.Ehdr.at` -> `E.elf_loader` -> `E.jit_loader`
# AND PRINTS THE RELOCATED IMAGE AS HEX.
#
# ⇒ THE ORACLE IS `elf/<name>.img`: UPSTREAM's OWN `jit_loader`
# (tinygrad/runtime/support/elf.py:52-86) ON THE SAME INPUT, AND THE COMPARER
# IS A BYTE DIFF.
import Base
import ./../../../tinybendygrad/runtime/support/elf.bend as E
import ./../../../tinybendygrad/helpers.bend as H

def nth(xs: List<&1, String>, k: Nat) -> String:
  Maybe.default(&1, String, List.get(&1, String, xs, k), "")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    nm : String = nth(args, 1n)
    ls : List<&2, String> <- H.lines(String.concat([".agents/slop/cpuseam/elf/", nm, ".hex"]))
    +h : String = Maybe.default(&2, String, List.get(&2, String, ls, 0n), "")
    ehdr : E.Ehdr = E.Ehdr.at(h, True{})
    img : E.Img = E.jit_loader(E.elf_loader(h, ehdr, True{}, 1, Nil{}), 0)
    IO.print(E.Img.body(img))
