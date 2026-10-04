
// Imports
// =======

// The Objective-C headers take #include, not #import: a build
// (-o) reads an #import as the framework of an effect.

#pragma clang fp contract(off)

#if defined(__CUDACC_RTC__)
#define BEND_RTC 1
#endif

#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
#elif !defined(BEND_RTC)
#ifdef __APPLE__
#define _DARWIN_UNLIMITED_SELECT
#else
#define _GNU_SOURCE
#endif
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>
#include <time.h>
#include <poll.h>
#include <sys/select.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
#ifdef __OBJC__
#include <Metal/Metal.h>
#include <Foundation/Foundation.h>
#elif BEND_CUDA
#include <cuda.h>
#include <nvrtc.h>
#include <fcntl.h>
#include <sys/stat.h>
#endif
#endif

// Dialect
// =======

// Metal needs coherent(device) (MSL 3.2), or M1-class parts lose stores
// across the threadgroups of a dispatch. CUDA keeps plain data cacheable
// in L1: lanes hand off through a32 and FENCE. Only clang 19+ has both
// preserve_none and preserve_most, and compiles preserve_most soundly. A
// segment is a case of the device's switch; on the host, a preserve_none
// function (WL_SIG) entered by musttail, its words fresh at WL_OPEN.

#ifdef __METAL_VERSION__
#if __METAL_VERSION__ >= 320
#define DEV     coherent(device) device
#else
#define DEV     device
#endif
#define THR     thread
#define TG      threadgroup
#define INLINE  inline
#define OUTLINE static
#define CONSTV  constant
#define DEVICE  1
#define CLZ(x)  clz(x)
#define FENCE() atomic_thread_fence(mem_flags::mem_device, memory_order_seq_cst)
#define BAR()   threadgroup_barrier(mem_flags::mem_threadgroup)
#define BARD()  threadgroup_barrier(mem_flags::mem_device \
  | mem_flags::mem_threadgroup)
#else
#define DEV
#define THR
#define TG
#define INLINE  static inline
#define CONSTV  static const
#ifdef BEND_RTC
#define OUTLINE static __attribute__((noinline))
#define DEVICE  1
#define CLZ(x)  (u32)__clz((int)(x))
#define FENCE() __threadfence()
#define BAR()   __syncthreads()
#define BARD()  \
  { __threadfence(); __syncthreads(); }
#else
#if __has_attribute(preserve_none) && __has_attribute(preserve_most)
#define PRESERVE(A) __attribute__((A))
#else
#define PRESERVE(A)
#endif
#define OUTLINE static __attribute__((noinline, cold)) PRESERVE(preserve_most)
#define DEVICE  0
#define CLZ(x)  (u32)__builtin_clz(x)
#define FENCE() ((void)0)
#endif
#endif
#define FAR static __attribute__((noinline))

#if DEVICE
#define LOCK(l)
#define UNLOCK(l)
#define WL_CASE(F) case F:
#define WL_OPEN    {
#define WL_JMP(F)  { fid = (F); break; }
#define WL_DYN     WL_JMP
#else
#define LOCK(l)    while (__atomic_exchange_n(&(l), 1, __ATOMIC_ACQUIRE)) {}
#define UNLOCK(l)  __atomic_store_n(&(l), 0, __ATOMIC_RELEASE)
#define WL_FN      static PRESERVE(preserve_none) __attribute__((noinline)) Term
#define WL_CASE(F) WL_FN WL_##F(WL_SIG)
#define WL_OPEN    { WL_BANK u32 rn;
#define WL_JMP(F)  __attribute__((musttail)) return WL_##F(WL_ALL)
#define WL_DYN(F)  __attribute__((musttail)) return wl_tab[F](WL_ALL)
#endif
#define WL_SPIN     for (;;) { if (err_spun(e.mem, &wpoll)) { return 0; }
#define WL_SPUN     } break;
#define WL_AGAIN(F) continue

#define LANE_STEP (DEVICE ? (long)CUBE : 1)
#define STK(I)    sp[(long)(I) * LANE_STEP]

#define WL_RETN(N)  { rn = (N); sp -= LANE_STEP; WL_DYN((u32)STK(0)); }
#define WL_CONT     STK(-3)
#define WL_IDX      STK(-2)
#define WL_POPN(N)  sp -= N * LANE_STEP
#define WL_PUSHN(N) sp += N * LANE_STEP
#define WL_FRAME(T) \
  u64 wtl = task_tail(T); \
  u64 wtw = e.mem[wtl + 1]; \
  STK(0) = e.mem[wtl]; \
  STK(1) = (wtw >> 32) & 0xFFFF; \
  STK(2) = FID_EXIT; \
  sp += 3 * LANE_STEP;
#define WL_ARGS(A, N) \
  for (u32 wi = 0; wi + 1 < N; wi += 1) { \
    STK(wi) = e.mem[A + wi]; \
  } \
  sp += (N - 1) * LANE_STEP;
#define WL_ROOM(N) \
  if (DEVICE && sp + (N) * CUBE >= e.mem + STAT_OFF + CUBE) { \
    err_post(e.mem, ERR_DEEP); \
    return 0; \
  }

// Types
// =====

#ifdef __METAL_VERSION__
typedef ulong u64;
typedef uint  u32;
typedef uchar u8;
#elif defined(BEND_RTC)
typedef unsigned long long u64;
typedef unsigned int       u32;
typedef unsigned char      u8;
#else
typedef uint64_t u64;
typedef uint32_t u32;
typedef uint8_t  u8;
#endif
typedef float f32;

typedef u64 Term;

typedef struct {
  DEV u64* mem;
  DEV u64* alc;
} Env;

typedef struct {
  u64 off;
  u32 rd;
  u32 wr;
  u32 top;
} Bank;

#if DEVICE
typedef u32 u32a;
#else
typedef u32 __attribute__((may_alias)) u32a;
#endif

// Constants
// =========

#define TAG_PAK 1ull
#define TAG_CTR 2ull
#define TAG_CLO 3ull
#define TAG_BUF 4ull
#define TAG_TSK 5ull
#define TAG_ARR 6ull

#define TERM_HOLE (~0ull)
#define LOC_MASK  ((1ull << 40) - 1)
#define RFC_BIT   (1ull << 63)
#define RFC_CNT   ((1u << 24) - 1)
#define NAT_IMM   ((1ull << 48) - 1)

#define ERR_RING 1
#define ERR_TAGS 2
#define ERR_HEAP 3
#define ERR_FIDS 4
#define ERR_NATS 5
#define ERR_RFCS 6
#define ERR_DEEP 7
#define ERR_ARRS 8

#define LINE      16
#define PAGE_BITS 7
#define PAGE_LEN  (1ull << PAGE_BITS)
#define CUBE_T    128
#define CUBE      ((u64)CUBE_T * CUBE_T)
#define CUBE_G    (1u << CUBE_LOG)
#define LANES     ((u64)CUBE_T << CUBE_LOG)
#define RING_LOG  (17 - CUBE_LOG)
#define RING_LEN  (1ull << RING_LOG)
#define STAK_LEN  (1ull << 11)
#define NCLS      8
#define NCLS_ALL  32
#define IO_HELP   64

#define TG_HOLD   2304
#define CHUNK     256
#define CAP_WORDS 32768
#define QUANTUM   (DEVICE ? PAGE_LEN \
  : KEEP_WORDS < 32 * PAGE_LEN ? KEEP_WORDS : 32 * PAGE_LEN)
#if DEVICE
#define KEEP_WORDS CHUNK
#endif
#define RING_WORDS ((1ull << 10) + 2)

#define H_BUMP       0
#define H_CAP        1
#define H_CURSOR     LINE
#define H_ROOT_DONE  (2 * LINE)
#define H_ERROR_CODE (3 * LINE)
#define H_ROOT_WORD  (4 * LINE)
#define H_BANK       (H_ROOT_WORD + WL_RESW)

#define PAGE_UP(n) (((n) + PAGE_LEN - 1) & ~(PAGE_LEN - 1))
#define ALC_OFF  PAGE_UP(H_BANK + 3 * NCLS_ALL)
#define RING_OFF (ALC_OFF + CUBE * 2 * NCLS_ALL)
#define STAK_OFF (RING_OFF + CUBE * RING_WORDS)
#define STAT_OFF (STAK_OFF + CUBE * STAK_LEN)
#define HEAP_OFF (STAT_OFF + PAGE_UP(STAT_LEN))

// Globals
// =======

// The bag is 2^CUBE_LOG groups of CUBE_T lanes (a -D constant on the
// device). The device program compiles from the binary's own text.

#if !DEVICE

static u64*    CORPUS;
static u64    ALC[CUBE_T + 1][3 * NCLS_ALL] __attribute__((aligned(128)));
static u32    KEEP_WORDS;
static u32    CUBE_LOG = 7;
static u32    bank_lock;

static u32             pool_size;
static u32             pool_row;
static bool            pool_grow;
static u32             pool_tick;
static u32             pool_done;
static pthread_mutex_t pool_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  pool_wake = PTHREAD_COND_INITIALIZER;

#if BEND_METAL || BEND_CUDA
#pragma clang diagnostic ignored "-Wc23-extensions"
static const char BEND_SRC[] = {
#embed __FILE__
, 0 };
#endif

#ifdef __OBJC__
static id<MTLDevice>               gpu_dev;
static id<MTLCommandQueue>         gpu_que;
static id<MTLComputePipelineState> gpu_pso;
static id<MTLBuffer>               gpu_buf;
static id<MTLComputeCommandEncoder> gpu_enc;
#elif BEND_CUDA
static CUdevice   gpu_dev;
static CUmodule   gpu_lib;
static CUfunction gpu_pso;
#endif
static bool io_gpu;
static DEV Term*  io_stk;

static const char* CLI_HELP =
  "usage: %s [options] [arguments]\n"
  "  --threads N       worker threads, 1 to 128 (default: the CPU count)\n"
  "  --gpu on|off|4GB  run ! calls on the GPU, over this much of its memory\n"
  "                    (default: on if present, over 2GB on Metal)\n"
  "  --gpu-build       write the GPU program and exit\n"
  "  --bend-help       show this text\n"
  "  --                the rest are the program's arguments (IO.args)\n";

#endif

// Tables
// ======

#define CID_TUPLE 0
#define CID_SNIL 1
#define CID_SCON 2
#define CID_WCON 3
#define CID_EMIT 4
#define CID_HALT 5
#define CID_FAIL 6
#define CID_DONE 7
#define CID_NONE 8
#define CID_SOME 9
#define CID_FALSE 10
#define CID_TRUE 11
#define CID_UNIT 12
#define CID_TINYBENDYGRAD_HELPERS_I64 13
#define CID_CHR 14
#define CID_NIL 15
#define CID_CON 16
#define CID_TINYBENDYGRAD_DTYPE_DT_I64_TRUNC 17
#define CID_IO_PRINT 18
#define CID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV 19
#define CID_TINYBENDYGRAD_DTYPE_DT_FP8_FROM 20
#define CID_TINYBENDYGRAD_DTYPE_DT_BF16 21
#define CID_TINYBENDYGRAD_DTYPE_DT_FP16 22
#define CID_TINYBENDYGRAD_DTYPE_DT_FP8_TO 23
#define FID_U32_SHOW_GO 0
#define FID_STRING_CONCAT 1
#define FID_STRING_CONCAT_K3 2
#define FID_U32_SHOW 3
#define FID_TINYBENDYGRAD_HELPERS_I64_TEXT 4
#define FID_TINYBENDYGRAD_HELPERS_I64_TEXT_K12 5
#define FID_TINYBENDYGRAD_HELPERS_I64_TEXT_K13 6
#define FID_STRING_APPEND 7
#define FID_STRING_APPEND_K15 8
#define FID_IO_BIND 9
#define FID_IO_BIND_C18 10
#define FID_IO_BIND_K19 11
#define FID_MAIN 12
#define FID_MAIN_C21 13
#define FID_MAIN_C22 14
#define FID_MAIN_K23 15
#define FID_MAIN_K24 16
#define FID_MAIN_C25 17
#define FID_MAIN_C26 18
#define FID_MAIN_C27 19
#define FID_MAIN_C28 20
#define FID_MAIN_K29 21
#define FID_MAIN_K30 22
#define FID_MAIN_C31 23
#define FID_MAIN_C32 24
#define FID_MAIN_C33 25
#define FID_MAIN_C34 26
#define FID_MAIN_K35 27
#define FID_MAIN_K36 28
#define FID_MAIN_C37 29
#define FID_MAIN_C38 30
#define FID_MAIN_C39 31
#define FID_MAIN_C40 32
#define FID_MAIN_K41 33
#define FID_MAIN_K42 34
#define FID_MAIN_C43 35
#define FID_MAIN_C44 36
#define FID_MAIN_C45 37
#define FID_MAIN_C46 38
#define FID_MAIN_K47 39
#define FID_MAIN_K48 40
#define FID_MAIN_C49 41
#define FID_MAIN_C50 42
#define FID_MAIN_C51 43
#define FID_MAIN_C52 44
#define FID_MAIN_K53 45
#define FID_MAIN_K54 46
#define FID_MAIN_C55 47
#define FID_MAIN_C56 48
#define FID_MAIN_C57 49
#define FID_MAIN_C58 50
#define FID_MAIN_K59 51
#define FID_MAIN_K60 52
#define FID_MAIN_C61 53
#define FID_MAIN_C62 54
#define FID_MAIN_C63 55
#define FID_MAIN_C64 56
#define FID_MAIN_K65 57
#define FID_MAIN_C66 58
#define FID_MAIN_C67 59
#define FID_MAIN_C68 60
#define FID_MAIN_C69 61
#define FID_MAIN_K70 62
#define FID_MAIN_C71 63
#define FID_MAIN_C72 64
#define FID_MAIN_C73 65
#define FID_MAIN_C74 66
#define FID_MAIN_K75 67
#define FID_MAIN_C76 68
#define FID_MAIN_C77 69
#define FID_MAIN_C78 70
#define FID_MAIN_C79 71
#define FID_MAIN_K80 72
#define FID_MAIN_C81 73
#define FID_MAIN_C82 74
#define FID_MAIN_C83 75
#define FID_MAIN_C84 76
#define FID_MAIN_K85 77
#define FID_TINYBENDYGRAD_DTYPE_DT_I64_TRUNC 78
#define FID_IO_PRINT 79
#define FID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV 80
#define FID_TINYBENDYGRAD_DTYPE_DT_FP8_FROM 81
#define FID_TINYBENDYGRAD_DTYPE_DT_BF16 82
#define FID_TINYBENDYGRAD_DTYPE_DT_FP16 83
#define FID_TINYBENDYGRAD_DTYPE_DT_FP8_TO 84
#define FID_IO_EMIT 85
#define FID_CLO_APPLY 86
#define FID_EXIT 87
#define FID_ENTER 88
CONSTV u8 FID_T[][3] = { { 3, 0, 2 }, { 1, 0, 2 }, { 2, 1, 2 }, { 1, 0, 2 }, { 2, 0, 2 }, { 2, 1, 2 }, { 2, 1, 2 }, { 2, 0, 2 }, { 2, 1, 2 }, { 3, 0, 2 }, { 3, 0, 2 }, { 2, 1, 2 }, { 0, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 2, 0, 2 }, { 3, 0, 2 }, { 3, 0, 2 }, { 2, 0, 2 }, { 2, 0, 2 }, { 3, 0, 2 }, { 1, 0, 2 }, { 2, 0, 2 } };
CONSTV u8 CID_T[][2] = { { 2, 0 }, { 0, 0 }, { 2, 0 }, { 2, 0 }, { 1, 0 }, { 2, 0 }, { 1, 0 }, { 1, 0 }, { 0, 0 }, { 1, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 2, 0 }, { 1, 0 }, { 0, 0 }, { 2, 0 }, { 2, 0 }, { 2, 0 }, { 3, 0 }, { 3, 0 }, { 2, 0 }, { 2, 0 }, { 3, 0 } };
#define STAT_LEN 348

#define WL_RESW 1
#define BANGS   0

#define WL_BANK Term r0, r1, r2;

#define WL_LOAD(A, N) \
  do { \
    if ((N) <= 0) break; r0 = e.mem[(A) + 0]; \
    if ((N) <= 1) break; r1 = e.mem[(A) + 1]; \
    if ((N) <= 2) break; r2 = e.mem[(A) + 2]; \
  } while (0);

#define WL_LAST(X) \
  switch (war) { \
    case 0: r0 = (X); \
      break; \
    case 1: r1 = (X); \
      break; \
    case 2: r2 = (X); \
      break; \
  }

#define WL_SAVE(V) (V)[0] = r0;

#define WL_TAKE(V) r0 = (V)[0];

#define WL_SIG Env e, DEV Term* sp, u32 seq, u32 rn, Term r0, Term r1, Term r2

#define WL_ALL e, sp, seq, rn, r0, r1, r2

#define WL_TABLE WL_X(FID_U32_SHOW_GO) WL_X(FID_STRING_CONCAT) WL_X(FID_STRING_CONCAT_K3) WL_X(FID_U32_SHOW) WL_X(FID_TINYBENDYGRAD_HELPERS_I64_TEXT) WL_X(FID_TINYBENDYGRAD_HELPERS_I64_TEXT_K12) WL_X(FID_TINYBENDYGRAD_HELPERS_I64_TEXT_K13) WL_X(FID_STRING_APPEND) WL_X(FID_STRING_APPEND_K15) WL_X(FID_IO_BIND) WL_X(FID_IO_BIND_C18) WL_X(FID_IO_BIND_K19) WL_X(FID_MAIN) WL_X(FID_MAIN_C21) WL_X(FID_MAIN_C22) WL_X(FID_MAIN_K23) WL_X(FID_MAIN_K24) WL_X(FID_MAIN_C25) WL_X(FID_MAIN_C26) WL_X(FID_MAIN_C27) WL_X(FID_MAIN_C28) WL_X(FID_MAIN_K29) WL_X(FID_MAIN_K30) WL_X(FID_MAIN_C31) WL_X(FID_MAIN_C32) WL_X(FID_MAIN_C33) WL_X(FID_MAIN_C34) WL_X(FID_MAIN_K35) WL_X(FID_MAIN_K36) WL_X(FID_MAIN_C37) WL_X(FID_MAIN_C38) WL_X(FID_MAIN_C39) WL_X(FID_MAIN_C40) WL_X(FID_MAIN_K41) WL_X(FID_MAIN_K42) WL_X(FID_MAIN_C43) WL_X(FID_MAIN_C44) WL_X(FID_MAIN_C45) WL_X(FID_MAIN_C46) WL_X(FID_MAIN_K47) WL_X(FID_MAIN_K48) WL_X(FID_MAIN_C49) WL_X(FID_MAIN_C50) WL_X(FID_MAIN_C51) WL_X(FID_MAIN_C52) WL_X(FID_MAIN_K53) WL_X(FID_MAIN_K54) WL_X(FID_MAIN_C55) WL_X(FID_MAIN_C56) WL_X(FID_MAIN_C57) WL_X(FID_MAIN_C58) WL_X(FID_MAIN_K59) WL_X(FID_MAIN_K60) WL_X(FID_MAIN_C61) WL_X(FID_MAIN_C62) WL_X(FID_MAIN_C63) WL_X(FID_MAIN_C64) WL_X(FID_MAIN_K65) WL_X(FID_MAIN_C66) WL_X(FID_MAIN_C67) WL_X(FID_MAIN_C68) WL_X(FID_MAIN_C69) WL_X(FID_MAIN_K70) WL_X(FID_MAIN_C71) WL_X(FID_MAIN_C72) WL_X(FID_MAIN_C73) WL_X(FID_MAIN_C74) WL_X(FID_MAIN_K75) WL_X(FID_MAIN_C76) WL_X(FID_MAIN_C77) WL_X(FID_MAIN_C78) WL_X(FID_MAIN_C79) WL_X(FID_MAIN_K80) WL_X(FID_MAIN_C81) WL_X(FID_MAIN_C82) WL_X(FID_MAIN_C83) WL_X(FID_MAIN_C84) WL_X(FID_MAIN_K85) WL_X(FID_TINYBENDYGRAD_DTYPE_DT_I64_TRUNC) WL_X(FID_IO_PRINT) WL_X(FID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV) WL_X(FID_TINYBENDYGRAD_DTYPE_DT_FP8_FROM) WL_X(FID_TINYBENDYGRAD_DTYPE_DT_BF16) WL_X(FID_TINYBENDYGRAD_DTYPE_DT_FP16) WL_X(FID_TINYBENDYGRAD_DTYPE_DT_FP8_TO) WL_X(FID_IO_EMIT) WL_X(FID_CLO_APPLY) WL_X(FID_EXIT)
#define MAIN_FID FID_MAIN
#define MAIN_PURE 0
#define BLK_SHR 0

#define TAB_AT(T, S, I) T[S < I ? S : I]

#define fid_arity(x) ((u32)FID_T[x][0])
#define fid_resw(x)  ((u32)FID_T[x][1])
#define fid_bangs(x) ((bool)(FID_T[x][2] & 1))
#define fid_nofk(x)  ((bool)(FID_T[x][2] & 2))
#define cid_arity(x) ((u32)CID_T[x][0])
#define cid_hot(x)   ((bool)CID_T[x][1])

// A32
// ===

// C11's atomics on every lane; a device FENCE releases or acquires.
// Metal's a32_load reads through a volatile local, or the M1 pipeline
// build dies. A weak CAS may fail with the cell still x: a32_cmpx loops.

#define A32_LOOP(k, x) \
  INLINE u32 a32_##k(DEV u32* p, u32 v) { \
    u32 o = a32_load(p); \
    while (!a32_cas(p, &o, x)) { \
    } \
    return o; \
  }

#ifdef __METAL_VERSION__

