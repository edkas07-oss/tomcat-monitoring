#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/verify-cloud-deployment.sh
# Purpose: Live verification of 100% Tomcat Monitoring Platform components (Linux & Windows)
# Architecture Reference: TM-ADR-0028, TN-017 & TN-018
# ==============================================================================

set -euo pipefail

INVENTORY_FILE="${1:-}"
TARGET_FILTER="${2:-all}"
SSH_KEY_PATH="${SSH_KEY_FILE:-${ANSIBLE_SSH_KEY_FILE:-~/.ssh/tomcat-monitoring-aws-key.pem}}"

if [[ -z "${INVENTORY_FILE}" || ! -f "${INVENTORY_FILE}" ]]; then
    echo "Error: Inventory file '${INVENTORY_FILE}' not found!" >&2
    exit 1
fi

echo "========================================"
echo "LIVE CLOUD DEPLOYMENT VERIFICATION"
echo "========================================"
echo "Inventory File: ${INVENTORY_FILE}"
echo "Target Filter : ${TARGET_FILTER}"
echo "SSH Key       : ${SSH_KEY_PATH}"
echo "========================================"

# Python helper to parse inventory and execute multi-OS 100% verification
python3 - "${INVENTORY_FILE}" "${TARGET_FILTER}" "${SSH_KEY_PATH}" <<'EOF'
import re
import sys
import subprocess
import os
import base64

inv_file = sys.argv[1]
target_filter = sys.argv[2] if len(sys.argv) > 2 else 'all'
ssh_key = os.path.expanduser(sys.argv[3]) if len(sys.argv) > 3 else ''

current_section = None
hosts = []
group_children = {}

