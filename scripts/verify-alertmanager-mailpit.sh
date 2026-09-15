#!/usr/bin/env bash
# Verify email firing and resolved delivery using a disposable local Mailpit runtime.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi
# shellcheck source=scripts/container-runtime-helper.sh
source "${SCRIPT_DIR}/container-runtime-helper.sh"

readonly SOURCE_CONFIG="${PROJECT_ROOT}/config/alertmanager/alertmanager.yml"
readonly ALERTMANAGER_IMAGE="${ALERTMANAGER_IMAGE:-localhost/alertmanager:1.0.0}"
readonly MAILPIT_IMAGE="${MAILPIT_IMAGE:-ghcr.io/axllent/mailpit:v1.31.0@sha256:c96991d9bef73594c246d89ca81411d4e916f03e76a7d2d72fa2ab5dd3c9ce24}"
readonly MAILPIT_DIGEST='sha256:c96991d9bef73594c246d89ca81411d4e916f03e76a7d2d72fa2ab5dd3c9ce24'
readonly NETWORK_NAME="tm-tn033-mailpit"
readonly MAILPIT_CONTAINER="tm-tn033-mailpit"
readonly ALERTMANAGER_CONTAINER="tm-tn033-alertmanager"
readonly MAILPIT_ALIAS="mailpit"
readonly SMTP_HOST="mailpit:1025"
readonly HOST_ADDRESS="127.0.0.1"
readonly MAILPIT_API_PORT="18025"
readonly ALERTMANAGER_API_PORT="19093"

temporary_root=""
mailpit_container_id=""
alertmanager_container_id=""
network_id=""
before_volumes=""

fail() {
    printf 'ALERTMANAGER MAILPIT VERIFICATION FAILED: %s\n' "$1" >&2
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

wait_for_message_count() {
    local expected_count="$1"
    local attempts="$2"
    local attempt

    for ((attempt = 1; attempt <= attempts; attempt++)); do
        if curl --fail --silent --show-error \
            "http://${HOST_ADDRESS}:${MAILPIT_API_PORT}/api/v1/messages" \
            >"${temporary_root}/messages.json" 2>/dev/null \
            && python3 - "${temporary_root}/messages.json" "${expected_count}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    payload = json.load(source)
raise SystemExit(0 if payload.get("total") == int(sys.argv[2]) else 1)
PY
        then
            return 0
        fi
        sleep 1
    done
    return 1
}

port_is_bindable() {
    python3 - "${HOST_ADDRESS}" "$@" <<'PY'
import socket
import sys

host = sys.argv[1]
for raw_port in sys.argv[2:]:
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind((host, int(raw_port)))
PY
}

cleanup() {
    local original_status="$?"
    local cleanup_status=0
    local current_id=""
    local after_volumes=""
    local volume_state="not-audited"

    trap - EXIT
    set +e

    if [[ -n "${alertmanager_container_id}" ]] \
        && container_exists "${ALERTMANAGER_CONTAINER}"; then
        current_id="$("${CONTAINER_ENGINE}" inspect --format '{{.Id}}' "${ALERTMANAGER_CONTAINER}" 2>/dev/null)"
        if [[ "${current_id}" == "${alertmanager_container_id}" ]]; then
            "${CONTAINER_ENGINE}" rm --force --volumes "${ALERTMANAGER_CONTAINER}" >/dev/null \
                || cleanup_status=1
        else
            printf 'Cleanup rejected: container ID changed for %s.\n' \
                "${ALERTMANAGER_CONTAINER}" >&2
            cleanup_status=1
        fi
    fi

    if [[ -n "${mailpit_container_id}" ]] \
        && container_exists "${MAILPIT_CONTAINER}"; then
        current_id="$("${CONTAINER_ENGINE}" inspect --format '{{.Id}}' "${MAILPIT_CONTAINER}" 2>/dev/null)"
        if [[ "${current_id}" == "${mailpit_container_id}" ]]; then
            "${CONTAINER_ENGINE}" rm --force --volumes "${MAILPIT_CONTAINER}" >/dev/null \
                || cleanup_status=1
        else
            printf 'Cleanup rejected: container ID changed for %s.\n' \
                "${MAILPIT_CONTAINER}" >&2
            cleanup_status=1
        fi
    fi

    if [[ -n "${network_id}" ]] && network_exists "${NETWORK_NAME}"; then
        current_id="$("${CONTAINER_ENGINE}" network inspect --format '{{.Id}}' "${NETWORK_NAME}" 2>/dev/null)"
        if [[ "${current_id}" == "${network_id}" ]]; then
            "${CONTAINER_ENGINE}" network rm "${NETWORK_NAME}" >/dev/null || cleanup_status=1
        else
            printf 'Cleanup rejected: network ID changed for %s.\n' \
                "${NETWORK_NAME}" >&2
            cleanup_status=1
        fi
    fi

    if [[ -n "${temporary_root}" && -d "${temporary_root}" ]]; then
        case "${temporary_root}" in
            /tmp/tm-tn033-mailpit.*) rm -rf -- "${temporary_root}" ;;
            *)
                printf 'Cleanup rejected: temporary path does not match contract.\n' >&2
                cleanup_status=1
                ;;
        esac
    fi

    if [[ -n "${before_volumes}" ]]; then
        after_volumes="$("${CONTAINER_ENGINE}" volume ls --format '{{.Name}}' | sort)"
        if [[ "${before_volumes}" != "${after_volumes}" ]]; then
            printf 'Cleanup audit failed: volume state changed.\n' >&2
            cleanup_status=1
        else
            volume_state="unchanged"
        fi
    fi

    if container_exists "${MAILPIT_CONTAINER}" \
        || container_exists "${ALERTMANAGER_CONTAINER}" \
        || network_exists "${NETWORK_NAME}"; then
        printf 'Cleanup audit failed: exact disposable resource still exists.\n' >&2
        cleanup_status=1
    fi
    port_is_bindable "${MAILPIT_API_PORT}" "${ALERTMANAGER_API_PORT}" \
        || cleanup_status=1

    if ((cleanup_status == 0)); then
        printf 'cleanup_result=passed containers_absent=true network_absent=true ports_released=true volume_state=%s image_retained=true\n' \
            "${volume_state}"
    fi

    if ((original_status != 0)); then
        exit "${original_status}"
    fi
    exit "${cleanup_status}"
}

