# 🎭 Ansible Roles — Tomcat Monitoring Fleet Automation

Documentation for the **Modular Ansible Roles** responsible for fleet provisioning and container stack orchestration across Linux and Windows Server target hosts.

---

## 📦 Role Catalog

| Role Name | Scope & Responsibilities | Key Task Files |
| :--- | :--- | :--- |
| **[`role_host_prep`](role_host_prep/)** | Initializes secure directories (`0700` Linux / `C:\monitoring` Windows), materializes TLS certificates (`0400`/`0444`), creates bridge networks (`tm-net`), provisions persistent named volumes, and deploys `tmctl` CLI. | `tasks/directories.yml`<br/>`tasks/secrets_and_tls.yml`<br/>`tasks/network_and_volumes.yml` |
| **[`role_event_collector`](role_event_collector/)** | Multi-OS Fact Branching for installing and managing `tm-agent` daemon (`systemd --user` unit on Linux, Windows background service). | `templates/tm-agent.service.j2`<br/>`tasks/main.yml` |
| **[`role_container_stack`](role_container_stack/)** | *Thin declarative orchestrator* that delegates deployment and reconciliation of monitoring containers (Mailpit, Postfix, Tomcat, Prometheus, Alertmanager, Diagnostic Service) to `tmctl stack deploy`. Safely skipped on pure Windows hosts. | `tasks/pull_images.yml`<br/>`tasks/mailpit.yml`<br/>`tasks/postfix.yml`<br/>`tasks/tomcat.yml`<br/>`tasks/prometheus.yml`<br/>`tasks/alertmanager.yml`<br/>`tasks/diagnostic_service.yml`<br/>`tasks/verify_readiness.yml` |

---

## 🚀 Usage Guide

### 1. End-to-End Stack Deployment (`deploy-stack.yml`)
Provisions target hosts from scratch, installs daemons, launches all containers, and verifies endpoint readiness:

```bash
# Local Lab
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/lab.ini

# Staging Environment
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/staging.ini

# Production Fleet
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/production.ini
```

### 2. Standalone Host Provisioning (`provision-fleet.yml`)
Prepares directories, TLS certificates, secrets, and starts `tm-agent` on target nodes without launching the monitoring container stack:

```bash
bash scripts/run-ansible-playbook.sh provision-fleet.yml -i inventories/production.ini
```

---

## 🔒 Security Governance & Zero Secret Leakage
- Sensitive directories (`secrets`, `spool`, `tls`) are strictly enforced with `0700` mode.
- Secret tokens (`diagnostic-bearer-token.secret`, SMTP credentials, `server.key`) are initialized with `0400` mode.
- Public certificates (`server.crt`) use `0444` mode.
- Zero plaintext credentials or passwords are committed to Git.
