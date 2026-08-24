#!/usr/bin/env bash
#
# Tujuan: memvalidasi contract statis Prometheus tanpa binary Prometheus atau
# runtime container. Penggunaan: ./scripts/validate-prometheus.sh
#
# Kontrak: validator memeriksa field scrape dan TLS yang disetujui. Ia tidak
# menggantikan `promtool check config`, component test, atau integration test.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly CONFIG_FILE="${PROJECT_ROOT}/config/prometheus/prometheus.yml"

fail() {
    printf 'PROMETHEUS VALIDATION FAILED: %s\n' "$1" >&2
    exit 1
}

require_line() {
    local expected_line="$1"

    grep --fixed-strings --quiet --line-regexp "${expected_line}" "${CONFIG_FILE}" \
        || fail "Field contract tidak ditemukan: ${expected_line}"
}

validate_contract() {
    local job_count

    [[ -f "${CONFIG_FILE}" ]] || fail "Configuration tidak ditemukan: ${CONFIG_FILE}"

    require_line '  scrape_interval: 30s'
    require_line '  scrape_timeout: 10s'
    require_line '  - job_name: tomcat-jmx-exporter'
    require_line '    scheme: https'
    require_line '    metrics_path: /metrics'
    require_line '      ca_file: /run/secrets/tomcat-monitoring/jmx-exporter-ca.crt'
    require_line '      insecure_skip_verify: false'
    require_line '          - tomcat-jmx-exporter:9404'
    require_line '  - job_name: telegraf-health'
    require_line '    scheme: http'
    require_line '          - telegraf:9273'

    job_count="$(grep --count --extended-regexp '^  - job_name: ' "${CONFIG_FILE}")"
    [[ "${job_count}" -eq 2 ]] \
        || fail "Configuration harus memiliki tepat dua scrape job."

    if grep --quiet --extended-regexp \
        '^[[:space:]]*(password|bearer_token|credentials):' "${CONFIG_FILE}"; then
        fail "Inline secret tidak diizinkan pada Prometheus configuration."
    fi

    if grep --quiet --fixed-strings 'insecure_skip_verify: true' "${CONFIG_FILE}"; then
        fail "TLS certificate verification tidak boleh dinonaktifkan."
    fi
}

main() {
    validate_contract
    printf 'Prometheus source validation passed: scrape contract statis valid.\n'
}

main "$@"
