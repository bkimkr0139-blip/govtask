# =====================================================================
# BC44 Pipeline - end-to-end callback test (PowerShell)
# ---------------------------------------------------------------------
# 1) mock callback 서버(http://localhost:4000) 가동 여부 확인
# 2) document-ingest 워크플로우를 callback_url=mock 으로 호출
# 3) mock 서버 /callbacks 를 조회하여 콜백 수신 여부 검증
#
# 사전조건: 다른 창에서 mock 서버 실행
#   node ..\mock\mock_callback_server.js
# Usage:  .\scripts\callback_test.ps1
# =====================================================================
$ErrorActionPreference = "Continue"
$base    = if ($env:N8N_BASE_URL) { $env:N8N_BASE_URL } else { "http://localhost:5678" }
$token   = if ($env:N8N_WEBHOOK_TOKEN) { $env:N8N_WEBHOOK_TOKEN } else { "dev-local-token" }
$mock    = if ($env:MOCK_CALLBACK_URL) { $env:MOCK_CALLBACK_URL } else { "http://localhost:4000" }
$reqId   = "REQ-CBTEST-" + ([guid]::NewGuid().ToString().Substring(0,8))

Write-Host "1) mock callback server health check ($mock/health)" -ForegroundColor Cyan
try {
  $h = Invoke-RestMethod -Uri "$mock/health" -Method GET -TimeoutSec 3
  Write-Host ("   OK - received so far: " + $h.received_count) -ForegroundColor Green
} catch {
  Write-Host "   mock server not reachable. Start it first:" -ForegroundColor Red
  Write-Host "     node $PSScriptRoot\..\mock\mock_callback_server.cjs"
  exit 1
}

Write-Host "2) trigger document-ingest (request_id=$reqId)" -ForegroundColor Cyan
$payload = @{
  request_id   = $reqId
  project_id   = "PRJ-2026-001"
  document_id  = "DOC-CBTEST"
  file_name    = "test.pdf"
  file_url     = "https://example.com/test.pdf"
  file_type    = "pdf"
  user_id      = "user_001"
  callback_url = "$mock/mock-callback"
} | ConvertTo-Json
$headers = @{ Authorization = "Bearer $token" }
$resp = Invoke-RestMethod -Uri "$base/webhook/document-ingest" -Method POST -Headers $headers -ContentType "application/json" -Body $payload
Write-Host ("   workflow response status: " + $resp.status + " / exec " + $resp.n8n_execution_id) -ForegroundColor Green

Start-Sleep -Milliseconds 800
Write-Host "3) verify callback received at mock server" -ForegroundColor Cyan
$cb = Invoke-RestMethod -Uri "$mock/callbacks" -Method GET
$match = $cb.items | Where-Object { $_.request_id -eq $reqId }
if ($match) {
  Write-Host "   PASS - callback received:" -ForegroundColor Green
  $match | ConvertTo-Json -Depth 20
} else {
  Write-Host "   FAIL - no callback found for $reqId (check token / callback_url / server logs)" -ForegroundColor Red
}
