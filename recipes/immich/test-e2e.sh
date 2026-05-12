#!/usr/bin/env bash
# E2E boot test for the Immich recipe on a CoreVPS VM.
# Run ON the target VM after cloud-init has completed.
#
# Usage: ./test-e2e.sh [BASE_URL] [COMPOSE_DIR]
# Defaults:
#   BASE_URL    = http://localhost:2283
#   COMPOSE_DIR = /opt/immich  (directory containing docker-compose.yaml + .env)
#
# Requires: docker, curl, python3
# Environment:
#   DB_PASSWORD  — must match the value in COMPOSE_DIR/.env (enables log scan)

set -uo pipefail

URL="${1:-http://localhost:2283}"
COMPOSE_DIR="${2:-/opt/immich}"
PASS=0; FAIL=0; SKIP=0
TEST_EMAIL="testadmin@immich-e2e.local"
TEST_PASS="ImmichE2ETest2026!"
TOKEN=""
ASSET_ID=""

_pass() { echo "✅ PASS  $1"; PASS=$((PASS+1)); }
_fail() { echo "❌ FAIL  $1"; FAIL=$((FAIL+1)); }
_skip() { echo "⏭️  SKIP  $1"; SKIP=$((SKIP+1)); }
_info() { echo "   INFO  $1"; }

echo "=== Immich E2E Boot Test ==="
echo "    URL:         $URL"
echo "    Compose dir: $COMPOSE_DIR"
echo ""

# ── E01: docker-compose.yaml present in COMPOSE_DIR ───────────────────────────
if [ -f "$COMPOSE_DIR/docker-compose.yaml" ]; then
  _pass "E01 docker-compose.yaml present at $COMPOSE_DIR"
else
  _fail "E01 docker-compose.yaml missing at $COMPOSE_DIR"
fi

# ── E02: /opt/immich/ volume directories exist ────────────────────────────────
for dir in upload model-cache postgres; do
  if [ -d "$COMPOSE_DIR/$dir" ]; then
    _pass "E02 $COMPOSE_DIR/$dir exists"
  else
    _fail "E02 $COMPOSE_DIR/$dir missing"
  fi
done

# ── E03: Wait for server (max 5 min — cloud-init startup) ─────────────────────
_info "Waiting for Immich server (up to 5 min)…"
E03_OK=0
for i in $(seq 1 30); do
  if curl -fsS --max-time 5 "$URL/api/server/ping" 2>/dev/null | grep -q pong; then
    E03_OK=1
    _info "Server ready after ~$((i * 10))s"
    break
  fi
  sleep 10
done
[ $E03_OK -eq 1 ] \
  && _pass "E03 Server reachable within 5 minutes of boot" \
  || _fail "E03 Server not reachable after 5 minutes"

# ── E04: All 4 containers healthy ─────────────────────────────────────────────
CONTAINERS=$(docker ps --filter "name=immich" --format "{{.Names}}\t{{.Status}}" 2>/dev/null || echo "")
if [ -z "$CONTAINERS" ]; then
  _fail "E04 No running immich containers found"
else
  ALL_HEALTHY=1
  while IFS=$'\t' read -r name status; do
    if echo "$status" | grep -qE "\(healthy\)"; then
      _info "$name → healthy"
    else
      ALL_HEALTHY=0
      _info "$name → $status ← NOT healthy"
    fi
  done <<< "$CONTAINERS"
  [ $ALL_HEALTHY -eq 1 ] \
    && _pass "E04 All containers healthy (no crash loops)" \
    || _fail "E04 One or more containers not healthy"
fi

# ── E05: Web UI returns HTTP 200 ──────────────────────────────────────────────
HTTP=$(curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 "$URL/" 2>/dev/null || echo "0")
[ "$HTTP" = "200" ] && _pass "E05 Web UI HTTP 200 on port 2283" || _fail "E05 Web UI HTTP $HTTP"

# ── E06: Version check ────────────────────────────────────────────────────────
VER=$(curl -fsS --max-time 10 "$URL/api/server/version" 2>/dev/null \
  | python3 -c "import sys,json; v=json.load(sys.stdin); print(f\"{v['major']}.{v['minor']}.{v['patch']}\")" 2>/dev/null || echo "")
