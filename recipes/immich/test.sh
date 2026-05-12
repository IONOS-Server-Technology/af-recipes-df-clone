#!/usr/bin/env bash
# Integration test suite for the Immich recipe.
# Usage: ./test.sh [BASE_URL]
# Optional env vars:
#   DB_PASSWORD  — enables log scan for password leakage (set from .env before running)

set -uo pipefail

URL="${1:-http://localhost:2283}"
PASS=0
FAIL=0
SKIP=0
TOKEN=""
ASSET_ID=""
TEST_EMAIL="testadmin@immich.local"
TEST_PASS="ImmichTestPass2026!"

_pass() { echo "✅ PASS  $1"; PASS=$((PASS+1)); }
_fail() { echo "❌ FAIL  $1"; FAIL=$((FAIL+1)); }
_skip() { echo "⏭️  SKIP  $1"; SKIP=$((SKIP+1)); }
_info() { echo "   INFO  $1"; }

echo "=== Immich Integration Tests ==="
echo "    URL: $URL"
echo ""

# ── T01: API ping ──────────────────────────────────────────────────────────────
if curl -fsS --max-time 10 "$URL/api/server/ping" 2>/dev/null | grep -q 'pong'; then
  _pass "T01 API ping returns pong"
else
  _fail "T01 API ping unreachable"
fi

# ── T02: Version is 2.7.5 ─────────────────────────────────────────────────────
VER=$(curl -fsS --max-time 10 "$URL/api/server/version" 2>/dev/null \
  | python3 -c "import sys,json; v=json.load(sys.stdin); print(f\"{v['major']}.{v['minor']}.{v['patch']}\")" 2>/dev/null || echo "")
if [ "$VER" = "2.7.5" ]; then
  _pass "T02 Server version = 2.7.5"
else
  _fail "T02 Version: expected 2.7.5, got '${VER}'"
fi

# ── T03: Web UI returns HTTP 200 ───────────────────────────────────────────────
HTTP_CODE=$(curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 "$URL/" 2>/dev/null || echo "0")
if [ "$HTTP_CODE" = "200" ]; then
  _pass "T03 Web UI HTTP 200"
else
  _fail "T03 Web UI HTTP $HTTP_CODE"
fi

# ── T04: Admin sign-up (first boot) ───────────────────────────────────────────
SIGNUP=$(curl -fsS -X POST "$URL/api/auth/admin-sign-up" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"name\":\"Test Admin\",\"password\":\"$TEST_PASS\"}" 2>/dev/null || echo "{}")
if echo "$SIGNUP" | python3 -c "import sys,json; j=json.load(sys.stdin); exit(0 if 'email' in j else 1)" 2>/dev/null; then
  _pass "T04 Admin account created via sign-up"
else
  _fail "T04 Admin sign-up: $(echo "$SIGNUP" | head -c 120)"
fi

# ── T05: Login → obtain token ─────────────────────────────────────────────────
LOGIN=$(curl -fsS -X POST "$URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASS\"}" 2>/dev/null || echo "{}")
TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin).get('accessToken',''))" 2>/dev/null || echo "")
if [ -n "$TOKEN" ]; then
  _pass "T05 Login successful, bearer token obtained"
else
  _fail "T05 Login: $(echo "$LOGIN" | head -c 120)"
fi

# ── T06: Photo upload ─────────────────────────────────────────────────────────
if [ -z "$TOKEN" ]; then
  _skip "T06 Photo upload (no token)"
else
  TMPIMG=$(mktemp /tmp/immich-test-XXXXXX.png)
  python3 - "$TMPIMG" <<'PYEOF'
