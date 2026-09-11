#!/usr/bin/env bash
# Memverifikasi webhook firing dan resolved dengan receiver lokal disposable.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi

readonly SOURCE_CONFIG="${PROJECT_ROOT}/config/alertmanager/alertmanager.yml"
readonly RECEIVER_FIXTURE="${PROJECT_ROOT}/fixtures/alertmanager-webhook-receiver/capture.py"
readonly IMAGE="${ALERTMANAGER_IMAGE:-localhost/alertmanager:1.0.0}"
readonly CONTAINER_NAME="tm-tn029-alertmanager"
readonly RECEIVER_HOST="127.0.0.1"
readonly RECEIVER_PORT="19080"
readonly ALERTMANAGER_PORT="19093"

temporary_root=""
receiver_pid=""
container_id=""
before_volumes=""

fail() {
    printf 'ALERTMANAGER WEBHOOK VERIFICATION FAILED: %s\n' "$1" >&2
    exit 1
}

wait_for_url() {
    local url="$1"
    local attempts="$2"
    local attempt

    for ((attempt = 1; attempt <= attempts; attempt++)); do
        if curl --fail --silent --show-error "${url}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

wait_for_file() {
    local path="$1"
    local attempts="$2"
    local attempt

    for ((attempt = 1; attempt <= attempts; attempt++)); do
        [[ -s "${path}" ]] && return 0
        sleep 1
    done
    return 1
}

cleanup() {
    local original_status="$?"
    local cleanup_status=0
    local current_id=""
    local after_volumes=""
    local volume_state="not-audited"

    trap - EXIT
    set +e

    if [[ -n "${container_id}" ]] && podman container exists "${CONTAINER_NAME}"; then
        current_id="$(podman inspect --format '{{.Id}}' "${CONTAINER_NAME}" 2>/dev/null)"
        if [[ "${current_id}" == "${container_id}" ]]; then
            podman rm --force --volumes "${CONTAINER_NAME}" >/dev/null || cleanup_status=1
        else
            printf 'Cleanup ditolak: container ID berubah untuk %s.\n' "${CONTAINER_NAME}" >&2
            cleanup_status=1
        fi
    fi

    if [[ -n "${receiver_pid}" ]] && kill -0 "${receiver_pid}" 2>/dev/null; then
        kill "${receiver_pid}" 2>/dev/null
        wait "${receiver_pid}" 2>/dev/null
    fi

    if [[ -n "${temporary_root}" && -d "${temporary_root}" ]]; then
        case "${temporary_root}" in
            /tmp/tm-tn029-alertmanager.*) rm -rf -- "${temporary_root}" ;;
            *)
                printf 'Cleanup ditolak: temporary path tidak sesuai contract.\n' >&2
                cleanup_status=1
                ;;
        esac
    fi

    if [[ -n "${before_volumes}" ]]; then
        after_volumes="$(podman volume ls --format '{{.Name}}' | sort)"
        if [[ "${before_volumes}" != "${after_volumes}" ]]; then
            printf 'Cleanup audit gagal: volume state berubah.\n' >&2
            cleanup_status=1
        else
            volume_state="unchanged"
        fi
    fi

    if ((cleanup_status == 0)); then
        printf 'cleanup_result=passed container_absent=true listener_stopped=true volume_state=%s\n' \
            "${volume_state}"
    fi

    if ((original_status != 0)); then
        exit "${original_status}"
    fi
    exit "${cleanup_status}"
}

trap cleanup EXIT

for command_name in python3 curl podman sed; do
    command -v "${command_name}" >/dev/null \
        || fail "Command tidak tersedia: ${command_name}"
done

[[ -f "${SOURCE_CONFIG}" ]] || fail "Source configuration tidak ditemukan."
[[ -f "${RECEIVER_FIXTURE}" ]] || fail "Receiver fixture tidak ditemukan."
podman image exists "${IMAGE}" || fail "Local image tidak tersedia: ${IMAGE}"
if podman container exists "${CONTAINER_NAME}"; then
    fail "Container target sudah tersedia: ${CONTAINER_NAME}"
fi

python3 - "${RECEIVER_HOST}" "${RECEIVER_PORT}" "${ALERTMANAGER_PORT}" <<'PY'
import socket
import sys

host = sys.argv[1]
for raw_port in sys.argv[2:]:
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind((host, int(raw_port)))
PY

before_volumes="$(podman volume ls --format '{{.Name}}' | sort)"
temporary_root="$(mktemp -d /tmp/tm-tn029-alertmanager.XXXXXX)"
mkdir -p "${temporary_root}/config" "${temporary_root}/captures"

cat >"${temporary_root}/config/alertmanager.yml" <<EOF
global:
  resolve_timeout: 5m

route:
  receiver: integration-bridge
  group_by:
    - alertname
    - job
    - instance
    - service
    - check
  group_wait: 1s
  group_interval: 1s
  repeat_interval: 4h

