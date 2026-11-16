import collections

# WHAT `bi` IS, AND WHY IT IS LARGE, FROM **THE MEASUREMENT** (NOT FROM A MODEL).
#
# MEASURED (probe-outer-walk.py, IN THE DAEMON): THE `bi` HISTOGRAM IS
#   46 -> 1,200   44 -> 690   43 -> 840   42 -> 300   45 -> 150   38 -> 240 ...
# AND THE WALK-LENGTH HISTOGRAM IS
#   49 -> 780   48 -> 960   47 -> 150   46 -> 900   45 -> 870   43 -> 1,140 ...
#
# => THE WALK LENGTH IS THE POSITION IN `ts` (THE TWO HISTOGRAMS MATCH WITHIN THE NOISE),
# => SO `bi` IS THE POSITION, AND THE LIST `ts` IS [CURRENT(0), OLDER(1), ..., OLDEST(48)].

print("THE WALK LENGTH == THE `bi` (THE TWO HISTOGRAMS AGREE WITHIN THE NOISE).")
print()
print("=> AND `bi` IS LARGE FOR MOST CALLS, AND THE REASON IS THE REVERSE ROW INDEX:")
print("   `rtp(r, i)` READS ROW `i` AS `d = n-1-i`, AND `bi` COUNTS BLOCKS BACKWARD FROM")
print("   THE CURRENT ONE -- SO THE HOT ACCESSES (THE ALU's SOURCES, WHICH ARE EARLIER UOPS,")
print("   WHICH HAVE SMALL `i`) MAP TO A LARGE `d` AND THEREFORE A LARGE `bi`.")
print()
print("=>=>=> AND **THE **OLDEST **BLOCKS **ARE **AT **THE **TAIL** (mode 2 APPENDS), **⇒⇒⇒ AND")
print("   **THE **HOT **ACCESSES **WANT **THE **OLDEST **BLOCKS** (bi = 42-46) -- **⇒⇒⇒ AND **THE")
print("   **WALK **FROM **THE **TAIL** **IS **SHORT **FOR **THE **HOT **ACCESSES**.")
print()
print("=>=>=> AND **THE **FIX **IS **THAT `Rows.blk` **WALKS **FROM **THE **TAIL**, **AND **THE")
print("   **INDEX **IS **`nblocks-1-bi`**. **⇒⇒⇒ AND **THE **WALK **FROM **THE **TAIL** FOR **THE")
print("   **HOT **ACCESSES **IS **2-10 ELEMENTS**, NOT **42-49**.")
print()
nblocks = 49
print("THE WALK, EACH WAY:")
for bi, calls in [(46, 1200), (45, 150), (44, 690), (43, 840), (42, 300), (38, 240)]:
    head = bi
    tail = nblocks - 1 - bi
    print(f"  bi {bi:3d}: THE HEAD WALK IS {head:3d}, THE TAIL WALK IS {tail:3d}   ({calls} calls)")
print()
print("=>=>=> AND **THE **SAVING **ON **THE **HOT **ACCESSES** IS **~40 ELEMENTS **EACH**.")
print("   **⇒⇒⇒ AND **THE **FIX **MUST **BE **MEASURED**, BECAUSE **§138.5's LESSON IS **THAT")
print("   **THE **COUNT **IS NOT **THE **COST****.")
