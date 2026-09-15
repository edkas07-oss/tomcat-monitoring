#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/test-tomcatdown-live.sh
# Tujuan: Pengujian komprehensif insiden TomcatDown pada live environment
#         (Fase FIRING, RESOLVED, Header RFC, Laporan 7-Seksi SRE, & Postfix Relay).
# ==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi
# shellcheck source=scripts/container-runtime-helper.sh
source "${SCRIPT_DIR}/container-runtime-helper.sh"

readonly NETWORK_NAME="${NETWORK_NAME:-tm-net}"
readonly DIAGNOSTIC_CONTAINER="${DIAGNOSTIC_CONTAINER:-diagnostic-service}"
readonly POSTFIX_CONTAINER="${POSTFIX_CONTAINER:-postfix-relay}"
readonly MAILPIT_CONTAINER="${MAILPIT_CONTAINER:-mailpit}"
readonly MAILPIT_API_URL="http://127.0.0.1:${MAILPIT_HTTP_PORT:-8025}"
readonly NODEJS_IMAGE="${NODEJS_IMAGE:-localhost/nodejs:24.18.0}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

pass() { printf "${GREEN}✔ PASS: %s${NC}\n" "$1"; }
fail() { printf "${RED}✘ FAIL: %s${NC}\n" "$1" >&2; exit 1; }
info() { printf "${CYAN}ℹ INFO: %s${NC}\n" "$1"; }
section() { printf "\n${BLUE}======================================================================\n▶ %s\n======================================================================${NC}\n" "$1"; }

main() {
    printf "${CYAN}╔══════════════════════════════════════════════════════════════════════╗\n"
    printf "║           TOMCATDOWN LIVE INCIDENT VERIFICATION SUITE               ║\n"
    printf "╚══════════════════════════════════════════════════════════════════════╝${NC}\n"

    local vol_ro="$(get_volume_flag "ro")"

    section "1. Pre-Flight Container & Infrastructure Readiness"
    network_exists "${NETWORK_NAME}" || fail "Network ${NETWORK_NAME} tidak ditemukan."
    pass "Network ${NETWORK_NAME} aktif"

    for container in "${MAILPIT_CONTAINER}" "${POSTFIX_CONTAINER}" "${DIAGNOSTIC_CONTAINER}"; do
        local status
        status="$("${CONTAINER_ENGINE}" inspect --format '{{.State.Status}}' "${container}" 2>/dev/null || echo "not_found")"
        [[ "${status}" == "running" ]] || fail "Container ${container} tidak berjalan (status: ${status})"
        pass "Container ${container} berjalan (status: ${status})"
    done

    section "2. Reset Mailpit Inbox Baseline"
    info "Mengosongkan mailbox Mailpit untuk memastikan hasil audit bersih..."
    curl -s -X DELETE "${MAILPIT_API_URL}/api/v1/messages" >/dev/null
    local initial_count
    initial_count="$(python3 -c "import urllib.request, json; print(json.load(urllib.request.urlopen('${MAILPIT_API_URL}/api/v1/messages')).get('total', 0))")"
    [[ "${initial_count}" -eq 0 ]] || fail "Mailpit inbox gagal dikosongkan (pesan tersisa: ${initial_count})"
    pass "Mailpit inbox bersih (0 pesan tersimpan)"

    section "3. Simulasi Insiden TomcatDown (Fase 1: FIRING - Severity CRITICAL)"
    local firing_fingerprint="tomcatdown-live-$(date +%s)"
    local tmp_payload
    tmp_payload="$(mktemp /tmp/tomcatdown-firing.XXXXXX.json)"

    python3 - "${tmp_payload}" "${firing_fingerprint}" <<'PY'
import json, sys, datetime
out_path = sys.argv[1]
fp = sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc)
data = {
  "version": "4",
  "groupKey": f"{{}}:{{alertname=\"TomcatDown\",fp=\"{fp}\"}}",
  "status": "firing",
  "receiver": "diagnostic-service",
  "groupLabels": {"alertname": "TomcatDown"},
  "commonLabels": {
    "alertname": "TomcatDown",
    "severity": "critical",
    "environment": "lab",
    "host": "tomcat-01",
    "tomcat_instance": "default",
    "job": "tomcat-jmx-exporter",
    "instance": "tomcat-jmx-exporter:9404",
    "service": "tomcat",
    "check": "runtime-availability"
  },
  "commonAnnotations": {
    "summary": "Tomcat JMX Exporter target unreachable on tomcat-01/default",
    "description": "Prometheus cannot scrape JMX Exporter target tomcat-jmx-exporter:9404; Tomcat may be down or unreachable."
  },
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "TomcatDown",
        "severity": "critical",
        "environment": "lab",
        "host": "tomcat-01",
        "tomcat_instance": "default",
        "job": "tomcat-jmx-exporter",
        "instance": "tomcat-jmx-exporter:9404",
        "service": "tomcat",
        "check": "runtime-availability"
      },
      "annotations": {
        "summary": "Tomcat JMX Exporter target unreachable on tomcat-01/default",
        "description": "Prometheus cannot scrape JMX Exporter target tomcat-jmx-exporter:9404; Tomcat may be down or unreachable."
      },
      "startsAt": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
      "endsAt": (now + datetime.timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ"),
      "generatorURL": "http://prometheus:9090/graph",
      "fingerprint": fp
    }
  ]
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(data, f)
PY
    chmod 0644 "${tmp_payload}"

    info "Mengirimkan webhook insiden TomcatDown (FIRING) ke Diagnostic Service HTTPS :8443..."
    local firing_response
    firing_response="$("${CONTAINER_ENGINE}" run --rm --network "${NETWORK_NAME}" \
        -v "${tmp_payload}:/payload.json${vol_ro}" "${NODEJS_IMAGE}" node -e "
