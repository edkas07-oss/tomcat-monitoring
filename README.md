# Tomcat Monitoring

Repository ini memiliki configuration, validation, integration, dan delivery
automation untuk Tomcat Monitoring. Ia mengonsumsi contract generic Tomcat dan
derived image JMX Exporter tanpa menyalin atau mengubah source keduanya.

## Status

Repository menyediakan layout non-secret, Telegraf health-check configuration,
Prometheus scrape configuration, dan validator statis. Image build, container
runtime, deployment, dan integrasi external belum diimplementasikan.

## Ownership

- `config/jmx-exporter/`: metric rules JMX Exporter milik project.
- `config/prometheus/`: scrape, storage, dan alert rules Prometheus.
- `config/telegraf/`: local application health check.
- `config/alertmanager/`: routing alert non-secret.
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
serta contract statis Telegraf dan Prometheus. Ia tidak melakukan semantic YAML
validation, menjalankan dependency, atau membuktikan integrasi monitoring.

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
