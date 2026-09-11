#!/usr/bin/env bash
#
# Tujuan: membuat dan mengisi named volumes Prometheus tanpa host bind.
# Penggunaan: ./scripts/initialize-prometheus-volumes.sh <jmx-exporter-ca-file>
#
# Contract: configuration dan CA disalin dengan `podman cp`; data volume
# dipertahankan. Hanya initializer container yang dihapus setelah initialization.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi

readonly CONFIG_FILE="${PROJECT_ROOT}/config/prometheus/prometheus.yml"
readonly RULES_DIR="${PROJECT_ROOT}/config/prometheus/rules"
readonly CA_FILE="${1:?Usage: ./scripts/initialize-prometheus-volumes.sh <jmx-exporter-ca-file>}"
readonly IMAGE="${PROMETHEUS_IMAGE:-localhost/prometheus:1.0.0}"
readonly INITIALIZER="prometheus-volume-init"
readonly CONFIG_VOLUME="${PROMETHEUS_CONFIG_VOLUME:-prometheus_config}"
readonly TRUSTSTORE_VOLUME="${PROMETHEUS_TRUSTSTORE_VOLUME:-prometheus_truststore}"
readonly DATA_VOLUME="${PROMETHEUS_DATA_VOLUME:-prometheus_data}"

cleanup_initializer() {
    if podman container exists "${INITIALIZER}"; then
        podman rm "${INITIALIZER}" >/dev/null
    fi
}

fail() {
    printf 'PROMETHEUS VOLUME INITIALIZATION FAILED: %s\n' "$1" >&2
    exit 1
}

main() {
    local volume_name

    [[ -f "${CONFIG_FILE}" && -r "${CONFIG_FILE}" ]] \
        || fail "Configuration tidak dapat dibaca: ${CONFIG_FILE}"
    [[ -f "${CA_FILE}" && -r "${CA_FILE}" ]] \
        || fail "CA file tidak dapat dibaca: ${CA_FILE}"
    podman image exists "${IMAGE}" || fail "Image lokal tidak tersedia: ${IMAGE}"
    ! podman container exists "${INITIALIZER}" \
        || fail "Initializer container sudah tersedia: ${INITIALIZER}"

    trap cleanup_initializer EXIT

    for volume_name in \
        "${CONFIG_VOLUME}" "${TRUSTSTORE_VOLUME}" "${DATA_VOLUME}"; do
        podman volume exists "${volume_name}" || podman volume create "${volume_name}" >/dev/null
    done

    podman create \
        --name "${INITIALIZER}" \
        --user 0 \
        --entrypoint /bin/sh \
        --volume "${CONFIG_VOLUME}:/staging/config" \
        --volume "${TRUSTSTORE_VOLUME}:/staging/truststore" \
        --volume "${DATA_VOLUME}:/staging/data" \
        "${IMAGE}" \
        -c 'chmod 0755 /staging/config /staging/config/rules /staging/truststore; chmod 0444 /staging/config/prometheus.yml /staging/config/rules/application-health.yml /staging/truststore/*; chown 65534:65534 /staging/data; chmod 0770 /staging/data' \
        >/dev/null

    podman cp "${CONFIG_FILE}" \
        "${INITIALIZER}:/staging/config/prometheus.yml"
    podman cp "${RULES_DIR}" \
        "${INITIALIZER}:/staging/config/"
    podman cp "${CA_FILE}" \
        "${INITIALIZER}:/staging/truststore/jmx-exporter-ca.crt"
    if [[ -f "/tmp/diagnostic-service-ca.crt" ]]; then
        podman cp "/tmp/diagnostic-service-ca.crt" \
            "${INITIALIZER}:/staging/truststore/diagnostic-service-ca.crt"
    fi
    podman start --attach "${INITIALIZER}" >/dev/null

    printf 'Prometheus volumes initialized: %s, %s, %s.\n' \
        "${CONFIG_VOLUME}" "${TRUSTSTORE_VOLUME}" "${DATA_VOLUME}"
}

main "$@"
