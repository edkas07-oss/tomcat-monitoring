# Tomcat Monitoring

Repository ini memiliki configuration, validation, integration, dan delivery
automation untuk Tomcat Monitoring. Ia mengonsumsi contract generic Tomcat dan
derived image JMX Exporter tanpa menyalin atau mengubah source keduanya.

## Status

Repository menyediakan layout non-secret, JMX Exporter baseline configuration,
Telegraf health-check configuration, Prometheus scrape configuration, dan
application-health alert rules beserta validator statis dan semantic test.
Repository juga memiliki non-secret Alertmanager routing baseline ke Mailpit
lokal serta Prometheus delivery reference untuk internal `alertmanager:9093`.
Repository juga menyediakan exploded JSP application fixture untuk membuktikan
persistent lab health integration tanpa mengubah generic Tomcat image. Tiga
application-health alert rules telah dimuat dan lulus firing/resolved
verification pada persistent lab. Persistent Alertmanager dan persistent
lab-only Mailpit telah diterapkan pada `devops-lab`; real Prometheus
application-health rule menghasilkan matching firing/resolved email pada
2026-08-28. Alur ini tidak menggunakan credential, personal recipient, host
SMTP publication, atau external delivery. Disposable Mailpit dan webhook
fixtures tetap tersedia sebagai isolated regression interfaces; integrasi
external belum diimplementasikan.

## Ownership

- `config/jmx-exporter/`: metric rules JMX Exporter milik project.
- `config/prometheus/`: scrape, storage, dan alert rules Prometheus.
- `config/telegraf/`: local application health check.
- `config/alertmanager/`: routing alert non-secret.
- `fixtures/tomcat-health-app/`: application fixture khusus integration lab.
- `fixtures/alertmanager-webhook-receiver/`: receiver capture khusus historical
  Alertmanager webhook verification.
- `validation/`: contract dan evidence validator per component.
- `scripts/validate.sh`: validation interface statis repository.

Nilai environment-specific, certificate, private key, password, token,
inventory, dan runtime state tidak boleh disimpan di repository.

## Validation

Jalankan validasi baseline berikut sebelum menambahkan artifact baru:

```bash
./scripts/validate.sh
```

Validator ini memeriksa layout, syntax script, nama file material sensitif,
serta contract statis JMX Exporter, Telegraf, Prometheus, Alertmanager, dan
application fixture. Semantic Prometheus rule test menggunakan `promtool`,
sedangkan semantic Alertmanager configuration check menggunakan `amtool` dari
runtime yang telah disetujui; keduanya tidak dijalankan otomatis oleh static
validator. Static validation tidak membuktikan integrasi monitoring.

Isolated Alertmanager Mailpit verification menggunakan Python 3, `curl`,
Podman, accepted immutable Mailpit image, dua loopback API port, internal-only
SMTP, dan exact disposable cleanup:

```bash
./scripts/verify-alertmanager-mailpit.sh
```

Interface tersebut tidak menggunakan credential, named volume, host SMTP
publication, external delivery, atau persistent runtime. Mailpit image tetap
disimpan setelah runtime cleanup. Historical webhook regression interface juga
tersedia:

```bash
./scripts/verify-alertmanager-webhook.sh
```

Webhook interface menggunakan synthetic endpoint file di temporary directory.
Ia tidak menggunakan Integration Bridge aktual, credential, named volume,
external network delivery, atau persistent Alertmanager.

## Lab Health Application Fixture

`fixtures/tomcat-health-app` merupakan exploded root web application untuk
integration lab. Tomcat memetakan JSP di bawah `WEB-INF` ke `/health` dan
menghasilkan HTTP `200` dengan JSON `{"status":"UP"}`. Pasang directory
tersebut read-only ke `/usr/local/tomcat/webapps/ROOT` pada derived JMX target.

Fixture ini membuktikan alur Tomcat–Telegraf–Prometheus dan bukan health
implementation untuk aplikasi production. Aplikasi downstream harus memiliki
endpoint dan dependency-aware health semantics sendiri.

Lab Prometheus menyimpan configuration, truststore, dan data pada named Podman
volumes. Gunakan initialization interface berikut sebelum menjalankan runtime:

```bash
./scripts/initialize-prometheus-volumes.sh /path/to/jmx-exporter-ca.crt
```

Interface tersebut tidak menggunakan host bind dan tidak menghapus data volume
yang sudah tersedia.

Persistent lab Alertmanager menggunakan named configuration dan data volumes.
Inisialisasi non-secret configuration dilakukan dengan:

```bash
./scripts/initialize-alertmanager-volumes.sh
```

Interface tersebut mempertahankan Alertmanager data yang sudah tersedia dan
tidak menghapus named volume.

## Related Contracts

- `../tomcat`: generic Apache Tomcat base image.
- `../tomcat-jmx-exporter`: derived image dan Java Agent HTTPS metrics contract.
- `../devops-handbook/docs/projects/tomcat-monitoring/`: architecture, status,
  decision record, dan Engineering Journal.
