
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
#define CID__________TINYBENDYGRAD_HELPERS_I64 13
#define CID_CHR 14
#define CID_NIL 15
#define CID_CON 16
#define CID_WIRE_FLAT 17
#define CID_WIRE_BOXED 18
#define CID_WIRE_BOXED_SWAP 19
#define CID_WIRE_BOXED_SAME 20
#define CID_IO_PRINT 21
#define FID_U32_SHOW_GO 0
#define FID_U32_SHOW 1
#define FID_STRING_CONCAT 2
#define FID_STRING_CONCAT_K5 3
#define FID__________TINYBENDYGRAD_HELPERS_I64_TEXT 4
#define FID__________TINYBENDYGRAD_HELPERS_I64_TEXT_K12 5
#define FID__________TINYBENDYGRAD_HELPERS_I64_TEXT_K13 6
#define FID_STRING_APPEND 7
#define FID_STRING_APPEND_K15 8
#define FID_IO_BIND 9
#define FID_IO_BIND_C18 10
#define FID_IO_BIND_K19 11
#define FID_MAIN 12
#define FID_MAIN_C21 13
#define FID_MAIN_C22 14
#define FID_MAIN_C23 15
#define FID_MAIN_C24 16
#define FID_MAIN_C25 17
#define FID_MAIN_C26 18
#define FID_MAIN_C27 19
#define FID_MAIN_C28 20
#define FID_MAIN_K29 21
#define FID_MAIN_K30 22
#define FID_MAIN_C31 23
#define FID_MAIN_C32 24
#define FID_MAIN_K33 25
#define FID_MAIN_K34 26
#define FID_MAIN_C35 27
#define FID_MAIN_C36 28
#define FID_MAIN_K37 29
#define FID_MAIN_K38 30
#define FID_MAIN_C39 31
#define FID_MAIN_C40 32
#define FID_MAIN_K41 33
#define FID_MAIN_K42 34
#define FID_MAIN_C43 35
#define FID_MAIN_C44 36
#define FID_MAIN_C45 37
#define FID_MAIN_C46 38
#define FID_MAIN_C47 39
#define FID_MAIN_C48 40
#define FID_MAIN_C49 41
#define FID_MAIN_C50 42
#define FID_MAIN_C51 43
#define FID_MAIN_C52 44
#define FID_MAIN_K53 45
#define FID_MAIN_K54 46
#define FID_MAIN_C55 47
#define FID_MAIN_C56 48
#define FID_MAIN_K57 49
#define FID_MAIN_K58 50
#define FID_MAIN_C59 51
#define FID_MAIN_C60 52
#define FID_MAIN_K61 53
#define FID_MAIN_K62 54
#define FID_MAIN_C63 55
#define FID_MAIN_C64 56
#define FID_MAIN_K65 57
#define FID_MAIN_K66 58
#define FID_MAIN_C67 59
#define FID_MAIN_C68 60
#define FID_MAIN_C69 61
#define FID_MAIN_C70 62
#define FID_MAIN_C71 63
#define FID_MAIN_C72 64
#define FID_MAIN_C73 65
#define FID_MAIN_C74 66
#define FID_MAIN_C75 67
#define FID_MAIN_C76 68
#define FID_MAIN_K77 69
#define FID_MAIN_K78 70
#define FID_MAIN_C79 71
#define FID_MAIN_C80 72
#define FID_MAIN_K81 73
#define FID_MAIN_K82 74
#define FID_MAIN_C83 75
#define FID_MAIN_C84 76
#define FID_MAIN_K85 77
#define FID_MAIN_K86 78
#define FID_MAIN_C87 79
#define FID_MAIN_C88 80
#define FID_MAIN_K89 81
#define FID_MAIN_K90 82
#define FID_MAIN_C91 83
#define FID_MAIN_C92 84
#define FID_MAIN_C93 85
#define FID_MAIN_C94 86
#define FID_MAIN_C95 87
#define FID_MAIN_C96 88
#define FID_MAIN_C97 89
#define FID_MAIN_C98 90
#define FID_MAIN_C99 91
#define FID_MAIN_C100 92
#define FID_MAIN_K101 93
#define FID_MAIN_K102 94
#define FID_MAIN_C103 95
#define FID_MAIN_C104 96
#define FID_MAIN_K105 97
#define FID_MAIN_K106 98
#define FID_MAIN_C107 99
#define FID_MAIN_C108 100
#define FID_MAIN_K109 101
#define FID_MAIN_K110 102
#define FID_MAIN_C111 103
#define FID_MAIN_C112 104
#define FID_MAIN_K113 105
#define FID_MAIN_K114 106
#define FID_MAIN_C115 107
#define FID_MAIN_C116 108
#define FID_MAIN_C117 109
#define FID_MAIN_C118 110
#define FID_MAIN_C119 111
#define FID_MAIN_C120 112
#define FID_MAIN_C121 113
#define FID_MAIN_C122 114
#define FID_MAIN_C123 115
#define FID_MAIN_C124 116
#define FID_MAIN_K125 117
#define FID_MAIN_K126 118
#define FID_MAIN_C127 119
#define FID_MAIN_C128 120
#define FID_MAIN_K129 121
#define FID_MAIN_K130 122
#define FID_MAIN_C131 123
#define FID_MAIN_C132 124
#define FID_MAIN_K133 125
#define FID_MAIN_K134 126
#define FID_MAIN_C135 127
#define FID_MAIN_C136 128
#define FID_MAIN_K137 129
#define FID_MAIN_K138 130
#define FID_MAIN_C139 131
#define FID_MAIN_C140 132
#define FID_MAIN_C141 133
#define FID_MAIN_C142 134
#define FID_MAIN_C143 135
#define FID_MAIN_C144 136
#define FID_MAIN_C145 137
#define FID_MAIN_C146 138
#define FID_MAIN_C147 139
#define FID_MAIN_C148 140
#define FID_MAIN_K149 141
#define FID_MAIN_K150 142
#define FID_MAIN_C151 143
#define FID_MAIN_C152 144
#define FID_MAIN_K153 145
#define FID_MAIN_K154 146
#define FID_MAIN_C155 147
#define FID_MAIN_C156 148
#define FID_MAIN_K157 149
#define FID_MAIN_K158 150
#define FID_MAIN_C159 151
#define FID_MAIN_C160 152
#define FID_MAIN_K161 153
#define FID_MAIN_K162 154
#define FID_MAIN_C163 155
#define FID_MAIN_C164 156
#define FID_MAIN_C165 157
#define FID_MAIN_C166 158
#define FID_MAIN_C167 159
#define FID_MAIN_C168 160
#define FID_MAIN_C169 161
#define FID_MAIN_C170 162
#define FID_MAIN_C171 163
#define FID_MAIN_C172 164
#define FID_MAIN_K173 165
#define FID_MAIN_K174 166
#define FID_MAIN_C175 167
#define FID_MAIN_C176 168
#define FID_MAIN_K177 169
#define FID_MAIN_K178 170
#define FID_MAIN_C179 171
#define FID_MAIN_C180 172
#define FID_MAIN_K181 173
#define FID_MAIN_K182 174
#define FID_MAIN_C183 175
#define FID_MAIN_C184 176
#define FID_MAIN_K185 177
#define FID_MAIN_K186 178
#define FID_MAIN_C187 179
#define FID_MAIN_C188 180
#define FID_MAIN_C189 181
#define FID_MAIN_C190 182
#define FID_MAIN_C191 183
#define FID_MAIN_C192 184
#define FID_MAIN_C193 185
#define FID_MAIN_C194 186
#define FID_MAIN_C195 187
#define FID_MAIN_C196 188
#define FID_MAIN_K197 189
#define FID_MAIN_K198 190
#define FID_MAIN_C199 191
#define FID_MAIN_C200 192
#define FID_MAIN_K201 193
#define FID_MAIN_K202 194
#define FID_MAIN_C203 195
#define FID_MAIN_C204 196
#define FID_MAIN_K205 197
#define FID_MAIN_K206 198
#define FID_MAIN_C207 199
#define FID_MAIN_C208 200
#define FID_MAIN_K209 201
#define FID_MAIN_K210 202
#define FID_WIRE_FLAT 203
#define FID_WIRE_BOXED 204
#define FID_WIRE_BOXED_SWAP 205
#define FID_WIRE_BOXED_SAME 206
#define FID_IO_PRINT 207
#define FID_IO_EMIT 208
#define FID_CLO_APPLY 209
#define FID_EXIT 210
#define FID_ENTER 211
CONSTV u8 FID_T[][3] = { { 3, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 2, 1, 2 }, { 2, 0, 2 }, { 2, 1, 2 }, { 2, 1, 2 }, { 2, 0, 2 }, { 2, 1, 2 }, { 3, 0, 2 }, { 3, 0, 2 }, { 2, 1, 2 }, { 0, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 3, 0, 2 }, { 3, 0, 2 }, { 5, 0, 2 }, { 5, 0, 2 }, { 7, 0, 2 }, { 7, 0, 2 }, { 7, 1, 2 }, { 7, 1, 2 }, { 8, 0, 2 }, { 7, 0, 2 }, { 5, 1, 2 }, { 5, 1, 2 }, { 6, 0, 2 }, { 5, 0, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 4, 0, 2 }, { 3, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 3, 0, 2 }, { 3, 0, 2 }, { 5, 0, 2 }, { 5, 0, 2 }, { 7, 0, 2 }, { 7, 0, 2 }, { 7, 1, 2 }, { 7, 1, 2 }, { 8, 0, 2 }, { 7, 0, 2 }, { 5, 1, 2 }, { 5, 1, 2 }, { 6, 0, 2 }, { 5, 0, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 4, 0, 2 }, { 3, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 3, 0, 2 }, { 3, 0, 2 }, { 5, 0, 2 }, { 5, 0, 2 }, { 7, 0, 2 }, { 7, 0, 2 }, { 7, 1, 2 }, { 7, 1, 2 }, { 8, 0, 2 }, { 7, 0, 2 }, { 5, 1, 2 }, { 5, 1, 2 }, { 6, 0, 2 }, { 5, 0, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 4, 0, 2 }, { 3, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 3, 0, 2 }, { 3, 0, 2 }, { 5, 0, 2 }, { 5, 0, 2 }, { 7, 0, 2 }, { 7, 0, 2 }, { 7, 1, 2 }, { 7, 1, 2 }, { 8, 0, 2 }, { 7, 0, 2 }, { 5, 1, 2 }, { 5, 1, 2 }, { 6, 0, 2 }, { 5, 0, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 4, 0, 2 }, { 3, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 3, 0, 2 }, { 3, 0, 2 }, { 5, 0, 2 }, { 5, 0, 2 }, { 7, 0, 2 }, { 7, 0, 2 }, { 7, 1, 2 }, { 7, 1, 2 }, { 8, 0, 2 }, { 7, 0, 2 }, { 5, 1, 2 }, { 5, 1, 2 }, { 6, 0, 2 }, { 5, 0, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 4, 0, 2 }, { 3, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 3, 0, 2 }, { 3, 0, 2 }, { 5, 0, 2 }, { 5, 0, 2 }, { 7, 0, 2 }, { 7, 0, 2 }, { 7, 1, 2 }, { 7, 1, 2 }, { 8, 0, 2 }, { 7, 0, 2 }, { 5, 1, 2 }, { 5, 1, 2 }, { 6, 0, 2 }, { 5, 0, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 4, 0, 2 }, { 3, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 3, 0, 2 }, { 3, 0, 2 }, { 5, 0, 2 }, { 5, 0, 2 }, { 7, 0, 2 }, { 7, 0, 2 }, { 7, 1, 2 }, { 7, 1, 2 }, { 8, 0, 2 }, { 7, 0, 2 }, { 5, 1, 2 }, { 5, 1, 2 }, { 6, 0, 2 }, { 5, 0, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 4, 0, 2 }, { 3, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 1, 0, 2 }, { 3, 0, 2 }, { 3, 0, 2 }, { 5, 0, 2 }, { 5, 0, 2 }, { 7, 0, 2 }, { 7, 0, 2 }, { 7, 1, 2 }, { 7, 1, 2 }, { 8, 0, 2 }, { 7, 0, 2 }, { 5, 1, 2 }, { 5, 1, 2 }, { 6, 0, 2 }, { 5, 0, 2 }, { 3, 1, 2 }, { 3, 1, 2 }, { 4, 0, 2 }, { 3, 0, 2 }, { 1, 1, 2 }, { 1, 1, 2 }, { 2, 0, 2 }, { 2, 0, 2 }, { 2, 0, 2 }, { 2, 0, 2 }, { 2, 0, 2 }, { 1, 0, 2 }, { 2, 0, 2 } };
CONSTV u8 CID_T[][2] = { { 2, 0 }, { 0, 0 }, { 2, 0 }, { 2, 0 }, { 1, 0 }, { 2, 0 }, { 1, 0 }, { 1, 0 }, { 0, 0 }, { 1, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 2, 0 }, { 1, 0 }, { 0, 0 }, { 2, 0 }, { 2, 0 }, { 2, 0 }, { 2, 0 }, { 2, 0 }, { 2, 0 } };
#define STAT_LEN 804

#define WL_RESW 1
#define BANGS   0

#define WL_BANK Term r0, r1, r2, r3, r4, r5, rp, r6, r7;

#define WL_LOAD(A, N) \
  do { \
    if ((N) <= 0) break; r0 = e.mem[(A) + 0]; \
    if ((N) <= 1) break; r1 = e.mem[(A) + 1]; \
    if ((N) <= 2) break; r2 = e.mem[(A) + 2]; \
    if ((N) <= 3) break; r3 = e.mem[(A) + 3]; \
    if ((N) <= 4) break; r4 = e.mem[(A) + 4]; \
    if ((N) <= 5) break; r5 = e.mem[(A) + 5]; \
    if ((N) <= 6) break; r6 = e.mem[(A) + 6]; \
    if ((N) <= 7) break; r7 = e.mem[(A) + 7]; \
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
    case 6: r6 = (X); \
      break; \
    case 7: r7 = (X); \
      break; \
  }

#define WL_SAVE(V) (V)[0] = r0;

#define WL_TAKE(V) r0 = (V)[0];

#define WL_SIG Env e, DEV Term* sp, u32 seq, u32 rn, Term r0, Term r1, Term r2, Term r3, Term r4, Term r5, Term rp, Term r6, Term r7

#define WL_ALL e, sp, seq, rn, r0, r1, r2, r3, r4, r5, rp, r6, r7

#define WL_TABLE WL_X(FID_U32_SHOW_GO) WL_X(FID_U32_SHOW) WL_X(FID_STRING_CONCAT) WL_X(FID_STRING_CONCAT_K5) WL_X(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT) WL_X(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT_K12) WL_X(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT_K13) WL_X(FID_STRING_APPEND) WL_X(FID_STRING_APPEND_K15) WL_X(FID_IO_BIND) WL_X(FID_IO_BIND_C18) WL_X(FID_IO_BIND_K19) WL_X(FID_MAIN) WL_X(FID_MAIN_C21) WL_X(FID_MAIN_C22) WL_X(FID_MAIN_C23) WL_X(FID_MAIN_C24) WL_X(FID_MAIN_C25) WL_X(FID_MAIN_C26) WL_X(FID_MAIN_C27) WL_X(FID_MAIN_C28) WL_X(FID_MAIN_K29) WL_X(FID_MAIN_K30) WL_X(FID_MAIN_C31) WL_X(FID_MAIN_C32) WL_X(FID_MAIN_K33) WL_X(FID_MAIN_K34) WL_X(FID_MAIN_C35) WL_X(FID_MAIN_C36) WL_X(FID_MAIN_K37) WL_X(FID_MAIN_K38) WL_X(FID_MAIN_C39) WL_X(FID_MAIN_C40) WL_X(FID_MAIN_K41) WL_X(FID_MAIN_K42) WL_X(FID_MAIN_C43) WL_X(FID_MAIN_C44) WL_X(FID_MAIN_C45) WL_X(FID_MAIN_C46) WL_X(FID_MAIN_C47) WL_X(FID_MAIN_C48) WL_X(FID_MAIN_C49) WL_X(FID_MAIN_C50) WL_X(FID_MAIN_C51) WL_X(FID_MAIN_C52) WL_X(FID_MAIN_K53) WL_X(FID_MAIN_K54) WL_X(FID_MAIN_C55) WL_X(FID_MAIN_C56) WL_X(FID_MAIN_K57) WL_X(FID_MAIN_K58) WL_X(FID_MAIN_C59) WL_X(FID_MAIN_C60) WL_X(FID_MAIN_K61) WL_X(FID_MAIN_K62) WL_X(FID_MAIN_C63) WL_X(FID_MAIN_C64) WL_X(FID_MAIN_K65) WL_X(FID_MAIN_K66) WL_X(FID_MAIN_C67) WL_X(FID_MAIN_C68) WL_X(FID_MAIN_C69) WL_X(FID_MAIN_C70) WL_X(FID_MAIN_C71) WL_X(FID_MAIN_C72) WL_X(FID_MAIN_C73) WL_X(FID_MAIN_C74) WL_X(FID_MAIN_C75) WL_X(FID_MAIN_C76) WL_X(FID_MAIN_K77) WL_X(FID_MAIN_K78) WL_X(FID_MAIN_C79) WL_X(FID_MAIN_C80) WL_X(FID_MAIN_K81) WL_X(FID_MAIN_K82) WL_X(FID_MAIN_C83) WL_X(FID_MAIN_C84) WL_X(FID_MAIN_K85) WL_X(FID_MAIN_K86) WL_X(FID_MAIN_C87) WL_X(FID_MAIN_C88) WL_X(FID_MAIN_K89) WL_X(FID_MAIN_K90) WL_X(FID_MAIN_C91) WL_X(FID_MAIN_C92) WL_X(FID_MAIN_C93) WL_X(FID_MAIN_C94) WL_X(FID_MAIN_C95) WL_X(FID_MAIN_C96) WL_X(FID_MAIN_C97) WL_X(FID_MAIN_C98) WL_X(FID_MAIN_C99) WL_X(FID_MAIN_C100) WL_X(FID_MAIN_K101) WL_X(FID_MAIN_K102) WL_X(FID_MAIN_C103) WL_X(FID_MAIN_C104) WL_X(FID_MAIN_K105) WL_X(FID_MAIN_K106) WL_X(FID_MAIN_C107) WL_X(FID_MAIN_C108) WL_X(FID_MAIN_K109) WL_X(FID_MAIN_K110) WL_X(FID_MAIN_C111) WL_X(FID_MAIN_C112) WL_X(FID_MAIN_K113) WL_X(FID_MAIN_K114) WL_X(FID_MAIN_C115) WL_X(FID_MAIN_C116) WL_X(FID_MAIN_C117) WL_X(FID_MAIN_C118) WL_X(FID_MAIN_C119) WL_X(FID_MAIN_C120) WL_X(FID_MAIN_C121) WL_X(FID_MAIN_C122) WL_X(FID_MAIN_C123) WL_X(FID_MAIN_C124) WL_X(FID_MAIN_K125) WL_X(FID_MAIN_K126) WL_X(FID_MAIN_C127) WL_X(FID_MAIN_C128) WL_X(FID_MAIN_K129) WL_X(FID_MAIN_K130) WL_X(FID_MAIN_C131) WL_X(FID_MAIN_C132) WL_X(FID_MAIN_K133) WL_X(FID_MAIN_K134) WL_X(FID_MAIN_C135) WL_X(FID_MAIN_C136) WL_X(FID_MAIN_K137) WL_X(FID_MAIN_K138) WL_X(FID_MAIN_C139) WL_X(FID_MAIN_C140) WL_X(FID_MAIN_C141) WL_X(FID_MAIN_C142) WL_X(FID_MAIN_C143) WL_X(FID_MAIN_C144) WL_X(FID_MAIN_C145) WL_X(FID_MAIN_C146) WL_X(FID_MAIN_C147) WL_X(FID_MAIN_C148) WL_X(FID_MAIN_K149) WL_X(FID_MAIN_K150) WL_X(FID_MAIN_C151) WL_X(FID_MAIN_C152) WL_X(FID_MAIN_K153) WL_X(FID_MAIN_K154) WL_X(FID_MAIN_C155) WL_X(FID_MAIN_C156) WL_X(FID_MAIN_K157) WL_X(FID_MAIN_K158) WL_X(FID_MAIN_C159) WL_X(FID_MAIN_C160) WL_X(FID_MAIN_K161) WL_X(FID_MAIN_K162) WL_X(FID_MAIN_C163) WL_X(FID_MAIN_C164) WL_X(FID_MAIN_C165) WL_X(FID_MAIN_C166) WL_X(FID_MAIN_C167) WL_X(FID_MAIN_C168) WL_X(FID_MAIN_C169) WL_X(FID_MAIN_C170) WL_X(FID_MAIN_C171) WL_X(FID_MAIN_C172) WL_X(FID_MAIN_K173) WL_X(FID_MAIN_K174) WL_X(FID_MAIN_C175) WL_X(FID_MAIN_C176) WL_X(FID_MAIN_K177) WL_X(FID_MAIN_K178) WL_X(FID_MAIN_C179) WL_X(FID_MAIN_C180) WL_X(FID_MAIN_K181) WL_X(FID_MAIN_K182) WL_X(FID_MAIN_C183) WL_X(FID_MAIN_C184) WL_X(FID_MAIN_K185) WL_X(FID_MAIN_K186) WL_X(FID_MAIN_C187) WL_X(FID_MAIN_C188) WL_X(FID_MAIN_C189) WL_X(FID_MAIN_C190) WL_X(FID_MAIN_C191) WL_X(FID_MAIN_C192) WL_X(FID_MAIN_C193) WL_X(FID_MAIN_C194) WL_X(FID_MAIN_C195) WL_X(FID_MAIN_C196) WL_X(FID_MAIN_K197) WL_X(FID_MAIN_K198) WL_X(FID_MAIN_C199) WL_X(FID_MAIN_C200) WL_X(FID_MAIN_K201) WL_X(FID_MAIN_K202) WL_X(FID_MAIN_C203) WL_X(FID_MAIN_C204) WL_X(FID_MAIN_K205) WL_X(FID_MAIN_K206) WL_X(FID_MAIN_C207) WL_X(FID_MAIN_C208) WL_X(FID_MAIN_K209) WL_X(FID_MAIN_K210) WL_X(FID_WIRE_FLAT) WL_X(FID_WIRE_BOXED) WL_X(FID_WIRE_BOXED_SWAP) WL_X(FID_WIRE_BOXED_SAME) WL_X(FID_IO_PRINT) WL_X(FID_IO_EMIT) WL_X(FID_CLO_APPLY) WL_X(FID_EXIT)
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

