#!/usr/bin/env bash
# Deploy script for Prometheus persistent runtime.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi
# shellcheck source=scripts/container-runtime-helper.sh
source "${SCRIPT_DIR}/container-runtime-helper.sh"

readonly CA_FILE="${CA_FILE:-${DEFAULT_JMX_TLS_DIR:-${HOME}/.local/share/tomcat-monitoring/jmx-exporter-tls}/server.crt}"
readonly CONTAINER_NAME="${PROMETHEUS_CONTAINER:-prometheus}"
readonly ROLLBACK_NAME="prometheus-rollback-tn015"
if [[ -z "${PROMETHEUS_REPO:-}" ]]; then
    if [[ -d "$(dirname "${PROJECT_ROOT}")/prometheus" ]]; then
        PROMETHEUS_REPO="$(dirname "${PROJECT_ROOT}")/prometheus"
    elif [[ -d "${HOME}/git/prometheus" ]]; then
        PROMETHEUS_REPO="${HOME}/git/prometheus"
    else
        PROMETHEUS_REPO="$(dirname "${PROJECT_ROOT}")/prometheus"
    fi
fi
readonly PROMETHEUS_REPO
readonly CONFIG_VOLUME="${PROMETHEUS_CONFIG_VOLUME:-prometheus_config}"
readonly TRUSTSTORE_VOLUME="${PROMETHEUS_TRUSTSTORE_VOLUME:-prometheus_truststore}"
readonly DATA_VOLUME="${PROMETHEUS_DATA_VOLUME:-prometheus_data}"
readonly PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"

fail() {
    printf 'PROMETHEUS DEPLOYMENT FAILED: %s\n' "$1" >&2
    exit 1
}

main() {
    [[ -f "${CA_FILE}" ]] || fail "CA file not found: ${CA_FILE}"
    [[ -d "${PROMETHEUS_REPO}" ]] || fail "Prometheus repository not found: ${PROMETHEUS_REPO}"

    echo "1. Initializing Prometheus Volumes..."
    "${SCRIPT_DIR}/initialize-prometheus-volumes.sh" "${CA_FILE}"

    if container_exists "${CONTAINER_NAME}"; then
        echo "2. Stopping and renaming existing Prometheus container..."
        "${CONTAINER_ENGINE}" stop "${CONTAINER_NAME}" || true
        "${CONTAINER_ENGINE}" rm -f "${ROLLBACK_NAME}" 2>/dev/null || true
        "${CONTAINER_ENGINE}" rename "${CONTAINER_NAME}" "${ROLLBACK_NAME}"
    else
        echo "2. No existing Prometheus container found."
    fi


    echo "3. Starting new Prometheus container..."
    "${PROMETHEUS_REPO}/scripts/run.sh" "${CONFIG_VOLUME}" "${TRUSTSTORE_VOLUME}" "${DATA_VOLUME}" "${CONTAINER_NAME}" "${PROMETHEUS_PORT}" >/dev/null

    echo "4. Verifying readiness..."
    local attempts=15
    for ((i = 1; i <= attempts; i++)); do
        if curl --fail --silent --show-error "http://127.0.0.1:${PROMETHEUS_PORT}/-/ready" >/dev/null 2>&1 \
            || curl --fail --silent --show-error "http://${CONTAINER_NAME}:${PROMETHEUS_PORT}/-/ready" >/dev/null 2>&1; then
            echo "Prometheus is ready."
            exit 0
        fi
        sleep 1
    done

    fail "Prometheus did not become ready within expected time."
}

main "$@"
