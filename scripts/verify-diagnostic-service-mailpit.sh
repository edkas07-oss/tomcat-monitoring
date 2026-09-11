#!/usr/bin/env bash
# Menjalankan disposable TN-013 runtime; cleanup sengaja menjadi approval gate terpisah.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi

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
[[ "${DIAGNOSTIC_IMAGE}" == localhost/tomcat-diagnostic-service@sha256:* ]] \
    || fail "DIAGNOSTIC_IMAGE harus exact local digest reference."

for command_name in cmp podman sort stat; do
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
    podman image exists "${image}" || fail "Image tidak tersedia: ${image}"
done

for container in "${DIAGNOSTIC_CONTAINER}" "${CLIENT_CONTAINER}" "${MAILPIT_CONTAINER}"; do
    podman container exists "${container}" \
        && fail "Exact container sudah tersedia: ${container}"
done
podman network exists "${NETWORK_NAME}" \
    && fail "Exact network sudah tersedia: ${NETWORK_NAME}"

podman volume ls --format '{{.Name}}' | sort \
    >"${TEMPORARY_ROOT}/volume-baseline.txt"

podman network create "${NETWORK_NAME}" >/dev/null

podman run --detach --pull=never \
    --name "${MAILPIT_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    --network-alias mailpit \
    --restart=no \
    --env MP_MAX_MESSAGES=10 \
    "${MAILPIT_IMAGE}" >/dev/null

podman run --detach --pull=never \
    --userns=keep-id \
    --name "${DIAGNOSTIC_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    --network-alias diagnostic-service \
    --restart=no \
    --volume "${TEMPORARY_ROOT}/config/application.json:/run/tomcat-diagnostic/application.json:ro,z" \
    --volume "${TEMPORARY_ROOT}/config/targets.json:/run/tomcat-diagnostic/config/targets.json:ro,z" \
    --volume "${TEMPORARY_ROOT}/secrets/bearer-token:/run/tomcat-diagnostic/secrets/bearer-token:ro,z" \
    --volume "${TEMPORARY_ROOT}/tls/server.crt:/run/tomcat-diagnostic/tls/server.crt:ro,z" \
    --volume "${TEMPORARY_ROOT}/tls/server.key:/run/tomcat-diagnostic/tls/server.key:ro,z" \
    --volume "${TEMPORARY_ROOT}/data:/var/lib/tomcat-diagnostic:z" \
    "${DIAGNOSTIC_IMAGE}" >/dev/null

podman run --detach --pull=never \
    --userns=keep-id \
    --name "${CLIENT_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    --restart=no \
    --volume "${PROJECT_ROOT}/fixtures/diagnostic-service-mailpit:/probe:ro,Z" \
    --volume "${TEMPORARY_ROOT}/tls/server.crt:/runtime/server.crt:ro,z" \
    --volume "${TEMPORARY_ROOT}/data:/runtime/data:ro,z" \
    --workdir /probe \
    "${CLIENT_IMAGE}" \
    node -e 'setInterval(() => {}, 60000)' >/dev/null

podman exec "${CLIENT_CONTAINER}" node runtime-probe.js

podman stop --time 10 "${DIAGNOSTIC_CONTAINER}" >/dev/null
[[ "$(podman inspect "${DIAGNOSTIC_CONTAINER}" --format '{{.State.ExitCode}}')" == "0" ]] \
    || fail "Diagnostic Service tidak exit 0 setelah SIGTERM."
podman exec "${CLIENT_CONTAINER}" node database-probe.js /runtime/data/diagnostic.db
[[ "$(stat -c '%a' "${TEMPORARY_ROOT}/data/diagnostic.db")" == "600" ]] \
    || fail "SQLite database mode tidak sesuai contract."

podman start "${DIAGNOSTIC_CONTAINER}" >/dev/null
podman exec "${CLIENT_CONTAINER}" node reopen-probe.js
podman stop --time 10 "${DIAGNOSTIC_CONTAINER}" >/dev/null
[[ "$(podman inspect "${DIAGNOSTIC_CONTAINER}" --format '{{.State.ExitCode}}')" == "0" ]] \
    || fail "Diagnostic Service tidak exit 0 setelah reopen verification."

podman volume ls --format '{{.Name}}' | sort \
    >"${TEMPORARY_ROOT}/volume-after-runtime.txt"
cmp --silent \
    "${TEMPORARY_ROOT}/volume-baseline.txt" \
    "${TEMPORARY_ROOT}/volume-after-runtime.txt" \
    || fail "Named/anonymous volume state berubah selama runtime."

readonly NETWORK_ID="$(podman network inspect "${NETWORK_NAME}" --format '{{.Id}}')"
readonly DIAGNOSTIC_CONTAINER_ID="$(podman inspect "${DIAGNOSTIC_CONTAINER}" --format '{{.Id}}')"
readonly CLIENT_CONTAINER_ID="$(podman inspect "${CLIENT_CONTAINER}" --format '{{.Id}}')"
readonly MAILPIT_CONTAINER_ID="$(podman inspect "${MAILPIT_CONTAINER}" --format '{{.Id}}')"

printf 'runtime_result=passed network=%s diagnostic=%s client=%s mailpit=%s host_ports=none named_volumes=none\n' \
    "${NETWORK_NAME}" "${DIAGNOSTIC_CONTAINER}" "${CLIENT_CONTAINER}" "${MAILPIT_CONTAINER}"
printf 'resource_ids network=%s diagnostic=%s client=%s mailpit=%s\n' \
    "${NETWORK_ID}" "${DIAGNOSTIC_CONTAINER_ID}" "${CLIENT_CONTAINER_ID}" "${MAILPIT_CONTAINER_ID}"
printf 'cleanup_state=pending_authorization temporary_root=%s images_retained=true\n' \
    "${TEMPORARY_ROOT}"
