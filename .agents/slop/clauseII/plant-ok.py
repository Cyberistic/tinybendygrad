class G:
    def run(self):
        self.tmp.unlink()
        try:
            pass
        finally:
            self._settle(0)
        return 0
