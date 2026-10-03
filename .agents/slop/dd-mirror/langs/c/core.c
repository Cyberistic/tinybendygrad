
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
#define CID_NIL 13
#define CID_CON 14
#define CID_CHR 15
#define CID_IO_ARGS 16
#define CID_IO_PRINT 17
#define FID_U32_READ_GO 0
#define FID_EXP_SUM 1
#define FID_EXP_SUM_K6 2
#define FID_MARKS 3
#define FID_MARKS_K8 4
#define FID_MARKS_K9 5
#define FID_DOT 6
#define FID_DOT_K12 7
#define FID_DOT_K13 8
#define FID_U32_SHOW_GO 9
#define FID_U32_READ 10
#define FID_LIST_APPEND 11
#define FID_LIST_APPEND_K18 12
#define FID_CROSS_ENTROPY 13
#define FID_CROSS_ENTROPY_K20 14
#define FID_CS4 15
#define FID_CS4_K23 16
#define FID_CS4_K24 17
#define FID_CS4_K25 18
#define FID_CS4_K26 19
#define FID_CS5 20
#define FID_CS5_K28 21
#define FID_CS5_K29 22
#define FID_CS5_K30 23
#define FID_CS5_K31 24
#define FID_ROWS 25
#define FID_ROWS_K34 26
#define FID_PARSE 27
#define FID_PARSE_K38 28
#define FID_SAMPLE 29
#define FID_SAMPLE_K41 30
#define FID_SAMPLE_K42 31
#define FID_SAMPLE_K43 32
#define FID_SAMPLE_K44 33
#define FID_SAMPLE_K45 34
#define FID_SAMPLE_K46 35
#define FID_U32_SHOW 36
#define FID_ARRAY_TO_LIST_GO_1 37
#define FID_ARRAY_TO_LIST_GO_1_K52 38
#define FID_ARRAY_TO_LIST_GO_0 39
#define FID_ARRAY_TO_LIST_GO_0_K54 40
#define FID_PUT_U 41
#define FID_PUT_U_K56 42
#define FID_LIST_REPLICATE 43
#define FID_LIST_REPLICATE_K59 44
#define FID_PUT 45
#define FID_PUT_K61 46
#define FID_BATCH 47
#define FID_BATCH_K63 48
#define FID_STRING_SPLIT 49
#define FID_STRING_SPLIT_K65 50
#define FID_SHOW_U 51
#define FID_SHOW_U_K67 52
#define FID_SHOW_U_K68 53
#define FID_SHOW_U_K69 54
#define FID_SHOW_F 55
#define FID_SHOW_F_K71 56
#define FID_SHOW_F_K72 57
#define FID_SHOW_F_K73 58
#define FID_BITS_AT 59
#define FID_BITS_AT_K75 60
#define FID_STRING_APPEND 61
#define FID_STRING_APPEND_K77 62
#define FID_ARRAY_TO_LIST_1 63
#define FID_SHARE_U 64
#define FID_SHARE_U_K81 65
#define FID_ARRAY_TO_LIST_0 66
#define FID_SHARE_F 67
#define FID_SHARE_F_K84 68
#define FID_WS_OF 69
#define FID_WS_OF_K86 70
#define FID_LABS_OF 71
#define FID_LABS_OF_K88 72
#define FID_IMGS_OF 73
#define FID_IMGS_OF_K90 74
#define FID_CORE_TRACE 75
#define FID_CORE_TRACE_K92 76
#define FID_CORE_TRACE_K93 77
#define FID_CORE_TRACE_K94 78
#define FID_CORE_TRACE_K95 79
#define FID_CORE_TRACE_K96 80
#define FID_CORE_TRACE_K97 81
#define FID_PAYLOAD 82
#define FID_RUN 83
#define FID_RUN_K100 84
#define FID_RUN_K101 85
#define FID_RUN_K102 86
#define FID_RUN_K103 87
#define FID_RUN_K104 88
#define FID_RUN_K105 89
#define FID_RUN_K106 90
#define FID_RUN_K107 91
#define FID_RUN_K108 92
#define FID_RUN_K109 93
#define FID_RUN_K110 94
#define FID_RUN_K111 95
#define FID_RUN_K112 96
#define FID_RUN_K113 97
#define FID_RUN_K114 98
#define FID_RUN_K115 99
#define FID_RUN_K116 100
#define FID_RUN_K117 101
#define FID_RUN_K118 102
#define FID_RUN_K119 103
#define FID_RUN_K120 104
#define FID_RUN_K121 105
#define FID_RUN_K122 106
#define FID_RUN_K123 107
#define FID_RUN_K124 108
#define FID_RUN_K125 109
#define FID_RUN_K126 110
#define FID_RUN_K127 111
#define FID_RUN_K128 112
#define FID_RUN_K129 113
#define FID_RUN_K130 114
#define FID_RUN_K131 115
#define FID_MAIN 116
#define FID_MAIN_C136 117
#define FID_MAIN_C137 118
#define FID_MAIN_K138 119
#define FID_MAIN_K139 120
#define FID_MAIN_C140 121
#define FID_MAIN_K141 122
#define FID_IO_ARGS 123
#define FID_IO_PRINT 124
#define FID_IO_EMIT 125
#define FID_CLO_APPLY 126
#define FID_EXIT 127
#define FID_ENTER 128
CONSTV u8 FID_T[][3] = { { 2, 0, 2 }, { 1, 0, 2 }, { 2, 1, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 2, 1, 2 }, { 2, 0, 2 }, { 2, 1, 2 }, { 3, 1, 2 }, { 3, 0, 2 }, { 1, 0, 2 }, { 2, 0, 2 }, { 2, 1, 2 }, { 3, 0, 2 }, { 4, 1, 2 }, { 0, 0, 2 }, { 1, 1, 2 }, { 2, 1, 2 }, { 1, 1, 2 }, { 2, 1, 2 }, { 0, 0, 2 }, { 1, 1, 2 }, { 2, 1, 2 }, { 1, 1, 2 }, { 2, 1, 2 }, { 3, 0, 2 }, { 4, 1, 2 }, { 1, 0, 2 }, { 2, 2, 2 }, { 4, 0, 2 }, { 5, 1, 2 }, { 4, 1, 2 }, { 5, 1, 2 }, { 4, 1, 2 }, { 3, 1, 2 }, { 2, 1, 2 }, { 1, 0, 2 }, { 2, 0, 2 }, { 2, 1, 2 }, { 2, 0, 2 }, { 2, 1, 2 }, { 4, 0, 2 }, { 5, 1, 2 }, { 2, 0, 2 }, { 2, 1, 2 }, { 4, 0, 2 }, { 5, 1, 2 }, { 6, 0, 2 }, { 6, 1, 2 }, { 2, 0, 2 }, { 3, 1, 2 }, { 1, 0, 2 }, { 2, 1, 2 }, { 2, 1, 2 }, { 2, 1, 2 }, { 1, 0, 2 }, { 2, 1, 2 }, { 2, 1, 2 }, { 2, 1, 2 }, { 2, 0, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 2, 1, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 2, 1, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 2, 1, 2 }, { 1, 0, 2 }, { 2, 1, 2 }, { 1, 0, 2 }, { 2, 1, 2 }, { 1, 0, 2 }, { 2, 1, 2 }, { 3, 0, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 2, 1, 2 }, { 3, 1, 2 }, { 4, 1, 2 }, { 2, 1, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 5, 1, 2 }, { 6, 1, 2 }, { 7, 1, 2 }, { 8, 1, 2 }, { 9, 1, 2 }, { 10, 1, 2 }, { 11, 1, 2 }, { 11, 1, 2 }, { 11, 1, 2 }, { 11, 1, 2 }, { 10, 1, 2 }, { 10, 1, 2 }, { 9, 1, 2 }, { 8, 1, 2 }, { 7, 1, 2 }, { 6, 1, 2 }, { 5, 1, 2 }, { 4, 1, 2 }, { 3, 1, 2 }, { 2, 1, 2 }, { 2, 1, 2 }, { 1, 1, 2 }, { 0, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 3, 0, 2 }, { 2, 1, 2 }, { 1, 0, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 2, 0, 2 } };
CONSTV u8 CID_T[][2] = { { 2, 0 }, { 0, 1 }, { 2, 1 }, { 2, 1 }, { 1, 0 }, { 2, 0 }, { 1, 0 }, { 1, 0 }, { 0, 0 }, { 1, 0 }, { 0, 1 }, { 0, 1 }, { 0, 0 }, { 0, 1 }, { 2, 1 }, { 1, 1 }, { 1, 0 }, { 2, 0 } };
#define STAT_LEN 34

#define WL_RESW 2
#define BANGS   0

#define WL_BANK Term r0, r1, r2, r3, r4, r5;

#define WL_LOAD(A, N) \
  do { \
    if ((N) <= 0) break; r0 = e.mem[(A) + 0]; \
    if ((N) <= 1) break; r1 = e.mem[(A) + 1]; \
    if ((N) <= 2) break; r2 = e.mem[(A) + 2]; \
    if ((N) <= 3) break; r3 = e.mem[(A) + 3]; \
    if ((N) <= 4) break; r4 = e.mem[(A) + 4]; \
    if ((N) <= 5) break; r5 = e.mem[(A) + 5]; \
  } while (0);

#define WL_LAST(X) \
  switch (war) { \
    case 0: r0 = (X); \
      break; \
    case 1: r1 = (X); \
      break; \
    case 2: r2 = (X); \
      break; \
    case 3: r3 = (X); \
      break; \
    case 4: r4 = (X); \
      break; \
    case 5: r5 = (X); \
      break; \
  }

#define WL_SAVE(V) (V)[0] = r0; (V)[1] = r1;

#define WL_TAKE(V) r0 = (V)[0]; r1 = (V)[1];

#define WL_SIG Env e, DEV Term* sp, u32 seq, u32 rn, Term r0, Term r1, Term r2, Term r3, Term r4, Term r5

#define WL_ALL e, sp, seq, rn, r0, r1, r2, r3, r4, r5

#define WL_TABLE WL_X(FID_U32_READ_GO) WL_X(FID_EXP_SUM) WL_X(FID_EXP_SUM_K6) WL_X(FID_MARKS) WL_X(FID_MARKS_K8) WL_X(FID_MARKS_K9) WL_X(FID_DOT) WL_X(FID_DOT_K12) WL_X(FID_DOT_K13) WL_X(FID_U32_SHOW_GO) WL_X(FID_U32_READ) WL_X(FID_LIST_APPEND) WL_X(FID_LIST_APPEND_K18) WL_X(FID_CROSS_ENTROPY) WL_X(FID_CROSS_ENTROPY_K20) WL_X(FID_CS4) WL_X(FID_CS4_K23) WL_X(FID_CS4_K24) WL_X(FID_CS4_K25) WL_X(FID_CS4_K26) WL_X(FID_CS5) WL_X(FID_CS5_K28) WL_X(FID_CS5_K29) WL_X(FID_CS5_K30) WL_X(FID_CS5_K31) WL_X(FID_ROWS) WL_X(FID_ROWS_K34) WL_X(FID_PARSE) WL_X(FID_PARSE_K38) WL_X(FID_SAMPLE) WL_X(FID_SAMPLE_K41) WL_X(FID_SAMPLE_K42) WL_X(FID_SAMPLE_K43) WL_X(FID_SAMPLE_K44) WL_X(FID_SAMPLE_K45) WL_X(FID_SAMPLE_K46) WL_X(FID_U32_SHOW) WL_X(FID_ARRAY_TO_LIST_GO_1) WL_X(FID_ARRAY_TO_LIST_GO_1_K52) WL_X(FID_ARRAY_TO_LIST_GO_0) WL_X(FID_ARRAY_TO_LIST_GO_0_K54) WL_X(FID_PUT_U) WL_X(FID_PUT_U_K56) WL_X(FID_LIST_REPLICATE) WL_X(FID_LIST_REPLICATE_K59) WL_X(FID_PUT) WL_X(FID_PUT_K61) WL_X(FID_BATCH) WL_X(FID_BATCH_K63) WL_X(FID_STRING_SPLIT) WL_X(FID_STRING_SPLIT_K65) WL_X(FID_SHOW_U) WL_X(FID_SHOW_U_K67) WL_X(FID_SHOW_U_K68) WL_X(FID_SHOW_U_K69) WL_X(FID_SHOW_F) WL_X(FID_SHOW_F_K71) WL_X(FID_SHOW_F_K72) WL_X(FID_SHOW_F_K73) WL_X(FID_BITS_AT) WL_X(FID_BITS_AT_K75) WL_X(FID_STRING_APPEND) WL_X(FID_STRING_APPEND_K77) WL_X(FID_ARRAY_TO_LIST_1) WL_X(FID_SHARE_U) WL_X(FID_SHARE_U_K81) WL_X(FID_ARRAY_TO_LIST_0) WL_X(FID_SHARE_F) WL_X(FID_SHARE_F_K84) WL_X(FID_WS_OF) WL_X(FID_WS_OF_K86) WL_X(FID_LABS_OF) WL_X(FID_LABS_OF_K88) WL_X(FID_IMGS_OF) WL_X(FID_IMGS_OF_K90) WL_X(FID_CORE_TRACE) WL_X(FID_CORE_TRACE_K92) WL_X(FID_CORE_TRACE_K93) WL_X(FID_CORE_TRACE_K94) WL_X(FID_CORE_TRACE_K95) WL_X(FID_CORE_TRACE_K96) WL_X(FID_CORE_TRACE_K97) WL_X(FID_PAYLOAD) WL_X(FID_RUN) WL_X(FID_RUN_K100) WL_X(FID_RUN_K101) WL_X(FID_RUN_K102) WL_X(FID_RUN_K103) WL_X(FID_RUN_K104) WL_X(FID_RUN_K105) WL_X(FID_RUN_K106) WL_X(FID_RUN_K107) WL_X(FID_RUN_K108) WL_X(FID_RUN_K109) WL_X(FID_RUN_K110) WL_X(FID_RUN_K111) WL_X(FID_RUN_K112) WL_X(FID_RUN_K113) WL_X(FID_RUN_K114) WL_X(FID_RUN_K115) WL_X(FID_RUN_K116) WL_X(FID_RUN_K117) WL_X(FID_RUN_K118) WL_X(FID_RUN_K119) WL_X(FID_RUN_K120) WL_X(FID_RUN_K121) WL_X(FID_RUN_K122) WL_X(FID_RUN_K123) WL_X(FID_RUN_K124) WL_X(FID_RUN_K125) WL_X(FID_RUN_K126) WL_X(FID_RUN_K127) WL_X(FID_RUN_K128) WL_X(FID_RUN_K129) WL_X(FID_RUN_K130) WL_X(FID_RUN_K131) WL_X(FID_MAIN) WL_X(FID_MAIN_C136) WL_X(FID_MAIN_C137) WL_X(FID_MAIN_K138) WL_X(FID_MAIN_K139) WL_X(FID_MAIN_C140) WL_X(FID_MAIN_K141) WL_X(FID_IO_ARGS) WL_X(FID_IO_PRINT) WL_X(FID_IO_EMIT) WL_X(FID_CLO_APPLY) WL_X(FID_EXIT)
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

CONSTV u64 STAT_IMG[] = { 48ull, term_pak(CID_SNIL, 0), term_pak(CID_SNIL, 0), term_pak(CID_NIL, 0), 44ull, term_pak(CID_SNIL, 0), 61ull, term_pak(CID_SNIL, 0), 110ull, term_ctr(CID_SCON, STAT_OFF + 6), 105ull, term_ctr(CID_SCON, STAT_OFF + 8), 32ull, term_ctr(CID_SCON, STAT_OFF + 10), 101ull, term_ctr(CID_SCON, STAT_OFF + 6), 99ull, term_ctr(CID_SCON, STAT_OFF + 14), 97ull, term_ctr(CID_SCON, STAT_OFF + 16), 114ull, term_ctr(CID_SCON, STAT_OFF + 18), 116ull, term_ctr(CID_SCON, STAT_OFF + 20), 32ull, term_ctr(CID_SCON, STAT_OFF + 22), 115ull, term_ctr(CID_SCON, STAT_OFF + 6), 115ull, term_ctr(CID_SCON, STAT_OFF + 26), 111ull, term_ctr(CID_SCON, STAT_OFF + 28), 108ull, term_ctr(CID_SCON, STAT_OFF + 30) };

INLINE Term spin_1(Env e, THR Term* o, Term r0, Term r1) {
  u32 wpoll = 0;
  u32 _v_3 = 0;
  Term _k_2 = r0;
  Term _xs_0 = r1;
  WL_SPIN
    if (_k_2 == 0) {
      if (term_aux(_xs_0) == CID_NIL) {
        _v_3 = 0ull;
      } else {
        Term _fb_0[2];
        u64 _sp_0 = ctr_take(e, _xs_0, 2, _fb_0);
        Term _f_0 = _fb_0[0];
        Term _f_1 = _fb_0[1];
        term_sink(e, _f_1);
        _v_3 = _f_0;
        spare_free(e, cls_fit(2), _sp_0);
      }
    } else {
      Term _p_0 = (_k_2 - 1);
      if (term_aux(_xs_0) == CID_NIL) {
        _v_3 = 0ull;
      } else {
        Term _fb_1[2];
        u64 _sp_1 = ctr_take(e, _xs_0, 2, _fb_1);
        Term _f_2 = _fb_1[0];
        Term _f_3 = _fb_1[1];
        spare_free(e, cls_fit(2), _sp_1);
        r0 = _p_0;
        r1 = _f_3;
        _k_2 = r0;
        _xs_0 = r1;
        WL_AGAIN(spin_1);
      }
    }
  break;
  }
  o[0] = _v_3;
  return 1;
}

INLINE Term spin_2(Env e, THR Term* o, Term r0, Term r1) {
  u32 wpoll = 0;
  u32 _v_5 = 0;
  Term _k_3 = r0;
  Term _xs_1 = r1;
  WL_SPIN
    if (_k_3 == 0) {
      if (term_aux(_xs_1) == CID_NIL) {
        _v_5 = 0ull;
      } else {
        Term _fb_2[2];
        u64 _sp_2 = ctr_take(e, _xs_1, 2, _fb_2);
        Term _f_4 = _fb_2[0];
        Term _f_5 = _fb_2[1];
        term_sink(e, _f_5);
        _v_5 = _f_4;
        spare_free(e, cls_fit(2), _sp_2);
      }
    } else {
      Term _p_1 = (_k_3 - 1);
      if (term_aux(_xs_1) == CID_NIL) {
        _v_5 = 0ull;
      } else {
        Term _fb_3[2];
        u64 _sp_3 = ctr_take(e, _xs_1, 2, _fb_3);
        Term _f_6 = _fb_3[0];
        Term _f_7 = _fb_3[1];
        spare_free(e, cls_fit(2), _sp_3);
        r0 = _p_1;
        r1 = _f_7;
        _k_3 = r0;
        _xs_1 = r1;
        WL_AGAIN(spin_2);
      }
    }
  break;
  }
  o[0] = _v_5;
  return 1;
}

INLINE Term spin_4(Env e, THR Term* o, Term r0, Term r1) {
  u32 wpoll = 0;
  Term _v_4 = 0;
  Term _xs_1 = r0;
  Term _acc_0 = r1;
  WL_SPIN
    if (term_aux(_xs_1) == CID_NIL) {
      _v_4 = _acc_0;
    } else {
      Term _fb_3[2];
      u64 _sp_3 = ctr_take(e, _xs_1, 2, _fb_3);
      Term _f_6 = _fb_3[0];
      Term _f_7 = _fb_3[1];
      u64 _nd_1 = _sp_3 >= HEAP_OFF ? _sp_3 : heap_alloc(e, cls_fit(2));
      e.mem[_nd_1 + 0] = rfc_seal(e, _f_6);
      e.mem[_nd_1 + 1] = rfc_seal(e, _acc_0);
      r0 = _f_7;
      r1 = term_ctr(CID_CON, _nd_1);
      _xs_1 = r0;
      _acc_0 = r1;
      WL_AGAIN(spin_4);
    }
  break;
  }
  o[0] = _v_4;
  return 1;
}

