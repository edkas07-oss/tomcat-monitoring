# Alertmanager Configuration Contract

Directory ini menyediakan routing alert non-secret untuk dua receiver:
`lab-diagnostic-service` (default receiver via HTTPS webhook ke Diagnostic Service)
dan `direct-email-emergency` (sub-route fallback darurat via direct SMTP ke Mailpit).
Lab baseline menggunakan stable group labels `alertname`, `job`, `instance`, `service`,
dan `check`; `group_wait: 10s`, `group_interval: 15s`, `repeat_interval: 4h`.

Seluruh alert operasional Tomcat (`TomcatDown`, Application Health, JVM GC/Memory,
Concurrency Threading) diteruskan ke `lab-diagnostic-service` untuk evaluasi diagnosis
deterministik multi-domain (TM-ADR-0023). Diagnostic Service kemudian menerbitkan
laporan investigasi 7-seksi ke Mailpit.

Bila terjadi kegagalan pada Diagnostic Service itu sendiri (`DiagnosticServiceDown`),
sub-route darurat `direct-email-emergency` menangkap alert tersebut (`continue: false`)
dan mengirimkan email notifikasi darurat langsung ke Mailpit (TM-ADR-0020).

Alertmanager mengirim email hanya ke Mailpit melalui SMTP internal berikut:

```text
mailpit:1025
```

Sender `alertmanager@tomcat-monitoring.invalid` dan recipient
`operator@tomcat-monitoring.invalid` merupakan synthetic identity pada reserved
domain. Configuration tidak memiliki authentication, credential, relay, atau
personal recipient. Persistent lab runtime tetap tidak membuktikan external
notification flow.

## Diagnostic Route Contract

Default route menggunakan receiver `lab-diagnostic-service` yang
mengirim webhook ke Diagnostic Service via HTTPS:

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

Receiver menggunakan `url_file` dan `credentials_file` yang merujuk ke path
mount non-Git:

```text
/run/secrets/tomcat-monitoring/diagnostic-service-webhook-url
/run/secrets/tomcat-monitoring/diagnostic-service-bearer-token
/run/secrets/tomcat-monitoring/diagnostic-service-ca.crt
```

File-file ini bukan tanggung jawab repository ini dan tidak disimpan di Git.
Mereka dipasang sebagai read-only secret mount oleh deployment orchestration.

Disposable verification Alertmanager → Diagnostic Service tersedia melalui:

```bash
temporary_root="$(mktemp -d /tmp/tm-tn014-diagnostic-route.XXXXXX)"
./scripts/prepare-alertmanager-diagnostic-service.sh "${temporary_root}"
DIAGNOSTIC_IMAGE='localhost/tomcat-diagnostic-service@sha256:<digest>' \
  ./scripts/verify-alertmanager-diagnostic-service.sh "${temporary_root}"
```

Verifier script menggunakan container `tm-tn014-alertmanager` dan
`tm-tn014-diagnostic-service` pada network `tm-tn014-diagnostic-route`.
Cleanup hanya dijalankan setelah authorization terpisah (pola TN-013).
Evidence: SQLite probe via `fixtures/alertmanager-diagnostic-route/probe.js`.


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

Subject wajib mengikuti format Enterprise SRE berikut:

```text
[<RESOLVED|CRITICAL|WARNING>] [LAB] Tomcat Service: <presentation-alert-name> (Instance: <instance>)
```

Subject dan email body menggunakan operator severity yang selaras: `RESOLVED` /
`normal` untuk resolved notification, `WARNING` / `warning` untuk firing
warning, dan `CRITICAL` / `critical` untuk firing critical. Normal memakai
banner hijau `#2e7d32`, warning oranye `#ef6c00`, dan critical merah `#c62828`
dengan badge `LAB Environment`.

Layout email body menggunakan format Modern SRE & Incident Operations yang
terstruktur:

1. **Header Banner**: Menampilkan status alert/recovery, judul layanan, dan
   badge environment (`LAB Environment`).
2. **Alert / Recovery Summary**: Box ringkasan berlatar halus dengan aksen warna
   kiri (`⚠️ Alert Summary` atau `✅ Recovery Summary`) yang menyajikan deskripsi
   aktif saat gangguan atau pesan pemulihan saat normal.
3. **Technical Details**: Grid key-value rapi yang menampilkan `Alert Name`,
   `Service / Check`, `Target Instance`, `Severity`, dan `Status` (`FIRING / ACTIVE`
   atau `RESOLVED / HEALTHY`).
4. **Impact & Recommended Actions**: Panduan operasional yang memuat dampak
   gangguan dan langkah diagnosis cepat bagi tim operator/on-call.
5. **Footer**: Metadata notifikasi otomatis platform tanpa memuat link internal
   yang tidak dapat diakses operator.

Body field contract berlaku identik untuk firing dan resolved:

| Key | Firing Value | Resolved Value |
| --- | --- | --- |
| Alert Name | Internal negative-condition name | Positive presentation name |
| Service / Check | Stable service / check labels | Stable service / check labels |
| Target Instance | Stable alert instance (Job: job name) | Stable alert instance (Job: job name) |
| Severity | Rule severity `warning` atau `critical` | `normal` |
| Status | `FIRING / ACTIVE` | `RESOLVED / HEALTHY` |

Template tidak boleh menampilkan internal `firing/resolved` mentah sebagai
operator severity, negative alert name pada normal email, stale firing
description pada normal email, empty `service`/`check`, atau inaccessible
Alertmanager link.

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