INLINE DEV atomic_uint* A32(DEV u32* p) {
  return (DEV atomic_uint*)p;
}

INLINE TG atomic_uint* A32(TG u32* p) {
  return (TG atomic_uint*)p;
}

#define a32_load(p) \
  ({ volatile thread u32 _a32v = atomic_load_explicit(A32(p), RLX); _a32v; })

#else

#define a32_load(p) atomic_load_explicit(A32(p), RLX)

#ifdef BEND_RTC

#define A32(p) (p)
#define atomic_load_explicit(p, o)     (*(volatile u32*)(p))
#define atomic_store_explicit(p, v, o) (*(volatile u32*)(p) = (v))
#define atomic_fetch_add_explicit(p, v, o) atomicAdd((u32*)(p), v)
#define atomic_fetch_sub_explicit(p, v, o) atomicSub((u32*)(p), v)
#define atomic_fetch_and_explicit(p, v, o) atomicAnd((u32*)(p), v)
#define atomic_fetch_or_explicit(p, v, o) atomicOr((u32*)(p), v)
#define atomic_fetch_xor_explicit(p, v, o) atomicXor((u32*)(p), v)
#define atomic_fetch_min_explicit(p, v, o) atomicMin((u32*)(p), v)
#define atomic_fetch_max_explicit(p, v, o) atomicMax((u32*)(p), v)
#define atomic_compare_exchange_weak_explicit(p, e, v, s, f) a32_swp(p, e, v)

INLINE bool a32_swp(DEV u32* p, u32* e, u32 v) {
  u32 x = *e;
  *e = atomicCAS((u32*)p, x, v);
  return *e == x;
}

#else

#define A32(p) ((_Atomic u32*)(p))
#define atomic_fetch_min_explicit __c11_atomic_fetch_min
#define atomic_fetch_max_explicit __c11_atomic_fetch_max

#endif

#endif

#define RLX memory_order_relaxed

#if DEVICE
#define REL RLX
#define ACQ RLX
#define ACR RLX
#define a32_acq(p) FENCE()
#define w64_load(p) (*(p))
#else
#define REL memory_order_release
#define ACQ memory_order_acquire
#define ACR memory_order_acq_rel
#define a32_acq(p) ((void)a32_load_acq(p))
#define w64_load(p) atomic_load_explicit((_Atomic u64*)(p), RLX)
#endif

#define a32_store(p, v)     atomic_store_explicit(A32(p), v, RLX)
#define a32_add(p, v) atomic_fetch_add_explicit(A32(p), v, RLX)
#define a32_sub(p, v) atomic_fetch_sub_explicit(A32(p), v, RLX)
#define a32_and(p, v) atomic_fetch_and_explicit(A32(p), v, RLX)
#define a32_or(p, v) atomic_fetch_or_explicit(A32(p), v, RLX)
#define a32_xor(p, v) atomic_fetch_xor_explicit(A32(p), v, RLX)
#define a32_min(p, v) atomic_fetch_min_explicit(A32(p), v, RLX)
#define a32_max(p, v) atomic_fetch_max_explicit(A32(p), v, RLX)
#define a32_sub_rel(p, v)   (FENCE(), atomic_fetch_sub_explicit(A32(p), v, REL))
#define a32_store_rel(p, v) (FENCE(), atomic_store_explicit(A32(p), v, REL))
#define a32_at(H, word)     ((DEV u32*)&(H)[word])

INLINE u32 a32_load_acq(DEV u32* p) {
  u32 v = atomic_load_explicit(A32(p), ACQ);
  FENCE();
  return v;
}

INLINE bool a32_cas(DEV u32* p, THR u32* e, u32 v) {
  FENCE();
  bool ok = atomic_compare_exchange_weak_explicit(A32(p), e, v, ACR, ACQ);
  FENCE();
  return ok;
}

A32_LOOP(exch, v)

INLINE u32 a32_cmpx(DEV u32* p, u32 x, u32 v) {
  u32 o = x;
  while (!a32_cas(p, &o, v) && o == x) {
  }
  return o;
}

// Err
// ===

#if DEVICE

INLINE void err_post(DEV u64* H, u32 code) {
  a32_cmpx(a32_at(H, H_ERROR_CODE), 0, code);
}

#else

static const char* ERR_TEXT[] = { "",
  "runtime fail-stop",
  "runtime fail-stop",
  "out of memory: run again with a bigger span, as in --gpu 8GB",
  "a function the device does not hold",
  "a Nat past the largest immediate 2^48-1",
  "runtime fail-stop",
  "memory fault (machine stack overflow?)",
  "an array past the deepest block class 31" };

static void err_fail(const char* msg) {
  fflush(stdout);
  fprintf(stderr, "bend: %s\n", msg);
  _exit(1);
}

static void err_post(u64* H, u32 code) {
  err_fail(ERR_TEXT[code]);
}

static void err_trap(int sig) {
  err_post(NULL, ERR_DEEP);
}

#endif

#define err_seen(H)    (DEVICE && a32_load(a32_at(H, H_ERROR_CODE)) != 0)
#define err_spun(H, n) ((++*(n) & 4095) == 0 && err_seen(H))

#ifdef __METAL_VERSION__
INLINE f32 atan2_c99(f32 y, f32 x) {
  return y == 0.0f && x == x
    ? copysign(signbit(x) ? M_PI_F : 0.0f, y) : atan2(y, x);
}
#define sqrt  precise::sqrt
#define exp   precise::exp
#define log   precise::log
#define log2  precise::log2
#define log10 precise::log10
#define sin   fast::sin
#define cos   fast::cos
#define tan   fast::tan
#define pow   precise::pow
#define fmod  precise::fmod
#define atan2 atan2_c99
#endif

#define U32_BIN(a, o, b) ((u64)((u32)(a) o (u32)(b)))

#define U32_QUO(a, b) \
  ((a) / 2 / (b) * 2 + ((a) - (a) / 2 / (b) * 2 * (b) >= (b)))

INLINE f32 f32_unbox(u64 x) {
  union { u32 u; f32 f; } p = { (u32)x };
  return p.f;
}

INLINE u64 f32_rewrap(f32 x) {
  union { f32 f; u32 u; } p = { x };
  return p.u;
}

INLINE u64 f32_to_u32(u64 a) {
  f32 v = f32_unbox(a);
  return v >= 0.0f && v < 4294967296.0f ? (u32)v : 0;
}

INLINE u64 nat_chk(Env e, u64 n) {
  if (n > NAT_IMM) {
    err_post(e.mem, ERR_NATS);
    return NAT_IMM;
  }
  return n;
}

INLINE u64 nat_mul(Env e, u64 a, u64 b) {
  return nat_chk(e, b != 0 && a > NAT_IMM / b ? NAT_IMM + 1 : a * b);
}

#if DEVICE

#define f32_show(e, x) (err_post(e.mem, ERR_FIDS), 0)
#define f32_read(e, s) (err_post(e.mem, ERR_FIDS), 0)

#else

static Term f32_show(Env e, Term x);
static Term f32_read(Env e, Term s);

#endif

A32_LOOP(fadd, f32_rewrap(f32_unbox(o) + f32_unbox(v)))

// Bank
// ====

// A stack of exact generations per class. The host pops and pushes at rd;
// a device pass pops below rd and pushes above top, compacted after it.

#define bank_at(H, c) ((DEV Bank*)((H) + H_BANK) + (c))

INLINE u64 bank_pop(DEV u64* H, u32 c) {
  DEV Bank* b = bank_at(H, c);
  u64 got = 0;
  LOCK(bank_lock);
  u32 t = a32_sub(&b->rd, 1);
  if ((int)t > 0) {
    got = H[b->off + t - 1];
  } else {
    a32_add(&b->rd, 1);
  }
  if (!DEVICE) {
    b->wr = b->top = b->rd;
  }
  UNLOCK(bank_lock);
  return got;
}

INLINE void bank_push(DEV u64* H, u32 c, u64 head) {
  DEV Bank* b = bank_at(H, c);
  LOCK(bank_lock);
  H[b->off + a32_add(&b->wr, 1)] = head;
  if (!DEVICE) {
    b->rd = b->top = b->wr;
  }
  UNLOCK(bank_lock);
}

// Heap
// ====

// Per lane and class: HOT, a LIFO free chain; LEN, its length in words;
// on the host COLD, one parked generation. A host free reaching KEEP_WORDS
// parks HOT as COLD and banks the old COLD. A miss takes COLD, a bank entry
// or a fresh quantum. A device lane banks its complete generations at the
// kernel end (dev_cut). The bump grows only when all of these are empty.

#define ALC_AT(e, i)   (e).alc[(i) * LANE_STEP]
#define ALC_LEN(e, c)  ALC_AT(e, NCLS_ALL + (c))
#define ALC_COLD(e, c) ALC_AT(e, 2 * NCLS_ALL + (c))
#define KEEP(c)        (KEEP_WORDS >> (c) ? KEEP_WORDS >> (c) : 1)

INLINE u32 cls_fit(u32 words) {
  return words > 1 ? 32 - CLZ(words - 1) : 0;
}

OUTLINE void heap_hand(Env e, u32 cls) {
  u64 cold = ALC_COLD(e, cls);
  if (cold) {
    bank_push(e.mem, cls, cold);
  }
  ALC_COLD(e, cls) = ALC_AT(e, cls);
  ALC_AT(e, cls)   = 0;
  ALC_LEN(e, cls)  = 0;
}

#if DEVICE
#define corpus_grow(H, n) false
#else
static bool corpus_grow(u64* H, u64 need);
#endif

OUTLINE u64 heap_alloc_miss(Env e, u32 cls) {
  DEV u64* H = e.mem;
  u64  got = 0;
  if (!DEVICE) {
    got = ALC_COLD(e, cls);
    ALC_COLD(e, cls) = 0;
  }
  if (!got) {
    got = bank_pop(H, cls);
  }
  u32 n = got ? KEEP(cls) : cls < NCLS ? QUANTUM >> cls : 1;
  if (!got) {
    u32 pages = (n << cls) >> PAGE_BITS;
    u32 p     = a32_add(a32_at(H, H_BUMP), pages);
    if ((u64)p + pages > a32_load_acq(a32_at(H, H_CAP))
      && !corpus_grow(H, (u64)p + pages)) {
      err_post(H, ERR_HEAP);
      return HEAP_OFF;
    }
    got = HEAP_OFF + ((u64)p << PAGE_BITS);
    for (u32 i = 1; i <= n; i += 1) {
      H[got + ((u64)(i - 1) << cls)] = i < n ? got + ((u64)i << cls) : 0;
    }
  }
  ALC_AT(e, cls)  = H[got];
  ALC_LEN(e, cls) = (u64)(n - 1) << cls;
  return got;
}

INLINE u64 heap_alloc(Env e, u32 cls) {
  u64 h = ALC_AT(e, cls);
  if (h) {
    ALC_AT(e, cls)   = e.mem[h];
    ALC_LEN(e, cls) -= 1ull << cls;
    return h;
  }
  return heap_alloc_miss(e, cls);
}

INLINE void heap_free(Env e, u32 cls, u64 loc) {
  if (err_seen(e.mem)) {
    return;
  }
  e.mem[loc]       = ALC_AT(e, cls);
  ALC_AT(e, cls)   = loc;
  ALC_LEN(e, cls) += 1ull << cls;
  if (!DEVICE && ALC_LEN(e, cls) >= KEEP_WORDS) {
    heap_hand(e, cls);
  }
}

INLINE void spare_free(Env e, u32 cls, u64 loc) {
  if (loc >= HEAP_OFF) {
    heap_free(e, cls, loc);
  }
}

// Term
// ====

#define term_make(tag, aux, loc) \
  (((u64)(tag) << 56) | ((u64)(aux) << 40) | (u64)(loc))

#define term_ctr(cid, loc) term_make(TAG_CTR, cid, loc)
#define term_pak(cid, loc) term_make(TAG_PAK, cid, loc)
#define term_clo(fid, loc) term_make(TAG_CLO, fid, loc)
#define term_buf(cls, loc) term_make(TAG_BUF, cls, loc)
#define term_tsk(fid, loc) term_make(TAG_TSK, fid, loc)

INLINE Term term_blk(bool arr, u32 cls, u64 loc) {
  return term_buf(cls, loc) | ((u64)arr << 57);
}

INLINE u64 term_tag(Term t) {
  return (t >> 56) & 0x7f;
}

INLINE bool term_rfc(Term t) {
  return (t & RFC_BIT) != 0;
}

INLINE u64 term_aux(Term t) {
  return (t >> 40) & 0xFFFF;
}

INLINE u64 term_loc(Term t) {
  return t & LOC_MASK;
}

INLINE bool term_triv(Term t) {
  return term_tag(t) <= TAG_PAK || t == TERM_HOLE || term_loc(t) < HEAP_OFF;
}

OUTLINE Term rfc_wrap(Env e, Term t, u32 cnt) {
  if (term_tag(t) == TAG_CLO || term_tag(t) == TAG_TSK) {
    err_post(e.mem, ERR_RFCS);
    return t;
  }
  u64 r = heap_alloc(e, 0);
  e.mem[r] = ((u64)term_loc(t) << 24) | cnt;
  return (t & ~LOC_MASK) | RFC_BIT | r;
}

INLINE Term rfc_seal(Env e, Term t) {
  if (term_tag(t) != TAG_CTR || term_rfc(t)) {
    return t;
  }
  return rfc_wrap(e, t, 1);
}

// A redirect cell holds its target's loc over a 24-bit count, which
// changes by atomic adds on the low half, so a host never reads it as one
// plain word.
INLINE u64 rfc_view(DEV u64* H, u64 r) {
  DEV u32* w = a32_at(H, r);
  u64 cell = ((u64)a32_load(w + 1) << 32) | a32_load(w);
  if ((cell & RFC_CNT) == 1) {
    a32_acq(w);
  }
  return cell;
}

INLINE void rfc_bump(Env e, u64 r, u32 k) {
  u32 c = a32_add(a32_at(e.mem, r), k);
  if ((c & RFC_CNT) >= RFC_CNT - k) {
    err_post(e.mem, ERR_RFCS);
  }
}

INLINE Term term_keep(Env e, Term t, u32 k) {
  if (term_rfc(t)) {
    rfc_bump(e, term_loc(t), k);
    return t;
  }
  if (term_triv(t)) {
    return t;
  }
  return rfc_wrap(e, t, 1 + k);
}

INLINE u64 term_peek(DEV u64* H, Term t) {
  if (term_rfc(t)) {
    return rfc_view(H, term_loc(t)) >> 24;
  }
  return term_loc(t);
}

#define blk_shr(t) (BLK_SHR && term_rfc(t))

INLINE u64 blk_loc(DEV u64* H, Term a) {
  return blk_shr(a) ? w64_load(&H[term_loc(a)]) >> 24 : term_loc(a);
}

INLINE u32 blk_cls(Term t) {
  return (u32)term_aux(t) & 31;
}

#define buf_wcls(c) ((c) == 0 ? 0 : (c) - 1)

INLINE u32 blk_span(Term t) {
  u32 c = blk_cls(t);
  return term_tag(t) == TAG_ARR ? c : buf_wcls(c);
}

FAR void term_drop(Env e, Term t) {
  DEV u64* H = e.mem;
  u64  cur = 0;
  Term c0  = 0;
  u32  step = 0;
  for (;;) {
    if (!term_triv(t) && term_rfc(t)) {
      u64      r = term_loc(t);
      DEV u32* p = a32_at(H, r);
      if ((a32_sub_rel(p, 1) & RFC_CNT) != 1) {
        t = 0;
      } else {
        a32_acq(p);
        t = (t & ~(RFC_BIT | LOC_MASK)) | (H[r] >> 24);
        heap_free(e, 0, r);
      }
    }
    if (!term_triv(t)) {
      u64 tag = term_tag(t);
      if (tag == TAG_BUF) {
        heap_free(e, blk_span(t), term_loc(t));
      } else {
        u32 aux = (u32)term_aux(t);
        u64 loc = term_loc(t);
        u32 n   = tag == TAG_ARR ? 0 : tag == TAG_CTR ? cid_arity(aux)
          : fid_arity(aux) - (tag == TAG_CLO);
        u32 cls = tag == TAG_ARR ? 64 | blk_cls(t)
          : n > 247 ? 64 | (n - 240)
          : cls_fit(tag == TAG_TSK ? n + 2 : n);
        c0 = H[loc];
        H[loc] = cur;
        cur = loc | ((u64)n << 48) | ((u64)cls << 56);
      }
    }
    for (;;) {
      if (err_spun(H, &step) || cur == 0) {
        return;
      }
      u64  loc = cur & LOC_MASK;
      u32  i   = (u8)(cur >> 40);
      u32  n   = (u8)(cur >> 48);
      u32  cls = (u32)(cur >> 56);
      bool arr = cls > 63;
      u32  j   = i;
      if (arr) {
        cls &= 63;
        n   = 1u << cls;
        if (i == 2) {
          j = (u32)H[loc + 1];
        }
      }
      if (j < n) {
        Term c = j == 0 ? c0 : H[loc + j];
        if (arr && j > 0) {
          H[loc + 1] = j + 1;
        }
        if (!arr || i < 2) {
          cur += 1ull << 40;
        }
        if (!term_triv(c)) {
          t = c;
          break;
        }
      } else {
        u64 up = H[loc];
        heap_free(e, cls, loc);
        cur = up;
      }
    }
  }
}

INLINE void term_sink(Env e, Term t) {
  if (!term_triv(t)) {
    term_drop(e, t);
  }
}

OUTLINE void span_fade(Env e, Term t, u64 src, u32 n) {
  for (u32 j = 0; j < n; j += 1) {
    Term f = e.mem[src + j];
    if (term_rfc(f)) {
      rfc_bump(e, term_loc(f), 1);
    } else if (!term_triv(f)) {
      err_post(e.mem, ERR_RFCS);
    }
  }
  term_drop(e, t);
}

INLINE u64 ctr_take(Env e, Term t, u32 n, THR Term* out) {
  DEV u64* H = e.mem;
  if (!term_rfc(t)) {
    for (u32 j = 0; j < n; j += 1) {
      out[j] = H[term_loc(t) + j];
    }
    return term_loc(t);
  }
  u64 r    = term_loc(t);
  u64 cell = rfc_view(H, r);
  u64 src  = cell >> 24;
  for (u32 j = 0; j < n; j += 1) {
    out[j] = H[src + j];
  }
  if ((cell & RFC_CNT) == 1) {
    heap_free(e, 0, r);
    return src;
  }
  span_fade(e, t, src, n);
  return 0;
}

INLINE Term term_word(Env e, Term w) {
  u32 x = 0;
  Term t = w;
  for (u32 i = 0; i < 32 && term_aux(t) == CID_WCON; i += 1) {
    u64 l = term_peek(e.mem, t);
    x |= (u32)(e.mem[l] & 1) << i;
    t = e.mem[l + 1];
  }
  term_sink(e, w);
  return x;
}

// Blk
// ===

// A block owns one allocation in its class (an ARR 2^c Terms, a BUF 2^c
// u32). Matching ANode is blk_half twice (the high call frees the source);
// ANode{l, r} is blk_node; Array.clone is blk_copy.

#define BLK_ALLOC(n, w) \
  u64 n = heap_alloc(e, w); \
  if (err_seen(e.mem)) { \
    return term_buf(0, n); \
  }

INLINE DEV u32a* blk_ptr(DEV u64* H, u64 loc, u32 i) {
  return (DEV u32a*)(H + loc) + i;
}

INLINE Term blk_read(DEV u64* H, bool arr, u64 loc, u32 i) {
  if (arr) {
    return H[loc + i];
  }
  return (u64)*blk_ptr(H, loc, i);
}

INLINE void blk_write(DEV u64* H, bool arr, u64 loc, u32 i, Term v) {
  if (arr) {
    H[loc + i] = v;
  } else {
    *blk_ptr(H, loc, i) = (u32)v;
  }
}

INLINE u32 blk_at(Term a, u64 i, u32 lgs) {
  return ((u32)i & (u32)((1ull << (blk_cls(a) - lgs)) - 1)) << lgs;
}

INLINE Term blk_keep(Env e, u64 at) {
  Term w = e.mem[at];
  Term v = term_keep(e, w, 1);
  if (v != w) {
    e.mem[at] = v;
  }
  return v;
}

INLINE void blk_fill(Env e, u64 dst, u64 src, u64 n, bool keep) {
  for (u64 j = 0; j < n; j += 1) {
    e.mem[dst + j] = keep ? blk_keep(e, src + j) : e.mem[src + j];
  }
}

INLINE void blk_free(Env e, Term t) {
  blk_shr(t) ? term_drop(e, t) : heap_free(e, blk_span(t), term_loc(t));
}

OUTLINE Term blk_copy(Env e, Term a) {
  bool arr = term_tag(a) == TAG_ARR;
  u32 cls = blk_span(a);
  BLK_ALLOC(dst, cls)
  blk_fill(e, dst, blk_loc(e.mem, a), 1ull << cls, arr);
  return term_blk(arr, blk_cls(a), dst);
}

INLINE Term blk_node(Env e, Term l, Term r) {
  DEV u64* H = e.mem;
  bool arr = term_tag(l) == TAG_ARR;
  u32 c = blk_cls(l);
  if (c != blk_cls(r) || c + 1 >= NCLS_ALL) {
    err_post(H, ERR_TAGS);
    return l;
  }
  u64 pl = blk_loc(H, l);
  u64 pr = blk_loc(H, r);
  BLK_ALLOC(n, arr ? c + 1 : c)
  if (!arr && c == 0) {
    H[n] = (u64)*blk_ptr(H, pl, 0) | ((u64)*blk_ptr(H, pr, 0) << 32);
  } else {
    u64 cw = 1ull << blk_span(l);
    blk_fill(e, n, pl, cw, arr && blk_shr(l));
    blk_fill(e, n + cw, pr, cw, arr && blk_shr(r));
  }
  blk_free(e, l);
  blk_free(e, r);
  return term_blk(arr, c + 1, n);
}

