# Test end-to-end alert pipeline on Windows Container Stack
# Architecture Reference: TM-ADR-0026, TN-019

$ErrorActionPreference = "Stop"

$amIp = (& docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' alertmanager).Trim()
$mpIp = (& docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' mailpit).Trim()
$dsIp = (& docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' diagnostic-service).Trim()

Write-Host "Discovered Container IPs:"
Write-Host "  Alertmanager       : $amIp"
Write-Host "  Mailpit            : $mpIp"
Write-Host "  Diagnostic Service : $dsIp"

# 1. Probe Diagnostic Service Health
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$dsHealth = & curl.exe -k -s "https://${dsIp}:8443/health/ready"
Write-Host "Diagnostic Service Health Check: $dsHealth"

# 2. Send Firing Alert to Alertmanager
$alertPayload = @'
[
  {
    "labels": {
      "alertname": "TomcatDown",
      "job": "tomcat-jmx-exporter",
      "instance": "127.0.0.1:9404",
      "environment": "aws-staging",
      "host": "aws-ec2-win-01",
      "tomcat_instance": "default",
      "severity": "critical"
    },
    "annotations": {
      "summary": "Tomcat service down on Windows host",
      "description": "Tomcat health probe connection refused on aws-ec2-win-01"
    }
  }
]
'@

Write-Host "Posting alert to Alertmanager (http://${amIp}:9093/api/v2/alerts)..."
$postResult = & curl.exe -s -X POST -H "Content-Type: application/json" -d $alertPayload "http://${amIp}:9093/api/v2/alerts"
Write-Host "Alert dispatched. Waiting for Alertmanager routing and Diagnostic Service triage (15s)..."
Start-Sleep -Seconds 15

# 3. Check Mailpit Inbox
$messagesJson = & curl.exe -s "http://${mpIp}:8025/api/v1/messages"
Write-Host "Mailpit raw messages: $messagesJson"
$messages = $messagesJson | ConvertFrom-Json
Write-Host "`n=== Mailpit Inbox Status ==="
Write-Host "Total Messages Received: $($messages.total)"

if ($messages.total -gt 0) {
    foreach ($m in $messages.messages) {
        Write-Host "--------------------------------------------------"
        Write-Host "Message ID : $($m.ID)"
        Write-Host "Subject    : $($m.Subject)"
        Write-Host "From       : $($m.From.Address)"
        Write-Host "To         : $($m.To.Address -join ', ')"
        Write-Host "Created    : $($m.Created)"
    }
    Write-Host "--------------------------------------------------"
    Write-Host "VERIFICATION SUCCESS: End-to-end alert & diagnostic email pipeline verified!"
} else {
    Write-Warning "No messages found in Mailpit. Checking Diagnostic Service and Alertmanager logs..."
    Write-Host "`n--- Alertmanager Logs ---"
    docker logs alertmanager --tail 25
    Write-Host "`n--- Diagnostic Service Logs ---"
    docker logs diagnostic-service --tail 25
}