const https = require('https');
const fs = require('fs');
const data = fs.readFileSync('/payload.json', 'utf8');
const req = https.request({
  hostname: 'diagnostic-service',
  port: 8443,
  path: '/api/v1/alerts/alertmanager',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(data),
    'Authorization': 'Bearer test-token-12345'
  },
  rejectUnauthorized: false
}, (res) => {
  let body = '';
  res.on('data', (c) => body += c);
  res.on('end', () => console.log('HTTP_' + res.statusCode + ':' + body));
});
req.write(data);
req.end();
")"
    rm -f "${tmp_payload}"
    info "Response webhook Diagnostic Service: ${firing_response}"
    [[ "${firing_response}" =~ HTTP_202 ]] || fail "Diagnostic Service menolak webhook TomcatDown FIRING."
    pass "Diagnostic Service menerima webhook FIRING dan memulai investigasi insiden"

    info "Menunggu Diagnostic Service mengumpulkan bukti telemetri & mengirim laporan via Postfix Relay..."
    sleep 3

    section "4. Audit Laporan Insiden TomcatDown FIRING di Mailpit API"
    local audit_firing
    audit_firing="$(python3 - "${MAILPIT_API_URL}" <<'PY'
import json, sys, urllib.request

try:
    with urllib.request.urlopen(f"{sys.argv[1]}/api/v1/messages", timeout=5) as resp:
        data = json.load(resp)
except Exception as e:
    sys.exit(f"Failed to query Mailpit API: {e}")

messages = data.get("messages", [])
if not messages:
    sys.exit("Mailpit messages list is empty.")

incident_msg = None
for m in messages:
    if "[CRITICAL] [LAB] Tomcat Service: TomcatDown" in m.get("Subject", ""):
        incident_msg = m
        break

if not incident_msg:
    sys.exit(f"No TomcatDown firing message found in Mailpit. Total messages: {len(messages)}")

subject = incident_msg.get("Subject", "")
sender = incident_msg.get("From", {}).get("Address", "")
recipients = [to.get("Address") for to in incident_msg.get("To", [])]
msg_id = incident_msg.get("ID")

print(f"FIRING_SUBJECT={subject}")
print(f"FIRING_SENDER={sender}")
print(f"FIRING_RECIPIENTS={recipients}")

# Retrieve full message HTML & Text
with urllib.request.urlopen(f"{sys.argv[1]}/api/v1/message/{msg_id}", timeout=5) as resp:
    full_msg = json.load(resp)

# Retrieve MIME Headers
with urllib.request.urlopen(f"{sys.argv[1]}/api/v1/message/{msg_id}/headers", timeout=5) as resp:
    headers = json.load(resp)

html = full_msg.get("HTML", "")
text = full_msg.get("Text", "")

auto_submitted = headers.get("Auto-Submitted", [])
x_priority = headers.get("X-Priority", [])
x_target = headers.get("X-Incident-Target", [])
x_rule = headers.get("X-Diagnostic-Rule", [])

print(f"HEADER_AUTO_SUBMITTED={auto_submitted}")
print(f"HEADER_X_PRIORITY={x_priority}")
print(f"HEADER_X_TARGET={x_target}")
print(f"HEADER_X_RULE={x_rule}")