CONSTV u64 STAT_IMG[] = { 48ull, term_pak(CID_SNIL, 0), 58ull, term_pak(CID_SNIL, 0), 1ull, 2ull, 32ull, term_pak(CID_SNIL, 0), 61ull, term_ctr(CID_SCON, STAT_OFF + 6), 32ull, term_ctr(CID_SCON, STAT_OFF + 8), 50ull, term_ctr(CID_SCON, STAT_OFF + 10), 124ull, term_ctr(CID_SCON, STAT_OFF + 12), 49ull, term_ctr(CID_SCON, STAT_OFF + 14), 124ull, term_ctr(CID_SCON, STAT_OFF + 16), 116ull, term_ctr(CID_SCON, STAT_OFF + 18), 97ull, term_ctr(CID_SCON, STAT_OFF + 20), 108ull, term_ctr(CID_SCON, STAT_OFF + 22), 102ull, term_ctr(CID_SCON, STAT_OFF + 24), 32ull, term_ctr(CID_SCON, STAT_OFF + 26), 69ull, term_ctr(CID_SCON, STAT_OFF + 28), 82ull, term_ctr(CID_SCON, STAT_OFF + 30), 73ull, term_ctr(CID_SCON, STAT_OFF + 32), 87ull, term_ctr(CID_SCON, STAT_OFF + 34), 100ull, term_ctr(CID_SCON, STAT_OFF + 18), 101ull, term_ctr(CID_SCON, STAT_OFF + 38), 120ull, term_ctr(CID_SCON, STAT_OFF + 40), 111ull, term_ctr(CID_SCON, STAT_OFF + 42), 98ull, term_ctr(CID_SCON, STAT_OFF + 44), 32ull, term_ctr(CID_SCON, STAT_OFF + 46), 69ull, term_ctr(CID_SCON, STAT_OFF + 48), 82ull, term_ctr(CID_SCON, STAT_OFF + 50), 73ull, term_ctr(CID_SCON, STAT_OFF + 52), 87ull, term_ctr(CID_SCON, STAT_OFF + 54), 112ull, term_ctr(CID_SCON, STAT_OFF + 18), 97ull, term_ctr(CID_SCON, STAT_OFF + 58), 119ull, term_ctr(CID_SCON, STAT_OFF + 60), 115ull, term_ctr(CID_SCON, STAT_OFF + 62), 32ull, term_ctr(CID_SCON, STAT_OFF + 64), 69ull, term_ctr(CID_SCON, STAT_OFF + 66), 82ull, term_ctr(CID_SCON, STAT_OFF + 68), 73ull, term_ctr(CID_SCON, STAT_OFF + 70), 87ull, term_ctr(CID_SCON, STAT_OFF + 72), 101ull, term_ctr(CID_SCON, STAT_OFF + 18), 109ull, term_ctr(CID_SCON, STAT_OFF + 76), 97ull, term_ctr(CID_SCON, STAT_OFF + 78), 115ull, term_ctr(CID_SCON, STAT_OFF + 80), 32ull, term_ctr(CID_SCON, STAT_OFF + 82), 69ull, term_ctr(CID_SCON, STAT_OFF + 84), 82ull, term_ctr(CID_SCON, STAT_OFF + 86), 73ull, term_ctr(CID_SCON, STAT_OFF + 88), 87ull, term_ctr(CID_SCON, STAT_OFF + 90), 123456ull, 654321ull, 49ull, term_ctr(CID_SCON, STAT_OFF + 10), 50ull, term_ctr(CID_SCON, STAT_OFF + 96), 51ull, term_ctr(CID_SCON, STAT_OFF + 98), 52ull, term_ctr(CID_SCON, STAT_OFF + 100), 53ull, term_ctr(CID_SCON, STAT_OFF + 102), 54ull, term_ctr(CID_SCON, STAT_OFF + 104), 124ull, term_ctr(CID_SCON, STAT_OFF + 106), 54ull, term_ctr(CID_SCON, STAT_OFF + 108), 53ull, term_ctr(CID_SCON, STAT_OFF + 110), 52ull, term_ctr(CID_SCON, STAT_OFF + 112), 51ull, term_ctr(CID_SCON, STAT_OFF + 114), 50ull, term_ctr(CID_SCON, STAT_OFF + 116), 49ull, term_ctr(CID_SCON, STAT_OFF + 118), 124ull, term_ctr(CID_SCON, STAT_OFF + 120), 116ull, term_ctr(CID_SCON, STAT_OFF + 122), 97ull, term_ctr(CID_SCON, STAT_OFF + 124), 108ull, term_ctr(CID_SCON, STAT_OFF + 126), 102ull, term_ctr(CID_SCON, STAT_OFF + 128), 32ull, term_ctr(CID_SCON, STAT_OFF + 130), 69ull, term_ctr(CID_SCON, STAT_OFF + 132), 82ull, term_ctr(CID_SCON, STAT_OFF + 134), 73ull, term_ctr(CID_SCON, STAT_OFF + 136), 87ull, term_ctr(CID_SCON, STAT_OFF + 138), 100ull, term_ctr(CID_SCON, STAT_OFF + 122), 101ull, term_ctr(CID_SCON, STAT_OFF + 142), 120ull, term_ctr(CID_SCON, STAT_OFF + 144), 111ull, term_ctr(CID_SCON, STAT_OFF + 146), 98ull, term_ctr(CID_SCON, STAT_OFF + 148), 32ull, term_ctr(CID_SCON, STAT_OFF + 150), 69ull, term_ctr(CID_SCON, STAT_OFF + 152), 82ull, term_ctr(CID_SCON, STAT_OFF + 154), 73ull, term_ctr(CID_SCON, STAT_OFF + 156), 87ull, term_ctr(CID_SCON, STAT_OFF + 158), 112ull, term_ctr(CID_SCON, STAT_OFF + 122), 97ull, term_ctr(CID_SCON, STAT_OFF + 162), 119ull, term_ctr(CID_SCON, STAT_OFF + 164), 115ull, term_ctr(CID_SCON, STAT_OFF + 166), 32ull, term_ctr(CID_SCON, STAT_OFF + 168), 69ull, term_ctr(CID_SCON, STAT_OFF + 170), 82ull, term_ctr(CID_SCON, STAT_OFF + 172), 73ull, term_ctr(CID_SCON, STAT_OFF + 174), 87ull, term_ctr(CID_SCON, STAT_OFF + 176), 101ull, term_ctr(CID_SCON, STAT_OFF + 122), 109ull, term_ctr(CID_SCON, STAT_OFF + 180), 97ull, term_ctr(CID_SCON, STAT_OFF + 182), 115ull, term_ctr(CID_SCON, STAT_OFF + 184), 32ull, term_ctr(CID_SCON, STAT_OFF + 186), 69ull, term_ctr(CID_SCON, STAT_OFF + 188), 82ull, term_ctr(CID_SCON, STAT_OFF + 190), 73ull, term_ctr(CID_SCON, STAT_OFF + 192), 87ull, term_ctr(CID_SCON, STAT_OFF + 194), 0ull, 7ull, 55ull, term_ctr(CID_SCON, STAT_OFF + 10), 124ull, term_ctr(CID_SCON, STAT_OFF + 200), 48ull, term_ctr(CID_SCON, STAT_OFF + 202), 124ull, term_ctr(CID_SCON, STAT_OFF + 204), 116ull, term_ctr(CID_SCON, STAT_OFF + 206), 97ull, term_ctr(CID_SCON, STAT_OFF + 208), 108ull, term_ctr(CID_SCON, STAT_OFF + 210), 102ull, term_ctr(CID_SCON, STAT_OFF + 212), 32ull, term_ctr(CID_SCON, STAT_OFF + 214), 69ull, term_ctr(CID_SCON, STAT_OFF + 216), 82ull, term_ctr(CID_SCON, STAT_OFF + 218), 73ull, term_ctr(CID_SCON, STAT_OFF + 220), 87ull, term_ctr(CID_SCON, STAT_OFF + 222), 100ull, term_ctr(CID_SCON, STAT_OFF + 206), 101ull, term_ctr(CID_SCON, STAT_OFF + 226), 120ull, term_ctr(CID_SCON, STAT_OFF + 228), 111ull, term_ctr(CID_SCON, STAT_OFF + 230), 98ull, term_ctr(CID_SCON, STAT_OFF + 232), 32ull, term_ctr(CID_SCON, STAT_OFF + 234), 69ull, term_ctr(CID_SCON, STAT_OFF + 236), 82ull, term_ctr(CID_SCON, STAT_OFF + 238), 73ull, term_ctr(CID_SCON, STAT_OFF + 240), 87ull, term_ctr(CID_SCON, STAT_OFF + 242), 112ull, term_ctr(CID_SCON, STAT_OFF + 206), 97ull, term_ctr(CID_SCON, STAT_OFF + 246), 119ull, term_ctr(CID_SCON, STAT_OFF + 248), 115ull, term_ctr(CID_SCON, STAT_OFF + 250), 32ull, term_ctr(CID_SCON, STAT_OFF + 252), 69ull, term_ctr(CID_SCON, STAT_OFF + 254), 82ull, term_ctr(CID_SCON, STAT_OFF + 256), 73ull, term_ctr(CID_SCON, STAT_OFF + 258), 87ull, term_ctr(CID_SCON, STAT_OFF + 260), 101ull, term_ctr(CID_SCON, STAT_OFF + 206), 109ull, term_ctr(CID_SCON, STAT_OFF + 264), 97ull, term_ctr(CID_SCON, STAT_OFF + 266), 115ull, term_ctr(CID_SCON, STAT_OFF + 268), 32ull, term_ctr(CID_SCON, STAT_OFF + 270), 69ull, term_ctr(CID_SCON, STAT_OFF + 272), 82ull, term_ctr(CID_SCON, STAT_OFF + 274), 73ull, term_ctr(CID_SCON, STAT_OFF + 276), 87ull, term_ctr(CID_SCON, STAT_OFF + 278), 4000000000ull, 4000000001ull, 48ull, term_ctr(CID_SCON, STAT_OFF + 96), 48ull, term_ctr(CID_SCON, STAT_OFF + 284), 48ull, term_ctr(CID_SCON, STAT_OFF + 286), 48ull, term_ctr(CID_SCON, STAT_OFF + 288), 48ull, term_ctr(CID_SCON, STAT_OFF + 290), 48ull, term_ctr(CID_SCON, STAT_OFF + 292), 48ull, term_ctr(CID_SCON, STAT_OFF + 294), 48ull, term_ctr(CID_SCON, STAT_OFF + 296), 52ull, term_ctr(CID_SCON, STAT_OFF + 298), 124ull, term_ctr(CID_SCON, STAT_OFF + 300), 48ull, term_ctr(CID_SCON, STAT_OFF + 302), 48ull, term_ctr(CID_SCON, STAT_OFF + 304), 48ull, term_ctr(CID_SCON, STAT_OFF + 306), 48ull, term_ctr(CID_SCON, STAT_OFF + 308), 48ull, term_ctr(CID_SCON, STAT_OFF + 310), 48ull, term_ctr(CID_SCON, STAT_OFF + 312), 48ull, term_ctr(CID_SCON, STAT_OFF + 314), 48ull, term_ctr(CID_SCON, STAT_OFF + 316), 48ull, term_ctr(CID_SCON, STAT_OFF + 318), 52ull, term_ctr(CID_SCON, STAT_OFF + 320), 124ull, term_ctr(CID_SCON, STAT_OFF + 322), 116ull, term_ctr(CID_SCON, STAT_OFF + 324), 97ull, term_ctr(CID_SCON, STAT_OFF + 326), 108ull, term_ctr(CID_SCON, STAT_OFF + 328), 102ull, term_ctr(CID_SCON, STAT_OFF + 330), 32ull, term_ctr(CID_SCON, STAT_OFF + 332), 69ull, term_ctr(CID_SCON, STAT_OFF + 334), 82ull, term_ctr(CID_SCON, STAT_OFF + 336), 73ull, term_ctr(CID_SCON, STAT_OFF + 338), 87ull, term_ctr(CID_SCON, STAT_OFF + 340), 100ull, term_ctr(CID_SCON, STAT_OFF + 324), 101ull, term_ctr(CID_SCON, STAT_OFF + 344), 120ull, term_ctr(CID_SCON, STAT_OFF + 346), 111ull, term_ctr(CID_SCON, STAT_OFF + 348), 98ull, term_ctr(CID_SCON, STAT_OFF + 350), 32ull, term_ctr(CID_SCON, STAT_OFF + 352), 69ull, term_ctr(CID_SCON, STAT_OFF + 354), 82ull, term_ctr(CID_SCON, STAT_OFF + 356), 73ull, term_ctr(CID_SCON, STAT_OFF + 358), 87ull, term_ctr(CID_SCON, STAT_OFF + 360), 112ull, term_ctr(CID_SCON, STAT_OFF + 324), 97ull, term_ctr(CID_SCON, STAT_OFF + 364), 119ull, term_ctr(CID_SCON, STAT_OFF + 366), 115ull, term_ctr(CID_SCON, STAT_OFF + 368), 32ull, term_ctr(CID_SCON, STAT_OFF + 370), 69ull, term_ctr(CID_SCON, STAT_OFF + 372), 82ull, term_ctr(CID_SCON, STAT_OFF + 374), 73ull, term_ctr(CID_SCON, STAT_OFF + 376), 87ull, term_ctr(CID_SCON, STAT_OFF + 378), 101ull, term_ctr(CID_SCON, STAT_OFF + 324), 109ull, term_ctr(CID_SCON, STAT_OFF + 382), 97ull, term_ctr(CID_SCON, STAT_OFF + 384), 115ull, term_ctr(CID_SCON, STAT_OFF + 386), 32ull, term_ctr(CID_SCON, STAT_OFF + 388), 69ull, term_ctr(CID_SCON, STAT_OFF + 390), 82ull, term_ctr(CID_SCON, STAT_OFF + 392), 73ull, term_ctr(CID_SCON, STAT_OFF + 394), 87ull, term_ctr(CID_SCON, STAT_OFF + 396), 0ull, 0ull, 48ull, term_ctr(CID_SCON, STAT_OFF + 10), 124ull, term_ctr(CID_SCON, STAT_OFF + 402), 48ull, term_ctr(CID_SCON, STAT_OFF + 404), 124ull, term_ctr(CID_SCON, STAT_OFF + 406), 116ull, term_ctr(CID_SCON, STAT_OFF + 408), 97ull, term_ctr(CID_SCON, STAT_OFF + 410), 108ull, term_ctr(CID_SCON, STAT_OFF + 412), 102ull, term_ctr(CID_SCON, STAT_OFF + 414), 32ull, term_ctr(CID_SCON, STAT_OFF + 416), 69ull, term_ctr(CID_SCON, STAT_OFF + 418), 82ull, term_ctr(CID_SCON, STAT_OFF + 420), 73ull, term_ctr(CID_SCON, STAT_OFF + 422), 87ull, term_ctr(CID_SCON, STAT_OFF + 424), 100ull, term_ctr(CID_SCON, STAT_OFF + 408), 101ull, term_ctr(CID_SCON, STAT_OFF + 428), 120ull, term_ctr(CID_SCON, STAT_OFF + 430), 111ull, term_ctr(CID_SCON, STAT_OFF + 432), 98ull, term_ctr(CID_SCON, STAT_OFF + 434), 32ull, term_ctr(CID_SCON, STAT_OFF + 436), 69ull, term_ctr(CID_SCON, STAT_OFF + 438), 82ull, term_ctr(CID_SCON, STAT_OFF + 440), 73ull, term_ctr(CID_SCON, STAT_OFF + 442), 87ull, term_ctr(CID_SCON, STAT_OFF + 444), 112ull, term_ctr(CID_SCON, STAT_OFF + 408), 97ull, term_ctr(CID_SCON, STAT_OFF + 448), 119ull, term_ctr(CID_SCON, STAT_OFF + 450), 115ull, term_ctr(CID_SCON, STAT_OFF + 452), 32ull, term_ctr(CID_SCON, STAT_OFF + 454), 69ull, term_ctr(CID_SCON, STAT_OFF + 456), 82ull, term_ctr(CID_SCON, STAT_OFF + 458), 73ull, term_ctr(CID_SCON, STAT_OFF + 460), 87ull, term_ctr(CID_SCON, STAT_OFF + 462), 101ull, term_ctr(CID_SCON, STAT_OFF + 408), 109ull, term_ctr(CID_SCON, STAT_OFF + 466), 97ull, term_ctr(CID_SCON, STAT_OFF + 468), 115ull, term_ctr(CID_SCON, STAT_OFF + 470), 32ull, term_ctr(CID_SCON, STAT_OFF + 472), 69ull, term_ctr(CID_SCON, STAT_OFF + 474), 82ull, term_ctr(CID_SCON, STAT_OFF + 476), 73ull, term_ctr(CID_SCON, STAT_OFF + 478), 87ull, term_ctr(CID_SCON, STAT_OFF + 480), 7ull, 7ull, 55ull, term_ctr(CID_SCON, STAT_OFF + 202), 124ull, term_ctr(CID_SCON, STAT_OFF + 486), 116ull, term_ctr(CID_SCON, STAT_OFF + 488), 97ull, term_ctr(CID_SCON, STAT_OFF + 490), 108ull, term_ctr(CID_SCON, STAT_OFF + 492), 102ull, term_ctr(CID_SCON, STAT_OFF + 494), 32ull, term_ctr(CID_SCON, STAT_OFF + 496), 69ull, term_ctr(CID_SCON, STAT_OFF + 498), 82ull, term_ctr(CID_SCON, STAT_OFF + 500), 73ull, term_ctr(CID_SCON, STAT_OFF + 502), 87ull, term_ctr(CID_SCON, STAT_OFF + 504), 100ull, term_ctr(CID_SCON, STAT_OFF + 488), 101ull, term_ctr(CID_SCON, STAT_OFF + 508), 120ull, term_ctr(CID_SCON, STAT_OFF + 510), 111ull, term_ctr(CID_SCON, STAT_OFF + 512), 98ull, term_ctr(CID_SCON, STAT_OFF + 514), 32ull, term_ctr(CID_SCON, STAT_OFF + 516), 69ull, term_ctr(CID_SCON, STAT_OFF + 518), 82ull, term_ctr(CID_SCON, STAT_OFF + 520), 73ull, term_ctr(CID_SCON, STAT_OFF + 522), 87ull, term_ctr(CID_SCON, STAT_OFF + 524), 112ull, term_ctr(CID_SCON, STAT_OFF + 488), 97ull, term_ctr(CID_SCON, STAT_OFF + 528), 119ull, term_ctr(CID_SCON, STAT_OFF + 530), 115ull, term_ctr(CID_SCON, STAT_OFF + 532), 32ull, term_ctr(CID_SCON, STAT_OFF + 534), 69ull, term_ctr(CID_SCON, STAT_OFF + 536), 82ull, term_ctr(CID_SCON, STAT_OFF + 538), 73ull, term_ctr(CID_SCON, STAT_OFF + 540), 87ull, term_ctr(CID_SCON, STAT_OFF + 542), 101ull, term_ctr(CID_SCON, STAT_OFF + 488), 109ull, term_ctr(CID_SCON, STAT_OFF + 546), 97ull, term_ctr(CID_SCON, STAT_OFF + 548), 115ull, term_ctr(CID_SCON, STAT_OFF + 550), 32ull, term_ctr(CID_SCON, STAT_OFF + 552), 69ull, term_ctr(CID_SCON, STAT_OFF + 554), 82ull, term_ctr(CID_SCON, STAT_OFF + 556), 73ull, term_ctr(CID_SCON, STAT_OFF + 558), 87ull, term_ctr(CID_SCON, STAT_OFF + 560), 4294967295ull, 4294967295ull, 53ull, term_ctr(CID_SCON, STAT_OFF + 10), 57ull, term_ctr(CID_SCON, STAT_OFF + 566), 50ull, term_ctr(CID_SCON, STAT_OFF + 568), 55ull, term_ctr(CID_SCON, STAT_OFF + 570), 54ull, term_ctr(CID_SCON, STAT_OFF + 572), 57ull, term_ctr(CID_SCON, STAT_OFF + 574), 52ull, term_ctr(CID_SCON, STAT_OFF + 576), 57ull, term_ctr(CID_SCON, STAT_OFF + 578), 50ull, term_ctr(CID_SCON, STAT_OFF + 580), 52ull, term_ctr(CID_SCON, STAT_OFF + 582), 124ull, term_ctr(CID_SCON, STAT_OFF + 584), 53ull, term_ctr(CID_SCON, STAT_OFF + 586), 57ull, term_ctr(CID_SCON, STAT_OFF + 588), 50ull, term_ctr(CID_SCON, STAT_OFF + 590), 55ull, term_ctr(CID_SCON, STAT_OFF + 592), 54ull, term_ctr(CID_SCON, STAT_OFF + 594), 57ull, term_ctr(CID_SCON, STAT_OFF + 596), 52ull, term_ctr(CID_SCON, STAT_OFF + 598), 57ull, term_ctr(CID_SCON, STAT_OFF + 600), 50ull, term_ctr(CID_SCON, STAT_OFF + 602), 52ull, term_ctr(CID_SCON, STAT_OFF + 604), 124ull, term_ctr(CID_SCON, STAT_OFF + 606), 116ull, term_ctr(CID_SCON, STAT_OFF + 608), 97ull, term_ctr(CID_SCON, STAT_OFF + 610), 108ull, term_ctr(CID_SCON, STAT_OFF + 612), 102ull, term_ctr(CID_SCON, STAT_OFF + 614), 32ull, term_ctr(CID_SCON, STAT_OFF + 616), 69ull, term_ctr(CID_SCON, STAT_OFF + 618), 82ull, term_ctr(CID_SCON, STAT_OFF + 620), 73ull, term_ctr(CID_SCON, STAT_OFF + 622), 87ull, term_ctr(CID_SCON, STAT_OFF + 624), 100ull, term_ctr(CID_SCON, STAT_OFF + 608), 101ull, term_ctr(CID_SCON, STAT_OFF + 628), 120ull, term_ctr(CID_SCON, STAT_OFF + 630), 111ull, term_ctr(CID_SCON, STAT_OFF + 632), 98ull, term_ctr(CID_SCON, STAT_OFF + 634), 32ull, term_ctr(CID_SCON, STAT_OFF + 636), 69ull, term_ctr(CID_SCON, STAT_OFF + 638), 82ull, term_ctr(CID_SCON, STAT_OFF + 640), 73ull, term_ctr(CID_SCON, STAT_OFF + 642), 87ull, term_ctr(CID_SCON, STAT_OFF + 644), 112ull, term_ctr(CID_SCON, STAT_OFF + 608), 97ull, term_ctr(CID_SCON, STAT_OFF + 648), 119ull, term_ctr(CID_SCON, STAT_OFF + 650), 115ull, term_ctr(CID_SCON, STAT_OFF + 652), 32ull, term_ctr(CID_SCON, STAT_OFF + 654), 69ull, term_ctr(CID_SCON, STAT_OFF + 656), 82ull, term_ctr(CID_SCON, STAT_OFF + 658), 73ull, term_ctr(CID_SCON, STAT_OFF + 660), 87ull, term_ctr(CID_SCON, STAT_OFF + 662), 101ull, term_ctr(CID_SCON, STAT_OFF + 608), 109ull, term_ctr(CID_SCON, STAT_OFF + 666), 97ull, term_ctr(CID_SCON, STAT_OFF + 668), 115ull, term_ctr(CID_SCON, STAT_OFF + 670), 32ull, term_ctr(CID_SCON, STAT_OFF + 672), 69ull, term_ctr(CID_SCON, STAT_OFF + 674), 82ull, term_ctr(CID_SCON, STAT_OFF + 676), 73ull, term_ctr(CID_SCON, STAT_OFF + 678), 87ull, term_ctr(CID_SCON, STAT_OFF + 680), 2147483648ull, 2147483648ull, 56ull, term_ctr(CID_SCON, STAT_OFF + 10), 52ull, term_ctr(CID_SCON, STAT_OFF + 686), 54ull, term_ctr(CID_SCON, STAT_OFF + 688), 51ull, term_ctr(CID_SCON, STAT_OFF + 690), 56ull, term_ctr(CID_SCON, STAT_OFF + 692), 52ull, term_ctr(CID_SCON, STAT_OFF + 694), 55ull, term_ctr(CID_SCON, STAT_OFF + 696), 52ull, term_ctr(CID_SCON, STAT_OFF + 698), 49ull, term_ctr(CID_SCON, STAT_OFF + 700), 50ull, term_ctr(CID_SCON, STAT_OFF + 702), 124ull, term_ctr(CID_SCON, STAT_OFF + 704), 56ull, term_ctr(CID_SCON, STAT_OFF + 706), 52ull, term_ctr(CID_SCON, STAT_OFF + 708), 54ull, term_ctr(CID_SCON, STAT_OFF + 710), 51ull, term_ctr(CID_SCON, STAT_OFF + 712), 56ull, term_ctr(CID_SCON, STAT_OFF + 714), 52ull, term_ctr(CID_SCON, STAT_OFF + 716), 55ull, term_ctr(CID_SCON, STAT_OFF + 718), 52ull, term_ctr(CID_SCON, STAT_OFF + 720), 49ull, term_ctr(CID_SCON, STAT_OFF + 722), 50ull, term_ctr(CID_SCON, STAT_OFF + 724), 124ull, term_ctr(CID_SCON, STAT_OFF + 726), 116ull, term_ctr(CID_SCON, STAT_OFF + 728), 97ull, term_ctr(CID_SCON, STAT_OFF + 730), 108ull, term_ctr(CID_SCON, STAT_OFF + 732), 102ull, term_ctr(CID_SCON, STAT_OFF + 734), 32ull, term_ctr(CID_SCON, STAT_OFF + 736), 69ull, term_ctr(CID_SCON, STAT_OFF + 738), 82ull, term_ctr(CID_SCON, STAT_OFF + 740), 73ull, term_ctr(CID_SCON, STAT_OFF + 742), 87ull, term_ctr(CID_SCON, STAT_OFF + 744), 100ull, term_ctr(CID_SCON, STAT_OFF + 728), 101ull, term_ctr(CID_SCON, STAT_OFF + 748), 120ull, term_ctr(CID_SCON, STAT_OFF + 750), 111ull, term_ctr(CID_SCON, STAT_OFF + 752), 98ull, term_ctr(CID_SCON, STAT_OFF + 754), 32ull, term_ctr(CID_SCON, STAT_OFF + 756), 69ull, term_ctr(CID_SCON, STAT_OFF + 758), 82ull, term_ctr(CID_SCON, STAT_OFF + 760), 73ull, term_ctr(CID_SCON, STAT_OFF + 762), 87ull, term_ctr(CID_SCON, STAT_OFF + 764), 112ull, term_ctr(CID_SCON, STAT_OFF + 728), 97ull, term_ctr(CID_SCON, STAT_OFF + 768), 119ull, term_ctr(CID_SCON, STAT_OFF + 770), 115ull, term_ctr(CID_SCON, STAT_OFF + 772), 32ull, term_ctr(CID_SCON, STAT_OFF + 774), 69ull, term_ctr(CID_SCON, STAT_OFF + 776), 82ull, term_ctr(CID_SCON, STAT_OFF + 778), 73ull, term_ctr(CID_SCON, STAT_OFF + 780), 87ull, term_ctr(CID_SCON, STAT_OFF + 782), 101ull, term_ctr(CID_SCON, STAT_OFF + 728), 109ull, term_ctr(CID_SCON, STAT_OFF + 786), 97ull, term_ctr(CID_SCON, STAT_OFF + 788), 115ull, term_ctr(CID_SCON, STAT_OFF + 790), 32ull, term_ctr(CID_SCON, STAT_OFF + 792), 69ull, term_ctr(CID_SCON, STAT_OFF + 794), 82ull, term_ctr(CID_SCON, STAT_OFF + 796), 73ull, term_ctr(CID_SCON, STAT_OFF + 798), 87ull, term_ctr(CID_SCON, STAT_OFF + 800) };

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
        STK(1) = FID_STRING_CONCAT_K5;
        WL_PUSHN(2);
      } else {
        u64 _t_0 = task_node(e, FID_STRING_CONCAT_K5, WL_CONT, WL_IDX, 1);
        e.mem[_t_0 + 0] = _f_0;
        WL_CONT = term_tsk(FID_STRING_CONCAT_K5, _t_0);
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
  WL_CASE(FID_STRING_CONCAT_K5)
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
  WL_CASE(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)
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
      STK(1) = FID__________TINYBENDYGRAD_HELPERS_I64_TEXT_K12;
      WL_PUSHN(2);
    } else {
      u64 _t_0 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT_K12, WL_CONT, WL_IDX, 1);
      e.mem[_t_0 + 0] = _v_3;
      WL_CONT = term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT_K12, _t_0);
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
  WL_CASE(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT_K12)
  {
    WL_POPN(1);
    u32 _v_6 = STK(0);
    Term _h_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(2);
      STK(0) = _h_0;
      STK(1) = FID__________TINYBENDYGRAD_HELPERS_I64_TEXT_K13;
      WL_PUSHN(2);
    } else {
      u64 _t_2 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT_K13, WL_CONT, WL_IDX, 1);
      e.mem[_t_2 + 0] = _h_0;
      WL_CONT = term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT_K13, _t_2);
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
  WL_CASE(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT_K13)
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
    e.mem[_nd_0 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 4);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_190 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_190 + 0] = term_clo(FID_WIRE_FLAT, _nd_0);
      e.mem[_t_190 + 1] = term_clo(FID_MAIN_C22, 0);
      e.mem[_t_190 + 2] = _x_0;
      return term_tsk(FID_IO_BIND, _t_190);
    }
    r0 = term_clo(FID_WIRE_FLAT, _nd_0);
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
    u64 _nd_1 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_1 + 0] = _f_0;
    e.mem[_nd_1 + 1] = _f_1;
    r0 = term_clo(FID_MAIN_C23, _nd_1);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C23)
  {
    u32 _f_2 = r0;
    u32 _f_3 = r1;
    Term _x_2 = r2;
    WL_OPEN
    u64 _nd_2 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_2 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 4);
    u64 _nd_3 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_3 + 0] = _f_2;
    e.mem[_nd_3 + 1] = _f_3;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_189 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_189 + 0] = term_clo(FID_WIRE_BOXED, _nd_2);
      e.mem[_t_189 + 1] = term_clo(FID_MAIN_C24, _nd_3);
      e.mem[_t_189 + 2] = _x_2;
      return term_tsk(FID_IO_BIND, _t_189);
    }
    r0 = term_clo(FID_WIRE_BOXED, _nd_2);
    r1 = term_clo(FID_MAIN_C24, _nd_3);
    r2 = _x_2;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C24)
  {
    u32 _f_4 = r0;
    u32 _f_5 = r1;
    Term _x_3 = r2;
    WL_OPEN
    Term _fb_1[2];
    u64 _sp_1 = ctr_take(e, _x_3, 2, _fb_1);
    u32 _f_6 = _fb_1[0];
    u32 _f_7 = _fb_1[1];
    spare_free(e, cls_fit(2), _sp_1);
    u64 _nd_4 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_4 + 0] = _f_4;
    e.mem[_nd_4 + 1] = _f_5;
    e.mem[_nd_4 + 2] = _f_6;
    e.mem[_nd_4 + 3] = _f_7;
    r0 = term_clo(FID_MAIN_C25, _nd_4);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C25)
  {
    u32 _f_8 = r0;
    u32 _f_9 = r1;
    u32 _f_10 = r2;
    u32 _f_11 = r3;
    Term _x_4 = r4;
    WL_OPEN
    u64 _nd_5 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_5 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 4);
    u64 _nd_6 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_6 + 0] = _f_8;
    e.mem[_nd_6 + 1] = _f_9;
    e.mem[_nd_6 + 2] = _f_10;
    e.mem[_nd_6 + 3] = _f_11;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_188 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_188 + 0] = term_clo(FID_WIRE_BOXED_SWAP, _nd_5);
      e.mem[_t_188 + 1] = term_clo(FID_MAIN_C26, _nd_6);
      e.mem[_t_188 + 2] = _x_4;
      return term_tsk(FID_IO_BIND, _t_188);
    }
    r0 = term_clo(FID_WIRE_BOXED_SWAP, _nd_5);
    r1 = term_clo(FID_MAIN_C26, _nd_6);
    r2 = _x_4;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C26)
  {
    u32 _f_12 = r0;
    u32 _f_13 = r1;
    u32 _f_14 = r2;
    u32 _f_15 = r3;
    Term _x_5 = r4;
    WL_OPEN
    Term _fb_2[2];
    u64 _sp_2 = ctr_take(e, _x_5, 2, _fb_2);
    u32 _f_16 = _fb_2[0];
    u32 _f_17 = _fb_2[1];
    spare_free(e, cls_fit(2), _sp_2);
    u64 _nd_7 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_7 + 0] = _f_12;
    e.mem[_nd_7 + 1] = _f_13;
    e.mem[_nd_7 + 2] = _f_14;
    e.mem[_nd_7 + 3] = _f_15;
    e.mem[_nd_7 + 4] = _f_16;
    e.mem[_nd_7 + 5] = _f_17;
    r0 = term_clo(FID_MAIN_C27, _nd_7);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C27)
  {
    u32 _f_18 = r0;
    u32 _f_19 = r1;
    u32 _f_20 = r2;
    u32 _f_21 = r3;
    u32 _f_22 = r4;
    u32 _f_23 = r5;
    Term _x_6 = r6;
    WL_OPEN
    u64 _nd_8 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_8 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 4);
    u64 _nd_9 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_9 + 0] = _f_18;
    e.mem[_nd_9 + 1] = _f_19;
    e.mem[_nd_9 + 2] = _f_20;
    e.mem[_nd_9 + 3] = _f_21;
    e.mem[_nd_9 + 4] = _f_22;
    e.mem[_nd_9 + 5] = _f_23;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_187 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_187 + 0] = term_clo(FID_WIRE_BOXED_SAME, _nd_8);
      e.mem[_t_187 + 1] = term_clo(FID_MAIN_C28, _nd_9);
      e.mem[_t_187 + 2] = _x_6;
      return term_tsk(FID_IO_BIND, _t_187);
    }
    r0 = term_clo(FID_WIRE_BOXED_SAME, _nd_8);
    r1 = term_clo(FID_MAIN_C28, _nd_9);
    r2 = _x_6;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C28)
  {
    u32 _f_24 = r0;
    u32 _f_25 = r1;
    u32 _f_26 = r2;
    u32 _f_27 = r3;
    u32 _f_28 = r4;
    u32 _f_29 = r5;
    Term _x_7 = r6;
    WL_OPEN
    Term _fb_3[2];
    u64 _sp_3 = ctr_take(e, _x_7, 2, _fb_3);
    u32 _f_30 = _fb_3[0];
    u32 _f_31 = _fb_3[1];
    spare_free(e, cls_fit(2), _sp_3);
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_26;
      STK(1) = _f_27;
      STK(2) = _f_28;
      STK(3) = _f_29;
      STK(4) = _f_30;
      STK(5) = _f_31;
      STK(6) = FID_MAIN_K29;
      WL_PUSHN(7);
    } else {
      u64 _t_0 = task_node(e, FID_MAIN_K29, WL_CONT, WL_IDX, 1);
      e.mem[_t_0 + 0] = _f_26;
      e.mem[_t_0 + 1] = _f_27;
      e.mem[_t_0 + 2] = _f_28;
      e.mem[_t_0 + 3] = _f_29;
      e.mem[_t_0 + 4] = _f_30;
      e.mem[_t_0 + 5] = _f_31;
      WL_CONT = term_tsk(FID_MAIN_K29, _t_0);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_1 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_1 + 0] = _f_24;
      e.mem[_t_1 + 1] = _f_25;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_1);
    }
    r0 = _f_24;
    r1 = _f_25;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K29)
  {
    WL_POPN(6);
    u32 _f_32 = STK(0);
    u32 _f_33 = STK(1);
    u32 _f_34 = STK(2);
    u32 _f_35 = STK(3);
    u32 _f_36 = STK(4);
    u32 _f_37 = STK(5);
    Term _h_0 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_32;
      STK(1) = _f_33;
      STK(2) = _f_34;
      STK(3) = _f_35;
      STK(4) = _f_36;
      STK(5) = _f_37;
      STK(6) = FID_MAIN_K30;
      WL_PUSHN(7);
    } else {
      u64 _t_2 = task_node(e, FID_MAIN_K30, WL_CONT, WL_IDX, 1);
      e.mem[_t_2 + 0] = _f_32;
      e.mem[_t_2 + 1] = _f_33;
      e.mem[_t_2 + 2] = _f_34;
      e.mem[_t_2 + 3] = _f_35;
      e.mem[_t_2 + 4] = _f_36;
      e.mem[_t_2 + 5] = _f_37;
      WL_CONT = term_tsk(FID_MAIN_K30, _t_2);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_3 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_3 + 0] = term_ctr(CID_SCON, STAT_OFF + 36);
      e.mem[_t_3 + 1] = _h_0;
      return term_tsk(FID_STRING_APPEND, _t_3);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 36);
    r1 = _h_0;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K30)
  {
    WL_POPN(6);
    u32 _f_38 = STK(0);
    u32 _f_39 = STK(1);
    u32 _f_40 = STK(2);
    u32 _f_41 = STK(3);
    u32 _f_42 = STK(4);
    u32 _f_43 = STK(5);
    Term _h_1 = r0;
    WL_OPEN
    u64 _nd_10 = heap_alloc(e, cls_fit(7));
    e.mem[_nd_10 + 0] = _f_38;
    e.mem[_nd_10 + 1] = _f_39;
    e.mem[_nd_10 + 2] = _f_40;
    e.mem[_nd_10 + 3] = _f_41;
    e.mem[_nd_10 + 4] = _f_42;
    e.mem[_nd_10 + 5] = _f_43;
    e.mem[_nd_10 + 6] = _h_1;
    r0 = term_clo(FID_MAIN_C31, _nd_10);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C31)
  {
    u32 _f_44 = r0;
    u32 _f_45 = r1;
    u32 _f_46 = r2;
    u32 _f_47 = r3;
    u32 _f_48 = r4;
    u32 _f_49 = r5;
    Term _h_2 = r6;
    Term _x_8 = r7;
    WL_OPEN
    u64 _nd_11 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_11 + 0] = _h_2;
    u64 _nd_12 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_12 + 0] = _f_44;
    e.mem[_nd_12 + 1] = _f_45;
    e.mem[_nd_12 + 2] = _f_46;
    e.mem[_nd_12 + 3] = _f_47;
    e.mem[_nd_12 + 4] = _f_48;
    e.mem[_nd_12 + 5] = _f_49;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_186 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_186 + 0] = term_clo(FID_IO_PRINT, _nd_11);
      e.mem[_t_186 + 1] = term_clo(FID_MAIN_C32, _nd_12);
      e.mem[_t_186 + 2] = _x_8;
      return term_tsk(FID_IO_BIND, _t_186);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_11);
    r1 = term_clo(FID_MAIN_C32, _nd_12);
    r2 = _x_8;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C32)
  {
    u32 _f_50 = r0;
    u32 _f_51 = r1;
    u32 _f_52 = r2;
    u32 _f_53 = r3;
    u32 _f_54 = r4;
    u32 _f_55 = r5;
    Term _x_9 = r6;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_52;
      STK(1) = _f_53;
      STK(2) = _f_54;
      STK(3) = _f_55;
      STK(4) = FID_MAIN_K33;
      WL_PUSHN(5);
    } else {
      u64 _t_4 = task_node(e, FID_MAIN_K33, WL_CONT, WL_IDX, 1);
      e.mem[_t_4 + 0] = _f_52;
      e.mem[_t_4 + 1] = _f_53;
      e.mem[_t_4 + 2] = _f_54;
      e.mem[_t_4 + 3] = _f_55;
      WL_CONT = term_tsk(FID_MAIN_K33, _t_4);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_5 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_5 + 0] = _f_50;
      e.mem[_t_5 + 1] = _f_51;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_5);
    }
    r0 = _f_50;
    r1 = _f_51;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K33)
  {
    WL_POPN(4);
    u32 _f_56 = STK(0);
    u32 _f_57 = STK(1);
    u32 _f_58 = STK(2);
    u32 _f_59 = STK(3);
    Term _h_3 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_56;
      STK(1) = _f_57;
      STK(2) = _f_58;
      STK(3) = _f_59;
      STK(4) = FID_MAIN_K34;
      WL_PUSHN(5);
    } else {
      u64 _t_6 = task_node(e, FID_MAIN_K34, WL_CONT, WL_IDX, 1);
      e.mem[_t_6 + 0] = _f_56;
      e.mem[_t_6 + 1] = _f_57;
      e.mem[_t_6 + 2] = _f_58;
      e.mem[_t_6 + 3] = _f_59;
      WL_CONT = term_tsk(FID_MAIN_K34, _t_6);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_7 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_7 + 0] = term_ctr(CID_SCON, STAT_OFF + 56);
      e.mem[_t_7 + 1] = _h_3;
      return term_tsk(FID_STRING_APPEND, _t_7);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 56);
    r1 = _h_3;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K34)
  {
    WL_POPN(4);
    u32 _f_60 = STK(0);
    u32 _f_61 = STK(1);
    u32 _f_62 = STK(2);
    u32 _f_63 = STK(3);
    Term _h_4 = r0;
    WL_OPEN
    u64 _nd_13 = heap_alloc(e, cls_fit(5));
    e.mem[_nd_13 + 0] = _f_60;
    e.mem[_nd_13 + 1] = _f_61;
    e.mem[_nd_13 + 2] = _f_62;
    e.mem[_nd_13 + 3] = _f_63;
    e.mem[_nd_13 + 4] = _h_4;
    r0 = term_clo(FID_MAIN_C35, _nd_13);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C35)
  {
    u32 _f_64 = r0;
    u32 _f_65 = r1;
    u32 _f_66 = r2;
    u32 _f_67 = r3;
    Term _h_5 = r4;
    Term _x_10 = r5;
    WL_OPEN
    u64 _nd_14 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_14 + 0] = _h_5;
    u64 _nd_15 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_15 + 0] = _f_64;
    e.mem[_nd_15 + 1] = _f_65;
    e.mem[_nd_15 + 2] = _f_66;
    e.mem[_nd_15 + 3] = _f_67;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_185 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_185 + 0] = term_clo(FID_IO_PRINT, _nd_14);
      e.mem[_t_185 + 1] = term_clo(FID_MAIN_C36, _nd_15);
      e.mem[_t_185 + 2] = _x_10;
      return term_tsk(FID_IO_BIND, _t_185);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_14);
    r1 = term_clo(FID_MAIN_C36, _nd_15);
    r2 = _x_10;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C36)
  {
    u32 _f_68 = r0;
    u32 _f_69 = r1;
    u32 _f_70 = r2;
    u32 _f_71 = r3;
    Term _x_11 = r4;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_70;
      STK(1) = _f_71;
      STK(2) = FID_MAIN_K37;
      WL_PUSHN(3);
    } else {
      u64 _t_8 = task_node(e, FID_MAIN_K37, WL_CONT, WL_IDX, 1);
      e.mem[_t_8 + 0] = _f_70;
      e.mem[_t_8 + 1] = _f_71;
      WL_CONT = term_tsk(FID_MAIN_K37, _t_8);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_9 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_9 + 0] = _f_68;
      e.mem[_t_9 + 1] = _f_69;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_9);
    }
    r0 = _f_68;
    r1 = _f_69;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K37)
  {
    WL_POPN(2);
    u32 _f_72 = STK(0);
    u32 _f_73 = STK(1);
    Term _h_6 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_72;
      STK(1) = _f_73;
      STK(2) = FID_MAIN_K38;
      WL_PUSHN(3);
    } else {
      u64 _t_10 = task_node(e, FID_MAIN_K38, WL_CONT, WL_IDX, 1);
      e.mem[_t_10 + 0] = _f_72;
      e.mem[_t_10 + 1] = _f_73;
      WL_CONT = term_tsk(FID_MAIN_K38, _t_10);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_11 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_11 + 0] = term_ctr(CID_SCON, STAT_OFF + 74);
      e.mem[_t_11 + 1] = _h_6;
      return term_tsk(FID_STRING_APPEND, _t_11);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 74);
    r1 = _h_6;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K38)
  {
    WL_POPN(2);
    u32 _f_74 = STK(0);
    u32 _f_75 = STK(1);
    Term _h_7 = r0;
    WL_OPEN
    u64 _nd_16 = heap_alloc(e, cls_fit(3));
    e.mem[_nd_16 + 0] = _f_74;
    e.mem[_nd_16 + 1] = _f_75;
    e.mem[_nd_16 + 2] = _h_7;
    r0 = term_clo(FID_MAIN_C39, _nd_16);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C39)
  {
    u32 _f_76 = r0;
    u32 _f_77 = r1;
    Term _h_8 = r2;
    Term _x_12 = r3;
    WL_OPEN
    u64 _nd_17 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_17 + 0] = _h_8;
    u64 _nd_18 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_18 + 0] = _f_76;
    e.mem[_nd_18 + 1] = _f_77;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_184 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_184 + 0] = term_clo(FID_IO_PRINT, _nd_17);
      e.mem[_t_184 + 1] = term_clo(FID_MAIN_C40, _nd_18);
      e.mem[_t_184 + 2] = _x_12;
      return term_tsk(FID_IO_BIND, _t_184);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_17);
    r1 = term_clo(FID_MAIN_C40, _nd_18);
    r2 = _x_12;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C40)
  {
    u32 _f_78 = r0;
    u32 _f_79 = r1;
    Term _x_13 = r2;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K41;
      WL_PUSHN(1);
    } else {
      u64 _t_12 = task_node(e, FID_MAIN_K41, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K41, _t_12);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_13 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_13 + 0] = _f_78;
      e.mem[_t_13 + 1] = _f_79;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_13);
    }
    r0 = _f_78;
    r1 = _f_79;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
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
      e.mem[_t_15 + 0] = term_ctr(CID_SCON, STAT_OFF + 92);
      e.mem[_t_15 + 1] = _h_9;
      return term_tsk(FID_STRING_APPEND, _t_15);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 92);
    r1 = _h_9;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K42)
  {
    Term _h_10 = r0;
    WL_OPEN
    u64 _nd_19 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_19 + 0] = _h_10;
    r0 = term_clo(FID_MAIN_C43, _nd_19);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C43)
  {
    Term _h_11 = r0;
    Term _x_14 = r1;
    WL_OPEN
    u64 _nd_20 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_20 + 0] = _h_11;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_183 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_183 + 0] = term_clo(FID_IO_PRINT, _nd_20);
      e.mem[_t_183 + 1] = term_clo(FID_MAIN_C44, 0);
      e.mem[_t_183 + 2] = _x_14;
      return term_tsk(FID_IO_BIND, _t_183);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_20);
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
    u64 _nd_21 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_21 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 94);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_182 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_182 + 0] = term_clo(FID_WIRE_FLAT, _nd_21);
      e.mem[_t_182 + 1] = term_clo(FID_MAIN_C46, 0);
      e.mem[_t_182 + 2] = _x_16;
      return term_tsk(FID_IO_BIND, _t_182);
    }
    r0 = term_clo(FID_WIRE_FLAT, _nd_21);
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
    u32 _f_80 = _fb_4[0];
    u32 _f_81 = _fb_4[1];
    spare_free(e, cls_fit(2), _sp_4);
    u64 _nd_22 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_22 + 0] = _f_80;
    e.mem[_nd_22 + 1] = _f_81;
    r0 = term_clo(FID_MAIN_C47, _nd_22);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C47)
  {
    u32 _f_82 = r0;
    u32 _f_83 = r1;
    Term _x_18 = r2;
    WL_OPEN
    u64 _nd_23 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_23 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 94);
    u64 _nd_24 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_24 + 0] = _f_82;
    e.mem[_nd_24 + 1] = _f_83;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_181 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_181 + 0] = term_clo(FID_WIRE_BOXED, _nd_23);
      e.mem[_t_181 + 1] = term_clo(FID_MAIN_C48, _nd_24);
      e.mem[_t_181 + 2] = _x_18;
      return term_tsk(FID_IO_BIND, _t_181);
    }
    r0 = term_clo(FID_WIRE_BOXED, _nd_23);
    r1 = term_clo(FID_MAIN_C48, _nd_24);
    r2 = _x_18;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C48)
  {
    u32 _f_84 = r0;
    u32 _f_85 = r1;
    Term _x_19 = r2;
    WL_OPEN
    Term _fb_5[2];
    u64 _sp_5 = ctr_take(e, _x_19, 2, _fb_5);
    u32 _f_86 = _fb_5[0];
    u32 _f_87 = _fb_5[1];
    spare_free(e, cls_fit(2), _sp_5);
    u64 _nd_25 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_25 + 0] = _f_84;
    e.mem[_nd_25 + 1] = _f_85;
    e.mem[_nd_25 + 2] = _f_86;
    e.mem[_nd_25 + 3] = _f_87;
    r0 = term_clo(FID_MAIN_C49, _nd_25);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C49)
  {
    u32 _f_88 = r0;
    u32 _f_89 = r1;
    u32 _f_90 = r2;
    u32 _f_91 = r3;
    Term _x_20 = r4;
    WL_OPEN
    u64 _nd_26 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_26 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 94);
    u64 _nd_27 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_27 + 0] = _f_88;
    e.mem[_nd_27 + 1] = _f_89;
    e.mem[_nd_27 + 2] = _f_90;
    e.mem[_nd_27 + 3] = _f_91;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_180 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_180 + 0] = term_clo(FID_WIRE_BOXED_SWAP, _nd_26);
      e.mem[_t_180 + 1] = term_clo(FID_MAIN_C50, _nd_27);
      e.mem[_t_180 + 2] = _x_20;
      return term_tsk(FID_IO_BIND, _t_180);
    }
    r0 = term_clo(FID_WIRE_BOXED_SWAP, _nd_26);
    r1 = term_clo(FID_MAIN_C50, _nd_27);
    r2 = _x_20;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C50)
  {
    u32 _f_92 = r0;
    u32 _f_93 = r1;
    u32 _f_94 = r2;
    u32 _f_95 = r3;
    Term _x_21 = r4;
    WL_OPEN
    Term _fb_6[2];
    u64 _sp_6 = ctr_take(e, _x_21, 2, _fb_6);
    u32 _f_96 = _fb_6[0];
    u32 _f_97 = _fb_6[1];
    spare_free(e, cls_fit(2), _sp_6);
    u64 _nd_28 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_28 + 0] = _f_92;
    e.mem[_nd_28 + 1] = _f_93;
    e.mem[_nd_28 + 2] = _f_94;
    e.mem[_nd_28 + 3] = _f_95;
    e.mem[_nd_28 + 4] = _f_96;
    e.mem[_nd_28 + 5] = _f_97;
    r0 = term_clo(FID_MAIN_C51, _nd_28);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C51)
  {
    u32 _f_98 = r0;
    u32 _f_99 = r1;
    u32 _f_100 = r2;
    u32 _f_101 = r3;
    u32 _f_102 = r4;
    u32 _f_103 = r5;
    Term _x_22 = r6;
    WL_OPEN
    u64 _nd_29 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_29 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 94);
    u64 _nd_30 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_30 + 0] = _f_98;
    e.mem[_nd_30 + 1] = _f_99;
    e.mem[_nd_30 + 2] = _f_100;
    e.mem[_nd_30 + 3] = _f_101;
    e.mem[_nd_30 + 4] = _f_102;
    e.mem[_nd_30 + 5] = _f_103;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_179 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_179 + 0] = term_clo(FID_WIRE_BOXED_SAME, _nd_29);
      e.mem[_t_179 + 1] = term_clo(FID_MAIN_C52, _nd_30);
      e.mem[_t_179 + 2] = _x_22;
      return term_tsk(FID_IO_BIND, _t_179);
    }
    r0 = term_clo(FID_WIRE_BOXED_SAME, _nd_29);
    r1 = term_clo(FID_MAIN_C52, _nd_30);
    r2 = _x_22;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C52)
  {
    u32 _f_104 = r0;
    u32 _f_105 = r1;
    u32 _f_106 = r2;
    u32 _f_107 = r3;
    u32 _f_108 = r4;
    u32 _f_109 = r5;
    Term _x_23 = r6;
    WL_OPEN
    Term _fb_7[2];
    u64 _sp_7 = ctr_take(e, _x_23, 2, _fb_7);
    u32 _f_110 = _fb_7[0];
    u32 _f_111 = _fb_7[1];
    spare_free(e, cls_fit(2), _sp_7);
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_106;
      STK(1) = _f_107;
      STK(2) = _f_108;
      STK(3) = _f_109;
      STK(4) = _f_110;
      STK(5) = _f_111;
      STK(6) = FID_MAIN_K53;
      WL_PUSHN(7);
    } else {
      u64 _t_16 = task_node(e, FID_MAIN_K53, WL_CONT, WL_IDX, 1);
      e.mem[_t_16 + 0] = _f_106;
      e.mem[_t_16 + 1] = _f_107;
      e.mem[_t_16 + 2] = _f_108;
      e.mem[_t_16 + 3] = _f_109;
      e.mem[_t_16 + 4] = _f_110;
      e.mem[_t_16 + 5] = _f_111;
      WL_CONT = term_tsk(FID_MAIN_K53, _t_16);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_17 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_17 + 0] = _f_104;
      e.mem[_t_17 + 1] = _f_105;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_17);
    }
    r0 = _f_104;
    r1 = _f_105;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K53)
  {
    WL_POPN(6);
    u32 _f_112 = STK(0);
    u32 _f_113 = STK(1);
    u32 _f_114 = STK(2);
    u32 _f_115 = STK(3);
    u32 _f_116 = STK(4);
    u32 _f_117 = STK(5);
    Term _h_12 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_112;
      STK(1) = _f_113;
      STK(2) = _f_114;
      STK(3) = _f_115;
      STK(4) = _f_116;
      STK(5) = _f_117;
      STK(6) = FID_MAIN_K54;
      WL_PUSHN(7);
    } else {
      u64 _t_18 = task_node(e, FID_MAIN_K54, WL_CONT, WL_IDX, 1);
      e.mem[_t_18 + 0] = _f_112;
      e.mem[_t_18 + 1] = _f_113;
      e.mem[_t_18 + 2] = _f_114;
      e.mem[_t_18 + 3] = _f_115;
      e.mem[_t_18 + 4] = _f_116;
      e.mem[_t_18 + 5] = _f_117;
      WL_CONT = term_tsk(FID_MAIN_K54, _t_18);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_19 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_19 + 0] = term_ctr(CID_SCON, STAT_OFF + 140);
      e.mem[_t_19 + 1] = _h_12;
      return term_tsk(FID_STRING_APPEND, _t_19);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 140);
    r1 = _h_12;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K54)
  {
    WL_POPN(6);
    u32 _f_118 = STK(0);
    u32 _f_119 = STK(1);
    u32 _f_120 = STK(2);
    u32 _f_121 = STK(3);
    u32 _f_122 = STK(4);
    u32 _f_123 = STK(5);
    Term _h_13 = r0;
    WL_OPEN
    u64 _nd_31 = heap_alloc(e, cls_fit(7));
    e.mem[_nd_31 + 0] = _f_118;
    e.mem[_nd_31 + 1] = _f_119;
    e.mem[_nd_31 + 2] = _f_120;
    e.mem[_nd_31 + 3] = _f_121;
    e.mem[_nd_31 + 4] = _f_122;
    e.mem[_nd_31 + 5] = _f_123;
    e.mem[_nd_31 + 6] = _h_13;
    r0 = term_clo(FID_MAIN_C55, _nd_31);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C55)
  {
    u32 _f_124 = r0;
    u32 _f_125 = r1;
    u32 _f_126 = r2;
    u32 _f_127 = r3;
    u32 _f_128 = r4;
    u32 _f_129 = r5;
    Term _h_14 = r6;
    Term _x_24 = r7;
    WL_OPEN
    u64 _nd_32 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_32 + 0] = _h_14;
    u64 _nd_33 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_33 + 0] = _f_124;
    e.mem[_nd_33 + 1] = _f_125;
    e.mem[_nd_33 + 2] = _f_126;
    e.mem[_nd_33 + 3] = _f_127;
    e.mem[_nd_33 + 4] = _f_128;
    e.mem[_nd_33 + 5] = _f_129;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_178 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_178 + 0] = term_clo(FID_IO_PRINT, _nd_32);
      e.mem[_t_178 + 1] = term_clo(FID_MAIN_C56, _nd_33);
      e.mem[_t_178 + 2] = _x_24;
      return term_tsk(FID_IO_BIND, _t_178);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_32);
    r1 = term_clo(FID_MAIN_C56, _nd_33);
    r2 = _x_24;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C56)
  {
    u32 _f_130 = r0;
    u32 _f_131 = r1;
    u32 _f_132 = r2;
    u32 _f_133 = r3;
    u32 _f_134 = r4;
    u32 _f_135 = r5;
    Term _x_25 = r6;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_132;
      STK(1) = _f_133;
      STK(2) = _f_134;
      STK(3) = _f_135;
      STK(4) = FID_MAIN_K57;
      WL_PUSHN(5);
    } else {
      u64 _t_20 = task_node(e, FID_MAIN_K57, WL_CONT, WL_IDX, 1);
      e.mem[_t_20 + 0] = _f_132;
      e.mem[_t_20 + 1] = _f_133;
      e.mem[_t_20 + 2] = _f_134;
      e.mem[_t_20 + 3] = _f_135;
      WL_CONT = term_tsk(FID_MAIN_K57, _t_20);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_21 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_21 + 0] = _f_130;
      e.mem[_t_21 + 1] = _f_131;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_21);
    }
    r0 = _f_130;
    r1 = _f_131;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K57)
  {
    WL_POPN(4);
    u32 _f_136 = STK(0);
    u32 _f_137 = STK(1);
    u32 _f_138 = STK(2);
    u32 _f_139 = STK(3);
    Term _h_15 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_136;
      STK(1) = _f_137;
      STK(2) = _f_138;
      STK(3) = _f_139;
      STK(4) = FID_MAIN_K58;
      WL_PUSHN(5);
    } else {
      u64 _t_22 = task_node(e, FID_MAIN_K58, WL_CONT, WL_IDX, 1);
      e.mem[_t_22 + 0] = _f_136;
      e.mem[_t_22 + 1] = _f_137;
      e.mem[_t_22 + 2] = _f_138;
      e.mem[_t_22 + 3] = _f_139;
      WL_CONT = term_tsk(FID_MAIN_K58, _t_22);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_23 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_23 + 0] = term_ctr(CID_SCON, STAT_OFF + 160);
      e.mem[_t_23 + 1] = _h_15;
      return term_tsk(FID_STRING_APPEND, _t_23);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 160);
    r1 = _h_15;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K58)
  {
    WL_POPN(4);
    u32 _f_140 = STK(0);
    u32 _f_141 = STK(1);
    u32 _f_142 = STK(2);
    u32 _f_143 = STK(3);
    Term _h_16 = r0;
    WL_OPEN
    u64 _nd_34 = heap_alloc(e, cls_fit(5));
    e.mem[_nd_34 + 0] = _f_140;
    e.mem[_nd_34 + 1] = _f_141;
    e.mem[_nd_34 + 2] = _f_142;
    e.mem[_nd_34 + 3] = _f_143;
    e.mem[_nd_34 + 4] = _h_16;
    r0 = term_clo(FID_MAIN_C59, _nd_34);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C59)
  {
    u32 _f_144 = r0;
    u32 _f_145 = r1;
    u32 _f_146 = r2;
    u32 _f_147 = r3;
    Term _h_17 = r4;
    Term _x_26 = r5;
    WL_OPEN
    u64 _nd_35 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_35 + 0] = _h_17;
    u64 _nd_36 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_36 + 0] = _f_144;
    e.mem[_nd_36 + 1] = _f_145;
    e.mem[_nd_36 + 2] = _f_146;
    e.mem[_nd_36 + 3] = _f_147;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_177 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_177 + 0] = term_clo(FID_IO_PRINT, _nd_35);
      e.mem[_t_177 + 1] = term_clo(FID_MAIN_C60, _nd_36);
      e.mem[_t_177 + 2] = _x_26;
      return term_tsk(FID_IO_BIND, _t_177);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_35);
    r1 = term_clo(FID_MAIN_C60, _nd_36);
    r2 = _x_26;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C60)
  {
    u32 _f_148 = r0;
    u32 _f_149 = r1;
    u32 _f_150 = r2;
    u32 _f_151 = r3;
    Term _x_27 = r4;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_150;
      STK(1) = _f_151;
      STK(2) = FID_MAIN_K61;
      WL_PUSHN(3);
    } else {
      u64 _t_24 = task_node(e, FID_MAIN_K61, WL_CONT, WL_IDX, 1);
      e.mem[_t_24 + 0] = _f_150;
      e.mem[_t_24 + 1] = _f_151;
      WL_CONT = term_tsk(FID_MAIN_K61, _t_24);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_25 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_25 + 0] = _f_148;
      e.mem[_t_25 + 1] = _f_149;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_25);
    }
    r0 = _f_148;
    r1 = _f_149;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K61)
  {
    WL_POPN(2);
    u32 _f_152 = STK(0);
    u32 _f_153 = STK(1);
    Term _h_18 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_152;
      STK(1) = _f_153;
      STK(2) = FID_MAIN_K62;
      WL_PUSHN(3);
    } else {
      u64 _t_26 = task_node(e, FID_MAIN_K62, WL_CONT, WL_IDX, 1);
      e.mem[_t_26 + 0] = _f_152;
      e.mem[_t_26 + 1] = _f_153;
      WL_CONT = term_tsk(FID_MAIN_K62, _t_26);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_27 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_27 + 0] = term_ctr(CID_SCON, STAT_OFF + 178);
      e.mem[_t_27 + 1] = _h_18;
      return term_tsk(FID_STRING_APPEND, _t_27);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 178);
    r1 = _h_18;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K62)
  {
    WL_POPN(2);
    u32 _f_154 = STK(0);
    u32 _f_155 = STK(1);
    Term _h_19 = r0;
    WL_OPEN
    u64 _nd_37 = heap_alloc(e, cls_fit(3));
    e.mem[_nd_37 + 0] = _f_154;
    e.mem[_nd_37 + 1] = _f_155;
    e.mem[_nd_37 + 2] = _h_19;
    r0 = term_clo(FID_MAIN_C63, _nd_37);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C63)
  {
    u32 _f_156 = r0;
    u32 _f_157 = r1;
    Term _h_20 = r2;
    Term _x_28 = r3;
    WL_OPEN
    u64 _nd_38 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_38 + 0] = _h_20;
    u64 _nd_39 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_39 + 0] = _f_156;
    e.mem[_nd_39 + 1] = _f_157;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_176 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_176 + 0] = term_clo(FID_IO_PRINT, _nd_38);
      e.mem[_t_176 + 1] = term_clo(FID_MAIN_C64, _nd_39);
      e.mem[_t_176 + 2] = _x_28;
      return term_tsk(FID_IO_BIND, _t_176);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_38);
    r1 = term_clo(FID_MAIN_C64, _nd_39);
    r2 = _x_28;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C64)
  {
    u32 _f_158 = r0;
    u32 _f_159 = r1;
    Term _x_29 = r2;
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
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_29 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_29 + 0] = _f_158;
      e.mem[_t_29 + 1] = _f_159;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_29);
    }
    r0 = _f_158;
    r1 = _f_159;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K65)
  {
    Term _h_21 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K66;
      WL_PUSHN(1);
    } else {
      u64 _t_30 = task_node(e, FID_MAIN_K66, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K66, _t_30);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_31 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_31 + 0] = term_ctr(CID_SCON, STAT_OFF + 196);
      e.mem[_t_31 + 1] = _h_21;
      return term_tsk(FID_STRING_APPEND, _t_31);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 196);
    r1 = _h_21;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K66)
  {
    Term _h_22 = r0;
    WL_OPEN
    u64 _nd_40 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_40 + 0] = _h_22;
    r0 = term_clo(FID_MAIN_C67, _nd_40);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C67)
  {
    Term _h_23 = r0;
    Term _x_30 = r1;
    WL_OPEN
    u64 _nd_41 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_41 + 0] = _h_23;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_175 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_175 + 0] = term_clo(FID_IO_PRINT, _nd_41);
      e.mem[_t_175 + 1] = term_clo(FID_MAIN_C68, 0);
      e.mem[_t_175 + 2] = _x_30;
      return term_tsk(FID_IO_BIND, _t_175);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_41);
    r1 = term_clo(FID_MAIN_C68, 0);
    r2 = _x_30;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C68)
  {
    Term _x_31 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C69, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C69)
  {
    Term _x_32 = r0;
    WL_OPEN
    u64 _nd_42 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_42 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 198);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_174 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_174 + 0] = term_clo(FID_WIRE_FLAT, _nd_42);
      e.mem[_t_174 + 1] = term_clo(FID_MAIN_C70, 0);
      e.mem[_t_174 + 2] = _x_32;
      return term_tsk(FID_IO_BIND, _t_174);
    }
    r0 = term_clo(FID_WIRE_FLAT, _nd_42);
    r1 = term_clo(FID_MAIN_C70, 0);
    r2 = _x_32;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C70)
  {
    Term _x_33 = r0;
    WL_OPEN
    Term _fb_8[2];
    u64 _sp_8 = ctr_take(e, _x_33, 2, _fb_8);
    u32 _f_160 = _fb_8[0];
    u32 _f_161 = _fb_8[1];
    spare_free(e, cls_fit(2), _sp_8);
    u64 _nd_43 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_43 + 0] = _f_160;
    e.mem[_nd_43 + 1] = _f_161;
    r0 = term_clo(FID_MAIN_C71, _nd_43);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C71)
  {
    u32 _f_162 = r0;
    u32 _f_163 = r1;
    Term _x_34 = r2;
    WL_OPEN
    u64 _nd_44 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_44 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 198);
    u64 _nd_45 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_45 + 0] = _f_162;
    e.mem[_nd_45 + 1] = _f_163;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_173 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_173 + 0] = term_clo(FID_WIRE_BOXED, _nd_44);
      e.mem[_t_173 + 1] = term_clo(FID_MAIN_C72, _nd_45);
      e.mem[_t_173 + 2] = _x_34;
      return term_tsk(FID_IO_BIND, _t_173);
    }
    r0 = term_clo(FID_WIRE_BOXED, _nd_44);
    r1 = term_clo(FID_MAIN_C72, _nd_45);
    r2 = _x_34;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C72)
  {
    u32 _f_164 = r0;
    u32 _f_165 = r1;
    Term _x_35 = r2;
    WL_OPEN
    Term _fb_9[2];
    u64 _sp_9 = ctr_take(e, _x_35, 2, _fb_9);
    u32 _f_166 = _fb_9[0];
    u32 _f_167 = _fb_9[1];
    spare_free(e, cls_fit(2), _sp_9);
    u64 _nd_46 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_46 + 0] = _f_164;
    e.mem[_nd_46 + 1] = _f_165;
    e.mem[_nd_46 + 2] = _f_166;
    e.mem[_nd_46 + 3] = _f_167;
    r0 = term_clo(FID_MAIN_C73, _nd_46);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C73)
  {
    u32 _f_168 = r0;
    u32 _f_169 = r1;
    u32 _f_170 = r2;
    u32 _f_171 = r3;
    Term _x_36 = r4;
    WL_OPEN
    u64 _nd_47 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_47 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 198);
    u64 _nd_48 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_48 + 0] = _f_168;
    e.mem[_nd_48 + 1] = _f_169;
    e.mem[_nd_48 + 2] = _f_170;
    e.mem[_nd_48 + 3] = _f_171;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_172 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_172 + 0] = term_clo(FID_WIRE_BOXED_SWAP, _nd_47);
      e.mem[_t_172 + 1] = term_clo(FID_MAIN_C74, _nd_48);
      e.mem[_t_172 + 2] = _x_36;
      return term_tsk(FID_IO_BIND, _t_172);
    }
    r0 = term_clo(FID_WIRE_BOXED_SWAP, _nd_47);
    r1 = term_clo(FID_MAIN_C74, _nd_48);
    r2 = _x_36;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C74)
  {
    u32 _f_172 = r0;
    u32 _f_173 = r1;
    u32 _f_174 = r2;
    u32 _f_175 = r3;
    Term _x_37 = r4;
    WL_OPEN
    Term _fb_10[2];
    u64 _sp_10 = ctr_take(e, _x_37, 2, _fb_10);
    u32 _f_176 = _fb_10[0];
    u32 _f_177 = _fb_10[1];
    spare_free(e, cls_fit(2), _sp_10);
    u64 _nd_49 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_49 + 0] = _f_172;
    e.mem[_nd_49 + 1] = _f_173;
    e.mem[_nd_49 + 2] = _f_174;
    e.mem[_nd_49 + 3] = _f_175;
    e.mem[_nd_49 + 4] = _f_176;
    e.mem[_nd_49 + 5] = _f_177;
    r0 = term_clo(FID_MAIN_C75, _nd_49);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C75)
  {
    u32 _f_178 = r0;
    u32 _f_179 = r1;
    u32 _f_180 = r2;
    u32 _f_181 = r3;
    u32 _f_182 = r4;
    u32 _f_183 = r5;
    Term _x_38 = r6;
    WL_OPEN
    u64 _nd_50 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_50 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 198);
    u64 _nd_51 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_51 + 0] = _f_178;
    e.mem[_nd_51 + 1] = _f_179;
    e.mem[_nd_51 + 2] = _f_180;
    e.mem[_nd_51 + 3] = _f_181;
    e.mem[_nd_51 + 4] = _f_182;
    e.mem[_nd_51 + 5] = _f_183;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_171 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_171 + 0] = term_clo(FID_WIRE_BOXED_SAME, _nd_50);
      e.mem[_t_171 + 1] = term_clo(FID_MAIN_C76, _nd_51);
      e.mem[_t_171 + 2] = _x_38;
      return term_tsk(FID_IO_BIND, _t_171);
    }
    r0 = term_clo(FID_WIRE_BOXED_SAME, _nd_50);
    r1 = term_clo(FID_MAIN_C76, _nd_51);
    r2 = _x_38;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C76)
  {
    u32 _f_184 = r0;
    u32 _f_185 = r1;
    u32 _f_186 = r2;
    u32 _f_187 = r3;
    u32 _f_188 = r4;
    u32 _f_189 = r5;
    Term _x_39 = r6;
    WL_OPEN
    Term _fb_11[2];
    u64 _sp_11 = ctr_take(e, _x_39, 2, _fb_11);
    u32 _f_190 = _fb_11[0];
    u32 _f_191 = _fb_11[1];
    spare_free(e, cls_fit(2), _sp_11);
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_186;
      STK(1) = _f_187;
      STK(2) = _f_188;
      STK(3) = _f_189;
      STK(4) = _f_190;
      STK(5) = _f_191;
      STK(6) = FID_MAIN_K77;
      WL_PUSHN(7);
    } else {
      u64 _t_32 = task_node(e, FID_MAIN_K77, WL_CONT, WL_IDX, 1);
      e.mem[_t_32 + 0] = _f_186;
      e.mem[_t_32 + 1] = _f_187;
      e.mem[_t_32 + 2] = _f_188;
      e.mem[_t_32 + 3] = _f_189;
      e.mem[_t_32 + 4] = _f_190;
      e.mem[_t_32 + 5] = _f_191;
      WL_CONT = term_tsk(FID_MAIN_K77, _t_32);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_33 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_33 + 0] = _f_184;
      e.mem[_t_33 + 1] = _f_185;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_33);
    }
    r0 = _f_184;
    r1 = _f_185;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K77)
  {
    WL_POPN(6);
    u32 _f_192 = STK(0);
    u32 _f_193 = STK(1);
    u32 _f_194 = STK(2);
    u32 _f_195 = STK(3);
    u32 _f_196 = STK(4);
    u32 _f_197 = STK(5);
    Term _h_24 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_192;
      STK(1) = _f_193;
      STK(2) = _f_194;
      STK(3) = _f_195;
      STK(4) = _f_196;
      STK(5) = _f_197;
      STK(6) = FID_MAIN_K78;
      WL_PUSHN(7);
    } else {
      u64 _t_34 = task_node(e, FID_MAIN_K78, WL_CONT, WL_IDX, 1);
      e.mem[_t_34 + 0] = _f_192;
      e.mem[_t_34 + 1] = _f_193;
      e.mem[_t_34 + 2] = _f_194;
      e.mem[_t_34 + 3] = _f_195;
      e.mem[_t_34 + 4] = _f_196;
      e.mem[_t_34 + 5] = _f_197;
      WL_CONT = term_tsk(FID_MAIN_K78, _t_34);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_35 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_35 + 0] = term_ctr(CID_SCON, STAT_OFF + 224);
      e.mem[_t_35 + 1] = _h_24;
      return term_tsk(FID_STRING_APPEND, _t_35);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 224);
    r1 = _h_24;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K78)
  {
    WL_POPN(6);
    u32 _f_198 = STK(0);
    u32 _f_199 = STK(1);
    u32 _f_200 = STK(2);
    u32 _f_201 = STK(3);
    u32 _f_202 = STK(4);
    u32 _f_203 = STK(5);
    Term _h_25 = r0;
    WL_OPEN
    u64 _nd_52 = heap_alloc(e, cls_fit(7));
    e.mem[_nd_52 + 0] = _f_198;
    e.mem[_nd_52 + 1] = _f_199;
    e.mem[_nd_52 + 2] = _f_200;
    e.mem[_nd_52 + 3] = _f_201;
    e.mem[_nd_52 + 4] = _f_202;
    e.mem[_nd_52 + 5] = _f_203;
    e.mem[_nd_52 + 6] = _h_25;
    r0 = term_clo(FID_MAIN_C79, _nd_52);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C79)
  {
    u32 _f_204 = r0;
    u32 _f_205 = r1;
    u32 _f_206 = r2;
    u32 _f_207 = r3;
    u32 _f_208 = r4;
    u32 _f_209 = r5;
    Term _h_26 = r6;
    Term _x_40 = r7;
    WL_OPEN
    u64 _nd_53 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_53 + 0] = _h_26;
    u64 _nd_54 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_54 + 0] = _f_204;
    e.mem[_nd_54 + 1] = _f_205;
    e.mem[_nd_54 + 2] = _f_206;
    e.mem[_nd_54 + 3] = _f_207;
    e.mem[_nd_54 + 4] = _f_208;
    e.mem[_nd_54 + 5] = _f_209;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_170 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_170 + 0] = term_clo(FID_IO_PRINT, _nd_53);
      e.mem[_t_170 + 1] = term_clo(FID_MAIN_C80, _nd_54);
      e.mem[_t_170 + 2] = _x_40;
      return term_tsk(FID_IO_BIND, _t_170);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_53);
    r1 = term_clo(FID_MAIN_C80, _nd_54);
    r2 = _x_40;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C80)
  {
    u32 _f_210 = r0;
    u32 _f_211 = r1;
    u32 _f_212 = r2;
    u32 _f_213 = r3;
    u32 _f_214 = r4;
    u32 _f_215 = r5;
    Term _x_41 = r6;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_212;
      STK(1) = _f_213;
      STK(2) = _f_214;
      STK(3) = _f_215;
      STK(4) = FID_MAIN_K81;
      WL_PUSHN(5);
    } else {
      u64 _t_36 = task_node(e, FID_MAIN_K81, WL_CONT, WL_IDX, 1);
      e.mem[_t_36 + 0] = _f_212;
      e.mem[_t_36 + 1] = _f_213;
      e.mem[_t_36 + 2] = _f_214;
      e.mem[_t_36 + 3] = _f_215;
      WL_CONT = term_tsk(FID_MAIN_K81, _t_36);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_37 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_37 + 0] = _f_210;
      e.mem[_t_37 + 1] = _f_211;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_37);
    }
    r0 = _f_210;
    r1 = _f_211;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K81)
  {
    WL_POPN(4);
    u32 _f_216 = STK(0);
    u32 _f_217 = STK(1);
    u32 _f_218 = STK(2);
    u32 _f_219 = STK(3);
    Term _h_27 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_216;
      STK(1) = _f_217;
      STK(2) = _f_218;
      STK(3) = _f_219;
      STK(4) = FID_MAIN_K82;
      WL_PUSHN(5);
    } else {
      u64 _t_38 = task_node(e, FID_MAIN_K82, WL_CONT, WL_IDX, 1);
      e.mem[_t_38 + 0] = _f_216;
      e.mem[_t_38 + 1] = _f_217;
      e.mem[_t_38 + 2] = _f_218;
      e.mem[_t_38 + 3] = _f_219;
      WL_CONT = term_tsk(FID_MAIN_K82, _t_38);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_39 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_39 + 0] = term_ctr(CID_SCON, STAT_OFF + 244);
      e.mem[_t_39 + 1] = _h_27;
      return term_tsk(FID_STRING_APPEND, _t_39);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 244);
    r1 = _h_27;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K82)
  {
    WL_POPN(4);
    u32 _f_220 = STK(0);
    u32 _f_221 = STK(1);
    u32 _f_222 = STK(2);
    u32 _f_223 = STK(3);
    Term _h_28 = r0;
    WL_OPEN
    u64 _nd_55 = heap_alloc(e, cls_fit(5));
    e.mem[_nd_55 + 0] = _f_220;
    e.mem[_nd_55 + 1] = _f_221;
    e.mem[_nd_55 + 2] = _f_222;
    e.mem[_nd_55 + 3] = _f_223;
    e.mem[_nd_55 + 4] = _h_28;
    r0 = term_clo(FID_MAIN_C83, _nd_55);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C83)
  {
    u32 _f_224 = r0;
    u32 _f_225 = r1;
    u32 _f_226 = r2;
    u32 _f_227 = r3;
    Term _h_29 = r4;
    Term _x_42 = r5;
    WL_OPEN
    u64 _nd_56 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_56 + 0] = _h_29;
    u64 _nd_57 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_57 + 0] = _f_224;
    e.mem[_nd_57 + 1] = _f_225;
    e.mem[_nd_57 + 2] = _f_226;
    e.mem[_nd_57 + 3] = _f_227;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_169 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_169 + 0] = term_clo(FID_IO_PRINT, _nd_56);
      e.mem[_t_169 + 1] = term_clo(FID_MAIN_C84, _nd_57);
      e.mem[_t_169 + 2] = _x_42;
      return term_tsk(FID_IO_BIND, _t_169);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_56);
    r1 = term_clo(FID_MAIN_C84, _nd_57);
    r2 = _x_42;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C84)
  {
    u32 _f_228 = r0;
    u32 _f_229 = r1;
    u32 _f_230 = r2;
    u32 _f_231 = r3;
    Term _x_43 = r4;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_230;
      STK(1) = _f_231;
      STK(2) = FID_MAIN_K85;
      WL_PUSHN(3);
    } else {
      u64 _t_40 = task_node(e, FID_MAIN_K85, WL_CONT, WL_IDX, 1);
      e.mem[_t_40 + 0] = _f_230;
      e.mem[_t_40 + 1] = _f_231;
      WL_CONT = term_tsk(FID_MAIN_K85, _t_40);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_41 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_41 + 0] = _f_228;
      e.mem[_t_41 + 1] = _f_229;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_41);
    }
    r0 = _f_228;
    r1 = _f_229;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K85)
  {
    WL_POPN(2);
    u32 _f_232 = STK(0);
    u32 _f_233 = STK(1);
    Term _h_30 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_232;
      STK(1) = _f_233;
      STK(2) = FID_MAIN_K86;
      WL_PUSHN(3);
    } else {
      u64 _t_42 = task_node(e, FID_MAIN_K86, WL_CONT, WL_IDX, 1);
      e.mem[_t_42 + 0] = _f_232;
      e.mem[_t_42 + 1] = _f_233;
      WL_CONT = term_tsk(FID_MAIN_K86, _t_42);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_43 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_43 + 0] = term_ctr(CID_SCON, STAT_OFF + 262);
      e.mem[_t_43 + 1] = _h_30;
      return term_tsk(FID_STRING_APPEND, _t_43);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 262);
    r1 = _h_30;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K86)
  {
    WL_POPN(2);
    u32 _f_234 = STK(0);
    u32 _f_235 = STK(1);
    Term _h_31 = r0;
    WL_OPEN
    u64 _nd_58 = heap_alloc(e, cls_fit(3));
    e.mem[_nd_58 + 0] = _f_234;
    e.mem[_nd_58 + 1] = _f_235;
    e.mem[_nd_58 + 2] = _h_31;
    r0 = term_clo(FID_MAIN_C87, _nd_58);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C87)
  {
    u32 _f_236 = r0;
    u32 _f_237 = r1;
    Term _h_32 = r2;
    Term _x_44 = r3;
    WL_OPEN
    u64 _nd_59 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_59 + 0] = _h_32;
    u64 _nd_60 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_60 + 0] = _f_236;
    e.mem[_nd_60 + 1] = _f_237;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_168 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_168 + 0] = term_clo(FID_IO_PRINT, _nd_59);
      e.mem[_t_168 + 1] = term_clo(FID_MAIN_C88, _nd_60);
      e.mem[_t_168 + 2] = _x_44;
      return term_tsk(FID_IO_BIND, _t_168);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_59);
    r1 = term_clo(FID_MAIN_C88, _nd_60);
    r2 = _x_44;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C88)
  {
    u32 _f_238 = r0;
    u32 _f_239 = r1;
    Term _x_45 = r2;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K89;
      WL_PUSHN(1);
    } else {
      u64 _t_44 = task_node(e, FID_MAIN_K89, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K89, _t_44);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_45 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_45 + 0] = _f_238;
      e.mem[_t_45 + 1] = _f_239;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_45);
    }
    r0 = _f_238;
    r1 = _f_239;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K89)
  {
    Term _h_33 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K90;
      WL_PUSHN(1);
    } else {
      u64 _t_46 = task_node(e, FID_MAIN_K90, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K90, _t_46);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_47 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_47 + 0] = term_ctr(CID_SCON, STAT_OFF + 280);
      e.mem[_t_47 + 1] = _h_33;
      return term_tsk(FID_STRING_APPEND, _t_47);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 280);
    r1 = _h_33;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K90)
  {
    Term _h_34 = r0;
    WL_OPEN
    u64 _nd_61 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_61 + 0] = _h_34;
    r0 = term_clo(FID_MAIN_C91, _nd_61);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C91)
  {
    Term _h_35 = r0;
    Term _x_46 = r1;
    WL_OPEN
    u64 _nd_62 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_62 + 0] = _h_35;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_167 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_167 + 0] = term_clo(FID_IO_PRINT, _nd_62);
      e.mem[_t_167 + 1] = term_clo(FID_MAIN_C92, 0);
      e.mem[_t_167 + 2] = _x_46;
      return term_tsk(FID_IO_BIND, _t_167);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_62);
    r1 = term_clo(FID_MAIN_C92, 0);
    r2 = _x_46;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C92)
  {
    Term _x_47 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C93, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C93)
  {
    Term _x_48 = r0;
    WL_OPEN
    u64 _nd_63 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_63 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 282);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_166 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_166 + 0] = term_clo(FID_WIRE_FLAT, _nd_63);
      e.mem[_t_166 + 1] = term_clo(FID_MAIN_C94, 0);
      e.mem[_t_166 + 2] = _x_48;
      return term_tsk(FID_IO_BIND, _t_166);
    }
    r0 = term_clo(FID_WIRE_FLAT, _nd_63);
    r1 = term_clo(FID_MAIN_C94, 0);
    r2 = _x_48;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C94)
  {
    Term _x_49 = r0;
    WL_OPEN
    Term _fb_12[2];
    u64 _sp_12 = ctr_take(e, _x_49, 2, _fb_12);
    u32 _f_240 = _fb_12[0];
    u32 _f_241 = _fb_12[1];
    spare_free(e, cls_fit(2), _sp_12);
    u64 _nd_64 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_64 + 0] = _f_240;
    e.mem[_nd_64 + 1] = _f_241;
    r0 = term_clo(FID_MAIN_C95, _nd_64);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C95)
  {
    u32 _f_242 = r0;
    u32 _f_243 = r1;
    Term _x_50 = r2;
    WL_OPEN
    u64 _nd_65 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_65 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 282);
    u64 _nd_66 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_66 + 0] = _f_242;
    e.mem[_nd_66 + 1] = _f_243;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_165 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_165 + 0] = term_clo(FID_WIRE_BOXED, _nd_65);
      e.mem[_t_165 + 1] = term_clo(FID_MAIN_C96, _nd_66);
      e.mem[_t_165 + 2] = _x_50;
      return term_tsk(FID_IO_BIND, _t_165);
    }
    r0 = term_clo(FID_WIRE_BOXED, _nd_65);
    r1 = term_clo(FID_MAIN_C96, _nd_66);
    r2 = _x_50;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C96)
  {
    u32 _f_244 = r0;
    u32 _f_245 = r1;
    Term _x_51 = r2;
    WL_OPEN
    Term _fb_13[2];
    u64 _sp_13 = ctr_take(e, _x_51, 2, _fb_13);
    u32 _f_246 = _fb_13[0];
    u32 _f_247 = _fb_13[1];
    spare_free(e, cls_fit(2), _sp_13);
    u64 _nd_67 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_67 + 0] = _f_244;
    e.mem[_nd_67 + 1] = _f_245;
    e.mem[_nd_67 + 2] = _f_246;
    e.mem[_nd_67 + 3] = _f_247;
    r0 = term_clo(FID_MAIN_C97, _nd_67);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C97)
  {
    u32 _f_248 = r0;
    u32 _f_249 = r1;
    u32 _f_250 = r2;
    u32 _f_251 = r3;
    Term _x_52 = r4;
    WL_OPEN
    u64 _nd_68 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_68 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 282);
    u64 _nd_69 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_69 + 0] = _f_248;
    e.mem[_nd_69 + 1] = _f_249;
    e.mem[_nd_69 + 2] = _f_250;
    e.mem[_nd_69 + 3] = _f_251;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_164 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_164 + 0] = term_clo(FID_WIRE_BOXED_SWAP, _nd_68);
      e.mem[_t_164 + 1] = term_clo(FID_MAIN_C98, _nd_69);
      e.mem[_t_164 + 2] = _x_52;
      return term_tsk(FID_IO_BIND, _t_164);
    }
    r0 = term_clo(FID_WIRE_BOXED_SWAP, _nd_68);
    r1 = term_clo(FID_MAIN_C98, _nd_69);
    r2 = _x_52;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C98)
  {
    u32 _f_252 = r0;
    u32 _f_253 = r1;
    u32 _f_254 = r2;
    u32 _f_255 = r3;
    Term _x_53 = r4;
    WL_OPEN
    Term _fb_14[2];
    u64 _sp_14 = ctr_take(e, _x_53, 2, _fb_14);
    u32 _f_256 = _fb_14[0];
    u32 _f_257 = _fb_14[1];
    spare_free(e, cls_fit(2), _sp_14);
    u64 _nd_70 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_70 + 0] = _f_252;
    e.mem[_nd_70 + 1] = _f_253;
    e.mem[_nd_70 + 2] = _f_254;
    e.mem[_nd_70 + 3] = _f_255;
    e.mem[_nd_70 + 4] = _f_256;
    e.mem[_nd_70 + 5] = _f_257;
    r0 = term_clo(FID_MAIN_C99, _nd_70);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C99)
  {
    u32 _f_258 = r0;
    u32 _f_259 = r1;
    u32 _f_260 = r2;
    u32 _f_261 = r3;
    u32 _f_262 = r4;
    u32 _f_263 = r5;
    Term _x_54 = r6;
    WL_OPEN
    u64 _nd_71 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_71 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 282);
    u64 _nd_72 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_72 + 0] = _f_258;
    e.mem[_nd_72 + 1] = _f_259;
    e.mem[_nd_72 + 2] = _f_260;
    e.mem[_nd_72 + 3] = _f_261;
    e.mem[_nd_72 + 4] = _f_262;
    e.mem[_nd_72 + 5] = _f_263;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_163 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_163 + 0] = term_clo(FID_WIRE_BOXED_SAME, _nd_71);
      e.mem[_t_163 + 1] = term_clo(FID_MAIN_C100, _nd_72);
      e.mem[_t_163 + 2] = _x_54;
      return term_tsk(FID_IO_BIND, _t_163);
    }
    r0 = term_clo(FID_WIRE_BOXED_SAME, _nd_71);
    r1 = term_clo(FID_MAIN_C100, _nd_72);
    r2 = _x_54;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C100)
  {
    u32 _f_264 = r0;
    u32 _f_265 = r1;
    u32 _f_266 = r2;
    u32 _f_267 = r3;
    u32 _f_268 = r4;
    u32 _f_269 = r5;
    Term _x_55 = r6;
    WL_OPEN
    Term _fb_15[2];
    u64 _sp_15 = ctr_take(e, _x_55, 2, _fb_15);
    u32 _f_270 = _fb_15[0];
    u32 _f_271 = _fb_15[1];
    spare_free(e, cls_fit(2), _sp_15);
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_266;
      STK(1) = _f_267;
      STK(2) = _f_268;
      STK(3) = _f_269;
      STK(4) = _f_270;
      STK(5) = _f_271;
      STK(6) = FID_MAIN_K101;
      WL_PUSHN(7);
    } else {
      u64 _t_48 = task_node(e, FID_MAIN_K101, WL_CONT, WL_IDX, 1);
      e.mem[_t_48 + 0] = _f_266;
      e.mem[_t_48 + 1] = _f_267;
      e.mem[_t_48 + 2] = _f_268;
      e.mem[_t_48 + 3] = _f_269;
      e.mem[_t_48 + 4] = _f_270;
      e.mem[_t_48 + 5] = _f_271;
      WL_CONT = term_tsk(FID_MAIN_K101, _t_48);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_49 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_49 + 0] = _f_264;
      e.mem[_t_49 + 1] = _f_265;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_49);
    }
    r0 = _f_264;
    r1 = _f_265;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K101)
  {
    WL_POPN(6);
    u32 _f_272 = STK(0);
    u32 _f_273 = STK(1);
    u32 _f_274 = STK(2);
    u32 _f_275 = STK(3);
    u32 _f_276 = STK(4);
    u32 _f_277 = STK(5);
    Term _h_36 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_272;
      STK(1) = _f_273;
      STK(2) = _f_274;
      STK(3) = _f_275;
      STK(4) = _f_276;
      STK(5) = _f_277;
      STK(6) = FID_MAIN_K102;
      WL_PUSHN(7);
    } else {
      u64 _t_50 = task_node(e, FID_MAIN_K102, WL_CONT, WL_IDX, 1);
      e.mem[_t_50 + 0] = _f_272;
      e.mem[_t_50 + 1] = _f_273;
      e.mem[_t_50 + 2] = _f_274;
      e.mem[_t_50 + 3] = _f_275;
      e.mem[_t_50 + 4] = _f_276;
      e.mem[_t_50 + 5] = _f_277;
      WL_CONT = term_tsk(FID_MAIN_K102, _t_50);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_51 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_51 + 0] = term_ctr(CID_SCON, STAT_OFF + 342);
      e.mem[_t_51 + 1] = _h_36;
      return term_tsk(FID_STRING_APPEND, _t_51);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 342);
    r1 = _h_36;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K102)
  {
    WL_POPN(6);
    u32 _f_278 = STK(0);
    u32 _f_279 = STK(1);
    u32 _f_280 = STK(2);
    u32 _f_281 = STK(3);
    u32 _f_282 = STK(4);
    u32 _f_283 = STK(5);
    Term _h_37 = r0;
    WL_OPEN
    u64 _nd_73 = heap_alloc(e, cls_fit(7));
    e.mem[_nd_73 + 0] = _f_278;
    e.mem[_nd_73 + 1] = _f_279;
    e.mem[_nd_73 + 2] = _f_280;
    e.mem[_nd_73 + 3] = _f_281;
    e.mem[_nd_73 + 4] = _f_282;
    e.mem[_nd_73 + 5] = _f_283;
    e.mem[_nd_73 + 6] = _h_37;
    r0 = term_clo(FID_MAIN_C103, _nd_73);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C103)
  {
    u32 _f_284 = r0;
    u32 _f_285 = r1;
    u32 _f_286 = r2;
    u32 _f_287 = r3;
    u32 _f_288 = r4;
    u32 _f_289 = r5;
    Term _h_38 = r6;
    Term _x_56 = r7;
    WL_OPEN
    u64 _nd_74 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_74 + 0] = _h_38;
    u64 _nd_75 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_75 + 0] = _f_284;
    e.mem[_nd_75 + 1] = _f_285;
    e.mem[_nd_75 + 2] = _f_286;
    e.mem[_nd_75 + 3] = _f_287;
    e.mem[_nd_75 + 4] = _f_288;
    e.mem[_nd_75 + 5] = _f_289;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_162 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_162 + 0] = term_clo(FID_IO_PRINT, _nd_74);
      e.mem[_t_162 + 1] = term_clo(FID_MAIN_C104, _nd_75);
      e.mem[_t_162 + 2] = _x_56;
      return term_tsk(FID_IO_BIND, _t_162);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_74);
    r1 = term_clo(FID_MAIN_C104, _nd_75);
    r2 = _x_56;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C104)
  {
    u32 _f_290 = r0;
    u32 _f_291 = r1;
    u32 _f_292 = r2;
    u32 _f_293 = r3;
    u32 _f_294 = r4;
    u32 _f_295 = r5;
    Term _x_57 = r6;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_292;
      STK(1) = _f_293;
      STK(2) = _f_294;
      STK(3) = _f_295;
      STK(4) = FID_MAIN_K105;
      WL_PUSHN(5);
    } else {
      u64 _t_52 = task_node(e, FID_MAIN_K105, WL_CONT, WL_IDX, 1);
      e.mem[_t_52 + 0] = _f_292;
      e.mem[_t_52 + 1] = _f_293;
      e.mem[_t_52 + 2] = _f_294;
      e.mem[_t_52 + 3] = _f_295;
      WL_CONT = term_tsk(FID_MAIN_K105, _t_52);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_53 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_53 + 0] = _f_290;
      e.mem[_t_53 + 1] = _f_291;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_53);
    }
    r0 = _f_290;
    r1 = _f_291;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K105)
  {
    WL_POPN(4);
    u32 _f_296 = STK(0);
    u32 _f_297 = STK(1);
    u32 _f_298 = STK(2);
    u32 _f_299 = STK(3);
    Term _h_39 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_296;
      STK(1) = _f_297;
      STK(2) = _f_298;
      STK(3) = _f_299;
      STK(4) = FID_MAIN_K106;
      WL_PUSHN(5);
    } else {
      u64 _t_54 = task_node(e, FID_MAIN_K106, WL_CONT, WL_IDX, 1);
      e.mem[_t_54 + 0] = _f_296;
      e.mem[_t_54 + 1] = _f_297;
      e.mem[_t_54 + 2] = _f_298;
      e.mem[_t_54 + 3] = _f_299;
      WL_CONT = term_tsk(FID_MAIN_K106, _t_54);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_55 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_55 + 0] = term_ctr(CID_SCON, STAT_OFF + 362);
      e.mem[_t_55 + 1] = _h_39;
      return term_tsk(FID_STRING_APPEND, _t_55);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 362);
    r1 = _h_39;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K106)
  {
    WL_POPN(4);
    u32 _f_300 = STK(0);
    u32 _f_301 = STK(1);
    u32 _f_302 = STK(2);
    u32 _f_303 = STK(3);
    Term _h_40 = r0;
    WL_OPEN
    u64 _nd_76 = heap_alloc(e, cls_fit(5));
    e.mem[_nd_76 + 0] = _f_300;
    e.mem[_nd_76 + 1] = _f_301;
    e.mem[_nd_76 + 2] = _f_302;
    e.mem[_nd_76 + 3] = _f_303;
    e.mem[_nd_76 + 4] = _h_40;
    r0 = term_clo(FID_MAIN_C107, _nd_76);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C107)
  {
    u32 _f_304 = r0;
    u32 _f_305 = r1;
    u32 _f_306 = r2;
    u32 _f_307 = r3;
    Term _h_41 = r4;
    Term _x_58 = r5;
    WL_OPEN
    u64 _nd_77 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_77 + 0] = _h_41;
    u64 _nd_78 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_78 + 0] = _f_304;
    e.mem[_nd_78 + 1] = _f_305;
    e.mem[_nd_78 + 2] = _f_306;
    e.mem[_nd_78 + 3] = _f_307;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_161 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_161 + 0] = term_clo(FID_IO_PRINT, _nd_77);
      e.mem[_t_161 + 1] = term_clo(FID_MAIN_C108, _nd_78);
      e.mem[_t_161 + 2] = _x_58;
      return term_tsk(FID_IO_BIND, _t_161);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_77);
    r1 = term_clo(FID_MAIN_C108, _nd_78);
    r2 = _x_58;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C108)
  {
    u32 _f_308 = r0;
    u32 _f_309 = r1;
    u32 _f_310 = r2;
    u32 _f_311 = r3;
    Term _x_59 = r4;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_310;
      STK(1) = _f_311;
      STK(2) = FID_MAIN_K109;
      WL_PUSHN(3);
    } else {
      u64 _t_56 = task_node(e, FID_MAIN_K109, WL_CONT, WL_IDX, 1);
      e.mem[_t_56 + 0] = _f_310;
      e.mem[_t_56 + 1] = _f_311;
      WL_CONT = term_tsk(FID_MAIN_K109, _t_56);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_57 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_57 + 0] = _f_308;
      e.mem[_t_57 + 1] = _f_309;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_57);
    }
    r0 = _f_308;
    r1 = _f_309;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K109)
  {
    WL_POPN(2);
    u32 _f_312 = STK(0);
    u32 _f_313 = STK(1);
    Term _h_42 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_312;
      STK(1) = _f_313;
      STK(2) = FID_MAIN_K110;
      WL_PUSHN(3);
    } else {
      u64 _t_58 = task_node(e, FID_MAIN_K110, WL_CONT, WL_IDX, 1);
      e.mem[_t_58 + 0] = _f_312;
      e.mem[_t_58 + 1] = _f_313;
      WL_CONT = term_tsk(FID_MAIN_K110, _t_58);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_59 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_59 + 0] = term_ctr(CID_SCON, STAT_OFF + 380);
      e.mem[_t_59 + 1] = _h_42;
      return term_tsk(FID_STRING_APPEND, _t_59);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 380);
    r1 = _h_42;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K110)
  {
    WL_POPN(2);
    u32 _f_314 = STK(0);
    u32 _f_315 = STK(1);
    Term _h_43 = r0;
    WL_OPEN
    u64 _nd_79 = heap_alloc(e, cls_fit(3));
    e.mem[_nd_79 + 0] = _f_314;
    e.mem[_nd_79 + 1] = _f_315;
    e.mem[_nd_79 + 2] = _h_43;
    r0 = term_clo(FID_MAIN_C111, _nd_79);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C111)
  {
    u32 _f_316 = r0;
    u32 _f_317 = r1;
    Term _h_44 = r2;
    Term _x_60 = r3;
    WL_OPEN
    u64 _nd_80 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_80 + 0] = _h_44;
    u64 _nd_81 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_81 + 0] = _f_316;
    e.mem[_nd_81 + 1] = _f_317;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_160 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_160 + 0] = term_clo(FID_IO_PRINT, _nd_80);
      e.mem[_t_160 + 1] = term_clo(FID_MAIN_C112, _nd_81);
      e.mem[_t_160 + 2] = _x_60;
      return term_tsk(FID_IO_BIND, _t_160);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_80);
    r1 = term_clo(FID_MAIN_C112, _nd_81);
    r2 = _x_60;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C112)
  {
    u32 _f_318 = r0;
    u32 _f_319 = r1;
    Term _x_61 = r2;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K113;
      WL_PUSHN(1);
    } else {
      u64 _t_60 = task_node(e, FID_MAIN_K113, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K113, _t_60);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_61 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_61 + 0] = _f_318;
      e.mem[_t_61 + 1] = _f_319;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_61);
    }
    r0 = _f_318;
    r1 = _f_319;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K113)
  {
    Term _h_45 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K114;
      WL_PUSHN(1);
    } else {
      u64 _t_62 = task_node(e, FID_MAIN_K114, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K114, _t_62);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_63 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_63 + 0] = term_ctr(CID_SCON, STAT_OFF + 398);
      e.mem[_t_63 + 1] = _h_45;
      return term_tsk(FID_STRING_APPEND, _t_63);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 398);
    r1 = _h_45;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K114)
  {
    Term _h_46 = r0;
    WL_OPEN
    u64 _nd_82 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_82 + 0] = _h_46;
    r0 = term_clo(FID_MAIN_C115, _nd_82);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C115)
  {
    Term _h_47 = r0;
    Term _x_62 = r1;
    WL_OPEN
    u64 _nd_83 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_83 + 0] = _h_47;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_159 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_159 + 0] = term_clo(FID_IO_PRINT, _nd_83);
      e.mem[_t_159 + 1] = term_clo(FID_MAIN_C116, 0);
      e.mem[_t_159 + 2] = _x_62;
      return term_tsk(FID_IO_BIND, _t_159);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_83);
    r1 = term_clo(FID_MAIN_C116, 0);
    r2 = _x_62;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C116)
  {
    Term _x_63 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C117, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C117)
  {
    Term _x_64 = r0;
    WL_OPEN
    u64 _nd_84 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_84 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 400);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_158 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_158 + 0] = term_clo(FID_WIRE_FLAT, _nd_84);
      e.mem[_t_158 + 1] = term_clo(FID_MAIN_C118, 0);
      e.mem[_t_158 + 2] = _x_64;
      return term_tsk(FID_IO_BIND, _t_158);
    }
    r0 = term_clo(FID_WIRE_FLAT, _nd_84);
    r1 = term_clo(FID_MAIN_C118, 0);
    r2 = _x_64;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C118)
  {
    Term _x_65 = r0;
    WL_OPEN
    Term _fb_16[2];
    u64 _sp_16 = ctr_take(e, _x_65, 2, _fb_16);
    u32 _f_320 = _fb_16[0];
    u32 _f_321 = _fb_16[1];
    spare_free(e, cls_fit(2), _sp_16);
    u64 _nd_85 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_85 + 0] = _f_320;
    e.mem[_nd_85 + 1] = _f_321;
    r0 = term_clo(FID_MAIN_C119, _nd_85);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C119)
  {
    u32 _f_322 = r0;
    u32 _f_323 = r1;
    Term _x_66 = r2;
    WL_OPEN
    u64 _nd_86 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_86 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 400);
    u64 _nd_87 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_87 + 0] = _f_322;
    e.mem[_nd_87 + 1] = _f_323;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_157 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_157 + 0] = term_clo(FID_WIRE_BOXED, _nd_86);
      e.mem[_t_157 + 1] = term_clo(FID_MAIN_C120, _nd_87);
      e.mem[_t_157 + 2] = _x_66;
      return term_tsk(FID_IO_BIND, _t_157);
    }
    r0 = term_clo(FID_WIRE_BOXED, _nd_86);
    r1 = term_clo(FID_MAIN_C120, _nd_87);
    r2 = _x_66;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C120)
  {
    u32 _f_324 = r0;
    u32 _f_325 = r1;
    Term _x_67 = r2;
    WL_OPEN
    Term _fb_17[2];
    u64 _sp_17 = ctr_take(e, _x_67, 2, _fb_17);
    u32 _f_326 = _fb_17[0];
    u32 _f_327 = _fb_17[1];
    spare_free(e, cls_fit(2), _sp_17);
    u64 _nd_88 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_88 + 0] = _f_324;
    e.mem[_nd_88 + 1] = _f_325;
    e.mem[_nd_88 + 2] = _f_326;
    e.mem[_nd_88 + 3] = _f_327;
    r0 = term_clo(FID_MAIN_C121, _nd_88);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C121)
  {
    u32 _f_328 = r0;
    u32 _f_329 = r1;
    u32 _f_330 = r2;
    u32 _f_331 = r3;
    Term _x_68 = r4;
    WL_OPEN
    u64 _nd_89 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_89 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 400);
    u64 _nd_90 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_90 + 0] = _f_328;
    e.mem[_nd_90 + 1] = _f_329;
    e.mem[_nd_90 + 2] = _f_330;
    e.mem[_nd_90 + 3] = _f_331;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_156 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_156 + 0] = term_clo(FID_WIRE_BOXED_SWAP, _nd_89);
      e.mem[_t_156 + 1] = term_clo(FID_MAIN_C122, _nd_90);
      e.mem[_t_156 + 2] = _x_68;
      return term_tsk(FID_IO_BIND, _t_156);
    }
    r0 = term_clo(FID_WIRE_BOXED_SWAP, _nd_89);
    r1 = term_clo(FID_MAIN_C122, _nd_90);
    r2 = _x_68;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C122)
  {
    u32 _f_332 = r0;
    u32 _f_333 = r1;
    u32 _f_334 = r2;
    u32 _f_335 = r3;
    Term _x_69 = r4;
    WL_OPEN
    Term _fb_18[2];
    u64 _sp_18 = ctr_take(e, _x_69, 2, _fb_18);
    u32 _f_336 = _fb_18[0];
    u32 _f_337 = _fb_18[1];
    spare_free(e, cls_fit(2), _sp_18);
    u64 _nd_91 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_91 + 0] = _f_332;
    e.mem[_nd_91 + 1] = _f_333;
    e.mem[_nd_91 + 2] = _f_334;
    e.mem[_nd_91 + 3] = _f_335;
    e.mem[_nd_91 + 4] = _f_336;
    e.mem[_nd_91 + 5] = _f_337;
    r0 = term_clo(FID_MAIN_C123, _nd_91);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C123)
  {
    u32 _f_338 = r0;
    u32 _f_339 = r1;
    u32 _f_340 = r2;
    u32 _f_341 = r3;
    u32 _f_342 = r4;
    u32 _f_343 = r5;
    Term _x_70 = r6;
    WL_OPEN
    u64 _nd_92 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_92 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 400);
    u64 _nd_93 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_93 + 0] = _f_338;
    e.mem[_nd_93 + 1] = _f_339;
    e.mem[_nd_93 + 2] = _f_340;
    e.mem[_nd_93 + 3] = _f_341;
    e.mem[_nd_93 + 4] = _f_342;
    e.mem[_nd_93 + 5] = _f_343;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_155 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_155 + 0] = term_clo(FID_WIRE_BOXED_SAME, _nd_92);
      e.mem[_t_155 + 1] = term_clo(FID_MAIN_C124, _nd_93);
      e.mem[_t_155 + 2] = _x_70;
      return term_tsk(FID_IO_BIND, _t_155);
    }
    r0 = term_clo(FID_WIRE_BOXED_SAME, _nd_92);
    r1 = term_clo(FID_MAIN_C124, _nd_93);
    r2 = _x_70;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C124)
  {
    u32 _f_344 = r0;
    u32 _f_345 = r1;
    u32 _f_346 = r2;
    u32 _f_347 = r3;
    u32 _f_348 = r4;
    u32 _f_349 = r5;
    Term _x_71 = r6;
    WL_OPEN
    Term _fb_19[2];
    u64 _sp_19 = ctr_take(e, _x_71, 2, _fb_19);
    u32 _f_350 = _fb_19[0];
    u32 _f_351 = _fb_19[1];
    spare_free(e, cls_fit(2), _sp_19);
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_346;
      STK(1) = _f_347;
      STK(2) = _f_348;
      STK(3) = _f_349;
      STK(4) = _f_350;
      STK(5) = _f_351;
      STK(6) = FID_MAIN_K125;
      WL_PUSHN(7);
    } else {
      u64 _t_64 = task_node(e, FID_MAIN_K125, WL_CONT, WL_IDX, 1);
      e.mem[_t_64 + 0] = _f_346;
      e.mem[_t_64 + 1] = _f_347;
      e.mem[_t_64 + 2] = _f_348;
      e.mem[_t_64 + 3] = _f_349;
      e.mem[_t_64 + 4] = _f_350;
      e.mem[_t_64 + 5] = _f_351;
      WL_CONT = term_tsk(FID_MAIN_K125, _t_64);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_65 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_65 + 0] = _f_344;
      e.mem[_t_65 + 1] = _f_345;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_65);
    }
    r0 = _f_344;
    r1 = _f_345;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K125)
  {
    WL_POPN(6);
    u32 _f_352 = STK(0);
    u32 _f_353 = STK(1);
    u32 _f_354 = STK(2);
    u32 _f_355 = STK(3);
    u32 _f_356 = STK(4);
    u32 _f_357 = STK(5);
    Term _h_48 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_352;
      STK(1) = _f_353;
      STK(2) = _f_354;
      STK(3) = _f_355;
      STK(4) = _f_356;
      STK(5) = _f_357;
      STK(6) = FID_MAIN_K126;
      WL_PUSHN(7);
    } else {
      u64 _t_66 = task_node(e, FID_MAIN_K126, WL_CONT, WL_IDX, 1);
      e.mem[_t_66 + 0] = _f_352;
      e.mem[_t_66 + 1] = _f_353;
      e.mem[_t_66 + 2] = _f_354;
      e.mem[_t_66 + 3] = _f_355;
      e.mem[_t_66 + 4] = _f_356;
      e.mem[_t_66 + 5] = _f_357;
      WL_CONT = term_tsk(FID_MAIN_K126, _t_66);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_67 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_67 + 0] = term_ctr(CID_SCON, STAT_OFF + 426);
      e.mem[_t_67 + 1] = _h_48;
      return term_tsk(FID_STRING_APPEND, _t_67);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 426);
    r1 = _h_48;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K126)
  {
    WL_POPN(6);
    u32 _f_358 = STK(0);
    u32 _f_359 = STK(1);
    u32 _f_360 = STK(2);
    u32 _f_361 = STK(3);
    u32 _f_362 = STK(4);
    u32 _f_363 = STK(5);
    Term _h_49 = r0;
    WL_OPEN
    u64 _nd_94 = heap_alloc(e, cls_fit(7));
    e.mem[_nd_94 + 0] = _f_358;
    e.mem[_nd_94 + 1] = _f_359;
    e.mem[_nd_94 + 2] = _f_360;
    e.mem[_nd_94 + 3] = _f_361;
    e.mem[_nd_94 + 4] = _f_362;
    e.mem[_nd_94 + 5] = _f_363;
    e.mem[_nd_94 + 6] = _h_49;
    r0 = term_clo(FID_MAIN_C127, _nd_94);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C127)
  {
    u32 _f_364 = r0;
    u32 _f_365 = r1;
    u32 _f_366 = r2;
    u32 _f_367 = r3;
    u32 _f_368 = r4;
    u32 _f_369 = r5;
    Term _h_50 = r6;
    Term _x_72 = r7;
    WL_OPEN
    u64 _nd_95 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_95 + 0] = _h_50;
    u64 _nd_96 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_96 + 0] = _f_364;
    e.mem[_nd_96 + 1] = _f_365;
    e.mem[_nd_96 + 2] = _f_366;
    e.mem[_nd_96 + 3] = _f_367;
    e.mem[_nd_96 + 4] = _f_368;
    e.mem[_nd_96 + 5] = _f_369;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_154 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_154 + 0] = term_clo(FID_IO_PRINT, _nd_95);
      e.mem[_t_154 + 1] = term_clo(FID_MAIN_C128, _nd_96);
      e.mem[_t_154 + 2] = _x_72;
      return term_tsk(FID_IO_BIND, _t_154);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_95);
    r1 = term_clo(FID_MAIN_C128, _nd_96);
    r2 = _x_72;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C128)
  {
    u32 _f_370 = r0;
    u32 _f_371 = r1;
    u32 _f_372 = r2;
    u32 _f_373 = r3;
    u32 _f_374 = r4;
    u32 _f_375 = r5;
    Term _x_73 = r6;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_372;
      STK(1) = _f_373;
      STK(2) = _f_374;
      STK(3) = _f_375;
      STK(4) = FID_MAIN_K129;
      WL_PUSHN(5);
    } else {
      u64 _t_68 = task_node(e, FID_MAIN_K129, WL_CONT, WL_IDX, 1);
      e.mem[_t_68 + 0] = _f_372;
      e.mem[_t_68 + 1] = _f_373;
      e.mem[_t_68 + 2] = _f_374;
      e.mem[_t_68 + 3] = _f_375;
      WL_CONT = term_tsk(FID_MAIN_K129, _t_68);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_69 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_69 + 0] = _f_370;
      e.mem[_t_69 + 1] = _f_371;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_69);
    }
    r0 = _f_370;
    r1 = _f_371;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K129)
  {
    WL_POPN(4);
    u32 _f_376 = STK(0);
    u32 _f_377 = STK(1);
    u32 _f_378 = STK(2);
    u32 _f_379 = STK(3);
    Term _h_51 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_376;
      STK(1) = _f_377;
      STK(2) = _f_378;
      STK(3) = _f_379;
      STK(4) = FID_MAIN_K130;
      WL_PUSHN(5);
    } else {
      u64 _t_70 = task_node(e, FID_MAIN_K130, WL_CONT, WL_IDX, 1);
      e.mem[_t_70 + 0] = _f_376;
      e.mem[_t_70 + 1] = _f_377;
      e.mem[_t_70 + 2] = _f_378;
      e.mem[_t_70 + 3] = _f_379;
      WL_CONT = term_tsk(FID_MAIN_K130, _t_70);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_71 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_71 + 0] = term_ctr(CID_SCON, STAT_OFF + 446);
      e.mem[_t_71 + 1] = _h_51;
      return term_tsk(FID_STRING_APPEND, _t_71);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 446);
    r1 = _h_51;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K130)
  {
    WL_POPN(4);
    u32 _f_380 = STK(0);
    u32 _f_381 = STK(1);
    u32 _f_382 = STK(2);
    u32 _f_383 = STK(3);
    Term _h_52 = r0;
    WL_OPEN
    u64 _nd_97 = heap_alloc(e, cls_fit(5));
    e.mem[_nd_97 + 0] = _f_380;
    e.mem[_nd_97 + 1] = _f_381;
    e.mem[_nd_97 + 2] = _f_382;
    e.mem[_nd_97 + 3] = _f_383;
    e.mem[_nd_97 + 4] = _h_52;
    r0 = term_clo(FID_MAIN_C131, _nd_97);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C131)
  {
    u32 _f_384 = r0;
    u32 _f_385 = r1;
    u32 _f_386 = r2;
    u32 _f_387 = r3;
    Term _h_53 = r4;
    Term _x_74 = r5;
    WL_OPEN
    u64 _nd_98 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_98 + 0] = _h_53;
    u64 _nd_99 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_99 + 0] = _f_384;
    e.mem[_nd_99 + 1] = _f_385;
    e.mem[_nd_99 + 2] = _f_386;
    e.mem[_nd_99 + 3] = _f_387;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_153 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_153 + 0] = term_clo(FID_IO_PRINT, _nd_98);
      e.mem[_t_153 + 1] = term_clo(FID_MAIN_C132, _nd_99);
      e.mem[_t_153 + 2] = _x_74;
      return term_tsk(FID_IO_BIND, _t_153);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_98);
    r1 = term_clo(FID_MAIN_C132, _nd_99);
    r2 = _x_74;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C132)
  {
    u32 _f_388 = r0;
    u32 _f_389 = r1;
    u32 _f_390 = r2;
    u32 _f_391 = r3;
    Term _x_75 = r4;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_390;
      STK(1) = _f_391;
      STK(2) = FID_MAIN_K133;
      WL_PUSHN(3);
    } else {
      u64 _t_72 = task_node(e, FID_MAIN_K133, WL_CONT, WL_IDX, 1);
      e.mem[_t_72 + 0] = _f_390;
      e.mem[_t_72 + 1] = _f_391;
      WL_CONT = term_tsk(FID_MAIN_K133, _t_72);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_73 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_73 + 0] = _f_388;
      e.mem[_t_73 + 1] = _f_389;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_73);
    }
    r0 = _f_388;
    r1 = _f_389;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K133)
  {
    WL_POPN(2);
    u32 _f_392 = STK(0);
    u32 _f_393 = STK(1);
    Term _h_54 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_392;
      STK(1) = _f_393;
      STK(2) = FID_MAIN_K134;
      WL_PUSHN(3);
    } else {
      u64 _t_74 = task_node(e, FID_MAIN_K134, WL_CONT, WL_IDX, 1);
      e.mem[_t_74 + 0] = _f_392;
      e.mem[_t_74 + 1] = _f_393;
      WL_CONT = term_tsk(FID_MAIN_K134, _t_74);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_75 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_75 + 0] = term_ctr(CID_SCON, STAT_OFF + 464);
      e.mem[_t_75 + 1] = _h_54;
      return term_tsk(FID_STRING_APPEND, _t_75);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 464);
    r1 = _h_54;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K134)
  {
    WL_POPN(2);
    u32 _f_394 = STK(0);
    u32 _f_395 = STK(1);
    Term _h_55 = r0;
    WL_OPEN
    u64 _nd_100 = heap_alloc(e, cls_fit(3));
    e.mem[_nd_100 + 0] = _f_394;
    e.mem[_nd_100 + 1] = _f_395;
    e.mem[_nd_100 + 2] = _h_55;
    r0 = term_clo(FID_MAIN_C135, _nd_100);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C135)
  {
    u32 _f_396 = r0;
    u32 _f_397 = r1;
    Term _h_56 = r2;
    Term _x_76 = r3;
    WL_OPEN
    u64 _nd_101 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_101 + 0] = _h_56;
    u64 _nd_102 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_102 + 0] = _f_396;
    e.mem[_nd_102 + 1] = _f_397;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_152 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_152 + 0] = term_clo(FID_IO_PRINT, _nd_101);
      e.mem[_t_152 + 1] = term_clo(FID_MAIN_C136, _nd_102);
      e.mem[_t_152 + 2] = _x_76;
      return term_tsk(FID_IO_BIND, _t_152);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_101);
    r1 = term_clo(FID_MAIN_C136, _nd_102);
    r2 = _x_76;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C136)
  {
    u32 _f_398 = r0;
    u32 _f_399 = r1;
    Term _x_77 = r2;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K137;
      WL_PUSHN(1);
    } else {
      u64 _t_76 = task_node(e, FID_MAIN_K137, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K137, _t_76);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_77 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_77 + 0] = _f_398;
      e.mem[_t_77 + 1] = _f_399;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_77);
    }
    r0 = _f_398;
    r1 = _f_399;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K137)
  {
    Term _h_57 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K138;
      WL_PUSHN(1);
    } else {
      u64 _t_78 = task_node(e, FID_MAIN_K138, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K138, _t_78);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_79 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_79 + 0] = term_ctr(CID_SCON, STAT_OFF + 482);
      e.mem[_t_79 + 1] = _h_57;
      return term_tsk(FID_STRING_APPEND, _t_79);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 482);
    r1 = _h_57;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K138)
  {
    Term _h_58 = r0;
    WL_OPEN
    u64 _nd_103 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_103 + 0] = _h_58;
    r0 = term_clo(FID_MAIN_C139, _nd_103);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C139)
  {
    Term _h_59 = r0;
    Term _x_78 = r1;
    WL_OPEN
    u64 _nd_104 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_104 + 0] = _h_59;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_151 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_151 + 0] = term_clo(FID_IO_PRINT, _nd_104);
      e.mem[_t_151 + 1] = term_clo(FID_MAIN_C140, 0);
      e.mem[_t_151 + 2] = _x_78;
      return term_tsk(FID_IO_BIND, _t_151);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_104);
    r1 = term_clo(FID_MAIN_C140, 0);
    r2 = _x_78;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C140)
  {
    Term _x_79 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C141, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C141)
  {
    Term _x_80 = r0;
    WL_OPEN
    u64 _nd_105 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_105 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 484);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_150 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_150 + 0] = term_clo(FID_WIRE_FLAT, _nd_105);
      e.mem[_t_150 + 1] = term_clo(FID_MAIN_C142, 0);
      e.mem[_t_150 + 2] = _x_80;
      return term_tsk(FID_IO_BIND, _t_150);
    }
    r0 = term_clo(FID_WIRE_FLAT, _nd_105);
    r1 = term_clo(FID_MAIN_C142, 0);
    r2 = _x_80;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C142)
  {
    Term _x_81 = r0;
    WL_OPEN
    Term _fb_20[2];
    u64 _sp_20 = ctr_take(e, _x_81, 2, _fb_20);
    u32 _f_400 = _fb_20[0];
    u32 _f_401 = _fb_20[1];
    spare_free(e, cls_fit(2), _sp_20);
    u64 _nd_106 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_106 + 0] = _f_400;
    e.mem[_nd_106 + 1] = _f_401;
    r0 = term_clo(FID_MAIN_C143, _nd_106);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C143)
  {
    u32 _f_402 = r0;
    u32 _f_403 = r1;
    Term _x_82 = r2;
    WL_OPEN
    u64 _nd_107 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_107 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 484);
    u64 _nd_108 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_108 + 0] = _f_402;
    e.mem[_nd_108 + 1] = _f_403;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_149 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_149 + 0] = term_clo(FID_WIRE_BOXED, _nd_107);
      e.mem[_t_149 + 1] = term_clo(FID_MAIN_C144, _nd_108);
      e.mem[_t_149 + 2] = _x_82;
      return term_tsk(FID_IO_BIND, _t_149);
    }
    r0 = term_clo(FID_WIRE_BOXED, _nd_107);
    r1 = term_clo(FID_MAIN_C144, _nd_108);
    r2 = _x_82;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C144)
  {
    u32 _f_404 = r0;
    u32 _f_405 = r1;
    Term _x_83 = r2;
    WL_OPEN
    Term _fb_21[2];
    u64 _sp_21 = ctr_take(e, _x_83, 2, _fb_21);
    u32 _f_406 = _fb_21[0];
    u32 _f_407 = _fb_21[1];
    spare_free(e, cls_fit(2), _sp_21);
    u64 _nd_109 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_109 + 0] = _f_404;
    e.mem[_nd_109 + 1] = _f_405;
    e.mem[_nd_109 + 2] = _f_406;
    e.mem[_nd_109 + 3] = _f_407;
    r0 = term_clo(FID_MAIN_C145, _nd_109);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C145)
  {
    u32 _f_408 = r0;
    u32 _f_409 = r1;
    u32 _f_410 = r2;
    u32 _f_411 = r3;
    Term _x_84 = r4;
    WL_OPEN
    u64 _nd_110 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_110 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 484);
    u64 _nd_111 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_111 + 0] = _f_408;
    e.mem[_nd_111 + 1] = _f_409;
    e.mem[_nd_111 + 2] = _f_410;
    e.mem[_nd_111 + 3] = _f_411;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_148 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_148 + 0] = term_clo(FID_WIRE_BOXED_SWAP, _nd_110);
      e.mem[_t_148 + 1] = term_clo(FID_MAIN_C146, _nd_111);
      e.mem[_t_148 + 2] = _x_84;
      return term_tsk(FID_IO_BIND, _t_148);
    }
    r0 = term_clo(FID_WIRE_BOXED_SWAP, _nd_110);
    r1 = term_clo(FID_MAIN_C146, _nd_111);
    r2 = _x_84;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C146)
  {
    u32 _f_412 = r0;
    u32 _f_413 = r1;
    u32 _f_414 = r2;
    u32 _f_415 = r3;
    Term _x_85 = r4;
    WL_OPEN
    Term _fb_22[2];
    u64 _sp_22 = ctr_take(e, _x_85, 2, _fb_22);
    u32 _f_416 = _fb_22[0];
    u32 _f_417 = _fb_22[1];
    spare_free(e, cls_fit(2), _sp_22);
    u64 _nd_112 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_112 + 0] = _f_412;
    e.mem[_nd_112 + 1] = _f_413;
    e.mem[_nd_112 + 2] = _f_414;
    e.mem[_nd_112 + 3] = _f_415;
    e.mem[_nd_112 + 4] = _f_416;
    e.mem[_nd_112 + 5] = _f_417;
    r0 = term_clo(FID_MAIN_C147, _nd_112);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C147)
  {
    u32 _f_418 = r0;
    u32 _f_419 = r1;
    u32 _f_420 = r2;
    u32 _f_421 = r3;
    u32 _f_422 = r4;
    u32 _f_423 = r5;
    Term _x_86 = r6;
    WL_OPEN
    u64 _nd_113 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_113 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 484);
    u64 _nd_114 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_114 + 0] = _f_418;
    e.mem[_nd_114 + 1] = _f_419;
    e.mem[_nd_114 + 2] = _f_420;
    e.mem[_nd_114 + 3] = _f_421;
    e.mem[_nd_114 + 4] = _f_422;
    e.mem[_nd_114 + 5] = _f_423;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_147 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_147 + 0] = term_clo(FID_WIRE_BOXED_SAME, _nd_113);
      e.mem[_t_147 + 1] = term_clo(FID_MAIN_C148, _nd_114);
      e.mem[_t_147 + 2] = _x_86;
      return term_tsk(FID_IO_BIND, _t_147);
    }
    r0 = term_clo(FID_WIRE_BOXED_SAME, _nd_113);
    r1 = term_clo(FID_MAIN_C148, _nd_114);
    r2 = _x_86;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C148)
  {
    u32 _f_424 = r0;
    u32 _f_425 = r1;
    u32 _f_426 = r2;
    u32 _f_427 = r3;
    u32 _f_428 = r4;
    u32 _f_429 = r5;
    Term _x_87 = r6;
    WL_OPEN
    Term _fb_23[2];
    u64 _sp_23 = ctr_take(e, _x_87, 2, _fb_23);
    u32 _f_430 = _fb_23[0];
    u32 _f_431 = _fb_23[1];
    spare_free(e, cls_fit(2), _sp_23);
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_426;
      STK(1) = _f_427;
      STK(2) = _f_428;
      STK(3) = _f_429;
      STK(4) = _f_430;
      STK(5) = _f_431;
      STK(6) = FID_MAIN_K149;
      WL_PUSHN(7);
    } else {
      u64 _t_80 = task_node(e, FID_MAIN_K149, WL_CONT, WL_IDX, 1);
      e.mem[_t_80 + 0] = _f_426;
      e.mem[_t_80 + 1] = _f_427;
      e.mem[_t_80 + 2] = _f_428;
      e.mem[_t_80 + 3] = _f_429;
      e.mem[_t_80 + 4] = _f_430;
      e.mem[_t_80 + 5] = _f_431;
      WL_CONT = term_tsk(FID_MAIN_K149, _t_80);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_81 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_81 + 0] = _f_424;
      e.mem[_t_81 + 1] = _f_425;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_81);
    }
    r0 = _f_424;
    r1 = _f_425;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K149)
  {
    WL_POPN(6);
    u32 _f_432 = STK(0);
    u32 _f_433 = STK(1);
    u32 _f_434 = STK(2);
    u32 _f_435 = STK(3);
    u32 _f_436 = STK(4);
    u32 _f_437 = STK(5);
    Term _h_60 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_432;
      STK(1) = _f_433;
      STK(2) = _f_434;
      STK(3) = _f_435;
      STK(4) = _f_436;
      STK(5) = _f_437;
      STK(6) = FID_MAIN_K150;
      WL_PUSHN(7);
    } else {
      u64 _t_82 = task_node(e, FID_MAIN_K150, WL_CONT, WL_IDX, 1);
      e.mem[_t_82 + 0] = _f_432;
      e.mem[_t_82 + 1] = _f_433;
      e.mem[_t_82 + 2] = _f_434;
      e.mem[_t_82 + 3] = _f_435;
      e.mem[_t_82 + 4] = _f_436;
      e.mem[_t_82 + 5] = _f_437;
      WL_CONT = term_tsk(FID_MAIN_K150, _t_82);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_83 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_83 + 0] = term_ctr(CID_SCON, STAT_OFF + 506);
      e.mem[_t_83 + 1] = _h_60;
      return term_tsk(FID_STRING_APPEND, _t_83);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 506);
    r1 = _h_60;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K150)
  {
    WL_POPN(6);
    u32 _f_438 = STK(0);
    u32 _f_439 = STK(1);
    u32 _f_440 = STK(2);
    u32 _f_441 = STK(3);
    u32 _f_442 = STK(4);
    u32 _f_443 = STK(5);
    Term _h_61 = r0;
    WL_OPEN
    u64 _nd_115 = heap_alloc(e, cls_fit(7));
    e.mem[_nd_115 + 0] = _f_438;
    e.mem[_nd_115 + 1] = _f_439;
    e.mem[_nd_115 + 2] = _f_440;
    e.mem[_nd_115 + 3] = _f_441;
    e.mem[_nd_115 + 4] = _f_442;
    e.mem[_nd_115 + 5] = _f_443;
    e.mem[_nd_115 + 6] = _h_61;
    r0 = term_clo(FID_MAIN_C151, _nd_115);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C151)
  {
    u32 _f_444 = r0;
    u32 _f_445 = r1;
    u32 _f_446 = r2;
    u32 _f_447 = r3;
    u32 _f_448 = r4;
    u32 _f_449 = r5;
    Term _h_62 = r6;
    Term _x_88 = r7;
    WL_OPEN
    u64 _nd_116 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_116 + 0] = _h_62;
    u64 _nd_117 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_117 + 0] = _f_444;
    e.mem[_nd_117 + 1] = _f_445;
    e.mem[_nd_117 + 2] = _f_446;
    e.mem[_nd_117 + 3] = _f_447;
    e.mem[_nd_117 + 4] = _f_448;
    e.mem[_nd_117 + 5] = _f_449;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_146 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_146 + 0] = term_clo(FID_IO_PRINT, _nd_116);
      e.mem[_t_146 + 1] = term_clo(FID_MAIN_C152, _nd_117);
      e.mem[_t_146 + 2] = _x_88;
      return term_tsk(FID_IO_BIND, _t_146);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_116);
    r1 = term_clo(FID_MAIN_C152, _nd_117);
    r2 = _x_88;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C152)
  {
    u32 _f_450 = r0;
    u32 _f_451 = r1;
    u32 _f_452 = r2;
    u32 _f_453 = r3;
    u32 _f_454 = r4;
    u32 _f_455 = r5;
    Term _x_89 = r6;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_452;
      STK(1) = _f_453;
      STK(2) = _f_454;
      STK(3) = _f_455;
      STK(4) = FID_MAIN_K153;
      WL_PUSHN(5);
    } else {
      u64 _t_84 = task_node(e, FID_MAIN_K153, WL_CONT, WL_IDX, 1);
      e.mem[_t_84 + 0] = _f_452;
      e.mem[_t_84 + 1] = _f_453;
      e.mem[_t_84 + 2] = _f_454;
      e.mem[_t_84 + 3] = _f_455;
      WL_CONT = term_tsk(FID_MAIN_K153, _t_84);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_85 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_85 + 0] = _f_450;
      e.mem[_t_85 + 1] = _f_451;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_85);
    }
    r0 = _f_450;
    r1 = _f_451;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K153)
  {
    WL_POPN(4);
    u32 _f_456 = STK(0);
    u32 _f_457 = STK(1);
    u32 _f_458 = STK(2);
    u32 _f_459 = STK(3);
    Term _h_63 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_456;
      STK(1) = _f_457;
      STK(2) = _f_458;
      STK(3) = _f_459;
      STK(4) = FID_MAIN_K154;
      WL_PUSHN(5);
    } else {
      u64 _t_86 = task_node(e, FID_MAIN_K154, WL_CONT, WL_IDX, 1);
      e.mem[_t_86 + 0] = _f_456;
      e.mem[_t_86 + 1] = _f_457;
      e.mem[_t_86 + 2] = _f_458;
      e.mem[_t_86 + 3] = _f_459;
      WL_CONT = term_tsk(FID_MAIN_K154, _t_86);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_87 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_87 + 0] = term_ctr(CID_SCON, STAT_OFF + 526);
      e.mem[_t_87 + 1] = _h_63;
      return term_tsk(FID_STRING_APPEND, _t_87);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 526);
    r1 = _h_63;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K154)
  {
    WL_POPN(4);
    u32 _f_460 = STK(0);
    u32 _f_461 = STK(1);
    u32 _f_462 = STK(2);
    u32 _f_463 = STK(3);
    Term _h_64 = r0;
    WL_OPEN
    u64 _nd_118 = heap_alloc(e, cls_fit(5));
    e.mem[_nd_118 + 0] = _f_460;
    e.mem[_nd_118 + 1] = _f_461;
    e.mem[_nd_118 + 2] = _f_462;
    e.mem[_nd_118 + 3] = _f_463;
    e.mem[_nd_118 + 4] = _h_64;
    r0 = term_clo(FID_MAIN_C155, _nd_118);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C155)
  {
    u32 _f_464 = r0;
    u32 _f_465 = r1;
    u32 _f_466 = r2;
    u32 _f_467 = r3;
    Term _h_65 = r4;
    Term _x_90 = r5;
    WL_OPEN
    u64 _nd_119 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_119 + 0] = _h_65;
    u64 _nd_120 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_120 + 0] = _f_464;
    e.mem[_nd_120 + 1] = _f_465;
    e.mem[_nd_120 + 2] = _f_466;
    e.mem[_nd_120 + 3] = _f_467;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_145 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_145 + 0] = term_clo(FID_IO_PRINT, _nd_119);
      e.mem[_t_145 + 1] = term_clo(FID_MAIN_C156, _nd_120);
      e.mem[_t_145 + 2] = _x_90;
      return term_tsk(FID_IO_BIND, _t_145);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_119);
    r1 = term_clo(FID_MAIN_C156, _nd_120);
    r2 = _x_90;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C156)
  {
    u32 _f_468 = r0;
    u32 _f_469 = r1;
    u32 _f_470 = r2;
    u32 _f_471 = r3;
    Term _x_91 = r4;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_470;
      STK(1) = _f_471;
      STK(2) = FID_MAIN_K157;
      WL_PUSHN(3);
    } else {
      u64 _t_88 = task_node(e, FID_MAIN_K157, WL_CONT, WL_IDX, 1);
      e.mem[_t_88 + 0] = _f_470;
      e.mem[_t_88 + 1] = _f_471;
      WL_CONT = term_tsk(FID_MAIN_K157, _t_88);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_89 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_89 + 0] = _f_468;
      e.mem[_t_89 + 1] = _f_469;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_89);
    }
    r0 = _f_468;
    r1 = _f_469;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K157)
  {
    WL_POPN(2);
    u32 _f_472 = STK(0);
    u32 _f_473 = STK(1);
    Term _h_66 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_472;
      STK(1) = _f_473;
      STK(2) = FID_MAIN_K158;
      WL_PUSHN(3);
    } else {
      u64 _t_90 = task_node(e, FID_MAIN_K158, WL_CONT, WL_IDX, 1);
      e.mem[_t_90 + 0] = _f_472;
      e.mem[_t_90 + 1] = _f_473;
      WL_CONT = term_tsk(FID_MAIN_K158, _t_90);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_91 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_91 + 0] = term_ctr(CID_SCON, STAT_OFF + 544);
      e.mem[_t_91 + 1] = _h_66;
      return term_tsk(FID_STRING_APPEND, _t_91);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 544);
    r1 = _h_66;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K158)
  {
    WL_POPN(2);
    u32 _f_474 = STK(0);
    u32 _f_475 = STK(1);
    Term _h_67 = r0;
    WL_OPEN
    u64 _nd_121 = heap_alloc(e, cls_fit(3));
    e.mem[_nd_121 + 0] = _f_474;
    e.mem[_nd_121 + 1] = _f_475;
    e.mem[_nd_121 + 2] = _h_67;
    r0 = term_clo(FID_MAIN_C159, _nd_121);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C159)
  {
    u32 _f_476 = r0;
    u32 _f_477 = r1;
    Term _h_68 = r2;
    Term _x_92 = r3;
    WL_OPEN
    u64 _nd_122 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_122 + 0] = _h_68;
    u64 _nd_123 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_123 + 0] = _f_476;
    e.mem[_nd_123 + 1] = _f_477;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_144 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_144 + 0] = term_clo(FID_IO_PRINT, _nd_122);
      e.mem[_t_144 + 1] = term_clo(FID_MAIN_C160, _nd_123);
      e.mem[_t_144 + 2] = _x_92;
      return term_tsk(FID_IO_BIND, _t_144);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_122);
    r1 = term_clo(FID_MAIN_C160, _nd_123);
    r2 = _x_92;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C160)
  {
    u32 _f_478 = r0;
    u32 _f_479 = r1;
    Term _x_93 = r2;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K161;
      WL_PUSHN(1);
    } else {
      u64 _t_92 = task_node(e, FID_MAIN_K161, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K161, _t_92);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_93 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_93 + 0] = _f_478;
      e.mem[_t_93 + 1] = _f_479;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_93);
    }
    r0 = _f_478;
    r1 = _f_479;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K161)
  {
    Term _h_69 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K162;
      WL_PUSHN(1);
    } else {
      u64 _t_94 = task_node(e, FID_MAIN_K162, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K162, _t_94);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_95 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_95 + 0] = term_ctr(CID_SCON, STAT_OFF + 562);
      e.mem[_t_95 + 1] = _h_69;
      return term_tsk(FID_STRING_APPEND, _t_95);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 562);
    r1 = _h_69;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K162)
  {
    Term _h_70 = r0;
    WL_OPEN
    u64 _nd_124 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_124 + 0] = _h_70;
    r0 = term_clo(FID_MAIN_C163, _nd_124);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C163)
  {
    Term _h_71 = r0;
    Term _x_94 = r1;
    WL_OPEN
    u64 _nd_125 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_125 + 0] = _h_71;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_143 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_143 + 0] = term_clo(FID_IO_PRINT, _nd_125);
      e.mem[_t_143 + 1] = term_clo(FID_MAIN_C164, 0);
      e.mem[_t_143 + 2] = _x_94;
      return term_tsk(FID_IO_BIND, _t_143);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_125);
    r1 = term_clo(FID_MAIN_C164, 0);
    r2 = _x_94;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C164)
  {
    Term _x_95 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C165, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C165)
  {
    Term _x_96 = r0;
    WL_OPEN
    u64 _nd_126 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_126 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 564);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_142 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_142 + 0] = term_clo(FID_WIRE_FLAT, _nd_126);
      e.mem[_t_142 + 1] = term_clo(FID_MAIN_C166, 0);
      e.mem[_t_142 + 2] = _x_96;
      return term_tsk(FID_IO_BIND, _t_142);
    }
    r0 = term_clo(FID_WIRE_FLAT, _nd_126);
    r1 = term_clo(FID_MAIN_C166, 0);
    r2 = _x_96;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C166)
  {
    Term _x_97 = r0;
    WL_OPEN
    Term _fb_24[2];
    u64 _sp_24 = ctr_take(e, _x_97, 2, _fb_24);
    u32 _f_480 = _fb_24[0];
    u32 _f_481 = _fb_24[1];
    spare_free(e, cls_fit(2), _sp_24);
    u64 _nd_127 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_127 + 0] = _f_480;
    e.mem[_nd_127 + 1] = _f_481;
    r0 = term_clo(FID_MAIN_C167, _nd_127);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C167)
  {
    u32 _f_482 = r0;
    u32 _f_483 = r1;
    Term _x_98 = r2;
    WL_OPEN
    u64 _nd_128 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_128 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 564);
    u64 _nd_129 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_129 + 0] = _f_482;
    e.mem[_nd_129 + 1] = _f_483;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_141 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_141 + 0] = term_clo(FID_WIRE_BOXED, _nd_128);
      e.mem[_t_141 + 1] = term_clo(FID_MAIN_C168, _nd_129);
      e.mem[_t_141 + 2] = _x_98;
      return term_tsk(FID_IO_BIND, _t_141);
    }
    r0 = term_clo(FID_WIRE_BOXED, _nd_128);
    r1 = term_clo(FID_MAIN_C168, _nd_129);
    r2 = _x_98;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C168)
  {
    u32 _f_484 = r0;
    u32 _f_485 = r1;
    Term _x_99 = r2;
    WL_OPEN
    Term _fb_25[2];
    u64 _sp_25 = ctr_take(e, _x_99, 2, _fb_25);
    u32 _f_486 = _fb_25[0];
    u32 _f_487 = _fb_25[1];
    spare_free(e, cls_fit(2), _sp_25);
    u64 _nd_130 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_130 + 0] = _f_484;
    e.mem[_nd_130 + 1] = _f_485;
    e.mem[_nd_130 + 2] = _f_486;
    e.mem[_nd_130 + 3] = _f_487;
    r0 = term_clo(FID_MAIN_C169, _nd_130);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C169)
  {
    u32 _f_488 = r0;
    u32 _f_489 = r1;
    u32 _f_490 = r2;
    u32 _f_491 = r3;
    Term _x_100 = r4;
    WL_OPEN
    u64 _nd_131 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_131 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 564);
    u64 _nd_132 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_132 + 0] = _f_488;
    e.mem[_nd_132 + 1] = _f_489;
    e.mem[_nd_132 + 2] = _f_490;
    e.mem[_nd_132 + 3] = _f_491;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_140 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_140 + 0] = term_clo(FID_WIRE_BOXED_SWAP, _nd_131);
      e.mem[_t_140 + 1] = term_clo(FID_MAIN_C170, _nd_132);
      e.mem[_t_140 + 2] = _x_100;
      return term_tsk(FID_IO_BIND, _t_140);
    }
    r0 = term_clo(FID_WIRE_BOXED_SWAP, _nd_131);
    r1 = term_clo(FID_MAIN_C170, _nd_132);
    r2 = _x_100;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C170)
  {
    u32 _f_492 = r0;
    u32 _f_493 = r1;
    u32 _f_494 = r2;
    u32 _f_495 = r3;
    Term _x_101 = r4;
    WL_OPEN
    Term _fb_26[2];
    u64 _sp_26 = ctr_take(e, _x_101, 2, _fb_26);
    u32 _f_496 = _fb_26[0];
    u32 _f_497 = _fb_26[1];
    spare_free(e, cls_fit(2), _sp_26);
    u64 _nd_133 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_133 + 0] = _f_492;
    e.mem[_nd_133 + 1] = _f_493;
    e.mem[_nd_133 + 2] = _f_494;
    e.mem[_nd_133 + 3] = _f_495;
    e.mem[_nd_133 + 4] = _f_496;
    e.mem[_nd_133 + 5] = _f_497;
    r0 = term_clo(FID_MAIN_C171, _nd_133);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C171)
  {
    u32 _f_498 = r0;
    u32 _f_499 = r1;
    u32 _f_500 = r2;
    u32 _f_501 = r3;
    u32 _f_502 = r4;
    u32 _f_503 = r5;
    Term _x_102 = r6;
    WL_OPEN
    u64 _nd_134 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_134 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 564);
    u64 _nd_135 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_135 + 0] = _f_498;
    e.mem[_nd_135 + 1] = _f_499;
    e.mem[_nd_135 + 2] = _f_500;
    e.mem[_nd_135 + 3] = _f_501;
    e.mem[_nd_135 + 4] = _f_502;
    e.mem[_nd_135 + 5] = _f_503;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_139 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_139 + 0] = term_clo(FID_WIRE_BOXED_SAME, _nd_134);
      e.mem[_t_139 + 1] = term_clo(FID_MAIN_C172, _nd_135);
      e.mem[_t_139 + 2] = _x_102;
      return term_tsk(FID_IO_BIND, _t_139);
    }
    r0 = term_clo(FID_WIRE_BOXED_SAME, _nd_134);
    r1 = term_clo(FID_MAIN_C172, _nd_135);
    r2 = _x_102;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C172)
  {
    u32 _f_504 = r0;
    u32 _f_505 = r1;
    u32 _f_506 = r2;
    u32 _f_507 = r3;
    u32 _f_508 = r4;
    u32 _f_509 = r5;
    Term _x_103 = r6;
    WL_OPEN
    Term _fb_27[2];
    u64 _sp_27 = ctr_take(e, _x_103, 2, _fb_27);
    u32 _f_510 = _fb_27[0];
    u32 _f_511 = _fb_27[1];
    spare_free(e, cls_fit(2), _sp_27);
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_506;
      STK(1) = _f_507;
      STK(2) = _f_508;
      STK(3) = _f_509;
      STK(4) = _f_510;
      STK(5) = _f_511;
      STK(6) = FID_MAIN_K173;
      WL_PUSHN(7);
    } else {
      u64 _t_96 = task_node(e, FID_MAIN_K173, WL_CONT, WL_IDX, 1);
      e.mem[_t_96 + 0] = _f_506;
      e.mem[_t_96 + 1] = _f_507;
      e.mem[_t_96 + 2] = _f_508;
      e.mem[_t_96 + 3] = _f_509;
      e.mem[_t_96 + 4] = _f_510;
      e.mem[_t_96 + 5] = _f_511;
      WL_CONT = term_tsk(FID_MAIN_K173, _t_96);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_97 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_97 + 0] = _f_504;
      e.mem[_t_97 + 1] = _f_505;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_97);
    }
    r0 = _f_504;
    r1 = _f_505;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K173)
  {
    WL_POPN(6);
    u32 _f_512 = STK(0);
    u32 _f_513 = STK(1);
    u32 _f_514 = STK(2);
    u32 _f_515 = STK(3);
    u32 _f_516 = STK(4);
    u32 _f_517 = STK(5);
    Term _h_72 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_512;
      STK(1) = _f_513;
      STK(2) = _f_514;
      STK(3) = _f_515;
      STK(4) = _f_516;
      STK(5) = _f_517;
      STK(6) = FID_MAIN_K174;
      WL_PUSHN(7);
    } else {
      u64 _t_98 = task_node(e, FID_MAIN_K174, WL_CONT, WL_IDX, 1);
      e.mem[_t_98 + 0] = _f_512;
      e.mem[_t_98 + 1] = _f_513;
      e.mem[_t_98 + 2] = _f_514;
      e.mem[_t_98 + 3] = _f_515;
      e.mem[_t_98 + 4] = _f_516;
      e.mem[_t_98 + 5] = _f_517;
      WL_CONT = term_tsk(FID_MAIN_K174, _t_98);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_99 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_99 + 0] = term_ctr(CID_SCON, STAT_OFF + 626);
      e.mem[_t_99 + 1] = _h_72;
      return term_tsk(FID_STRING_APPEND, _t_99);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 626);
    r1 = _h_72;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K174)
  {
    WL_POPN(6);
    u32 _f_518 = STK(0);
    u32 _f_519 = STK(1);
    u32 _f_520 = STK(2);
    u32 _f_521 = STK(3);
    u32 _f_522 = STK(4);
    u32 _f_523 = STK(5);
    Term _h_73 = r0;
    WL_OPEN
    u64 _nd_136 = heap_alloc(e, cls_fit(7));
    e.mem[_nd_136 + 0] = _f_518;
    e.mem[_nd_136 + 1] = _f_519;
    e.mem[_nd_136 + 2] = _f_520;
    e.mem[_nd_136 + 3] = _f_521;
    e.mem[_nd_136 + 4] = _f_522;
    e.mem[_nd_136 + 5] = _f_523;
    e.mem[_nd_136 + 6] = _h_73;
    r0 = term_clo(FID_MAIN_C175, _nd_136);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C175)
  {
    u32 _f_524 = r0;
    u32 _f_525 = r1;
    u32 _f_526 = r2;
    u32 _f_527 = r3;
    u32 _f_528 = r4;
    u32 _f_529 = r5;
    Term _h_74 = r6;
    Term _x_104 = r7;
    WL_OPEN
    u64 _nd_137 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_137 + 0] = _h_74;
    u64 _nd_138 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_138 + 0] = _f_524;
    e.mem[_nd_138 + 1] = _f_525;
    e.mem[_nd_138 + 2] = _f_526;
    e.mem[_nd_138 + 3] = _f_527;
    e.mem[_nd_138 + 4] = _f_528;
    e.mem[_nd_138 + 5] = _f_529;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_138 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_138 + 0] = term_clo(FID_IO_PRINT, _nd_137);
      e.mem[_t_138 + 1] = term_clo(FID_MAIN_C176, _nd_138);
      e.mem[_t_138 + 2] = _x_104;
      return term_tsk(FID_IO_BIND, _t_138);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_137);
    r1 = term_clo(FID_MAIN_C176, _nd_138);
    r2 = _x_104;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C176)
  {
    u32 _f_530 = r0;
    u32 _f_531 = r1;
    u32 _f_532 = r2;
    u32 _f_533 = r3;
    u32 _f_534 = r4;
    u32 _f_535 = r5;
    Term _x_105 = r6;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_532;
      STK(1) = _f_533;
      STK(2) = _f_534;
      STK(3) = _f_535;
      STK(4) = FID_MAIN_K177;
      WL_PUSHN(5);
    } else {
      u64 _t_100 = task_node(e, FID_MAIN_K177, WL_CONT, WL_IDX, 1);
      e.mem[_t_100 + 0] = _f_532;
      e.mem[_t_100 + 1] = _f_533;
      e.mem[_t_100 + 2] = _f_534;
      e.mem[_t_100 + 3] = _f_535;
      WL_CONT = term_tsk(FID_MAIN_K177, _t_100);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_101 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_101 + 0] = _f_530;
      e.mem[_t_101 + 1] = _f_531;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_101);
    }
    r0 = _f_530;
    r1 = _f_531;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K177)
  {
    WL_POPN(4);
    u32 _f_536 = STK(0);
    u32 _f_537 = STK(1);
    u32 _f_538 = STK(2);
    u32 _f_539 = STK(3);
    Term _h_75 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_536;
      STK(1) = _f_537;
      STK(2) = _f_538;
      STK(3) = _f_539;
      STK(4) = FID_MAIN_K178;
      WL_PUSHN(5);
    } else {
      u64 _t_102 = task_node(e, FID_MAIN_K178, WL_CONT, WL_IDX, 1);
      e.mem[_t_102 + 0] = _f_536;
      e.mem[_t_102 + 1] = _f_537;
      e.mem[_t_102 + 2] = _f_538;
      e.mem[_t_102 + 3] = _f_539;
      WL_CONT = term_tsk(FID_MAIN_K178, _t_102);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_103 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_103 + 0] = term_ctr(CID_SCON, STAT_OFF + 646);
      e.mem[_t_103 + 1] = _h_75;
      return term_tsk(FID_STRING_APPEND, _t_103);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 646);
    r1 = _h_75;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K178)
  {
    WL_POPN(4);
    u32 _f_540 = STK(0);
    u32 _f_541 = STK(1);
    u32 _f_542 = STK(2);
    u32 _f_543 = STK(3);
    Term _h_76 = r0;
    WL_OPEN
    u64 _nd_139 = heap_alloc(e, cls_fit(5));
    e.mem[_nd_139 + 0] = _f_540;
    e.mem[_nd_139 + 1] = _f_541;
    e.mem[_nd_139 + 2] = _f_542;
    e.mem[_nd_139 + 3] = _f_543;
    e.mem[_nd_139 + 4] = _h_76;
    r0 = term_clo(FID_MAIN_C179, _nd_139);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C179)
  {
    u32 _f_544 = r0;
    u32 _f_545 = r1;
    u32 _f_546 = r2;
    u32 _f_547 = r3;
    Term _h_77 = r4;
    Term _x_106 = r5;
    WL_OPEN
    u64 _nd_140 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_140 + 0] = _h_77;
    u64 _nd_141 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_141 + 0] = _f_544;
    e.mem[_nd_141 + 1] = _f_545;
    e.mem[_nd_141 + 2] = _f_546;
    e.mem[_nd_141 + 3] = _f_547;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_137 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_137 + 0] = term_clo(FID_IO_PRINT, _nd_140);
      e.mem[_t_137 + 1] = term_clo(FID_MAIN_C180, _nd_141);
      e.mem[_t_137 + 2] = _x_106;
      return term_tsk(FID_IO_BIND, _t_137);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_140);
    r1 = term_clo(FID_MAIN_C180, _nd_141);
    r2 = _x_106;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C180)
  {
    u32 _f_548 = r0;
    u32 _f_549 = r1;
    u32 _f_550 = r2;
    u32 _f_551 = r3;
    Term _x_107 = r4;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_550;
      STK(1) = _f_551;
      STK(2) = FID_MAIN_K181;
      WL_PUSHN(3);
    } else {
      u64 _t_104 = task_node(e, FID_MAIN_K181, WL_CONT, WL_IDX, 1);
      e.mem[_t_104 + 0] = _f_550;
      e.mem[_t_104 + 1] = _f_551;
      WL_CONT = term_tsk(FID_MAIN_K181, _t_104);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_105 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_105 + 0] = _f_548;
      e.mem[_t_105 + 1] = _f_549;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_105);
    }
    r0 = _f_548;
    r1 = _f_549;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K181)
  {
    WL_POPN(2);
    u32 _f_552 = STK(0);
    u32 _f_553 = STK(1);
    Term _h_78 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_552;
      STK(1) = _f_553;
      STK(2) = FID_MAIN_K182;
      WL_PUSHN(3);
    } else {
      u64 _t_106 = task_node(e, FID_MAIN_K182, WL_CONT, WL_IDX, 1);
      e.mem[_t_106 + 0] = _f_552;
      e.mem[_t_106 + 1] = _f_553;
      WL_CONT = term_tsk(FID_MAIN_K182, _t_106);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_107 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_107 + 0] = term_ctr(CID_SCON, STAT_OFF + 664);
      e.mem[_t_107 + 1] = _h_78;
      return term_tsk(FID_STRING_APPEND, _t_107);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 664);
    r1 = _h_78;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K182)
  {
    WL_POPN(2);
    u32 _f_554 = STK(0);
    u32 _f_555 = STK(1);
    Term _h_79 = r0;
    WL_OPEN
    u64 _nd_142 = heap_alloc(e, cls_fit(3));
    e.mem[_nd_142 + 0] = _f_554;
    e.mem[_nd_142 + 1] = _f_555;
    e.mem[_nd_142 + 2] = _h_79;
    r0 = term_clo(FID_MAIN_C183, _nd_142);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C183)
  {
    u32 _f_556 = r0;
    u32 _f_557 = r1;
    Term _h_80 = r2;
    Term _x_108 = r3;
    WL_OPEN
    u64 _nd_143 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_143 + 0] = _h_80;
    u64 _nd_144 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_144 + 0] = _f_556;
    e.mem[_nd_144 + 1] = _f_557;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_136 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_136 + 0] = term_clo(FID_IO_PRINT, _nd_143);
      e.mem[_t_136 + 1] = term_clo(FID_MAIN_C184, _nd_144);
      e.mem[_t_136 + 2] = _x_108;
      return term_tsk(FID_IO_BIND, _t_136);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_143);
    r1 = term_clo(FID_MAIN_C184, _nd_144);
    r2 = _x_108;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C184)
  {
    u32 _f_558 = r0;
    u32 _f_559 = r1;
    Term _x_109 = r2;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K185;
      WL_PUSHN(1);
    } else {
      u64 _t_108 = task_node(e, FID_MAIN_K185, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K185, _t_108);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_109 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_109 + 0] = _f_558;
      e.mem[_t_109 + 1] = _f_559;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_109);
    }
    r0 = _f_558;
    r1 = _f_559;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K185)
  {
    Term _h_81 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K186;
      WL_PUSHN(1);
    } else {
      u64 _t_110 = task_node(e, FID_MAIN_K186, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K186, _t_110);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_111 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_111 + 0] = term_ctr(CID_SCON, STAT_OFF + 682);
      e.mem[_t_111 + 1] = _h_81;
      return term_tsk(FID_STRING_APPEND, _t_111);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 682);
    r1 = _h_81;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K186)
  {
    Term _h_82 = r0;
    WL_OPEN
    u64 _nd_145 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_145 + 0] = _h_82;
    r0 = term_clo(FID_MAIN_C187, _nd_145);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C187)
  {
    Term _h_83 = r0;
    Term _x_110 = r1;
    WL_OPEN
    u64 _nd_146 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_146 + 0] = _h_83;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_135 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_135 + 0] = term_clo(FID_IO_PRINT, _nd_146);
      e.mem[_t_135 + 1] = term_clo(FID_MAIN_C188, 0);
      e.mem[_t_135 + 2] = _x_110;
      return term_tsk(FID_IO_BIND, _t_135);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_146);
    r1 = term_clo(FID_MAIN_C188, 0);
    r2 = _x_110;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C188)
  {
    Term _x_111 = r0;
    WL_OPEN
    r0 = term_clo(FID_MAIN_C189, 0);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C189)
  {
    Term _x_112 = r0;
    WL_OPEN
    u64 _nd_147 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_147 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 684);
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_134 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_134 + 0] = term_clo(FID_WIRE_FLAT, _nd_147);
      e.mem[_t_134 + 1] = term_clo(FID_MAIN_C190, 0);
      e.mem[_t_134 + 2] = _x_112;
      return term_tsk(FID_IO_BIND, _t_134);
    }
    r0 = term_clo(FID_WIRE_FLAT, _nd_147);
    r1 = term_clo(FID_MAIN_C190, 0);
    r2 = _x_112;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C190)
  {
    Term _x_113 = r0;
    WL_OPEN
    Term _fb_28[2];
    u64 _sp_28 = ctr_take(e, _x_113, 2, _fb_28);
    u32 _f_560 = _fb_28[0];
    u32 _f_561 = _fb_28[1];
    spare_free(e, cls_fit(2), _sp_28);
    u64 _nd_148 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_148 + 0] = _f_560;
    e.mem[_nd_148 + 1] = _f_561;
    r0 = term_clo(FID_MAIN_C191, _nd_148);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C191)
  {
    u32 _f_562 = r0;
    u32 _f_563 = r1;
    Term _x_114 = r2;
    WL_OPEN
    u64 _nd_149 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_149 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 684);
    u64 _nd_150 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_150 + 0] = _f_562;
    e.mem[_nd_150 + 1] = _f_563;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_133 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_133 + 0] = term_clo(FID_WIRE_BOXED, _nd_149);
      e.mem[_t_133 + 1] = term_clo(FID_MAIN_C192, _nd_150);
      e.mem[_t_133 + 2] = _x_114;
      return term_tsk(FID_IO_BIND, _t_133);
    }
    r0 = term_clo(FID_WIRE_BOXED, _nd_149);
    r1 = term_clo(FID_MAIN_C192, _nd_150);
    r2 = _x_114;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C192)
  {
    u32 _f_564 = r0;
    u32 _f_565 = r1;
    Term _x_115 = r2;
    WL_OPEN
    Term _fb_29[2];
    u64 _sp_29 = ctr_take(e, _x_115, 2, _fb_29);
    u32 _f_566 = _fb_29[0];
    u32 _f_567 = _fb_29[1];
    spare_free(e, cls_fit(2), _sp_29);
    u64 _nd_151 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_151 + 0] = _f_564;
    e.mem[_nd_151 + 1] = _f_565;
    e.mem[_nd_151 + 2] = _f_566;
    e.mem[_nd_151 + 3] = _f_567;
    r0 = term_clo(FID_MAIN_C193, _nd_151);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C193)
  {
    u32 _f_568 = r0;
    u32 _f_569 = r1;
    u32 _f_570 = r2;
    u32 _f_571 = r3;
    Term _x_116 = r4;
    WL_OPEN
    u64 _nd_152 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_152 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 684);
    u64 _nd_153 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_153 + 0] = _f_568;
    e.mem[_nd_153 + 1] = _f_569;
    e.mem[_nd_153 + 2] = _f_570;
    e.mem[_nd_153 + 3] = _f_571;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_132 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_132 + 0] = term_clo(FID_WIRE_BOXED_SWAP, _nd_152);
      e.mem[_t_132 + 1] = term_clo(FID_MAIN_C194, _nd_153);
      e.mem[_t_132 + 2] = _x_116;
      return term_tsk(FID_IO_BIND, _t_132);
    }
    r0 = term_clo(FID_WIRE_BOXED_SWAP, _nd_152);
    r1 = term_clo(FID_MAIN_C194, _nd_153);
    r2 = _x_116;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C194)
  {
    u32 _f_572 = r0;
    u32 _f_573 = r1;
    u32 _f_574 = r2;
    u32 _f_575 = r3;
    Term _x_117 = r4;
    WL_OPEN
    Term _fb_30[2];
    u64 _sp_30 = ctr_take(e, _x_117, 2, _fb_30);
    u32 _f_576 = _fb_30[0];
    u32 _f_577 = _fb_30[1];
    spare_free(e, cls_fit(2), _sp_30);
    u64 _nd_154 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_154 + 0] = _f_572;
    e.mem[_nd_154 + 1] = _f_573;
    e.mem[_nd_154 + 2] = _f_574;
    e.mem[_nd_154 + 3] = _f_575;
    e.mem[_nd_154 + 4] = _f_576;
    e.mem[_nd_154 + 5] = _f_577;
    r0 = term_clo(FID_MAIN_C195, _nd_154);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C195)
  {
    u32 _f_578 = r0;
    u32 _f_579 = r1;
    u32 _f_580 = r2;
    u32 _f_581 = r3;
    u32 _f_582 = r4;
    u32 _f_583 = r5;
    Term _x_118 = r6;
    WL_OPEN
    u64 _nd_155 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_155 + 0] = term_ctr(CID__________TINYBENDYGRAD_HELPERS_I64, STAT_OFF + 684);
    u64 _nd_156 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_156 + 0] = _f_578;
    e.mem[_nd_156 + 1] = _f_579;
    e.mem[_nd_156 + 2] = _f_580;
    e.mem[_nd_156 + 3] = _f_581;
    e.mem[_nd_156 + 4] = _f_582;
    e.mem[_nd_156 + 5] = _f_583;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_131 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_131 + 0] = term_clo(FID_WIRE_BOXED_SAME, _nd_155);
      e.mem[_t_131 + 1] = term_clo(FID_MAIN_C196, _nd_156);
      e.mem[_t_131 + 2] = _x_118;
      return term_tsk(FID_IO_BIND, _t_131);
    }
    r0 = term_clo(FID_WIRE_BOXED_SAME, _nd_155);
    r1 = term_clo(FID_MAIN_C196, _nd_156);
    r2 = _x_118;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C196)
  {
    u32 _f_584 = r0;
    u32 _f_585 = r1;
    u32 _f_586 = r2;
    u32 _f_587 = r3;
    u32 _f_588 = r4;
    u32 _f_589 = r5;
    Term _x_119 = r6;
    WL_OPEN
    Term _fb_31[2];
    u64 _sp_31 = ctr_take(e, _x_119, 2, _fb_31);
    u32 _f_590 = _fb_31[0];
    u32 _f_591 = _fb_31[1];
    spare_free(e, cls_fit(2), _sp_31);
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_586;
      STK(1) = _f_587;
      STK(2) = _f_588;
      STK(3) = _f_589;
      STK(4) = _f_590;
      STK(5) = _f_591;
      STK(6) = FID_MAIN_K197;
      WL_PUSHN(7);
    } else {
      u64 _t_112 = task_node(e, FID_MAIN_K197, WL_CONT, WL_IDX, 1);
      e.mem[_t_112 + 0] = _f_586;
      e.mem[_t_112 + 1] = _f_587;
      e.mem[_t_112 + 2] = _f_588;
      e.mem[_t_112 + 3] = _f_589;
      e.mem[_t_112 + 4] = _f_590;
      e.mem[_t_112 + 5] = _f_591;
      WL_CONT = term_tsk(FID_MAIN_K197, _t_112);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_113 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_113 + 0] = _f_584;
      e.mem[_t_113 + 1] = _f_585;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_113);
    }
    r0 = _f_584;
    r1 = _f_585;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K197)
  {
    WL_POPN(6);
    u32 _f_592 = STK(0);
    u32 _f_593 = STK(1);
    u32 _f_594 = STK(2);
    u32 _f_595 = STK(3);
    u32 _f_596 = STK(4);
    u32 _f_597 = STK(5);
    Term _h_84 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(7);
      STK(0) = _f_592;
      STK(1) = _f_593;
      STK(2) = _f_594;
      STK(3) = _f_595;
      STK(4) = _f_596;
      STK(5) = _f_597;
      STK(6) = FID_MAIN_K198;
      WL_PUSHN(7);
    } else {
      u64 _t_114 = task_node(e, FID_MAIN_K198, WL_CONT, WL_IDX, 1);
      e.mem[_t_114 + 0] = _f_592;
      e.mem[_t_114 + 1] = _f_593;
      e.mem[_t_114 + 2] = _f_594;
      e.mem[_t_114 + 3] = _f_595;
      e.mem[_t_114 + 4] = _f_596;
      e.mem[_t_114 + 5] = _f_597;
      WL_CONT = term_tsk(FID_MAIN_K198, _t_114);
      WL_IDX = 6;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_115 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_115 + 0] = term_ctr(CID_SCON, STAT_OFF + 746);
      e.mem[_t_115 + 1] = _h_84;
      return term_tsk(FID_STRING_APPEND, _t_115);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 746);
    r1 = _h_84;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K198)
  {
    WL_POPN(6);
    u32 _f_598 = STK(0);
    u32 _f_599 = STK(1);
    u32 _f_600 = STK(2);
    u32 _f_601 = STK(3);
    u32 _f_602 = STK(4);
    u32 _f_603 = STK(5);
    Term _h_85 = r0;
    WL_OPEN
    u64 _nd_157 = heap_alloc(e, cls_fit(7));
    e.mem[_nd_157 + 0] = _f_598;
    e.mem[_nd_157 + 1] = _f_599;
    e.mem[_nd_157 + 2] = _f_600;
    e.mem[_nd_157 + 3] = _f_601;
    e.mem[_nd_157 + 4] = _f_602;
    e.mem[_nd_157 + 5] = _f_603;
    e.mem[_nd_157 + 6] = _h_85;
    r0 = term_clo(FID_MAIN_C199, _nd_157);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C199)
  {
    u32 _f_604 = r0;
    u32 _f_605 = r1;
    u32 _f_606 = r2;
    u32 _f_607 = r3;
    u32 _f_608 = r4;
    u32 _f_609 = r5;
    Term _h_86 = r6;
    Term _x_120 = r7;
    WL_OPEN
    u64 _nd_158 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_158 + 0] = _h_86;
    u64 _nd_159 = heap_alloc(e, cls_fit(6));
    e.mem[_nd_159 + 0] = _f_604;
    e.mem[_nd_159 + 1] = _f_605;
    e.mem[_nd_159 + 2] = _f_606;
    e.mem[_nd_159 + 3] = _f_607;
    e.mem[_nd_159 + 4] = _f_608;
    e.mem[_nd_159 + 5] = _f_609;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_130 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_130 + 0] = term_clo(FID_IO_PRINT, _nd_158);
      e.mem[_t_130 + 1] = term_clo(FID_MAIN_C200, _nd_159);
      e.mem[_t_130 + 2] = _x_120;
      return term_tsk(FID_IO_BIND, _t_130);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_158);
    r1 = term_clo(FID_MAIN_C200, _nd_159);
    r2 = _x_120;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C200)
  {
    u32 _f_610 = r0;
    u32 _f_611 = r1;
    u32 _f_612 = r2;
    u32 _f_613 = r3;
    u32 _f_614 = r4;
    u32 _f_615 = r5;
    Term _x_121 = r6;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_612;
      STK(1) = _f_613;
      STK(2) = _f_614;
      STK(3) = _f_615;
      STK(4) = FID_MAIN_K201;
      WL_PUSHN(5);
    } else {
      u64 _t_116 = task_node(e, FID_MAIN_K201, WL_CONT, WL_IDX, 1);
      e.mem[_t_116 + 0] = _f_612;
      e.mem[_t_116 + 1] = _f_613;
      e.mem[_t_116 + 2] = _f_614;
      e.mem[_t_116 + 3] = _f_615;
      WL_CONT = term_tsk(FID_MAIN_K201, _t_116);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_117 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_117 + 0] = _f_610;
      e.mem[_t_117 + 1] = _f_611;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_117);
    }
    r0 = _f_610;
    r1 = _f_611;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K201)
  {
    WL_POPN(4);
    u32 _f_616 = STK(0);
    u32 _f_617 = STK(1);
    u32 _f_618 = STK(2);
    u32 _f_619 = STK(3);
    Term _h_87 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(5);
      STK(0) = _f_616;
      STK(1) = _f_617;
      STK(2) = _f_618;
      STK(3) = _f_619;
      STK(4) = FID_MAIN_K202;
      WL_PUSHN(5);
    } else {
      u64 _t_118 = task_node(e, FID_MAIN_K202, WL_CONT, WL_IDX, 1);
      e.mem[_t_118 + 0] = _f_616;
      e.mem[_t_118 + 1] = _f_617;
      e.mem[_t_118 + 2] = _f_618;
      e.mem[_t_118 + 3] = _f_619;
      WL_CONT = term_tsk(FID_MAIN_K202, _t_118);
      WL_IDX = 4;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_119 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_119 + 0] = term_ctr(CID_SCON, STAT_OFF + 766);
      e.mem[_t_119 + 1] = _h_87;
      return term_tsk(FID_STRING_APPEND, _t_119);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 766);
    r1 = _h_87;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K202)
  {
    WL_POPN(4);
    u32 _f_620 = STK(0);
    u32 _f_621 = STK(1);
    u32 _f_622 = STK(2);
    u32 _f_623 = STK(3);
    Term _h_88 = r0;
    WL_OPEN
    u64 _nd_160 = heap_alloc(e, cls_fit(5));
    e.mem[_nd_160 + 0] = _f_620;
    e.mem[_nd_160 + 1] = _f_621;
    e.mem[_nd_160 + 2] = _f_622;
    e.mem[_nd_160 + 3] = _f_623;
    e.mem[_nd_160 + 4] = _h_88;
    r0 = term_clo(FID_MAIN_C203, _nd_160);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C203)
  {
    u32 _f_624 = r0;
    u32 _f_625 = r1;
    u32 _f_626 = r2;
    u32 _f_627 = r3;
    Term _h_89 = r4;
    Term _x_122 = r5;
    WL_OPEN
    u64 _nd_161 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_161 + 0] = _h_89;
    u64 _nd_162 = heap_alloc(e, cls_fit(4));
    e.mem[_nd_162 + 0] = _f_624;
    e.mem[_nd_162 + 1] = _f_625;
    e.mem[_nd_162 + 2] = _f_626;
    e.mem[_nd_162 + 3] = _f_627;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_129 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_129 + 0] = term_clo(FID_IO_PRINT, _nd_161);
      e.mem[_t_129 + 1] = term_clo(FID_MAIN_C204, _nd_162);
      e.mem[_t_129 + 2] = _x_122;
      return term_tsk(FID_IO_BIND, _t_129);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_161);
    r1 = term_clo(FID_MAIN_C204, _nd_162);
    r2 = _x_122;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C204)
  {
    u32 _f_628 = r0;
    u32 _f_629 = r1;
    u32 _f_630 = r2;
    u32 _f_631 = r3;
    Term _x_123 = r4;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_630;
      STK(1) = _f_631;
      STK(2) = FID_MAIN_K205;
      WL_PUSHN(3);
    } else {
      u64 _t_120 = task_node(e, FID_MAIN_K205, WL_CONT, WL_IDX, 1);
      e.mem[_t_120 + 0] = _f_630;
      e.mem[_t_120 + 1] = _f_631;
      WL_CONT = term_tsk(FID_MAIN_K205, _t_120);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_121 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_121 + 0] = _f_628;
      e.mem[_t_121 + 1] = _f_629;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_121);
    }
    r0 = _f_628;
    r1 = _f_629;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K205)
  {
    WL_POPN(2);
    u32 _f_632 = STK(0);
    u32 _f_633 = STK(1);
    Term _h_90 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(3);
      STK(0) = _f_632;
      STK(1) = _f_633;
      STK(2) = FID_MAIN_K206;
      WL_PUSHN(3);
    } else {
      u64 _t_122 = task_node(e, FID_MAIN_K206, WL_CONT, WL_IDX, 1);
      e.mem[_t_122 + 0] = _f_632;
      e.mem[_t_122 + 1] = _f_633;
      WL_CONT = term_tsk(FID_MAIN_K206, _t_122);
      WL_IDX = 2;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_123 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_123 + 0] = term_ctr(CID_SCON, STAT_OFF + 784);
      e.mem[_t_123 + 1] = _h_90;
      return term_tsk(FID_STRING_APPEND, _t_123);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 784);
    r1 = _h_90;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K206)
  {
    WL_POPN(2);
    u32 _f_634 = STK(0);
    u32 _f_635 = STK(1);
    Term _h_91 = r0;
    WL_OPEN
    u64 _nd_163 = heap_alloc(e, cls_fit(3));
    e.mem[_nd_163 + 0] = _f_634;
    e.mem[_nd_163 + 1] = _f_635;
    e.mem[_nd_163 + 2] = _h_91;
    r0 = term_clo(FID_MAIN_C207, _nd_163);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C207)
  {
    u32 _f_636 = r0;
    u32 _f_637 = r1;
    Term _h_92 = r2;
    Term _x_124 = r3;
    WL_OPEN
    u64 _nd_164 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_164 + 0] = _h_92;
    u64 _nd_165 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_165 + 0] = _f_636;
    e.mem[_nd_165 + 1] = _f_637;
    if (!DEVICE && !seq && fid_nofk(FID_IO_BIND)) {
      u64 _t_128 = task_node(e, FID_IO_BIND, WL_CONT, WL_IDX, 0);
      e.mem[_t_128 + 0] = term_clo(FID_IO_PRINT, _nd_164);
      e.mem[_t_128 + 1] = term_clo(FID_MAIN_C208, _nd_165);
      e.mem[_t_128 + 2] = _x_124;
      return term_tsk(FID_IO_BIND, _t_128);
    }
    r0 = term_clo(FID_IO_PRINT, _nd_164);
    r1 = term_clo(FID_MAIN_C208, _nd_165);
    r2 = _x_124;
    WL_JMP(FID_IO_BIND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_C208)
  {
    u32 _f_638 = r0;
    u32 _f_639 = r1;
    Term _x_125 = r2;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K209;
      WL_PUSHN(1);
    } else {
      u64 _t_124 = task_node(e, FID_MAIN_K209, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K209, _t_124);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT)) {
      u64 _t_125 = task_node(e, FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, WL_CONT, WL_IDX, 0);
      e.mem[_t_125 + 0] = _f_638;
      e.mem[_t_125 + 1] = _f_639;
      return term_tsk(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT, _t_125);
    }
    r0 = _f_638;
    r1 = _f_639;
    WL_JMP(FID__________TINYBENDYGRAD_HELPERS_I64_TEXT);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K209)
  {
    Term _h_93 = r0;
    WL_OPEN
    if (seq) {
      WL_ROOM(1);
      STK(0) = FID_MAIN_K210;
      WL_PUSHN(1);
    } else {
      u64 _t_126 = task_node(e, FID_MAIN_K210, WL_CONT, WL_IDX, 1);
      WL_CONT = term_tsk(FID_MAIN_K210, _t_126);
      WL_IDX = 0;
    }
    if (!DEVICE && !seq && fid_nofk(FID_STRING_APPEND)) {
      u64 _t_127 = task_node(e, FID_STRING_APPEND, WL_CONT, WL_IDX, 0);
      e.mem[_t_127 + 0] = term_ctr(CID_SCON, STAT_OFF + 802);
      e.mem[_t_127 + 1] = _h_93;
      return term_tsk(FID_STRING_APPEND, _t_127);
    }
    r0 = term_ctr(CID_SCON, STAT_OFF + 802);
    r1 = _h_93;
    WL_JMP(FID_STRING_APPEND);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_MAIN_K210)
  {
    Term _h_94 = r0;
    WL_OPEN
    u64 _nd_166 = heap_alloc(e, cls_fit(1));
    e.mem[_nd_166 + 0] = _h_94;
    r0 = term_clo(FID_IO_PRINT, _nd_166);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_WIRE_FLAT)
  {
    Term __4 = r0;
    Term _k_5 = r1;
    WL_OPEN
    u64 _nd_5 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_5 + 0] = __4;
    e.mem[_nd_5 + 1] = _k_5;
    r0 = term_ctr(CID_WIRE_FLAT, _nd_5);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_WIRE_BOXED)
  {
    Term __5 = r0;
    Term _k_6 = r1;
    WL_OPEN
    u64 _nd_6 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_6 + 0] = __5;
    e.mem[_nd_6 + 1] = _k_6;
    r0 = term_ctr(CID_WIRE_BOXED, _nd_6);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_WIRE_BOXED_SWAP)
  {
    Term __6 = r0;
    Term _k_7 = r1;
    WL_OPEN
    u64 _nd_7 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_7 + 0] = __6;
    e.mem[_nd_7 + 1] = _k_7;
    r0 = term_ctr(CID_WIRE_BOXED_SWAP, _nd_7);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_WIRE_BOXED_SAME)
  {
    Term __7 = r0;
    Term _k_8 = r1;
    WL_OPEN
    u64 _nd_8 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_8 + 0] = __7;
    e.mem[_nd_8 + 1] = _k_8;
    r0 = term_ctr(CID_WIRE_BOXED_SAME, _nd_8);
    WL_RETN(1);
  }}
