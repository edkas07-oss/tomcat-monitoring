#!/usr/bin/env bash
#
# Tujuan: memvalidasi contract statis Alertmanager tanpa binary atau runtime.
# Penggunaan: ./scripts/validate-alertmanager.sh
#
# Kontrak: validator memeriksa routing baseline, receiver boundary, resolved
# delivery, dan file-based secret reference. Ia tidak menggantikan `amtool
# check-config`, webhook test, Prometheus delivery, atau deployment verification.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly CONFIG_FILE="${PROJECT_ROOT}/config/alertmanager/alertmanager.yml"

fail() {
    printf 'ALERTMANAGER VALIDATION FAILED: %s\n' "$1" >&2
    exit 1
}

require_line() {
    local expected_line="$1"

    grep --fixed-strings --quiet --line-regexp "${expected_line}" "${CONFIG_FILE}" \
        || fail "Field contract tidak ditemukan: ${expected_line}"
}

validate_contract() {
    local group_label_count
    local receiver_count

    [[ -f "${CONFIG_FILE}" ]] \
        || fail "Configuration tidak ditemukan: ${CONFIG_FILE}"

    require_line '  resolve_timeout: 5m'
    require_line 'route:'
    require_line '  receiver: integration-bridge'
    require_line '  group_by:'
    require_line '    - alertname'
    require_line '    - job'
    require_line '    - instance'
    require_line '    - service'
    require_line '    - check'
    require_line '  group_wait: 30s'
    require_line '  group_interval: 5m'
    require_line '  repeat_interval: 4h'
    require_line 'receivers:'
    require_line '  - name: integration-bridge'
    require_line '    webhook_configs:'
    require_line '      - url_file: /run/secrets/tomcat-monitoring/integration-bridge-webhook-url'
    require_line '        send_resolved: true'

    group_label_count="$(
        sed -n '/^  group_by:$/,/^  group_wait:/p' "${CONFIG_FILE}" \
            | grep --count --extended-regexp '^    - (alertname|job|instance|service|check)$'
    )"
    [[ "${group_label_count}" -eq 5 ]] \
        || fail "Grouping harus menggunakan tepat lima stable labels."

    receiver_count="$(grep --count --fixed-strings \
        '  - name: integration-bridge' "${CONFIG_FILE}")"
    [[ "${receiver_count}" -eq 1 ]] \
        || fail "Configuration harus memiliki tepat satu Integration Bridge receiver."

    if grep --quiet --extended-regexp \
        '^[[:space:]]+(url|password|token|bearer_token|credentials):' \
        "${CONFIG_FILE}"; then
        fail "Inline endpoint atau secret tidak diizinkan pada Alertmanager configuration."
    fi

    if grep --ignore-case --quiet --extended-regexp \
        'truesight|msend|snmp[[:space:]_-]*trap' "${CONFIG_FILE}"; then
        fail "TrueSight mapping tidak boleh menjadi tanggung jawab Alertmanager configuration."
    fi
}

main() {
    validate_contract
    printf 'Alertmanager source validation passed: routing dan receiver boundary statis valid.\n'
}

main "$@"
