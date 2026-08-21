#!/usr/bin/env bash
#
# Tujuan: memvalidasi baseline layout Tomcat Monitoring tanpa dependency atau
# runtime. Penggunaan: ./scripts/validate.sh
#
# Kontrak: validator hanya memeriksa file contract, syntax Bash, dan nama file
# material sensitif yang dilarang. Ia tidak memvalidasi configuration component
# yang belum tersedia dan tidak membaca isi material sensitif.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly REQUIRED_FILES=(
    "AGENTS.md"
    "README.md"
    ".gitignore"
    "config/README.md"
    "config/jmx-exporter/README.md"
    "config/prometheus/README.md"
    "config/telegraf/README.md"
    "config/telegraf/health-check.conf"
    "config/alertmanager/README.md"
    "validation/README.md"
    "scripts/validate.sh"
    "scripts/validate-telegraf.sh"
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
    "${SCRIPT_DIR}/validate-telegraf.sh"
    printf 'Baseline validation passed: repository layout dan contract statis valid.\n'
}

main "$@"
