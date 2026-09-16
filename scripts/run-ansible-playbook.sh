#!/usr/bin/env bash
# ==============================================================================
# Seamless Ansible Playbook Runner (Host or Containerized Ansible Controller)
# Architecture Reference: TM-ADR-0025
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi
# shellcheck source=scripts/container-runtime-helper.sh
source "${SCRIPT_DIR}/container-runtime-helper.sh"

ANSIBLE_IMAGE="localhost/ansible-controller:1.0"
if [[ $# -eq 0 ]]; then
    PLAYBOOK_ARGS=("deploy-stack.yml")
else
    PLAYBOOK_ARGS=("$@")
fi

# Determine execution mode: local binary vs containerized controller
if command -v ansible-playbook >/dev/null 2>&1; then
    echo "=== Executing Ansible Playbook via Local Binary ==="
    cd "${PROJECT_ROOT}"
    ansible-playbook "${PLAYBOOK_ARGS[@]}"
else
    echo "=== Executing Ansible Playbook via Containerized Ansible Controller (${ANSIBLE_IMAGE}) ==="
    image_exists "${ANSIBLE_IMAGE}" || {
        echo "Error: Ansible Controller image '${ANSIBLE_IMAGE}' not found. Please build it via ansible-controller/scripts/build.sh" >&2
        exit 1
    }

    USER_UID="$(id -u)"
    USER_GID="$(id -g)"
    RUNTIME_DIR="/run/user/${USER_UID}"
    vol_z="$(get_volume_flag "z")"
    userns_flag="$(get_userns_flag)"

    CONTAINER_ARGS=(
        --rm -i
        --network host
        --volume "${HOME}:${HOME}${vol_z}"
        --volume "${PROJECT_ROOT}:/ansible${vol_z}"
        --workdir "${PROJECT_ROOT}"
        --env "HOME=${HOME}"
        --env "ANSIBLE_CONFIG=${PROJECT_ROOT}/ansible.cfg"
        --env "CONTAINER_ENGINE=${CONTAINER_ENGINE}"
    )

    if [[ -n "${ANSIBLE_SSH_KEY_FILE:-}" ]]; then
        if [[ -f "${ANSIBLE_SSH_KEY_FILE}" ]]; then
            CONTAINER_ARGS+=(--volume "${ANSIBLE_SSH_KEY_FILE}:${ANSIBLE_SSH_KEY_FILE}${vol_z}")
        fi
        CONTAINER_ARGS+=(--env "ANSIBLE_SSH_KEY_FILE=${ANSIBLE_SSH_KEY_FILE}")
    fi
    if [[ -n "${ANSIBLE_PRIVATE_KEY_FILE:-}" ]]; then
        if [[ -f "${ANSIBLE_PRIVATE_KEY_FILE}" ]]; then
            CONTAINER_ARGS+=(--volume "${ANSIBLE_PRIVATE_KEY_FILE}:${ANSIBLE_PRIVATE_KEY_FILE}${vol_z}")
        fi
        CONTAINER_ARGS+=(--env "ANSIBLE_PRIVATE_KEY_FILE=${ANSIBLE_PRIVATE_KEY_FILE}")
    fi

    if [[ -n "${userns_flag}" ]]; then
        CONTAINER_ARGS=("${userns_flag}" "${CONTAINER_ARGS[@]}")
    fi

    if [[ -d "${RUNTIME_DIR}" ]]; then
        CONTAINER_ARGS+=(
            --volume "${RUNTIME_DIR}:${RUNTIME_DIR}${vol_z}"
            --env "XDG_RUNTIME_DIR=${RUNTIME_DIR}"
            --env "DBUS_SESSION_BUS_ADDRESS=unix:path=${RUNTIME_DIR}/bus"
        )
        if [[ -S "${RUNTIME_DIR}/podman/podman.sock" ]]; then
            CONTAINER_ARGS+=(
                --volume "${RUNTIME_DIR}/podman/podman.sock:/run/podman/podman.sock${vol_z}"
                --env "CONTAINER_HOST=unix:///run/podman/podman.sock"
            )
        fi
    fi

    "${CONTAINER_ENGINE}" run "${CONTAINER_ARGS[@]}" \
        "${ANSIBLE_IMAGE}" \
        ansible-playbook "${PLAYBOOK_ARGS[@]}"
fi
