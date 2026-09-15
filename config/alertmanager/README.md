# Alertmanager Configuration Contract & Routing Architecture

This directory provides non-secret alert routing definitions for two primary receivers:
1. `lab-diagnostic-service` (Default receiver dispatching HTTPS webhooks to the Autonomous Diagnostic Service).
2. `direct-email-emergency` (Fallback sub-route dispatching direct SMTP notifications to Mailpit/relay during Diagnostic Service outages).

The baseline uses stable group labels: `alertname`, `job`, `instance`, `service`, and `check`; configured with `group_wait: 10s`, `group_interval: 15s`, and `repeat_interval: 4h`.

All operational Tomcat alerts (`TomcatDown`, Application Health, JVM GC/Memory, Threading Concurrency) are routed to `lab-diagnostic-service` for multi-domain deterministic diagnostic evaluation. The Diagnostic Service then publishes a comprehensive 7-Section SRE Incident Investigation Report.

In the event of an outage on the Diagnostic Service itself (`DiagnosticServiceDown`), the emergency sub-route `direct-email-emergency` intercepts the alert (`continue: false`) and immediately sends an emergency direct email alert to Mailpit/relay.

---

## 📨 Direct SMTP Settings

Alertmanager delivers emergency notifications internally via:

```text
postfix-relay:587 / mailpit:1025
```

The sender `alertmanager@tomcat-monitoring.invalid` and recipient `operator@tomcat-monitoring.invalid` are synthetic identity placeholders adhering to RFC standards.

---

## 🔀 Diagnostic Route Contract

The default routing tree uses `lab-diagnostic-service` to post webhooks to the Diagnostic Service over HTTPS:

```yaml
route:
  receiver: lab-diagnostic-service
  group_by:
    - alertname
    - job
    - instance
    - service
    - check
  group_wait: 10s
  group_interval: 15s
  repeat_interval: 4h
  routes:
    - receiver: direct-email-emergency
      matchers:
        - alertname = "DiagnosticServiceDown"
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 1h
      continue: false
```

The webhook receiver utilizes `url_file`, `credentials_file`, and `ca_file` pointing to runtime mounted secrets:

```text
/run/secrets/tomcat-monitoring/diagnostic-service-webhook-url
/run/secrets/tomcat-monitoring/diagnostic-service-bearer-token
/run/secrets/tomcat-monitoring/diagnostic-service-ca.crt
```

These secret files are never stored in Git; they are mounted as read-only volumes during runtime deployment.

---

## 📧 Alert Notification & Email Template Contract

Prometheus and Alertmanager maintain stable internal `alertname` and rule severity throughout the firing/resolved lifecycle. This stability is critical for grouping, deduplication, and correlation.

The email presentation layer translates internal lifecycle states into clear, human-readable operator statuses:

| Internal State | Rule Severity | Operator Severity | Banner Color |
| --- | --- | --- | --- |
| `firing` | `warning` | `WARNING` | Orange `#ef6c00` |
| `firing` | `critical` | `CRITICAL` | Red `#c62828` |
| `resolved` | `warning` or `critical` | `RESOLVED` / `NORMAL` | Green `#2e7d32` |

### Email Presentation Mapping

| Internal Alert Name | Firing Presentation | Resolved Presentation |
| --- | --- | --- |
| `TelegrafHealthScrapeUnavailable` | `TelegrafHealthScrapeUnavailable` | `TelegrafHealthScrapeAvailable` |
| `TomcatApplicationHealthMetricsMissing` | `TomcatApplicationHealthMetricsMissing` | `TomcatApplicationHealthMetricsAvailable` |
| `TomcatApplicationHealthFailed` | `TomcatApplicationHealthFailed` | `TomcatApplicationHealthNormal` |

### Email Subject Format
```text
[<RESOLVED|CRITICAL|WARNING>] [MONITORING] Tomcat Service: <presentation-alert-name> (Instance: <instance>)
```

### Structured Email Body Layout
1. **Header Banner:** Displays alert/recovery status, service title, and environment badge.
2. **Alert / Recovery Summary:** Subtle background card (`⚠️ Alert Summary` or `✅ Recovery Summary`) presenting active symptoms or resolution confirmation.
3. **Technical Details Grid:** Structured key-value grid showing `Alert Name`, `Service / Check`, `Target Instance`, `Severity`, and `Status` (`FIRING / ACTIVE` or `RESOLVED / HEALTHY`).
4. **Impact & Recommended Actions:** Operator troubleshooting guide outlining impact and actionable diagnosis steps.
5. **Footer:** Automated platform metadata.

---

## 💾 Persistent Named Volumes

Alertmanager utilizes dedicated named volumes:
* `alertmanager_config`: Stores `alertmanager.yml` (mounted read-only).
* `alertmanager_data`: Stores notification logs and active silence states (mounted read-write).

---

## 🧪 Validation & Testing

Execute static validation for Alertmanager rules and configurations:

```bash
# Static configuration validation
./scripts/validate.sh
```
