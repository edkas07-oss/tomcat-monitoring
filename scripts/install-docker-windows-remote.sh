#!/usr/bin/env bash
# ==============================================================================
# Tomcat Monitoring Platform — Remote Windows Docker Engine Installer via SSH
# Architecture Reference: TM-ADR-0026, TN-018, TN-019
# ==============================================================================
# Usage:
#   ./scripts/install-docker-windows-remote.sh <TARGET_IP_OR_HOST> [-i /path/to/key.pem] [-u Administrator]
#
# Examples:
#   ./scripts/install-docker-windows-remote.sh 184.194.25.77
#   ./scripts/install-docker-windows-remote.sh 184.194.25.77 -i ~/Downloads/tomcat-monitoring-aws-key.pem
#   ./scripts/install-docker-windows-remote.sh 54.242.205.212 -u Administrator
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default settings
DEFAULT_SSH_KEY="${ANSIBLE_SSH_KEY_FILE:-${HOME}/.ssh/tomcat-monitoring-aws-key.pem}"
SSH_USER="Administrator"
SSH_KEY=""
TARGET_HOST=""
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

show_help() {
    cat <<EOF
Usage: $(basename "$0") <TARGET_IP_OR_HOST> [OPTIONS]

Installs and initializes Docker Engine (Windows Containers) on a remote Windows Server via SSH.
Automatically handles Windows reboot if the 'Containers' feature requires kernel initialization.

Arguments:
  TARGET_IP_OR_HOST        IP address or hostname of the remote Windows Server

Options:
  -i, --key PATH           Path to SSH private key (default: ~/.ssh/tomcat-monitoring-aws-key.pem)
  -u, --user USERNAME      SSH username on Windows host (default: Administrator)
  -h, --help               Show this help message and exit

Examples:
  # Deploy to AWS EC2 Windows instance
  $(basename "$0") 184.194.25.77 -i ~/Downloads/tomcat-monitoring-aws-key.pem

  # Deploy with default key in ~/.ssh
  $(basename "$0") 3.210.194.165

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
        -*)
            echo "Error: Unknown option '$1'" >&2
            show_help
            exit 1
            ;;
        *)
            if [[ -z "${TARGET_HOST}" ]]; then
                TARGET_HOST="$1"
                shift
            else
                echo "Error: Unexpected argument '$1'" >&2
                show_help
                exit 1
            fi
            ;;
    esac
done

if [[ -z "${TARGET_HOST}" ]]; then
    echo "Error: TARGET_IP_OR_HOST is required." >&2
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
        echo "Error: No SSH private key found. Specify one via -i <key_path>." >&2
        exit 1
    fi
fi

INSTALLER_PS1="${REPO_ROOT}/scripts/install-docker-windows.ps1"
if [[ ! -f "${INSTALLER_PS1}" ]]; then
    echo "Error: Installer script '${INSTALLER_PS1}' not found." >&2
    exit 1
fi

echo "=================================================================="
echo "🚀 Remote Docker Windows Container Provisioner via SSH"
echo "=================================================================="
echo "Target Host : ${TARGET_HOST}"
echo "SSH User    : ${SSH_USER}"
echo "SSH Key     : ${SSH_KEY}"
echo "Installer   : $(basename "${INSTALLER_PS1}")"
echo "=================================================================="

# 1. Test SSH Connectivity
echo "[1/4] Testing SSH connectivity to ${SSH_USER}@${TARGET_HOST}..."
if ! ssh -i "${SSH_KEY}" ${SSH_OPTS} -o ConnectTimeout=10 "${SSH_USER}@${TARGET_HOST}" "whoami" >/dev/null 2>&1; then
    echo "❌ Error: Unable to authenticate via SSH to ${SSH_USER}@${TARGET_HOST}." >&2
    echo "   Ensure OpenSSH is running and authorized keys are configured." >&2
    exit 1
fi
echo "      SSH Authentication OK."

# 2. Upload installer script via SCP
REMOTE_TEMP_PATH='C:\Windows\Temp\install-docker-windows.ps1'
echo "[2/4] Uploading installer script to remote host (${REMOTE_TEMP_PATH})..."
scp -i "${SSH_KEY}" ${SSH_OPTS} "${INSTALLER_PS1}" "${SSH_USER}@${TARGET_HOST}:${REMOTE_TEMP_PATH}"
echo "      Upload completed."

# 3. Execute installer script remotely via PowerShell
echo "[3/4] Executing Docker installation script on Windows target..."
set +e
ssh -i "${SSH_KEY}" ${SSH_OPTS} "${SSH_USER}@${TARGET_HOST}" \
    "powershell.exe -ExecutionPolicy Bypass -NoProfile -File ${REMOTE_TEMP_PATH}"
set -e

# Verify if Docker Engine is alive and responding
echo "      Checking Docker Engine readiness..."
if ! ssh -i "${SSH_KEY}" ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${TARGET_HOST}" "docker version" >/dev/null 2>&1; then
    echo ""
    echo "🔄 [Reboot / Recovery in Progress] Docker is not yet active (Storage driver 'windowsfilter' requires kernel initialization)."
    echo "   Ensuring host reboot is initiated on ${TARGET_HOST}..."
    
    # Send reboot command if host is still responsive
    ssh -i "${SSH_KEY}" ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${TARGET_HOST}" "Restart-Computer -Force" 2>/dev/null || true
    
    echo "   Waiting 25s for host shutdown..."
    sleep 25
    
    # Poll SSH until back online
    echo "   Waiting for SSH to become available on ${TARGET_HOST}..."
    MAX_WAIT=240
    ELAPSED=25
    while ! ssh -i "${SSH_KEY}" ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${TARGET_HOST}" "whoami" >/dev/null 2>&1; do
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        if [[ ${ELAPSED} -ge ${MAX_WAIT} ]]; then
            echo "❌ Error: Host ${TARGET_HOST} did not come back online within ${MAX_WAIT}s." >&2
            exit 1
        fi
        echo "   ... waiting for host (${ELAPSED}s / ${MAX_WAIT}s)"
    done
    echo "✔ Remote host is back online! Resuming Docker installation post-reboot..."
    
    # Re-run installation script post-reboot
    ssh -i "${SSH_KEY}" ${SSH_OPTS} "${SSH_USER}@${TARGET_HOST}" \
        "powershell.exe -ExecutionPolicy Bypass -NoProfile -File ${REMOTE_TEMP_PATH}"
fi

# 4. Verify Docker Engine Status
echo "[4/4] Verifying Docker Engine on remote Windows host..."
ssh -i "${SSH_KEY}" ${SSH_OPTS} "${SSH_USER}@${TARGET_HOST}" "docker version"

echo "=================================================================="
echo "✔ Docker Windows Containers successfully installed and active on ${TARGET_HOST}!"
echo "=================================================================="
