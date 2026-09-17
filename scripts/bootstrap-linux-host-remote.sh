#!/usr/bin/env bash
# ==============================================================================
# Tomcat Monitoring Platform — Remote Linux Host Bootstrap via SSH
# Architecture Reference: TM-ADR-0026, TM-ADR-0028, TN-017
# ==============================================================================
# Usage:
#   ./scripts/bootstrap-linux-host-remote.sh <TARGET_IP_OR_HOST> [OPTIONS]
#
# Examples:
#   ./scripts/bootstrap-linux-host-remote.sh 98.81.129.144 -i ~/Downloads/tomcat-monitoring-aws-key.pem
#   ./scripts/bootstrap-linux-host-remote.sh 184.194.25.77 -u ec2-user --engine podman
#   ./scripts/bootstrap-linux-host-remote.sh 54.242.205.212 -u ubuntu --engine docker
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default settings
DEFAULT_SSH_KEY="${ANSIBLE_SSH_KEY_FILE:-${HOME}/.ssh/tomcat-monitoring-aws-key.pem}"
SSH_USER=""
SSH_KEY=""
TARGET_HOST=""
TARGET_ENGINE="auto"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

show_help() {
    cat <<EOF
Usage: $(basename "$0") <TARGET_IP_OR_HOST> [OPTIONS]

Connects to a remote Linux server via SSH, inspects container runtimes (Podman/Docker),
provisions Podman (default) if no runtime exists, hardens memory with 2GB swap, installs
Python 3 (Ansible requirement), and configures systemd lingering.

Arguments:
  TARGET_IP_OR_HOST        IP address or hostname of the remote Linux Server

Options:
  -i, --key PATH           Path to SSH private key (default: ~/.ssh/tomcat-monitoring-aws-key.pem)
  -u, --user USERNAME      SSH username on Linux host (default: auto-detect ec2-user/ubuntu/root)
  -e, --engine ENGINE      Target runtime preference: auto, podman, docker (default: auto)
  -h, --help               Show this help message and exit

Examples:
  # Deploy with auto-detected user and SSH key
  $(basename "$0") 98.81.129.144 -i ~/Downloads/tomcat-monitoring-aws-key.pem

  # Explicit user & install podman if none exists
  $(basename "$0") 54.242.205.212 -u ec2-user --engine podman

EOF
}

# Parse command-line arguments
if [[ $# -eq 0 ]]; then
    show_help
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -i|--key)
            SSH_KEY="$2"
            shift 2
            ;;
        -u|--user)
            SSH_USER="$2"
            shift 2
            ;;
        -e|--engine)
            TARGET_ENGINE="$2"
            shift 2
            ;;
        -*)
            echo -e "${RED}Error: Unknown option '$1'${NC}" >&2
            show_help
            exit 1
            ;;
        *)
            if [[ -z "${TARGET_HOST}" ]]; then
                TARGET_HOST="$1"
                shift
            else
                echo -e "${RED}Error: Unexpected argument '$1'${NC}" >&2
                show_help
                exit 1
            fi
            ;;
    esac
done

if [[ -z "${TARGET_HOST}" ]]; then
    echo -e "${RED}Error: TARGET_IP_OR_HOST is required.${NC}" >&2
    show_help
    exit 1
fi

# Fallback SSH key resolution
if [[ -z "${SSH_KEY}" ]]; then
    if [[ -f "${DEFAULT_SSH_KEY}" ]]; then
        SSH_KEY="${DEFAULT_SSH_KEY}"
    elif [[ -f "${HOME}/Downloads/tomcat-monitoring-aws-key.pem" ]]; then
        SSH_KEY="${HOME}/Downloads/tomcat-monitoring-aws-key.pem"
    elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
        SSH_KEY="${HOME}/.ssh/id_rsa"
    elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
        SSH_KEY="${HOME}/.ssh/id_ed25519"
    else
        echo -e "${RED}Error: No SSH private key found. Specify one via -i <key_path>.${NC}" >&2
        exit 1
    fi
fi

BOOTSTRAP_SH="${REPO_ROOT}/scripts/bootstrap-linux-host.sh"
if [[ ! -f "${BOOTSTRAP_SH}" ]]; then
    echo -e "${RED}Error: Bootstrap script '${BOOTSTRAP_SH}' not found.${NC}" >&2
    exit 1
