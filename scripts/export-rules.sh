#!/usr/bin/env bash
# Helper CLI untuk Operator/SRE mengekspor katalog Declarative Rulepack dari Diagnostic Service
# Penggunaan:
#   ./scripts/export-rules.sh                                  # Menampilkan semua rule aktif (JSON)
#   ./scripts/export-rules.sh --categories                     # Menampilkan daftar ringkasan kategori aktif
#   ./scripts/export-rules.sh --category database_persistence  # Filter rule berdasarkan kategori
#   ./scripts/export-rules.sh TD-09                            # Menampilkan detail rule spesifik
#   ./scripts/export-rules.sh > rules.json                     # Menyimpan katalog ke berkas lokal
#   BEARER_TOKEN="my-token" ./scripts/export-rules.sh
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly NETWORK_NAME="devops-lab"
readonly NODEJS_IMAGE="localhost/nodejs:latest"
readonly DIAGNOSTIC_URL="https://diagnostic-service:8443"
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

podman run --rm -i --network "${NETWORK_NAME}" "${NODEJS_IMAGE}" node --no-warnings --env-file-if-exists=/dev/null -e "
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
try {
  const res = await fetch('${DIAGNOSTIC_URL}${ENDPOINT}', {
    headers: { 'Authorization': 'Bearer ${AUTH_TOKEN}' }
  });
  if (!res.ok) {
    console.error('Error status:', res.status, await res.text());
    process.exit(1);
  }
  const data = await res.json();
  
  if ('${MODE}' === 'categories') {
    const rules = data.rules || [];
    const catMap = {};
    for (const r of rules) {
      const cat = r.category || 'general';
      if (!catMap[cat]) catMap[cat] = [];
      catMap[cat].push(r.branch);
    }
    
    console.log('=== Daftar Kategori Rulepack Aktif di Sistem ===');
    const sortedCats = Object.keys(catMap).sort();
    for (const cat of sortedCats) {
      const branches = catMap[cat].join(', ');
      console.log(\`• \${cat.padEnd(24)} : \${catMap[cat].length} aturan (\${branches})\`);
    }
    console.log('--------------------------------------------------');
    console.log(\`Total Kategori Terdaftar: \${sortedCats.length}\`);
    console.log(\`Total Aturan Kustom     : \${rules.length}\`);
  } else {
    console.log(JSON.stringify(data, null, 2));
  }
} catch (err) {
  console.error(err);
  process.exit(1);
}
"
