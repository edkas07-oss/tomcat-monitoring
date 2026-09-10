#!/usr/bin/env bash
# Deploy script for Diagnostic Service persistent runtime.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly CONTAINER_NAME="diagnostic-service"
readonly ROLLBACK_NAME="diagnostic-service-rollback-v016"
readonly NETWORK_NAME="devops-lab"
readonly DIAGNOSTIC_IMAGE="localhost/tomcat-diagnostic-service@sha256:ae212a72419e7c10f6b7d4e1af06a576546143d2f20e335629a21ddc16fcbb25"
readonly DIAGNOSTIC_REPO="${HOME}/git/tomcat-diagnostic-service"
if [[ -f "${DIAGNOSTIC_REPO}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${DIAGNOSTIC_REPO}/CONFIG"
fi
readonly DATA_VOLUME="${DATA_VOLUME:-diagnostic_data}"
readonly LOG_VOLUME="${LOG_VOLUME:-tomcat_logs}"
readonly SPOOL_DIR="${SPOOL_DIR:-${HOME}/.local/share/tomcat-monitoring/spool}"

fail() {
    printf 'DIAGNOSTIC SERVICE DEPLOYMENT FAILED: %s\n' "$1" >&2
    exit 1
}

main() {
    podman image exists "${DIAGNOSTIC_IMAGE}" || fail "Diagnostic Service image tidak ditemukan: ${DIAGNOSTIC_IMAGE}"
    podman volume exists "${DATA_VOLUME}" || podman volume create "${DATA_VOLUME}" >/dev/null
    podman volume exists "${LOG_VOLUME}" || podman volume create "${LOG_VOLUME}" >/dev/null

    # Create dummy config and secrets if they do not exist
    local config_dir="/tmp/diagnostic-service-config"
    rm -rf "${config_dir}" && mkdir -p "${config_dir}"/{config,secrets,tls}
    echo '{
  "schemaVersion": 1,
  "listen": {"host": "0.0.0.0", "port": 8443},
  "databasePath": "/var/lib/tomcat-diagnostic/diagnostic.db",
  "tls": {
    "certificateFile": "/run/tomcat-diagnostic/tls/server.crt",
    "privateKeyFile": "/run/tomcat-diagnostic/tls/server.key"
  },
  "bearerTokenFile": "/run/tomcat-diagnostic/secrets/bearer-token",
  "targetAllowlistFile": "/run/tomcat-diagnostic/config/targets.json",
  "smtp": {
    "host": "mailpit",
    "port": 1025,
    "secure": false,
    "from": "diagnostic@tomcat-monitoring.invalid",
    "to": "operator@tomcat-monitoring.invalid"
  },
  "prometheus": {
    "baseUrl": "http://prometheus:9090"
  },
  "queue": {"capacity": 50, "pollIntervalMs": 250},
  "timeouts": {"diagnosticMs": 60000, "smtpMs": 10000, "shutdownMs": 10000, "prometheusMs": 5000},
  "requestLimitBytes": 262144
}' > "${config_dir}/config/application.json"
    mkdir -p "${SPOOL_DIR}"
    chmod 0700 "${SPOOL_DIR}"
    echo '[{"identity":{"environment":"lab","host":"tomcat-01","tomcat_instance":"default"},"collectorSpool":"/run/tomcat-diagnostic/spool","logDirectory":"/run/tomcat-diagnostic/logs","prometheusSelector":"job=\"tomcat-jmx-exporter\",instance=\"tomcat-jmx-exporter:9404\""},{"identity":{"environment":"lab","host":"edkas-pc1","tomcat_instance":"tomcat-jmx-exporter"},"collectorSpool":"/run/tomcat-diagnostic/spool","logDirectory":"/run/tomcat-diagnostic/logs","prometheusSelector":"job=\"tomcat-jmx-exporter\",instance=\"tomcat-jmx-exporter:9404\""}]' > "${config_dir}/config/targets.json"
    echo "test-token-12345" > "${config_dir}/secrets/bearer-token"
    local tls_persist_dir="${HOME}/.local/share/tomcat-monitoring/diagnostic-service-tls"
    mkdir -p "${tls_persist_dir}"
    if [[ ! -f "${tls_persist_dir}/server.crt" || ! -f "${tls_persist_dir}/server.key" ]]; then
        openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
            -subj '/CN=diagnostic-service' \
            -addext 'subjectAltName=DNS:diagnostic-service' \
            -keyout "${tls_persist_dir}/server.key" \
            -out "${tls_persist_dir}/server.crt" >/dev/null 2>&1
        chmod 0400 "${tls_persist_dir}/server.key"
        chmod 0444 "${tls_persist_dir}/server.crt"
    fi
    cp "${tls_persist_dir}/server.crt" "${config_dir}/tls/server.crt"
    cp "${tls_persist_dir}/server.key" "${config_dir}/tls/server.key"
    cp "${tls_persist_dir}/server.crt" /tmp/diagnostic-service-ca.crt

    chmod 0444 "${config_dir}/config/application.json" \
               "${config_dir}/config/targets.json" \
               "${config_dir}/secrets/bearer-token" \
               "${config_dir}/tls/server.crt"
    chmod 0400 "${config_dir}/tls/server.key"

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
        --network-alias diagnostic-service \
        --publish 8443:8443 \
        --restart=on-failure:5 \
        --volume "${config_dir}/config/application.json:/run/tomcat-diagnostic/application.json:ro,z" \
        --volume "${config_dir}/config/targets.json:/run/tomcat-diagnostic/config/targets.json:ro,z" \
        --volume "${config_dir}/secrets/bearer-token:/run/tomcat-diagnostic/secrets/bearer-token:ro,z" \
        --volume "${config_dir}/tls/server.crt:/run/tomcat-diagnostic/tls/server.crt:ro,z" \
        --volume "${config_dir}/tls/server.key:/run/tomcat-diagnostic/tls/server.key:ro,z" \
        --volume "${SPOOL_DIR}:/run/tomcat-diagnostic/spool:ro,z" \
        --volume "${LOG_VOLUME}:/run/tomcat-diagnostic/logs:ro,z" \
        --volume "${DATA_VOLUME}:/var/lib/tomcat-diagnostic:z" \
        "${DIAGNOSTIC_IMAGE}" >/dev/null

    echo "3. Verifying readiness..."
    sleep 6
    if [[ "$(podman inspect --format '{{.State.Status}}' "${CONTAINER_NAME}")" == "running" ]]; then
        echo "Diagnostic Service is running."
    else
        fail "Diagnostic Service failed to start or exited."
    fi
}

main "$@"