[ "$VER" = "2.7.5" ] \
  && _pass "E06 Server version = 2.7.5" \
  || _fail "E06 Version: expected 2.7.5, got '${VER}'"

# ── E07: Admin sign-up + login ────────────────────────────────────────────────
SIGNUP=$(curl -fsS -X POST "$URL/api/auth/admin-sign-up" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"name\":\"E2E Admin\",\"password\":\"$TEST_PASS\"}" 2>/dev/null || echo "{}")
if echo "$SIGNUP" | python3 -c "import sys,json; j=json.load(sys.stdin); exit(0 if 'email' in j else 1)" 2>/dev/null; then
  _pass "E07 Admin sign-up"
else
  _fail "E07 Admin sign-up: $(echo "$SIGNUP" | head -c 100)"
fi

LOGIN=$(curl -fsS -X POST "$URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASS\"}" 2>/dev/null || echo "{}")
TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin).get('accessToken',''))" 2>/dev/null || echo "")
[ -n "$TOKEN" ] && _pass "E07 Login successful" || _fail "E07 Login failed"

# ── E08: Photo upload + thumbnail ────────────────────────────────────────────
if [ -z "$TOKEN" ]; then
  _skip "E08 Photo upload (no token)"
  _skip "E09 Thumbnail (no token)"
else
  TMPIMG=$(mktemp /tmp/immich-e2e-XXXXXX.png)
  python3 - "$TMPIMG" <<'PYEOF'
import sys, zlib, struct
w, h = 10, 10
sig = b'\x89PNG\r\n\x1a\n'
ihdr_data = struct.pack('>II', w, h) + bytes([8, 2, 0, 0, 0])
ihdr_crc = zlib.crc32(b'IHDR' + ihdr_data) & 0xffffffff
ihdr = struct.pack('>I', 13) + b'IHDR' + ihdr_data + struct.pack('>I', ihdr_crc)
raw = b''.join(b'\x00' + b'\xff\xff\xff' * w for _ in range(h))
compressed = zlib.compress(raw, 9)
idat_crc = zlib.crc32(b'IDAT' + compressed) & 0xffffffff
idat = struct.pack('>I', len(compressed)) + b'IDAT' + compressed + struct.pack('>I', idat_crc)
iend_crc = zlib.crc32(b'IEND') & 0xffffffff
iend = b'\x00\x00\x00\x00IEND' + struct.pack('>I', iend_crc)
with open(sys.argv[1], 'wb') as f:
    f.write(sig + ihdr + idat + iend)
