#!/usr/bin/env bash
# Helper CLI untuk Operator/SRE meng-ingest Declarative Rulepack ke Diagnostic Service
# Mendukung:
#   1. Single Rule JSON Object: {...}
#   2. Batch Array of Rules:    [{...}, {...}]
#   3. Custom Token via: BEARER_TOKEN="your-token" ./scripts/ingest-rule.sh <file>
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly NETWORK_NAME="devops-lab"
readonly NODEJS_IMAGE="localhost/nodejs:latest"
readonly DIAGNOSTIC_URL="https://diagnostic-service:8443"
readonly AUTH_TOKEN="${BEARER_TOKEN:-test-token-12345}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

fail() {
    printf "${RED}✘ ERROR:${NC} %s\n" "$1" >&2
    exit 1
}

pass() {
    printf "${GREEN}✔ SUCCESS:${NC} %s\n" "$1"
}

info() {
    printf "${BLUE}ℹ INFO:${NC} %s\n" "$1"
}

if [[ $# -lt 1 ]]; then
    printf "Penggunaan: $0 <path-to-rulepack.json>\n" >&2
    printf "Contoh:     $0 /tmp/my-ai-rule.json\n" >&2
    printf "            cat rule.json | $0 -\n" >&2
    printf "            BEARER_TOKEN=\"my-token\" $0 /tmp/my-ai-rule.json\n" >&2
    exit 1
fi

PAYLOAD_INPUT="$1"
PAYLOAD_CONTENT=""

if [[ "${PAYLOAD_INPUT}" == "-" ]]; then
    PAYLOAD_CONTENT="$(cat)"
else
    [[ -f "${PAYLOAD_INPUT}" ]] || fail "File tidak ditemukan: ${PAYLOAD_INPUT}"
    PAYLOAD_CONTENT="$(cat "${PAYLOAD_INPUT}")"
fi

# Validasi format JSON
if ! echo "${PAYLOAD_CONTENT}" | jq . >/dev/null 2>&1; then
    fail "Isi berkas bukan format JSON yang valid."
fi

# Deteksi tipe JSON: Array (batch) vs Object (single)
IS_ARRAY=$(echo "${PAYLOAD_CONTENT}" | jq 'if type == "array" then true else false end')

if [[ "${IS_ARRAY}" == "true" ]]; then
    TOTAL_RULES=$(echo "${PAYLOAD_CONTENT}" | jq 'length')
    info "Mendeteksi Batch Rulepack: Terdiri dari ${TOTAL_RULES} aturan."
    
    CREATED_COUNT=0
    CONFLICT_COUNT=0
    FAILED_COUNT=0

    for ((i = 0; i < TOTAL_RULES; i++)); do
        SINGLE_RULE=$(echo "${PAYLOAD_CONTENT}" | jq -c ".[$i]")
        BRANCH=$(echo "${SINGLE_RULE}" | jq -r '.branch // "UNKNOWN"')
        NAME=$(echo "${SINGLE_RULE}" | jq -r '.ruleName // "UNKNOWN"')

        RESPONSE=$(podman run --rm -i --network "${NETWORK_NAME}" "${NODEJS_IMAGE}" node --no-warnings --env-file-if-exists=/dev/null -e "
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
import fs from 'node:fs';
const payload = fs.readFileSync(0, 'utf-8');
try {
  const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules', {
    method: 'POST',
    headers: {
      'Authorization': 'Bearer ${AUTH_TOKEN}',
      'Content-Type': 'application/json'
    },
    body: payload
  });
  const data = await res.json();
  console.log(JSON.stringify({ status: res.status, data }));
} catch (err) {
  console.error(err);
  process.exit(1);
}
" <<< "${SINGLE_RULE}")

        STATUS_CODE=$(echo "${RESPONSE}" | jq -r .status)

        if [[ "${STATUS_CODE}" == "201" ]]; then
            pass "Rule ${BRANCH} (${NAME}) berhasil di-ingest (201 Created)."
            CREATED_COUNT=$((CREATED_COUNT + 1))
        elif [[ "${STATUS_CODE}" == "409" ]]; then
            printf "${YELLOW}⚠ SKIP:${NC} Rule ${BRANCH} (${NAME}) sudah terdaftar (409 Conflict).\n"
            CONFLICT_COUNT=$((CONFLICT_COUNT + 1))
        else
            printf "${RED}✘ GAGAL:${NC} Rule ${BRANCH} (${NAME}) ditolak (${STATUS_CODE}): %s\n" "$(echo "${RESPONSE}" | jq -c .data)" >&2
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    done

    printf "\n${CYAN}=== Ringkasan Batch Ingestion ===${NC}\n"
    printf "Total Diproses : %d\n" "${TOTAL_RULES}"
    printf "${GREEN}Berhasil (Baru): %d${NC}\n" "${CREATED_COUNT}"
    printf "${YELLOW}Dilewati (Ada) : %d${NC}\n" "${CONFLICT_COUNT}"
    printf "${RED}Gagal Ditolak  : %d${NC}\n" "${FAILED_COUNT}"

    if [[ ${FAILED_COUNT} -gt 0 ]]; then
        exit 1
    fi
else
    BRANCH=$(echo "${PAYLOAD_CONTENT}" | jq -r '.branch // "UNKNOWN"')
    NAME=$(echo "${PAYLOAD_CONTENT}" | jq -r '.ruleName // "UNKNOWN"')
    info "Mengirimkan Rulepack ${BRANCH} (${NAME}) ke ${DIAGNOSTIC_URL}/api/v1/rules..."

    RESPONSE=$(podman run --rm -i --network "${NETWORK_NAME}" "${NODEJS_IMAGE}" node --no-warnings --env-file-if-exists=/dev/null -e "
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
import fs from 'node:fs';
const payload = fs.readFileSync(0, 'utf-8');
try {
  const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules', {
    method: 'POST',
    headers: {
      'Authorization': 'Bearer ${AUTH_TOKEN}',
      'Content-Type': 'application/json'
    },
    body: payload
  });
  const data = await res.json();
  console.log(JSON.stringify({ status: res.status, data }));
} catch (err) {
  console.error(err);
  process.exit(1);
}
" <<< "${PAYLOAD_CONTENT}")

    STATUS_CODE=$(echo "${RESPONSE}" | jq -r .status)

    if [[ "${STATUS_CODE}" == "201" ]]; then
        pass "Rulepack ${BRANCH} (${NAME}) berhasil di-ingest dan aktif seketika (201 Created)."
        printf "${GREEN}Detail Rule Tersimpan:${NC}\n"
        echo "${RESPONSE}" | jq .data
    elif [[ "${STATUS_CODE}" == "409" ]]; then
        printf "${YELLOW}⚠ CONFLICT (409): Rule branch atau nama '${BRANCH}' sudah terdaftar sebelumnya.${NC}\n"
        echo "${RESPONSE}" | jq .data
    else
        fail "Ingestion ditolak oleh 5-Layer Guard (Status: ${STATUS_CODE}): $(echo "${RESPONSE}" | jq -c .data)"
    fi
fi
