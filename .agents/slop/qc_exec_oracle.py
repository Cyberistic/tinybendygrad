import tinygrad.runtime.ops_qcom as Q


class K:
    def __init__(self, o=0):
        self.o = o

    def getaddr(self, devs):
        return 0x1000

    def rtag(self, t):
        return self

    def index(self, i):
        return self

    def store(self, v):
        return self

    def after(self, *a):
        return self

    @property
    def max_numel(self):
        return 256


class D:
    gpu_id = (6, 5, 0)
    devs = (0,)


class Data:
    def __init__(self, samp=0, tex=0, ibo=0, nir=False, max_threads=256):
        self.samp_cnt, self.tex_cnt, self.ibo_cnt, self.NIR = samp, tex, ibo, nir
        self.max_threads = max_threads
        self.image_size, self.prg_offset, self.brnchstck = 0x18, 0x30, 5
        self.pvtmem, self.shmem, self.hregs, self.fregs = 0x600, 0x1800, 25, 33
        self.hw_stack_offset, self.shared_size = 0x1000, 5
        self.kernargs_alloc_size = 0x900
        self.wgsz, self.wgid, self.lid = 0xfc, 0, 0
        self.samp_off, self.tex_off, self.ibo_off = 0x800, 0x800, 0x800
        self.buf_offs, self.samplers, self.consts_info = [], [], []
        self.signature = ()
        # the six DERIVED sizes, computed by the source's own expressions
        from tinygrad.helpers import round_up, next_power2
        self.pvtmem_size_per_item = round_up(self.pvtmem, 512) >> 9
        self.pvtmem_size_total = self.pvtmem_size_per_item * 128 * 2
        self.shared_size = max(1, (self.shmem - 1) // 1024)


def run(samp, tex, ibo, nir, max_threads=256, gs=(16, 1, 1), ls=(8, 1, 1)):
    """the REAL QCOMComputeQueue.exec, with `q` bound to a recorder."""
    calls = []

    class Prg:
        arg = type('A', (), {'global_size': gs, 'local_size': ls})()

    Q.qcom_build_program = lambda dev, p, dv: (Data(samp, tex, ibo, nir, max_threads), K())
    Q.QCOMComputeQueue.kernargs = lambda self, call, prg, data: K()
    Q.UOp = type('U', (), {
        'placeholder': staticmethod(lambda *a, **kw: K()),
        'range': staticmethod(lambda *a, **kw: K()),
    })
    q = Q.QCOMComputeQueue.__new__(Q.QCOMComputeQueue)
    # wrap `cmd` and `reg` so the record is the OPCODE or the REGISTER NUMBER
    # and the word COUNT -- the two things the port's trace carries.
    def mcmd(self, opcode, *vals):
        calls.append(('CMD7', opcode, sum(1 for _ in vals)))

    def mreg(self, reg, *vals):
        calls.append(('CMD4', reg, sum(1 for _ in vals)))
    q.cmd = mcmd.__get__(q, Q.QCOMComputeQueue)
    q.reg = mreg.__get__(q, Q.QCOMComputeQueue)
    q.q = lambda *v: None
    q.dev = D()
    q.devs = (0,)
    try:
        q.exec(K(), Prg())
    except RuntimeError as e:
        return ('RAISE', str(e))
    return calls


def kinds(calls):
    """the (kind, arg) sequence -- `arg` is the OPCODE for a `cmd` and the
    REGISTER NUMBER for a `reg`, which is exactly what the port's trace holds."""
    return ['%s:%d' % (c[0], c[1]) for c in calls]


def counts(calls):
    """the word counts, one per call, which the port does NOT carry."""
    return [c[2] for c in calls]


if __name__ == '__main__':
    for nm, args in (('cl', (0, 0, 0, False)), ('full', (2, 1, 1, False)),
                     ('nir', (2, 1, 1, True)), ('samp_only', (1, 0, 0, False)),
                     ('tex_only', (0, 1, 0, False)), ('ibo_only', (0, 0, 1, False)),
                     ('refuse_res', (0, 0, 0, False, 63, (16, 1, 1), (64, 1, 1))),
                     ('refuse_dim', (0, 0, 0, False, 4096, (64, 1, 1), (2048, 1, 1)))):
        r = run(*args)
        if isinstance(r, tuple):
            print('exec_%s=RAISE:%s' % (nm, r[1]))
        else:
            # the recorder stores the RAW q() arguments; the header is first
            print('exec_%s=%s' % (nm, ','.join(kinds(r))))
            print('execn_%s=%s' % (nm, ','.join(str(x) for x in counts(r))))