import sys, zlib, struct
# Valid 10x10 white PNG (pure Python stdlib — no Pillow required)
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
    -F "deviceAssetId=af-test-$(date +%s)" \
    -F "deviceId=af-test-device" \
    -F "fileCreatedAt=$NOW" \
    -F "fileModifiedAt=$NOW" 2>/dev/null || echo "{}")
  rm -f "$TMPIMG"

  ASSET_ID=$(echo "$UPLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
  if [ -n "$ASSET_ID" ]; then
    _pass "T06 Photo upload successful (id=${ASSET_ID:0:8}…)"
  else
    _fail "T06 Photo upload: $(echo "$UPLOAD" | head -c 200)"
  fi
fi

# ── T07: Thumbnail generation ─────────────────────────────────────────────────
if [ -z "$ASSET_ID" ]; then
  _skip "T07 Thumbnail (upload failed)"
else
  _info "Waiting for thumbnail (max 60s)…"
  THUMB_OK=0
  for i in $(seq 1 20); do
    HTTP=$(curl -fsS -o /dev/null -w "%{http_code}" \
      "$URL/api/assets/$ASSET_ID/thumbnail?size=thumbnail" \
      -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "0")
    if [ "$HTTP" = "200" ]; then THUMB_OK=1; break; fi
    sleep 3
  done
  [ $THUMB_OK -eq 1 ] && _pass "T07 Thumbnail generated (HTTP 200)" || _fail "T07 Thumbnail not ready after 60s"
fi

# ── T08: Volume persistence (restart immich-server, asset still accessible) ───
if [ -z "$ASSET_ID" ]; then
  _skip "T08 Volume persistence (no asset)"
else
  SRV=$(docker ps --filter "name=immich" --filter "status=running" \
    --format "{{.Names}}" 2>/dev/null | grep -v "machine-learning" | grep "server" | head -1 || echo "")
  if [ -z "$SRV" ]; then
    _skip "T08 Volume persistence (immich-server container not found)"
  else
    _info "Restarting $SRV…"
    docker restart "$SRV" > /dev/null 2>&1
    # Wait for API to recover
    for i in $(seq 1 20); do
      if curl -fsS --max-time 5 "$URL/api/server/ping" 2>/dev/null | grep -q 'pong'; then break; fi
      sleep 3
    done
    # Re-login (session may have been invalidated)
    LOGIN2=$(curl -fsS -X POST "$URL/api/auth/login" \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASS\"}" 2>/dev/null || echo "{}")
    TOKEN=$(echo "$LOGIN2" | python3 -c "import sys,json; print(json.load(sys.stdin).get('accessToken','$TOKEN'))" 2>/dev/null || echo "$TOKEN")
    CHECK=$(curl -fsS "$URL/api/assets/$ASSET_ID" \
      -H "Authorization: Bearer $TOKEN" 2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
    [ "$CHECK" = "$ASSET_ID" ] \
      && _pass "T08 Volume persistence: asset accessible after server restart" \
      || _fail "T08 Volume persistence: asset missing after restart"
  fi
fi

# ── T09: DB_PASSWORD not visible in container logs ───────────────────────────
if [ -z "${DB_PASSWORD:-}" ]; then
  _skip "T09 Log scan (set DB_PASSWORD env var to enable)"
else
  SRV=$(docker ps --filter "name=immich" --filter "status=running" \
    --format "{{.Names}}" 2>/dev/null | grep -v "machine-learning" | grep "server" | head -1 || echo "")
  if [ -n "$SRV" ]; then
    COUNT=$(docker logs "$SRV" 2>&1 | grep -Fc "$DB_PASSWORD" || true)
    [ "${COUNT:-0}" = "0" ] \
      && _pass "T09 DB_PASSWORD not found in container logs" \
      || _fail "T09 DB_PASSWORD appears ${COUNT} times in logs"
  else
    _skip "T09 Log scan (container not found)"
  fi
fi

# ── T10: Performance baseline ─────────────────────────────────────────────────
echo ""
echo "--- Performance Baseline ---"
STATS=$(docker stats --no-stream --format "{{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}" 2>/dev/null \
  | grep "immich" || echo "")
if [ -n "$STATS" ]; then
  echo "$STATS"
  _pass "T10 Performance baseline captured"
else
  _skip "T10 Performance baseline (no running immich containers)"
fi

# ── T11: All 4 containers healthy (no crash loops) ───────────────────────────
CONTAINERS=$(docker ps --filter "name=immich" --format "{{.Names}}\t{{.Status}}" 2>/dev/null || echo "")
if [ -z "$CONTAINERS" ]; then
  _skip "T11 Container health (no running immich containers found)"
else
  ALL_HEALTHY=1
  UNHEALTHY_LIST=""
  while IFS=$'\t' read -r name status; do
    if echo "$status" | grep -qE "\(healthy\)"; then
      _info "$name → $status"
    elif echo "$status" | grep -qE "\(health: starting\)"; then
      _info "$name → $status (still starting)"
    else
      ALL_HEALTHY=0
      UNHEALTHY_LIST="$UNHEALTHY_LIST $name"
      _info "$name → $status ← NOT healthy"
    fi
  done <<< "$CONTAINERS"
  [ $ALL_HEALTHY -eq 1 ] \
    && _pass "T11 All containers healthy (no crash loops)" \
    || _fail "T11 Unhealthy containers:$UNHEALTHY_LIST"
fi

# ── T12: REDIS_PASSWORD not in container logs ─────────────────────────────────
SRV=$(docker ps --filter "name=immich" --filter "status=running" \
  --format "{{.Names}}" 2>/dev/null | grep -v "machine-learning" | grep "server" | head -1 || echo "")
if [ -n "$SRV" ]; then
  COUNT=$(docker logs "$SRV" 2>&1 | grep -Fc "REDIS_PASSWORD" || true)
  [ "${COUNT:-0}" = "0" ] \
    && _pass "T12 REDIS_PASSWORD not found in container logs (not used in v2)" \
    || _fail "T12 REDIS_PASSWORD appears ${COUNT} times in logs"
else
  _skip "T12 REDIS_PASSWORD log scan (container not found)"
fi

# ── T13: JPEG upload + thumbnail (real JPEG with correct Huffman tables) ──────
# This tests what T06 cannot: that Immich's Sharp image processor accepts a
# standards-compliant JPEG (not just PNG). Uses an 8x8 mid-gray JPEG built
# from the standard JFIF quantization and Huffman tables (JPEG spec Annex K).
if [ -z "$TOKEN" ]; then
  _skip "T13 JPEG upload (no token)"
else
  TMPJPEG=$(mktemp /tmp/immich-test-XXXXXX.jpg)
  python3 - "$TMPJPEG" <<'PYEOF'
import sys, struct

def seg(marker, data):
    return bytes([0xFF, marker]) + struct.pack('>H', len(data) + 2) + data

# APP0 JFIF header
app0 = seg(0xE0, b'JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00')

# DQT: standard luminance quantization table (quality ~50, JPEG spec Annex K)
luma_q = bytes([
    16,11,10,16,24,40,51,61, 12,12,14,19,26,58,60,55,
    14,13,16,24,40,57,69,56, 14,17,22,29,51,87,80,62,
    18,22,37,56,68,109,103,77, 24,35,55,64,81,104,113,92,
    49,64,78,87,103,121,120,101, 72,92,95,98,112,100,103,99,
])
dqt = seg(0xDB, bytes([0x00]) + luma_q)

# SOF0: 8x8 grayscale, 8-bit precision
sof0 = seg(0xC0, bytes([8, 0,8, 0,8, 1, 1, 0x11, 0]))

# DHT DC luminance (JPEG spec K.3.3.1)
dc_bits = bytes([0,1,5,1,1,1,1,1,1,0,0,0,0,0,0,0])
dc_vals = bytes([0,1,2,3,4,5,6,7,8,9,10,11])
dht_dc = seg(0xC4, bytes([0x00]) + dc_bits + dc_vals)

# DHT AC luminance (JPEG spec K.3.3.2)
ac_bits = bytes([0,2,1,3,3,2,4,3,5,5,4,4,0,0,1,125])
ac_vals = bytes([
    0x01,0x02,0x03,0x00,0x04,0x11,0x05,0x12,0x21,0x31,0x41,0x06,0x13,0x51,0x61,0x07,
    0x22,0x71,0x14,0x32,0x81,0x91,0xa1,0x08,0x23,0x42,0xb1,0xc1,0x15,0x52,0xd1,0xf0,
    0x24,0x33,0x62,0x72,0x82,0x09,0x0a,0x16,0x17,0x18,0x19,0x1a,0x25,0x26,0x27,0x28,
    0x29,0x2a,0x34,0x35,0x36,0x37,0x38,0x39,0x3a,0x43,0x44,0x45,0x46,0x47,0x48,0x49,
    0x4a,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5a,0x63,0x64,0x65,0x66,0x67,0x68,0x69,
    0x6a,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7a,0x83,0x84,0x85,0x86,0x87,0x88,0x89,
    0x8a,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9a,0xa2,0xa3,0xa4,0xa5,0xa6,0xa7,
    0xa8,0xa9,0xaa,0xb2,0xb3,0xb4,0xb5,0xb6,0xb7,0xb8,0xb9,0xba,0xc2,0xc3,0xc4,0xc5,
    0xc6,0xc7,0xc8,0xc9,0xca,0xd2,0xd3,0xd4,0xd5,0xd6,0xd7,0xd8,0xd9,0xda,0xe1,0xe2,
    0xe3,0xe4,0xe5,0xe6,0xe7,0xe8,0xe9,0xea,0xf1,0xf2,0xf3,0xf4,0xf5,0xf6,0xf7,0xf8,
    0xf9,0xfa,
])
dht_ac = seg(0xC4, bytes([0x10]) + ac_bits + ac_vals)

# SOS: 1 component, DC table 0, AC table 0
sos = seg(0xDA, bytes([1, 1, 0x00, 0, 63, 0]))

# Entropy-coded data for 8x8 mid-gray (all pixels = 128):
# After level shift: 0; all DCT coefficients = 0.
# DC diff=0 → category 0 → Huffman code "00" (2 bits)
# All AC=0  → EOB (0x00) → Huffman code "1010" (4 bits)
# Bit stream: 00 1010 → padded with 1s → 00101011 = 0x2B
entropy = bytes([0x2B])

jpeg = bytes([0xFF,0xD8]) + app0 + dqt + sof0 + dht_dc + dht_ac + sos + entropy + bytes([0xFF,0xD9])
with open(sys.argv[1], 'wb') as f:
    f.write(jpeg)
PYEOF

  CSUM=$(python3 -c "
import hashlib, base64
with open('$TMPJPEG','rb') as f: d = f.read()
print(base64.b64encode(hashlib.sha1(d).digest()).decode())
" 2>/dev/null || echo "")
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  UPLOAD=$(curl -fsS -X POST "$URL/api/assets" \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-immich-checksum: $CSUM" \
    -F "assetData=@${TMPJPEG};type=image/jpeg" \
    -F "deviceAssetId=af-jpeg-$(date +%s)" \
    -F "deviceId=af-test-device" \
    -F "fileCreatedAt=$NOW" \
    -F "fileModifiedAt=$NOW" 2>/dev/null || echo "{}")
  rm -f "$TMPJPEG"

  JPEG_ASSET_ID=$(echo "$UPLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
  if [ -n "$JPEG_ASSET_ID" ]; then
    _pass "T13 JPEG upload successful (id=${JPEG_ASSET_ID:0:8}…)"
    # Thumbnail for JPEG
    _info "Waiting for JPEG thumbnail (max 60s)…"
    JPEG_THUMB_OK=0
    for i in $(seq 1 20); do
      HTTP=$(curl -fsS -o /dev/null -w "%{http_code}" \
        "$URL/api/assets/$JPEG_ASSET_ID/thumbnail?size=thumbnail" \
        -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "0")
      [ "$HTTP" = "200" ] && JPEG_THUMB_OK=1 && break
      sleep 3
    done
    [ $JPEG_THUMB_OK -eq 1 ] \
      && _pass "T13 JPEG thumbnail generated (HTTP 200)" \
      || _fail "T13 JPEG thumbnail not ready after 60s"
  else
    _fail "T13 JPEG upload: $(echo "$UPLOAD" | head -c 200)"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
