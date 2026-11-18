<!-- FROM: tinybendygrad/runtime/support/hcq2.bend:11 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF. `hcq2.py` is 646 lines and most of it is a
# `graph_rewrite` over the UOp ARENA, which `uop/ops.bend` owns and this file
# must not re-derive. What survives as PURE ARITHMETIC is the queue model, and
# that is what is here.
#
#   hcq2.py:16 `HCQ_CACHE_THRESH`         PORTED  symbol=HCQ_CACHE_THRESH
#   tinygrad/device.py:19 `HCQ_DEVS`        PORTED  `HCQ_DEV_*` BOTH directions symbol=HCQ_DEVS
#   hcq2.py:29 `all_devices_in`           PORTED  `all_in` symbol=all_devices_in
#   hcq2.py:31 `get_enqueue_devs`          PORTED  `enq_*` (the table + refusals) symbol=get_enqueue_devs
#   hcq2.py:39 `unwrap_view`               PORTED  `view_*` (the offset arithmetic) symbol=unwrap_view
#   hcq2.py:45 `unwrap_lane`               PORTED  `lane_of` symbol=unwrap_lane
#   tinygrad/helpers.py:21 `to_name`       PORTED  symbol=to_name -- hcq2.py CALLS it in `make_submit`
#   hcq2.py:52 `timeline`                  PORTED  `tl*` symbol=timeline
#   hcq2.py:53 `timeline_value`            PORTED  symbol=timeline_value
#   hcq2.py:60 `make_submit`               PORTED  `submit_of` + `Tr` SUBMIT symbol=make_submit
#   hcq2.py:114 `layout_args`              PORTED  `layout` -- THE CITED ONE symbol=layout_args
#   hcq2.py:118 `pack_args`                PORTED  `pack` symbol=pack_args
#   hcq2.py:129 `cstruct`                  PORTED  `cstruct` FIELD ORDER symbol=cstruct
#   hcq2.py:234 `slot`                     PORTED  `slot` symbol=slot
#   hcq2.py:235 `queue_signal`             PORTED  `qsig` symbol=queue_signal
#   hcq2.py:236 `stamps`                   PORTED  `stamps` -- the `n -> n*2` symbol=stamps
#   hcq2.py:238 `_wait_ins`                PORTED  `waits` + `Tr` WAIT symbol=_wait_ins
#   hcq2.py:241 `_start_ins`               PORTED  `start` + `Tr` BARRIER/WAIT symbol=_start_ins
#   hcq2.py:244 `_build_queues`            PORTED  `build_queues` -- THE ORDER symbol=_build_queues
#   hcq2.py:288 `_finalize_batch`          PORTED  `finalize` + `Tr` FENCE/SUBMIT symbol=_finalize_batch
#   hcq2.py:311 `sched_batches`            PORTED  `copyq`, `qname_of`, `nqueues` symbol=sched_batches
#   hcq2.py:357 `__init__`                 PORTED  `hwq` symbol=__init__
#   hcq2.py:364 `q`                        PORTED  symbol=q -- THE WORD SEQUENCE
#   hcq2.py:377 `loop`                     PORTED  `loop_*` symbol=loop
#   hcq2.py:385 `memory_barrier`           PORTED  a no-op (records nothing) symbol=memory_barrier
#   hcq2.py:386 `submit`                   PORTED  `Tr.raise` -- THE REFUSAL symbol=submit
#   hcq2.py:93 `_is_link_patch`            PORTED  `is_link` (the ladder) symbol=_is_link_patch
#   hcq2.py:100 `patch`                    PORTED  `pkey` (the group key) symbol=patch
#   GONE upstream at this pin, each named with the construct that SURVIVED it:
#   `select_lane` (folded into upstream's `unwrap_lane`, tinygrad/runtime/support/hcq2.py:45 symbol=unwrap_lane),
#   `CDTYPE` (`dtypes.uints` at tinygrad/runtime/support/hcq2.py:130), `cfield` (`7d2420e64`;
#   `cstruct` at tinygrad/runtime/support/hcq2.py:129 reads the fields),
#   `STAGING_SIZE`/`STAGING_SLOTS` (`6816873ad`), `epilogue_queue` (`dc9af790e`,
#   the queues are built by `_build_queues` at :244), and `sched_tl`/`staging_chunk`,
# END BLOCK