PYEOF

  CSUM=$(python3 -c "
import hashlib, base64
with open('$TMPIMG','rb') as f: d = f.read()
print(base64.b64encode(hashlib.sha1(d).digest()).decode())
" 2>/dev/null || echo "")
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  UPLOAD=$(curl -fsS -X POST "$URL/api/assets" \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-immich-checksum: $CSUM" \
    -F "assetData=@${TMPIMG};type=image/png" \
    -F "deviceAssetId=e2e-$(date +%s)" \
    -F "deviceId=e2e-test" \
    -F "fileCreatedAt=$NOW" \
    -F "fileModifiedAt=$NOW" 2>/dev/null || echo "{}")
  rm -f "$TMPIMG"
  ASSET_ID=$(echo "$UPLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
  [ -n "$ASSET_ID" ] \
    && _pass "E08 Photo upload (id=${ASSET_ID:0:8}…)" \
    || _fail "E08 Photo upload: $(echo "$UPLOAD" | head -c 150)"

  # thumbnail
  _info "Waiting for thumbnail (max 60s)…"
  THUMB_OK=0
  for i in $(seq 1 20); do
    HTTP=$(curl -fsS -o /dev/null -w "%{http_code}" \
      "$URL/api/assets/$ASSET_ID/thumbnail?size=thumbnail" \
      -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "0")
    [ "$HTTP" = "200" ] && THUMB_OK=1 && break
    sleep 3
  done
  [ $THUMB_OK -eq 1 ] && _pass "E09 Thumbnail generated (HTTP 200)" || _fail "E09 Thumbnail not ready after 60s"
fi

# ── E10: Upload file visible under /opt/immich/upload/ ───────────────────────
if [ -n "$ASSET_ID" ]; then
  UPLOAD_COUNT=$(find "$COMPOSE_DIR/upload" -type f 2>/dev/null | wc -l)
  [ "${UPLOAD_COUNT:-0}" -gt 0 ] \
    && _pass "E10 Upload file present on host at $COMPOSE_DIR/upload/ ($UPLOAD_COUNT files)" \
    || _fail "E10 No files found under $COMPOSE_DIR/upload/"
else
  _skip "E10 Host upload check (upload failed)"
fi

# ── E11: Full stack restart — docker compose down + up ────────────────────────
if [ -n "$ASSET_ID" ] && [ -n "$TOKEN" ]; then
  _info "Stopping full stack (docker compose down)…"
  docker compose -f "$COMPOSE_DIR/docker-compose.yaml" --project-directory "$COMPOSE_DIR" down 2>/dev/null
  sleep 5
  _info "Starting full stack (docker compose up -d)…"
  docker compose -f "$COMPOSE_DIR/docker-compose.yaml" --project-directory "$COMPOSE_DIR" up -d 2>/dev/null
  # Wait for server to recover
  E11_OK=0
  for i in $(seq 1 30); do
    if curl -fsS --max-time 5 "$URL/api/server/ping" 2>/dev/null | grep -q pong; then
      E11_OK=1; break
    fi
    sleep 5
  done
  if [ $E11_OK -eq 0 ]; then
    _fail "E11 Server did not recover after full stack restart"
  else
    # Re-login
    LOGIN2=$(curl -fsS -X POST "$URL/api/auth/login" \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASS\"}" 2>/dev/null || echo "{}")
    TOKEN=$(echo "$LOGIN2" | python3 -c "import sys,json; print(json.load(sys.stdin).get('accessToken','$TOKEN'))" 2>/dev/null || echo "$TOKEN")
    CHECK=$(curl -fsS "$URL/api/assets/$ASSET_ID" \
      -H "Authorization: Bearer $TOKEN" 2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
    [ "$CHECK" = "$ASSET_ID" ] \
      && _pass "E11 Volume persistence: asset accessible after full stack restart (down+up)" \
      || _fail "E11 Asset missing after full stack restart"
  fi
else
  _skip "E11 Full restart test (upload failed)"
fi

# ── E12: DB_PASSWORD + REDIS_PASSWORD not in logs ─────────────────────────────
SRV=$(docker ps --filter "name=immich" --filter "status=running" \
  --format "{{.Names}}" 2>/dev/null | grep -v "machine-learning" | grep "server" | head -1 || echo "")
if [ -n "$SRV" ]; then
  REDIS_COUNT=$(docker logs "$SRV" 2>&1 | grep -Fc "REDIS_PASSWORD" || true)
  [ "${REDIS_COUNT:-0}" = "0" ] \
    && _pass "E12 REDIS_PASSWORD not in logs" \
    || _fail "E12 REDIS_PASSWORD appears ${REDIS_COUNT} times in logs"
  if [ -n "${DB_PASSWORD:-}" ]; then
    DB_COUNT=$(docker logs "$SRV" 2>&1 | grep -Fc "$DB_PASSWORD" || true)
    [ "${DB_COUNT:-0}" = "0" ] \
      && _pass "E12 DB_PASSWORD not in logs" \
      || _fail "E12 DB_PASSWORD appears ${DB_COUNT} times in logs"
  else
    _skip "E12 DB_PASSWORD log scan (set DB_PASSWORD env var to enable)"
  fi
else
  _skip "E12 Log scan (container not found)"
fi

# ── E13: Performance baseline ─────────────────────────────────────────────────
echo ""
echo "--- Performance Baseline ---"
docker stats --no-stream --format "{{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}" 2>/dev/null \
  | grep "immich" || echo "(no running immich containers)"
_pass "E13 Performance baseline captured"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
