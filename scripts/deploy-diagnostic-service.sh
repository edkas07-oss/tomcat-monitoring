#!/usr/bin/env bash
# Deploy script for Diagnostic Service persistent runtime.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi

readonly CONTAINER_NAME="${DIAGNOSTIC_CONTAINER:-diagnostic-service}"
readonly ROLLBACK_NAME="${ROLLBACK_NAME:-${CONTAINER_NAME}-rollback-snapshot}"
readonly NETWORK_NAME="${NETWORK_NAME:-devops-lab}"
readonly DIAGNOSTIC_REPO="${DIAGNOSTIC_REPO:-$(dirname "${PROJECT_ROOT}")/tomcat-diagnostic-service}"
if [[ -f "${DIAGNOSTIC_REPO}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${DIAGNOSTIC_REPO}/CONFIG"
fi
readonly DIAGNOSTIC_IMAGE="${DIAGNOSTIC_IMAGE:-localhost/tomcat-diagnostic-service@sha256:4519277d6a36d8ce0ce9cf01434ee0f0302e1ba4a63e3b0abe883e4497b5ab2e}"
readonly DATA_VOLUME="${DATA_VOLUME:-${DIAGNOSTIC_DATA_VOLUME:-diagnostic_data}}"
readonly LOG_VOLUME="${LOG_VOLUME:-${TOMCAT_LOG_VOLUME:-tomcat_logs}}"
readonly SPOOL_DIR="${SPOOL_DIR:-${DEFAULT_SPOOL_DIR:-${HOME}/.local/share/tomcat-monitoring/spool}}"
readonly CONFIG_FILE="${PROJECT_ROOT}/config/diagnostic-service/application.json"
readonly TARGETS_FILE="${PROJECT_ROOT}/config/diagnostic-service/targets.json"
readonly SECRETS_DIR="${SECRETS_DIR:-${DEFAULT_SECRETS_DIR:-${HOME}/.local/share/tomcat-monitoring/diagnostic-service-secrets}}"
readonly TLS_DIR="${TLS_DIR:-${DEFAULT_TLS_DIR:-${HOME}/.local/share/tomcat-monitoring/diagnostic-service-tls}}"
readonly DIAGNOSTIC_PORT="${DIAGNOSTIC_PORT:-8443}"

fail() {
    printf 'DIAGNOSTIC SERVICE DEPLOYMENT FAILED: %s\n' "$1" >&2
    exit 1
}

rollback_on_failure() {
    echo "PERINGATAN: Deployment Diagnostic Service gagal! Mengeksekusi automated rollback..." >&2
    if podman container exists "${CONTAINER_NAME}"; then
        podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi
    if podman container exists "${ROLLBACK_NAME}"; then
        echo "Memulihkan kontainer snapshot cadangan: ${ROLLBACK_NAME} -> ${CONTAINER_NAME}..." >&2
        podman rename "${ROLLBACK_NAME}" "${CONTAINER_NAME}" >/dev/null 2>&1 || true
        podman start "${CONTAINER_NAME}" >/dev/null 2>&1 || true
        echo "Automated rollback selesai. Kontainer versi sebelumnya telah dipulihkan dan aktif." >&2
    fi
}

main() {
    podman image exists "${DIAGNOSTIC_IMAGE}" || fail "Diagnostic Service image tidak ditemukan: ${DIAGNOSTIC_IMAGE}"
    podman volume exists "${DATA_VOLUME}" || podman volume create "${DATA_VOLUME}" >/dev/null
    podman volume exists "${LOG_VOLUME}" || podman volume create "${LOG_VOLUME}" >/dev/null
    [[ -f "${CONFIG_FILE}" ]] || fail "Config file tidak ditemukan: ${CONFIG_FILE}"
    [[ -f "${TARGETS_FILE}" ]] || fail "Targets file tidak ditemukan: ${TARGETS_FILE}"

    # Initialize persistent spool, secrets, and TLS directories with 0700
    mkdir -p "${SPOOL_DIR}" "${SECRETS_DIR}" "${TLS_DIR}"
    chmod 0700 "${SPOOL_DIR}" "${SECRETS_DIR}" "${TLS_DIR}"

    # Initialize secrets if they do not exist
    if [[ ! -f "${SECRETS_DIR}/bearer-token" ]]; then
        echo "test-token-12345" > "${SECRETS_DIR}/bearer-token"
    fi
    if [[ ! -f "${SECRETS_DIR}/smtp-username" ]]; then
        echo "diagnostic-service" > "${SECRETS_DIR}/smtp-username"
    fi
    if [[ ! -f "${SECRETS_DIR}/smtp-password" ]]; then
        echo "SecretPassword123!" > "${SECRETS_DIR}/smtp-password"
    fi
    chmod 0400 "${SECRETS_DIR}/bearer-token" "${SECRETS_DIR}/smtp-username" "${SECRETS_DIR}/smtp-password"

    # Initialize TLS certificates
    if [[ ! -f "${TLS_DIR}/server.crt" || ! -f "${TLS_DIR}/server.key" ]]; then
        openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
            -subj '/CN=diagnostic-service' \
            -addext 'subjectAltName=DNS:diagnostic-service' \
            -keyout "${TLS_DIR}/server.key" \
            -out "${TLS_DIR}/server.crt" >/dev/null 2>&1
    fi
    chmod 0400 "${TLS_DIR}/server.key"
    chmod 0444 "${TLS_DIR}/server.crt"

    # Copy Postfix TLS CA for verification
    podman cp postfix-relay:/etc/postfix/tls/server.crt "${TLS_DIR}/postfix-ca.crt" 2>/dev/null || true
    chmod 0444 "${TLS_DIR}/postfix-ca.crt" 2>/dev/null || true

    trap rollback_on_failure ERR

    if podman container exists "${CONTAINER_NAME}"; then
        echo "1. Stopping and renaming existing Diagnostic Service container..."
        podman stop "${CONTAINER_NAME}" || true
        podman rm -f "${ROLLBACK_NAME}" 2>/dev/null || true
        podman rename "${CONTAINER_NAME}" "${ROLLBACK_NAME}"
    else
        echo "1. No existing Diagnostic Service container found."
    fi

    echo "2. Starting new Diagnostic Service container..."
    podman run --detach --pull=never \
        --userns=keep-id \
        --name "${CONTAINER_NAME}" \
        --network "${NETWORK_NAME}" \
        --network-alias "${CONTAINER_NAME}" \
        --publish "${DIAGNOSTIC_PORT}:${DIAGNOSTIC_PORT}" \
        --restart=on-failure:5 \
        --env "NODE_EXTRA_CA_CERTS=/run/tomcat-diagnostic/tls/postfix-ca.crt" \
        --volume "${CONFIG_FILE}:/run/tomcat-diagnostic/application.json:ro,z" \
        --volume "${TARGETS_FILE}:/run/tomcat-diagnostic/config/targets.json:ro,z" \
        --volume "${SECRETS_DIR}/bearer-token:/run/tomcat-diagnostic/secrets/bearer-token:ro,z" \
        --volume "${SECRETS_DIR}/smtp-username:/run/tomcat-diagnostic/secrets/smtp-username:ro,z" \
        --volume "${SECRETS_DIR}/smtp-password:/run/tomcat-diagnostic/secrets/smtp-password:ro,z" \
        --volume "${TLS_DIR}/server.crt:/run/tomcat-diagnostic/tls/server.crt:ro,z" \
        --volume "${TLS_DIR}/server.key:/run/tomcat-diagnostic/tls/server.key:ro,z" \
        --volume "${TLS_DIR}/postfix-ca.crt:/run/tomcat-diagnostic/tls/postfix-ca.crt:ro,z" \
        --volume "${SPOOL_DIR}:/run/tomcat-diagnostic/spool:ro,z" \
        --volume "${LOG_VOLUME}:/run/tomcat-diagnostic/logs:ro,z" \
        --volume "${DATA_VOLUME}:/var/lib/tomcat-diagnostic:z" \
        "${DIAGNOSTIC_IMAGE}" >/dev/null

    echo "3. Verifying readiness..."
    sleep 6
    if [[ "$(podman inspect --format '{{.State.Status}}' "${CONTAINER_NAME}")" == "running" ]]; then
        echo "Diagnostic Service is running."
        trap - ERR
        if podman container exists "${ROLLBACK_NAME}"; then
            podman rm -f "${ROLLBACK_NAME}" >/dev/null 2>&1 || true
        fi
    else
        rollback_on_failure
        fail "Diagnostic Service failed to start or exited."
    fi
}

main "$@"
