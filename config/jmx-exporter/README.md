# JMX Exporter Configuration Contract

Directory ini kelak menyimpan metric rules project untuk JMX Exporter. Runtime
path tetap mengikuti derived-image contract:
`/etc/tomcat-jmx-exporter/config.yml`.

TLS keystore dan password bukan configuration repository; keduanya harus
dipasang sebagai secret read-only saat runtime. Jangan menambahkan metric rules
atau file executable sebelum scope component configuration disetujui.
