# Diagnostic Service Configuration Guide

This directory contains the runtime configuration files for the **Tomcat Diagnostic Service** microservice on Linux and Windows platforms.

---

## 📁 File Structure

```text
config/diagnostic-service/
├── application.json        # Linux configuration (POSIX paths, /run/tomcat-diagnostic/...)
├── application.win.json    # Windows configuration (Normalized Windows paths, C:\monitoring\...)
├── targets.json            # Linux targets allowlist
├── targets.win.json        # Windows targets allowlist
└── README.md               # Parameter specifications and operational guide
```

---

## ⚙️ Configuration Parameter Specifications (`application.json` / `application.win.json`)

### 1. SMTP Block (`"smtp"`)

Configures delivery of 7-Section SRE Incident Investigation Reports via SMTP Relay or Mailpit:

```json
"smtp": {
  "host": "mailpit",
  "port": 1025,
  "secure": false,
  "requireTLS": false,
  "from": "diagnostic@tomcat-monitoring.invalid",
  "to": "operator@tomcat-monitoring.invalid"
}
```

| Parameter | Type | Required | Description |
| :--- | :---: | :---: | :--- |
| **`host`** | `string` | Yes | FQDN or IP of SMTP Server / Relay (e.g. `"postfix-relay"`, `"mailpit"`, `"smtp.corp.internal"`). |
| **`port`** | `integer` | Yes | SMTP Port (`587` for STARTTLS Submission, `465` for Direct TLS, `25`/`1025`). |
| **`secure`** | `boolean` | Yes | `true` for direct TLS (port 465), `false` for STARTTLS (port 587) or plain SMTP. |
| **`requireTLS`** | `boolean` | No | If `true`, requires TLS handshake and rejects plaintext fallback. |
| **`usernameFile`** | `string` | Optional | Absolute container mount path containing SMTP username. |
| **`passwordFile`** | `string` | Optional | Absolute container mount path containing SMTP password. |
| **`from`** | `string` | Yes | From email address for incident reports. |
| **`to`** | `string` | Yes | Recipient email address (SRE team or on-call inbox). |

---

### 2. Server & Security Block (`"listen"`, `"tls"`, `"bearerTokenFile"`)

- **`listen`**: Host (`0.0.0.0`) and port (`8443`) for internal HTTPS interface.
- **`tls`**: Paths to public certificate (`certificateFile`) and private key (`privateKeyFile`).
- **`bearerTokenFile`**: Path to secret bearer token for Alertmanager webhook and Rules API authorization.

---

### 3. Prometheus Evidence Telemetry Block (`"prometheus"`)

- **`baseUrl`**: Internal Prometheus URL (`http://prometheus:9090`) used to query live metric snapshots during incident correlation.

---

### 4. Queue & State Resilience Block (`"queue"`)

- **`capacity`**: Maximum capacity of bounded FIFO incident queue (`50`).
- **`pollIntervalMs`**: Worker database poll interval (`250` ms).
- **`staleLockTimeoutMs`**: Processing lease timeout before stale events are recovered (`300000` ms / 5 minutes).
- **`maxRetries`**: Maximum retry attempts before marking an event as `failed` (`3`).
- **`retentionDays`**: Retention window for purging old SQLite incident records (`30` days).
- **`housekeepingIntervalMs`**: Execution interval for database vacuum and pruning routine (`86400000` ms / 24 hours).

---

## 🔐 Secrets Management & Security (Zero `/tmp` Policy)

In compliance with platform security standards, credentials and sensitive keys are mounted from host-isolated persistent paths:
- **Linux Secrets Directory:** `${HOME}/.local/share/tomcat-monitoring/diagnostic-service-secrets/` (`0700` dir, `0400` files)
- **Linux TLS Directory:** `${HOME}/.local/share/tomcat-monitoring/diagnostic-service-tls/` (`0700` dir, `0400` key, `0444` cert)
- **Windows Directories:** `C:\monitoring\secrets` and `C:\monitoring\tls`

---

## 🚀 Applying Configuration Changes

1. Modify configuration files:
   - Linux: [`application.json`](application.json) or [`targets.json`](targets.json).
   - Windows: [`application.win.json`](application.win.json) or [`targets.win.json`](targets.win.json).
2. Redeploy the diagnostic container:
   ```bash
   # Linux
   ./scripts/deploy-diagnostic-service.sh

   # Windows (via Ansible)
   bash scripts/run-ansible-playbook.sh -i inventories/aws-staging.ini playbooks/deploy-windows.yml
   ```
