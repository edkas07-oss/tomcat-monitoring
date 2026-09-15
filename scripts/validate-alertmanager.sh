#!/usr/bin/env bash
#
# Purpose: Validate Alertmanager static contract without dependencies or runtime.
# Usage: ./scripts/validate-alertmanager.sh
#
# Contract: The validator inspects routing baseline, local Mailpit receiver, and
# resolved delivery without credentials. It does not replace `amtool check-config`,
# SMTP capture tests, Prometheus delivery, or deployment verification.

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
        || fail "Required contract field not found: ${expected_line}"
}

validate_contract() {
    local group_label_count
    local receiver_count
    local diagnostic_receiver_count
    local emergency_receiver_count

    [[ -f "${CONFIG_FILE}" ]] \
        || fail "Configuration file not found: ${CONFIG_FILE}"

    require_line '  resolve_timeout: 5m'
    require_line 'route:'
    require_line '  receiver: lab-diagnostic-service'
    require_line '  group_by:'
    require_line '    - alertname'
    require_line '    - job'
    require_line '    - instance'
    require_line '    - service'
    require_line '    - check'
    require_line '  group_wait: 10s'
    require_line '  group_interval: 15s'
    require_line '  repeat_interval: 4h'
    require_line 'receivers:'

    if grep --quiet --fixed-strings 'View in Alertmanager' "${CONFIG_FILE}"; then
        fail "Email templates must not expose inaccessible Alertmanager links to operators."
    fi

    group_label_count="$(
        sed -n '/^  group_by:$/,/^  group_wait:/p' "${CONFIG_FILE}" \
            | grep --count --extended-regexp '^    - (alertname|job|instance|service|check)$'
    )"
    [[ "${group_label_count}" -eq 5 ]] \
        || fail "Grouping must use exactly five stable labels."

    if grep --quiet --fixed-strings '  - name: lab-mailpit' "${CONFIG_FILE}"; then
        fail "Configuration must not have receiver lab-mailpit (all alerts must route through diagnostic service)."
    fi

    diagnostic_receiver_count="$(grep --count --fixed-strings \
        '  - name: lab-diagnostic-service' "${CONFIG_FILE}")"
    [[ "${diagnostic_receiver_count}" -eq 1 ]] \
        || fail "Configuration must have exactly one Diagnostic Service receiver."

    emergency_receiver_count="$(grep --count --fixed-strings \
        '  - name: direct-email-emergency' "${CONFIG_FILE}")"
    [[ "${emergency_receiver_count}" -eq 1 ]] \
        || fail "Configuration must have exactly one direct emergency SMTP receiver."

    if grep --quiet --extended-regexp \
        '^[[:space:]]+(auth_username|auth_password|auth_secret|password|token|bearer_token|credentials):' \
        "${CONFIG_FILE}"; then
        fail "Credentials or secrets are not permitted in Alertmanager configuration files."
    fi

    if sed -n '/^  - name: direct-email-emergency$/,/^  - name: /p' "${CONFIG_FILE}" \
            | head -n -1 \
            | grep --quiet --fixed-strings 'webhook_configs:'; then
        fail "Receiver direct-email-emergency must not contain webhook_configs."
    fi

    # Sub-route DiagnosticServiceDown and receiver direct-email-emergency must exist
    require_line '    - receiver: direct-email-emergency'
    require_line '        - alertname = "DiagnosticServiceDown"'

    # Receiver lab-diagnostic-service must be securely configured
    require_line '  - name: lab-diagnostic-service'
    require_line '    webhook_configs:'
    require_line '      - url_file: /run/secrets/tomcat-monitoring/diagnostic-service-webhook-url'
    require_line '            credentials_file: /run/secrets/tomcat-monitoring/diagnostic-service-bearer-token'
    require_line '            ca_file: /run/secrets/tomcat-monitoring/diagnostic-service-ca.crt'
    require_line '        max_alerts: 1'

    if grep --extended-regexp '^[[:space:]]+(to|from):' "${CONFIG_FILE}" \
        | grep --invert-match --quiet --fixed-strings '@tomcat-monitoring.invalid'; then
        fail "Mail identity must use reserved tomcat-monitoring.invalid domain."
    fi

    if grep --ignore-case --quiet --extended-regexp \
        'truesight|msend|snmp[[:space:]_-]*trap' "${CONFIG_FILE}"; then
        fail "External monitoring mapping must not be embedded in Alertmanager configuration."
    fi
}