INLINE Term blk_half(Env e, Term a, u32 hi) {
  DEV u64* H = e.mem;
  bool arr = term_tag(a) == TAG_ARR;
  u32 c = blk_cls(a);
  if (c == 0) {
    err_post(H, ERR_TAGS);
    return a;
  }
  c -= 1;
  u32 cw = arr ? c : buf_wcls(c);
  u64 src = blk_loc(H, a);
  BLK_ALLOC(n, cw)
  if (!arr && c == 0) {
    H[n] = (u64)*blk_ptr(H, src, hi);
  } else {
    blk_fill(e, n, src + ((u64)hi << cw), 1ull << cw, arr && blk_shr(a));
  }
  if (hi) {
    blk_free(e, a);
  }
  return term_blk(arr, c, n);
}

INLINE Term blk_new(Env e, bool arr, u64 d, u32 lgs, u32 n, THR Term* v) {
  DEV u64* H = e.mem;
  if (d + lgs > 31) {
    err_post(H, ERR_ARRS);
    d = 0;
  }
  u32 c = (u32)d + lgs;
  BLK_ALLOC(l, arr ? c : buf_wcls(c))
  for (u32 j = 0; arr && d > 0 && j < n; j += 1) {
    if (d >= 24 && !term_triv(v[j])) {
      err_post(H, ERR_RFCS);
    }
    v[j] = term_keep(e, v[j], (1u << d) - 1);
  }
  for (u64 i = 0; i < (1ull << c); i += 1) {
    blk_write(H, arr, l, (u32)i, i % (1u << lgs) < n ? v[i % (1u << lgs)] : 0);
  }
  return term_blk(arr, c, l);
}

// Ring
// ====

#define ring_word(H, r, w) ((H) + RING_OFF + (w) * LANES + (r))
#define ring_slot(H, r, p) ring_word(H, r, (p) & (RING_LEN - 1))
#define ring_get(H, r)     ((DEV u32*)ring_word(H, r, RING_LEN))
#define ring_put(H, r)     ((DEV u32*)ring_word(H, r, RING_LEN + 1))

INLINE u32 ring_lap(u32 pos) {
  return ~(u32)(pos / RING_LEN) & 1;
}

INLINE void ring_push(DEV u64* H, u32 r, Term tsk) {
  u32 pos = a32_add(ring_put(H, r), 1);
  if (pos - a32_load(ring_get(H, r)) >= RING_LEN) {
    err_post(H, ERR_RING);
    return;
  }
  DEV u32* lo = (DEV u32*)ring_slot(H, r, pos);
  a32_store(lo, (u32)tsk);
  a32_store_rel(lo + 1, (u32)(tsk >> 32) | (ring_lap(pos) << 31));
}

INLINE u32 ring_flip(u32 i) {
  return (i % CUBE_T << CUBE_LOG) + i / CUBE_T;
}

#define ring_pick(b, s, c) ((b) + (s) * (a32_add(c, 1) & (CUBE_T - 1)))

// Task
// ====

INLINE u64 task_node(Env e, u32 fid, Term cont, u32 idx, u32 rem) {
  u32 ar  = fid_arity(fid);
  u64 loc = heap_alloc(e, cls_fit(ar + 2));
  for (u32 i = 0; rem && i < ar; i += 1) {
    e.mem[loc + i] = TERM_HOLE;
  }
  e.mem[loc + ar]     = cont;
  e.mem[loc + ar + 1] = ((u64)idx << 32) | rem;
  return loc;
}

INLINE u64 task_tail(Term t) {
  return term_loc(t) + fid_arity((u32)term_aux(t));
}

INLINE Term task_deliver(DEV u64* H, Term cont, u32 idx, THR Term* v, u32 n) {
  u64 at = cont == TERM_HOLE ? H_ROOT_WORD : term_loc(cont) + idx;
  for (u32 j = 0; j < WL_RESW; j += 1) {
    if (j < n) {
      H[at + j] = v[j];
    }
  }
  if (cont == TERM_HOLE) {
    a32_store_rel(a32_at(H, H_ROOT_DONE), n + 1);
    return 0;
  }
  u64 tl = task_tail(cont);
  if (a32_sub_rel(a32_at(H, tl + 1), 1) == 1) {
    a32_acq(a32_at(H, tl + 1));
    return cont;
  }
  return 0;
}

INLINE void task_deal(DEV u64* H, Term join, u32 base, u32 stride, TG u32* cur) {
  u64 loc = term_loc(join);
  u32 ar  = fid_arity((u32)term_aux(join));
  u32 g   = 0;
  if (stride == 0) {
    u32 rem = (u32)H[loc + ar + 1];
    g = a32_add(a32_at(H, H_CURSOR), rem);
  }
  for (u32 i = 0; i < ar; i += 1) {
    Term k = H[loc + i];
    if (term_tag(k) == TAG_TSK) {
      H[loc + i] = TERM_HOLE;
      u32 to;
      if (stride != 0) {
        to = ring_pick(base, stride, cur);
      } else {
        to = ring_flip(g & (u32)(LANES - 1));
        g += 1;
      }
      ring_push(H, to, k);
    }
  }
}

// Root
// ====

INLINE bool root_done(DEV u64* H) {
  return a32_load_acq(a32_at(H, H_ROOT_DONE)) != 0;
}

static u32 root_take(DEV u64* H, THR Term* v) {
  u32 n = a32_load_acq(a32_at(H, H_ROOT_DONE)) - 1;
  for (u32 j = 0; j < n; j += 1) {
    v[j] = H[H_ROOT_WORD + j];
  }
  a32_store(a32_at(H, H_ROOT_DONE), 0);
  return n;
}

// Spins
// =====

CONSTV u64 STAT_IMG[] = { 48ull, term_pak(CID_SNIL, 0), 58ull, term_pak(CID_SNIL, 0), 15ull, 240ull, 32ull, term_pak(CID_SNIL, 0), 61ull, term_ctr(CID_SCON, STAT_OFF + 6), 32ull, term_ctr(CID_SCON, STAT_OFF + 8), 65ull, term_ctr(CID_SCON, STAT_OFF + 10), 95ull, term_ctr(CID_SCON, STAT_OFF + 12), 99ull, term_ctr(CID_SCON, STAT_OFF + 14), 110ull, term_ctr(CID_SCON, STAT_OFF + 16), 117ull, term_ctr(CID_SCON, STAT_OFF + 18), 114ull, term_ctr(CID_SCON, STAT_OFF + 20), 116ull, term_ctr(CID_SCON, STAT_OFF + 22), 32ull, term_ctr(CID_SCON, STAT_OFF + 24), 51ull, term_ctr(CID_SCON, STAT_OFF + 26), 50ull, term_ctr(CID_SCON, STAT_OFF + 28), 49ull, term_ctr(CID_SCON, STAT_OFF + 30), 105ull, term_ctr(CID_SCON, STAT_OFF + 32), 98ull, term_ctr(CID_SCON, STAT_OFF + 34), 97ull, term_ctr(CID_SCON, STAT_OFF + 36), 3735928559ull, 305419896ull, 66ull, term_ctr(CID_SCON, STAT_OFF + 10), 95ull, term_ctr(CID_SCON, STAT_OFF + 42), 99ull, term_ctr(CID_SCON, STAT_OFF + 44), 110ull, term_ctr(CID_SCON, STAT_OFF + 46), 117ull, term_ctr(CID_SCON, STAT_OFF + 48), 114ull, term_ctr(CID_SCON, STAT_OFF + 50), 116ull, term_ctr(CID_SCON, STAT_OFF + 52), 32ull, term_ctr(CID_SCON, STAT_OFF + 54), 51ull, term_ctr(CID_SCON, STAT_OFF + 56), 50ull, term_ctr(CID_SCON, STAT_OFF + 58), 49ull, term_ctr(CID_SCON, STAT_OFF + 60), 105ull, term_ctr(CID_SCON, STAT_OFF + 62), 98ull, term_ctr(CID_SCON, STAT_OFF + 64), 97ull, term_ctr(CID_SCON, STAT_OFF + 66), 7ull, 0ull, 3ull, 0ull, 51ull, term_ctr(CID_SCON, STAT_OFF + 10), 98ull, term_ctr(CID_SCON, STAT_OFF + 74), 95ull, term_ctr(CID_SCON, STAT_OFF + 76), 118ull, term_ctr(CID_SCON, STAT_OFF + 78), 105ull, term_ctr(CID_SCON, STAT_OFF + 80), 100ull, term_ctr(CID_SCON, STAT_OFF + 82), 102ull, term_ctr(CID_SCON, STAT_OFF + 84), 32ull, term_ctr(CID_SCON, STAT_OFF + 86), 51ull, term_ctr(CID_SCON, STAT_OFF + 88), 50ull, term_ctr(CID_SCON, STAT_OFF + 90), 49ull, term_ctr(CID_SCON, STAT_OFF + 92), 105ull, term_ctr(CID_SCON, STAT_OFF + 94), 98ull, term_ctr(CID_SCON, STAT_OFF + 96), 97ull, term_ctr(CID_SCON, STAT_OFF + 98), 5ull, 0ull, 53ull, term_ctr(CID_SCON, STAT_OFF + 10), 98ull, term_ctr(CID_SCON, STAT_OFF + 104), 95ull, term_ctr(CID_SCON, STAT_OFF + 106), 118ull, term_ctr(CID_SCON, STAT_OFF + 108), 105ull, term_ctr(CID_SCON, STAT_OFF + 110), 100ull, term_ctr(CID_SCON, STAT_OFF + 112), 102ull, term_ctr(CID_SCON, STAT_OFF + 114), 32ull, term_ctr(CID_SCON, STAT_OFF + 116), 51ull, term_ctr(CID_SCON, STAT_OFF + 118), 50ull, term_ctr(CID_SCON, STAT_OFF + 120), 49ull, term_ctr(CID_SCON, STAT_OFF + 122), 105ull, term_ctr(CID_SCON, STAT_OFF + 124), 98ull, term_ctr(CID_SCON, STAT_OFF + 126), 97ull, term_ctr(CID_SCON, STAT_OFF + 128), 1ull, 0ull, 49ull, term_ctr(CID_SCON, STAT_OFF + 10), 98ull, term_ctr(CID_SCON, STAT_OFF + 134), 95ull, term_ctr(CID_SCON, STAT_OFF + 136), 118ull, term_ctr(CID_SCON, STAT_OFF + 138), 105ull, term_ctr(CID_SCON, STAT_OFF + 140), 100ull, term_ctr(CID_SCON, STAT_OFF + 142), 102ull, term_ctr(CID_SCON, STAT_OFF + 144), 32ull, term_ctr(CID_SCON, STAT_OFF + 146), 51ull, term_ctr(CID_SCON, STAT_OFF + 148), 50ull, term_ctr(CID_SCON, STAT_OFF + 150), 49ull, term_ctr(CID_SCON, STAT_OFF + 152), 105ull, term_ctr(CID_SCON, STAT_OFF + 154), 98ull, term_ctr(CID_SCON, STAT_OFF + 156), 97ull, term_ctr(CID_SCON, STAT_OFF + 158), 109ull, term_ctr(CID_SCON, STAT_OFF + 74), 52ull, term_ctr(CID_SCON, STAT_OFF + 162), 101ull, term_ctr(CID_SCON, STAT_OFF + 164), 95ull, term_ctr(CID_SCON, STAT_OFF + 166), 109ull, term_ctr(CID_SCON, STAT_OFF + 168), 111ull, term_ctr(CID_SCON, STAT_OFF + 170), 114ull, term_ctr(CID_SCON, STAT_OFF + 172), 102ull, term_ctr(CID_SCON, STAT_OFF + 174), 56ull, term_ctr(CID_SCON, STAT_OFF + 176), 112ull, term_ctr(CID_SCON, STAT_OFF + 178), 102ull, term_ctr(CID_SCON, STAT_OFF + 180), 32ull, term_ctr(CID_SCON, STAT_OFF + 182), 49ull, term_ctr(CID_SCON, STAT_OFF + 184), 105ull, term_ctr(CID_SCON, STAT_OFF + 186), 98ull, term_ctr(CID_SCON, STAT_OFF + 188), 97ull, term_ctr(CID_SCON, STAT_OFF + 190), 122ull, term_ctr(CID_SCON, STAT_OFF + 10), 117ull, term_ctr(CID_SCON, STAT_OFF + 194), 110ull, term_ctr(CID_SCON, STAT_OFF + 196), 102ull, term_ctr(CID_SCON, STAT_OFF + 198), 95ull, term_ctr(CID_SCON, STAT_OFF + 200), 109ull, term_ctr(CID_SCON, STAT_OFF + 202), 111ull, term_ctr(CID_SCON, STAT_OFF + 204), 114ull, term_ctr(CID_SCON, STAT_OFF + 206), 102ull, term_ctr(CID_SCON, STAT_OFF + 208), 56ull, term_ctr(CID_SCON, STAT_OFF + 210), 112ull, term_ctr(CID_SCON, STAT_OFF + 212), 102ull, term_ctr(CID_SCON, STAT_OFF + 214), 32ull, term_ctr(CID_SCON, STAT_OFF + 216), 49ull, term_ctr(CID_SCON, STAT_OFF + 218), 105ull, term_ctr(CID_SCON, STAT_OFF + 220), 98ull, term_ctr(CID_SCON, STAT_OFF + 222), 97ull, term_ctr(CID_SCON, STAT_OFF + 224), 112ull, term_ctr(CID_SCON, STAT_OFF + 104), 49ull, term_ctr(CID_SCON, STAT_OFF + 228), 95ull, term_ctr(CID_SCON, STAT_OFF + 230), 54ull, term_ctr(CID_SCON, STAT_OFF + 232), 49ull, term_ctr(CID_SCON, STAT_OFF + 234), 102ull, term_ctr(CID_SCON, STAT_OFF + 236), 98ull, term_ctr(CID_SCON, STAT_OFF + 238), 32ull, term_ctr(CID_SCON, STAT_OFF + 240), 49ull, term_ctr(CID_SCON, STAT_OFF + 242), 105ull, term_ctr(CID_SCON, STAT_OFF + 244), 98ull, term_ctr(CID_SCON, STAT_OFF + 246), 97ull, term_ctr(CID_SCON, STAT_OFF + 248), 112ull, term_ctr(CID_SCON, STAT_OFF + 236), 102ull, term_ctr(CID_SCON, STAT_OFF + 252), 32ull, term_ctr(CID_SCON, STAT_OFF + 254), 52ull, term_ctr(CID_SCON, STAT_OFF + 256), 105ull, term_ctr(CID_SCON, STAT_OFF + 258), 98ull, term_ctr(CID_SCON, STAT_OFF + 260), 97ull, term_ctr(CID_SCON, STAT_OFF + 262), 112ull, term_ctr(CID_SCON, STAT_OFF + 134), 49ull, term_ctr(CID_SCON, STAT_OFF + 266), 95ull, term_ctr(CID_SCON, STAT_OFF + 268), 54ull, term_ctr(CID_SCON, STAT_OFF + 270), 49ull, term_ctr(CID_SCON, STAT_OFF + 272), 112ull, term_ctr(CID_SCON, STAT_OFF + 274), 102ull, term_ctr(CID_SCON, STAT_OFF + 276), 32ull, term_ctr(CID_SCON, STAT_OFF + 278), 52ull, term_ctr(CID_SCON, STAT_OFF + 280), 105ull, term_ctr(CID_SCON, STAT_OFF + 282), 98ull, term_ctr(CID_SCON, STAT_OFF + 284), 97ull, term_ctr(CID_SCON, STAT_OFF + 286), 50ull, term_ctr(CID_SCON, STAT_OFF + 104), 112ull, term_ctr(CID_SCON, STAT_OFF + 290), 50ull, term_ctr(CID_SCON, STAT_OFF + 292), 109ull, term_ctr(CID_SCON, STAT_OFF + 294), 95ull, term_ctr(CID_SCON, STAT_OFF + 296), 54ull, term_ctr(CID_SCON, STAT_OFF + 298), 49ull, term_ctr(CID_SCON, STAT_OFF + 300), 112ull, term_ctr(CID_SCON, STAT_OFF + 302), 102ull, term_ctr(CID_SCON, STAT_OFF + 304), 32ull, term_ctr(CID_SCON, STAT_OFF + 306), 52ull, term_ctr(CID_SCON, STAT_OFF + 308), 105ull, term_ctr(CID_SCON, STAT_OFF + 310), 98ull, term_ctr(CID_SCON, STAT_OFF + 312), 97ull, term_ctr(CID_SCON, STAT_OFF + 314), 67ull, term_ctr(CID_SCON, STAT_OFF + 10), 51ull, term_ctr(CID_SCON, STAT_OFF + 318), 120ull, term_ctr(CID_SCON, STAT_OFF + 320), 48ull, term_ctr(CID_SCON, STAT_OFF + 322), 95ull, term_ctr(CID_SCON, STAT_OFF + 324), 111ull, term_ctr(CID_SCON, STAT_OFF + 326), 116ull, term_ctr(CID_SCON, STAT_OFF + 328), 56ull, term_ctr(CID_SCON, STAT_OFF + 330), 112ull, term_ctr(CID_SCON, STAT_OFF + 332), 102ull, term_ctr(CID_SCON, STAT_OFF + 334), 32ull, term_ctr(CID_SCON, STAT_OFF + 336), 52ull, term_ctr(CID_SCON, STAT_OFF + 338), 105ull, term_ctr(CID_SCON, STAT_OFF + 340), 98ull, term_ctr(CID_SCON, STAT_OFF + 342), 97ull, term_ctr(CID_SCON, STAT_OFF + 344) };

INLINE Term spin_0(Env e, THR Term* o, u32 r0, u32 r1) {
  u32 wpoll = 0;
  u32 _v_2 = 0;
  u32 _x_2 = r0;
  u32 _x_3 = r1;
  WL_SPIN
    _v_2 = _x_2;
  break;
  }
  o[0] = _v_2;
  return 1;
}

INLINE Term spin_1(Env e, THR Term* o, u32 r0, u32 r1) {
  u32 wpoll = 0;
  u32 _v_5 = 0;
  u32 _x_4 = r0;
  u32 _x_5 = r1;
  WL_SPIN
    _v_5 = _x_5;
  break;
  }
  o[0] = _v_5;
  return 1;
}

// Work
// ====

// A host self-jump is a tail call: as a loop, clang hoisted constants into
// symreg's entry (3.05 s against 2.51 s).
#if !DEVICE
#undef  WL_SPIN
#undef  WL_SPUN
#undef  WL_AGAIN
#define WL_SPIN
#define WL_SPUN
#define WL_AGAIN(F) __attribute__((musttail)) return WL_##F(WL_ALL)

typedef Term (PRESERVE(preserve_none) *WlFn)(WL_SIG);
#define WL_X(F) WL_FN WL_##F(WL_SIG);
WL_TABLE WL_X(FID_ENTER)
#undef WL_X
#define WL_X(F) WL_##F,
static const WlFn wl_tab[] = { WL_TABLE };
#undef WL_X
#endif

