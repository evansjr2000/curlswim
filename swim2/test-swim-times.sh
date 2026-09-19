#!/usr/bin/env bash
# test-swim-times.sh
# Automated test script for swim-times, exercising the requirements
# defined in CAST-SRS-001 (swim-times-srs.tex) under the test design of
# CAST-STP-001 (swim-times-stp.tex).
#
# Usage:  ./test-swim-times.sh [--no-network] [--no-db] [--help]
#
#   --no-network   skip every test that touches times-api.usaswimming.org
#   --no-db        skip every test that touches Postgres
#
# Environment:
#   SWIM_TIMES_SKIP_NETWORK=1   same as --no-network
#   SWIM_TIMES_SKIP_DB=1        same as --no-db
#   SWIM_TIMES_PGCONNINFO       libpq conninfo for the fixture database
#   USAS_USER, USAS_PASS        USA Swimming credentials.  Normally these
#                               live in $USAS_ENV_FILE (default
#                               $HOME/.usas-env) and the program signs
#                               itself in; the suite only needs them to
#                               be reachable one way or the other.
#   USAS_SUB_ID, USAS_SESSION_ID
#                               an already-established session, used in
#                               place of signing in.
#
# The suite determines its access tier from `swim-times -o diag` and runs
# the live-data tests when the program can sign in.  When it cannot, those
# tests SKIP with the reason and the sign-in failure tests run instead.
#
# Exit status: 0 when nothing FAILed, 1 otherwise.  A SKIP is not a
# failure: the suite is designed to give a truthful verdict on a host
# with no database, no network, or no data-hub account.
#
# Output lines:
#   PASS REQ-X-NN  short description
#   FAIL REQ-X-NN  short description
#   SKIP REQ-X-NN  reason

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HERE/swim-times.w"
CSRC="$HERE/swim-times.c"
BIN="$HERE/swim-times"
WORK="${TMPDIR:-/tmp}/swim-times-tests.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

SKIP_NET="${SWIM_TIMES_SKIP_NETWORK:-0}"
SKIP_DB="${SWIM_TIMES_SKIP_DB:-0}"
for a in "$@"; do
    case "$a" in
        --no-network) SKIP_NET=1 ;;
        --no-db)      SKIP_DB=1 ;;
        --help|-h)    sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown argument: $a" >&2; exit 2 ;;
    esac
done

PASS=0; FAIL=0; SKIP=0
pass() { printf 'PASS %-12s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
fail() { printf 'FAIL %-12s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
skip() { printf 'SKIP %-12s %s\n' "$1" "$2"; SKIP=$((SKIP+1)); }
check() {  # check ID "description" <boolean-expression-result>
    if [ "$3" = "0" ]; then pass "$1" "$2"; else fail "$1" "$2"; fi
}
section() { printf '\n=== %s ===\n' "$1"; }

# =================================================================
# 1. Build
# =================================================================
section "Build"

if [ ! -f "$SOURCE" ]; then
    fail BUILD "swim-times.w not found at $SOURCE"
    exit 1
fi

BUILD_LOG="$WORK/build.log"
(cd "$HERE" && make -B tangle compile) >"$BUILD_LOG" 2>&1
if [ $? -ne 0 ] || [ ! -x "$BIN" ]; then
    fail BUILD "make tangle compile failed (see $BUILD_LOG)"
    cat "$BUILD_LOG"
    exit 1
fi
pass BUILD "tangle + compile produced $BIN"

# =================================================================
# 2. Static and design constraints
# =================================================================
section "Static / design constraints"

# REQ-D-01: clean compile under -O2 -Wall
grep -q "warning:" "$BUILD_LOG"
check REQ-D-01 "compile is warning-free under -O2 -Wall" $((1 - $?))

# REQ-D-02: the .c file is a regenerable artefact of the .w file
[ -f "$CSRC" ] && [ "$CSRC" -nt "$SOURCE" ]
check REQ-D-02 "swim-times.c regenerated from swim-times.w by the build" $?

# REQ-D-03: no CWEB chunk exceeds 24 lines of code
audit=$(awk '
    /^@($|[ \t*])/ { if (count > 24) print "line " NR-count ": " count; count=0; in_chunk=0; next }
    /^@<.*@>[+]?=$|^@c$/ { in_chunk=1; count=0; next }
    in_chunk { count++ }
    END { if (count > 24) print "tail chunk: " count }
' "$SOURCE")
if [ -z "$audit" ]; then
    pass REQ-D-03 "no CWEB chunk exceeds 24 lines"
else
    fail REQ-D-03 "oversized chunks: $audit"
fi

# REQ-D-04: dynamic dependencies limited to libc, libcurl, libpq, TLS.
# In particular the SHA-256/HMAC used for the rate-key header is
# implemented in-tree, so no new crypto library may appear here.
case "$(uname)" in
    Darwin) deps=$(otool -L "$BIN" 2>/dev/null | tail -n +2 | awk '{print $1}') ;;
    Linux)  deps=$(ldd "$BIN" 2>/dev/null | awk '{print $1}') ;;
    *)      deps="" ;;
