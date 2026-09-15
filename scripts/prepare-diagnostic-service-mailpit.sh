#!/usr/bin/env bash
# Prepare non-persistent TN-013 fixtures without launching containers/runtimes.
set -euo pipefail

readonly EXPECTED_PREFIX="/tmp/tomcat-diagnostic-tn013."

fail() {
    printf 'DIAGNOSTIC FIXTURE PREPARATION FAILED: %s\n' "$1" >&2
    exit 1
}

[[ "$#" -eq 1 ]] || fail "Usage: $0 <exact-temporary-directory>"
readonly TEMPORARY_ROOT="$1"
[[ "${TEMPORARY_ROOT}" == "${EXPECTED_PREFIX}"* && -d "${TEMPORARY_ROOT}" ]] \
    || fail "Temporary directory does not adhere to TN-013 contract."

for command_name in openssl chmod mkdir; do
    command -v "${command_name}" >/dev/null \
        || fail "Command not available: ${command_name}"
done

[[ -z "$(find "${TEMPORARY_ROOT}" -mindepth 1 -print -quit)" ]] \
    || fail "Temporary directory must be empty."

umask 077
mkdir -p \
    "${TEMPORARY_ROOT}/config" \
    "${TEMPORARY_ROOT}/data" \
    "${TEMPORARY_ROOT}/secrets" \
    "${TEMPORARY_ROOT}/tls"

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=diagnostic-service' \
    -addext 'subjectAltName=DNS:diagnostic-service' \
    -keyout "${TEMPORARY_ROOT}/tls/server.key" \
    -out "${TEMPORARY_ROOT}/tls/server.crt" >/dev/null 2>&1

printf '%s\n' 'tn013-disposable-bearer-token' \
    >"${TEMPORARY_ROOT}/secrets/bearer-token"

printf '%s\n' \
    '[{"identity":{"environment":"tn013","host":"tomcat-01","tomcat_instance":"default"}}]' \
    >"${TEMPORARY_ROOT}/config/targets.json"

printf '%s\n' \
    '{' \
    '  "schemaVersion": 1,' \
    '  "listen": {"host": "0.0.0.0", "port": 8443},' \
    '  "databasePath": "/var/lib/tomcat-diagnostic/diagnostic.db",' \
    '  "tls": {' \
    '    "certificateFile": "/run/tomcat-diagnostic/tls/server.crt",' \
    '    "privateKeyFile": "/run/tomcat-diagnostic/tls/server.key"' \
    '  },' \
    '  "bearerTokenFile": "/run/tomcat-diagnostic/secrets/bearer-token",' \
    '  "targetAllowlistFile": "/run/tomcat-diagnostic/config/targets.json",' \
    '  "smtp": {' \
    '    "host": "mailpit", "port": 1025, "secure": false,' \
    '    "from": "diagnostic@tomcat-monitoring.invalid",' \
    '    "to": "operator@tomcat-monitoring.invalid"' \
    '  },' \
    '  "queue": {"capacity": 50, "pollIntervalMs": 250},' \
    '  "timeouts": {"diagnosticMs": 60000, "smtpMs": 10000, "shutdownMs": 10000},' \
    '  "requestLimitBytes": 262144' \
    '}' >"${TEMPORARY_ROOT}/config/application.json"

chmod 0700 "${TEMPORARY_ROOT}" "${TEMPORARY_ROOT}"/{config,data,secrets,tls}
chmod 0444 \
    "${TEMPORARY_ROOT}/config/application.json" \
    "${TEMPORARY_ROOT}/config/targets.json" \
    "${TEMPORARY_ROOT}/tls/server.crt"
chmod 0400 \
    "${TEMPORARY_ROOT}/secrets/bearer-token" \
    "${TEMPORARY_ROOT}/tls/server.key"

printf 'fixture_result=prepared temporary_root=%s secret_material_in_git=false\n' \
    "${TEMPORARY_ROOT}"
