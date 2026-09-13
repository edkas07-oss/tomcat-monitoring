#!/bin/bash
###############################################################################
#
# Project : Tomcat Monitoring
# File    : scripts/registry-login-helper.sh
#
# Tujuan
# -------
# Melakukan login terisolasi ke Enterprise Container Registry (Harbor/Nexus/Quay)
# dengan opsi --authfile khusus tanpa mencemari kredensial global host.
#
# Penggunaan
# ----------
# ./scripts/registry-login-helper.sh login <registry_url> <username> <password> [auth_file] [tls_verify]
# ./scripts/registry-login-helper.sh logout [registry_url] [auth_file]
#
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/container-runtime-helper.sh
source "${SCRIPT_DIR}/container-runtime-helper.sh"

login_registry() {
    local registry_url="${1:-}"
    local username="${2:-}"
    local password="${3:-}"
    local auth_file="${4:-}"
    local tls_verify="${5:-true}"

    if [[ -z "${registry_url}" ]]; then
        echo "Error: Registry URL tidak boleh kosong." >&2
        return 1
    fi

    local login_args=()
    if [[ "${CONTAINER_ENGINE}" == "podman" ]]; then
        if [[ -n "${auth_file}" ]]; then
            login_args+=(--authfile "${auth_file}")
        fi
        if [[ "${tls_verify}" == "false" ]]; then
            login_args+=(--tls-verify=false)
        elif [[ "${tls_verify}" != "true" && -f "${tls_verify}" ]]; then
            login_args+=(--cert-dir "$(dirname "${tls_verify}")")
        fi
    fi

    if [[ -n "${username}" && -n "${password}" ]]; then
        echo "${password}" | "${CONTAINER_ENGINE}" login "${login_args[@]}" -u "${username}" --password-stdin "${registry_url}"
    else
        echo "Login helper: Parameter autentikasi tidak lengkap atau mode otentikasi eksternal aktif."
    fi
}

logout_registry() {
    local registry_url="${1:-}"
    local auth_file="${2:-}"

    local logout_args=()
    if [[ "${CONTAINER_ENGINE}" == "podman" && -n "${auth_file}" ]]; then
        logout_args+=(--authfile "${auth_file}")
    fi

    if [[ -n "${registry_url}" ]]; then
        "${CONTAINER_ENGINE}" logout "${logout_args[@]}" "${registry_url}" 2>/dev/null || true
    fi

    if [[ -n "${auth_file}" && -f "${auth_file}" && "${auth_file}" == /tmp/* ]]; then
        rm -f "${auth_file}"
    fi
}

main() {
    local action="${1:-help}"
    shift || true

    case "${action}" in
        login)
            login_registry "$@"
            ;;
        logout)
            logout_registry "$@"
            ;;
        *)
            echo "Usage: $0 {login|logout} [args...]" >&2
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
