# Telegraf Configuration Contract

Directory ini menyediakan configuration `inputs.http_response` yang memeriksa
application health endpoint melalui container network lokal. File
`health-check.conf` adalah contract sementara non-secret dan menggunakan
`TOMCAT_HEALTH_URL` sebagai target runtime.

Path `/health` dan Tomcat internal port `8080` sudah menjadi architecture
interface. Contract sementara menggunakan HTTP `200`, body status `UP`, timeout
`5s`, interval `30s`, dan Prometheus client internal `:9273/metrics`. Nilai
tersebut belum membuktikan deployment topology, Prometheus scrape, atau health
endpoint aplikasi nyata.
