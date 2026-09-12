#!/usr/bin/env bash
# Deploy and automate Restricted Event Collector as a systemd user daemon.
set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -z "${COLLECTOR_REPO:-}" ]]; then
    if [[ -d "$(dirname "${PROJECT_ROOT}")/tomcat-diagnostic-event-collector" ]]; then
        COLLECTOR_REPO="$(dirname "${PROJECT_ROOT}")/tomcat-diagnostic-event-collector"
    elif [[ -d "${HOME}/git/tomcat-diagnostic-event-collector" ]]; then
        COLLECTOR_REPO="${HOME}/git/tomcat-diagnostic-event-collector"
    else
        COLLECTOR_REPO="$(dirname "${PROJECT_ROOT}")/tomcat-diagnostic-event-collector"
    fi
fi
readonly COLLECTOR_REPO
readonly SERVICE_NAME="tomcat-diagnostic-event-collector.service"
readonly SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
readonly UNIT_FILE="${SYSTEMD_USER_DIR}/${SERVICE_NAME}"

if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi

if [[ -f "${COLLECTOR_REPO}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${COLLECTOR_REPO}/CONFIG"
fi

readonly SPOOL_DIR="${SPOOL_DIR:-${DEFAULT_SPOOL_DIR:-${HOME}/.local/share/tomcat-monitoring/spool}}"
readonly TARGET_CONTAINER="${TARGET_CONTAINER:-${DEFAULT_TARGET_CONTAINER:-tomcat-jmx-exporter}}"
readonly TARGET_ID="${TARGET_ID:-${DEFAULT_TARGET_ID:-lab/tomcat-01/default}}"
readonly MAX_SPOOL_AGE_HOURS="${MAX_SPOOL_AGE_HOURS:-${DEFAULT_MAX_SPOOL_AGE_HOURS:-24}}"
readonly MAX_SPOOL_FILES="${MAX_SPOOL_FILES:-${DEFAULT_MAX_SPOOL_FILES:-1000}}"
readonly STALE_TMP_AGE_MINUTES="${STALE_TMP_AGE_MINUTES:-${DEFAULT_STALE_TMP_AGE_MINUTES:-60}}"

fail() {
    printf 'EVENT COLLECTOR DEPLOYMENT FAILED: %s\n' "$1" >&2
    exit 1
}

main() {
    echo "=== Deploying Tomcat Diagnostic Restricted Event Collector Daemon ==="

    # Pre-flight assertions
    for cmd in systemctl podman bash python3; do
        command -v "${cmd}" >/dev/null || fail "Required command not found: ${cmd}"
    done

    [[ -d "${COLLECTOR_REPO}" ]] \
        || fail "Collector repository tidak ditemukan: ${COLLECTOR_REPO}"
    [[ -f "${COLLECTOR_REPO}/src/collector.sh" ]] \
        || fail "Collector script tidak ditemukan: ${COLLECTOR_REPO}/src/collector.sh"

    # Ensure executable permission
    chmod 0755 "${COLLECTOR_REPO}/src/collector.sh"

    # 1. Prepare persistent spool directory with strict 0700 permissions
    echo "1. Preparing persistent spool directory: ${SPOOL_DIR} (mode 0700)..."
    mkdir -p "${SPOOL_DIR}"
    chmod 0700 "${SPOOL_DIR}"

    # 2. Generate and install systemd user service unit
    echo "2. Installing systemd user unit: ${UNIT_FILE}..."
    mkdir -p "${SYSTEMD_USER_DIR}"

    cat <<UNIT_EOF > "${UNIT_FILE}"
[Unit]
Description=Tomcat Diagnostic Restricted Event Collector Daemon
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash ${COLLECTOR_REPO}/src/collector.sh
Restart=always
RestartSec=3s
Environment=SPOOL_DIR=${SPOOL_DIR}
Environment=TARGET_CONTAINER=${TARGET_CONTAINER}
Environment=TARGET_ID=${TARGET_ID}
Environment=MAX_SPOOL_AGE_HOURS=${MAX_SPOOL_AGE_HOURS}
Environment=MAX_SPOOL_FILES=${MAX_SPOOL_FILES}
Environment=STALE_TMP_AGE_MINUTES=${STALE_TMP_AGE_MINUTES}

[Install]
WantedBy=default.target
UNIT_EOF

    chmod 0644 "${UNIT_FILE}"

    # 3. Reload systemd daemon and activate service
    echo "3. Reloading systemd user daemon and enabling service..."
    systemctl --user daemon-reload
    systemctl --user enable --now "${SERVICE_NAME}"

    # 4. Verify service activation
    echo "4. Verifying service status..."
    sleep 2

    if systemctl --user is-active --quiet "${SERVICE_NAME}"; then
        echo "Restricted Event Collector daemon is active and running."
        systemctl --user status "${SERVICE_NAME}" --no-pager
    else
        fail "Service ${SERVICE_NAME} gagal mencapai status active!"
    fi
}

main "$@"
