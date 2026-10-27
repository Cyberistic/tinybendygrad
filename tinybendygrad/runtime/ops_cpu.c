// ops_cpu.c -- THE CPU DEVICE's SEAM, IN UPSTREAM's OWN SHAPE.
//
// UPSTREAM's `CPUProgram` (tinygrad/runtime/ops_cpu.py:18-46) DOES FOUR THINGS,
// IN THIS ORDER:
//
//   1. `cc` COMPILES THE C TO AN ELF OBJECT (support/compiler_cpu.py:21-22):
//      `[cc, '-c', '-x', 'c', '-O2', '-fPIC', '-ffreestanding', '-fno-math-errno',
//      '-nostdlib', '-fno-ident', '--target=<arch>-none-unknown-elf', *args, '-',
//      '-o', '-']` -- THE SOURCE ON STDIN, THE OBJECT ON STDOUT.
//   2. `jit_loader` (support/elf.py:52-86) RELOCATES THE OBJECT INTO AN IMAGE.
//   3. AN ANONYMOUS RWX REGION IS MMAPPED (ops_cpu.py:29-32) AND THE IMAGE IS
//      COPIED INTO IT, WITH `MAP_JIT` AND `pthread_jit_write_protect_np` AROUND
//      THE WRITE ON APPLE SILICON (ops_cpu.py:33, :35), WHERE RWX PAGES ARE
//      UNREPRESENTABLE (SPRR).
//   4. THE FUNCTION IS CALLED WITH 64-BIT POINTERS (ops_cpu.py:61).
//
// ⇒ STEP 2 IS THE PORT's OWN `runtime/support/elf.bend:1816` `jit_loader`, SO IT
// IS NOT AN EFFECT: THE BEND SIDE RELOCATES AND THE C SIDE NEVER SEES AN ELF.
// ⇒ STEPS 1 AND 3-4 ARE EFFECTS, AND THEY ARE TWO EFFECTS BECAUSE UPSTREAM's
// ORDER HAS THE RELOCATION BETWEEN THEM.
//
// ⇒ AND THE FIRST VERSION OF THIS FILE DID NOT DO THIS. IT COMPILED TO A SHARED
// OBJECT AND `dlopen`ed IT, WHICH IS NOT UPSTREAM's SHAPE. MEASURED: ON THIS
// MACHINE THAT PATH DOES NOT RUN AT ALL. `dlopen` BLOCKS IN THE KERNEL'S
// CODE-SIGNING PATH (`fcntl(F_ADDFILESIGS)`, VISIBLE IN A `sample` OF THE
// STUCK PROCESS) WHILE `/usr/libexec/syspolicyd` SPINS AT 100% CPU AND ITS LOG
// SAYS "Unable to initialize qtn_proc: 3"; A `dlopen` OF A SYSTEM DYLDIB IS
// INSTANT AND A `dlopen` OF A LOCALLY-BUILT ONE HANKS, AND IT HANGS FOR A FILE
// THAT WAS ASSESSED SUCCESSFULLY EARLIER, SO IT IS NOT THE FILE. THE MMAP PATH
// BELOW ASKS THE DYNAMIC LOADER NOTHING.
//
// ⇒ THE BUFFERS CROSS AS HEX. A Bend `List<String>` IS A CONSTRUCTOR CHAIN AND
// BUILDING ONE IN C IS NOT A THING TO WRITE; ONE HEX STRING OF THE CONCATENATED
// BUFFERS, WITH A COMMA-SEPARATED LIST OF THEIR BYTE SIZES, IS. THE HEX IS THE
// PORT's OWN `Blob`/`Hex` SPELLING (runtime/support/elf.bend), SO THE SAME BYTES
// CROSS THE SEAM EITHER WAY.
//
// ⇒ THE ARGV CROSSES AS ONE "\n"-JOINED STRING, BECAUSE THE ARGV IS THE PORT's
// OWN SPELLING: `runtime/support/compiler_cpu.bend:268`
// `ClangCompiler.compile_argv(cc, arch)` IS UPSTREAM's argv, SPELLED IN BEND.
// THE C SIDE SPLITS IT AND EXECS IT; IT DOES NOT BUILD AN ARGV OF ITS OWN.

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <pthread.h>
#include <sys/mman.h>
// MAP_JIT IS NOT IN THE HEADERS BEFORE MACOS 11; ops_cpu.py:26 SAYS THE SAME
// ("MAP_JIT is added to mmap module in python 3.13") AND SPELLS THE NUMBER.
#define CPU_MAP_JIT 0x0800
// THE REAL SIGNATURE IS `void pthread_jit_write_protect_np(int enabled)` -- ONE
// ARGUMENT, AND IT TOGGLES THE PROTECTION FOR THE WHOLE PROCESS, NOT FOR AN
// ADDRESS (pthread.h:588). MEASURED: A VERSION THAT PASSED THE ADDRESS AS THE
// FLAG LEFT THE PAGES READ-ONLY AND THE WRITE DIED WITH SIGBUS.
extern void __clear_cache(void *start, void *end);
#else
#define CPU_MAP_JIT 0
#endif

