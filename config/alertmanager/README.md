# Alertmanager Configuration Contract

Directory ini menyediakan routing alert non-secret untuk local Mailpit
receiver `lab-mailpit`. Lab baseline menggunakan stable group labels
`alertname`, `job`, `instance`, `service`, dan `check`; `group_wait: 30s`,
`group_interval: 5m`, `repeat_interval: 4h`, serta `send_resolved: true`.

Alertmanager mengirim email hanya ke Mailpit melalui SMTP internal berikut:

```text
mailpit:1025
```

Sender `alertmanager@tomcat-monitoring.invalid` dan recipient
`operator@tomcat-monitoring.invalid` merupakan synthetic identity pada reserved
domain. Configuration tidak memiliki authentication, credential, relay, atau
personal recipient dan belum mengotorisasi persistent runtime maupun external
notification flow.

Jalankan static validation dengan:

```bash
./scripts/validate-alertmanager.sh
```

Static validation tidak menggantikan `amtool check-config`, isolated SMTP
capture test, Prometheus delivery, persistence, atau end-to-end verification.

Jalankan isolated firing/resolved Mailpit verification dengan:

```bash
./scripts/verify-alertmanager-mailpit.sh
```

Interface ini menggunakan exact disposable network dan containers TN-033,
mempublikasikan hanya loopback Mailpit API serta Alertmanager API, dan tidak
mempublikasikan SMTP. Mailpit image dipertahankan setelah exact runtime cleanup.

Jalankan isolated firing/resolved webhook verification dengan:

```bash
./scripts/verify-alertmanager-webhook.sh
```

Verification interface historis TN-029 membuat receiver dan configuration
webhook synthetic pada temporary directory serta membersihkan exact disposable
runtime. Ia tetap tersedia untuk regression contract, tetapi bukan active lab
receiver. Hasilnya tidak membuktikan lab timing baseline, persistent
Prometheus delivery, Integration Bridge, atau TrueSight.
