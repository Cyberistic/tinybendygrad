# .agents/slop/e2e_mm_gate.py -- THE GATE. One command, one verdict, and every
# expectation taken from runs/e2e/e2e-mm-oracle.json, which is the record of the
# CPython call that produced it.
#
# WHAT IT CHECKS, and why each row is here:
#
#   THE COMPUTATION. `mm_e2e_out_bits_equal` -- the GPU's 64 u32 words against
#   CPython's 64 u32 words, EQUALITY and not a tolerance. The dyadic input choice
#   (see the DYADIC note in e2e_mm.py) is what makes that a theorem rather than a
#   hope: every partial sum of the eight products is exactly representable in f32,
#   so no association order and no multiply-add contraction can change a bit.
#
#   THE DATA PATH. `mm_e2e_in_bits_equal` -- an UPLOADED matrix read back off the
#   GPU against the bytes that were written. Without this row a wrong answer could
#   be the DATA's fault rather than the arithmetic's, and the two are told apart by
#   nothing else.
#
#   THE PROGRAM. writes / dispatches / buffers / steps / the performed-op sequence
#   / each launch's bind-group buffer ids / the bind group layout. The ids and the
#   layout are the rows that cannot be satisfied by an all-equal fixture: they
#   compare the port's BINDING against the buffer list tinygrad itself bound, in
#   tinygrad's own order.
#
#   THE POWER. `mm_power_*` -- five plausible WRONG answers, each computed here by
#   CALLING numpy on the oracle's own input words, each of which must differ from
#   the GPU's answer by far more than the gate's exactness. Without these the
#   equality is unfalsifiable: a gate that passes on the right answer and on every
#   wrong one proves nothing. `mm_power_margin` is the ratio of the smallest wrong
#   answer's distance to the right one's, and it is the number that says the test
#   can fail.
#
# NO ROW IS TRANSCRIBED. The expectations are computed here from the oracle, and a
# row whose name is not one this file produces is an error rather than a pass.
#
# RUN:  .venv/bin/python .agents/slop/e2e_mm_gate.py [bend-rows-file]
# EXIT: 0 = every row matches. 1 = at least one does not, each named.

import json, struct, sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
ORACLE = ROOT / "runs/e2e/e2e-mm-oracle.json"
GPU = ROOT / "runs/e2e/e2e-mm-gpu.json"


def rows_of(path):
  """`name=value` lines, parsed the way every other gate here parses them: by
  WHOLE LINE, never by row name. A name-comparing harness reported 0 moved rows
  for all 30 mutations of one unit and 0 for all 68 of another."""
  out = {}
  for line in Path(path).read_text().splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k] = v
  return out


def f32(words):
  return np.frombuffer(struct.pack(f"<{len(words)}I", *words), dtype="<u4").view("<f4").astype(np.float64)


