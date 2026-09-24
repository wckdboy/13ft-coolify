#!/usr/bin/env bash
# Smoke test for a deployed 13ft stack.
#
#   ./scripts/smoke-test.sh https://13ft.example.com
#   ./scripts/smoke-test.sh http://localhost        # local compose
#
# Exits non-zero if any check fails.

set -uo pipefail

BASE="${1:-http://localhost}"
BASE="${BASE%/}"
CURL="curl -sS --max-time 25"
FAILED=0

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILED=1; }
head2() { printf '\n\033[1m%s\033[0m\n' "$1"; }

code() { # code <url> [extra curl args...]
  local url="$1"; shift
  $CURL -o /dev/null -w '%{http_code}' "$@" "$url"
}

head2 "Target: $BASE"

# 1. Landing page is ours, not the stock app UI.
head2 "1/6  Landing page"
status=$(code "$BASE/")
body=$($CURL "$BASE/" || true)
if [ "$status" = "200" ]; then pass "GET / -> 200"; else fail "GET / -> $status (want 200)"; fi
if printf '%s' "$body" | grep -q 'name="13ft-landing"'; then
  pass "landing page marker found (custom UI is being served)"
else
  fail "custom landing page marker missing — serving something else?"
fi

# 2. Proxy -> upstream passthrough.
#    /status with no url is answered by the app with 400 "Missing URL". A 400
#    proves the request traversed the proxy into the app; the upstream app has
#    a catch-all /<path> route, so it never returns a clean 404.
head2 "2/6  Proxy passthrough"
status=$(code "$BASE/status")
if [ "$status" = "400" ]; then
  pass "GET /status -> 400 'Missing URL' (app answered through the proxy)"
else
  fail "GET /status -> $status (want 400 from the app; 404/502 means the proxy isn't reaching it)"
fi

# 3. Upstream asset (the landing page links to /favicon.ico, which the app
#    serves from logo.png in the image).
head2 "3/6  Upstream asset"
status=$(code "$BASE/favicon.ico")
if [ "$status" = "200" ]; then pass "GET /favicon.ico -> 200"; else fail "GET /favicon.ico -> $status (want 200)"; fi

# 4. The app's own form POST still reaches the upstream.
head2 "4/6  POST /article"
status=$(code "$BASE/article" -X POST -d 'link=https://example.com')
if [ "$status" = "200" ]; then pass "POST /article -> 200"; else fail "POST /article -> $status (want 200)"; fi

# 5. Live progress stream (SSE) is proxied without buffering.
head2 "5/6  SSE /status"
sse=$($CURL -N --max-time 40 "$BASE/status?url=https%3A%2F%2Fexample.com" || true)
if printf '%s' "$sse" | grep -q '^event:'; then
  pass "SSE stream emitted events ($(printf '%s' "$sse" | grep -c '^event:') events seen)"
else
  fail "no SSE events received — stream buffered or app unhealthy"
  printf '       first bytes: %s\n' "$(printf '%s' "$sse" | head -c 120)"
fi

# 6. Bypass path resolves (any non-5xx response means routing + app are alive;
#    the app answers unknown paths with 400 "Invalid URL").
head2 "6/6  Bypass route"
status=$(code "$BASE/https://example.com")
if [ "$status" -lt 500 ] 2>/dev/null; then
  pass "GET /https://example.com -> $status (not a gateway error)"
else
  fail "GET /https://example.com -> $status"
fi

head2 "Result"
if [ "$FAILED" -eq 0 ]; then
  printf '  \033[32mAll checks passed.\033[0m\n'
else
  printf '  \033[31mSome checks failed.\033[0m See the README troubleshooting table.\n'
fi
exit "$FAILED"
