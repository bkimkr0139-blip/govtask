# =====================================================================
# BC44 Pipeline - workflow export script
# Pulls "[BC44" workflows from the n8n public API into workflows/*.json
# ---------------------------------------------------------------------
# Usage:
#   $env:N8N_API_URL = "http://127.0.0.1:5678"
#   $env:N8N_API_KEY = "<your n8n api key>"
#   .\scripts\export_workflows.ps1
# NOTE: never hardcode the API key in this file.
# =====================================================================
$ErrorActionPreference = "Stop"
$apiUrl = if ($env:N8N_API_URL) { $env:N8N_API_URL } else { "http://127.0.0.1:5678" }
$apiKey = $env:N8N_API_KEY
if (-not $apiKey) { Write-Error "Set N8N_API_KEY environment variable."; exit 1 }

$outDir = Join-Path $PSScriptRoot "..\workflows"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$headers = @{ "X-N8N-API-KEY" = $apiKey; "Accept" = "application/json" }

$list = Invoke-RestMethod -Uri "$apiUrl/api/v1/workflows?limit=100" -Headers $headers -Method GET
$targets = $list.data | Where-Object { $_.name -match 'BC44' }
Write-Output ("Target workflows: " + $targets.Count)

foreach ($w in $targets) {
  $full = Invoke-RestMethod -Uri "$apiUrl/api/v1/workflows/$($w.id)" -Headers $headers -Method GET
  $export = [ordered]@{
    name        = $full.name
    nodes       = $full.nodes
    connections = $full.connections
    settings    = $full.settings
  }
  $webhookNode = $full.nodes | Where-Object { $_.type -eq "n8n-nodes-base.webhook" } | Select-Object -First 1
  $wfPath = $webhookNode.parameters.path
  if (-not $wfPath) { $wfPath = $full.id }
  $fileName = "$wfPath.json"
  $target = Join-Path $outDir $fileName
  $export | ConvertTo-Json -Depth 30 | Out-File -FilePath $target -Encoding utf8
  Write-Output ("  saved: workflows/$fileName  <- " + $full.name)
}
Write-Output "Done."
