#!/usr/bin/env bash
# ==============================================================================
# Tomcat Monitoring Platform — Linux Target Host Bootstrap & Runtime Provisioner
# Architecture Reference: TM-ADR-0026, TM-ADR-0028, TN-017
# Supported Distros: Amazon Linux 2/2023, Ubuntu, Debian, RHEL, CentOS, Rocky, AlmaLinux
# ==============================================================================
# Usage (run locally on target host or via bootstrap-linux-host-remote.sh):
#   sudo bash scripts/bootstrap-linux-host.sh [--engine podman|docker|auto]
# ==============================================================================

set -euo pipefail

TARGET_ENGINE="${1:-auto}"
TARGET_USER="${SUDO_USER:-$(whoami)}"
if [[ "${TARGET_USER}" == "root" && -n "${LOGNAME:-}" && "${LOGNAME}" != "root" ]]; then
    TARGET_USER="${LOGNAME}"
fi

# Colors for formatting
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}==================================================================${NC}"
echo -e "${CYAN}🚀 Tomcat Monitoring — Linux Host Bootstrap & Runtime Provisioner${NC}"
echo -e "${CYAN}==================================================================${NC}"
echo -e "Target User       : ${GREEN}${TARGET_USER}${NC}"
echo -e "Requested Engine  : ${YELLOW}${TARGET_ENGINE}${NC}"
echo -e "OS Release Info   : $(cat /etc/os-release | grep -E "^PRETTY_NAME=" | cut -d= -f2 | tr -d '"')"
echo -e "${CYAN}==================================================================${NC}"

# Detect OS package manager
PKG_MGR=""
if command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
elif command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt-get"
elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR="zypper"
elif command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
else
    echo -e "${RED}❌ Error: Unsupported Linux distribution. No compatible package manager found.${NC}" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 1. Ensure Python 3 is installed (Mandatory for Ansible execution)
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}[1/5] Checking Python 3 Runtime (Ansible Prerequisite)...${NC}"
if command -v python3 >/dev/null 2>&1; then
    echo -e "      ${GREEN}✔ Python 3 is already installed: $(python3 --version)${NC}"
else
    echo -e "      ${YELLOW}Installing Python 3 via ${PKG_MGR}...${NC}"
    case "${PKG_MGR}" in
        dnf|yum)
            ${PKG_MGR} install -y python3
            ;;
        apt-get)
            apt-get update -y && apt-get install -y python3
            ;;
        zypper)
            zypper install -y python3
            ;;
        pacman)
            pacman -Sy --noconfirm python
            ;;
    esac
    echo -e "      ${GREEN}✔ Python 3 successfully installed: $(python3 --version)${NC}"
fi

# ------------------------------------------------------------------------------
# 2. Swap Memory Hardening (Crucial for 1GB RAM instances like AWS t2.micro)
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}[2/5] Checking Memory & Swap Space Allocation...${NC}"
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
TOTAL_SWAP_MB=$(free -m | awk '/^Swap:/{print $2}')
echo -e "      Total Physical RAM : ${TOTAL_RAM_MB} MB"
echo -e "      Total Swap Memory  : ${TOTAL_SWAP_MB} MB"

if [[ ${TOTAL_RAM_MB} -le 2048 && ${TOTAL_SWAP_MB} -lt 1024 ]]; then
    echo -e "      ${YELLOW}Host has <= 2GB RAM and insufficient Swap. Provisioning 2GB Swapfile to prevent OOM...${NC}"
    if [[ ! -f /swapfile ]]; then
        if command -v fallocate >/dev/null 2>&1; then
            fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=128M count=16
        else
            dd if=/dev/zero of=/swapfile bs=128M count=16
        fi
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        if ! grep -q "/swapfile" /etc/fstab; then
            echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
        fi
        # Optimize swappiness for server workloads
        sysctl vm.swappiness=10 >/dev/null 2>&1 || true
        echo -e "      ${GREEN}✔ 2GB Swap successfully created and activated!${NC}"
    else
        swapon /swapfile 2>/dev/null || true
        echo -e "      ${GREEN}✔ /swapfile already exists and is active.${NC}"
    fi
else
    echo -e "      ${GREEN}✔ Memory configuration is sufficient (${TOTAL_RAM_MB} MB RAM, ${TOTAL_SWAP_MB} MB Swap).${NC}"
fi

# ------------------------------------------------------------------------------
# 3. Systemd User Session Lingering (Required for background daemons / Rootless Podman)
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}[3/5] Configuring Systemd User Session Lingering...${NC}"
if command -v loginctl >/dev/null 2>&1 && [[ "${TARGET_USER}" != "root" ]]; then
    loginctl enable-linger "${TARGET_USER}" 2>/dev/null || true
    echo -e "      ${GREEN}✔ Systemd user lingering enabled for '${TARGET_USER}'.${NC}"