INLINE Term spin_3(Env e, THR Term* o, Term r0) {
  u32 wpoll = 0;
  Term _v_2 = 0;
  Term _xs_0 = r0;
  WL_SPIN
    Term _v_3 = 0;
    Term _o_0[1];
    if (spin_4(e, _o_0, _xs_0, term_pak(CID_NIL, 0)) == 0) {
      return 0;
    }
    _v_3 = _o_0[0];
    _v_2 = _v_3;
  break;
  }
  o[0] = _v_2;
  return 1;
}

INLINE Term spin_5(Env e, THR Term* o, u32 r0, u32 r1) {
  u32 wpoll = 0;
  u32 _v_1 = 0;
  u32 _m_0 = r0;
  u32 _m_1 = r1;
  WL_SPIN
    if (_m_0 == 1) {
      _v_1 = _m_1;
    } else {
      _v_1 = 0ull;
    }
  break;
  }
  o[0] = _v_1;
  return 1;
}

INLINE Term spin_6(Env e, THR Term* o, Term r0, Term r1, Term r2, Term r3) {
  u32 wpoll = 0;
  Term _v_2 = 0;
  Term _marks_0 = r0;
  Term _w_0 = r1;
  Term _cur_0 = r2;
  Term _out_0 = r3;
  WL_SPIN
    if (term_aux(_marks_0) == CID_NIL) {
      if (term_aux(_w_0) == CID_NIL) {
        term_sink(e, _cur_0);
        _v_2 = _out_0;
      } else {
        Term _fb_0[2];
        u64 _sp_0 = ctr_take(e, _w_0, 2, _fb_0);
        Term _f_0 = _fb_0[0];
        Term _f_1 = _fb_0[1];
        term_sink(e, _f_1);
        term_sink(e, _cur_0);
        _v_2 = _out_0;
        spare_free(e, cls_fit(2), _sp_0);
      }
    } else {
      Term _fb_1[2];
      u64 _sp_1 = ctr_take(e, _marks_0, 2, _fb_1);
      Term _f_2 = _fb_1[0];
      Term _f_3 = _fb_1[1];
      if (_f_2 == 0) {
        if (term_aux(_w_0) == CID_NIL) {
          term_sink(e, _f_3);
          term_sink(e, _cur_0);
          _v_2 = _out_0;
          spare_free(e, cls_fit(2), _sp_1);
        } else {
          Term _fb_2[2];
          u64 _sp_2 = ctr_take(e, _w_0, 2, _fb_2);
          Term _f_4 = _fb_2[0];
          Term _f_5 = _fb_2[1];
          Term _v_3 = 0;
          u64 _nd_0 = _sp_1 >= HEAP_OFF ? _sp_1 : heap_alloc(e, cls_fit(2));
          e.mem[_nd_0 + 0] = rfc_seal(e, _f_4);
          e.mem[_nd_0 + 1] = rfc_seal(e, _cur_0);
          Term _v_4 = 0;
          Term _o_0[1];
          if (spin_3(e, _o_0, term_ctr(CID_CON, _nd_0)) == 0) {
            return 0;
          }
          _v_4 = _o_0[0];
          _v_3 = _v_4;
          u64 _nd_1 = _sp_2 >= HEAP_OFF ? _sp_2 : heap_alloc(e, cls_fit(2));
          e.mem[_nd_1 + 0] = rfc_seal(e, _v_3);
          e.mem[_nd_1 + 1] = rfc_seal(e, _out_0);
          r0 = _f_3;
          r1 = _f_5;
          r2 = term_pak(CID_NIL, 0);
          r3 = term_ctr(CID_CON, _nd_1);
          _marks_0 = r0;
          _w_0 = r1;
          _cur_0 = r2;
          _out_0 = r3;
          WL_AGAIN(spin_6);
        }
      } else {
        Term _p_0 = (_f_2 - 1);
        if (term_aux(_w_0) == CID_NIL) {
          term_sink(e, _f_3);
          term_sink(e, _cur_0);
          _v_2 = _out_0;
          spare_free(e, cls_fit(2), _sp_1);
        } else {
          Term _fb_3[2];
          u64 _sp_3 = ctr_take(e, _w_0, 2, _fb_3);
          Term _f_6 = _fb_3[0];
          Term _f_7 = _fb_3[1];
          u64 _nd_2 = _sp_1 >= HEAP_OFF ? _sp_1 : heap_alloc(e, cls_fit(2));
          e.mem[_nd_2 + 0] = rfc_seal(e, _f_6);
          e.mem[_nd_2 + 1] = rfc_seal(e, _cur_0);
          spare_free(e, cls_fit(2), _sp_3);
          r0 = _f_3;
          r1 = _f_7;
          r2 = term_ctr(CID_CON, _nd_2);
          r3 = _out_0;
          _marks_0 = r0;
          _w_0 = r1;
          _cur_0 = r2;
          _out_0 = r3;
          WL_AGAIN(spin_6);
        }
      }
    }
  break;
  }
  o[0] = _v_2;
  return 1;
}

INLINE Term spin_7(Env e, THR Term* o, Term r0, Term r1) {
  u32 wpoll = 0;
  Term _v_8 = 0;
  Term _n_0 = r0;
  Term _xs_0 = r1;
  WL_SPIN
    if (_n_0 == 0) {
      if (term_aux(_xs_0) == CID_NIL) {
        _v_8 = term_pak(CID_NIL, 0);
      } else {
        Term _fb_4[2];
        u64 _sp_4 = ctr_take(e, _xs_0, 2, _fb_4);
        Term _f_8 = _fb_4[0];
        Term _f_9 = _fb_4[1];
        u64 _nd_3 = _sp_4 >= HEAP_OFF ? _sp_4 : heap_alloc(e, cls_fit(2));
        e.mem[_nd_3 + 0] = rfc_seal(e, _f_8);
        e.mem[_nd_3 + 1] = rfc_seal(e, _f_9);
        _v_8 = term_ctr(CID_CON, _nd_3);
      }
    } else {
      Term _p_1 = (_n_0 - 1);
      if (term_aux(_xs_0) == CID_NIL) {
        _v_8 = term_pak(CID_NIL, 0);
      } else {
        Term _fb_5[2];
        u64 _sp_5 = ctr_take(e, _xs_0, 2, _fb_5);
        Term _f_10 = _fb_5[0];
        Term _f_11 = _fb_5[1];
        spare_free(e, cls_fit(2), _sp_5);
        r0 = _p_1;
        r1 = _f_11;
        _n_0 = r0;
        _xs_0 = r1;
        WL_AGAIN(spin_7);
      }
    }
  break;
  }
  o[0] = _v_8;
  return 1;
}

INLINE Term spin_8(Env e, THR Term* o, u32 r0, Term r1) {
  u32 wpoll = 0;
  Term _v_1 = 0;
  u32 _c_1 = r0;
  Term _ps_0 = r1;
  WL_SPIN
    if (term_aux(_ps_0) == CID_NIL) {
      u64 _nd_0 = heap_alloc(e, cls_fit(2));
      e.mem[_nd_0 + 0] = rfc_seal(e, _c_1);
      e.mem[_nd_0 + 1] = rfc_seal(e, term_pak(CID_SNIL, 0));
      u64 _nd_1 = heap_alloc(e, cls_fit(2));
      e.mem[_nd_1 + 0] = rfc_seal(e, term_ctr(CID_SCON, _nd_0));
      e.mem[_nd_1 + 1] = rfc_seal(e, term_pak(CID_NIL, 0));
      _v_1 = term_ctr(CID_CON, _nd_1);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _ps_0, 2, _fb_0);
      Term _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      u64 _nd_2 = _sp_0 >= HEAP_OFF ? _sp_0 : heap_alloc(e, cls_fit(2));
      e.mem[_nd_2 + 0] = rfc_seal(e, _c_1);
      e.mem[_nd_2 + 1] = rfc_seal(e, _f_0);
      u64 _nd_3 = heap_alloc(e, cls_fit(2));
      e.mem[_nd_3 + 0] = rfc_seal(e, term_ctr(CID_SCON, _nd_2));
      e.mem[_nd_3 + 1] = rfc_seal(e, _f_1);
      _v_1 = term_ctr(CID_CON, _nd_3);
    }
  break;
  }
  o[0] = _v_1;
  return 1;
}

INLINE Term spin_9(Env e, THR Term* o, u32 r0) {
  u32 wpoll = 0;
  u32 _v_2 = 0;
  u32 _b_0 = r0;
  WL_SPIN
    u32 _w_0 = ((_b_0 >> 0) & 1);
    u32 _w_1 = ((_b_0 >> 1) & 1);
    u32 _w_2 = ((_b_0 >> 2) & 1);
    u32 _w_3 = ((_b_0 >> 3) & 1);
    u32 _w_4 = ((_b_0 >> 4) & 1);
    u32 _w_5 = ((_b_0 >> 5) & 1);
    u32 _w_6 = ((_b_0 >> 6) & 1);
    u32 _w_7 = ((_b_0 >> 7) & 1);
    u32 _w_8 = ((_b_0 >> 8) & 1);
    u32 _w_9 = ((_b_0 >> 9) & 1);
    u32 _w_10 = ((_b_0 >> 10) & 1);
    u32 _w_11 = ((_b_0 >> 11) & 1);
    u32 _w_12 = ((_b_0 >> 12) & 1);
    u32 _w_13 = ((_b_0 >> 13) & 1);
    u32 _w_14 = ((_b_0 >> 14) & 1);
    u32 _w_15 = ((_b_0 >> 15) & 1);
    u32 _w_16 = ((_b_0 >> 16) & 1);
    u32 _w_17 = ((_b_0 >> 17) & 1);
    u32 _w_18 = ((_b_0 >> 18) & 1);
    u32 _w_19 = ((_b_0 >> 19) & 1);
    u32 _w_20 = ((_b_0 >> 20) & 1);
    u32 _w_21 = ((_b_0 >> 21) & 1);
    u32 _w_22 = ((_b_0 >> 22) & 1);
    u32 _w_23 = ((_b_0 >> 23) & 1);
    u32 _w_24 = ((_b_0 >> 24) & 1);
    u32 _w_25 = ((_b_0 >> 25) & 1);
    u32 _w_26 = ((_b_0 >> 26) & 1);
    u32 _w_27 = ((_b_0 >> 27) & 1);
    u32 _w_28 = ((_b_0 >> 28) & 1);
    u32 _w_29 = ((_b_0 >> 29) & 1);
    u32 _w_30 = ((_b_0 >> 30) & 1);
    u32 _w_31 = ((_b_0 >> 31) & 1);
    _v_2 = (((u64)_w_0 << 0) | ((u64)_w_1 << 1) | ((u64)_w_2 << 2) | ((u64)_w_3 << 3) | ((u64)_w_4 << 4) | ((u64)_w_5 << 5) | ((u64)_w_6 << 6) | ((u64)_w_7 << 7) | ((u64)_w_8 << 8) | ((u64)_w_9 << 9) | ((u64)_w_10 << 10) | ((u64)_w_11 << 11) | ((u64)_w_12 << 12) | ((u64)_w_13 << 13) | ((u64)_w_14 << 14) | ((u64)_w_15 << 15) | ((u64)_w_16 << 16) | ((u64)_w_17 << 17) | ((u64)_w_18 << 18) | ((u64)_w_19 << 19) | ((u64)_w_20 << 20) | ((u64)_w_21 << 21) | ((u64)_w_22 << 22) | ((u64)_w_23 << 23) | ((u64)_w_24 << 24) | ((u64)_w_25 << 25) | ((u64)_w_26 << 26) | ((u64)_w_27 << 27) | ((u64)_w_28 << 28) | ((u64)_w_29 << 29) | ((u64)_w_30 << 30) | ((u64)_w_31 << 31));
  break;
  }
  o[0] = _v_2;
  return 1;
}

INLINE Term spin_10(Env e, THR Term* o, u32 r0, Term r1) {
  u32 wpoll = 0;
  Term _v_1 = 0;
  u32 _acc_1 = r0;
  Term _r_1 = r1;
  WL_SPIN
    u64 _nd_0 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_0 + 0] = rfc_seal(e, f32_rewrap(f32_unbox(_acc_1) / f32_unbox(1073741824ull)));
    e.mem[_nd_0 + 1] = rfc_seal(e, _r_1);
    _v_1 = term_ctr(CID_CON, _nd_0);
  break;
  }
  o[0] = _v_1;
  return 1;
}

INLINE Term spin_11(Env e, THR Term* o, u32 r0, u32 r1) {
  u32 wpoll = 0;
  u32 _v_2 = 0;
  u32 _a_0 = r0;
  u32 _b_0 = r1;
  WL_SPIN
    _v_2 = U32_BIN(_a_0, ==, _b_0);
  break;
  }
  o[0] = _v_2;
  return 1;
}

INLINE Term spin_12(Env e, THR Term* o, u32 r0, Term r1, u32 r2) {
  u32 wpoll = 0;
  Term _v_4 = 0;
  u32 _c_0 = r0;
  Term _r_0 = r1;
  u32 _cut_0 = r2;
  WL_SPIN
    if (_cut_0 == 0) {
      Term _v_5 = 0;
      Term _o_1[1];
      if (spin_8(e, _o_1, _c_0, _r_0) == 0) {
        return 0;
      }
      _v_5 = _o_1[0];
      _v_4 = _v_5;
    } else {
      u64 _nd_0 = heap_alloc(e, cls_fit(2));
      e.mem[_nd_0 + 0] = rfc_seal(e, term_pak(CID_SNIL, 0));
      e.mem[_nd_0 + 1] = rfc_seal(e, _r_0);
      _v_4 = term_ctr(CID_CON, _nd_0);
    }
  break;
  }
  o[0] = _v_4;
  return 1;
}

INLINE Term spin_13(Env e, THR Term* o, Term r0, Term r1) {
  u32 wpoll = 0;
  Term _v_2 = 0;
  Term _n_0 = r0;
  Term _xs_0 = r1;
  WL_SPIN
    if (_n_0 == 0) {
      if (term_aux(_xs_0) == CID_NIL) {
        _v_2 = term_pak(CID_NIL, 0);
      } else {
        Term _fb_0[2];
        u64 _sp_0 = ctr_take(e, _xs_0, 2, _fb_0);
        Term _f_0 = _fb_0[0];
        Term _f_1 = _fb_0[1];
        u64 _nd_0 = _sp_0 >= HEAP_OFF ? _sp_0 : heap_alloc(e, cls_fit(2));
        e.mem[_nd_0 + 0] = rfc_seal(e, _f_0);
        e.mem[_nd_0 + 1] = rfc_seal(e, _f_1);
        _v_2 = term_ctr(CID_CON, _nd_0);
      }
    } else {
      Term _p_0 = (_n_0 - 1);
      if (term_aux(_xs_0) == CID_NIL) {
        _v_2 = term_pak(CID_NIL, 0);
      } else {
        Term _fb_1[2];
        u64 _sp_1 = ctr_take(e, _xs_0, 2, _fb_1);
        Term _f_2 = _fb_1[0];
        Term _f_3 = _fb_1[1];
        term_sink(e, _f_2);
        spare_free(e, cls_fit(2), _sp_1);
        r0 = _p_0;
        r1 = _f_3;
        _n_0 = r0;
        _xs_0 = r1;
        WL_AGAIN(spin_13);
      }
    }
  break;
  }
  o[0] = _v_2;
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
  WL_CASE(FID_U32_READ_GO)
  {
    Term _s_0 = r0;
    u32 _acc_0 = r1;
    WL_OPEN
    WL_SPIN
    if (term_aux(_s_0) == CID_SNIL) {
      r0 = 1;
      r1 = _acc_0;
      WL_RETN(2);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _s_0, 2, _fb_0);
      u32 _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      u32 _n_0 = U32_BIN(U32_BIN(_acc_0, *, 10ull), +, U32_BIN(_f_0, -, 48ull));
      Term _a_0 = 10ull;
      u32 _s_1 = U32_BIN(((u32)(_a_0) == 0 ? 0 : (u64)U32_QUO((u32)(_n_0), (u32)(_a_0))), ==, _acc_0);
      if (_s_1 == 1) {
        spare_free(e, cls_fit(2), _sp_0);
        r0 = _f_1;
        r1 = _n_0;
        _s_0 = r0;
        _acc_0 = r1;
        WL_AGAIN(FID_U32_READ_GO);
      } else {
        term_sink(e, _f_1);
        spare_free(e, cls_fit(2), _sp_0);
        r0 = 0;
        r1 = 0;
        WL_RETN(2);
      }
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_EXP_SUM)
  {
    Term _z_0 = r0;
    WL_OPEN
    WL_SPIN
    if (term_aux(_z_0) == CID_NIL) {
      r0 = 0ull;
      WL_RETN(1);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _z_0, 2, _fb_0);
      Term _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      spare_free(e, cls_fit(2), _sp_0);
      if (seq) {
        WL_ROOM(2);
        STK(0) = _f_0;
        STK(1) = FID_EXP_SUM_K6;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_EXP_SUM_K6, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _f_0;
        WL_CONT = term_tsk(FID_EXP_SUM_K6, _t_0);
        WL_IDX = 1;
      }
      r0 = _f_1;
      _z_0 = r0;
      WL_AGAIN(FID_EXP_SUM);
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_EXP_SUM_K6)
  {
    WL_POPN(1);
    u32 _f_2 = STK(0);
    u32 _h_0 = r0;
    WL_OPEN
    r0 = f32_rewrap(f32_unbox(f32_rewrap((f32)exp(f32_unbox(_f_2)))) + f32_unbox(_h_0));
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MARKS)
  {
    Term _n_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MARKS_K8;
      WL_PUSHN(1);
    } else {
      u64 _t_0 = task_node(e, FID_MARKS_K8, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MARKS_K8, _t_0);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_LIST_REPLICATE)) {
      u64 _t_1 = task_node(e, FID_LIST_REPLICATE, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _n_0;
      e.mem[_t_1 + 1] = 1ull;
      return term_tsk(FID_LIST_REPLICATE, _t_1);
    }
    r0 = _n_0;
    r1 = 1ull;
    WL_JMP(FID_LIST_REPLICATE);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MARKS_K8)
  {
    Term _h_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _h_0;
      STK(1) = FID_MARKS_K9;
      WL_PUSHN(2);
    } else {
      u64 _t_2 = task_node(e, FID_MARKS_K9, WL_CONT, WL_IDX, 1);
      e.mem[_t_2 + 0] = _h_0;
      WL_CONT = term_tsk(FID_MARKS_K9, _t_2);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_LIST_REPLICATE)) {
      u64 _t_3 = task_node(e, FID_LIST_REPLICATE, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = 1ull;
      e.mem[_t_3 + 1] = 0;
      return term_tsk(FID_LIST_REPLICATE, _t_3);
    }
    r0 = 1ull;
    r1 = 0;
    WL_JMP(FID_LIST_REPLICATE);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MARKS_K9)
  {
    WL_POPN(1);
    Term _h_2 = STK(0);
    Term _h_1 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_LIST_APPEND)) {
      u64 _t_4 = task_node(e, FID_LIST_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_4 + 0] = _h_2;
      e.mem[_t_4 + 1] = _h_1;
      return term_tsk(FID_LIST_APPEND, _t_4);
    }
    r0 = _h_2;
    r1 = _h_1;
    WL_JMP(FID_LIST_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_DOT)
  {
    Term _r_0 = r0;
    Term _xs_0 = r1;
    WL_OPEN
    WL_SPIN
    if (term_aux(_r_0) == CID_NIL) {
      if (term_aux(_xs_0) == CID_NIL) {
        r0 = 0ull;
        WL_RETN(1);
      } else {
        Term _fb_0[2];
        u64 _sp_0 = ctr_take(e, _xs_0, 2, _fb_0);
        Term _f_0 = _fb_0[0];
        Term _f_1 = _fb_0[1];
        term_sink(e, _f_1);
        spare_free(e, cls_fit(2), _sp_0);
        r0 = 0ull;
        WL_RETN(1);
      }
    } else {
      Term _fb_1[2];
      u64 _sp_1 = ctr_take(e, _r_0, 2, _fb_1);
      Term _f_2 = _fb_1[0];
      Term _f_3 = _fb_1[1];
      if (term_aux(_xs_0) == CID_NIL) {
        spare_free(e, cls_fit(2), _sp_1);
        if (seq) {
          WL_ROOM(2);
          STK(0) = _f_2;
          STK(1) = FID_DOT_K12;
          WL_PUSHN(2);
        } else {
          u64 _t_0 = task_node(e, FID_DOT_K12, WL_CONT, WL_IDX, 1);
          e.mem[_t_0 + 0] = _f_2;
          WL_CONT = term_tsk(FID_DOT_K12, _t_0);
          WL_IDX = 1;
        }
        r0 = _f_3;
        r1 = term_pak(CID_NIL, 0);
        _r_0 = r0;
        _xs_0 = r1;
        WL_AGAIN(FID_DOT);
      } else {
        Term _fb_2[2];
        u64 _sp_2 = ctr_take(e, _xs_0, 2, _fb_2);
        Term _f_5 = _fb_2[0];
        Term _f_6 = _fb_2[1];
        spare_free(e, cls_fit(2), _sp_2);
        spare_free(e, cls_fit(2), _sp_1);
        if (seq) {
          WL_ROOM(3);
          STK(0) = _f_2;
          STK(1) = _f_5;
          STK(2) = FID_DOT_K13;
          WL_PUSHN(3);
        } else {
          u64 _t_1 = task_node(e, FID_DOT_K13, WL_CONT, WL_IDX, 1);
          e.mem[_t_1 + 0] = _f_2;
          e.mem[_t_1 + 1] = _f_5;
          WL_CONT = term_tsk(FID_DOT_K13, _t_1);
          WL_IDX = 2;
        }
        r0 = _f_3;
        r1 = _f_6;
        _r_0 = r0;
        _xs_0 = r1;
        WL_AGAIN(FID_DOT);
      }
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_DOT_K12)
  {
    WL_POPN(1);
    u32 _f_4 = STK(0);
    u32 _h_0 = r0;
    WL_OPEN
    r0 = f32_rewrap(f32_unbox(_h_0) + f32_unbox(_f_4));
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_DOT_K13)
  {
    WL_POPN(2);
    u32 _f_7 = STK(0);
    u32 _f_8 = STK(1);
    u32 _h_1 = r0;
    WL_OPEN
    r0 = f32_rewrap(f32_unbox(f32_rewrap(f32_unbox(_f_7) * f32_unbox(_f_8))) + f32_unbox(_h_1));
    WL_RETN(1);
  }}
