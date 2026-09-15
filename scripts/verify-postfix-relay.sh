#!/usr/bin/env bash
# Automated Verification Suite for Postfix Enterprise SMTP Relay Bridge (Pattern A).
# Architecture:
#   [Diagnostic Service] ──(Port 587 / STARTTLS + SASL)──► [Postfix Container] ──(Downstream Relay / Port 1025)──► [Mailpit Web UI / Port 8025]
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
readonly POSTFIX_CONTAINER="${POSTFIX_CONTAINER:-postfix-relay}"
readonly DIAGNOSTIC_CONTAINER="${DIAGNOSTIC_CONTAINER:-diagnostic-service}"
readonly MAILPIT_CONTAINER="${MAILPIT_CONTAINER:-mailpit}"
if [[ -z "${DIAGNOSTIC_SERVICE_DIR:-}" ]]; then
    if [[ -d "$(dirname "${PROJECT_ROOT}")/tomcat-diagnostic-service" ]]; then
        DIAGNOSTIC_SERVICE_DIR="$(dirname "${PROJECT_ROOT}")/tomcat-diagnostic-service"
    elif [[ -d "${HOME}/git/tomcat-diagnostic-service" ]]; then
        DIAGNOSTIC_SERVICE_DIR="${HOME}/git/tomcat-diagnostic-service"
    else
        DIAGNOSTIC_SERVICE_DIR="$(dirname "${PROJECT_ROOT}")/tomcat-diagnostic-service"
    fi
fi
readonly DIAGNOSTIC_SERVICE_DIR
readonly MAILPIT_API_URL="http://127.0.0.1:${MAILPIT_HTTP_PORT:-8025}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { printf "${GREEN}✔ PASS:${NC} %s\n" "$1"; }
fail() { printf "${RED}✘ FAIL:${NC} %s\n" "$1" >&2; exit 1; }
info() { printf "${BLUE}ℹ INFO:${NC} %s\n" "$1"; }
section() {
    printf "\n${CYAN}======================================================================${NC}\n"
    printf "${CYAN}▶ %s${NC}\n" "$1"
    printf "${CYAN}======================================================================${NC}\n"
}

