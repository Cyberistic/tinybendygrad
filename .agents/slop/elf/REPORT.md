# REPORT — two upstream defects on the ELF path, BOTH REPRODUCED, NEITHER FIXED
#
# `tinygrad/` is READ-ONLY to this unit (mid-rebase). Both defects below are in
# `tinygrad/runtime/support/elf.py`, are reproduced by CALLING the real file, and
# are NOT fixed here. The port `tinybendygrad/runtime/support/elf.bend` ports the
# behaviour AS WRITTEN (see "WHAT THE PORT DOES ABOUT IT" in each section).
#
# ===========================================================================
# DEFECT 1 (LIVE, on the currently-broken path) — elf.py:47 reads symbol names
#                          out of the WRONG STRING TABLE.
# ===========================================================================
#
# elf.py:47
#
#   relocs += [(target_image_off + roff,
#               link_sym(_strtab(sh_strtab, sym.st_name), link_libs or [])
#               if sym.st_shndx == 0 else ...
#
# `sym.st_name` is an offset into the string table named by the SYMTAB's
# `sh_link` (ELF spec, gABI "Symbol Table Section"). elf.py resolves it against
# `sh_strtab` -- the SECTION HEADER string table -- instead. It is only correct
# when the two tables coincide, which they do NOT in general.
#
# REPRODUCED, `.agents/slop/elf/rx64.exe` (a REAL linked ELF64 x86-64 executable
# built here with clang+ld.lld, `file` says
#   "ELF 64-bit LSB executable, x86-64 ... statically linked"):
#
#   $ python3 -c "... spy on elf.link_sym, then elf_loader(b, link_libs=[stub])"
#   RAISED: Attempting to relocate against an undefined symbol h_frame
#   link_sym was ASKED for: ['h_frame']
#
# The symbol at that relocation is `_ext_fn` (its symtab entry has
# st_shndx == 0, i.e. undefined, and its real name via `symtab.sh_link` is
# `ext_fn`). `h_frame` is what you get by indexing the SECTION string table at
# the same byte offset -- it lands inside `.eh_frame_hdr`.
#
# PROOF IT IS THE TABLE AND NOT A FIXTURE ARTEFACT -- the whole symtab of
# rx64.exe, both ways, from the same bytes:
#
#   symtab.sh_link = 15 -> '.strtab'          (the correct table)
#   symtab section-header name is '.symtab'
#
#   sym[1]  st_name=1   shndx=65521  viaSHSTRTAB='.text'   viaSTRTAB='x.c'
#   sym[2]  st_name=5   shndx=3      viaSHSTRTAB='t'       viaSTRTAB='tbl'
#   sym[3]  st_name=9   shndx=3      viaSHSTRTAB='nterp'   viaSTRTAB='.LCPI2_0'
#   sym[9]  st_name=18  shndx=1      viaSHSTRTAB='data'    viaSTRTAB='helper'
#   sym[10] st_name=25  shndx=0      viaSHSTRTAB='h_frame' viaSTRTAB='ext_fn'   <== THIS ONE
#   sym[11] st_name=32  shndx=0      viaSHSTRTAB=''        viaSTRTAB='ext_data'
#   sym[12] st_name=41  shndx=1      viaSHSTRTAB='e_hdr'   viaSTRTAB='bump'
#   sym[13] st_name=46  shndx=8      viaSHSTRTAB=''        viaSTRTAB='gdata'
#   sym[14] st_name=52  shndx=1      viaSHSTRTAB='.relro_padding' viaSTRTAB='_start_c'
#   sym[15] st_name=61  shndx=8      viaSHRTRTAB='dding'   viaSTRTAB='msg'
#
# EIGHT of FIFTEEN symbols misresolve. Only the shndx==0 ones matter for a
# relocation, and BOTH of those are wrong ('h_frame' and '' for `ext_fn` and
# `ext_data`), so the load dies at the exact line the task brief calls out.
#
# WHY IT IS INVISIBLE TODAY: `elf_loader` is only ever called on OBJECT FILES
# (`jit_loader(obj, ...)` from ops_cpu.py:21 and ops_amd.py:544), and in a
# relocatable object produced by clang the two string tables COINCIDE -- measured
# on all three of e64.o / ea64.o / n64.o, every symbol resolves identically both
# ways. It is a latent bug that fires the moment anyone feeds elf_loader a
# LINKED image (a .so or an executable), which is what the function is
# nominally for and what `force_section_align` / the fixed-address path exist to
# support.
#
# WHAT THE PORT DOES ABOUT IT: `runtime/support/elf.bend` ports the behaviour AS
# WRITTEN -- `sym_name` reads `sh_strtab` at `st_name` -- because a 1:1 port
# that silently "fixed" it would diverge from the SUT on every linked image and
# the gate would have to explain the divergence. The port says so in its header
# and its row `elf.symtab_strtab_is_shstrtab` names the table the port reads.
#
# ===========================================================================
# DEFECT 2 — elf.py:44 `next(...)` raises StopIteration, not a named error.
# ===========================================================================
#
# elf.py:44
#
#   target_image_off = next(tsh for tsh in sections if tsh.name == trgt_sh_name).header.sh_addr
#
# `trgt_sh_name` is `sh.name[4:]` for SHT_REL and `sh.name[5:]` for SHT_RELA.
# A shared object built by any real linker has `.rela.dyn` and `.rela.plt`, whose
# `[5:]` is `.dyn` and `.plt`. A `.so` here has no `.dyn` section, so the
# generator is exhausted and this raises a bare `StopIteration` out of a
# non-generator function -- which under CPython is a confusing traceback and,
# inside any generator pipeline, a silent `RuntimeError: generator raised
# StopIteration`.
#
# REPRODUCED on real files produced here:
#
#   e2_64.so   (ELF 64-bit LSB shared object, x86-64)
#     StopIteration    # .rela.dyn -> ".dyn", absent
#   e2_a64.so  (ELF 64-bit LSB shared object, ARM aarch64)
#     StopIteration    # same
#
# The object's section table, from the same bytes:
#   4 .rela.dyn   type=4   -> name[5:] = '.dyn'    (no such section)
#   5 .rela.plt   type=4   -> name[5:] = '.plt'    (present, but its own relocs
#                                                     target the PLT)
#   16 .rela.text type=4   -> name[5:] = '.text'   (this one resolves)
#
# So elf_loader works on a `.so` ONLY IF the linker emitted no `.rela.dyn`.
# `-Wl,-Bsymbolic` removes `.rela.dyn` in some cases and does not in others; the
# aarch64 build here has it too.
#
# WHAT THE PORT DOES ABOUT IT: `relocs_of` returns an EMPTY list on a missing
# target rather than raising, which is the only TOTAL answer available in Bend
# (Bend has no exceptions and no `next`), and the row
# `elf.trgtdyn_missing` pins the fact that the target-name derivation yields
# `.dyn`/`.plt` -- so the port does not lose the information, it re-spells the
# refusal as an empty trace. See the port header, "THE TWO UPSTREAM DEFECTS".
#
# ===========================================================================
# DEFECT 3 (SEPARATE OWNER, REPORTED NOT FIXED) — ops_cpu.py:19/21 drops
#                          libobjc from link_libs.
# ===========================================================================
#
# This is `tinygrad/runtime/ops_cpu.py`, owned by ANOTHER unit. Reproduced here
# only as evidence, and the evidence is IN this report rather than in the port:
#
#   $ python3 -c "..."
#   ls_sel_registerName = libSystem:0,libobjc:1,libm:0,libc:0
#   ls_objc_msgSend    = libSystem:0,libobjc:1,libm:0,libc:0
#
# MEASURED, per library, with tinygrad's OWN link_sym:
#   /usr/lib/libSystem.dylib  has 0 hits for `sel_registerName`
#   /usr/lib/libobjc.dylib    has 1 hit
#
# So any kernel whose object file references an objc symbol dies at
# elf.py:13 with `Attempting to relocate against an undefined symbol
# sel_registerName`, because ops_cpu.py:21 builds
# `link_libs=[self.libm, self.rt_lib]` and rt_lib is libSystem. The fix is one
# line in ops_cpu.py (add libobjc to the list) and it is NOT here: another agent
# owns runtime/ops_cpu.py. OWNER: the ops_cpu.py unit.
#
# The rows `ls_*` in elf.bend's gate pin this measurement so that whoever fixes
# ops_cpu.py can see which rows move.