trap cleanup EXIT

for command_name in curl "${CONTAINER_ENGINE}" python3 sed sort; do
    command -v "${command_name}" >/dev/null \
        || fail "Command not available: ${command_name}"
done

[[ -f "${SOURCE_CONFIG}" ]] || fail "Source configuration not found."
image_exists "${ALERTMANAGER_IMAGE}" \
    || fail "Local Alertmanager image not available: ${ALERTMANAGER_IMAGE}"

if container_exists "${MAILPIT_CONTAINER}" \
    || container_exists "${ALERTMANAGER_CONTAINER}" \
    || network_exists "${NETWORK_NAME}"; then
    fail "One or more disposable resources already exist."
fi
port_is_bindable "${MAILPIT_API_PORT}" "${ALERTMANAGER_API_PORT}" \
    || fail "Loopback ports are not available for binding."

before_volumes="$("${CONTAINER_ENGINE}" volume ls --format '{{.Name}}' | sort)"
temporary_root="$(mktemp -d /tmp/tm-tn033-mailpit.XXXXXX)"
mkdir -p "${temporary_root}/config" "${temporary_root}/secrets"
sed \
    -e 's/^  group_wait: 30s$/  group_wait: 1s/' \
    -e 's/^  group_interval: 5m$/  group_interval: 1s/' \
    -e 's/^  receiver: lab-diagnostic-service$/  receiver: direct-email-emergency/' \
    "${SOURCE_CONFIG}" >"${temporary_root}/config/alertmanager.yml"

printf 'http://127.0.0.1:8443\n' >"${temporary_root}/secrets/diagnostic-service-webhook-url"
printf 'dummy-token\n' >"${temporary_root}/secrets/diagnostic-service-bearer-token"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=localhost' \
    -keyout /dev/null -out "${temporary_root}/secrets/diagnostic-service-ca.crt" >/dev/null 2>&1 \
    || touch "${temporary_root}/secrets/diagnostic-service-ca.crt"

"${CONTAINER_ENGINE}" pull "${MAILPIT_IMAGE}" >/dev/null
read -r observed_digest observed_arch observed_os < <(
    "${CONTAINER_ENGINE}" image inspect --format '{{.Digest}} {{.Architecture}} {{.Os}}' \
        "${MAILPIT_IMAGE}"
)
[[ "${observed_digest}" == "${MAILPIT_DIGEST}" ]] \
    || fail "Mailpit manifest digest does not match pinned digest: ${observed_digest}"
[[ "${observed_arch}" == "amd64" && "${observed_os}" == "linux" ]] \
    || fail "Mailpit platform mismatch: ${observed_os}/${observed_arch}"

"${CONTAINER_ENGINE}" network create "${NETWORK_NAME}" >/dev/null
network_id="$("${CONTAINER_ENGINE}" network inspect --format '{{.Id}}' "${NETWORK_NAME}")"

