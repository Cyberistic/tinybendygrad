#!/usr/bin/env python3
"""b3_fetch.py -- measure the out-of-repo network input of the Bend toolchain.

`references/bend/bend2/main.ts:185-212` (`check()`) does, once a day, a GET of
`ORIGIN + "/check?v=&os=&arch="` whose answer `{ver, notice}` is cached in
`~/.bend/check.json` and printed on stderr.  `ORIGIN` is
`process.env.BEND_ORIGIN ?? "https://bend-lang.com"` (main.ts:65).

This script points BEND_ORIGIN at a LOCAL http server, so the request is
observed directly, and it measures three things:

  1. does a request arrive, and what does it look like?
  2. does the server's answer reach stderr?
  3. does the answer change the --verdict outcome?
  4. does BEND_NO_TELEMETRY=1 stop the request?

The server is HTTP, not HTTPS: that is deliberate -- it is the point.  The
DEFAULT ORIGIN is https://bend-lang.com; the env var is what makes the
transport downgradeable, and this measures what a downgrade can reach.
"""
import http.server
import json
import os
import subprocess
import sys
import threading

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
BEND = os.path.join(REPO, "bin/bend")
CAND = os.path.join(REPO, ".agents/slop/verdict-hunt2/cand/f03_unreachable.bend")

REQUESTS = []
ANSWER = {"ver": "9.9.9", "notice": "NOTICE-FROM-THE-LOCAL-SERVER"}


class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        REQUESTS.append(self.path)
        body = json.dumps(ANSWER).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def main():
    srv = http.server.HTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    origin = "http://127.0.0.1:%d" % port

    home = os.environ["VH2_HOME"]
    os.makedirs(os.path.join(home, ".bend"), exist_ok=True)

    def run(args, extra_env=None, label=""):
        env = dict(os.environ)
        env["HOME"] = home
        env["BEND_ORIGIN"] = origin
        env.pop("BENDTT", None)
        if extra_env:
            env.update(extra_env)
        p = subprocess.run([BEND] + args, cwd=REPO, env=env,
                           capture_output=True, text=True, timeout=300)
        print("== %s" % label)
        print("   rc=%d" % p.returncode)
        print("   stdout=%r" % p.stdout.strip()[:160])
        print("   stderr=%r" % p.stderr.strip()[:300])
        return p

    # 1. no check.json at all: the compiler must fetch
    run(["--help"], label="A: no ~/.bend/check.json, BEND_ORIGIN=local http")
    print("   requests so far: %r" % (REQUESTS,))
    print("   ~/.bend/check.json now: %r"
          % open(os.path.join(home, ".bend", "check.json")).read())

    # 2. the cached answer is used for a day
    REQUESTS.clear()
    run(["--help"], label="B: the cache is fresh -> no request")
    print("   requests so far: %r" % (REQUESTS,))

    # 3. BEND_NO_TELEMETRY=1: no request, and no read of the cache
    REQUESTS.clear()
    run(["--help"], {"BEND_NO_TELEMETRY": "1"}, label="C: BEND_NO_TELEMETRY=1")
    print("   requests so far: %r" % (REQUESTS,))

    # 4. does the server's answer change the --verdict outcome?
    REQUESTS.clear()
    p = run(["--verdict", CAND], label="D: --verdict with the local server")
    print("   requests so far: %r" % (REQUESTS,))
    print("   VERDICT-OK? %s" % (p.stdout.strip() == "ALL PROOFS CHECK"))

    # 5. a CRAFTED cache with t=0: the compiler fetches on EVERY run
    with open(os.path.join(home, ".bend", "check.json"), "w") as f:
        f.write(json.dumps({"t": 0, "ver": "9.9.9", "notice": "CRAFTED"}))
    REQUESTS.clear()
    run(["--help"], label="E: crafted check.json with t=0")
    print("   requests so far: %r" % (REQUESTS,))
    srv.shutdown()


if __name__ == "__main__":
    main()
