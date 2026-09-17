#!/usr/bin/env bash
# ==============================================================================
# Tomcat Monitoring Platform — Linux Target Host Bootstrap & Runtime Provisioner
# Architecture Reference: TM-ADR-0026, TM-ADR-0028, TN-017
# Supported Distros: Amazon Linux 2/2023, Ubuntu, Debian, RHEL, CentOS, Rocky, AlmaLinux
# ==============================================================================
# Logic:
#   1. Check if any container runtime (Docker/Podman) exists on the host.
#   2. If a runtime exists -> Verify health & socket -> DONE (NO INSTALLATION).
#   3. If NO runtime exists -> Install default runtime (Podman) -> Verify.
# ==============================================================================

set -euo pipefail

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
echo -e "${CYAN}🚀 Tomcat Monitoring — Linux Host Runtime Verifier & Provisioner${NC}"
echo -e "${CYAN}==================================================================${NC}"
echo -e "Target User     : ${GREEN}${TARGET_USER}${NC}"
echo -e "OS Distribution : $(cat /etc/os-release | grep -E "^PRETTY_NAME=" | cut -d= -f2 | tr -d '"')"
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
# 1. Check & Ensure Python 3 (Ansible Requirement)
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}[1/4] Checking Python 3 Runtime (Ansible Prerequisite)...${NC}"
if command -v python3 >/dev/null 2>&1; then
    echo -e "      ${GREEN}✔ Python 3 is present: $(python3 --version)${NC}"
else
    echo -e "      ${YELLOW}Python 3 not found. Installing via ${PKG_MGR}...${NC}"
    case "${PKG_MGR}" in
        dnf|yum)   ${PKG_MGR} install -y python3 ;;
        apt-get)   apt-get update -y && apt-get install -y python3 ;;
        zypper)    zypper install -y python3 ;;
        pacman)    pacman -Sy --noconfirm python ;;
    esac
    echo -e "      ${GREEN}✔ Python 3 installed: $(python3 --version)${NC}"
fi

# ------------------------------------------------------------------------------
# 2. Check Memory & Swap Hardening (Prevents OOM on 1GB RAM / t2.micro)
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}[2/4] Checking Memory & Swap Space Allocation...${NC}"
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
TOTAL_SWAP_MB=$(free -m | awk '/^Swap:/{print $2}')

if [[ ${TOTAL_RAM_MB} -le 2048 && ${TOTAL_SWAP_MB} -lt 1024 ]]; then
    echo -e "      ${YELLOW}Low RAM detected (${TOTAL_RAM_MB} MB) without adequate Swap. Provisioning 2GB /swapfile...${NC}"
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
        sysctl vm.swappiness=10 >/dev/null 2>&1 || true
        echo -e "      ${GREEN}✔ 2GB Swapfile activated.${NC}"
    else
        swapon /swapfile 2>/dev/null || true
        echo -e "      ${GREEN}✔ Existing /swapfile activated.${NC}"
    fi
else
    echo -e "      ${GREEN}✔ Memory is healthy: ${TOTAL_RAM_MB} MB RAM, ${TOTAL_SWAP_MB} MB Swap.${NC}"
fi

# ------------------------------------------------------------------------------
# 3. Check & Enable Systemd User Session Lingering
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}[3/4] Checking Systemd User Session Lingering...${NC}"
if command -v loginctl >/dev/null 2>&1 && [[ "${TARGET_USER}" != "root" ]]; then
    loginctl enable-linger "${TARGET_USER}" 2>/dev/null || true
    echo -e "      ${GREEN}✔ Systemd user lingering enabled for user '${TARGET_USER}'.${NC}"
else
    echo -e "      ${GREEN}✔ Systemd user lingering check passed.${NC}"
fi

# ------------------------------------------------------------------------------
# 4. Check Container Runtime -> If Found: Verify & Done. If None: Install Podman.
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}[4/4] Checking Container Runtime Status...${NC}"

ACTIVE_ENGINE=""

# Step A: Check if Docker is installed & operational
if command -v docker >/dev/null 2>&1; then
    echo -e "      Found existing ${CYAN}Docker${NC} binary. Verifying daemon..."
    systemctl enable --now docker >/dev/null 2>&1 || true
    
    # Ensure target user belongs to docker group
    if [[ "${TARGET_USER}" != "root" ]]; then
        if ! id -nG "${TARGET_USER}" | grep -qw "docker"; then
            groupadd -f docker
            usermod -aG docker "${TARGET_USER}"
            echo -e "      ${YELLOW}Configured '${TARGET_USER}' into 'docker' group.${NC}"
        fi
    fi

    if docker info >/dev/null 2>&1; then
        ACTIVE_ENGINE="docker"
        echo -e "      ${GREEN}✔ Existing Docker Engine is healthy and operational! ($(docker --version))${NC}"
        echo -e "      ${GREEN}✔ Verification passed. No runtime installation needed.${NC}"
    else
        echo -e "      ${YELLOW}Docker binary is present but daemon failed to start.${NC}"
    fi
fi

# Step B: Check if Podman is installed & operational (if Docker not already validated)
if [[ -z "${ACTIVE_ENGINE}" ]] && command -v podman >/dev/null 2>&1; then
    echo -e "      Found existing ${CYAN}Podman${NC} binary. Verifying runtime..."
    if podman info >/dev/null 2>&1; then
        ACTIVE_ENGINE="podman"
        echo -e "      ${GREEN}✔ Existing Podman runtime is healthy and operational! ($(podman --version))${NC}"
        echo -e "      ${GREEN}✔ Verification passed. No runtime installation needed.${NC}"
    fi
fi

# Step C: If NO container runtime exists at all -> Install default runtime (Podman)
if [[ -z "${ACTIVE_ENGINE}" ]]; then
    echo -e "      ${YELLOW}⚠️ No operational container runtime found on this server.${NC}"
    echo -e "      ${YELLOW}Installing default container runtime: Podman...${NC}"

    case "${PKG_MGR}" in
        dnf|yum)   ${PKG_MGR} install -y podman ;;
        apt-get)   apt-get update -y && apt-get install -y podman ;;
        zypper)    zypper install -y podman ;;
        pacman)    pacman -Sy --noconfirm podman ;;
    esac

    # Verify newly installed Podman
    if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
        ACTIVE_ENGINE="podman"
        echo -e "      ${GREEN}✔ Podman successfully installed and verified: $(podman --version)${NC}"
    else
        echo -e "${RED}❌ Error: Podman installation completed but runtime verification failed.${NC}" >&2
        exit 1
    fi
fi

echo -e "\n${GREEN}==================================================================${NC}"
echo -e "${GREEN}✔ Linux Target Host verification complete! Ready for Ansible deployment.${NC}"
echo -e "  Active Container Runtime : ${CYAN}${ACTIVE_ENGINE}${NC}"
echo -e "  Python 3 Version         : ${CYAN}$(python3 --version)${NC}"
echo -e "  Memory & Swap Status     : ${CYAN}${TOTAL_RAM_MB} MB RAM / $(free -m | awk '/^Swap:/{print $2}') MB Swap${NC}"
echo -e "${GREEN}==================================================================${NC}"
