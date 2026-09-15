# Platform Validation & Test Contract

Every component configuration provides an automated local validation interface before participating in CI/CD automation. The platform differentiates between static source validation, unit tests, integration tests, and live deployment verification.

---

## 📑 Validation Interfaces

### 1. Static Contract & Layout Validation (`scripts/validate.sh`)
Validates repository baseline layout, YAML/JSON schemas, PromQL alert syntax, and configuration contracts without requiring running containers or external dependencies.

```bash
bash scripts/validate.sh
```

### 2. Ansible Playbook & Role Validation (`scripts/validate-ansible.sh`)
Verifies role directory hierarchies, tasks, handlers, syntax, and inventory targets using Ansible syntax-check mode.

```bash
bash scripts/validate-ansible.sh
```

### 3. Alertmanager & Prometheus Semantic Testing
- **Promtool Unit Tests:** Tests rule expressions and state transitions against synthetic metric series using `config/prometheus/tests/*.test.yml`.
- **Amtool Config Check:** Verifies `alertmanager.yml` routing trees and syntax.

### 4. Live Verification Suites
- **`scripts/test-tomcatdown-live.sh`:** End-to-end TomcatDown incident simulation (Firing -> Diagnosis -> Resolution).
- **`scripts/verify-postfix-relay.sh`:** Verification of SASL authentication, STARTTLS encryption, and RFC-compliant email delivery.
- **`scripts/verify-jvm-workload-live.sh`:** Workload simulation verifying JVM GC pauses, Old Gen pressure, and Thread Pool saturation alert rules.
- **`scripts/validate-ai-knowledge-lifecycle.sh`:** 5-layer ingestion defense and dynamic AI rule lifecycle verification.
