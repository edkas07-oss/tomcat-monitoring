#!/usr/bin/env bash
# ==============================================================================
# Validation script for Ansible Playbooks, Roles, and Inventories
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# shellcheck source=scripts/container-runtime-helper.sh
source "${SCRIPT_DIR}/container-runtime-helper.sh"

ANSIBLE_IMAGE="localhost/ansible-controller:1.0"

echo "=== Validating Ansible Playbooks and Roles Layout ==="

# 1. Check required Ansible files
REQUIRED_ANSIBLE_FILES=(
    "ansible.cfg"
    "inventories/lab.ini"
    "inventories/enterprise-matrix.ini.example"
    "inventories/aws-staging.ini.example"
    "inventories/aws-production.ini.example"
    "inventories/production.ini.example"
    "inventories/group_vars/all.yml"
    "roles/role_host_prep/meta/main.yml"
    "roles/role_host_prep/defaults/main.yml"
    "roles/role_host_prep/tasks/main.yml"
    "roles/role_host_prep/tasks/linux/main.yml"
    "roles/role_host_prep/tasks/linux/directories.yml"
    "roles/role_host_prep/tasks/linux/secrets_and_tls.yml"
    "roles/role_host_prep/tasks/linux/network_and_volumes.yml"
    "roles/role_host_prep/tasks/windows/main.yml"
    "roles/role_host_prep/tasks/windows/directories.yml"
    "roles/role_host_prep/tasks/windows/secrets_and_tls.yml"
    "roles/role_host_prep/tasks/windows/network_and_volumes.yml"
    "roles/role_event_collector/meta/main.yml"
    "roles/role_event_collector/defaults/main.yml"
    "roles/role_event_collector/templates/tm-agent.service.j2"
    "roles/role_event_collector/tasks/main.yml"
    "roles/role_event_collector/tasks/linux/main.yml"
    "roles/role_event_collector/tasks/windows/main.yml"
    "roles/role_container_stack/meta/main.yml"
    "roles/role_container_stack/defaults/main.yml"
    "roles/role_container_stack/tasks/main.yml"
    "roles/role_container_stack/tasks/linux/main.yml"
    "roles/role_container_stack/tasks/linux/pull_images.yml"
    "roles/role_container_stack/tasks/linux/mailpit.yml"
    "roles/role_container_stack/tasks/linux/postfix.yml"
    "roles/role_container_stack/tasks/linux/tomcat.yml"
    "roles/role_container_stack/tasks/linux/prometheus.yml"
    "roles/role_container_stack/tasks/linux/alertmanager.yml"
    "roles/role_container_stack/tasks/linux/diagnostic_service.yml"
    "roles/role_container_stack/tasks/linux/verify_readiness.yml"
    "roles/role_container_stack/tasks/windows/main.yml"
    "roles/role_container_stack/tasks/windows/build_images.yml"
    "roles/role_container_stack/tasks/windows/mailpit.yml"
    "roles/role_container_stack/tasks/windows/prometheus.yml"
    "roles/role_container_stack/tasks/windows/alertmanager.yml"
    "roles/role_container_stack/tasks/windows/diagnostic_service.yml"
    "roles/role_container_stack/tasks/windows/verify_readiness.yml"
    "deploy-stack.yml"
    "provision-fleet.yml"

)

for f in "${REQUIRED_ANSIBLE_FILES[@]}"; do
    if [[ ! -f "${PROJECT_ROOT}/${f}" ]]; then
        echo "Error: Required Ansible file missing: ${f}" >&2
        exit 1
    fi
done
echo "1. All required Ansible files and roles structure present."

# 2. Syntax check via Ansible runner / Controller
echo "2. Running Ansible syntax check..."
"${SCRIPT_DIR}/run-ansible-playbook.sh" deploy-stack.yml -i inventories/lab.ini --syntax-check
"${SCRIPT_DIR}/run-ansible-playbook.sh" provision-fleet.yml -i inventories/lab.ini --syntax-check

echo "3. Ansible validation successful."
