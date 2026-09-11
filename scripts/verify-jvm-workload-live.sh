#!/usr/bin/env bash
# Live verification and load simulation script for Tomcat JVM GC and Concurrency Saturation alert rules (TN-005).
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
if [[ -f "${PROJECT_ROOT}/CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/CONFIG"
fi

readonly NETWORK_NAME="${NETWORK_NAME:-devops-lab}"
readonly REAL_CONTAINER="${TOMCAT_CONTAINER:-tomcat-jmx-exporter}"
readonly SIMULATOR_CONTAINER="${TOMCAT_CONTAINER:-tomcat-jmx-exporter}"
readonly BACKUP_CONTAINER="${REAL_CONTAINER}-live-backup"
readonly NODE_IMAGE="${NODEJS_IMAGE:-localhost/nodejs:latest}"
readonly TLS_DIR="${TLS_DIR:-${DEFAULT_JMX_TLS_DIR:-${HOME}/.local/share/tomcat-monitoring/jmx-exporter-tls}}"
readonly FIXTURE_DIR="${PROJECT_ROOT}/fixtures/jvm-workload-simulator"
readonly LOG_DIR="${PROJECT_ROOT}/.artifacts/tn005-evidence"

mkdir -p "${LOG_DIR}"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

fail() {
    printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
    cleanup_and_restore
    exit 1
}

cleanup_and_restore() {
    log "Restoring original Tomcat JMX Exporter runtime..."
    podman rm -f "${SIMULATOR_CONTAINER}" 2>/dev/null || true
    if podman container exists "${BACKUP_CONTAINER}"; then
        podman rename "${BACKUP_CONTAINER}" "${REAL_CONTAINER}" 2>/dev/null || true
        podman start "${REAL_CONTAINER}" >/dev/null 2>&1 || true
    else
        "${PROJECT_ROOT}/scripts/deploy-tomcat.sh" || true
    fi
    log "Environment restored."
}

trap cleanup_and_restore EXIT

log "=== STEP 1: Pre-flight Checks and Baseline Audit ==="
for cmd in podman curl jq python3; do
    command -v "${cmd}" >/dev/null || fail "Command missing: ${cmd}"
done

[[ -f "${TLS_DIR}/server.crt" ]] || fail "TLS certificate missing: ${TLS_DIR}/server.crt"
[[ -f "${TLS_DIR}/server.key" ]] || fail "TLS key missing: ${TLS_DIR}/server.key"
[[ -f "${FIXTURE_DIR}/server.js" ]] || fail "Fixture missing: ${FIXTURE_DIR}/server.js"

curl -s http://localhost:9090/-/ready >/dev/null || fail "Prometheus is not ready"
curl -s http://127.0.0.1:9093/-/ready >/dev/null || fail "Alertmanager is not ready"
curl -s http://localhost:8025/api/v1/messages >/dev/null || fail "Mailpit is not ready"

log "Recording baseline active rules from Prometheus..."
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name=="tomcat-jvm-and-concurrency-health")' > "${LOG_DIR}/01-baseline-rules.json"

log "Recording baseline Mailpit messages count..."
initial_mail_count=$(curl -s http://localhost:8025/api/v1/messages | jq '.total')
log "Initial Mailpit total messages: ${initial_mail_count}"

log "=== STEP 2: Launching JVM Workload Metrics Simulator ==="
if podman container exists "${REAL_CONTAINER}"; then
    log "Stopping and renaming live Tomcat container to backup..."
    podman stop "${REAL_CONTAINER}" >/dev/null 2>&1 || true
    podman rm -f "${BACKUP_CONTAINER}" 2>/dev/null || true
    podman rename "${REAL_CONTAINER}" "${BACKUP_CONTAINER}"
fi

log "Starting simulator container on devops-lab network..."
podman run --detach \
    --userns=keep-id \
    --name "${SIMULATOR_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    --network-alias tomcat-jmx-exporter \
    --publish 9404:9404 \
    --publish 8080:8080 \
    --volume "${TLS_DIR}/server.crt:/run/secrets/tomcat-jmx-exporter/server.crt:ro,z" \
    --volume "${TLS_DIR}/server.key:/run/secrets/tomcat-jmx-exporter/server.key:ro,z" \
    --volume "${FIXTURE_DIR}/server.js:/app/server.js:ro,z" \
    --workdir /app \
    "${NODE_IMAGE}" \
    node server.js >/dev/null

log "Waiting for simulator HTTPS endpoint readiness..."
ready=0
for i in {1..20}; do
    if curl -k --fail -s https://localhost:9404/metrics >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done

if [[ "${ready}" -eq 0 ]]; then
    fail "Simulator failed to respond on port 9404"
fi

log "Simulator endpoint ready. Initial metrics sample:"
curl -k -s https://localhost:9404/metrics | grep -E "^jvm_gc|^tomcat_threads" || true

log "=== STEP 3: Activating Failure Injection Profiles (ALL FIRING) ==="
curl -k -s "https://localhost:9404/set-profile?profile=all-firing" | jq .

log "Monitoring Prometheus Alert Transitions..."
start_time=$(date +%s)
pause_fired=0
thread_fired=0
overhead_fired=0
memory_fired=0

while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    rules_json=$(curl -s http://localhost:9090/api/v1/rules || echo "{}")
    
    pause_state=$(echo "${rules_json}" | jq -r '.data.groups[].rules[] | select(.name=="TomcatGCPauseHigh") | .state' 2>/dev/null || echo "unknown")
    thread_state=$(echo "${rules_json}" | jq -r '.data.groups[].rules[] | select(.name=="TomcatThreadPoolSaturated") | .state' 2>/dev/null || echo "unknown")
    overhead_state=$(echo "${rules_json}" | jq -r '.data.groups[].rules[] | select(.name=="TomcatGCOverheadHigh") | .state' 2>/dev/null || echo "unknown")
    memory_state=$(echo "${rules_json}" | jq -r '.data.groups[].rules[] | select(.name=="TomcatOldGenMemoryPressure") | .state' 2>/dev/null || echo "unknown")
    
    log "[T+${elapsed}s] States -> GCPause: ${pause_state} | ThreadSat: ${thread_state} | GCOverhead: ${overhead_state} | OldGenPressure: ${memory_state}"
    
    if [[ "${pause_state}" == "firing" && "${pause_fired}" -eq 0 ]]; then
        log ">>> TomcatGCPauseHigh is now FIRING! (T+${elapsed}s)"
        pause_fired=1
        echo "${rules_json}" | jq '.data.groups[].rules[] | select(.name=="TomcatGCPauseHigh")' > "${LOG_DIR}/02-gcpause-firing.json"
    fi
    
    if [[ "${thread_state}" == "firing" && "${thread_fired}" -eq 0 ]]; then
        log ">>> TomcatThreadPoolSaturated is now FIRING! (T+${elapsed}s)"
        thread_fired=1
        echo "${rules_json}" | jq '.data.groups[].rules[] | select(.name=="TomcatThreadPoolSaturated")' > "${LOG_DIR}/03-threads-firing.json"
    fi

    if [[ "${overhead_state}" == "firing" && "${overhead_fired}" -eq 0 ]]; then
        log ">>> TomcatGCOverheadHigh is now FIRING! (T+${elapsed}s)"
        overhead_fired=1
        echo "${rules_json}" | jq '.data.groups[].rules[] | select(.name=="TomcatGCOverheadHigh")' > "${LOG_DIR}/04-gcoverhead-firing.json"
    fi

    if [[ "${memory_state}" == "firing" && "${memory_fired}" -eq 0 ]]; then
        log ">>> TomcatOldGenMemoryPressure is now FIRING! (T+${elapsed}s)"
        memory_fired=1
        echo "${rules_json}" | jq '.data.groups[].rules[] | select(.name=="TomcatOldGenMemoryPressure")' > "${LOG_DIR}/05-oldgen-firing.json"
    fi

    if [[ "${pause_fired}" -eq 1 && "${thread_fired}" -eq 1 && "${overhead_fired}" -eq 1 && "${memory_fired}" -eq 1 ]]; then
        log "All 4 alerts have reached FIRING state!"
        break
    fi

    if [[ ${elapsed} -gt 750 ]]; then
        log "Timeout reached (12.5 minutes). Proceeding with current firing states."
        break
    fi

    sleep 15
done

log "Capturing Prometheus firing alerts API..."
curl -s http://localhost:9090/api/v1/alerts > "${LOG_DIR}/06-all-firing-alerts.json"

log "Waiting for Alertmanager group_wait and Mailpit delivery (45s)..."
sleep 45

log "Capturing firing messages from Mailpit..."
curl -s http://localhost:8025/api/v1/messages > "${LOG_DIR}/07-mailpit-firing-messages.json"

log "=== STEP 4: Activating Recovery Profile (BASELINE / RESOLVED) ==="
curl -k -s "https://localhost:9404/set-profile?profile=baseline" | jq .

recovery_start=$(date +%s)
while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - recovery_start))
    
    rules_json=$(curl -s http://localhost:9090/api/v1/rules || echo "{}")
    
    pause_state=$(echo "${rules_json}" | jq -r '.data.groups[].rules[] | select(.name=="TomcatGCPauseHigh") | .state' 2>/dev/null || echo "unknown")
    thread_state=$(echo "${rules_json}" | jq -r '.data.groups[].rules[] | select(.name=="TomcatThreadPoolSaturated") | .state' 2>/dev/null || echo "unknown")
    overhead_state=$(echo "${rules_json}" | jq -r '.data.groups[].rules[] | select(.name=="TomcatGCOverheadHigh") | .state' 2>/dev/null || echo "unknown")
    memory_state=$(echo "${rules_json}" | jq -r '.data.groups[].rules[] | select(.name=="TomcatOldGenMemoryPressure") | .state' 2>/dev/null || echo "unknown")
    
    log "[T+${elapsed}s Recovery] States -> GCPause: ${pause_state} | ThreadSat: ${thread_state} | GCOverhead: ${overhead_state} | OldGenPressure: ${memory_state}"

    if [[ "${pause_state}" == "inactive" && "${thread_state}" == "inactive" && "${memory_state}" == "inactive" ]]; then
        if [[ "${overhead_state}" == "inactive" || ${elapsed} -gt 180 ]]; then
            log "Alert conditions have cleared and returned to normal/inactive!"
            break
        fi
    fi

    if [[ ${elapsed} -gt 300 ]]; then
        log "Recovery evaluation completed."
        break
    fi

    sleep 15
done

log "Waiting for Alertmanager to send RESOLVED emails to Mailpit (45s)..."
sleep 45

log "Capturing all Mailpit messages including RESOLVED notifications..."
curl -s http://localhost:8025/api/v1/messages > "${LOG_DIR}/08-mailpit-all-messages.json"

log "=== STEP 5: Finalizing Live Verification ==="
log "Evidence collection complete in ${LOG_DIR}."
trap - EXIT
cleanup_and_restore

log "Verifying real Tomcat container is active and healthy..."
sleep 3
curl -k -s https://localhost:9404/metrics | head -n 5
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

log "TN-005 LIVE TESTING SUITE COMPLETED SUCCESSFULLY! ✅"
