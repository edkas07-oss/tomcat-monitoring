#!/usr/bin/env bash
#
# Tujuan: memvalidasi baseline layout Tomcat Monitoring tanpa dependency atau
# runtime. Penggunaan: ./scripts/validate.sh
#
# Kontrak: validator memeriksa file contract, syntax Bash, nama file material
# sensitif yang dilarang, dan static component contracts tanpa menjalankan
# dependency atau runtime.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly REQUIRED_FILES=(
    "AGENTS.md"
    "CONFIG"
    "README.md"
    ".gitignore"
    "config/README.md"
    "config/jmx-exporter/README.md"
    "config/jmx-exporter/jmx-exporter.yml"
    "config/prometheus/README.md"
    "config/prometheus/prometheus.yml"
    "config/prometheus/rules/application-health.yml"
    "config/prometheus/tests/application-health.test.yml"
    "config/telegraf/README.md"
    "config/telegraf/health-check.conf"
    "config/alertmanager/README.md"
    "config/alertmanager/alertmanager.yml"
    "config/diagnostic-service/README.md"
    "config/diagnostic-service/application.json"
    "config/diagnostic-service/targets.json"
    "config/event-collector/README.md"
    "fixtures/alertmanager-webhook-receiver/capture.py"
    "fixtures/alertmanager-diagnostic-route/probe.js"
    "fixtures/diagnostic-service-mailpit/database-probe.js"
    "fixtures/diagnostic-service-mailpit/reopen-probe.js"
    "fixtures/diagnostic-service-mailpit/runtime-probe.js"
    "fixtures/prometheus-empty-metrics/metrics"
    "fixtures/prometheus-empty-metrics/respond.sh"
    "fixtures/tomcat-health-app/WEB-INF/health.jsp"
    "fixtures/tomcat-health-app/WEB-INF/web.xml"
    "validation/README.md"
    "scripts/validate.sh"
    "scripts/deploy-alertmanager.sh"
    "scripts/deploy-diagnostic-service.sh"
    "scripts/deploy-event-collector.sh"
    "scripts/deploy-prometheus.sh"
    "scripts/deploy-tomcat.sh"
    "scripts/export-rules.sh"
    "scripts/ingest-rule.sh"
    "scripts/initialize-alertmanager-volumes.sh"
    "scripts/initialize-prometheus-volumes.sh"
    "scripts/prepare-alertmanager-diagnostic-service.sh"
    "scripts/prepare-diagnostic-service-mailpit.sh"
    "scripts/test-tomcatdown-live.sh"
    "scripts/validate-ai-knowledge-lifecycle.sh"
    "scripts/validate-alertmanager.sh"
    "scripts/validate-jmx-exporter.sh"
    "scripts/validate-prometheus.sh"
    "scripts/validate-telegraf.sh"
    "scripts/validate-tomcat-health-app.sh"
    "scripts/verify-alertmanager-diagnostic-service.sh"
    "scripts/verify-alertmanager-mailpit.sh"
    "scripts/verify-alertmanager-webhook.sh"
    "scripts/verify-diagnostic-service-mailpit.sh"
    "scripts/verify-jvm-workload-live.sh"
    "scripts/verify-postfix-relay.sh"
)

fail() {
    printf 'VALIDATION FAILED: %s\n' "$1" >&2
    exit 1
}

validate_required_files() {
    local relative_path

    for relative_path in "${REQUIRED_FILES[@]}"; do
        [[ -f "${PROJECT_ROOT}/${relative_path}" ]] \
            || fail "File contract tidak ditemukan: ${relative_path}"
    done
}

