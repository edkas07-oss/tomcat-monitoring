# 🎭 Ansible Roles — Tomcat Monitoring Fleet Automation

Documentation for the **Modular Multi-OS Ansible Roles** responsible for fleet provisioning and container stack orchestration across Linux and Windows Server target hosts.

---

## 📦 Role Catalog

| Role Name | Scope & Responsibilities | Key Task Files |
| :--- | :--- | :--- |
| **[`role_host_prep`](role_host_prep/)** | Initializes secure directories (`0700` Linux / `C:\tm_data` Windows), materializes TLS certificates (`0400`/`0444`), auto-detects container runtime OS (`linux` vs `windows`), creates bridge/nat networks (`tm-net`), provisions persistent named volumes, and deploys `tmctl` CLI. | `tasks/linux/directories.yml`<br/>`tasks/linux/secrets_and_tls.yml`<br/>`tasks/windows/directories.yml`<br/>`tasks/windows/secrets_and_tls.yml`<br/>`tasks/windows/network_and_volumes.yml` |
| **[`role_event_collector`](role_event_collector/)** | Multi-OS Fact Branching for installing and managing `tm-agent` event collector (`systemd --user` unit on Linux, Docker NanoServer / Linux container on Windows). | `tasks/linux/main.yml`<br/>`tasks/windows/main.yml`<br/>`templates/tm-agent.service.j2` |
| **[`role_container_stack`](role_container_stack/)** | Declarative container orchestrator for monitoring and diagnostic stack (Mailpit, Postfix, Tomcat, Prometheus, Alertmanager, Diagnostic Service). Uses `tmctl stack deploy` on Linux, and auto-adapts on Windows to Docker NanoServer or Linux containers (WSL2). | `tasks/linux/*.yml`<br/>`tasks/windows/build_images.yml`<br/>`tasks/windows/*.yml`<br/>`tasks/windows/linux_*.yml`<br/>`tasks/windows/verify_readiness.yml` |

---

## 🚀 Usage Guide

### 1. End-to-End Stack Deployment (`playbooks/deploy-all.yml` / `deploy-stack.yml`)
Provisions target hosts from scratch, installs daemons/containers, launches all containers, and verifies endpoint readiness:

```bash
# Local Lab
bash scripts/run-ansible-playbook.sh -i inventories/lab.ini playbooks/deploy-all.yml

# AWS Staging Multi-OS Fleet (Linux & Windows Server)
bash scripts/run-ansible-playbook.sh -i inventories/aws-staging.ini playbooks/deploy-all.yml

# Dedicated Windows Server Fleet Deployment
bash scripts/run-ansible-playbook.sh -i inventories/aws-staging.ini playbooks/deploy-windows.yml

# Dedicated Linux Fleet Deployment
bash scripts/run-ansible-playbook.sh -i inventories/aws-staging.ini playbooks/deploy-linux.yml
```

### 2. Standalone Host Provisioning (`provision-fleet.yml`)
Prepares directories, TLS certificates, secrets, and starts `tm-agent` on target nodes without launching the monitoring container stack:

```bash
bash scripts/run-ansible-playbook.sh -i inventories/aws-staging.ini provision-fleet.yml
```

---

## 🔒 Security Governance & Zero Secret Leakage
- Sensitive directories (`secrets`, `spool`, `tls`) are strictly enforced with `0700` mode on Linux and restricted ACLs on Windows.
- Secret tokens (`bearer-token`, SMTP credentials, `server.key`) are initialized with `0400` mode.
- Public certificates (`server.crt`) use `0444` mode.
- Zero plaintext credentials or passwords are committed to Git.
