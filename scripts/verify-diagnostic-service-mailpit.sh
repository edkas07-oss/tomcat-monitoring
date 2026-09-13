#!/usr/bin/env bash
# Menjalankan disposable TN-013 runtime; cleanup sengaja menjadi approval gate terpisah.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi
# shellcheck source=scripts/container-runtime-helper.sh
source "${SCRIPT_DIR}/container-runtime-helper.sh"

readonly NETWORK_NAME="tm-tn013-diagnostic"
readonly DIAGNOSTIC_CONTAINER="tm-tn013-diagnostic-service"
readonly CLIENT_CONTAINER="tm-tn013-diagnostic-client"
readonly MAILPIT_CONTAINER="tm-tn013-diagnostic-mailpit"
readonly CLIENT_IMAGE='localhost/nodejs@sha256:76b1444d507be3398f3196f37bd20f7a97a703871ed2716fa91a1a9520fc482d'
readonly MAILPIT_IMAGE="${MAILPIT_IMAGE:-ghcr.io/axllent/mailpit:v1.31.0@sha256:c96991d9bef73594c246d89ca81411d4e916f03e76a7d2d72fa2ab5dd3c9ce24}"
readonly EXPECTED_PREFIX="/tmp/tomcat-diagnostic-tn013."

fail() {
    printf 'DIAGNOSTIC MAILPIT VERIFICATION FAILED: %s\n' "$1" >&2
    exit 1
}

[[ "$#" -eq 1 ]] || fail "Usage: DIAGNOSTIC_IMAGE=<exact-digest> $0 <exact-temporary-directory>"
readonly TEMPORARY_ROOT="$1"
readonly DIAGNOSTIC_IMAGE="${DIAGNOSTIC_IMAGE:-}"
umask 077

[[ "${TEMPORARY_ROOT}" == "${EXPECTED_PREFIX}"* && -d "${TEMPORARY_ROOT}" ]] \
    || fail "Temporary directory tidak sesuai TN-013 contract."
[[ "${DIAGNOSTIC_IMAGE}" == */tomcat-diagnostic-service@sha256:* || "${DIAGNOSTIC_IMAGE}" == */tomcat-diagnostic-service:* ]] \
    || fail "DIAGNOSTIC_IMAGE harus merujuk ke image tomcat-diagnostic-service dengan digest atau tag."

for command_name in cmp "${CONTAINER_ENGINE}" sort stat; do
    command -v "${command_name}" >/dev/null \
        || fail "Command tidak tersedia: ${command_name}"
done

for relative_path in \
    config/application.json config/targets.json secrets/bearer-token \
    tls/server.crt tls/server.key; do
    [[ -f "${TEMPORARY_ROOT}/${relative_path}" ]] \
        || fail "Fixture tidak ditemukan: ${relative_path}"
done
[[ "$(stat -c '%a' "${TEMPORARY_ROOT}/config/application.json")" == "444" ]]
[[ "$(stat -c '%a' "${TEMPORARY_ROOT}/config/targets.json")" == "444" ]]
[[ "$(stat -c '%a' "${TEMPORARY_ROOT}/tls/server.crt")" == "444" ]]
[[ "$(stat -c '%a' "${TEMPORARY_ROOT}/tls/server.key")" == "400" ]]
[[ "$(stat -c '%a' "${TEMPORARY_ROOT}/secrets/bearer-token")" == "400" ]]
[[ "$(stat -c '%a' "${TEMPORARY_ROOT}/data")" == "700" ]]

for image in "${DIAGNOSTIC_IMAGE}" "${CLIENT_IMAGE}" "${MAILPIT_IMAGE}"; do
    image_exists "${image}" || fail "Image tidak tersedia: ${image}"
done

for container in "${DIAGNOSTIC_CONTAINER}" "${CLIENT_CONTAINER}" "${MAILPIT_CONTAINER}"; do
    container_exists "${container}" \
        && fail "Exact container sudah tersedia: ${container}"
done
network_exists "${NETWORK_NAME}" \
    && fail "Exact network sudah tersedia: ${NETWORK_NAME}"

"${CONTAINER_ENGINE}" volume ls --format '{{.Name}}' | sort \
    >"${TEMPORARY_ROOT}/volume-baseline.txt"

"${CONTAINER_ENGINE}" network create "${NETWORK_NAME}" >/dev/null

