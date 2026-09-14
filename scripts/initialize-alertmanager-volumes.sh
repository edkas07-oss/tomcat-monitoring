#!/usr/bin/env bash
#
# Tujuan: membuat dan mengisi named volumes Alertmanager tanpa host bind.
# Penggunaan: ./scripts/initialize-alertmanager-volumes.sh
#
# Contract: configuration disalin dengan `podman cp`; data volume
# dipertahankan. Hanya initializer container yang dihapus setelah initialization.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi
# shellcheck source=scripts/container-runtime-helper.sh
source "${SCRIPT_DIR}/container-runtime-helper.sh"

readonly CONFIG_FILE="${PROJECT_ROOT}/config/alertmanager/alertmanager.yml"
readonly IMAGE="${ALERTMANAGER_IMAGE:-localhost/alertmanager:1.0.0}"
readonly INITIALIZER="alertmanager-volume-init"
readonly CONFIG_VOLUME="${ALERTMANAGER_CONFIG_VOLUME:-alertmanager_config}"
readonly TRUSTSTORE_VOLUME="${ALERTMANAGER_TRUSTSTORE_VOLUME:-alertmanager_truststore}"
readonly DATA_VOLUME="${ALERTMANAGER_DATA_VOLUME:-alertmanager_data}"

cleanup_initializer() {
    if container_exists "${INITIALIZER}"; then
        "${CONTAINER_ENGINE}" rm "${INITIALIZER}" >/dev/null
    fi
}

fail() {
    printf 'ALERTMANAGER VOLUME INITIALIZATION FAILED: %s\n' "$1" >&2
    exit 1
}

main() {
    local volume_name

    [[ -f "${CONFIG_FILE}" && -r "${CONFIG_FILE}" ]] \
        || fail "Configuration tidak dapat dibaca: ${CONFIG_FILE}"
    image_exists "${IMAGE}" || fail "Image lokal tidak tersedia: ${IMAGE}"
    ! container_exists "${INITIALIZER}" \
        || fail "Initializer container sudah tersedia: ${INITIALIZER}"

    trap cleanup_initializer EXIT

    for volume_name in "${CONFIG_VOLUME}" "${TRUSTSTORE_VOLUME}" "${DATA_VOLUME}"; do
        volume_exists "${volume_name}" \
            || "${CONTAINER_ENGINE}" volume create "${volume_name}" >/dev/null
    done

    "${CONTAINER_ENGINE}" create \
        --name "${INITIALIZER}" \
        --user 0 \
        --entrypoint /bin/sh \
        --volume "${CONFIG_VOLUME}:/staging/config" \
        --volume "${TRUSTSTORE_VOLUME}:/staging/truststore" \
        --volume "${DATA_VOLUME}:/staging/data" \
        "${IMAGE}" \
        -c 'chmod 0755 /staging/config /staging/truststore; chmod 0444 /staging/config/alertmanager.yml /staging/truststore/*; chown 65534:65534 /staging/data; chmod 0770 /staging/data' \
        >/dev/null

    local secret_dir="/tmp/alertmanager-secrets-init-$$"
    rm -rf "${secret_dir}" && mkdir -p "${secret_dir}"
    echo "https://${DIAGNOSTIC_CONTAINER:-diagnostic-service}:${DIAGNOSTIC_PORT:-8443}/api/v1/alerts/alertmanager" > "${secret_dir}/diagnostic-service-webhook-url"

    local bearer_token_src="${DEFAULT_SECRETS_DIR:-${HOME}/.local/share/tomcat-monitoring/diagnostic-service-secrets}/bearer-token"
    if [[ -f "${bearer_token_src}" ]]; then
        cp "${bearer_token_src}" "${secret_dir}/diagnostic-service-bearer-token"
    else
        echo "test-token-12345" > "${secret_dir}/diagnostic-service-bearer-token"
    fi

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

    "${CONTAINER_ENGINE}" cp "${CONFIG_FILE}" \
        "${INITIALIZER}:/staging/config/alertmanager.yml"
    "${CONTAINER_ENGINE}" cp "${secret_dir}/diagnostic-service-webhook-url" \
        "${INITIALIZER}:/staging/truststore/diagnostic-service-webhook-url"
    "${CONTAINER_ENGINE}" cp "${secret_dir}/diagnostic-service-bearer-token" \
        "${INITIALIZER}:/staging/truststore/diagnostic-service-bearer-token"
    "${CONTAINER_ENGINE}" cp "${secret_dir}/diagnostic-service-ca.crt" \
        "${INITIALIZER}:/staging/truststore/diagnostic-service-ca.crt"
    rm -rf "${secret_dir}"

    "${CONTAINER_ENGINE}" start --attach "${INITIALIZER}" >/dev/null

    printf 'Alertmanager volumes initialized: %s, %s, %s.\n' \
        "${CONFIG_VOLUME}" "${TRUSTSTORE_VOLUME}" "${DATA_VOLUME}"
}

main "$@"
