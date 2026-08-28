#!/usr/bin/env bash
#
# Tujuan: memvalidasi contract statis Alertmanager tanpa binary atau runtime.
# Penggunaan: ./scripts/validate-alertmanager.sh
#
# Kontrak: validator memeriksa routing baseline, local Mailpit receiver, dan
# resolved delivery tanpa credential. Ia tidak menggantikan `amtool
# check-config`, SMTP capture test, Prometheus delivery, atau deployment
# verification.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly CONFIG_FILE="${PROJECT_ROOT}/config/alertmanager/alertmanager.yml"
readonly RECEIVER_FIXTURE="${PROJECT_ROOT}/fixtures/alertmanager-webhook-receiver/capture.py"
readonly WEBHOOK_VERIFICATION_SCRIPT="${SCRIPT_DIR}/verify-alertmanager-webhook.sh"
readonly MAILPIT_VERIFICATION_SCRIPT="${SCRIPT_DIR}/verify-alertmanager-mailpit.sh"
readonly VOLUME_INITIALIZER="${SCRIPT_DIR}/initialize-alertmanager-volumes.sh"

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
    require_line '  receiver: lab-mailpit'
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
    require_line '  - name: lab-mailpit'
    require_line '    email_configs:'
    require_line '      - to: operator@tomcat-monitoring.invalid'
    require_line '        from: alertmanager@tomcat-monitoring.invalid'
    require_line '        smarthost: mailpit:1025'
    require_line '        require_tls: false'
    require_line '        send_resolved: true'
    require_line "          Subject: '[Tomcat Monitoring][{{ .Status }}] {{ .CommonLabels.alertname }} - {{ .CommonLabels.instance }}'"

    group_label_count="$(
        sed -n '/^  group_by:$/,/^  group_wait:/p' "${CONFIG_FILE}" \
            | grep --count --extended-regexp '^    - (alertname|job|instance|service|check)$'
    )"
    [[ "${group_label_count}" -eq 5 ]] \
        || fail "Grouping harus menggunakan tepat lima stable labels."

    receiver_count="$(grep --count --fixed-strings \
        '  - name: lab-mailpit' "${CONFIG_FILE}")"
    [[ "${receiver_count}" -eq 1 ]] \
        || fail "Configuration harus memiliki tepat satu local Mailpit receiver."

    if grep --quiet --extended-regexp \
        '^[[:space:]]+(auth_username|auth_password|auth_secret|password|token|bearer_token|credentials):' \
        "${CONFIG_FILE}"; then
        fail "Credential atau secret tidak diizinkan pada Alertmanager configuration."
    fi

    if grep --quiet --fixed-strings 'webhook_configs:' "${CONFIG_FILE}"; then
        fail "Active webhook receiver tidak diizinkan pada local Mailpit baseline."
    fi

    if grep --extended-regexp '^[[:space:]]+(to|from):' "${CONFIG_FILE}" \
        | grep --invert-match --quiet --fixed-strings '@tomcat-monitoring.invalid'; then
        fail "Mail identity harus menggunakan reserved tomcat-monitoring.invalid domain."
    fi

    if grep --ignore-case --quiet --extended-regexp \
        'truesight|msend|snmp[[:space:]_-]*trap' "${CONFIG_FILE}"; then
        fail "TrueSight mapping tidak boleh menjadi tanggung jawab Alertmanager configuration."
    fi
}

validate_fixture_contract() {
    [[ -f "${RECEIVER_FIXTURE}" ]] \
        || fail "Webhook receiver fixture tidak ditemukan."
    [[ -f "${WEBHOOK_VERIFICATION_SCRIPT}" ]] \
        || fail "Webhook verification interface tidak ditemukan."
    [[ -f "${MAILPIT_VERIFICATION_SCRIPT}" ]] \
        || fail "Mailpit verification interface tidak ditemukan."

    grep --fixed-strings --quiet 'if self.path != "/alerts":' "${RECEIVER_FIXTURE}" \
        || fail "Receiver fixture harus membatasi endpoint pada /alerts."
    grep --fixed-strings --quiet 'Thread(target=self.server.shutdown' "${RECEIVER_FIXTURE}" \
        || fail "Receiver fixture harus berhenti setelah bounded request count."
    grep --fixed-strings --quiet 'readonly CONTAINER_NAME="tm-tn029-alertmanager"' \
        "${WEBHOOK_VERIFICATION_SCRIPT}" \
        || fail "Verification interface harus menggunakan exact disposable container."
    grep --fixed-strings --quiet 'podman rm --force --volumes "${CONTAINER_NAME}"' \
        "${WEBHOOK_VERIFICATION_SCRIPT}" \
        || fail "Verification interface harus membersihkan exact disposable container."
    grep --fixed-strings --quiet 'readonly MAILPIT_CONTAINER="tm-tn033-mailpit"' \
        "${MAILPIT_VERIFICATION_SCRIPT}" \
        || fail "Mailpit interface harus menggunakan exact disposable Mailpit container."
    grep --fixed-strings --quiet 'readonly NETWORK_NAME="tm-tn033-mailpit"' \
        "${MAILPIT_VERIFICATION_SCRIPT}" \
        || fail "Mailpit interface harus menggunakan exact disposable network."
    grep --fixed-strings --quiet 'readonly SMTP_HOST="mailpit:1025"' \
        "${MAILPIT_VERIFICATION_SCRIPT}" \
        || fail "Mailpit interface harus menjaga SMTP tetap internal."
}

validate_persistent_volume_contract() {
    [[ -x "${VOLUME_INITIALIZER}" ]] \
        || fail "Persistent volume initializer tidak tersedia atau tidak executable."
    bash -n "${VOLUME_INITIALIZER}"

    grep --fixed-strings --quiet 'readonly INITIALIZER="alertmanager-volume-init"' \
        "${VOLUME_INITIALIZER}" \
        || fail "Initializer harus menggunakan exact temporary container."
    grep --fixed-strings --quiet 'readonly CONFIG_VOLUME="alertmanager_config"' \
        "${VOLUME_INITIALIZER}" \
        || fail "Initializer harus menggunakan exact configuration volume."
    grep --fixed-strings --quiet 'readonly DATA_VOLUME="alertmanager_data"' \
        "${VOLUME_INITIALIZER}" \
        || fail "Initializer harus menggunakan exact data volume."
    grep --fixed-strings --quiet 'podman cp "${CONFIG_FILE}"' \
        "${VOLUME_INITIALIZER}" \
        || fail "Configuration harus disalin melalui podman cp."
    grep --fixed-strings --quiet 'podman rm "${INITIALIZER}"' \
        "${VOLUME_INITIALIZER}" \
        || fail "Initializer cleanup harus menargetkan exact container."

    if grep --quiet --extended-regexp \
        'podman[[:space:]]+(volume[[:space:]]+rm|rm[[:space:]].*--volumes)' \
        "${VOLUME_INITIALIZER}"; then
        fail "Initializer tidak boleh menghapus named volume."
    fi
}

main() {
    validate_contract
    validate_fixture_contract
    validate_persistent_volume_contract
    printf 'Alertmanager source validation passed: routing, local Mailpit receiver, disposable verification, dan persistent volume contract statis valid.\n'
}

main "$@"
