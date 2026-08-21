# Validation Contract

Setiap component configuration harus menyediakan validator lokal sebelum
bergantung pada CI/CD. Validator harus membedakan source validation, component
test, integration test, dan deployment verification.

Saat ini `scripts/validate.sh` hanya memvalidasi baseline repository. Ia tidak
memvalidasi YAML atau runtime behavior karena belum ada configuration component
yang disetujui dan diimplementasikan.