#endif

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
        e.mem[_nd_0 + 0] = rfc_seal(e, U32_BIN(48ull, +, ((u32)(_a_1) == 0 ? _n_0 : U32_BIN(_n_0, -, U32_QUO((u32)(_n_0), (u32)(_a_1)) * _a_1))));
        e.mem[_nd_0 + 1] = rfc_seal(e, _acc_0);
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
  WL_CASE(FID_U32_READ)
  {
    Term _s_0 = r0;
    WL_OPEN
    if (term_aux(_s_0) == CID_SNIL) {
      r0 = 0;
      r1 = 0;
      WL_RETN(2);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _s_0, 2, _fb_0);
      u32 _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      u64 _nd_0 = _sp_0 >= HEAP_OFF ? _sp_0 : heap_alloc(e, cls_fit(2));
      e.mem[_nd_0 + 0] = rfc_seal(e, _f_0);
      e.mem[_nd_0 + 1] = rfc_seal(e, _f_1);
      if (!DEVICE && !seq && fid_nofk(FID_U32_READ_GO)) {
        u64 _t_0 = task_node(e, FID_U32_READ_GO, WL_CONT, WL_IDX, 0);
        e.mem[_t_0 + 0] = term_ctr(CID_SCON, _nd_0);
        e.mem[_t_0 + 1] = 0ull;
        return term_tsk(FID_U32_READ_GO, _t_0);
      }
      r0 = term_ctr(CID_SCON, _nd_0);
      r1 = 0ull;
      WL_JMP(FID_U32_READ_GO);
    }
  }}
#endif

#if !DEVICE
  WL_CASE(FID_LIST_APPEND)
  {
    Term _xs_0 = r0;
    Term _ys_0 = r1;
    WL_OPEN
    WL_SPIN
    if (term_aux(_xs_0) == CID_NIL) {
      r0 = _ys_0;
      WL_RETN(1);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _xs_0, 2, _fb_0);
      Term _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      spare_free(e, cls_fit(2), _sp_0);
      if (seq) {
        WL_ROOM(2);
        STK(0) = _f_0;
        STK(1) = FID_LIST_APPEND_K18;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_LIST_APPEND_K18, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _f_0;
        WL_CONT = term_tsk(FID_LIST_APPEND_K18, _t_0);
        WL_IDX = 1;
      }
      r0 = _f_1;
      r1 = _ys_0;
      _xs_0 = r0;
      _ys_0 = r1;
      WL_AGAIN(FID_LIST_APPEND);
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_LIST_APPEND_K18)
  {
    WL_POPN(1);
    Term _f_2 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    u64 _nd_0 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_0 + 0] = rfc_seal(e, _f_2);
    e.mem[_nd_0 + 1] = rfc_seal(e, _h_0);
    r0 = term_ctr(CID_CON, _nd_0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CROSS_ENTROPY)
  {
    Term _z_0 = r0;
    Term _ls_0 = r1;
    Term _k_0 = r2;
    WL_OPEN
    _z_0 = term_keep(e, _z_0, 1);
    if (seq) {
      WL_ROOM(4);
      STK(0) = _z_0;
      STK(1) = _ls_0;
      STK(2) = _k_0;
      STK(3) = FID_CROSS_ENTROPY_K20;
      WL_PUSHN(4);
    } else {
      u64 _t_0 = task_node(e, FID_CROSS_ENTROPY_K20, WL_CONT, WL_IDX, 1);
      e.mem[_t_0 + 0] = _z_0;
      e.mem[_t_0 + 1] = _ls_0;
      e.mem[_t_0 + 2] = _k_0;
      WL_CONT = term_tsk(FID_CROSS_ENTROPY_K20, _t_0);
      WL_IDX = 3;
    }
    if (!DEVICE && !seq && fid_nofk(FID_EXP_SUM)) {
      u64 _t_1 = task_node(e, FID_EXP_SUM, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _z_0;
      return term_tsk(FID_EXP_SUM, _t_1);
    }
    r0 = _z_0;
    WL_JMP(FID_EXP_SUM);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CROSS_ENTROPY_K20)
  {
    WL_POPN(3);
    Term _z_1 = STK(0);
    Term _ls_1 = STK(1);
    Term _k_1 = STK(2);
    u32 _h_0 = r0;
    WL_OPEN
    u32 _v_0 = 0;
    u32 _v_1 = 0;
    u32 _v_2 = 0;
    Term _o_0[1];
    if (spin_1(e, _o_0, _k_1, _ls_1) == 0) {
      return 0;
    }
    _v_2 = _o_0[0];
    _v_1 = _v_2;
    u32 _v_4 = 0;
    Term _o_1[1];
    if (spin_2(e, _o_1, ((u64)_v_1), _z_1) == 0) {
      return 0;
    }
    _v_4 = _o_1[0];
    _v_0 = _v_4;
    r0 = f32_rewrap(f32_unbox(f32_rewrap((f32)log(f32_unbox(_h_0)))) - f32_unbox(f32_rewrap((f32)exp(f32_unbox(_v_0)))));
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CS4)
  {
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_CS4_K23;
      WL_PUSHN(1);
    } else {
      u64 _t_0 = task_node(e, FID_CS4_K23, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_CS4_K23, _t_0);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_MARKS)) {
      u64 _t_1 = task_node(e, FID_MARKS, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = 3ull;
      return term_tsk(FID_MARKS, _t_1);
    }
    r0 = 3ull;
    WL_JMP(FID_MARKS);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CS4_K23)
  {
    Term _h_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _h_0;
      STK(1) = FID_CS4_K24;
      WL_PUSHN(2);
    } else {
      u64 _t_2 = task_node(e, FID_CS4_K24, WL_CONT, WL_IDX, 1);
      e.mem[_t_2 + 0] = _h_0;
      WL_CONT = term_tsk(FID_CS4_K24, _t_2);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_MARKS)) {
      u64 _t_3 = task_node(e, FID_MARKS, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = 3ull;
      return term_tsk(FID_MARKS, _t_3);
    }
    r0 = 3ull;
    WL_JMP(FID_MARKS);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CS4_K24)
  {
    WL_POPN(1);
    Term _h_2 = STK(0);
    Term _h_1 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_CS4_K25;
      WL_PUSHN(1);
    } else {
      u64 _t_4 = task_node(e, FID_CS4_K25, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_CS4_K25, _t_4);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_LIST_APPEND)) {
      u64 _t_5 = task_node(e, FID_LIST_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_5 + 0] = _h_2;
      e.mem[_t_5 + 1] = _h_1;
      return term_tsk(FID_LIST_APPEND, _t_5);
    }
    r0 = _h_2;
    r1 = _h_1;
    WL_JMP(FID_LIST_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CS4_K25)
  {
    Term _h_3 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _h_3;
      STK(1) = FID_CS4_K26;
      WL_PUSHN(2);
    } else {
      u64 _t_6 = task_node(e, FID_CS4_K26, WL_CONT, WL_IDX, 1);
      e.mem[_t_6 + 0] = _h_3;
      WL_CONT = term_tsk(FID_CS4_K26, _t_6);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_MARKS)) {
      u64 _t_7 = task_node(e, FID_MARKS, WL_CONT, WL_IDX, 0);
      e.mem[_t_7 + 0] = 3ull;
      return term_tsk(FID_MARKS, _t_7);
    }
    r0 = 3ull;
    WL_JMP(FID_MARKS);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CS4_K26)
  {
    WL_POPN(1);
    Term _h_5 = STK(0);
    Term _h_4 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_LIST_APPEND)) {
      u64 _t_8 = task_node(e, FID_LIST_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_8 + 0] = _h_5;
      e.mem[_t_8 + 1] = _h_4;
      return term_tsk(FID_LIST_APPEND, _t_8);
    }
    r0 = _h_5;
    r1 = _h_4;
    WL_JMP(FID_LIST_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CS5)
  {
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_CS5_K28;
      WL_PUSHN(1);
    } else {
      u64 _t_0 = task_node(e, FID_CS5_K28, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_CS5_K28, _t_0);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_MARKS)) {
      u64 _t_1 = task_node(e, FID_MARKS, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = 4ull;
      return term_tsk(FID_MARKS, _t_1);
    }
    r0 = 4ull;
    WL_JMP(FID_MARKS);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CS5_K28)
  {
    Term _h_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _h_0;
      STK(1) = FID_CS5_K29;
      WL_PUSHN(2);
    } else {
      u64 _t_2 = task_node(e, FID_CS5_K29, WL_CONT, WL_IDX, 1);
      e.mem[_t_2 + 0] = _h_0;
      WL_CONT = term_tsk(FID_CS5_K29, _t_2);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_MARKS)) {
      u64 _t_3 = task_node(e, FID_MARKS, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = 4ull;
      return term_tsk(FID_MARKS, _t_3);
    }
    r0 = 4ull;
    WL_JMP(FID_MARKS);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CS5_K29)
  {
    WL_POPN(1);
    Term _h_2 = STK(0);
    Term _h_1 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_CS5_K30;
      WL_PUSHN(1);
    } else {
      u64 _t_4 = task_node(e, FID_CS5_K30, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_CS5_K30, _t_4);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_LIST_APPEND)) {
      u64 _t_5 = task_node(e, FID_LIST_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_5 + 0] = _h_2;
      e.mem[_t_5 + 1] = _h_1;
      return term_tsk(FID_LIST_APPEND, _t_5);
    }
    r0 = _h_2;
    r1 = _h_1;
    WL_JMP(FID_LIST_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CS5_K30)
  {
    Term _h_3 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _h_3;
      STK(1) = FID_CS5_K31;
      WL_PUSHN(2);
    } else {
      u64 _t_6 = task_node(e, FID_CS5_K31, WL_CONT, WL_IDX, 1);
      e.mem[_t_6 + 0] = _h_3;
      WL_CONT = term_tsk(FID_CS5_K31, _t_6);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_MARKS)) {
      u64 _t_7 = task_node(e, FID_MARKS, WL_CONT, WL_IDX, 0);
      e.mem[_t_7 + 0] = 4ull;
      return term_tsk(FID_MARKS, _t_7);
    }
    r0 = 4ull;
    WL_JMP(FID_MARKS);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CS5_K31)
  {
    WL_POPN(1);
    Term _h_5 = STK(0);
    Term _h_4 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_LIST_APPEND)) {
      u64 _t_8 = task_node(e, FID_LIST_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_8 + 0] = _h_5;
      e.mem[_t_8 + 1] = _h_4;
      return term_tsk(FID_LIST_APPEND, _t_8);
    }
    r0 = _h_5;
    r1 = _h_4;
    WL_JMP(FID_LIST_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_ROWS)
  {
    Term _rs_0 = r0;
    Term _x_0 = r1;
    Term _out_0 = r2;
    WL_OPEN
    if (term_aux(_rs_0) == CID_NIL) {
      term_sink(e, _x_0);
      r0 = _out_0;
      WL_RETN(1);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _rs_0, 2, _fb_0);
      Term _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      _x_0 = term_keep(e, _x_0, 1);
      spare_free(e, cls_fit(2), _sp_0);
      if (seq) {
        WL_ROOM(4);
        STK(0) = _f_1;
        STK(1) = _x_0;
        STK(2) = _out_0;
        STK(3) = FID_ROWS_K34;
        WL_PUSHN(4);
      } else {
        u64 _t_0 = task_node(e, FID_ROWS_K34, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _f_1;
        e.mem[_t_0 + 1] = _x_0;
        e.mem[_t_0 + 2] = _out_0;
        WL_CONT = term_tsk(FID_ROWS_K34, _t_0);
        WL_IDX = 3;
      }
      if (!DEVICE && !seq && fid_nofk(FID_DOT)) {
        u64 _t_1 = task_node(e, FID_DOT, WL_CONT, WL_IDX, 0);
        e.mem[_t_1 + 0] = _f_0;
        e.mem[_t_1 + 1] = _x_0;
        return term_tsk(FID_DOT, _t_1);
      }
      r0 = _f_0;
      r1 = _x_0;
      WL_JMP(FID_DOT);
    }
  }}
#endif

