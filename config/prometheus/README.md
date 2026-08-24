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

Jalankan source-level validation dengan:

```bash
./scripts/validate-prometheus.sh
```

Validator tersebut memeriksa contract statis tanpa membuktikan semantic YAML,
resolusi target, TLS handshake, scrape, storage, atau deployment. Semantic
validation menggunakan `promtool check config` memerlukan verification scope
terpisah.

Storage, retention, alert rules, deployment target, dan certificate lifecycle
belum ditetapkan.

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

Script menyalin file ke Podman volumes menggunakan `podman cp`, bukan host
bind. Data yang sudah ada pada `prometheus_data` tidak dihapus.
