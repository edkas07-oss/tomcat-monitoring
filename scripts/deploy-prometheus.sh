#!/usr/bin/env bash
# Deploy script for Prometheus persistent runtime.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly CA_FILE="${HOME}/.local/share/tomcat-monitoring/jmx-exporter-tls/server.crt"
readonly CONTAINER_NAME="prometheus"
readonly ROLLBACK_NAME="prometheus-rollback-tn015"
readonly PROMETHEUS_REPO="${HOME}/git/prometheus"

fail() {
    printf 'PROMETHEUS DEPLOYMENT FAILED: %s\n' "$1" >&2
    exit 1
}

main() {
    [[ -f "${CA_FILE}" ]] || fail "CA file tidak ditemukan: ${CA_FILE}"
    [[ -d "${PROMETHEUS_REPO}" ]] || fail "Prometheus repository tidak ditemukan: ${PROMETHEUS_REPO}"

    echo "1. Initializing Prometheus Volumes..."
    "${SCRIPT_DIR}/initialize-prometheus-volumes.sh" "${CA_FILE}"

    if podman container exists "${CONTAINER_NAME}"; then
        echo "2. Stopping and renaming existing Prometheus container..."
        podman stop "${CONTAINER_NAME}" || true
        podman rm -f "${ROLLBACK_NAME}" 2>/dev/null || true
        podman rename "${CONTAINER_NAME}" "${ROLLBACK_NAME}"
    else
        echo "2. No existing Prometheus container found."
    fi

    echo "3. Starting new Prometheus container..."
    "${PROMETHEUS_REPO}/scripts/run.sh" prometheus_config prometheus_truststore prometheus_data "${CONTAINER_NAME}" 9090 >/dev/null

    echo "4. Verifying readiness..."
    local attempts=15
    for ((i = 1; i <= attempts; i++)); do
        if curl --fail --silent --show-error http://127.0.0.1:9090/-/ready >/dev/null 2>&1; then
            echo "Prometheus is ready."
            exit 0
        fi
        sleep 1
    done

    fail "Prometheus did not become ready within expected time."
}

main "$@"