else
    echo -e "      ${YELLOW}Skipping lingering (running as root or loginctl not present).${NC}"
fi

# ------------------------------------------------------------------------------
# 4. Container Runtime Detection, Verification & Auto-Installation
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}[4/5] Inspecting & Provisioning Container Runtime...${NC}"

ACTIVE_ENGINE=""

# A. Probe Docker
if command -v docker >/dev/null 2>&1; then
    echo -e "      Detected installed binary: ${CYAN}docker${NC}"
    # Ensure Docker service is running
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker >/dev/null 2>&1 || true
    
    # Add user to docker group if not root
    if [[ "${TARGET_USER}" != "root" ]]; then
        if ! id -nG "${TARGET_USER}" | grep -qw "docker"; then
            groupadd -f docker
            usermod -aG docker "${TARGET_USER}"
            echo -e "      ${YELLOW}Added user '${TARGET_USER}' to 'docker' group.${NC}"
        fi
    fi

    if docker info >/dev/null 2>&1; then
        ACTIVE_ENGINE="docker"
        echo -e "      ${GREEN}✔ Docker Engine is operational: $(docker --version)${NC}"
    fi
fi

# B. Probe Podman
if command -v podman >/dev/null 2>&1; then
    echo -e "      Detected installed binary: ${CYAN}podman${NC}"
    if podman info >/dev/null 2>&1; then
        ACTIVE_ENGINE="${ACTIVE_ENGINE:-podman}"
        echo -e "      ${GREEN}✔ Podman is operational: $(podman --version)${NC}"
    fi
fi

# C. If user explicitly requested a specific engine or no engine was found
if [[ -z "${ACTIVE_ENGINE}" ]] || [[ "${TARGET_ENGINE}" != "auto" && "${ACTIVE_ENGINE}" != "${TARGET_ENGINE}" ]]; then
    ENGINE_TO_INSTALL="${TARGET_ENGINE}"
    if [[ "${ENGINE_TO_INSTALL}" == "auto" ]]; then
        # Default fallback to podman as requested
        ENGINE_TO_INSTALL="podman"
    fi

    echo -e "      ${YELLOW}No operational runtime matched '${TARGET_ENGINE}'. Installing '${ENGINE_TO_INSTALL}'...${NC}"
    
    case "${ENGINE_TO_INSTALL}" in
        podman)
            case "${PKG_MGR}" in
                dnf|yum)
                    ${PKG_MGR} install -y podman
                    ;;
                apt-get)
                    apt-get update -y && apt-get install -y podman
                    ;;
                zypper)
                    zypper install -y podman
                    ;;
                pacman)
                    pacman -Sy --noconfirm podman
                    ;;
            esac
            ACTIVE_ENGINE="podman"
            ;;
        docker)
            case "${PKG_MGR}" in
                dnf|yum)
                    ${PKG_MGR} install -y docker
                    systemctl enable --now docker
                    ;;
                apt-get)
                    apt-get update -y && apt-get install -y docker.io
                    systemctl enable --now docker
                    ;;
                zypper)
                    zypper install -y docker
                    systemctl enable --now docker
                    ;;
                pacman)
                    pacman -Sy --noconfirm docker
                    systemctl enable --now docker
                    ;;
            esac
            if [[ "${TARGET_USER}" != "root" ]]; then
                groupadd -f docker
                usermod -aG docker "${TARGET_USER}"
            fi
            ACTIVE_ENGINE="docker"
            ;;
        *)
            echo -e "${RED}❌ Error: Unknown container engine requested '${ENGINE_TO_INSTALL}'.${NC}" >&2
            exit 1
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# 5. Final Functional Verification
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}[5/5] Performing Final Container Engine Functional Check...${NC}"
if [[ "${ACTIVE_ENGINE}" == "docker" ]]; then
    docker version --format 'Engine: {{.Server.Version}} (OS/Arch: {{.Server.Os}}/{{.Server.Arch}})' || docker version
elif [[ "${ACTIVE_ENGINE}" == "podman" ]]; then
    podman version --format 'Engine: {{.Server.Version}} (OS/Arch: {{.Server.Os}}/{{.Server.Arch}})' || podman version
fi

echo -e "\n${GREEN}==================================================================${NC}"
echo -e "${GREEN}✔ Linux Target Host successfully bootstrapped & ready for deployment!${NC}"
echo -e "  Active Container Engine : ${CYAN}${ACTIVE_ENGINE}${NC}"
echo -e "  Python 3 Version        : ${CYAN}$(python3 --version)${NC}"
echo -e "  Memory Health           : ${CYAN}${TOTAL_RAM_MB} MB RAM / $(free -m | awk '/^Swap:/{print $2}') MB Swap${NC}"
echo -e "${GREEN}==================================================================${NC}"
