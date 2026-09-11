#!/usr/bin/env bash
# Helper CLI untuk Operator/SRE mengekspor katalog Declarative Rulepack dari Diagnostic Service
# Penggunaan:
#   ./scripts/export-rules.sh                                  # Menampilkan semua rule aktif (JSON)
#   ./scripts/export-rules.sh --categories                     # Menampilkan daftar ringkasan kategori aktif
#   ./scripts/export-rules.sh --category database_persistence  # Filter rule berdasarkan kategori
#   ./scripts/export-rules.sh TD-09                            # Menampilkan detail rule spesifik
#   ./scripts/export-rules.sh > ~/master-rules.json            # Menyimpan katalog ke berkas lokal
#   DIAGNOSTIC_URL="https://remote-host:8443" BEARER_TOKEN="my-token" ./scripts/export-rules.sh
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi

readonly DIAGNOSTIC_URL="${DIAGNOSTIC_URL:-https://localhost:${DIAGNOSTIC_PORT:-8443}}"
readonly AUTH_TOKEN="${BEARER_TOKEN:-test-token-12345}"

MODE="default"
ENDPOINT="/api/v1/rules"

if [[ "${1:-}" == "--categories" || "${1:-}" == "--list-categories" ]]; then
    MODE="categories"
elif [[ "${1:-}" == "--category" && -n "${2:-}" ]]; then
    ENDPOINT="/api/v1/rules?category=${2}"
elif [[ -n "${1:-}" ]]; then
    ENDPOINT="/api/v1/rules/${1}"
fi

HTTP_RESPONSE=$(curl -k -s -w "\n%{http_code}" -H "Authorization: Bearer ${AUTH_TOKEN}" "${DIAGNOSTIC_URL}${ENDPOINT}" || true)
HTTP_STATUS=$(echo "${HTTP_RESPONSE}" | tail -n1)
BODY=$(echo "${HTTP_RESPONSE}" | sed '$d')

if [[ "${HTTP_STATUS}" -ne 200 ]]; then
    echo "Error status: ${HTTP_STATUS}" >&2
    echo "${BODY}" >&2
    exit 1
fi

if [[ "${MODE}" == "categories" ]]; then
    echo "=== Daftar Kategori Rulepack Aktif di Sistem ==="
    python3 -c '
import sys, json
data = json.loads(sys.argv[1])
rules = data.get("rules", [])
cat_map = {}
for r in rules:
    cat = r.get("category", "general")
    cat_map.setdefault(cat, []).append(r.get("branch", ""))
for cat in sorted(cat_map.keys()):
    branches = ", ".join(cat_map[cat])
    print(f"• {cat:<24} : {len(cat_map[cat])} aturan ({branches})")
print("-" * 50)
print(f"Total Kategori Terdaftar: {len(cat_map)}")
print(f"Total Aturan Kustom     : {len(rules)}")
' "${BODY}"
else
    echo "${BODY}" | jq . 2>/dev/null || echo "${BODY}"
fi
