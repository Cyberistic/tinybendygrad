# `extra/datasets/` — the export slice: 13 rows, 10 stubs, 3 refusals

**HEAD `6dab8e95d80f77054460f98ce9c723f641b6fb1a` (`6dab8e95d`) · read `2026-10-19T03:52:24Z` ·
upstream read from the worktree `extra/datasets/` (identical bytes at HEAD; `git show HEAD:<path>`
agrees) · machine load `8.61` at start.**

Denominator: **13**, the number of `extra/datasets/` rows in
`.agents/slop/exledger/examples.manifest.rows` (lines 273–285). A count without that
denominator is not a result, so it is named here and in `summary.rows`.

## THE COUNTS

| class | n | of 13 |
|---|---:|---|
| **(a)** thin `fetch`/tar/gunzip wrapper | **0** | 0% |
| **(b)** needs real porting | **10** | 77% |
| **(c)** not worth porting | **3** | 23% |
| written `.bend`, all `ALL PROOFS CHECK` | **10** | 10 of 10 |
| could NOT reach `ALL PROOFS CHECK` | **0** | — |

**The brief's expectation that these loaders are "largely a call to `fetch`" is FALSE, and the
denominator for that claim is the same 13.** I set out to find a class-(a) file and there is not
one. Not one of the 11 `.py` files is a bare downloader: every one reaches `PIL`, `librosa`,
`nibabel`, `boto3`, `pandas`, `transformers`, `torch`, `gdown`, `tarfile`, `multiprocessing` or
`unicodedata` on its own body, and the two that are *nearly* bare —
`imagenet_download.py` and `wikipedia_download.py` — both unpack and check checksums. **The one
thing they all share is not thinness, it is the shared seam:** `fetch` is unported for the entire
slice (`tinybendygrad/helpers.bend:2815`), and no ndarray exists to receive the bytes.

## TWO MEASUREMENTS THAT CHANGED A DECISION

### 1. ImageNet is NOT behind a login. I nearly filed a recalled claim as a finding.

`extra/datasets/imagenet_download.py` is the obvious class (c) — "a dataset behind a licence, or a
downloader that needs credentials", the brief's own example. So I measured it instead of
recalling it:

```
$ curl -sSL -o /dev/null -m 12 -w '%{http_code} %{content_type} %{size_download} %{redirect_url}\n' \
    https://image-net.org/data/ILSVRC/2012/ILSVRC2012_img_val.tar
http=200 type=application/x-tar, 86900736 of 6744924160 bytes received (12s cap hit)
```

Anonymous, unauthenticated, and it **starts**. The download is open. `imagenet_download.py` is
therefore class **(b)** and a stub was written. Had I filed it as (c) on memory, I would have
recorded a licence wall that does not exist — which is exactly the failure AGENTS.md's doctrine 1
warns about, reproduced inside the census of doctrine 1. `openimages.py` got the same treatment:
its bucket is `botocore.config.Config(signature_version=botocore.UNSIGNED)` (upstream:112), public
data, so (b) as well.

### 2. `preprocess_imagenet.py` cannot run, and the reason is an upstream hole.

```
$ grep -n "iterate" extra/datasets/imagenet.py          # NO MATCH
$ grep -rn "^def iterate" extra/datasets/
extra/datasets/kits19.py:73:def iterate(files, preprocessed_dir=None, val=True, shuffle=False, bs=1):
extra/datasets/squad.py:133:def iterate(tokenizer, start=0):
extra/datasets/librispeech.py:67:def iterate(bs=1, start=0):
```

Line 2 is `from extra.datasets.imagenet import iterate, get_val_files` and `imagenet.py` defines no
`iterate`. So the file raises `ImportError` at import time and **has never run**. The stub's stop
point is line 2, not line 6, and — this is the part that matters for a 1:1 port — `imagenet.bend`
ports `get_val_files` but is **not** given an `iterate`, because inventing the symbol would port a
fix upstream does not have and would hide the defect behind a green check.