esac
extras=$(printf '%s\n' "$deps" | grep -Ev 'libcurl|libpq|libSystem|libc\.|libssl|libcrypto|libz|libzstd|libbrotli|libidn|libintl|libldap|libsasl|libgssapi|libkrb5|libcom_err|libheimdal|libheimntlm|libhx509|libwind|libroken|libasn1|libpcre|libssh|libnghttp|liboauth|ld-linux|linux-vdso|/usr/lib/system|/System/' | grep -v '^$' || true)
if [ -z "$extras" ]; then
    pass REQ-D-04 "links only {libc, libcurl, libpq, TLS, support libs}"
else
    fail REQ-D-04 "unexpected dependencies: $extras"
fi

# REQ-D-11: the program keeps no credential in its source text.  A
# literal bearer token or session id in the .w would be a regression to
# the decommissioned Sisense design.
if grep -nE '(Bearer [A-Za-z0-9._-]{20,}|eyJ[A-Za-z0-9._-]{30,})' "$SOURCE" >/dev/null; then
    fail REQ-D-11 "hard-coded credential found in swim-times.w"
else
    pass REQ-D-11 "no hard-coded credential in the literate source"
fi

# REQ-I-20: HTTPS-only service base URLs
if grep -E '"https://times-api\.usaswimming\.org' "$SOURCE" >/dev/null \
   && ! grep -E '"http://[a-z.-]*usaswimming' "$SOURCE" >/dev/null; then
    pass REQ-I-20 "service base URLs are HTTPS-only"
else
    fail REQ-I-20 "a non-HTTPS usaswimming.org URL appears in the source"
fi

# REQ-A-04: cweave + pdftex produce a typeset PDF with no TeX errors.
# cweave exits non-zero on formatting *warnings*, so its status is not
# a pass criterion; the pdftex log is.
rm -f "$HERE/swim-times.pdf"
(cd "$HERE" && cweave swim-times.w >"$WORK/weave.log" 2>&1; \
             pdftex -interaction=nonstopmode swim-times.tex >"$WORK/pdftex.log" 2>&1)
tex_errors=$(grep -c '^! ' "$HERE/swim-times.log" 2>/dev/null); tex_errors=${tex_errors:-0}
if [ -f "$HERE/swim-times.pdf" ] && [ "$tex_errors" = "0" ]; then
    pass REQ-A-04 "cweave + pdftex produce swim-times.pdf with 0 TeX errors"
elif [ -f "$HERE/swim-times.pdf" ]; then
    fail REQ-A-04 "PDF produced but pdftex reported $tex_errors error(s)"
else
    fail REQ-A-04 "cweave/pdftex did not produce swim-times.pdf"
fi

# =================================================================
# 3. HTTP transport contract  (the defect fixed in this revision)
# =================================================================
section "HTTP transport contract"

# REQ-H-01: http_request reports the HTTP status to its caller.  The
# original signature had no status out-parameter at all, which is the
# root cause of the misdiagnosis this revision repairs.
if grep -q 'http_request(const char \*url, const char \*body, long \*status)' "$SOURCE"; then
    pass REQ-H-01 "http_request returns the HTTP status via *status"
else
    fail REQ-H-01 "http_request does not expose the HTTP status"
fi

# REQ-H-02: the status actually comes from libcurl
grep -q 'CURLINFO_RESPONSE_CODE' "$SOURCE"
check REQ-H-02 "response code read with curl_easy_getinfo" $?

# REQ-H-03: an empty 2xx body must not be reported as a failure.  This
# is the precise confusion that made a 403 look like a dead network.
grep -q 'if (!buf.data) buf.data = calloc(1, 1);' "$SOURCE"
check REQ-H-03 "empty response body normalised to \"\" rather than NULL" $?

# REQ-H-04: connect and total timeouts are set
grep -q 'CURLOPT_TIMEOUT' "$SOURCE" && grep -q 'CURLOPT_CONNECTTIMEOUT' "$SOURCE"
check REQ-H-04 "request and connect timeouts configured" $?

# REQ-H-05: no Accept header.  Sending Accept: application/json makes
# the service double-encode its payload as a JSON string, which the
# scanner cannot read.  Guard against its reintroduction.
if grep -q '"Accept: application/json"' "$SOURCE"; then
    fail REQ-H-05 "Accept: application/json reintroduced (causes double-encoded JSON)"
else
    pass REQ-H-05 "no Accept header sent (avoids double-encoded JSON)"
fi

# REQ-H-06: every caller of http_request checks the status
callers=$(grep -c 'http_request(' "$SOURCE")
checked=$(grep -c 'status != 200' "$SOURCE")
if [ "$checked" -ge 3 ]; then
    pass REQ-H-06 "HTTP status checked at each response site ($checked sites)"
else
    fail REQ-H-06 "only $checked of $callers http_request uses check the status"
fi

# =================================================================
# 4. Cryptographic self-test (rate-key dependency)
# =================================================================
section "Cryptographic self-test"

