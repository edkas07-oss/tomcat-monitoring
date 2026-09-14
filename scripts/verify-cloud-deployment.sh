#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/verify-cloud-deployment.sh
# Tujuan: Verifikasi live multi-node / multi-OS (Linux & Windows) pada cloud deployment
# Architecture Reference: TM-ADR-0028, TN-017 & TN-018
# ==============================================================================

set -euo pipefail

INVENTORY_FILE="${1:-}"
TARGET_FILTER="${2:-all}"
SSH_KEY_PATH="${SSH_KEY_FILE:-${ANSIBLE_SSH_KEY_FILE:-~/.ssh/tomcat-monitoring-aws-key.pem}}"

if [[ -z "${INVENTORY_FILE}" || ! -f "${INVENTORY_FILE}" ]]; then
    echo "Error: Inventory file '${INVENTORY_FILE}' tidak ditemukan!" >&2
    exit 1
fi

echo "========================================"
echo "LIVE CLOUD DEPLOYMENT VERIFICATION"
echo "========================================"
echo "Inventory File: ${INVENTORY_FILE}"
echo "Target Filter : ${TARGET_FILTER}"
echo "SSH Key       : ${SSH_KEY_PATH}"
echo "========================================"

# Gunakan python helper untuk mem-parsing inventory dan mengeksekusi verifikasi multi-OS
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
    print(f"Peringatan: Tidak ada host di {inv_file} yang cocok dengan filter '{target_filter}'.", flush=True)
    sys.exit(0)

print(f"Ditemukan {len(matched_hosts)} target host untuk diverifikasi:\n", flush=True)

total_failed = 0

for h in matched_hosts:
    host_name = h['name']
    host_ip = h['ip']
    host_user = h['user']
    os_type = h['os']
    
    print("--------------------------------------------------", flush=True)
    print(f"Verifikasi Node: {host_name} ({host_user}@{host_ip}) [OS: {os_type.upper()}]", flush=True)
    print("--------------------------------------------------", flush=True)
    
    ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "ConnectTimeout=15"]
    if os.path.exists(ssh_key):
        ssh_opts = ["-i", ssh_key] + ssh_opts

    if os_type == 'windows':
        ps_script = """
$ProgressPreference = "SilentlyContinue"
Write-Output "1. Memeriksa direktori instalasi C:\\monitoring..."
if (Test-Path "C:\\monitoring\\bin") { Write-Output "Monitoring Directories: OK" } else { Write-Output "C:\\monitoring\\bin NOT FOUND" }
Write-Output "2. Memeriksa ketersediaan binary tm-agent / tmctl..."
if (Test-Path "C:\\monitoring\\bin\\tm-agent.exe") { Write-Output "tm-agent.exe: PRESENT" } else { Write-Output "tm-agent.exe: NOT FOUND" }
Write-Output "3. Memeriksa status proses tm-agent daemon..."
$p = Get-Process -Name tm-agent -ErrorAction SilentlyContinue
if ($p) { Write-Output "tm-agent daemon: ACTIVE (PID: $($p.Id))" } else { Write-Output "tm-agent daemon: NOT RUNNING" }
"""
        encoded_cmd = base64.b64encode(ps_script.encode("utf-16le")).decode("ascii")
        cmd = ["ssh"] + ssh_opts + [f"{host_user}@{host_ip}", f"powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {encoded_cmd}"]
    else:
        linux_cmd = (
            "set -euo pipefail; "
            "echo '1. Memeriksa status kesehatan Diagnostic Service...'; "
            "curl -sk https://127.0.0.1:8443/health >/dev/null && echo 'Diagnostic Service: OK' || echo 'Diagnostic Service: DOWN'; "
            "echo '2. Memeriksa kesiapan Prometheus TSDB...'; "
            "curl -s http://127.0.0.1:9090/-/ready >/dev/null && echo 'Prometheus: READY' || echo 'Prometheus: DOWN'; "
            "echo '3. Memeriksa kesiapan Alertmanager...'; "
            "curl -s http://127.0.0.1:9093/-/ready >/dev/null && echo 'Alertmanager: OK' || echo 'Alertmanager: DOWN'; "
            "echo '4. Memeriksa ketersediaan metrik Tomcat JMX Exporter...'; "
            "curl -sk https://127.0.0.1:9404/metrics >/dev/null && echo 'Tomcat JMX Exporter: OK' || echo 'Tomcat JMX Exporter: DOWN'; "
            "echo '5. Memeriksa Mailpit inbox...'; "
            "curl -s http://127.0.0.1:8025/api/v1/messages >/dev/null && echo 'Mailpit API: OK' || echo 'Mailpit API: DOWN'; "
            "echo '6. Memeriksa status service tm-agent daemon...'; "
            "systemctl --user is-active tm-agent >/dev/null && echo 'tm-agent daemon: ACTIVE' || echo 'tm-agent daemon: INACTIVE'; "
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
            print(f"✘ Verifikasi host {host_name} ({host_ip}) mengembalikan exit code {res.returncode}\n", flush=True)
            total_failed += 1
        else:
            print(f"✔ Verifikasi host {host_name} ({host_ip}) selesai dengan sukses.\n", flush=True)
    except Exception as e:
        print(f"✘ Gagal menghubungi host {host_name} ({host_ip}): {e}\n", flush=True)
        total_failed += 1

if total_failed > 0:
    print(f"Total kegagalan verifikasi host: {total_failed}", flush=True)
    sys.exit(1)
EOF

echo "Live cloud deployment verification completed."
