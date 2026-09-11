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

- Telegraf scrape unavailable dengan severity `critical` karena monitoring
  target mati dan application-health state tidak dapat ditentukan;
- expected application-health metric missing ketika scrape sehat dengan
  severity `warning`; dan
- application-health result non-zero ketika scrape sehat dengan severity
  `critical`.

Ketiga alert menggunakan lab baseline `for: 2m`. Prometheus memuat rule dari
`/etc/prometheus/rules/*.yml`.

Ketiga alert juga menyediakan `service=tomcat` dan
`check=application-health` agar notification body memakai key yang sama tanpa
field kosong. Alertmanager memetakan resolved state menjadi operator status
`normal`; firing state mempertahankan rule severity `warning` atau `critical`.

Prometheus meneruskan firing dan resolved alert melalui API v2 ke internal
target `alertmanager:9093`. Reference ini hanya menetapkan delivery target pada
container network; ia tidak membuktikan Alertmanager tersedia atau notification
diterima receiver.

Jalankan source-level validation dengan:

```bash
./scripts/validate-prometheus.sh
```

Semua alert rule divalidasi secara otomatis melalui `scripts/validate-prometheus.sh` dan unit test promtool pada `tests/application-health.test.yml`.

## Persistent Storage, Retention & TSDB Contract

Prometheus runtime menerapkan kontrak penyimpanan data historis berbasis TSDB:

- **Storage Engine:** Prometheus Time Series Database (TSDB) dengan Write-Ahead Log (WAL) 2-jam per blok.
- **Data Retention Policy:** Retensi data historis aktif selama **15 hari (`15d`)** secara *rolling compaction*.
- **Volume Persisten:** Podman Named Volume `prometheus_data` dipasang pada path container `/prometheus`.
- **Durabilitas Data:** Replay WAL otomatis saat container restart tanpa kehilangan metrik time-series.
- **Web Lifecycle Management:** Flag `--web.enable-lifecycle` aktif, memungkinkan *zero-downtime hot-reload* via HTTP POST.

---

## 🛠️ Panduan Operasional SRE (How-To Configuration & Operations SOP)

Bagian ini memuat panduan langkah-demi-langkah bagi SRE on-call dan engineer operasional untuk memodifikasi konfigurasi Prometheus, menyesuaikan retensi data, menambah alert rules, dan menerapkan perubahan ke runtime.

### 1. Menyesuaikan Kebijakan Retensi Data (Time & Size Based)

Secara default, Prometheus menyimpan metrik selama 15 hari. Jika host memiliki batasan disk atau memerlukan retensi lebih lama:

- **Opsi Durasi Waktu (`PROMETHEUS_RETENTION_TIME`):** Mengatur masa simpan (misal `7d`, `15d`, `30d`, `60d`).
- **Opsi Batas Ukuran Disk (`PROMETHEUS_RETENTION_SIZE`):** Membatasi ukuran total data TSDB di disk (misal `5GB`, `10GB`).

**Langkah Penerapan:**
Jalankan skrip deploy dengan mengekspor variabel lingkungan yang diinginkan:

```bash
# Contoh 1: Mengubah retensi menjadi 30 hari
PROMETHEUS_RETENTION_TIME="30d" ./scripts/deploy-prometheus.sh

# Contoh 2: Mengubah retensi menjadi 7 hari dengan batas kapasitas 5 GB
PROMETHEUS_RETENTION_TIME="7d" PROMETHEUS_RETENTION_SIZE="5GB" ./scripts/deploy-prometheus.sh
```

> **Catatan Keamanan Data:** Volume data `prometheus_data` tidak akan dihapus atau di-reset saat deployment ulang dijalankan. Seluruh data historis yang belum melewati batas retensi baru akan tetap aman tersimpan.

---

### 2. Menyesuaikan Scrape Interval & Timeout Target

Jika SRE ingin mempercepat deteksi degradasi atau menghemat penggunaan CPU/jaringan:

1. Buka dan edit berkas [`config/prometheus/prometheus.yml`](prometheus.yml):
   ```yaml
   global:
     scrape_interval: 30s    # Ubah global scrape interval (misal: 15s)
     scrape_timeout: 10s     # Ubah global scrape timeout
   
   scrape_configs:
     - job_name: "tomcat-jmx-exporter"
       scrape_interval: 15s  # Atau atur khusus per-job
   ```
2. Validasi integritas sintaks konfigurasi:
   ```bash
   promtool check config config/prometheus/prometheus.yml
   ```
3. Terapkan perubahan ke runtime menggunakan metode **Hot-Reload (Zero Downtime)** di bawah.

---

### 3. Menambah atau Mengubah Alert Rules

Jika threshold peringatan (seperti GC latency atau Thread Pool) perlu disesuaikan dengan pola trafik aplikasi:

1. Edit berkas rule terkait di `config/prometheus/rules/` (misal: `jvm-workload-performance.yml` atau `application-health.yml`).
2. Jalankan pengujian unit promtool untuk memastikan logika evaluasi valid:
   ```bash
   promtool test rules config/prometheus/tests/*.test.yml
   ```
3. Validasi aturan dengan validator repositori:
   ```bash
   ./scripts/validate-prometheus.sh
   ```
4. Terapkan perubahan ke runtime menggunakan metode **Hot-Reload**.

---

### 4. Prosedur Menerapkan Perubahan (Hot-Reload vs Redeployment)

#### A. Metode Hot-Reload (Rekomendasi Utama — Zero Downtime)
Gunakan metode ini ketika hanya mengubah `prometheus.yml` atau file rules di `rules/*.yml` tanpa mengubah parameter startup container:

```bash
# 1. Sinkronkan perubahan konfigurasi ke Named Volume Prometheus
./scripts/initialize-prometheus-volumes.sh ~/.local/share/tomcat-monitoring/jmx-exporter-tls/server.crt

# 2. Panggil endpoint lifecycle reload Prometheus
curl -X POST http://127.0.0.1:9090/-/reload
```

*Verifikasi log:* Periksa log container untuk memastikan konfigurasi berhasil di-reload:
```bash
podman logs --tail 20 prometheus | grep "Completed loading of configuration file"
```

#### B. Metode Redeployment (Diperlukan Jika Mengubah Retention / Flag Container)
Gunakan metode ini jika mengubah variabel `PROMETHEUS_RETENTION_TIME`, port binding, atau opsi container:

```bash
./scripts/deploy-prometheus.sh
```

---

### 5. Memantau Status & Kapasitas Penyimpanan TSDB

SRE dapat memantau kesehatan dan ukuran penyimpanan TSDB melalui beberapa cara:

1. **Prometheus Web UI (TSDB Status):**
   - Akses browser ke `http://<host>:9090/status` lalu pilih menu **TSDB Status**.
   - Halaman ini menampilkan *Head Stats*, *Top 10 Series by Cardinality*, dan ringkasan *Chunk Blocks*.
2. **Kueri PromQL Kesehatan TSDB:**
   - Pertumbuhan data per detik: `rate(prometheus_tsdb_head_samples_appended_total[5m])`
   - Ukuran total blok data TSDB: `prometheus_tsdb_storage_blocks_bytes`
   - Total pemangkasan data kadaluwarsa: `prometheus_tsdb_tombstones_applied_total`
3. **Pemeriksaan Direktori Fisik di Host:**
   ```bash
   # Ambil path mountpoint volume data
   mountpoint=$(podman volume inspect prometheus_data --format '{{.Mountpoint}}')
   
   # Cek ukuran fisik disk
   du -sh "${mountpoint}"
   ```

---

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