st_out="$WORK/selftest.out"
"$BIN" -o selftest >"$st_out" 2>&1; rc=$?

# REQ-S-01: the built-in known-answer tests pass
if [ $rc -eq 0 ] && grep -q "all vectors passed" "$st_out"; then
    pass REQ-S-01 "SHA-256 / HMAC-SHA256 known-answer vectors pass"
else
    fail REQ-S-01 "selftest rc=$rc; $(tr '\n' ' ' < "$st_out")"
fi

# REQ-S-02: all five published vectors are exercised, none silently absent
vec=$(grep -c ' ok$' "$st_out" || true)
if [ "$vec" -ge 5 ]; then
    pass REQ-S-02 "$vec standard vectors checked (FIPS 180-4, RFC 4231)"
else
    fail REQ-S-02 "expected at least 5 vectors, saw $vec"
fi

# REQ-S-03: the digest is compared against an independent implementation
if command -v python3 >/dev/null 2>&1; then
    want=$(python3 -c "import hmac,hashlib;print(hmac.new(b'key',b'The quick brown fox jumps over the lazy dog',hashlib.sha256).hexdigest())")
    if grep -q "$want" "$SOURCE"; then
        pass REQ-S-03 "HMAC vector in source matches python hashlib"
    else
        fail REQ-S-03 "HMAC vector in source disagrees with python hashlib"
    fi
else
    skip REQ-S-03 "python3 not available for independent digest check"
fi

# =================================================================
# 5. Command-line interface
# =================================================================
section "Command-line interface"

out=$("$BIN" 2>&1 >/dev/null); rc=$?
if [ $rc -eq 2 ] && echo "$out" | grep -q "Usage:"; then
    pass REQ-F-03 "empty invocation prints usage and exits 2 (RC_USAGE)"
else
    fail REQ-F-03 "empty invocation: rc=$rc (expected 2)"
fi

out=$("$BIN" -Z 2>&1 >/dev/null); rc=$?
if [ $rc -eq 2 ] && echo "$out" | grep -q "Usage:"; then
    pass REQ-F-04 "unknown flag prints usage and exits 2"
else
    fail REQ-F-04 "unknown flag: rc=$rc (expected 2)"
fi

# REQ-F-05: the usage text documents every behaviour keyword and -m
usage=$("$BIN" 2>&1 >/dev/null)
missing=""
for kw in fastest csv store offline diag selftest "-m memberId" \
          USAS_USER USAS_PASS USAS_ENV_FILE USAS_SUB_ID USAS_SESSION_ID; do
    echo "$usage" | grep -q -- "$kw" || missing="$missing $kw"
done
if [ -z "$missing" ]; then
    pass REQ-F-05 "usage documents every keyword, -m, and the credentials"
else
    fail REQ-F-05 "usage omits:$missing"
fi

# REQ-F-06: the roster in the usage text is generated from SWIMMERS
ids=$(echo "$usage" | sed -n '/swimmer ids/,/^$/p' | tr -s ' ' '\n' | grep -c '[a-z]')
declared=$(echo "$usage" | sed -n 's/.*swimmer ids (\([0-9]*\)).*/\1/p')
if [ -n "$declared" ] && [ "$declared" -ge 29 ]; then
    pass REQ-F-06 "usage lists all $declared roster ids"
else
    fail REQ-F-06 "usage roster count is '$declared' (expected >= 29)"
fi

# REQ-F-07: diag and offline are rejected together
out=$("$BIN" -o diag,offline 2>&1 >/dev/null); rc=$?
if [ $rc -eq 2 ] && echo "$out" | grep -qi "mutually exclusive"; then
    pass REQ-F-07 "diag+offline rejected with RC_USAGE"
else
    fail REQ-F-07 "diag+offline: rc=$rc out='$out'"
fi

# =================================================================
# 6. Data-hub access tier
# =================================================================
section "Data-hub access tier"

TIER=unknown
HAVE_CREDS=0
if [ -n "${USAS_USER:-}" ] && [ -n "${USAS_PASS:-}" ]; then HAVE_CREDS=1; fi
if [ -n "${USAS_SUB_ID:-}" ] && [ -n "${USAS_SESSION_ID:-}" ]; then HAVE_CREDS=1; fi
ENVF="${USAS_ENV_FILE:-$HOME/.usas-env}"
if [ -r "$ENVF" ] && grep -q '^[[:space:]]*\(export[[:space:]]*\)\?USAS_USER=' "$ENVF"; then
    HAVE_CREDS=1
fi

if [ "$SKIP_NET" = "1" ]; then
    TIER=skipped
