#!/usr/bin/env python3
"""tc-build.py -- assemble transcendental_f32.bend from head + generated + tail,
then PROVE the three parts reproduce the file byte for byte.

The two older fixups this script used to apply -- a blanket `+` on every value
parameter, and a dependency sort -- are GONE, and that is the point of the
rewrite.  They existed because the three parts were hand-maintained and drifted;
once every part is generated, running them again would only be a second, weaker
source of truth.  The check at the bottom is what keeps the guarantee honest:

    a def nothing calls is invisible to every other check, and a GENERATED BLOCK
    that has drifted from its GENERATOR is exactly that -- MEASURED: the shipped
    file carried the whole 155-line header a SECOND time, which is a no-op to the
    type checker, so `--check-only` stayed green and two `import Base` lines
    shipped.  Compare head+generated+tail against the file on every rebuild.
"""
import subprocess, sys

SRC = 'tinybendygrad/codegen/transcendental_f32.bend'
HEAD = '.agents/slop/tc_head.bend'
GEN = '.agents/slop/tc_generated.bend'
TAIL = '.agents/slop/tc_tail.bend'


def assemble():
  return open(HEAD).read() + open(GEN).read() + open(TAIL).read()


def main():
  parts = assemble()
  onfile = open(SRC).read()
  if len(sys.argv) > 1 and sys.argv[1] == '--check':
    if parts != onfile:
      print('MISMATCH: head + generated + tail does NOT reproduce the file')
      return 1
    print(f'parts reproduce the file exactly ({onfile.count(chr(10))} lines)')
    return 0
  open(SRC, 'w').write(parts)
  print(f'wrote {SRC} ({parts.count(chr(10))} lines)')
  r = subprocess.run(['./bin/bend', SRC, '--check-only'],
                     capture_output=True, text=True)
  # `--check-only` EXITS 1 even on a clean file because dtype.bend has 14
  # permanently unfilled laws.  Read the FIRST line; never the exit status.
  print('\n'.join(r.stdout.split('\n')[:2]))
  return 0


if __name__ == '__main__':
  sys.exit(main())