validate_fixture_contract() {
    [[ -f "${RECEIVER_FIXTURE}" ]] \
        || fail "Webhook receiver fixture not found."
    [[ -f "${WEBHOOK_VERIFICATION_SCRIPT}" ]] \
        || fail "Webhook verification interface not found."
    [[ -f "${MAILPIT_VERIFICATION_SCRIPT}" ]] \
        || fail "Mailpit verification interface not found."

    grep --fixed-strings --quiet 'if self.path != "/alerts":' "${RECEIVER_FIXTURE}" \
        || fail "Receiver fixture must restrict endpoints to /alerts."
    grep --fixed-strings --quiet 'Thread(target=self.server.shutdown' "${RECEIVER_FIXTURE}" \
        || fail "Receiver fixture must terminate after bounded request count."
    grep --fixed-strings --quiet 'readonly CONTAINER_NAME="tm-tn029-alertmanager"' \
        "${WEBHOOK_VERIFICATION_SCRIPT}" \
        || fail "Verification interface must use exact disposable container."
    grep --extended-regexp --quiet '(podman|"\$\{CONTAINER_ENGINE\}") rm --force --volumes "\$\{CONTAINER_NAME\}"' \
        "${WEBHOOK_VERIFICATION_SCRIPT}" \
        || fail "Verification interface must clean up exact disposable container."
    grep --fixed-strings --quiet 'readonly MAILPIT_CONTAINER="tm-tn033-mailpit"' \
        "${MAILPIT_VERIFICATION_SCRIPT}" \
        || fail "Mailpit interface must use exact disposable Mailpit container."
    grep --fixed-strings --quiet 'readonly NETWORK_NAME="tm-tn033-mailpit"' \
        "${MAILPIT_VERIFICATION_SCRIPT}" \
        || fail "Mailpit interface must use exact disposable network."
    grep --fixed-strings --quiet 'readonly SMTP_HOST="mailpit:1025"' \
        "${MAILPIT_VERIFICATION_SCRIPT}" \
        || fail "Mailpit interface must maintain SMTP internal."

    [[ -f "${DIAGNOSTIC_PREPARE_SCRIPT}" ]] \
        || fail "Diagnostic service fixture preparation script not found."
    [[ -f "${DIAGNOSTIC_VERIFICATION_SCRIPT}" ]] \
        || fail "Diagnostic service verification interface not found."

    grep --fixed-strings --quiet 'readonly NETWORK_NAME="tm-tn014-diagnostic-route"' \
        "${DIAGNOSTIC_VERIFICATION_SCRIPT}" \
        || fail "Diagnostic verification interface must use exact disposable network."
    grep --fixed-strings --quiet 'readonly ALERTMANAGER_CONTAINER="tm-tn014-alertmanager"' \
        "${DIAGNOSTIC_VERIFICATION_SCRIPT}" \
        || fail "Diagnostic verification interface must use exact disposable Alertmanager container."
    grep --fixed-strings --quiet 'readonly DIAGNOSTIC_CONTAINER="tm-tn014-diagnostic-service"' \
        "${DIAGNOSTIC_VERIFICATION_SCRIPT}" \
        || fail "Diagnostic verification interface must use exact disposable DS container."
    grep --fixed-strings --quiet 'readonly HOST_ADDRESS="127.0.0.1"' \
        "${DIAGNOSTIC_VERIFICATION_SCRIPT}" \
        || fail "Diagnostic verification interface must only publish Alertmanager API to loopback."
    grep --fixed-strings --quiet 'readonly EXPECTED_PREFIX="/tmp/tm-tn014-diagnostic-route."' \
        "${DIAGNOSTIC_PREPARE_SCRIPT}" \
        || fail "Diagnostic prepare script must use exact temp path prefix."
}

validate_persistent_volume_contract() {
    [[ -x "${VOLUME_INITIALIZER}" ]] \
        || fail "Persistent volume initializer not found or not executable."
    bash -n "${VOLUME_INITIALIZER}"

    grep --fixed-strings --quiet 'readonly INITIALIZER="alertmanager-volume-init"' \
        "${VOLUME_INITIALIZER}" \
        || fail "Initializer must use exact temporary container."
    grep --fixed-strings --quiet 'readonly CONFIG_VOLUME="${ALERTMANAGER_CONFIG_VOLUME:-alertmanager_config}"' \
        "${VOLUME_INITIALIZER}" \
        || fail "Initializer must use exact configuration volume."
    grep --fixed-strings --quiet 'readonly DATA_VOLUME="${ALERTMANAGER_DATA_VOLUME:-alertmanager_data}"' \
        "${VOLUME_INITIALIZER}" \
        || fail "Initializer must use exact data volume."
    grep --extended-regexp --quiet '(podman|"\$\{CONTAINER_ENGINE\}") cp "\$\{CONFIG_FILE\}"' \
        "${VOLUME_INITIALIZER}" \
        || fail "Configuration must be copied via container cp."
    grep --extended-regexp --quiet '(podman|"\$\{CONTAINER_ENGINE\}") rm "\$\{INITIALIZER\}"' \
        "${VOLUME_INITIALIZER}" \
        || fail "Initializer cleanup must target exact container."

    if grep --quiet --extended-regexp \
        '(podman|"\$\{CONTAINER_ENGINE\}")[[:space:]]+(volume[[:space:]]+rm|rm[[:space:]].*--volumes)' \
        "${VOLUME_INITIALIZER}"; then
        fail "Initializer must not delete named volumes."
    fi
}

main() {
    validate_contract
    validate_fixture_contract
    validate_persistent_volume_contract
    printf 'Alertmanager source validation passed: routing, local Mailpit receiver, disposable verification, and persistent volume static contracts are valid.\n'
}

main "$@"