static Term work_loop(Env e, DEV Term* sp, Term t, u32 seq) {
  WL_BANK
  u32 rn = 0;
  r0 = t;
#if DEVICE
  u32 fid   = FID_ENTER;
  u32 wpoll = 0;
  for (;;) {
  if (err_spun(e.mem, &wpoll)) {
    return 0;
  }
  switch (fid) {
#else
  return WL_FID_ENTER(WL_ALL);
}
#endif

// Segments
// ========

// A task enters through its words: a continuation's results ride r0..
// and its parameters the stack; any other segment's parameters ride r0..

#if !DEVICE
  WL_CASE(FID_U32_SHOW_GO)
  {
    Term _f_0 = r0;
    u32 _n_0 = r1;
    Term _acc_0 = r2;
    WL_OPEN
    WL_SPIN
    if (_f_0 == 0) {
      r0 = _acc_0;
      WL_RETN(1);
    } else {
      Term _g_0 = (_f_0 - 1);
      u32 _s_0 = U32_BIN(_n_0, ==, 0);
      if (_s_0 == 1) {
        r0 = _acc_0;
        WL_RETN(1);
      } else {
        Term _a_0 = 10ull;
        Term _a_1 = 10ull;
        u64 _nd_0 = heap_alloc(e, cls_fit(2));
        e.mem[_nd_0 + 0] = U32_BIN(48ull, +, ((u32)(_a_1) == 0 ? _n_0 : U32_BIN(_n_0, -, U32_QUO((u32)(_n_0), (u32)(_a_1)) * _a_1)));
        e.mem[_nd_0 + 1] = _acc_0;
        r0 = _g_0;
        r1 = ((u32)(_a_0) == 0 ? 0 : (u64)U32_QUO((u32)(_n_0), (u32)(_a_0)));
        r2 = term_ctr(CID_SCON, _nd_0);
        _f_0 = r0;
        _n_0 = r1;
        _acc_0 = r2;
        WL_AGAIN(FID_U32_SHOW_GO);
      }
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_STRING_CONCAT)
  {
    Term _xs_0 = r0;
    WL_OPEN
    WL_SPIN
    if (term_aux(_xs_0) == CID_NIL) {
      r0 = term_pak(CID_SNIL, 0);
      WL_RETN(1);
    } else {
      u64 _sp_0 = term_loc(_xs_0);
      Term _f_0 = e.mem[_sp_0 + 0];
      Term _f_1 = e.mem[_sp_0 + 1];
      heap_free(e, cls_fit(2), _sp_0);
      if (seq) {
        WL_ROOM(2);
        STK(0) = _f_0;
        STK(1) = FID_STRING_CONCAT_K3;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_STRING_CONCAT_K3, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _f_0;
        WL_CONT = term_tsk(FID_STRING_CONCAT_K3, _t_0);
        WL_IDX = 1;
      }
      r0 = _f_1;
      _xs_0 = r0;
      WL_AGAIN(FID_STRING_CONCAT);
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_STRING_CONCAT_K3)
  {
    WL_POPN(1);
    Term _f_2 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_1 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _f_2;
      e.mem[_t_1 + 1] = _h_0;
      return term_tsk(FID_STRING_APPEND, _t_1);
    }
    r0 = _f_2;
    r1 = _h_0;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_U32_SHOW)
  {
    u32 _a_0 = r0;
    WL_OPEN
    u32 _s_0 = U32_BIN(_a_0, ==, 0);
    if (_s_0 == 1) {
      r0 = term_ctr(CID_SCON, STAT_OFF + 0);
      WL_RETN(1);
    } else {
      if (!DEVICE && !seq && fid_nofk(FID_U32_SHOW_GO)) {
        u64 _t_0 = task_node(e, FID_U32_SHOW_GO, WL_CONT, WL_IDX, 0);
        e.mem[_t_0 + 0] = 10ull;
        e.mem[_t_0 + 1] = _a_0;
        e.mem[_t_0 + 2] = term_pak(CID_SNIL, 0);
        return term_tsk(FID_U32_SHOW_GO, _t_0);
      }
      r0 = 10ull;
      r1 = _a_0;
      r2 = term_pak(CID_SNIL, 0);
      WL_JMP(FID_U32_SHOW_GO);
    }
  }}
#endif

#if !DEVICE
  WL_CASE(FID_TINYBENDYGRAD_HELPERS_I64_TEXT)
  {
    u32 _x_0 = r0;
    u32 _x_1 = r1;
    WL_OPEN
    u32 _v_0 = 0;
    u32 _v_1 = 0;
    Term _o_0[1];
    if (spin_0(e, _o_0, _x_0, _x_1) == 0) {
      return 0;
    }
    _v_1 = _o_0[0];
    _v_0 = _v_1;
    u32 _v_3 = 0;
    u32 _v_4 = 0;
    Term _o_1[1];
    if (spin_1(e, _o_1, _x_0, _x_1) == 0) {
      return 0;
    }
    _v_4 = _o_1[0];
    _v_3 = _v_4;
    if (seq) {
      WL_ROOM(2);
      STK(0) = _v_3;
      STK(1) = FID_TINYBENDYGRAD_HELPERS_I64_TEXT_K12;
      WL_PUSHN(2);
    } else {
      u64 _t_0 = task_node(e, FID_TINYBENDYGRAD_HELPERS_I64_TEXT_K12, WL_CONT, WL_IDX, 1);
      e.mem[_t_0 + 0] = _v_3;
      WL_CONT = term_tsk(FID_TINYBENDYGRAD_HELPERS_I64_TEXT_K12, _t_0);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_U32_SHOW)) {
      u64 _t_1 = task_node(e, FID_U32_SHOW, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _v_0;
      return term_tsk(FID_U32_SHOW, _t_1);
    }
    r0 = _v_0;
    WL_JMP(FID_U32_SHOW);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_TINYBENDYGRAD_HELPERS_I64_TEXT_K12)
  {
    WL_POPN(1);
    u32 _v_6 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _h_0;
      STK(1) = FID_TINYBENDYGRAD_HELPERS_I64_TEXT_K13;
      WL_PUSHN(2);
    } else {
      u64 _t_2 = task_node(e, FID_TINYBENDYGRAD_HELPERS_I64_TEXT_K13, WL_CONT, WL_IDX, 1);
      e.mem[_t_2 + 0] = _h_0;
      WL_CONT = term_tsk(FID_TINYBENDYGRAD_HELPERS_I64_TEXT_K13, _t_2);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_U32_SHOW)) {
      u64 _t_3 = task_node(e, FID_U32_SHOW, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = _v_6;
      return term_tsk(FID_U32_SHOW, _t_3);
    }
    r0 = _v_6;
    WL_JMP(FID_U32_SHOW);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_TINYBENDYGRAD_HELPERS_I64_TEXT_K13)
  {
    WL_POPN(1);
    Term _h_2 = STK(0);
    Term _h_1 = r0;
    WL_OPEN
    u64 _nd_0 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_0 + 0] = _h_1;
    e.mem[_nd_0 + 1] = term_pak(CID_NIL, 0);
    u64 _nd_1 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_1 + 0] = term_ctr(CID_SCON, STAT_OFF + 2);
    e.mem[_nd_1 + 1] = term_ctr(CID_CON, _nd_0);
    u64 _nd_2 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_2 + 0] = _h_2;
    e.mem[_nd_2 + 1] = term_ctr(CID_CON, _nd_1);
    if (!DEVICE && !seq && fid_nofk(FID_STRING_CONCAT)) {
      u64 _t_4 = task_node(e, FID_STRING_CONCAT, WL_CONT, WL_IDX, 0);
      e.mem[_t_4 + 0] = term_ctr(CID_CON, _nd_2);
      return term_tsk(FID_STRING_CONCAT, _t_4);
    }
    r0 = term_ctr(CID_CON, _nd_2);
    WL_JMP(FID_STRING_CONCAT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_STRING_APPEND)
  {
    Term _a_0 = r0;
    Term _b_0 = r1;
    WL_OPEN
    WL_SPIN
    if (term_aux(_a_0) == CID_SNIL) {
      r0 = _b_0;
      WL_RETN(1);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _a_0, 2, _fb_0);
      u32 _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      spare_free(e, cls_fit(2), _sp_0);
      if (seq) {
        WL_ROOM(2);
        STK(0) = _f_0;
        STK(1) = FID_STRING_APPEND_K15;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_STRING_APPEND_K15, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _f_0;
        WL_CONT = term_tsk(FID_STRING_APPEND_K15, _t_0);
        WL_IDX = 1;
      }
      r0 = _f_1;
      r1 = _b_0;
      _a_0 = r0;
      _b_0 = r1;
      WL_AGAIN(FID_STRING_APPEND);
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_STRING_APPEND_K15)
  {
    WL_POPN(1);
    u32 _f_2 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    u64 _nd_0 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_0 + 0] = _f_2;
    e.mem[_nd_0 + 1] = _h_0;
    r0 = term_ctr(CID_SCON, _nd_0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_IO_BIND)
  {
    Term _m_0 = r0;
    Term _f_0 = r1;
    Term _k_0 = r2;
    WL_OPEN
    u64 _nd_0 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_0 + 0] = _f_0;
    e.mem[_nd_0 + 1] = _k_0;
    if (!DEVICE && !seq && fid_nofk(FID_CLO_APPLY)) {
      u64 _t_3 = task_node(e, FID_CLO_APPLY, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = _m_0;
      e.mem[_t_3 + 1] = term_clo(FID_IO_BIND_C18, _nd_0);
      return term_tsk(FID_CLO_APPLY, _t_3);
    }
    r0 = _m_0;
    r1 = term_clo(FID_IO_BIND_C18, _nd_0);
    WL_JMP(FID_CLO_APPLY);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_IO_BIND_C18)
  {
    Term _f_1 = r0;
    Term _k_1 = r1;
    Term _x_0 = r2;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _k_1;
      STK(1) = FID_IO_BIND_K19;
      WL_PUSHN(2);
    } else {
      u64 _t_0 = task_node(e, FID_IO_BIND_K19, WL_CONT, WL_IDX, 1);
      e.mem[_t_0 + 0] = _k_1;
      WL_CONT = term_tsk(FID_IO_BIND_K19, _t_0);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_CLO_APPLY)) {
      u64 _t_1 = task_node(e, FID_CLO_APPLY, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _f_1;
      e.mem[_t_1 + 1] = _x_0;
      return term_tsk(FID_CLO_APPLY, _t_1);
    }
    r0 = _f_1;
    r1 = _x_0;
    WL_JMP(FID_CLO_APPLY);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_IO_BIND_K19)
  {
    WL_POPN(1);
    Term _k_2 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_CLO_APPLY)) {
      u64 _t_2 = task_node(e, FID_CLO_APPLY, WL_CONT, WL_IDX, 0);
      e.mem[_t_2 + 0] = _h_0;
      e.mem[_t_2 + 1] = _k_2;
      return term_tsk(FID_CLO_APPLY, _t_2);
    }
    r0 = _h_0;
    r1 = _k_2;
    WL_JMP(FID_CLO_APPLY);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN)
  {
    WL_OPEN
    r0 = term_clo(FID_MAIN_C21, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C21)
  {
    Term _x_0 = r0;
    WL_OPEN
    u64 _nd_0 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_0 + 0] = term_ctr(CID_TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 4);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_60 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_60 + 0] = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_I64_TRUNC, _nd_0);
      e.mem[_t_60 + 1] = term_clo(FID_MAIN_C22, 0);
      e.mem[_t_60 + 2] = _x_0;
      return term_tsk(FID_IO_BIND, _t_60);
    }
    r0 = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_I64_TRUNC, _nd_0);
    r1 = term_clo(FID_MAIN_C22, 0);
    r2 = _x_0;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C22)
  {
    Term _x_1 = r0;
    WL_OPEN
    Term _fb_0[2];
    u64 _sp_0 = ctr_take(e, _x_1, 2, _fb_0);
    u32 _f_0 = _fb_0[0];
    u32 _f_1 = _fb_0[1];
    spare_free(e, cls_fit(2), _sp_0);
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K23;
      WL_PUSHN(1);
    } else {
      u64 _t_0 = task_node(e, FID_MAIN_K23, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K23, _t_0);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_1 = task_node(e, FID_TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _f_0;
      e.mem[_t_1 + 1] = _f_1;
      return term_tsk(FID_TINYBENDYGRAD_HELPERS_I64_TEXT, _t_1);
    }
    r0 = _f_0;
    r1 = _f_1;
    WL_JMP(FID_TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K23)
  {
    Term _h_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K24;
      WL_PUSHN(1);
    } else {
      u64 _t_2 = task_node(e, FID_MAIN_K24, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K24, _t_2);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_3 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = term_ctr(CID_SCON, STAT_OFF + 38);
      e.mem[_t_3 + 1] = _h_0;
      return term_tsk(FID_STRING_APPEND, _t_3);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 38);
    r1 = _h_0;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K24)
  {
    Term _h_1 = r0;
    WL_OPEN
    u64 _nd_1 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_1 + 0] = _h_1;
    r0 = term_clo(FID_MAIN_C25, _nd_1);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C25)
  {
    Term _h_2 = r0;
    Term _x_2 = r1;
    WL_OPEN
    u64 _nd_2 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_2 + 0] = _h_2;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_59 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_59 + 0] = term_clo(FID_IO_PRINT, _nd_2);
      e.mem[_t_59 + 1] = term_clo(FID_MAIN_C26, 0);
      e.mem[_t_59 + 2] = _x_2;
      return term_tsk(FID_IO_BIND, _t_59);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_2);
    r1 = term_clo(FID_MAIN_C26, 0);
    r2 = _x_2;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C26)
  {
    Term _x_3 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C27, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C27)
  {
    Term _x_4 = r0;
    WL_OPEN
    u64 _nd_3 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_3 + 0] = term_ctr(CID_TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 40);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_58 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_58 + 0] = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_I64_TRUNC, _nd_3);
      e.mem[_t_58 + 1] = term_clo(FID_MAIN_C28, 0);
      e.mem[_t_58 + 2] = _x_4;
      return term_tsk(FID_IO_BIND, _t_58);
    }
    r0 = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_I64_TRUNC, _nd_3);
    r1 = term_clo(FID_MAIN_C28, 0);
    r2 = _x_4;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C28)
  {
    Term _x_5 = r0;
    WL_OPEN
    Term _fb_1[2];
    u64 _sp_1 = ctr_take(e, _x_5, 2, _fb_1);
    u32 _f_2 = _fb_1[0];
    u32 _f_3 = _fb_1[1];
    spare_free(e, cls_fit(2), _sp_1);
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K29;
      WL_PUSHN(1);
    } else {
      u64 _t_4 = task_node(e, FID_MAIN_K29, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K29, _t_4);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_5 = task_node(e, FID_TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_5 + 0] = _f_2;
      e.mem[_t_5 + 1] = _f_3;
      return term_tsk(FID_TINYBENDYGRAD_HELPERS_I64_TEXT, _t_5);
    }
    r0 = _f_2;
    r1 = _f_3;
    WL_JMP(FID_TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K29)
  {
    Term _h_3 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K30;
      WL_PUSHN(1);
    } else {
      u64 _t_6 = task_node(e, FID_MAIN_K30, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K30, _t_6);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_7 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_7 + 0] = term_ctr(CID_SCON, STAT_OFF + 68);
      e.mem[_t_7 + 1] = _h_3;
      return term_tsk(FID_STRING_APPEND, _t_7);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 68);
    r1 = _h_3;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K30)
  {
    Term _h_4 = r0;
    WL_OPEN
    u64 _nd_4 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_4 + 0] = _h_4;
    r0 = term_clo(FID_MAIN_C31, _nd_4);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C31)
  {
    Term _h_5 = r0;
    Term _x_6 = r1;
    WL_OPEN
    u64 _nd_5 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_5 + 0] = _h_5;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_57 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_57 + 0] = term_clo(FID_IO_PRINT, _nd_5);
      e.mem[_t_57 + 1] = term_clo(FID_MAIN_C32, 0);
      e.mem[_t_57 + 2] = _x_6;
      return term_tsk(FID_IO_BIND, _t_57);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_5);
    r1 = term_clo(FID_MAIN_C32, 0);
    r2 = _x_6;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C32)
  {
    Term _x_7 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C33, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C33)
  {
    Term _x_8 = r0;
    WL_OPEN
    u64 _nd_6 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_6 + 0] = term_ctr(CID_TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 70);
    e.mem[_nd_6 + 1] = term_ctr(CID_TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 72);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_56 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_56 + 0] = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV, _nd_6);
      e.mem[_t_56 + 1] = term_clo(FID_MAIN_C34, 0);
      e.mem[_t_56 + 2] = _x_8;
      return term_tsk(FID_IO_BIND, _t_56);
    }
    r0 = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV, _nd_6);
    r1 = term_clo(FID_MAIN_C34, 0);
    r2 = _x_8;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C34)
  {
    Term _x_9 = r0;
    WL_OPEN
    Term _fb_2[2];
    u64 _sp_2 = ctr_take(e, _x_9, 2, _fb_2);
    u32 _f_4 = _fb_2[0];
    u32 _f_5 = _fb_2[1];
    spare_free(e, cls_fit(2), _sp_2);
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K35;
      WL_PUSHN(1);
    } else {
      u64 _t_8 = task_node(e, FID_MAIN_K35, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K35, _t_8);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_9 = task_node(e, FID_TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_9 + 0] = _f_4;
      e.mem[_t_9 + 1] = _f_5;
      return term_tsk(FID_TINYBENDYGRAD_HELPERS_I64_TEXT, _t_9);
    }
    r0 = _f_4;
    r1 = _f_5;
    WL_JMP(FID_TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K35)
  {
    Term _h_6 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K36;
      WL_PUSHN(1);
    } else {
      u64 _t_10 = task_node(e, FID_MAIN_K36, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K36, _t_10);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_11 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_11 + 0] = term_ctr(CID_SCON, STAT_OFF + 100);
      e.mem[_t_11 + 1] = _h_6;
      return term_tsk(FID_STRING_APPEND, _t_11);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 100);
    r1 = _h_6;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K36)
  {
    Term _h_7 = r0;
    WL_OPEN
    u64 _nd_7 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_7 + 0] = _h_7;
    r0 = term_clo(FID_MAIN_C37, _nd_7);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C37)
  {
    Term _h_8 = r0;
    Term _x_10 = r1;
    WL_OPEN
    u64 _nd_8 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_8 + 0] = _h_8;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_55 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_55 + 0] = term_clo(FID_IO_PRINT, _nd_8);
      e.mem[_t_55 + 1] = term_clo(FID_MAIN_C38, 0);
      e.mem[_t_55 + 2] = _x_10;
      return term_tsk(FID_IO_BIND, _t_55);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_8);
    r1 = term_clo(FID_MAIN_C38, 0);
    r2 = _x_10;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C38)
  {
    Term _x_11 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C39, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C39)
  {
    Term _x_12 = r0;
    WL_OPEN
    u64 _nd_9 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_9 + 0] = term_ctr(CID_TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 70);
    e.mem[_nd_9 + 1] = term_ctr(CID_TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 102);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_54 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_54 + 0] = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV, _nd_9);
      e.mem[_t_54 + 1] = term_clo(FID_MAIN_C40, 0);
      e.mem[_t_54 + 2] = _x_12;
      return term_tsk(FID_IO_BIND, _t_54);
    }
    r0 = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV, _nd_9);
    r1 = term_clo(FID_MAIN_C40, 0);
    r2 = _x_12;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C40)
  {
    Term _x_13 = r0;
    WL_OPEN
    Term _fb_3[2];
    u64 _sp_3 = ctr_take(e, _x_13, 2, _fb_3);
    u32 _f_6 = _fb_3[0];
    u32 _f_7 = _fb_3[1];
    spare_free(e, cls_fit(2), _sp_3);
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K41;
      WL_PUSHN(1);
    } else {
      u64 _t_12 = task_node(e, FID_MAIN_K41, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K41, _t_12);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_13 = task_node(e, FID_TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_13 + 0] = _f_6;
      e.mem[_t_13 + 1] = _f_7;
      return term_tsk(FID_TINYBENDYGRAD_HELPERS_I64_TEXT, _t_13);
    }
    r0 = _f_6;
    r1 = _f_7;
    WL_JMP(FID_TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K41)
  {
    Term _h_9 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K42;
      WL_PUSHN(1);
    } else {
      u64 _t_14 = task_node(e, FID_MAIN_K42, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K42, _t_14);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_15 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_15 + 0] = term_ctr(CID_SCON, STAT_OFF + 130);
      e.mem[_t_15 + 1] = _h_9;
      return term_tsk(FID_STRING_APPEND, _t_15);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 130);
    r1 = _h_9;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K42)
  {
    Term _h_10 = r0;
    WL_OPEN
    u64 _nd_10 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_10 + 0] = _h_10;
    r0 = term_clo(FID_MAIN_C43, _nd_10);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C43)
  {
    Term _h_11 = r0;
    Term _x_14 = r1;
    WL_OPEN
    u64 _nd_11 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_11 + 0] = _h_11;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_53 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_53 + 0] = term_clo(FID_IO_PRINT, _nd_11);
      e.mem[_t_53 + 1] = term_clo(FID_MAIN_C44, 0);
      e.mem[_t_53 + 2] = _x_14;
      return term_tsk(FID_IO_BIND, _t_53);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_11);
    r1 = term_clo(FID_MAIN_C44, 0);
    r2 = _x_14;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C44)
  {
    Term _x_15 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C45, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C45)
  {
    Term _x_16 = r0;
    WL_OPEN
    u64 _nd_12 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_12 + 0] = term_ctr(CID_TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 70);
    e.mem[_nd_12 + 1] = term_ctr(CID_TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 132);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_52 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_52 + 0] = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV, _nd_12);
      e.mem[_t_52 + 1] = term_clo(FID_MAIN_C46, 0);
      e.mem[_t_52 + 2] = _x_16;
      return term_tsk(FID_IO_BIND, _t_52);
    }
    r0 = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV, _nd_12);
    r1 = term_clo(FID_MAIN_C46, 0);
    r2 = _x_16;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C46)
  {
    Term _x_17 = r0;
    WL_OPEN
    Term _fb_4[2];
    u64 _sp_4 = ctr_take(e, _x_17, 2, _fb_4);
    u32 _f_8 = _fb_4[0];
    u32 _f_9 = _fb_4[1];
    spare_free(e, cls_fit(2), _sp_4);
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K47;
      WL_PUSHN(1);
    } else {
      u64 _t_16 = task_node(e, FID_MAIN_K47, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K47, _t_16);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_17 = task_node(e, FID_TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_17 + 0] = _f_8;
      e.mem[_t_17 + 1] = _f_9;
      return term_tsk(FID_TINYBENDYGRAD_HELPERS_I64_TEXT, _t_17);
    }
    r0 = _f_8;
    r1 = _f_9;
    WL_JMP(FID_TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K47)
  {
    Term _h_12 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K48;
      WL_PUSHN(1);
    } else {
      u64 _t_18 = task_node(e, FID_MAIN_K48, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K48, _t_18);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_19 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_19 + 0] = term_ctr(CID_SCON, STAT_OFF + 160);
      e.mem[_t_19 + 1] = _h_12;
      return term_tsk(FID_STRING_APPEND, _t_19);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 160);
    r1 = _h_12;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K48)
  {
    Term _h_13 = r0;
    WL_OPEN
    u64 _nd_13 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_13 + 0] = _h_13;
    r0 = term_clo(FID_MAIN_C49, _nd_13);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C49)
  {
    Term _h_14 = r0;
    Term _x_18 = r1;
    WL_OPEN
    u64 _nd_14 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_14 + 0] = _h_14;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_51 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_51 + 0] = term_clo(FID_IO_PRINT, _nd_14);
      e.mem[_t_51 + 1] = term_clo(FID_MAIN_C50, 0);
      e.mem[_t_51 + 2] = _x_18;
      return term_tsk(FID_IO_BIND, _t_51);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_14);
    r1 = term_clo(FID_MAIN_C50, 0);
    r2 = _x_18;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C50)
  {
    Term _x_19 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C51, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C51)
  {
    Term _x_20 = r0;
    WL_OPEN
    u64 _nd_15 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_15 + 0] = 1069547520ull;
    e.mem[_nd_15 + 1] = 0ull;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_50 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_50 + 0] = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_FP8_FROM, _nd_15);
      e.mem[_t_50 + 1] = term_clo(FID_MAIN_C52, 0);
      e.mem[_t_50 + 2] = _x_20;
      return term_tsk(FID_IO_BIND, _t_50);
    }
    r0 = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_FP8_FROM, _nd_15);
    r1 = term_clo(FID_MAIN_C52, 0);
    r2 = _x_20;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C52)
  {
    Term _x_21 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K53;
      WL_PUSHN(1);
    } else {
      u64 _t_20 = task_node(e, FID_MAIN_K53, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K53, _t_20);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_U32_SHOW)) {
      u64 _t_21 = task_node(e, FID_U32_SHOW, WL_CONT, WL_IDX, 0);
      e.mem[_t_21 + 0] = _x_21;
      return term_tsk(FID_U32_SHOW, _t_21);
    }
    r0 = _x_21;
    WL_JMP(FID_U32_SHOW);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K53)
  {
    Term _h_15 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K54;
      WL_PUSHN(1);
    } else {
      u64 _t_22 = task_node(e, FID_MAIN_K54, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K54, _t_22);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_23 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_23 + 0] = term_ctr(CID_SCON, STAT_OFF + 192);
      e.mem[_t_23 + 1] = _h_15;
      return term_tsk(FID_STRING_APPEND, _t_23);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 192);
    r1 = _h_15;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K54)
  {
    Term _h_16 = r0;
    WL_OPEN
    u64 _nd_16 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_16 + 0] = _h_16;
    r0 = term_clo(FID_MAIN_C55, _nd_16);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C55)
  {
    Term _h_17 = r0;
    Term _x_22 = r1;
    WL_OPEN
    u64 _nd_17 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_17 + 0] = _h_17;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_49 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_49 + 0] = term_clo(FID_IO_PRINT, _nd_17);
      e.mem[_t_49 + 1] = term_clo(FID_MAIN_C56, 0);
      e.mem[_t_49 + 2] = _x_22;
      return term_tsk(FID_IO_BIND, _t_49);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_17);
    r1 = term_clo(FID_MAIN_C56, 0);
    r2 = _x_22;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C56)
  {
    Term _x_23 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C57, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C57)
  {
    Term _x_24 = r0;
    WL_OPEN
    u64 _nd_18 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_18 + 0] = 1069547520ull;
    e.mem[_nd_18 + 1] = 2ull;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_48 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_48 + 0] = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_FP8_FROM, _nd_18);
      e.mem[_t_48 + 1] = term_clo(FID_MAIN_C58, 0);
      e.mem[_t_48 + 2] = _x_24;
      return term_tsk(FID_IO_BIND, _t_48);
    }
    r0 = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_FP8_FROM, _nd_18);
    r1 = term_clo(FID_MAIN_C58, 0);
    r2 = _x_24;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C58)
  {
    Term _x_25 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K59;
      WL_PUSHN(1);
    } else {
      u64 _t_24 = task_node(e, FID_MAIN_K59, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K59, _t_24);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_U32_SHOW)) {
      u64 _t_25 = task_node(e, FID_U32_SHOW, WL_CONT, WL_IDX, 0);
      e.mem[_t_25 + 0] = _x_25;
      return term_tsk(FID_U32_SHOW, _t_25);
    }
    r0 = _x_25;
    WL_JMP(FID_U32_SHOW);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K59)
  {
    Term _h_18 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K60;
      WL_PUSHN(1);
    } else {
      u64 _t_26 = task_node(e, FID_MAIN_K60, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K60, _t_26);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_27 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_27 + 0] = term_ctr(CID_SCON, STAT_OFF + 226);
      e.mem[_t_27 + 1] = _h_18;
      return term_tsk(FID_STRING_APPEND, _t_27);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 226);
    r1 = _h_18;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K60)
  {
    Term _h_19 = r0;
    WL_OPEN
    u64 _nd_19 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_19 + 0] = _h_19;
    r0 = term_clo(FID_MAIN_C61, _nd_19);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C61)
  {
    Term _h_20 = r0;
    Term _x_26 = r1;
    WL_OPEN
    u64 _nd_20 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_20 + 0] = _h_20;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_47 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_47 + 0] = term_clo(FID_IO_PRINT, _nd_20);
      e.mem[_t_47 + 1] = term_clo(FID_MAIN_C62, 0);
      e.mem[_t_47 + 2] = _x_26;
      return term_tsk(FID_IO_BIND, _t_47);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_20);
    r1 = term_clo(FID_MAIN_C62, 0);
    r2 = _x_26;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C62)
  {
    Term _x_27 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C63, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C63)
  {
    Term _x_28 = r0;
    WL_OPEN
    u64 _nd_21 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_21 + 0] = 1069547520ull;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_46 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_46 + 0] = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_BF16, _nd_21);
      e.mem[_t_46 + 1] = term_clo(FID_MAIN_C64, 0);
      e.mem[_t_46 + 2] = _x_28;
      return term_tsk(FID_IO_BIND, _t_46);
    }
    r0 = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_BF16, _nd_21);
    r1 = term_clo(FID_MAIN_C64, 0);
    r2 = _x_28;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C64)
  {
    Term _x_29 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K65;
      WL_PUSHN(1);
    } else {
      u64 _t_28 = task_node(e, FID_MAIN_K65, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K65, _t_28);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_29 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_29 + 0] = term_ctr(CID_SCON, STAT_OFF + 250);
      e.mem[_t_29 + 1] = f32_show(e, _x_29);
      return term_tsk(FID_STRING_APPEND, _t_29);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 250);
    r1 = f32_show(e, _x_29);
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K65)
  {
    Term _h_21 = r0;
    WL_OPEN
    u64 _nd_22 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_22 + 0] = _h_21;
    r0 = term_clo(FID_MAIN_C66, _nd_22);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C66)
  {
    Term _h_22 = r0;
    Term _x_30 = r1;
    WL_OPEN
    u64 _nd_23 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_23 + 0] = _h_22;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_45 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_45 + 0] = term_clo(FID_IO_PRINT, _nd_23);
      e.mem[_t_45 + 1] = term_clo(FID_MAIN_C67, 0);
      e.mem[_t_45 + 2] = _x_30;
      return term_tsk(FID_IO_BIND, _t_45);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_23);
    r1 = term_clo(FID_MAIN_C67, 0);
    r2 = _x_30;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C67)
  {
    Term _x_31 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C68, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C68)
  {
    Term _x_32 = r0;
    WL_OPEN
    u64 _nd_24 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_24 + 0] = 1069547520ull;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_44 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_44 + 0] = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_FP16, _nd_24);
      e.mem[_t_44 + 1] = term_clo(FID_MAIN_C69, 0);
      e.mem[_t_44 + 2] = _x_32;
      return term_tsk(FID_IO_BIND, _t_44);
    }
    r0 = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_FP16, _nd_24);
    r1 = term_clo(FID_MAIN_C69, 0);
    r2 = _x_32;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C69)
  {
    Term _x_33 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K70;
      WL_PUSHN(1);
    } else {
      u64 _t_30 = task_node(e, FID_MAIN_K70, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K70, _t_30);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_31 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_31 + 0] = term_ctr(CID_SCON, STAT_OFF + 264);
      e.mem[_t_31 + 1] = f32_show(e, _x_33);
      return term_tsk(FID_STRING_APPEND, _t_31);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 264);
    r1 = f32_show(e, _x_33);
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K70)
  {
    Term _h_23 = r0;
    WL_OPEN
    u64 _nd_25 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_25 + 0] = _h_23;
    r0 = term_clo(FID_MAIN_C71, _nd_25);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C71)
  {
    Term _h_24 = r0;
    Term _x_34 = r1;
    WL_OPEN
    u64 _nd_26 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_26 + 0] = _h_24;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_43 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_43 + 0] = term_clo(FID_IO_PRINT, _nd_26);
      e.mem[_t_43 + 1] = term_clo(FID_MAIN_C72, 0);
      e.mem[_t_43 + 2] = _x_34;
      return term_tsk(FID_IO_BIND, _t_43);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_26);
    r1 = term_clo(FID_MAIN_C72, 0);
    r2 = _x_34;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C72)
  {
    Term _x_35 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C73, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C73)
  {
    Term _x_36 = r0;
    WL_OPEN
    u64 _nd_27 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_27 + 0] = 1066192077ull;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_42 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_42 + 0] = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_FP16, _nd_27);
      e.mem[_t_42 + 1] = term_clo(FID_MAIN_C74, 0);
      e.mem[_t_42 + 2] = _x_36;
      return term_tsk(FID_IO_BIND, _t_42);
    }
    r0 = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_FP16, _nd_27);
    r1 = term_clo(FID_MAIN_C74, 0);
    r2 = _x_36;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C74)
  {
    Term _x_37 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K75;
      WL_PUSHN(1);
    } else {
      u64 _t_32 = task_node(e, FID_MAIN_K75, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K75, _t_32);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_33 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_33 + 0] = term_ctr(CID_SCON, STAT_OFF + 288);
      e.mem[_t_33 + 1] = f32_show(e, _x_37);
      return term_tsk(FID_STRING_APPEND, _t_33);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 288);
    r1 = f32_show(e, _x_37);
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K75)
  {
    Term _h_25 = r0;
    WL_OPEN
    u64 _nd_28 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_28 + 0] = _h_25;
    r0 = term_clo(FID_MAIN_C76, _nd_28);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C76)
  {
    Term _h_26 = r0;
    Term _x_38 = r1;
    WL_OPEN
    u64 _nd_29 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_29 + 0] = _h_26;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_41 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_41 + 0] = term_clo(FID_IO_PRINT, _nd_29);
      e.mem[_t_41 + 1] = term_clo(FID_MAIN_C77, 0);
      e.mem[_t_41 + 2] = _x_38;
      return term_tsk(FID_IO_BIND, _t_41);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_29);
    r1 = term_clo(FID_MAIN_C77, 0);
    r2 = _x_38;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C77)
  {
    Term _x_39 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C78, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C78)
  {
    Term _x_40 = r0;
    WL_OPEN
    u64 _nd_30 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_30 + 0] = f32_rewrap(-f32_unbox(1074790400ull));
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_40 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_40 + 0] = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_FP16, _nd_30);
      e.mem[_t_40 + 1] = term_clo(FID_MAIN_C79, 0);
      e.mem[_t_40 + 2] = _x_40;
      return term_tsk(FID_IO_BIND, _t_40);
    }
    r0 = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_FP16, _nd_30);
    r1 = term_clo(FID_MAIN_C79, 0);
    r2 = _x_40;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C79)
  {
    Term _x_41 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K80;
      WL_PUSHN(1);
    } else {
      u64 _t_34 = task_node(e, FID_MAIN_K80, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K80, _t_34);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_35 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_35 + 0] = term_ctr(CID_SCON, STAT_OFF + 316);
      e.mem[_t_35 + 1] = f32_show(e, _x_41);
      return term_tsk(FID_STRING_APPEND, _t_35);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 316);
    r1 = f32_show(e, _x_41);
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K80)
  {
    Term _h_27 = r0;
    WL_OPEN
    u64 _nd_31 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_31 + 0] = _h_27;
    r0 = term_clo(FID_MAIN_C81, _nd_31);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C81)
  {
    Term _h_28 = r0;
    Term _x_42 = r1;
    WL_OPEN
    u64 _nd_32 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_32 + 0] = _h_28;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_39 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_39 + 0] = term_clo(FID_IO_PRINT, _nd_32);
      e.mem[_t_39 + 1] = term_clo(FID_MAIN_C82, 0);
      e.mem[_t_39 + 2] = _x_42;
      return term_tsk(FID_IO_BIND, _t_39);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_32);
    r1 = term_clo(FID_MAIN_C82, 0);
    r2 = _x_42;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C82)
  {
    Term _x_43 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C83, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C83)
  {
    Term _x_44 = r0;
    WL_OPEN
    u64 _nd_33 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_33 + 0] = 60ull;
    e.mem[_nd_33 + 1] = 0ull;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_38 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_38 + 0] = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_FP8_TO, _nd_33);
      e.mem[_t_38 + 1] = term_clo(FID_MAIN_C84, 0);
      e.mem[_t_38 + 2] = _x_44;
      return term_tsk(FID_IO_BIND, _t_38);
    }
    r0 = term_clo(FID_TINYBENDYGRAD_DTYPE_DT_FP8_TO, _nd_33);
    r1 = term_clo(FID_MAIN_C84, 0);
    r2 = _x_44;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C84)
  {
    Term _x_45 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K85;
      WL_PUSHN(1);
    } else {
      u64 _t_36 = task_node(e, FID_MAIN_K85, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K85, _t_36);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_37 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_37 + 0] = term_ctr(CID_SCON, STAT_OFF + 346);
      e.mem[_t_37 + 1] = f32_show(e, _x_45);
      return term_tsk(FID_STRING_APPEND, _t_37);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 346);
    r1 = f32_show(e, _x_45);
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K85)
  {
    Term _h_29 = r0;
    WL_OPEN
    u64 _nd_34 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_34 + 0] = _h_29;
    r0 = term_clo(FID_IO_PRINT, _nd_34);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_TINYBENDYGRAD_DTYPE_DT_I64_TRUNC)
  {
    Term _x_2 = r0;
    Term _k_7 = r1;
    WL_OPEN
    u64 _nd_7 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_7 + 0] = _x_2;
    e.mem[_nd_7 + 1] = _k_7;
    r0 = term_ctr(CID_TINYBENDYGRAD_DTYPE_DT_I64_TRUNC, _nd_7);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_IO_PRINT)
  {
    Term _text_1 = r0;
    Term _k_8 = r1;
    WL_OPEN
    u64 _nd_8 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_8 + 0] = _text_1;
    e.mem[_nd_8 + 1] = _k_8;
    r0 = term_ctr(CID_IO_PRINT, _nd_8);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV)
  {
    Term _a_1 = r0;
    Term _b_1 = r1;
    Term _k_9 = r2;
    WL_OPEN
    u64 _nd_9 = heap_alloc(e, cls_fit(3));
    e.mem[_nd_9 + 0] = _a_1;
    e.mem[_nd_9 + 1] = _b_1;
    e.mem[_nd_9 + 2] = _k_9;
    r0 = term_ctr(CID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV, _nd_9);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_TINYBENDYGRAD_DTYPE_DT_FP8_FROM)
  {
    Term _bits_3 = r0;
    Term _kind_2 = r1;
    Term _k_10 = r2;
    WL_OPEN
    u64 _nd_10 = heap_alloc(e, cls_fit(3));
    e.mem[_nd_10 + 0] = _bits_3;
    e.mem[_nd_10 + 1] = _kind_2;
    e.mem[_nd_10 + 2] = _k_10;
    r0 = term_ctr(CID_TINYBENDYGRAD_DTYPE_DT_FP8_FROM, _nd_10);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_TINYBENDYGRAD_DTYPE_DT_BF16)
  {
    Term _bits_4 = r0;
    Term _k_11 = r1;
    WL_OPEN
    u64 _nd_11 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_11 + 0] = _bits_4;
    e.mem[_nd_11 + 1] = _k_11;
    r0 = term_ctr(CID_TINYBENDYGRAD_DTYPE_DT_BF16, _nd_11);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_TINYBENDYGRAD_DTYPE_DT_FP16)
  {
    Term _x_3 = r0;
    Term _k_12 = r1;
    WL_OPEN
    u64 _nd_12 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_12 + 0] = _x_3;
    e.mem[_nd_12 + 1] = _k_12;
    r0 = term_ctr(CID_TINYBENDYGRAD_DTYPE_DT_FP16, _nd_12);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_TINYBENDYGRAD_DTYPE_DT_FP8_TO)
  {
    Term _bits_5 = r0;
    Term _kind_3 = r1;
    Term _k_13 = r2;
    WL_OPEN
    u64 _nd_13 = heap_alloc(e, cls_fit(3));
    e.mem[_nd_13 + 0] = _bits_5;
    e.mem[_nd_13 + 1] = _kind_3;
    e.mem[_nd_13 + 2] = _k_13;
    r0 = term_ctr(CID_TINYBENDYGRAD_DTYPE_DT_FP8_TO, _nd_13);
    WL_RETN(1);
  }}