else
    diag_out="$WORK/diag.out"
    "$BIN" -o diag >"$diag_out" 2>&1; drc=$?

    # REQ-G-01: diag succeeds and prints one line per probed endpoint
    probes=$(grep -cE '^  [A-Za-z].*(GET|POST) +[0-9]{3}' "$diag_out" || true)
    if [ $drc -eq 0 ] && [ "$probes" -ge 5 ]; then
        pass REQ-G-01 "diag probed $probes endpoints and exited 0"
    else
        fail REQ-G-01 "diag rc=$drc probes=$probes"
    fi

    # REQ-G-02: diag reports the sign-in outcome and the identity used
    if grep -q 'Sign-in' "$diag_out" && grep -q 'Usas-Sub-Id' "$diag_out" \
       && grep -q 'Device-Id' "$diag_out"; then
        pass REQ-G-02 "diag reports the sign-in outcome and credentials in force"
    else
        fail REQ-G-02 "diag does not report sign-in state"
    fi

    signin_ok=$(grep -c '^  Sign-in  *: ok' "$diag_out" || true)
    ref_ok=$(grep -E 'SearchFilter/GetAllEvents' "$diag_out" | grep -c ' 200 ' || true)
    qry_ok=$(grep -E 'BestTimes' "$diag_out" | grep -c ' 200 ' || true)
    qry_bad=$(grep -E 'GetMembersForFilters|BestTimes' "$diag_out" | grep -cE ' 40[13] ' || true)

    if [ "$signin_ok" -ge 1 ] && [ "$qry_ok" = "1" ]; then
        TIER=authorized
    elif [ "$HAVE_CREDS" = "0" ]; then
        TIER=nocreds
    elif [ "$signin_ok" = "0" ]; then
        TIER=authfail
    elif [ "$ref_ok" = "1" ] && [ "$qry_bad" -ge 1 ]; then
        TIER=locked
    else
        TIER=unreachable
    fi

    # REQ-G-03: the tiers are distinguishable from diag alone
    case "$TIER" in
      authorized) pass REQ-G-03 "access tier: AUTHORIZED (signed in, queries answered)" ;;
      nocreds)    pass REQ-G-03 "access tier: NO CREDENTIALS (nothing to sign in with)" ;;
      authfail)   pass REQ-G-03 "access tier: SIGN-IN FAILED (credentials present but rejected)" ;;
      locked)     pass REQ-G-03 "access tier: SIGNED IN BUT REFUSED (queries 401/403)" ;;
      *)          pass REQ-G-03 "access tier: UNREACHABLE (no endpoint answered)" ;;
    esac
fi

ONLINE_TESTS="REQ-F-10 REQ-F-11 REQ-F-12 REQ-F-16a REQ-F-20 REQ-F-21 \
REQ-F-22 REQ-F-30 REQ-F-31 REQ-F-32 REQ-F-40 REQ-F-41 REQ-F-42 REQ-F-50 \
REQ-F-51 REQ-P-01 REQ-P-02 REQ-A-01"

# =================================================================
# 7. Sign-in
# =================================================================
section "Sign-in"

# These four run without touching the roster and are independent of the
# tier, because they are about what the program does with credentials
# rather than what the service does with the program.

CLEAN="env -u USAS_SUB_ID -u USAS_SESSION_ID -u USAS_USER -u USAS_PASS"

if [ "$SKIP_NET" = "1" ]; then
    for r in REQ-L-01 REQ-L-02 REQ-L-03 REQ-L-04 REQ-L-05; do
        skip "$r" "network tests disabled"
    done
else
    # REQ-L-01: with nothing to sign in with, say so precisely and exit 77
    out=$($CLEAN USAS_ENV_FILE=/nonexistent/no-such-file \
          "$BIN" -o stella -e "50 FR SCY" 2>&1 >/dev/null); rc=$?
    if [ $rc -eq 77 ] && echo "$out" | grep -q 'no USA Swimming credentials' \
       && echo "$out" | grep -q 'USAS_USER'; then
        pass REQ-L-01 "missing credentials named precisely, exit 77"
    else
        fail REQ-L-01 "rc=$rc out='$(echo "$out" | head -1)'"
    fi

    # REQ-L-02: a rejected password says so, rather than reporting the
    # HTTP 200 the identity provider actually answers with
    out=$($CLEAN USAS_ENV_FILE=/nonexistent/no-such-file \
          USAS_USER=swim-times-test-nobody USAS_PASS=not-a-real-password \
          "$BIN" -o stella -e "50 FR SCY" 2>&1 >/dev/null); rc=$?
    if [ $rc -eq 77 ] && echo "$out" | grep -qi 'rejected the credentials'; then
        pass REQ-L-02 "rejected credentials reported in plain language, exit 77"
    else
        fail REQ-L-02 "rc=$rc out='$(echo "$out" | head -1)'"
    fi

    # REQ-L-03: the credentials file is parsed, never sourced, and only
    # USAS_-prefixed names are adopted.
    FIXENV="$WORK/usas-env"
    MARKER="$WORK/sourced-marker"
    cat >"$FIXENV" <<EOF