## PER-FILE, WITH THE DECISIVE LINES

**(b) — stub written, `--check-only` = `ALL PROOFS CHECK`**

| upstream | LOC | the quoted line that made it (b) |
|---|---:|---|
| `__init__.py` | 43 | `[0x10:]` / `[8:]` IDX header offsets (8-9) and `assert idx == X.shape[0] and X.shape[0] == Y.shape[0]` (31) — array plumbing, not a download |
| `fake_imagenet_from_mnist.py` | 40 | `Image.fromarray(img).resize((224,224)).convert('RGB').save(...)` (19) and `with Pool(64) as p` (36) |
| `imagenet.py` | 91 | `glob.glob(p := str(BASEDIR / "val/*/*"))` under `if getenv("MNISTMOCK"):` (13, 34); `F.interpolate`-style 100-try sampler (63) |
| `imagenet_download.py` | 51 | `images.sort()` (22) then `os.replace(.../<image>, .../<synset>/<image>)` (26) — label N goes to the Nth sorted name |
| `kits19.py` | 219 | `F.interpolate(..., mode="trilinear", align_corners=True)` for image vs `mode="nearest"` for label (38-39); `padding_val=-2.2` (108) must sit outside `np.clip(image, -79.0, 304.0)` (45) |
| `openimages.py` | 209 | two chained `isin` joins (101-102) and `pd.factorize(...)[0]` numbering images by first appearance (77) |
| `preprocess_imagenet.py` | 21 | `from extra.datasets.imagenet import iterate, get_val_files` (2) — unresolvable, see above |
| `squad.py` | 148 | `min(num_left_context, num_right_context) + 0.01 * doc_length` (53) and stride `min(length, 128)` (85) are pure and worth porting first; blocked on `fetch` (11) and `BertTokenizer` (4) |
| `wikipedia.py` | 398 | `_is_punctuation`'s four ranges (39), `_is_chinese_char`'s eight ranges (44-51), greedy `##` wordpiece (116-121) — the best value-per-line in the slice |
| `wikipedia_download.py` | 53 | `if not os.path.exists(os.path.join(path, "results4"))` (14) and the md5 `raise ValueError` (30-34) |

**(c) — no file written**

| upstream | why |
|---|---|
| `librispeech.py` (82) | **No tinygrad API at all** — the manifest's `MINIMAL_COPY` is right and I confirmed it: the imports are `json`, `pathlib`, `numpy`, `librosa`, `soundfile`. Every computation is `librosa.filters.mel` / `librosa.stft` (22-23, 32) or `soundfile.read` (64). The corpus is a **manual** openslr.org/12 download plus an `ffmpeg` flac→wav pass (docstring 8-16). There is nothing to port into tinygrad and nothing to verify against. |
| `.gitignore` (4) | An **asset row, not a `.bend`**: four download-directory names (`imagenet`, `imagenet_bak`, `mnist`, `open-images-v6TEST`) and zero API. Copying the bytes would only teach git to ignore four directories this port cannot create, since `fetch` is unported. The manifest's disposition is `VERBATIM_COPY` and `ported_path` is the `.gitignore` itself — this is the orchestrator's call, not a `.bend` stub's. |
| `sops.gz` (836) | A **binary asset, not source**: gunzips to 4,457 lines of captured `UOp(Ops.SINK,dtypes.void,...)` debug text, and `grep -rn "sops" extra/datasets/*.py` finds **no reference** — a dangling artifact. |

## THE STUB SHAPE, AND WHY IT REFUSES RATHER THAN RETURNS EMPTY

Every def returns `D.Refused`, **not upstream's return type**. `fetch_mnist` returns four ndarrays
(or four `Tensor`s); returning an empty list — the thin stub's reflex — is indistinguishable from a
dataset of size zero, and a loader that can report an empty dataset instead of admitting it is
absent is the one lie this directory must not tell. `Refused{at}` carries the upstream
`path:line function` of the missing def, so a refusal names an address rather than claiming there
is no work.