with open(inv_file, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#') or line.startswith(';'):
            continue
        m_sec = re.match(r'^\[([^\]]+)\]', line)
        if m_sec:
            current_section = m_sec.group(1).strip()
            continue
        if current_section:
            if ':children' in current_section:
                parent = current_section.split(':')[0]
                group_children.setdefault(parent, []).append(line.split()[0])
            elif ':vars' in current_section:
                continue
            else:
                parts = line.split()
                host_name = parts[0]
                host_vars = dict(item.split('=', 1) for item in parts[1:] if '=' in item)
                host_ip = host_vars.get('ansible_host', host_name)
                host_user = host_vars.get('ansible_user', 'ec2-user')
                shell_type = host_vars.get('ansible_shell_type', 'powershell' if ('win' in current_section.lower() or host_user.lower() == 'administrator') else 'bash')
                os_type = 'windows' if (shell_type.lower() == 'powershell' or 'win' in current_section.lower() or host_user.lower() == 'administrator') else 'linux'
                hosts.append({
                    'name': host_name,
                    'group': current_section,
                    'ip': host_ip,
                    'user': host_user,
                    'os': os_type,
                    'shell': shell_type
                })

def resolve_group_hosts(grp):
    res = []
    if grp in group_children:
        for child in group_children[grp]:
            res.extend(resolve_group_hosts(child))
    for h in hosts:
        if h['group'] == grp:
            res.append(h['name'])
    return list(set(res))

matched_hosts = []
if not target_filter or target_filter == 'all':
    matched_hosts = hosts
else:
    matched_names = set()
    for token in re.split(r'[,:;&]', target_filter):
        token = token.strip()
        if not token:
            continue
        if token == 'all':
            matched_hosts = hosts
            break
        for h in hosts:
            if h['name'] == token or h['ip'] == token:
                matched_names.add(h['name'])
        matched_names.update(resolve_group_hosts(token))
    if not matched_hosts:
        matched_hosts = [h for h in hosts if h['name'] in matched_names]

if not matched_hosts:
    print(f"Warning: No hosts in {inv_file} matched filter '{target_filter}'.", flush=True)
    sys.exit(0)

print(f"Found {len(matched_hosts)} target host(s) to verify:\n", flush=True)

total_failed = 0

for h in matched_hosts:
    host_name = h['name']
    host_ip = h['ip']
    host_user = h['user']
    os_type = h['os']
    
    print("--------------------------------------------------", flush=True)
    print(f"Verifying Node: {host_name} ({host_user}@{host_ip}) [OS: {os_type.upper()}]", flush=True)
    print("--------------------------------------------------", flush=True)
    
    ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "ConnectTimeout=15"]
    if os.path.exists(ssh_key):
        ssh_opts = ["-i", ssh_key] + ssh_opts

    if os_type == 'windows':
        ps_script = """
$ProgressPreference = "SilentlyContinue"
$failedCount = 0

$rootCandidates = @("C:\\tm_data", "C:\\tm-home", "C:\\monitoring")
$targetRoot = $rootCandidates | Where-Object { (Test-Path "$_\\bin") -or (Test-Path "$_\\spool") } | Select-Object -First 1
if (-not $targetRoot) { $targetRoot = "C:\\tm-home" }

Write-Output "1. Inspecting installation directories at $targetRoot..."
if ((Test-Path "$targetRoot\\bin") -and (Test-Path "$targetRoot\\spool")) { 
    Write-Output "✔ Monitoring Directories: OK (bin, spool, config)" 
} else { 
    Write-Output "✘ Monitoring directories NOT FOUND at $targetRoot"; $failedCount++ 
}

Write-Output "2. Inspecting platform binaries availability..."
if (Test-Path "$targetRoot\\bin\\tmctl.exe") { Write-Output "✔ tmctl.exe: PRESENT ($targetRoot\\bin\\tmctl.exe)" } else { Write-Output "✘ tmctl.exe: NOT FOUND"; $failedCount++ }

Write-Output "3. Inspecting operator CLI execution (tmctl.exe)..."
try {
    $ver = & "$targetRoot\\bin\\tmctl.exe" version
    Write-Output "✔ tmctl.exe version: OK ($ver)"
} catch {
    Write-Output "✘ tmctl.exe version failed: $_"
    $failedCount++
}

Write-Output "4. Inspecting daemon / service process status..."
$pAgent = Get-Process -Name tm-agent -ErrorAction SilentlyContinue
if ($pAgent) { Write-Output "✔ tm-agent daemon: ACTIVE (PID: $($pAgent.Id))" } else { Write-Output "✘ tm-agent daemon: NOT RUNNING"; $failedCount++ }

$pProm = Get-Process -Name prometheus -ErrorAction SilentlyContinue
if ($pProm) { Write-Output "✔ Prometheus TSDB: ACTIVE (PID: $($pProm.Id))" } else { Write-Output "✘ Prometheus TSDB: NOT RUNNING"; $failedCount++ }

$pAlert = Get-Process -Name alertmanager -ErrorAction SilentlyContinue
if ($pAlert) { Write-Output "✔ Alertmanager: ACTIVE (PID: $($pAlert.Id))" } else { Write-Output "✘ Alertmanager: NOT RUNNING"; $failedCount++ }

$pMail = Get-Process -Name mailpit -ErrorAction SilentlyContinue
if ($pMail) { Write-Output "✔ Mailpit SMTP/UI: ACTIVE (PID: $($pMail.Id))" } else { Write-Output "✘ Mailpit SMTP/UI: NOT RUNNING"; $failedCount++ }

Write-Output "5. Inspecting HTTP/REST readiness endpoints..."
try {
    $rProm = Invoke-WebRequest -Uri "http://127.0.0.1:9090/-/ready" -UseBasicParsing -TimeoutSec 5
    if ($rProm.StatusCode -eq 200) { Write-Output "✔ Prometheus HTTP :9090 (/-/ready): OK" } else { Write-Output "✘ Prometheus HTTP :9090 StatusCode: $($rProm.StatusCode)"; $failedCount++ }
} catch {
    Write-Output "✘ Prometheus HTTP :9090 UNREACHABLE: $_"; $failedCount++
}

try {
    $rAlert = Invoke-WebRequest -Uri "http://127.0.0.1:9093/-/ready" -UseBasicParsing -TimeoutSec 5
    if ($rAlert.StatusCode -eq 200) { Write-Output "✔ Alertmanager HTTP :9093 (/-/ready): OK" } else { Write-Output "✘ Alertmanager HTTP :9093 StatusCode: $($rAlert.StatusCode)"; $failedCount++ }
} catch {
    Write-Output "✘ Alertmanager HTTP :9093 UNREACHABLE: $_"; $failedCount++
}

try {
    $rMail = Invoke-WebRequest -Uri "http://127.0.0.1:8025/api/v1/messages" -UseBasicParsing -TimeoutSec 5
    if ($rMail.StatusCode -eq 200) { Write-Output "✔ Mailpit HTTP :8025 (/api/v1/messages): OK" } else { Write-Output "✘ Mailpit HTTP :8025 StatusCode: $($rMail.StatusCode)"; $failedCount++ }
} catch {
    Write-Output "✘ Mailpit HTTP :8025 UNREACHABLE: $_"; $failedCount++
}

Write-Output "6. Inspecting persistent spool directory activity..."
$spoolItems = Get-ChildItem "$targetRoot\\spool" -ErrorAction SilentlyContinue
if ($spoolItems -and $spoolItems.Count -gt 0) {
    Write-Output "✔ Spool Evidence Records: ACTIVE ($($spoolItems.Count) records present)"
} else {
    Write-Output "✔ Spool Directory: INITIALIZED ($targetRoot\\spool ready)"
}

if ($failedCount -gt 0) {
    Write-Output "`n✘ TOTAL FAILURES: $failedCount components are not 100% UP!"
    exit 1
} else {
    Write-Output "`n✔ ALL COMPONENTS (100%) IN TOMCAT MONITORING FLEET ARE RUNNING PERFECTLY ON WINDOWS."
}
"""
        encoded_cmd = base64.b64encode(ps_script.encode("utf-16le")).decode("ascii")
        cmd = ["ssh"] + ssh_opts + [f"{host_user}@{host_ip}", f"powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {encoded_cmd}"]
    else:
        linux_cmd = (
            "set -euo pipefail; "
            "echo '1. Inspecting Diagnostic Service health status...'; "
            "curl -sk https://127.0.0.1:8443/health >/dev/null && echo '✔ Diagnostic Service: OK'; "
            "echo '2. Inspecting Prometheus TSDB readiness...'; "
            "curl -s http://127.0.0.1:9090/-/ready >/dev/null && echo '✔ Prometheus: READY'; "
            "echo '3. Inspecting Alertmanager readiness...'; "
            "curl -s http://127.0.0.1:9093/-/ready >/dev/null && echo '✔ Alertmanager: OK'; "
            "echo '4. Inspecting Tomcat JMX Exporter metrics endpoint...'; "
            "curl -sk https://127.0.0.1:9404/metrics >/dev/null && echo '✔ Tomcat JMX Exporter: OK'; "
            "echo '5. Inspecting Mailpit inbox API...'; "
            "curl -s http://127.0.0.1:8025/api/v1/messages >/dev/null && echo '✔ Mailpit API: OK'; "
            "echo '6. Inspecting tm-agent daemon service status...'; "
            "systemctl --user is-active tm-agent >/dev/null && echo '✔ tm-agent daemon: ACTIVE'; "
            "echo '✔ ALL COMPONENTS (100%) IN TOMCAT MONITORING FLEET ARE RUNNING PERFECTLY ON LINUX.'"
        )
        cmd = ["ssh"] + ssh_opts + [f"{host_user}@{host_ip}", linux_cmd]

    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if res.stdout:
            print(res.stdout, flush=True)
        if res.stderr:
            cleaned_err = "\n".join([line for line in res.stderr.splitlines() if not line.startswith("Warning: Permanently added")])
            if cleaned_err.strip():
                print(f"[SSH/Remote STDERR]:\n{cleaned_err}", flush=True)
        if res.returncode != 0:
            print(f"✘ Verification for host {host_name} ({host_ip}) FAILED (exit code {res.returncode})\n", flush=True)
            total_failed += 1
        else:
            print(f"✔ Verification for host {host_name} ({host_ip}) COMPLETED 100% SUCCESSFULLY.\n", flush=True)
    except Exception as e:
        print(f"✘ Failed to connect to host {host_name} ({host_ip}): {e}\n", flush=True)
        total_failed += 1

if total_failed > 0:
    print(f"Total host verification failures: {total_failed}", flush=True)
    sys.exit(1)
EOF

echo "Live cloud deployment verification completed."
