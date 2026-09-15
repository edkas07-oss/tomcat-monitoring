#!/usr/bin/env bash
#
# Purpose: Validate JMX Exporter baseline static contract without Java Agent or runtime.
# Usage: ./scripts/validate-jmx-exporter.sh
#
# Contract: The validator inspects TLS structure, password reference, certificate alias,
# and baseline rules. It does not replace runtime parse, TLS handshake, or Prometheus scraping.

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
        || fail "Required contract field not found: ${expected_line}"
}

validate_contract() {
    local password_field_count
    local rule_count

    [[ -f "${CONFIG_FILE}" ]] \
        || fail "Configuration file not found: ${CONFIG_FILE}"

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
    [[ "${rule_count}" -ge 2 ]] \
        || fail "Configuration must have at least two baseline rules."

    password_field_count="$(
        grep --count --extended-regexp '^[[:space:]]*password:' "${CONFIG_FILE}"
    )"
    [[ "${password_field_count}" -eq 1 ]] \
        || fail "Configuration must have exactly one password reference."

    if grep --quiet --extended-regexp \
        '^[[:space:]]*password:[[:space:]]+[^$]' "${CONFIG_FILE}"; then
        fail "Inline plaintext password is not permitted in JMX Exporter configuration."
    fi
}

main() {
    validate_contract
    printf 'JMX Exporter source validation passed: TLS and baseline rules are valid.\n'
}

main "$@"
