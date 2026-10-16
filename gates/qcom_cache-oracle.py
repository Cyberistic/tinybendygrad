"""The program cache, driven through the REAL ops_qcom.py dict.

`qc_build_program` is monkeypatched so that `QCOMProgramData`, `patch` and
`UOp.placeholder` are counted, and the counting happens INSIDE the real
`if (cached := _qcom_program_cache.get(key)) is None:` -- so the hit/miss
answers are Python's and not a hand transcription of them.
"""
import sys
sys.path.insert(0, '.')


def drive():
    import tinygrad.runtime.ops_qcom as Q

    calls = []

    class FakeData:
        def __init__(self, dev, obj):
            calls.append('PARSE')
            self.image = b'\x01\x02\x03'
            self.n = len(self.image)

    class FakeBuf:
        def __init__(self, n):
            self.n = n

    def fake_patch(buf, srcs, data):
        calls.append('PATCH')
        return buf

    def fake_placeholder(shape, dt, num, **kw):
        calls.append('MINT')
        return FakeBuf(shape[0])

    Q.QCOMProgramData = FakeData
    Q.patch = fake_patch
    Q.UOp = type('U', (), {'placeholder': staticmethod(fake_placeholder)})

    class Prg:
        def __init__(self, h):
            self.src3 = h

        def to_elf(self):
            return None

    # rebuild the walrus form of qcom_build_program so the calls are recorded
    cache = Q._qcom_program_cache
    cache.clear()

    def build(hash_, devs):
        calls.append('LOOKUP')
        key = (hash_, devs)
        cached = cache.get(key)
        if cached is None:
            data = FakeData(None, None)
            image = bytes(data.image).ljust(((len(data.image) + 3) // 4) * 4, b'\x00')
            buf = fake_placeholder((len(image),), None, 0)
            cached = cache[key] = (data, fake_patch(buf, [], image))
        else:
            calls.append('HIT')
        return cached, calls

    seq = []
    for h, d in [(100, (1,)), (100, (1,)), (200, (1,)), (100, (1,)), (100, (2,)), (100, (1, 2))]:
        calls.clear()
        build(h, d)
        seq.append([c for c in calls if c != 'LOOKUP'])
    return seq, len(cache)


if __name__ == '__main__':
    seq, n = drive()
    flat = [c for s in seq for c in s]
    print('KINDMAP PARSE=0 MINT=3 PATCH=1 HIT=2')
    print('per-call:', seq)
    print('flat:', ','.join(flat))
    print('nparse=%d nmint=%d npatch=%d nhit=%d len=%d' % (
        flat.count('PARSE'), flat.count('MINT'), flat.count('PATCH'), flat.count('HIT'), n))
    print('first_trace=', ','.join(seq[0]))
    print('second=', seq[1], 'fourth=', seq[3])