if "auto-generated" not in auto_submitted:
    sys.exit("Missing Auto-Submitted: auto-generated header")
if "1" not in x_priority:
    sys.exit("Missing X-Priority: 1 header for critical alert")
if not x_target or "lab/tomcat-01/default" not in x_target[0]:
    sys.exit(f"Missing or invalid X-Incident-Target header: {x_target}")
if "TomcatDown" not in x_rule:
    sys.exit(f"Missing X-Diagnostic-Rule: TomcatDown header")

required_tokens = [
    "Alert Summary",
    "Diagnostic Assessment",
    "Key Metrics Snapshot",
    "Correlated Log Evidence",
    "Unavailable or Contradicting Evidence",
    "Recommended Operator Actions",
    "Rule and Diagnostic Traceability"
]

missing = [t for t in required_tokens if t not in html and t not in text]
if missing:
    sys.exit(f"Report missing required 7-section tokens: {missing}")

print("FIRING_VERIFIED=true")
PY
)"
    info "Hasil audit TomcatDown FIRING:\n${audit_firing}"
    [[ "${audit_firing}" =~ FIRING_VERIFIED=true ]] || fail "Audit laporan FIRING di Mailpit gagal."
    pass "Laporan TomcatDown (FIRING) terverifikasi: Subjek CRITICAL, 4 Header RFC valid, dan 7 Seksi SRE lengkap"

    section "5. Simulasi Resolusi Insiden TomcatDown (Fase 2: RESOLVED)"
    local tmp_resolved_payload
    tmp_resolved_payload="$(mktemp /tmp/tomcatdown-resolved.XXXXXX.json)"

    python3 - "${tmp_resolved_payload}" "${firing_fingerprint}" <<'PY'
