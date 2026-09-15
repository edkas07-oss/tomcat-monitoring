# Prometheus Configuration & SRE Operations Guide

This directory maintains the Prometheus scraping configurations, PromQL alerting rules, and unit test suites.

---

## 📑 Table of Contents

- [🏛️ Scrape Targets & Topology](#️-scrape-targets--topology)
- [💾 Persistent Storage, Retention & TSDB Contract](#-persistent-storage-retention--tsdb-contract)
- [🛠️ SRE Operational Runbook (How-To Operations SOP)](#️-sre-operational-runbook-how-to-operations-sop)
  - [1. Adjusting Retention Policy (Time & Size Based)](#1-adjusting-retention-policy-time--size-based)
  - [2. Adjusting Scrape Intervals & Timeouts](#2-adjusting-scrape-intervals--timeouts)
  - [3. Adding or Modifying Alert Rules](#3-adding-or-modifying-alert-rules)
  - [4. Applying Configuration Changes (Hot-Reload vs Redeploy)](#4-applying-configuration-changes-hot-reload-vs-redeploy)
  - [5. Monitoring TSDB Storage Health](#5-monitoring-tsdb-storage-health)
- [🧪 Validation & Testing](#-validation--testing)

---

## 🏛️ Scrape Targets & Topology

Prometheus continuously scrapes runtime metrics over the container network:
1. **JMX Exporter:** `https://tomcat-jmx-exporter:9404/metrics` (secured with TLS CA verification).
2. **Telegraf HTTP Probe:** `http://telegraf:9273/metrics`.
3. **Diagnostic Service:** `https://diagnostic-service:8443/metrics`.

Scraped alerts are forwarded via Prometheus API v2 to `http://alertmanager:9093`.

---

## 💾 Persistent Storage, Retention & TSDB Contract

* **Storage Engine:** Prometheus Time Series Database (TSDB) with 2-hour Write-Ahead Logging (WAL).
* **Data Retention Policy:** Default **15 days (`15d`)** with rolling compaction.
* **Persistent Volume:** Podman/Docker Named Volume `prometheus_data` mounted at `/prometheus`.
* **Lifecycle API:** `--web.enable-lifecycle` is enabled to support zero-downtime hot-reloads via HTTP POST.

---

## 🛠️ SRE Operational Runbook (How-To Operations SOP)

### 1. Adjusting Retention Policy (Time & Size Based)

If disk constraints require shorter retention, or compliance demands longer storage:

```bash
# Example 1: Extend retention to 30 days
PROMETHEUS_RETENTION_TIME="30d" ./scripts/deploy-prometheus.sh

# Example 2: Set retention to 7 days with a 5 GB storage cap
PROMETHEUS_RETENTION_TIME="7d" PROMETHEUS_RETENTION_SIZE="5GB" ./scripts/deploy-prometheus.sh
```

> [!NOTE]
> Named volume `prometheus_data` is preserved during redeployment; historical data is never wiped.

---

### 2. Adjusting Scrape Intervals & Timeouts

1. Edit [`config/prometheus/prometheus.yml`](prometheus.yml):
   ```yaml
   global:
     scrape_interval: 30s
     scrape_timeout: 10s

   scrape_configs:
     - job_name: "tomcat-jmx-exporter"
       scrape_interval: 15s
   ```
2. Validate syntax:
   ```bash
   promtool check config config/prometheus/prometheus.yml
   ```
3. Apply changes via **Hot-Reload** (see Section 4).

---

### 3. Adding or Modifying Alert Rules

1. Edit the relevant rule file under `config/prometheus/rules/` (e.g. `jvm-workload-performance.yml` or `application-health.yml`).
2. Run Promtool unit tests:
   ```bash
   promtool test rules config/prometheus/tests/*.test.yml
   ```
3. Validate repository rules:
   ```bash
   ./scripts/validate.sh
   ```
4. Apply via **Hot-Reload**.

---

### 4. Applying Configuration Changes (Hot-Reload vs Redeploy)

#### A. Zero-Downtime Hot-Reload (Recommended)
When only updating `prometheus.yml` or rules in `rules/*.yml`:

```bash
# 1. Sync config into Prometheus Named Volume
./scripts/initialize-prometheus-volumes.sh ~/.local/share/tomcat-monitoring/jmx-exporter-tls/server.crt

# 2. Trigger lifecycle reload
curl -X POST http://127.0.0.1:9090/-/reload
```

#### B. Container Redeployment
Required when changing container flags, port bindings, or `PROMETHEUS_RETENTION_TIME`:

```bash
./scripts/deploy-prometheus.sh
```

---

### 5. Monitoring TSDB Storage Health

* **Prometheus Web UI:** Navigate to `http://localhost:9090/status` and select **TSDB Status**.
* **Key PromQL Health Metrics:**
  * Sample append rate: `rate(prometheus_tsdb_head_samples_appended_total[5m])`
  * Total TSDB disk size: `prometheus_tsdb_storage_blocks_bytes`

---

## 🧪 Validation & Testing

Execute static validation and rule testing:

```bash
./scripts/validate.sh
```