main() {
    printf "${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${YELLOW}║   POSTFIX ENTERPRISE SMTP RELAY BRIDGE (PATTERN A) VERIFICATION SUITE║${NC}\n"
    printf "${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"

    local vol_ro="$(get_volume_flag "ro")"

    section "1. Pre-Flight Infrastructure & Container Readiness"
    network_exists "${NETWORK_NAME}" || fail "Network ${NETWORK_NAME} not found."
    pass "Network ${NETWORK_NAME} active"
    [[ -d "${DIAGNOSTIC_SERVICE_DIR}" ]] || fail "Diagnostic service directory not found: ${DIAGNOSTIC_SERVICE_DIR}"
    pass "Diagnostic service directory verified: ${DIAGNOSTIC_SERVICE_DIR}"

    for container in "${MAILPIT_CONTAINER}" "${POSTFIX_CONTAINER}" "${DIAGNOSTIC_CONTAINER}"; do
        container_exists "${container}" || fail "Container ${container} not found."
        local status
        status="$("${CONTAINER_ENGINE}" inspect --format '{{.State.Status}}' "${container}")"
        [[ "${status}" == "running" ]] || fail "Container ${container} has status ${status} (expected running)."
        pass "Container ${container} running (status: running)"
    done

    section "2. Postfix Image & Service Smoke Inspection"
    local version_info
    version_info="$("${CONTAINER_ENGINE}" exec "${POSTFIX_CONTAINER}" postconf mail_version)"
    info "Postfix runtime version: ${version_info}"
    [[ "${version_info}" =~ mail_version\ =\ 3\. ]] || fail "Postfix version does not match 3.x baseline"
    pass "Postfix runtime engine verified"

    section "3. SASL Authentication Negative Testing (Port 587 Security Defense)"
    info "Testing rejection of unauthenticated delivery attempts..."
    local unauth_result
    unauth_result="$("${CONTAINER_ENGINE}" run --rm --network "${NETWORK_NAME}" \
        -v "${DIAGNOSTIC_SERVICE_DIR}:/app${vol_ro}" -w /app "${NODEJS_IMAGE}" \
        node --input-type=module -e '
import nodemailer from "nodemailer";
const transport = nodemailer.createTransport({
  host: "postfix-relay",
  port: 587,
  secure: false,
  tls: { rejectUnauthorized: false }
});
try {
  await transport.sendMail({ from: "unauth@example.local", to: "operator@tomcat-monitoring.invalid", subject: "unauth", text: "unauth" });
  process.exit(1);
} catch (err) {
  console.log("REJECTED_AS_EXPECTED:" + err.message);
  process.exit(0);
}
' 2>&1)" || fail "Postfix permitted relay without SASL authentication!"
    info "Unauthenticated rejection response: ${unauth_result}"
    pass "Postfix rejected relay connection without SASL credentials"

    info "Testing authentication failure with invalid credentials..."
    local wrong_cred_result
    wrong_cred_result="$("${CONTAINER_ENGINE}" run --rm --network "${NETWORK_NAME}" \
        -v "${DIAGNOSTIC_SERVICE_DIR}:/app${vol_ro}" -w /app "${NODEJS_IMAGE}" \
        node --input-type=module -e '
import nodemailer from "nodemailer";
const transport = nodemailer.createTransport({
  host: "postfix-relay",
  port: 587,
  secure: false,
  auth: { user: "diagnostic-service", pass: "WrongPassword999!" },
  tls: { rejectUnauthorized: false }
});
try {
  await transport.sendMail({ from: "diagnostic@tomcat-monitoring.invalid", to: "operator@tomcat-monitoring.invalid", subject: "wrong", text: "wrong" });
  process.exit(1);
} catch (err) {
  console.log("REJECTED_AS_EXPECTED:" + err.message);
  process.exit(0);
}
' 2>&1)" || fail "Postfix permitted login with incorrect password!"
    info "Wrong password rejection response: ${wrong_cred_result}"
    pass "Postfix rejected invalid SASL credentials (Authentication Failed)"

    section "4. Direct STARTTLS + SASL Submission to Downstream Mailpit Relay"
    info "Sending authenticated STARTTLS + SASL test email directly to Postfix Port 587..."
    local send_result
    send_result="$("${CONTAINER_ENGINE}" run --rm --network "${NETWORK_NAME}" \
        -v "${DIAGNOSTIC_SERVICE_DIR}:/app${vol_ro}" -w /app "${NODEJS_IMAGE}" \
        node --input-type=module -e '
import nodemailer from "nodemailer";
const transport = nodemailer.createTransport({
  host: "postfix-relay",
  port: 587,
  secure: false,
  auth: { user: "diagnostic-service", pass: "SecretPassword123!" },
  tls: { rejectUnauthorized: false }
});
try {
  const info = await transport.sendMail({
    from: "diagnostic@tomcat-monitoring.invalid",
    to: "operator@tomcat-monitoring.invalid",
    subject: "[CRITICAL] [LAB] Postfix Pattern A Smoke Test",
    text: "Pattern A Enterprise Relay Bridge direct test verification.",
    html: "<p>Pattern A Enterprise Relay Bridge direct test verification.</p>"
  });
  console.log("SUCCESS:" + info.response);
} catch (err) {
  console.error("FAIL:" + err.message);
  process.exit(1);
}
')"
    info "Dispatch result: ${send_result}"
    [[ "${send_result}" =~ SUCCESS:250 ]] || fail "Direct delivery via Postfix failed."
    pass "Postfix accepted authenticated email, queued message, and relayed to Mailpit"

    section "5. End-to-End Incident Webhook -> Diagnostic Service -> Postfix -> Mailpit"
    info "Posting TomcatDown incident webhook to Diagnostic Service..."
    local test_fingerprint="postfix-relay-e2e-$(date +%s)"
    local payload_dir
    payload_dir="$(mktemp -d)"
    local tmp_payload="${payload_dir}/postfix-e2e-payload.json"
    python3 - "${test_fingerprint}" "${tmp_payload}" <<'PY'
import json, sys, datetime
now = datetime.datetime.now(datetime.timezone.utc)
fp = sys.argv[1]
out_path = sys.argv[2]
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
    "check": "tomcat-down"
  },
  "commonAnnotations": {
    "summary": "Tomcat instance default on host tomcat-01 is DOWN (Pattern A Automated E2E Verification)",
    "description": "Synthetic TomcatDown alert routed through Postfix Enterprise Relay Bridge."
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
        "check": "tomcat-down"
      },
      "annotations": {
        "summary": "Tomcat instance default on host tomcat-01 is DOWN (Pattern A Automated E2E Verification)",
        "description": "Synthetic TomcatDown alert routed through Postfix Enterprise Relay Bridge."
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

    local webhook_response
    webhook_response="$("${CONTAINER_ENGINE}" run --rm --network "${NETWORK_NAME}" \
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
    rm -rf "${payload_dir}"
    info "Diagnostic Service webhook response: ${webhook_response}"
    [[ "${webhook_response}" =~ HTTP_202 ]] || fail "Diagnostic Service rejected incident webhook."
    pass "Diagnostic Service accepted webhook and initiated incident diagnosis"

    info "Waiting for Diagnostic Service to process and dispatch 7-section report via Postfix..."
    sleep 3

    section "6. Mailpit Web UI & SRE 7-Section Report Content Verification"
    info "Verifying report email in Mailpit Web UI API (${MAILPIT_API_URL})..."
    local mailpit_check
    mailpit_check="$(python3 - "${MAILPIT_API_URL}" <<'PY'
import json, sys, urllib.request

try:
    with urllib.request.urlopen(f"{sys.argv[1]}/api/v1/messages", timeout=5) as resp:
        data = json.load(resp)
except Exception as e:
    sys.exit(f"Failed to query Mailpit API: {e}")

messages = data.get("messages", [])
if not messages:
    sys.exit("Mailpit messages list is empty.")

# Find the latest Diagnostic Service incident message
incident_msg = None
for m in messages:
    if "Tomcat Service: TomcatDown" in m.get("Subject", ""):
        incident_msg = m
        break

if not incident_msg:
    sys.exit("No Diagnostic Service incident message found in Mailpit.")

subject = incident_msg.get("Subject", "")
sender = incident_msg.get("From", {}).get("Address", "")
recipients = [to.get("Address") for to in incident_msg.get("To", [])]
msg_id = incident_msg.get("ID")

print(f"LATEST_SUBJECT={subject}")
print(f"LATEST_SENDER={sender}")
print(f"LATEST_RECIPIENTS={recipients}")

# Retrieve full message HTML & Text
with urllib.request.urlopen(f"{sys.argv[1]}/api/v1/message/{msg_id}", timeout=5) as resp:
    full_msg = json.load(resp)

# Retrieve MIME Headers
with urllib.request.urlopen(f"{sys.argv[1]}/api/v1/message/{msg_id}/headers", timeout=5) as resp:
    headers = json.load(resp)

html = full_msg.get("HTML", "")
text = full_msg.get("Text", "")

# Verify RFC Enterprise Headers
auto_submitted = headers.get("Auto-Submitted", [])
x_priority = headers.get("X-Priority", [])
x_target = headers.get("X-Incident-Target", [])
x_rule = headers.get("X-Diagnostic-Rule", [])

print(f"HEADER_AUTO_SUBMITTED={auto_submitted}")
print(f"HEADER_X_PRIORITY={x_priority}")
print(f"HEADER_X_TARGET={x_target}")
print(f"HEADER_X_RULE={x_rule}")

if "auto-generated" not in auto_submitted:
    sys.exit("Missing or invalid Auto-Submitted header")
if "1" not in x_priority:
    sys.exit("Missing or invalid X-Priority header for critical alert")
if not x_target or "lab/tomcat-01/default" not in x_target[0]:
    sys.exit(f"Missing or invalid X-Incident-Target header: {x_target}")
if "TomcatDown" not in x_rule:
    sys.exit(f"Missing or invalid X-Diagnostic-Rule header: {x_rule}")

print("ENTERPRISE_HEADERS_VERIFIED=true")

# Verify SRE 7-Section tokens
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

print("SEVEN_SECTION_REPORT_VERIFIED=true")
PY
)"
    info "Mailpit audit result:\n${mailpit_check}"
    [[ "${mailpit_check}" =~ ENTERPRISE_HEADERS_VERIFIED=true ]] || fail "RFC enterprise header verification failed in Mailpit."
    [[ "${mailpit_check}" =~ SEVEN_SECTION_REPORT_VERIFIED=true ]] || fail "7-section report format verification failed in Mailpit."
    pass "RFC Enterprise Headers and complete 7-Section SRE Report received in Mailpit via Postfix Relay"

    section "7. Postfix Queue & Resource Audit"
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
    [[ "${queue_status}" =~ "Mail queue is empty" ]] || fail "Messages stuck in Postfix queue: ${queue_status}"
    pass "Postfix Queue clean (0 messages queued / Mail queue is empty)"

    printf "\n${GREEN}══════════════════════════════════════════════════════════════════════${NC}\n"
    printf "${GREEN}✔ ALL PATTERN A (POSTFIX RELAY BRIDGE) TESTS VERIFIED SUCCESSFULLY!   ${NC}\n"
    printf "${GREEN}══════════════════════════════════════════════════════════════════════${NC}\n"
}

main "$@"
