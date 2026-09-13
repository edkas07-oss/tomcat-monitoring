#!/usr/bin/env bash
# Deploy script for Tomcat with JMX Exporter runtime in devops-lab.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi
# shellcheck source=scripts/container-runtime-helper.sh
source "${SCRIPT_DIR}/container-runtime-helper.sh"

if [[ -z "${TOMCAT_JMX_REPO:-}" ]]; then
    if [[ -d "$(dirname "${PROJECT_ROOT}")/tomcat-jmx-exporter" ]]; then
        TOMCAT_JMX_REPO="$(dirname "${PROJECT_ROOT}")/tomcat-jmx-exporter"
    elif [[ -d "${HOME}/git/tomcat-jmx-exporter" ]]; then
        TOMCAT_JMX_REPO="${HOME}/git/tomcat-jmx-exporter"
    else
        TOMCAT_JMX_REPO="$(dirname "${PROJECT_ROOT}")/tomcat-jmx-exporter"
    fi
fi
readonly TOMCAT_JMX_REPO
readonly TLS_DIR="${TLS_DIR:-${DEFAULT_JMX_TLS_DIR:-${HOME}/.local/share/tomcat-monitoring/jmx-exporter-tls}}"
readonly CONFIG_FILE="${PROJECT_ROOT}/config/jmx-exporter/jmx-exporter.yml"
readonly KEYSTORE_FILE="${TLS_DIR}/keystore.p12"
readonly PASSWORD_FILE="${TLS_DIR}/keystore-password"
readonly CONTAINER_NAME="${TOMCAT_CONTAINER:-tomcat-jmx-exporter}"
readonly ROLLBACK_NAME="tomcat-jmx-exporter-rollback-tn016"
readonly TOMCAT_JMX_PORT="${TOMCAT_JMX_PORT:-9404}"

fail() {
    printf 'TOMCAT DEPLOYMENT FAILED: %s\n' "$1" >&2
    exit 1
}

main() {
    [[ -d "${TOMCAT_JMX_REPO}" ]] || fail "Tomcat JMX Exporter repo tidak ditemukan: ${TOMCAT_JMX_REPO}"
    [[ -f "${CONFIG_FILE}" ]] || fail "Config file tidak ditemukan: ${CONFIG_FILE}"
    [[ -f "${KEYSTORE_FILE}" ]] || fail "Keystore file tidak ditemukan: ${KEYSTORE_FILE}"
    [[ -f "${PASSWORD_FILE}" ]] || fail "Password file tidak ditemukan: ${PASSWORD_FILE}"

    if container_exists "${CONTAINER_NAME}"; then
        echo "1. Stopping and renaming existing Tomcat container..."
        "${CONTAINER_ENGINE}" stop "${CONTAINER_NAME}" || true
        "${CONTAINER_ENGINE}" rm -f "${ROLLBACK_NAME}" 2>/dev/null || true
        "${CONTAINER_ENGINE}" rename "${CONTAINER_NAME}" "${ROLLBACK_NAME}"
    else
        echo "1. No existing Tomcat container found."
    fi


    echo "2. Starting new Tomcat JMX Exporter container..."
    "${TOMCAT_JMX_REPO}/scripts/run.sh" \
        "${CONFIG_FILE}" \
        "${KEYSTORE_FILE}" \
        "${PASSWORD_FILE}" \
        "${CONTAINER_NAME}" \
        "${TOMCAT_HTTP_PORT:-8083}" \
        "${TOMCAT_JMX_PORT:-9404}" >/dev/null

    echo "3. Verifying readiness..."
    local attempts=15
    for ((i = 1; i <= attempts; i++)); do
        if curl --fail --silent --insecure "https://127.0.0.1:${TOMCAT_JMX_PORT}/metrics" >/dev/null 2>&1 \
            || curl --fail --silent --insecure "https://${CONTAINER_NAME}:${TOMCAT_JMX_PORT}/metrics" >/dev/null 2>&1; then
            echo "Tomcat JMX Exporter is ready and exposing metrics over HTTPS."
            exit 0
        fi
        sleep 1
    done

    fail "Tomcat JMX Exporter did not become ready within expected time."
}

main "$@"
