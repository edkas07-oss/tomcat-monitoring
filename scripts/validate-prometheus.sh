#!/usr/bin/env bash
#
# Purpose: Validate Prometheus static configuration contracts without runtime containers.
# Usage: ./scripts/validate-prometheus.sh
#
# Contract: Inspects scrape fields, rules, and TLS contracts.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly CONFIG_FILE="${PROJECT_ROOT}/config/prometheus/prometheus.yml"
readonly RULE_FILE="${PROJECT_ROOT}/config/prometheus/rules/application-health.yml"
readonly EMPTY_METRICS_FIXTURE="${PROJECT_ROOT}/fixtures/prometheus-empty-metrics/metrics"
readonly EMPTY_METRICS_RESPONDER="${PROJECT_ROOT}/fixtures/prometheus-empty-metrics/respond.sh"

fail() {
    printf 'PROMETHEUS VALIDATION FAILED: %s\n' "$1" >&2
    exit 1
}

require_line() {
    local expected_line="$1"
    local target_file="${2:-${CONFIG_FILE}}"

    grep --fixed-strings --quiet --line-regexp "${expected_line}" "${target_file}" \
        || fail "Required contract field not found in ${target_file}: ${expected_line}"
}

validate_contract() {
    local job_count
    local alert_count
    local duration_count

    [[ -f "${CONFIG_FILE}" ]] || fail "Configuration file not found: ${CONFIG_FILE}"
    [[ -f "${RULE_FILE}" ]] || fail "Alert rules file not found: ${RULE_FILE}"
    [[ -f "${EMPTY_METRICS_FIXTURE}" ]] \
        || fail "Empty metrics fixture not found: ${EMPTY_METRICS_FIXTURE}"
    [[ -x "${EMPTY_METRICS_RESPONDER}" ]] \
        || fail "Empty metrics responder not executable: ${EMPTY_METRICS_RESPONDER}"
    bash -n "${EMPTY_METRICS_RESPONDER}"

    require_line '  scrape_interval: 30s'
    require_line '  scrape_timeout: 10s'
    require_line 'rule_files:'
    require_line '  - /etc/prometheus/rules/*.yml'
    require_line 'alerting:'
    require_line '  alertmanagers:'
    require_line '    - api_version: v2'
    require_line '      static_configs:'
    require_line '        - targets:'
    require_line '            - alertmanager:9093'
    require_line '  - job_name: tomcat-jmx-exporter'
    require_line '    scheme: https'
    require_line '    metrics_path: /metrics'
    require_line '      ca_file: /run/secrets/tomcat-monitoring/jmx-exporter-ca.crt'
    require_line '      insecure_skip_verify: false'
    require_line '          - tomcat-jmx-exporter:9404'
    require_line '  - job_name: telegraf-health'
    require_line '    scheme: http'
    require_line '          - telegraf:9273'
    require_line '  - job_name: tomcat-diagnostic-service'
    require_line '    scheme: https'
    require_line '    metrics_path: /health'
    require_line '      ca_file: /run/secrets/tomcat-monitoring/diagnostic-service-ca.crt'
    require_line '          - diagnostic-service:8443'
    require_line '      - alert: TelegrafHealthScrapeUnavailable' "${RULE_FILE}"
    require_line '      - alert: TomcatApplicationHealthMetricsMissing' "${RULE_FILE}"
    require_line '      - alert: TomcatApplicationHealthFailed' "${RULE_FILE}"
    require_line '      - alert: TomcatDown' "${RULE_FILE}"
    require_line '      - alert: DiagnosticServiceDown' "${RULE_FILE}"
    require_line '          severity: warning' "${RULE_FILE}"
    require_line '          severity: critical' "${RULE_FILE}"
    require_line '              service="tomcat",' "${RULE_FILE}"
    require_line '              check="application-health"' "${RULE_FILE}"

    job_count="$(grep --count --extended-regexp '^  - job_name: ' "${CONFIG_FILE}")"
    [[ "${job_count}" -eq 3 ]] \
        || fail "Configuration must have exactly three scrape jobs."

    alert_count="$(grep --count --extended-regexp '^      - alert: ' "${RULE_FILE}")"
    [[ "${alert_count}" -eq 5 ]] \
        || fail "Rule file must have exactly five alerts."

    duration_count="$(grep --count --fixed-strings '        for: 2m' "${RULE_FILE}")"
    [[ "${duration_count}" -eq 4 ]] \
        || fail "Application alerts must use for: 2m baseline."

    ds_duration_count="$(grep --count --fixed-strings '        for: 1m' "${RULE_FILE}")"
    [[ "${ds_duration_count}" -eq 1 ]] \
        || fail "DiagnosticServiceDown alert must use for: 1m."

    sed -n '/^      - alert: TelegrafHealthScrapeUnavailable$/,/^        annotations:$/p' \
        "${RULE_FILE}" | grep --fixed-strings --quiet '          severity: critical' \
        || fail "Telegraf scrape unavailable must be critical."
    sed -n '/^      - alert: TelegrafHealthScrapeUnavailable$/,/^        annotations:$/p' \
        "${RULE_FILE}" | grep --fixed-strings --quiet '          service: tomcat' \
        || fail "Telegraf scrape unavailable must have service label."
    sed -n '/^      - alert: TelegrafHealthScrapeUnavailable$/,/^        annotations:$/p' \
        "${RULE_FILE}" | grep --fixed-strings --quiet '          check: application-health' \
        || fail "Telegraf scrape unavailable must have check label."

    if grep --quiet --extended-regexp \
        '^[[:space:]]*(password|bearer_token|credentials):' "${CONFIG_FILE}"; then
        fail "Inline secrets are not permitted in Prometheus configuration."
    fi

    if grep --quiet --fixed-strings 'insecure_skip_verify: true' "${CONFIG_FILE}"; then
        fail "TLS certificate verification must not be disabled."
    fi

    if grep --quiet --extended-regexp \
        '^[[:space:]]*(password|bearer_token|credentials):' "${RULE_FILE}"; then
        fail "Inline secrets are not permitted in Prometheus alert rules."
    fi

    if grep --quiet --fixed-strings 'http_response_result_code' \
        "${EMPTY_METRICS_FIXTURE}"; then
        fail "Empty metrics fixture must not generate application-health series."
    fi

    grep --fixed-strings --quiet \
        'Content-Type: text/plain; version=0.0.4' "${EMPTY_METRICS_RESPONDER}" \
        || fail "Empty metrics responder must send Prometheus content type."
}

main() {
    validate_contract
    printf 'Prometheus source validation passed: scrape, rule, and Alertmanager delivery contracts are valid.\n'
}

main "$@"