import json, sys, datetime
out_path = sys.argv[1]
fp = sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc)
data = {
  "version": "4",
  "groupKey": f"{{}}:{{alertname=\"TomcatDown\",fp=\"{fp}\"}}",
  "status": "resolved",
  "receiver": "diagnostic-service",
  "groupLabels": {"alertname": "TomcatDown"},
  "commonLabels": {
    "alertname": "TomcatDown",
    "severity": "critical",
    "environment": "lab",
    "host": "tomcat-01",
    "tomcat_instance": "default",
    "job": "tomcat-jmx-exporter",
    "instance": "tomcat-jmx-exporter:9404",
    "service": "tomcat",
    "check": "runtime-availability"
  },
  "commonAnnotations": {
    "summary": "Tomcat JMX Exporter target reachable on tomcat-01/default",
    "description": "Tomcat instance default on host tomcat-01 has recovered."
  },
  "alerts": [
    {
      "status": "resolved",
      "labels": {
        "alertname": "TomcatDown",
        "severity": "critical",
        "environment": "lab",
        "host": "tomcat-01",
        "tomcat_instance": "default",
        "job": "tomcat-jmx-exporter",
        "instance": "tomcat-jmx-exporter:9404",
        "service": "tomcat",
        "check": "runtime-availability"
      },
      "annotations": {
        "summary": "Tomcat JMX Exporter target reachable on tomcat-01/default",
        "description": "Tomcat instance default on host tomcat-01 has recovered."
      },
      "startsAt": (now - datetime.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%SZ"),
      "endsAt": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
      "generatorURL": "http://prometheus:9090/graph",
      "fingerprint": fp
    }
  ]
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(data, f)
PY
    chmod 0644 "${tmp_resolved_payload}"

    info "Mengirimkan webhook resolusi insiden TomcatDown (RESOLVED) ke Diagnostic Service HTTPS :8443..."
    local resolved_response
    resolved_response="$("${CONTAINER_ENGINE}" run --rm --network "${NETWORK_NAME}" \
        -v "${tmp_resolved_payload}:/payload.json${vol_ro}" "${NODEJS_IMAGE}" node -e "
const https = require('https');
const fs = require('fs');
const data = fs.readFileSync('/payload.json', 'utf8');
const req = https.request({
  hostname: 'diagnostic-service',
  port: 8443,
  path: '/api/v1/alerts/alertmanager',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(data),
    'Authorization': 'Bearer test-token-12345'
  },
  rejectUnauthorized: false
}, (res) => {
  let body = '';
  res.on('data', (c) => body += c);
  res.on('end', () => console.log('HTTP_' + res.statusCode + ':' + body));
});
req.write(data);
req.end();
")"
    rm -f "${tmp_resolved_payload}"
    info "Response webhook Diagnostic Service: ${resolved_response}"
    [[ "${resolved_response}" =~ HTTP_202 ]] || fail "Diagnostic Service menolak webhook TomcatDown RESOLVED."
    pass "Diagnostic Service menerima webhook RESOLVED dan memproses evaluasi pemulihan"

    info "Menunggu Diagnostic Service memproses dan mengirim notifikasi pemulihan..."
    sleep 3

    section "6. Audit Notifikasi Pemulihan TomcatDown RESOLVED di Mailpit API"
    local audit_resolved
    audit_resolved="$(python3 - "${MAILPIT_API_URL}" <<'PY'
import json, sys, urllib.request

try:
    with urllib.request.urlopen(f"{sys.argv[1]}/api/v1/messages", timeout=5) as resp:
        data = json.load(resp)
except Exception as e:
    sys.exit(f"Failed to query Mailpit API: {e}")

messages = data.get("messages", [])
resolved_msg = None
for m in messages:
    if "[RESOLVED] [LAB] Tomcat Service: TomcatDown Restored" in m.get("Subject", ""):
        resolved_msg = m
        break

if not resolved_msg:
    sys.exit(f"No TomcatDown resolved message found in Mailpit. Total messages: {len(messages)}")

subject = resolved_msg.get("Subject", "")
sender = resolved_msg.get("From", {}).get("Address", "")
recipients = [to.get("Address") for to in resolved_msg.get("To", [])]
msg_id = resolved_msg.get("ID")

print(f"RESOLVED_SUBJECT={subject}")
print(f"RESOLVED_SENDER={sender}")
print(f"RESOLVED_RECIPIENTS={recipients}")

with urllib.request.urlopen(f"{sys.argv[1]}/api/v1/message/{msg_id}/headers", timeout=5) as resp:
    headers = json.load(resp)

auto_submitted = headers.get("Auto-Submitted", [])
x_priority = headers.get("X-Priority", [])
x_target = headers.get("X-Incident-Target", [])
x_rule = headers.get("X-Diagnostic-Rule", [])

print(f"HEADER_AUTO_SUBMITTED={auto_submitted}")
print(f"HEADER_X_PRIORITY={x_priority}")
print(f"HEADER_X_TARGET={x_target}")
print(f"HEADER_X_RULE={x_rule}")

if "auto-generated" not in auto_submitted:
    sys.exit("Missing Auto-Submitted: auto-generated header on resolved notification")
if "3" not in x_priority:
    sys.exit(f"Expected X-Priority: 3 (Normal) for resolved alert, got: {x_priority}")
if not x_target or "lab/tomcat-01/default" not in x_target[0]:
    sys.exit(f"Missing or invalid X-Incident-Target header: {x_target}")
if "TomcatDown" not in x_rule:
    sys.exit(f"Missing X-Diagnostic-Rule: TomcatDown header")

print("RESOLVED_VERIFIED=true")
PY
)"
    info "Hasil audit TomcatDown RESOLVED:\n${audit_resolved}"
    [[ "${audit_resolved}" =~ RESOLVED_VERIFIED=true ]] || fail "Audit notifikasi RESOLVED di Mailpit gagal."
    pass "Notifikasi TomcatDown (RESOLVED) terverifikasi: Subjek RESTORED, X-Priority: 3, dan Auto-Submitted valid"

    section "7. Postfix Queue & Delivery Channel Audit"
    local queue_status=""
    local attempts=0
    while (( attempts < 10 )); do
        queue_status="$("${CONTAINER_ENGINE}" exec "${POSTFIX_CONTAINER}" postqueue -p 2>&1 || true)"
        if [[ "${queue_status}" =~ "Mail queue is empty" ]]; then
            break
        fi
        "${CONTAINER_ENGINE}" exec "${POSTFIX_CONTAINER}" postqueue -f >/dev/null 2>&1 || true
        sleep 1
        (( attempts++ ))
    done
    info "Postfix Queue Status: ${queue_status}"
    [[ "${queue_status}" =~ "Mail queue is empty" ]] || fail "Ada pesan tertahan di antrean Postfix."
    pass "Postfix Relay Queue bersih (0 pesan tertahan / Mail queue is empty)"

    printf "\n${GREEN}══════════════════════════════════════════════════════════════════════${NC}\n"
    printf "${GREEN}✔ SELURUH PENGUJIAN INSIDEN TOMCATDOWN TELAH BERHASIL DIVERIFIKASI!   ${NC}\n"
    printf "${GREEN}══════════════════════════════════════════════════════════════════════${NC}\n"
}

main "$@"
