# =====================================================================
# BC44 Pipeline - sample tests (PowerShell, Windows-friendly)
# ---------------------------------------------------------------------
#   $env:N8N_BASE_URL      base url (default http://localhost:5678)
#   $env:N8N_WEBHOOK_TOKEN bearer token (default dev-local-token)
# Usage:  .\scripts\test_all.ps1
# =====================================================================
$ErrorActionPreference = "Continue"
$base  = if ($env:N8N_BASE_URL) { $env:N8N_BASE_URL } else { "http://localhost:5678" }
$token = if ($env:N8N_WEBHOOK_TOKEN) { $env:N8N_WEBHOOK_TOKEN } else { "dev-local-token" }
$pdir  = Join-Path $PSScriptRoot "..\samples\payloads"

function Invoke-WF([string]$path, [string]$file) {
  Write-Host "`n========== $path ==========" -ForegroundColor Cyan
  $body = Get-Content (Join-Path $pdir $file) -Raw -Encoding UTF8
  $headers = @{ Authorization = "Bearer $token"; "X-Request-Id" = ([guid]::NewGuid().ToString()) }
  try {
    $r = Invoke-RestMethod -Uri "$base/webhook/$path" -Method POST -Headers $headers -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
    $r | ConvertTo-Json -Depth 20
  } catch {
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
  }
}

Write-Host "========== health (GET) ==========" -ForegroundColor Cyan
try { (Invoke-RestMethod -Uri "$base/webhook/health" -Method GET) | ConvertTo-Json -Depth 20 } catch { Write-Host $_.Exception.Message -ForegroundColor Red }

Invoke-WF "document-ingest"     "document-ingest.json"
Invoke-WF "rag-chat"            "rag-chat.json"
Invoke-WF "web-crawl"           "web-crawl.json"
Invoke-WF "evaluation-simulate" "evaluation-simulate.json"
Invoke-WF "report-generate"     "report-generate.json"
Invoke-WF "wbs-delay-check"     "wbs-delay-check.json"
Invoke-WF "llm-route"           "llm-route.json"
Invoke-WF "notify"              "notify.json"
Invoke-WF "vector-reindex"      "vector-reindex.json"

Write-Host "`n========== AUTH fail case ==========" -ForegroundColor Yellow
try {
  $h = @{ Authorization = "Bearer WRONG" }
  Invoke-RestMethod -Uri "$base/webhook/document-ingest" -Method POST -Headers $h -ContentType "application/json" -Body (Get-Content (Join-Path $pdir "document-ingest.json") -Raw) | ConvertTo-Json -Depth 10
} catch { Write-Host $_.Exception.Message }

Write-Host "`nDone. Mock callbacks: GET http://localhost:4000/callbacks"
