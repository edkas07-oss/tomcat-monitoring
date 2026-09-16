#!/usr/bin/env bash
#
# Purpose: Create and populate Prometheus named volumes without host bind mounts.
# Usage: ./scripts/initialize-prometheus-volumes.sh <jmx-exporter-ca-file>
#
# Contract: Configuration and CA certificates are copied using `podman cp`; data
# volume is preserved. Only the initializer container is removed after initialization.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi
# shellcheck source=scripts/container-runtime-helper.sh
source "${SCRIPT_DIR}/container-runtime-helper.sh"

readonly CONFIG_FILE="${PROJECT_ROOT}/config/prometheus/prometheus.yml"
readonly RULES_DIR="${PROJECT_ROOT}/config/prometheus/rules"
readonly CA_FILE="${1:?Usage: ./scripts/initialize-prometheus-volumes.sh <jmx-exporter-ca-file> [diagnostic-service-ca-file]}"
readonly DIAG_CA_FILE="${2:-}"
readonly IMAGE="${PROMETHEUS_IMAGE:-localhost/prometheus:1.0.0}"
readonly INITIALIZER="prometheus-volume-init"
readonly CONFIG_VOLUME="${PROMETHEUS_CONFIG_VOLUME:-prometheus_config}"
readonly TRUSTSTORE_VOLUME="${PROMETHEUS_TRUSTSTORE_VOLUME:-prometheus_truststore}"
readonly DATA_VOLUME="${PROMETHEUS_DATA_VOLUME:-prometheus_data}"

cleanup_initializer() {
    if container_exists "${INITIALIZER}"; then
        "${CONTAINER_ENGINE}" rm "${INITIALIZER}" >/dev/null
    fi
}

fail() {
    printf 'PROMETHEUS VOLUME INITIALIZATION FAILED: %s\n' "$1" >&2
    exit 1
}

main() {
    local volume_name

    [[ -f "${CONFIG_FILE}" && -r "${CONFIG_FILE}" ]] \
        || fail "Configuration file is not readable: ${CONFIG_FILE}"
    [[ -f "${CA_FILE}" && -r "${CA_FILE}" ]] \
        || fail "CA file is not readable: ${CA_FILE}"
    image_exists "${IMAGE}" || fail "Local image is not available: ${IMAGE}"
    ! container_exists "${INITIALIZER}" \
        || fail "Initializer container already exists: ${INITIALIZER}"

    trap cleanup_initializer EXIT

    for volume_name in \
        "${CONFIG_VOLUME}" "${TRUSTSTORE_VOLUME}" "${DATA_VOLUME}"; do
        volume_exists "${volume_name}" || "${CONTAINER_ENGINE}" volume create "${volume_name}" >/dev/null
    done

    "${CONTAINER_ENGINE}" create \
        --name "${INITIALIZER}" \
        --user 0 \
        --entrypoint /bin/sh \
        --volume "${CONFIG_VOLUME}:/staging/config" \
        --volume "${TRUSTSTORE_VOLUME}:/staging/truststore" \
        --volume "${DATA_VOLUME}:/staging/data" \
        "${IMAGE}" \
        -c 'chmod 0755 /staging/config /staging/config/rules /staging/truststore; chmod 0444 /staging/config/prometheus.yml /staging/config/rules/application-health.yml /staging/truststore/*; chown 65534:65534 /staging/data; chmod 0770 /staging/data' \
        >/dev/null

    "${CONTAINER_ENGINE}" cp "${CONFIG_FILE}" \
        "${INITIALIZER}:/staging/config/prometheus.yml"
    "${CONTAINER_ENGINE}" cp "${RULES_DIR}" \
        "${INITIALIZER}:/staging/config/"
    "${CONTAINER_ENGINE}" cp "${CA_FILE}" \
        "${INITIALIZER}:/staging/truststore/jmx-exporter-ca.crt"
    if [[ -n "${DIAG_CA_FILE}" && -f "${DIAG_CA_FILE}" ]]; then
        "${CONTAINER_ENGINE}" cp "${DIAG_CA_FILE}" \
            "${INITIALIZER}:/staging/truststore/diagnostic-service-ca.crt"
    elif [[ -f "/tmp/diagnostic-service-ca.crt" ]]; then
        "${CONTAINER_ENGINE}" cp "/tmp/diagnostic-service-ca.crt" \
            "${INITIALIZER}:/staging/truststore/diagnostic-service-ca.crt"
    fi
    "${CONTAINER_ENGINE}" start --attach "${INITIALIZER}" >/dev/null

    printf 'Prometheus volumes initialized: %s, %s, %s.\n' \
        "${CONFIG_VOLUME}" "${TRUSTSTORE_VOLUME}" "${DATA_VOLUME}"
}


main "$@"