"${CONTAINER_ENGINE}" run --detach --pull=never \
    --name "${MAILPIT_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    --network-alias "${MAILPIT_ALIAS}" \
    --publish "${HOST_ADDRESS}:${MAILPIT_API_PORT}:8025" \
    --env MP_DATABASE=/tmp/mailpit.db \
    --env MP_MAX_MESSAGES=10 \
    "${MAILPIT_IMAGE}" >/dev/null
mailpit_container_id="$("${CONTAINER_ENGINE}" inspect --format '{{.Id}}' "${MAILPIT_CONTAINER}")"

wait_for_url "http://${HOST_ADDRESS}:${MAILPIT_API_PORT}/api/v1/info" 30 \
    || fail "Mailpit API did not become ready within 30 seconds."
curl --fail --silent --show-error \
    "http://${HOST_ADDRESS}:${MAILPIT_API_PORT}/api/v1/info" \
    >"${temporary_root}/mailpit-info.json"
mailpit_version="$(python3 - "${temporary_root}/mailpit-info.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    payload = json.load(source)
version = payload.get("Version", payload.get("version", ""))
if not version:
    raise SystemExit("Mailpit API info did not provide a version")
print(version)
PY
)"
[[ "${mailpit_version}" == "v1.31.0" ]] \
    || fail "Mailpit runtime version mismatch: ${mailpit_version}"

local_vol_ro="$(get_volume_flag "ro")"
"${CONTAINER_ENGINE}" run --detach --pull=never \
    --name "${ALERTMANAGER_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    --publish "${HOST_ADDRESS}:${ALERTMANAGER_API_PORT}:9093" \
    --tmpfs /alertmanager:rw \
    --volume "${temporary_root}/config:/etc/alertmanager${local_vol_ro}" \
    --volume "${temporary_root}/secrets:/run/secrets/tomcat-monitoring${local_vol_ro}" \
    "${ALERTMANAGER_IMAGE}" \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/alertmanager >/dev/null
alertmanager_container_id="$("${CONTAINER_ENGINE}" inspect --format '{{.Id}}' "${ALERTMANAGER_CONTAINER}")"

wait_for_url "http://${HOST_ADDRESS}:${ALERTMANAGER_API_PORT}/-/ready" 30 \
    || fail "Alertmanager did not become ready within 30 seconds."
"${CONTAINER_ENGINE}" exec "${ALERTMANAGER_CONTAINER}" amtool check-config \
    /etc/alertmanager/alertmanager.yml >/dev/null

python3 - "${temporary_root}/firing.json" "${temporary_root}/resolved.json" <<'PY'
import datetime
import json
import sys

