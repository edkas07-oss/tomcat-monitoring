#!/usr/bin/env bash
# ==============================================================================
# Container Entrypoint for Tomcat JMX Exporter
# Architecture Reference: TM-ADR-0026 & TN-019
# ==============================================================================
set -euo pipefail

readonly AGENT_JAR=/opt/jmx-exporter/jmx_prometheus_javaagent.jar
readonly CONFIG_FILE="${JMX_EXPORTER_CONFIG:-/etc/tomcat-jmx-exporter/config.yml}"
readonly KEYSTORE_FILE="${JMX_EXPORTER_KEYSTORE:-/run/secrets/tomcat-jmx-exporter/keystore.p12}"
readonly PASSWORD_FILE="${JMX_EXPORTER_KEYSTORE_PASSWORD_FILE:-/run/secrets/tomcat-jmx-exporter/keystore-password}"
readonly EXPORTER_PORT="${JMX_EXPORTER_PORT:-9404}"

die() {
    echo "[ERROR] $1" >&2
    exit 1
}

require_readable_file() {
    local file="$1"
    local description="$2"

    [[ -f "${file}" && -r "${file}" ]] \
        || die "${description} is missing or not readable: ${file}"
}

validate_port() {
    [[ "${EXPORTER_PORT}" =~ ^[0-9]+$ ]] \
        && (( EXPORTER_PORT >= 1 && EXPORTER_PORT <= 65535 )) \
        || die "JMX_EXPORTER_PORT must be a valid port number (1-65535)."
}

configure_java_agent() {
    if [[ -f "${AGENT_JAR}" && -f "${CONFIG_FILE}" && -f "${KEYSTORE_FILE}" && -f "${PASSWORD_FILE}" ]]; then
        require_readable_file "${AGENT_JAR}" "JMX Exporter Java Agent"
        require_readable_file "${CONFIG_FILE}" "JMX Exporter Config"
        require_readable_file "${KEYSTORE_FILE}" "TLS Keystore"
        require_readable_file "${PASSWORD_FILE}" "TLS Keystore Password"
        validate_port

        local password
        IFS= read -r password < "${PASSWORD_FILE}" || true
        [[ -n "${password}" ]] || die "TLS Keystore Password file cannot be empty."

        export JMX_EXPORTER_KEYSTORE_PASSWORD="${password}"
        export CATALINA_OPTS="${CATALINA_OPTS:+${CATALINA_OPTS} }-javaagent:${AGENT_JAR}=0.0.0.0:${EXPORTER_PORT}:${CONFIG_FILE}"

        echo "JMX Exporter configured on HTTPS port ${EXPORTER_PORT}"
    else
        echo "Warning: JMX Exporter prerequisites not fully mounted, starting Tomcat normally..."
    fi
}

main() {
    configure_java_agent
    if [[ -x /entrypoint.sh ]]; then
        exec /entrypoint.sh "$@"
    elif command -v catalina.sh >/dev/null 2>&1; then
        exec catalina.sh "${@:-run}"
    else
        exec "$@"
    fi
}

main "$@"
