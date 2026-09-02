# Validation Contract

Setiap component configuration harus menyediakan validator lokal sebelum
bergantung pada CI/CD. Validator harus membedakan source validation, component
test, integration test, dan deployment verification.

`scripts/validate.sh` memvalidasi baseline repository serta contract statis JMX
Exporter, Telegraf, Prometheus, dan Alertmanager tanpa dependency eksternal.
Pemeriksaan JMX Exporter tidak menggantikan Java Agent runtime parse atau
Prometheus scrape. Pemeriksaan Prometheus tidak menggantikan `promtool check
config`; pemeriksaan Alertmanager tidak menggantikan `amtool check-config`.
Static validation tidak membuktikan runtime behavior, network resolution, TLS
handshake, scrape result, notification delivery, atau deployment.

Prometheus semantic fixture pada
`config/prometheus/tests/application-health.test.yml` membuktikan expression
dan state transition rule terhadap synthetic series. Fixture tersebut tidak
membuktikan bahwa persistent Prometheus telah memuat rule atau bahwa actual
Telegraf failure menghasilkan runtime alert.

Persistent lab verification pada TN-024 melengkapi semantic fixture dengan
actual Prometheus rule loading, firing, dan resolved evidence. Verification
tersebut tetap terpisah dari Alertmanager dan external notification flow.

Alertmanager semantic validation memeriksa `alertmanager.yml` menggunakan
`amtool` dari local runtime image. Validation tersebut membuktikan configuration
dapat diparse, bukan bahwa `alertmanager:9093` tersedia, Mailpit SMTP dapat
dihubungi, atau firing/resolved email berhasil ditangkap.

`scripts/verify-alertmanager-mailpit.sh` merupakan active isolated component
verification. Interface ini menjalankan exact disposable Mailpit network dan
containers, mengirim synthetic API v2 alert, lalu memeriksa sender, recipient,
subject firing/resolved, immutable image identity, dan cleanup. SMTP hanya
tersedia pada internal network; loopback host hanya mengekspos Mailpit API dan
Alertmanager API. Timing dipercepat pada temporary configuration sehingga
hasilnya tidak membuktikan lab timing baseline, persistence, Prometheus
delivery, atau external notification flow.

`scripts/verify-alertmanager-webhook.sh` merupakan historical TN-029 isolated
verification. Interface ini menjalankan receiver capture lokal dan exact
disposable Alertmanager, mengirim synthetic API v2 alert, memeriksa payload
firing/resolved serta grouping, lalu mengaudit cleanup. Timing pada temporary
configuration dipercepat agar test bounded; oleh karena itu hasilnya tidak
membuktikan lab timing baseline, persistence, Prometheus delivery, atau
external notification flow.

`scripts/prepare-diagnostic-service-mailpit.sh` membuat certificate, non-secret
configuration/allowlist, disposable bearer token, serta SQLite directory pada
exact TN-013 temporary path. Ia tidak menjalankan container atau network.

`scripts/verify-diagnostic-service-mailpit.sh` merupakan runtime integration
interface terpisah. Interface ini memerlukan exact Diagnostic Service digest,
menjalankan tiga exact container pada internal-only network tanpa host port
atau named volume, kemudian memeriksa TLS trust, health/readiness, metrics,
bearer rejection, firing/duplicate/resolved webhook, SQLite persistence,
Mailpit plain-text/HTML, dan SIGTERM. Script sengaja tidak menghapus resource;
cleanup memerlukan authorization terpisah setelah evidence dicatat.

`scripts/initialize-prometheus-volumes.sh` merupakan runtime initialization
interface dan tidak dipanggil oleh source validator karena membuat Podman
volumes serta initializer container.

`scripts/initialize-alertmanager-volumes.sh` merupakan runtime initialization
interface untuk exact `alertmanager_config` dan `alertmanager_data` volumes.
Static validator hanya memeriksa source contract interface; execution tetap
merupakan runtime mutation yang memerlukan authorization terpisah.
