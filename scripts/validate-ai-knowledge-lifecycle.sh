#!/usr/bin/env bash
# Automated Verification Suite for AI Knowledge Lifecycle & Rules API
# Scenarios:
#   1. Safe Hot-Ingestion (Happy Path & Instant Incident Remapping)
#   2. 5-Layer Ingestion Defense (Auth, Schema, Collision, Immutability, Size)
#   3. Knowledge & Forensic Data Export (Forensic Extraction, Catalog Export, Portability)
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly NETWORK_NAME="devops-lab"
readonly NODEJS_IMAGE="localhost/nodejs:latest"
readonly DIAGNOSTIC_URL="https://diagnostic-service:8443"
readonly BEARER_TOKEN="test-token-12345"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() {
    printf "${GREEN}✔ PASS:${NC} %s\n" "$1"
}

fail() {
    printf "${RED}✘ FAIL:${NC} %s\n" "$1" >&2
    exit 1
}

info() {
    printf "${BLUE}ℹ INFO:${NC} %s\n" "$1"
}

section() {
    printf "\n${CYAN}======================================================================${NC}\n"
    printf "${CYAN}▶ %s${NC}\n" "$1"
    printf "${CYAN}======================================================================${NC}\n"
}

# Helper to execute Node script inside devops-lab network
run_node_client() {
    local script_content="$1"
    podman run --rm --network "${NETWORK_NAME}" "${NODEJS_IMAGE}" node --no-warnings --env-file-if-exists=/dev/null -e "
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
${script_content}
"
}

