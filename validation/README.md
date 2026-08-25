# Validation Contract

Setiap component configuration harus menyediakan validator lokal sebelum
bergantung pada CI/CD. Validator harus membedakan source validation, component
test, integration test, dan deployment verification.

`scripts/validate.sh` memvalidasi baseline repository serta contract statis JMX
Exporter, Telegraf, dan Prometheus tanpa dependency eksternal. Pemeriksaan JMX
Exporter tidak menggantikan Java Agent runtime parse atau Prometheus scrape.
Pemeriksaan Prometheus tidak menggantikan `promtool check config`. Static
validation tidak membuktikan runtime behavior, network resolution, TLS
handshake, scrape result, atau deployment.

`scripts/initialize-prometheus-volumes.sh` merupakan runtime initialization
interface dan tidak dipanggil oleh source validator karena membuat Podman
volumes serta initializer container.
