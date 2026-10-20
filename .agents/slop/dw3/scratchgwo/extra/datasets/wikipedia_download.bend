# STUB -- 1:1 PATH MIRROR of extra/datasets/wikipedia_download.py (53 LOC upstream). NOT YET PORTED.
#
# WHAT UPSTREAM IS. The MLPerf BERT 2020 corpus fetcher, off Google Drive. Not class
# (c): the Drive ids are public links and `gdown` is a plain HTTP client, not a
# credentialed account. It is (b) because its real work is the UNPACK and the CHECKSUM.
#   * `wikipedia_uncompress_and_extract` (upstream:13) is gated on
#     `if not os.path.exists(os.path.join(path, "results4"))` (upstream:14) -- an
#     extracted-PRESENT probe, not an extracted-COMPLETE one -- then
#     `tarfile.open(file, 'r:gz')` + `extractall` + `os.remove(file)` (upstream:16-18),
#     and only THEN, still inside the `with`, `tar.extract` per member (upstream:19-22),
#     which is redundant after `extractall` and is upstream's business, not this
#     port's to fix.
#   * `verify_checksum` (upstream:24) is the part that must not be softened: it
#     `hashlib.md5()`s each file in 4096-byte blocks (upstream:30-32) and
#     `raise ValueError(f"Checksum does not match for file: {file_path}")` (upstream:34).
#     `folder_name[2:]` (upstream:29) strips the leading `./` the checksum file
#     writes, so a path that does NOT start with `./` is read from the wrong place.
# TODO(port): STOPPED AT `gdrive_download` (extra/datasets/wikipedia_download.py:10).
#   MISSING: `gdown` -- upstream's own line 1 is `# pip install gdown`, i.e. a
#   third-party dependency this port does not carry, and Google Drive serves these
#   through a confirm-token interstitial rather than a plain GET, so it is not
#   `fetch` either. AFTER it: `tarfile` for the unpack, and `hashlib.md5` -- the port
#   has no MD5, and "just skip the checksum" is the exact deletion this stub exists to
#   prevent, because `VERIFY_CHECKSUM` (upstream:50) is how the corpus proves it is
#   the corpus MLPerf scored. `getenv` IS ported (`helpers.bend:148` `getenv_str`,
#   `:299` `getenv_int`), so lines 46/50/54 are the only part already reachable.
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `wikipedia_uncompress_and_extract`
#   (upstream:13), `verify_checksum` (upstream:24), `download_wikipedia`
#   (upstream:37), and the `__main__` block (upstream:53).
import Base
import ./__init__.bend as D

# upstream: `def gdrive_download(url:str, path:str)` -> None, skipped if `path` exists
def gdrive_download(url: String, path: String) -> D.Refused:
  D.refuse("extra/datasets/wikipedia_download.py:10 gdrive_download")

# upstream: `def wikipedia_uncompress_and_extract(file:str, path:str, small:bool=False)`
def wikipedia_uncompress_and_extract(file: String, path: String, small: Bool) -> D.Refused:
  D.refuse("extra/datasets/wikipedia_download.py:13 wikipedia_uncompress_and_extract")

# upstream: `def verify_checksum(folder_path:str, checksum_path:str)` -> None
def verify_checksum(folder_path: String, checksum_path: String) -> D.Refused:
  D.refuse("extra/datasets/wikipedia_download.py:24 verify_checksum")

# upstream: `def download_wikipedia(path:str)` -> None
def download_wikipedia(path: String) -> D.Refused:
  D.refuse("extra/datasets/wikipedia_download.py:37 download_wikipedia")