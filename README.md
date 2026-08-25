# Tomcat Monitoring

Repository ini memiliki configuration, validation, integration, dan delivery
automation untuk Tomcat Monitoring. Ia mengonsumsi contract generic Tomcat dan
derived image JMX Exporter tanpa menyalin atau mengubah source keduanya.

## Status

Repository menyediakan layout non-secret, JMX Exporter baseline configuration,
Telegraf health-check configuration, Prometheus scrape configuration, dan
validator statis. Repository juga menyediakan exploded JSP application fixture
untuk membuktikan persistent lab health integration tanpa mengubah generic
Tomcat image. CI/CD deployment automation, alerting, dan integrasi external
belum diimplementasikan.

## Ownership

- `config/jmx-exporter/`: metric rules JMX Exporter milik project.
- `config/prometheus/`: scrape, storage, dan alert rules Prometheus.
- `config/telegraf/`: local application health check.
- `config/alertmanager/`: routing alert non-secret.
- `fixtures/tomcat-health-app/`: application fixture khusus integration lab.
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
serta contract statis JMX Exporter, Telegraf, Prometheus, dan application
fixture. Ia tidak melakukan semantic configuration validation, menjalankan
dependency, atau membuktikan integrasi monitoring.

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

## Related Contracts

- `../tomcat`: generic Apache Tomcat base image.
- `../tomcat-jmx-exporter`: derived image dan Java Agent HTTPS metrics contract.
- `../devops-handbook/docs/projects/tomcat-monitoring/`: architecture, status,
  decision record, dan Engineering Journal.