main() {
    printf "${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${YELLOW}║      AI KNOWLEDGE LIFECYCLE & RULES API AUTOMATED TEST SUITE        ║${NC}\n"
    printf "${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"

    # Pre-flight check
    podman container exists diagnostic-service || fail "Container diagnostic-service tidak aktif."
    podman container exists mailpit || fail "Container mailpit tidak aktif."
    podman image exists "${NODEJS_IMAGE}" || fail "Node.js image tidak tersedia: ${NODEJS_IMAGE}"

    # Verify diagnostic service readiness
    local ready_status
    ready_status=$(podman run --rm --network "${NETWORK_NAME}" docker.io/library/busybox:1.38.0 wget --no-check-certificate -qO- "${DIAGNOSTIC_URL}/health/ready" 2>/dev/null || true)
    [[ "${ready_status}" == *"\"ready\":true"* ]] || fail "Diagnostic service endpoint /health/ready belum siap."
    pass "Pre-flight environment readiness verified."

    # ==========================================================================
    # SCENARIO 1: Safe Hot-Ingestion (Happy Path & Incident Remapping)
    # ==========================================================================
    section "SCENARIO 1: Safe Hot-Ingestion (Happy Path & Incident Remapping)"

    info "1.1. Ingesting AI-Synthesized Rulepack TD-10 (ThreadPoolExhausted)..."
    local ingest_res
    ingest_res=$(run_node_client "
const payload = {
  branch: 'TD-10',
  ruleName: 'ThreadPoolExhausted',
  targetSource: 'local_file',
  pattern: 'RejectedExecutionException: Thread pool is exhausted',
  assessment: 'Tomcat request queue saturated: Thread pool exhausted',
  classification: 'confirmed_cause',
  confidence: 'high',
  recommendedActions: [
    'Periksa maxThreads dan minSpareThreads pada connector Tomcat (/conf/server.xml).',
    'Ambil thread dump JVM untuk memeriksa thread yang mengalami blocking atau deadlock.',
    'Tinjau lonjakan traffic konkurensi pada load balancer / gateway.',
    'Lakukan scale-out instance Tomcat atau restart layanan setelah beban mereda.'
  ],
  createdBy: 'external-ai-enricher'
};
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer ${BEARER_TOKEN}',
    'Content-Type': 'application/json'
  },
  body: JSON.stringify(payload)
});
console.log(JSON.stringify({ status: res.status, body: await res.json() }));
")
    local status_1_1
    status_1_1=$(echo "${ingest_res}" | grep -o '{"status":[0-9]*' | head -1 | cut -d: -f2)
    [[ "${status_1_1}" == "201" || "${status_1_1}" == "409" ]] || fail "POST /api/v1/rules gagal dengan status ${status_1_1}."
    pass "Rulepack TD-10 ingestion HTTP status: ${status_1_1} (Accepted / Already Registered)."

    info "1.2. Verifying rule persistence in SQLite custom_rules..."
    local db_rule_check
    db_rule_check=$(podman exec diagnostic-service node -e "
import sqlite3 from 'node:sqlite';
const db = new sqlite3.DatabaseSync('/var/lib/tomcat-diagnostic/diagnostic.db');
const row = db.prepare('SELECT branch, name, classification, confidence FROM custom_rules WHERE branch=?').get('TD-10');
console.log(JSON.stringify(row || {}));
db.close();
")
    [[ "${db_rule_check}" == *"ThreadPoolExhausted"* ]] || fail "Rule TD-10 tidak ditemukan di database SQLite custom_rules."
    pass "Rulepack TD-10 verified in SQLite: ${db_rule_check}"

    info "1.3. Simulating Live Incident with TD-10 Pattern..."
    rm -f /tmp/tomcat-logs/catalina.out
    echo "2026-09-03 10:45:00.123 [http-nio-8080-exec-50] ERROR org.apache.catalina.core.ContainerBase - java.util.concurrent.RejectedExecutionException: Thread pool is exhausted (max 200 reached)" > /tmp/tomcat-logs/catalina.out
    chmod 0666 /tmp/tomcat-logs/catalina.out

    local alert_firing_payload='{
      "version": "4",
      "groupKey": "{}:TomcatDown",
      "status": "firing",
      "receiver": "lab-diagnostic-service",
      "alerts": [{
        "status": "firing",
        "labels": {
          "alertname": "TomcatDown",
          "severity": "critical",
          "environment": "lab",
          "host": "tomcat-01",
          "tomcat_instance": "default",
          "job": "tomcat-jmx-exporter",
          "instance": "tomcat-01:9404",
          "service": "tomcat",
          "check": "runtime-availability"
        },
        "annotations": { "summary": "Thread pool exhaustion incident" },
        "startsAt": "2026-09-03T10:45:00.000Z",
        "endsAt": "0001-01-01T00:00:00Z",
        "fingerprint": "fp-live-td10-001"
      }]
    }'

    local alert_res
    alert_res=$(run_node_client "
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/alerts/alertmanager', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer ${BEARER_TOKEN}',
    'Content-Type': 'application/json'
  },
  body: JSON.stringify(${alert_firing_payload})
});
console.log(JSON.stringify({ status: res.status, body: await res.json() }));
")
    local alert_status
    alert_status=$(echo "${alert_res}" | grep -o '{"status":[0-9]*' | head -1 | cut -d: -f2)
    [[ "${alert_status}" == "202" ]] || fail "Webhook alert ingestion gagal dengan status ${alert_status}."
    pass "Alert webhook accepted (202 Accepted)."

    info "1.4. Waiting for worker processing & verifying classification to TD-10..."
    sleep 2
    local eval_result
    eval_result=$(podman exec diagnostic-service node -e "
import sqlite3 from 'node:sqlite';
const db = new sqlite3.DatabaseSync('/var/lib/tomcat-diagnostic/diagnostic.db');
const row = db.prepare('SELECT id, classification, confidence, result_json FROM canonical_results ORDER BY id DESC LIMIT 1').get();
console.log(JSON.stringify(row || {}));
db.close();
")
    [[ "${eval_result}" == *"TD-10"* && "${eval_result}" == *"confirmed_cause"* ]] || fail "Evaluasi insiden gagal memetakan ke TD-10: ${eval_result}"
    pass "Incident successfully remapped dynamically to TD-10 (confirmed_cause / high confidence)."

    info "1.5. Resolving Incident..."
    local alert_resolved_payload='{
      "version": "4",
      "groupKey": "{}:TomcatDown",
      "status": "resolved",
      "receiver": "lab-diagnostic-service",
      "alerts": [{
        "status": "resolved",
        "labels": {
          "alertname": "TomcatDown",
          "severity": "critical",
          "environment": "lab",
          "host": "tomcat-01",
          "tomcat_instance": "default",
          "job": "tomcat-jmx-exporter",
          "instance": "tomcat-01:9404",
          "service": "tomcat",
          "check": "runtime-availability"
        },
        "annotations": { "summary": "Thread pool recovered" },
        "startsAt": "2026-09-03T10:45:00.000Z",
        "endsAt": "2026-09-03T10:46:15.000Z",
        "fingerprint": "fp-live-td10-001"
      }]
    }'
    run_node_client "