now = datetime.datetime.now(datetime.timezone.utc)
labels = {
    "alertname": "DiagnosticServiceDown",
    "job": "tomcat-diagnostic-service",
    "instance": "diagnostic-service:8443",
    "service": "tomcat",
    "check": "diagnostic-service-health",
    "severity": "critical",
}
base = {
    "labels": labels,
    "annotations": {
        "summary": "Synthetic TN-033 Mailpit direct email verification",
        "description": "Prometheus cannot scrape Diagnostic Service target diagnostic-service:8443; automated incident notification pipeline is compromised.",
    },
    "startsAt": (now - datetime.timedelta(minutes=5)).isoformat().replace("+00:00", "Z"),
    "generatorURL": "http://127.0.0.1/tn-033",
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
    "http://${HOST_ADDRESS}:${ALERTMANAGER_API_PORT}/api/v2/alerts" >/dev/null
wait_for_message_count 1 30 \
    || fail "Firing email not received by Mailpit within 30 seconds."

curl --fail --silent --show-error \
    --header 'Content-Type: application/json' \
    --data-binary "@${temporary_root}/resolved.json" \
    "http://${HOST_ADDRESS}:${ALERTMANAGER_API_PORT}/api/v2/alerts" >/dev/null
wait_for_message_count 2 30 \
    || fail "Resolved email not received by Mailpit within 30 seconds."

python3 - "${temporary_root}/messages.json" \
    "http://${HOST_ADDRESS}:${MAILPIT_API_PORT}" <<'PY'
import json
import sys
import urllib.request

with open(sys.argv[1], encoding="utf-8") as source:
    payload = json.load(source)

expected_subjects = {
    "[FIRING] [EMERGENCY] Diagnostic Service Alert: DiagnosticServiceDown (Instance: diagnostic-service:8443)",
    "[RESOLVED] [EMERGENCY] Diagnostic Service Alert: DiagnosticServiceDown (Instance: diagnostic-service:8443)",
}
messages = payload.get("messages", [])
if payload.get("total") != 2 or len(messages) != 2:
    raise SystemExit("unexpected Mailpit message count")
subjects = {message.get("Subject") for message in messages}
if subjects != expected_subjects:
    raise SystemExit(f"unexpected subjects: {sorted(subjects)}")
for message in messages:
    sender = message.get("From", {}).get("Address")
    recipients = {entry.get("Address") for entry in message.get("To", [])}
    if sender != "alertmanager@tomcat-monitoring.invalid":
        raise SystemExit(f"unexpected sender: {sender}")
    if recipients != {"operator@tomcat-monitoring.invalid"}:
        raise SystemExit(f"unexpected recipients: {sorted(recipients)}")
    message_id = message.get("ID")
    if not message_id:
        raise SystemExit("Mailpit summary did not provide message ID")
    with urllib.request.urlopen(
        f"{sys.argv[2]}/api/v1/message/{message_id}", timeout=5
    ) as response:
        full_message = json.load(response)
    rendered_message = full_message.get("HTML", "")
    subject = message.get("Subject")
    expected_render = {
        "[FIRING] [EMERGENCY] Diagnostic Service Alert: DiagnosticServiceDown (Instance: diagnostic-service:8443)":
            (
                "background-color:#c62828",
                "🚨 [ EMERGENCY ] Direct Alert Notification",
                "🚨 Emergency Notice (Bypass Webhook)",
                "📋 Technical Details",
                "🛠️ Immediate Operator Actions Required",
                ">critical</td>",
                ">DiagnosticServiceDown</td>",
                "Prometheus cannot scrape Diagnostic Service target diagnostic-service:8443; automated incident notification pipeline is compromised.",
            ),
        "[RESOLVED] [EMERGENCY] Diagnostic Service Alert: DiagnosticServiceDown (Instance: diagnostic-service:8443)":
            (
                "background-color:#2e7d32",
                "[ RESOLVED ] Diagnostic Service Restored",
                "✅ Service Recovery Summary",
                "📋 Technical Details",
                "🛠️ Immediate Operator Actions Required",
                ">normal</td>",
                ">DiagnosticServiceDown</td>",
                "Diagnostic Service target diagnostic-service:8443 has recovered and is scrapeable again. Automated incident notification pipeline is restored.",
            ),
    }.get(subject)
    for expected_token in expected_render:
        if expected_token not in rendered_message:
            raise SystemExit(
                f"message {message_id} does not contain render token {expected_token}"
            )
    expected_keys = (
        "Alert Name",
        "Service / Check",
        "Target Instance",
        "Severity",
        "Delivery Route",
    )
    for expected_key in expected_keys:
        if rendered_message.count(f">{expected_key}</td>") != 1:
            raise SystemExit(
                f"message {message_id} does not contain exactly one key {expected_key}"
            )
    for expected_token in (
        "diagnostic-service",
        "diagnostic-service:8443",
        "tomcat",
        "diagnostic-service-health",
    ):
        if expected_token not in rendered_message:
            raise SystemExit(
                f"message {message_id} does not contain token {expected_token}"
            )
    if "View in Alertmanager" in rendered_message or ":9093/#/alerts?receiver=" in rendered_message:
        raise SystemExit(
            f"message {message_id} contains inaccessible Alertmanager link"
        )
    if "[FIRING]" in subject:
        if "Prometheus cannot scrape Diagnostic Service target diagnostic-service:8443; automated incident notification pipeline is compromised." not in rendered_message:
            raise SystemExit(f"critical message {message_id} does not contain firing description")
        if "has recovered and is scrapeable again" in rendered_message:
            raise SystemExit(f"critical message {message_id} contains normal description")
    else:
        for forbidden in (
            "Prometheus cannot scrape Diagnostic Service",
            "background-color:#c62828",
            ">critical</td>",
        ):
            if forbidden in rendered_message:
                raise SystemExit(
                    f"normal message {message_id} contains critical token {forbidden}"
                )

print("mailpit_sequence=firing,resolved")
print("sender=alertmanager@tomcat-monitoring.invalid")
print("recipient=operator@tomcat-monitoring.invalid")
print("subjects_validation=passed")
print("status_specific_body=passed")
print("status_color_rendering=passed")
print("resolved_stale_description=absent")
print("operator_status_subjects=critical,normal")
print("unified_key_layout=passed")
print("message_body_group_labels=passed")
PY

printf 'semantic_config=passed\n'
printf 'mailpit_manifest_digest=%s platform=%s/%s\n' \
    "${observed_digest}" "${observed_os}" "${observed_arch}"
printf 'mailpit_version=%s\n' "${mailpit_version}"
printf 'smtp_endpoint=%s host_smtp_published=false\n' "${SMTP_HOST}"
