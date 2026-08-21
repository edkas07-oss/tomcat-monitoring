#!/usr/bin/env bash
#
# Tujuan: memvalidasi contract statis Telegraf health check tanpa binary
# Telegraf atau runtime container. Penggunaan: ./scripts/validate-telegraf.sh
#
# Kontrak: validator memeriksa field input HTTP dan output Prometheus yang
# disetujui. Ia tidak menggantikan `telegraf --test`, scrape Prometheus, atau
# health check terhadap aplikasi nyata.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly CONFIG_FILE="${PROJECT_ROOT}/config/telegraf/health-check.conf"

fail() {
    printf 'TELEGRAF VALIDATION FAILED: %s\n' "$1" >&2
    exit 1
}

require_line() {
    local expected_line="$1"

    grep --fixed-strings --quiet --line-regexp "${expected_line}" "${CONFIG_FILE}" \
        || fail "Field contract tidak ditemukan: ${expected_line}"
}

validate_contract() {
    [[ -f "${CONFIG_FILE}" ]] || fail "Configuration tidak ditemukan: ${CONFIG_FILE}"

    require_line '  urls = ["${TOMCAT_HEALTH_URL:?TOMCAT_HEALTH_URL wajib diisi}"]'
    require_line '  method = "GET"'
    require_line '  response_timeout = "5s"'
    require_line '  response_status_code = 200'
    require_line '  response_string_match = "\"status\"\\s*:\\s*\"UP\""'
    require_line '  interval = "30s"'
    require_line '  listen = ":9273"'
    require_line '  path = "/metrics"'
    require_line '  metric_version = 2'
}

main() {
    validate_contract
    printf 'Telegraf source validation passed: health-check contract statis valid.\n'
}

main "$@"
