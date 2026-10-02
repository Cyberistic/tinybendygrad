#!/usr/bin/env python3
"""Regenerate the MUTATION TABLE inside a .bend file from the harness's output.

    .venv/bin/python .agents/slop/mt-table.py <file.bend> <mt_mutate-output.txt>

The prose column ("what it is testing") is KEPT: the harness measures the "rows
moved" column and knows nothing about what a mutation is for. Prose for an id the
file already has is reused; prose for a new id comes from EXTRA below; an id with
neither is a FAILURE, because a table row with an empty last column is a row
nobody will read twice.
"""
import re, sys
from pathlib import Path

EXTRA = {
  "M17": ":247's argument evaluation order. Now ONE row -- and that is the point: before `cns_string` was wired this mutation was refused with `PATTERN MATCHES 0x` because the pattern no longer existed, which is what a stale table entry looks like.",
  "M17b": ":247's NSString. `pipe_pat` compares the WHOLE list, so a missing call in the MIDDLE is a length mismatch, and eight rows move because every ICB builds a pipeline per command.",
  "M42": ":47's `if error == 0`. Four rows and not one, because inverting it also inverts `mt_cb_ok_live` -- which is what makes this a test of the arm rather than of the constant.",
  "M43": "the error arm's RAISE. One row, and one is right: a refusal that still made both calls is exactly what `mt_cb_bad_calls` exists to distinguish from skipping them.",
  "M44": "the error arm's ORDER -- refuse before the call rather than after. Two rows, and they are the two COUNT rows, so the table records that the port calls first and refuses second.",
  "M45": ":50's header sum, on the value a REAL reply carried. This is the row that did not exist before this session: `mt_liboff42` and `mt_liboff00` were synthetic and 104 was unreachable.",
  "M46": "THE TWO BLOBS. Printing MTLB as the reply's leading word moves `mt_reply_is_mtlb` to True and the row then says the un-sliced reply carries the magic, which it does not. `nv_query_litter` in two rows.",
  "M47": "the compiler's error code. One row, because `CB_ERR_COMPILE` is also `cc_error_ok`'s input and M42 covers the consumer.",
  "M48": ":55-56's ladder at the HOST's version, so the four-way ladder is checked at the value it will actually be asked about.",
  "M49": ":70's ENDT conjunct. **THIS MOVED 0 ROWS BEFORE THE FIXTURE.** Every fixture fed `ccompile.ok` a good pair, and both magics are CONSTANTS, so the check was only ever asked a question it had been told the answer to. `mt_cb_badtail` and `mt_cb_badhead` are the negative halves.",
  "M50": ":276-281's walk: drop the per-entry work and keep walking. Two rows and both are COUNT rows at two sizes, which is the fixture M51 needed.",
  "M51": "the scan losing its LAST entry. **ALSO 0 BEFORE THE FIXTURE**: `mt_sync_scan_idx` read `sync_starts` DIRECTLY, so the row never went through the def under repair, and `sync_starts` is unchanged by such a bug. `mt_sync_scan_calls21` is the second size.",
  "M52": "the guard, through the scan rather than through `sync.one`. One row, the guarded arm's count.",
  "M53": ":267's weak-dictionary count. One row, and adding ZERO is the mutation that matters: the entry is created and the count does not move, which is a bug an `nics`-reading gate would miss.",
  "M54": "`str_list_eq`'s ELEMENT comparison. **ALSO 0 BEFORE THE FIXTURE**, and for a worse reason than M49: `mt_tbl_handles` and `mt_tbl_sels` compare the table against a copy of the table INSIDE THIS FILE, so the lengths always agree and deleting the element walk changed nothing. `mt_tbl_reorder` (same length, two names swapped) and `mt_tbl_wrong` (same length, one name changed) are the two negatives a length check cannot see.",
  "M54b": "the same walk made unconditional. Two rows and not four, because the two POSITIVE rows cannot tell.",
  "M55": ":112's 256. Twenty-one rows and one of them is `mt_c_arg_align`; the other twenty are the layout, the header word and the ICB's byte offset, which is the composability claim.",
  "M56": ":278's scan start. Fourteen rows: the profile scan's count, its index list at three lengths, AND the new `mt_sync_scan_*` pair.",
  "M57": "the magic's ENDIANNESS. Two rows and both would read as plausible -- this is the failure mode the seam's two-blob rows exist to make visible.",
  "M58": "`:116`'s `len(dims)`. One row, and one is a FINDING: `DIM_WORDS` feeds nothing but the fixture's symbolic mask, so before `mt_c_dim_words` existed it was invisible. `mt_c_all_syms` catches the mask.",
  "M59": "(1 << len(dims)) - 1, on a NON-ALL mask. Two rows, and `mt_dims_all` is the one that would have caught a fixture that stopped being all-symbolic.",
  "M60": "one of the eighteen selector indices. Two rows, and it is the LAST one, so a table that dropped its tail would still agree on the other seventeen -- which is why `mt_sel_n` counts.",
  "M61": "the ICB's word index. Two rows, and the `mt_hdr_icb` half is the one that is about the header layout rather than the trace.",
}


def main():
  bend, out = Path(sys.argv[1]), Path(sys.argv[2])
  src = bend.read_text()
  measured = {}
  for line in out.read_text().splitlines():
    m = re.match(r"^\| (M\w+) \| (.*?) \| (.*?) \|$", line)
    if m: measured[m.group(1)] = (m.group(2), m.group(3))
  prose = {m.group(1): (m.group(2), m.group(3))
           for m in re.finditer(r"^# \| (M\w+) \| (.*?) \| .*? \| (.*?) \|$", src, re.M)}
  missing = [k for k in measured if k not in prose and k not in EXTRA]
  print("no prose for", missing) if False else None
  if missing:
    sys.exit(f"NO PROSE for {missing}: add them to EXTRA or to the file's table")
  lines = []
  for mid, (what, moved) in measured.items():
    p = prose[mid][1] if mid in prose else EXTRA[mid]
    n = 0 if "NOTHING" in moved else moved
    lines.append(f"# | {mid} | {what} | {n}{'' if 'NOTHING' in moved else '  ' + moved.split('  ', 1)[1] if '  ' in moved else ''} | {p} |")
  table = "\n".join(lines)
  block = re.compile(r"(# \| # \| the edit \| rows moved \| what it is testing \|\n# \| --- \| --- \| --- \| --- \|\n)(?:# \|.*\n)+")
  if not block.search(src):
    sys.exit("could not find the table block")
  bend.write_text(block.sub(lambda m: m.group(1) + table + "\n", src, count=1))
  print(f"{bend.name}: wrote {len(lines)} rows; "
        f"{sum(1 for l in lines if '| 0 |' in l)} move nothing")


if __name__ == "__main__":
  sys.exit(main())
