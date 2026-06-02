#!/usr/bin/env bash
# =====================================================================
# BC44 Pipeline - sample curl tests (bash)
# ---------------------------------------------------------------------
# 모든 webhook 워크플로우를 sample payload로 호출한다.
#   BASE_URL : n8n 베이스 URL (기본 http://localhost:5678)
#              외부 터널 테스트 시 N8N_BASE_URL(공개 URL)로 덮어쓴다.
#   TOKEN    : 웹훅 Bearer 토큰 (기본 dev-local-token)
# 사용:
#   bash scripts/curl_samples.sh
#   BASE_URL=https://xxxx.trycloudflare.com TOKEN=prod-token bash scripts/curl_samples.sh
# =====================================================================
set -u
BASE_URL="${N8N_BASE_URL:-${BASE_URL:-http://localhost:5678}}"
TOKEN="${N8N_WEBHOOK_TOKEN:-${TOKEN:-dev-local-token}}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
P="$DIR/samples/payloads"

hr() { printf '\n========== %s ==========\n' "$1"; }
post() {
  local path="$1" file="$2"
  hr "$path"
  curl -sS -X POST "$BASE_URL/webhook/$path" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "X-Request-Id: $(date +%s)" \
    --data-binary @"$P/$file"
  printf '\n'
}

# 0) health (GET)
hr "health (GET)"
curl -sS "$BASE_URL/webhook/health"; printf '\n'

# 1~9) POST workflows
post document-ingest     document-ingest.json
post rag-chat            rag-chat.json
post web-crawl           web-crawl.json
post evaluation-simulate evaluation-simulate.json
post report-generate     report-generate.json
post wbs-delay-check     wbs-delay-check.json
post llm-route           llm-route.json
post notify              notify.json
post vector-reindex      vector-reindex.json

hr "AUTH 실패 케이스 (잘못된 토큰)"
curl -sS -X POST "$BASE_URL/webhook/document-ingest" \
  -H "Authorization: Bearer WRONG-TOKEN" -H "Content-Type: application/json" \
  --data-binary @"$P/document-ingest.json"; printf '\n'

hr "VALIDATION 실패 케이스 (필수필드 누락)"
curl -sS -X POST "$BASE_URL/webhook/rag-chat" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"request_id":"REQ-X","project_id":"PRJ-X","user_id":"u1"}'; printf '\n'

echo
echo "완료. 콜백 수신 확인: curl $BASE_URL/../  또는 mock 서버 GET http://localhost:4000/callbacks"