#endif

#if !DEVICE
  WL_CASE(FID_IO_PRINT)
  {
    Term _text_1 = r0;
    Term _k_9 = r1;
    WL_OPEN
    u64 _nd_9 = heap_alloc(e, cls_fit(2));
    e.mem[_nd_9 + 0] = _text_1;
    e.mem[_nd_9 + 1] = _k_9;
    r0 = term_ctr(CID_IO_PRINT, _nd_9);
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

// t1_wire.c -- the argument wire of the `Dt.i64_*` seam, read TWO ways.
//
// THE QUESTION. `runtime/dtype.c:205-206` reads an `H.I64` argument as
//
//     return (s64)(((u64)(u32)f[0] << 32) | (u32)f[1]);
//
// i.e. it assumes the two halves arrive as two consecutive words of the effect
// argument frame. This file asks whether they do.
//
// THE METHOD IS A DIFFERENTIAL, NOT AN ORACLE. `H.i64_of_hi_lo` is the identity,
// so for every pair `x`, a CORRECT reader answers `x`. Two readers are applied to
// the SAME received bytes and exactly one of them is the identity. Nothing here
// asserts what a wrong answer looks like -- "it is a heap address" is not a
// prediction this file makes and does not need. The identity is definitional, so
// WHICH reader is it is a measurement.
//
//   wire_flat    f[0], f[1]              -- dtype.c:206's rule
//   wire_boxed   ctr_take(f[0], 2, o)    -- through the argument's own Term
//
// `ctr_take` is the runtime's own field reader (it handles a static payload as
// well as a heap one), so `wire_boxed` is not a reader I invented.

static Term wire_flat(Env e, Term* f, IoWork* w) {
  return io_tup(e, (Term)(intptr_t)(u32)f[0], (Term)(intptr_t)(u32)f[1]);
}

static Term wire_boxed(Env e, Term* f, IoWork* w) {
  Term o[2];
  ctr_take(e, f[0], 2, o);
  return io_tup(e, o[0], o[1]);
}

// The PLANT: the halves swapped. It must move every row whose two halves
// DIFFER and must not move a single row whose halves are equal, which is why
// the fixture set is half equal-halves on purpose.
static Term wire_boxed_swap(Env e, Term* f, IoWork* w) {
  Term o[2];
  ctr_take(e, f[0], 2, o);
  return io_tup(e, o[1], o[0]);
}

// The DISARM: a different EXPRESSION for `wire_boxed`, not a different function.
// `U32.or(x, 0)` is x for every x, so this rewrites the program without changing
// the answer, and the only correct moved-set is the empty one.
static Term wire_boxed_same(Env e, Term* f, IoWork* w) {
  Term o[2];
  ctr_take(e, f[0], 2, o);
  return io_tup(e, (Term)(intptr_t)(u32)(o[0] | 0u), (Term)(intptr_t)(u32)(o[1] | 0u));
}

#ifdef CID_WIRE_FLAT
static void __attribute__((constructor)) wire_flat_use(void) { io_eff(CID_WIRE_FLAT, wire_flat, 0); }
#endif
#ifdef CID_WIRE_BOXED
static void __attribute__((constructor)) wire_boxed_use(void) { io_eff(CID_WIRE_BOXED, wire_boxed, 0); }
#endif
#ifdef CID_WIRE_BOXED_SWAP
static void __attribute__((constructor)) wire_boxed_swap_use(void) { io_eff(CID_WIRE_BOXED_SWAP, wire_boxed_swap, 0); }
#endif
#ifdef CID_WIRE_BOXED_SAME
static void __attribute__((constructor)) wire_boxed_same_use(void) { io_eff(CID_WIRE_BOXED_SAME, wire_boxed_same, 0); }
#endif// IO
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