#endif

  WL_CASE(FID_ENTER)
  {
    Term t = r0;
    WL_OPEN
    u32 f   = (u32)term_aux(t);
    u64 a   = term_loc(t);
    u32 war = fid_arity(f);
    WL_FRAME(t)
    seq |= fid_nofk(f) << 1;
    u32 rw = fid_resw(f);
    if (rw) {
      WL_LOAD(a + war - rw, rw)
      WL_ARGS(a, war - rw + 1)
    } else {
      WL_LOAD(a, war)
    }
    heap_free(e, cls_fit(war + 2), a);
    WL_DYN(f);
  }}

  WL_CASE(FID_IO_EMIT)
  {
    Term x = r0;
    WL_OPEN
    u64 l = heap_alloc(e, 0);
    e.mem[l] = x;
    r0 = term_ctr(CID_EMIT, l);
    WL_RETN(1);
  }}

  WL_CASE(FID_CLO_APPLY)
  {
    Term fun = r0;
    Term arg = r1;
    WL_OPEN
    u32 f    = (u32)term_aux(fun);
    u32 war  = fid_arity(f) - 1;
    u64 a    = term_loc(fun);
    WL_LOAD(a, war)
    spare_free(e, cls_fit(war), a);
    WL_LAST(arg)
    WL_DYN(f);
  }}

  WL_CASE(FID_EXIT)
  {
    u32  n = rn;
    Term rv[WL_RESW];
    WL_SAVE(rv)
    WL_OPEN
    if (err_seen(e.mem)) {
      return 0;
    }
    sp -= 2 * LANE_STEP;
    Term cont = STK(0);
    u32  idx  = (u32)STK(1);
    u32  wf   = (u32)term_aux(cont);
    if (cont != TERM_HOLE && fid_resw(wf)) {
      u64 wa = term_loc(cont);
      u32 wn = fid_arity(wf);
      WL_FRAME(cont)
      seq = (seq & 1) | fid_nofk(wf) << 1;
      WL_ARGS(wa, wn - n + 1)
      heap_free(e, cls_fit(wn + 2), wa);
      WL_TAKE(rv)
      WL_DYN(wf);
    }
    return task_deliver(e.mem, cont, idx, rv, n);
  }}

#if DEVICE
  default: {
    err_post(e.mem, ERR_FIDS);
    return 0;
  }
  }
  }
}
#endif

// Monk
// ====

// One turn on a ring: its head task below put0 runs (a growing
// lane skips a fork-free one). The host grows a row ring by
// ring and drains a ring; a device lane does both.
INLINE u32 monk_step(Env e, DEV Term* stk, u32 rg, u32 put0, u32 base, u32 stride,
  TG u32* cur) {
  DEV u64* H   = e.mem;
  bool     seq = stride == 0;
  DEV u32* get = ring_get(H, rg);
  if (*get == put0) {
    return 0;
  }
  DEV u32* lo = (DEV u32*)ring_slot(H, rg, *get);
  u32      hi = a32_load_acq(lo + 1);
  Term     t  = (((u64)hi << 32) | a32_load(lo)) & ~RFC_BIT;
  if ((hi >> 31) != ring_lap(*get) || (!seq && fid_nofk((u32)term_aux(t)))) {
    return 0;
  }
  a32_store(get, *get + 1);
  u32 spin = 0;
  for (;;) {
    Term r = work_loop(e, stk, t, seq);
    if (r == 0) {
      return 2;
    }
    if ((u32)H[task_tail(r) + 1] == 0) {
      if (err_spun(H, &spin)) {
        return 2;
      }
      if (stride != 0 && fid_nofk((u32)term_aux(r))) {
        ring_push(H, ring_pick(base, stride, cur), r);
        return 2;
      }
      t      = r;
      seq    = false;
      stride = 0;
      continue;
    }
    task_deal(H, r, base, stride, cur);
    return 1;
  }
}

// Dev
// ===

// One kernel: pass 0 grows the frontier, pass 1 drains each lane's ring,
// pass 2 packs the banks: in one group, each bank's [top, wr) slides onto
// rd, CUBE_T entries a step (loads, barrier, stores: rd <= top), off the
// host's pages. A grow pass ends when its group is full or nothing grew,
// so a spine of forks unrolls whole. TG_HOLD words of threadgroup memory
// hold one group per Apple core (bitonic 1.35x without).

#if DEVICE

INLINE void dev_cut(Env e) {
  if (err_seen(e.mem)) {
    return;
  }
  for (u32 c = 0; c < NCLS_ALL; c += 1) {
    u64 gen = (u64)KEEP(c) << c;
    while (ALC_LEN(e, c) >= gen) {
      u64 head = ALC_AT(e, c);
      u64 tail = head;
      for (u32 i = 1; i < KEEP(c); i += 1) {
        tail = e.mem[tail];
      }
      ALC_AT(e, c)    = e.mem[tail];
      ALC_LEN(e, c)  -= gen;
      e.mem[tail]     = 0;
      bank_push(e.mem, c, head);
    }
  }
}

INLINE void bank_pack(DEV u64* H, u32 lane) {
  for (u32 c = 0; c < NCLS_ALL; c += 1) {
    DEV Bank* b  = bank_at(H, c);
    u32       rd = b->rd;
    u32       n  = b->wr - b->top;
    for (u32 i = 0; i < n; i += CUBE_T) {
      Term v = i + lane < n ? H[b->off + b->top + i + lane] : 0;
      BAR();
      if (i + lane < n) {
        H[b->off + rd + i + lane] = v;
      }
    }
    BAR();
    if (lane == 0) {
      b->rd = b->wr = b->top = rd + n;
    }
  }
}