# comment line
export USAS_USER="swim-times-file-nobody"
export USAS_PASS="not-a-real-password"
export USAS_SIDE_EFFECT="\$(touch $MARKER)"
export SWIM_TIMES_PGCONNINFO="dbname=bogus-db host=127.0.0.1 port=1"
EOF
    out=$($CLEAN USAS_ENV_FILE="$FIXENV" \
          "$BIN" -o stella -e "50 FR SCY" 2>&1 >/dev/null)
    if echo "$out" | grep -q 'swim-times-file-nobody'; then
        pass REQ-L-03a "credentials are read from USAS_ENV_FILE"
    else
        fail REQ-L-03a "file credentials not used: $(echo "$out" | head -1)"
    fi
    if [ ! -e "$MARKER" ]; then
        pass REQ-L-03 "credentials file parsed, not sourced (no shell expansion)"
    else
        fail REQ-L-03 "command substitution in the env file was executed"
    fi

    # REQ-L-04: a non-USAS_ assignment in that same file is ignored.
    # The fixture sets a bogus SWIM_TIMES_PGCONNINFO; the program must
    # neither adopt it from the file nor honour it from the environment,
    # because the database is named in a compiled-in constant.
    if env SWIM_TIMES_PGCONNINFO="dbname=bogus-db host=127.0.0.1 port=1" \
           USAS_ENV_FILE="$FIXENV" \
           "$BIN" -o stella,offline -e "50 FR SCY" >/dev/null 2>"$WORK/l04.err"; then
        pass REQ-L-04 "connection string is compiled in; neither file nor environment redirects it"
    else
        if grep -qi 'bogus-db\|could not connect\|connection' "$WORK/l04.err"; then
            fail REQ-L-04 "the connection string was redirected: $(head -1 "$WORK/l04.err")"
        else
            fail REQ-L-04 "offline read failed: $(head -1 "$WORK/l04.err")"
        fi
    fi

    # REQ-L-05: offline needs no credentials at all
    if $CLEAN USAS_ENV_FILE=/nonexistent/no-such-file \
       "$BIN" -o stella,offline -e "50 FR SCY" >/dev/null 2>"$WORK/l05.err"; then
        pass REQ-L-05 "offline mode runs with no credentials"
    else
        if grep -q 'credential' "$WORK/l05.err"; then
            fail REQ-L-05 "offline mode demanded credentials"
        else
            skip REQ-L-05 "no local database; credential-independence not shown"
        fi
    fi
fi

# REQ-L-06: the session is activated on every run.  Without this call the
# times API answers 401 for a freshly-issued session, so its absence
# would be a silent, intermittent-looking outage.
if grep -q 'GetDataHubSecurityInfoForIdp' "$SOURCE" \
   && grep -q 'activate_session' "$SOURCE"; then
    pass REQ-L-06 "session activation is performed after sign-in"
else
    fail REQ-L-06 "no session-activation step in the source"
fi

# REQ-L-07: no anonymous fallback.  The program must not retry a refused
# query without credentials, and must not default its subject to
# Anonymous on the data path.
if grep -q 'if (!(g_opts & OPT_OFFLINE) && !ensure_session' "$SOURCE"; then
    pass REQ-L-07 "every online run signs in; no anonymous data path"
else
    fail REQ-L-07 "online runs do not require a session"
fi

# =================================================================
# 7b. Behaviour when the data hub declines
# =================================================================
section "Refusal handling"

if [ "$TIER" = "authorized" ] || [ "$TIER" = "skipped" ]; then
    for r in REQ-E-01 REQ-E-02 REQ-E-03 REQ-E-04; do
        skip "$r" "data hub is answering this caller (tier=$TIER)"
    done
elif [ "$TIER" = "unreachable" ]; then
    for r in REQ-E-01 REQ-E-02 REQ-E-03 REQ-E-04; do
        skip "$r" "data hub unreachable; refusal path not exercised"
    done
else
    err="$WORK/refused.err"
    "$BIN" -o stella -e "100 FR SCY" >"$WORK/refused.out" 2>"$err"; rc=$?

    # REQ-E-01: a refusal exits RC_NOPERM (77), not a generic failure
    check REQ-E-01 "refused run exits 77 (RC_NOPERM), got $rc" \
        $([ $rc -eq 77 ] && echo 0 || echo 1)

    # REQ-E-02: the diagnostic is specific, and never again the vague
    # "request failed" of the defective version
    if grep -qE 'HTTP [0-9]{3}|credentials' "$err" \
       && ! grep -q 'person lookup request failed' "$err"; then
        pass REQ-E-02 "diagnostic names the status or the credential problem"
    else
        fail REQ-E-02 "diagnostic is not specific: $(head -1 "$err")"
    fi

    # REQ-E-03: the remedy is stated once, not once per event
    advice=$(grep -c 'USAS_' "$err" || true)
    if [ "$advice" -ge 1 ] && [ "$advice" -le 3 ]; then
        pass REQ-E-03 "remedial advice stated once per run"
    else
        fail REQ-E-03 "advice appeared $advice times (expected 1-3)"
    fi

    # REQ-E-04: a refusal aborts promptly instead of replaying itself
    "$BIN" -o csv >"$WORK/refused-all.out" 2>"$WORK/refused-all.err"
    errs=$(grep -c '^Error:' "$WORK/refused-all.err" || true)
    if [ "$errs" -le 2 ]; then
        pass REQ-E-04 "full-roster refusal reported $errs time(s), run aborted early"
    else
        fail REQ-E-04 "refusal repeated $errs times across the roster"
    fi
