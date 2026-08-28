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

## Alert Template Contract

Prometheus dan Alertmanager mempertahankan internal `alertname` serta rule
severity yang stabil selama firing/resolved lifecycle. Stability tersebut
diperlukan untuk grouping, deduplication, notification log, dan correlation;
resolved notification tidak mengubah source labels.

Email presentation menerjemahkan internal lifecycle menjadi status yang dapat
dibaca operator:

| Internal State | Rule Severity | Operator Severity | Color |
| --- | --- | --- | --- |
| `firing` | `warning` | `warning` | Orange `#ef6c00` |
| `firing` | `critical` | `critical` | Red `#c62828` |
| `resolved` | `warning` atau `critical` | `normal` | Green `#2e7d32` |

Resolved presentation juga menggunakan positive alert name dan description:

| Internal Alert Name | Firing Presentation | Resolved Presentation |
| --- | --- | --- |
| `TelegrafHealthScrapeUnavailable` | `TelegrafHealthScrapeUnavailable` | `TelegrafHealthScrapeAvailable` |
| `TomcatApplicationHealthMetricsMissing` | `TomcatApplicationHealthMetricsMissing` | `TomcatApplicationHealthMetricsAvailable` |
| `TomcatApplicationHealthFailed` | `TomcatApplicationHealthFailed` | `TomcatApplicationHealthNormal` |

Subject wajib mengikuti satu format untuk seluruh lifecycle:

```text
[Tomcat Monitoring][<normal|warning|critical>] <presentation-alert-name> - <instance>
```

Subject dan email body menggunakan operator severity yang sama: `normal` untuk
resolved notification, `warning` untuk firing warning, dan `critical` untuk
firing critical. Normal memakai banner hijau, warning oranye, dan critical
merah. Kedua state memakai key body yang identik—`Alert name`, `Instance`,
`Job`, `Severity`, `Service`, `Check`, dan `Description`—serta hanya mengganti
value. Untuk resolved `TelegrafHealthScrapeUnavailable`, presentation layer
menampilkan `TelegrafHealthScrapeAvailable`, severity `normal`, dan description
bahwa Prometheus kembali dapat scrape. Internal Prometheus `alertname` tetap
stabil agar firing/resolved correlation tidak rusak.

Body field contract berlaku identik untuk firing dan resolved:

| Key | Firing Value | Resolved Value |
| --- | --- | --- |
| Alert name | Internal negative-condition name | Positive presentation name |
| Instance | Stable alert instance | Stable alert instance |
| Job | Stable alert job | Stable alert job |
| Severity | Rule severity `warning` atau `critical` | `normal` |
| Service | Stable service label | Stable service label |
| Check | Stable check label | Stable check label |
| Description | Active rule description | Positive recovery description |

Template tidak boleh menampilkan internal `firing/resolved` sebagai operator
severity, negative alert name pada normal email, stale firing description pada
normal email, empty `service`/`check`, atau field key yang berbeda antara kedua
states.

Custom body tidak menampilkan default `View in Alertmanager` link. Persistent
Alertmanager API tidak dipublikasikan ke host, sehingga URL yang dibuat dari
internal container hostname tidak operator-accessible. Mailpit UI tetap menjadi
operator-facing notification review interface tanpa membuka port Alertmanager
baru.

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
