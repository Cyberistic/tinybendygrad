<!-- FROM: tinybendygrad/runtime/support/elf.bend:104 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF. `libc` is `tinygrad/runtime/autogen/libc.py`,
# generated and NOT in this unit's scope; its STRUCT LAYOUTS and its constants
# are named here as the port's own tables and are gated against the oracle
# reading those same constants out of the real module.
#
#   :7   ElfSection                PORTED  `type ElfSection` + name/header/content
#   :9   link_sym                  PORTED  `link_sym`, `type Link`, `Link.pick`
#   :15  elf_loader                PORTED  `elf_loader`
#   :16  the ELFMAG assert         PORTED  `magic_ok` -- upstream asserts `ELFMAG` in `elf_loader`
#   :17  the ecls dict             PORTED  `ecls.name`, `is64`
#   :19  _strtab                   PORTED  `Str.tab`, `Str.at`
#   :21  the Ehdr struct           PORTED  `type Ehdr`, `Ehdr.at`, 13 readers
#   :22  the Shdr array            PORTED  `Shdr.at`, `Sections.of`, 10 readers
#   :23  the shstrtab slice        PORTED  `shstrtab`, `shstrtab_at` -- upstream slices `sh_strtab` in `elf_loader`
#   :24  the ElfSection list       PORTED  `Sections.build`
#   :26  _to_carray                PORTED  `Rel.entsize`, `Rel.count`,
#                                         `Symtab.base`, `Symtab.ent`
#   :27  rel                       PORTED  `Rel.sects(xs, False{})`, `Rel.trgt`
#   :28  rela                      PORTED  `Rel.sects(xs, True{})`, `Rel.trgt`
#   :29  symtab                    PORTED  `Symtab.idx/n/at`, `type Sym`, 6 readers
#   :30  progbits                  PORTED  `Sec.is_progbits` -- upstream collects the PROGBITS sections in `progbits`
#   :33  the image prealloc        PORTED  `Sec.prealloc_of` -- upstream allocates the `image` in `elf_loader`
#   :34-38 the aligned append      PORTED  `Built.of_secs`, `Img.pad`, `Img.place`,
#                                         `Img.write_at`, `Shdr.put_addr`
#   :42-48 the reloc loop          PORTED  `type Rctx`, `Rc.walk`, `Rc.mk`,
#                                         `Trg.off`, `Rc.defined`, `Rc.undefined`
#   tinygrad/runtime/support/elf.py:50 symbol=elf_loader  the return  PORTED  `type ElfImage` + its four readers -- upstream's `relocs`
#   :52  jit_loader                PORTED  `jit_loader`, `Jit.go`, `Jit.step`
#   :56  relocate                  PORTED  `Jit.relocate`..`Jit.relocate8`, the ten
#                                         `Reloc.a_*` arms, `type Sdiff` (the one
#                                         signed-difference representation),
#                                         `type Rloc` (word + appended bytes)
#   :58-81 the two trampolines     PORTED  `Tramp.x86`, `Tramp.arm`, `Tramp.x86_len`,
#                                         `Tramp.arm_len`, `Tramp.x86_ret`,
#                                         `Tramp.arm_ret`
#   :84-85 the 4-byte write-back   PORTED  `Jit.instr` (unpack), `Jit.pack`, and
#                                         `Img.write_at` as the placed write
# END BLOCK