validate_shell_syntax() {
    bash -n "${SCRIPT_DIR}"/*.sh
}

validate_sensitive_filenames() {
    local sensitive_file

    while IFS= read -r sensitive_file; do
        fail "Nama file material sensitif tidak diizinkan: ${sensitive_file#"${PROJECT_ROOT}/"}"
    done < <(
        find "${PROJECT_ROOT}" \
            -path "${PROJECT_ROOT}/.git" -prune -o \
            -type f \( \
                -name '*.pem' -o -name '*.key' -o -name '*.p12' -o \
                -name '*.pfx' -o -name '*.jks' -o -name '*.keystore' -o \
                -name '.env' -o -name '*.env' \
            \) -print
    )
}

validate_diagnostic_service_mailpit_contract() {
    local prepare_script="${SCRIPT_DIR}/prepare-diagnostic-service-mailpit.sh"
    local verify_script="${SCRIPT_DIR}/verify-diagnostic-service-mailpit.sh"

    grep --fixed-strings --quiet 'readonly NETWORK_NAME="tm-tn013-diagnostic"' "${verify_script}" \
        || fail "TN-013 network identity tidak sesuai contract."
    grep --fixed-strings --quiet 'readonly DIAGNOSTIC_CONTAINER="tm-tn013-diagnostic-service"' "${verify_script}" \
        || fail "TN-013 Diagnostic Service identity tidak sesuai contract."
    grep --fixed-strings --quiet 'readonly CLIENT_CONTAINER="tm-tn013-diagnostic-client"' "${verify_script}" \
        || fail "TN-013 client identity tidak sesuai contract."
    grep --fixed-strings --quiet 'readonly MAILPIT_CONTAINER="tm-tn013-diagnostic-mailpit"' "${verify_script}" \
        || fail "TN-013 Mailpit identity tidak sesuai contract."
    grep --fixed-strings --quiet 'tomcat-diagnostic-service@sha256:' "${verify_script}" \
        || fail "Diagnostic Service harus dikonsumsi dengan exact digest."
    grep --fixed-strings --quiet 'mailpit:v1.31.0@sha256:c96991d9bef73594c246d89ca81411d4e916f03e76a7d2d72fa2ab5dd3c9ce24' "${verify_script}" \
        || fail "Mailpit immutable reference tidak sesuai contract."
    grep --fixed-strings --quiet '/tmp/tomcat-diagnostic-tn013.' "${prepare_script}" \
        || fail "TN-013 temporary path contract tidak tersedia."
    if grep --extended-regexp --quiet -- '--publish|-p[[:space:]]' "${verify_script}"; then
        fail "TN-013 disposable runtime tidak boleh memublikasikan host port."
    fi
}

validate_config_contract() {
    local config_file="${PROJECT_ROOT}/CONFIG"
    [[ -f "${config_file}" ]] || fail "Declarative CONFIG file tidak ditemukan: ${config_file}"

    # Verify bash syntax of CONFIG
    bash -n "${config_file}" || fail "Syntax error pada ${config_file}"

    # Verify baseline keys
    for key in \
        PLATFORM_NAME NETWORK_NAME \
        TOMCAT_CONTAINER PROMETHEUS_CONTAINER ALERTMANAGER_CONTAINER DIAGNOSTIC_CONTAINER POSTFIX_CONTAINER MAILPIT_CONTAINER \
        TOMCAT_HTTP_PORT TOMCAT_JMX_PORT PROMETHEUS_PORT ALERTMANAGER_PORT DIAGNOSTIC_PORT MAILPIT_HTTP_PORT MAILPIT_SMTP_PORT POSTFIX_PORT TELEGRAF_PORT \
        TOMCAT_LOG_VOLUME DIAGNOSTIC_DATA_VOLUME PROMETHEUS_DATA_VOLUME ALERTMANAGER_DATA_VOLUME \
        DEFAULT_PROMETHEUS_RETENTION_TIME DEFAULT_MAX_SPOOL_AGE_HOURS DEFAULT_MAX_SPOOL_FILES DEFAULT_STALE_TMP_AGE_MINUTES; do
        grep --extended-regexp --quiet "^${key}=" "${config_file}" \
            || fail "Key '${key}' wajib didefinisikan pada CONFIG baseline."
    done
}

main() {
    validate_required_files
    validate_shell_syntax
    validate_sensitive_filenames
    validate_config_contract
    validate_diagnostic_service_mailpit_contract
    "${SCRIPT_DIR}/validate-alertmanager.sh"
    "${SCRIPT_DIR}/validate-jmx-exporter.sh"
    "${SCRIPT_DIR}/validate-prometheus.sh"
    "${SCRIPT_DIR}/validate-telegraf.sh"
    "${SCRIPT_DIR}/validate-tomcat-health-app.sh"
    printf 'Baseline validation passed: repository layout dan contract statis valid.\n'
}

main "$@"
