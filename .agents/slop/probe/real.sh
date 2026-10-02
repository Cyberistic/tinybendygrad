#!/bin/sh
# Run webgpu_call.js against a REAL navigator.gpu, in headless Chrome, and print
# one line. Chrome is started and killed inside this script because a detached
# Chrome does not survive the shell that launched it on this machine (MEASURED:
# `nohup ... &` then a later shell found nothing on :9222).
#
# Usage: .agents/slop/probe/real.sh '<js expression returning a string>'
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad || exit 1
EXPR="$1"
rm -rf .agents/slop/probe/chrome
mkdir -p .agents/slop/probe/chrome
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --enable-unsafe-webgpu --use-angle=metal \
  --no-sandbox --disable-gpu-sandbox \
  --user-data-dir="$PWD/.agents/slop/probe/chrome" \
  --remote-debugging-port=9222 about:blank > .agents/slop/probe/chrome.log 2>&1 &
CPID=$!
i=0
while [ $i -lt 40 ]; do
  curl -s --max-time 1 http://127.0.0.1:9222/json/version > /dev/null 2>&1 && break
  i=$((i+1)); sleep 0.5
done
bun .agents/slop/probe/cdp.mjs \
  "http://127.0.0.1:8731/.agents/slop/probe/${PAGE:-run.html}" "$EXPR" 40000 2>&1 | tail -4
kill -9 $CPID 2>/dev/null
pkill -9 -f "probe/chrome" 2>/dev/null
exit 0