#if !DEVICE
  WL_CASE(FID_ROWS_K34)
  {
    WL_POPN(3);
    Term _f_2 = STK(0);
    Term _x_1 = STK(1);
    Term _out_1 = STK(2);
    u32 _h_0 = r0;
    WL_OPEN
    u64 _nd_0 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_0 + 0] = rfc_seal(e, _h_0);
    e.mem[_nd_0 + 1] = rfc_seal(e, _out_1);
    if (!DEVICE && !seq && fid_nofk(FID_ROWS)) {
      u64 _t_2 = task_node(e, FID_ROWS, WL_CONT, WL_IDX, 0);
      e.mem[_t_2 + 0] = _f_2;
      e.mem[_t_2 + 1] = _x_1;
      e.mem[_t_2 + 2] = term_ctr(CID_CON, _nd_0);
      return term_tsk(FID_ROWS, _t_2);
    }
    r0 = _f_2;
    r1 = _x_1;
    r2 = term_ctr(CID_CON, _nd_0);
    WL_JMP(FID_ROWS);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_PARSE)
  {
    Term _s_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_PARSE_K38;
      WL_PUSHN(1);
    } else {
      u64 _t_0 = task_node(e, FID_PARSE_K38, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_PARSE_K38, _t_0);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_U32_READ)) {
      u64 _t_1 = task_node(e, FID_U32_READ, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _s_0;
      return term_tsk(FID_U32_READ, _t_1);
    }
    r0 = _s_0;
    WL_JMP(FID_U32_READ);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_PARSE_K38)
  {
    u32 _h_0 = r0;
    u32 _h_1 = r1;
    WL_OPEN
    u32 _v_0 = 0;
    Term _o_0[1];
    if (spin_5(e, _o_0, _h_0, _h_1) == 0) {
      return 0;
    }
    _v_0 = _o_0[0];
    r0 = _v_0;
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SAMPLE)
  {
    Term _row_0 = r0;
    Term _ls_0 = r1;
    Term _ws_0 = r2;
    Term _li_0 = r3;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _row_0;
      STK(1) = _ls_0;
      STK(2) = _ws_0;
      STK(3) = _li_0;
      STK(4) = FID_SAMPLE_K41;
      WL_PUSHN(5);
    } else {
      u64 _t_0 = task_node(e, FID_SAMPLE_K41, WL_CONT, WL_IDX, 1);
      e.mem[_t_0 + 0] = _row_0;
      e.mem[_t_0 + 1] = _ls_0;
      e.mem[_t_0 + 2] = _ws_0;
      e.mem[_t_0 + 3] = _li_0;
      WL_CONT = term_tsk(FID_SAMPLE_K41, _t_0);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID_CS5)) {
      u64 _t_1 = task_node(e, FID_CS5, WL_CONT, WL_IDX, 0);
      return term_tsk(FID_CS5, _t_1);
    }
    WL_JMP(FID_CS5);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SAMPLE_K41)
  {
    WL_POPN(4);
    Term _row_1 = STK(0);
    Term _ls_1 = STK(1);
    Term _ws_1 = STK(2);
    Term _li_1 = STK(3);
    Term _h_0 = r0;
    WL_OPEN
    Term _v_0 = 0;
    _ws_1 = term_keep(e, _ws_1, 1);
    Term _v_1 = 0;
    Term _o_1[1];
    if (spin_6(e, _o_1, _h_0, _ws_1, term_pak(CID_NIL, 0), term_pak(CID_NIL, 0)) == 0) {
      return 0;
    }
    _v_1 = _o_1[0];
    _v_0 = _v_1;
    if (seq) {
      WL_ROOM(4);
      STK(0) = _ls_1;
      STK(1) = _ws_1;
      STK(2) = _li_1;
      STK(3) = FID_SAMPLE_K42;
      WL_PUSHN(4);
    } else {
      u64 _t_2 = task_node(e, FID_SAMPLE_K42, WL_CONT, WL_IDX, 1);
      e.mem[_t_2 + 0] = _ls_1;
      e.mem[_t_2 + 1] = _ws_1;
      e.mem[_t_2 + 2] = _li_1;
      WL_CONT = term_tsk(FID_SAMPLE_K42, _t_2);
      WL_IDX = 3;
    }
    if (!DEVICE && !seq && fid_nofk(FID_ROWS)) {
      u64 _t_3 = task_node(e, FID_ROWS, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = _v_0;
      e.mem[_t_3 + 1] = _row_1;
      e.mem[_t_3 + 2] = term_pak(CID_NIL, 0);
      return term_tsk(FID_ROWS, _t_3);
    }
    r0 = _v_0;
    r1 = _row_1;
    r2 = term_pak(CID_NIL, 0);
    WL_JMP(FID_ROWS);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SAMPLE_K42)
  {
    WL_POPN(3);
    Term _ls_2 = STK(0);
    Term _ws_2 = STK(1);
    Term _li_2 = STK(2);
    Term _h_1 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _ls_2;
      STK(1) = _ws_2;
      STK(2) = _li_2;
      STK(3) = _h_1;
      STK(4) = FID_SAMPLE_K43;
      WL_PUSHN(5);
    } else {
      u64 _t_4 = task_node(e, FID_SAMPLE_K43, WL_CONT, WL_IDX, 1);
      e.mem[_t_4 + 0] = _ls_2;
      e.mem[_t_4 + 1] = _ws_2;
      e.mem[_t_4 + 2] = _li_2;
      e.mem[_t_4 + 3] = _h_1;
      WL_CONT = term_tsk(FID_SAMPLE_K43, _t_4);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID_CS4)) {
      u64 _t_5 = task_node(e, FID_CS4, WL_CONT, WL_IDX, 0);
      return term_tsk(FID_CS4, _t_5);
    }
    WL_JMP(FID_CS4);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SAMPLE_K43)
  {
    WL_POPN(4);
    Term _ls_3 = STK(0);
    Term _ws_3 = STK(1);
    Term _li_3 = STK(2);
    Term _h_3 = STK(3);
    Term _h_2 = r0;
    WL_OPEN
    Term _v_5 = 0;
    Term _v_6 = 0;
    Term _v_7 = 0;
    Term _o_2[1];
    if (spin_7(e, _o_2, 15ull, _ws_3) == 0) {
      return 0;
    }
    _v_7 = _o_2[0];
    _v_6 = _v_7;
    Term _v_9 = 0;
    Term _o_3[1];
    if (spin_6(e, _o_3, _h_2, _v_6, term_pak(CID_NIL, 0), term_pak(CID_NIL, 0)) == 0) {
      return 0;
    }
    _v_9 = _o_3[0];
    _v_5 = _v_9;
    _h_3 = term_keep(e, _h_3, 1);
    if (seq) {
      WL_ROOM(4);
      STK(0) = _ls_3;
      STK(1) = _li_3;
      STK(2) = _h_3;
      STK(3) = FID_SAMPLE_K44;
      WL_PUSHN(4);
    } else {
      u64 _t_6 = task_node(e, FID_SAMPLE_K44, WL_CONT, WL_IDX, 1);
      e.mem[_t_6 + 0] = _ls_3;
      e.mem[_t_6 + 1] = _li_3;
      e.mem[_t_6 + 2] = _h_3;
      WL_CONT = term_tsk(FID_SAMPLE_K44, _t_6);
      WL_IDX = 3;
    }
    if (!DEVICE && !seq && fid_nofk(FID_ROWS)) {
      u64 _t_7 = task_node(e, FID_ROWS, WL_CONT, WL_IDX, 0);
      e.mem[_t_7 + 0] = _v_5;
      e.mem[_t_7 + 1] = _h_3;
      e.mem[_t_7 + 2] = term_pak(CID_NIL, 0);
      return term_tsk(FID_ROWS, _t_7);
    }
    r0 = _v_5;
    r1 = _h_3;
    r2 = term_pak(CID_NIL, 0);
    WL_JMP(FID_ROWS);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SAMPLE_K44)
  {
    WL_POPN(3);
    Term _ls_4 = STK(0);
    Term _li_4 = STK(1);
    Term _h_4 = STK(2);
    Term _z_0 = r0;
    WL_OPEN
    _z_0 = term_keep(e, _z_0, 1);
    if (seq) {
      WL_ROOM(3);
      STK(0) = _h_4;
      STK(1) = _z_0;
      STK(2) = FID_SAMPLE_K45;
      WL_PUSHN(3);
    } else {
      u64 _t_8 = task_node(e, FID_SAMPLE_K45, WL_CONT, WL_IDX, 1);
      e.mem[_t_8 + 0] = _h_4;
      e.mem[_t_8 + 1] = _z_0;
      WL_CONT = term_tsk(FID_SAMPLE_K45, _t_8);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_CROSS_ENTROPY)) {
      u64 _t_9 = task_node(e, FID_CROSS_ENTROPY, WL_CONT, WL_IDX, 0);
      e.mem[_t_9 + 0] = _z_0;
      e.mem[_t_9 + 1] = _ls_4;
      e.mem[_t_9 + 2] = _li_4;
      return term_tsk(FID_CROSS_ENTROPY, _t_9);
    }
    r0 = _z_0;
    r1 = _ls_4;
    r2 = _li_4;
    WL_JMP(FID_CROSS_ENTROPY);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SAMPLE_K45)
  {
    WL_POPN(2);
    Term _h_6 = STK(0);
    Term _z_1 = STK(1);
    u32 _h_5 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _h_5;
      STK(1) = FID_SAMPLE_K46;
      WL_PUSHN(2);
    } else {
      u64 _t_10 = task_node(e, FID_SAMPLE_K46, WL_CONT, WL_IDX, 1);
      e.mem[_t_10 + 0] = _h_5;
      WL_CONT = term_tsk(FID_SAMPLE_K46, _t_10);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_LIST_APPEND)) {
      u64 _t_11 = task_node(e, FID_LIST_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_11 + 0] = _h_6;
      e.mem[_t_11 + 1] = _z_1;
      return term_tsk(FID_LIST_APPEND, _t_11);
    }
    r0 = _h_6;
    r1 = _z_1;
    WL_JMP(FID_LIST_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SAMPLE_K46)
  {
    WL_POPN(1);
    u32 _h_8 = STK(0);
    Term _h_7 = r0;
    WL_OPEN
    u64 _nd_4 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_4 + 0] = rfc_seal(e, _h_8);
    e.mem[_nd_4 + 1] = rfc_seal(e, _h_7);
    r0 = term_ctr(CID_CON, _nd_4);
    WL_RETN(1);
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
  WL_CASE(FID_ARRAY_TO_LIST_GO_1)
  {
    Term _a_0 = r0;
    Term _acc_0 = r1;
    WL_OPEN
    WL_SPIN
    if (blk_cls(_a_0) == 0) {
      u32 _c_0 = blk_read(e.mem, 0, blk_loc(e.mem, _a_0), 0 + 0);
      blk_free(e, _a_0);
      u64 _nd_0 = heap_alloc(e, cls_fit(2));
      e.mem[_nd_0 + 0] = rfc_seal(e, _c_0);
      e.mem[_nd_0 + 1] = rfc_seal(e, _acc_0);
      r0 = term_ctr(CID_CON, _nd_0);
      WL_RETN(1);
    } else {
      Term _h_0 = blk_half(e, _a_0, 0);
      Term _h_1 = blk_half(e, _a_0, 1);
      if (seq) {
        WL_ROOM(2);
        STK(0) = _h_0;
        STK(1) = FID_ARRAY_TO_LIST_GO_1_K52;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_ARRAY_TO_LIST_GO_1_K52, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _h_0;
        WL_CONT = term_tsk(FID_ARRAY_TO_LIST_GO_1_K52, _t_0);
        WL_IDX = 1;
      }
      r0 = _h_1;
      r1 = _acc_0;
      _a_0 = r0;
      _acc_0 = r1;
      WL_AGAIN(FID_ARRAY_TO_LIST_GO_1);
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_ARRAY_TO_LIST_GO_1_K52)
  {
    WL_POPN(1);
    Term _h_3 = STK(0);
    Term _h_2 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_ARRAY_TO_LIST_GO_1)) {
      u64 _t_1 = task_node(e, FID_ARRAY_TO_LIST_GO_1, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _h_3;
      e.mem[_t_1 + 1] = _h_2;
      return term_tsk(FID_ARRAY_TO_LIST_GO_1, _t_1);
    }
    r0 = _h_3;
    r1 = _h_2;
    WL_JMP(FID_ARRAY_TO_LIST_GO_1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_ARRAY_TO_LIST_GO_0)
  {
    Term _a_0 = r0;
    Term _acc_0 = r1;
    WL_OPEN
    WL_SPIN
    if (blk_cls(_a_0) == 0) {
      u32 _c_0 = blk_read(e.mem, 0, blk_loc(e.mem, _a_0), 0 + 0);
      blk_free(e, _a_0);
      u64 _nd_0 = heap_alloc(e, cls_fit(2));
      e.mem[_nd_0 + 0] = rfc_seal(e, _c_0);
      e.mem[_nd_0 + 1] = rfc_seal(e, _acc_0);
      r0 = term_ctr(CID_CON, _nd_0);
      WL_RETN(1);
    } else {
      Term _h_0 = blk_half(e, _a_0, 0);
      Term _h_1 = blk_half(e, _a_0, 1);
      if (seq) {
        WL_ROOM(2);
        STK(0) = _h_0;
        STK(1) = FID_ARRAY_TO_LIST_GO_0_K54;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_ARRAY_TO_LIST_GO_0_K54, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _h_0;
        WL_CONT = term_tsk(FID_ARRAY_TO_LIST_GO_0_K54, _t_0);
        WL_IDX = 1;
      }
      r0 = _h_1;
      r1 = _acc_0;
      _a_0 = r0;
      _acc_0 = r1;
      WL_AGAIN(FID_ARRAY_TO_LIST_GO_0);
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_ARRAY_TO_LIST_GO_0_K54)
  {
    WL_POPN(1);
    Term _h_3 = STK(0);
    Term _h_2 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_ARRAY_TO_LIST_GO_0)) {
      u64 _t_1 = task_node(e, FID_ARRAY_TO_LIST_GO_0, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _h_3;
      e.mem[_t_1 + 1] = _h_2;
      return term_tsk(FID_ARRAY_TO_LIST_GO_0, _t_1);
    }
    r0 = _h_3;
    r1 = _h_2;
    WL_JMP(FID_ARRAY_TO_LIST_GO_0);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_PUT_U)
  {
    Term _ns_0 = r0;
    Term _xs_0 = r1;
    Term _a_0 = r2;
    u32 _i_0 = r3;
    WL_OPEN
    if (term_aux(_ns_0) == CID_NIL) {
      if (term_aux(_xs_0) == CID_NIL) {
        r0 = _a_0;
        WL_RETN(1);
      } else {
        Term _fb_0[2];
        u64 _sp_0 = ctr_take(e, _xs_0, 2, _fb_0);
        Term _f_0 = _fb_0[0];
        Term _f_1 = _fb_0[1];
        term_sink(e, _f_0);
        term_sink(e, _f_1);
        spare_free(e, cls_fit(2), _sp_0);
        r0 = _a_0;
        WL_RETN(1);
      }
    } else {
      Term _fb_1[2];
      u64 _sp_1 = ctr_take(e, _ns_0, 2, _fb_1);
      Term _f_2 = _fb_1[0];
      Term _f_3 = _fb_1[1];
      if (term_aux(_xs_0) == CID_NIL) {
        term_sink(e, _f_3);
        spare_free(e, cls_fit(2), _sp_1);
        r0 = _a_0;
        WL_RETN(1);
      } else {
        Term _fb_2[2];
        u64 _sp_2 = ctr_take(e, _xs_0, 2, _fb_2);
        Term _f_4 = _fb_2[0];
        Term _f_5 = _fb_2[1];
        spare_free(e, cls_fit(2), _sp_2);
        spare_free(e, cls_fit(2), _sp_1);
        if (seq) {
          WL_ROOM(5);
          STK(0) = _f_3;
          STK(1) = _f_5;
          STK(2) = _a_0;
          STK(3) = _i_0;
          STK(4) = FID_PUT_U_K56;
          WL_PUSHN(5);
        } else {
          u64 _t_0 = task_node(e, FID_PUT_U_K56, WL_CONT, WL_IDX, 1);
          e.mem[_t_0 + 0] = _f_3;
          e.mem[_t_0 + 1] = _f_5;
          e.mem[_t_0 + 2] = _a_0;
          e.mem[_t_0 + 3] = _i_0;
          WL_CONT = term_tsk(FID_PUT_U_K56, _t_0);
          WL_IDX = 4;
        }
        if (!DEVICE && !seq && fid_nofk(FID_PARSE)) {
          u64 _t_1 = task_node(e, FID_PARSE, WL_CONT, WL_IDX, 0);
          e.mem[_t_1 + 0] = _f_4;
          return term_tsk(FID_PARSE, _t_1);
        }
        r0 = _f_4;
        WL_JMP(FID_PARSE);
      }
    }
  }}
#endif

#if !DEVICE
  WL_CASE(FID_PUT_U_K56)
  {
    WL_POPN(4);
    Term _f_6 = STK(0);
    Term _f_7 = STK(1);
    Term _a_1 = STK(2);
    u32 _i_1 = STK(3);
    u32 _h_0 = r0;
    WL_OPEN
    Term _at_0 = blk_loc(e.mem, _a_1);
    Term _at_1 = blk_at(_a_1, _i_1, 0);
    u32 _c_0 = blk_read(e.mem, 0, _at_0, _at_1 + 0);
    blk_write(e.mem, 0, _at_0, _at_1 + 0, _h_0);
    if (!DEVICE && !seq && fid_nofk(FID_PUT_U)) {
      u64 _t_2 = task_node(e, FID_PUT_U, WL_CONT, WL_IDX, 0);
      e.mem[_t_2 + 0] = _f_6;
      e.mem[_t_2 + 1] = _f_7;
      e.mem[_t_2 + 2] = _a_1;
      e.mem[_t_2 + 3] = U32_BIN(_i_1, +, 1);
      return term_tsk(FID_PUT_U, _t_2);
    }
    r0 = _f_6;
    r1 = _f_7;
    r2 = _a_1;
    r3 = U32_BIN(_i_1, +, 1);
    WL_JMP(FID_PUT_U);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_LIST_REPLICATE)
  {
    Term _n_0 = r0;
    Term _x_0 = r1;
    WL_OPEN
    WL_SPIN
    if (_n_0 == 0) {
      term_sink(e, _x_0);
      r0 = term_pak(CID_NIL, 0);
      WL_RETN(1);
    } else {
      Term _p_0 = (_n_0 - 1);
      _x_0 = term_keep(e, _x_0, 1);
      if (seq) {
        WL_ROOM(2);
        STK(0) = _x_0;
        STK(1) = FID_LIST_REPLICATE_K59;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_LIST_REPLICATE_K59, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _x_0;
        WL_CONT = term_tsk(FID_LIST_REPLICATE_K59, _t_0);
        WL_IDX = 1;
      }
      r0 = _p_0;
      r1 = _x_0;
      _n_0 = r0;
      _x_0 = r1;
      WL_AGAIN(FID_LIST_REPLICATE);
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_LIST_REPLICATE_K59)
  {
    WL_POPN(1);
    Term _x_1 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    u64 _nd_0 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_0 + 0] = rfc_seal(e, _x_1);
    e.mem[_nd_0 + 1] = rfc_seal(e, _h_0);
    r0 = term_ctr(CID_CON, _nd_0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_PUT)
  {
    Term _ns_0 = r0;
    Term _xs_0 = r1;
    Term _a_0 = r2;
    u32 _i_0 = r3;
    WL_OPEN
    if (term_aux(_ns_0) == CID_NIL) {
      if (term_aux(_xs_0) == CID_NIL) {
        r0 = _a_0;
        WL_RETN(1);
      } else {
        Term _fb_0[2];
        u64 _sp_0 = ctr_take(e, _xs_0, 2, _fb_0);
        Term _f_0 = _fb_0[0];
        Term _f_1 = _fb_0[1];
        term_sink(e, _f_0);
        term_sink(e, _f_1);
        spare_free(e, cls_fit(2), _sp_0);
        r0 = _a_0;
        WL_RETN(1);
      }
    } else {
      Term _fb_1[2];
      u64 _sp_1 = ctr_take(e, _ns_0, 2, _fb_1);
      Term _f_2 = _fb_1[0];
      Term _f_3 = _fb_1[1];
      if (term_aux(_xs_0) == CID_NIL) {
        term_sink(e, _f_3);
        spare_free(e, cls_fit(2), _sp_1);
        r0 = _a_0;
        WL_RETN(1);
      } else {
        Term _fb_2[2];
        u64 _sp_2 = ctr_take(e, _xs_0, 2, _fb_2);
        Term _f_4 = _fb_2[0];
        Term _f_5 = _fb_2[1];
        spare_free(e, cls_fit(2), _sp_2);
        spare_free(e, cls_fit(2), _sp_1);
        if (seq) {
          WL_ROOM(5);
          STK(0) = _f_3;
          STK(1) = _f_5;
          STK(2) = _a_0;
          STK(3) = _i_0;
          STK(4) = FID_PUT_K61;
          WL_PUSHN(5);
        } else {
          u64 _t_0 = task_node(e, FID_PUT_K61, WL_CONT, WL_IDX, 1);
          e.mem[_t_0 + 0] = _f_3;
          e.mem[_t_0 + 1] = _f_5;
          e.mem[_t_0 + 2] = _a_0;
          e.mem[_t_0 + 3] = _i_0;
          WL_CONT = term_tsk(FID_PUT_K61, _t_0);
          WL_IDX = 4;
        }
        if (!DEVICE && !seq && fid_nofk(FID_PARSE)) {
          u64 _t_1 = task_node(e, FID_PARSE, WL_CONT, WL_IDX, 0);
          e.mem[_t_1 + 0] = _f_4;
          return term_tsk(FID_PARSE, _t_1);
        }
        r0 = _f_4;
        WL_JMP(FID_PARSE);
      }
    }
  }}
#endif

