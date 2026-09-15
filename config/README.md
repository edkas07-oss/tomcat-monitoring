# ⚙️ Configuration Contract & Platform-Wide Threshold Matrix

This directory stores all static, non-secret configuration artifacts and parameter specifications for orchestrating the **Tomcat Monitoring & Autonomous Diagnostic Platform**.

---

## 📑 Table of Contents

- [🏛️ Configuration Governance Principles](#️-configuration-governance-principles)
- [📂 Configuration Component Catalog](#-configuration-component-catalog)
- [📊 Centralized Platform-Wide Threshold Matrix](#-centralized-platform-wide-threshold-matrix)
- [🔒 Secret Governance & Zero `/tmp` Policy](#-secret-governance--zero-tmp-policy)

---

## 🏛️ Configuration Governance Principles

1. **Non-Secret Declarative Baseline (SSOT):** All platform orchestration metadata is declared declaratively at the root [`CONFIG`](../CONFIG). Configuration files under `config/` are version-controlled non-secret declarations in Git.
2. **Runtime Secret Injection:** Credentials, TLS private keys, keystore passwords, and Bearer Tokens are injected separately at runtime via host-isolated secret files with strict permissions (`0400`/`0444`) under `${HOME}/.local/share/tomcat-monitoring/`.
3. **Pre-Flight Static Validation:** Every configuration file is validated by [`scripts/validate.sh`](../scripts/validate.sh) before deployment to any target runtime environment.

---

## 📂 Configuration Component Catalog

| Component Directory | Primary Configuration File | Description & Scope | Technical Guide |
| :--- | :--- | :--- | :--- |
| **`CONFIG` (Root)** | [`CONFIG`](../CONFIG) | Single Source of Truth (SSOT) metadata: network names, container IDs, ports, volumes, images, and default thresholds. | [Threshold Matrix](#-centralized-platform-wide-threshold-matrix) |
| **`alertmanager/`** | `alertmanager.yml` | Alert routing trees, Diagnostic Service HTTPS webhook endpoint, and direct SMTP emergency route. | [`alertmanager/README.md`](alertmanager/README.md) |
| **`diagnostic-service/`** | `application.json`, `targets.json` | Diagnostic engine runtime config, monitored target allowlist, TLS bindings, and enterprise SMTP relay. | [`diagnostic-service/README.md`](diagnostic-service/README.md) |
| **`event-collector/`** | *Declarative CONFIG* | Restricted daemon specifications, persistent spool governance contract, and retention pruning limits. | [`event-collector/README.md`](event-collector/README.md) |
| **`jmx-exporter/`** | `jmx-exporter.yml` | JVM Heap, GC, Thread Pool MBean pattern rules, and HTTPS port bindings. | [`jmx-exporter/README.md`](jmx-exporter/README.md) |
| **`prometheus/`** | `prometheus.yml`, `rules/*.yml` | Scrape targets, TSDB storage retention, and PromQL alert evaluation rules. | [`prometheus/README.md`](prometheus/README.md) |
| **`rules/`** | `curated-production-rulepacks.json` | Curated production dynamic diagnostic rulepacks for continuous learning. | [`rules/`](rules/) |
| **`telegraf/`** | `health-check.conf` | HTTP probe configuration monitoring the application `/health` endpoint. | [`telegraf/README.md`](telegraf/README.md) |

---

## 📊 Centralized Platform-Wide Threshold Matrix

The platform enforces bounded thresholds across all layers to ensure high availability, storage predictability, and alerting accuracy:

| Component | Domain / Aspect | Parameter / Rule Name | Bounded Threshold | Evaluation Logic & Operational Impact |
| :--- | :--- | :--- | :---: | :--- |
| **`event-collector`** | Spool Storage | `MAX_SPOOL_AGE_HOURS` | `24h` | JSON files older than 24h are automatically pruned on startup and event processing. |
| **`event-collector`** | Spool Storage | `MAX_SPOOL_FILES` | `1000 files` | Capacity quota enforcement via *FIFO pruning* (removes oldest records during event storms). |
| **`event-collector`** | Spool Storage | `STALE_TMP_AGE_MINUTES` | `60m` | Abandoned `.tmp` files from crashed processes are automatically cleaned up. |
| **`event-collector`** | Payload Boundary | `MAX_RECORD_BYTES` | `16 KiB` | Maximum payload limit per event record to prevent memory bloat. |
| **`prometheus`** | TSDB Storage | `--storage.tsdb.retention.time` | `15d` | Time-series data retention in persistent volume `prometheus_data`. |
| **`prometheus`** | Scrape Interval | `scrape_interval` | `30s` / `15s` | Scrape interval for Tomcat targets (`30s`) and internal Diagnostic Service (`15s`). |
| **`prometheus`** | Alert: Availability | `TomcatDown` | `up == 0` (`for: 1m`) | Fires when Tomcat target is unresponsive for more than 1 minute. |
| **`prometheus`** | Alert: Self-Health | `DiagnosticServiceDown` | `up == 0` (`for: 1m`) | Triggers Alertmanager direct SMTP emergency route if Diagnostic Service fails. |
| **`prometheus`** | Alert: GC STW Pause | `TomcatGCPauseHigh` | `max > 1.5s` (`for: 1m`) | Detects critical *Stop-The-World* GC pauses before latency spikes impact users. |
| **`prometheus`** | Alert: GC Overhead | `TomcatGCOverheadHigh` | `rate(gc_sum) * 100 > 15%` (`for: 5m`) | Detects *GC Thrashing* where CPU cycles are consumed by garbage collection. |
| **`prometheus`** | Alert: Old Gen | `TomcatOldGenMemoryPressure` | `used/max * 100 > 90%` (`for: 10m`) | Persistent high Old Generation retention (indicator of memory leak). |
| **`prometheus`** | Alert: Concurrency | `TomcatThreadPoolSaturated` | `busy/current >= 1.0` (`for: 5m`) | 100% saturation of the Tomcat Connector thread pool. |
| **`alertmanager`** | Alert Routing | `group_wait` / `group_interval` | `10s` / `1m` | Alert aggregation buffer before posting to Diagnostic Service webhook. |
| **`alertmanager`** | Alert Routing | `repeat_interval` | `12h` | Re-notification interval for unresolved ongoing incidents. |
| **`diagnostic-service`**| State Resilience | `lease_expires_at` | `5m` | Worker lock lease. Events processing $> 5\text{m}$ are re-queued (*Stale Lock Recovery*). |
| **`diagnostic-service`**| State Resilience | `maxRetries` | `3 attempts` | Max event processing retries before moving record to `failed` state. |
| **`diagnostic-service`**| DB Retention | `retentionDays` | `30 days` | Prunes historical SQLite records and executes `PRAGMA incremental_vacuum`. |
| **`diagnostic-service`**| Evidence Timeout | `timeoutMs` | `5000 ms` | Timeout for fetching live Prometheus metrics without blocking evaluation pipeline. |

---

## 🔒 Secret Governance & Zero `/tmp` Policy

* Never commit secret files (`.pem`, `.key`, `.p12`, `.jks`, `.env`, or passwords) into the `config/` directory.
* All components utilize named persistent volumes (`tomcat_logs`, `diagnostic_data`, `prometheus_data`, `alertmanager_data`) and host-isolated directories (`0700`/`0400`) at `${HOME}/.local/share/tomcat-monitoring/`.
