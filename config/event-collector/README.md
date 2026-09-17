# Event Collector Configuration & Governance Guide

This document specifies the parameter configurations, *spool* retention contracts, and threshold management mechanisms for the **Tomcat Diagnostic Event Collector** (`tm-agent`).

---

## 📑 Table of Contents

- [🏛️ Role in Monitoring Ecosystem](#️-role-in-monitoring-ecosystem)
- [📊 Threshold Matrix & Capacity Governance](#-threshold-matrix--capacity-governance)
- [🔒 Access Control & Persistence Contract (Zero `/tmp` Policy)](#-access-control--persistence-contract-zero-tmp-policy)
- [🔧 SRE Operational Runbook: Threshold Tuning](#-sre-operational-runbook-threshold-tuning)
- [🛠️ Daemon Lifecycle (`systemd --user` & Windows Service)](#️-daemon-lifecycle-systemd---user--windows-service)

---

## 🏛️ Role in Monitoring Ecosystem

The Event Collector (`tm-agent`) is a lightweight background daemon running under `systemd --user` (Linux) or as a Windows background service. It listens to the container engine Socket API (`died`, `stop`, `start`, `oom`, `restart`) in real-time and persists atomic structured JSON diagnostic evidence into a persistent spool directory.

The **Diagnostic Service** mounts this spool directory as **read-only** (`ro,z`) to correlate container lifecycle events when diagnosing incoming alerts from Alertmanager.

---

## 📊 Threshold Matrix & Capacity Governance

Thresholds are declared in [`CONFIG`](../../CONFIG) and Ansible variables:

| Threshold Parameter | Default Value | Unit / Type | Operational Impact & Pruning Logic |
| :--- | :---: | :---: | :--- |
| **`MAX_SPOOL_AGE_HOURS`** | `24` | Hours (Integer) | **Time Retention:** `.json` files older than 24h are automatically purged upon daemon startup and per-event cycles. |
| **`MAX_SPOOL_FILES`** | `1000` | Files (Integer) | **Capacity Quota:** When the `.json` count exceeds 1000, oldest files are pruned (*FIFO pruning*). |
| **`STALE_TMP_AGE_MINUTES`** | `60` | Minutes (Integer) | **Orphan File Cleanup:** Incomplete `.tmp` files older than 60m from crashed processes are cleaned up automatically. |
| **`MAX_RECORD_BYTES`** | `16384` | Bytes (16 KiB) | **Payload Boundary:** Event records larger than 16 KiB are rejected to prevent memory exhaustion. |

---

## 🔒 Access Control & Persistence Contract (Zero `/tmp` Policy)

* **Spool Directory Path:** `${HOME}/.local/share/tomcat-monitoring/spool` (never uses volatile `/tmp`).
* **Directory Permission Mode:** Strict `0700` (`drwx------`), isolated exclusively to the user session.
* **File Permission Mode:** Individual evidence records are created with mode `0600` (`-rw-------`).
* **Read-Only Container Mount:** The `diagnostic-service` container mounts this path via `--volume "${SPOOL_DIR}:/run/tomcat-diagnostic/spool:ro,z"`.

---

## 🔧 SRE Operational Runbook: Threshold Tuning

To adjust retention or capacity limits:

```bash
# 1. Update parameter in CONFIG or CONFIG.local
nano CONFIG.local

# 2. Redeploy or restart daemon
./scripts/deploy-event-collector.sh

# 3. Verify active status
systemctl --user status tm-agent.service
```

---

## 🛠️ Daemon Lifecycle (`systemd --user` & Windows Service)

### Linux Management
Unit file location: `~/.config/systemd/user/tm-agent.service`

```bash
# Check daemon status
systemctl --user status tm-agent.service

# Stream live audit logs
journalctl --user -u tm-agent.service -f

# Inspect spool directory
ls -la ~/.local/share/tomcat-monitoring/spool
```

### Windows Server Management (PowerShell)
```powershell
# Inspect container / process
docker ps --filter "name=tm-agent"

# Inspect spool directory
Get-ChildItem C:\tm-home\spool\
```
