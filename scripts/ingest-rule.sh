#!/usr/bin/env bash
# Helper CLI untuk Operator/SRE meng-ingest Declarative Rulepack ke Diagnostic Service
# Penggunaan:
#   ./scripts/ingest-rule.sh <path-to-rulepack.json>
#   cat rule.json | ./scripts/ingest-rule.sh -
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly NETWORK_NAME="devops-lab"
readonly NODEJS_IMAGE="localhost/nodejs:latest"
readonly DIAGNOSTIC_URL="https://diagnostic-service:8443"
readonly BEARER_TOKEN="${BEARER_TOKEN:-test-token-12345}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

fail() {
    printf "${RED}✘ ERROR:${NC} %s\n" "$1" >&2
    exit 1
}

pass() {
    printf "${GREEN}✔ SUCCESS:${NC} %s\n" "$1"
}

if [[ $# -lt 1 ]]; then
    printf "Penggunaan: $0 <path-to-rulepack.json>\n" >&2
    printf "Contoh:     $0 /tmp/my-ai-rule.json\n" >&2
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

# Validasi JSON sederhana
if ! echo "${PAYLOAD_CONTENT}" | jq . >/dev/null 2>&1; then
    fail "Isi berkas bukan format JSON yang valid."
fi

printf "${BLUE}ℹ Mengirimkan Rulepack ke Diagnostic Service (${DIAGNOSTIC_URL}/api/v1/rules)...${NC}\n"

RESPONSE=$(podman run --rm -i --network "${NETWORK_NAME}" "${NODEJS_IMAGE}" node --env-file-if-exists=/dev/null -e "
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
import fs from 'node:fs';
const payload = fs.readFileSync(0, 'utf-8');

try {
  const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules', {
    method: 'POST',
    headers: {
      'Authorization': 'Bearer ${BEARER_TOKEN}',
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
    pass "Rulepack berhasil di-ingest dan diaktifkan secara hot-reload (Status: 201 Created)."
    printf "${GREEN}Detail Aturan Tersimpan:${NC}\n"
    echo "${RESPONSE}" | jq .data
elif [[ "${STATUS_CODE}" == "409" ]]; then
    printf "${YELLOW}⚠ CONFLICT (409): Rule branch atau nama sudah terdaftar sebelumnya.${NC}\n"
    echo "${RESPONSE}" | jq .data
else
    fail "Ingestion ditolak oleh 5-Layer Guard (Status: ${STATUS_CODE}): $(echo "${RESPONSE}" | jq -c .data)"
fi