#if !DEVICE
  WL_CASE(FID_PUT_K61)
  {
    WL_POPN(4);
    Term _f_6 = STK(0);
    Term _f_7 = STK(1);
    Term _a_1 = STK(2);
    u32 _i_1 = STK(3);
    u32 _h_0 = r0;
    WL_OPEN
    u32 _v_0 = 0;
    u32 _v_1 = 0;
    Term _o_0[1];
    if (spin_9(e, _o_0, _h_0) == 0) {
      return 0;
    }
    _v_1 = _o_0[0];
    _v_0 = _v_1;
    Term _at_0 = blk_loc(e.mem, _a_1);
    Term _at_1 = blk_at(_a_1, _i_1, 0);
    u32 _c_0 = blk_read(e.mem, 0, _at_0, _at_1 + 0);
    blk_write(e.mem, 0, _at_0, _at_1 + 0, _v_0);
    if (!DEVICE && !seq && fid_nofk(FID_PUT)) {
      u64 _t_2 = task_node(e, FID_PUT, WL_CONT, WL_IDX, 0);
      e.mem[_t_2 + 0] = _f_6;
      e.mem[_t_2 + 1] = _f_7;
      e.mem[_t_2 + 2] = _a_1;
      e.mem[_t_2 + 3] = U32_BIN(_i_1, +, 1);
      return term_tsk(FID_PUT, _t_2);
    }
    r0 = _f_6;
    r1 = _f_7;
    r2 = _a_1;
    r3 = U32_BIN(_i_1, +, 1);
    WL_JMP(FID_PUT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_BATCH)
  {
    Term _xs_0 = r0;
    Term _li_0 = r1;
    Term _ls_0 = r2;
    Term _ws_0 = r3;
    Term _r_0 = r4;
    u32 _acc_0 = r5;
    WL_OPEN
    if (term_aux(_xs_0) == CID_NIL) {
      term_sink(e, _ls_0);
      term_sink(e, _ws_0);
      Term _v_0 = 0;
      Term _o_0[1];
      if (spin_10(e, _o_0, _acc_0, _r_0) == 0) {
        return 0;
      }
      _v_0 = _o_0[0];
      r0 = _v_0;
      WL_RETN(1);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _xs_0, 2, _fb_0);
      Term _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      if (term_aux(_f_1) == CID_NIL) {
        term_sink(e, _ls_0);
        term_sink(e, _ws_0);
        Term _v_2 = 0;
        Term _o_1[1];
        if (spin_10(e, _o_1, _acc_0, _r_0) == 0) {
          return 0;
        }
        _v_2 = _o_1[0];
        spare_free(e, cls_fit(2), _sp_0);
        r0 = _v_2;
        WL_RETN(1);
      } else {
        Term _fb_1[2];
        u64 _sp_1 = ctr_take(e, _f_1, 2, _fb_1);
        Term _f_2 = _fb_1[0];
        Term _f_3 = _fb_1[1];
        if (term_aux(_f_3) == CID_NIL) {
          term_sink(e, _ls_0);
          term_sink(e, _ws_0);
          Term _v_3 = 0;
          Term _o_2[1];
          if (spin_10(e, _o_2, _acc_0, _r_0) == 0) {
            return 0;
          }
          _v_3 = _o_2[0];
          spare_free(e, cls_fit(2), _sp_1);
          spare_free(e, cls_fit(2), _sp_0);
          r0 = _v_3;
          WL_RETN(1);
        } else {
          Term _fb_2[2];
          u64 _sp_2 = ctr_take(e, _f_3, 2, _fb_2);
          Term _f_4 = _fb_2[0];
          Term _f_5 = _fb_2[1];
          if (term_aux(_f_5) == CID_NIL) {
            term_sink(e, _ls_0);
            term_sink(e, _ws_0);
            Term _v_4 = 0;
            Term _o_3[1];
            if (spin_10(e, _o_3, _acc_0, _r_0) == 0) {
              return 0;
            }
            _v_4 = _o_3[0];
            spare_free(e, cls_fit(2), _sp_2);
            spare_free(e, cls_fit(2), _sp_1);
            spare_free(e, cls_fit(2), _sp_0);
            r0 = _v_4;
            WL_RETN(1);
          } else {
            Term _fb_3[2];
            u64 _sp_3 = ctr_take(e, _f_5, 2, _fb_3);
            Term _f_6 = _fb_3[0];
            Term _f_7 = _fb_3[1];
            if (term_aux(_ls_0) == CID_NIL) {
              term_sink(e, _f_7);
              term_sink(e, _ws_0);
              Term _v_5 = 0;
              Term _o_4[1];
              if (spin_10(e, _o_4, _acc_0, _r_0) == 0) {
                return 0;
              }
              _v_5 = _o_4[0];
              spare_free(e, cls_fit(2), _sp_3);
              spare_free(e, cls_fit(2), _sp_2);
              spare_free(e, cls_fit(2), _sp_1);
              spare_free(e, cls_fit(2), _sp_0);
              r0 = _v_5;
              WL_RETN(1);
            } else {
              Term _fb_4[2];
              u64 _sp_4 = ctr_take(e, _ls_0, 2, _fb_4);
              Term _f_8 = _fb_4[0];
              Term _f_9 = _fb_4[1];
              term_sink(e, _r_0);
              u64 _nd_1 = _sp_0 >= HEAP_OFF ? _sp_0 : heap_alloc(e, cls_fit(2));
              e.mem[_nd_1 + 0] = rfc_seal(e, _f_6);
              e.mem[_nd_1 + 1] = rfc_seal(e, term_pak(CID_NIL, 0));
              u64 _nd_2 = _sp_1 >= HEAP_OFF ? _sp_1 : heap_alloc(e, cls_fit(2));
              e.mem[_nd_2 + 0] = rfc_seal(e, _f_4);
              e.mem[_nd_2 + 1] = rfc_seal(e, term_ctr(CID_CON, _nd_1));
              u64 _nd_3 = _sp_2 >= HEAP_OFF ? _sp_2 : heap_alloc(e, cls_fit(2));
              e.mem[_nd_3 + 0] = rfc_seal(e, _f_2);
              e.mem[_nd_3 + 1] = rfc_seal(e, term_ctr(CID_CON, _nd_2));
              u64 _nd_4 = _sp_3 >= HEAP_OFF ? _sp_3 : heap_alloc(e, cls_fit(2));
              e.mem[_nd_4 + 0] = rfc_seal(e, _f_0);
              e.mem[_nd_4 + 1] = rfc_seal(e, term_ctr(CID_CON, _nd_3));
              _f_9 = term_keep(e, _f_9, 1);
              u64 _nd_5 = _sp_4 >= HEAP_OFF ? _sp_4 : heap_alloc(e, cls_fit(2));
              e.mem[_nd_5 + 0] = rfc_seal(e, _f_8);
              e.mem[_nd_5 + 1] = rfc_seal(e, _f_9);
              _ws_0 = term_keep(e, _ws_0, 1);
              if (seq) {
                WL_ROOM(6);
                STK(0) = _f_7;
                STK(1) = _li_0;
                STK(2) = _f_9;
                STK(3) = _ws_0;
                STK(4) = _acc_0;
                STK(5) = FID_BATCH_K63;
                WL_PUSHN(6);
              } else {
                u64 _t_0 = task_node(e, FID_BATCH_K63, WL_CONT, WL_IDX, 1);
                e.mem[_t_0 + 0] = _f_7;
                e.mem[_t_0 + 1] = _li_0;
                e.mem[_t_0 + 2] = _f_9;
                e.mem[_t_0 + 3] = _ws_0;
                e.mem[_t_0 + 4] = _acc_0;
                WL_CONT = term_tsk(FID_BATCH_K63, _t_0);
                WL_IDX = 5;
              }
              if (!DEVICE && !seq && fid_nofk(FID_SAMPLE)) {
                u64 _t_1 = task_node(e, FID_SAMPLE, WL_CONT, WL_IDX, 0);
                e.mem[_t_1 + 0] = term_ctr(CID_CON, _nd_4);
                e.mem[_t_1 + 1] = term_ctr(CID_CON, _nd_5);
                e.mem[_t_1 + 2] = _ws_0;
                e.mem[_t_1 + 3] = _li_0;
                return term_tsk(FID_SAMPLE, _t_1);
              }
              r0 = term_ctr(CID_CON, _nd_4);
              r1 = term_ctr(CID_CON, _nd_5);
              r2 = _ws_0;
              r3 = _li_0;
              WL_JMP(FID_SAMPLE);
            }
          }
        }
      }
    }
  }}
#endif

#if !DEVICE
  WL_CASE(FID_BATCH_K63)
  {
    WL_POPN(5);
    Term _f_10 = STK(0);
    Term _li_1 = STK(1);
    Term _f_11 = STK(2);
    Term _ws_1 = STK(3);
    u32 _acc_2 = STK(4);
    Term _s_0 = r0;
    WL_OPEN
    u32 _v_6 = 0;
    _s_0 = term_keep(e, _s_0, 1);
    u32 _v_7 = 0;
    Term _o_5[1];
    if (spin_2(e, _o_5, 0, _s_0) == 0) {
      return 0;
    }
    _v_7 = _o_5[0];
    _v_6 = _v_7;
    if (!DEVICE && !seq && fid_nofk(FID_BATCH)) {
      u64 _t_2 = task_node(e, FID_BATCH, WL_CONT, WL_IDX, 0);
      e.mem[_t_2 + 0] = _f_10;
      e.mem[_t_2 + 1] = nat_chk(e, _li_1 + 1ull);
      e.mem[_t_2 + 2] = _f_11;
      e.mem[_t_2 + 3] = _ws_1;
      e.mem[_t_2 + 4] = _s_0;
      e.mem[_t_2 + 5] = f32_rewrap(f32_unbox(_acc_2) + f32_unbox(_v_6));
      return term_tsk(FID_BATCH, _t_2);
    }
    r0 = _f_10;
    r1 = nat_chk(e, _li_1 + 1ull);
    r2 = _f_11;
    r3 = _ws_1;
    r4 = _s_0;
    r5 = f32_rewrap(f32_unbox(_acc_2) + f32_unbox(_v_6));
    WL_JMP(FID_BATCH);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_STRING_SPLIT)
  {
    Term _s_0 = r0;
    u32 _sep_0 = r1;
    WL_OPEN
    WL_SPIN
    if (term_aux(_s_0) == CID_SNIL) {
      r0 = term_ctr(CID_CON, STAT_OFF + 2);
      WL_RETN(1);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _s_0, 2, _fb_0);
      u32 _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      spare_free(e, cls_fit(2), _sp_0);
      if (seq) {
        WL_ROOM(3);
        STK(0) = _f_0;
        STK(1) = _sep_0;
        STK(2) = FID_STRING_SPLIT_K65;
        WL_PUSHN(3);
      } else {
        u64 _t_0 = task_node(e, FID_STRING_SPLIT_K65, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _f_0;
        e.mem[_t_0 + 1] = _sep_0;
        WL_CONT = term_tsk(FID_STRING_SPLIT_K65, _t_0);
        WL_IDX = 2;
      }
      r0 = _f_1;
      r1 = _sep_0;
      _s_0 = r0;
      _sep_0 = r1;
      WL_AGAIN(FID_STRING_SPLIT);
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_STRING_SPLIT_K65)
  {
    WL_POPN(2);
    u32 _f_2 = STK(0);
    u32 _sep_1 = STK(1);
    Term _h_0 = r0;
    WL_OPEN
    u32 _v_0 = 0;
    u32 _v_1 = 0;
    Term _o_0[1];
    if (spin_11(e, _o_0, _f_2, _sep_1) == 0) {
      return 0;
    }
    _v_1 = _o_0[0];
    _v_0 = _v_1;
    Term _v_3 = 0;
    Term _o_2[1];
    if (spin_12(e, _o_2, _f_2, _h_0, _v_0) == 0) {
      return 0;
    }
    _v_3 = _o_2[0];
    r0 = _v_3;
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SHOW_U)
  {
    Term _xs_0 = r0;
    WL_OPEN
    if (term_aux(_xs_0) == CID_NIL) {
      r0 = term_pak(CID_SNIL, 0);
      WL_RETN(1);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _xs_0, 2, _fb_0);
      Term _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      spare_free(e, cls_fit(2), _sp_0);
      if (seq) {
        WL_ROOM(2);
        STK(0) = _f_1;
        STK(1) = FID_SHOW_U_K67;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_SHOW_U_K67, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _f_1;
        WL_CONT = term_tsk(FID_SHOW_U_K67, _t_0);
        WL_IDX = 1;
      }
      if (!DEVICE && !seq && fid_nofk(FID_U32_SHOW)) {
        u64 _t_1 = task_node(e, FID_U32_SHOW, WL_CONT, WL_IDX, 0);
        e.mem[_t_1 + 0] = _f_0;
        return term_tsk(FID_U32_SHOW, _t_1);
      }
      r0 = _f_0;
      WL_JMP(FID_U32_SHOW);
    }
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SHOW_U_K67)
  {
    WL_POPN(1);
    Term _f_2 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _h_0;
      STK(1) = FID_SHOW_U_K68;
      WL_PUSHN(2);
    } else {
      u64 _t_2 = task_node(e, FID_SHOW_U_K68, WL_CONT, WL_IDX, 1);
      e.mem[_t_2 + 0] = _h_0;
      WL_CONT = term_tsk(FID_SHOW_U_K68, _t_2);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_SHOW_U)) {
      u64 _t_3 = task_node(e, FID_SHOW_U, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = _f_2;
      return term_tsk(FID_SHOW_U, _t_3);
    }
    r0 = _f_2;
    WL_JMP(FID_SHOW_U);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SHOW_U_K68)
  {
    WL_POPN(1);
    Term _h_2 = STK(0);
    Term _h_1 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _h_2;
      STK(1) = FID_SHOW_U_K69;
      WL_PUSHN(2);
    } else {
      u64 _t_4 = task_node(e, FID_SHOW_U_K69, WL_CONT, WL_IDX, 1);
      e.mem[_t_4 + 0] = _h_2;
      WL_CONT = term_tsk(FID_SHOW_U_K69, _t_4);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_5 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_5 + 0] = term_ctr(CID_SCON, STAT_OFF + 4);
      e.mem[_t_5 + 1] = _h_1;
      return term_tsk(FID_STRING_APPEND, _t_5);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 4);
    r1 = _h_1;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SHOW_U_K69)
  {
    WL_POPN(1);
    Term _h_4 = STK(0);
    Term _h_3 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_6 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_6 + 0] = _h_4;
      e.mem[_t_6 + 1] = _h_3;
      return term_tsk(FID_STRING_APPEND, _t_6);
    }
    r0 = _h_4;
    r1 = _h_3;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SHOW_F)
  {
    Term _xs_0 = r0;
    WL_OPEN
    if (term_aux(_xs_0) == CID_NIL) {
      r0 = term_pak(CID_SNIL, 0);
      WL_RETN(1);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _xs_0, 2, _fb_0);
      Term _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      spare_free(e, cls_fit(2), _sp_0);
      if (seq) {
        WL_ROOM(2);
        STK(0) = _f_1;
        STK(1) = FID_SHOW_F_K71;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_SHOW_F_K71, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _f_1;
        WL_CONT = term_tsk(FID_SHOW_F_K71, _t_0);
        WL_IDX = 1;
      }
      if (!DEVICE && !seq && fid_nofk(FID_U32_SHOW)) {
        u64 _t_1 = task_node(e, FID_U32_SHOW, WL_CONT, WL_IDX, 0);
        e.mem[_t_1 + 0] = _f_0;
        return term_tsk(FID_U32_SHOW, _t_1);
      }
      r0 = _f_0;
      WL_JMP(FID_U32_SHOW);
    }
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SHOW_F_K71)
  {
    WL_POPN(1);
    Term _f_2 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _h_0;
      STK(1) = FID_SHOW_F_K72;
      WL_PUSHN(2);
    } else {
      u64 _t_2 = task_node(e, FID_SHOW_F_K72, WL_CONT, WL_IDX, 1);
      e.mem[_t_2 + 0] = _h_0;
      WL_CONT = term_tsk(FID_SHOW_F_K72, _t_2);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_SHOW_F)) {
      u64 _t_3 = task_node(e, FID_SHOW_F, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = _f_2;
      return term_tsk(FID_SHOW_F, _t_3);
    }
    r0 = _f_2;
    WL_JMP(FID_SHOW_F);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SHOW_F_K72)
  {
    WL_POPN(1);
    Term _h_2 = STK(0);
    Term _h_1 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _h_2;
      STK(1) = FID_SHOW_F_K73;
      WL_PUSHN(2);
    } else {
      u64 _t_4 = task_node(e, FID_SHOW_F_K73, WL_CONT, WL_IDX, 1);
      e.mem[_t_4 + 0] = _h_2;
      WL_CONT = term_tsk(FID_SHOW_F_K73, _t_4);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_5 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_5 + 0] = term_ctr(CID_SCON, STAT_OFF + 4);
      e.mem[_t_5 + 1] = _h_1;
      return term_tsk(FID_STRING_APPEND, _t_5);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 4);
    r1 = _h_1;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SHOW_F_K73)
  {
    WL_POPN(1);
    Term _h_4 = STK(0);
    Term _h_3 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_6 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_6 + 0] = _h_4;
      e.mem[_t_6 + 1] = _h_3;
      return term_tsk(FID_STRING_APPEND, _t_6);
    }
    r0 = _h_4;
    r1 = _h_3;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_BITS_AT)
  {
    Term _k_0 = r0;
    Term _xs_0 = r1;
    WL_OPEN
    u32 _v_0 = 0;
    u32 _v_1 = 0;
    Term _o_0[1];
    if (spin_2(e, _o_0, _k_0, _xs_0) == 0) {
      return 0;
    }
    _v_1 = _o_0[0];
    _v_0 = _v_1;
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_BITS_AT_K75;
      WL_PUSHN(1);
    } else {
      u64 _t_0 = task_node(e, FID_BITS_AT_K75, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_BITS_AT_K75, _t_0);
      WL_IDX = 0;
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
  WL_CASE(FID_BITS_AT_K75)
  {
    Term _h_0 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_2 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_2 + 0] = term_ctr(CID_SCON, STAT_OFF + 4);
      e.mem[_t_2 + 1] = _h_0;
      return term_tsk(FID_STRING_APPEND, _t_2);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 4);
    r1 = _h_0;
    WL_JMP(FID_STRING_APPEND);
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
        STK(1) = FID_STRING_APPEND_K77;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_STRING_APPEND_K77, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _f_0;
        WL_CONT = term_tsk(FID_STRING_APPEND_K77, _t_0);
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
  WL_CASE(FID_STRING_APPEND_K77)
  {
    WL_POPN(1);
    u32 _f_2 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    u64 _nd_0 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_0 + 0] = rfc_seal(e, _f_2);
    e.mem[_nd_0 + 1] = rfc_seal(e, _h_0);
    r0 = term_ctr(CID_SCON, _nd_0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_ARRAY_TO_LIST_1)
  {
    Term _a_0 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_ARRAY_TO_LIST_GO_1)) {
      u64 _t_0 = task_node(e, FID_ARRAY_TO_LIST_GO_1, WL_CONT, WL_IDX, 0);
      e.mem[_t_0 + 0] = _a_0;
      e.mem[_t_0 + 1] = term_pak(CID_NIL, 0);
      return term_tsk(FID_ARRAY_TO_LIST_GO_1, _t_0);
    }
    r0 = _a_0;
    r1 = term_pak(CID_NIL, 0);
    WL_JMP(FID_ARRAY_TO_LIST_GO_1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SHARE_U)
  {
    Term _xs_0 = r0;
    WL_OPEN
    WL_SPIN
    if (term_aux(_xs_0) == CID_NIL) {
      r0 = term_pak(CID_NIL, 0);
      WL_RETN(1);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _xs_0, 2, _fb_0);
      Term _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      spare_free(e, cls_fit(2), _sp_0);
      if (seq) {
        WL_ROOM(2);
        STK(0) = _f_0;
        STK(1) = FID_SHARE_U_K81;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_SHARE_U_K81, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _f_0;
        WL_CONT = term_tsk(FID_SHARE_U_K81, _t_0);
        WL_IDX = 1;
      }
      r0 = _f_1;
      _xs_0 = r0;
      WL_AGAIN(FID_SHARE_U);
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SHARE_U_K81)
  {
    WL_POPN(1);
    u32 _f_2 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    u64 _nd_0 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_0 + 0] = rfc_seal(e, _f_2);
    e.mem[_nd_0 + 1] = rfc_seal(e, _h_0);
    r0 = term_ctr(CID_CON, _nd_0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_ARRAY_TO_LIST_0)
  {
    Term _a_0 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_ARRAY_TO_LIST_GO_0)) {
      u64 _t_0 = task_node(e, FID_ARRAY_TO_LIST_GO_0, WL_CONT, WL_IDX, 0);
      e.mem[_t_0 + 0] = _a_0;
      e.mem[_t_0 + 1] = term_pak(CID_NIL, 0);
      return term_tsk(FID_ARRAY_TO_LIST_GO_0, _t_0);
    }
    r0 = _a_0;
    r1 = term_pak(CID_NIL, 0);
    WL_JMP(FID_ARRAY_TO_LIST_GO_0);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SHARE_F)
  {
    Term _xs_0 = r0;
    WL_OPEN
    WL_SPIN
    if (term_aux(_xs_0) == CID_NIL) {
      r0 = term_pak(CID_NIL, 0);
      WL_RETN(1);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _xs_0, 2, _fb_0);
      Term _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      spare_free(e, cls_fit(2), _sp_0);
      if (seq) {
        WL_ROOM(2);
        STK(0) = _f_0;
        STK(1) = FID_SHARE_F_K84;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_SHARE_F_K84, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _f_0;
        WL_CONT = term_tsk(FID_SHARE_F_K84, _t_0);
        WL_IDX = 1;
      }
      r0 = _f_1;
      _xs_0 = r0;
      WL_AGAIN(FID_SHARE_F);
    }
    WL_SPUN
  }}
#endif

