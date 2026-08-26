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
        || fail "Field contract tidak ditemukan pada ${target_file}: ${expected_line}"
}

validate_contract() {
    local job_count
    local alert_count
    local duration_count

    [[ -f "${CONFIG_FILE}" ]] || fail "Configuration tidak ditemukan: ${CONFIG_FILE}"
    [[ -f "${RULE_FILE}" ]] || fail "Alert rules tidak ditemukan: ${RULE_FILE}"
    [[ -f "${EMPTY_METRICS_FIXTURE}" ]] \
        || fail "Empty metrics fixture tidak ditemukan: ${EMPTY_METRICS_FIXTURE}"
    [[ -x "${EMPTY_METRICS_RESPONDER}" ]] \
        || fail "Empty metrics responder tidak executable: ${EMPTY_METRICS_RESPONDER}"
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
    require_line '      - alert: TelegrafHealthScrapeUnavailable' "${RULE_FILE}"
    require_line '      - alert: TomcatApplicationHealthMetricsMissing' "${RULE_FILE}"
    require_line '      - alert: TomcatApplicationHealthFailed' "${RULE_FILE}"
    require_line '          severity: warning' "${RULE_FILE}"
    require_line '          severity: critical' "${RULE_FILE}"
    require_line '              service="tomcat",' "${RULE_FILE}"
    require_line '              check="application-health"' "${RULE_FILE}"

    job_count="$(grep --count --extended-regexp '^  - job_name: ' "${CONFIG_FILE}")"
    [[ "${job_count}" -eq 2 ]] \
        || fail "Configuration harus memiliki tepat dua scrape job."

    alert_count="$(grep --count --extended-regexp '^      - alert: ' "${RULE_FILE}")"
    [[ "${alert_count}" -eq 3 ]] \
        || fail "Rule file harus memiliki tepat tiga alert."

    duration_count="$(grep --count --fixed-strings '        for: 2m' "${RULE_FILE}")"
    [[ "${duration_count}" -eq 3 ]] \
        || fail "Setiap alert harus menggunakan lab baseline for: 2m."

    if grep --quiet --extended-regexp \
        '^[[:space:]]*(password|bearer_token|credentials):' "${CONFIG_FILE}"; then
        fail "Inline secret tidak diizinkan pada Prometheus configuration."
    fi

    if grep --quiet --fixed-strings 'insecure_skip_verify: true' "${CONFIG_FILE}"; then
        fail "TLS certificate verification tidak boleh dinonaktifkan."
    fi

    if grep --quiet --extended-regexp \
        '^[[:space:]]*(password|bearer_token|credentials):' "${RULE_FILE}"; then
        fail "Inline secret tidak diizinkan pada Prometheus alert rules."
    fi

    if grep --quiet --fixed-strings 'http_response_result_code' \
        "${EMPTY_METRICS_FIXTURE}"; then
        fail "Empty metrics fixture tidak boleh menghasilkan application-health series."
    fi

    grep --fixed-strings --quiet \
        'Content-Type: text/plain; version=0.0.4' "${EMPTY_METRICS_RESPONDER}" \
        || fail "Empty metrics responder harus mengirim Prometheus content type."
}

main() {
    validate_contract
    printf 'Prometheus source validation passed: scrape, rule, dan Alertmanager delivery contract statis valid.\n'
}

main "$@"