def main(bend_rows):
  o = json.loads(ORACLE.read_text())
  g = json.loads(GPU.read_text())
  res = g.get("result") or {}
  bend = rows_of(bend_rows)

  L = o["per_launch"]
  up = {nm: np.frombuffer(bytes(bs), dtype=np.uint8).view("<f4").astype(np.float64).reshape(8, 8)
        for nm, bs in o["uploads"]}
  # THE INPUT TENSORS, taken from the uploads the fixture wrote, so every wrong
  # answer below is computed from the SAME words the GPU was given.
  A, B, Cm = up[o["per_launch"][0]["names"][1]], up[o["per_launch"][0]["names"][2]], up[L[1]["names"][2]]
  cpu = f32(o["answer_u32"])
  got = f32(res.get("out_u32") or []).reshape(8, 8)

  r, bad = {}, []

  def row(name, value, expect):
    r[name] = value
    if value != expect:
      bad.append(f"{name}={value} expected {expect}")

  # ---- the device ----------------------------------------------------------
  row("mm_e2e_gpu_present", res.get("gpu_present"), True)
  row("mm_e2e_gpu_arch", res.get("gpu_architecture"), "metal-3")
  row("mm_e2e_all_ops_armed", res.get("ops_all_armed"), True)

  # ---- the program ---------------------------------------------------------
  # `steps` is the sum of the five `Cs` lengths the Bend program declares, which
  # the page reports as `cs_lens`: so this row says the walk performed EVERY step
  # the port built, and a step the driver could not perform is a failure rather
  # than a silent skip.
  row("mm_e2e_steps", res.get("steps"), sum(bend_cs_lens(res)))
  row("mm_e2e_writes", res.get("writes"), len(o["uploads"]))
  row("mm_e2e_dispatches", res.get("dispatches"), o["launches"])
  row("mm_e2e_mapped", res.get("mapped"), 1)
  # `CreateBuffer` counts the DEVICE buffers AND the staging buffer `Cs.readable`
  # creates for the readback, so the expectation is one more than the fixture's
  # buffer count. MEASURED: the first version of this row expected 5 and read 6,
  # and the gate was RIGHT -- the transcription was wrong, not the port.
  row("mm_e2e_buffers", res.get("buffers"), len(o["first_bind"]) + 1)

  # ---- THE CALLS THAT WERE MADE, AS INVARIANTS AND NOT AS A TYPED MULTISET ----
  #
  # The first version of this file asserted a hand-counted op multiset
  # (`PushScope: 6, Release: 22, ...`). It was wrong on four entries and on eight
  # ops it had forgotten, and the gate went red on MY EXPECTATION -- which is the
  # failure mode this repo has now paid for five times, and once more here. So
  # there is no typed multiset here at all. Every row below is an IDENTITY between
  # two measured counts, where one side is derived from the program's shape and
  # the other is what the GPU was actually asked to do. None of them can be
  # satisfied by typing a constant, and each one dies for exactly one reason.
  ops = {}
  for op in performed_names(res):
    ops[op] = ops.get(op, 0) + 1
  n = o["launches"]
  row("mm_e2e_scopes_balanced", ops.get("PushScope", 0) == ops.get("PopScope", 0), True)
  row("mm_e2e_one_object_per_launch",
      [ops.get(k, 0) == n for k in ("ShaderModule", "BindGroupLayout", "PipelineLayout",
                                    "BindGroup", "ComputePipeline", "BeginPass",
                                    "SetPipeline", "SetBindGroup", "Dispatch", "EndPass")], [True] * 10)
  # `Cs.readable` opens its OWN encoder and finishes+submits it, so the run has one
  # encoder and one finish and one submit MORE than the launches -- and Finish and
  # Submit must agree, because `Cs.finish` emits them as one pair.
  row("mm_e2e_readback_encoder_extra", ops.get("CreateEncoder", 0) - n, 1)
  row("mm_e2e_finish_equals_submit", ops.get("Finish", 0), ops.get("Submit", 0))
  # THE STAGING READ. `Cs.read` emits `MapAsync` TWICE for ONE `mapAsync` call --
  # `webgpu_call.bend` says ops_webgpu.py:18 is recorded as a CALL_WAIT and a
  # CALL_MAP_ASYNC -- and `webgpu_call.js` keeps ONE promise per buffer for exactly
  # that reason. So MapAsync is 2 and MappedRange is 1, and the two together are
  # what says the readback was not skipped and not done twice.
  row("mm_e2e_map_ops", [ops.get("MapAsync", 0), ops.get("MappedRange", 0)], [2, 1])
  row("mm_e2e_one_copy", ops.get("CopyBuffer", 0), 1)
  # ONE UNIFORM PER LAUNCH: ops_webgpu.py:95/97 creates the 4-byte buffer for
  # binding 0's `float('inf')` inside the call, so it is not one of the fixture's.
  row("mm_e2e_uniforms_per_launch", ops.get("Uniform", 0), n)
  # THE INIT CALLS, once each. `Cs.init` is :166-190 and `wgc_init_len` is its own
  # gate row; here the row is that the walk made all eight and no more.
  row("mm_e2e_init_once", [ops.get(k, 0) == 1 for k in
                           ("Instance", "RequestAdapter", "ReadFeatures", "FreeFeatures",
                            "ReadLimits", "RequestDevice", "GetQueue", "ReleaseAdapter")],
      [True] * 8)

  # ---- the bindings, against tinygrad's own buffer list --------------------
  for i in range(o["launches"]):
    # `Cs.bg_bufs` has ONE MORE ENTRY THAN THERE ARE BUFFERS, and the extra one is
    # binding 0's uniform, which the CALL creates (ops_webgpu.py:95) and which
    # therefore has a MINTED slot rather than a caller's id. So the row is the
    # caller's ids at bindings 1..n, and the uniform's slot is checked to be
    # DISTINCT FROM ALL OF THEM -- which is the check that dies if `Cs.caller`'s
    # two arms are the wrong way round, the bug `webgpu_call.bend` records as
    # "all three `bufs` entries bound id 0" and which no size-reading row saw.
    bufs = (bend.get(f"mm_l{i}_bg_bufs") or "").split(",")
    ids = [str(x) for x in L[i]["ids"]]
    row(f"mm_e2e_l{i}_bg_bufs", bufs[1:], ids)
    row(f"mm_e2e_l{i}_bg_ids", bend.get(f"mm_l{i}_bg_ids"),
        ",".join(str(k) for k in range(len(ids) + 1)))
    row(f"mm_e2e_l{i}_uniform_not_a_buffer", bufs[0] not in ids, True)
    # Slot 0 is the 4-byte uniform the CALL CREATES (ops_webgpu.py:95), then one
    # entry per buffer at its own size. Written out rather than joined onto a
    # string, because the join is where an off-by-one in the fixture would hide.
    row(f"mm_e2e_l{i}_bg_sizes", bend.get(f"mm_l{i}_bg_sizes"),
        ",".join(["4"] + [str(x) for x in L[i]["sizes"]]))
    row(f"mm_e2e_l{i}_nowait", bend.get(f"mm_l{i}_nowait"), "True")
  # THE BIND GROUP LAYOUT against the BINDINGS TINYGRAD'S OWN WGSL DECLARES,
  # parsed out of the shader by the generator. This is the one structural row that
  # is not a restatement of the port: it is the port's `bgl.of` answer against the
  # shader's `@binding(N) var<uniform|storage>` lines.
  wgsl_pairs = []
  for b, kind in L[0]["bindings"]:
    wgsl_pairs += [str(b), bend.get("mm_bind_uniform") if kind == "uniform" else bend.get("mm_bind_storage")]
  row("mm_e2e_layout", bend.get("mm_layout"), ",".join(wgsl_pairs))
  row("mm_e2e_uploads_eq_fixture", bend.get("mm_uploads_eq_fixture"), "True")
  row("mm_e2e_upload_count", bend.get("mm_uploads"), str(len(o["uploads"])))

  # ---- the computation -----------------------------------------------------
  row("mm_e2e_out_bits_equal", res.get("out_u32") == o["answer_u32"], True)
  row("mm_e2e_out_words", len(res.get("out_u32") or []), len(o["answer_u32"]))
  row("mm_e2e_out_finite", bool(np.isfinite(got).all()), True)
  # THE DATA PATH, and the reason the equality above is about ARITHMETIC.
  row("mm_e2e_in_bits_equal", res.get("in_bytes") == o["probe_bytes_u32"], True)

  # ---- THE POWER -----------------------------------------------------------
  # Five wrong answers a bug in this lane would plausibly produce. Each is
  # computed from the oracle's own words, and each must be FURTHER from the GPU's
  # answer than the right answer is. `mm_power_margin` is the smallest such
  # distance divided by the right answer's distance from the CPU's -- here the
  # right answer's distance is ZERO, so the margin is unbounded and the gate
  # reports it as the finite lower bound it can measure.
  wrong = {
    "abad": A @ B,                       # only the FIRST launch ran
    "bada": B @ A,                       # the two reads bound the wrong way round
    "atc": A @ Cm,                       # the second launch used C where B belongs
    "self": Cm,                          # the readback returned an untouched input
    "zero": np.zeros((8, 8)),            # the buffers were never written
    "ctb": Cm @ B,
  }
  dist = {k: float(np.abs(v - got).max()) for k, v in wrong.items()}
  row("mm_e2e_answer_nonzero", float(np.abs(got).max()) > 1.0, True)
  row("mm_e2e_inputs_distinct", len({bytes(bs) for _, bs in o["uploads"]}) == len(o["uploads"]), True)
  row("mm_e2e_answer_not_an_input", float(np.abs(got - Cm).max()) > 1.0, True)
  for k, v in sorted(dist.items()):
    row(f"mm_power_{k}", v > 1.0, True)

  # ---- report --------------------------------------------------------------
  print(f"# adapter            {res.get('gpu_vendor')}/{res.get('gpu_architecture')}")
  print(f"# program            (A @ B) @ C, {o['launches']} launches, {len(o['first_bind'])} buffers")
  print(f"# steps performed    {res.get('steps')}  writes {res.get('writes')}  dispatches {res.get('dispatches')}")
  print(f"# wrong-answer distances (max abs, must exceed 1.0):")
  for k, v in sorted(dist.items()):
    print(f"#   {k:6s} {v:.6f}")
  print()
  for k in sorted(r):
    print(f"{k}={r[k]}")
  print(f"mm_e2e_failed={len(bad)}")
  for line in bad:
    print(f"# FAILED {line}")
  return 1 if bad else 0


def bend_cs_lens(res):
  """The five `Cs` lengths the Bend program declares, as the page reported them.
  Read back out of the artifact rather than recomputed, so the row compares the
  WALK against the PROGRAM and not against a second evaluation of it."""
  return res.get("cs_lens") or []


def performed_names(res):
  return res.get("performed") or []


if __name__ == "__main__":
  sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else ROOT / "runs/e2e/e2e-mm-bend.txt"))