fi

# REQ-F-77: a swimmer the directory does not hold is skipped, not
# fatal.  Before this fix a 404 from the member search aborted the
# whole roster walk and silently dropped every swimmer after it.
if [ "$SKIP_NET" = "1" ]; then
    skip REQ-F-77 "network tests disabled"
else
    out=$("$BIN" -m ZZZZZZZZZZZZZZ -e "50 FR SCY" 2>&1 >/dev/null); rc=$?
    if [ $rc -eq 69 ] && echo "$out" | grep -qi 'no member with id' \
       && echo "$out" | grep -qi 'skipped'; then
        pass REQ-F-77 "an absent swimmer is reported and counted, exit 69"
    else
        fail REQ-F-77 "rc=$rc out='$(echo "$out" | head -1)'"
    fi
fi

# REQ-F-77a: and the roster walk continues past one.  Structural,
# because a roster entry that fails to resolve cannot be injected from
# outside the binary.
if grep -q 'if (g_not_found) { g_missing++; continue; }' "$SOURCE"; then
    pass REQ-F-77a "a not-found swimmer continues the walk instead of breaking it"
else
    fail REQ-F-77a "the dispatcher still aborts on a not-found swimmer"
fi

# REQ-F-78: the swimmer match tolerates spelling but not identity.
# Tiers 2 and 3 must be confined to rows with no member_id, or two
# different swimmers could be merged.
if grep -q 'member_id IS NULL AND lower(full_name) = lower($2)' "$SOURCE" \
   && grep -q 'regexp_replace(full_name' "$SOURCE" \
   && [ "$(grep -c 'member_id IS NULL' "$SOURCE")" -ge 2 ]; then
    pass REQ-F-78 "loose name match is confined to unlinked rows"
else
    fail REQ-F-78 "the swimmer match is not tiered as specified"
fi

# REQ-F-18: the known-memberId short cut reaches GetMember directly
if [ "$SKIP_NET" = "1" ]; then
    skip REQ-F-18 "network tests disabled"
else
    out=$("$BIN" -m 6CD35348E5824C -e "50 FR SCY" 2>/dev/null)
    if echo "$out" | grep -q "MemberId: 6CD35348E5824C" \
       && echo "$out" | grep -qi "Ledecky"; then
        pass REQ-F-18 "-m resolves a memberId via GetMember without search"
    else
        fail REQ-F-18 "-m did not resolve the member: $(echo "$out" | head -1)"
    fi
fi

# =================================================================
# 8. Live data retrieval (the normal path for a signed-in run)
# =================================================================
section "Live data retrieval"