#define CPU_MAX_BUFS 16
#define CPU_MAX_ARGV 32
// THE OBJECT AND THE CHATTER ARE BOUNDED, AND THE BOUNDS ARE DRAINED, NOT
// TRUNCATED: A COMPILER THAT WRITES MORE THAN A PIPE'S BUFFER MUST NOT BLOCK
// ON A PIPE NOBODY READS.
#define CPU_MAX_OUT (1u << 20)
#define CPU_MAX_ERR 4096

static int cpu_hex_val(int c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

static int cpu_hex_decode(const char* h, u64 n, unsigned char* out, u64 cap) {
  if (n % 2 != 0) return EINVAL;
  for (u64 i = 0; i + 1 < n; i += 2) {
    int a = cpu_hex_val((unsigned char)h[i]), b = cpu_hex_val((unsigned char)h[i+1]);
    if (a < 0 || b < 0 || i / 2 >= cap) return EINVAL;
    out[i / 2] = (unsigned char)((a << 4) | (b));
  }
  return 0;
}

static char* cpu_hex_encode(const unsigned char* b, u64 n) {
  static const char* d = "0123456789abcdef";
  char* out = io_mem(malloc(2 * (size_t)n + 1));
  for (u64 i = 0; i < n; i++) {
    out[2 * i] = d[b[i] >> 4];
    out[2 * i + 1] = d[b[i] & 15];
  }
  out[2 * n] = 0;
  return out;
}

// THE SIZES: "n,n,n" IN DECIMAL. THE COUNT IS THE NUMBER OF BUFFERS.
static int cpu_sizes(const char* zs, u64 n, u64* out, int* count) {
  int k = 0;
  u64 i = 0;
  while (i < n && k < CPU_MAX_BUFS) {
    u64 v = 0;
    int any = 0;
    while (i < n && zs[i] >= '0' && zs[i] <= '9') {
      v = v * 10 + (u64)(zs[i] - '0');
      i += 1;
      any = 1;
    }
    if (!any) return EINVAL;
    out[k++] = v;
    if (i < n) {
      if (zs[i] != ',') return EINVAL;
      i += 1;
    }
  }
  if (i != n || k == 0) return EINVAL;
  *count = k;
  return 0;
}

// THE ARGV, SPLIT ON "\n". A PATH CANNOT CONTAIN A NEWLINE, AND A FLAG CANNOT
// EITHER, SO THE JOIN IS UNAMBIGUOUS.
static int cpu_argv_split(const char* j, u64 n, char** argv, int max) {
  int k = 0;
  u64 i = 0;
  while (k < max - 1) {
    u64 e = i;
    while (e < n && j[e] != '\n') e += 1;
    char* s = io_mem(malloc((size_t)(e - i) + 1));
    memcpy(s, j + i, (size_t)(e - i));
    s[e - i] = 0;
    argv[k++] = s;
    if (e >= n) break;
    i = e + 1;
  }
  argv[k] = NULL;
  return k;
}

// A PIPE'S READ END, DRAINED INTO A BUFFER. `keep` IS HOW MANY BYTES ARE KEPT;
// THE REST ARE DRAINED AND DROPPED, BECAUSE A COMPILER THAT WRITES MORE THAN
// THE PIPE'S BUFFER MUST NOT BLOCK ON A PIPE NOBODY READS.
static u64 cpu_drain(int fd, unsigned char* out, u64 cap, u64 keep) {
  u64 got = 0, kept = 0;
  unsigned char buf[4096];
  while (1) {
    ssize_t k = read(fd, buf, sizeof buf);
    if (k <= 0) break;
    for (ssize_t i = 0; i < k; i++) {
      if (kept < keep && out != NULL) out[kept++] = buf[i];
    }
    got += (u64)k;
  }
  return got;
}

// EFFECT 1 -- UPSTREAM's STEP 1: `cc` THE C TO AN ELF OBJECT.
static Term cpu_compile_run(Env e, Term* f, IoWork* w) {
  u64 slen = 0, alen = 0;
  char* src = io_cstr(e, f[0], &slen);
  char* joined = io_cstr(e, f[1], &alen);

  char* argv[CPU_MAX_ARGV];
  int n = cpu_argv_split(joined, alen, argv, CPU_MAX_ARGV);
  if (n == 0) return io_fail(e, EINVAL, "cpu compile: the argv is empty");

  int in[2], outp[2], errp[2];
  if (pipe(in) != 0) return io_fail(e, errno, "cpu compile: pipe failed");
  if (pipe(outp) != 0) { close(in[0]); close(in[1]); return io_fail(e, errno, "cpu compile: pipe failed"); }
  if (pipe(errp) != 0) {
    close(in[0]); close(in[1]); close(outp[0]); close(outp[1]);
    return io_fail(e, errno, "cpu compile: pipe failed");
  }
  pid_t pid = fork();
  if (pid < 0) return io_fail(e, errno, "cpu compile: fork failed");
  if (pid == 0) {
    dup2(in[0], 0);
    dup2(outp[1], 1);
    dup2(errp[1], 2);
    close(in[0]); close(in[1]); close(outp[0]); close(outp[1]); close(errp[0]); close(errp[1]);
    execvp(argv[0], argv);
    _exit(127);
  }
  close(in[0]); close(outp[1]); close(errp[1]);

  size_t written = 0;
  while (written < slen) {
    ssize_t k = write(in[1], src + written, slen - written);
    if (k <= 0) break;
    written += (size_t)k;
  }
  close(in[1]);

  unsigned char* obj = io_mem(malloc(CPU_MAX_OUT + 1));
  u64 objlen = cpu_drain(outp[0], obj, CPU_MAX_OUT, CPU_MAX_OUT);
  close(outp[0]);
  char err[CPU_MAX_ERR + 1];
  u64 errlen = cpu_drain(errp[0], (unsigned char*)err, CPU_MAX_ERR, CPU_MAX_ERR);
  close(errp[0]);
  err[errlen < CPU_MAX_ERR ? errlen : CPU_MAX_ERR] = 0;

  int status = 0;
  while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    free(obj);
    return io_fail(e, ECHILD, errlen ? err : "cpu compile: cc failed");
  }
  if (objlen == 0) {
    free(obj);
    return io_fail(e, ECHILD, "cpu compile: cc produced nothing");
  }

  char* hex = cpu_hex_encode(obj, objlen);
  free(obj);
  Term r = io_str(e, hex, 2 * objlen);
  free(hex);
  return io_done(e, r);
}

