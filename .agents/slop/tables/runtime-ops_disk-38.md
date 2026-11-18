<!-- FROM: tinybendygrad/runtime/ops_disk.bend:38 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF.
#
#   tinygrad/runtime/ops_disk.py:14  `synchronize`              PORTED  `dev_sync` -- it is `pass`
#   tinygrad/runtime/ops_disk.py:16-20 `__init__`                PORTED  `dev_init`
#   GONE  the io_uring guard         PORTED  `dev_ioring_setup`, `Dev.tried` -- upstream DELETED it
#   tinygrad/runtime/ops_disk.py:21-41 `_might_open`             PORTED  `dev_might_open` and its steps
#                                             `dev_warm`, `dev_shm.on`,
#                                             `dev_file.at`, `dev_finish.at`
#   :22  the assert                 PORTED  `dev_fits`, `dev_reopen_msg` -- upstream's `size`
#                                             IS the same refusal
#   :23  the fast path              PORTED  `dev_is_open`, `dev_warm` -- upstream's `size`
#                                             IS the already-open test
#   :26  `filename`                 PORTED  `dsk_filename`
#   :28  the shm predicate          PORTED  `dev_is_shm`, `dsk_shm_name` -- upstream's `filename`
#                                             IS the same predicate's subject
#   :29-31 the shm branch            PORTED  `dev_shm.on`
#   :33-34 the try/except open       PORTED  `dev_file.open.at` -- and :34's
#                                             branch is NOT a parameter; see
#                                             THE EXCEPT IS NOT A BRANCH
#   :35  the block-device guard     PORTED  `dev_file.trunc.at`, `dev_trunc`
#   :36  the mapping                PORTED  `dev_file.mmap.at`
#   tinygrad/runtime/ops_disk.py:37-41 the tail -- upstream's `refcount` IS the
#                                             tail's last word --   PORTED  `dev_sized`, `dev_bumped`,
#                                             `dev_finish.at`
#   tinygrad/runtime/ops_disk.py:39-40 `madvise`                 PORTED  `dev_finish.at` (the condition)
#   tinygrad/runtime/ops_disk.py:42-49 `_might_close`            PORTED  `dev_might_close`
#   tinygrad/runtime/ops_disk.py:160-164 `uring`                PARTIAL `dev_ioring.*` -- the call ORDER and
#                                             the four numbers Python spells
#                                             itself; the three mmap LENGTHS are
#                                             WALL 2
#   tinygrad/runtime/ops_disk.py:51-57 `DiskBuffer`             PORTED  `Db.of`, `db_repr`, `db_buf`
#   tinygrad/runtime/ops_disk.py:59  `MAP_LOCKED`/`MAP_POPULATE` PORTED  `map_locked`, `map_populate`
#   tinygrad/runtime/ops_disk.py:61  `lru` = False               PORTED  `ALLOC_LRU`
#   tinygrad/runtime/ops_disk.py:62-64 `_alloc`                  PORTED  `alloc_of` (`mv_address` is WALL 1)
#   tinygrad/runtime/ops_disk.py:66  `_free`                     PORTED  `alloc_free`
#   tinygrad/runtime/ops_disk.py:67  `_as_buffer`                PORTED  `alloc_as_buffer`
#   tinygrad/runtime/ops_disk.py:68  `_copyin`                   PORTED  `alloc_copyin`
#   tinygrad/runtime/ops_disk.py:69-77 `_copyout`                PORTED  `alloc_copyout`
#   GONE  the NON-uring shard    PORTED  `shard_at`, `shard.go`, `shard_read`,
#                                             `shard_real` -- upstream 4e4f6b9fb DELETED it
#   tinygrad/runtime/ops_disk.py:88-111 `disk_read`              PARTIAL `shard_ioring` -- the two submission
#                                             calls and the segment arithmetic
#   tinygrad/runtime/ops_disk.py:79 `_offset`                   PORTED  `alloc_offset`
# END BLOCK
