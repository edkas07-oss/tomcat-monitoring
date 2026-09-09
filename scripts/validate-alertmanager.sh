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
readonly DIAGNOSTIC_PREPARE_SCRIPT="${SCRIPT_DIR}/prepare-alertmanager-diagnostic-service.sh"
readonly DIAGNOSTIC_VERIFICATION_SCRIPT="${SCRIPT_DIR}/verify-alertmanager-diagnostic-service.sh"
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
    local diagnostic_receiver_count
    local emergency_receiver_count

    [[ -f "${CONFIG_FILE}" ]] \
        || fail "Configuration tidak ditemukan: ${CONFIG_FILE}"

    require_line '  resolve_timeout: 5m'
    require_line 'route:'
    require_line '  receiver: lab-diagnostic-service'
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

    if grep --quiet --fixed-strings 'View in Alertmanager' "${CONFIG_FILE}"; then
        fail "Email tidak boleh menampilkan link Alertmanager yang tidak operator-accessible."
    fi

    group_label_count="$(
        sed -n '/^  group_by:$/,/^  group_wait:/p' "${CONFIG_FILE}" \
            | grep --count --extended-regexp '^    - (alertname|job|instance|service|check)$'
    )"
    [[ "${group_label_count}" -eq 5 ]] \
        || fail "Grouping harus menggunakan tepat lima stable labels."

    if grep --quiet --fixed-strings '  - name: lab-mailpit' "${CONFIG_FILE}"; then
        fail "Configuration tidak boleh memiliki receiver lab-mailpit (seluruh alert wajib melalui diagnostic service)."
    fi

    diagnostic_receiver_count="$(grep --count --fixed-strings \
        '  - name: lab-diagnostic-service' "${CONFIG_FILE}")"
    [[ "${diagnostic_receiver_count}" -eq 1 ]] \
        || fail "Configuration harus memiliki tepat satu Diagnostic Service receiver."

    emergency_receiver_count="$(grep --count --fixed-strings \
        '  - name: direct-email-emergency' "${CONFIG_FILE}")"
    [[ "${emergency_receiver_count}" -eq 1 ]] \
        || fail "Configuration harus memiliki tepat satu direct emergency SMTP receiver."

    if grep --quiet --extended-regexp \
        '^[[:space:]]+(auth_username|auth_password|auth_secret|password|token|bearer_token|credentials):' \
        "${CONFIG_FILE}"; then
        fail "Credential atau secret tidak diizinkan pada Alertmanager configuration."
    fi

    if sed -n '/^  - name: direct-email-emergency$/,/^  - name: /p' "${CONFIG_FILE}" \
            | head -n -1 \
            | grep --quiet --fixed-strings 'webhook_configs:'; then
        fail "Receiver direct-email-emergency tidak boleh memiliki webhook_configs."
    fi

    # Sub-route DiagnosticServiceDown dan receiver direct-email-emergency harus tersedia
    require_line '    - receiver: direct-email-emergency'
    require_line '        - alertname = "DiagnosticServiceDown"'

    # Receiver lab-diagnostic-service harus dikonfigurasi dengan aman
    require_line '  - name: lab-diagnostic-service'
    require_line '    webhook_configs:'
    require_line '      - url_file: /run/secrets/tomcat-monitoring/diagnostic-service-webhook-url'
    require_line '            credentials_file: /run/secrets/tomcat-monitoring/diagnostic-service-bearer-token'
    require_line '            ca_file: /run/secrets/tomcat-monitoring/diagnostic-service-ca.crt'
    require_line '        max_alerts: 1'

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

    [[ -f "${DIAGNOSTIC_PREPARE_SCRIPT}" ]] \
        || fail "Diagnostic service fixture preparation script tidak ditemukan."
    [[ -f "${DIAGNOSTIC_VERIFICATION_SCRIPT}" ]] \
        || fail "Diagnostic service verification interface tidak ditemukan."

    grep --fixed-strings --quiet 'readonly NETWORK_NAME="tm-tn014-diagnostic-route"' \
        "${DIAGNOSTIC_VERIFICATION_SCRIPT}" \
        || fail "Diagnostic verification interface harus menggunakan exact disposable network."
    grep --fixed-strings --quiet 'readonly ALERTMANAGER_CONTAINER="tm-tn014-alertmanager"' \
        "${DIAGNOSTIC_VERIFICATION_SCRIPT}" \
        || fail "Diagnostic verification interface harus menggunakan exact disposable Alertmanager container."
    grep --fixed-strings --quiet 'readonly DIAGNOSTIC_CONTAINER="tm-tn014-diagnostic-service"' \
        "${DIAGNOSTIC_VERIFICATION_SCRIPT}" \
        || fail "Diagnostic verification interface harus menggunakan exact disposable DS container."
    grep --fixed-strings --quiet 'readonly HOST_ADDRESS="127.0.0.1"' \
        "${DIAGNOSTIC_VERIFICATION_SCRIPT}" \
        || fail "Diagnostic verification interface harus hanya publish Alertmanager API ke loopback."
    grep --fixed-strings --quiet 'readonly EXPECTED_PREFIX="/tmp/tm-tn014-diagnostic-route."' \
        "${DIAGNOSTIC_PREPARE_SCRIPT}" \
        || fail "Diagnostic prepare script harus menggunakan exact temp path prefix."
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