"${CONTAINER_ENGINE}" run --detach --pull=never \
    --name "${MAILPIT_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    --network-alias mailpit \
    --restart=no \
    --env MP_MAX_MESSAGES=10 \
    "${MAILPIT_IMAGE}" >/dev/null

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

"${CONTAINER_ENGINE}" run "${ds_run_args[@]}" \
    "${DIAGNOSTIC_IMAGE}" >/dev/null

local client_run_args=(
    --detach --pull=never
    --name "${CLIENT_CONTAINER}"
    --network "${NETWORK_NAME}"
    --restart=no
    --volume "${PROJECT_ROOT}/fixtures/diagnostic-service-mailpit:/probe${local_vol_ro_Z}"
    --volume "${TEMPORARY_ROOT}/tls/server.crt:/runtime/server.crt${local_vol_ro_z}"
    --volume "${TEMPORARY_ROOT}/data:/runtime/data${local_vol_ro_z}"
    --workdir /probe
)
if [[ -n "${local_userns_flag}" ]]; then
    client_run_args=("${local_userns_flag}" "${client_run_args[@]}")
fi

"${CONTAINER_ENGINE}" run "${client_run_args[@]}" \
    "${CLIENT_IMAGE}" \
    node -e 'setInterval(() => {}, 60000)' >/dev/null

"${CONTAINER_ENGINE}" exec "${CLIENT_CONTAINER}" node runtime-probe.js

"${CONTAINER_ENGINE}" stop --time 10 "${DIAGNOSTIC_CONTAINER}" >/dev/null
[[ "$("${CONTAINER_ENGINE}" inspect "${DIAGNOSTIC_CONTAINER}" --format '{{.State.ExitCode}}')" == "0" ]] \
    || fail "Diagnostic Service tidak exit 0 setelah SIGTERM."
"${CONTAINER_ENGINE}" exec "${CLIENT_CONTAINER}" node database-probe.js /runtime/data/diagnostic.db
[[ "$(stat -c '%a' "${TEMPORARY_ROOT}/data/diagnostic.db")" == "600" ]] \
    || fail "SQLite database mode tidak sesuai contract."

"${CONTAINER_ENGINE}" start "${DIAGNOSTIC_CONTAINER}" >/dev/null
"${CONTAINER_ENGINE}" exec "${CLIENT_CONTAINER}" node reopen-probe.js
"${CONTAINER_ENGINE}" stop --time 10 "${DIAGNOSTIC_CONTAINER}" >/dev/null
[[ "$("${CONTAINER_ENGINE}" inspect "${DIAGNOSTIC_CONTAINER}" --format '{{.State.ExitCode}}')" == "0" ]] \
    || fail "Diagnostic Service tidak exit 0 setelah reopen verification."

"${CONTAINER_ENGINE}" volume ls --format '{{.Name}}' | sort \
    >"${TEMPORARY_ROOT}/volume-after-runtime.txt"
cmp --silent \
    "${TEMPORARY_ROOT}/volume-baseline.txt" \
    "${TEMPORARY_ROOT}/volume-after-runtime.txt" \
    || fail "Named/anonymous volume state berubah selama runtime."

readonly NETWORK_ID="$("${CONTAINER_ENGINE}" network inspect "${NETWORK_NAME}" --format '{{.Id}}')"
readonly DIAGNOSTIC_CONTAINER_ID="$("${CONTAINER_ENGINE}" inspect "${DIAGNOSTIC_CONTAINER}" --format '{{.Id}}')"
readonly CLIENT_CONTAINER_ID="$("${CONTAINER_ENGINE}" inspect "${CLIENT_CONTAINER}" --format '{{.Id}}')"
readonly MAILPIT_CONTAINER_ID="$("${CONTAINER_ENGINE}" inspect "${MAILPIT_CONTAINER}" --format '{{.Id}}')"

printf 'runtime_result=passed network=%s diagnostic=%s client=%s mailpit=%s host_ports=none named_volumes=none\n' \
    "${NETWORK_NAME}" "${DIAGNOSTIC_CONTAINER}" "${CLIENT_CONTAINER}" "${MAILPIT_CONTAINER}"
printf 'resource_ids network=%s diagnostic=%s client=%s mailpit=%s\n' \
    "${NETWORK_ID}" "${DIAGNOSTIC_CONTAINER_ID}" "${CLIENT_CONTAINER_ID}" "${MAILPIT_CONTAINER_ID}"
printf 'cleanup_state=pending_authorization temporary_root=%s images_retained=true\n' \
    "${TEMPORARY_ROOT}"
