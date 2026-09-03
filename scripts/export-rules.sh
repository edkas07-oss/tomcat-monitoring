#!/usr/bin/env bash
# Helper CLI untuk Operator/SRE mengekspor katalog Declarative Rulepack dari Diagnostic Service
# Penggunaan:
#   ./scripts/export-rules.sh              # Menampilkan semua rule aktif (JSON)
#   ./scripts/export-rules.sh TD-09        # Menampilkan detail rule spesifik
#   ./scripts/export-rules.sh > rules.json # Menyimpan ke berkas backup
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly NETWORK_NAME="devops-lab"
readonly NODEJS_IMAGE="localhost/nodejs:latest"
readonly DIAGNOSTIC_URL="https://diagnostic-service:8443"
readonly BEARER_TOKEN="${BEARER_TOKEN:-test-token-12345}"

BRANCH_OR_ID="${1:-}"
ENDPOINT="/api/v1/rules"

if [[ -n "${BRANCH_OR_ID}" ]]; then
    ENDPOINT="/api/v1/rules/${BRANCH_OR_ID}"
fi

podman run --rm -i --network "${NETWORK_NAME}" "${NODEJS_IMAGE}" node --env-file-if-exists=/dev/null -e "
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
try {
  const res = await fetch('${DIAGNOSTIC_URL}${ENDPOINT}', {
    headers: { 'Authorization': 'Bearer ${BEARER_TOKEN}' }
  });
  if (!res.ok) {
    console.error('Error status:', res.status, await res.text());
    process.exit(1);
  }
  const data = await res.json();
  console.log(JSON.stringify(data, null, 2));
} catch (err) {
  console.error(err);
  process.exit(1);
}
"
