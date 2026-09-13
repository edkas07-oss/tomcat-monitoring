#!/bin/bash
###############################################################################
# Container Runtime Abstraction Helper
# Provides dynamic detection of container engine (podman / docker),
# universal lifecycle assertions, and SELinux volume relabeling guards.
###############################################################################
set -euo pipefail

detect_container_engine() {
    if [[ -n "${CONTAINER_ENGINE:-}" ]]; then
        if command -v "${CONTAINER_ENGINE}" >/dev/null 2>&1; then
            echo "${CONTAINER_ENGINE}"
            return 0
        fi
        echo "Error: Specified CONTAINER_ENGINE '${CONTAINER_ENGINE}' is not available in PATH." >&2
        return 1
    fi

    if command -v podman >/dev/null 2>&1; then
        echo "podman"
    elif command -v docker >/dev/null 2>&1; then
        echo "docker"
    else
        echo "Error: Neither podman nor docker CLI was found in PATH." >&2
        return 1
    fi
}

CONTAINER_ENGINE="$(detect_container_engine 2>/dev/null || echo "")"
export CONTAINER_ENGINE

container_exists() {
    local container_name="$1"
    if [[ "${CONTAINER_ENGINE}" == "podman" ]]; then
        podman container exists "${container_name}" 2>/dev/null
    elif [[ "${CONTAINER_ENGINE}" == "docker" ]]; then
        docker container inspect "${container_name}" >/dev/null 2>&1
    else
        return 1
    fi
}

image_exists() {
    local image_name="$1"
    if [[ "${CONTAINER_ENGINE}" == "podman" ]]; then
        podman image exists "${image_name}" 2>/dev/null
    elif [[ "${CONTAINER_ENGINE}" == "docker" ]]; then
        docker image inspect "${image_name}" >/dev/null 2>&1
    else
        return 1
    fi
}

volume_exists() {
    local vol_name="$1"
    if [[ "${CONTAINER_ENGINE}" == "podman" ]]; then
        podman volume exists "${vol_name}" 2>/dev/null
    elif [[ "${CONTAINER_ENGINE}" == "docker" ]]; then
        docker volume inspect "${vol_name}" >/dev/null 2>&1
    else
        return 1
    fi
}

network_exists() {
    local net_name="$1"
    if [[ "${CONTAINER_ENGINE}" == "podman" ]]; then
        podman network exists "${net_name}" 2>/dev/null
    elif [[ "${CONTAINER_ENGINE}" == "docker" ]]; then
        docker network inspect "${net_name}" >/dev/null 2>&1
    else
        return 1
    fi
}

get_volume_flag() {
    local mode="${1:-}"
    local selinux_enabled=false

    if command -v getenforce >/dev/null 2>&1; then
        local enforce_mode
        enforce_mode="$(getenforce 2>/dev/null || echo "Disabled")"
        if [[ "${enforce_mode}" == "Enforcing" || "${enforce_mode}" == "Permissive" ]]; then
            selinux_enabled=true
        fi
    fi

    if [[ "${CONTAINER_ENGINE}" == "podman" && "${selinux_enabled}" == "true" ]]; then
        case "${mode}" in
            "z"|"shared") echo ":z" ;;
            "Z"|"private") echo ":Z" ;;
            "ro,z"|"ro_shared") echo ":ro,z" ;;
            "ro,Z"|"ro_private") echo ":ro,Z" ;;
            "ro") echo ":ro" ;;
            *) echo "" ;;
        esac
    else
        case "${mode}" in
            "ro,z"|"ro_shared"|"ro,Z"|"ro_private"|"ro") echo ":ro" ;;
            *) echo "" ;;
        esac
    fi
}

get_userns_flag() {
    if [[ "${CONTAINER_ENGINE}" == "podman" ]]; then
        echo "--userns=keep-id"
    else
        echo ""
    fi
}