fi

# Auto-detect SSH user if not provided
if [[ -z "${SSH_USER}" ]]; then
    echo "🔍 Auto-detecting SSH username for ${TARGET_HOST}..."
    for CANDIDATE_USER in "ec2-user" "ubuntu" "rocky" "almalinux" "centos" "admin" "root"; do
        if ssh -i "${SSH_KEY}" ${SSH_OPTS} -o ConnectTimeout=3 "${CANDIDATE_USER}@${TARGET_HOST}" "whoami" >/dev/null 2>&1; then
            SSH_USER="${CANDIDATE_USER}"
            break
        fi
    done
    if [[ -z "${SSH_USER}" ]]; then
        SSH_USER="ec2-user" # fallback
    fi
fi

echo -e "${CYAN}==================================================================${NC}"
echo -e "${CYAN}🚀 Remote Linux Host Bootstrap & Runtime Provisioner via SSH${NC}"
echo -e "${CYAN}==================================================================${NC}"
echo -e "Target Host : ${GREEN}${TARGET_HOST}${NC}"
echo -e "SSH User    : ${GREEN}${SSH_USER}${NC}"
echo -e "SSH Key     : ${YELLOW}${SSH_KEY}${NC}"
echo -e "Engine Mode : ${CYAN}${TARGET_ENGINE}${NC}"
echo -e "${CYAN}==================================================================${NC}"

# 1. Test SSH Connectivity
echo -e "\n[1/4] Testing SSH connectivity to ${SSH_USER}@${TARGET_HOST}..."
if ! ssh -i "${SSH_KEY}" ${SSH_OPTS} -o ConnectTimeout=10 "${SSH_USER}@${TARGET_HOST}" "whoami" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Unable to authenticate via SSH to ${SSH_USER}@${TARGET_HOST}.${NC}" >&2
    echo "   Verify target IP address, security group / firewall rules, and SSH key permissions." >&2
    exit 1
fi
echo -e "      ${GREEN}SSH Authentication OK (${SSH_USER}@${TARGET_HOST}).${NC}"

# 2. Upload bootstrap script via SCP
REMOTE_TEMP_PATH="/tmp/bootstrap-linux-host.sh"
echo -e "\n[2/4] Uploading bootstrap script to remote host (${REMOTE_TEMP_PATH})..."
scp -i "${SSH_KEY}" ${SSH_OPTS} "${BOOTSTRAP_SH}" "${SSH_USER}@${TARGET_HOST}:${REMOTE_TEMP_PATH}"
echo -e "      ${GREEN}Upload completed.${NC}"

# 3. Execute bootstrap script remotely
echo -e "\n[3/4] Executing bootstrap script with sudo on remote Linux target..."
ssh -i "${SSH_KEY}" ${SSH_OPTS} "${SSH_USER}@${TARGET_HOST}" \
    "sudo bash ${REMOTE_TEMP_PATH} ${TARGET_ENGINE} && rm -f ${REMOTE_TEMP_PATH}"

# 4. Verify Final State from User Perspective (without sudo)
echo -e "\n[4/4] Verifying Non-Sudo Container & Python Execution for '${SSH_USER}'..."
ssh -i "${SSH_KEY}" ${SSH_OPTS} "${SSH_USER}@${TARGET_HOST}" bash -s << 'EOF'
set -e
echo "--- Remote Host Verification ---"
echo "Host OS   : $(cat /etc/os-release | grep -E '^PRETTY_NAME=' | cut -d= -f2 | tr -d '\"')"
echo "Python 3  : $(python3 --version 2>&1 || echo 'NOT FOUND')"

if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    echo "Container : $(podman --version) [OPERATIONAL]"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "Container : $(docker --version) [OPERATIONAL]"
else
    echo "Container : FAILED TO RUN WITHOUT SUDO (User may need session reload for group changes)"
fi
echo "Memory    : $(free -h | awk '/^Mem:/{print "RAM "$2} /^Swap:/{print "Swap "$2}')"
echo "--------------------------------"
EOF

echo -e "\n${GREEN}==================================================================${NC}"
echo -e "${GREEN}✔ Linux host ${TARGET_HOST} is fully bootstrapped and ready for Ansible!${NC}"
echo -e "${GREEN}==================================================================${NC}"
