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
personal recipient. Persistent lab runtime tetap tidak membuktikan external
notification flow.

Jalankan static validation dengan:

```bash
./scripts/validate-alertmanager.sh
```

Static validation tidak menggantikan `amtool check-config`, isolated SMTP
capture test, Prometheus delivery, persistence, atau end-to-end verification.

## Persistent Named Volumes

Persistent lab Alertmanager menggunakan named volume tanpa host bind:

- `alertmanager_config` untuk `alertmanager.yml`; dan
- `alertmanager_data` untuk notification log serta silence state.

Configuration dipasang read-only pada runtime, sedangkan data dipasang
read-write. Inisialisasi dilakukan dari repository integration dengan:

```bash
./scripts/initialize-alertmanager-volumes.sh
```

Initializer menyalin configuration melalui `podman cp`, mempertahankan data
yang sudah tersedia, dan hanya membersihkan exact initializer container. Ia
tidak menghapus named volume atau persistent Alertmanager.

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
