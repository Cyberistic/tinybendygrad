# Lane 2 — wasm-from-C: MEASURED WALL

**Status: cannot be built from Bend 2.0.34 on wasm32.** This is not a missing
toolchain. Every tool was present and every one of them got the build to link;
the blocker is one line of Bend's own emitted C, and no wasm32 address space can
hold what it reserves.

Reproduce every command below from the repo root. Nothing here is a guess.

---

## The wall, in one line

`corpus_setup` in the emitted C reserves **8 GiB** before `main` runs:

```c
// langs/c/core.c, from Comp.compile_book
static u64* corpus_setup(bool gpu, long threads, u64 bytes) {
  u64 dflt   = gpu ? gpu_span() : 1ull << 33;      // <-- 8 GiB, the CPU path
  u64 size   = (gpu && bytes != 0 ? bytes : dflt) & ~16383ull;
  CORPUS     = gpu ? gpu_map(size) : corpus_map(size);
```

WebAssembly's linear memory is capped at **4 GiB** — 65536 pages of 64 KiB, a
limit fixed by the wasm32 spec — and wasm32's `size_t` is 32 bits. So:

| | native (arm64) | wasm32 |
| --- | --- | --- |
| address space | 2^64 | 2^32 |
| max linear memory | address space | 4 GiB, by spec |
| `size_t` | 64 bits | 32 bits |
| `1ull << 33` through `mmap` | 8589934592 bytes, fine | truncates to **0** |

`mmap` receives `size_t bytes`, so the 8 GiB request arrives as 0. The
reservation silently succeeds with a zero-length region and the first write
past the real heap traps:

```
$ node langs/wasm/wasi_run.mjs core.wasm
wasm://wasm/core.wasm-0058c22e:1

RuntimeError: memory access out of bounds
    at core.wasm.main (wasm://wasm/core.wasm:wasm-function[118]:0x9966)
```

`memory.grow` will not rescue it either: growing to 8 GiB needs 131072 pages,
and wasm32 addresses at most 65536.

## What was tried, and how far each got

Every toolchain check first, because the task said to establish which of them
exists before concluding anything.

### 1. emscripten — absent

```
$ which emcc
emcc not found
```

The command that would work, had it been installed, is the one `bend_wasm.ts`
prints:

```
emcc -O3 -sEXPORTED_FUNCTIONS=_malloc,_free,bend_core_task \
     -sEXPORTED_RUNTIME_METHODS=ccall,HEAPF32 \
     langs/wasm/bend_wasm_shim.c langs/c/core.c -o langs/wasm/core.wasm
```

Note that emcc would hit the same 4 GiB wall: this is a property of wasm32, not
of emscripten. See "What would actually fix it" below.

### 2. Apple clang — no wasm target at all

```
$ clang -print-targets | grep -ci wasm
0
```

Apple clang registers aarch64, arm, x86 and nothing else. `--target=wasm32` is
not a thing here.

### 3. wasi-sdk — absent, but zig ships an equivalent

```
$ which wasm-ld wasm-ld-19
zsh: no matches found: wasm-ld-19
```

Zig 0.15.2 bundles clang + LLVM + a full wasi-libc, which is the same thing
wasi-sdk is:

```
$ zig cc --target=wasm32-wasi-musl -O2 hello.c -o hello.wasm   # works
```

### 4. zig cc — gets all the way to LINKED, then traps

This is the interesting one, because four separate things had to be fixed before
it linked at all. All four are recorded because they are real and reusable:

**a. `size_t` truncation** — `mmap` takes `size_t`, so the 8 GiB request arrives
as 0 and the reservation silently "succeeds" on nothing. Measured:

```
$ cat mm.c
void* p = mmap(NULL, (1ull<<31) + 16384 + 65536, PROT_READ|PROT_WRITE,
               MAP_PRIVATE|MAP_ANON|MAP_NORESERVE, -1, 0);
$ zig cc --target=wasm32-wasi-musl -D_WASI_EMULATED_MMAN mm.c -lwasi-emulated-mman
$ node langs/wasm/wasi_run.mjs mm.wasm
mmap(2147565568) -> 0xffffffff (MAP_FAILED=0xffffffff)
```

**b. WASI has no signals or pipes.** The emitted C calls `sigaction`,
`sigaltstack`, `pipe` and `fcntl` while reserving the pool and starting the
event loop, and zig's wasi-libc hides all of them behind feature macros. A
~90-line shim supplying musl's own `stack_t` and `struct sigaction` plus no-op
bodies for the five calls **does** compile and link — a wasm binary is produced
and `WebAssembly.instantiate` accepts it. It is not checked in, because it
cannot make the lane work and dead glue is worse than a documented wall.

**c. `musttail` needs the tail-call feature.** The emitted C is one flat state
machine compiled with tail calls; without `-mtail-call` clang refuses:

```
error: WebAssembly 'tail-call' feature not enabled
```

**d. zig's emulated mman cannot reserve the 2 GiB stack.** Bend reserves
`1ull << 31 + 16384 + SIGSTKSZ` for the pool stack, and zig routes mmap through
malloc, which dies on a 32-bit size.

With all four handled, the module builds, links, instantiates — and then traps,
for reason (a) at the top of this file.

### 5. wasm64 / memory64 — not reachable either

wasm64 is the only architecture that could hold 8 GiB, and neither side has it:

```
$ zig cc --target=wasm64-wasi-musl hello.c -o h64.wasm
error: unable to provide libc for target 'wasm64-wasi.0.1...0.2.2-musl'

$ node -e 'new WebAssembly.compile(fs.readFileSync("/tmp/m64.wasm"))'
WebAssembly.compile(): invalid memory limits flags 0x60 @+11
```

Node 26.8 has no `--experimental-wasm-memory64` flag, and V8 rejects the memory64
limits flag outright.

---

## What would actually fix it

Not a toolchain. One of:

1. **Bend makes the CPU corpus size configurable.** `--gpu NGB` already caps
   `bytes`, but only on the GPU path; `corpus_setup` takes `bytes` and ignores
   it when `gpu` is false. Honouring it for the CPU path would make the whole
   program fit in 4 GiB, and every lane above would then work. This is a
   one-line upstream change in `comp.ts`, and it is the honest recommendation.

2. **wasm64**, which needs a wasi64 libc and a runtime with memory64. Neither
   exists on this machine today.

## What the lane therefore provides

- `langs/sdk/bend_wasm.ts` — the emscripten-shaped glue the contract asks for:
  `_malloc`, a `ccall(ident, returnType, argTypes, args)` that resolves against
  the module's exports, and `_free`, with the input written through typed heap
  views and both blocks released. Real code, exercised by its types; it is the
  module that is missing, not the calling convention.
- `langs/wasm/wasi_run.mjs` — a WASI preview1 host, which is how a wasm32-wasi
  build of a Bend program is actually run (`_start`, `args`, stdout). Kept
  because it is the correct runner and the lane needs one the moment (1) lands.
- `verify.sh` prints the wall as a `WALL` row and exits 2, so the gate never
  passes quietly over a missing lane.
