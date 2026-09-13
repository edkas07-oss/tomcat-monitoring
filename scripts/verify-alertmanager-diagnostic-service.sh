#!/usr/bin/env bash
# Memverifikasi Alertmanager → Diagnostic Service webhook delivery dengan
# disposable runtime. Cleanup sengaja menjadi approval gate terpisah.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi
# shellcheck source=scripts/container-runtime-helper.sh
source "${SCRIPT_DIR}/container-runtime-helper.sh"

readonly PROBE_FIXTURE="${PROJECT_ROOT}/fixtures/alertmanager-diagnostic-route/probe.js"
readonly ALERTMANAGER_IMAGE="${ALERTMANAGER_IMAGE:-localhost/alertmanager:1.0.0}"
readonly CLIENT_IMAGE='localhost/nodejs@sha256:76b1444d507be3398f3196f37bd20f7a97a703871ed2716fa91a1a9520fc482d'
readonly NETWORK_NAME="tm-tn014-diagnostic-route"
readonly ALERTMANAGER_CONTAINER="tm-tn014-alertmanager"
readonly DIAGNOSTIC_CONTAINER="tm-tn014-diagnostic-service"
readonly HOST_ADDRESS="127.0.0.1"
readonly ALERTMANAGER_API_PORT="19094"
readonly EXPECTED_PREFIX="/tmp/tm-tn014-diagnostic-route."

