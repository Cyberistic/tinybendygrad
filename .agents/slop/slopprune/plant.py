#!/usr/bin/env python3
"""What `gates/slop-prune-census.py` must not be able to cite, BY PATH.

This file is loaded by `gates/slop-prune-census.py:excluded()` and by nothing else. It is the same
shape as `checks/slop-declare.py:plant_exclusions()` loading `.agents/slop/declare/plant.py`, and as
`checks/oracle-txt-census.py` loading `.agents/slop/oracletxt/plant.py`: **the exclusion follows the
plant if the plant moves, and there is no second copy in the gate to rot into a different answer.**

WHY IT IS NEEDED, AND IT IS NOT DEFENSIVENESS. `gates/slop-prune-census.py`'s own docstring contains
the string `.agents/slop/` 20 times, and that string is an ANCESTOR DIRECTORY OF EVERY FILE IN THE
POPULATION. Without this exclusion the census would classify all 6 341 files LOAD-BEARING on the
strength of the instrument's own prose -- a population that contains its own author. That is
`checks/sweep.py`'s `LIVE_UNITS` failure inverted: there, finished units were invisible to the guard;
here, the guard would be blinded by itself.

The census names `.agents/slop/slopprune/` rather than anything else, and that prefix is the
population's OWN evidence directory. If the census moves its evidence, this list must move with it,
which is why it lives here and is read from here.
"""


def excluded() -> frozenset[str]:
    """Path prefixes no citation may charge to a file, as a caller-visible string set."""
    return frozenset({
        ".agents/slop/slopprune/",   # this census's own rows, plant and report
        "gates/slop-prune-census.py",  # the census itself
    })