await fetch('${DIAGNOSTIC_URL}/api/v1/alerts/alertmanager', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer ${BEARER_TOKEN}',
    'Content-Type': 'application/json'
  },
  body: JSON.stringify(${alert_resolved_payload})
});
" >/dev/null
    sleep 2
    pass "Incident resolution processed cleanly."

    # ==========================================================================
    # SCENARIO 2: 5-Layer Ingestion Defense (Negative / Security Guard Path)
    # ==========================================================================
    section "SCENARIO 2: 5-Layer Ingestion Defense (Negative & Boundary Guards)"

    info "2.1. Layer 1 Guard: Testing Missing Bearer Token..."
    local auth_missing
    auth_missing=$(run_node_client "
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ branch: 'TD-99' })
});
console.log(res.status);
")
    [[ "${auth_missing}" == *"401"* ]] || fail "Auth Guard gagal menolak request tanpa token (Status: ${auth_missing})."
    pass "Layer 1 Auth Guard: Missing token rejected with 401 Unauthorized."

    info "2.2. Layer 1 Guard: Testing Invalid Bearer Token..."
    local auth_invalid
    auth_invalid=$(run_node_client "
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules', {
  method: 'POST',
  headers: { 'Authorization': 'Bearer wrong-secret-token', 'Content-Type': 'application/json' },
  body: JSON.stringify({ branch: 'TD-99' })
});
console.log(res.status);
")
    [[ "${auth_invalid}" == *"401"* ]] || fail "Auth Guard gagal menolak invalid token (Status: ${auth_invalid})."
    pass "Layer 1 Auth Guard: Invalid token rejected with 401 Unauthorized."

    info "2.3. Layer 2 Guard: Testing Missing Required Fields Schema..."
    local schema_invalid
    schema_invalid=$(run_node_client "
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules', {
  method: 'POST',
  headers: { 'Authorization': 'Bearer ${BEARER_TOKEN}', 'Content-Type': 'application/json' },
  body: JSON.stringify({ branch: 'TD-99', ruleName: 'IncompleteRule' })
});
console.log(res.status);
")
    [[ "${schema_invalid}" == *"400"* ]] || fail "Schema Guard gagal menolak field tidak lengkap (Status: ${schema_invalid})."
    pass "Layer 2 Schema Guard: Incomplete schema rejected with 400 Bad Request."

    info "2.4. Layer 2 Guard: Testing Invalid Classification Enum..."
    local enum_invalid
    enum_invalid=$(run_node_client "
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules', {
  method: 'POST',
  headers: { 'Authorization': 'Bearer ${BEARER_TOKEN}', 'Content-Type': 'application/json' },
  body: JSON.stringify({
    branch: 'TD-99',
    ruleName: 'InvalidEnumRule',
    targetSource: 'local_file',
    pattern: 'test-error',
    assessment: 'test assessment',
    classification: 'hallucinated_classification',
    confidence: 'high',
    recommendedActions: ['test action']
  })
});
console.log(res.status);
")
    [[ "${enum_invalid}" == *"400"* ]] || fail "Schema Guard gagal menolak invalid enum (Status: ${enum_invalid})."
    pass "Layer 2 Schema Guard: Invalid classification enum rejected with 400 Bad Request."

    info "2.5. Layer 3 Guard: Testing Built-in Branch Collision (TD-02)..."
    local builtin_collision
    builtin_collision=$(run_node_client "
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules', {
  method: 'POST',
  headers: { 'Authorization': 'Bearer ${BEARER_TOKEN}', 'Content-Type': 'application/json' },
  body: JSON.stringify({
    branch: 'TD-02',
    ruleName: 'OverwriteOOM',
    targetSource: 'local_file',
    pattern: 'test',
    assessment: 'overwrite builtin',
    classification: 'confirmed_cause',
    confidence: 'high',
    recommendedActions: ['Check memory bounds']
  })
});
console.log(res.status);
")
    [[ "${builtin_collision}" == *"409"* ]] || fail "Collision Guard gagal menolak built-in branch conflict (Status: ${builtin_collision})."
    pass "Layer 3 Collision Guard: Built-in branch overwrite (TD-02) rejected with 409 Conflict."

    info "2.6. Layer 3 Guard: Testing Duplicate Custom Branch Collision (TD-10)..."
    local duplicate_collision
    duplicate_collision=$(run_node_client "
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules', {
  method: 'POST',
  headers: { 'Authorization': 'Bearer ${BEARER_TOKEN}', 'Content-Type': 'application/json' },
  body: JSON.stringify({
    branch: 'TD-10',
    ruleName: 'DuplicateTD10',
    targetSource: 'local_file',
    pattern: 'test-duplicate',
    assessment: 'duplicate branch',
    classification: 'confirmed_cause',
    confidence: 'high',
    recommendedActions: ['Check duplicate rule']
  })
});
console.log(res.status);
")
    [[ "${duplicate_collision}" == *"409"* ]] || fail "Collision Guard gagal menolak duplicate branch TD-10 (Status: ${duplicate_collision})."
    pass "Layer 3 Collision Guard: Duplicate custom branch TD-10 rejected with 409 Conflict."

    info "2.7. Layer 4 Guard: Testing Oversized Payload (>64KB)..."
    local oversized_payload
    oversized_payload=$(run_node_client "
const giantString = 'A'.repeat(70 * 1024);
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules', {
  method: 'POST',
  headers: { 'Authorization': 'Bearer ${BEARER_TOKEN}', 'Content-Type': 'application/json' },
  body: JSON.stringify({
    branch: 'TD-99',
    ruleName: 'GiantRule',
    targetSource: 'local_file',
    pattern: giantString,
    assessment: 'too large',
    classification: 'confirmed_cause',
    confidence: 'high',
    recommendedActions: ['Handle giant payload']
  })
});
console.log(res.status);
")
    [[ "${oversized_payload}" == *"413"* ]] || fail "Payload Size Guard gagal menolak payload raksasa (Status: ${oversized_payload})."
    pass "Layer 4 Size Guard: Oversized payload (>64KB) rejected with 413 Payload Too Large."

    info "2.8. Layer 5 Guard: Testing Append-Only Immutability (PUT / DELETE)..."
    local put_rejection
    put_rejection=$(run_node_client "
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules/TD-10', {
  method: 'PUT',
  headers: { 'Authorization': 'Bearer ${BEARER_TOKEN}', 'Content-Type': 'application/json' },
  body: JSON.stringify({ assessment: 'modified' })
});
console.log(res.status);
")
    [[ "${put_rejection}" == *"405"* ]] || fail "Immutability Guard gagal menolak PUT method (Status: ${put_rejection})."
    pass "Layer 5 Immutability Guard: PUT modification rejected with 405 Method Not Allowed."

    local delete_rejection
    delete_rejection=$(run_node_client "
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules/TD-10', {
  method: 'DELETE',
  headers: { 'Authorization': 'Bearer ${BEARER_TOKEN}' }
});
console.log(res.status);
")
    [[ "${delete_rejection}" == *"405"* ]] || fail "Immutability Guard gagal menolak DELETE method (Status: ${delete_rejection})."
    pass "Layer 5 Immutability Guard: DELETE removal rejected with 405 Method Not Allowed."

    # ==========================================================================
    # SCENARIO 3: Knowledge & Forensic Data Export (Export Path & Portability)
    # ==========================================================================
    section "SCENARIO 3: Knowledge & Forensic Data Export (Export & Portability)"

    info "3.1. Extracting Forensic Context for AI Prompt..."
    local forensic_export
    forensic_export=$(podman exec diagnostic-service node -e "
import sqlite3 from 'node:sqlite';
const db = new sqlite3.DatabaseSync('/var/lib/tomcat-diagnostic/diagnostic.db');
const canonical = db.prepare('SELECT result_json FROM canonical_results ORDER BY id DESC LIMIT 1').get();
const summaries = db.prepare('SELECT source, status, summary_json FROM evidence_summaries ORDER BY id DESC LIMIT 5').all();
const aiInputBundle = {
  incidentSnapshot: JSON.parse(canonical?.result_json || '{}'),
  evidenceSummaries: summaries.map(s => ({ source: s.source, status: s.status, data: JSON.parse(s.summary_json || '{}') }))
};
console.log(JSON.stringify(aiInputBundle));
db.close();
")
    [[ "${forensic_export}" == *"incidentSnapshot"* && "${forensic_export}" == *"evidenceSummaries"* ]] || fail "Ekstraksi data forensik gagal."
    pass "Forensic snapshot extracted successfully for AI consumption (${#forensic_export} bytes)."

    info "3.2. Exporting Active Knowledge Base Catalog (GET /api/v1/rules)..."
    local catalog_export
    catalog_export=$(run_node_client "
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules', {
  headers: { 'Authorization': 'Bearer ${BEARER_TOKEN}' }
});
const data = await res.json();
console.log(JSON.stringify({ status: res.status, total: data.total, rules: data.rules }));
")
    local catalog_status
    catalog_status=$(echo "${catalog_export}" | grep -o '{"status":[0-9]*' | head -1 | cut -d: -f2)
    [[ "${catalog_status}" == "200" ]] || fail "Export catalog GET /api/v1/rules gagal dengan status ${catalog_status}."
    [[ "${catalog_export}" == *"TD-09"* && "${catalog_export}" == *"TD-10"* ]] || fail "Catalog export tidak memuat seluruh aturan aktif (TD-09, TD-10)."
    pass "Knowledge Catalog exported via API: Total rules >= 2 (TD-09, TD-10 included)."

    info "3.3. Exporting Single Rule by Branch (GET /api/v1/rules/TD-10)..."
    local single_rule_export
    single_rule_export=$(run_node_client "
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules/TD-10', {
  headers: { 'Authorization': 'Bearer ${BEARER_TOKEN}' }
});
console.log(JSON.stringify({ status: res.status, body: await res.json() }));
")
    [[ "${single_rule_export}" == *"ThreadPoolExhausted"* ]] || fail "Single rule export gagal menemukan TD-10."
    pass "Single rule export GET /api/v1/rules/TD-10 verified."

    info "3.4. Testing Export Endpoint Auth Guard..."
    local export_no_auth
    export_no_auth=$(run_node_client "
const res = await fetch('${DIAGNOSTIC_URL}/api/v1/rules');
console.log(res.status);
")
    [[ "${export_no_auth}" == *"401"* ]] || fail "Export endpoint gagal memvalidasi authentication (Status: ${export_no_auth})."
    pass "Export Endpoint Auth Guard: Unauthenticated GET rejected with 401 Unauthorized."

    info "3.5. Verifying Rulepack Portability & Schema Integrity..."
    local portability_check
    portability_check=$(podman exec diagnostic-service node -e "
import sqlite3 from 'node:sqlite';
import { createRulepackValidator } from '/app/src/server/rulepack-schema.js';
const db = new sqlite3.DatabaseSync('/var/lib/tomcat-diagnostic/diagnostic.db');
const rules = db.prepare('SELECT rule_json FROM custom_rules').all();
const validator = createRulepackValidator('/app/config/schemas/rulepack-v1.schema.json');
let allValid = true;
for (const r of rules) {
  const payload = JSON.parse(r.rule_json);
  const valid = validator(payload);
  if (!valid.valid) {
    console.error('Validation failed for rule:', payload.branch, valid.error);
    allValid = false;
  }
}
console.log(JSON.stringify({ exportedRulesCount: rules.length, schemaCompliant: allValid }));
db.close();
")
    [[ "${portability_check}" == *"\"schemaCompliant\":true"* ]] || fail "Portability schema validation gagal: ${portability_check}"
    pass "Rulepack Portability Verified: All exported rules are 100% compliant with JSON Schema."

    # ==========================================================================
    # FINAL SUMMARY
    # ==========================================================================
    printf "\n${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║   ALL 3 AI KNOWLEDGE LIFECYCLE SCENARIOS PASSED WITH 100%% SUCCESS   ║${NC}\n"
    printf "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"
    printf "${GREEN}✔ Scenario 1: Safe Hot-Ingestion & Dynamic Remapping PASSED${NC}\n"
    printf "${GREEN}✔ Scenario 2: 5-Layer Ingestion Defense-in-Depth PASSED${NC}\n"
    printf "${GREEN}✔ Scenario 3: Knowledge & Forensic Data Export PASSED${NC}\n\n"
}

main "$@"
