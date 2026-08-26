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
    "fixtures/prometheus-empty-metrics/metrics"
    "fixtures/prometheus-empty-metrics/respond.sh"
    "fixtures/tomcat-health-app/WEB-INF/health.jsp"
    "fixtures/tomcat-health-app/WEB-INF/web.xml"
    "validation/README.md"
    "scripts/validate.sh"
    "scripts/initialize-prometheus-volumes.sh"
    "scripts/validate-alertmanager.sh"
    "scripts/validate-jmx-exporter.sh"
    "scripts/validate-prometheus.sh"
    "scripts/validate-telegraf.sh"
    "scripts/validate-tomcat-health-app.sh"
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

main() {
    validate_required_files
    validate_shell_syntax
    validate_sensitive_filenames
    "${SCRIPT_DIR}/validate-alertmanager.sh"
    "${SCRIPT_DIR}/validate-jmx-exporter.sh"
    "${SCRIPT_DIR}/validate-prometheus.sh"
    "${SCRIPT_DIR}/validate-telegraf.sh"
    "${SCRIPT_DIR}/validate-tomcat-health-app.sh"
    printf 'Baseline validation passed: repository layout dan contract statis valid.\n'
}

main "$@"