fail() {
    printf 'ALERTMANAGER DIAGNOSTIC VERIFICATION FAILED: %s\n' "$1" >&2
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

[[ "$#" -eq 1 ]] || fail "Usage: DIAGNOSTIC_IMAGE=<exact-digest> $0 <exact-temporary-directory>"
readonly TEMPORARY_ROOT="$1"
readonly DIAGNOSTIC_IMAGE="${DIAGNOSTIC_IMAGE:-}"

[[ "${TEMPORARY_ROOT}" == "${EXPECTED_PREFIX}"* && -d "${TEMPORARY_ROOT}" ]] \
    || fail "Temporary directory tidak sesuai TN-014 contract."
[[ "${DIAGNOSTIC_IMAGE}" == */tomcat-diagnostic-service@sha256:* || "${DIAGNOSTIC_IMAGE}" == */tomcat-diagnostic-service:* ]] \
    || fail "DIAGNOSTIC_IMAGE harus merujuk ke image tomcat-diagnostic-service dengan digest atau tag."

for command_name in cmp curl "${CONTAINER_ENGINE}" python3 sort stat; do
    command -v "${command_name}" >/dev/null \
        || fail "Command tidak tersedia: ${command_name}"
done

for relative_path in \
    alertmanager/alertmanager.yml \
    alertmanager/diagnostic-service-webhook-url \
    config/application.json config/targets.json \
    secrets/bearer-token \
    tls/server.crt tls/server.key; do
    [[ -f "${TEMPORARY_ROOT}/${relative_path}" ]] \
        || fail "Fixture tidak ditemukan: ${relative_path}"
done
[[ -f "${PROBE_FIXTURE}" ]] || fail "Probe fixture tidak ditemukan: ${PROBE_FIXTURE}"

for image in "${DIAGNOSTIC_IMAGE}" "${ALERTMANAGER_IMAGE}" "${CLIENT_IMAGE}"; do
    image_exists "${image}" || fail "Image tidak tersedia: ${image}"
done

for container in "${ALERTMANAGER_CONTAINER}" "${DIAGNOSTIC_CONTAINER}"; do
    container_exists "${container}" \
        && fail "Exact container sudah tersedia: ${container}"
done
network_exists "${NETWORK_NAME}" \
    && fail "Exact network sudah tersedia: ${NETWORK_NAME}"

# Audit volume state sebelum runtime
"${CONTAINER_ENGINE}" volume ls --format '{{.Name}}' | sort \
    >"${TEMPORARY_ROOT}/volume-baseline.txt"

"${CONTAINER_ENGINE}" network create "${NETWORK_NAME}" >/dev/null

local_userns_flag="$(get_userns_flag)"
local_vol_ro_z="$(get_volume_flag "ro,z")"
local_vol_z="$(get_volume_flag "z")"
local_vol_ro_Z="$(get_volume_flag "ro,Z")"

local ds_run_args=(
    --detach --pull=never
    --name "${DIAGNOSTIC_CONTAINER}"
    --network "${NETWORK_NAME}"
    --network-alias diagnostic-service
    --restart=no
    --volume "${TEMPORARY_ROOT}/config/application.json:/run/tomcat-diagnostic/application.json${local_vol_ro_z}"
    --volume "${TEMPORARY_ROOT}/config/targets.json:/run/tomcat-diagnostic/config/targets.json${local_vol_ro_z}"
    --volume "${TEMPORARY_ROOT}/secrets/bearer-token:/run/tomcat-diagnostic/secrets/bearer-token${local_vol_ro_z}"
    --volume "${TEMPORARY_ROOT}/tls/server.crt:/run/tomcat-diagnostic/tls/server.crt${local_vol_ro_z}"
    --volume "${TEMPORARY_ROOT}/tls/server.key:/run/tomcat-diagnostic/tls/server.key${local_vol_ro_z}"
    --volume "${TEMPORARY_ROOT}/data:/var/lib/tomcat-diagnostic${local_vol_z}"
)
if [[ -n "${local_userns_flag}" ]]; then
    ds_run_args=("${local_userns_flag}" "${ds_run_args[@]}")
fi

# Jalankan Diagnostic Service (internal network, tanpa host port)
"${CONTAINER_ENGINE}" run "${ds_run_args[@]}" \
    "${DIAGNOSTIC_IMAGE}" >/dev/null

# Beri waktu Node.js startup (DS tidak mencetak log ready)
sleep 6
[[ "$("${CONTAINER_ENGINE}" inspect --format '{{.State.Status}}' "${DIAGNOSTIC_CONTAINER}")" == "running" ]] \
    || fail "Diagnostic Service gagal start atau sudah exit."

# Jalankan Alertmanager (loopback port untuk API; DS hanya internal)
"${CONTAINER_ENGINE}" run --detach --pull=never \
    --name "${ALERTMANAGER_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    --network-alias alertmanager \
    --restart=no \
    --publish "${HOST_ADDRESS}:${ALERTMANAGER_API_PORT}:9093" \
    --tmpfs /alertmanager:rw \
    --volume "${TEMPORARY_ROOT}/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml${local_vol_ro_z}" \
    --volume "${TEMPORARY_ROOT}/tls/server.crt:/etc/alertmanager/tls/ca.crt${local_vol_ro_z}" \
    --volume "${TEMPORARY_ROOT}/alertmanager/diagnostic-service-webhook-url:/run/secrets/tomcat-monitoring/diagnostic-service-webhook-url${local_vol_ro_z}" \
    --volume "${TEMPORARY_ROOT}/secrets/bearer-token:/run/secrets/tomcat-monitoring/diagnostic-service-bearer-token${local_vol_ro_z}" \
    "${ALERTMANAGER_IMAGE}" \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/alertmanager \
    --web.listen-address="0.0.0.0:9093" >/dev/null

wait_for_url "http://${HOST_ADDRESS}:${ALERTMANAGER_API_PORT}/-/ready" 30 \
    || fail "Alertmanager tidak ready dalam 30 detik."

readonly ALERTMANAGER_CONTAINER_ID="$("${CONTAINER_ENGINE}" inspect --format '{{.Id}}' "${ALERTMANAGER_CONTAINER}")"
readonly DIAGNOSTIC_CONTAINER_ID="$("${CONTAINER_ENGINE}" inspect --format '{{.Id}}' "${DIAGNOSTIC_CONTAINER}")"
readonly NETWORK_ID="$("${CONTAINER_ENGINE}" network inspect "${NETWORK_NAME}" --format '{{.Id}}')"

# Buat synthetic TomcatDown firing payload
python3 - "${TEMPORARY_ROOT}/firing.json" "${TEMPORARY_ROOT}/resolved.json" <<'PY'
import datetime
import json
import sys

now = datetime.datetime.now(datetime.timezone.utc)
labels = {
    "alertname": "TomcatDown",
    "severity": "critical",
    "environment": "lab",
    "host": "tomcat-01",
    "tomcat_instance": "default",
    "job": "tomcat-jmx-exporter",
    "instance": "tomcat-jmx-exporter:9404",
    "service": "tomcat",
    "check": "runtime-availability",
}
base = {
    "labels": labels,
    "annotations": {"summary": "Synthetic TN-014 alertmanager route verification"},
    "startsAt": (now - datetime.timedelta(minutes=5)).isoformat().replace("+00:00", "Z"),
    "generatorURL": "http://127.0.0.1/tn-014",
}
firing = dict(base, endsAt=(now + datetime.timedelta(hours=1)).isoformat().replace("+00:00", "Z"))
resolved = dict(base, endsAt=(now - datetime.timedelta(seconds=1)).isoformat().replace("+00:00", "Z"))
for path, payload in zip(sys.argv[1:], (firing, resolved)):
    with open(path, "w", encoding="utf-8") as f:
        json.dump([payload], f)
PY

# Kirim TomcatDown firing ke Alertmanager API
curl --fail --silent --show-error \
    --header 'Content-Type: application/json' \
    --data-binary "@${TEMPORARY_ROOT}/firing.json" \
    "http://${HOST_ADDRESS}:${ALERTMANAGER_API_PORT}/api/v2/alerts" >/dev/null

printf 'Menunggu Alertmanager mengirim firing webhook ke Diagnostic Service...\n'
sleep 20

# Kirim TomcatDown resolved ke Alertmanager API
curl --fail --silent --show-error \
    --header 'Content-Type: application/json' \
    --data-binary "@${TEMPORARY_ROOT}/resolved.json" \
    "http://${HOST_ADDRESS}:${ALERTMANAGER_API_PORT}/api/v2/alerts" >/dev/null

printf 'Menunggu Alertmanager mengirim resolved webhook ke Diagnostic Service...\n'
sleep 20

# Hentikan Diagnostic Service via SIGTERM dan verifikasi exit 0
"${CONTAINER_ENGINE}" stop --time 15 "${DIAGNOSTIC_CONTAINER}" >/dev/null
[[ "$("${CONTAINER_ENGINE}" inspect "${DIAGNOSTIC_CONTAINER}" --format '{{.State.ExitCode}}')" == "0" ]] \
    || fail "Diagnostic Service tidak exit 0 setelah SIGTERM."

# SQLite probe: verifikasi firing dan resolved tersimpan
[[ "$(stat -c '%a' "${TEMPORARY_ROOT}/data/diagnostic.db")" == "600" ]] \
    || fail "SQLite database mode tidak sesuai contract (expected 0600)."

local client_probe_args=(
    --rm --pull=never
    --network none
    --volume "${PROJECT_ROOT}/fixtures/alertmanager-diagnostic-route:/probe${local_vol_ro_Z}"
    --volume "${TEMPORARY_ROOT}/data:/data${local_vol_ro_z}"
)
if [[ -n "${local_userns_flag}" ]]; then
    client_probe_args=("${local_userns_flag}" "${client_probe_args[@]}")
fi

"${CONTAINER_ENGINE}" run "${client_probe_args[@]}" \
    "${CLIENT_IMAGE}" \
    node /probe/probe.js /data/diagnostic.db \
    || fail "SQLite probe gagal: firing atau resolved event tidak ditemukan."

# Audit volume state setelah runtime
"${CONTAINER_ENGINE}" volume ls --format '{{.Name}}' | sort \
    >"${TEMPORARY_ROOT}/volume-after-runtime.txt"
cmp --silent \
    "${TEMPORARY_ROOT}/volume-baseline.txt" \
    "${TEMPORARY_ROOT}/volume-after-runtime.txt" \
    || fail "Named/anonymous volume state berubah selama runtime."

printf 'runtime_result=passed network=%s alertmanager=%s diagnostic=%s host_ports=127.0.0.1:%s named_volumes=none\n' \
    "${NETWORK_NAME}" "${ALERTMANAGER_CONTAINER}" "${DIAGNOSTIC_CONTAINER}" "${ALERTMANAGER_API_PORT}"
printf 'resource_ids network=%s alertmanager=%s diagnostic=%s\n' \
    "${NETWORK_ID}" "${ALERTMANAGER_CONTAINER_ID}" "${DIAGNOSTIC_CONTAINER_ID}"
printf 'cleanup_state=pending_authorization temporary_root=%s images_retained=true\n' \
    "${TEMPORARY_ROOT}"
