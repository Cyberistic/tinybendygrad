#!/bin/sh
# elffix.sh -- rebuild the nine real ELF fixtures from source, into
# .agents/slop/elf/. RUN THIS FIRST if the fixtures are missing: they are COMPILED
# ARTIFACTS, not checked in, and the gate is only meaningful against real object
# files.
#
# The three targets are chosen so both word sizes and both Rel/Rela arms appear,
# and so one of them JITS. `j_aarch64.o` is the jitting fixture because the
# aarch64 relocation arms take a raw `tgt` and therefore do not overflow
# `struct.pack("<I", ...)` the way the x86-64 PC32 arm does against a dylib symbol
# address on this arm64 machine.
set -e
D=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/elf
mkdir -p "$D"
cd "$D"

cat > e2.c <<'EOF'
extern void ext_fn(int);
extern int ext_data;
int gdata = 7;
static const double tbl[4] = {1.5, 2.5, 3.5, 4.5};
double helper(double x, int n) { double s=0; for(int i=0;i<n;i++) { s += x*tbl[i&3] + (double)i; ext_fn(i); } return s + ext_data; }
int bump(void) { return gdata + ext_data; }
const char *msg = "hello elf";
EOF

cat > j.c <<'EOF'
extern int ext_data;
int gdata = 7;
int f(int x) { return x * 3 + 1; }
int g(int x) { return f(x) + gdata + ext_data; }
EOF

cat > stub.c <<'EOF'
#ifdef __APPLE__
typedef void (*gotfn)(void);
gotfn _GLOBAL_OFFSET_TABLE_[64] __asm("__GLOBAL_OFFSET_TABLE_") = {0};
#endif
void ext_fn(int i) { (void)i; }
int ext_data = 41;
double dsin(double x) { return __builtin_sin(x); }
EOF

cat > x.c <<'EOF'
extern void ext_fn(int);
extern int ext_data;
int gdata = 7;
static const double tbl[4] = {1.5, 2.5, 3.5, 4.5};
double helper(double x, int n) { double s=0; for(int i=0;i<n;i++) { s += x*tbl[i&3] + (double)i; ext_fn(i); } return s + ext_data; }
int bump(void) { return gdata + ext_data; }
const char *msg = "hello elf";
int _start_c(void) { return (int)helper(1.0,2); }
EOF

# PIC objects: every PROGBITS is at sh_addr == 0, so the ALIGNED-APPEND path runs.
for T in x86_64 aarch64 i386; do
  clang -target $T-unknown-linux-gnu -c -O1 -fPIC e2.c -o ${T}.o 2>/dev/null || \
  clang -target $T-unknown-linux-gnu -c -O1 e2.c -o ${T}.o
done
mv x86_64.o e64.o; mv aarch64.o ea64.o; mv i386.o e32.o
clang -target x86_64-unknown-linux-gnu -c -O1 -fPIC e2.c -o n64.o
clang -target aarch64-unknown-linux-gnu -c -O1 e2.c -o na64.o
clang -target i386-unknown-linux-gnu -c -O1 e2.c -o n32.o
# The non-PIC build has bigger/different sections (no GOT), which is what makes
# n64/na64/n32 differ from e64/ea64/e32 in the WIDTHS the gate relies on.
clang -target x86_64-unknown-linux-gnu -c -O2 e2.c -o n64.o
clang -target aarch64-unknown-linux-gnu -c -O2 e2.c -o na64.o
clang -target i386-unknown-linux-gnu -c -O2 e2.c -o n32.o

# THE JITTING FIXTURE.
clang -target aarch64-unknown-linux-gnu -c -O1 j.c -o j_aarch64.o

# THE TWO REFUSING FIXTURES: a real .so (`.rela.dyn` -> `.dyn` -> StopIteration at
# elf.py:44) and a real linked executable (symbol names out of the WRONG string
# table at elf.py:47). Both are produced by the SYSTEM linker.
clang -target x86_64-unknown-linux-gnu -fuse-ld=lld -shared -nostdlib -fPIC e2.c \
  -o r64.so -Wl,--unresolved-symbols=ignore-all
clang -target x86_64-unknown-linux-gnu -fuse-ld=lld -nostdlib -no-pie \
  -Wl,--emit-relocs,-Ttext=0x400000,--unresolved-symbols=ignore-all x.c -o rx64.exe 2>/dev/null

# The link_libs that make the UNDEFINED symbols resolve.
clang -dynamiclib -O1 stub.c -o libstub.dylib

echo "=== the fixtures, and what file(1) says about each"
ls -la *.o *.so *.exe *.dylib
for f in *.o *.so *.exe; do printf '%-16s %s\n' "$f" "$(file -b "$f" 2>/dev/null | cut -c1-70)"; done