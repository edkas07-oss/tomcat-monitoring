# JMX Exporter Configuration Contract

Directory ini menyimpan baseline metric rules project untuk JMX Exporter.
Runtime path mengikuti derived-image contract:
`/etc/tomcat-jmx-exporter/config.yml`.

TLS keystore dan password bukan configuration repository; keduanya harus
dipasang sebagai secret read-only saat runtime. Configuration hanya mereferensi
`${JMX_EXPORTER_KEYSTORE_PASSWORD}` dan tidak menyimpan password literal.

Baseline awal menyediakan dua metrics:

- `jvm_memory_heap_used_bytes` untuk membuktikan JVM MBean mapping; dan
- `tomcat_server` untuk membuktikan Tomcat MBean mapping.

Suffix `_info` tidak digunakan karena current JMX Exporter memperlakukannya
sebagai reserved metric suffix dan menormalkan base name
`tomcat_server_info` menjadi `tomcat_server`. Source contract menggunakan nama
runtime aktual agar query, validator, dashboard, dan alert tidak bergantung
pada nama yang tidak diekspos.

Kedua rules hanya menjadi integration baseline. GC, thread, class loading,
connector, request, error, throughput, dan session metrics tetap memerlukan
metric-catalog activity terpisah.

Jalankan source validation dengan:

```bash
./scripts/validate-jmx-exporter.sh
```

Validator memeriksa TLS structure, password reference, certificate alias, dan
tepat dua baseline rules tanpa menjalankan Java Agent. Runtime parse, TLS
handshake, hostname verification, dan Prometheus scrape dibuktikan pada
verification activity terpisah.
