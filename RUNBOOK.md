# 🔧 SRE Operational Runbook — Tomcat Monitoring Platform

[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Windows%20Server-blue.svg)](inventories/README.md)
[![Observability](https://img.shields.io/badge/Observability-Prometheus%20%7C%20PromQL-orange.svg)](config/prometheus/README.md)
[![Diagnosis](https://img.shields.io/badge/Diagnosis-18--Branch%20Autonomous%20Engine-brightgreen.svg)](config/diagnostic-service/README.md)

This runbook outlines daily operational procedures, metric analysis cheatsheets, dynamic knowledge rule management, and incident verification suites for SREs and System Administrators.

---

## 📑 Table of Contents

- [1. Web UIs & Operational Endpoints](#1-web-uis--operational-endpoints)
- [2. Container Logs & Status Inspection](#2-container-logs--status-inspection)
- [3. Core Observability Metrics & SRE PromQL Cheatsheet](#3-core-observability-metrics--sre-promql-cheatsheet)
- [4. Dynamic AI Diagnostic Rule Management (Hot-Ingest & Export)](#4-dynamic-ai-diagnostic-rule-management-hot-ingest--export)
- [5. Adjusting Prometheus Retention & TSDB Quotas](#5-adjusting-prometheus-retention--tsdb-quotas)
- [6. Restricted Event Collector Daemon (`tm-agent`) Lifecycle](#6-restricted-event-collector-daemon-tm-agent-lifecycle)
- [7. Managing Persistent Volumes & State](#7-managing-persistent-volumes--state)
- [8. Automated Incident Simulation & Chaos Verification](#8-automated-incident-simulation--chaos-verification)

---

## 1. Web UIs & Operational Endpoints

| Service / Interface | URL / Endpoint | Protocol & Authentication | Description |
| :--- | :--- | :--- | :--- |
| **📬 Mailpit Web Inbox** | [`http://localhost:8025`](http://localhost:8025) | HTTP / No Auth | View generated 7-Section SRE Incident Reports |
| **📊 Prometheus Web UI** | [`http://localhost:9090`](http://localhost:9090) | HTTP / No Auth | Query PromQL metrics, inspect target health & active alerts |
| **🔔 Alertmanager Web UI** | [`http://localhost:9093`](http://localhost:9093) | HTTP / No Auth | Inspect alert routing tree & active silences |
| **🩺 Diagnostic Engine API** | [`https://localhost:8443/health`](https://localhost:8443/health) | HTTPS / TLS | Diagnostic Service liveness & readiness status |
| **🌐 Tomcat Application** | [`http://localhost:8080`](http://localhost:8080) | HTTP | Target application & `/health` endpoint |
| **📈 Tomcat JMX Metrics** | [`https://localhost:9404/metrics`](https://localhost:9404/metrics) | HTTPS / TLS Keystore | Raw JVM MBeans Prometheus metrics |

---

## 2. Container Logs & Status Inspection

All components follow the **12-Factor App (Factor XI: Logs as Event Streams)** convention by writing output directly to `stdout` / `stderr`:

```bash
# View live logs for specific components
docker logs -f diagnostic-service
docker logs -f alertmanager
docker logs --tail 50 prometheus
docker logs --tail 50 tm-agent
docker logs --tail 50 mailpit

# Inspect stack runtime status via tmctl
tmctl stack status
```

---

## 3. Core Observability Metrics & SRE PromQL Cheatsheet

### A. JVM & Tomcat Performance Metrics (`tomcat-jmx-exporter` :9404)

* **Heap Memory Used (MB):**
  ```promql
  jvm_memory_bytes_used{area="heap"} / (1024 * 1024)
  ```
* **Heap Utilization Ratio (%):**
  ```promql
  (jvm_memory_bytes_used{area="heap"} / jvm_memory_bytes_max{area="heap"}) * 100
  ```
* **Old Generation Pool Saturation (%):**
  ```promql
  (jvm_memory_pool_used_bytes{pool=~".*Old.*"} / jvm_memory_pool_max_bytes{pool=~".*Old.*"}) * 100
  ```
* **Garbage Collection Overhead (% CPU Time):**
  ```promql
  (rate(jvm_gc_pause_seconds_sum[5m]) * 100)
  ```
* **Max GC STW Latency (Seconds):**
  ```promql
  jvm_gc_pause_seconds_max
  ```
* **Tomcat Thread Pool Saturation (%):**
  ```promql
  (tomcat_threads_busy_threads / tomcat_threads_current_threads) * 100
  ```

### B. Autonomous Diagnostic Engine Metrics (`tomcat-diagnostic-service` :8443)
* **Engine Liveness & Readiness:** `diagnostic_service_ready` (`1`=Ready, `0`=Down)
* **SQLite Database Size (KB):** `diagnostic_db_size_bytes / 1024`
* **Recovered Stale Locks:** `diagnostic_stale_locks_recovered_total`
* **Webhook Ingestion Rate:** `rate(diagnostic_events_ingested_total[5m])`

---

## 4. Dynamic AI Diagnostic Rule Management (Hot-Ingest & Export)

Inject post-mortem incident diagnosis rules or export active rule knowledge dynamically:

```bash
# 1. Hot-ingest curated production rulepack into SQLite DB
BEARER_TOKEN="test-token-12345" ./scripts/ingest-rule.sh config/rules/curated-production-rulepacks.json

# 2. Hot-ingest single custom rule JSON
BEARER_TOKEN="test-token-12345" ./scripts/ingest-rule.sh /path/to/custom-rule.json

# 3. Export active master rule catalog
./scripts/export-rules.sh > ~/master-rules.json

# 4. Export rules filtered by incident category
./scripts/export-rules.sh --category database_persistence
```

---

## 5. Adjusting Prometheus Retention & TSDB Quotas

```bash
# Set retention to 30 days
PROMETHEUS_RETENTION_TIME="30d" ./scripts/deploy-prometheus.sh

# Set retention to 7 days with a 5 GB disk quota limit
PROMETHEUS_RETENTION_TIME="7d" PROMETHEUS_RETENTION_SIZE="5GB" ./scripts/deploy-prometheus.sh

# Zero-downtime hot-reload for prometheus.yml alert rules
curl -X POST http://127.0.0.1:9090/-/reload
```

---

## 6. Restricted Event Collector Daemon (`tm-agent`) Lifecycle

The `tm-agent` daemon captures socket events (`died`, `oom`, exit codes) into a secured `0700` spool:

### Linux (Systemd User Unit)
```bash
# Check daemon service status
systemctl --user status tm-agent.service

# Stream daemon audit logs
journalctl --user -u tm-agent.service -f

# Verify spool directory permissions (strict 0700 required)
ls -ld ~/.local/share/tomcat-monitoring/spool
```

### Windows Server (PowerShell)
```powershell
# Inspect tm-agent container
docker ps --filter "name=tm-agent"

# Inspect event spool JSON records
Get-ChildItem C:\tm-home\spool\
Get-Content (Get-ChildItem C:\tm-home\spool\*.json | Select-Object -Last 1).FullName
```

---

## 7. Managing Persistent Volumes & State

```bash
# Inspect Docker / Podman Named Volumes
podman volume ls

# Stream Tomcat runtime logs in real-time
podman logs -f tomcat-jmx-exporter

# Verify log mount visibility from inside Diagnostic Service container
podman exec -it diagnostic-service ls -la /run/tomcat-diagnostic/logs
```

---

## 8. Automated Incident Simulation & Chaos Verification

```bash
# 1. Trigger live TomcatDown outage test (Proves Alerting -> Correlation -> SMTP Report -> Resolution)
./scripts/test-tomcatdown-live.sh

# 2. Verify Postfix SMTP relay & RFC-compliant email delivery
./scripts/verify-postfix-relay.sh

# 3. Trigger live JVM GC & concurrency saturation stress test
./scripts/verify-jvm-workload-live.sh

# 4. Validate AI knowledge lifecycle & 5-layer ingestion defense
./scripts/validate-ai-knowledge-lifecycle.sh
```
