# tinybendygrad/renderer/amd/__init__.bend -- port of tinygrad/renderer/amd/__init__.py
#
# not an empty marker. upstream is 75 lines and they are declared out of scope.
#
# `tinygrad/renderer/amd/__init__.py` is AMD instruction-format DETECTION and DECODING:
# `_VARIANT_SRC0` (the SDWA/DPP16 variant words), `_matches()` over a `Inst` subclass's
# `FixedBitField`s, and the `EnumBitField`/`defines()` machinery that turns a byte
# pattern into an AMD instruction `Inst`. It reads AMD ISA bit layouts and nothing else.
#
# WHY IT IS NOT PORTED -- the scope decision this file obeys, `.agents/TODO.md`,
# "Out of scope -- needs hardware we do not have": that section names
# `renderer/amd/` by path and says these get a documented not-ported stub, with their
# tests excluded by tinygrad's own hardware markers rather than by us.
#
# - and the siblings under this directory are ported, which is why this file exists
# rather than the directory being skipped: `dsl.bend`, `elf.bend`, `generate.bend` and
# `sqtt.bend` are here, and the decoder is the one piece that needs an AMD device to
# mean anything. A missing file would make that distinction invisible.
