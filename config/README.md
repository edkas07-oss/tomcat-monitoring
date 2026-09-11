# ⚙️ Configuration Contract & Platform-Wide Threshold Matrix

Direktori ini menyimpan seluruh artefak konfigurasi non-secret dan spesifikasi parameter untuk orkestrasi platform **Tomcat Monitoring & Autonomous Diagnostic Platform**.

---

## 📑 Daftar Isi

- [🏛️ Prinsip Tata Kelola Konfigurasi](#️-prinsip-tata-kelola-konfigurasi)
- [📂 Katalog Komponen Konfigurasi](#-katalog-komponen-konfigurasi)
- [📊 Matriks Ambang Batas Platform Terpusat (*Platform-Wide Threshold Matrix*)](#-matriks-ambang-batas-platform-terpusat-platform-wide-threshold-matrix)
- [🔒 Kebijakan Rahasia & Zero `/tmp` Policy](#-kebijakan-rahasia--zero-tmp-policy)

---

## 🏛️ Prinsip Tata Kelola Konfigurasi

1. **Non-Secret Declarative Baseline:** Seluruh berkas konfigurasi di bawah direktori ini adalah deklarasi non-secret yang tercatat di Git (*version-controlled*).
2. **Runtime Secret Injection:** Kredensial, kunci privat TLS, password keystore, dan Bearer Token diinjeksikan secara terpisah saat runtime melalui *mounted secret files* berizin ketat (`0400`/`0444`) di `${HOME}/.local/share/tomcat-monitoring/`.
3. **Pre-Flight Static Validation:** Setiap berkas konfigurasi divalidasi oleh [`scripts/validate.sh`](../scripts/validate.sh) sebelum dapat di-deploy ke lingkungan runtime `devops-lab`.

---

## 📂 Katalog Komponen Konfigurasi

| Direktori Komponen | Berkas Konfigurasi Utama | Deskripsi & Peran | Panduan Teknis |
| :--- | :--- | :--- | :--- |
| **`alertmanager/`** | `alertmanager.yml` | Konfigurasi perutean webhook HTTPS Diagnostic Service & rute darurat direct SMTP. | [`alertmanager/README.md`](alertmanager/README.md) |
| **`diagnostic-service/`** | `application.json`, `targets.json` | Konfigurasi engine diagnostik, allowlist targets, TLS, and enterprise SMTP relay. | [`diagnostic-service/README.md`](diagnostic-service/README.md) |
| **`event-collector/`** | *Declarative CONFIG* | Spesifikasi daemon restricted collector, kontrak spool persisten, dan batas retensi. | [`event-collector/README.md`](event-collector/README.md) |
| **`jmx-exporter/`** | `jmx-exporter.yml` | Pola filter MBean JVM Heap, GC, Thread Pool, dan binding port HTTPS. | [`jmx-exporter/README.md`](jmx-exporter/README.md) |
| **`prometheus/`** | `prometheus.yml`, `rules/*.yml` | Scrape targets, TSDB storage retention, dan alert evaluation rules. | [`prometheus/README.md`](prometheus/README.md) |
| **`rules/`** | `curated-production-rulepacks.json` | Master catalog dynamic rulepacks hasil kurasi untuk continuous learning. | [`rules/`](rules/) |
| **`telegraf/`** | `health-check.conf` | Konfigurasi agent probe HTTP endpoint aplikasi `/health`. | [`telegraf/README.md`](telegraf/README.md) |

---

## 📊 Matriks Ambang Batas Platform Terpusat (*Platform-Wide Threshold Matrix*)

Platform ini menerapkan batasan ambang batas (*bounded thresholds*) terpadu di seluruh komponen untuk menjamin ketersediaan, stabilitas storage, dan akurasi alerting:

| Komponen | Domain / Aspek | Nama Parameter / Rule | Nilai Ambang Batas (*Threshold*) | Logika Evaluasi & Dampak Operasional |
| :--- | :--- | :--- | :---: | :--- |
| **`event-collector`** | Spool Storage | `MAX_SPOOL_AGE_HOURS` | `24 jam` | Berkas `.json` berusia $> 24\text{h}$ dipangkas otomatis saat startup dan event loop. |
| **`event-collector`** | Spool Storage | `MAX_SPOOL_FILES` | `1000 berkas` | Penegakan kuota kapasitas via *FIFO pruning* (menghapus file tertua saat event storm). |
| **`event-collector`** | Spool Storage | `STALE_TMP_AGE_MINUTES` | `60 menit` | Berkas `.tmp` terlantar akibat proses crash dibersihkan otomatis. |
| **`event-collector`** | Payload Boundary | `MAX_RECORD_BYTES` | `16 KiB` | Batas payload maksimum per record event untuk mencegah pembengkakan memori. |
| **`prometheus`** | TSDB Storage | `--storage.tsdb.retention.time` | `15d` (15 hari) | Retensi time-series metrik di volume persisten `prometheus_data`. |
| **`prometheus`** | Scrape Interval | `scrape_interval` | `30s` / `15s` | Interval penarikan metrik target Tomcat (`30s`) dan Diagnostic Service (`15s`). |
| **`prometheus`** | Alert: Availability | `TomcatDown` | `up == 0` (`for: 1m`) | Memicu firing jika target Tomcat tidak responsif selama $> 1\text{ menit}$. |
| **`prometheus`** | Alert: Self-Health | `DiagnosticServiceDown` | `up == 0` (`for: 1m`) | Memicu rute darurat direct SMTP Alertmanager jika Diagnostic Service mati. |
| **`prometheus`** | Alert: GC STW Pause | `TomcatGCPauseHigh` | `max > 1.5s` (`for: 1m`) | Mendeteksi jeda *Stop-The-World* GC kritis sebelum terjadi latency spike. |
| **`prometheus`** | Alert: GC Overhead | `TomcatGCOverheadHigh` | `rate(gc_sum) * 100 > 15%` (`for: 5m`) | Mendeteksi *GC Thrashing* di mana CPU dihabiskan untuk siklus GC. |
| **`prometheus`** | Alert: Old Gen | `TomcatOldGenMemoryPressure` | `used/max * 100 > 90%` (`for: 10m`) | Retensi memori Old Gen tinggi persisten (gejala kebocoran memori). |
| **`prometheus`** | Alert: Concurrency | `TomcatThreadPoolSaturated` | `busy/current >= 1.0` (`for: 5m`) | Kejenuhan penuh 100% pada Tomcat Connector thread pool. |
| **`alertmanager`** | Alert Routing | `group_wait` / `group_interval` | `10s` / `1m` | Jeda agregasi alert sebelum dikirim ke Webhook Diagnostic Service. |
| **`alertmanager`** | Alert Routing | `repeat_interval` | `12h` | Pengulangan notifikasi untuk insiden yang belum terselesaikan. |
| **`diagnostic-service`**| State Resilience | `lease_expires_at` | `5 menit` | Batas sewa claim worker. Event processing $> 5\text{m}$ otomatis di-requeue (*Stale Lock Recovery*). |
| **`diagnostic-service`**| State Resilience | `maxRetries` | `3 kali` | Batas retry pemrosesan event sebelum dialihkan ke status `failed`. |
| **`diagnostic-service`**| DB Retention | `retentionDays` | `30 hari` | Pembersihan data historis SQLite lama dan eksekusi `PRAGMA incremental_vacuum`. |
| **`diagnostic-service`**| Evidence Timeout | `timeoutMs` | `5000 ms` | Batas waktu pengambilan bukti Prometheus live tanpa memblokir rantai evaluasi. |

---

## 🔒 Kebijakan Rahasia & Zero `/tmp` Policy

* Jangan pernah meletakkan file rahasia (`.pem`, `.key`, `.p12`, `.jks`, `.env`, atau kredensial) di dalam direktori `config/`.
* Seluruh komponen menggunakan **Podman Named Volumes** (`tomcat_logs`, `diagnostic_data`, `prometheus_data`, `alertmanager_data`) dan direktori terisolasi host (`0700`/`0400`) di `${HOME}/.local/share/tomcat-monitoring/`.
