#!/usr/bin/env bash
# Menyiapkan fixture non-persistent TN-014 tanpa menjalankan container/runtime.
set -euo pipefail

readonly EXPECTED_PREFIX="/tmp/tm-tn014-diagnostic-route."

fail() {
    printf 'ALERTMANAGER DIAGNOSTIC FIXTURE PREPARATION FAILED: %s\n' "$1" >&2
    exit 1
}

[[ "$#" -eq 1 ]] || fail "Usage: $0 <exact-temporary-directory>"
readonly TEMPORARY_ROOT="$1"
[[ "${TEMPORARY_ROOT}" == "${EXPECTED_PREFIX}"* && -d "${TEMPORARY_ROOT}" ]] \
    || fail "Temporary directory tidak sesuai TN-014 contract."

for command_name in openssl chmod mkdir; do
    command -v "${command_name}" >/dev/null \
        || fail "Command tidak tersedia: ${command_name}"
done

[[ -z "$(find "${TEMPORARY_ROOT}" -mindepth 1 -print -quit)" ]] \
    || fail "Temporary directory harus kosong."

umask 077
mkdir -p \
    "${TEMPORARY_ROOT}/alertmanager" \
    "${TEMPORARY_ROOT}/config" \
    "${TEMPORARY_ROOT}/data" \
    "${TEMPORARY_ROOT}/secrets" \
    "${TEMPORARY_ROOT}/tls"

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=diagnostic-service' \
    -addext 'subjectAltName=DNS:diagnostic-service' \
    -keyout "${TEMPORARY_ROOT}/tls/server.key" \
    -out "${TEMPORARY_ROOT}/tls/server.crt" >/dev/null 2>&1

printf '%s\n' 'tn014-disposable-bearer-token' \
    >"${TEMPORARY_ROOT}/secrets/bearer-token"

# URL file: Alertmanager mengirim webhook ke DS internal endpoint
printf '%s\n' 'https://diagnostic-service:8443/api/v1/alerts/alertmanager' \
    >"${TEMPORARY_ROOT}/alertmanager/diagnostic-service-webhook-url"

printf '%s\n' \
    '[{"identity":{"environment":"lab","host":"tomcat-01","tomcat_instance":"default"}}]' \
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
    '    "host": "localhost", "port": 1025, "secure": false,' \
    '    "from": "diagnostic@tomcat-monitoring.invalid",' \
    '    "to": "operator@tomcat-monitoring.invalid"' \
    '  },' \
    '  "queue": {"capacity": 50, "pollIntervalMs": 250},' \
    '  "timeouts": {"diagnosticMs": 60000, "smtpMs": 10000, "shutdownMs": 10000},' \
    '  "requestLimitBytes": 262144' \
    '}' >"${TEMPORARY_ROOT}/config/application.json"

# Synthetic Alertmanager config: route semua ke DS (disposable verification only)
printf '%s\n' \
    'global:' \
    '  resolve_timeout: 5m' \
    '' \
    'route:' \
    '  receiver: lab-diagnostic-service' \
    '  group_by:' \
    '    - alertname' \
    '    - job' \
    '    - instance' \
    '    - service' \
    '    - check' \
    '  group_wait: 5s' \
    '  group_interval: 5s' \
    '  repeat_interval: 4h' \
    '' \
    'receivers:' \
    '  - name: lab-diagnostic-service' \
    '    webhook_configs:' \
    '      - url_file: /run/secrets/tomcat-monitoring/diagnostic-service-webhook-url' \
    '        http_config:' \
    '          authorization:' \
    '            credentials_file: /run/secrets/tomcat-monitoring/diagnostic-service-bearer-token' \
    '          tls_config:' \
    '            ca_file: /etc/alertmanager/tls/ca.crt' \
    '        send_resolved: true' \
    '        max_alerts: 1' \
    >"${TEMPORARY_ROOT}/alertmanager/alertmanager.yml"

chmod 0700 \
    "${TEMPORARY_ROOT}" \
    "${TEMPORARY_ROOT}"/{alertmanager,config,data,secrets,tls}
chmod 0444 \
    "${TEMPORARY_ROOT}/alertmanager/alertmanager.yml" \
    "${TEMPORARY_ROOT}/alertmanager/diagnostic-service-webhook-url" \
    "${TEMPORARY_ROOT}/config/application.json" \
    "${TEMPORARY_ROOT}/config/targets.json" \
    "${TEMPORARY_ROOT}/secrets/bearer-token" \
    "${TEMPORARY_ROOT}/tls/server.crt"
chmod 0400 \
    "${TEMPORARY_ROOT}/tls/server.key"

printf 'fixture_result=prepared temporary_root=%s secret_material_in_git=false\n' \
    "${TEMPORARY_ROOT}"