// EFFECT 2 -- UPSTREAM's STEPS 3 AND 4: MMAP THE IMAGE AND CALL IT.
static Term cpu_exec_run(Env e, Term* f, IoWork* w) {
  u64 ilen = 0, blen = 0, zlen = 0;
  char* ihex = io_cstr(e, f[0], &ilen);
  char* bhex = io_cstr(e, f[1], &blen);
  char* zs = io_cstr(e, f[2], &zlen);

  u64 sizes[CPU_MAX_BUFS];
  int count = 0;
  if (cpu_sizes(zs, zlen, sizes, &count) != 0) {
    return io_fail(e, EINVAL, "cpu exec: bad buffer sizes");
  }
  u64 total = 0;
  for (int i = 0; i < count; i++) total += sizes[i];
  if (blen != 2 * total) {
    return io_fail(e, EINVAL, "cpu exec: buffer hex does not match the sizes");
  }
  unsigned char* data = io_mem(malloc((size_t)total + 1));
  if (cpu_hex_decode(bhex, blen, data, total) != 0) {
    return io_fail(e, EINVAL, "cpu exec: bad buffer hex");
  }

  u64 imglen = ilen / 2;
  if (ilen % 2 != 0 || imglen == 0) {
    return io_fail(e, EINVAL, "cpu exec: bad image hex");
  }
  unsigned char* img = io_mem(malloc((size_t)imglen + 1));
  if (cpu_hex_decode(ihex, ilen, img, imglen) != 0) {
    return io_fail(e, EINVAL, "cpu exec: bad image hex");
  }

  // THE MMAP. UPSTREAM MAPS `len(obj.lib)` AND WRITES THE IMAGE INTO IT
  // (ops_cpu.py:29-32); THE IMAGE IS WHAT IS EXECUTED, SO THE IMAGE'S LENGTH
  // IS WHAT IS MAPPED HERE.
  void* mem = mmap(NULL, (size_t)imglen, PROT_READ | PROT_WRITE | PROT_EXEC,
                   MAP_ANON | MAP_PRIVATE | CPU_MAP_JIT, -1, 0);
  if (mem == MAP_FAILED) return io_fail(e, errno, "cpu exec: mmap failed");
#if defined(__APPLE__)
  pthread_jit_write_protect_np(0);
#endif
  memcpy(mem, img, (size_t)imglen);
#if defined(__APPLE__)
  pthread_jit_write_protect_np(1);
  __clear_cache(mem, (char*)mem + imglen);
#endif
  free(img);

  void* ptrs[CPU_MAX_BUFS];
  u64 off = 0;
  for (int i = 0; i < count; i++) {
    ptrs[i] = data + off;
    off += sizes[i];
  }
  // THE CALL. UPSTREAM'S SIGNATURE IS `void name(float*, ...)`; THE KERNELS THE
  // PORT RENDERS TAKE UP TO EIGHT POINTERS.
  typedef void (*CpuKernel)(void*, void*, void*, void*, void*, void*, void*, void*);
  CpuKernel fn = (CpuKernel)mem;
  switch (count) {
    case 1: fn(ptrs[0], 0, 0, 0, 0, 0, 0, 0); break;
    case 2: fn(ptrs[0], ptrs[1], 0, 0, 0, 0, 0, 0); break;
    case 3: fn(ptrs[0], ptrs[1], ptrs[2], 0, 0, 0, 0, 0); break;
    case 4: fn(ptrs[0], ptrs[1], ptrs[2], ptrs[3], 0, 0, 0, 0); break;
    case 5: fn(ptrs[0], ptrs[1], ptrs[2], ptrs[3], ptrs[4], 0, 0, 0); break;
    case 6: fn(ptrs[0], ptrs[1], ptrs[2], ptrs[3], ptrs[4], ptrs[5], 0, 0); break;
    case 7: fn(ptrs[0], ptrs[1], ptrs[2], ptrs[3], ptrs[4], ptrs[5], ptrs[6], 0); break;
    default: fn(ptrs[0], ptrs[1], ptrs[2], ptrs[3], ptrs[4], ptrs[5], ptrs[6], ptrs[7]); break;
  }

  char* out = cpu_hex_encode(data, total);
  Term r = io_str(e, out, 2 * total);
  free(out);
  return io_done(e, r);
}

static void __attribute__((constructor)) cpu_use(void) {
  io_eff(CID(Cpu.compile), cpu_compile_run);
  io_eff(CID(Cpu.exec), cpu_exec_run);
}