#if !DEVICE
  WL_CASE(FID_SHARE_F_K84)
  {
    WL_POPN(1);
    u32 _f_2 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    u64 _nd_0 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_0 + 0] = rfc_seal(e, _f_2);
    e.mem[_nd_0 + 1] = rfc_seal(e, _h_0);
    r0 = term_ctr(CID_CON, _nd_0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_WS_OF)
  {
    Term _fs_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _fs_0;
      STK(1) = FID_WS_OF_K86;
      WL_PUSHN(2);
    } else {
      u64 _t_0 = task_node(e, FID_WS_OF_K86, WL_CONT, WL_IDX, 1);
      e.mem[_t_0 + 0] = _fs_0;
      WL_CONT = term_tsk(FID_WS_OF_K86, _t_0);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_LIST_REPLICATE)) {
      u64 _t_1 = task_node(e, FID_LIST_REPLICATE, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = 32ull;
      e.mem[_t_1 + 1] = 0;
      return term_tsk(FID_LIST_REPLICATE, _t_1);
    }
    r0 = 32ull;
    r1 = 0;
    WL_JMP(FID_LIST_REPLICATE);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_WS_OF_K86)
  {
    WL_POPN(1);
    Term _fs_1 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    Term _v_0 = 0;
    Term _v_1 = 0;
    Term _o_0[1];
    if (spin_13(e, _o_0, 10ull, _fs_1) == 0) {
      return 0;
    }
    _v_1 = _o_0[0];
    _v_0 = _v_1;
    Term _fv_0[1];
    _fv_0[0] = 0ull;
    if (!DEVICE && !seq && fid_nofk(FID_PUT)) {
      u64 _t_2 = task_node(e, FID_PUT, WL_CONT, WL_IDX, 0);
      e.mem[_t_2 + 0] = _h_0;
      e.mem[_t_2 + 1] = _v_0;
      e.mem[_t_2 + 2] = blk_new(e, 0, 5ull, 0, 1, _fv_0);
      e.mem[_t_2 + 3] = 0ull;
      return term_tsk(FID_PUT, _t_2);
    }
    r0 = _h_0;
    r1 = _v_0;
    r2 = blk_new(e, 0, 5ull, 0, 1, _fv_0);
    r3 = 0ull;
    WL_JMP(FID_PUT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_LABS_OF)
  {
    Term _fs_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _fs_0;
      STK(1) = FID_LABS_OF_K88;
      WL_PUSHN(2);
    } else {
      u64 _t_0 = task_node(e, FID_LABS_OF_K88, WL_CONT, WL_IDX, 1);
      e.mem[_t_0 + 0] = _fs_0;
      WL_CONT = term_tsk(FID_LABS_OF_K88, _t_0);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_LIST_REPLICATE)) {
      u64 _t_1 = task_node(e, FID_LIST_REPLICATE, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = 2ull;
      e.mem[_t_1 + 1] = 0;
      return term_tsk(FID_LIST_REPLICATE, _t_1);
    }
    r0 = 2ull;
    r1 = 0;
    WL_JMP(FID_LIST_REPLICATE);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_LABS_OF_K88)
  {
    WL_POPN(1);
    Term _fs_1 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    Term _v_0 = 0;
    Term _v_1 = 0;
    Term _o_0[1];
    if (spin_13(e, _o_0, 8ull, _fs_1) == 0) {
      return 0;
    }
    _v_1 = _o_0[0];
    _v_0 = _v_1;
    Term _fv_0[1];
    _fv_0[0] = 0ull;
    if (!DEVICE && !seq && fid_nofk(FID_PUT_U)) {
      u64 _t_2 = task_node(e, FID_PUT_U, WL_CONT, WL_IDX, 0);
      e.mem[_t_2 + 0] = _h_0;
      e.mem[_t_2 + 1] = _v_0;
      e.mem[_t_2 + 2] = blk_new(e, 0, 1ull, 0, 1, _fv_0);
      e.mem[_t_2 + 3] = 0ull;
      return term_tsk(FID_PUT_U, _t_2);
    }
    r0 = _h_0;
    r1 = _v_0;
    r2 = blk_new(e, 0, 1ull, 0, 1, _fv_0);
    r3 = 0ull;
    WL_JMP(FID_PUT_U);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_IMGS_OF)
  {
    Term _fs_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _fs_0;
      STK(1) = FID_IMGS_OF_K90;
      WL_PUSHN(2);
    } else {
      u64 _t_0 = task_node(e, FID_IMGS_OF_K90, WL_CONT, WL_IDX, 1);
      e.mem[_t_0 + 0] = _fs_0;
      WL_CONT = term_tsk(FID_IMGS_OF_K90, _t_0);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_LIST_REPLICATE)) {
      u64 _t_1 = task_node(e, FID_LIST_REPLICATE, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = 8ull;
      e.mem[_t_1 + 1] = 0;
      return term_tsk(FID_LIST_REPLICATE, _t_1);
    }
    r0 = 8ull;
    r1 = 0;
    WL_JMP(FID_LIST_REPLICATE);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_IMGS_OF_K90)
  {
    WL_POPN(1);
    Term _fs_1 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    Term _v_0 = 0;
    Term _v_1 = 0;
    Term _o_0[1];
    if (spin_13(e, _o_0, 0, _fs_1) == 0) {
      return 0;
    }
    _v_1 = _o_0[0];
    _v_0 = _v_1;
    Term _fv_0[1];
    _fv_0[0] = 0ull;
    if (!DEVICE && !seq && fid_nofk(FID_PUT)) {
      u64 _t_2 = task_node(e, FID_PUT, WL_CONT, WL_IDX, 0);
      e.mem[_t_2 + 0] = _h_0;
      e.mem[_t_2 + 1] = _v_0;
      e.mem[_t_2 + 2] = blk_new(e, 0, 3ull, 0, 1, _fv_0);
      e.mem[_t_2 + 3] = 0ull;
      return term_tsk(FID_PUT, _t_2);
    }
    r0 = _h_0;
    r1 = _v_0;
    r2 = blk_new(e, 0, 3ull, 0, 1, _fv_0);
    r3 = 0ull;
    WL_JMP(FID_PUT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CORE_TRACE)
  {
    Term _images_0 = r0;
    Term _labels_0 = r1;
    Term _weights_0 = r2;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _labels_0;
      STK(1) = _weights_0;
      STK(2) = FID_CORE_TRACE_K92;
      WL_PUSHN(3);
    } else {
      u64 _t_0 = task_node(e, FID_CORE_TRACE_K92, WL_CONT, WL_IDX, 1);
      e.mem[_t_0 + 0] = _labels_0;
      e.mem[_t_0 + 1] = _weights_0;
      WL_CONT = term_tsk(FID_CORE_TRACE_K92, _t_0);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_ARRAY_TO_LIST_0)) {
      u64 _t_1 = task_node(e, FID_ARRAY_TO_LIST_0, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _images_0;
      return term_tsk(FID_ARRAY_TO_LIST_0, _t_1);
    }
    r0 = _images_0;
    WL_JMP(FID_ARRAY_TO_LIST_0);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CORE_TRACE_K92)
  {
    WL_POPN(2);
    Term _labels_1 = STK(0);
    Term _weights_1 = STK(1);
    Term _h_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _labels_1;
      STK(1) = _weights_1;
      STK(2) = FID_CORE_TRACE_K93;
      WL_PUSHN(3);
    } else {
      u64 _t_2 = task_node(e, FID_CORE_TRACE_K93, WL_CONT, WL_IDX, 1);
      e.mem[_t_2 + 0] = _labels_1;
      e.mem[_t_2 + 1] = _weights_1;
      WL_CONT = term_tsk(FID_CORE_TRACE_K93, _t_2);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_SHARE_F)) {
      u64 _t_3 = task_node(e, FID_SHARE_F, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = _h_0;
      return term_tsk(FID_SHARE_F, _t_3);
    }
    r0 = _h_0;
    WL_JMP(FID_SHARE_F);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CORE_TRACE_K93)
  {
    WL_POPN(2);
    Term _labels_2 = STK(0);
    Term _weights_2 = STK(1);
    Term _h_1 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _weights_2;
      STK(1) = _h_1;
      STK(2) = FID_CORE_TRACE_K94;
      WL_PUSHN(3);
    } else {
      u64 _t_4 = task_node(e, FID_CORE_TRACE_K94, WL_CONT, WL_IDX, 1);
      e.mem[_t_4 + 0] = _weights_2;
      e.mem[_t_4 + 1] = _h_1;
      WL_CONT = term_tsk(FID_CORE_TRACE_K94, _t_4);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_ARRAY_TO_LIST_1)) {
      u64 _t_5 = task_node(e, FID_ARRAY_TO_LIST_1, WL_CONT, WL_IDX, 0);
      e.mem[_t_5 + 0] = _labels_2;
      return term_tsk(FID_ARRAY_TO_LIST_1, _t_5);
    }
    r0 = _labels_2;
    WL_JMP(FID_ARRAY_TO_LIST_1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CORE_TRACE_K94)
  {
    WL_POPN(2);
    Term _weights_3 = STK(0);
    Term _h_3 = STK(1);
    Term _h_2 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _weights_3;
      STK(1) = _h_3;
      STK(2) = FID_CORE_TRACE_K95;
      WL_PUSHN(3);
    } else {
      u64 _t_6 = task_node(e, FID_CORE_TRACE_K95, WL_CONT, WL_IDX, 1);
      e.mem[_t_6 + 0] = _weights_3;
      e.mem[_t_6 + 1] = _h_3;
      WL_CONT = term_tsk(FID_CORE_TRACE_K95, _t_6);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_SHARE_U)) {
      u64 _t_7 = task_node(e, FID_SHARE_U, WL_CONT, WL_IDX, 0);
      e.mem[_t_7 + 0] = _h_2;
      return term_tsk(FID_SHARE_U, _t_7);
    }
    r0 = _h_2;
    WL_JMP(FID_SHARE_U);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CORE_TRACE_K95)
  {
    WL_POPN(2);
    Term _weights_4 = STK(0);
    Term _h_5 = STK(1);
    Term _h_4 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _h_5;
      STK(1) = _h_4;
      STK(2) = FID_CORE_TRACE_K96;
      WL_PUSHN(3);
    } else {
      u64 _t_8 = task_node(e, FID_CORE_TRACE_K96, WL_CONT, WL_IDX, 1);
      e.mem[_t_8 + 0] = _h_5;
      e.mem[_t_8 + 1] = _h_4;
      WL_CONT = term_tsk(FID_CORE_TRACE_K96, _t_8);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_ARRAY_TO_LIST_0)) {
      u64 _t_9 = task_node(e, FID_ARRAY_TO_LIST_0, WL_CONT, WL_IDX, 0);
      e.mem[_t_9 + 0] = _weights_4;
      return term_tsk(FID_ARRAY_TO_LIST_0, _t_9);
    }
    r0 = _weights_4;
    WL_JMP(FID_ARRAY_TO_LIST_0);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CORE_TRACE_K96)
  {
    WL_POPN(2);
    Term _h_7 = STK(0);
    Term _h_8 = STK(1);
    Term _h_6 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _h_7;
      STK(1) = _h_8;
      STK(2) = FID_CORE_TRACE_K97;
      WL_PUSHN(3);
    } else {
      u64 _t_10 = task_node(e, FID_CORE_TRACE_K97, WL_CONT, WL_IDX, 1);
      e.mem[_t_10 + 0] = _h_7;
      e.mem[_t_10 + 1] = _h_8;
      WL_CONT = term_tsk(FID_CORE_TRACE_K97, _t_10);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_SHARE_F)) {
      u64 _t_11 = task_node(e, FID_SHARE_F, WL_CONT, WL_IDX, 0);
      e.mem[_t_11 + 0] = _h_6;
      return term_tsk(FID_SHARE_F, _t_11);
    }
    r0 = _h_6;
    WL_JMP(FID_SHARE_F);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_CORE_TRACE_K97)
  {
    WL_POPN(2);
    Term _h_10 = STK(0);
    Term _h_11 = STK(1);
    Term _h_9 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_BATCH)) {
      u64 _t_12 = task_node(e, FID_BATCH, WL_CONT, WL_IDX, 0);
      e.mem[_t_12 + 0] = _h_10;
      e.mem[_t_12 + 1] = 0;
      e.mem[_t_12 + 2] = _h_11;
      e.mem[_t_12 + 3] = _h_9;
      e.mem[_t_12 + 4] = term_pak(CID_NIL, 0);
      e.mem[_t_12 + 5] = 0ull;
      return term_tsk(FID_BATCH, _t_12);
    }
    r0 = _h_10;
    r1 = 0;
    r2 = _h_11;
    r3 = _h_9;
    r4 = term_pak(CID_NIL, 0);
    r5 = 0ull;
    WL_JMP(FID_BATCH);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_PAYLOAD)
  {
    Term _args_0 = r0;
    WL_OPEN
    if (term_aux(_args_0) == CID_NIL) {
      r0 = term_pak(CID_NIL, 0);
      WL_RETN(1);
    } else {
      Term _fb_0[2];
      u64 _sp_0 = ctr_take(e, _args_0, 2, _fb_0);
      Term _f_0 = _fb_0[0];
      Term _f_1 = _fb_0[1];
      term_sink(e, _f_0);
      if (term_aux(_f_1) == CID_CON) {
        Term _fb_1[2];
        u64 _sp_1 = ctr_take(e, _f_1, 2, _fb_1);
        Term _f_2 = _fb_1[0];
        Term _f_3 = _fb_1[1];
        term_sink(e, _f_3);
        spare_free(e, cls_fit(2), _sp_1);
        spare_free(e, cls_fit(2), _sp_0);
        if (!DEVICE && !seq && fid_nofk(FID_STRING_SPLIT)) {
          u64 _t_0 = task_node(e, FID_STRING_SPLIT, WL_CONT, WL_IDX, 0);
          e.mem[_t_0 + 0] = _f_2;
          e.mem[_t_0 + 1] = 44ull;
          return term_tsk(FID_STRING_SPLIT, _t_0);
        }
        r0 = _f_2;
        r1 = 44ull;
        WL_JMP(FID_STRING_SPLIT);
      } else {
        spare_free(e, cls_fit(2), _sp_0);
        r0 = term_pak(CID_NIL, 0);
        WL_RETN(1);
      }
    }
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN)
  {
    Term _fs_0 = r0;
    WL_OPEN
    _fs_0 = term_keep(e, _fs_0, 1);
    if (seq) {
      WL_ROOM(2);
      STK(0) = _fs_0;
      STK(1) = FID_RUN_K100;
      WL_PUSHN(2);
    } else {
      u64 _t_0 = task_node(e, FID_RUN_K100, WL_CONT, WL_IDX, 1);
      e.mem[_t_0 + 0] = _fs_0;
      WL_CONT = term_tsk(FID_RUN_K100, _t_0);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_IMGS_OF)) {
      u64 _t_1 = task_node(e, FID_IMGS_OF, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _fs_0;
      return term_tsk(FID_IMGS_OF, _t_1);
    }
    r0 = _fs_0;
    WL_JMP(FID_IMGS_OF);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K100)
  {
    WL_POPN(1);
    Term _fs_1 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    _fs_1 = term_keep(e, _fs_1, 1);
    if (seq) {
      WL_ROOM(3);
      STK(0) = _fs_1;
      STK(1) = _h_0;
      STK(2) = FID_RUN_K101;
      WL_PUSHN(3);
    } else {
      u64 _t_2 = task_node(e, FID_RUN_K101, WL_CONT, WL_IDX, 1);
      e.mem[_t_2 + 0] = _fs_1;
      e.mem[_t_2 + 1] = _h_0;
      WL_CONT = term_tsk(FID_RUN_K101, _t_2);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_LABS_OF)) {
      u64 _t_3 = task_node(e, FID_LABS_OF, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = _fs_1;
      return term_tsk(FID_LABS_OF, _t_3);
    }
    r0 = _fs_1;
    WL_JMP(FID_LABS_OF);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K101)
  {
    WL_POPN(2);
    Term _fs_2 = STK(0);
    Term _h_2 = STK(1);
    Term _h_1 = r0;
    WL_OPEN
    _fs_2 = term_keep(e, _fs_2, 1);
    if (seq) {
      WL_ROOM(4);
      STK(0) = _fs_2;
      STK(1) = _h_2;
      STK(2) = _h_1;
      STK(3) = FID_RUN_K102;
      WL_PUSHN(4);
    } else {
      u64 _t_4 = task_node(e, FID_RUN_K102, WL_CONT, WL_IDX, 1);
      e.mem[_t_4 + 0] = _fs_2;
      e.mem[_t_4 + 1] = _h_2;
      e.mem[_t_4 + 2] = _h_1;
      WL_CONT = term_tsk(FID_RUN_K102, _t_4);
      WL_IDX = 3;
    }
    if (!DEVICE && !seq && fid_nofk(FID_WS_OF)) {
      u64 _t_5 = task_node(e, FID_WS_OF, WL_CONT, WL_IDX, 0);
      e.mem[_t_5 + 0] = _fs_2;
      return term_tsk(FID_WS_OF, _t_5);
    }
    r0 = _fs_2;
    WL_JMP(FID_WS_OF);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K102)
  {
    WL_POPN(3);
    Term _fs_3 = STK(0);
    Term _h_4 = STK(1);
    Term _h_5 = STK(2);
    Term _h_3 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _fs_3;
      STK(1) = FID_RUN_K103;
      WL_PUSHN(2);
    } else {
      u64 _t_6 = task_node(e, FID_RUN_K103, WL_CONT, WL_IDX, 1);
      e.mem[_t_6 + 0] = _fs_3;
      WL_CONT = term_tsk(FID_RUN_K103, _t_6);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_CORE_TRACE)) {
      u64 _t_7 = task_node(e, FID_CORE_TRACE, WL_CONT, WL_IDX, 0);
      e.mem[_t_7 + 0] = _h_4;
      e.mem[_t_7 + 1] = _h_5;
      e.mem[_t_7 + 2] = _h_3;
      return term_tsk(FID_CORE_TRACE, _t_7);
    }
    r0 = _h_4;
    r1 = _h_5;
    r2 = _h_3;
    WL_JMP(FID_CORE_TRACE);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K103)
  {
    WL_POPN(1);
    Term _fs_4 = STK(0);
    Term _r_0 = r0;
    WL_OPEN
    _fs_4 = term_keep(e, _fs_4, 1);
    if (seq) {
      WL_ROOM(3);
      STK(0) = _fs_4;
      STK(1) = _r_0;
      STK(2) = FID_RUN_K104;
      WL_PUSHN(3);
    } else {
      u64 _t_8 = task_node(e, FID_RUN_K104, WL_CONT, WL_IDX, 1);
      e.mem[_t_8 + 0] = _fs_4;
      e.mem[_t_8 + 1] = _r_0;
      WL_CONT = term_tsk(FID_RUN_K104, _t_8);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_IMGS_OF)) {
      u64 _t_9 = task_node(e, FID_IMGS_OF, WL_CONT, WL_IDX, 0);
      e.mem[_t_9 + 0] = _fs_4;
      return term_tsk(FID_IMGS_OF, _t_9);
    }
    r0 = _fs_4;
    WL_JMP(FID_IMGS_OF);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K104)
  {
    WL_POPN(2);
    Term _fs_5 = STK(0);
    Term _r_1 = STK(1);
    Term _h_6 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _fs_5;
      STK(1) = _r_1;
      STK(2) = FID_RUN_K105;
      WL_PUSHN(3);
    } else {
      u64 _t_10 = task_node(e, FID_RUN_K105, WL_CONT, WL_IDX, 1);
      e.mem[_t_10 + 0] = _fs_5;
      e.mem[_t_10 + 1] = _r_1;
      WL_CONT = term_tsk(FID_RUN_K105, _t_10);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_ARRAY_TO_LIST_0)) {
      u64 _t_11 = task_node(e, FID_ARRAY_TO_LIST_0, WL_CONT, WL_IDX, 0);
      e.mem[_t_11 + 0] = _h_6;
      return term_tsk(FID_ARRAY_TO_LIST_0, _t_11);
    }
    r0 = _h_6;
    WL_JMP(FID_ARRAY_TO_LIST_0);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K105)
  {
    WL_POPN(2);
    Term _fs_6 = STK(0);
    Term _r_2 = STK(1);
    Term _h_7 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _fs_6;
      STK(1) = _r_2;
      STK(2) = FID_RUN_K106;
      WL_PUSHN(3);
    } else {
      u64 _t_12 = task_node(e, FID_RUN_K106, WL_CONT, WL_IDX, 1);
      e.mem[_t_12 + 0] = _fs_6;
      e.mem[_t_12 + 1] = _r_2;
      WL_CONT = term_tsk(FID_RUN_K106, _t_12);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_SHARE_F)) {
      u64 _t_13 = task_node(e, FID_SHARE_F, WL_CONT, WL_IDX, 0);
      e.mem[_t_13 + 0] = _h_7;
      return term_tsk(FID_SHARE_F, _t_13);
    }
    r0 = _h_7;
    WL_JMP(FID_SHARE_F);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K106)
  {
    WL_POPN(2);
    Term _fs_7 = STK(0);
    Term _r_3 = STK(1);
    Term _ic_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _r_3;
      STK(1) = _ic_0;
      STK(2) = FID_RUN_K107;
      WL_PUSHN(3);
    } else {
      u64 _t_14 = task_node(e, FID_RUN_K107, WL_CONT, WL_IDX, 1);
      e.mem[_t_14 + 0] = _r_3;
      e.mem[_t_14 + 1] = _ic_0;
      WL_CONT = term_tsk(FID_RUN_K107, _t_14);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_LABS_OF)) {
      u64 _t_15 = task_node(e, FID_LABS_OF, WL_CONT, WL_IDX, 0);
      e.mem[_t_15 + 0] = _fs_7;
      return term_tsk(FID_LABS_OF, _t_15);
    }
    r0 = _fs_7;
    WL_JMP(FID_LABS_OF);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K107)
  {
    WL_POPN(2);
    Term _r_4 = STK(0);
    Term _ic_1 = STK(1);
    Term _h_8 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _r_4;
      STK(1) = _ic_1;
      STK(2) = FID_RUN_K108;
      WL_PUSHN(3);
    } else {
      u64 _t_16 = task_node(e, FID_RUN_K108, WL_CONT, WL_IDX, 1);
      e.mem[_t_16 + 0] = _r_4;
      e.mem[_t_16 + 1] = _ic_1;
      WL_CONT = term_tsk(FID_RUN_K108, _t_16);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_ARRAY_TO_LIST_1)) {
      u64 _t_17 = task_node(e, FID_ARRAY_TO_LIST_1, WL_CONT, WL_IDX, 0);
      e.mem[_t_17 + 0] = _h_8;
      return term_tsk(FID_ARRAY_TO_LIST_1, _t_17);
    }
    r0 = _h_8;
    WL_JMP(FID_ARRAY_TO_LIST_1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K108)
  {
    WL_POPN(2);
    Term _r_5 = STK(0);
    Term _ic_2 = STK(1);
    Term _h_9 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _r_5;
      STK(1) = _ic_2;
      STK(2) = FID_RUN_K109;
      WL_PUSHN(3);
    } else {
      u64 _t_18 = task_node(e, FID_RUN_K109, WL_CONT, WL_IDX, 1);
      e.mem[_t_18 + 0] = _r_5;
      e.mem[_t_18 + 1] = _ic_2;
      WL_CONT = term_tsk(FID_RUN_K109, _t_18);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_SHARE_U)) {
      u64 _t_19 = task_node(e, FID_SHARE_U, WL_CONT, WL_IDX, 0);
      e.mem[_t_19 + 0] = _h_9;
      return term_tsk(FID_SHARE_U, _t_19);
    }
    r0 = _h_9;
    WL_JMP(FID_SHARE_U);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K109)
  {
    WL_POPN(2);
    Term _r_6 = STK(0);
    Term _ic_3 = STK(1);
    Term _lc_0 = r0;
    WL_OPEN
    u32 _v_0 = 0;
    _r_6 = term_keep(e, _r_6, 1);
    u32 _v_1 = 0;
    Term _o_0[1];
    if (spin_2(e, _o_0, 0, _r_6) == 0) {
      return 0;
    }
    _v_1 = _o_0[0];
    _v_0 = _v_1;
    _r_6 = term_keep(e, _r_6, 1);
    if (seq) {
      WL_ROOM(5);
      STK(0) = _r_6;
      STK(1) = _ic_3;
      STK(2) = _lc_0;
      STK(3) = _v_0;
      STK(4) = FID_RUN_K110;
      WL_PUSHN(5);
    } else {
      u64 _t_20 = task_node(e, FID_RUN_K110, WL_CONT, WL_IDX, 1);
      e.mem[_t_20 + 0] = _r_6;
      e.mem[_t_20 + 1] = _ic_3;
      e.mem[_t_20 + 2] = _lc_0;
      e.mem[_t_20 + 3] = _v_0;
      WL_CONT = term_tsk(FID_RUN_K110, _t_20);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID_BITS_AT)) {
      u64 _t_21 = task_node(e, FID_BITS_AT, WL_CONT, WL_IDX, 0);
      e.mem[_t_21 + 0] = 0;
      e.mem[_t_21 + 1] = _r_6;
      return term_tsk(FID_BITS_AT, _t_21);
    }
    r0 = 0;
    r1 = _r_6;
    WL_JMP(FID_BITS_AT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K110)
  {
    WL_POPN(4);
    Term _r_7 = STK(0);
    Term _ic_4 = STK(1);
    Term _lc_1 = STK(2);
    u32 _v_2 = STK(3);
    Term _h_10 = r0;
    WL_OPEN
    _r_7 = term_keep(e, _r_7, 1);
    if (seq) {
      WL_ROOM(6);
      STK(0) = _r_7;
      STK(1) = _ic_4;
      STK(2) = _lc_1;
      STK(3) = _v_2;
      STK(4) = _h_10;
      STK(5) = FID_RUN_K111;
      WL_PUSHN(6);
    } else {
      u64 _t_22 = task_node(e, FID_RUN_K111, WL_CONT, WL_IDX, 1);
      e.mem[_t_22 + 0] = _r_7;
      e.mem[_t_22 + 1] = _ic_4;
      e.mem[_t_22 + 2] = _lc_1;
      e.mem[_t_22 + 3] = _v_2;
      e.mem[_t_22 + 4] = _h_10;
      WL_CONT = term_tsk(FID_RUN_K111, _t_22);
      WL_IDX = 5;
    }
    if (!DEVICE && !seq && fid_nofk(FID_BITS_AT)) {
      u64 _t_23 = task_node(e, FID_BITS_AT, WL_CONT, WL_IDX, 0);
      e.mem[_t_23 + 0] = 1ull;
      e.mem[_t_23 + 1] = _r_7;
      return term_tsk(FID_BITS_AT, _t_23);
    }
    r0 = 1ull;
    r1 = _r_7;
    WL_JMP(FID_BITS_AT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K111)
  {
    WL_POPN(5);
    Term _r_8 = STK(0);
    Term _ic_5 = STK(1);
    Term _lc_2 = STK(2);
    u32 _v_3 = STK(3);
    Term _h_12 = STK(4);
    Term _h_11 = r0;
    WL_OPEN
    _r_8 = term_keep(e, _r_8, 1);
    if (seq) {
      WL_ROOM(7);
      STK(0) = _r_8;
      STK(1) = _ic_5;
      STK(2) = _lc_2;
      STK(3) = _v_3;
      STK(4) = _h_12;
      STK(5) = _h_11;
      STK(6) = FID_RUN_K112;
      WL_PUSHN(7);
    } else {
      u64 _t_24 = task_node(e, FID_RUN_K112, WL_CONT, WL_IDX, 1);
      e.mem[_t_24 + 0] = _r_8;
      e.mem[_t_24 + 1] = _ic_5;
      e.mem[_t_24 + 2] = _lc_2;
      e.mem[_t_24 + 3] = _v_3;
      e.mem[_t_24 + 4] = _h_12;
      e.mem[_t_24 + 5] = _h_11;
      WL_CONT = term_tsk(FID_RUN_K112, _t_24);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID_BITS_AT)) {
      u64 _t_25 = task_node(e, FID_BITS_AT, WL_CONT, WL_IDX, 0);
      e.mem[_t_25 + 0] = 2ull;
      e.mem[_t_25 + 1] = _r_8;
      return term_tsk(FID_BITS_AT, _t_25);
    }
    r0 = 2ull;
    r1 = _r_8;
    WL_JMP(FID_BITS_AT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K112)
  {
    WL_POPN(6);
    Term _r_9 = STK(0);
    Term _ic_6 = STK(1);
    Term _lc_3 = STK(2);
    u32 _v_4 = STK(3);
    Term _h_14 = STK(4);
    Term _h_15 = STK(5);
    Term _h_13 = r0;
    WL_OPEN
    _r_9 = term_keep(e, _r_9, 1);
    if (seq) {
      WL_ROOM(8);
      STK(0) = _r_9;
      STK(1) = _ic_6;
      STK(2) = _lc_3;
      STK(3) = _v_4;
      STK(4) = _h_14;
      STK(5) = _h_15;
      STK(6) = _h_13;
      STK(7) = FID_RUN_K113;
      WL_PUSHN(8);
    } else {
      u64 _t_26 = task_node(e, FID_RUN_K113, WL_CONT, WL_IDX, 1);
      e.mem[_t_26 + 0] = _r_9;
      e.mem[_t_26 + 1] = _ic_6;
      e.mem[_t_26 + 2] = _lc_3;
      e.mem[_t_26 + 3] = _v_4;
      e.mem[_t_26 + 4] = _h_14;
      e.mem[_t_26 + 5] = _h_15;
      e.mem[_t_26 + 6] = _h_13;
      WL_CONT = term_tsk(FID_RUN_K113, _t_26);
      WL_IDX = 7;
    }
    if (!DEVICE && !seq && fid_nofk(FID_BITS_AT)) {
      u64 _t_27 = task_node(e, FID_BITS_AT, WL_CONT, WL_IDX, 0);
      e.mem[_t_27 + 0] = 3ull;
      e.mem[_t_27 + 1] = _r_9;
      return term_tsk(FID_BITS_AT, _t_27);
    }
    r0 = 3ull;
    r1 = _r_9;
    WL_JMP(FID_BITS_AT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K113)
  {
    WL_POPN(7);
    Term _r_10 = STK(0);
    Term _ic_7 = STK(1);
    Term _lc_4 = STK(2);
    u32 _v_5 = STK(3);
    Term _h_17 = STK(4);
    Term _h_18 = STK(5);
    Term _h_19 = STK(6);
    Term _h_16 = r0;
    WL_OPEN
    _r_10 = term_keep(e, _r_10, 1);
    if (seq) {
      WL_ROOM(9);
      STK(0) = _r_10;
      STK(1) = _ic_7;
      STK(2) = _lc_4;
      STK(3) = _v_5;
      STK(4) = _h_17;
      STK(5) = _h_18;
      STK(6) = _h_19;
      STK(7) = _h_16;
      STK(8) = FID_RUN_K114;
      WL_PUSHN(9);
    } else {
      u64 _t_28 = task_node(e, FID_RUN_K114, WL_CONT, WL_IDX, 1);
      e.mem[_t_28 + 0] = _r_10;
      e.mem[_t_28 + 1] = _ic_7;
      e.mem[_t_28 + 2] = _lc_4;
      e.mem[_t_28 + 3] = _v_5;
      e.mem[_t_28 + 4] = _h_17;
      e.mem[_t_28 + 5] = _h_18;
      e.mem[_t_28 + 6] = _h_19;
      e.mem[_t_28 + 7] = _h_16;
      WL_CONT = term_tsk(FID_RUN_K114, _t_28);
      WL_IDX = 8;
    }
    if (!DEVICE && !seq && fid_nofk(FID_BITS_AT)) {
      u64 _t_29 = task_node(e, FID_BITS_AT, WL_CONT, WL_IDX, 0);
      e.mem[_t_29 + 0] = 4ull;
      e.mem[_t_29 + 1] = _r_10;
      return term_tsk(FID_BITS_AT, _t_29);
    }
    r0 = 4ull;
    r1 = _r_10;
    WL_JMP(FID_BITS_AT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K114)
  {
    WL_POPN(8);
    Term _r_11 = STK(0);
    Term _ic_8 = STK(1);
    Term _lc_5 = STK(2);
    u32 _v_6 = STK(3);
    Term _h_21 = STK(4);
    Term _h_22 = STK(5);
    Term _h_23 = STK(6);
    Term _h_24 = STK(7);
    Term _h_20 = r0;
    WL_OPEN
    _r_11 = term_keep(e, _r_11, 1);
    if (seq) {
      WL_ROOM(10);
      STK(0) = _r_11;
      STK(1) = _ic_8;
      STK(2) = _lc_5;
      STK(3) = _v_6;
      STK(4) = _h_21;
      STK(5) = _h_22;
      STK(6) = _h_23;
      STK(7) = _h_24;
      STK(8) = _h_20;
      STK(9) = FID_RUN_K115;
      WL_PUSHN(10);
    } else {
      u64 _t_30 = task_node(e, FID_RUN_K115, WL_CONT, WL_IDX, 1);
      e.mem[_t_30 + 0] = _r_11;
      e.mem[_t_30 + 1] = _ic_8;
      e.mem[_t_30 + 2] = _lc_5;
      e.mem[_t_30 + 3] = _v_6;
      e.mem[_t_30 + 4] = _h_21;
      e.mem[_t_30 + 5] = _h_22;
      e.mem[_t_30 + 6] = _h_23;
      e.mem[_t_30 + 7] = _h_24;
      e.mem[_t_30 + 8] = _h_20;
      WL_CONT = term_tsk(FID_RUN_K115, _t_30);
      WL_IDX = 9;
    }
    if (!DEVICE && !seq && fid_nofk(FID_BITS_AT)) {
      u64 _t_31 = task_node(e, FID_BITS_AT, WL_CONT, WL_IDX, 0);
      e.mem[_t_31 + 0] = 5ull;
      e.mem[_t_31 + 1] = _r_11;
      return term_tsk(FID_BITS_AT, _t_31);
    }
    r0 = 5ull;
    r1 = _r_11;
    WL_JMP(FID_BITS_AT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K115)
  {
    WL_POPN(9);
    Term _r_12 = STK(0);
    Term _ic_9 = STK(1);
    Term _lc_6 = STK(2);
    u32 _v_7 = STK(3);
    Term _h_26 = STK(4);
    Term _h_27 = STK(5);
    Term _h_28 = STK(6);
    Term _h_29 = STK(7);
    Term _h_30 = STK(8);
    Term _h_25 = r0;
    WL_OPEN
    _r_12 = term_keep(e, _r_12, 1);
    if (seq) {
      WL_ROOM(11);
      STK(0) = _r_12;
      STK(1) = _ic_9;
      STK(2) = _lc_6;
      STK(3) = _v_7;
      STK(4) = _h_26;
      STK(5) = _h_27;
      STK(6) = _h_28;
      STK(7) = _h_29;
      STK(8) = _h_30;
      STK(9) = _h_25;
      STK(10) = FID_RUN_K116;
      WL_PUSHN(11);
    } else {
      u64 _t_32 = task_node(e, FID_RUN_K116, WL_CONT, WL_IDX, 1);
      e.mem[_t_32 + 0] = _r_12;
      e.mem[_t_32 + 1] = _ic_9;
      e.mem[_t_32 + 2] = _lc_6;
      e.mem[_t_32 + 3] = _v_7;
      e.mem[_t_32 + 4] = _h_26;
      e.mem[_t_32 + 5] = _h_27;
      e.mem[_t_32 + 6] = _h_28;
      e.mem[_t_32 + 7] = _h_29;
      e.mem[_t_32 + 8] = _h_30;
      e.mem[_t_32 + 9] = _h_25;
      WL_CONT = term_tsk(FID_RUN_K116, _t_32);
      WL_IDX = 10;
    }
    if (!DEVICE && !seq && fid_nofk(FID_BITS_AT)) {
      u64 _t_33 = task_node(e, FID_BITS_AT, WL_CONT, WL_IDX, 0);
      e.mem[_t_33 + 0] = 6ull;
      e.mem[_t_33 + 1] = _r_12;
      return term_tsk(FID_BITS_AT, _t_33);
    }
    r0 = 6ull;
    r1 = _r_12;
    WL_JMP(FID_BITS_AT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K116)
  {
    WL_POPN(10);
    Term _r_13 = STK(0);
    Term _ic_10 = STK(1);
    Term _lc_7 = STK(2);
    u32 _v_8 = STK(3);
    Term _h_32 = STK(4);
    Term _h_33 = STK(5);
    Term _h_34 = STK(6);
    Term _h_35 = STK(7);
    Term _h_36 = STK(8);
    Term _h_37 = STK(9);
    Term _h_31 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(11);
      STK(0) = _ic_10;
      STK(1) = _lc_7;
      STK(2) = _v_8;
      STK(3) = _h_32;
      STK(4) = _h_33;
      STK(5) = _h_34;
      STK(6) = _h_35;
      STK(7) = _h_36;
      STK(8) = _h_37;
      STK(9) = _h_31;
      STK(10) = FID_RUN_K117;
      WL_PUSHN(11);
    } else {
      u64 _t_34 = task_node(e, FID_RUN_K117, WL_CONT, WL_IDX, 1);
      e.mem[_t_34 + 0] = _ic_10;
      e.mem[_t_34 + 1] = _lc_7;
      e.mem[_t_34 + 2] = _v_8;
      e.mem[_t_34 + 3] = _h_32;
      e.mem[_t_34 + 4] = _h_33;
      e.mem[_t_34 + 5] = _h_34;
      e.mem[_t_34 + 6] = _h_35;
      e.mem[_t_34 + 7] = _h_36;
      e.mem[_t_34 + 8] = _h_37;
      e.mem[_t_34 + 9] = _h_31;
      WL_CONT = term_tsk(FID_RUN_K117, _t_34);
      WL_IDX = 10;
    }
    if (!DEVICE && !seq && fid_nofk(FID_BITS_AT)) {
      u64 _t_35 = task_node(e, FID_BITS_AT, WL_CONT, WL_IDX, 0);
      e.mem[_t_35 + 0] = 7ull;
      e.mem[_t_35 + 1] = _r_13;
      return term_tsk(FID_BITS_AT, _t_35);
    }
    r0 = 7ull;
    r1 = _r_13;
    WL_JMP(FID_BITS_AT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K117)
  {
    WL_POPN(10);
    Term _ic_11 = STK(0);
    Term _lc_8 = STK(1);
    u32 _v_9 = STK(2);
    Term _h_39 = STK(3);
    Term _h_40 = STK(4);
    Term _h_41 = STK(5);
    Term _h_42 = STK(6);
    Term _h_43 = STK(7);
    Term _h_44 = STK(8);
    Term _h_45 = STK(9);
    Term _h_38 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(11);
      STK(0) = _lc_8;
      STK(1) = _v_9;
      STK(2) = _h_39;
      STK(3) = _h_40;
      STK(4) = _h_41;
      STK(5) = _h_42;
      STK(6) = _h_43;
      STK(7) = _h_44;
      STK(8) = _h_45;
      STK(9) = _h_38;
      STK(10) = FID_RUN_K118;
      WL_PUSHN(11);
    } else {
      u64 _t_36 = task_node(e, FID_RUN_K118, WL_CONT, WL_IDX, 1);
      e.mem[_t_36 + 0] = _lc_8;
      e.mem[_t_36 + 1] = _v_9;
      e.mem[_t_36 + 2] = _h_39;
      e.mem[_t_36 + 3] = _h_40;
      e.mem[_t_36 + 4] = _h_41;
      e.mem[_t_36 + 5] = _h_42;
      e.mem[_t_36 + 6] = _h_43;
      e.mem[_t_36 + 7] = _h_44;
      e.mem[_t_36 + 8] = _h_45;
      e.mem[_t_36 + 9] = _h_38;
      WL_CONT = term_tsk(FID_RUN_K118, _t_36);
      WL_IDX = 10;
    }
    if (!DEVICE && !seq && fid_nofk(FID_SHOW_F)) {
      u64 _t_37 = task_node(e, FID_SHOW_F, WL_CONT, WL_IDX, 0);
      e.mem[_t_37 + 0] = _ic_11;
      return term_tsk(FID_SHOW_F, _t_37);
    }
    r0 = _ic_11;
    WL_JMP(FID_SHOW_F);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K118)
  {
    WL_POPN(10);
    Term _lc_9 = STK(0);
    u32 _v_10 = STK(1);
    Term _h_47 = STK(2);
    Term _h_48 = STK(3);
    Term _h_49 = STK(4);
    Term _h_50 = STK(5);
    Term _h_51 = STK(6);
    Term _h_52 = STK(7);
    Term _h_53 = STK(8);
    Term _h_54 = STK(9);
    Term _h_46 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(11);
      STK(0) = _v_10;
      STK(1) = _h_47;
      STK(2) = _h_48;
      STK(3) = _h_49;
      STK(4) = _h_50;
      STK(5) = _h_51;
      STK(6) = _h_52;
      STK(7) = _h_53;
      STK(8) = _h_54;
      STK(9) = _h_46;
      STK(10) = FID_RUN_K119;
      WL_PUSHN(11);
    } else {
      u64 _t_38 = task_node(e, FID_RUN_K119, WL_CONT, WL_IDX, 1);
      e.mem[_t_38 + 0] = _v_10;
      e.mem[_t_38 + 1] = _h_47;
      e.mem[_t_38 + 2] = _h_48;
      e.mem[_t_38 + 3] = _h_49;
      e.mem[_t_38 + 4] = _h_50;
      e.mem[_t_38 + 5] = _h_51;
      e.mem[_t_38 + 6] = _h_52;
      e.mem[_t_38 + 7] = _h_53;
      e.mem[_t_38 + 8] = _h_54;
      e.mem[_t_38 + 9] = _h_46;
      WL_CONT = term_tsk(FID_RUN_K119, _t_38);
      WL_IDX = 10;
    }
    if (!DEVICE && !seq && fid_nofk(FID_SHOW_U)) {
      u64 _t_39 = task_node(e, FID_SHOW_U, WL_CONT, WL_IDX, 0);
      e.mem[_t_39 + 0] = _lc_9;
      return term_tsk(FID_SHOW_U, _t_39);
    }
    r0 = _lc_9;
    WL_JMP(FID_SHOW_U);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K119)
  {
    WL_POPN(10);
    u32 _v_11 = STK(0);
    Term _h_56 = STK(1);
    Term _h_57 = STK(2);
    Term _h_58 = STK(3);
    Term _h_59 = STK(4);
    Term _h_60 = STK(5);
    Term _h_61 = STK(6);
    Term _h_62 = STK(7);
    Term _h_63 = STK(8);
    Term _h_64 = STK(9);
    Term _h_55 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(10);
      STK(0) = _v_11;
      STK(1) = _h_56;
      STK(2) = _h_57;
      STK(3) = _h_58;
      STK(4) = _h_59;
      STK(5) = _h_60;
      STK(6) = _h_61;
      STK(7) = _h_62;
      STK(8) = _h_63;
      STK(9) = FID_RUN_K120;
      WL_PUSHN(10);
    } else {
      u64 _t_40 = task_node(e, FID_RUN_K120, WL_CONT, WL_IDX, 1);
      e.mem[_t_40 + 0] = _v_11;
      e.mem[_t_40 + 1] = _h_56;
      e.mem[_t_40 + 2] = _h_57;
      e.mem[_t_40 + 3] = _h_58;
      e.mem[_t_40 + 4] = _h_59;
      e.mem[_t_40 + 5] = _h_60;
      e.mem[_t_40 + 6] = _h_61;
      e.mem[_t_40 + 7] = _h_62;
      e.mem[_t_40 + 8] = _h_63;
      WL_CONT = term_tsk(FID_RUN_K120, _t_40);
      WL_IDX = 9;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_41 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_41 + 0] = _h_64;
      e.mem[_t_41 + 1] = _h_55;
      return term_tsk(FID_STRING_APPEND, _t_41);
    }
    r0 = _h_64;
    r1 = _h_55;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K120)
  {
    WL_POPN(9);
    u32 _v_12 = STK(0);
    Term _h_66 = STK(1);
    Term _h_67 = STK(2);
    Term _h_68 = STK(3);
    Term _h_69 = STK(4);
    Term _h_70 = STK(5);
    Term _h_71 = STK(6);
    Term _h_72 = STK(7);
    Term _h_73 = STK(8);
    Term _h_65 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(10);
      STK(0) = _v_12;
      STK(1) = _h_66;
      STK(2) = _h_67;
      STK(3) = _h_68;
      STK(4) = _h_69;
      STK(5) = _h_70;
      STK(6) = _h_71;
      STK(7) = _h_72;
      STK(8) = _h_73;
      STK(9) = FID_RUN_K121;
      WL_PUSHN(10);
    } else {
      u64 _t_42 = task_node(e, FID_RUN_K121, WL_CONT, WL_IDX, 1);
      e.mem[_t_42 + 0] = _v_12;
      e.mem[_t_42 + 1] = _h_66;
      e.mem[_t_42 + 2] = _h_67;
      e.mem[_t_42 + 3] = _h_68;
      e.mem[_t_42 + 4] = _h_69;
      e.mem[_t_42 + 5] = _h_70;
      e.mem[_t_42 + 6] = _h_71;
      e.mem[_t_42 + 7] = _h_72;
      e.mem[_t_42 + 8] = _h_73;
      WL_CONT = term_tsk(FID_RUN_K121, _t_42);
      WL_IDX = 9;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_43 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_43 + 0] = term_ctr(CID_SCON, STAT_OFF + 12);
      e.mem[_t_43 + 1] = _h_65;
      return term_tsk(FID_STRING_APPEND, _t_43);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 12);
    r1 = _h_65;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K121)
  {
    WL_POPN(9);
    u32 _v_13 = STK(0);
    Term _h_75 = STK(1);
    Term _h_76 = STK(2);
    Term _h_77 = STK(3);
    Term _h_78 = STK(4);
    Term _h_79 = STK(5);
    Term _h_80 = STK(6);
    Term _h_81 = STK(7);
    Term _h_82 = STK(8);
    Term _h_74 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(9);
      STK(0) = _v_13;
      STK(1) = _h_75;
      STK(2) = _h_76;
      STK(3) = _h_77;
      STK(4) = _h_78;
      STK(5) = _h_79;
      STK(6) = _h_80;
      STK(7) = _h_81;
      STK(8) = FID_RUN_K122;
      WL_PUSHN(9);
    } else {
      u64 _t_44 = task_node(e, FID_RUN_K122, WL_CONT, WL_IDX, 1);
      e.mem[_t_44 + 0] = _v_13;
      e.mem[_t_44 + 1] = _h_75;
      e.mem[_t_44 + 2] = _h_76;
      e.mem[_t_44 + 3] = _h_77;
      e.mem[_t_44 + 4] = _h_78;
      e.mem[_t_44 + 5] = _h_79;
      e.mem[_t_44 + 6] = _h_80;
      e.mem[_t_44 + 7] = _h_81;
      WL_CONT = term_tsk(FID_RUN_K122, _t_44);
      WL_IDX = 8;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_45 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_45 + 0] = _h_82;
      e.mem[_t_45 + 1] = _h_74;
      return term_tsk(FID_STRING_APPEND, _t_45);
    }
    r0 = _h_82;
    r1 = _h_74;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K122)
  {
    WL_POPN(8);
    u32 _v_14 = STK(0);
    Term _h_84 = STK(1);
    Term _h_85 = STK(2);
    Term _h_86 = STK(3);
    Term _h_87 = STK(4);
    Term _h_88 = STK(5);
    Term _h_89 = STK(6);
    Term _h_90 = STK(7);
    Term _h_83 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(8);
      STK(0) = _v_14;
      STK(1) = _h_84;
      STK(2) = _h_85;
      STK(3) = _h_86;
      STK(4) = _h_87;
      STK(5) = _h_88;
      STK(6) = _h_89;
      STK(7) = FID_RUN_K123;
      WL_PUSHN(8);
    } else {
      u64 _t_46 = task_node(e, FID_RUN_K123, WL_CONT, WL_IDX, 1);
      e.mem[_t_46 + 0] = _v_14;
      e.mem[_t_46 + 1] = _h_84;
      e.mem[_t_46 + 2] = _h_85;
      e.mem[_t_46 + 3] = _h_86;
      e.mem[_t_46 + 4] = _h_87;
      e.mem[_t_46 + 5] = _h_88;
      e.mem[_t_46 + 6] = _h_89;
      WL_CONT = term_tsk(FID_RUN_K123, _t_46);
      WL_IDX = 7;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_47 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_47 + 0] = _h_90;
      e.mem[_t_47 + 1] = _h_83;
      return term_tsk(FID_STRING_APPEND, _t_47);
    }
    r0 = _h_90;
    r1 = _h_83;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K123)
  {
    WL_POPN(7);
    u32 _v_15 = STK(0);
    Term _h_92 = STK(1);
    Term _h_93 = STK(2);
    Term _h_94 = STK(3);
    Term _h_95 = STK(4);
    Term _h_96 = STK(5);
    Term _h_97 = STK(6);
    Term _h_91 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(7);
      STK(0) = _v_15;
      STK(1) = _h_92;
      STK(2) = _h_93;
      STK(3) = _h_94;
      STK(4) = _h_95;
      STK(5) = _h_96;
      STK(6) = FID_RUN_K124;
      WL_PUSHN(7);
    } else {
      u64 _t_48 = task_node(e, FID_RUN_K124, WL_CONT, WL_IDX, 1);
      e.mem[_t_48 + 0] = _v_15;
      e.mem[_t_48 + 1] = _h_92;
      e.mem[_t_48 + 2] = _h_93;
      e.mem[_t_48 + 3] = _h_94;
      e.mem[_t_48 + 4] = _h_95;
      e.mem[_t_48 + 5] = _h_96;
      WL_CONT = term_tsk(FID_RUN_K124, _t_48);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_49 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_49 + 0] = _h_97;
      e.mem[_t_49 + 1] = _h_91;
      return term_tsk(FID_STRING_APPEND, _t_49);
    }
    r0 = _h_97;
    r1 = _h_91;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K124)
  {
    WL_POPN(6);
    u32 _v_16 = STK(0);
    Term _h_99 = STK(1);
    Term _h_100 = STK(2);
    Term _h_101 = STK(3);
    Term _h_102 = STK(4);
    Term _h_103 = STK(5);
    Term _h_98 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(6);
      STK(0) = _v_16;
      STK(1) = _h_99;
      STK(2) = _h_100;
      STK(3) = _h_101;
      STK(4) = _h_102;
      STK(5) = FID_RUN_K125;
      WL_PUSHN(6);
    } else {
      u64 _t_50 = task_node(e, FID_RUN_K125, WL_CONT, WL_IDX, 1);
      e.mem[_t_50 + 0] = _v_16;
      e.mem[_t_50 + 1] = _h_99;
      e.mem[_t_50 + 2] = _h_100;
      e.mem[_t_50 + 3] = _h_101;
      e.mem[_t_50 + 4] = _h_102;
      WL_CONT = term_tsk(FID_RUN_K125, _t_50);
      WL_IDX = 5;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_51 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_51 + 0] = _h_103;
      e.mem[_t_51 + 1] = _h_98;
      return term_tsk(FID_STRING_APPEND, _t_51);
    }
    r0 = _h_103;
    r1 = _h_98;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K125)
  {
    WL_POPN(5);
    u32 _v_17 = STK(0);
    Term _h_105 = STK(1);
    Term _h_106 = STK(2);
    Term _h_107 = STK(3);
    Term _h_108 = STK(4);
    Term _h_104 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _v_17;
      STK(1) = _h_105;
      STK(2) = _h_106;
      STK(3) = _h_107;
      STK(4) = FID_RUN_K126;
      WL_PUSHN(5);
    } else {
      u64 _t_52 = task_node(e, FID_RUN_K126, WL_CONT, WL_IDX, 1);
      e.mem[_t_52 + 0] = _v_17;
      e.mem[_t_52 + 1] = _h_105;
      e.mem[_t_52 + 2] = _h_106;
      e.mem[_t_52 + 3] = _h_107;
      WL_CONT = term_tsk(FID_RUN_K126, _t_52);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_53 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_53 + 0] = _h_108;
      e.mem[_t_53 + 1] = _h_104;
      return term_tsk(FID_STRING_APPEND, _t_53);
    }
    r0 = _h_108;
    r1 = _h_104;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K126)
  {
    WL_POPN(4);
    u32 _v_18 = STK(0);
    Term _h_110 = STK(1);
    Term _h_111 = STK(2);
    Term _h_112 = STK(3);
    Term _h_109 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(4);
      STK(0) = _v_18;
      STK(1) = _h_110;
      STK(2) = _h_111;
      STK(3) = FID_RUN_K127;
      WL_PUSHN(4);
    } else {
      u64 _t_54 = task_node(e, FID_RUN_K127, WL_CONT, WL_IDX, 1);
      e.mem[_t_54 + 0] = _v_18;
      e.mem[_t_54 + 1] = _h_110;
      e.mem[_t_54 + 2] = _h_111;
      WL_CONT = term_tsk(FID_RUN_K127, _t_54);
      WL_IDX = 3;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_55 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_55 + 0] = _h_112;
      e.mem[_t_55 + 1] = _h_109;
      return term_tsk(FID_STRING_APPEND, _t_55);
    }
    r0 = _h_112;
    r1 = _h_109;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K127)
  {
    WL_POPN(3);
    u32 _v_19 = STK(0);
    Term _h_114 = STK(1);
    Term _h_115 = STK(2);
    Term _h_113 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _v_19;
      STK(1) = _h_114;
      STK(2) = FID_RUN_K128;
      WL_PUSHN(3);
    } else {
      u64 _t_56 = task_node(e, FID_RUN_K128, WL_CONT, WL_IDX, 1);
      e.mem[_t_56 + 0] = _v_19;
      e.mem[_t_56 + 1] = _h_114;
      WL_CONT = term_tsk(FID_RUN_K128, _t_56);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_57 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_57 + 0] = _h_115;
      e.mem[_t_57 + 1] = _h_113;
      return term_tsk(FID_STRING_APPEND, _t_57);
    }
    r0 = _h_115;
    r1 = _h_113;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K128)
  {
    WL_POPN(2);
    u32 _v_20 = STK(0);
    Term _h_117 = STK(1);
    Term _h_116 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _v_20;
      STK(1) = FID_RUN_K129;
      WL_PUSHN(2);
    } else {
      u64 _t_58 = task_node(e, FID_RUN_K129, WL_CONT, WL_IDX, 1);
      e.mem[_t_58 + 0] = _v_20;
      WL_CONT = term_tsk(FID_RUN_K129, _t_58);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_59 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_59 + 0] = _h_117;
      e.mem[_t_59 + 1] = _h_116;
      return term_tsk(FID_STRING_APPEND, _t_59);
    }
    r0 = _h_117;
    r1 = _h_116;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K129)
  {
    WL_POPN(1);
    u32 _v_21 = STK(0);
    Term _h_118 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _v_21;
      STK(1) = FID_RUN_K130;
      WL_PUSHN(2);
    } else {
      u64 _t_60 = task_node(e, FID_RUN_K130, WL_CONT, WL_IDX, 1);
      e.mem[_t_60 + 0] = _v_21;
      WL_CONT = term_tsk(FID_RUN_K130, _t_60);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_61 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_61 + 0] = term_ctr(CID_SCON, STAT_OFF + 24);
      e.mem[_t_61 + 1] = _h_118;
      return term_tsk(FID_STRING_APPEND, _t_61);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 24);
    r1 = _h_118;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K130)
  {
    WL_POPN(1);
    u32 _v_22 = STK(0);
    Term _h_119 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_RUN_K131;
      WL_PUSHN(1);
    } else {
      u64 _t_62 = task_node(e, FID_RUN_K131, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_RUN_K131, _t_62);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_63 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_63 + 0] = f32_show(e, _v_22);
      e.mem[_t_63 + 1] = _h_119;
      return term_tsk(FID_STRING_APPEND, _t_63);
    }
    r0 = f32_show(e, _v_22);
    r1 = _h_119;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_RUN_K131)
  {
    Term _h_120 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_64 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_64 + 0] = term_ctr(CID_SCON, STAT_OFF + 32);
      e.mem[_t_64 + 1] = _h_120;
      return term_tsk(FID_STRING_APPEND, _t_64);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 32);
    r1 = _h_120;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN)
  {
    WL_OPEN
    r0 = term_clo(FID_MAIN_C136, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C136)
  {
    Term _x_0 = r0;
    WL_OPEN
    Term _m_0 = term_clo(FID_IO_ARGS, 0);
    Term _f_0 = term_clo(FID_MAIN_C137, 0);
    u64 _nd_1 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_1 + 0] = _f_0;
    e.mem[_nd_1 + 1] = _x_0;
    if (!DEVICE && !seq && fid_nofk(FID_CLO_APPLY)) {
      u64 _t_7 = task_node(e, FID_CLO_APPLY, WL_CONT, WL_IDX, 0);
      e.mem[_t_7 + 0] = _m_0;
      e.mem[_t_7 + 1] = term_clo(FID_MAIN_C140, _nd_1);
      return term_tsk(FID_CLO_APPLY, _t_7);
    }
    r0 = _m_0;
    r1 = term_clo(FID_MAIN_C140, _nd_1);
    WL_JMP(FID_CLO_APPLY);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C137)
  {
    Term _x_1 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K138;
      WL_PUSHN(1);
    } else {
      u64 _t_0 = task_node(e, FID_MAIN_K138, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K138, _t_0);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_PAYLOAD)) {
      u64 _t_1 = task_node(e, FID_PAYLOAD, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _x_1;
      return term_tsk(FID_PAYLOAD, _t_1);
    }
    r0 = _x_1;
    WL_JMP(FID_PAYLOAD);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K138)
  {
    Term _h_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K139;
      WL_PUSHN(1);
    } else {
      u64 _t_2 = task_node(e, FID_MAIN_K139, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K139, _t_2);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_RUN)) {
      u64 _t_3 = task_node(e, FID_RUN, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = _h_0;
      return term_tsk(FID_RUN, _t_3);
    }
    r0 = _h_0;
    WL_JMP(FID_RUN);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K139)
  {
    Term _h_1 = r0;
    WL_OPEN
    u64 _nd_0 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_0 + 0] = _h_1;
    r0 = term_clo(FID_IO_PRINT, _nd_0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C140)
  {
    Term _f_1 = r0;
    Term _x_3 = r1;
    Term _x_2 = r2;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _x_3;
      STK(1) = FID_MAIN_K141;
      WL_PUSHN(2);
    } else {
      u64 _t_4 = task_node(e, FID_MAIN_K141, WL_CONT, WL_IDX, 1);
      e.mem[_t_4 + 0] = _x_3;
      WL_CONT = term_tsk(FID_MAIN_K141, _t_4);
      WL_IDX = 1;
    }
    if (!DEVICE && !seq && fid_nofk(FID_CLO_APPLY)) {
      u64 _t_5 = task_node(e, FID_CLO_APPLY, WL_CONT, WL_IDX, 0);
      e.mem[_t_5 + 0] = _f_1;
      e.mem[_t_5 + 1] = _x_2;
      return term_tsk(FID_CLO_APPLY, _t_5);
    }
    r0 = _f_1;
    r1 = _x_2;
    WL_JMP(FID_CLO_APPLY);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K141)
  {
    WL_POPN(1);
    Term _x_4 = STK(0);
    Term _h_2 = r0;
    WL_OPEN
    if (!DEVICE && !seq && fid_nofk(FID_CLO_APPLY)) {
      u64 _t_6 = task_node(e, FID_CLO_APPLY, WL_CONT, WL_IDX, 0);
      e.mem[_t_6 + 0] = _h_2;
      e.mem[_t_6 + 1] = _x_4;
      return term_tsk(FID_CLO_APPLY, _t_6);
    }
    r0 = _h_2;
    r1 = _x_4;
    WL_JMP(FID_CLO_APPLY);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_IO_ARGS)
  {
    Term _k_6 = r0;
    WL_OPEN
    u64 _nd_6 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_6 + 0] = _k_6;
    r0 = term_ctr(CID_IO_ARGS, _nd_6);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_IO_PRINT)
  {
    Term _text_3 = r0;
    Term _k_7 = r1;
    WL_OPEN
    u64 _nd_7 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_7 + 0] = _text_3;
    e.mem[_nd_7 + 1] = _k_7;
    r0 = term_ctr(CID_IO_PRINT, _nd_7);
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

// IO
// ==

Term io_args_run(Env e, Term* f, IoWork* w) {
  Term xs = term_pak(CID_NIL, 0);
  for (int i = io_argc; i > 0; i -= 1) {
    const char* a = io_argv[i - 1];
    xs = io_node(e, CID_CON, io_str(e, a, strlen(a)), xs);
  }
  return xs;
}

static void __attribute__((constructor)) io_args_use(void) {
  io_eff(CID_IO_ARGS, io_args_run, 0);
}
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
