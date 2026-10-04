#!/bin/sh
# elfrun.sh -- build the port, run the gate, diff against CPython. One command.
#
#     sh .agents/slop/elfrun.sh
#
# IT USES A LOCAL COPY OF helpers.bend ONLY IF THE REAL ONE DOES NOT COMPILE, and
# it says so. `tinybendygrad/helpers.bend` is READ-ONLY to this unit and was
# mid-edit from another agent when this was written: `ansistrip.seq_end.at`
# (line 865) calls `ansistrip.seq_end.go` (line 875) and the reverse, which is
# MUTUAL RECURSION and bend 2.0.34 refuses:
#
#   SOME PROOFS FAIL
#   Error:
#   - expected : a filled definition (an unfilled law is a dead claim: live code
#     cannot use it)
#   - observed : ansistrip.seq_end.at
#   Location: ansistrip.seq_end.go
#
# THE PORT ITSELF IMPORTS `./../../helpers.bend` and is unaffected. The shim is a
# byte-for-byte copy of the four defs the port reads, so the gate can run while
# the substrate is broken; when the substrate compiles the shim is not used and
# this script says "real helpers.bend".
set -e
R=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
cd "$R"
mkdir -p .agents/slop/elfprobe

if ./bin/bend tinybendygrad/runtime/support/elf.bend --check-only 2>&1 | head -1 | grep -q "ALL PROOFS CHECK"; then
  echo "== substrate OK, using the REAL helpers.bend"
  python3 .agents/slop/elfbuild.py > tinybendygrad/runtime/support/elf.bend
  ./bin/bend tinybendygrad/runtime/support/elf.bend > .agents/slop/elf_bend.txt
  LANE=interpreted
else
  echo "== helpers.bend does not compile (another agent mid-edit); using the SHIM"
  head -3 tinybendygrad/runtime/support/elf.bend | tail -1
  python3 .agents/slop/elfbuild.py > tinybendygrad/runtime/support/elf.bend
  grep -n "import ./../../helpers.bend as H" tinybendygrad/runtime/support/elf.bend
  cp .agents/slop/elfprobe/helpers_local.bend /dev/null 2>/dev/null || true
  sed 's|import ./../../helpers.bend as H|import ./helpers_local.bend as H|' \
      tinybendygrad/runtime/support/elf.bend > .agents/slop/elfprobe/elf_local.bend
  ./bin/bend .agents/slop/elfprobe/elf_local.bend > .agents/slop/elf_bend.txt
  LANE=shim
fi
echo "== lane: $LANE"
wc -l < .agents/slop/elf_bend.txt

# TWO ORACLE SCRIPTS, ONE EXPECTATION FILE. `elf_rows.py` calls tinygrad's
# elf_loader/jit_loader/link_sym on the nine fixtures; `elf_reloc_probe.py` calls
# the same `jit_loader` on PATCHED copies of one fixture to reach `relocate`, which
# is a closure and is otherwise unreachable. Both emit `name=value` and both are
# read on the SAME side of the diff, so the gate is still one whole-line
# comparison over one namespace. Concatenated, and the EXIT PATH of each is
# checked: a script that emits nothing must not leave the gate green.
python3 .agents/slop/elf_rows.py > .agents/slop/elf_rows.txt || { echo "FATAL: elf_rows.py failed"; exit 1; }
python3 .agents/slop/elf_reloc_probe.py > .agents/slop/elf_reloc_probe.txt || { echo "FATAL: elf_reloc_probe.py failed"; exit 1; }
[ -s .agents/slop/elf_rows.txt ] || { echo "FATAL: elf_rows.py emitted ZERO rows"; exit 1; }
[ -s .agents/slop/elf_reloc_probe.txt ] || { echo "FATAL: elf_reloc_probe.py emitted ZERO rows"; exit 1; }
cat .agents/slop/elf_rows.txt .agents/slop/elf_reloc_probe.txt > .agents/slop/elf_oracle_all.txt
python3 .agents/slop/elfdiff.py .agents/slop/elf_bend.txt .agents/slop/elf_oracle_all.txt