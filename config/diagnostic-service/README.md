# Diagnostic Service Configuration Guide

Direktori ini berisi konfigurasi resmi untuk runtime **Tomcat Diagnostic Service** pada platform monitoring.

---

## 📁 Struktur Berkas

```text
config/diagnostic-service/
├── application.json    # Berkas konfigurasi utama aplikasi (listen, tls, smtp, prometheus, queue)
├── targets.json        # Berkas target allowlist instans Tomcat yang dimonitor
└── README.md           # Petunjuk dan spesifikasi parameter konfigurasi
```

---

## ⚙️ Spesifikasi Parameter Konfigurasi (`application.json`)

### 1. Blok SMTP (`"smtp"`)

Blok `"smtp"` mengatur rute pengiriman laporan investigasi 7-seksi SRE via email ke relay MTA atau Mailpit:

```json
"smtp": {
  "host": "postfix-relay",
  "port": 587,
  "secure": false,
  "requireTLS": true,
  "usernameFile": "/run/tomcat-diagnostic/secrets/smtp-username",
  "passwordFile": "/run/tomcat-diagnostic/secrets/smtp-password",
  "from": "diagnostic@tomcat-monitoring.invalid",
  "to": "operator@tomcat-monitoring.invalid"
}
```

| Parameter | Tipe Data | Wajib | Keterangan |
| :--- | :---: | :---: | :--- |
| **`host`** | `string` | Ya | Hostname atau IP server SMTP / Relay (misal: `"postfix-relay"`, `"mail.corp.local"`). |
| **`port`** | `integer` | Ya | Port SMTP (`587` untuk STARTTLS Submission, `465` untuk SSL langsung, `25`/`1025`). |
| **`secure`** | `boolean` | Ya | `true` jika koneksi SSL/TLS langsung (port 465), `false` jika menggunakan STARTTLS (port 587) atau port 25. |
| **`requireTLS`** | `boolean` | Tidak | Jika `true`, Nodemailer mewajibkan enkripsi TLS dan menolak fallback ke plaintext. |
| **`usernameFile`** | `string` | Opsional | Path absolut ke file teks yang memuat username SMTP (di-mount ke container). |
| **`passwordFile`** | `string` | Opsional | Path absolut ke file teks yang memuat password SMTP (di-mount ke container). |
| **`from`** | `string` | Ya | Alamat email resmi pengirim laporan diagnosis. |
| **`to`** | `string` | Ya | Alamat email tujuan penerima notifikasi (tim SRE / On-call engineer). |

---

### 2. Blok Server & Keamanan (`"listen"`, `"tls"`, `"bearerTokenFile"`)

- **`listen`**: Host (`0.0.0.0`) dan port (`8443`) antarmuka HTTPS internal.
- **`tls`**: Lokasi file sertifikat publik (`certificateFile`) dan kunci privat (`privateKeyFile`).
- **`bearerTokenFile`**: Lokasi file rahasia Bearer Token untuk autentikasi webhook Alertmanager dan Rules API.

---

### 3. Blok Prometheus & Telemetri Bukti (`"prometheus"`)

- **`baseUrl`**: URL internal Prometheus server (`http://prometheus:9090`) untuk penarikan bukti metrik live (*instant query snapshot*).

---

### 4. Blok Antrean & Ketahanan State (`"queue"`)

- **`capacity`**: Kapasitas maksimum antrean bounded FIFO (`50`).
- **`pollIntervalMs`**: Interval polling worker terhadap database (`250` ms).
- **`staleLockTimeoutMs`**: Batas waktu sewa lock pemrosesan sebelum status event di-recover (`300000` ms / 5 menit).
- **`maxRetries`**: Batas maksimum percobaan ulang event sebelum ditandai failed (`3`).
- **`retentionDays`**: Batas retensi pembersihan rekam data historis SQLite (`30` hari).
- **`housekeepingIntervalMs`**: Interval eksekusi rutinitas pruning data SQLite (`86400000` ms / 24 jam).

---

## 🔐 Manajemen Secrets & Keamanan (Zero `/tmp` Policy)

Sesuai standar keamanan, seluruh kredensial dan file sensitif disimpan di direktori persisten terlindungi milik user host:
- **Direktori Secrets:** `${HOME}/.local/share/tomcat-monitoring/diagnostic-service-secrets/` (izin `0700` direktori, `0400` file)
- **Direktori TLS:** `${HOME}/.local/share/tomcat-monitoring/diagnostic-service-tls/` (izin `0700` direktori, `0400` key, `0444` cert)

---

## 🚀 Cara Menerapkan Perubahan Konfigurasi

1. Edit berkas [`application.json`](application.json) atau [`targets.json`](targets.json).
2. Jalankan skrip deployment:
   ```bash
   /home/eddywiyatno/git/tomcat-monitoring/scripts/deploy-diagnostic-service.sh
   ```
3. Verifikasi ketersediaan service:
   ```bash
   /home/eddywiyatno/git/tomcat-monitoring/scripts/verify-postfix-relay.sh
   ```
