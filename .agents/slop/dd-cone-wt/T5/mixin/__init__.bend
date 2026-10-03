# tinybendygrad/mixin/__init__.bend -- port of tinygrad/mixin/__init__.py
#
# `tinygrad/mixin/__init__.py` is ZERO BYTES. There is no name to expose, no
# re-export to honour, and the package boundary is held by the same rule as
# `viz/__init__.py`: a missing file reads as "not done", and an empty upstream
# with no bend reads as "skipped", which is a different and wrong claim.
#
# Submodule imports in tinygrad (e.g. `from tinygrad.mixin import movement`)
# resolve in Bend by path (`import ./movement.bend`), which is the same
# mechanism `viz/cli.bend` uses against `serve.bend`. So this file is a
# marker and nothing more -- re-exports would be the only thing here that
# is not in the upstream file, and a re-export of nothing is a tautology.