receivers:
  - name: integration-bridge
    webhook_configs:
      - url_file: /run/secrets/tomcat-monitoring/integration-bridge-webhook-url
        send_resolved: true
EOF
printf 'http://127.0.0.1:%s/alerts\n' "${RECEIVER_PORT}" \
    >"${temporary_root}/integration-bridge-webhook-url"
chmod 0444 "${temporary_root}/integration-bridge-webhook-url"

python3 "${RECEIVER_FIXTURE}" \
    --host "${RECEIVER_HOST}" \
    --port "${RECEIVER_PORT}" \
    --output-directory "${temporary_root}/captures" \
    --max-requests 2 &
receiver_pid="$!"

podman run --detach --pull=never \
    --name "${CONTAINER_NAME}" \
    --network host \
    --tmpfs /alertmanager:rw \
    --volume "${temporary_root}/config:/etc/alertmanager:ro" \
    --volume "${temporary_root}/integration-bridge-webhook-url:/run/secrets/tomcat-monitoring/integration-bridge-webhook-url:ro" \
    "${IMAGE}" \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/alertmanager \
    --web.listen-address="127.0.0.1:${ALERTMANAGER_PORT}" >/dev/null
container_id="$(podman inspect --format '{{.Id}}' "${CONTAINER_NAME}")"

wait_for_url "http://127.0.0.1:${ALERTMANAGER_PORT}/-/ready" 30 \
    || fail "Alertmanager tidak ready dalam 30 detik."

python3 - "${temporary_root}/firing.json" "${temporary_root}/resolved.json" <<'PY'
import datetime
import json
import sys

now = datetime.datetime.now(datetime.timezone.utc)
labels = {
    "alertname": "TomcatApplicationHealthFailed",
    "job": "telegraf",
    "instance": "telegraf:9273",
    "service": "tomcat",
    "check": "application-health",
}
base = {
    "labels": labels,
    "annotations": {"summary": "Synthetic TN-029 webhook verification"},
    "startsAt": (now - datetime.timedelta(minutes=5)).isoformat().replace("+00:00", "Z"),
    "generatorURL": "http://127.0.0.1/tn-029",
}
firing = dict(base, endsAt=(now + datetime.timedelta(hours=1)).isoformat().replace("+00:00", "Z"))
resolved = dict(base, endsAt=(now - datetime.timedelta(seconds=1)).isoformat().replace("+00:00", "Z"))
for path, payload in zip(sys.argv[1:], (firing, resolved)):
    with open(path, "w", encoding="utf-8") as output:
        json.dump([payload], output)
PY

curl --fail --silent --show-error \
    --header 'Content-Type: application/json' \
    --data-binary "@${temporary_root}/firing.json" \
    "http://127.0.0.1:${ALERTMANAGER_PORT}/api/v2/alerts" >/dev/null
wait_for_file "${temporary_root}/captures/webhook-001.json" 30 \
    || fail "Payload firing tidak diterima dalam 30 detik."

curl --fail --silent --show-error \
    --header 'Content-Type: application/json' \
    --data-binary "@${temporary_root}/resolved.json" \
    "http://127.0.0.1:${ALERTMANAGER_PORT}/api/v2/alerts" >/dev/null
wait_for_file "${temporary_root}/captures/webhook-002.json" 30 \
    || fail "Payload resolved tidak diterima dalam 30 detik."

wait "${receiver_pid}"
receiver_pid=""

python3 - "${temporary_root}/captures/webhook-001.json" \
    "${temporary_root}/captures/webhook-002.json" <<'PY'
import json
import sys

expected_labels = {
    "alertname": "TomcatApplicationHealthFailed",
    "job": "telegraf",
    "instance": "telegraf:9273",
    "service": "tomcat",
    "check": "application-health",
}
expected_statuses = ("firing", "resolved")

for path, expected_status in zip(sys.argv[1:], expected_statuses):
    with open(path, encoding="utf-8") as source:
        payload = json.load(source)
    if payload.get("status") != expected_status:
        raise SystemExit(f"unexpected payload status in {path}")
    if payload.get("receiver") != "integration-bridge":
        raise SystemExit(f"unexpected receiver in {path}")
    if payload.get("groupLabels") != expected_labels:
        raise SystemExit(f"unexpected groupLabels in {path}")
    alerts = payload.get("alerts", [])
    if len(alerts) != 1 or alerts[0].get("status") != expected_status:
        raise SystemExit(f"unexpected alert entry in {path}")
    if alerts[0].get("labels") != expected_labels:
        raise SystemExit(f"unexpected alert labels in {path}")

print("webhook_sequence=firing,resolved")
print("receiver=integration-bridge")
print("group_labels=alertname,check,instance,job,service")
print("payload_validation=passed")
PY
