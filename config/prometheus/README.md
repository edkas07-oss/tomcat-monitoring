# Prometheus Configuration Contract

Directory ini menyimpan scrape configuration non-secret Prometheus. Contract
awal menggunakan dua target internal pada container network yang sama:

- JMX Exporter melalui `https://tomcat-jmx-exporter:9404/metrics` dengan
  verifikasi CA dari
  `/run/secrets/tomcat-monitoring/jmx-exporter-ca.crt`; dan
- Telegraf melalui `http://telegraf:9273/metrics`.

Global scrape interval adalah `30s` dengan timeout `10s`. Alias target harus
tersedia pada network runtime. Certificate, private key, credential, dan
material environment-specific tidak boleh disimpan di directory ini.

`rules/application-health.yml` memisahkan tiga signal berdasarkan contract
TN-023:

- Telegraf scrape unavailable dengan severity `warning`;
- expected application-health metric missing ketika scrape sehat dengan
  severity `warning`; dan
- application-health result non-zero ketika scrape sehat dengan severity
  `critical`.

Ketiga alert menggunakan lab baseline `for: 2m`. Prometheus memuat rule dari
`/etc/prometheus/rules/*.yml`.

Jalankan source-level validation dengan:

```bash
./scripts/validate-prometheus.sh
```

Validator tersebut memeriksa contract statis tanpa membuktikan semantic YAML,
resolusi target, TLS handshake, scrape, storage, atau deployment. Semantic
fixture tersedia pada `tests/application-health.test.yml` dan dijalankan dengan
`promtool check rules`, `promtool check config`, serta `promtool test rules`
dalam verification scope yang disetujui.

Retention, persistent rule application, deployment target production, dan
production certificate lifecycle belum ditetapkan.

## Named Volumes

Lab runtime menggunakan named volume tanpa host bind:

- `prometheus_config` untuk `prometheus.yml`;
- `prometheus_truststore` untuk CA JMX Exporter; dan
- `prometheus_data` untuk time-series data.

Configuration dan truststore dipasang read-only pada Prometheus container,
sedangkan data dipasang read-write. Inisialisasi dilakukan dari repository
integration dengan:

```bash
./scripts/initialize-prometheus-volumes.sh /path/to/jmx-exporter-ca.crt
```

Script menyalin main configuration, alert rules, dan CA ke Podman volumes
menggunakan `podman cp`, bukan host bind. Data yang sudah ada pada
`prometheus_data` tidak dihapus.

## Missing-Metric Verification Fixture

`fixtures/prometheus-empty-metrics/metrics` merupakan valid empty Prometheus
exposition untuk verification terkontrol. Responder `respond.sh` menyajikannya
dengan HTTP `200` dan Prometheus-compatible content type melalui disposable
BusyBox `nc` container beralias `telegraf`. Prometheus menghasilkan target
`up=1`, tetapi expected `http_response_result_code` series tidak tersedia.

Fixture hanya digunakan pada approved lab verification. Ia bukan Telegraf
configuration dan tidak menggantikan persistent health collector.

## Persistent Lab Result

Pada 2026-08-26, persistent lab Prometheus memuat ketiga rules dan memverifikasi
boundary berikut dengan `for: 2m`:

- non-zero Telegraf result hanya memicu application-failed alert;
- scrape `up=1` tanpa result series hanya memicu missing-metric alert;
- scrape `up=0` hanya memicu scrape-unavailable alert; dan
- pemulihan original Telegraf mengembalikan seluruh alert ke inactive.

Hasil tersebut membuktikan lab rule behavior. Ia tidak membuktikan
Alertmanager routing, notification delivery, TrueSight integration, atau
production application semantics.
