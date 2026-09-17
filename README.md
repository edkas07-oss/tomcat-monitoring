# 🚀 Tomcat Monitoring & Autonomous Diagnostic Platform

[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Windows%20Server%20%28Docker%20NanoServer%29-blue.svg)](inventories/README.md)
[![Installation](https://img.shields.io/badge/Installation-INSTALL.md-blueviolet.svg)](INSTALL.md)
[![Runbook](https://img.shields.io/badge/Runbook-RUNBOOK.md-yellow.svg)](RUNBOOK.md)
[![Container Engine](https://img.shields.io/badge/Container%20Engine-Podman%20%7C%20Docker-orange.svg)](scripts/container-runtime-helper.sh)
[![Ansible](https://img.shields.io/badge/Ansible-2.16%2B%20%28Dual--Execution%29-red.svg)](roles/README.md)
[![Stack](https://img.shields.io/badge/Stack-Prometheus%20%7C%20Alertmanager%20%7C%20Node.js%2024%20%7C%20Postfix-brightgreen.svg)](config/README.md)
[![Security](https://img.shields.io/badge/Security-Zero%20%2Ftmp%20%7C%200400%20Secrets-purple.svg)](CONFIG)

Welcome to the **Tomcat Monitoring & Autonomous Diagnostic Platform** repository. This repository acts as the master orchestrator for configuration, automated deployment, AI-driven diagnostic rule management, and comprehensive live verification suites. 

**Built as an internal and embedded solution**, this monitoring platform lives directly within the Apache Tomcat instance. By utilizing the server's existing capacity, it eliminates the need for additional infrastructure procurement, making it highly cost-efficient while remaining fully effective for all monitoring needs. This design ensures deep, low-latency observability and rapid incident recovery for enterprise environments.

The monitoring stack combines **real-time runtime metrics captured directly from the source via JMX & HTTP Probes**, **intelligent alert routing (Alertmanager)**, and an **autonomous incident diagnostic engine (*Diagnostic Service*)** backed by SRE-curated knowledge packs—with a strict **Zero Destructive Auto-Remediation** policy.

---

## 📑 Table of Contents

- [💡 Overview & Value Proposition](#-overview--value-proposition)
- [🏆 Key Differentiators & Unique Advantages](#-key-differentiators--unique-advantages)
- [🗺️ Flexible Deployment Topologies & Use Cases](#-flexible-deployment-topologies--use-cases)
- [🏛️ Architecture & Component Topology](#-architecture--component-topology)
- [📦 Stack Components & Service Catalog](#-stack-components--service-catalog)
- [💾 Two-Tier Storage Architecture](#-two-tier-storage-architecture)
- [⚡ 5-Minute Quick Start](#-5-minute-quick-start)
- [📚 Documentation Navigation Hub](#-documentation-navigation-hub)
- [📂 Repository Structure](#-repository-structure)
- [📖 Technical References & Architecture Records](#-technical-references--architecture-records)
- [📄 License, Ownership & Disclaimer](#-license-ownership--disclaimer)

---

## 💡 Overview & Value Proposition

### The Operational Challenge
In enterprise environments, diagnosing production Apache Tomcat outages—such as OOM crashes, thread pool exhaustion, GC pauses, or kernel terminations—typically involves severe operational bottlenecks:
* **High Mean-Time-To-Resolution (MTTR):** On-call engineers must manually SSH into production servers to scrape logs and collect data while the system is down.
* **Fragmented Investigations:** Troubleshooting is hindered by hunting through scattered log files and correlating timestamps across disparate systems.
* **Risk of Blind Recovery:** High probability of service disruption or data corruption caused by uncoordinated automatic container restarts without root-cause analysis.

### The Solution & Design Principles
* **Resource-Efficient Footprint:** Smartly harnesses idle host capacity without impacting core Tomcat application throughput.
* **Zero-External Data Leak (Absolute Security):** All metric collection, log analysis, and root-cause correlations remain strictly inside the local host boundary.
* **Instant Evidence Capture:** The moment an anomaly occurs, the platform instantly freezes and captures point-in-time digital evidence (thread dumps, logs, container events) into a secure spool.
* **Autonomous 7-Section SRE Incident Reports:** Automatically dispatches actionable root-cause analysis reports via SMTP within seconds.
* **Strict Safety Policy (Zero-Destructive Auto-Remediation):** Directly empowers SREs with unassailable facts and remediation runbooks, avoiding dangerous automated state mutations.

---

## 🏆 Key Differentiators & Unique Advantages

What makes this platform uniquely powerful compared to traditional SaaS APM tools (Datadog, Dynatrace, New Relic) or standard Prometheus+Grafana setups?

| Architectural Capability | Traditional SaaS APM | Generic Prometheus + Grafana | 🚀 **This Platform (Tomcat Monitoring)** |
| :--- | :---: | :---: | :---: |
| **Infrastructure & Licensing Cost** | $$$$ (Expensive per-host/core billing) | Medium (Dedicated monitoring servers) | **$0 Extra (Embedded on idle server capacity)** |
| **Incident Investigation MTTR** | Manual dashboard & log correlation | Manual PromQL & log grepping | **Autonomous & Extensible Diagnostic Engine (18+ Baseline Branches + Hot-Ingest)** |
| **Crash Evidence Preservation** | Often lost if container auto-restarts | Missed if scrape interval passes | **Instant Digital Forensics (0700 Spool Freeze)** |
| **Actionable Incident Output** | Raw alert notifications (Slack/Webhook) | Metric threshold alert text | **7-Section RFC-Compliant SRE Email Report** |
| **Data Privacy & Governance** | Data leaves host to third-party cloud | Internal network | **Zero-External Data Leak (100% In-Host Boundary)** |
| **Safety & Remediation Policy** | Blind auto-restart risks data corruption | Manual restart | **Zero-Destructive Auto-Remediation (Fact-Driven)** |
| **Cross-Platform OS Parity** | Windows often secondary / heavy agent | Complex Windows exporter setup | **First-Class Windows Docker NanoServer & Linux** |
| **Topology Adaptability & Setup Flexibility** | Rigid agent-collector model (inflexible) | Rigid central cluster model | **Extreme Architectural Flexibility (All-in-One, Distributed Fleet, Custom Subsets)** |
| **Cross-Platform Automation & DevOps** | Fragmented scripts & brittle OS conditionals | Incompatible Linux vs Windows exporters | **Zero-Friction Thin Automation (`tmctl` Go Operator)** |
| **Platform Automanage & Self-Healing** | Requires external orchestrators/scripts | Manual maintenance & cert renewal | **Autonomous TLS Auto-Renewal & Self-Housekeeping** |
| **Knowledge Evolution (Rulepacks)** | Fixed vendor detection models | Static rule files | **Dynamic REST/CLI Hot-Ingest into SQLite DB (Infinite Rule Growth)** |
| **Zero-Dependency Runner** | Complex agent installation steps | Manual Ansible/Puppet setup | **Dual-Execution Containerized Ansible Controller** |

### 💎 Core Architectural Differentiators:

1. **💰 Embedded Zero-Procurement Efficiency:**
   Unlike traditional observability stacks that demand dedicated server clusters or costly SaaS subscriptions, this platform leverages the residual idle CPU/memory of your existing Tomcat hosts. It provides deep enterprise observability with **zero additional hardware or licensing procurement**.

2. **⚡ Instant Digital Evidence Freezing (*Point-in-Time Forensics*):**
   When a Tomcat JVM crashes or thread pool saturates, crucial forensic evidence (thread dumps, socket lifecycle events `died`/`oom`, localized `catalina.out` slices) is typically lost as soon as the container restarts. The platform's `tm-agent` daemon captures and freezes this evidence in a hardened `0700` spool the millisecond the anomaly happens.

3. **🧠 Autonomous & Extensible Diagnostic Engine (*Continuous Knowledge Enrichment*):**
   The platform features an autonomous diagnostic engine pre-equipped with 18 core baseline branches (`TD-01`..`TD-18` for JVM OOM, GC Pauses, Thread Starvation, Connection Leaks, Socket Terminations, etc.). **Crucially, the engine is not limited to 18 branches**: SRE teams can continuously expand and enrich the knowledge base at runtime by hot-ingesting declarative JSON rulepacks via REST API or CLI (`./scripts/ingest-rule.sh`) **without rebuilding images or restarting containers**. Every post-mortem finding transforms into *Knowledge as Code* for automated future triage.

4. **🛡️ Absolute Data Security & Privacy (*Zero External Telemetry Egress*):**
   No customer request payloads, database queries, or proprietary stack traces ever leave your server boundary. It eliminates third-party SaaS cloud data leakage risks, making it fully compliant with strict financial and defense regulatory standards.

5. **🔀 Unrivaled Setup & Topology Flexibility (*All-in-One, Distributed Fleet, Custom Subsets*):**
   Whether you run a single stand-alone server, a distributed multi-node enterprise fleet (hundreds of `monitoring_node` agents feeding one `central_hub`), or a custom brownfield integration—the platform delivers **unrivaled architectural flexibility** via a single parameter (`deploy_topology`) to adapt directly to your organization's topology without modifying a single line of codebase.

6. **🪟 True Linux & Windows Server Dual-Symmetry:**
   Full native support with automated fact branching for both Linux (systemd user units, Podman rootless) and Windows Server 2019 / 2022 / 2025 (verified on Windows Server 2019 with automated kernel-matched Docker NanoServer image selection, PowerShell WMI lifecycle management).

7. **⚡ Zero-Friction Cross-Platform DevOps & Operator CLI (`tmctl`):**
   Cross-platform fleet management (Linux + Windows Server) is traditionally complex and error-prone. The platform eliminates this friction through **`tmctl`**—a standalone, zero-dependency Go operator CLI. Whether on Linux or Windows Server, `tmctl` provides a **single, unified declarative command interface** (`tmctl stack deploy`, `tmctl stack status`, `tmctl stack verify`) communicating directly with container engine sockets. Ansible roles act as *Thin Orchestrators* that delegate container lifecycle to `tmctl`, eliminating brittle OS conditional branching in playbooks.

8. **🤖 End-to-End Automanage & Self-Healing Lifecycle:**
   The platform operates with built-in autonomous self-management:
   - **Automated TLS Certificate Lifecycle:** Continuously audits TLS certificate expiration and triggers zero-touch automated renewal whenever certificates enter the `<30 days` window.
   - **Automated DB Housekeeping & Lock Recovery:** The diagnostic engine automatically purges old incident history (30-day retention), reclaims orphaned worker locks, and optimizes SQLite databases without manual SRE intervention.
   - **Socket Event Auto-Surveillance:** `tm-agent` daemon automatically tracks container lifecycles, purges stale temporary files, and enforces strict `0700` spool security.

---

## 🗺️ Flexible Deployment Topologies & Use Cases

The platform is designed with **Flexible Setup & Topology Adaptation** at its core. Via the single `deploy_topology` parameter, it seamlessly fits single-node co-located servers, distributed fleets, or custom brownfield stacks:

```
Your Environment:
│
├─ Single Server (Tomcat + Monitoring co-located on same host)?
│   └─► Topology: all_in_one  (Default — simplest, zero extra infrastructure needed)
│
├─ Distributed Fleet (Tomcat servers separate from Central Operations)?
│   ├─► Target Tomcat Fleet  ──► Topology: monitoring_node  (Lightweight agent + JMX probe)
│   └─► Central Monitoring   ──► Topology: central_hub      (Prometheus, Alertmanager, Diagnostic Engine)
│
└─ Custom Infrastructure (e.g. Existing Prometheus elsewhere)?
    └─► Topology: custom      (Explicitly select components via selected_components)
```

### Topology Profiles Summary

| Topology Profile | Target Components | Architecture & Use Case | Deployment Flexibility & Flag |
| :--- | :--- | :--- | :--- |
| **`all_in_one`** *(Default)* | Tomcat, Prometheus, Alertmanager, Diagnostic Service, Postfix, Mailpit, tm-agent | Single-server co-located monitoring | **Plug-and-Play Zero-Config**<br/>*(Default — no flag needed)* |
| **`monitoring_node`** | Tomcat, Telegraf, tm-agent | Target Tomcat server in a multi-node fleet | **Lightweight Edge Fleet Scale**<br/>`-e "deploy_topology=monitoring_node"` |
| **`central_hub`** | Prometheus, Alertmanager, Diagnostic Service, Postfix, Mailpit | Dedicated centralized monitoring server | **Central Operations Aggregation**<br/>`-e "deploy_topology=central_hub"` |
| **`custom`** | Explicit list in `selected_components` | Custom tailored stack | **Granular Component-Level Gating**<br/>`-e "deploy_topology=custom"` |

> 📖 **Full Installation & Topology Guide:** Detailed multi-node playbooks and targeting matrices are documented in [**`INSTALL.md`**](INSTALL.md).

---

## 🏛️ Architecture & Component Topology

```mermaid
flowchart LR
    subgraph TargetHost ["Target Tomcat Fleet (Linux / Windows)"]
        TOMCAT["<b>Apache Tomcat</b><br/>:8080 (App) / :9404 (JMX TLS)"]
        TELEGRAF["<b>Telegraf</b><br/>:9273 (HTTP Probe)"]
        AGENT["<b>tm-agent Daemon</b><br/>(Socket API Event Listener)"]
        SPOOL[("<b>0700 Event Spool</b><br/>tm-home/spool")]
        LOGS[("<b>Named Volume</b><br/>tomcat_logs")]
        
        TOMCAT -->|Writes Logs| LOGS
        AGENT -->|Captures died/oom/exit| SPOOL
    end

    subgraph MonitoringCore ["Monitoring & Autonomous Diagnostic Stack"]
        PROM["<b>Prometheus TSDB</b><br/>:9090"]
        AM["<b>Alertmanager</b><br/>:9093"]
        DS["<b>Diagnostic Service</b><br/>:8443 (HTTPS Webhook & Rules API)"]
        SQLITE[("<b>SQLite DB</b><br/>diagnostic.db")]
        POSTFIX["<b>Postfix SMTP Relay</b><br/>:587 (SASL / STARTTLS)"]
        MAILPIT["<b>Mailpit Web Inbox</b><br/>:1025 (SMTP) / :8025 (UI)"]
        
        TOMCAT -->|JMX Scrape| PROM
        TELEGRAF -->|Health Scrape| PROM
        PROM -->|Fires Alert| AM
        AM -->|HTTPS Webhook| DS
        AM -.->|Emergency Fallback Route| POSTFIX
        DS <-->|Durable Incident State| SQLITE
        DS -->|Read Logs & Spool Evidence| LOGS
        DS -->|Read Spool Evidence| SPOOL
        DS -->|Dispatches 7-Section SRE Report| POSTFIX
        POSTFIX -->|Forward Relay| MAILPIT
    end

    subgraph SREClient ["SRE & Operations"]
        SRE["<b>On-Call SRE Engineer</b>"]
        MAILPIT -->|View Incident Report| SRE
        SRE <-->|Curated Rules API & CLI| DS
        SRE <-->|PromQL Queries & Dashboards| PROM
    end
```

---

## 📦 Stack Components & Service Catalog

| Component | Port / Interface | Scope & Architectural Function | Configuration |
| :--- | :---: | :--- | :--- |
| **`tomcat-jmx-exporter`** | `8080` (HTTP)<br/>`9404` (HTTPS TLS) | Target Tomcat running Java Agent JMX Exporter exposing JVM Heap, GC STW pauses, and Thread Pool metrics over TLS. | [`config/jmx-exporter/`](config/jmx-exporter/README.md) |
| **`telegraf`** | `9273` (HTTP) | Lightweight agent probing the `/health` endpoint and exporting HTTP response codes and latencies. | [`config/telegraf/`](config/telegraf/README.md) |
| **`prometheus`** | `9090` (HTTP) | TSDB scraping engine with custom alerting rules (`TomcatDown`, `TomcatThreadPoolSaturated`, `TomcatGCPauseHigh`). | [`config/prometheus/`](config/prometheus/README.md) |
| **`alertmanager`** | `9093` (HTTP) | Alert router forwarding incidents to the Diagnostic Service webhook, with direct SMTP fallback. | [`config/alertmanager/`](config/alertmanager/README.md) |
| **`diagnostic-service`** | `8443` (HTTPS) | Autonomous 18-branch diagnostic engine (`TD-01`..`TD-18`), durable SQLite state machine, and 7-Section report generator. | [`config/diagnostic-service/`](config/diagnostic-service/README.md) |
| **`postfix-relay`** | `587` (Internal) | Enterprise SMTP Relay Bridge with SASL Authentication and STARTTLS encryption relaying to corporate MTAs/Mailpit. | [`config/diagnostic-service/`](config/diagnostic-service/README.md) |
| **`event-collector` (`tm-agent`)** | *Daemon* | Go daemon listening to container socket events (`died`, `oom`, `stop`) and writing structured JSON to a `0700` spool. | [`config/event-collector/`](config/event-collector/README.md) |
| **`tmctl`** | *CLI* | Standalone Go operator CLI for declarative container lifecycle orchestration and stack health auditing. | Included in release tooling |
| **`mailpit`** | `8025` (Web UI)<br/>`1025` (SMTP) | Developer & Lab mock SMTP server with a full-featured web inbox for inspecting incident reports. | Pre-configured in stack |

---

## 💾 Two-Tier Storage Architecture

The platform strictly adheres to a **Zero `/tmp` Policy** using a **Two-Tier Storage Architecture**:

```
                                  STORAGE ARCHITECTURE
   ┌──────────────────────────────────────────────────────────────────────────────────┐
   │ 1. Container Engine Named Volumes (Managed by Docker / Podman Engine Subsystem)   │
   │    • prometheus_data      ──► TSDB chunks & WAL (:9090)                          │
   │    • diagnostic_data      ──► SQLite diagnostic.db state machine (:8443)         │
   │    • alertmanager_data    ──► Silences & notification logs (:9093)               │
   │    • mailpit_data         ──► Mailbox SQLite database (:8025)                    │
   │    • tomcat_logs          ──► Catalina runtime logs intake (optional volume)     │
   ├──────────────────────────────────────────────────────────────────────────────────┤
   │ 2. Host Home Directory (tm-home: C:\tm-home or /opt/tm-home)                      │
   │    • config/    [ro bind] ──► Declarative YAML/JSON configurations               │
   │    • secrets/   [ro bind] ──► 0400 Bearer tokens & credentials                   │
   │    • tls/       [ro bind] ──► X.509 Certificates & private keys                  │
   │    • spool/     [rw bind] ──► 0700 Event snapshots from tm-agent                 │
   │    • bin/     [host-only] ──► Operator CLI binaries (tmctl, tm-agent)            │
   │    • scripts/ [host-only] ──► Operational verification suites                    │
   └──────────────────────────────────────────────────────────────────────────────────┘
```

* **Tier 1 (Container Engine Named Volumes):** Stateful databases and time-series TSDB chunks (`prometheus_data`, `diagnostic_data`, `alertmanager_data`, `mailpit_data`) are managed directly by Docker/Podman for native I/O throughput and crash safety.
* **Tier 2 (Host Workspace `tm-home`):** Host workspace (`C:\tm-home` on Windows, `/opt/tm-home` on Linux) acts as the Control Plane containing declarative configs, TLS certs, restricted event spools, and operator binaries.

---

## ⚡ 5-Minute Quick Start

Get the entire monitoring and diagnostic platform running in under 5 minutes on `localhost`:

```bash
# 1. Clone repository
git clone git@github.com:edkas07-oss/tomcat-monitoring.git
cd tomcat-monitoring

# 2. Deploy all-in-one stack in local lab mode
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/lab.ini
```

### Web UIs Access Matrix

| Service | Local URL | Description |
| :--- | :--- | :--- |
| **📬 Mailpit Web Inbox** | [`http://localhost:8025`](http://localhost:8025) | View generated 7-Section SRE Incident Reports |
| **📊 Prometheus Web UI** | [`http://localhost:9090`](http://localhost:9090) | PromQL queries, targets health & alert rules |
| **🔔 Alertmanager Web UI** | [`http://localhost:9093`](http://localhost:9093) | Alert routing tree & active silences |
| **🌐 Tomcat Application** | [`http://localhost:8080`](http://localhost:8080) | Target application & `/health` endpoint |

---

## 📚 Documentation Navigation Hub

| Document | Scope & Contents |
| :--- | :--- |
| [**`INSTALL.md`**](INSTALL.md) | **Complete Installation & Deployment Guide:** Prerequisites, Ansible playbooks, targeting matrices (`--limit`), multi-cloud AWS, Windows Docker NanoServer, custom drive configuration (`tm-home`), TLS governance, private registries, Jenkins CI/CD, and live verification. |
| [**`RUNBOOK.md`**](RUNBOOK.md) | **Daily SRE Operations:** PromQL cheatsheet, Prometheus retention & quota tuning, dynamic AI diagnostic rules hot-ingestion, container logs inspection, and chaos incident simulation. |
| [**`inventories/README.md`**](inventories/README.md) | **Ansible Inventory Architecture:** Multi-Dimensional matrix grouping (App x Env x OS), AWS staging/production inventories, and Boolean targeting logic. |
| [**`roles/README.md`**](roles/README.md) | **Modular Ansible Roles Guide:** Multi-OS role architecture (`role_host_prep`, `role_event_collector`, `role_container_stack`). |
| [**`config/README.md`**](config/README.md) | **Configuration Governance:** Declarative configurations and platform threshold matrix. |

---

## 📂 Repository Structure

```text
tomcat-monitoring/
├── INSTALL.md                   Dedicated comprehensive installation & fleet deployment guide
├── RUNBOOK.md                   Daily SRE operational runbook & PromQL cheatsheet
├── CONFIG                       Declarative SSOT metadata & platform baseline
├── CONFIG.example               Enterprise container registry configuration template
├── Jenkinsfile                  Declarative Jenkins CI/CD pipeline with parameterized targeting
├── deploy-stack.yml             Master Ansible playbook: end-to-end stack deployment
├── provision-fleet.yml          Ansible playbook: standalone host provisioning
├── playbooks/                   Modular Multi-OS playbooks (deploy-all, deploy-linux, deploy-windows)
├── docker/                      Multi-OS Containerfiles (Linux) & Dockerfiles (Windows NanoServer)
├── inventories/                 Hierarchical Multi-OS Ansible inventory catalog & group_vars
├── roles/                       Modular Ansible roles with Multi-OS fact branching
├── config/                      Declarative non-secret configurations (Prometheus, Alertmanager, Diagnostic)
├── fixtures/                    Mock components & JSP test fixtures
├── scripts/                     Automation runners, CLI tooling, & live verification suites
└── validation/                  Static validation test runners & assertions
```

---

## 📖 Technical References & Architecture Records

* 🏛️ **Architecture Decisions:**
  * **[TM-ADR-0030]** Host Directory Standardization (`tm-home`), Two-Tier Storage Architecture & Pure Container Logging Model
  * **[TM-ADR-0029]** Flexible Multi-OS Deployment Topology Profiles, Component Gating & TLS Lifecycle Governance
  * **[TM-ADR-0028]** Hierarchical Multi-Dimensional Inventory Grouping for Cross-Targeting
  * **[TM-ADR-0027]** Standalone Go Operator CLI (`tmctl`) for Declarative Engine Socket Orchestration
  * **[TM-ADR-0026]** Thin Ansible Roles Delegating Container Lifecycle to `tmctl`
  * **[TM-ADR-0025]** Ansible Playbook Architecture for Cross-Platform Fleet Provisioning
  * **[TM-ADR-0024]** Decoupled Component CI + Orchestrated Stack CD Hub Architecture
* 📓 **Technical Implementation Notes:**
  * **[TN-022]** Host Directory Standardization to `tm-home`, Two-Tier Storage Architecture & Pure Container Logging (stdout/stderr)
  * **[TN-020]** Implement Flexible Multi-OS Deployment Topology Profiles, Component Gating & TLS Lifecycle Governance
  * **[TN-019]** Windows Container Migration (Docker NanoServer), All-in-One Diagnostic Packaging & Multi-OS Modular Refactoring
  * **[TN-018]** AWS Windows Fleet Deployment, Cross-Platform Provisioning & Live Verification
  * **[TN-017]** Multi-Cloud AWS Fleet Staging Environment Provisioning
  * **[TN-014]** Refactoring Ansible Roles into Thin Orchestrator with OS Fact Branching
  * **[TN-010]** Plug-and-Play Enterprise Container Registry Integration & Image Lifecycle

---

## 📄 License, Ownership & Disclaimer

### 👤 Author & Ownership
This repository, along with its associated architectures, automation playbooks, configurations, and diagnostic rulepacks, is designed, authored, and maintained by **Eddy Wiyatno** ([@edkas07-oss](https://github.com/edkas07-oss)).

### ⚖️ License
This project is licensed under the [Apache License 2.0](LICENSE) - see the [LICENSE](LICENSE) file for complete terms and conditions.

### 🛡️ Research & Development Disclaimer
> [!NOTE]
> All research, development, architectural design, prototyping, test fixtures, and validation suites in this repository were conducted and verified exclusively within **independent, personal laboratory environments** using personal hardware, network infrastructure, and self-hosted tooling. No confidential corporate assets, proprietary production data, or third-party enterprise infrastructure were utilized in the creation or publication of this project.
