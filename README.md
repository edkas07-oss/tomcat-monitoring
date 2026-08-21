# Tomcat Monitoring

Repository ini memiliki configuration, validation, integration, dan delivery
automation untuk Tomcat Monitoring. Ia mengonsumsi contract generic Tomcat dan
derived image JMX Exporter tanpa menyalin atau mengubah source keduanya.

## Status

Repository baru menyediakan layout non-secret dan validator statis. Belum ada
configuration executable, image build, container runtime, deployment, atau
integrasi external yang diimplementasikan.

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

Validator ini hanya memeriksa layout, syntax script, dan nama file material
sensitif. Ia belum memvalidasi YAML, menjalankan dependency, atau membuktikan
integrasi monitoring.

## Related Contracts

- `../tomcat`: generic Apache Tomcat base image.
- `../tomcat-jmx-exporter`: derived image dan Java Agent HTTPS metrics contract.
- `../devops-handbook/docs/projects/tomcat-monitoring/`: architecture, status,
  decision record, dan Engineering Journal.
