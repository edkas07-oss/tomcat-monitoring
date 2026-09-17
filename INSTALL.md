# 📦 Installation & Deployment Guide — Tomcat Monitoring Platform

[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Windows%20Server%20%28Docker%20NanoServer%29-blue.svg)](inventories/README.md)
[![Ansible](https://img.shields.io/badge/Ansible-2.16%2B%20%28Dual--Execution%29-red.svg)](roles/README.md)
[![Container Engine](https://img.shields.io/badge/Container%20Engine-Podman%20%7C%20Docker-orange.svg)](scripts/container-runtime-helper.sh)
[![Registry](https://img.shields.io/badge/Registry-Harbor%20%7C%20Nexus%20%7C%20ECR%20%7C%20Quay-blueviolet.svg)](scripts/registry-login-helper.sh)

This guide provides comprehensive instructions for deploying the **Tomcat Monitoring & Autonomous Diagnostic Platform** across local development environments, on-premise datacenters, and multi-cloud enterprise fleets (Linux & Windows Server).

---

## 📑 Table of Contents

- [1. System & Fleet Prerequisites](#1-system--fleet-prerequisites)
- [2. Quick Start Lab Deployment](#2-quick-start-lab-deployment)
- [3. Automated Fleet Deployment (Ansible)](#3-automated-fleet-deployment-ansible)
  - [A. Master Stack Deployment (`playbooks/deploy-all.yml`)](#a-master-stack-deployment-playbooksdeploy-allyml)
  - [B. OS-Specific Fleet Deployment (`deploy-linux.yml` / `deploy-windows.yml`)](#b-os-specific-fleet-deployment-deploy-linuxyml--deploy-windowsyml)
  - [C. Standalone Host Provisioning (`provision-fleet.yml`)](#c-standalone-host-provisioning-provision-fleetyml)
  - [D. Single Host & Target Group Filtering (`--limit`)](#d-single-host--target-group-filtering---limit)
  - [E. Enterprise Multi-Dimensional Matrix Targeting](#e-enterprise-multi-dimensional-matrix-targeting)
  - [F. Intelligent Dual-Execution Runner](#f-intelligent-dual-execution-runner)
- [4. Topology Profiles & Component Allocation](#4-topology-profiles--component-allocation)
- [5. Host Workspace (`tm-home`) & Drive Configuration](#5-host-workspace-tm-home--drive-configuration)
- [6. TLS Governance & Custom SSL Certificates](#6-tls-governance--custom-ssl-certificates)
- [7. Enterprise Container Registry Integration](#7-enterprise-container-registry-integration)
- [8. Alternative Deployment Methods](#8-alternative-deployment-methods)
  - [A. Modern Declarative CLI (`tmctl`)](#a-modern-declarative-cli-tmctl)
  - [B. Modular Shell Scripts](#b-modular-shell-scripts)
- [9. CI/CD Pipeline Deployment (Jenkins)](#9-cicd-pipeline-deployment-jenkins)
- [10. Post-Installation Live Verification](#10-post-installation-live-verification)

---

## 1. System & Fleet Prerequisites

### Host Operating Systems Supported
* **Linux:** Ubuntu 20.04/22.04/24.04, Debian 11/12, RHEL/CentOS/Rocky Linux 8/9, Amazon Linux 2023.
* **Windows Server / Desktop:**
  * **Windows Server 2019 (Build 17763 / LTSC 2019):** **Verified in Live Testing** (uses `nanoserver:1809`).
  * **Windows Server 2022 (Build 20348 / LTSC 2022):** Supported via `nanoserver:ltsc2022`.
  * **Windows Server 2025 (Build 26100 / LTSC 2025):** Supported via `nanoserver:ltsc2025`.
  * **Linux Containers on Windows (WSL2 / Docker Desktop):** Fully supported via adaptive container mode.

> [!IMPORTANT]
> **Windows Container Engine Modes (`WINDOWS_CONTAINER_MODE`):**  
> * **`auto` (Default):** The deployment automation automatically queries the Docker daemon on the Windows host (`docker info --format '{{.OSType}}'`). If the daemon is in Linux container mode (WSL2/LCOW), it seamlessly deploys the Linux container stack with POSIX mount paths. If in Windows container mode, it builds kernel-matched NanoServer images.
> * **`windows`:** Forces Windows Native Container (NanoServer) execution.
> * **`linux`:** Forces Linux Container on Windows execution.

### Container Runtimes Supported
* **Podman:** Version 4.0+ (Rootless mode recommended for Linux).
* **Docker Engine / Mirantis Container Runtime:** Version 24.0+ (Linux and Windows Docker NanoServer).

### Linux Host Preparation Scripts
To prepare a fresh Linux Server (Amazon Linux 2023, Ubuntu, Debian, RHEL, Rocky, AlmaLinux) for fleet deployment, the repository provides automated helper scripts:

1. **Remote Zero-Touch Linux Host Bootstrap (from Local Machine via SSH):**
   ```bash
   ./scripts/bootstrap-linux-host-remote.sh <TARGET_IP_OR_HOST> -i ~/.ssh/tomcat-monitoring-aws-key.pem
   ```
   *Connects via SSH, inspects container runtimes (Docker/Podman), installs Podman by default if no engine exists, provisions 2GB Swap (preventing OOM on 1GB RAM instances), installs Python 3 for Ansible, enables systemd user lingering, and verifies non-sudo runtime execution.*

2. **Local Linux Host Bootstrap (Run directly on Linux Target):**
   ```bash
   sudo ./scripts/bootstrap-linux-host.sh [--engine auto|podman|docker]
   ```

### Windows Server Host Preparation Scripts
To prepare a fresh Windows Server (2019 / 2022 / 2025) for fleet deployment, the repository provides automated helper scripts:

1. **Remote Zero-Touch Docker Provisioner (from Linux Controller via SSH):**
   ```bash
   ./scripts/install-docker-windows-remote.sh <TARGET_IP_OR_HOST> -i ~/.ssh/tomcat-monitoring-aws-key.pem
   ```
   *Connects over SSH, uploads the installer, installs the `Containers` Windows feature, automatically handles host reboot (Exit Code 3010) and post-reboot recovery, copies binaries to `C:\Windows\System32\`, and verifies `docker version`.*

2. **Local Docker Engine Installer (PowerShell on Windows Target):**
   ```powershell
   .\scripts\install-docker-windows.ps1
   ```
   *Installs the `Containers` Windows feature, downloads official Docker static binaries, registers `dockerd` service, and starts Docker for Windows Containers.*

3. **OpenSSH Server Bootstrap & Security Hardening (PowerShell on Windows Target):**
   ```powershell
   .\scripts\bootstrap-windows-host.ps1
   ```
   *Installs OpenSSH Server capability, binds service to `LocalSystem`, enforces strict .NET ACLs on host keys, sets `DefaultShell` to PowerShell, and injects authorized SSH keys.*

### Network & Port Allocations
Ensure the following ports are open in host firewalls / cloud security groups:

| Component | Port | Protocol | Scope | Description |
| :--- | :---: | :---: | :---: | :--- |
| **Tomcat App / Probe** | `8080` / `8083` | HTTP | Internal / Public | Web application traffic & `/health` probes |
| **Tomcat JMX Exporter** | `9404` | HTTPS (TLS) | Monitoring Network | JVM metrics scrape endpoint |
| **Prometheus TSDB** | `9090` | HTTP | Monitoring Core | Prometheus TSDB Web UI & PromQL API |
| **Alertmanager** | `9093` | HTTP | Monitoring Core | Alert routing engine & webhook dispatch |
| **Diagnostic Service** | `8443` | HTTPS (TLS) | Monitoring Core | Autonomous diagnostic API & Alertmanager webhook |
| **Mailpit Web UI** | `8025` | HTTP | Lab / Operations | Incident report email web viewer |
| **Mailpit SMTP** | `1025` | SMTP | Monitoring Core | Internal SMTP sink for lab/staging |
| **Postfix SMTP Relay** | `587` | SMTP (STARTTLS) | Monitoring Core | Enterprise SMTP outbound bridge |

---

## 2. Quick Start Lab Deployment

Deploy the complete stack on `localhost` in under 5 minutes without configuring complex inventories:

### Linux / WSL (Ansible Dual-Execution)
```bash
# 1. Clone repository
git clone git@github.com:edkas07-oss/tomcat-monitoring.git
cd tomcat-monitoring

# 2. Deploy all-in-one stack to local environment
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/lab.ini
```

> [!TIP]
> **Ansible is NOT required on your host.** The runner (`scripts/run-ansible-playbook.sh`) automatically spawns an ephemeral containerized Ansible controller (`localhost/ansible-controller:1.0`) if `ansible-playbook` is not found locally.

### Windows Host (`tmctl.exe` / PowerShell)
On native Windows environments with Docker (Windows Containers mode), deploy instantly using the standalone operator CLI **`tmctl.exe`**:
```powershell
.\tmctl.exe stack deploy --env lab
```

> [!NOTE]
> * **How to install `tmctl`:** To build from source or download `tmctl.exe`, refer to the [**`tmctl` Repository**](https://github.com/edkas07-oss/tmctl) (`make build-all` or `go build`).
> * **Ansible Fleet Deployment:** For automated multi-node Windows Server fleet deployment via Ansible, refer to [**Section 3.B (OS-Specific Fleet Deployment)**](#b-os-specific-fleet-deployment-deploy-linuxyml--deploy-windowsyml).

---

## 3. Automated Fleet Deployment (Ansible)

The platform provides idempotent, enterprise-ready automation using Ansible Playbooks & Thin Declarative Roles with native **Multi-OS Fact Branching**.

### A. Master Stack Deployment (`playbooks/deploy-all.yml`)
Provisions directories, TLS material, secrets, Docker/Podman network bridge, named volumes, installs `tm-agent` daemon, starts all containers, and verifies endpoint readiness across all targets:

```bash
# Local Lab
bash scripts/run-ansible-playbook.sh -i inventories/lab.ini playbooks/deploy-all.yml

# AWS Staging Multi-OS Fleet (Linux & Windows)
bash scripts/run-ansible-playbook.sh -i inventories/aws-staging.ini playbooks/deploy-all.yml
```

### B. OS-Specific Fleet Deployment (`deploy-linux.yml` / `deploy-windows.yml`)
Deploy only to specific operating system fleets:

```bash
# Deploy to Windows Server nodes only (Docker NanoServer)
bash scripts/run-ansible-playbook.sh -i inventories/aws-staging.ini playbooks/deploy-windows.yml

# Deploy to Linux nodes only
bash scripts/run-ansible-playbook.sh -i inventories/aws-staging.ini playbooks/deploy-linux.yml
```

### C. Standalone Host Provisioning (`provision-fleet.yml`)
Prepares host folders (`C:\tm-home` / `/opt/tm-home`), injects TLS/secrets, deploys `tmctl` CLI, and starts the `tm-agent` daemon without launching monitoring containers:

```bash
bash scripts/run-ansible-playbook.sh -i inventories/aws-staging.ini provision-fleet.yml
```

### D. Single Host & Target Group Filtering (`--limit`)

```bash
# Deploy ONLY to a specific Windows node
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/aws-staging.ini --limit aws-ec2-win-01

# Deploy ONLY to a specific Linux host by IP
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/aws-staging.ini --limit 198.51.100.10

# Deploy ONLY to Windows group
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/aws-staging.ini --limit windows_nodes
```

### E. Enterprise Multi-Dimensional Matrix Targeting
Using [`inventories/enterprise-matrix.ini.example`](inventories/enterprise-matrix.ini.example), filter targets by Application, Environment, and OS using Ansible boolean logic:

```bash
# 1. Intersection (AND / &): Deploy to Payment App in UAT
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/enterprise-matrix.ini.example --limit "app_payment:&env_uat"

# 2. Intersection (AND / &): Deploy to Windows nodes in Production
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/enterprise-matrix.ini.example --limit "windows_nodes:&env_production"

# 3. Union (OR / :): Deploy to DEV and SIT simultaneously
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/enterprise-matrix.ini.example --limit "env_dev:env_sit"

# 4. Negation (NOT / !): Deploy to Production EXCEPT Site B
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/enterprise-matrix.ini.example --limit "env_production:!env_siteprodB"
```

### F. Intelligent Dual-Execution Runner
`scripts/run-ansible-playbook.sh` automatically detects the execution environment:
* **Native Mode:** Uses local `ansible-playbook` if available.
* **Containerized Mode:** Automatically runs inside `localhost/ansible-controller:1.0` with `--network host` and SSH key socket passthrough.

---

## 4. Topology Profiles & Component Allocation

The platform adapts dynamically to various topological architectures via the `deploy_topology` parameter:

| Topology Profile | Target Components | Architecture & Purpose | Deployment Flexibility & CLI Command |
| :--- | :--- | :--- | :--- |
| **`all_in_one`** *(Default)* | Tomcat, Prometheus, Alertmanager, Diagnostic Service, Postfix, Mailpit, tm-agent | Single-server co-located deployment | **Instant Single-Node Setup**<br/>*(Default — no extra flag)* |
| **`monitoring_node`** | Tomcat, Telegraf, tm-agent | Monitored application server shipping metrics/events | **Lightweight Edge Agent Scaling**<br/>`-e "deploy_topology=monitoring_node"` |
| **`central_hub`** | Prometheus, Alertmanager, Diagnostic Service, Postfix, Mailpit | Dedicated monitoring server aggregating multi-node fleet | **Centralized Multi-Fleet Management**<br/>`-e "deploy_topology=central_hub"` |
| **`custom`** | User-defined list in `selected_components` | Tailored component allocation | **100% Granular Component Selection**<br/>`-e "deploy_topology=custom" -e 'selected_components=["prometheus","alertmanager"]'` |

#### Distributed Deployment Example:
```bash
# 1. Deploy monitoring agents on all Tomcat target servers:
bash scripts/run-ansible-playbook.sh -i inventories/aws-staging.ini playbooks/deploy-all.yml \
  -e "deploy_topology=monitoring_node" --limit tomcat_fleet

# 2. Deploy central monitoring hub on dedicated operations server:
bash scripts/run-ansible-playbook.sh -i inventories/aws-staging.ini playbooks/deploy-all.yml \
  -e "deploy_topology=central_hub" --limit monitoring_core
```

---

## 5. Host Workspace (`tm-home`) & Drive Configuration

The platform implements a **Two-Tier Storage Model**:

1. **Stateful Databases (Tier 1):** Stored in Container Engine Named Volumes (`prometheus_data`, `diagnostic_data`, `alertmanager_data`, `mailpit_data`).
2. **Host Workspace (Tier 2):** Stored in `tm-home` (`C:\tm-home` on Windows, `/opt/tm-home` on Linux).

### Custom Drive & Path Overrides:
You can relocate the host directory to any partition (e.g. `D:\tm-home`, `E:\monitoring`, `/data/tm-home`):

```ini
# In your inventory file:
[windows_nodes:vars]
tm_root_dir=D:\tm-home
project_root=D:\tm-home
spool_dir=D:\tm-home\spool

[linux_nodes:vars]
tm_root_dir=/data/tm-home
```

Or pass dynamically via Ansible extra vars:
```bash
bash scripts/run-ansible-playbook.sh playbooks/deploy-all.yml -i inventories/aws-staging.ini \
  -e "custom_tm_root_dir=D:\tm-home"
```

---

## 6. TLS Governance & Custom SSL Certificates

| Parameter | Default | Options | Description |
| :--- | :---: | :---: | :--- |
| **`tls_mode`** / `TLS_MODE` | `auto` | `auto`, `custom` | `auto` auto-generates certificates; `custom` uses user-provided certificates. |
| **`TLS_RENEW_THRESHOLD_DAYS`** | `30` | Days | Triggers auto-renewal if existing certificate expires within this threshold. |
| **`custom_tls_cert_path`** | `""` | File path | Path to custom X.509 certificate (`.crt` / `.pem`). |
| **`custom_tls_key_path`** | `""` | File path | Path to custom RSA private key (`.key`). |

### Deploying with Enterprise Custom SSL Certificates:
```bash
bash scripts/run-ansible-playbook.sh playbooks/deploy-all.yml -i inventories/aws-staging.ini \
  -e "tls_mode=custom" \
  -e "custom_tls_cert_path=/path/to/company.crt" \
  -e "custom_tls_key_path=/path/to/company.key"
```

---

## 7. Enterprise Container Registry Integration

The platform integrates out-of-the-box with enterprise registries (Harbor, Nexus, JFrog Artifactory, AWS ECR, Quay, GitHub Container Registry):

| Parameter | Lab Default | Enterprise Production Example | Description |
| :--- | :--- | :--- | :--- |
| `registry_host` | `localhost` | `harbor.corp.internal:5000` | Registry FQDN / IP address |
| `registry_namespace` | `""` *(empty)* | `tomcat-platform` | Project namespace |
| `registry_tls_verify` | `false` | `true` | Enforce TLS verification |
| `image_pull_policy` | `IfNotPresent` | `Always` / `IfNotPresent` | Image pull reconciliation policy |
| `registry_auth_file` | `""` | `~/.config/containers/auth.json` | Isolated credential store |

### Authenticating to Private Registry:
```bash
# Interactive login
./scripts/registry-login-helper.sh login harbor.corp.internal:5000 myuser

# Token-based non-interactive login
./scripts/registry-login-helper.sh login harbor.corp.internal:5000 myuser /path/to/token.txt ~/.config/containers/auth.json
```

---

## 8. Alternative Deployment Methods

### A. Modern Declarative CLI (`tmctl`)

> [!TIP]
> **Why `tmctl` for DevOps Automation?** `tmctl` compiles into a single, self-contained binary for both Linux (`tmctl`) and Windows (`tmctl.exe`). It abstracts away underlying container engine socket differences, enabling unified declarative CI/CD pipelines across diverse operating systems without complex, fragile OS-branching scripts.
>
> 📥 **Installation & Repository:** Clone and build from the [**`tmctl` Repository**](https://github.com/edkas07-oss/tmctl) (`git clone git@github.com:edkas07-oss/tmctl.git && cd tmctl && make build-all`). Pre-built binaries are placed in `bin/` (`bin/windows_amd64/tmctl.exe`, `bin/linux_amd64/tmctl`).

```bash
# Deploy complete stack
tmctl stack deploy --env lab

# Deploy specific component
tmctl stack deploy --target diagnostic --env lab

# Check runtime stack health
tmctl stack status
```

### B. Modular Shell Scripts
```bash
./scripts/deploy-tomcat.sh               # Deploy Tomcat JMX target container
./scripts/deploy-prometheus.sh           # Deploy Prometheus TSDB (Port 9090)
./scripts/deploy-alertmanager.sh         # Deploy Alertmanager router (Port 9093)
./scripts/deploy-diagnostic-service.sh   # Deploy Diagnostic Service HTTPS (Port 8443)
./scripts/deploy-event-collector.sh      # Deploy tm-agent background event collector
```

---

## 9. CI/CD Pipeline Deployment (Jenkins)

The repository provides a production-grade `Jenkinsfile` featuring a **Two-Tier Defense-in-Depth Safety Mechanism**:

1. **Tier 1 (Jenkins Job Switch):** Blocks builds entirely during change freezes.
2. **Tier 2 (`ENABLE_DEPLOYMENT` Parameter):** Defaults to `false` (*Dry-Run Safe Mode*). Pipeline validates configurations without altering target servers unless explicitly confirmed by the operator.

### Jenkins Pipeline Parameters (Complete Matrix):

| Parameter | Type | Default | Options / Example Values | Scope & Purpose |
| :--- | :---: | :---: | :--- | :--- |
| **`DEPLOY_ENV`** | Choice | `corporate-matrix` | `corporate-matrix`, `aws-staging`, `aws-production`, `production`, `staging`, `lab` | Target Deployment Environment |
| **`INVENTORY_PATH`** | String | `""` | `inventories/aws-staging.ini`, `inventories/corporate-matrix.ini` | Custom inventory path (auto-detects in `inventories/` if empty) |
| **`TARGET_HOST`** | String | `all` | `all`, `windows_nodes`, `linux_nodes`, `aws-ec2-win-01`, `app_payment:&env_uat` | Target Host / Group pattern |
| **`ENABLE_DEPLOYMENT`** | Boolean | `false` | `true` / `false` | **Safety Switch:** Must be checked for live deployment (Dry-Run when false) |
| **`REGISTRY_HOST`** | String | `localhost` | `localhost`, `harbor.corp.internal`, `nexus.corp.internal:8443` | Enterprise Container Registry host |
| **`DEPLOY_TOPOLOGY`** | Choice | `all_in_one` | `all_in_one`, `monitoring_node`, `central_hub`, `custom` | Deployment Topology Profile |
| **`SELECTED_COMPONENTS`** | String | `all` | `all`, `prometheus,alertmanager,diagnostic_service` | Granular components to deploy (when topology is custom) |
| **`TLS_MODE`** | Choice | `auto` | `auto`, `custom` | TLS Certificate Mode (`auto`: self-signed with <30d auto-renewal) |
| **`CUSTOM_TLS_CERT_PATH`** | String | `""` | `/path/to/server.crt` | Local path to custom server.crt (when `TLS_MODE=custom`) |
| **`CUSTOM_TLS_KEY_PATH`** | String | `""` | `/path/to/server.key` | Local path to custom server.key (when `TLS_MODE=custom`) |
| **`TM_ROOT_DIR`** | String | `""` | `C:\tm_data`, `/opt/tm_data`, `D:\tm_data` | Custom root installation directory (defaults to OS standard if empty) |
| **`WINDOWS_CONTAINER_MODE`** | Choice | `auto` | `auto`, `windows`, `linux` | Container OS mode on Windows (`auto`: auto-detect; `windows`: NanoServer) |
| **`EXECUTE_LIVE_TESTS`** | Boolean | `true` | `true` / `false` | Execute post-deployment live verification suite |

---

## 10. Post-Installation Live Verification

Verify the health of the entire platform immediately after deployment:

```bash
# 1. Static Layout & Governance Contract Validation
./scripts/validate.sh

# 2. Live TomcatDown Incident Simulation (Alert -> Diagnosis -> SMTP Report -> Resolution)
./scripts/test-tomcatdown-live.sh

# 3. Enterprise SMTP Relay & Header Verification
./scripts/verify-postfix-relay.sh

# 4. Live JVM GC & Concurrency Saturation Workload Simulation
./scripts/verify-jvm-workload-live.sh
```

On Windows Server (PowerShell):
```powershell
# Run complete end-to-end alert pipeline test
powershell -ExecutionPolicy Bypass -File C:\tm-home\scripts\test-alert-pipeline.ps1
```
