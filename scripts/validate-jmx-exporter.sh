#!/usr/bin/env bash
#
# Tujuan: memvalidasi baseline contract JMX Exporter tanpa Java Agent atau
# runtime container. Penggunaan: ./scripts/validate-jmx-exporter.sh
#
# Kontrak: validator memeriksa TLS structure, password reference, certificate
# alias, dan tepat dua baseline rules. Ia tidak menggantikan runtime parse,
# TLS handshake, Prometheus scrape, atau final operational metric validation.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly CONFIG_FILE="${PROJECT_ROOT}/config/jmx-exporter/jmx-exporter.yml"

fail() {
    printf 'JMX EXPORTER VALIDATION FAILED: %s\n' "$1" >&2
    exit 1
}

require_line() {
    local expected_line="$1"

    grep --fixed-strings --quiet --line-regexp "${expected_line}" "${CONFIG_FILE}" \
        || fail "Field contract tidak ditemukan: ${expected_line}"
}

validate_contract() {
    local password_field_count
    local rule_count

    [[ -f "${CONFIG_FILE}" ]] \
        || fail "Configuration tidak ditemukan: ${CONFIG_FILE}"

    require_line 'httpServer:'
    require_line '      filename: /run/secrets/tomcat-jmx-exporter/keystore.p12'
    require_line '      type: PKCS12'
    require_line '      password: ${JMX_EXPORTER_KEYSTORE_PASSWORD}'
    require_line '      alias: tomcat-jmx-exporter'
    require_line "  - pattern: 'java.lang<type=Memory><HeapMemoryUsage>used: (.+)'"
    require_line '    name: jvm_memory_heap_used_bytes'
    require_line "  - pattern: 'Catalina<type=Server><>serverInfo: (.+)'"
    require_line '    name: tomcat_server'

    rule_count="$(grep --count --extended-regexp '^  - pattern: ' "${CONFIG_FILE}")"
    [[ "${rule_count}" -eq 2 ]] \
        || fail "Configuration harus memiliki tepat dua baseline rules."

    password_field_count="$(
        grep --count --extended-regexp '^[[:space:]]*password:' "${CONFIG_FILE}"
    )"
    [[ "${password_field_count}" -eq 1 ]] \
        || fail "Configuration harus memiliki tepat satu password reference."

    if grep --quiet --extended-regexp \
        '^[[:space:]]*password:[[:space:]]+[^$]' "${CONFIG_FILE}"; then
        fail "Inline password tidak diizinkan pada JMX Exporter configuration."
    fi
}

main() {
    validate_contract
    printf 'JMX Exporter source validation passed: TLS dan two-rule baseline valid.\n'
}

main "$@"
