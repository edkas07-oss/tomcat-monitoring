#!/usr/bin/env bash
# Deploy script for Alertmanager persistent runtime.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi
# shellcheck source=scripts/container-runtime-helper.sh
source "${SCRIPT_DIR}/container-runtime-helper.sh"

readonly CONTAINER_NAME="${ALERTMANAGER_CONTAINER:-alertmanager}"
readonly ROLLBACK_NAME="alertmanager-rollback-tn015"
if [[ -z "${ALERTMANAGER_REPO:-}" ]]; then
    if [[ -d "$(dirname "${PROJECT_ROOT}")/alertmanager" ]]; then
        ALERTMANAGER_REPO="$(dirname "${PROJECT_ROOT}")/alertmanager"
    elif [[ -d "${HOME}/git/alertmanager" ]]; then
        ALERTMANAGER_REPO="${HOME}/git/alertmanager"
    else
        ALERTMANAGER_REPO="$(dirname "${PROJECT_ROOT}")/alertmanager"
    fi
fi
readonly ALERTMANAGER_REPO
readonly CONFIG_VOLUME="${ALERTMANAGER_CONFIG_VOLUME:-alertmanager_config}"
readonly SECRETS_VOLUME="${ALERTMANAGER_TRUSTSTORE_VOLUME:-alertmanager_truststore}"
readonly DATA_VOLUME="${ALERTMANAGER_DATA_VOLUME:-alertmanager_data}"
readonly ALERTMANAGER_IMAGE="${ALERTMANAGER_IMAGE:-localhost/alertmanager:1.0.0}"
readonly ALERTMANAGER_PORT="${ALERTMANAGER_PORT:-9093}"
readonly INITIALIZER="alertmanager-secrets-init"

fail() {
    printf 'ALERTMANAGER DEPLOYMENT FAILED: %s\n' "$1" >&2
    exit 1
}

cleanup_initializer() {
    if container_exists "${INITIALIZER}"; then
        "${CONTAINER_ENGINE}" rm "${INITIALIZER}" >/dev/null
    fi
}

main() {
    [[ -d "${ALERTMANAGER_REPO}" ]] || fail "Alertmanager repository tidak ditemukan: ${ALERTMANAGER_REPO}"

    echo "1. Initializing Alertmanager Volumes..."
    "${SCRIPT_DIR}/initialize-alertmanager-volumes.sh"

    echo "1b. Initializing Alertmanager Secrets..."
    trap cleanup_initializer EXIT
    volume_exists "${SECRETS_VOLUME}" || "${CONTAINER_ENGINE}" volume create "${SECRETS_VOLUME}" >/dev/null
    "${CONTAINER_ENGINE}" create --name "${INITIALIZER}" --user 0 --entrypoint /bin/sh --volume "${SECRETS_VOLUME}:/staging/secrets" "${ALERTMANAGER_IMAGE}" -c 'chmod 0755 /staging/secrets; chmod 0444 /staging/secrets/*' >/dev/null
    
    # We will use dummy secrets for lab environment if real ones don't exist
    local secret_dir="/tmp/alertmanager-secrets-stage"
    rm -rf "${secret_dir}" && mkdir -p "${secret_dir}"
    echo "https://${DIAGNOSTIC_CONTAINER:-diagnostic-service}:${DIAGNOSTIC_PORT:-8443}/api/v1/alerts/alertmanager" > "${secret_dir}/diagnostic-service-webhook-url"
    echo "test-token-12345" > "${secret_dir}/diagnostic-service-bearer-token"
    local tls_ca_source="${DEFAULT_TLS_DIR:-${HOME}/.local/share/tomcat-monitoring/diagnostic-service-tls}/server.crt"
    if [[ -f "/tmp/diagnostic-service-ca.crt" ]]; then
        cp "/tmp/diagnostic-service-ca.crt" "${secret_dir}/diagnostic-service-ca.crt"
    elif [[ -f "${tls_ca_source}" ]]; then
        cp "${tls_ca_source}" "${secret_dir}/diagnostic-service-ca.crt"
    else
        openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
            -subj '/CN=diagnostic-service' \
            -addext 'subjectAltName=DNS:diagnostic-service' \
            -keyout /dev/null \
            -out "${secret_dir}/diagnostic-service-ca.crt" >/dev/null 2>&1
    fi

    "${CONTAINER_ENGINE}" cp "${secret_dir}/diagnostic-service-webhook-url" "${INITIALIZER}:/staging/secrets/diagnostic-service-webhook-url"
    "${CONTAINER_ENGINE}" cp "${secret_dir}/diagnostic-service-bearer-token" "${INITIALIZER}:/staging/secrets/diagnostic-service-bearer-token"
    "${CONTAINER_ENGINE}" cp "${secret_dir}/diagnostic-service-ca.crt" "${INITIALIZER}:/staging/secrets/diagnostic-service-ca.crt"
    "${CONTAINER_ENGINE}" start --attach "${INITIALIZER}" >/dev/null

    if container_exists "${CONTAINER_NAME}"; then
        echo "2. Stopping and renaming existing Alertmanager container..."
        "${CONTAINER_ENGINE}" stop "${CONTAINER_NAME}" || true
        "${CONTAINER_ENGINE}" rm -f "${ROLLBACK_NAME}" 2>/dev/null || true
        "${CONTAINER_ENGINE}" rename "${CONTAINER_NAME}" "${ROLLBACK_NAME}"
    else
        echo "2. No existing Alertmanager container found."
    fi


    echo "3. Starting new Alertmanager container..."
    "${ALERTMANAGER_REPO}/scripts/run.sh" "${CONFIG_VOLUME}" "${SECRETS_VOLUME}" "${DATA_VOLUME}" "${CONTAINER_NAME}" "${ALERTMANAGER_PORT}" >/dev/null

    echo "4. Verifying readiness..."
    local attempts=15
    for ((i = 1; i <= attempts; i++)); do
        if curl --fail --silent --show-error "http://127.0.0.1:${ALERTMANAGER_PORT}/-/ready" >/dev/null 2>&1 \
            || curl --fail --silent --show-error "http://${CONTAINER_NAME}:${ALERTMANAGER_PORT}/-/ready" >/dev/null 2>&1; then
            echo "Alertmanager is ready."
            exit 0
        fi
        sleep 1
    done

    fail "Alertmanager did not become ready within expected time."
}

main "$@"
