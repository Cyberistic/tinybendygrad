# tinybendygrad/runtime/support/nv/ip.bend -- port of tinygrad/runtime/support/nv/ip.py
#
# ===========================================================================
# WHAT THIS FILE ACTUALLY IS, because the name misleads.
#
# `nv/ip.py` is NOT the NVOS ioctl attribute file. There is no `nv_ioctl`, no
# NV2080_ALLOC_MEMORY attribute table and no channel/allocation bitmask table in
# it: all of those live in `tinygrad/runtime/autogen/nv.py` and `nv_570.py`,
# which are GENERATED ctypes bindings. What ip.py is -- and what this file
# ports -- is the GSP RPC RING PROTOCOL and the two bootloaders that drive it:
#
#   * `NVRpcQueue` (:19-91) -- the msgqTxHeader ring, the RPC record layout, the
#     u64 checksum, the write-pointer advance, the wrap-around copy, the
#     response read and the wait.
#   * `NV_FLCN` (:93-283) -- pulling the Falcon ucode and booter out of VBIOS
#     and a `booter_load` image, and the DMA/start/halt sequence that runs one.
#   * `NV_FLCN_COT` (:285-344) -- the FSP message framing and the COT payload.
#   * `NV_GSP` (:346-661) -- the radix3 page tree, the WPR meta layout, the RM
#     alloc/control RPCs, the registry table, and the cpu-sequencer opcode
#     dispatch.
#
# So the STRUCT FIELD LAYOUTS this file uses are the load-bearing part, and they
# are all here under THE LAYOUTS: 54 ctypes structs, 413 fields, in declaration
# order, with byte offsets and widths. The generated block below is that
# transcription; `.agents/slop/nv_ip_gen.py` produced it out of CPython with no
# device present, and produced the gate rows from the same run.
#
# ---------------------------------------------------------------------------
# A DISAGREEMENT WITH THE TASK BRIEF, REPORTED NOT RECONCILED.
#
# The brief said `ops_nv.bend` (3897 lines, committed, green) cites `nv/ip.py`
# by line and that those citations "point at nothing" until this file exists.
# IT DOES NOT. Measured:
#
#     $ grep -n "nv/ip\|nv_ip" tinybendygrad/runtime/ops_nv.bend   -> no hits
#     $ grep -c "nv/ip\|nv_ip" ops_nv.bend                          -> 0
#     $ grep -o "[A-Za-z0-9_/]*\.py" ops_nv.bend | sort | uniq -c
#        22 ops_nv.py   10 hcq2.py    2 tinygrad/runtime/ops_nv.py
#         2 realize.py   1 support/elf.py  1 oracle.py  1 mutate.py
#         1 helpers.py   1 diff.py     1 device.py    1 autogen/nv_570.py
#         1 tinygrad/runtime/autogen/nv_570.py
#
# `ops_nv.bend` cites `hcq2.py` ten times and `ops_nv.py` twenty-two, and
# `nv/ip.py` ZERO times. So there is no wall or row in that file for this port to
# contradict, and nothing in it constrains the choices below. That is the honest
# finding; it is not the same as agreement, and no row here is offered as
# corroboration of anything in ops_nv.bend.
#
# ---------------------------------------------------------------------------
# THE SHARED CONTRACT WITH hcq2, AND WHY IT IS NOT SETTLED YET.
#
# `hcq2.py` overlaps this file on exactly one thing: the GSP command queue this
# file drives (`cmd_q`/`stat_q`, :387/:511) and the doorbell
# `NV_PGSP_QUEUE_HEAD[0].write(0x0)` at :55. At the time of writing
# `tinybendygrad/runtime/support/hcq2.bend` is still a 29-line STUB (imports plus
# an empty `main`), so there is no second table to contradict and I have NOT
# picked a side. What this port therefore fixes, and what the hcq2 agent must
# agree with or report, is:
#
#   1. The queue header is `nv.msgqTxHeader` -- (version, size, msgSize,
#      msgCount, writePtr, flags, rxHdrOff, entryOff), 32 bytes, and
#      :384-385 writes (0, queue_size, 0x1000, (queue_size-0x1000)//0x1000, 0, 1,
#      sizeof(msgqTxHeader)). `q.init` is that and nothing else.
#   2. The ring's usable length is `msgSize*msgCount`, and the wrap threshold is
#      `wp*msgSize + msgSize*msgCount` -- i.e. `ring_len`, NOT `size`. :30 slices
#      the ring at `entryOff` but :48 measures the wrap against
#      `len(self.queue_mv)`, which is `msgSize*msgCount`. `q.ring_len` is the
#      second number and `q.rx_hdr_off` is the first; a port that confuses them
#      wraps one message early.
#   3. The doorbell is a write of 0x0, once per RPC record, AFTER the write
#      pointer is advanced. Order is the gate; see `ip_doorbell_*`.
#
# ---------------------------------------------------------------------------
# THE SPLIT, stated once and then obeyed: a def here EITHER builds the argument
# of ONE call (pure, and the gate checks it) OR records that call in the trace
# (and the gate checks the ORDER). There is no third kind. Every seam is a trace
# tag and nothing else, so ORDER and IDENTITY are gateable even though none of
# the calls is made here.
#
# THE RAISE IS IN THE TRACE. `Tr.emit` records nothing once the seam has
# reported a failure, so a refusal shows up as a TRUNCATED trace and needs no
# guard of its own anywhere downstream. The failing call IS recorded -- it is
# what the seam refused -- so the rule is the same one ops_webgpu.bend uses for
# its four pop sites, and the row that pins it is named `ip_refuse_*`.
#
# ---------------------------------------------------------------------------
# ===========================================================================
# THE SEAMS, named with their Python lines. These are FFI, not logic.
#
#   * every `ctypes` struct construction, and `bytes(x)`: the field VALUES are
#     real ctypes writes into a real buffer. This port reproduces the layouts
#     (THE LAYOUTS) and the U32-representable field values, and the ctypes
#     marshalling itself is the seam.
#       # TODO(p3) support/nv/ip.py:39  rpc_message_header_v(...)
#       # TODO(p3) support/nv/ip.py:43  GSP_MSG_QUEUE_ELEMENT(...)
#       # TODO(p3) support/nv/ip.py:146 FWSECLIC_READ_VBIOS_DESC(...)
#       # TODO(p3) support/nv/ip.py:147 FWSECLIC_FRTS_REGION_DESC(...)
#       # TODO(p3) support/nv/ip.py:374 MESSAGE_QUEUE_INIT_ARGUMENTS(...)
#       # TODO(p3) support/nv/ip.py:394 LibosMemoryRegionInitArgument(...)
#       # TODO(p3) support/nv/ip.py:438 GspFwWprMeta(**common, ...)
#       # TODO(p3) support/nv/ip.py:530 rpc_alloc_memory_v(...)
#       # TODO(p3) support/nv/ip.py:551 rpc_gsp_rm_alloc_v(...)
#       # TODO(p3) support/nv/ip.py:582 rpc_gsp_rm_control_v(...)
#       # TODO(p3) support/nv/ip.py:595 struct_NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_...
#       # TODO(p3) support/nv/ip.py:597 rpc_set_page_directory_v(...)
#       # TODO(p3) support/nv/ip.py:605 GspSystemInfo(...)
#       # TODO(p3) support/nv/ip.py:612 rpc_unloading_guest_driver_v(...)
#       # TODO(p3) support/nv/ip.py:622 PACKED_REGISTRY_ENTRY(...)
#       # TODO(p3) support/nv/ip.py:626 PACKED_REGISTRY_TABLE(...)
#
#   * the `/dev/nvidia*` fds and the `nvdev` register file. `nvdev.include(...)`
#     (:99-105), `nvdev.wreg`/`rreg` (:231,:637), every `NV_P*` register, the
#     `mmio` views (:111) and `_alloc_boot_mem` (:167) are device memory this
#     file cannot reach.
#       # TODO(p3) support/nv/ip.py:99   self.nvdev.include("dev_gsp", "ga102")
#       # TODO(p3) support/nv/ip.py:111  self.nvdev.mmio[0x300000//4:...]
#       # TODO(p3) support/nv/ip.py:167  self.nvdev._alloc_boot_mem(...)
#       # TODO(p3) support/nv/ip.py:199  self.nvdev.NV_PGSP_FALCON_MAILBOX0.write
#
#   * `fetch_fw` (:174,:303,:402,:429) and `elf_loader` (:303) -- firmware
#     download and ELF parsing. The offsets read OUT of their results are
#     arithmetic and are ported (`prep_booter`, `init_gsp_image`,
#     `init_boot_binary_image`); the download and the parse are the seam.
#       # TODO(p3) support/nv/ip.py:174  fetch_fw(... "booter_load-570.144.bin" ...)
#       # TODO(p3) support/nv/ip.py:303  elf_loader(fetch_fw(... "fmc-570.144.bin" ...))
#       # TODO(p3) support/nv/ip.py:402  elf_loader(fetch_fw(... "gsp-570.144.bin" ...))
#       # TODO(p3) support/nv/ip.py:429  fetch_fw(... "bootloader-570.144.bin" ...)
#
#   * `wait_cond` (:22,:96,:213,:277,:288,:326,:640), `time.sleep` (:274,:641)
#     and `System.memory_barrier` (:52,:63,:78). `System.memory_barrier` IS a
#     trace call -- it is `C_BARRIER`, and its POSITION between the pointer store
#     and the doorbell is what `ip_tr_<i>_order` pins. `wait_resp` (:87-91) is a
#     trace call too (`C_WAIT_RESP`, then `C_RPC_RAISE` on the timeout). The
#     POLLING LOOPS are not: `wait_cond` and `time.sleep` are the seam, and no
#     trace tag claims to be either of them.
#       # TODO(p3) support/nv/ip.py:22   wait_cond(... "RPC queue not initialized")
#       # TODO(p3) support/nv/ip.py:52   System.memory_barrier()  [PORTED: C_BARRIER]
#       # TODO(p3) support/nv/ip.py:274  time.sleep(0.1)
#       # TODO(p3) support/nv/ip.py:640  wait_cond(lambda a, m: ...)
#
#   * the VBIOS scan (:110-143). It walks a firmware image with a
#     `match/case` over two code types and then walks three token tables; the
#     WALKS are over bytes this file does not have. The one thing ported is the
#     arithmetic that survives without the bytes -- `frts_offset` (:145),
#     `desc_v3` size arithmetic (:141-143) -- and the refusal at :123.
#       # TODO(p3) support/nv/ip.py:111  the PCI expansion ROM walk
#       # TODO(p3) support/nv/ip.py:123  assert bit_header.Signature == 0x00544942
#
# ---------------------------------------------------------------------------
# THE WALLS. Three, and each is named with the line that owns it.
#
# 1. THE 64-BIT WALL, in three separate places, and they are not the same place.
#    `base.bend` exports no 64-bit integer, so:
#      - `GSP_FW_WPR_META_MAGIC` = 15869187694674993331 (:442). ONE of the 65
#        integer constants ip.py names does not fit a U32. `ip_c_over64` names
#        it; it is not ported, and the WPR meta builder records the field as the
#        seam's.
#      - `maxUserVa=0x7ffffffff000` (:608) and the four `gpuPhys*Addr` fields of
#        `GspSystemInfo` (:605). Their OFFSETS and WIDTHS are in the layout table
#        -- 8-byte fields at their byte offsets -- and their VALUES are the
#        seam's. `GspSystemInfo` is 48 fields and 928 bytes and the port knows
#        all of that.
#      - `_checksum` (:32-36) sums u64 words. This one is NOT a wall and the
#        reason is the whole reason the checksum gate is worth having: the
#        accumulator is a XOR and `hi32(x) ^ lo32(x)` COMMUTES with XOR over the
#        words, so the whole checksum collapses to two U32 folds over the
#        TWENTY U32 words of `GSP_MSG_QUEUE_ELEMENT ++ rpc_message_header_v`.
#        `rp.cksum.xor` does that, and it needs the byte OFFSETS -- so it fails
#        on a wrong field order and a wrong offset, which a count gate would not.
#        It does NOT fail on a wrong endianness, because XOR is commutative: the
#        mutation table records the exchange of `rp.pickw`'s arms as an equivalent
#        mutant, and the comment above `rp.pickw` says so where a reader needs it.
#
#    Two more 64-bit facts live where they bite rather than here, because each is
#    one arithmetic chain and not a type boundary:
#      - `init_wpr_meta` (:434-455) SUBTRACTS from `vram_size`, so every offset it
#        computes exceeds 2**32 for any real card. See THE FIXTURES beside
#        `wpr.leg4` and `ip_wpr_vram_max`.
#      - `id8=int.from_bytes(bytes(f"LOG{name}", 'utf-8'), 'big')` (:395) is an
#        EIGHT-BYTE name read big-endian. See the note beside `libos` and
#        `ip_libos_id8_bytes`.
#      # TODO(p3) support/nv/ip.py:442  GSP_FW_WPR_META_MAGIC
#      # TODO(p3) support/nv/ip.py:605  GspSystemInfo.gpuPhysAddr / maxUserVa
#
# 2. THE DICT WALL, and it is a soft one. `self.chan_runlists` (:348),
#    `self.runlists` (:475), `self.grctx_bufs` (:501), `ctxbufs` (:457) and the
#    `table` in `rpc_set_registry_table` (:617) are Python dicts, so they are
#    INSERTION-ORDERED, and two of them are read with a MISS HANDLER that
#    returns a default (`self.runlists.get(..., 0)` :557,
#    `(bufs or {}).get(buf, ...) :461`). A `List` here is the same information
#    plus an explicit key list, and every miss is an explicit arm. What is lost
#    is dict ITERATION order under mutation, which none of these sites relies on.
#
# 3. THE GENERATOR WALL. `self.nvdev.include("dev_gsp", "ga102")` (:99-105)
#    pulls a device REGISTER MAP at run time, and that map is where
#    `NV_PFALCON_FALCON_DMATRFCMD_SIZE_256B`, `..._MEM_TYPE_PHYSICAL` and
#    `NV_PFALCON2_FALCON_MOD_SEL_ALGO_RSA3K` come from -- `autogen/nv_570.py`
#    is not enough for them. So those three constants are NOT PORTED here and
#    NOT in `nv_ip_tables.bend`: they belong to whoever ports `ops_nv.py`'s
#    register table, and `fl.dma_cmd` takes its bit positions as parameters for
#    exactly that reason.
#      # TODO(p3) support/nv/ip.py:242  NV_PFALCON_FALCON_DMATRFCMD.encode(...)
#      # TODO(p3) support/nv/ip.py:253  NV_PFALCON2_FALCON_MOD_SEL_ALGO_RSA3K
#      # TODO(p3) support/nv/ip.py:99   the register map `include` produces
#
# CTYPES SHAPING is not a wall and is named once: `(FALCON_APPLICATION_INTERFACE_ENTRY_V1
# * hdr.entryCount)(...)` at :156 spells "an array of n descriptors", so the
# layout of `FALCON_APPLICATION_INTERFACE_ENTRY_V1` is one row of the table and
# the array is a `List`. `memoryview(...).cast('I'/'Q')` (:111,:419,:306) is the
# same statement about width.
#
# ---------------------------------------------------------------------------
# ===========================================================================
# STATUS
#   PORTED:      see WHAT IS PORTED, DEF BY DEF, below.
#   NOT PORTED:  the seams and the three walls above, each with a Python line.
#   PYTHON:      tinygrad/runtime/support/nv/ip.py:1-661 (the whole file)
#
# WHAT IS PORTED, DEF BY DEF. Every def named here EXISTS; the first draft of this
# table named forty-eight defs that were never written (`ip.init_hw`, `q.init`,
# `gsp.wpr_meta`, `seq.table`, ...), which is what a plan written before the code
# looks like from the outside. The names below are the file's own namespaces.
#
#   GENERATED   cn_table / cn_rows / cn_names             the 64 U32 constants
#               st_<struct> / st_rows / st_sum_*          the 54 layouts, 413 fields
#               ce_rows / ce_min / ce_max                 the two dispatch tables
#               const_of / const_name / const_name_n       both directions
#               rpc_label / overlap / hex8                the row printers
#   QUEUE       Q / q.of / rp.{msg_size,msg_count,        :19-31 the header, the ring
#               ring_len,entry_off,hdr_len,phdr_len,      length `msgSize*msgCount`,
#               max_payload,length,elem,total,off,first,   `max_payload`, the record
#               wraps,wp_after}                            arithmetic :38-55
#   CHECKSUM    rp.{word,word2,which,w_*,fold,acc4,       :32-36 the 64-bit XOR, folded
#               wordof,pickw,finish,cksum.xor,nu64,nwords} into two U32 folds
#   TRACE       Cx / Tr / tr.{hit,put,put2,emit,go,show,   :38-55 the five calls, the
#               tagname,one,sep,at,put_seq,fail}           refusals, the render
#               rp.{record..trace,wp2,wp3,put_wp,barrier,
#               bump,door,bumped,bumped2,cont_n,cont_more,
#               cont_func,rx_up,rx_elems,rx_after,rx_tag}
#   RPC         rpc.{func_alloc,am2,am3,minted,wait,       :526-536 alloc, :534 send,
#               raise,raise2,ra_plen,rc_plen,runlist_key,  :535 wait, :84 the raise,
#               nvdec_add,nvdec0,runlist_miss}              :557 the runlist addend
#               am.{page_ok,pages_ok2,pages_ok4,plen}      :527 the page assert
#               hgen.{first,next,n,nxt7,go}                :348 the handle generator
#   FALCON      fl.{frts_offset,desc_sig,order,falcon,    :186-283 the register order
#               sec2,ctx_dma,imem,sec,dmactl,allow_phys,
#               reset_engines,dma_chunk,chunks,alias,
#               startcpu,riscv_core1,riscv_core0,init_n,
#               init_order}                               :212-234
#   WPR META    wpr.{leg..leg9,fmc} / over.fixtures_fit   :434-455 both branches
#   LIBOS       radix.{npages,offs}                        :401-423
#               bdf.{lo,mid,fn,as_int}                      :605 :608
#   PMA         pma.{is_one,phys,nomap,ro,flags,all_ones}  :345 the flag shifts
#   CLASSES     cls.{one,gpfifo,compute,dma,viddec,gp2,    :538-569
#               cp2,dm2,vd2,join4,row}
#   REGISTRY    ctx.{go,idxlist,keys3,rows,cfg_rows}       :616-627 the whole layout
#   CPU SEQ     seq.{n,words,name,ops,count,walk,prog_n,   :629-661 the opcode table,
#               prog_ops,wordlist,join,joinu,at,next_skip,  the walk, the five ops
#               put,opslist,join5} / seq_walk.go
#   FSP         fsp.{w0,w1,pad,tot,words,tail,head,        :328-344 the framing and
#               tail_off,aincw,aincr,trace,tr2,tr3,put,     the four calls in order
#               ememd,do_tail,do_head,nvmd_cot}
#   GRCTX       grctx.{keylist,keys,walk,row,size,virt,    :468-508 the map, the
#               phys,local,n,sep,tag,reuse,reuses_10,        GRBufDesc table
#               count_local,early,early2,join,join1,local_n}
#   DOORBELL    door.{bit30,rl_shift,gb2_bit,token}        :590-591 the token
#   INIT ORDER  gsp.{init_order,init_n,priv_root}           :444-455, :519
#   REFUSALS    ref.{bit_sig,wpr2,mbx,active,fsp_len,      :123, :194, :207, :210,
#               frts,mailbox,pages_ok,pages_go,bad_op,       :332, :453, :527, :660,
#               timeout}                                     :661, :91
#   GATE        t_tables / t_arith / t_trace / t_refuse / t_misc / main
#
# NOT PORTED, and each one is a SEAM or a WALL, never a simplification:
#   the device MMIO map and every register value written to it
#   the VBIOS byte scan at :110-169 -- the offsets are ported, the bytes are not
#   the payload bytes of every RPC (:526-569 assemble the framing, the fields are
#     the device's) and the `pay` term of the checksum fold
#   the one 64-BIT CONSTANT that does not fit a U32
#   `init_sw` and `init_hw` themselves, which are no-ops plus an include list --
#     the include ORDER is ported as data and the includes are not
# ---------------------------------------------------------------------------
# THE MUTATION TABLE, in prose, because the file itself is the thing under test.
#
# `python3 .agents/slop/nv_ip_mutate.py` applies ONE textual edit per rule to this
# file, runs the interpreted lane, and records how many rows moved. Thirty-seven
# mutations: thirty-three move at least one row, and FOUR cannot move any row
# because the mutant is the same function.
#
#   rd.trunc            `x - x%m` for `x/m*m`. Euclidean division gives
#                       x == q*m + r with 0 <= r < m, so subtracting r gives q*m.
#   rp.cont_more.ge     `>` -> `>=`. At plen == max_payload both guards reach
#                       `cdiv(0, max_payload) == 0`, so `rp.cont_n` answers 1.
#   rp.pickw.swap       exchange `hi` and `lo`. `rp.finish` XORs the two
#                       accumulators together, so permuting the twenty words
#                       between them is the identity -- the ENDIANNESS assumption
#                       is not gateable through the checksum at all.
#   rp.which.last_word  clamp 19 -> 18. Words 18 and 19 are both zero slots with
#                       no `rp.word2` arm, so both answer 0.
#
# Two fixtures closed the spots that were NOT arithmetic:
#
#   rp.elem.no_header   dropping the 32-byte header from `elemCount` moved NO
#                       rows, because all seven requests are small enough that
#                       `plen + 48` and `plen + 80` round to the same element
#                       count. The header matters only in the band
#                       `4096k - 79 <= plen <= 4096k - 49`, so `ip_rp_elem_4017`,
#                       `_4047` and `_4048` are the fixtures; it now moves four.
#   rp.word2.*          the twenty `ip_rp_<i>_w<k>` rows exist for this. The folded
#                       checksum sees the SET of words and their byte OFFSETS but
#                       not which index each came from, so pinning every index
#                       separately is what makes a zeroed arm move something.
#
# Two mutations found defects that prose did not:
#
#   rp.put_wp.arms_swapped   moved 8 rows, and found that the ONLY guard in the
#       file -- the one that stops the write pointer advancing past a refusal --
#       had its arms the wrong way round, so it did the opposite of its comment.
#       The oracle that missed it had tabulated `wp` BY HAND.
#   rpc.func_alloc.is_tag    moved 2 rows, and found `C_ALLOC_MEM()` passed to
#       `rp.record` WHERE PYTHON PASSES A FUNCTION ID: the alloc trace claimed to
#       send function 8 and sent 4. The trace tag and the RPC id are different
#       things, and the holes in the tag space are where the confusion lived.
#
# `rp.seq.after_door` moves exactly ONE row, `ip_refuse_at5_seq`: the sequence bump
# sits between the barrier and the doorbell (:52, :54, :55), and rung after the
# doorbell that row would read 0. Before those rows existed the position was a
# comment, and a comment cannot fail.
#
# `const_name.last_wins` is instructive for a different reason: flipping a guard
# around the existing self-call does NOTHING, because `Bool.pick` DROPS the
# untaken arm and the fold returns at the first match without ever recursing.
# First-wins is not a policy in `const_name.go` -- it is a consequence of where
# the self-call sits, and last-wins needs the recursion to move into the CALLER.
# That is the substrate fact the whole file is built on.
# ---------------------------------------------------------------------------
# THE FOUR GATE SECTIONS, and what each one can be wrong about.
#   t_tables   the 54 layouts, the 64 constants both directions, the two
#              dispatch tables. A transposed field, a wrong offset, a wrong
#              width, a wrong constant, a wrong first-wins winner.
#   t_arith    the allocator arithmetic: queue sizing, radix3, WPR meta (both
#              branches), the registry table layout, bdf_as_int, the PMA flag
#              shifts, the ctx-buffer map, the FRTS offset.
#   t_trace    the request trace for a FIXED request list: one RPC record per
#              request, the write-pointer advance, the doorbell, the handle
#              sequence, the cpu-sequencer ops, the FSP framing, the falcon
#              register order, and the init order.
#   t_refuse   each refusal: what the trace looks like after it.
#
# 1394 rows, and BOTH lanes print the same 57 KB. `ip.py` IS IN tinygrad's tree
# at the revision this port follows, so every expectation in the gate was
# produced by CALLING CPython on it -- never typed. Five units have now been
# bitten by a hand-typed expectation, and the fifth was the worst: the Stage E
# trace truncations were tabulated by hand, the table had the fault position
# backwards, and so it AGREED with a port whose write-pointer guard was
# inverted -- five green rows over a bug. `.agents/slop/nv_ip_oracle4.py` now
# EXECUTES `_send_rpc_record` with the fault raised and reads `tx.writePtr` off
# the struct, and a table of expected values cannot be wrong in the same way
# twice. The CPython runs are `nv_ip_gen.py`, `nv_ip_oracle.py`,
# `nv_ip_oracle3.py` and `nv_ip_oracle4.py`, all in the tree.
# ===========================================================================

import Base
import ../../../helpers.bend as H
import ../../../device.bend as D
