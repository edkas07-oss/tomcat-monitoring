# Event Collector Configuration & Threshold Guide

Direktori ini berisi dokumentasi resmi spesifikasi parameter konfigurasi, kontrak retensi berkas *spool*, dan mekanisme manajemen ambang batas (*threshold management*) untuk **Tomcat Diagnostic Event Collector** dari sudut pandang orkestrator platform `tomcat-monitoring`.

---

## 📑 Daftar Isi

- [🏛️ Peran dalam Ekosistem Monitoring](#️-peran-dalam-ekosistem-monitoring)
- [📊 Matriks Ambang Batas & Konfigurasi (*Threshold Matrix*)](#-matriks-ambang-batas--konfigurasi-threshold-matrix)
- [🔒 Kontrak Hak Akses & Persistensi (Zero `/tmp` Policy)](#-kontrak-hak-akses--persistensi-zero-tmp-policy)
- [🔧 Panduan Operasional SRE: Penyesuaian Threshold](#-panduan-operasional-sre-penyesuaian-threshold)
- [🛠️ Siklus Hidup Daemon `systemd --user`](#️-siklus-hidup-daemon-systemd---user)

---

## 🏛️ Peran dalam Ekosistem Monitoring

Event Collector adalah daemon *host-side rootless* yang berjalan di bawah supervisor `systemd --user`. Daemon ini bertugas menangkap event container Podman (`died`, `stop`, `start`, `oom`, `restart`) secara real-time dan menuliskan bukti diagnosis (*evidence record*) dalam format JSON atomik ke direktori spool persisten.

Diagnostic Service kemudian me-mount direktori spool ini secara *read-only* (`ro,z`) untuk mengorelasikan bukti status container saat memproses alert insiden dari Alertmanager.

---

## 📊 Matriks Ambang Batas & Konfigurasi (*Threshold Matrix*)

Ambang batas dikelola secara deklaratif pada [`CONFIG`](file:///home/eddywiyatno/git/tomcat-diagnostic-event-collector/CONFIG) di repositori `tomcat-diagnostic-event-collector` sebagai *Single Source of Truth* (SSOT):

| Parameter Threshold | Nilai Bawaan (*Default*) | Satuan / Tipe | Dampak Operasional & Logika Pemangkasan |
| :--- | :---: | :---: | :--- |
| **`MAX_SPOOL_AGE_HOURS`** | `24` | Jam (Integer) | **Retensi Waktu:** Berkas `.json` berusia $> 24\text{ jam}$ dihapus otomatis saat startup dan setiap siklus event. |
| **`MAX_SPOOL_FILES`** | `1000` | Berkas (Integer) | **Batas Kapasitas Kuota:** Jika total file `.json` di direktori spool melebihi 1000, berkas terlama dipangkas (*FIFO pruning*). |
| **`STALE_TMP_AGE_MINUTES`** | `60` | Menit (Integer) | **Batas Berkas Yatim:** Berkas `.tmp` yang tidak selesai $> 60\text{ menit}$ akibat proses crash/terhenti dibersihkan otomatis. |
| **`MAX_RECORD_BYTES`** | `16384` | Bytes (16 KiB) | **Batas Payload:** Rekaman yang melebihi 16 KiB ditolak untuk mencegah lonjakan alokasi memori. |

---

## 🔒 Kontrak Hak Akses & Persistensi (Zero `/tmp` Policy)

* **Jalur Penyimpanan Spool:** `${HOME}/.local/share/tomcat-monitoring/spool` (tidak menggunakan direktori `/tmp` yang volatile).
* **Mode Izin Direktori:** Wajib mode `0700` (`drwx------`), terisolasi hanya untuk user session rootless.
* **Mode Izin Berkas Bukti:** Setiap berkas record bukti dibuat dengan mode `0600` (`-rw-------`).
* **Konsumsi Read-Only:** Container `diagnostic-service` membaca direktori ini melalui volume mount Podman `--volume "${SPOOL_DIR}:/run/tomcat-diagnostic/spool:ro,z"`.

---

## 🔧 Panduan Operasional SRE: Penyesuaian Threshold

Untuk mengubah ambang batas retensi atau batas kuota kapasitas direktori spool secara terstruktur:

```bash
# 1. Edit berkas deklaratif CONFIG di repositori event collector
nano /home/eddywiyatno/git/tomcat-diagnostic-event-collector/CONFIG

# 2. Jalankan validasi integritas repositori
/home/eddywiyatno/git/tomcat-diagnostic-event-collector/scripts/validate.sh

# 3. Terapkan pembaruan melalui redeploy atau restart daemon
/home/eddywiyatno/git/tomcat-monitoring/scripts/deploy-event-collector.sh
# ATAU
systemctl --user restart tomcat-diagnostic-event-collector.service

# 4. Verifikasi status dan parameter aktif daemon
systemctl --user status tomcat-diagnostic-event-collector.service --no-pager
```

---

## 🛠️ Siklus Hidup Daemon `systemd --user`

Unit service dikelola oleh systemd user instance pada:
`~/.config/systemd/user/tomcat-diagnostic-event-collector.service`

```bash
# Cek status aktif daemon
systemctl --user status tomcat-diagnostic-event-collector.service

# Membaca log live audit daemon
journalctl --user -u tomcat-diagnostic-event-collector.service -f

# Memeriksa direktori spool dan berkas event
ls -la ~/.local/share/tomcat-monitoring/spool
```