#ifdef __METAL_VERSION__
kernel void bend_dev(DEV u64* H [[buffer(0)]], constant u32& pass [[buffer(1)]],
  TG u32* vote [[threadgroup(0)]],
  u32 grids [[threadgroups_per_grid]],
  u32 row [[threadgroup_position_in_grid]],
  u32 lane [[thread_position_in_threadgroup]]) {
#else
extern "C" __global__ void bend_dev(DEV u64* H, u32 pass) {
  extern __shared__ u32 vote[];
  u32 grids = gridDim.x;
  u32 row   = blockIdx.x;
  u32 lane  = threadIdx.x;
#endif
  if (pass == 2) {
    bank_pack(H, lane);
    return;
  }
  u32  stride = grids == 1 ? CUBE_G : 1;
  u32  me     = row * CUBE_T + stride * lane;
  u32 rg     = pass ? ring_flip(me) : me;
  Env  e      = { H, H + ALC_OFF + me };
  DEV Term*  stk    = (DEV Term*)(H + STAK_OFF + me);
  if (lane == 0) {
    for (u32 i = 0; i < 3; i += 1) {
      a32_store(vote + i, 0);
    }
  }
  BAR();
  u32 put0      = a32_load(ring_put(H, rg));
  u32 seen_has  = 0;
  u32 seen_grew = 0;
  for (;;) {
    if (pass) {
      if (*ring_get(H, rg) == put0 || err_seen(H)) {
        break;
      }
    } else {
      put0 = a32_load(ring_put(H, rg));
      u32 has = put0 != a32_load(ring_get(H, rg));
      if (lane == 0 && (err_seen(H) || root_done(H))) {
        has = CUBE_T;
      }
      a32_add(vote + 2, has);
      BAR();
      has = a32_load(vote + 2);
      if (has - seen_has >= CUBE_T) {
        break;
      }
      seen_has = has;
    }
    u32 ran = monk_step(e, stk, rg, put0, row * CUBE_T, pass ? 0 : stride,
      vote);
    if (!pass) {
      if (ran == 1) {
        a32_add(vote + 1, 1);
      }
      BARD();
      u32 grew = a32_load(vote + 1);
      if (grew == seen_grew) {
        break;
      }
      seen_grew = grew;
    }
  }
  dev_cut(e);
}

#endif

// Window
// ======

// Linux's window fill (the Mac's is window_msl): an Image is a quadtree over
// 2^k x 2^k (Qua splits tl, tr, bl, br; Pix is 0xRRGGBB).
#if defined(__linux__) || defined(BEND_RTC)

INLINE u32 window_pix(DEV u64* H, Term t, u32 k, u32 x, u32 y) {
  for (u32 i = k; term_tag(t) == TAG_CTR;) {
    u32 j = 0;
    if (i > 0) {
      i -= 1;
      j = ((y >> i) & 1) * 2 + ((x >> i) & 1);
    }
    t = H[term_peek(H, t) + j];
  }
  return (u32)term_loc(t) & 0xFFFFFF;
}

#ifdef BEND_RTC
extern "C" __global__ void window_dev(DEV u64* H, Term root, u32 w, u32 h,
  u32 k, u32* out) {
  u32 x = blockIdx.x * blockDim.x + threadIdx.x;
  u32 y = blockIdx.y * blockDim.y + threadIdx.y;
  if (x < w && y < h) {
    out[y * w + x] = window_pix(H, root, k, x, y);
  }
}
#endif

#endif

#if !DEVICE

// Row
// ===

static void row_grow(Env e, DEV Term* stk, u32 base, u32 stride, u32 want) {
  u64* H = e.mem;
  u32 cur = 0;
  for (;;) {
    u32 put0[CUBE_T];
    u32 has = 0;
    for (u32 i = 0; i < CUBE_T; i += 1) {
      put0[i] = *ring_put(H, base + i * stride);
      has += put0[i] != *ring_get(H, base + i * stride);
    }
    if (root_done(H) || has >= want) {
      return;
    }
    u32 grew = 0;
    u32 ran  = 0;
    for (u32 i = 0; i < CUBE_T && ran != 2; i += 1) {
      ran   = monk_step(e, stk, base + i * stride, put0[i], base, stride,
        &cur);
      grew += ran == 1;
    }
    if (grew == 0) {
      return;
    }
  }
}

// Pool
// ====

static void* pool_try(void* at, u64 bytes) {
  return mmap(at, bytes, PROT_READ | PROT_WRITE,
    MAP_PRIVATE | MAP_ANON | MAP_NORESERVE, -1, 0);
}

static void* pool_mmap(u64 bytes) {
  void* p = pool_try(NULL, bytes);
  if (p == MAP_FAILED) {
    err_fail("reservation failed");
  }
  return p;
}

static Term* pool_stack(void) {
  u64   len = 1ull << 31;
  char* p   = pool_mmap(len + 16384 + SIGSTKSZ);
  if (mprotect(p + len, 16384, PROT_NONE) != 0) {
    err_fail("stack guard failed");
  }
  stack_t ss = { .ss_sp = p + len + 16384, .ss_size = SIGSTKSZ };
  sigaltstack(&ss, NULL);
  struct sigaction sa = { .sa_handler = err_trap, .sa_flags = SA_ONSTACK };
  sigaction(SIGSEGV, &sa, NULL);
  sigaction(SIGBUS, &sa, NULL);
  return (Term*)p;
}

static void* pool_work(void* arg) {
  Term* stk  = pool_stack();
  u32   seen = 0;
  for (;;) {
    pthread_mutex_lock(&pool_lock);
    while (pool_tick == seen) {
      pthread_cond_wait(&pool_wake, &pool_lock);
    }
    seen = pool_tick;
    pthread_mutex_unlock(&pool_lock);
    Env e = { CORPUS, ALC[1 + (u32)(uintptr_t)arg] };
    for (;;) {
      u32 r = a32_add(&pool_row, 1);
      if (r >= (pool_grow ? CUBE_G : LANES / LINE)) {
        break;
      }
      if (pool_grow) {
        row_grow(e, stk, r * CUBE_T, 1, CUBE_T);
      } else {
        u32  step = CUBE_T / LINE;
        u32 row  = r / step * CUBE_T;
        for (u32 rg = row + r % step; rg < row + CUBE_T; rg += step) {
          u32 put0 = a32_load(ring_put(e.mem, rg));
          while (*ring_get(e.mem, rg) != put0 && !err_seen(e.mem)) {
            monk_step(e, stk, rg, put0, rg, 0, NULL);
          }
        }
      }
    }
    if (a32_sub_rel(&pool_done, 1) == 1) {
      pthread_mutex_lock(&pool_lock);
      pthread_cond_broadcast(&pool_wake);
      pthread_mutex_unlock(&pool_lock);
    }
  }
}

OUTLINE void pool_open(void) {
  static bool up;
  if (up) {
    return;
  }
  up = true;
  for (u32 w = 0; w < pool_size; w += 1) {
    pthread_t tid;
    if (pthread_create(&tid, NULL, pool_work, (void*)(uintptr_t)w)) {
      err_fail("pthread_create");
    }
  }
}

static int cpu_read(const char* path, long* a, long* b) {
  FILE* f = fopen(path, "r");
  if (f == NULL) {
    return 0;
  }
  int n = fscanf(f, "%ld %ld", a, b);
  fclose(f);
  return n;
}

static long cpu_count(void) {
  long n = sysconf(_SC_NPROCESSORS_ONLN);
#ifdef __linux__
  cpu_set_t set;
  if (sched_getaffinity(0, sizeof set, &set) == 0) {
    n = CPU_COUNT(&set);
  }
  long q = 0;
  long p = 0;
  if (cpu_read("/sys/fs/cgroup/cpu.max", &q, &p) != 2) {
    cpu_read("/sys/fs/cgroup/cpu/cpu.cfs_quota_us", &q, &p);
    cpu_read("/sys/fs/cgroup/cpu/cpu.cfs_period_us", &p, &p);
  }
  if (q > 0 && p > 0 && (q + p - 1) / p < n) {
    n = (q + p - 1) / p;
  }
#endif
  return n;
}

OUTLINE void pool_turn(bool grow) {
  pool_grow = grow;
  a32_store(&pool_row, 0);
  a32_store(&pool_done, pool_size);
  pthread_mutex_lock(&pool_lock);
  pool_tick += 1;
  pthread_cond_broadcast(&pool_wake);
  while (a32_load_acq(&pool_done) != 0) {
    pthread_cond_wait(&pool_wake, &pool_lock);
  }
  pthread_mutex_unlock(&pool_lock);
}

// Gpu
// ===

// gpu_make compiles the device program into <binary>.gpu
// (--gpu-build): Metal's binary archive, or CUDA's cubin behind a
// hash of the text. A launch loads it, else notes and compiles. CUDA
// shapes the bag by the device: a group of 128 lanes per 64 KB of
// L2, a power of two in 16..128 (Apple keeps the tuned 128). CUDA
// runs one stream: the default 8 cost about half of the startup.

static const char* gpu_path(void) {
  static char path[4096];
  u32 n = sizeof path - 8;
#ifdef __APPLE__
  _NSGetExecutablePath(path, &n);
#else
  path[readlink("/proc/self/exe", path, n)] = 0;
#endif
  return strcat(path, ".gpu");
}

static void gpu_note(const char* path) {
  fprintf(stderr, "bend: compiling the GPU program (%s is missing or"
    " stale)\n", path);
}

#if !BEND_CUDA
#define gpu_map pool_mmap
#endif

#if BEND_METAL || BEND_CUDA

static void gpu_kernel(u32 pass, u32 groups);

static void gpu_run(u32 f) {
  if (f < CUBE_T) {
    gpu_kernel(0, 1);
  }
  if (f < LANES) {
    gpu_kernel(0, CUBE_G);
  }
  gpu_kernel(1, CUBE_G);
  gpu_kernel(2, 1);
}

#endif

#if BEND_CUDA

static u64 gpu_hash(void) {
  u64 key = 14695981039346656037ull ^ CUBE_LOG;
  for (const char* p = BEND_SRC; *p != 0; p += 1) {
    key = (key ^ (u8)*p) * 1099511628211ull;
  }
  return key;
}

#endif

#if BEND_METAL

static void gpu_fail(NSError* err) {
  err_fail([[err localizedDescription] UTF8String]);
}

static bool gpu_probe(void) {
  return (gpu_dev = MTLCreateSystemDefaultDevice()) != nil;
}

static MTLComputePipelineDescriptor* gpu_desc(void) {
  NSError* err = nil;
  MTLCompileOptions* opts = [MTLCompileOptions new];
  opts.mathMode = MTLMathModeSafe;
  opts.preprocessorMacros = @{ @"CUBE_LOG": @(CUBE_LOG) };
  id<MTLLibrary> lib = [gpu_dev newLibraryWithSource:@(BEND_SRC) options:opts
    error:&err];
  if (!lib) {
    gpu_fail(err);
  }
  MTLComputePipelineDescriptor* d = [MTLComputePipelineDescriptor new];
  d.computeFunction = [lib newFunctionWithName:@"bend_dev"];
  return d;
}

static bool gpu_make(const char* path) {
  NSError* err = nil;
  id<MTLBinaryArchive> ar = [gpu_dev
    newBinaryArchiveWithDescriptor:[MTLBinaryArchiveDescriptor new] error:&err];
  if (![ar addComputePipelineFunctionsWithDescriptor:gpu_desc() error:&err]) {
    gpu_fail(err);
  }
  return [ar serializeToURL:[NSURL fileURLWithPath:@(path)] error:&err];
}

static id<MTLComputePipelineState> gpu_pipe(MTLComputePipelineDescriptor* d,
  id<MTLBinaryArchive> ar) {
  NSError* err = nil;
  d.binaryArchives = ar ? @[ar] : @[];
  id<MTLComputePipelineState> pso = [gpu_dev
    newComputePipelineStateWithDescriptor:d
    options:ar ? MTLPipelineOptionFailOnBinaryArchiveMiss : 0 reflection:nil
    error:&err];
  if (!pso && !ar) {
    gpu_fail(err);
  }
  return pso;
}

static u64 gpu_span(void) {
  u64 span = [gpu_dev recommendedMaxWorkingSetSize];
  u64 most = [gpu_dev maxBufferLength];
  span = span < most ? span : most;
  return span < (2ull << 30) ? span : 2ull << 30;
}

static void gpu_load(u64 bytes) {
  gpu_buf = [gpu_dev newBufferWithBytesNoCopy:CORPUS length:bytes
    options:MTLResourceStorageModeShared
      | MTLResourceHazardTrackingModeUntracked deallocator:nil];
  u64 most = [gpu_dev maxBufferLength];
  if (!gpu_buf && bytes > most) {
    char msg[96];
    snprintf(msg, sizeof msg, "--gpu %lluMB is over the device's %lluMB",
      (unsigned long long)(bytes >> 20), (unsigned long long)(most >> 20));
    err_fail(msg);
  }
  if (!gpu_buf) {
    err_fail("the GPU span is more than the device has");
  }
  @autoreleasepool {
    gpu_que = [gpu_dev newCommandQueue];
    const char* path = gpu_path();
    MTLBinaryArchiveDescriptor* ad = [MTLBinaryArchiveDescriptor new];
    ad.url = [NSURL fileURLWithPath:@(path)];
    MTLComputePipelineDescriptor* d = gpu_desc();
    id<MTLBinaryArchive> ar = [gpu_dev newBinaryArchiveWithDescriptor:ad
      error:nil];
    gpu_pso = ar ? gpu_pipe(d, ar) : nil;
    if (!gpu_pso) {
      gpu_note(path);
      gpu_pso = gpu_pipe(d, nil);
    }
  }
}

static void gpu_kernel(u32 pass, u32 groups) {
  [gpu_enc setComputePipelineState:gpu_pso];
  [gpu_enc setBuffer:gpu_buf offset:0 atIndex:0];
  [gpu_enc setBytes:&pass length:sizeof pass atIndex:1];
  [gpu_enc setThreadgroupMemoryLength:TG_HOLD * 8 atIndex:0];
  [gpu_enc dispatchThreadgroups:MTLSizeMake(groups, 1, 1)
    threadsPerThreadgroup:MTLSizeMake(CUBE_T, 1, 1)];
  [gpu_enc memoryBarrierWithScope:MTLBarrierScopeBuffers];
}

static void gpu_pass(u32 f) {
  @autoreleasepool {
    id<MTLCommandBuffer> cb = [gpu_que commandBuffer];
    gpu_enc = [cb computeCommandEncoder];
    gpu_run(f);
    [gpu_enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    if ([cb error]) {
      gpu_fail([cb error]);
    }
  }
}

#elif BEND_CUDA

static void gpu_shape(int units) {
  CUBE_LOG = 31 - CLZ(units < 16 ? 16 : units > 128 ? 128 : units);
}

static bool gpu_probe(void) {
  int       managed = 0;
  CUcontext ctx;
  setenv("CUDA_DEVICE_MAX_CONNECTIONS", "1", 0);
  if (cuInit(0) == CUDA_SUCCESS && cuDeviceGet(&gpu_dev, 0) == CUDA_SUCCESS) {
    cuDeviceGetAttribute(&managed,
      CU_DEVICE_ATTRIBUTE_CONCURRENT_MANAGED_ACCESS, gpu_dev);
  }
  int l2 = 1 << 23;
  cuDeviceGetAttribute(&l2, CU_DEVICE_ATTRIBUTE_L2_CACHE_SIZE, gpu_dev);
  gpu_shape(l2 >> 16);
  return managed != 0
    && cuDevicePrimaryCtxRetain(&ctx, gpu_dev) == CUDA_SUCCESS
    && cuCtxSetCurrent(ctx) == CUDA_SUCCESS;
}

static u64* gpu_map(u64 bytes) {
  CUdeviceptr p = 0;
  if (cuMemAllocManaged(&p, bytes, CU_MEM_ATTACH_GLOBAL) != CUDA_SUCCESS) {
    err_fail("corpus reservation failed");
  }
#if CUDA_VERSION >= 13000
  cuMemAdvise(p, bytes, CU_MEM_ADVISE_SET_PREFERRED_LOCATION,
    (CUmemLocation){ CU_MEM_LOCATION_TYPE_DEVICE, gpu_dev });
#else
  cuMemAdvise(p, bytes, CU_MEM_ADVISE_SET_PREFERRED_LOCATION, gpu_dev);
#endif
  return (u64*)(uintptr_t)p;
}

static bool gpu_make(const char* path) {
  int cc[2] = {0, 0};
  cuDeviceGetAttribute(cc,
    CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, gpu_dev);
  cuDeviceGetAttribute(cc + 1,
    CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, gpu_dev);
  char arch[40];
  char bag[24];
  snprintf(arch, sizeof arch, "--gpu-architecture=sm_%d%d", cc[0], cc[1]);
  snprintf(bag, sizeof bag, "-DCUBE_LOG=%u", CUBE_LOG);
  const char* opts[] = { arch, bag, "--fmad=false", "-default-device" };
  nvrtcProgram prog;
  if (nvrtcCreateProgram(&prog, BEND_SRC, "bend.cu", 0, NULL, NULL)
    != NVRTC_SUCCESS) {
    err_fail("cannot compile the CUDA library");
  }
  if (nvrtcCompileProgram(prog, 4, opts) != NVRTC_SUCCESS) {
    size_t n = 0;
    nvrtcGetProgramLogSize(prog, &n);
    char* log = calloc(n + 1, 1);
    if (log != NULL && nvrtcGetProgramLog(prog, log) == NVRTC_SUCCESS) {
      fprintf(stderr, "%s\n", log);
    }
    err_fail("cannot compile the CUDA library");
  }
  size_t len = 0;
  nvrtcGetCUBINSize(prog, &len);
  char* bin = malloc(len);
  if (bin == NULL || nvrtcGetCUBIN(prog, bin) != NVRTC_SUCCESS) {
    err_fail("cannot load the CUDA library");
  }
  nvrtcDestroyProgram(&prog);
  u64   key = gpu_hash();
  FILE* out = path == NULL ? NULL : fopen(path, "wb");
  bool  ok  = out != NULL && fwrite(&key, 8, 1, out) == 1
    && fwrite(bin, 1, len, out) == len && fclose(out) == 0;
  if (cuModuleLoadData(&gpu_lib, bin) != CUDA_SUCCESS) {
    err_fail("cannot load the CUDA library");
  }
  free(bin);
  return path == NULL || ok;
}

static u64 gpu_span(void) {
  size_t span = 0;
  cuDeviceTotalMem(&span, gpu_dev);
  return span;
}

static void gpu_load(u64 bytes) {
  const char* path = gpu_path();
  int         fd   = open(path, O_RDONLY);
  struct stat st   = { 0 };
  u64         key  = 0;
  char*       bin  = fd < 0 || fstat(fd, &st) != 0 || st.st_size <= 8 ? NULL
    : mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  if (bin != NULL && bin != MAP_FAILED) {
    memcpy(&key, bin, 8);
  }
  if (key != gpu_hash()
    || cuModuleLoadData(&gpu_lib, bin + 8) != CUDA_SUCCESS) {
    gpu_note(path);
    gpu_make(path);
  }
  if (cuModuleGetFunction(&gpu_pso, gpu_lib, "bend_dev") != CUDA_SUCCESS) {
    err_fail("cannot load the GPU program");
  }
}

static void gpu_kernel(u32 pass, u32 groups) {
  void* args[] = { &CORPUS, &pass };
  if (cuLaunchKernel(gpu_pso, groups, 1, 1, CUBE_T, 1, 1, TG_HOLD * 8, NULL,
    args, NULL) != CUDA_SUCCESS) {
    err_fail("device launch failed");
  }
}

static void gpu_pass(u32 f) {
  gpu_run(f);
  if (cuCtxSynchronize() != CUDA_SUCCESS) {
    err_fail("device fault");
  }
}

#else

#define gpu_probe() false
#define gpu_make(p) true
#define gpu_span()  0
#define gpu_load(b)
#define gpu_pass(f)

#endif

// Cube
// ====

// Under a row per thread, the host's column grows to a row per thread: a
// row is CUBE_T / LINE units, and each touches a page of every plane.

static void cube_run(u64* H, bool gpu) {
  for (;;) {
    u32 f = a32_exch(a32_at(H, H_CURSOR), 0);
    if (root_done(H)) {
      return;
    }
    if (f == 0) {
      err_fail("frontier drained without a result");
    }
    if (gpu) {
      gpu_pass(f);
    } else {
      if (f < pool_size) {
        row_grow((Env){ H, ALC[0] }, io_stk, 0, CUBE_G, pool_size);
      }
      if (f < CUBE) {
        pool_turn(true);
      }
      pool_turn(false);
    }
    u32 ec = a32_load(a32_at(H, H_ERROR_CODE));
    if (ec != 0) {
      err_post(H, ec);
    }
  }
}

// Corpus
// ======

// The cores map 8 GiB at a high base and double it in place, so one
// base holds every location; the banks move up past the pages. The GPU maps
// its whole span at once, and never grows it.

static u64 corpus_size;

static void* corpus_map(u64 size) {
  u64   hint = 1ull << 45;
  void* p    = pool_try((void*)hint, size);
  while (p != (void*)hint && hint > size) {
    if (p != MAP_FAILED) {
      munmap(p, size);
    }
    hint /= 2;
    p     = pool_try((void*)hint, size);
  }
  if (p == MAP_FAILED) {
    err_fail("reservation failed");
  }
  return p;
}

static void corpus_lay(u64* H, u64 size) {
  u64 span = size / 8;
  u64 cap  = span > HEAP_OFF ? (span - HEAP_OFF) / (PAGE_LEN + 10) : 0;
  if (cap <= CUBE) {
    err_fail("the GPU span is under the rings, stacks and a page per lane");
  }
  cap = cap < ~0u ? cap : ~0u - 1;
  u64 at = HEAP_OFF + (cap << PAGE_BITS);
  for (u32 c = 0; c < NCLS_ALL; c += 1) {
    Bank* b = bank_at(H, c);
    memcpy(H + at, H + b->off, b->wr * sizeof(u64));
    b->off  = at;
    at     += 2 * (cap >> ((c < NCLS ? NCLS : c) - PAGE_BITS));
  }
  corpus_size = size;
  a32_store_rel(a32_at(H, H_CAP), (u32)cap);
}

static bool corpus_grow(u64* H, u64 need) {
  bool ok = true;
  LOCK(bank_lock);
  while (ok && need > a32_load(a32_at(H, H_CAP))) {
    u64   more = corpus_size;
    char* at   = (char*)H + more;
    void* got  = io_gpu || more >= 1ull << 43 ? MAP_FAILED
      : pool_try(at, more);
    ok = got == at;
    if (ok) {
      corpus_lay(H, more * 2);
    } else if (got != MAP_FAILED) {
      munmap(got, more);
    }
  }
  UNLOCK(bank_lock);
  return ok;
}

static u64* corpus_setup(bool gpu, long threads, u64 bytes) {
  io_gpu     = gpu;
  KEEP_WORDS = gpu ? CHUNK : CAP_WORDS;
  u64 dflt   = gpu ? gpu_span() : 1ull << 33;
  u64 size   = (gpu && bytes != 0 ? bytes : dflt) & ~16383ull;
  CORPUS     = gpu ? gpu_map(size) : corpus_map(size);
  u64* H     = CORPUS;
#if BEND_CUDA
  if (gpu) {
    cuMemsetD8((CUdeviceptr)(uintptr_t)H, 0, STAK_OFF * 8);
    cuCtxSynchronize();
  }
#endif
  corpus_lay(H, size);
  memcpy(H + STAT_OFF, STAT_IMG, STAT_LEN * sizeof(u64));
  a32_store(a32_at(H, H_BUMP), 1);
  if (gpu) {
    gpu_load(size);
  }
  pool_size = threads < 1 ? 1 : threads < CUBE_T ? threads : CUBE_T;
  return H;
}

OUTLINE Term corpus_eval(u64* H, Term t) {
  Env  e = { H, ALC[0] };
  Term rv[WL_RESW];
  for (;;) {
    Term r = work_loop(e, io_stk, t, !BANGS && pool_size == 1);
    if (r == 0) {
      if (root_done(H)) {
        break;
      }
      err_fail("solo delivery lost");
    }
    if ((u32)H[task_tail(r) + 1] == 0) {
      t = r;
      if (io_gpu && fid_bangs((u32)term_aux(t))) {
        u64  tl   = task_tail(t);
        Term cont = H[tl];
        u32  idx  = (u32)(H[tl + 1] >> 32) & 0xFFFF;
        H[tl]     = TERM_HOLE;
        a32_store(a32_at(H, H_CURSOR), 1);
        ring_push(H, 0, t);
        cube_run(H, true);
        Term p = task_deliver(H, cont, idx, rv, root_take(H, rv));
        if (root_done(H)) {
          break;
        }
        if (p == 0) {
          err_fail("seam delivery lost");
        }
        t = p;
      }
      continue;
    }
    task_deal(H, r, 0, 0, NULL);
    pool_open();
    cube_run(H, false);
    break;
  }
  root_take(H, rv);
  return rv[0];
}

// Io
// ==

// Base's opaque, linear handles pack host fds or pointers into aux and loc:
// no forging, copying, reuse or host wrapper. A request's cont applied to
// its item is the next request. A parked request keeps its fd, deadline and
// readiness in word, time and evts; the loop then calls pack: a value
// resumes, IO_PARK parks again. The edge is UTF-8, decoded as WHATWG does: a
// broken sequence yields one U+FFFD and its breaking byte is read again as a
// lead. inet_aton reads a leading zero as octal, so io_sys_addr refuses it.
// macOS poll misses FIFO EOF, so io_wait selects, its sets sized to the
// highest fd (_DARWIN_UNLIMITED_SELECT allows fds past FD_SETSIZE).

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>

#define IO_READ 1
#define IO_TIME 2
#define IO_PARK TERM_HOLE

#define io_hand(v)   term_make(TAG_PAK, (u64)(v) >> 40, (u64)(v) & LOC_MASK)
#define io_hand_v(t) (((u64)term_aux(t) << 40) | term_loc(t))

struct IoWork;
typedef void (*IoCall)(struct IoWork* w);
typedef Term (*IoPack)(Env e, struct IoWork* w);

typedef struct IoWork {
  intptr_t       hand;
  intptr_t       made;
  u32            word;
  u64            size;
  char*          data;
  char*          text;
  u32            code;
  IoCall         call;
  IoPack         pack;
  Term           cont;
  Term           item;
  u64            time;
  short          evts;
  struct IoWork* next;
} IoWork;

typedef Term (*Effect)(Env e, Term* f, IoWork* w);

typedef struct {
  Effect run;
  u32    ask;
} IoEff;

static IoEff io_eff_rows[1 << 16];
static u32   io_live;

static u64 io_tick(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (u64)ts.tv_sec * 1000000000ull + (u64)ts.tv_nsec;
}

OUTLINE void* io_mem(void* mem) {
  if (mem == NULL) {
    err_fail("host allocation failed");
  }
  return mem;
}

static int io_sys_addr(const char* host, u32 port, struct sockaddr_in* at) {
  memset(at, 0, sizeof(*at));
  at->sin_family = AF_INET;
  at->sin_port   = htons((uint16_t)port);
  for (const char* p = host; *p != 0; p += 1) {
    if ((p == host || p[-1] == '.') && *p == '0'
      && p[1] >= '0' && p[1] <= '9') {
      return -1;
    }
  }
  return port > 65535 || inet_pton(AF_INET, host, &at->sin_addr) != 1
    ? -1 : 0;
}

static int    io_argc;
static char** io_argv;

static void io_eff(u32 cid, Effect run, u32 need) {
  if (io_eff_rows[cid].run != NULL) {
    err_fail("two effects register one request");
  }
  io_eff_rows[cid] = (IoEff){ run, need };
}

static u64 io_sys_end(IoWork* w, ssize_t n) {
  w->code = n < 0 ? (u32)errno : 0;
  return n < 0 ? 0 : (u64)n;
}

static IoWork* io_runs;
static IoWork* io_park;
static IoWork* io_jobs;

static void io_push(IoWork** q, IoWork* a) {
  IoWork* l = *q != NULL ? *q : a;
  a->next = l->next;
  l->next = a;
  *q      = a;
}

static IoWork* io_pop(IoWork** q) {
  IoWork* a  = (*q)->next;
  (*q)->next = a->next;
  *q         = a != *q ? *q : NULL;
  return a;
}

static void io_spawn(Term m) {
  IoWork* a = io_mem(calloc(1, sizeof(IoWork)));
  a->cont  = m;
  a->item  = term_clo(FID_IO_EMIT, 0);
  io_push(&io_runs, a);
  io_live += 1;
}

// io_park stays in deadline order (time 0, none, sorts last; ties keep
// their park order), so io_wait wakes due timers in the order they expire.
static void io_park_add(IoWork* w) {
  IoWork* p = io_park;
  if (p == NULL || p->time - 1 <= w->time - 1) {
    io_push(&io_park, w);
    return;
  }
  while (p->next->time - 1 <= w->time - 1) {
    p = p->next;
  }
  io_push(&p, w);
}

static Term io_wait_on(IoWork* w, int fd, short evts, u64 time, IoPack more) {
  w->word = (u32)fd;
  w->pack = more;
  w->time = time;
  w->evts = evts;
  io_park_add(w);
  return IO_PARK;
}

OUTLINE void io_out(FILE* h, const char* data, u64 len) {
  if (fwrite(data, 1, len, h) != len) {
    err_fail("a short write on a standard stream");
  }
}

OUTLINE void io_sync(void) {
  if (fflush(stdout) != 0) {
    err_fail("a short write on a standard stream");
  }
}

static u64 io_utf8(char* buf, u64 c) {
  u64 k = c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
  for (u64 i = k; i > 1; i -= 1) {
    buf[i - 1] = (char)(0x80 | (c & 0x3F));
    c >>= 6;
  }
  buf[0] = (char)(k == 1 ? c : (0xF00 >> k) | c);
  return k;
}

// io_cbuf writes a String (cons SCon) as UTF-8, or a List (cons Con) as
// its bytes, with no UTF-8: NULL if a value is past 255.
OUTLINE char* io_cbuf(Env e, Term s, u64* len, u64 cons) {
  u64   cap = 64;
  u64   n   = 0;
  u64   bad = 0;
  char* buf = io_mem(malloc(cap));
  while (term_aux(s) == cons) {
    Term fb[2];
    spare_free(e, cls_fit(2), ctr_take(e, s, 2, fb));
    if (n + 5 > cap) {
      cap *= 2;
      buf = io_mem(realloc(buf, cap));
    }
    if (cons == CID_SCON) {
      n += io_utf8(buf + n, fb[0]);
    } else {
      bad |= fb[0] > 255;
      buf[n++] = (char)fb[0];
    }
    s = fb[1];
  }
  buf[n] = 0;
  *len = n;
  if (bad) {
    free(buf);
    return NULL;
  }
  return buf;
}

#define io_cstr(e, s, len) io_cbuf(e, s, len, CID_SCON)

OUTLINE void io_errs(Env e, Term s) {
  u64   n    = 0;
  char* text = io_cstr(e, s, &n);
  io_sync();
  io_out(stderr, text, n);
  io_out(stderr, "\n", 1);
  free(text);
}

#define io_nul(s, n) (strlen(s) != (n))

#define io_seal(e, t, cid) (cid_hot(cid) ? rfc_seal(e, t) : (t))

static Term io_node(Env e, u64 cid, Term a, Term b) {
  u64 l = heap_alloc(e, 1);
  e.mem[l]     = io_seal(e, a, cid);
  e.mem[l + 1] = io_seal(e, b, cid);
  return term_ctr(cid, l);
}

static Term io_str(Env e, const char* p, u64 n) {
  Term s    = term_pak(CID_SNIL, 0);
  u64  hole = 0;
  u64  c = 0, need = 0, lo = 0x80, hi = 0xBF;
  for (u64 i = 0; i < n || need > 0; i += 1) {
    u64 b = i < n ? (uint8_t)p[i] : 0x100;
    if (need > 0 && (b < lo || b > hi)) {
      need = 0;
      c    = 0xFFFD;
      i   -= 1;
    } else if (need > 0) {
      lo = 0x80;
      hi = 0xBF;
      c  = (c << 6) | (b & 0x3F);
      if (--need > 0) {
        continue;
      }
    } else if (b < 0x80) {
      c = b;
    } else if (b < 0xC2 || b > 0xF4) {
      c = 0xFFFD;
    } else {
      need = b < 0xE0 ? 1 : b < 0xF0 ? 2 : 3;
      lo   = b == 0xE0 ? 0xA0 : b == 0xF0 ? 0x90 : 0x80;
      hi   = b == 0xED ? 0x9F : b == 0xF4 ? 0x8F : 0xBF;
      c    = b & (0x3F >> need);
      continue;
    }
    u64  l = heap_alloc(e, 1);
    Term t = term_ctr(CID_SCON, l);
    e.mem[l] = c;
    if (hole == 0) {
      s = t;
    } else {
      e.mem[hole] = io_seal(e, t, CID_SCON);
    }
    hole = l + 1;
  }
  if (hole != 0) {
    e.mem[hole] = io_seal(e, term_pak(CID_SNIL, 0), CID_SCON);
  }
  return s;
}

// Bytes cross as they are (0..255), one List cell each, with no UTF-8.
#ifdef CID_CON

static Term io_list(Env e, const char* p, u64 n) {
  Term xs = term_pak(CID_NIL, 0);
  for (u64 i = n; i > 0; i -= 1) {
    xs = io_node(e, CID_CON, (uint8_t)p[i - 1], xs);
  }
  return xs;
}

#endif

#define io_tup(e, a, b) io_node(e, CID_TUPLE, a, b)
#define io_done(e, v)   io_box(e, CID_DONE, v)
#define io_res(e, w, v) ((w)->code ? io_fail(e, (w)->code, NULL) \
  : io_done(e, v))

static Term io_box(Env e, u64 cid, Term v) {
  u64 l = heap_alloc(e, 0);
  e.mem[l] = io_seal(e, v, cid);
  return term_ctr(cid, l);
}

static Term io_fail(Env e, u32 code, const char* text) {
  const char* s = text != NULL ? text : strerror((int)code);
  Term t = io_tup(e, code, io_str(e, s, strlen(s)));
  return io_box(e, CID_FAIL, t);
}

static pthread_mutex_t io_gate = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  io_bell = PTHREAD_COND_INITIALIZER;
static u32             io_busy;
static u32             io_size;
static int             io_wake_fd[2];

static void io_take(Env e) {
  IoWork* acts[64];
  ssize_t n;
  while ((n = read(io_wake_fd[0], acts, sizeof acts)) > 0) {
    for (u32 i = 0; i < (u32)n / sizeof(IoWork*); i += 1) {
      IoWork* a = acts[i];
      a->item   = a->pack(e, a);
      io_push(&io_runs, a);
      io_busy -= 1;
    }
  }
}

static void* io_help(void* arg) {
  for (;;) {
    pthread_mutex_lock(&io_gate);
    while (io_jobs == NULL) {
      pthread_cond_wait(&io_bell, &io_gate);
    }
    IoWork* a = io_pop(&io_jobs);
    pthread_mutex_unlock(&io_gate);
    a->call(a);
    while (write(io_wake_fd[1], &a, sizeof a) != sizeof a) {
    }
  }
}

static Term io_work(IoWork* w, IoCall call, IoPack pack) {
  w->call  = call;
  w->pack  = pack;
  io_busy += 1;
  if (io_busy > io_size && io_size < IO_HELP) {
    pthread_t tid;
    if (pthread_create(&tid, NULL, io_help, NULL)) {
      err_fail("pthread_create");
    }
    pthread_detach(tid);
    io_size += 1;
  }
  pthread_mutex_lock(&io_gate);
  io_push(&io_jobs, w);
  pthread_cond_signal(&io_bell);
  pthread_mutex_unlock(&io_gate);
  return IO_PARK;
}

static Term io_exec(Env e, IoWork* w) {
  Term fs[256];
  u32  c = (u32)term_aux(w->cont);
  u32  n = cid_arity(c);
  spare_free(e, cls_fit(n), ctr_take(e, w->cont, n, fs));
  w->cont = fs[n - 1];
  return io_eff_rows[c].run(e, fs, w);
}

static bool io_bit(u8* set, int fd, bool put) {
  u8* at = set + fd / 8;
  *at |= put << fd % 8;
  return *at >> fd % 8 & 1;
}

static void io_wait(Env e) {
  int top  = io_wake_fd[0];
  u64 soon = io_park != NULL ? io_park->next->time : 0;
  for (IoWork* a = io_park; a != NULL;
    a = a->next != io_park ? a->next : NULL) {
    if (a->evts != 0 && (int)a->word > top) {
      top = (int)a->word;
    }
  }
  u64 len = (u64)top / 64 * 8 + 8;
  u8* set[2] = { io_mem(calloc(2, len)), NULL };
  set[1] = set[0] + len;
  io_bit(set[0], io_wake_fd[0], true);
  for (IoWork* a = io_park; a != NULL;
    a = a->next != io_park ? a->next : NULL) {
    if (a->evts != 0) {
      io_bit(set[a->evts == POLLOUT], (int)a->word, true);
    }
  }
  u64 tick = io_tick();
  u64 ms = soon > tick ? (soon - tick) / 1000000 + 1 : 0;
  struct timeval tv = { ms / 1000, ms % 1000 * 1000 };
  io_sync();
  if (select(top + 1, (fd_set*)set[0], (fd_set*)set[1], NULL,
    soon == 0 ? NULL : &tv) < 0) {
    if (errno != EINTR) {
      err_fail("the poller failed");
    }
    memset(set[0], 0, 2 * len);
  }
  if (io_bit(set[0], io_wake_fd[0], false)) {
    io_take(e);
  }
  u64     now  = io_tick();
  IoWork* todo = io_park;
  io_park = NULL;
  while (todo != NULL) {
    IoWork* a   = io_pop(&todo);
    bool    due = (a->evts != 0
        && io_bit(set[a->evts == POLLOUT], (int)a->word, false))
      || (a->time != 0 && a->time <= now);
    if (!due) {
      io_park_add(a);
      continue;
    }
    Term x = a->pack(e, a);
    if (x != IO_PARK) {
      a->item = x;
      io_push(&io_runs, a);
    }
  }
  free(set[0]);
}

static int f32_text(char* buf, f32 v) {
  int n = 0;
  int p = 0;
  if (v != v) {
    return sprintf(buf, "nan");
  }
  for (; p < 9; p += 1) {
    n = snprintf(buf, 40, "%.*e", p, (double)v);
    if (strtof(buf, NULL) == v) {
      break;
    }
  }
  char* ep = strchr(buf, 'e');
  if (ep == NULL) {
    return n;
  }
  int ex = atoi(ep + 1);
  if (ex >= 21 || ex <= -7) {
    n = (int)(ep - buf) + sprintf(ep, "e%c%d", ex < 0 ? '-' : '+', abs(ex));
  } else if (ex <= p) {
    n = snprintf(buf, 40, "%.*f", p - ex, (double)v);
  } else {
    int s = *buf == '-';
    memmove(buf + s + 1, buf + s + 2, p);
    memset(buf + s + 1 + p, '0', ex - p);
    n = s + 1 + ex;
  }
  return n;
}

static Term f32_show(Env e, Term x) {
  char buf[40];
  return io_str(e, buf, f32_text(buf, f32_unbox(x)));
}

static Term f32_read(Env e, Term s) {
  u64 n = 0;
  char* text = io_cstr(e, s, &n);
  char* end;
  f32 v = strtof(text, &end);
  Term out = n > 0 && (u64)(end - text) == n && strpbrk(text, "xX(") == NULL
    ? io_box(e, CID_SOME, f32_rewrap(v)) : term_pak(CID_NONE, 0);
  free(text);
  return out;
}


// Show
// ====

// show_val prints a pure main's value as term_show spells it: d
// is a SHOW_DESC node (see show_main), w its words, and chain the
// bracket of the [a, b] or (a, b) the value continues, or 0. Con
// or Nil spell a list, Tuple a tuple, and their tails continue
// it. show_chr escapes as char_show does; show_f32 prints the
// shortest text that reads back, with a point before an e.

#if MAIN_PURE

static void show_val(Env e, u32 d, const Term* w, char chain);

static void show_chr(u64 c, char q) {
  char b[4];
  int  k = c == 10 ? 'n' : c == 9 ? 't' : c == 13 ? 'r' : c == 0 ? '0'
    : c == 92 || c == (u64)q ? (int)c : 0;
  if (k != 0) {
    printf("\\%c", k);
  } else if (c < 32 || c == 127 || (c >= 0xD800 && c <= 0xDFFF)
    || c > 0x10FFFF) {
    printf("\\u{%llx}", (unsigned long long)c);
  } else {
    fwrite(b, 1, io_utf8(b, c), stdout);
  }
}

static void show_f32(u32 x) {
  char  buf[40];
  int   n  = f32_text(buf, f32_unbox(x));
  char* ep = memchr(buf, 'e', n);
  int   m  = ep == NULL ? n : (int)(ep - buf);
  buf[n] = 0;
  if (strpbrk(buf, ".ni") == NULL) {
    printf("%.*s.0%s", m, buf, buf + m);
  } else {
    fputs(buf, stdout);
  }
}

static void show_val(Env e, u32 d, const Term* w, char chain) {
  const u32* D = SHOW_DESC;
  Term one;
  char zs[4];
  u32  zn = 0;
  for (bool tail = true; tail;) switch (tail = false, D[d]) {
    case 0:
      printf("%u", (u32)w[0]);
      break;
    case 1:
      show_f32((u32)w[0]);
      break;
    case 2:
      printf("%llun", (unsigned long long)w[0]);
      break;
    case 3:
      putchar('\'');
      show_chr(D[d + 1] != 0 ? term_loc(w[0]) : w[0], '\'');
      putchar('\'');
      break;
    case 4:
      putchar('"');
      for (Term s = w[0]; term_aux(s) == CID_SCON;) {
        u64 l = term_peek(e.mem, s);
        show_chr(e.mem[l], '"');
        s = e.mem[l + 1];
      }
      putchar('"');
      break;
    case 5:
      fputs("{==}", stdout);
      break;
    case 6:
      putchar('[');
      for (u32 i = 0, g = D[d + 2]; i < 1u << (blk_cls(w[0]) - g); i += 1) {
        Term v[1u << g];
        for (u32 j = 0; j < 1u << g; j += 1) {
          v[j] = blk_read(e.mem, term_tag(w[0]) == TAG_ARR,
            term_peek(e.mem, w[0]), (i << g) + j);
        }
        fputs(i > 0 ? ", " : "", stdout);
        show_val(e, D[d + 1], v, 0);
      }
      putchar(']');
      break;
    default: {
      Term t   = w[0];
      bool box = D[d + 1] != 0;
      u32  key = box ? (u32)term_aux(t) : D[d + 2] > 1 ? (u32)t : 0;
      u32  a   = d + 3;
      for (u32 i = 0; box ? D[a + 1] != key : i != key; i += 1) {
        a += 4 + 2 * D[a + 2];
      }
      if (box) {
        one = term_loc(t);
        w   = term_tag(t) == TAG_PAK ? &one : e.mem + term_peek(e.mem, t);
      }
      char o = "{[("[D[a + 3]];
      if (o == '{') {
        printf("%s{", SHOW_NAMES[D[a]]);
      } else if (chain != o) {
        putchar(o);
      }
      if (o == '{' || chain != o) {
        zs[zn++] = "}])"[D[a + 3]];
      }
      for (u32 j = 0; j < D[a + 2]; j += 1) {
        if (o == '[' ? j == 0 && chain == o : j > 0) {
          fputs(", ", stdout);
        }
        if (j == 1 && o != '{') {
          tail  = true;
          chain = o;
          d     = D[a + 5 + 2 * j];
          w     = w + D[a + 4 + 2 * j];
        } else {
          show_val(e, D[a + 5 + 2 * j], w + D[a + 4 + 2 * j], 0);
        }
      }
    }
  }
  while (zn > 0) {
    putchar(zs[--zn]);
  }
}

#endif

// Run
// ===

static void io_step(Env e, IoWork* a) {
  for (;;) {
    u64  ap  = task_node(e, FID_CLO_APPLY, TERM_HOLE, 0, 0);
    e.mem[ap]     = a->cont;
    e.mem[ap + 1] = a->item;
    Term req = corpus_eval(e.mem, term_tsk(FID_CLO_APPLY, ap));
    u32  c   = (u32)term_aux(req);
    u64  at  = term_peek(e.mem, req);
    if (c == CID_EMIT) {
      term_drop(e, req);
      free(a);
      io_live -= 1;
      return;
    }
    if (c == CID_HALT) {
      io_errs(e, e.mem[at + 1]);
      exit((int)(u32)e.mem[at]);
    }
    if (io_eff_rows[c].run == NULL) {
      err_fail("an alien request");
    }
    u32 need = io_eff_rows[c].ask;
    u32 word = (u32)(need & IO_READ ? io_hand_v(e.mem[at]) : e.mem[at]);
    a->cont  = req;
    if (need != 0) {
      io_wait_on(a, (int)word, need & IO_READ ? POLLIN : 0,
        need & IO_TIME ? io_tick() + (u64)word * 1000000ull : 0, io_exec);
      return;
    }
    Term x = io_exec(e, a);
    if (x == IO_PARK) {
      return;
    }
    a->item = x;
  }
}

OUTLINE void io_loop(u64* H) {
  Env e = { H, ALC[0] };
  io_stk = pool_stack();
  signal(SIGPIPE, SIG_IGN);
  if (pipe(io_wake_fd) | fcntl(io_wake_fd[0], F_SETFL, O_NONBLOCK)) {
    err_fail("the event loop failed to open");
  }
  Term m = corpus_eval(H, term_tsk(MAIN_FID, task_node(e, MAIN_FID,
    TERM_HOLE, 0, 0)));
#if MAIN_PURE
  show_val(e, 0, H + H_ROOT_WORD, 0);
  putchar('\n');
  return;
#endif
  io_spawn(m);
  for (u32 n = 0;; n += 1) {
    if (io_runs == NULL) {
      if (io_live == 0) {
        return;
      }
      if (io_park == NULL && io_busy == 0) {
        io_sync();
        err_fail("deadlock: every computation waits on a channel");
      }
      io_wait(e);
      continue;
    }
    if ((n & 63) == 0 && io_busy != 0) {
      io_take(e);
    }
    io_step(e, io_pop(&io_runs));
  }
}

// Requests
// ========

// dtype.c -- the numeric conversions tinygrad/dtype.py does with struct and
// ctypes, as Bend effects.
//
// WHY AN EFFECT AT ALL. Bend's only float is F32, and it can read an F32's bits
// (F32.bits) but cannot build an F32 from a bit pattern. Every conversion here
// is bit twiddling in both directions, so without this seam none of them is
// expressible: float_to_bf16 rounds bits, float_to_fp16/fp8 build a value from
// bits, fp8_to_float builds a value from bits, and the 64-bit div/mod need a
// 64-bit quotient. That is the whole list; the rest of dtype.bend is pure.
//
// The f32 restatement of float_to_fp8 is not a simplification. dtype.py does the
// arithmetic on f64 (`struct.pack('d', x)`), and this file does it on the f32
// pattern handed in. The two agree bit for bit on every f32 input, because the
// tie bit dtype.py compares against is at f64 bit (52 - sig_bits) and an f32 has
// no bits below pattern bit 23: see .agents/slop/notes/fp8_oracle.py, which
// checks all four formats over a million random patterns, every boundary
// exponent, and all 256 codes in both directions.
//
// ONE FILE, BOTH LANES. The .js file beside this one is the same arithmetic on
// the same tables, for the interpreted lane; keeping them adjacent is what makes
// the agreement checkable by eye.

// (bias, sig_bits, mant_mask, min_denorm_half, ovf_threshold, max_norm, min_norm)
// dtype.py's _fp8_cfg with the three f64 magnitude patterns rewritten as the f32
// patterns of the same values. Two of dtype.py's constants are an f64 ULP below
// 61440, which rounds to the same f32 pattern as 61440 itself.
#define FP8_E4M3      0
#define FP8_E5M2      1
#define FP8_E4M3FNUZ  2
#define FP8_E5M2FNUZ  3

// bend2's generated C declares u64/u32/u8 but no signed 64-bit type; the
// div/mod half of this file needs one and the casts are the whole of the cost.
typedef int64_t s64;

static const u32 fp8_bias[4]      = {  7, 15,  8, 16 };
static const u32 fp8_sig[4]       = {  4,  3,  4,  3 };
static const u32 fp8_mant[4]      = { 0x7, 0x3, 0x7, 0x3 };
static const u32 fp8_denorm[4]    = { 0x3A800000, 0x37000000, 0x3A000000, 0x36800000 };
static const u32 fp8_ovf[4]       = { 0x43E80000,  0x47700000, 0x43780000,  0x47700000 };
static const u32 fp8_max_norm[4]  = { 0x7E,       0x7B,       0x7F,        0x7F };
static const u32 fp8_min_norm[4]  = { 0x3C800000, 0x38800000, 0x3C000000,  0x38000000 };

static inline int fp8_is_fnuz(u32 kind) { return kind >= FP8_E4M3FNUZ; }

// dtype.py float_to_fp8, on the f32 bit pattern. `kind` is one of the FP8_* ids.
static u32 fp8_encode(u32 xb, u32 kind) {
  u32 exp_field = (xb >> 23) & 0xFFu;
  u32 sgn       = ((xb >> 31) & 1u) << 7;
  u32 bias      = fp8_bias[kind];
  u32 sig       = fp8_sig[kind];
  u32 hu        = 1u << (23 - sig);           // the tie bit, see fp8_oracle.py
  u32 absx      = xb & 0x7FFFFFFFu;
  u32 exp, mant, res;

  if (exp_field == 0xFFu) {
    // dtype.py's three non-finite cases, in its order. The fnuz formats have no
    // inf or nan at all and answer 0x80; e4m3 has no inf and answers jax's
    // 0x7f/0xff; e5m2 has a full nan and inf.
    if (fp8_is_fnuz(kind)) return 0x80u;
    if (kind == FP8_E4M3) return sgn != 0 ? 0xFFu : 0x7Fu;
    u32 mant_all = (xb & 0x7FFFFFu) == 0;
    return (mant_all ? 0x7Cu : 0x7Fu) | sgn;
  }

  exp  = exp_field - 127u + bias;
  mant = (xb >> (24 - sig)) & fp8_mant[kind];
  if (absx <= fp8_denorm[kind]) {
    res = 0;
  } else if (absx > fp8_ovf[kind]) {
    res = fp8_max_norm[kind];
  } else if (absx >= fp8_min_norm[kind]) {
    res = (exp << (sig - 1)) | mant;
    u32 rb = xb & ((hu << 1) - 1);
    if (rb > hu || (rb == hu && (mant & 1))) res += 1;
  } else {
    u32 sh = 1 - exp;
    u32 half;
    mant |= 1u << (sig - 1);
    res  = mant >> sh;
    half = hu << sh;
    u32 rb = (xb | (1u << 23)) & ((half << 1) - 1);
    if (rb > half || (rb == half && (res & 1))) res += 1;
  }
  // fnuz has no negative zero, so a zero result carries no sign
  return (fp8_is_fnuz(kind) && res == 0) ? 0u : (res | sgn);
}

// dtype.py fp8_to_float, answering the f32 bit pattern of the value.
static u32 fp8_decode(u32 x, u32 kind) {
  u32 sig = fp8_sig[kind], bias = fp8_bias[kind];
  if (fp8_is_fnuz(kind) && x == 0x80u) return 0x7FC00000u;   // nan
  if ((x & 0x7Fu) == 0) return (x & 0x80u) ? 0x80000000u : 0u;
  u32 mant_bits = sig - 1, exp_bits = 8 - sig;
  u32 exp_max = (1u << exp_bits) - 1, mant_max = (1u << mant_bits) - 1;
  u32 sgn = (x >> 7) & 1, exp = (x >> mant_bits) & exp_max, mant = x & mant_max;
  f32 v;
  if (!fp8_is_fnuz(kind) && exp == exp_max) {
    if (kind == FP8_E5M2) {
      // dtype.py: copysign(nan if mantissa else inf, -1 if sign else 1)
      return mant ? (sgn ? 0xFFC00000u : 0x7FC00000u)
                  : (sgn ? 0xFF800000u : 0x7F800000u);
    }
    if (mant == mant_max) return sgn ? 0xFFC00000u : 0x7FC00000u;
  }
  // the value is exact in f32 -- an fp8 has at most four significant bits
  v = (f32)(exp == 0 ? (mant / (f32)(mant_max + 1)) * (1.0f / (1u << bias))
                     : (1.0f + mant / (f32)(mant_max + 1)) *
                       ldexpf(1.0f, (int)exp - (int)bias));
  return f32_rewrap(sgn ? -v : v);
}

// float_to_fp16, as an f32 whose pattern is the half zero-extended. dtype.py is
// `struct.pack('e', x)` and catches OverflowError to return copysign(inf, x),
// which is exactly "saturate to a signed infinity". IEEE binary16 from an
// f32 pattern, round-half-to-even.
static u32 fp16_encode(u32 x) {
  u32 s = (x >> 16) & 0x8000u;          // sign, already in half position
  u32 e = (x >> 23) & 0xffu;
  u32 m = x & 0x7fffffu;
  if (e == 0xff) return s | 0x7c00u | (m ? 0x200u : 0u);   // inf / nan
  if (e == 0 && m == 0) return s;                          // signed zero
  int exp = (int)e - 127 + 15;
  if (exp >= 0x1f) return s | 0x7c00u;                     // overflow -> inf
  if (exp <= 0) {                                           // subnormal / zero
    if (exp < -10) return s;
    m |= 0x800000u;
    u32 shift = (u32)(14 - exp);
    u32 half = m >> shift;
    u32 rem = m & ((1u << shift) - 1u);
    u32 halfway = 1u << (shift - 1);
    if (rem > halfway || (rem == halfway && (half & 1u))) half++;
    return s | half;
  }
  u32 half = ((u32)exp << 10) | (m >> 13);
  u32 rem = m & 0x1fffu;
  if (rem > 0x1000u || (rem == 0x1000u && (half & 1u))) half++;   // may carry
  return s | half;
}

// The f32 pattern of a half value. NOT a zero extension: the two formats have
// different exponent widths and biases (f32 8/127, half 5/15), so the exponent
// is rebased and the fraction is shifted. A half subnormal is m * 2^-24, which
// is always an f32 normal, so it needs no denormal path on this side.
static u32 fp16_f32(u32 h) {
  u32 s = (h >> 15) & 1u, e = (h >> 10) & 0x1Fu, m = h & 0x3FFu;
  if (e == 0x1Fu) return (s << 31) | 0x7F800000u | (m ? 0x400000u : 0u);
  if (e == 0) {
    if (m == 0) return s << 31;
    u32 k = 31u - (u32)__builtin_clz(m);
    return (s << 31) | ((k + 103u) << 23) | ((m << (23 - k)) & 0x7FFFFFu);
  }
  return (s << 31) | ((e + 112u) << 23) | (m << 13);
}

static Term fp16_run(Env e, Term* f, IoWork* w) {
  return (Term)(intptr_t)fp16_f32(fp16_encode((u32)f[0]));
}

static Term fp8_to_run(Env e, Term* f, IoWork* w) {
  return (Term)(intptr_t)fp8_decode((u32)f[0] & 0xFFu, (u32)f[1] & 0xFFu);
}

static Term fp8_from_run(Env e, Term* f, IoWork* w) {
  return (Term)(intptr_t)fp8_encode((u32)f[0], (u32)f[1] & 0xFFu);
}

static Term bf16_run(Env e, Term* f, IoWork* w) {
  // dtype.py: round the f32 bits to bf16 with round-half-to-even, and answer
  // the value. bf16 IS the top half of an f32 pattern, so the rounded pattern
  // is the answer with no rebias -- which is exactly why this one differs from
  // the half above. NOTE the explicit u32: f32_rewrap takes an f32, so handing
  // it a u32 would reinterpret the bits as a float and back.
  u32 x = (u32)f[0];
  return (Term)(intptr_t)((x + 0x7FFFu + ((x >> 16) & 1u)) & 0xFFFF0000u);
}

// ===========================================================================
// The 64-bit helpers. Python's // and % are floor division; its cdiv/cmod
// truncate toward zero. A signed 64-bit quotient has no U32 encoding, which is
// the whole reason these are an effect and not a def.
//
// Every one takes an I64 as (hi, lo) and answers one the same way. INT64_MIN
// has no positive counterpart, so nothing here negates its divisor: cdiv uses
// |a|//|b| and the ceiling is computed directly, which is what Python's
// -(a // -b) means without the negation.
typedef struct { s64 q, r; } DivMod;

static DivMod floor_div_mod(s64 a, s64 b) {
  DivMod d;
  if (b == 0) { d.q = 0; d.r = a; return d; }   // tinygrad's zero-divisor branch
  d.q = a / b;
  d.r = a % b;
  if (d.r != 0 && ((d.r < 0) != (b < 0))) { d.q -= 1; d.r += b; }
  return d;
}

// cdiv truncates toward zero; its sign comes from the operands, not from a*b,
// because the product would overflow.
static s64 cdiv_of(s64 a, s64 b) {
  s64 q = (a < 0 ? -a : a) / (b < 0 ? -b : b);
  return (a < 0) != (b < 0) ? -q : q;
}

static s64 i64_of(Env e, Term t) {
  Term o[2];
  ctr_take(e, t, 2, o);
  return (s64)((((u64)(u32)o[0]) << 32) | (u32)o[1]);
}

static Term pack64(Env e, s64 v) {
  return io_tup(e, (Term)(intptr_t)(u32)((u64)v >> 32), (Term)(intptr_t)(u32)(u64)v);
}

static Term i64_run(Env e, Term* f, IoWork* w) {
  return pack64(e, i64_of(e, f[0]));
}

static Term div64_floor_run(Env e, Term* f, IoWork* w) {
  return pack64(e, floor_div_mod(i64_of(e, f[0]), i64_of(e, f[1])).q);
}

static Term div64_mod_run(Env e, Term* f, IoWork* w) {
  return pack64(e, floor_div_mod(i64_of(e, f[0]), i64_of(e, f[1])).r);
}

static Term div64_cdiv_run(Env e, Term* f, IoWork* w) {
  s64 a = i64_of(e, f[0]), b = i64_of(e, f[1]);
  return pack64(e, b == 0 ? 0 : cdiv_of(a, b));
}

static Term div64_cmod_run(Env e, Term* f, IoWork* w) {
  s64 a = i64_of(e, f[0]), b = i64_of(e, f[1]);
  return pack64(e, b == 0 ? a : a - cdiv_of(a, b) * b);
}

static Term div64_ceildiv_run(Env e, Term* f, IoWork* w) {
  s64 a = i64_of(e, f[0]), b = i64_of(e, f[1]);
  if (b == 0) return pack64(e, 0);
  s64 c = a / b;
  if (a % b != 0 && (a < 0) == (b < 0)) c += 1;
  return pack64(e, c);
}

// One guard per registration, the way base.bend's file_read.c does it: CID is
// only defined for an effect the calling program actually uses, so a program
// that never calls fp8_from must not name it.
#ifdef CID_TINYBENDYGRAD_DTYPE_DT_BF16
static void __attribute__((constructor)) dtype_bf16_use(void) {
  io_eff(CID_TINYBENDYGRAD_DTYPE_DT_BF16, bf16_run, 0);
}
#endif
#ifdef CID_TINYBENDYGRAD_DTYPE_DT_FP16
static void __attribute__((constructor)) dtype_fp16_use(void) {
  io_eff(CID_TINYBENDYGRAD_DTYPE_DT_FP16, fp16_run, 0);
}
#endif
#ifdef CID_TINYBENDYGRAD_DTYPE_DT_FP8_FROM
static void __attribute__((constructor)) dtype_fp8_from_use(void) {
  io_eff(CID_TINYBENDYGRAD_DTYPE_DT_FP8_FROM, fp8_from_run, 0);
}
#endif
#ifdef CID_TINYBENDYGRAD_DTYPE_DT_FP8_TO
static void __attribute__((constructor)) dtype_fp8_to_use(void) {
  io_eff(CID_TINYBENDYGRAD_DTYPE_DT_FP8_TO, fp8_to_run, 0);
}
#endif
#ifdef CID_TINYBENDYGRAD_DTYPE_DT_I64_TRUNC
static void __attribute__((constructor)) dtype_i64_trunc_use(void) {
  io_eff(CID_TINYBENDYGRAD_DTYPE_DT_I64_TRUNC, i64_run, 0);
}
#endif
#ifdef CID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV
static void __attribute__((constructor)) dtype_i64_floor_div_use(void) {
  io_eff(CID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_DIV, div64_floor_run, 0);
}
#endif
#ifdef CID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_MOD
static void __attribute__((constructor)) dtype_i64_floor_mod_use(void) {
  io_eff(CID_TINYBENDYGRAD_DTYPE_DT_I64_FLOOR_MOD, div64_mod_run, 0);
}
#endif
#ifdef CID_TINYBENDYGRAD_DTYPE_DT_I64_CDIV
static void __attribute__((constructor)) dtype_i64_cdiv_use(void) {
  io_eff(CID_TINYBENDYGRAD_DTYPE_DT_I64_CDIV, div64_cdiv_run, 0);
}
#endif
#ifdef CID_TINYBENDYGRAD_DTYPE_DT_I64_CMOD
static void __attribute__((constructor)) dtype_i64_cmod_use(void) {
  io_eff(CID_TINYBENDYGRAD_DTYPE_DT_I64_CMOD, div64_cmod_run, 0);
}
#endif
#ifdef CID_TINYBENDYGRAD_DTYPE_DT_I64_CEILDIV
static void __attribute__((constructor)) dtype_i64_ceildiv_use(void) {
  io_eff(CID_TINYBENDYGRAD_DTYPE_DT_I64_CEILDIV, div64_ceildiv_run, 0);
}
#endif
// IO
// ==

Term io_print_run(Env e, Term* f, IoWork* w) {
  uint64_t n = 0;
  char* text = io_cstr(e, f[0], &n);
  io_out(stdout, text, n);
  io_out(stdout, "\n", 1);
  free(text);
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) io_print_use(void) {
  io_eff(CID_IO_PRINT, io_print_run, 0);
}


// Main
// ====

int main(int argc, char** argv) {
  long thr = 0;
  int  gpu = -1;
  u64  mem = 0;
  io_argv = argv;
  io_argc = 1;
  for (int i = 1; i < argc; i += 1) {
    const char* a = argv[i];
    const char* v = i + 1 < argc ? argv[i + 1] : NULL;
    if (strcmp(a, "--") == 0) {
      while (i + 1 < argc) {
        io_argv[io_argc++] = argv[++i];
      }
    } else if (strcmp(a, "--bend-help") == 0) {
      printf(CLI_HELP, argv[0]);
      return 0;
    } else if (strcmp(a, "--gpu-build") == 0) {
      if (gpu_probe() && !gpu_make(gpu_path())) {
        fprintf(stderr, "bend: cannot write %s\n", gpu_path());
        return 1;
      }
      return 0;
    } else if (strcmp(a, "--threads") == 0) {
      char* end = NULL;
      thr = v != NULL ? strtol(v, &end, 10) : 0;
      if (thr < 1 || *end != '\0') {
        err_fail("expected a thread count of 1 or more after --threads");
      }
      i += 1;
    } else if (strcmp(a, "--gpu") == 0) {
      char*  end = NULL;
      double n   = v != NULL ? strtod(v, &end) : 0;
      u64    mul = end == NULL ? 0 : strcmp(end, "GB") == 0 ? 1ull << 30
        : strcmp(end, "MB") == 0 ? 1ull << 20 : 0;
      if (v != NULL && strcmp(v, "off") == 0) {
        gpu = 0;
      } else if (v != NULL && (strcmp(v, "on") == 0 || (mul != 0 && n > 0))) {
        gpu = 1;
        mem = (u64)(n * (double)mul);
      } else {
        err_fail("expected on, off or a size like 4GB after --gpu");
      }
      i += 1;
    } else {
      io_argv[io_argc++] = argv[i];
    }
  }
  bool dev = gpu != 0 && BANGS != 0 && gpu_probe();
  if (gpu == 1 && BANGS != 0 && !dev) {
    err_fail("--gpu on, but this binary found no usable GPU (a CUDA GPU needs"
      " concurrent managed access, which WSL2's lack)");
  }
  io_loop(corpus_setup(dev, thr > 0 ? thr : cpu_count(), mem));
  io_sync();
  return 0;
}

#endif