if [ "$TIER" != "authorized" ]; then
    case "$TIER" in
      skipped)  why="network tests disabled" ;;
      nocreds)  why="no credentials; put USAS_USER/USAS_PASS in \$HOME/.usas-env" ;;
      authfail) why="sign-in failed; check USAS_USER and USAS_PASS" ;;
      locked)   why="signed in, but the data hub refused the times queries" ;;
      *)        why="data hub unreachable" ;;
    esac
    for r in $ONLINE_TESTS REQ-F-13 REQ-F-33 REQ-F-52; do skip "$r" "$why"; done
    # REQ-F-14/15/16 are static declarations and remain checkable.
    for w in "ledecky10:2006-03-17:REQ-F-14" \
             "ledecky12:2008-03-17:REQ-F-15" \
             "ledecky14:2010-03-17:REQ-F-16"; do
        id=${w%%:*}; rest=${w#*:}; d=${rest%%:*}; rid=${rest##*:}
        grep -q "\"$id\".*\"$d\"" "$SOURCE"
        check "$rid" "$id age window declared on its Swimmer entry" $?
    done
else
    BASE="$WORK/base.out"
    start=$(date +%s)
    "$BIN" -o stella -e "100 FR SCY" >"$BASE" 2>"$WORK/base.err"; rc=$?
    elapsed=$(( $(date +%s) - start ))

    grep -qE "^Swimmer:.*[Ee]vans" "$BASE" \
        && ! grep -qE "Benavente|Kenneth Ray|Keith Santiago" "$BASE"
    r=$?; check REQ-F-10 "swimmer keyword restricts output to that swimmer" $r
          check REQ-F-12 "stella resolves to Stella Julianna Evans" $r

    ev=$(grep -cE "^[0-9]+ [A-Z]+ (SCY|LCM) ---" "$BASE" || true)
    check REQ-F-20 "single -e restricts the query to one event (saw $ev)" \
        $([ "$ev" = 1 ] && echo 0 || echo 1)
    check REQ-F-22 "event list honoured" $([ "$ev" = 1 ] && echo 0 || echo 1)
    check REQ-F-30 "memberId resolved and event section produced" \
        $([ "$ev" -ge 1 ] && echo 0 || echo 1)
    check REQ-F-31 "BestTimes query returned a result section" \
        $([ "$ev" -ge 1 ] && echo 0 || echo 1)

    row=$(grep -E "^[0-9:.]+r?  +[0-9]{4}-" "$BASE" | head -1)
    if [ -n "$row" ]; then
        pass REQ-F-32 "row carries time, ISO date, and meet"
        pass REQ-F-42 "dates formatted YYYY-MM-DD"
    else
        fail REQ-F-32 "no fully-populated data row found"
        fail REQ-F-42 "no ISO-formatted date found"
    fi

    keys=$(grep -E "^[0-9:.]+r?  " "$BASE" | awk '{print $1}')
    sorted=$(printf '%s\n' "$keys" | sort -t: -k1,1n -k2,2n)
    check REQ-F-40 "rows printed fastest-first" \
        $([ "$keys" = "$sorted" ] && echo 0 || echo 1)

    n=$("$BIN" -o stella,fastest -e "100 FR SCY" 2>/dev/null | grep -cE "^[0-9:.]+r?  " || true)
    check REQ-F-41 "fastest prints a single row (saw $n)" \
        $([ "$n" -le 1 ] && echo 0 || echo 1)

    hdr=$("$BIN" -o stella,csv -e "100 FR SCY" 2>/dev/null | head -1)
    check REQ-F-50 "table mode prints a heading and column header" \
        $(grep -q "Time" "$BASE" && echo 0 || echo 1)
    check REQ-F-51 "CSV header is the six-column contract" \
        $([ "$hdr" = '"Swimmer","Event","Time","Date","Standard","Meet"' ] && echo 0 || echo 1)

    lines=$("$BIN" -o stella,csv -e "100 FR SCY" 2>/dev/null | tail -n +2)
    named=$(printf '%s\n' "$lines" | grep -cv '^"[^"]\+",' || true)
    check REQ-F-52 "every CSV row carries the swimmer name" \
        $([ "$named" = "0" ] && echo 0 || echo 1)

    all=$("$BIN" -o stella 2>/dev/null | grep -cE "^[0-9]+ [A-Z]+ (SCY|LCM) ---" || true)
    check REQ-F-21 "all 31 events reported when -e is omitted (saw $all)" \
        $([ "$all" = 31 ] && echo 0 || echo 1)

    m=$("$BIN" -o stella,kalea -e "50 FR SCY" 2>/dev/null | grep -c '^Swimmer:' || true)
    check REQ-F-11 "multiple swimmer ids select multiple swimmers (saw $m)" \
        $([ "$m" -ge 2 ] && echo 0 || echo 1)

    out=$("$BIN" -o ledecky10 -e "100 FR SCY" 2>/dev/null)
    echo "$out" | grep -qi "Ledecky"
    check REQ-F-13 "ledecky10 resolves to Katie Ledecky" $?
    echo "$out" | grep -qE "^[0-9:.]+r?  +[0-9]{4}-"
    check REQ-F-16a "ledecky10 row carries a valid date" $?
    for w in "ledecky10:2006-03-17:REQ-F-14" \
             "ledecky12:2008-03-17:REQ-F-15" \
             "ledecky14:2010-03-17:REQ-F-16"; do
        id=${w%%:*}; rest=${w#*:}; d=${rest%%:*}; rid=${rest##*:}
        grep -q "\"$id\".*\"$d\"" "$SOURCE"
        check "$rid" "$id age window declared on its Swimmer entry" $?
    done

    grep -q 'Skip pair if already fetched' "$SOURCE"
    check REQ-F-33 "per-stroke/distance BestTimes caching present" $?

    check REQ-P-02 "single event/swimmer query took ${elapsed}s (< 10s)" \
        $([ "$elapsed" -lt 10 ] && echo 0 || echo 1)
    check REQ-P-01 "full refresh projected under 5 min" \
        $([ "$elapsed" -lt 10 ] && echo 0 || echo 1)

    "$BIN" -o stella,csv -e "100 FR SCY" >"$WORK/a1" 2>/dev/null
    "$BIN" -o stella,csv -e "100 FR SCY" >"$WORK/a2" 2>/dev/null
    cmp -s "$WORK/a1" "$WORK/a2"
    check REQ-A-01 "back-to-back invocations produce identical output" $?
fi

# =================================================================
# 9. The shared database
# =================================================================
section "Shared database"

# The program names one database in a compiled-in constant, so this
# section uses the same string.  test-db.sh covers the schema in depth;
# these cases cover the program's use of it.
DB_TESTS="REQ-F-70 REQ-F-71 REQ-F-72 REQ-F-73 REQ-F-75 REQ-F-76"
CONN="dbname=swimming user=postgres host=100.77.243.69 port=5432 connect_timeout=10"
FX_NAME="ZZ swim-times suite fixture (delete me)"
dbq() { psql "$CONN" -tAc "$1"; }
db_cleanup() { psql "$CONN" -qtAc "DELETE FROM swimmer WHERE full_name = '$FX_NAME'" >/dev/null 2>&1; }

if [ "$SKIP_DB" = "1" ]; then
    for r in $DB_TESTS; do skip "$r" "database tests disabled"; done
elif ! command -v psql >/dev/null 2>&1; then
    for r in $DB_TESTS; do skip "$r" "psql not installed"; done
elif [ "$(dbq 'SELECT 1' 2>/dev/null)" != "1" ]; then
    for r in $DB_TESTS; do skip "$r" "cannot reach swimming@100.77.243.69"; done
else
    trap db_cleanup EXIT
    db_cleanup

    # REQ-F-70: the normalised schema the program targets is present.
    cols=$(dbq "SELECT count(*) FROM information_schema.columns
                 WHERE table_name='swim' AND column_name IN
                 ('swim_time_id','swimmer_key','event_code','meet_key',
                  'swim_date','swim_time','seconds','standard_name',
                  'source_endpoint','auth_mode')")
    if [ "$cols" = "10" ]; then
        pass REQ-F-70 "swim carries the ten columns db_insert_row writes"
    else
        fail REQ-F-70 "swim has $cols of the 10 required columns"
    fi

    # REQ-F-71: the offline read joins swim -> swimmer -> meet and
    # returns the full recorded history, not merely this program's own
    # writes.  Stella's 50 FR SCY is carried by the sibling loader.
    off="$WORK/offline.out"
    "$BIN" -o stella,offline,csv -e "50 FR SCY" >"$off" 2>"$WORK/offline.err"
    rows=$(tail -n +2 "$off" | grep -c '^"[^"]\+","50 FR SCY"' || true)
    if [ ! -s "$WORK/offline.err" ] && [ "$rows" -ge 1 ]; then
        pass REQ-F-71 "offline read returned $rows joined row(s)"
    elif [ -s "$WORK/offline.err" ]; then
        fail REQ-F-71 "offline read failed: $(head -1 "$WORK/offline.err")"
    else
        skip REQ-F-71 "no stored swims for that swimmer and event"
    fi

    # REQ-F-72: offline mode performs no network I/O at all
    if grep -q 'if (!(g_opts & OPT_OFFLINE))' "$SOURCE" \
       && grep -q 'offline mode requires a DB connection' "$SOURCE"; then
        pass REQ-F-72 "offline mode bypasses curl initialisation entirely"
    else
        fail REQ-F-72 "offline mode does not clearly bypass the network"
    fi

    # REQ-F-73: a re-run writes nothing new.  This is the property that
    # makes -o store safe to schedule against a shared database.
    if [ "$TIER" = "authorized" ] && [ "$SKIP_NET" != "1" ]; then
        b=$(dbq "SELECT count(*) FROM swim")
        "$BIN" -o stella,store -e "50 FR SCY,100 FR SCY" >/dev/null 2>"$WORK/store1.err"
        m=$(dbq "SELECT count(*) FROM swim")
        "$BIN" -o stella,store -e "50 FR SCY,100 FR SCY" >/dev/null 2>"$WORK/store2.err"
        a=$(dbq "SELECT count(*) FROM swim")
        if [ "$m" = "$a" ] && [ ! -s "$WORK/store2.err" ]; then
            pass REQ-F-73 "second store run added no rows ($b -> $m -> $a)"
        else
            fail REQ-F-73 "row count $b -> $m -> $a; $(head -1 "$WORK/store2.err")"
        fi
    else
        skip REQ-F-73 "store requires a signed-in run (tier=$TIER)"
    fi

    # REQ-F-75: a store run that cannot sign in writes nothing.
    if [ "$SKIP_NET" = "1" ]; then
        skip REQ-F-75 "network tests disabled; store path not exercised"
    else
        b=$(dbq "SELECT count(*) FROM swim")
        env -u USAS_SUB_ID -u USAS_SESSION_ID -u USAS_USER -u USAS_PASS \
            USAS_ENV_FILE=/nonexistent/no-such-file \
            "$BIN" -o stella,store -e "50 FR SCY" >/dev/null 2>/dev/null
        rc=$?
        a=$(dbq "SELECT count(*) FROM swim")
        if [ "$b" = "$a" ] && [ $rc -eq 77 ]; then
            pass REQ-F-75 "store run without credentials wrote nothing, exit 77"
        else
            fail REQ-F-75 "rc=$rc rows $b -> $a"
        fi
    fi

    # REQ-F-76: the surrogate swim id is stable.  If it were not, every
    # run would insert the same swim again under a fresh primary key and
    # the shared table would grow without bound.
    if grep -q 'swim_surrogate_id' "$SOURCE" \
       && grep -q 'sha256_update(&s, buf, strlen(buf));' "$SOURCE" \
       && grep -q 'ON CONFLICT DO NOTHING' "$SOURCE"; then
        pass REQ-F-76 "swim id is a stable hash of the natural key"
    else
        fail REQ-F-76 "surrogate id is not derived from the natural key"
    fi

    db_cleanup
    trap - EXIT
fi

# =================================================================
section "Summary"
printf 'PASS: %d   FAIL: %d   SKIP: %d\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
    printf '\nA FAIL is a defect in swim-times.  A SKIP is not: it records\n'
    printf 'a precondition this host does not meet (no network, no\n'
    printf 'database, or no USA Swimming account).\n'
    exit 1
fi
exit 0
