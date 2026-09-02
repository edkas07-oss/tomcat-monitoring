#!/usr/bin/env bash
# Deploy script for Alertmanager persistent runtime.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly CONTAINER_NAME="alertmanager"
readonly ROLLBACK_NAME="alertmanager-rollback-tn015"
readonly ALERTMANAGER_REPO="${HOME}/git/alertmanager"
readonly SECRETS_VOLUME="alertmanager_truststore"
readonly INITIALIZER="alertmanager-secrets-init"

fail() {
    printf 'ALERTMANAGER DEPLOYMENT FAILED: %s\n' "$1" >&2
    exit 1
}

cleanup_initializer() {
    if podman container exists "${INITIALIZER}"; then
        podman rm "${INITIALIZER}" >/dev/null
    fi
}

main() {
    [[ -d "${ALERTMANAGER_REPO}" ]] || fail "Alertmanager repository tidak ditemukan: ${ALERTMANAGER_REPO}"

    echo "1. Initializing Alertmanager Volumes..."
    "${SCRIPT_DIR}/initialize-alertmanager-volumes.sh"

    echo "1b. Initializing Alertmanager Secrets..."
    trap cleanup_initializer EXIT
    podman volume exists "${SECRETS_VOLUME}" || podman volume create "${SECRETS_VOLUME}" >/dev/null
    podman create --name "${INITIALIZER}" --user 0 --entrypoint /bin/sh --volume "${SECRETS_VOLUME}:/staging/secrets" localhost/alertmanager:1.0.0 -c 'chmod 0755 /staging/secrets; chmod 0444 /staging/secrets/*' >/dev/null
    
    # We will use dummy secrets for lab environment if real ones don't exist
    local secret_dir="/tmp/alertmanager-secrets-stage"
    rm -rf "${secret_dir}" && mkdir -p "${secret_dir}"
    echo "https://diagnostic-service:8443/api/v1/alerts/alertmanager" > "${secret_dir}/diagnostic-service-webhook-url"
    echo "test-token-12345" > "${secret_dir}/diagnostic-service-bearer-token"
    if [[ -f "/tmp/diagnostic-service-ca.crt" ]]; then
        cp "/tmp/diagnostic-service-ca.crt" "${secret_dir}/diagnostic-service-ca.crt"
    else
        echo "dummy-ca" > "${secret_dir}/diagnostic-service-ca.crt"
    fi

    podman cp "${secret_dir}/diagnostic-service-webhook-url" "${INITIALIZER}:/staging/secrets/diagnostic-service-webhook-url"
    podman cp "${secret_dir}/diagnostic-service-bearer-token" "${INITIALIZER}:/staging/secrets/diagnostic-service-bearer-token"
    podman cp "${secret_dir}/diagnostic-service-ca.crt" "${INITIALIZER}:/staging/secrets/diagnostic-service-ca.crt"
    podman start --attach "${INITIALIZER}" >/dev/null

    if podman container exists "${CONTAINER_NAME}"; then
        echo "2. Stopping and renaming existing Alertmanager container..."
        podman stop "${CONTAINER_NAME}" || true
        podman rm -f "${ROLLBACK_NAME}" 2>/dev/null || true
        podman rename "${CONTAINER_NAME}" "${ROLLBACK_NAME}"
    else
        echo "2. No existing Alertmanager container found."
    fi

    echo "3. Starting new Alertmanager container..."
    "${ALERTMANAGER_REPO}/scripts/run.sh" alertmanager_config alertmanager_truststore alertmanager_data "${CONTAINER_NAME}" 9093 >/dev/null

    echo "4. Verifying readiness..."
    local attempts=15
    for ((i = 1; i <= attempts; i++)); do
        if curl --fail --silent --show-error http://127.0.0.1:9093/-/ready >/dev/null 2>&1; then
            echo "Alertmanager is ready."
            exit 0
        fi
        sleep 1
    done

    fail "Alertmanager did not become ready within expected time."
}

main "$@"
