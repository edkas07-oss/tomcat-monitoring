# Telegraf Configuration Contract & Application Health Probing

This directory provides the `inputs.http_response` configuration for actively probing target Tomcat `/health` endpoints over the container network.

---

## ⚙️ Probe Specifications (`health-check.conf`)

* **Target URL:** Configured via `${TOMCAT_HEALTH_URL}` (defaults to `http://tomcat-jmx-exporter:8080/health`).
* **Expected Response:** HTTP Status `200` with body substring `UP`.
* **Probe Interval:** `30s` with a `5s` timeout.
* **Output Plugin:** Prometheus client endpoint exporting metrics at `:9273/metrics`.

---

## 🧪 Validation

Run repository static validation:

```bash
./scripts/validate.sh
```
