# Alertmanager Configuration Contract

Directory ini menyediakan routing alert non-secret untuk generic webhook
receiver `integration-bridge`. Lab baseline menggunakan stable group labels
`alertname`, `job`, `instance`, `service`, dan `check`; `group_wait: 30s`,
`group_interval: 5m`, `repeat_interval: 4h`, serta `send_resolved: true`.

Webhook endpoint tidak disimpan pada configuration. Alertmanager membaca URL
dari file runtime berikut:

```text
/run/secrets/tomcat-monitoring/integration-bridge-webhook-url
```

Secret provider, actual endpoint, authentication, TLS trust, Integration
Bridge ownership, dan TrueSight mapping belum ditetapkan. Configuration ini
belum mengotorisasi persistent receiver atau external notification flow.

Jalankan static validation dengan:

```bash
./scripts/validate-alertmanager.sh
```

Static validation tidak menggantikan `amtool check-config`, isolated webhook
test, Prometheus delivery, persistence, atau end-to-end verification.
