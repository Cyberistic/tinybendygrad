"""pytest plugin: pin DEV=BEND to the PRE-FIX executor binary, for a true before/after of the SAME tree.

The executor is `functools.cache`d on ops_python.bend's mtime+size, so the edited file no longer maps
to the binary it had yesterday.  This restores that mapping for one process's worth of tests.

usage: PYTHONPATH=.agents/slop/bendwire DEV=BEND .venv/bin/python -m pytest <file> -p oldexec
"""
import pathlib

OLD = pathlib.Path.home() / "Library/Caches/tinygrad" / "bend-executor-970cbc1d5f288c9a"


def pytest_configure(config):
    import tinygrad.runtime.ops_bend as ob
    ob.executor = lambda: OLD
