# 🎭 Ansible Roles — Tomcat Monitoring Fleet Automation

Dokumentasi kumpulan **Ansible Roles Modular** untuk penyediaan infrastruktur host (*fleet provisioning*) dan deployment tumpukan monitoring (*container stack deployment*) pada platform Tomcat Monitoring sesuai arsitektur [TM-ADR-0025](file:///home/eddywiyatno/git/devops-handbook/docs/adr/tomcat-monitoring/adr-records/TM-ADR-0025.md) dan [TM-ADR-0026](file:///home/eddywiyatno/git/devops-handbook/docs/adr/tomcat-monitoring/adr-records/TM-ADR-0026.md).

---

## 📦 Daftar Role

| Nama Role | Ruang Lingkup & Tanggung Jawab | File Tugas Utama |
| :--- | :--- | :--- |
| **[`role_host_prep`](role_host_prep/)** | Inisialisasi direktori izin ketat `0700` (`spool`, `secrets`, `tls`), material rahasia & sertifikat TLS (`0400`/`0444`), *network bridge* (`tm-net`), dan 8 *named volumes* persisten. | `tasks/directories.yml`<br/>`tasks/secrets_and_tls.yml`<br/>`tasks/network_and_volumes.yml` |
| **[`role_event_collector`](role_event_collector/)** | Multi-OS Fact Branching untuk instalasi daemon `tm-agent`, pemeliharaan direktori spool `0700`, unit service Linux `systemd --user` (`tm-agent.service.j2`), dan Windows Service (`TomcatMonitoringAgent`). | `templates/tm-agent.service.j2`<br/>`tasks/main.yml` |
| **[`role_container_stack`](role_container_stack/)** | *Thin declarative orchestrator* yang mendelegasikan deployment dan rekonsiliasi kontainer monitoring (Mailpit, Postfix Relay, Tomcat JMX, Prometheus, Alertmanager, Diagnostic Service) ke biner operator `tmctl stack deploy`. | `tasks/pull_images.yml`<br/>`tasks/mailpit.yml`<br/>`tasks/postfix.yml`<br/>`tasks/tomcat.yml`<br/>`tasks/prometheus.yml`<br/>`tasks/alertmanager.yml`<br/>`tasks/diagnostic_service.yml`<br/>`tasks/verify_readiness.yml` |

---

## 🚀 Cara Penggunaan

### 1. Eksekusi Playbook Menyeluruh (`deploy-stack.yml`)
Menyiapkan host dari nol, memasang daemon, meluncurkan seluruh kontainer, dan memverifikasi kesehatan seluruh endpoint:
```bash
# Menjalankan di lingkungan Lab
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/lab.ini

# Menjalankan di lingkungan Staging
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/staging.ini

# Menjalankan di lingkungan Production
bash scripts/run-ansible-playbook.sh deploy-stack.yml -i inventories/production.ini
```

### 2. Eksekusi Penyiapan Host Armada Saja (`provision-fleet.yml`)
Menyiapkan folder, token rahasia, sertifikat TLS, dan daemon event collector pada node armada baru tanpa menyalakan kontainer monitoring:
```bash
bash scripts/run-ansible-playbook.sh provision-fleet.yml -i inventories/production.ini
```

---

## 🔒 Tata Kelola Keamanan & Zero Secret Leakage
- Direktori sensitif (`secrets`, `spool`, `tls`) selalu ditegakkan dengan mode `0700`.
- Berkas token rahasia (`diagnostic-bearer-token.secret`, kredensial SMTP, dan `server.key`) selalu diinisialisasi dengan mode `0400`.
- Sertifikat publik (`server.crt`) diinisialisasi dengan mode `0444`.
- Tidak ada password atau token yang di-*hardcode* di dalam Git.