`Refused`/`refuse` are declared **once**, in `tinybendygrad/extra/datasets/__init__.bend`, and the
nine siblings `import ./__init__.bend as D`. One definition, not ten copies — and the manifest's
own `__init__.py` row is the natural home, matching upstream's own package entry.

## THE PILOT'S FAILURE MODE, AVOIDED AND VERIFIED

`.agents/slop/exledger/README.md` records that an honestly-refusing stub reported `SOME PROOFS FAIL`,
and that `checks/substrate.py` defines `COLD` as exactly `first line != "ALL PROOFS CHECK"`. I
confirmed that mechanism before writing anything: a file calling `nosuchdef(1)` reports
`SOME PROOFS FAIL` / `- expected : a defined name`. So every stub imports the one thing it
references (`./__init__.bend as D`) and names nothing else.

**Verified 2026-10-19, `./bin/bend <file> --check-only`, first line, all ten:**

```
__init__.bend                  ALL PROOFS CHECK
fake_imagenet_from_mnist.bend  ALL PROOFS CHECK
imagenet.bend                  ALL PROOFS CHECK
imagenet_download.bend         ALL PROOFS CHECK
kits19.bend                    ALL PROOFS CHECK
openimages.bend                ALL PROOFS CHECK
preprocess_imagenet.bend       ALL PROOFS CHECK
squad.bend                     ALL PROOFS CHECK
wikipedia.bend                 ALL PROOFS CHECK
wikipedia_download.bend        ALL PROOFS CHECK
```

**10 of 10, zero failures, zero `NOT-RUN` among written files.** No stub needed `@unsafe`, which
`bend2-constraints.md` §1.5 flags as the thing that turns a green file red, so no `AFFINITY.tsv`
entry is owed.

## WHAT THIS DOES NOT ESTABLISH

- **No stub has ever been executed.** `--check-only` is termination and type checking, and
  `Use --verdict for mathematical validity` is its own second line. A `Refused` carries no claim
  about the upstream algorithms being right; the per-file tables above are claims about *upstream*
  code, read and quoted, and the port carries none of it yet.
- **The 10 stubs now exist in the substrate census.** Per the exledger README they should read WARM
  (`ALL PROOFS CHECK`), but that is a claim about `checks/substrate.py`'s definition of COLD, which
  I did not run (out of scope for this unit). If the census disagrees, this report is the thing to
  check first.
- **`checks/substrate.py`'s import-graph sweep now sees `tinybendygrad/extra/datasets/`** for the
  first time — 10 new files and a new directory. Whether the census wants that directory is not a
  question this unit may answer.
- **`tinybendygrad/extra/` is a SHARED WRITABLE DIRECTORY, and it is not only mine.**
  `tinybendygrad/extra/models/resnet.bend` was already present when this unit finished and belongs
  to the `extra/models/` slice, not this one; this report's counts, the `summary.rows` rows and
  every `--check-only` line above cover **`extra/datasets/` only — 13 rows, 10 stubs, 547 LOC**.
  This is the AGENTS.md "shared writable path named in an instruction" class, with
  `tinybendygrad/extra/` as the shared path and `extra/datasets/` as the per-unit key. Do not read
  a census over `tinybendygrad/extra/` as this slice's result.
- **Counts in this report are a snapshot.** HEAD moved from `80d329a33` (when the slice was read)
  to `6dab8e95d` (when the report was written) inside this session; `extra/datasets/` was not
  touched in between, but nothing here is pinned.

## SUGGESTED ORDER, IF THE ORCHESTRATOR WANTS THE NEXT UNIT

`wikipedia.py`'s `_is_punctuation` and `_is_chinese_char` first: pure integer ranges, no ndarray, no
`fetch`, no network — the only (b) work in this slice that a substrate change cannot gate. Then
`squad.py`'s `_check_is_max_context` and span loop on the same grounds. Everything else in these 13
rows waits on `fetch` (`helpers.bend:2815`), and `fetch` is one file-wide decision, not 10.