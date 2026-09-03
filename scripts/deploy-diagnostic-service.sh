#!/usr/bin/env bash
# Deploy script for Diagnostic Service persistent runtime.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly CONTAINER_NAME="diagnostic-service"
readonly ROLLBACK_NAME="diagnostic-service-rollback-tn018"
readonly NETWORK_NAME="devops-lab"
readonly DIAGNOSTIC_IMAGE="localhost/tomcat-diagnostic-service@sha256:e781b9fb1cdad484763ab17ec5c0c0004da3fd4775ba5d88eba651382099aae8"
readonly DATA_VOLUME="diagnostic_data"

fail() {
    printf 'DIAGNOSTIC SERVICE DEPLOYMENT FAILED: %s\n' "$1" >&2
    exit 1
}

main() {
    podman image exists "${DIAGNOSTIC_IMAGE}" || fail "Diagnostic Service image tidak ditemukan: ${DIAGNOSTIC_IMAGE}"
    podman volume exists "${DATA_VOLUME}" || podman volume create "${DATA_VOLUME}" >/dev/null

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
  "queue": {"capacity": 50, "pollIntervalMs": 250},
  "timeouts": {"diagnosticMs": 60000, "smtpMs": 10000, "shutdownMs": 10000},
  "requestLimitBytes": 262144
}' > "${config_dir}/config/application.json"
    mkdir -p /tmp/diagnostic-spool
    echo '[{"identity":{"environment":"lab","host":"tomcat-01","tomcat_instance":"default"},"collectorSpool":"/run/tomcat-diagnostic/spool"},{"identity":{"environment":"lab","host":"edkas-pc1","tomcat_instance":"tomcat-jmx-exporter"},"collectorSpool":"/run/tomcat-diagnostic/spool"}]' > "${config_dir}/config/targets.json"
    echo "test-token-12345" > "${config_dir}/secrets/bearer-token"
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
        -subj '/CN=diagnostic-service' \
        -addext 'subjectAltName=DNS:diagnostic-service' \
        -keyout "${config_dir}/tls/server.key" \
        -out "${config_dir}/tls/server.crt" >/dev/null 2>&1
    cp "${config_dir}/tls/server.crt" /tmp/diagnostic-service-ca.crt

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
        --restart=no \
        --volume "${config_dir}/config/application.json:/run/tomcat-diagnostic/application.json:ro,z" \
        --volume "${config_dir}/config/targets.json:/run/tomcat-diagnostic/config/targets.json:ro,z" \
        --volume "${config_dir}/secrets/bearer-token:/run/tomcat-diagnostic/secrets/bearer-token:ro,z" \
        --volume "${config_dir}/tls/server.crt:/run/tomcat-diagnostic/tls/server.crt:ro,z" \
        --volume "${config_dir}/tls/server.key:/run/tomcat-diagnostic/tls/server.key:ro,z" \
        --volume "/tmp/diagnostic-spool:/run/tomcat-diagnostic/spool:ro,z" \
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
